#!/bin/bash
cd /root/dijun
for s in do_timer_create __set_task_comm posix_timer_unhash_and_free exit_itimers \
         release_task timerqueue_del posix_cpu_timers_exit discard_slab \
         __arm64_sys_getpid rb_alloc __alloc_frozen_pages_noprof; do
    a=$(nm vmlinux.elf 2>/dev/null | awk -v s="$s" '$3==s {print $1; exit}')
    printf '%-34s %s\n' "$s" "${a:-MISSING}"
done
