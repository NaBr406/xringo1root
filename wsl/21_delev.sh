#!/bin/bash
cd /root/dijun
echo "=== del_ev / wf helpers (lines 40-100) ==="
sed -n '40,100p' o3p.c
echo
echo "=== main() head ==="
sed -n '/^int main(/,/^}/p' o3p.c | head -60
