/*
 * initramfs init for validating kernelsu.ko on our own kernel build.
 *  1) mount devtmpfs/proc/sys
 *  2) finit_module(/kernelsu.ko)
 *  3) execve() ourselves again to prove exec still works afterwards
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

static void say(const char *s) { write(1, s, strlen(s)); }

int main(int argc, char **argv) {
    int fd;

    if (argc > 1 && !strcmp(argv[1], "--exec-ok")) {
        say("EXEC_AFTER_MODULE_OK\n");
        sync();
        reboot(RB_POWER_OFF);
        for (;;) pause();
    }

    mkdir("/dev", 0755);
    mkdir("/proc", 0755);
    mkdir("/sys", 0755);
    mount("devtmpfs", "/dev", "devtmpfs", 0, "");
    mount("proc", "/proc", "proc", 0, "");
    mount("sysfs", "/sys", "sysfs", 0, "");
    say("MOUNTS_OK\n");

    fd = open("/kernelsu.ko", O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        printf("KO_OPEN_FAIL errno=%d\n", errno);
        goto done;
    }
    long rc = syscall(SYS_finit_module, fd, "", 0);
    printf("FINIT_MODULE_RC=%ld (flags=0) errno=%d\n", rc, rc ? errno : 0);
    close(fd);

    /* module loaded? check /proc/modules */
    {
        char b[512];
        int n = 0, f2 = open("/proc/modules", O_RDONLY);
        if (f2 >= 0) { n = read(f2, b, sizeof b - 1); close(f2); }
        if (n > 0) { b[n] = 0; printf("PROC_MODULES: %s\n", strtok(b, "\n")); }
    }

done:
    say("TRY_EXEC\n");
    {
        char *const a[] = { (char *)"/init", (char *)"--exec-ok", NULL };
        char *const e[] = { NULL };
        execve("/init", a, e);
    }
    printf("EXEC_FAIL errno=%d\n", errno);
    sync();
    reboot(RB_POWER_OFF);
    return 0;
}
