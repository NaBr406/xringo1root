#include <errno.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

int main(int argc, char **argv) {
    int uid = atoi(argv[1]);
    const char *cmd = argc > 2 ? argv[2] : "id -u";
    if (setuid((uid_t)uid) != 0) { perror("setuid"); return 3; }

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un a; memset(&a, 0, sizeof a);
    a.sun_family = AF_UNIX; a.sun_path[0] = 0;
    strncpy(a.sun_path + 1, "o3p_rootd", sizeof(a.sun_path) - 2);
    socklen_t al = (socklen_t)(offsetof(struct sockaddr_un, sun_path) + 1 + strlen("o3p_rootd"));
    if (connect(fd, (struct sockaddr *)&a, al) < 0) {
        printf("[uid %d] CONNECT FAIL errno=%d\n", uid, errno); return 1;
    }
    dprintf(fd, "%s\n", cmd); shutdown(fd, SHUT_WR);
    char b[512]; ssize_t n;
    printf("[uid %d] ", uid);
    while ((n = read(fd, b, sizeof b - 1)) > 0) { b[n] = 0; fputs(b, stdout); }
    close(fd);
    return 0;
}
