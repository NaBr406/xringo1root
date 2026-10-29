REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
#!/bin/bash
set -uo pipefail
cd /root/kernel-gki

[ -d .git ] && mv .git /root/kernel-git-off
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- modules_prepare </dev/null >/tmp/prep3.log 2>&1
echo "modules_prepare rc=$?"
echo -n "utsrelease: "; cat include/generated/utsrelease.h

cd /root/ksu/kernel
make clean >/dev/null 2>&1 || true
make -C /root/kernel-gki M=/root/ksu/kernel ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
     KCFLAGS="-Wno-error" KBUILD_MODPOST_WARN=1 -j"$(nproc)" modules > /tmp/ksu-final2.log 2>&1
echo "build rc=$? errors=$(grep -c '^ERROR' /tmp/ksu-final2.log)"
ls -l kernelsu.ko 2>/dev/null || { tail -8 /tmp/ksu-final2.log; exit 1; }
aarch64-linux-gnu-strip --strip-debug kernelsu.ko -o kernelsu-stripped.ko
echo -n "vermagic: "; strings -a kernelsu-stripped.ko | grep -m1 '^vermagic='
ls -l kernelsu-stripped.ko
cp kernelsu-stripped.ko $REPO_ROOT/o3root-port/lkm/ksu-dijun-v331.ko

cd /root/kernel-gki
[ -d /root/kernel-git-off ] && mv /root/kernel-git-off .git
echo DONE
