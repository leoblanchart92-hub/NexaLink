package com.nexalink.app.network

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/** Tests coordination using a test double; not Android network or VPN tests. */
class OwnerEngineControllerTest {
    private class TestEngine : LocalOwnerEngine {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val stops = AtomicInteger()
        @Volatile var fail = false
        override fun start(privateKey: String, guestPublicKey: String, guestAddress: String, port: Int): Int {
            entered.countDown()
            check(release.await(5, TimeUnit.SECONDS))
            check(!fail)
            return 1234
        }
        override fun stop() { stops.incrementAndGet() }
    }
    private fun drain(executor: java.util.concurrent.ExecutorService) { executor.submit {}.get(5, TimeUnit.SECONDS) }
    private fun start(c: OwnerEngineController) = c.start("test", "test", "10.0.0.2", 0)

    @Test fun doubleStartAndNormalRestart() {
        val worker = Executors.newSingleThreadExecutor(); val engine = TestEngine()
        val c = OwnerEngineController(engine, worker)
        try {
            assertTrue(start(c)); assertTrue(engine.entered.await(5, TimeUnit.SECONDS)); assertFalse(start(c))
            engine.release.countDown(); drain(worker); assertEquals(OwnerState.RUNNING_LOCAL, c.state())
            assertTrue(c.stop()); drain(worker); assertEquals(OwnerState.IDLE, c.state())
            assertTrue(start(c)); drain(worker); assertEquals(OwnerState.RUNNING_LOCAL, c.state())
            assertTrue(c.stop()); drain(worker); assertEquals(2, engine.stops.get())
        } finally { worker.shutdownNow() }
    }

    @Test fun lossDuringStartQueuesCleanupAndForbidsFallbackOrRestart() {
        val worker = Executors.newSingleThreadExecutor(); val engine = TestEngine()
        val c = OwnerEngineController(engine, worker)
        try {
            assertTrue(start(c)); assertTrue(engine.entered.await(5, TimeUnit.SECONDS))
            c.onNetworkLost(); assertEquals(OwnerState.STOPPING, c.state()); assertFalse(start(c))
            engine.release.countDown(); drain(worker)
            assertEquals(OwnerState.NETWORK_LOST, c.state()); assertEquals(1, engine.stops.get())
            assertFalse(start(c))
        } finally { worker.shutdownNow() }
    }

    @Test fun destroyDuringStartClosesBeforeDestroyed() {
        val worker = Executors.newSingleThreadExecutor(); val engine = TestEngine()
        val c = OwnerEngineController(engine, worker)
        assertTrue(start(c)); assertTrue(engine.entered.await(5, TimeUnit.SECONDS))
        c.destroy(); assertEquals(OwnerState.STOPPING, c.state()); engine.release.countDown()
        assertTrue(worker.awaitTermination(5, TimeUnit.SECONDS))
        assertEquals(OwnerState.DESTROYED, c.state()); assertEquals(1, engine.stops.get())
        assertFalse(start(c)); c.destroy()
    }

    @Test fun failedStartIsNotReportedAsRunning() {
        val worker = Executors.newSingleThreadExecutor(); val engine = TestEngine(); engine.fail = true
        val c = OwnerEngineController(engine, worker)
        try {
            engine.release.countDown(); assertTrue(start(c)); drain(worker)
            assertEquals(OwnerState.FAILED, c.state()); assertTrue(c.stop()); drain(worker)
            assertEquals(OwnerState.IDLE, c.state())
        } finally { worker.shutdownNow() }
    }
}
