package com.nexalink.app.network

import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/** Internal preparation for a future authorized service; never exposed to Flutter.
 * RUNNING_LOCAL only means Go started; it is not a handshake or Internet access.
 * Stop cannot interrupt an in-progress native callback, but is queued on the same
 * worker and runs immediately after it returns. Never call this from a VPN UI as
 * proof of network protection, and never automatically migrate to another network.
 */
internal interface LocalOwnerEngine {
    fun start(privateKey: String, guestPublicKey: String, guestAddress: String, port: Int): Int
    fun stop()
}

internal enum class OwnerState { IDLE, STARTING, RUNNING_LOCAL, STOPPING, NETWORK_LOST, FAILED, DESTROYED }

internal class OwnerEngineController(
    private val engine: LocalOwnerEngine,
    private val executor: ExecutorService = Executors.newSingleThreadExecutor(),
) {
    private val lock = Any()
    private var state = OwnerState.IDLE
    private var networkLost = false
    private var destroyRequested = false

    fun state(): OwnerState = synchronized(lock) { state }

    /** The caller must already hold consent and the chosen validated cellular network. */
    fun start(privateKey: String, guestPublicKey: String, guestAddress: String, port: Int): Boolean = synchronized(lock) {
        if (state != OwnerState.IDLE || networkLost || destroyRequested) return false
        state = OwnerState.STARTING
        executor.execute {
            val ok = try { engine.start(privateKey, guestPublicKey, guestAddress, port) > 0 } catch (_: Exception) { false }
            synchronized(lock) {
                // A queued stop owns cleanup if network loss/destruction occurred.
                if (state == OwnerState.STARTING) state = if (ok) OwnerState.RUNNING_LOCAL else OwnerState.FAILED
            }
        }
        true
    }

    fun stop(): Boolean = synchronized(lock) { if (destroyRequested) false else enqueueStop() }

    /** Permanently invalidates this controller; selecting a new network requires a new one. */
    fun onNetworkLost() = synchronized(lock) {
        if (destroyRequested) return@synchronized
        networkLost = true
        if (state == OwnerState.IDLE || state == OwnerState.FAILED) state = OwnerState.NETWORK_LOST
        else if (state != OwnerState.DESTROYED && state != OwnerState.STOPPING) enqueueStop()
    }

    /** Asynchronous: DESTROYED is published only after engine.stop returns. */
    fun destroy() = synchronized(lock) {
        if (!destroyRequested) {
            destroyRequested = true
            if (state != OwnerState.STOPPING && state != OwnerState.DESTROYED) enqueueStop()
        }
    }

    private fun enqueueStop(): Boolean {
        if (state == OwnerState.DESTROYED || state == OwnerState.STOPPING) return false
        state = OwnerState.STOPPING
        executor.execute {
            val closed = try { engine.stop(); true } catch (_: Exception) { false }
            synchronized(lock) {
                state = when {
                    !closed -> OwnerState.FAILED
                    destroyRequested -> OwnerState.DESTROYED
                    networkLost -> OwnerState.NETWORK_LOST
                    else -> OwnerState.IDLE
                }
                if (destroyRequested) executor.shutdown()
            }
        }
        return true
    }
}
