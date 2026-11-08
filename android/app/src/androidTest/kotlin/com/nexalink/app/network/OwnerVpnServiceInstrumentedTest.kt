package com.nexalink.app.network

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.net.ConnectivityManager
import android.util.Log
import android.os.Build
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

/** Uses real Android VPN and WireGuard on an isolated emulator, not Internet sharing. */
@RunWith(AndroidJUnit4::class)
class OwnerVpnServiceInstrumentedTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext

    private fun appOp(mode: String) {
        // Emulator-only test authorization; not a test of the consent dialog.
        val descriptor = instrumentation.uiAutomation.executeShellCommand("appops set ${context.packageName} ACTIVATE_VPN $mode")
        ParcelFileDescriptor.AutoCloseInputStream(descriptor).use { it.readBytes() }
    }

    private fun shell(command: String) {
        val fd = instrumentation.uiAutomation.executeShellCommand(command)
        ParcelFileDescriptor.AutoCloseInputStream(fd).use { it.readBytes() }
    }

    private fun awaitState(expected: OwnerServiceState, timeoutMs: Long = 20000): Boolean {
        val end = SystemClock.elapsedRealtime() + timeoutMs
        while (SystemClock.elapsedRealtime() < end) {
            if (OwnerServiceStateMonitor.state == expected) return true
            Thread.sleep(100)
        }
        return false
    }

    @Test(timeout = 100000) fun ownerServiceStartsAndStopsOnActualCellularLossWhenAvailable() {
        assumeTrue(Build.VERSION.SDK_INT >= 29)
        val egress = CellularEgress(context)
        assumeTrue("A validated cellular network is required for this test", egress.validatedCellularNetwork() != null)
        val parameters = OwnerSessionParameters(
            "YWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWE=",
            "YmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmI=", "10.77.0.2", 0,
        )
        val intent = Intent(context, OwnerVpnService::class.java)
        try {
            appOp("allow")
            assertNull(VpnService.prepare(context))
            assertTrue(OwnerSessionRequest.stage(parameters))
            context.startService(intent)
            val started = awaitState(OwnerServiceState.RUNNING_LOCAL)
            assertTrue("owner startup: ${OwnerServiceStateMonitor.failure}", started)
            assertFalse("guest Go runtime must not be loaded into the owner process", NativeRuntimeGuard.reserve(NativeRuntimeGuard.Kind.GUEST))
            // Android emulator's actual network is toggled, not an injected callback.
            shell("svc data disable")
            assertTrue("owner should stop after cellular loss", awaitState(OwnerServiceState.STOPPED))
            shell("svc data enable")
            val end = SystemClock.elapsedRealtime() + 20000
            while (egress.validatedCellularNetwork() == null && SystemClock.elapsedRealtime() < end) Thread.sleep(200)
            assertNotNull("cellular should return before explicit restart", egress.validatedCellularNetwork())
            assertTrue(OwnerSessionRequest.stage(parameters))
            context.startService(intent)
            assertTrue("a fresh service should start", awaitState(OwnerServiceState.RUNNING_LOCAL))
            context.stopService(intent)
            assertTrue("native cleanup must finish", awaitState(OwnerServiceState.STOPPED))
        } finally {
            shell("svc data enable")
            context.stopService(intent)
            OwnerSessionRequest.clear()
            appOp("ignore")
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
