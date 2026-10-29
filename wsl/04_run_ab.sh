#!/bin/bash
# Boot one kernel with the harness as init; capture serial output.
# usage: 04_run_ab.sh <kernel> <logfile> [iters]
set -uo pipefail
K="$1"
LOG="$2"
ITERS="${3:-30}"

timeout --signal=KILL 240 qemu-system-x86_64 \
    -kernel "$K" \
    -initrd /root/initrd.gz \
    -append "console=ttyS0 panic=1 iters=$ITERS" \
    -nographic -no-reboot -m 2048 -smp 4 \
    -cpu max >"$LOG" 2>&1
rc=$?
echo "qemu exit=$rc log=$LOG"
echo "--- markers ---"
grep -E "AB_START|AB_ITER|AB_NO_PANIC|Kernel panic|BUG:|general protection|unable to handle|RIP:" "$LOG" | tail -25
