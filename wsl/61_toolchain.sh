#!/bin/bash
set -uo pipefail
cd "$HOME"

echo "=== java ==="
if ! command -v java >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y -qq default-jdk-headless >/tmp/jdk.log 2>&1
fi
java -version 2>&1 | head -1

echo "=== kotlin compiler ==="
if [ ! -x "$HOME/kotlinc/bin/kotlinc" ]; then
  curl -sSL -o /tmp/kotlin.zip \
    https://github.com/JetBrains/kotlin/releases/download/v2.1.21/kotlin-compiler-2.1.21.zip
  unzip -q -o /tmp/kotlin.zip -d "$HOME"
fi
"$HOME/kotlinc/bin/kotlinc" -version 2>&1 | head -2

echo "=== bouncy castle ==="
mkdir -p "$HOME/libs"
M=https://repo1.maven.org/maven2/org/bouncycastle
[ -f "$HOME/libs/bcprov.jar" ] || curl -sSL -o "$HOME/libs/bcprov.jar" "$M/bcprov-jdk18on/1.78.1/bcprov-jdk18on-1.78.1.jar"
[ -f "$HOME/libs/bcpkix.jar" ] || curl -sSL -o "$HOME/libs/bcpkix.jar" "$M/bcpkix-jdk18on/1.78.1/bcpkix-jdk18on-1.78.1.jar"
[ -f "$HOME/libs/bcutil.jar" ] || curl -sSL -o "$HOME/libs/bcutil.jar" "$M/bcutil-jdk18on/1.78.1/bcutil-jdk18on-1.78.1.jar"
ls -l "$HOME/libs"
