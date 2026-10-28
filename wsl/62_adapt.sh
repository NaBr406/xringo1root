#!/bin/bash
# Adapt the Shizuku adb sources to a standalone package.
set -uo pipefail
cd "$HOME/port/adb"

for f in *.kt; do
  # package + internal imports
  sed -i 's/^package moe\.shizuku\.manager\.adb$/package o3.st.shell.adb/' "$f"
  sed -i 's/^import moe\.shizuku\.manager\.adb\./import o3.st.shell.adb./' "$f"
  # drop external conveniences
  sed -i '/^import moe\.shizuku\.manager\.ktx\.logd$/d' "$f"
  sed -i '/^import rikka\.core\.util\.BuildUtils$/d' "$f"
  sed -i '/^import rikka\.core\.ktx\.unsafeLazy$/d' "$f"
  sed -i 's/^import com\.android\.org\.conscrypt\.Conscrypt$/import o3.st.shell.adb.ConscryptCompat/' "$f"
  # substitutions
  sed -i 's/BuildUtils\.atLeast29/(android.os.Build.VERSION.SDK_INT >= 29)/g' "$f"
  sed -i 's/by unsafeLazy {/by lazy(LazyThreadSafetyMode.NONE) {/g' "$f"
  sed -i 's/Conscrypt\.exportKeyingMaterial/ConscryptCompat.exportKeyingMaterial/g' "$f"
  sed -i 's/Conscrypt\.isConscrypt/ConscryptCompat.isConscrypt/g' "$f"
done

# logd(...) -> android.util.Log.d
sed -i 's/\blogd(/android.util.Log.d("o3p-adb", /g' *.kt

echo "=== remaining external refs ==="
grep -n 'moe\.shizuku\|rikka\.\|com\.android\.org\.conscrypt\.Conscrypt' *.kt | head -10
echo "=== done ==="
grep -c '' *.kt
