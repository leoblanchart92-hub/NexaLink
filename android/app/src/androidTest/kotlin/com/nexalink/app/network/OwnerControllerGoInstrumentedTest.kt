package com.nexalink.app.network

import androidx.test.ext.junit.runners.AndroidJUnit4
import mobile.Mobile
import mobile.SocketBinder
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Real JNI engine + controller; test-only callback does not protect/bind sockets. */
@RunWith(AndroidJUnit4::class)
class OwnerControllerGoInstrumentedTest {
    @Test(timeout = 45000) fun networkLossStopsRealLocalEngineAndFreshControllerCanRestart() {
        val privateKey = "YWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWE="
        val publicKey = "YmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmI="
        fun runOne(simulateLoss: Boolean) {
            val worker = Executors.newSingleThreadExecutor()
            val native = Mobile.newEngine(object : SocketBinder {
                override fun bindSocket(fd: Int): Boolean = fd >= 0
            })
            val controller = OwnerEngineController(object : LocalOwnerEngine {
                override fun start(privateKey: String, guestPublicKey: String, guestAddress: String, port: Int): Int =
                    native.start(privateKey, guestPublicKey, guestAddress, port)
                override fun stop() = native.stop()
            }, worker)
            try {
                assertTrue(controller.start(privateKey, publicKey, "10.77.0.2", 0))
                worker.submit {}.get(10, TimeUnit.SECONDS)
                assertEquals(OwnerState.RUNNING_LOCAL, controller.state())
                assertTrue(native.statusJSON().contains("\"running\":true"))
                if (simulateLoss) controller.onNetworkLost() else assertTrue(controller.stop())
                worker.submit {}.get(10, TimeUnit.SECONDS)
                assertTrue(native.statusJSON().contains("\"running\":false"))
                assertEquals(if (simulateLoss) OwnerState.NETWORK_LOST else OwnerState.IDLE, controller.state())
                if (simulateLoss) assertFalse(controller.start(privateKey, publicKey, "10.77.0.2", 0))
                controller.destroy()
                assertTrue(worker.awaitTermination(10, TimeUnit.SECONDS))
                assertEquals(OwnerState.DESTROYED, controller.state())
            } finally { native.stop(); worker.shutdownNow() }
        }
        // This exercises an injected loss event, not a real ConnectivityManager loss.
        runOne(true)
        runOne(false)
    }
}
