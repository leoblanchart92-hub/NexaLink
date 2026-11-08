package com.nexalink.app.network

/** One in-process owner for the single Android VPN slot. Fail closed on uncertainty. */
internal object VpnRoleLease {
    private var holder: Any? = null
    @Synchronized fun acquire(owner: Any): Boolean {
        if (holder != null) return false
        holder = owner
        return true
    }
    @Synchronized fun release(owner: Any) {
        if (holder === owner) holder = null
    }
}
