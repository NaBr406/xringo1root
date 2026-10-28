#!/bin/bash
set -uo pipefail
cd /root/ksu/kernel

cat > nsimport.c <<'EOF'
#include <linux/module.h>
MODULE_IMPORT_NS("ANDROID_GKI_VFS_internal_I_am_really_a_filesystem_and_am_NOT_a_driver");
EOF
cat nsimport.c

make -C /root/kernel-gki M=/root/ksu/kernel ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
     KCFLAGS="-Wno-error" KBUILD_MODPOST_WARN=1 -j"$(nproc)" modules > /tmp/ksu-build6.log 2>&1
echo "build rc=$?"
echo "errors=$(grep -c '^ERROR' /tmp/ksu-build6.log)"
tail -4 /tmp/ksu-build6.log
ls -l /root/ksu/kernel/kernelsu.ko 2>/dev/null || echo "NO KO"
