/*
 * Minimal module loader that passes MODULE_INIT_IGNORE_MODVERSIONS.
 * Needed because our LKM is built from a slightly different GKI revision, so
 * the module_layout CRC differs from the device kernel's.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

#ifndef MODULE_INIT_IGNORE_MODVERSIONS
#define MODULE_INIT_IGNORE_MODVERSIONS 1
#endif
#ifndef MODULE_INIT_IGNORE_VERMAGIC
#define MODULE_INIT_IGNORE_VERMAGIC 2
#endif

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <module.ko> [flags]\n", argv[0]);
        return 2;
    }
    int flags = MODULE_INIT_IGNORE_MODVERSIONS;
    if (argc > 2) flags = (int)strtol(argv[2], NULL, 0);

    int fd = open(argv[1], O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        fprintf(stderr, "open %s: %s\n", argv[1], strerror(errno));
        return 3;
    }
    long rc = syscall(SYS_finit_module, fd, "", flags);
    int e = errno;
    close(fd);
    if (rc != 0) {
        fprintf(stderr, "finit_module(flags=0x%x) failed: %s (%d)\n",
                flags, strerror(e), e);
        return 1;
    }
    printf("finit_module OK (flags=0x%x)\n", flags);
    return 0;
}
