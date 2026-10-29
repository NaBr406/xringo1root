REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
#!/bin/bash
# Extract clean source trees for arm64 builds and produce KASAN Images.
set -euo pipefail
V=6.18.21
X=/root/linux-$V.tar.xz
CC=aarch64-linux-gnu-
D=$REPO_ROOT/wsl

for t in linux-arm64-vuln linux-arm64-patched; do
    if [ ! -f "/root/$t/Makefile" ]; then
        echo "[*] extracting $t"
        mkdir -p "/root/$t"
        tar -xf "$X" -C "/root/$t" --strip-components=1
    fi
done

echo "[*] applying fix to linux-arm64-patched"
python3 "$D/apply_fix.py" /root/linux-arm64-patched/fs/exec.c
grep -n "posixtimer_exec(me)" /root/linux-arm64-patched/fs/exec.c

build() {
    local tree="$1" out="$2"
    cd "/root/$tree"
    make ARCH=arm64 CROSS_COMPILE="$CC" defconfig >/dev/null
    ./scripts/config --enable POSIX_TIMERS
    ./scripts/config --enable POSIX_CPU_TIMERS_TASK_WORK
    ./scripts/config --enable DEVTMPFS
    ./scripts/config --enable DEVTMPFS_MOUNT
    ./scripts/config --enable BLK_DEV_INITRD
    ./scripts/config --enable RD_GZIP
    ./scripts/config --enable SERIAL_AMBA_PL011
    ./scripts/config --enable SERIAL_AMBA_PL011_CONSOLE
    ./scripts/config --enable KALLSYMS
    ./scripts/config --disable RANDOMIZE_BASE
    ./scripts/config --enable KASAN
    ./scripts/config --enable KASAN_GENERIC
    ./scripts/config --enable KASAN_INLINE
    ./scripts/config --enable KASAN_STACK
    ./scripts/config --enable STACKTRACE
    ./scripts/config --set-val FRAME_WARN 2048
    make ARCH=arm64 CROSS_COMPILE="$CC" olddefconfig >/dev/null
    grep -E "^CONFIG_(ARM64_4K_PAGES|KASAN|POSIX_CPU_TIMERS_TASK_WORK|SERIAL_AMBA_PL011_CONSOLE)=" .config
    make ARCH=arm64 CROSS_COMPILE="$CC" -j"$(nproc)" Image 2>&1 | tail -3
    cp arch/arm64/boot/Image "$out"
    ls -l "$out"
}

echo "=== build vuln ==="
build linux-arm64-vuln /root/Image-arm64-vuln-kasan
echo "=== build patched ==="
build linux-arm64-patched /root/Image-arm64-patched-kasan
echo ARM64_BUILD_DONE
