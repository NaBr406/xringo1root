/*
 * Derived from RikkaApps/Shizuku (Apache-2.0).
 * Source revision: b844bc491f1790c72328e1a8e5b2349f8978f0ea
 * Source path: manager/src/main/java/moe/shizuku/manager/adb/AdbProtocol.kt
 * Upstream code preserved; provenance comment added by xringo1root.
 * See THIRD_PARTY_NOTICES.md and licenses/Shizuku-LICENSE at repository root.
 */
package moe.shizuku.manager.adb

object AdbProtocol {

    const val A_SYNC = 0x434e5953
    const val A_CNXN = 0x4e584e43
    const val A_AUTH = 0x48545541
    const val A_OPEN = 0x4e45504f
    const val A_OKAY = 0x59414b4f
    const val A_CLSE = 0x45534c43
    const val A_WRTE = 0x45545257
    const val A_STLS = 0x534C5453

    const val A_VERSION = 0x01000000
    const val A_MAXDATA = 4096

    const val A_STLS_VERSION = 0x01000000

    const val ADB_AUTH_TOKEN = 1
    const val ADB_AUTH_SIGNATURE = 2
    const val ADB_AUTH_RSAPUBLICKEY = 3
}