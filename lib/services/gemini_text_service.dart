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

  /// Clear conversation history
  void clearHistory() {
    _history.clear();
  }

  void dispose() {
    _responseController.close();
  }
}
