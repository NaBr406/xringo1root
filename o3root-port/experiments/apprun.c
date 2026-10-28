#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
int main(int argc, char **argv) {
    int uid = atoi(argv[1]);
    if (setuid((uid_t)uid) != 0) { perror("setuid"); return 3; }
    fprintf(stderr, "[runner] uid=%d\n", (int)getuid());
    execl("/data/local/tmp/o3p_new.bin", "o3p", argv[2], argv[3], argv[4], argv[5],
          argv[6], argv[7], argv[8], argv[9], (char *)0);
    perror("execl");
    return 4;
}
