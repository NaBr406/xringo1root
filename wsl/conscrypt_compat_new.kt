package moe.shizuku.manager.adb

import android.os.Build
import java.lang.reflect.Method
import javax.net.ssl.SSLSocket

/**
 * TLS keying-material export (RFC 5705), needed as the SPAKE2 password salt.
 *
 * Shizuku called com.android.org.conscrypt.Conscrypt.exportKeyingMaterial
 * directly. That class is a hidden API, and on Android 17 its method list is
 * not even visible to reflection. The same functionality is exposed as a
 * *public* API since Android 10: android.net.ssl.SSLSockets.
 * Reflection against the hidden class is kept as a fallback for older builds.
 */
object ConscryptCompat {

    private val conscrypt: Class<*>? = try {
        Class.forName("com.android.org.conscrypt.Conscrypt")
    } catch (t: Throwable) {
        null
    }

    private val exportMethod: Method? = try {
        conscrypt?.getMethod(
            "exportKeyingMaterial",
            SSLSocket::class.java,
            String::class.java,
            ByteArray::class.java,
            Int::class.javaPrimitiveType
        )
    } catch (t: Throwable) {
        null
    }

    private val isConscryptMethod: Method? = try {
        conscrypt?.getMethod("isConscrypt", SSLSocket::class.java)
    } catch (t: Throwable) {
        null
    }

    @JvmStatic
    fun isConscrypt(socket: SSLSocket): Boolean {
        return try {
            isConscryptMethod?.invoke(null, socket) as? Boolean ?: false
        } catch (t: Throwable) {
            false
        }
    }

    @JvmStatic
    fun exportKeyingMaterial(
        socket: SSLSocket,
        label: String,
        context: ByteArray?,
        length: Int
    ): ByteArray? {
        if (Build.VERSION.SDK_INT >= 29) {
            try {
                val r = android.net.ssl.SSLSockets.exportKeyingMaterial(
                    socket, label, context, length
                )
                android.util.Log.d("o1p-conscrypt", "public API ok len=${r?.size ?: -1}")
                if (r != null) return r
            } catch (t: Throwable) {
                android.util.Log.e("o1p-conscrypt", "public API failed: $t")
            }
        }
        return try {
            val r = exportMethod?.invoke(null, socket, label, context, length) as? ByteArray
            android.util.Log.d(
                "o1p-conscrypt",
                "reflection method=${exportMethod != null} len=${r?.size ?: -1}"
            )
            r
        } catch (t: Throwable) {
            android.util.Log.e("o1p-conscrypt", "reflection failed: $t")
            null
        }
    }
}
