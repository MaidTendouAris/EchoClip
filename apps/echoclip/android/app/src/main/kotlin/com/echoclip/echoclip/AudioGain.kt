package com.echoclip.echoclip

internal object AudioGain {
    fun apply(samples: ShortArray, count: Int, percent: Int) {
        val gain = percent.coerceIn(0, 300)
        if (gain == 100) return
        for (index in 0 until count) samples[index] = (samples[index].toInt() * gain / 100)
            .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
    }
}
