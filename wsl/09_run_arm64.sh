#!/bin/bash
# Boot an arm64 kernel under qemu -M virt with the harness as init.
# usage: 09_run_arm64.sh <Image> <logfile>
set -uo pipefail
K="$1"
LOG="$2"

timeout --signal=KILL 900 qemu-system-aarch64 \
    -M virt -cpu max -m 4096 -smp 8 \
    -kernel "$K" \
    -initrd /root/initrd-arm64.gz \
    -append "console=ttyAMA0 panic=1 ab_iters=50 ab_lockers=24" \
    -nographic -no-reboot \
    >"$LOG" 2>&1
echo "qemu exit=$? log=$LOG"
echo "--- markers ---"
grep -E "AB_START|AB_ITER|AB_NO_PANIC|BUG: KASAN|slab-use-after-free|Kernel panic|Call Trace|posix_cpu|timerqueue|release_task|posix_timers_cache" "$LOG" | head -30
echo "--- KASAN reports: $(grep -c 'BUG: KASAN' "$LOG" || true) ---"
