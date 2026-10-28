#!/bin/bash
set -uo pipefail
cd /root/dijun
BASE=https://raw.githubusercontent.com/zsw125/o3root/main
mkdir -p lkm
for f in lkm/lkm-aarch64-android17-6.18_kernelsu.ko \
         lkm/aarch64-next-android17-6.18_kernelsu.ko \
         lkm/sukisu-aarch64-android17-6.18.ko; do
    out="lkm/$(basename "$f")"
    [ -f "$out" ] || curl -sSL --retry 3 -o "$out" "$BASE/$f"
    printf '%-46s %s bytes\n' "$(basename "$f")" "$(stat -c%s "$out")"
done
echo
echo "=== vermagic of each ==="
for k in lkm/*.ko; do
    printf '%s: ' "$(basename "$k")"
    strings -a "$k" | grep -m1 -E '^vermagic=' || echo "(no vermagic string)"
done
echo
echo "=== our kernel release ==="
echo "6.18.21-android17-5-g1d099fcb35e0-abogki538445360-4k"
