REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
#!/bin/bash
# arm64 initramfs whose /init is the A/B harness.
set -euo pipefail
SRC=$REPO_ROOT/trigger_ab.c
R=/root/initrd-arm64

rm -rf "$R"
mkdir -p "$R/dev" "$R/proc" "$R/sys"
aarch64-linux-gnu-gcc -static -O2 -pthread -o "$R/init" "$SRC"
ls -l "$R/init"
cd "$R"
find . -print0 | cpio --null -o -H newc 2>/dev/null | gzip -9 > /root/initrd-arm64.gz
ls -l /root/initrd-arm64.gz
