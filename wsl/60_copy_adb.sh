#!/bin/bash
set -e
mkdir -p "$HOME/port/adb"
S="$HOME/shizuku-src/manager/src/main/java/moe/shizuku/manager/adb"
for f in AdbProtocol.kt AdbMessage.kt AdbKey.kt AdbClient.kt AdbPairingClient.kt AdbMdns.kt AdbException.kt; do
  if [ -f "$S/$f" ]; then
    cp "$S/$f" "$HOME/port/adb/"
    echo "copied $f"
  else
    echo "MISSING $f"
  fi
done
wc -l "$HOME/port/adb/"*.kt | tail -9
