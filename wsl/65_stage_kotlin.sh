REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
#!/bin/bash
# Compile Kotlin sources and stage everything the Windows build needs.
set -uo pipefail
SRC="$HOME/port/adb"
OUT="$HOME/port/out"
AJAR="/mnt/f/Android/Sdk/platforms/android-35/android.jar"
BC="$HOME/libs/bcprov.jar:$HOME/libs/bcpkix.jar:$HOME/libs/bcutil.jar"
DST="$REPO_ROOT/apk"

rm -rf "$OUT"; mkdir -p "$OUT"

echo "=== kotlinc ==="
"$HOME/kotlinc/bin/kotlinc" \
  -classpath "$AJAR:$BC" \
  -jvm-target 11 -nowarn \
  -d "$OUT" \
  "$SRC"/*.kt "$DST/src/o1/st/shell/Bootstrap.kt" 2>&1 | grep -vE "^(WARNING|warning:)" | head -20

N=$(find "$OUT" -name '*.class' | wc -l)
echo "classes=$N"
[ "$N" -gt 0 ] || { echo "BUILD FAILED"; exit 1; }

echo "=== stage classes ==="
rm -rf "$DST/kout"
mkdir -p "$DST/kout"
cp -r "$OUT"/. "$DST/kout/"

echo "=== stage runtime libs ==="
mkdir -p "$DST/libs"
cp -f "$HOME/kotlinc/lib/kotlin-stdlib.jar" "$DST/libs/"
cp -f "$HOME/libs/bcprov.jar" "$DST/libs/"
cp -f "$HOME/libs/bcpkix.jar" "$DST/libs/"
cp -f "$HOME/libs/bcutil.jar" "$DST/libs/"
ls -l "$DST/libs"
