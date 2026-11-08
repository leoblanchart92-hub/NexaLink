package com.nexalink.app.network

/**
 * Each native Go .so embeds a runtime. Loading both runtimes in one Android
 * process has not been established safe. The reservation is intentionally
 * irreversible: stopping a tunnel does not unload a Go runtime.
 */
internal object NativeRuntimeGuard {
    enum class Kind { OWNER, GUEST }
    private var loaded: Kind? = null
    @Synchronized fun reserve(kind: Kind): Boolean {
        if (loaded != null && loaded != kind) return false
        loaded = kind
        return true
    }
}
