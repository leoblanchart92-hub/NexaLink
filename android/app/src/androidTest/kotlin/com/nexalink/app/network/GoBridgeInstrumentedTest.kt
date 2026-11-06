package com.nexalink.app.network

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import android.util.Log
import org.junit.Before
import org.junit.Assert.assertEquals
import mobile.Mobile
import mobile.SocketBinder
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.atomic.AtomicInteger

/** JNI lifecycle/fail-closed smoke test; no VpnService or real mobile network. */
@RunWith(AndroidJUnit4::class)
class GoBridgeInstrumentedTest {
    @Before fun verifyArchitecture() {
        val actual = Mobile.runtimeArchitecture()
        Log.i("NexaLinkABI", "Go runtime architecture: $actual")
        InstrumentationRegistry.getArguments().getString("expectedGoArch")?.let { assertEquals(it, actual) }
    }
    @Test fun startsAndStopsLocalEngineWithTestOnlyBinder() {
        // This deliberately permissive stub is restricted to this isolated
        // emulator test. It does NOT validate VPN protection or cellular routing.
        val calls = AtomicInteger()
        val binder = object : SocketBinder {
            override fun bindSocket(fd: Int): Boolean { calls.incrementAndGet(); return true }
        }
        val engine = Mobile.newEngine(binder)
        val a = "YWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWE="
        val b = "YmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmI="
        try {
            val port = engine.start(a, b, "10.77.0.2", 0)
            assertTrue(port in 1..65535)
            assertTrue(calls.get() >= 2)
            assertTrue(engine.statusJSON().contains("\"running\":true"))
        } finally { engine.stop() }
        assertTrue(engine.statusJSON().contains("\"running\":false"))
    }

    @Test fun loadsGoAndRefusesToStartWhenBindingIsDenied() {
        assertTrue(Mobile.runtimeVersion().startsWith("go"))
        val calls = AtomicInteger()
        val binder = object : SocketBinder {
            override fun bindSocket(fd: Int): Boolean {
                calls.incrementAndGet()
                return false
            }
        }
        val engine = Mobile.newEngine(binder)
        // Fixed non-secret keys for a test that must never become connected.
        val a = "YWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWE="
        val b = "YmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmI="
        var failed = false
        try { engine.start(a, b, "10.77.0.2", 0) } catch (_: Exception) { failed = true }
        assertTrue("unprotected engine start must fail", failed)
        assertTrue("Go must invoke Kotlin's socket binder", calls.get() > 0)
        assertTrue(engine.statusJSON().contains("\"running\":false"))
        engine.stop()
        engine.stop()
        assertFalse(engine.statusJSON().contains("\"running\":true"))
    }
}
