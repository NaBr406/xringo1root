/* Minimal su: setuid root then exec the requested command. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    setgid(0);
    setuid(0);
    if (getuid() != 0) {
        fprintf(stderr, "su: cannot drop into root\n");
        return 1;
    }
    if (argc >= 3 && (!strcmp(argv[1], "-c") || !strcmp(argv[1], "0"))) {
        execl("/system/bin/sh", "sh", "-c", argv[2], (char *)0);
    }
    if (argc >= 2 && argv[1][0] != '-') {
        execv(argv[1], &argv[1]);
    }
    execl("/system/bin/sh", "sh", (char *)0);
    perror("su: exec");
    return 1;
}
