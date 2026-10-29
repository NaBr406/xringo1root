REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
#!/bin/bash
cd /root/hello
echo "=== our module (gcc) relocation types ==="
aarch64-linux-gnu-readelf -r hello.ko 2>/dev/null | awk '{print $3}' | grep '^R_AARCH64' | sort | uniq -c
echo
echo "=== reference module (clang-built) relocation types ==="
aarch64-linux-gnu-readelf -r $REPO_ROOT/o3root-port/lkm/ksu-tiann.ko 2>/dev/null | awk '{print $3}' | grep '^R_AARCH64' | sort | uniq -c
