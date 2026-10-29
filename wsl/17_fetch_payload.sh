#!/bin/bash
set -uo pipefail
cd /root/dijun
BASE=https://raw.githubusercontent.com/zsw125/o3root/main
for f in payload/build-payload.sh payload/mk_payload.py payload/README.zh-CN.md \
         payload/ksu/ksu_symtab.h payload/ksu/mksymtab.py payload/ksu/relink_ksu.py; do
    out=$(basename "$f")
    curl -sSL --retry 3 -o "$out" "$BASE/$f"
    echo "$out $(stat -c%s "$out") bytes"
done
echo "=== build-payload.sh ==="
cat build-payload.sh
