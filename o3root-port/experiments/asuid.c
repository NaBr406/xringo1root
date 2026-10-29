#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: %s <uid> <cmd...>\n", argv[0]); return 2; }
    int uid = atoi(argv[1]);
    if (setgid(uid) != 0) { fprintf(stderr, "asuid: setgid(%d) failed: %s\n", uid, strerror(errno)); return 3; }
    if (setuid(uid) != 0) { fprintf(stderr, "asuid: setuid(%d) failed: %s\n", uid, strerror(errno)); return 3; }
    if (getuid() != uid || geteuid() != uid) {
        fprintf(stderr, "asuid: uid not applied (got %d, want %d)\n", (int)getuid(), uid);
        return 3;
    }
    execv(argv[2], &argv[2]);
    fprintf(stderr, "asuid: execv %s failed: %s\n", argv[2], strerror(errno));
    return 1;
}
