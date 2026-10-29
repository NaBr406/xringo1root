#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: %s <uid>\n", argv[0]); return 2; }
    int uid = atoi(argv[1]);
    if (setuid((uid_t)uid) != 0) { perror("setuid"); return 3; }
    fprintf(stderr, "[test] running as uid=%d\n", (int)getuid());
    execl("/data/local/tmp/o3p_new.bin", "o3p", "--shell", "id -u", (char *)0);
    perror("execl");
    return 4;
}
