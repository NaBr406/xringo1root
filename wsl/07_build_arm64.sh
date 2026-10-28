#!/bin/bash
# Build an arm64 (aarch64) KASAN kernel out-of-tree from the given source tree.
# usage: 07_build_arm64.sh <tree> <objdir> <outfile>
set -euo pipefail
TREE="$1"
OBJ="$2"
OUT="$3"
CC="aarch64-linux-gnu-"
SRC="/root/$TREE"

mkdir -p "$OBJ"
make -C "$SRC" O="$OBJ" ARCH=arm64 CROSS_COMPILE="$CC" defconfig >/dev/null

CFG="$SRC/scripts/config --file $OBJ/.config"
$CFG --enable POSIX_TIMERS
$CFG --enable POSIX_CPU_TIMERS_TASK_WORK
$CFG --enable DEVTMPFS
$CFG --enable DEVTMPFS_MOUNT
$CFG --enable BLK_DEV_INITRD
$CFG --enable RD_GZIP
$CFG --enable SERIAL_AMBA_PL011
$CFG --enable SERIAL_AMBA_PL011_CONSOLE
$CFG --enable KALLSYMS
$CFG --disable RANDOMIZE_BASE
$CFG --enable KASAN
$CFG --enable KASAN_GENERIC
$CFG --enable KASAN_INLINE
$CFG --enable KASAN_STACK
$CFG --enable STACKTRACE
$CFG --set-val FRAME_WARN 2048
make -C "$SRC" O="$OBJ" ARCH=arm64 CROSS_COMPILE="$CC" olddefconfig >/dev/null

grep -E "^CONFIG_(ARM64_4K_PAGES|KASAN|POSIX_CPU_TIMERS_TASK_WORK|SERIAL_AMBA_PL011_CONSOLE)=" "$OBJ/.config"

make -C "$SRC" O="$OBJ" ARCH=arm64 CROSS_COMPILE="$CC" -j"$(nproc)" Image 2>&1 | tail -3
cp "$OBJ/arch/arm64/boot/Image" "$OUT"
ls -l "$OUT"
