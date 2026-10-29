REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
#!/bin/bash
set -uo pipefail
cd /root/dijun

echo "=== symbols near selinux_state (neighbour of the stage-0 write) ==="
nm -n vmlinux.elf | awk '$1 >= "ffffffc082950000" && $1 <= "ffffffc08295a000"' | head -20
echo
echo "=== selinux-related symbols ==="
nm vmlinux.elf | grep -E " (selinux_state|avc_latest_notif_update|init_user_ns|avc_cache_stats)$"
echo
echo "=== probe targets ==="
nm vmlinux.elf | grep -E " (__arm64_sys_getpid|__arm64_sys_getppid|rb_erase|timerqueue_del|posix_cpu_timers_exit|exit_itimers|begin_new_exec)$"
echo
echo "=== kprobe support ==="
grep -E "^CONFIG_(KPROBES|KPROBE_EVENTS|PANIC_ON_WARN|PANIC_ON_OOPS|PANIC_TIMEOUT)" $REPO_ROOT/device-dump/config.txt
echo
echo "=== heap-reclaim cache params ==="
grep -E "^CONFIG_(SLUB|SLAB|SLUB_CPU_PARTIAL|SLUB_DEBUG|HARDENED_USERCOPY|INIT_ON_ALLOC|INIT_ON_FREE|RANDOM_KMALLOC_CACHES|SHUFFLE_PAGE_ALLOCATOR|SLAB_FREELIST_RANDOM|SLAB_FREELIST_HARDENED)" $REPO_ROOT/device-dump/config.txt
