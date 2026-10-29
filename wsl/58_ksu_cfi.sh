REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
#!/bin/bash
# Final KernelSU build recipe for dijun (validated with hello.ko -> Live):
#   clang/LLVM + CONFIG_CFI=y (kCFI type hashes), KASAN off,
#   debug stripped (no R_AARCH64_ABS32), __version* sizes zeroed.
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
make -C /root/kernel-gki M=/root/ksu/kernel ARCH=arm64 LLVM=1 \
     KCFLAGS="-Wno-error" KBUILD_MODPOST_WARN=1 -j"$(nproc)" modules > /tmp/ksu-cfi.log 2>&1
echo "build rc=$?"
ls -l kernelsu.ko 2>/dev/null || { tail -10 /tmp/ksu-cfi.log; exit 1; }

llvm-strip --strip-debug kernelsu.ko -o kernelsu-st.ko
python3 $REPO_ROOT/wsl/50_zero_versions.py kernelsu-st.ko kernelsu-cfi.ko
echo -n "asan refs: "; strings -a kernelsu-cfi.ko | grep -c __asan || true
echo -n "ABS32 relocs: "; llvm-readelf -r kernelsu-cfi.ko | grep -c ABS32 || true
echo -n "vermagic: "; strings -a kernelsu-cfi.ko | grep -m1 '^vermagic='
ls -l kernelsu-cfi.ko
cp -f kernelsu-cfi.ko $REPO_ROOT/o3root-port/lkm/ksu-dijun-cfi.ko
echo DONE
