#!/bin/bash
set -uo pipefail
mkdir -p /root/hello
cat > /root/hello/hello.c <<'EOF'
#include <linux/module.h>
#include <linux/kernel.h>
static int __init hello_init(void) { pr_info("hello: init ok\n"); return 0; }
static void __exit hello_exit(void) { pr_info("hello: exit\n"); }
module_init(hello_init);
module_exit(hello_exit);
MODULE_LICENSE("GPL");
EOF
cat > /root/hello/Makefile <<'EOF'
obj-m += hello.o
EOF
make -C /root/kernel-gki M=/root/hello ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
     KCFLAGS="-Wno-error" KBUILD_MODPOST_WARN=1 modules > /tmp/hello.log 2>&1
echo "hello build rc=$?"
ls -l /root/hello/hello.ko 2>/dev/null || { tail -5 /tmp/hello.log; exit 1; }
aarch64-linux-gnu-objcopy --remove-section=.init_array --remove-section=.fini_array \
    --remove-section=.rela.init_array --remove-section=.rela.fini_array /root/hello/hello.ko 2>/dev/null
strings -a /root/hello/hello.ko | grep -m1 '^vermagic='
cp /root/hello/hello.ko /mnt/e/code/CVE/cve-2026-98260-xring/o3root-port/lkm/hello.ko
ls -l /mnt/e/code/CVE/cve-2026-98260-xring/o3root-port/lkm/hello.ko
