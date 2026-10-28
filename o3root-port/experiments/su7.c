#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stddef.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>

#define ROOTD_SOCK "o1p_rootd"

/* NOTE: deliberately no setuid()/setgid() here. Android's app seccomp filter
 * kills the process with SIGSYS on those calls, so privilege comes from the
 * daemon (which already runs as root in the shell domain) instead. */

static int rootd_run(const char *cmd) {
    int s = socket(AF_UNIX, SOCK_STREAM, 0);
    if (s < 0) return -1;
    struct sockaddr_un a;
    memset(&a, 0, sizeof a);
    a.sun_family = AF_UNIX;
    a.sun_path[0] = '\0';
    strncpy(a.sun_path + 1, ROOTD_SOCK, sizeof(a.sun_path) - 2);
    socklen_t al = (socklen_t)(offsetof(struct sockaddr_un, sun_path) + 1 + strlen(ROOTD_SOCK));
    if (connect(s, (struct sockaddr *)&a, al) < 0) { close(s); return -1; }
    if (write(s, cmd, strlen(cmd)) < 0) { close(s); return -1; }
    if (write(s, "\n", 1) < 0) { close(s); return -1; }
    char buf[8192];
    ssize_t n;
    while ((n = read(s, buf, sizeof buf)) > 0) {
        if (write(1, buf, (size_t)n) < 0) break;
    }
    close(s);
    return 0;
}

int main(int argc, char **argv) {
    const char *shell = "/system/bin/sh";
    const char *single = NULL;
    int i = 1;
    int first = 0;

    while (i < argc) {
        if (!strcmp(argv[i], "-c") || !strcmp(argv[i], "--command")) {
            if (i + 1 < argc) single = argv[i + 1];
            break;
        } else if (!strcmp(argv[i], "-s") || !strcmp(argv[i], "--shell")) {
            if (i + 1 < argc) shell = argv[i + 1];
            i += 2;
        } else if (!strcmp(argv[i], "0") || !strcmp(argv[i], "root")) {
            first = i + 1;
            break;
        } else if (argv[i][0] == '-') {
            i++;
        } else {
            first = i;
            break;
        }
    }

    if (single != NULL) {
        if (rootd_run(single) == 0) return 0;
        execl(shell, shell, "-c", single, (char *)0);
        return 1;
    }

    if (first > 0 && first < argc) {
        size_t need = 0;
        for (int k = first; k < argc; k++) need += strlen(argv[k]) + 1;
        char *line = malloc(need + 1);
        if (line != NULL) {
            line[0] = '\0';
            for (int k = first; k < argc; k++) {
                strcat(line, argv[k]);
                if (k + 1 < argc) strcat(line, " ");
            }
            if (rootd_run(line) == 0) { free(line); return 0; }
            execl(shell, shell, "-c", line, (char *)0);
            free(line);
            return 1;
        }
    }

    char *line = NULL;
    size_t cap = 0;
    ssize_t len;
    while ((len = getline(&line, &cap, stdin)) > 0) {
        while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r')) {
            line[--len] = '\0';
        }
        if (len == 0) continue;
        if (rootd_run(line) != 0) {
            pid_t pid = fork();
            if (pid == 0) {
                execl(shell, shell, "-c", line, (char *)0);
                _exit(127);
            }
            if (pid > 0) {
                int st = 0;
                waitpid(pid, &st, 0);
            }
        }
        fflush(stdout);
    }
    free(line);
    return 0;
}
