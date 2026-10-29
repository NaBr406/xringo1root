#!/bin/bash
# Build a bootable arm64 Image from our tree and a test initramfs that loads
# kernelsu.ko as init and then verifies execve still works.
set -uo pipefail
cd /root/kernel-gki
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
make -j"$(nproc)" Image > /tmp/image.log 2>&1
echo "Image build rc=$?"
ls -l arch/arm64/boot/Image 2>/dev/null || { tail -5 /tmp/image.log; exit 1; }
cp arch/arm64/boot/Image /root/Image-dijun-gki
