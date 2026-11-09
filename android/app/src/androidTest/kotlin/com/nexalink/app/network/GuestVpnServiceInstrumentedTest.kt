package com.nexalink.app.network

import android.app.ActivityManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.util.Log
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.ParcelFileDescriptor
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
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Uses real Android VPN and WireGuard on an isolated emulator, not Internet sharing. */
@RunWith(AndroidJUnit4::class)
class GuestVpnServiceInstrumentedTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext

    private fun appOp(mode: String) {
        // Emulator-only test authorization; not a test of the consent dialog.
        val descriptor = instrumentation.uiAutomation.executeShellCommand("appops set ${context.packageName} ACTIVATE_VPN $mode")
        ParcelFileDescriptor.AutoCloseInputStream(descriptor).use { it.readBytes() }
    }

    private fun sendProbeFromTestUid(expectEcho: Boolean = false) {
        val done = CountDownLatch(1)
        var uid = -1
        var sent = false
        var error: String? = null
        var echo = false
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val extras = getResultExtras(false)
                uid = extras?.getInt("uid", -1) ?: -1
                sent = extras?.getBoolean("sent", false) ?: false
                error = extras?.getString("error")
                echo = extras?.getBoolean("echo", false) ?: false
                done.countDown()
            }
        }
        context.sendOrderedBroadcast(Intent().setClassName(
            instrumentation.context.packageName, "com.nexalink.app.network.VpnProbeReceiver",
        ).putExtra("expectEcho", expectEcho), null, receiver, Handler(Looper.getMainLooper()), 0, null, null)
        assertTrue("test APK probe receiver must complete", done.await(12, TimeUnit.SECONDS))
        assertTrue("probe must execute under a distinct test APK UID", uid >= 0 && uid != Process.myUid())
        assertTrue("test APK UDP send failed: $error", sent)
        if (expectEcho) assertTrue("routed UDP echo must return through WireGuard and the Android TUN: $error", echo)
    }

    private fun awaitVpnRoute() {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val end = SystemClock.elapsedRealtime() + 10000
        while (SystemClock.elapsedRealtime() < end) {
            val ready = cm.allNetworks.any { network ->
                cm.getNetworkCapabilities(network)?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true &&
                    cm.getLinkProperties(network)?.routes?.any {
                        it.matches(InetAddress.getByName("198.18.0.1"))
                    } == true
            }
            if (ready) return
            Thread.sleep(100)
        }
        fail("VPN network and probe route must be visible before sending")
    }

    @Test(timeout = 60000) fun consentAndGuestTunProduceLocalWireGuardHandshakeAndStop() {
        assumeTrue(Build.VERSION.SDK_INT >= 29)
        appOp("ignore")
        assertNotNull("VPN consent must be required", VpnService.prepare(context))
        appOp("allow")
        assertNull("VPN consent must be granted on the test emulator", VpnService.prepare(context))
        val privateKey = "YWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWE="
        val publicKey = "YmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmI="
        val socket = DatagramSocket(0, InetAddress.getByName("127.0.0.1"))
        socket.soTimeout = 1500
        val guest = GuestTunnel(context)
        assertFalse("owner Go runtime must not be loaded into the guest process", NativeRuntimeGuard.reserve(NativeRuntimeGuard.Kind.OWNER))
        val config = Config.Builder()
            .setInterface(Interface.Builder().setKeyPair(KeyPair(Key.fromBase64(privateKey)))
                .addAddress(InetNetwork.parse("10.77.0.2/32")).build())
            .addPeer(Peer.Builder().setPublicKey(Key.fromBase64(publicKey))
                .setEndpoint(InetEndpoint.parse("127.0.0.1:${socket.localPort}"))
                .addAllowedIp(InetNetwork.parse("198.18.0.1/32")).build())
            .build()
        try {
            repeat(2) {
                assertEquals(Tunnel.State.UP, guest.start(config))
                val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                cm.allNetworks.forEach { Log.i("NexaLinkVPN", "network=${it} routes=${cm.getLinkProperties(it)?.routes}") }
                awaitVpnRoute()
                Log.i("NexaLinkVPN", "Tunnel UP, cycle $it; sending routed probe")
                val probe = DatagramSocket()
                try {
                    val data = byteArrayOf(1, 2, 3)
                    probe.send(DatagramPacket(data, data.size, InetAddress.getByName("198.18.0.1"), 5555))
                    // Only the distinct test APK UID proves an ordinary application route.
                    val wire = ByteArray(2048)
                    val packet = DatagramPacket(wire, wire.size)
                    var received = false
                    repeat(10) {
                        if (!received) {
                            sendProbeFromTestUid()
                            try { socket.receive(packet); received = true }
                            catch (_: java.net.SocketTimeoutException) { }
                        }
                    }
                    assertTrue("WireGuard initiation must be observed", received)
                    Log.i("NexaLinkVPN", "Received WireGuard datagram in cycle $it")
                    // WireGuard handshake initiation, not plaintext IP, is observed on loopback.
                    assertEquals(148, packet.length)
                    assertEquals(1, wire[0].toInt())
                } finally { probe.close() }
                assertEquals(Tunnel.State.DOWN, guest.stop())
                assertEquals(Tunnel.State.DOWN, guest.state())
                // Wait for the WireGuard service to finish destruction before restart.
                val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                var serviceGone = false
                for (i in 0 until 50) {
                    @Suppress("DEPRECATION")
                    val running = manager.getRunningServices(100).any {
                        it.service.className == "com.wireguard.android.backend.GoBackend\$VpnService"
                    }
                    if (!running) { serviceGone = true; break }
                    Thread.sleep(100)
                }
                assertTrue("WireGuard service must stop before restart", serviceGone)
            }
        } finally {
            try { guest.stop() } finally { socket.close(); appOp("ignore") }
        }
    }

    /** A real second WireGuard endpoint runs on the CI host, loopback-only.
     * The test APK is an ordinary separate UID and checks the returned bytes.
     * 0/0 deliberately includes the endpoint: GoBackend must protect its sockets.
     */
    @Test(timeout = 90000) fun guestTunRoundTripsThroughRealWireGuardPeer() {
        assumeTrue(Build.VERSION.SDK_INT >= 29)
        appOp("allow")
        val guest = GuestTunnel(context)
        val guestKey = KeyPair(Key.fromBase64("YWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWE="))
        val ownerKey = KeyPair(Key.fromBase64("YmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmI="))
        val config = Config.Builder()
            .setInterface(Interface.Builder().setKeyPair(guestKey)
                .addAddress(InetNetwork.parse("10.77.0.2/32")).setMtu(1280).build())
            .addPeer(Peer.Builder().setPublicKey(ownerKey.publicKey)
                .setEndpoint(InetEndpoint.parse("10.0.2.2:38673"))
                .addAllowedIp(InetNetwork.parse("0.0.0.0/0")).build())
            .build()
        try {
            repeat(2) { cycle ->
                assertEquals(Tunnel.State.UP, guest.start(config))
                awaitVpnRoute()
                try { sendProbeFromTestUid(expectEcho = true) } finally {
                    val diagnostic = guest.statistics()
                    Log.i("NexaLinkVPN", "Guest WG byte totals tx=${diagnostic.totalTx()} rx=${diagnostic.totalRx()}")
                }
                val stats = guest.statistics()
                assertTrue("WireGuard transmitted bytes in cycle $cycle", stats.totalTx() > 0)
                assertTrue("WireGuard received bytes in cycle $cycle", stats.totalRx() > 0)
                Log.i("NexaLinkVPN", "Bidirectional test succeeded in cycle $cycle")
                assertEquals(Tunnel.State.DOWN, guest.stop())
                assertEquals(Tunnel.State.DOWN, guest.state())
            }
        } finally {
            try { guest.stop() } finally { appOp("ignore") }
        }
    }

}
