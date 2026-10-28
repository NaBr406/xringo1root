#!/bin/bash
set -uo pipefail
cd /root/kernel-gki

echo "=== pin release (no auto git suffix) ==="
./scripts/config --disable LOCALVERSION_AUTO
./scripts/config --set-str LOCALVERSION "-android17-5-g1d099fcb35e0-abogki538445360-4k"
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig </dev/null >/tmp/def3.log 2>&1
echo "olddefconfig rc=$?"
grep -E '^CONFIG_LOCALVERSION' .config
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- modules_prepare </dev/null >/tmp/prep2.log 2>&1
echo "modules_prepare rc=$?"
grep -E 'exceeds|Error' /tmp/prep2.log | head -3
echo -n "utsrelease: "; cat include/generated/utsrelease.h

echo "=== rebuild module ==="
cd /root/ksu/kernel
make clean >/dev/null 2>&1 || true
make -C /root/kernel-gki M=/root/ksu/kernel ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
     KCFLAGS="-Wno-error" KBUILD_MODPOST_WARN=1 -j"$(nproc)" modules > /tmp/ksu-final.log 2>&1
echo "build rc=$? errors=$(grep -c '^ERROR' /tmp/ksu-final.log)"
ls -l kernelsu.ko 2>/dev/null || { tail -8 /tmp/ksu-final.log; exit 1; }
aarch64-linux-gnu-strip --strip-debug kernelsu.ko -o kernelsu-stripped.ko
echo -n "vermagic: "; strings -a kernelsu-stripped.ko | grep -m1 '^vermagic='
ls -l kernelsu-stripped.ko
cp kernelsu-stripped.ko /mnt/e/code/CVE/cve-2026-98260-xring/o3root-port/lkm/ksu-dijun-v331.ko
echo DONE
