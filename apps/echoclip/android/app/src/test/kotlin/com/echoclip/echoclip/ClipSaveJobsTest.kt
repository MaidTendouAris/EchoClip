package com.echoclip.echoclip

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import org.junit.Assert.*
import org.junit.Test

class ClipSaveJobsTest {
    private fun job() = SaveJobState(1, 30, "Queued", 0)

    @Test fun cancelBeforeStartPreventsCommit() {
        val state = job()
        assertTrue(state.requestCancel())
        assertFalse(state.finish("content://test/output"))
        assertNull(state.uri)
        state.cancel()
        assertEquals("Canceled", state.toMap()["state"])
        assertFalse(state.requestCancel())
    }

    @Test fun successfulCommitWinsAgainstLateCancel() {
        val state = job()
        assertTrue(state.finish("content://test/output"))
        assertFalse(state.requestCancel())
        assertEquals("Finished", state.state)
        assertFalse(state.cancelRequested)
    }

    @Test fun cancelDuringCopyStopsBeforeWritingTheNextChunk() {
        val state = job()
        val source = ByteArray(700000) { 42 }
        val target = object : ByteArrayOutputStream() {
            override fun write(bytes: ByteArray, offset: Int, count: Int) {
                super.write(bytes, offset, count)
                state.requestCancel()
            }
        }
        assertThrows(InterruptedException::class.java) {
            copyRecording(ByteArrayInputStream(source), target, state)
        }
        assertEquals(256 * 1024, target.size())
        assertEquals(target.size().toLong(), state.copyBytesWritten)
        assertFalse(state.finish("content://test/partial"))
    }

    @Test fun completeCopyReportsRealBytesAndKeepsAudioIntact() {
        val state = job()
        val source = ByteArray(700001) { (it % 128).toByte() }
        state.copyTotalBytes = source.size.toLong()
        val target = ByteArrayOutputStream()
        assertNull(job().toMap()["progress"])
        copyRecording(ByteArrayInputStream(source), target, state)
        assertArrayEquals(source, target.toByteArray())
        assertEquals(1.0, state.toMap()["progress"])
        assertEquals(source.size.toLong(), state.copyBytesWritten)
    }

    @Test fun cancellationAfterFinalWriteStillPreventsCompletion() {
        val state = job()
        val target = object : ByteArrayOutputStream() {
            override fun write(bytes: ByteArray, offset: Int, count: Int) {
                super.write(bytes, offset, count)
                state.requestCancel()
            }
        }
        assertThrows(InterruptedException::class.java) {
            copyRecording(ByteArrayInputStream(byteArrayOf(1, 2)), target, state)
        }
        assertFalse(state.finish("content://test/output"))
    }
}
