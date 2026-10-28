#!/bin/bash
set -uo pipefail
cd /root/kernel-gki
echo "=== built kernel version ==="
grep -E "^VERSION|^PATCHLEVEL|^SUBLEVEL" Makefile | head -3
echo
echo "=== task_struct offsets (built) vs device (0x908/0x868/0x960/0x968) ==="
pahole -C task_struct vmlinux 2>/dev/null | grep -E "struct task_struct \{|cred;|real_cred;|posix_cputimers;|signal;|sighand;" | head -8
echo
echo "=== cred (device: uid 0x8 euid 0x18 fsuid 0x20 security 0x80 user_ns 0x90) ==="
pahole -C cred vmlinux 2>/dev/null | head -30 | grep -E "struct cred \{|\*security|user_ns|group_info|ucounts|kuid_t uid|euid|fsuid"
echo
echo "=== k_itimer (device: size 0x180, it at 0xe0) ==="
pahole -C k_itimer vmlinux 2>/dev/null | head -6
