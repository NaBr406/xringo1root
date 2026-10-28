#!/bin/bash
set -uo pipefail
cd /root/dijun

echo "=== sections of interest ==="
readelf -S vmlinux.elf 2>/dev/null | grep -E "BTF|symtab" | head

echo
echo "=== struct offsets via BTF (pahole) ==="
if ! command -v pahole >/dev/null 2>&1; then
    echo "pahole missing"
    exit 1
fi
pahole -C task_struct vmlinux.elf 2>/dev/null | grep -E "cred|real_cred|posix_cputimers|signal|sighand|struct task_struct \{" | head -20
echo
echo "--- cred ---"
pahole -C cred vmlinux.elf 2>/dev/null | head -40
echo
echo "--- k_itimer ---"
pahole -C k_itimer vmlinux.elf 2>/dev/null | head -30
echo
echo "--- k_clock / timerqueue_node (entry offset) ---"
pahole -C timerqueue_node vmlinux.elf 2>/dev/null | head -12
pahole -C cpu_timer vmlinux.elf 2>/dev/null | head -12
