package o1.st.shell.adb

import java.lang.reflect.Method
import javax.net.ssl.SSLSocket

/**
 * com.android.org.conscrypt.Conscrypt is a hidden platform class, so call it
 * reflectively instead of compiling against it.
 */
object ConscryptCompat {

    private val conscrypt: Class<*>? = try {
        Class.forName("com.android.org.conscrypt.Conscrypt")
    } catch (t: Throwable) {
        null
    }

    private val isConscryptMethod: Method? = try {
        conscrypt?.getMethod("isConscrypt", SSLSocket::class.java)
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

    @JvmStatic
    fun isConscrypt(socket: SSLSocket): Boolean = try {
        isConscryptMethod?.invoke(null, socket) as? Boolean ?: false
    } catch (t: Throwable) {
        false
    }

    @JvmStatic
    fun exportKeyingMaterialDbg(
        socket: SSLSocket,
        label: String,
        context: ByteArray?,
        length: Int
    ): ByteArray? = try {
        exportMethod?.invoke(null, socket, label, context, length) as? ByteArray
    } catch (t: Throwable) {
        null
    }
}
