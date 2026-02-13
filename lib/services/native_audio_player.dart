import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Native PCM audio player that uses Android AudioTrack with
/// USAGE_VOICE_COMMUNICATION, enabling system AEC to work correctly
/// when recording and playing back simultaneously.
class NativeAudioPlayer {
  static const _channel = MethodChannel('com.speakmate/native_audio_player');

  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// Initialize the native audio player.
  /// Must be called before [push].
  Future<void> init({
    int sampleRate = 24000,
    int channels = 1,
  }) async {
    await _channel.invokeMethod('init', {
      'sampleRate': sampleRate,
      'channels': channels,
    });
    _initialized = true;
  }

  /// Push PCM 16-bit data for playback.
  /// Data is queued and played back in order.
  Future<void> push(Uint8List pcmData) async {
    if (!_initialized) return;
    await _channel.invokeMethod('push', {
      'data': pcmData,
    });
  }

  /// Stop playback and clear all buffered audio.
  Future<void> stop() async {
    await _channel.invokeMethod('stop');
    _initialized = false;
  }

  /// Release all resources.
  Future<void> dispose() async {
    await _channel.invokeMethod('dispose');
    _initialized = false;
  }
}
