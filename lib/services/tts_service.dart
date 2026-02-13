import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../config/constants.dart';

/// TTS service using Gemini TTS REST API (streamGenerateContent SSE).
/// Collects all audio chunks, writes WAV, plays via audioplayers.
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

  final AudioPlayer _player = AudioPlayer();
  final Map<String, String> _savedAudioFiles = {};

  TtsService();

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

  /// Speak text: call TTS API, collect PCM, write WAV, play
  Future<void> speak(String text, {String? messageId}) async {
    if (text.trim().isEmpty || _apiKey == null) return;

    await stop();
    _isPlaying = true;
    _stateController.add(true);

    try {
      final pcmData = await _fetchAudio(text);
      if (pcmData == null || pcmData.isEmpty) {
        debugPrint('TTS: no audio returned');
        return;
      }

      // Write WAV
      final wavData = _buildWav(pcmData);
      final tmpDir = await getTemporaryDirectory();
      final wavFile = File(
          '${tmpDir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.wav');
      await wavFile.writeAsBytes(wavData);

      // Save for replay
      if (messageId != null) {
        final appDir = await getApplicationDocumentsDirectory();
        final audioDir = Directory('${appDir.path}/audio');
        if (!await audioDir.exists()) await audioDir.create(recursive: true);
        final saved = File('${audioDir.path}/tts_$messageId.wav');
        await saved.writeAsBytes(wavData);
        _savedAudioFiles[messageId] = saved.path;
      }

      // Play
      await _player.play(DeviceFileSource(wavFile.path));

      // Wait for playback to finish
      final c = Completer<void>();
      late StreamSubscription sub;
      sub = _player.onPlayerComplete.listen((_) {
        if (!c.isCompleted) c.complete();
        sub.cancel();
      });
      await c.future.timeout(const Duration(seconds: 120),
          onTimeout: () => sub.cancel());

      // Cleanup temp
      try {
        await wavFile.delete();
      } catch (_) {}
    } catch (e) {
      debugPrint('TTS error: $e');
    } finally {
      _isPlaying = false;
      _stateController.add(false);
    }
  }

  /// Fetch audio PCM from Gemini TTS streaming API
  Future<Uint8List?> _fetchAudio(String text) async {
    final url =
        'https://generativelanguage.googleapis.com/v1beta/models/'
        'gemini-2.5-flash-preview-tts:streamGenerateContent?alt=sse&key=$_apiKey';

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': text}
          ]
        }
      ],
      'generationConfig': {
        'response_modalities': ['AUDIO'],
        'speech_config': {
          'voice_config': {
            'prebuilt_voice_config': {'voice_name': _voiceName}
          }
        }
      }
    });

    final httpClient = HttpClient();
    if (_proxyEnabled &&
        _proxyHost != null &&
        _proxyHost!.isNotEmpty &&
        _proxyPort != null) {
      httpClient.findProxy = (uri) => 'PROXY $_proxyHost:$_proxyPort';
    }

    try {
      final request = await httpClient.postUrl(Uri.parse(url));
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.add(utf8.encode(body));
      final response = await request.close();

      if (response.statusCode != 200) {
        final err = await response.transform(utf8.decoder).join();
        debugPrint('TTS API ${response.statusCode}: ${err.substring(0, err.length.clamp(0, 200))}');
        return null;
      }

      // Parse SSE and collect PCM
      final allPcm = <int>[];
      String buffer = '';
      await for (final chunk in response.transform(utf8.decoder)) {
        buffer += chunk;
        while (true) {
          int idx = buffer.indexOf('\n\n');
          if (idx == -1) idx = buffer.indexOf('\r\n\r\n');
          if (idx == -1) break;
          final segment = buffer.substring(0, idx).trim();
          buffer = buffer.substring(idx + (buffer[idx] == '\r' ? 4 : 2));

          String? dataPayload;
          for (final line in segment.split(RegExp(r'\r?\n'))) {
            if (line.startsWith('data: ')) {
              dataPayload = (dataPayload ?? '') + line.substring(6);
            }
          }
          if (dataPayload == null) continue;

          try {
            final json = jsonDecode(dataPayload) as Map<String, dynamic>;
            final parts = json['candidates']?[0]?['content']?['parts'] as List?;
            if (parts == null) continue;
            for (final part in parts) {
              final b64 = part['inlineData']?['data'] as String?;
              if (b64 != null && b64.isNotEmpty) {
                allPcm.addAll(base64Decode(b64));
              }
            }
          } catch (_) {}
        }
      }
      return allPcm.isEmpty ? null : Uint8List.fromList(allPcm);
    } finally {
      httpClient.close();
    }
  }

  /// Replay saved audio
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

    _isPlaying = true;
    _stateController.add(true);
    try {
      await _player.play(DeviceFileSource(path));
      final c = Completer<void>();
      late StreamSubscription sub;
      sub = _player.onPlayerComplete.listen((_) {
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
    // RIFF
    h.setUint8(0, 0x52); h.setUint8(1, 0x49); h.setUint8(2, 0x46); h.setUint8(3, 0x46);
    h.setUint32(4, 36 + pcm.length, Endian.little);
    // WAVE
    h.setUint8(8, 0x57); h.setUint8(9, 0x41); h.setUint8(10, 0x56); h.setUint8(11, 0x45);
    // fmt
    h.setUint8(12, 0x66); h.setUint8(13, 0x6D); h.setUint8(14, 0x74); h.setUint8(15, 0x20);
    h.setUint32(16, 16, Endian.little);
    h.setUint16(20, 1, Endian.little);
    h.setUint16(22, ch, Endian.little);
    h.setUint32(24, sr, Endian.little);
    h.setUint32(28, byteRate, Endian.little);
    h.setUint16(32, blockAlign, Endian.little);
    h.setUint16(34, bps, Endian.little);
    // data
    h.setUint8(36, 0x64); h.setUint8(37, 0x61); h.setUint8(38, 0x74); h.setUint8(39, 0x61);
    h.setUint32(40, pcm.length, Endian.little);
    final out = Uint8List(44 + pcm.length);
    out.setRange(0, 44, h.buffer.asUint8List());
    out.setRange(44, 44 + pcm.length, pcm);
    return out;
  }

  Future<void> stop() async {
    _isPlaying = false;
    _stateController.add(false);
    await _player.stop();
  }

  void dispose() {
    stop();
    _player.dispose();
    _stateController.close();
  }
}
