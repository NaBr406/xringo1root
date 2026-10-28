#!/bin/bash
# Build a KASAN-instrumented bzImage for the given tree.
set -euo pipefail
TREE="$1"
OUT="$2"
cd "/root/$TREE"

make defconfig >/dev/null
./scripts/config --enable POSIX_TIMERS
./scripts/config --enable POSIX_CPU_TIMERS_TASK_WORK
./scripts/config --enable DEVTMPFS
./scripts/config --enable DEVTMPFS_MOUNT
./scripts/config --enable BLK_DEV_INITRD
./scripts/config --enable RD_GZIP
./scripts/config --enable SERIAL_8250
./scripts/config --enable SERIAL_8250_CONSOLE
./scripts/config --enable KALLSYMS
./scripts/config --disable RANDOMIZE_BASE
./scripts/config --enable KASAN
./scripts/config --enable KASAN_GENERIC
./scripts/config --enable KASAN_INLINE
./scripts/config --enable KASAN_STACK
./scripts/config --enable STACKTRACE
./scripts/config --set-val FRAME_WARN 2048
./scripts/config --disable MODULE_SIG
./scripts/config --disable SYSTEM_TRUSTED_KEYRING
make olddefconfig >/dev/null

grep -E "^CONFIG_(KASAN|KASAN_INLINE|POSIX_CPU_TIMERS_TASK_WORK)=" .config

make -j"$(nproc)" bzImage 2>&1 | tail -3
cp arch/x86/boot/bzImage "$OUT"
ls -l "$OUT"
