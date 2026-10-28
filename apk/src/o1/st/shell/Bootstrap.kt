package o1.st.shell

import android.content.Context
import moe.shizuku.manager.adb.AdbClient
import moe.shizuku.manager.adb.AdbKey
import moe.shizuku.manager.adb.AdbMdns
import moe.shizuku.manager.adb.AdbPairingClient
import moe.shizuku.manager.adb.Observer
import moe.shizuku.manager.adb.PreferenceAdbKeyStore
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Wireless-debugging bootstrap.
 *
 * The pairing code expires quickly, so the pairing port is discovered *ahead
 * of time* (the caller starts [watchPairing] before the user opens the system
 * pairing dialog) and [pairAndRun] pairs the moment the code arrives.
 *
 * Once paired, adb runs a shell command with uid 2000 and Seccomp 0; anything
 * launched from there gives a *complete* root, unlike the app-domain one.
 */
fun interface Logger { fun log(msg: String) }

object Bootstrap {

    private const val DISCOVER_TIMEOUT_S = 10L

    @Volatile
    private var pairingPort: Int = -1

    private var watch: AdbMdns? = null

    private fun adbKey(ctx: Context): AdbKey? = try {
        val prefs = ctx.getSharedPreferences("o1p_adb", Context.MODE_PRIVATE)
        AdbKey(PreferenceAdbKeyStore(prefs), "o1p")
    } catch (t: Throwable) {
        null
    }

    /** Listen for the pairing service ahead of time so the port is known the
     *  instant the user submits the code. */
    @JvmStatic
    fun watchPairing(ctx: Context, logger: Logger): Boolean {
        stopWatch()
        pairingPort = -1
        return try {
            val m = AdbMdns(ctx, AdbMdns.TLS_PAIRING, Observer { p: Int ->
                if (p > 0) {
                    pairingPort = p
                    logger.log("已发现配对端口 = $p（现在可以提交配对码）")
                }
            })
            m.start()
            watch = m
            true
        } catch (t: Throwable) {
            logger.log("监听配对服务失败: $t")
            false
        }
    }

    @JvmStatic
    fun stopWatch() {
        try {
            watch?.stop()
        } catch (ignored: Throwable) {
        }
        watch = null
    }

    @JvmStatic
    fun currentPort(): Int = pairingPort

    /** Pair immediately with the already-known port, then connect and run. */
    @JvmStatic
    fun pairAndRun(ctx: Context, code: String, command: String, logger: Logger): Boolean {
        val trimmed = code.trim()
        if (trimmed.length < 6) {
            logger.log("配对码需要 6 位数字")
            return false
        }
        val port = pairingPort
        if (port <= 0) {
            logger.log("还没发现配对服务：请先点开「使用配对码配对设备」，等配对码出现后再提交。")
            return false
        }

        val k = adbKey(ctx)
        if (k == null) {
            logger.log("生成 adb 密钥失败")
            return false
        }

        logger.log("② 立即配对（端口 $port）...")
        val paired = try {
            AdbPairingClient("127.0.0.1", port, trimmed, k).start()
        } catch (t: Throwable) {
            logger.log("配对异常: $t")
            false
        }
        if (!paired) {
            logger.log("配对失败：配对码错误或已过期（出现配对码后 30 秒内提交）")
            return false
        }
        logger.log("   配对成功")

        stopWatch()

        logger.log("③ 查找连接服务 (_adb-tls-connect)...")
        val connPort = discover(ctx, AdbMdns.TLS_CONNECT)
        if (connPort == null) {
            logger.log("找不到连接服务，adb 可能还没就绪")
            return false
        }
        logger.log("   连接端口 = $connPort")

        logger.log("④ 建立 adb 连接并执行命令...")
        return try {
            val client = AdbClient("127.0.0.1", connPort, k)
            client.connect()
            logger.log("   已连接（shell 域，Seccomp=0）")
            client.shellCommand(command) { bytes ->
                val text = String(bytes, Charsets.UTF_8)
                if (text.isNotEmpty()) logger.log(text)
            }
            client.close()
            logger.log("   命令执行结束")
            true
        } catch (t: Throwable) {
            logger.log("shell 执行失败: $t")
            false
        }
    }

    /** Already paired: just connect and run (no pairing needed again). */
    @JvmStatic
    fun runOnly(ctx: Context, command: String, logger: Logger): Boolean {
        val k = adbKey(ctx)
        if (k == null) {
            logger.log("读取 adb 密钥失败，需要重新配对")
            return false
        }
        logger.log("查找连接服务 (_adb-tls-connect)...")
        val connPort = discover(ctx, AdbMdns.TLS_CONNECT)
        if (connPort == null) {
            logger.log("找不到连接服务：请确认无线调试仍处于开启状态")
            return false
        }
        logger.log("连接端口 = $connPort")
        return try {
            val client = AdbClient("127.0.0.1", connPort, k)
            client.connect()
            logger.log("已连接（shell 域，Seccomp=0）")
            client.shellCommand(command) { bytes ->
                val text = String(bytes, Charsets.UTF_8)
                if (text.isNotEmpty()) logger.log(text)
            }
            client.close()
            logger.log("命令执行结束")
            true
        } catch (t: Throwable) {
            logger.log("连接失败: $t")
            false
        }
    }

    private fun discover(ctx: Context, serviceType: String): Int? {
        val latch = CountDownLatch(1)
        var found = -1
        val mdns = AdbMdns(ctx, serviceType, Observer { port ->
            if (port > 0 && found < 0) {
                found = port
                latch.countDown()
            }
        })
        try {
            mdns.start()
            latch.await(DISCOVER_TIMEOUT_S, TimeUnit.SECONDS)
        } catch (t: Throwable) {
            return null
        } finally {
            try {
                mdns.stop()
            } catch (ignored: Throwable) {
            }
        }
        return if (found > 0) found else null
    }
}
