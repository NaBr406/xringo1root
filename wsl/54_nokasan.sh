#!/bin/bash
set -uo pipefail
cd /root/kernel-gki
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-

echo "=== disable KASAN in the module build config ==="
./scripts/config --disable KASAN
./scripts/config --disable KASAN_INLINE
./scripts/config --disable KASAN_GENERIC
make olddefconfig </dev/null >/dev/null 2>&1
grep -E '^CONFIG_KASAN=' .config || echo "KASAN off"
make modules_prepare </dev/null >/tmp/prep4.log 2>&1
echo "modules_prepare rc=$?"

echo "=== rebuild hello ==="
cd /root/hello
make -C /root/kernel-gki M=/root/hello ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
     KCFLAGS="-Wno-error" KBUILD_MODPOST_WARN=1 clean >/dev/null 2>&1
make -C /root/kernel-gki M=/root/hello ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
     KCFLAGS="-Wno-error" KBUILD_MODPOST_WARN=1 modules >/tmp/hello2.log 2>&1
echo "build rc=$?"
ls -l hello.ko
echo -n "asan refs: "; strings -a hello.ko | grep -c __asan
aarch64-linux-gnu-strip --strip-debug hello.ko -o h-nk.ko
python3 /mnt/e/code/CVE/cve-2026-98260-xring/wsl/50_zero_versions.py h-nk.ko h-ok.ko
cp -f h-ok.ko /mnt/e/code/CVE/cve-2026-98260-xring/o3root-port/lkm/hello-ok.ko
ls -l h-ok.ko
