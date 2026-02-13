package com.speakmate.speakmate

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.util.concurrent.ConcurrentLinkedQueue

/**
 * Native PCM audio player using Android AudioTrack.
 *
 * Uses USAGE_VOICE_COMMUNICATION so the system AEC (AcousticEchoCanceler
 * bound to AudioRecord with VOICE_COMMUNICATION source) can correctly
 * reference the playback signal and cancel echo.
 */
class NativeAudioPlayer : MethodChannel.MethodCallHandler {
    companion object {
        private const val TAG = "NativeAudioPlayer"
    }

    private var audioTrack: AudioTrack? = null
    private var sampleRate: Int = 24000
    private var channels: Int = 1
    private var isInitialized = false

    // Background writer coroutine
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val pcmQueue = ConcurrentLinkedQueue<ByteArray>()
    private var writerJob: Job? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> {
                sampleRate = call.argument<Int>("sampleRate") ?: 24000
                channels = call.argument<Int>("channels") ?: 1
                init()
                result.success(null)
            }
            "push" -> {
                val data = call.argument<ByteArray>("data")
                if (data != null) {
                    push(data)
                }
                result.success(null)
            }
            "stop" -> {
                stop()
                result.success(null)
            }
            "dispose" -> {
                dispose()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun init() {
        stop() // Clean up previous instance

        val channelConfig = if (channels == 1)
            AudioFormat.CHANNEL_OUT_MONO else AudioFormat.CHANNEL_OUT_STEREO

        val minBufferSize = AudioTrack.getMinBufferSize(
            sampleRate,
            channelConfig,
            AudioFormat.ENCODING_PCM_16BIT
        )

        // Use a larger buffer for smooth playback (4x min)
        val bufferSize = minBufferSize * 4

        audioTrack = AudioTrack(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build(),
            AudioFormat.Builder()
                .setSampleRate(sampleRate)
                .setChannelMask(channelConfig)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .build(),
            bufferSize,
            AudioTrack.MODE_STREAM,
            AudioManager.AUDIO_SESSION_ID_GENERATE
        )

        if (audioTrack?.state != AudioTrack.STATE_INITIALIZED) {
            Log.e(TAG, "AudioTrack initialization failed")
            audioTrack = null
            return
        }

        audioTrack?.play()
        isInitialized = true

        // Start background writer
        writerJob = scope.launch {
            while (isActive) {
                val data = pcmQueue.poll()
                if (data != null) {
                    audioTrack?.write(data, 0, data.size)
                } else {
                    delay(5) // Small sleep to avoid busy loop
                }
            }
        }

        Log.d(TAG, "Initialized: sampleRate=$sampleRate, channels=$channels, bufferSize=$bufferSize")
    }

    private fun push(pcmData: ByteArray) {
        if (!isInitialized || audioTrack == null) return
        pcmQueue.add(pcmData)
    }

    private fun stop() {
        writerJob?.cancel()
        writerJob = null
        pcmQueue.clear()

        audioTrack?.let { track ->
            try {
                if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                    track.pause()
                    track.flush()
                }
                track.stop()
                track.release()
            } catch (e: Exception) {
                Log.e(TAG, "Error stopping AudioTrack: ${e.message}")
            }
        }
        audioTrack = null
        isInitialized = false
    }

    fun dispose() {
        stop()
        scope.cancel()
    }
}
