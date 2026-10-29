#!/bin/bash
# Add diagnostics to ConscryptCompat so a null reflection result is visible.
set -uo pipefail
cd "$HOME/port/adb"

python3 - <<'PY'
import re
p = "ConscryptCompat.kt"
s = open(p, encoding="utf-8").read()

# instrument the body of exportKeyingMaterial
old_tail = s[s.find("    @JvmStatic\n    fun exportKeyingMaterial("):]
new_body = '''    @JvmStatic
    fun exportKeyingMaterial(
        socket: SSLSocket,
        label: String,
        context: ByteArray?,
        length: Int
    ): ByteArray? {
        val r = try {
            exportMethod?.invoke(null, socket, label, context, length) as? ByteArray
        } catch (t: Throwable) {
            android.util.Log.e("o1p-conscrypt", "invoke failed: $t")
            null
        }
        android.util.Log.d(
            "o1p-conscrypt",
            "cls=${conscrypt != null} method=${exportMethod != null} len=${r?.size ?: -1}"
        )
        return r
    }
}
'''
s = s[:s.find("    @JvmStatic\n    fun exportKeyingMaterial(")] + new_body
open(p, "w", encoding="utf-8").write(s)
print("instrumented")
PY

tail -20 ConscryptCompat.kt
