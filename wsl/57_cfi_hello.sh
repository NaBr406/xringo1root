#!/bin/bash
set -uo pipefail
cd /root/kernel-gki
export ARCH=arm64

./scripts/config --enable CFI
./scripts/config --enable CFI_ICALL_NORMALIZE_INTEGERS
make LLVM=1 olddefconfig </dev/null >/tmp/cfi-def.log 2>&1
echo "olddefconfig rc=$?"
grep -E '^CONFIG_(CFI|CFI_ICALL_NORMALIZE_INTEGERS|CC_IS_CLANG|KASAN)=' .config || true
make LLVM=1 -j"$(nproc)" modules_prepare </dev/null >/tmp/cfi-prep.log 2>&1
echo "modules_prepare rc=$?"

cd /root/hello
make -C /root/kernel-gki M=/root/hello ARCH=arm64 LLVM=1 KCFLAGS="-Wno-error" KBUILD_MODPOST_WARN=1 clean >/dev/null 2>&1
make -C /root/kernel-gki M=/root/hello ARCH=arm64 LLVM=1 KCFLAGS="-Wno-error" KBUILD_MODPOST_WARN=1 modules >/tmp/hello-cfi.log 2>&1
echo "hello build rc=$?"
ls -l hello.ko 2>/dev/null || { tail -6 /tmp/hello-cfi.log; exit 1; }
echo -n ".kcfi_traps/.kcfi sections: "; llvm-readelf -SW hello.ko | grep -c kcfi || true
llvm-strip --strip-debug hello.ko -o h-cfi.ko
python3 /mnt/e/code/CVE/cve-2026-98260-xring/wsl/50_zero_versions.py h-cfi.ko h-cfi-z.ko
cp -f h-cfi-z.ko /mnt/e/code/CVE/cve-2026-98260-xring/o3root-port/lkm/hello-cfi.ko
ls -l h-cfi-z.ko
