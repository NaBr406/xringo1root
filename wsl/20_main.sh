#!/bin/bash
cd /root/dijun
echo "=== getenv flags ==="
grep -oE 'getenv\("[A-Z0-9_]+"\)' o3p.c | sort -u
echo
echo "=== main() ==="
sed -n '/^int main(/,/^}/p' o3p.c | head -80
