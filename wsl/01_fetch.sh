#!/bin/bash
set -euo pipefail
cd /root
V=6.18.21
rm -f "linux-$V.tar.xz" 2>/dev/null || true
if [ ! -f "linux-$V.tar.xz" ]; then
    echo "[*] downloading linux-$V"
    curl -sSL -o "linux-$V.tar.xz" "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$V.tar.xz"
fi
ls -l "linux-$V.tar.xz"
x="linux-$V.tar.xz"
# verify it is a real tarball
if ! tar -tf "$x" >/dev/null 2>&1; then
    echo "[!] not a valid tarball, size=$(stat -c%s "$x")"
    exit 1
fi
for t in linux-vuln linux-patched; do
    if [ ! -f "$t/Makefile" ]; then
        echo "[*] extracting into $t"
        mkdir -p "$t"
        tar -xf "$x" -C "$t" --strip-components=1
    fi
done
echo "[*] trees ready"
grep -n "posix_cpu_timers_exit(me)" linux-vuln/fs/exec.c
grep -n "de_thread(me)" linux-vuln/fs/exec.c
