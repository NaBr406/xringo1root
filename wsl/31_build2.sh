#!/bin/bash
set -uo pipefail
cd /root/kernel-gki
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
./scripts/config --disable TRIM_UNUSED_KSYMS
./scripts/config --set-str UNUSED_KSYMS_WHITELIST ""
make olddefconfig >/tmp/kdef2.log 2>&1
echo "cfg rc=$?"
grep -E "^CONFIG_(TRIM_UNUSED_KSYMS|UNUSED_KSYMS_WHITELIST|MODVERSIONS|DEBUG_INFO_BTF)=" .config
echo "=== build ==="
make -j"$(nproc)" vmlinux modules > /tmp/build2.log 2>&1
echo "build rc=$?"
grep -cE 'error:' /tmp/build2.log || true
tail -5 /tmp/build2.log
ls -l vmlinux Module.symvers 2>/dev/null
