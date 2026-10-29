#!/bin/bash
# Rename all o3/o3p identifiers to o1/o1p across the ported Kotlin sources.
set -uo pipefail
cd "$HOME/port/adb"

for f in *.kt; do
  sed -i 's/^package o3\.st\.shell\.adb$/package o1.st.shell.adb/' "$f"
  sed -i 's/^import o3\.st\.shell\.adb\./import o1.st.shell.adb./' "$f"
  sed -i 's/o3\.st\.shell/o1.st.shell/g' "$f"
  sed -i 's/o3p/o1p/g' "$f"
done

echo "=== check ==="
grep -h '^package' *.kt | sort -u
grep -rn 'o3' *.kt | head -5
echo "(no o3 above = clean)"
