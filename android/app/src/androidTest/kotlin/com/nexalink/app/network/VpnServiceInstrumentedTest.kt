package com.nexalink.app.network

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.net.ConnectivityManager
import android.util.Log
import android.os.Build
import android.os.ParcelFileDescriptor
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

/** Uses real Android VPN and WireGuard on an isolated emulator, not Internet sharing. */
@RunWith(AndroidJUnit4::class)
class VpnServiceInstrumentedTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext

    private fun appOp(mode: String) {
        // Emulator-only test authorization; not a test of the consent dialog.
        val descriptor = instrumentation.uiAutomation.executeShellCommand("appops set ${context.packageName} ACTIVATE_VPN $mode")
        ParcelFileDescriptor.AutoCloseInputStream(descriptor).use { it.readBytes() }
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
        socket.soTimeout = 15000
        val guest = GuestTunnel(context)
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
                Log.i("NexaLinkVPN", "Tunnel UP, cycle $it; sending routed probe")
                val probe = DatagramSocket()
                try {
                    val data = byteArrayOf(1, 2, 3)
                    probe.send(DatagramPacket(data, data.size, InetAddress.getByName("198.18.0.1"), 5555))
                    val wire = ByteArray(2048)
                    val packet = DatagramPacket(wire, wire.size)
                    socket.receive(packet)
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

    @Test(timeout = 15000) fun ownerRejectsStartWithoutStagedSession() {
        assumeTrue(Build.VERSION.SDK_INT >= 29)
        OwnerSessionRequest.clear()
        context.startService(Intent(context, OwnerVpnService::class.java))
        instrumentation.waitForIdleSync()
        val activity = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        var stopped = false
        repeat(40) {
            @Suppress("DEPRECATION")
            val running = activity.getRunningServices(100).any { it.service.className == OwnerVpnService::class.java.name }
            if (!running) { stopped = true; return@repeat }
            Thread.sleep(100)
        }
        assertTrue("service must fail closed with no staged session", stopped)
    }
}
