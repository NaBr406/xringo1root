REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
#!/bin/bash
# Fix kernel release to the device's exact string at build time, switch KSU to
# v3.3.1 (matching the official manager APK), then rebuild the module.
set -uo pipefail

echo "=== 1. pin kernel release to 6.18.21-... ==="
cd /root/kernel-gki
sed -i 's/^PATCHLEVEL = .*/PATCHLEVEL = 18/' Makefile
sed -i 's/^SUBLEVEL = .*/SUBLEVEL = 21/' Makefile
sed -i 's/^EXTRAVERSION =.*/EXTRAVERSION =/' Makefile
./scripts/config --set-str LOCALVERSION "-android17-5-g1d099fcb35e0-abogki538445360-4k"
make olddefconfig >/dev/null 2>&1
grep -E '^CONFIG_LOCALVERSION=' .config
grep -E '^VERSION|^PATCHLEVEL|^SUBLEVEL|^EXTRAVERSION' Makefile
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- modules_prepare >/tmp/prep.log 2>&1
echo "modules_prepare rc=$?"
cat include/generated/utsrelease.h

echo "=== 2. switch KSU to v3.3.1 ==="
cd /root/ksu
git checkout -f v3.3.1 >/tmp/co.log 2>&1 || { git fetch --depth 1 origin tag v3.3.1 >>/tmp/co.log 2>&1; git checkout -f v3.3.1 >>/tmp/co.log 2>&1; }
git log --oneline -1
tail -2 /tmp/co.log

echo "=== 3. re-apply our build tweaks ==="
cd /root/ksu/kernel
sed -i 's/^obj-\$(CONFIG_KSU) += kernelsu.o/obj-m += kernelsu.o/' Kbuild
cat > nsimport.c <<'EOF'
#include <linux/module.h>
MODULE_IMPORT_NS("ANDROID_GKI_VFS_internal_I_am_really_a_filesystem_and_am_NOT_a_driver");
EOF
grep -q 'nsimport.o' Kbuild || echo 'kernelsu-objs += nsimport.o' >> Kbuild

echo "=== 4. build module ==="
make clean >/dev/null 2>&1 || true
make -C /root/kernel-gki M=/root/ksu/kernel ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
     KCFLAGS="-Wno-error" KBUILD_MODPOST_WARN=1 -j"$(nproc)" modules > /tmp/ksu-v331b.log 2>&1
echo "build rc=$?  errors=$(grep -c '^ERROR' /tmp/ksu-v331b.log)"
ls -l kernelsu.ko 2>/dev/null || { tail -10 /tmp/ksu-v331b.log; exit 1; }
aarch64-linux-gnu-strip --strip-debug kernelsu.ko -o kernelsu-stripped.ko
echo -n "vermagic: "; strings -a kernelsu-stripped.ko | grep -m1 '^vermagic='
ls -l kernelsu-stripped.ko
cp kernelsu-stripped.ko $REPO_ROOT/o3root-port/lkm/ksu-dijun-v331.ko
echo DONE
