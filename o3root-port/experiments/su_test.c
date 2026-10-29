#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
int main(int argc, char **argv) {
    int uid = atoi(argv[1]);
    setgid(uid); setuid(uid);
    fprintf(stderr, "[test] running as uid=%d, calling /system/bin/su\n", (int)getuid());
    execl("/system/bin/su", "su", "-c", "id -u; getenforce", (char *)0);
    perror("exec su");
    return 1;
}
