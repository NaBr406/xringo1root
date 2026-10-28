#!/bin/bash
set -uo pipefail
cd /root/kernel-gki
cp /mnt/e/code/CVE/cve-2026-98260-xring/device-dump/config.txt .config
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
make olddefconfig >/tmp/kdef.log 2>&1
echo "olddefconfig rc=$?"
grep -E "^CONFIG_(DEBUG_INFO_BTF|POSIX_CPU_TIMERS_TASK_WORK|MODVERSIONS|MODULE_SIG|KALLSYMS)=" .config | head
echo "=== building vmlinux + modules ==="
make -j"$(nproc)" vmlinux modules 2>&1 | tail -15
ls -l vmlinux Module.symvers 2>/dev/null
