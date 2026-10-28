#!/bin/bash
# Rebuild the KernelSU LKM from the v3.3.1 tag so it matches the official manager APK.
set -uo pipefail
cd /root/ksu
git fetch --depth 1 origin refs/tags/v3.3.1:refs/tags/v3.3.1 >/tmp/ksu-tag.log 2>&1 || git fetch origin --tags >>/tmp/ksu-tag.log 2>&1
git checkout -q v3.3.1 2>&1 | tail -2
git log --oneline -1

cd /root/ksu/kernel
sed -i 's/^obj-\$(CONFIG_KSU) += kernelsu.o/obj-m += kernelsu.o/' Kbuild
grep -q '^obj-m' Kbuild || true
cat > nsimport.c <<'EOF'
#include <linux/module.h>
MODULE_IMPORT_NS("ANDROID_GKI_VFS_internal_I_am_really_a_filesystem_and_am_NOT_a_driver");
EOF
grep -q 'nsimport.o' Kbuild || echo 'kernelsu-objs += nsimport.o' >> Kbuild

make clean >/dev/null 2>&1 || true
make -C /root/kernel-gki M=/root/ksu/kernel ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
     KCFLAGS="-Wno-error" KBUILD_MODPOST_WARN=1 -j"$(nproc)" modules > /tmp/ksu-v331.log 2>&1
echo "build rc=$?"
grep -c '^ERROR' /tmp/ksu-v331.log || true
ls -l kernelsu.ko 2>/dev/null || { tail -8 /tmp/ksu-v331.log; exit 1; }
aarch64-linux-gnu-strip --strip-debug kernelsu.ko -o kernelsu-stripped.ko
strings -a kernelsu-stripped.ko | grep -m1 '^vermagic='
ls -l kernelsu-stripped.ko
cp kernelsu-stripped.ko /mnt/e/code/CVE/cve-2026-98260-xring/o3root-port/lkm/ksu-dijun-v331.ko
