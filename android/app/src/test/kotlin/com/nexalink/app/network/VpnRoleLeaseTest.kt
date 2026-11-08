package com.nexalink.app.network

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class VpnRoleLeaseTest {
    @Test fun oneRoleAtATimeAndOnlyOwnerCanRelease() {
        val owner = Any(); val guest = Any()
        try {
            assertTrue(VpnRoleLease.acquire(owner))
            assertFalse(VpnRoleLease.acquire(guest))
            VpnRoleLease.release(guest)
            assertFalse(VpnRoleLease.acquire(guest))
            VpnRoleLease.release(owner)
            assertTrue(VpnRoleLease.acquire(guest))
        } finally { VpnRoleLease.release(owner); VpnRoleLease.release(guest) }
    }

    @Test fun concurrentAcquisitionHasOnlyOneWinner() {
        val a = Any(); val b = Any(); val gate = CountDownLatch(1)
        val pool = Executors.newFixedThreadPool(2)
        try {
            val first = pool.submit<Boolean> { gate.await(); VpnRoleLease.acquire(a) }
            val second = pool.submit<Boolean> { gate.await(); VpnRoleLease.acquire(b) }
            gate.countDown()
            assertNotEquals(first.get(5, TimeUnit.SECONDS), second.get(5, TimeUnit.SECONDS))
        } finally { pool.shutdownNow(); VpnRoleLease.release(a); VpnRoleLease.release(b) }
    }

    @Test fun pendingOwnerCredentialsAreOneShot() {
        val p = OwnerSessionParameters("private", "public", "10.0.0.2", 0)
        try {
            assertTrue(OwnerSessionRequest.stage(p))
            assertFalse(OwnerSessionRequest.stage(p))
            assertSame(p, OwnerSessionRequest.take())
            assertNull(OwnerSessionRequest.take())
        } finally { OwnerSessionRequest.clear() }
    }
}
