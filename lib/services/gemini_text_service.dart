import 'dart:async';
import 'dart:convert';
import 'dart:io' if (dart.library.html) 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/constants.dart';
import '../models/message.dart';

/// Standard mode: Text-based Gemini API with persistent conversation history.
/// Unlike Live API, this maintains full conversation context across the session.
class GeminiTextService {
  String? _apiKey;
  String? _proxyHost;
  int? _proxyPort;
  bool _proxyEnabled = true;
  String _systemPrompt = AppConstants.systemPrompt;

  // Full conversation history (persists as long as the service lives)
  final List<Map<String, dynamic>> _history = [];

  bool _isGenerating = false;
  bool get isGenerating => _isGenerating;

  final _responseController = StreamController<String>.broadcast();
  Stream<String> get onResponse => _responseController.stream;

  void configure({
    required String apiKey,
    String? proxyHost,
    int? proxyPort,
    bool proxyEnabled = true,
    String? systemPromptAddition,
  }) {
    _apiKey = apiKey;
    _proxyHost = proxyHost;
    _proxyPort = proxyPort;
    _proxyEnabled = proxyEnabled;
    if (systemPromptAddition != null && systemPromptAddition.isNotEmpty) {
      _systemPrompt =
          '${AppConstants.systemPromptStandard}\n\n$systemPromptAddition';
    } else {
      _systemPrompt = AppConstants.systemPromptStandard;
    }
  }

  /// Restore conversation history from saved messages
  void restoreHistory(List<Message> messages) {
    _history.clear();
    for (final msg in messages) {
      _history.add({
        'role': msg.role == MessageRole.user ? 'user' : 'model',
        'parts': [{'text': msg.text}],
      });
    }
  }

