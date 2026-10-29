#!/bin/bash
# Build an x86_64 kernel from the given tree with a config that exercises the
# POSIX CPU timer + exec path.
set -euo pipefail

TREE="$1"
cd "/root/$TREE"

if [ ! -f .config ]; then
    make defconfig >/dev/null
fi

# Make sure the vulnerable path is compiled in and the VM can boot/print.
./scripts/config --enable POSIX_TIMERS || true
./scripts/config --enable POSIX_CPU_TIMERS_TASK_WORK || true
./scripts/config --enable DEVTMPFS || true
./scripts/config --enable DEVTMPFS_MOUNT || true
./scripts/config --enable BLK_DEV_INITRD || true
./scripts/config --enable RD_GZIP || true
./scripts/config --enable SERIAL_8250 || true
./scripts/config --enable SERIAL_8250_CONSOLE || true
./scripts/config --enable KALLSYMS || true
./scripts/config --disable RANDOMIZE_BASE || true
./scripts/config --disable MODULE_SIG || true
./scripts/config --disable SYSTEM_TRUSTED_KEYRING || true
make olddefconfig >/dev/null

grep -E "^CONFIG_(POSIX_TIMERS|POSIX_CPU_TIMERS_TASK_WORK|DEVTMPFS|BLK_DEV_INITRD|SERIAL_8250_CONSOLE|KALLSYMS)=" .config || true

make -j"$(nproc)" bzImage 2>&1 | tail -4
ls -l arch/x86/boot/bzImage
