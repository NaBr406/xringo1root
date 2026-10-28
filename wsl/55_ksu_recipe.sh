#!/bin/bash
# Build the KernelSU LKM with the recipe that works on dijun:
#  - kernel-gki tree (struct module == 1664, matches device)
#  - KASAN disabled in the module build
#  - strip debug (avoids R_AARCH64_ABS32 that the arm64 relocator rejects)
#  - __version* section sizes zeroed (no CRC comparisons, vermagic tail only)
set -uo pipefail
cd /root/ksu/kernel

sed -i 's/^obj-\$(CONFIG_KSU) += kernelsu.o/obj-m += kernelsu.o/' Kbuild
grep -q '^obj-m' Kbuild || true
cat > nsimport.c <<'EOF'
#include <linux/module.h>
MODULE_IMPORT_NS("ANDROID_GKI_VFS_internal_I_am_really_a_filesystem_and_am_NOT_a_driver");
EOF
grep -q 'nsimport.o' Kbuild || echo 'kernelsu-objs += nsimport.o' >> Kbuild

make clean >/dev/null 2>&1 || true
make -C /root/kernel-gki M=/root/ksu/kernel ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
     KCFLAGS="-Wno-error" KBUILD_MODPOST_WARN=1 -j"$(nproc)" modules > /tmp/ksu-dijun.log 2>&1
echo "build rc=$?"
ls -l kernelsu.ko 2>/dev/null || { tail -8 /tmp/ksu-dijun.log; exit 1; }

aarch64-linux-gnu-strip --strip-debug kernelsu.ko -o kernelsu-st.ko
python3 /mnt/e/code/CVE/cve-2026-98260-xring/wsl/50_zero_versions.py kernelsu-st.ko kernelsu-dijun.ko
echo -n "asan refs: "; strings -a kernelsu-dijun.ko | grep -c __asan || true
echo -n "ABS32 relocs: "; aarch64-linux-gnu-readelf -r kernelsu-dijun.ko | grep -c ABS32 || true
echo -n "vermagic: "; strings -a kernelsu-dijun.ko | grep -m1 '^vermagic='
ls -l kernelsu-dijun.ko
cp -f kernelsu-dijun.ko /mnt/e/code/CVE/cve-2026-98260-xring/o3root-port/lkm/ksu-dijun-final.ko
echo DONE
