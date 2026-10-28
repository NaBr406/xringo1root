#!/bin/bash
# Compile the ported adb Kotlin sources against android.jar + Bouncy Castle.
set -uo pipefail
SRC="$HOME/port/adb"
OUT="$HOME/port/out"
AJAR="/mnt/f/Android/Sdk/platforms/android-35/android.jar"
BC="$HOME/libs/bcprov.jar:$HOME/libs/bcpkix.jar:$HOME/libs/bcutil.jar"

rm -rf "$OUT"; mkdir -p "$OUT"

"$HOME/kotlinc/bin/kotlinc" \
  -classpath "$AJAR:$BC" \
  -jvm-target 11 \
  -nowarn \
  -d "$OUT" \
  "$SRC"/*.kt 2>&1 | grep -vE "^(WARNING|warning:)" | head -40

echo "--- classes produced ---"
find "$OUT" -name '*.class' | wc -l
