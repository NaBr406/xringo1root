#!/bin/bash
cd /root/dijun
echo "=== probe_on_r call sites ==="
grep -n "probe_on_r" o3p.c
echo
echo "=== likely probe tables (lines with event names) ==="
grep -n 'probe_on_r(' o3p.c | wc -l
echo
echo "=== context around the trace parser (fields) ==="
sed -n '415,440p' o3p.c
echo
echo "=== search for the event names used in parsing ==="
grep -n ' x: \| tm: \| fs: \|ei: \|rl: \|td: \|pe: ' o3p.c | head -10
