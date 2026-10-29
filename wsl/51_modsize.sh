REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
#!/bin/bash
set -uo pipefail
echo "=== device kernel: sizeof(struct module) from BTF ==="
python3 $REPO_ROOT/wsl/carve_btf.py $REPO_ROOT/kernel_image.bin /root/device-btf.bin 2>&1 | tail -2
bpftool btf dump file /root/device-btf.bin format raw > /root/device-btf.raw 2>/dev/null
grep -A3 "^\[[0-9]*\] STRUCT 'module'" /root/device-btf.raw | head -5

echo
echo "=== our 6.18.21 build ==="
pahole -C module /root/kernel-6.18.21/vmlinux 2>/dev/null | head -4
echo
echo "=== our 6.18.33 build ==="
pahole -C module /root/kernel-gki/vmlinux 2>/dev/null | head -4
