REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
#!/bin/bash
set -uo pipefail
mkdir -p /root/dijun
cd /root/dijun
cp -f $REPO_ROOT/kernel_image.bin Image

find / -maxdepth 4 -name 'vmlinux-to-elf' -type f 2>/dev/null | head -3
python3 -m vmlinux_to_elf --help >/dev/null 2>&1 && echo "module invocation ok"
python3 -c "import vmlinux_to_elf; print('import ok')"

if [ ! -f vmlinux.elf ]; then
    /usr/local/bin/vmlinux-to-elf Image vmlinux.elf 2>&1 | tail -15
fi
ls -l vmlinux.elf 2>/dev/null || echo "NO ELF"
file vmlinux.elf 2>/dev/null

echo "=== symbols ==="
for s in init_user_ns selinux_state timerqueue_del rb_erase begin_new_exec posix_cpu_timers_exit exit_itimers; do
    printf '%-24s %s\n' "$s" "$(nm vmlinux.elf 2>/dev/null | awk -v s="$s" '$3==s {print $1; exit}')"
done
