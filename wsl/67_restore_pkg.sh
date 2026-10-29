#!/bin/bash
# libadb.so registers JNI against moe.shizuku.manager.adb.*, so the ported
# adb classes must keep that package name. The app itself stays o1.st.shell.
set -uo pipefail
cd "$HOME/port/adb"

for f in *.kt; do
  sed -i 's/^package o1\.st\.shell\.adb$/package moe.shizuku.manager.adb/' "$f"
  sed -i 's/^import o1\.st\.shell\.adb\./import moe.shizuku.manager.adb./' "$f"
done

echo "=== packages ==="
grep -h '^package' *.kt | sort -u
echo "=== PairingContext definition ==="
grep -n 'class PairingContext' *.kt
