/*
 * Derived from RikkaApps/Shizuku (Apache-2.0).
 * Source revision: b844bc491f1790c72328e1a8e5b2349f8978f0ea
 * Source path: manager/src/main/java/moe/shizuku/manager/adb/AdbException.kt
 * Upstream code preserved; provenance comment added by xringo1root.
 * See THIRD_PARTY_NOTICES.md and licenses/Shizuku-LICENSE at repository root.
 */
package moe.shizuku.manager.adb

@Suppress("NOTHING_TO_INLINE")
inline fun adbError(message: Any): Nothing = throw AdbException(message.toString())

open class AdbException : Exception {

    constructor(message: String, cause: Throwable?) : super(message, cause)
    constructor(message: String) : super(message)
    constructor(cause: Throwable) : super(cause)
    constructor()
}

class AdbInvalidPairingCodeException : AdbException()

class AdbKeyException(cause: Throwable) : AdbException(cause)
