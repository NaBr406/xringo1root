#!/bin/bash
# Boot a KASAN kernel with the harness as init and capture the report.
# usage: 06_run_kasan.sh <kernel> <logfile>
set -uo pipefail
K="$1"
LOG="$2"

ACCEL=""
if [ -w /dev/kvm ]; then ACCEL="-enable-kvm -cpu host"; fi
echo "[*] accel: ${ACCEL:-tcg}"

timeout --signal=KILL 600 qemu-system-x86_64 \
    -kernel "$K" \
    -initrd /root/initrd.gz \
    -append "console=ttyS0 panic=1 ab_iters=20 ab_nvma=8192 ab_lockers=8" \
    -nographic -no-reboot -m 4096 -smp 8 $ACCEL \
    >"$LOG" 2>&1
echo "qemu exit=$? log=$LOG"
echo "--- markers ---"
grep -E "AB_START|AB_ITER|AB_NO_PANIC|BUG: KASAN|use-after-free|Kernel panic|general protection|Call Trace|posix_cpu|timerqueue|release_task" "$LOG" | head -40
