import 'dart:async';
import 'dart:typed_data';

import '../config/constants.dart';
import 'gemini_live_service.dart';
import 'volc_live_service.dart';
import 'storage_service.dart';

/// Unified interface for realtime voice services.
/// Wraps GeminiLiveService or VolcLiveService based on the selected provider.
class LiveServiceWrapper {
  final AIProvider provider;
  GeminiLiveService? _gemini;
  VolcLiveService? _volc;

  LiveServiceWrapper(this.provider) {
    switch (provider) {
      case AIProvider.gemini:
        _gemini = GeminiLiveService();
      case AIProvider.volcengine:
        _volc = VolcLiveService();
      case AIProvider.minimax:
        // TODO: implement MiniMax live service
        _gemini = GeminiLiveService(); // fallback
    }
  }

  Stream<GeminiConnectionState> get onStateChanged =>
      _gemini?.onStateChanged ?? _volc!.onStateChanged;

  Stream<Uint8List> get onAudioReceived =>
      _gemini?.onAudioReceived ?? _volc!.onAudioReceived;

  Stream<String> get onTranscriptReceived =>
      _gemini?.onTranscriptReceived ?? _volc!.onTranscriptReceived;

  Stream<String> get onUserTranscriptReceived =>
      _gemini?.onUserTranscriptReceived ?? _volc!.onUserTranscriptReceived;

  GeminiConnectionState get state =>
      _gemini?.state ?? _volc?.state ?? GeminiConnectionState.disconnected;

  bool get isModelSpeaking =>
      _gemini?.isModelSpeaking ?? _volc?.isModelSpeaking ?? false;

  /// Fires when TTS audio generation ends (VolcEngine only).
  /// Note: speaker may still be playing buffered audio for ~1-2s after this.
  Stream<void>? get onTTSEnded => _volc?.onTTSEnded;

  Future<bool> get setupComplete =>
      _gemini?.setupComplete ?? _volc!.setupComplete;

  void configure({
    required StorageService storage,
    String? systemPromptAddition,
  }) {
    if (_gemini != null) {
      _gemini!.configure(
        apiKey: storage.apiKey,
        proxyHost: storage.proxyHost,
        proxyPort: storage.proxyPort,
        proxyEnabled: storage.proxyEnabled,
        voiceName: storage.voiceName,
        systemPromptAddition: systemPromptAddition,
      );
    } else if (_volc != null) {
      _volc!.configure(
        appId: storage.volcAppId,
        accessKey: storage.volcApiKey,
        systemPromptAddition: systemPromptAddition,
      );
    }
  }

  Future<void> connect() => _gemini?.connect() ?? _volc!.connect();

  void sendAudio(Uint8List pcmData) {
    _gemini?.sendAudio(pcmData);
    _volc?.sendAudio(pcmData);
  }

  void sendTextMessage(String text) {
    _gemini?.sendTextMessage(text);
    _volc?.sendTextMessage(text);
  }

  Future<void> disconnect() =>
      _gemini?.disconnect() ?? _volc!.disconnect();

  void dispose() {
    _gemini?.dispose();
    _volc?.dispose();
  }
}
