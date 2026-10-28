#!/bin/bash
# Build the validation initramfs and boot it in qemu with our own kernel.
set -uo pipefail
R=/root/vmtest
rm -rf "$R"
mkdir -p "$R/dev" "$R/proc" "$R/sys"

aarch64-linux-gnu-gcc -static -O2 -o "$R/init" /mnt/e/code/CVE/cve-2026-98260-xring/wsl/vmtest_init.c
cp /root/vmtest_ko.ko "$R/kernelsu.ko"
ls -l "$R/init" "$R/kernelsu.ko"

cd "$R"
find . -print0 | cpio --null -o -H newc 2>/dev/null | gzip -9 > /root/vmtest.cpio.gz
ls -l /root/vmtest.cpio.gz

timeout --signal=KILL 300 qemu-system-aarch64 \
    -M virt -cpu max -m 2048 -smp 4 \
    -kernel /root/Image-dijun-gki \
    -initrd /root/vmtest.cpio.gz \
    -append "console=ttyAMA0 panic=1 dyndbg=\"file kernel/module/* +p\"" \
    -nographic -no-reboot > /root/vmtest.log 2>&1
echo "qemu exit=$?"
echo "=== markers ==="
grep -E "MOUNTS_OK|KO_OPEN_FAIL|FINIT_MODULE_RC|PROC_MODULES|TRY_EXEC|EXEC_AFTER_MODULE_OK|EXEC_FAIL|Kernel panic|kernelsu" /root/vmtest.log | head -20
