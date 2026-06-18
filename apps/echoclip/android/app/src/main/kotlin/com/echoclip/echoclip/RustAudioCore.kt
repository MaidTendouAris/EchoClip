package com.echoclip.echoclip

import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.min

object RustAudioCore {
    private val nextHandle = AtomicLong(1)
    private val fallbackBuffers = ConcurrentHashMap<Long, FallbackRingBuffer>()
    private val nativeAvailable: Boolean = runCatching {
        System.loadLibrary("echoclip_android_jni")
    }.isSuccess

    fun backendName(): String = if (nativeAvailable) {
        "rust+jni"
    } else {
        "kotlin-fallback"
    }

    fun create(sampleRate: Int, channels: Int, capacitySeconds: Int): Long {
        fun createFallback(handle: Long): Long {
            fallbackBuffers[handle] = FallbackRingBuffer(
                sampleRate = sampleRate,
                channels = channels,
                capacitySeconds = capacitySeconds,
            )
            return handle
        }

        if (nativeAvailable) {
            runCatching {
                val handle = nativeCreate(sampleRate, channels, capacitySeconds)
                if (handle != 0L) {
                    return createFallback(handle)
                }
            }
        }

        val handle = nextHandle.getAndIncrement()
        return createFallback(handle)
    }

    fun destroy(handle: Long) {
        if (nativeAvailable) {
            runCatching { nativeDestroy(handle) }
        }
        fallbackBuffers.remove(handle)
    }

    fun push(handle: Long, samples: ShortArray, count: Int) {
        if (nativeAvailable) {
            runCatching {
                nativePush(handle, samples, count)
            }
        }
        fallbackBuffers[handle]?.push(samples, count)
    }

    fun availableSeconds(handle: Long): Int {
        if (nativeAvailable) {
            runCatching {
                val available = nativeAvailableSeconds(handle)
                if (available > 0) {
                    return available
                }
            }
        }
        return fallbackBuffers[handle]?.availableSeconds() ?: 0
    }

    fun latest(handle: Long, seconds: Int): ShortArray {
        if (nativeAvailable) {
            runCatching {
                val samples = nativeLatest(handle, seconds)
                if (samples.isNotEmpty()) {
                    return samples
                }
            }
        }
        return fallbackBuffers[handle]?.latest(seconds) ?: ShortArray(0)
    }

    private external fun nativeCreate(sampleRate: Int, channels: Int, capacitySeconds: Int): Long
    private external fun nativeDestroy(handle: Long)
    private external fun nativePush(handle: Long, samples: ShortArray, count: Int)
    private external fun nativeAvailableSeconds(handle: Long): Int
    private external fun nativeLatest(handle: Long, seconds: Int): ShortArray
}

private class FallbackRingBuffer(
    private val sampleRate: Int,
    channels: Int,
    capacitySeconds: Int,
) {
    private val lock = Any()
    private val samples = ShortArray(sampleRate * channels * capacitySeconds)
    private var writePosition = 0
    private var availableSamples = 0

    fun push(input: ShortArray, count: Int) {
        synchronized(lock) {
            for (index in 0 until min(count, input.size)) {
                samples[writePosition] = input[index]
                writePosition = (writePosition + 1) % samples.size
                availableSamples = min(availableSamples + 1, samples.size)
            }
        }
    }

    fun availableSeconds(): Int {
        synchronized(lock) {
            return availableSamples / sampleRate
        }
    }

    fun latest(seconds: Int): ShortArray {
        synchronized(lock) {
            val count = min(seconds * sampleRate, availableSamples)
            val output = ShortArray(count)
            val start = (writePosition + samples.size - count) % samples.size
            for (index in 0 until count) {
                output[index] = samples[(start + index) % samples.size]
            }
            return output
        }
    }
}
