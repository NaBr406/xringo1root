#!/bin/bash
set -uo pipefail
cd /root/dijun

echo "=== probe/kprobe targets referenced by the payload ==="
grep -oE 'probe_on_r\("[^"]+","[^"]+","[^"]+"' o3p.c | head -40
echo
grep -oE '"[rp]:[a-zA-Z0-9_]+ [^"]+"' o3p.c | head -40
echo
echo "=== symbol existence check in our kernel ==="
for s in __arm64_sys_getpid __alloc_frozen_pages_noprof __alloc_pages_noprof \
         timerqueue_del rb_erase posix_cpu_timers_exit exit_itimers begin_new_exec \
         init_user_ns selinux_state __x64_sys_getpid; do
    a=$(nm vmlinux.elf 2>/dev/null | awk -v s="$s" '$3==s {print $1; exit}')
    if [ -n "$a" ]; then printf '%-36s OK   %s\n' "$s" "$a"; else printf '%-36s MISSING\n' "$s"; fi
done
