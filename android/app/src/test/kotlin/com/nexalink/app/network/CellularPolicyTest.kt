package com.nexalink.app.network

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CellularPolicyTest {
    @Test fun requiresValidatedCellularWithoutWifiOrVpn() {
        assertTrue(isAllowedCellular(true, false, false, true, true))
        assertFalse(isAllowedCellular(false, true, false, true, true))
        assertFalse(isAllowedCellular(true, true, false, true, true))
        assertFalse(isAllowedCellular(true, false, true, true, true))
        assertFalse(isAllowedCellular(true, false, false, false, true))
        assertFalse(isAllowedCellular(true, false, false, true, false))
    }
}
