package com.echoclip.echoclip

internal data class RecorderLease(val handle: Long, val settings: AudioSettings)

/** One writer per replay cache, shared by capture and exports. */
internal class ReplayRecorderOwner(private val close: (Long) -> Unit) {
    private var current: RecorderLease? = null
    private var users = 0

    @Synchronized
    fun acquire(settings: AudioSettings, create: () -> Long): RecorderLease {
        val existing = current
        if (existing != null) {
            users++
            return existing
        }
        val lease = RecorderLease(create(), settings)
        if (lease.handle != 0L) {
            current = lease
            users = 1
        }
        return lease
    }

    @Synchronized
    fun retain(handle: Long): RecorderLease {
        val lease = current
        check(lease != null && lease.handle == handle) { "recorder_unavailable" }
        users++
        return lease
    }

    @Synchronized
    fun release(handle: Long) {
        if (current?.handle != handle) return
        check(users > 0)
        users--
        if (users == 0) {
            current = null
            close(handle)
        }
    }
}
