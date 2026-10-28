#!/bin/bash
# arm64 initramfs whose /init is the A/B harness.
set -euo pipefail
SRC=/mnt/e/code/CVE/cve-2026-98260-xring/trigger_ab.c
R=/root/initrd-arm64

rm -rf "$R"
mkdir -p "$R/dev" "$R/proc" "$R/sys"
aarch64-linux-gnu-gcc -static -O2 -pthread -o "$R/init" "$SRC"
ls -l "$R/init"
cd "$R"
find . -print0 | cpio --null -o -H newc 2>/dev/null | gzip -9 > /root/initrd-arm64.gz
ls -l /root/initrd-arm64.gz
