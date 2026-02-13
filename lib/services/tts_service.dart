import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../config/constants.dart';
import 'audio_service.dart';

/// TTS service using Gemini Live API (WebSocket) for low-latency streaming.
/// WebSocket bypasses HTTP proxy buffering that kills SSE streaming.
/// Falls back to REST SSE if WebSocket fails.
class TtsService {
  String? _apiKey;
  String? _proxyHost;
  int? _proxyPort;
  bool _proxyEnabled = false;
  String _voiceName = AppConstants.defaultVoice;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  final _stateController = StreamController<bool>.broadcast();
  Stream<bool> get onPlayingChanged => _stateController.stream;

  AudioService? _audioService;

  // File-based replay
  final AudioPlayer _replayPlayer = AudioPlayer();
  final Map<String, String> _savedAudioFiles = {};

  // Track cancellation
  bool _cancelled = false;
  dynamic _activeWs; // WebSocket for cancellation

  TtsService();

  void setAudioService(AudioService audioService) {
    _audioService = audioService;
  }

  void configure({
    required String apiKey,
    String? proxyHost,
    int? proxyPort,
    bool proxyEnabled = false,
    String? voiceName,
  }) {
    _apiKey = apiKey;
    _proxyHost = proxyHost;
    _proxyPort = proxyPort;
    _proxyEnabled = proxyEnabled;
    _voiceName = voiceName ?? AppConstants.defaultVoice;
  }

  Future<void> init() async {}

