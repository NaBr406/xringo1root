#!/bin/bash
set -uo pipefail
cd /root/ksu/kernel
# ungate the module from CONFIG_KSU (not present in the GKI .config)
sed -i 's/^obj-\$(CONFIG_KSU) += kernelsu.o/obj-m += kernelsu.o/' Kbuild
grep -n '^obj-' Kbuild | head -3

make -C /root/kernel-gki M=/root/ksu/kernel ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- KCFLAGS="-Wno-error" KBUILD_MODPOST_WARN=1 -j"$(nproc)" modules > /tmp/ksu-build4.log 2>&1
echo "build rc=$?"
echo "errors: $(grep -cE 'error:' /tmp/ksu-build4.log)"
tail -5 /tmp/ksu-build4.log
ls -l /root/ksu/kernel/kernelsu.ko 2>/dev/null || echo "NO KO"
