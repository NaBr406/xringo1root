#!/bin/bash
# Build a kernel tree from vanilla 6.18.21 with the device config, so module
# symbol CRCs match the device kernel (6.18.21 based).
set -uo pipefail
V=6.18.21
X=/root/linux-$V.tar.xz

[ -f "$X" ] || curl -sSL -o "$X" "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$V.tar.xz"
ls -l "$X"

if [ ! -f "/root/kernel-$V/Makefile" ]; then
    mkdir -p "/root/kernel-$V"
    tar -xf "$X" -C "/root/kernel-$V" --strip-components=1
fi

cd "/root/kernel-$V"
cp /mnt/e/code/CVE/cve-2026-98260-xring/device-dump/config.txt .config
./scripts/config --disable TRIM_UNUSED_KSYMS
./scripts/config --set-str UNUSED_KSYMS_WHITELIST ""
./scripts/config --set-str MODULE_SIG_PROTECT_LIST ""
./scripts/config --disable LOCALVERSION_AUTO
./scripts/config --set-str LOCALVERSION ""
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig </dev/null >/tmp/k621-def.log 2>&1
echo "olddefconfig rc=$?"
: > abi_symbollist.raw; : > protected_module_names_list
grep -E '^CONFIG_(MODVERSIONS|MODULE_SIG|DEBUG_INFO_BTF)=' .config

make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" vmlinux modules >/tmp/k621-build.log 2>&1
echo "build rc=$?"
grep -cE 'error:' /tmp/k621-build.log || true
ls -l vmlinux Module.symvers 2>/dev/null
