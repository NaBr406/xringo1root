#!/bin/bash
set -uo pipefail
cd /root/dijun
OBJDUMP=aarch64-linux-gnu-objdump

echo "=== rb_erase (write primitive site) ==="
$OBJDUMP -d --start-address=0xffffffc0801912a4 --stop-address=0xffffffc080191340 vmlinux.elf 2>/dev/null | sed -n '5,40p'

echo
echo "=== timerqueue_del ==="
$OBJDUMP -d --start-address=0xffffffc080191230 --stop-address=0xffffffc0801912a4 vmlinux.elf 2>/dev/null | sed -n '5,30p'

echo
echo "=== selinux enforcing accessor (sanity: enforcing at +0) ==="
nm vmlinux.elf | grep -E " (selinux_is_enabled|enforcing_set|selinux_enforcing|selinux_state)$" | head -5
