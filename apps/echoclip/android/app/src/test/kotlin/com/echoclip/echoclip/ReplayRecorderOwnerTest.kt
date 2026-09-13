package com.echoclip.echoclip

import org.junit.Assert.*
import org.junit.Test

class ReplayRecorderOwnerTest {
    private val settings = AudioSettings(16000, 1800)

    @Test fun offlineSaveAndCaptureShareOneWriterUntilBothFinish() {
        val closed = mutableListOf<Long>()
        val owner = ReplayRecorderOwner { closed.add(it) }
        val saving = owner.acquire(settings) { 1L }
        val capture = owner.acquire(AudioSettings(48000, 3600)) {
            fail("must reuse the cache writer while saving"); 2L
        }
        assertEquals(saving, capture)
        assertEquals(settings, capture.settings)
        owner.release(saving.handle)
        assertTrue(closed.isEmpty())
        owner.release(capture.handle)
        assertEquals(listOf(1L), closed)
        val next = owner.acquire(AudioSettings(48000, 3600)) { 2L }
        assertEquals(48000, next.settings.sampleRate)
        assertEquals(2L, next.handle)
    }

    @Test fun stoppingCaptureKeepsQueuedExportAndItsCancellationHandleAlive() {
        val closed = mutableListOf<Long>()
        val owner = ReplayRecorderOwner { closed.add(it) }
        val capture = owner.acquire(settings) { 4L }
        val queuedSave = owner.retain(capture.handle)
        owner.release(capture.handle)
        assertTrue(closed.isEmpty())
        assertEquals(4L, queuedSave.handle)
        owner.release(queuedSave.handle)
        assertEquals(listOf(4L), closed)
        owner.release(queuedSave.handle)
        assertEquals(1, closed.size)
    }

    @Test fun failedCreationDoesNotLeaveAReferenceOrBlockRetry() {
        var closed = false
        val owner = ReplayRecorderOwner { closed = true }
        assertEquals(0L, owner.acquire(settings) { 0L }.handle)
        owner.release(0L)
        assertFalse(closed)
        assertEquals(5L, owner.acquire(settings) { 5L }.handle)
        owner.release(5L)
        assertTrue(closed)
    }
}