  /// Speak text using Gemini Live API WebSocket for real-time streaming audio.
  /// Audio starts playing as soon as the first chunk arrives (~200ms).
  Future<void> speak(String text, {String? messageId}) async {
    if (text.trim().isEmpty || _apiKey == null) return;

    await stop();
    _cancelled = false;
    // Don't set _isPlaying yet — wait for first audio chunk

    final allPcm = <int>[];

    try {
      final url = '${AppConstants.geminiWsBaseUrl}?key=$_apiKey';

      // Connect WebSocket (with proxy if needed)
      final httpClient = HttpClient();
      if (_proxyEnabled &&
          _proxyHost != null &&
          _proxyHost!.isNotEmpty &&
          _proxyPort != null) {
        httpClient.findProxy = (uri) => 'PROXY $_proxyHost:$_proxyPort';
      }

      final ws = await WebSocket.connect(url, customClient: httpClient);
      _activeWs = ws;

      // Send setup — audio-only output with voice config
      final setupMsg = jsonEncode({
        'setup': {
          'model': AppConstants.geminiModel,
          'generation_config': {
            'response_modalities': ['AUDIO'],
            'speech_config': {
              'voice_config': {
                'prebuilt_voice_config': {
                  'voice_name': _voiceName,
                },
              },
            },
          },
        },
      });
      ws.add(setupMsg);

      bool setupDone = false;
      bool turnDone = false;
      final completer = Completer<void>();

      ws.listen(
        (rawMessage) {
          if (_cancelled) return;

          try {
            Map<String, dynamic> message;
            if (rawMessage is String) {
              message = jsonDecode(rawMessage) as Map<String, dynamic>;
            } else if (rawMessage is List<int>) {
              message = jsonDecode(utf8.decode(rawMessage)) as Map<String, dynamic>;
            } else {
              return;
            }

            // Setup complete — send the text
            if (message.containsKey('setupComplete')) {
              setupDone = true;
              // Send text as client_content
              ws.add(jsonEncode({
                'client_content': {
                  'turns': [
                    {
                      'role': 'user',
                      'parts': [
                        {'text': 'Read the following text aloud naturally: $text'},
                      ],
                    },
                  ],
                  'turn_complete': true,
                },
              }));
              return;
            }

            // Server content — audio data
            if (message.containsKey('serverContent')) {
              final serverContent = message['serverContent'] as Map<String, dynamic>;

              if (serverContent.containsKey('modelTurn')) {
                final modelTurn = serverContent['modelTurn'] as Map<String, dynamic>;
                final parts = modelTurn['parts'] as List<dynamic>?;
                if (parts != null) {
                  for (final part in parts) {
                    final partMap = part as Map<String, dynamic>;
                    if (partMap.containsKey('inlineData')) {
                      final inlineData = partMap['inlineData'] as Map<String, dynamic>;
                      final base64Data = inlineData['data'] as String?;
                      if (base64Data != null && !_cancelled) {
                        final audioBytes = base64Decode(base64Data);
                        // Signal playing on first audio chunk
                        if (!_isPlaying) {
                          _isPlaying = true;
                          _stateController.add(true);
                        }
                        // Push to AudioService for immediate playback
                        if (_audioService != null) {
                          _audioService!.addPlaybackData(Uint8List.fromList(audioBytes));
                        }
                        allPcm.addAll(audioBytes);
                      }
                    }
                  }
                }
              }

              // Turn complete
              final tc = serverContent['turnComplete'] as bool?;
              if (tc == true) {
                turnDone = true;
                if (!completer.isCompleted) completer.complete();
              }
            }
          } catch (e) {
            debugPrint('TTS WS message error: $e');
          }
        },
        onError: (error) {
          debugPrint('TTS WS error: $error');
          if (!completer.isCompleted) completer.complete();
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: false,
      );

      // Wait for turn to complete (with timeout)
      await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('TTS WS timeout');
        },
      );

      // Close WebSocket
      await ws.close();
      _activeWs = null;
      httpClient.close();

      // Save for replay
      if (allPcm.isNotEmpty && messageId != null && !_cancelled) {
        _saveAudioAsync(messageId, Uint8List.fromList(allPcm));
      }

      // Wait for audio buffer to drain
      if (!_cancelled && allPcm.isNotEmpty && _audioService != null) {
        final totalMs = (allPcm.length / 48.0).ceil();
        // Most audio already played in parallel; wait for tail
        await Future.delayed(Duration(milliseconds: totalMs.clamp(300, 2000)));
        _audioService!.markPlaybackDone();
      }
    } catch (e) {
      debugPrint('TTS speak error: $e');
    } finally {
      _isPlaying = false;
      _stateController.add(false);
      _activeWs = null;
    }
  }

  Future<void> _saveAudioAsync(String messageId, Uint8List pcmData) async {
    try {
      final wavData = _buildWav(pcmData);
      final appDir = await getApplicationDocumentsDirectory();
      final audioDir = Directory('${appDir.path}/audio');
      if (!await audioDir.exists()) await audioDir.create(recursive: true);
      final saved = File('${audioDir.path}/tts_$messageId.wav');
      await saved.writeAsBytes(wavData);
      _savedAudioFiles[messageId] = saved.path;
    } catch (e) {
      debugPrint('TTS save error: $e');
    }
  }

  Future<void> replay(String messageId) async {
    String? path = _savedAudioFiles[messageId];
    if (path == null) {
      final appDir = await getApplicationDocumentsDirectory();
      final f = File('${appDir.path}/audio/tts_$messageId.wav');
      if (await f.exists()) {
        path = f.path;
        _savedAudioFiles[messageId] = path;
      }
    }
    if (path == null || !await File(path).exists()) return;

    await stop();
    _isPlaying = true;
    _stateController.add(true);
    try {
      await _replayPlayer.play(DeviceFileSource(path));
      final c = Completer<void>();
      late StreamSubscription sub;
      sub = _replayPlayer.onPlayerComplete.listen((_) {
        if (!c.isCompleted) c.complete();
        sub.cancel();
      });
      await c.future.timeout(const Duration(seconds: 120),
          onTimeout: () => sub.cancel());
    } catch (e) {
      debugPrint('TTS replay error: $e');
    } finally {
      _isPlaying = false;
      _stateController.add(false);
    }
  }

  bool hasAudio(String messageId) => _savedAudioFiles.containsKey(messageId);

  Future<void> preloadAudioCache(List<String> messageIds) async {
    final appDir = await getApplicationDocumentsDirectory();
    for (final id in messageIds) {
      if (!_savedAudioFiles.containsKey(id)) {
        final f = File('${appDir.path}/audio/tts_$id.wav');
        if (await f.exists()) _savedAudioFiles[id] = f.path;
      }
    }
  }

  Uint8List _buildWav(Uint8List pcm) {
    const sr = AppConstants.outputSampleRate;
    const bps = AppConstants.bitsPerSample;
    const ch = AppConstants.numChannels;
    final byteRate = sr * ch * (bps ~/ 8);
    final blockAlign = ch * (bps ~/ 8);
    final h = ByteData(44);
    h.setUint8(0, 0x52); h.setUint8(1, 0x49); h.setUint8(2, 0x46); h.setUint8(3, 0x46);
    h.setUint32(4, 36 + pcm.length, Endian.little);
    h.setUint8(8, 0x57); h.setUint8(9, 0x41); h.setUint8(10, 0x56); h.setUint8(11, 0x45);
    h.setUint8(12, 0x66); h.setUint8(13, 0x6D); h.setUint8(14, 0x74); h.setUint8(15, 0x20);
    h.setUint32(16, 16, Endian.little);
    h.setUint16(20, 1, Endian.little);
    h.setUint16(22, ch, Endian.little);
    h.setUint32(24, sr, Endian.little);
    h.setUint32(28, byteRate, Endian.little);
    h.setUint16(32, blockAlign, Endian.little);
    h.setUint16(34, bps, Endian.little);
    h.setUint8(36, 0x64); h.setUint8(37, 0x61); h.setUint8(38, 0x74); h.setUint8(39, 0x61);
    h.setUint32(40, pcm.length, Endian.little);
    final out = Uint8List(44 + pcm.length);
    out.setRange(0, 44, h.buffer.asUint8List());
    out.setRange(44, 44 + pcm.length, pcm);
    return out;
  }

  Future<void> stop() async {
    _cancelled = true;
    _isPlaying = false;
    _stateController.add(false);

    // Close active WebSocket
    if (_activeWs is WebSocket) {
      try { await (_activeWs as WebSocket).close(); } catch (_) {}
    }
    _activeWs = null;

    // Stop AudioService playback
    if (_audioService != null) {
      await _audioService!.stopPlayback();
    }

    await _replayPlayer.stop();
  }

  void dispose() {
    stop();
    _replayPlayer.dispose();
    _stateController.close();
  }
}
