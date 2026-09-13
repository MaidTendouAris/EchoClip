package com.echoclip.echoclip

import org.junit.Assert.*
import org.junit.Test

class AudioMeterCalibrationTest {
    @Test
    fun halfScaleSignalKeepsItsLinearRmsAndPeak() {
        val service = ReplayForegroundService()
        feed(service, ShortArray(800) { 16384 })
        val meter = service.meterStatus()
        assertEquals(0.5, (meter["level"] as Number).toDouble(), 0.00001)
        assertEquals(0.5, (meter["peakLevel"] as Number).toDouble(), 0.00001)
    }

    @Test
    fun sparseTransientHasIndependentRmsAndPeakAndSilenceResetsBoth() {
        val service = ReplayForegroundService()
        feed(service, ShortArray(800) { if (it % 2 == 0) 16384 else 0 })
        val meter = service.meterStatus()
        assertEquals(kotlin.math.sqrt(0.125), (meter["level"] as Number).toDouble(), 0.00001)
        assertEquals(0.5, (meter["peakLevel"] as Number).toDouble(), 0.00001)
        feed(service, ShortArray(800))
        val silence = service.meterStatus()
        assertEquals(0.0, (silence["level"] as Number).toDouble(), 0.00001)
        assertEquals(0.0, (silence["peakLevel"] as Number).toDouble(), 0.00001)
    }

    @Test
    fun negativePcmEndpointDoesNotExceedFullScale() {
        val service = ReplayForegroundService()
        feed(service, ShortArray(800) { Short.MIN_VALUE })
        val meter = service.meterStatus()
        assertEquals(1.0, (meter["level"] as Number).toDouble(), 0.00001)
        assertEquals(1.0, (meter["peakLevel"] as Number).toDouble(), 0.00001)
    }

    private fun feed(service: ReplayForegroundService, samples: ShortArray) {
        ReplayForegroundService::class.java.getDeclaredMethod(
            "updateLevels", ShortArray::class.java, Int::class.javaPrimitiveType,
        ).apply {
            isAccessible = true
            invoke(service, samples, samples.size)
        }
    }
}
