#!/bin/bash
set -uo pipefail
cd "$HOME/port/adb"

# 1. androidx.annotation.RequiresApi -> remove (compile-time only hint)
sed -i '/^import androidx\.annotation\.RequiresApi$/d' *.kt
sed -i '/^@RequiresApi(/d' *.kt
sed -i 's/^@RequiresApi([^)]*)$//' *.kt

# 2. androidx.lifecycle.Observer -> our own minimal interface
sed -i '/^import androidx\.lifecycle\.Observer$/d' *.kt

# 3. androidx.core SharedPreferences.edit { } extension -> plain edit()
sed -i 's/preference\.edit { putString(preferenceKey, String(Base64\.encode(bytes, Base64\.NO_WRAP))) }/preference.edit().putString(preferenceKey, String(Base64.encode(bytes, Base64.NO_WRAP))).apply()/' AdbKey.kt

echo "=== remaining androidx ==="
grep -n 'androidx' *.kt | head
echo "=== Observer uses ==="
grep -n 'Observer' AdbMdns.kt | head
