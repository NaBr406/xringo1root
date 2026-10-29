#!/bin/bash
set -uo pipefail
cd /root/kernel-gki
echo "=== current UTS_RELEASE ==="
cat include/generated/utsrelease.h 2>/dev/null
# force our device's exact release string so the module vermagic matches
cat > include/generated/utsrelease.h <<'EOF'
#define UTS_RELEASE "6.18.21-android17-5-g1d099fcb35e0-abogki538445360-4k"
EOF
echo "=== patched UTS_RELEASE ==="
cat include/generated/utsrelease.h

echo
echo "=== KernelSU kernel dir ==="
ls /root/ksu/kernel | head -8
sed -n '1,30p' /root/ksu/kernel/Makefile 2>/dev/null | head -20
