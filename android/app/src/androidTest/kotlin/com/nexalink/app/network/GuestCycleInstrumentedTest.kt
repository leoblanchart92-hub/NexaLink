package com.nexalink.app.network

import android.app.ActivityManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.Process
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import com.wireguard.config.InetEndpoint
import com.wireguard.config.InetNetwork
import com.wireguard.config.Interface
import com.wireguard.config.Peer
import com.wireguard.crypto.Key
import com.wireguard.crypto.KeyPair
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Real network test, never part of a release APK. No success retry. */
@RunWith(AndroidJUnit4::class)
class GuestCycleInstrumentedTest {
    private val inst = InstrumentationRegistry.getInstrumentation()
    private val context = inst.targetContext

    private fun shell(command: String): String {
        val fd = inst.uiAutomation.executeShellCommand(command)
        return ParcelFileDescriptor.AutoCloseInputStream(fd).use { it.readBytes().toString(Charsets.UTF_8).trim() }
    }

    private fun probe(cycle: Int, inspect: Boolean = false, stopped: Boolean = false, bound: Boolean = false): Bundle {
        val done = CountDownLatch(1)
        var result: Bundle? = null
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                result = getResultExtras(false)?.let { Bundle(it) }
                done.countDown()
            }
        }
        val intent = Intent().setClassName(inst.context.packageName, "com.nexalink.app.network.VpnProbeReceiver")
            .putExtra("cycle", cycle).putExtra("inspectOnly", inspect).putExtra("expectStopped", stopped)
            .putExtra("expectEcho", !inspect && !stopped).putExtra("bindVpn", bound)
        context.sendOrderedBroadcast(intent, null, receiver, Handler(Looper.getMainLooper()), 0, null, null)
        if (!done.await(12, TimeUnit.SECONDS)) return Bundle().apply { putString("error", "broadcast-timeout") }
        return result ?: Bundle().apply { putString("error", "empty-broadcast-result") }
    }

    // Raw kernel interface counters, not WireGuard TUN-read counters.
    // Shell permissions may deny these: retain "unavailable" rather than inventing a value.
    private fun tunCounters(iface: String?): String {
        if (iface == null || !iface.matches(Regex("[A-Za-z0-9_.-]{1,32}"))) return "unavailable-interface"
        return shell("for x in tx_packets tx_bytes tx_dropped tx_errors rx_packets rx_bytes rx_dropped rx_errors; do printf '%s=' \"\$x\"; cat /sys/class/net/$iface/statistics/\$x 2>/dev/null || printf 'unavailable\\n'; done").replace('\n', ',')
    }

    private fun count(path: String): Int = File(path).list()?.size ?: -1
    private fun serviceRunning(): Boolean {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        @Suppress("DEPRECATION")
        return am.getRunningServices(100).any { it.service.className == "com.wireguard.android.backend.GoBackend\$VpnService" }
    }
    private fun recordProbe(b: Bundle): JSONObject = JSONObject().apply {
        for (k in listOf("uid", "localPort", "sentBytes", "receivedBytes")) put(k, b.getInt(k, -1))
        for (k in listOf("networkHandle", "startedElapsedMs", "sentElapsedMs", "receivedElapsedMs", "finishedElapsedMs")) put(k, b.getLong(k, -1))
        for (k in listOf("sent", "echo", "vpnReady", "vpnGone", "boundVpn")) put(k, b.getBoolean(k, false))
        put("interfaceName", b.getString("interfaceName", "unavailable"))
        put("error", b.getString("error", "none"))
    }

    @Test(timeout = 1800000) fun oneHundredRealGuestCycles() {
        assumeTrue(Build.VERSION.SDK_INT >= 29)
        shell("appops set ${context.packageName} ACTIVATE_VPN allow")
        assertNull("emulator VPN authorization", VpnService.prepare(context))
        val out = File(context.filesDir, "phase81-cycles.jsonl")
        out.writeText("")
        val guestKey = KeyPair(Key.fromBase64("YWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWE="))
        val ownerKey = KeyPair(Key.fromBase64("YmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmI="))
        val config = Config.Builder().setInterface(Interface.Builder().setKeyPair(guestKey)
            .addAddress(InetNetwork.parse("10.77.0.2/32")).setMtu(1280).build())
            .addPeer(Peer.Builder().setPublicKey(ownerKey.publicKey)
                .setEndpoint(InetEndpoint.parse("10.0.2.2:38673"))
                .addAllowedIp(InetNetwork.parse("0.0.0.0/0")).build()).build()
        val reused = GuestTunnel(context)
        var failures = 0
        var completed = 0
        var blocked = false
        try {
            for (cycle in 0 until 100) {
                val guest = if (cycle < 50) reused else GuestTunnel(context)
                val row = JSONObject().put("cycle", cycle).put("mode", if (cycle < 50) "reused" else "fresh")
                    .put("wallMs", System.currentTimeMillis()).put("startElapsedMs", SystemClock.elapsedRealtime())
                    .put("fdBefore", count("/proc/self/fd")).put("threadsBefore", count("/proc/self/task"))
                val errors = mutableListOf<String>()
                var started = false
                try {
                    val before = probe(cycle, stopped = true)
                    row.put("before", recordProbe(before))
                    if (!before.getBoolean("vpnGone") || before.getInt("uid", -1) == Process.myUid()) errors.add("prior-vpn-not-gone-or-uid")
                    if (errors.isEmpty()) {
                        if (guest.start(config) != Tunnel.State.UP) errors.add("start-not-up") else started = true
                    }
                    row.put("serviceAfterStart", serviceRunning())
                    if (started) {
                        val inspected = probe(cycle, inspect = true)
                        row.put("inspect", recordProbe(inspected))
                        val iface = inspected.getString("interfaceName")
                        row.put("tunBefore", tunCounters(iface))
                        val result = probe(cycle)
                        row.put("probe", recordProbe(result))
                        row.put("tunAfter", tunCounters(iface))
                        val stats = guest.statistics()
                        val peer = stats.peer(ownerKey.publicKey)
                        row.put("wgTxBytes", stats.totalTx()).put("wgRxBytes", stats.totalRx())
                            .put("handshakeMillis", peer?.latestHandshakeEpochMillis() ?: 0L)
                        if (result.getInt("uid", -1) < 0 || result.getInt("uid", -1) == Process.myUid()) errors.add("wrong-probe-uid")
                        if (!result.getBoolean("sent")) errors.add("send")
                        if (!result.getBoolean("echo")) errors.add("echo")
                        if (stats.totalTx() <= 0 || stats.totalRx() <= 0) errors.add("wg-bytes")
                        if ((peer?.latestHandshakeEpochMillis() ?: 0L) <= 0L) errors.add("handshake")
                        // Differential probe is diagnostic only: it cannot turn a failed cycle into success.
                        if (errors.isNotEmpty()) row.put("boundDiagnostic", recordProbe(probe(cycle, bound = true)))
                    }
                } catch (e: Exception) {
                    errors.add("exception:${e.javaClass.simpleName}")
                } catch (e: AssertionError) {
                    errors.add("assertion:${e.javaClass.simpleName}")
                } finally {
                    try {
                        val state = guest.stop()
                        row.put("stopState", state.toString()).put("serviceAfterStop", serviceRunning())
                        if (state != Tunnel.State.DOWN || serviceRunning()) errors.add("service-not-stopped")
                        val stopped = probe(cycle, stopped = true)
                        row.put("after", recordProbe(stopped))
                        if (!stopped.getBoolean("vpnGone")) errors.add("vpn-not-gone")
                        val marker = Any()
                        val released = VpnRoleLease.acquire(marker)
                        if (released) VpnRoleLease.release(marker) else { errors.add("lease-not-released"); blocked = true }
                        row.put("leaseReleased", released)
                    } catch (e: Exception) { errors.add("stop:${e.javaClass.simpleName}"); blocked = true }
                    row.put("fdAfter", count("/proc/self/fd")).put("threadsAfter", count("/proc/self/task"))
                        .put("endElapsedMs", SystemClock.elapsedRealtime()).put("errors", errors.joinToString(","))
                    out.appendText(row.toString() + "\n")
                    completed++
                    if (errors.isNotEmpty()) failures++
                    android.util.Log.i("NexaLinkCycle", "cycle=$cycle result=${if (errors.isEmpty()) "pass" else errors.joinToString(",")}")
                }
                if (blocked) break // fail closed: never overlap another VPN when cleanup is uncertain
            }
        } finally { shell("appops set ${context.packageName} ACTIVATE_VPN ignore") }
        assertEquals("all 100 cycles must execute; diagnostics in phase81-cycles.jsonl", 100, completed)
        assertEquals("every cycle must pass without a retry", 0, failures)
    }
}
