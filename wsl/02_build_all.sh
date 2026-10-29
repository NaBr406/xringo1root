REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
#!/bin/bash
set -euo pipefail
D=$REPO_ROOT/wsl

echo "=== sanity: patched tree ==="
grep -n "posixtimer_exec" /root/linux-patched/fs/exec.c
echo "old cleanup blocks left in patched tree: $(grep -c 'posix_cpu_timers_exit(me)' /root/linux-patched/fs/exec.c || true)"
echo "=== build vuln ==="
bash "$D/build_kernel.sh" linux-vuln
cp /root/linux-vuln/arch/x86/boot/bzImage /root/bzImage-vuln
echo "=== build patched ==="
bash "$D/build_kernel.sh" linux-patched
cp /root/linux-patched/arch/x86/boot/bzImage /root/bzImage-patched
ls -l /root/bzImage-vuln /root/bzImage-patched
echo BUILD_ALL_DONE
