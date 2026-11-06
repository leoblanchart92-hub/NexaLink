package com.nexalink.app.network

import androidx.test.ext.junit.runners.AndroidJUnit4
import mobile.Mobile
import mobile.SocketBinder
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/** Local JNI lifecycle tests only. The stub is NOT VPN protection or real cellular routing. */
@RunWith(AndroidJUnit4::class)
class GoBridgeStressInstrumentedTest {
    private val a = "YWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWE="
    private val b = "YmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmI="
    private fun binder() = object : SocketBinder {
        override fun bindSocket(fd: Int): Boolean = fd >= 0
    }

    @Test(timeout = 180000) fun oneHundredFreshEnginesAndRestarts() {
        val version = Mobile.runtimeVersion()
        repeat(100) {
            // Native libraries cannot safely be unloaded/reloaded by this API;
            // these are fresh Go engine objects, not shared-library reloads.
            val engine = Mobile.newEngine(binder())
            try {
                assertTrue(engine.start(a, b, "10.77.0.2", 0) in 1..65535)
                assertTrue(engine.statusJSON().contains("\"running\":true"))
            } finally { engine.stop() }
            assertTrue(engine.statusJSON().contains("\"running\":false"))
            engine.stop()
            assertEquals(version, Mobile.runtimeVersion())
        }
        val engine = Mobile.newEngine(binder())
        repeat(2) {
            try { assertTrue(engine.start(a, b, "10.77.0.2", 0) > 0) }
            finally { engine.stop() }
        }
    }

    @Test(timeout = 30000) fun invalidAndDoubleStartLeaveEngineUsable() {
        val engine = Mobile.newEngine(binder())
        try {
            var rejected = false
            try { engine.start("invalid", b, "10.77.0.2", 0) } catch (_: Exception) { rejected = true }
            assertTrue(rejected)
            assertTrue(engine.statusJSON().contains("\"running\":false"))
            assertTrue(engine.start(a, b, "10.77.0.2", 0) > 0)
            rejected = false
            try { engine.start(a, b, "10.77.0.2", 0) } catch (_: Exception) { rejected = true }
            assertTrue(rejected)
            assertTrue(engine.statusJSON().contains("\"running\":true"))
        } finally { engine.stop() }
        assertTrue(engine.start(a, b, "10.77.0.2", 0) > 0)
        engine.stop()
    }

    @Test(timeout = 30000) fun simultaneousStatusAndStopAreSerialized() {
        val engine = Mobile.newEngine(binder())
        val pool = Executors.newFixedThreadPool(5)
        try {
            assertTrue(engine.start(a, b, "10.77.0.2", 0) > 0)
            val gate = CountDownLatch(1)
            val tasks = (0 until 5).map { i -> pool.submit {
                assertTrue(gate.await(10, TimeUnit.SECONDS))
                repeat(20) {
                    if (i == 0) engine.stop() else {
                        assertTrue(Mobile.runtimeVersion().startsWith("go"))
                        assertTrue(engine.statusJSON().contains("\"running\":"))
                    }
                }
            } }
            gate.countDown()
            tasks.forEach { it.get(20, TimeUnit.SECONDS) }
            assertTrue(engine.statusJSON().contains("\"running\":false"))
        } finally { engine.stop(); pool.shutdownNow() }
    }

    @Test(timeout = 30000) fun stopDuringBlockedStartClosesAfterCallbackReturns() {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val count = AtomicInteger()
        val engine = Mobile.newEngine(object : SocketBinder {
            override fun bindSocket(fd: Int): Boolean {
                if (count.getAndIncrement() == 0) {
                    entered.countDown()
                    if (!release.await(10, TimeUnit.SECONDS)) return false
                }
                return fd >= 0
            }
        })
        val pool = Executors.newFixedThreadPool(2)
        try {
            val start = pool.submit<Int> { engine.start(a, b, "10.77.0.2", 0) }
            assertTrue(entered.await(10, TimeUnit.SECONDS))
            val stop = pool.submit { engine.stop() }
            release.countDown()
            assertTrue(start.get(10, TimeUnit.SECONDS) > 0)
            stop.get(10, TimeUnit.SECONDS)
            assertTrue(engine.statusJSON().contains("\"running\":false"))
        } finally { release.countDown(); engine.stop(); pool.shutdownNow() }
    }
}
