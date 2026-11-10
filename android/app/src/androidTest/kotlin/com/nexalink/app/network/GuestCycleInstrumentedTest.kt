package com.nexalink.app.network

import android.app.ActivityManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.Process
import android.os.SystemClock
import android.system.Os
import android.system.OsConstants
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
import org.junit.FixMethodOrder
import org.junit.runners.MethodSorters
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.Executors
import java.util.concurrent.TimeoutException

/** Real network test, never part of a release APK. No success retry. */
@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class GuestCycleInstrumentedTest {
    companion object { @Volatile private var cleanupUncertain = false }
    private val inst = InstrumentationRegistry.getInstrumentation()
    private val context = inst.targetContext

    private fun shell(command: String): String {
        val fd = inst.uiAutomation.executeShellCommand(command)
        return ParcelFileDescriptor.AutoCloseInputStream(fd).use { it.readBytes().toString(Charsets.UTF_8).trim() }
    }

    private fun probe(cycle: Int, inspect: Boolean = false, stopped: Boolean = false, bound: Boolean = false, variant: String? = null): Bundle {
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
            .putExtra("expectEcho", !inspect && !stopped).putExtra("bindVpn", bound).putExtra("probeVariant", variant)
        context.sendOrderedBroadcast(intent, null, receiver, Handler(Looper.getMainLooper()), 0, null, null)
        if (!done.await(12, TimeUnit.SECONDS)) return Bundle().apply { putString("error", "broadcast-timeout") }
        return result ?: Bundle().apply { putString("error", "empty-broadcast-result") }
    }

    // Raw kernel interface counters, not WireGuard TUN-read counters.
    // Shell permissions may deny these: retain "unavailable" rather than inventing a value.
    private fun tunCounters(iface: String?): String {
        if (iface == null || !iface.matches(Regex("[A-Za-z0-9_.-]{1,32}"))) return "unavailable-interface"
        // Do not read a UiAutomation shell pipe here: on these emulators it
        // remained open indefinitely. Direct, bounded, read-only sysfs access
        // may be denied by SELinux; report that rather than fabricating counts.
        val pool = Executors.newSingleThreadExecutor { task -> Thread(task, "tun-counter-read").apply { isDaemon = true } }
        return try {
            pool.submit<String> {
                listOf("tx_packets", "tx_bytes", "tx_dropped", "tx_errors", "rx_packets", "rx_bytes", "rx_dropped", "rx_errors").joinToString(",") { name ->
                    val value = try {
                        File("/sys/class/net/$iface/statistics/$name").bufferedReader().use { it.readLine()?.trim() }
                    } catch (_: Exception) { null }
                    "$name=${if (value != null && value.matches(Regex("[0-9]+"))) value else "unavailable"}"
                }
            }.get(3, TimeUnit.SECONDS)
        } catch (_: Exception) { "unavailable-or-timeout" }
        finally { pool.shutdownNow() }
    }

    private fun count(path: String): Int = File(path).list()?.size ?: -1
    private fun serviceRunning(): Boolean {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        @Suppress("DEPRECATION")
        return am.getRunningServices(100).any { it.service.className == "com.wireguard.android.backend.GoBackend\$VpnService" }
    }
    // Reflection is confined to instrumentation. It never changes a socket or
    // calls protect: upstream GoBackend does not expose protect's return value.
    private fun wireGuardSockets(guest: GuestTunnel, inspectMark: Boolean = true): JSONObject {
        val result = JSONObject()
        try {
            val field = GuestTunnel::class.java.getDeclaredField("backend").apply { isAccessible = true }
            val backend = field.get(guest)
            val type = backend.javaClass
            val handle = type.getDeclaredField("currentTunnelHandle").apply { isAccessible = true }.getInt(backend)
            result.put("handleValid", handle >= 0)
            for (family in listOf("V4", "V6")) {
                val socket = JSONObject()
                try {
                    val method = type.getDeclaredMethod("wgGetSocket$family", Int::class.javaPrimitiveType).apply { isAccessible = true }
                    val fd = method.invoke(null, handle) as Int
                    socket.put("fd", fd)
                    if (fd >= 0) {
                        socket.put("link", Os.readlink("/proc/self/fd/$fd"))
                        if (inspectMark) ParcelFileDescriptor.fromFd(fd).use { copy ->
                            try {
                                // Linux SO_MARK=36. It is diagnostic only; no mark is changed.
                                val get = Os::class.java.getMethod("getsockoptInt", java.io.FileDescriptor::class.java,
                                    Int::class.javaPrimitiveType, Int::class.javaPrimitiveType)
                                socket.put("soMark", get.invoke(null, copy.fileDescriptor, OsConstants.SOL_SOCKET, 36) as Int)
                            } catch (e: Exception) { socket.put("soMarkError", e.javaClass.simpleName) }
                        }
                    }
                } catch (e: Exception) { socket.put("error", e.javaClass.simpleName) }
                result.put(family, socket)
            }
        } catch (e: Exception) { result.put("error", e.javaClass.simpleName) }
        return result
    }

    private fun socketsClosed(previous: JSONObject): JSONObject = JSONObject().apply {
        for (family in listOf("V4", "V6")) {
            val old = previous.optJSONObject(family) ?: continue
            val fd = old.optInt("fd", -1)
            val oldLink = old.optString("link", "")
            if (fd < 0 || !oldLink.startsWith("socket:[")) { put(family, "unavailable"); continue }
            val current = try { Os.readlink("/proc/self/fd/$fd") } catch (_: Exception) { "closed" }
            put(family, if (current == oldLink) "still-open" else "closed-or-reused")
        }
    }

    private fun recordProbe(b: Bundle): JSONObject = JSONObject().apply {
        for (k in listOf("uid", "pid", "localPort", "localPortAfterSend", "sentBytes", "receivedBytes")) put(k, b.getInt(k, -1))
        for (k in listOf("networkHandle", "startedElapsedMs", "sentElapsedMs", "receivedElapsedMs", "finishedElapsedMs", "socketCreateElapsedMs")) put(k, b.getLong(k, -1))
        for (k in listOf("sent", "echo", "vpnReady", "vpnGone", "boundVpn")) put(k, b.getBoolean(k, false))
        put("interfaceName", b.getString("interfaceName", "unavailable"))
        put("error", b.getString("error", "none"))
        for (k in listOf("thread", "activeBefore", "activeAtCreate", "activeAtSend", "activeAfter", "networkEvents", "callbackError", "callbackUnregisterError", "socketLocalOnCreate", "socketLocalAfterSend", "remote", "variant")) {
            put(k, b.getString(k, "unavailable"))
        }
        put("socketConnected", b.getBoolean("socketConnected", false))
    }

    // A stuck native call makes the process unsafe to reuse. Bound the wait,
    // record the failure and stop the series rather than starting a second VPN.
    private fun <T> lifecycleCall(action: () -> T): T {
        val pool = Executors.newSingleThreadExecutor { task -> Thread(task, "vpn-cycle-operation").apply { isDaemon = true } }
        return try { pool.submit<T> { action() }.get(15, TimeUnit.SECONDS) }
        finally { pool.shutdownNow() }
    }
    private fun checkpoint(cycle: Int, stage: String) {
        android.util.Log.i("NexaLinkCycle", "CHECK cycle=$cycle stage=$stage elapsedMs=${SystemClock.elapsedRealtime()}")
    }

    private fun physicalInternetAvailable(): Boolean {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        return cm.allNetworks.any { network ->
            val caps = cm.getNetworkCapabilities(network)
            caps != null && !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) &&
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        }
    }
    private fun awaitPhysicalNetwork(available: Boolean): Boolean {
        val deadline = SystemClock.elapsedRealtime() + 20000
        while (SystemClock.elapsedRealtime() < deadline) {
            if (physicalInternetAvailable() == available) return true
            Thread.sleep(100)
        }
        return false
    }

    @Test(timeout = 120000) fun zGuestNetworkLossAndReturn() {
        assumeTrue(Build.VERSION.SDK_INT >= 29)
        assertFalse("previous cycle left VPN cleanup uncertain", cleanupUncertain)
        val guestKey = KeyPair(Key.fromBase64("YWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWE="))
        val ownerKey = KeyPair(Key.fromBase64("YmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmI="))
        val config = Config.Builder().setInterface(Interface.Builder().setKeyPair(guestKey)
            .addAddress(InetNetwork.parse("10.77.0.2/32")).setMtu(1280).build())
            .addPeer(Peer.Builder().setPublicKey(ownerKey.publicKey)
                .setEndpoint(InetEndpoint.parse("10.0.2.2:38673"))
                .addAllowedIp(InetNetwork.parse("0.0.0.0/0")).build()).build()
        val guest = GuestTunnel(context)
        try {
            shell("appops set ${context.packageName} ACTIVATE_VPN allow")
            assertNull(VpnService.prepare(context))
            assertTrue("initial physical network must be validated", awaitPhysicalNetwork(true))
            assertTrue("old VPN must be gone", probe(900, stopped = true).getBoolean("vpnGone"))
            assertEquals(Tunnel.State.UP, guest.start(config))
            assertTrue("initial echo", probe(901).getBoolean("echo"))
            shell("svc wifi disable")
            shell("svc data disable")
            assertTrue("both physical networks must disappear", awaitPhysicalNetwork(false))
            val offline = probe(902)
            android.util.Log.i("NexaLinkCycle", "network-offline ${recordProbe(offline)}")
            assertTrue("offline probe must execute as a different UID", offline.getInt("uid", -1) >= 0 && offline.getInt("uid", -1) != Process.myUid())
            assertFalse("no echo is possible without an underlying network", offline.getBoolean("echo"))
            shell("svc data enable")
            shell("svc wifi enable")
            assertTrue("physical network must return validated", awaitPhysicalNetwork(true))
            val restored = probe(903)
            android.util.Log.i("NexaLinkCycle", "network-restored ${recordProbe(restored)}")
            assertTrue("echo must resume after real network restoration", restored.getBoolean("echo"))
        } finally {
            shell("svc data enable")
            shell("svc wifi enable")
            try { guest.stop() } finally { shell("appops set ${context.packageName} ACTIVATE_VPN ignore") }
        }
    }

    /** Thirty genuine restarts, with two separate sockets in alternating order.
     * Binding is a differential control only; it cannot erase a baseline failure.
     * Upstream libwg-go is opaque: do not label byte totals as TUN-read counters.
     */
    @Test(timeout = 600000) fun shortDifferentialCycles() {
        assumeTrue(Build.VERSION.SDK_INT >= 29)
        assertFalse("previous cleanup uncertain", cleanupUncertain)
        shell("appops set ${context.packageName} ACTIVATE_VPN allow")
        assertNull(VpnService.prepare(context))
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
        try {
            for (cycle in 0 until 30) {
                val guest = if (cycle < 15) reused else GuestTunnel(context)
                val row = JSONObject().put("cycle", cycle).put("mode", if (cycle < 15) "reused" else "fresh")
                    .put("startElapsedMs", SystemClock.elapsedRealtime())
                val errors = mutableListOf<String>()
                var uncertain = false
                try {
                    val before = probe(cycle, stopped = true)
                    row.put("before", recordProbe(before))
                    check(before.getBoolean("vpnGone")) { "prior VPN still visible" }
                    check(lifecycleCall { guest.start(config) } == Tunnel.State.UP) { "start did not return UP" }
                    row.put("serviceAfterStart", serviceRunning())
                    row.put("vpnStartedElapsedMs", SystemClock.elapsedRealtime())
                    val order = if (cycle % 2 == 0) listOf(false, true) else listOf(true, false)
                    row.put("order", if (order[0]) "bound,default" else "default,bound")
                    for (bound in order) {
                        val name = if (bound) "bound" else "default"
                        val beforeStats = lifecycleCall { guest.statistics() }
                        val txBefore = beforeStats.totalTx(); val rxBefore = beforeStats.totalRx()
                        val result = probe(cycle, bound = bound, variant = if (bound) "B" else "A")
                        val afterStats = lifecycleCall { guest.statistics() }
                        val sample = recordProbe(result).put("wgTxBefore", txBefore).put("wgRxBefore", rxBefore)
                            .put("wgTxAfter", afterStats.totalTx()).put("wgRxAfter", afterStats.totalRx())
                            .put("handshakeMillis", afterStats.peer(ownerKey.publicKey)?.latestHandshakeEpochMillis() ?: 0L)
                        row.put(name, sample)
                        if (result.getInt("uid", -1) < 0 || result.getInt("uid", -1) == Process.myUid()) errors.add("$name-uid")
                        if (!result.getBoolean("sent")) errors.add("$name-send")
                        if (!result.getBoolean("echo")) errors.add("$name-echo")
                    }
                    // No application-level hooks exist in the upstream Android AAR.
                    row.put("androidTunRead", "unavailable-upstream-aar")
                        .put("androidWgDatagramSend", "unavailable-upstream-aar")
                        .put("androidWgDatagramReceive", "unavailable-upstream-aar")
                        .put("androidDecrypt", "unavailable-upstream-aar")
                        .put("androidTunWrite", "unavailable-upstream-aar")
                        .put("soMark", "unavailable-not-a-validation-condition")
                } catch (e: TimeoutException) {
                    errors.add("lifecycle-timeout"); uncertain = true
                } catch (e: Exception) {
                    errors.add("exception:${e.javaClass.simpleName}")
                } finally {
                    try {
                        if (uncertain) throw IllegalStateException("lifecycle uncertain")
                        val state = lifecycleCall { guest.stop() }
                        row.put("stopState", state.toString()).put("serviceAfterStop", serviceRunning())
                        val after = probe(cycle, stopped = true)
                        row.put("after", recordProbe(after))
                        if (state != Tunnel.State.DOWN || serviceRunning() || !after.getBoolean("vpnGone")) {
                            errors.add("cleanup"); uncertain = true
                        }
                        val marker = Any(); val released = VpnRoleLease.acquire(marker)
                        if (released) VpnRoleLease.release(marker) else { errors.add("lease"); uncertain = true }
                        row.put("leaseReleased", released)
                    } catch (e: Exception) { errors.add("stop:${e.javaClass.simpleName}"); uncertain = true }
                    row.put("endElapsedMs", SystemClock.elapsedRealtime()).put("errors", errors.joinToString(","))
                    // Android log entries have a size limit. Chunk rather than
                    // silently truncating failures or relying on a shell pipe.
                    val text = row.toString()
                    val parts = text.chunked(1000)
                    parts.forEachIndexed { index, part ->
                        android.util.Log.i("NexaLinkShort", "PART=$cycle:$index/${parts.size}:$part")
                    }
                    completed++
                    if (errors.isNotEmpty()) failures++
                }
                if (uncertain) { cleanupUncertain = true; break }
            }
        } finally { shell("appops set ${context.packageName} ACTIVATE_VPN ignore") }
        assertEquals("all short diagnostic cycles must be recorded", 30, completed)
        assertEquals("baseline and differential probes must succeed without retries", 0, failures)
    }

    /** Separate lifecycle observation; it does not replace the phase 8.2 baseline. */
    @Test(timeout = 180000) fun lifecycleObservation() {
        assumeTrue(Build.VERSION.SDK_INT >= 29)
        assertFalse("previous cleanup uncertain", cleanupUncertain)
        shell("appops set ${context.packageName} ACTIVATE_VPN allow")
        assertNull(VpnService.prepare(context))
        val guestKey = KeyPair(Key.fromBase64("YWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWE="))
        val ownerKey = KeyPair(Key.fromBase64("YmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmI="))
        val config = Config.Builder().setInterface(Interface.Builder().setKeyPair(guestKey)
            .addAddress(InetNetwork.parse("10.77.0.2/32")).setMtu(1280).build())
            .addPeer(Peer.Builder().setPublicKey(ownerKey.publicKey)
                .setEndpoint(InetEndpoint.parse("10.0.2.2:38673"))
                .addAllowedIp(InetNetwork.parse("0.0.0.0/0")).build()).build()
        val guest = GuestTunnel(context)
        var completed = 0
        var failures = 0
        try {
            for (cycle in 0 until 8) {
                val row = JSONObject().put("cycle", cycle).put("beginElapsedMs", SystemClock.elapsedRealtime()).put("probeCycle", cycle + 100)
                    .put("tunEstablishedEvent", "unavailable-in-public-aar")
                    .put("socketOpenedEvent", "unavailable-in-public-aar")
                    .put("protectResult", "unavailable-in-public-aar")
                    .put("handshakeEvent", "not-exposed-snapshot-only")
                    .put("tunPacketEvent", "not-exposed")
                val errors = mutableListOf<String>()
                var uncertain = false
                var sockets: JSONObject? = null
                try {
                    row.put("stateBefore", lifecycleCall { guest.state() }.toString())
                        .put("serviceBefore", serviceRunning()).put("before", recordProbe(probe(cycle + 100, stopped = true)))
                    if (!row.getJSONObject("before").optBoolean("vpnGone")) error("prior VPN remains")
                    row.put("startCalledElapsedMs", SystemClock.elapsedRealtime())
                    row.put("startReturnedState", lifecycleCall { guest.start(config) }.toString())
                        .put("startReturnedElapsedMs", SystemClock.elapsedRealtime()).put("serviceAfterStart", serviceRunning())
                    // Test-only reflection: FD snapshot is not an opening event or proof of protect.
                    sockets = lifecycleCall { wireGuardSockets(guest, inspectMark = false) }
                    row.put("socketSnapshotAfterStart", sockets).put("socketSnapshotElapsedMs", SystemClock.elapsedRealtime())
                    row.put("networkAfterStart", recordProbe(probe(cycle + 100, inspect = true)))
                    val sample = probe(cycle + 100, variant = "A")
                    row.put("firstProbe", recordProbe(sample))
                    val stats = lifecycleCall { guest.statistics() }
                    row.put("statisticsObservedElapsedMs", SystemClock.elapsedRealtime())
                        .put("wgTxBytes", stats.totalTx()).put("wgRxBytes", stats.totalRx())
                        .put("latestHandshakeEpochMs", stats.peer(ownerKey.publicKey)?.latestHandshakeEpochMillis() ?: 0L)
                    if (!sample.getBoolean("sent") || !sample.getBoolean("echo")) errors.add("probe")
                    if (row.optString("startReturnedState") != "UP") errors.add("start")
                } catch (e: TimeoutException) {
                    errors.add("lifecycle-timeout"); uncertain = true
                } catch (e: Exception) { errors.add("exception:${e.javaClass.simpleName}") }
                finally {
                    try {
                        if (uncertain) throw IllegalStateException("lifecycle uncertain")
                        row.put("stopCalledElapsedMs", SystemClock.elapsedRealtime())
                        val state = lifecycleCall { guest.stop() }
                        row.put("stopReturnedState", state.toString()).put("stopReturnedElapsedMs", SystemClock.elapsedRealtime())
                            .put("serviceAfterStop", serviceRunning()).put("after", recordProbe(probe(cycle + 100, stopped = true)))
                        sockets?.let { row.put("socketSnapshotAfterStop", socketsClosed(it)) }
                        val marker = Any(); val released = VpnRoleLease.acquire(marker)
                        if (released) VpnRoleLease.release(marker) else { errors.add("lease"); uncertain = true }
                        row.put("leaseReleased", released)
                        if (state != Tunnel.State.DOWN || serviceRunning() || !row.getJSONObject("after").optBoolean("vpnGone")) {
                            errors.add("cleanup"); uncertain = true
                        }
                    } catch (e: Exception) { errors.add("stop:${e.javaClass.simpleName}"); uncertain = true }
                    row.put("errors", errors.joinToString(",")).put("endElapsedMs", SystemClock.elapsedRealtime())
                    val parts = row.toString().chunked(1000)
                    parts.forEachIndexed { i, part -> android.util.Log.i("NexaLinkLife", "PART=$cycle:$i/${parts.size}:$part") }
                    completed++
                    if (errors.isNotEmpty()) failures++
                }
                if (uncertain) { cleanupUncertain = true; break }
            }
        } finally { shell("appops set ${context.packageName} ACTIVATE_VPN ignore") }
        assertEquals("all lifecycle observations recorded", 8, completed)
        assertEquals("no probe or lifecycle failures", 0, failures)
    }

    @Test(timeout = 2400000) fun oneHundredRealGuestCycles() {
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
                var sockets: JSONObject? = null
                var lifecycleUncertain = false
                checkpoint(cycle, "begin")
                try {
                    val before = probe(cycle, stopped = true)
                    row.put("before", recordProbe(before))
                    if (!before.getBoolean("vpnGone") || before.getInt("uid", -1) == Process.myUid()) errors.add("prior-vpn-not-gone-or-uid")
                    if (errors.isEmpty()) {
                        checkpoint(cycle, "starting")
                        if (lifecycleCall { guest.start(config) } != Tunnel.State.UP) errors.add("start-not-up") else started = true
                        checkpoint(cycle, "started")
                    }
                    row.put("serviceAfterStart", serviceRunning())
                    if (started) {
                        sockets = wireGuardSockets(guest)
                        row.put("wireSocketsBefore", sockets)
                        checkpoint(cycle, "inspect")
                        val inspected = probe(cycle, inspect = true)
                        checkpoint(cycle, "inspected")
                        row.put("inspect", recordProbe(inspected))
                        val iface = inspected.getString("interfaceName")
                        row.put("tunBefore", tunCounters(iface))
                        checkpoint(cycle, "counters-before")
                        checkpoint(cycle, "probe")
                        val result = probe(cycle)
                        checkpoint(cycle, "probed")
                        row.put("probe", recordProbe(result))
                        row.put("tunAfter", tunCounters(iface))
                        row.put("wireSocketsAfter", wireGuardSockets(guest))
                        val stats = lifecycleCall { guest.statistics() }
                        val peer = stats.peer(ownerKey.publicKey)
                        row.put("wgTxBytes", stats.totalTx()).put("wgRxBytes", stats.totalRx())
                            .put("handshakeMillis", peer?.latestHandshakeEpochMillis() ?: 0L)
                        if (result.getInt("uid", -1) < 0 || result.getInt("uid", -1) == Process.myUid()) errors.add("wrong-probe-uid")
                        if (!result.getBoolean("sent")) errors.add("send")
                        if (!result.getBoolean("echo")) errors.add("echo")
                        if (stats.totalTx() <= 0 || stats.totalRx() <= 0) errors.add("wg-bytes")
                        if ((peer?.latestHandshakeEpochMillis() ?: 0L) <= 0L) errors.add("handshake")
                        // Differential probe is diagnostic only: it cannot turn a failed cycle into success.
                        if (errors.isNotEmpty() && failures < 10) row.put("boundDiagnostic", recordProbe(probe(cycle, bound = true)))
                    }
                } catch (e: TimeoutException) {
                    errors.add("lifecycle-timeout")
                    lifecycleUncertain = true
                    blocked = true
                } catch (e: Exception) {
                    errors.add("exception:${e.javaClass.simpleName}")
                } catch (e: AssertionError) {
                    errors.add("assertion:${e.javaClass.simpleName}")
                } finally {
                    try {
                        if (lifecycleUncertain) throw IllegalStateException("lifecycle still uncertain")
                        checkpoint(cycle, "stopping")
                        val state = lifecycleCall { guest.stop() }
                        checkpoint(cycle, "stopped")
                        row.put("stopState", state.toString()).put("serviceAfterStop", serviceRunning())
                        sockets?.let {
                            val closed = socketsClosed(it)
                            row.put("wireSocketsClosed", closed)
                            if (closed.optString("V4") == "still-open" || closed.optString("V6") == "still-open") errors.add("wire-socket-still-open")
                        }
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
                    android.util.Log.i("NexaLinkCycle", "RECORD=${row}")
                }
                if (blocked) {
                    cleanupUncertain = true
                    break // fail closed: never overlap another VPN when cleanup is uncertain
                }
            }
        } finally { shell("appops set ${context.packageName} ACTIVATE_VPN ignore") }
        assertEquals("all 100 cycles must execute; diagnostics in phase81-cycles.jsonl", 100, completed)
        assertEquals("every cycle must pass without a retry", 0, failures)
    }
}
