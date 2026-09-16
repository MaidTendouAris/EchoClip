package com.echoclip.echoclip
import org.junit.Assert.assertArrayEquals
import org.junit.Test

class AudioGainTest {
    @Test fun muteUnityBoostAndSaturation() {
        val values = shortArrayOf(1000, -20000, 20000, 123)
        AudioGain.apply(values, 3, 300)
        assertArrayEquals(shortArrayOf(3000, Short.MIN_VALUE, Short.MAX_VALUE, 123), values)
        AudioGain.apply(values, 4, 100)
        assertArrayEquals(shortArrayOf(3000, Short.MIN_VALUE, Short.MAX_VALUE, 123), values)
        AudioGain.apply(values, 4, 0)
        assertArrayEquals(shortArrayOf(0, 0, 0, 0), values)
    }
}
