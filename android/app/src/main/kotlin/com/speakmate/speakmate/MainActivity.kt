package com.speakmate.speakmate

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val nativeAudioPlayer = NativeAudioPlayer()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.speakmate/native_audio_player"
        ).setMethodCallHandler(nativeAudioPlayer)
    }

    override fun onDestroy() {
        nativeAudioPlayer.dispose()
        super.onDestroy()
    }
}
