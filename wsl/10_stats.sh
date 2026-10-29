#!/bin/bash
cd /root
tot_r=0
tot_i=0
for f in kasan-vuln2 kasan-vuln3 kasan-vuln4 kasan-vuln5 kasan-vuln6 kasan-vuln7 kasan-vuln8 \
         kasan-patched kasan-patched2 arm64-vuln4; do
    [ -f "$f.log" ] || continue
    r=$(grep -c 'BUG: KASAN' "$f.log")
    i=$(grep -c AB_ITER "$f.log")
    echo "$f reports=$r iters=$i"
    case "$f" in
        kasan-vuln*) tot_r=$((tot_r + r)); tot_i=$((tot_i + i));;
    esac
done
echo "---"
echo "x86 unpatched total: reports=$tot_r iters=$tot_i"
