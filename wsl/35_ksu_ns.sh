#!/bin/bash
set -uo pipefail
cd /root/ksu/kernel

# The GKI build puts VFS-internal exports in a symbol namespace; import it.
cat > nsimport.c <<'EOF'
#include <linux/module.h>
MODULE_IMPORT_NS(ANDROID_GKI_VFS_internal_I_am_really_a_filesystem_and_am_NOT_a_driver);
MODULE_LICENSE("GPL");
EOF
grep -q 'nsimport.o' Kbuild || echo 'kernelsu-objs += nsimport.o' >> Kbuild
grep -n 'nsimport' Kbuild

make -C /root/kernel-gki M=/root/ksu/kernel ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
     KCFLAGS="-Wno-error" KBUILD_MODPOST_WARN=1 -j"$(nproc)" modules > /tmp/ksu-build5.log 2>&1
echo "build rc=$?"
echo "errors: $(grep -cE '^ERROR|error:' /tmp/ksu-build5.log)"
tail -6 /tmp/ksu-build5.log
ls -l /root/ksu/kernel/kernelsu.ko 2>/dev/null || echo "NO KO"