  /// Send a text message and get a streaming response
  Future<String> sendMessage(String text) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw Exception('API key not configured');
    }

    _isGenerating = true;

    // Add user message to history
    _history.add({
      'role': 'user',
      'parts': [{'text': text}],
    });

    try {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/'
        '${AppConstants.geminiTextModel}:generateContent?key=$_apiKey',
      );

      final body = jsonEncode({
        'contents': _history,
        'system_instruction': {
          'parts': [{'text': _systemPrompt}],
        },
        'generation_config': {
          'temperature': 0.8,
          'max_output_tokens': 500,
        },
      });

      http.Response response;

      if (!kIsWeb && _proxyEnabled && _proxyHost != null && _proxyPort != null) {
        // Use dart:io HttpClient for proxy support on native
        final httpClient = HttpClient();
        httpClient.findProxy = (uri) => 'PROXY $_proxyHost:$_proxyPort';

        final request = await httpClient.postUrl(url);
        request.headers.contentType = ContentType.json;
        request.write(body);
        final ioResponse = await request.close();
        final responseBody = await ioResponse.transform(utf8.decoder).join();
        response = http.Response(responseBody, ioResponse.statusCode);
        httpClient.close();
      } else {
        // Direct request (web or no proxy)
        response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: body,
        );
      }

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body);
        final errorMsg = error['error']?['message'] ?? 'Unknown error';
        throw Exception('API error ${response.statusCode}: $errorMsg');
      }

      final data = jsonDecode(response.body);
      final candidates = data['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        throw Exception('No response from model');
      }

      final parts = candidates[0]['content']['parts'] as List;
      final responseText = parts.map((p) => p['text'] as String).join();

      // Add model response to history
      _history.add({
        'role': 'model',
        'parts': [{'text': responseText}],
      });

      _responseController.add(responseText);
      _isGenerating = false;
      return responseText;
    } catch (e) {
      _isGenerating = false;
      // Remove the failed user message from history
      if (_history.isNotEmpty && _history.last['role'] == 'user') {
        _history.removeLast();
      }
      rethrow;
    }
  }

  /// Send an audio message (PCM 16-bit, 16kHz mono) and get a text response.
  /// Gemini processes the audio as multimodal input and responds in text.
  Future<String> sendAudioMessage(Uint8List pcmData) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw Exception('API key not configured');
    }

    _isGenerating = true;

    // Convert PCM to WAV for proper MIME type
    final wavData = _buildWav(pcmData);
    final base64Audio = base64Encode(wavData);

    // Add user audio message to history
    _history.add({
      'role': 'user',
      'parts': [
        {
          'inlineData': {
            'mimeType': 'audio/wav',
            'data': base64Audio,
          },
        },
        {
          'text': '(The user sent a voice message. Listen to the audio, '
              'understand what they said, and respond accordingly. '
              'If they spoke in English, evaluate their pronunciation '
              'and grammar as well.)',
        },
      ],
    });

    try {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/'
        '${AppConstants.geminiTextModel}:generateContent?key=$_apiKey',
      );

      final body = jsonEncode({
        'contents': _history,
        'system_instruction': {
          'parts': [{'text': _systemPrompt}],
        },
        'generation_config': {
          'temperature': 0.8,
          'max_output_tokens': 500,
        },
      });

      http.Response response;

      if (!kIsWeb && _proxyEnabled && _proxyHost != null && _proxyPort != null) {
        final httpClient = HttpClient();
        httpClient.findProxy = (uri) => 'PROXY $_proxyHost:$_proxyPort';
        final request = await httpClient.postUrl(url);
        request.headers.contentType = ContentType.json;
        request.write(body);
        final ioResponse = await request.close();
        final responseBody = await ioResponse.transform(utf8.decoder).join();
        response = http.Response(responseBody, ioResponse.statusCode);
        httpClient.close();
      } else {
        response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: body,
        );
      }

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body);
        final errorMsg = error['error']?['message'] ?? 'Unknown error';
        throw Exception('API error ${response.statusCode}: $errorMsg');
      }

      final data = jsonDecode(response.body);
      final candidates = data['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        throw Exception('No response from model');
      }

      final parts = candidates[0]['content']['parts'] as List;
      final responseText = parts.map((p) => p['text'] as String).join();

      // Replace user audio parts in history with text summary to save tokens
      if (_history.isNotEmpty && _history.last['role'] == 'user') {
        _history.last = {
          'role': 'user',
          'parts': [{'text': '[Voice message from user]'}],
        };
      }

      // Add model response to history
      _history.add({
        'role': 'model',
        'parts': [{'text': responseText}],
      });

      _responseController.add(responseText);
      _isGenerating = false;
      return responseText;
    } catch (e) {
      _isGenerating = false;
      if (_history.isNotEmpty && _history.last['role'] == 'user') {
        _history.removeLast();
      }
      rethrow;
    }
  }

  /// Build WAV header for PCM data
  Uint8List _buildWav(Uint8List pcm) {
    const sr = 16000; // input sample rate
    const bps = 16;
    const ch = 1;
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

  /// Transcribe audio to text using Gemini (standalone, doesn't affect history)
  Future<String?> transcribeAudio(Uint8List pcmData) async {
    if (_apiKey == null || _apiKey!.isEmpty) return null;

    final wavData = _buildWav(pcmData);
    final base64Audio = base64Encode(wavData);

    try {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/'
        '${AppConstants.geminiTextModel}:generateContent?key=$_apiKey',
      );

      final body = jsonEncode({
        'contents': [
          {
            'parts': [
              {
                'inlineData': {
                  'mimeType': 'audio/wav',
                  'data': base64Audio,
                },
              },
              {
                'text': 'Transcribe exactly what the user said in this audio. '
                    'Output ONLY the transcription, nothing else. '
                    'If they spoke English, transcribe in English. '
                    'If they spoke Chinese, transcribe in Simplified Chinese.',
              },
            ],
          },
        ],
        'generation_config': {
          'temperature': 0.0,
          'max_output_tokens': 200,
        },
      });

      http.Response response;

      if (!kIsWeb && _proxyEnabled && _proxyHost != null && _proxyPort != null) {
        final httpClient = HttpClient();
        httpClient.findProxy = (uri) => 'PROXY $_proxyHost:$_proxyPort';
        final request = await httpClient.postUrl(url);
        request.headers.contentType = ContentType.json;
        request.write(body);
        final ioResponse = await request.close();
        final responseBody = await ioResponse.transform(utf8.decoder).join();
        response = http.Response(responseBody, ioResponse.statusCode);
        httpClient.close();
      } else {
        response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: body,
        );
      }

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      final candidates = data['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) return null;

      final parts = candidates[0]['content']['parts'] as List;
      return parts.map((p) => p['text'] as String).join().trim();
    } catch (e) {
      debugPrint('Transcribe error: $e');
      return null;
    }
  }

  /// Clear conversation history
  void clearHistory() {
    _history.clear();
  }

  void dispose() {
    _responseController.close();
  }
}
