package com.echoclip.echoclip

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.junit.After
import org.junit.Assert.*
import org.junit.Test

/** Tests the real service's lifecycle methods without microphone hardware/JNI. */
class RecordingModeLifecycleTest {
    @After
    fun resetService() {
        ReplayForegroundService.isRunning = false
        ReplayForegroundService.activeService = null
    }

    @Test
    fun stopDisarmsWaitingLockRecordingAndIgnoresLaterScreenOff() {
        val service = lockService("armed")
        val result = service.stopManualCapture()
        assertEquals(true, result["stopped"])
        assertStopped(result, serviceActive = false)
        assertNull(field(service, "screenReceiver"))
        ReplayForegroundService::class.java.getDeclaredMethod("handleScreenOff").apply {
            isAccessible = true
            invoke(service)
        }
        assertStopped(service.recordingControlStatus(), serviceActive = false)
        assertEquals(false, service.stopManualCapture()["stopped"])
    }

    @Test
    fun stopDisarmsActiveLockRecording() {
        val service = lockService("recording")
        ReplayForegroundService.isRunning = true
        val result = service.stopManualCapture()
        assertEquals(true, result["stopped"])
        assertStopped(result, serviceActive = false)
        assertNull(field(service, "screenReceiver"))
    }

    @Test
    fun stoppingLockModePreservesSchedulerWithoutLeavingLockModeArmed() {
        val service = lockService("armed")
        setField(service, "schedulerArmed", true)
        val result = service.stopManualCapture()
        assertStopped(result, serviceActive = true)
        assertEquals(true, result["schedulerArmed"])
        service.setSchedulerArmed(false)
        assertStopped(service.recordingControlStatus(), serviceActive = false)
    }

    @Test
    fun switchingToStandardDisarmsLockListenerAndReturnsTheNewMode() {
        for (state in listOf("armed", "recording")) {
            val service = lockService(state)
            ReplayForegroundService.isRunning = state == "recording"
            setField(service, "schedulerArmed", true)
            val result = service.applyRecordingMode(RecordingModeSettings("standard", "screen_off"))
            assertEquals("standard", result["recordingMode"])
            assertEquals("standard_paused", result["serviceState"])
            assertStopped(result, serviceActive = true)
            assertNull(field(service, "screenReceiver"))
        }
    }

    @Test
    fun switchingFromStandardRequiresExplicitStartInTheNewMode() {
        val service = ReplayForegroundService()
        ReplayForegroundService.isRunning = true
        val result = service.applyRecordingMode(RecordingModeSettings("lockscreen", "screen_off"))
        assertEquals("lockscreen", result["recordingMode"])
        assertStopped(result, serviceActive = false)
    }

    @Test
    fun triggerChangesDoNotStartSchedulerOnlyService() {
        val service = lockService("armed")
        setField(service, "schedulerArmed", true)
        service.stopManualCapture()
        val result = service.applyRecordingMode(RecordingModeSettings("lockscreen", "keyguard_locked"))
        assertEquals("keyguard_locked", result["lockRecordingTrigger"])
        assertStopped(result, serviceActive = true)
        assertNull(field(service, "screenReceiver"))
    }

    private fun assertStopped(result: Map<String, Any?>, serviceActive: Boolean) {
        assertEquals(false, result["running"])
        assertEquals(serviceActive, result["serviceActive"])
        assertEquals("off", result["evidenceState"])
        assertNull(result["evidenceLastStopReason"])
    }

    private fun lockService(state: String): ReplayForegroundService {
        val service = ReplayForegroundService()
        setField(service, "recordingMode", "lockscreen")
        setField(service, "evidenceState", state)
        setField(service, "evidenceLastStopReason", "screen_on")
        setField(service, "screenReceiver", object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {}
        })
        return service
    }

    private fun setField(service: ReplayForegroundService, name: String, value: Any) {
        ReplayForegroundService::class.java.getDeclaredField(name).apply {
            isAccessible = true
            set(service, value)
        }
    }

    private fun field(service: ReplayForegroundService, name: String): Any? =
        ReplayForegroundService::class.java.getDeclaredField(name).run {
            isAccessible = true
            get(service)
        }
}
