#!/bin/bash
# Switch the module build to clang so kCFI instrumentation matches the device
# kernel (CONFIG_CFI_CLANG=y); GCC-built modules fail the initcall type check.
set -uo pipefail
cd /root/kernel-gki
export ARCH=arm64

make LLVM=1 olddefconfig </dev/null >/tmp/clang-def.log 2>&1
echo "olddefconfig rc=$?"
grep -E '^CONFIG_(CFI_CLANG|CFI_AUTO_DEFAULT|KASAN|CC_IS_CLANG|CC_IS_GCC)=' .config || true

make LLVM=1 -j"$(nproc)" modules_prepare </dev/null >/tmp/clang-prep.log 2>&1
echo "modules_prepare rc=$?"
tail -3 /tmp/clang-prep.log

echo "=== build hello with clang ==="
cd /root/hello
make -C /root/kernel-gki M=/root/hello ARCH=arm64 LLVM=1 \
     KCFLAGS="-Wno-error" KBUILD_MODPOST_WARN=1 clean >/dev/null 2>&1
make -C /root/kernel-gki M=/root/hello ARCH=arm64 LLVM=1 \
     KCFLAGS="-Wno-error" KBUILD_MODPOST_WARN=1 modules >/tmp/hello-clang.log 2>&1
echo "hello build rc=$?"
ls -l hello.ko 2>/dev/null || { tail -6 /tmp/hello-clang.log; exit 1; }
echo -n "kcfi symbols: "; llvm-nm hello.ko 2>/dev/null | grep -c __kcfi || true
llvm-strip --strip-debug hello.ko -o h-clang.ko
python3 /mnt/e/code/CVE/cve-2026-98260-xring/wsl/50_zero_versions.py h-clang.ko h-clang-z.ko
cp -f h-clang-z.ko /mnt/e/code/CVE/cve-2026-98260-xring/o3root-port/lkm/hello-clang.ko
ls -l h-clang-z.ko
