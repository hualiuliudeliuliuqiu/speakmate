import 'dart:async';
import 'dart:convert';
import 'dart:io' if (dart.library.html) 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/constants.dart';

enum GeminiConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

class GeminiLiveService {
  // We use WebSocketChannel (works on both mobile and web)
  // For mobile with proxy, we fall back to dart:io WebSocket
  dynamic _ws; // Either WebSocket (dart:io) or WebSocketChannel
  StreamSubscription? _wsSubscription;

  final _stateController =
      StreamController<GeminiConnectionState>.broadcast();
  final _audioController = StreamController<Uint8List>.broadcast();
  final _transcriptController = StreamController<String>.broadcast();
  final _userTranscriptController = StreamController<String>.broadcast();

  GeminiConnectionState _state = GeminiConnectionState.disconnected;

  Stream<GeminiConnectionState> get onStateChanged => _stateController.stream;
  Stream<Uint8List> get onAudioReceived => _audioController.stream;
  Stream<String> get onTranscriptReceived => _transcriptController.stream;
  Stream<String> get onUserTranscriptReceived =>
      _userTranscriptController.stream;
  GeminiConnectionState get state => _state;

  String? _apiKey;
  String? _proxyHost;
  int? _proxyPort;
  bool _proxyEnabled = true;
  String _voiceName = AppConstants.defaultVoice;
  String _systemPrompt = AppConstants.systemPrompt;
  bool _isModelSpeaking = false;
  bool get isModelSpeaking => _isModelSpeaking;

  Completer<bool>? _setupCompleter;
  Future<bool> get setupComplete =>
      (_setupCompleter ?? Completer<bool>()).future;

  void configure({
    required String apiKey,
    String? proxyHost,
    int? proxyPort,
    bool proxyEnabled = true,
    String? voiceName,
    String? systemPromptAddition,
  }) {
    _apiKey = apiKey;
    _proxyHost = proxyHost;
    _proxyPort = proxyPort;
    _proxyEnabled = proxyEnabled;
    _voiceName = voiceName ?? AppConstants.defaultVoice;
    if (systemPromptAddition != null && systemPromptAddition.isNotEmpty) {
      _systemPrompt =
          '${AppConstants.systemPrompt}\n\nADDITIONAL CONTEXT:\n$systemPromptAddition';
    } else {
      _systemPrompt = AppConstants.systemPrompt;
    }
  }

  Future<void> connect() async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      _setState(GeminiConnectionState.error);
      throw Exception('API key not configured');
    }

    _setState(GeminiConnectionState.connecting);
    _setupCompleter = Completer<bool>();

    final url = '${AppConstants.geminiWsBaseUrl}?key=$_apiKey';

    try {
      if (kIsWeb) {
        // Web: use WebSocketChannel directly (no proxy support)
        await _connectWeb(url);
      } else {
        // Mobile/Desktop: use dart:io WebSocket with proxy
        await _connectNative(url);
      }
    } catch (e) {
      debugPrint('Failed to connect: $e');
      _setState(GeminiConnectionState.error);
      rethrow;
    }
  }

  Future<void> _connectWeb(String url) async {
    final channel = WebSocketChannel.connect(Uri.parse(url));
    _ws = channel;

    // Send setup
    _sendRaw(_buildSetupMessage());

    // Listen
    _wsSubscription = channel.stream.listen(
      (data) => _handleMessage(data),
      onError: (error) {
        debugPrint('WebSocket error: $error');
        _setState(GeminiConnectionState.error);
      },
      onDone: () {
        debugPrint('WebSocket closed');
        _setState(GeminiConnectionState.disconnected);
      },
    );
  }

  Future<void> _connectNative(String url) async {
    final httpClient = HttpClient();
    if (_proxyEnabled &&
        _proxyHost != null &&
        _proxyHost!.isNotEmpty &&
        _proxyPort != null) {
      httpClient.findProxy =
          (uri) => 'PROXY $_proxyHost:$_proxyPort';
    }

    final ws = await WebSocket.connect(url, customClient: httpClient);
    _ws = ws;

    // Send setup
    _sendRaw(_buildSetupMessage());

    // Listen
    _wsSubscription = ws.listen(
      (data) => _handleMessage(data),
      onError: (error) {
        debugPrint('WebSocket error: $error');
        _setState(GeminiConnectionState.error);
      },
      onDone: () {
        debugPrint('WebSocket closed');
        _setState(GeminiConnectionState.disconnected);
      },
      cancelOnError: false,
    );
  }

  String _buildSetupMessage() {
    return jsonEncode({
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
        'output_audio_transcription': {},
        'system_instruction': {
          'parts': [
            {'text': _systemPrompt},
          ],
        },
      },
    });
  }

  void _sendRaw(String data) {
    if (_ws == null) return;
    if (_ws is WebSocketChannel) {
      (_ws as WebSocketChannel).sink.add(data);
    } else if (_ws is WebSocket) {
      (_ws as WebSocket).add(data);
    }
  }

  void _handleMessage(dynamic rawMessage) {
    try {
      Map<String, dynamic> message;
      if (rawMessage is String) {
        message = jsonDecode(rawMessage) as Map<String, dynamic>;
      } else if (rawMessage is List<int>) {
        message =
            jsonDecode(utf8.decode(rawMessage)) as Map<String, dynamic>;
      } else {
        return;
      }

      // Setup complete
      if (message.containsKey('setupComplete')) {
        debugPrint('Gemini setup complete');
        _setState(GeminiConnectionState.connected);
        if (_setupCompleter != null && !_setupCompleter!.isCompleted) {
          _setupCompleter!.complete(true);
        }
        return;
      }

      // Server content (model responses)
      if (message.containsKey('serverContent')) {
        final serverContent =
            message['serverContent'] as Map<String, dynamic>;

        if (serverContent.containsKey('modelTurn')) {
          _isModelSpeaking = true;
          final modelTurn =
              serverContent['modelTurn'] as Map<String, dynamic>;
          final parts = modelTurn['parts'] as List<dynamic>?;

          if (parts != null) {
            for (final part in parts) {
              final partMap = part as Map<String, dynamic>;

              // Audio data
              if (partMap.containsKey('inlineData')) {
                final inlineData =
                    partMap['inlineData'] as Map<String, dynamic>;
                final base64Data = inlineData['data'] as String?;
                if (base64Data != null) {
                  final audioBytes = base64Decode(base64Data);
                  _audioController.add(Uint8List.fromList(audioBytes));
                }
              }

              // Ignore inline text from modelTurn — it's thinking/planning text,
              // not the actual speech transcription.
            }
          }
        }

        // Output audio transcription (the real speech-to-text)
        if (serverContent.containsKey('outputTranscription')) {
          final transcription =
              serverContent['outputTranscription'] as Map<String, dynamic>;
          final text = transcription['text'] as String?;
          if (text != null && text.isNotEmpty) {
            _transcriptController.add(text);
          }
        }

        // Turn complete
        final turnComplete = serverContent['turnComplete'] as bool?;
        if (turnComplete == true) {
          _isModelSpeaking = false;
        }

        // Barge-in
        final interrupted = serverContent['interrupted'] as bool?;
        if (interrupted == true) {
          _isModelSpeaking = false;
        }
      }
    } catch (e) {
      debugPrint('Error handling message: $e');
    }
  }

  /// Send audio from mic
  void sendAudio(Uint8List pcmData) {
    if (_ws == null || _state != GeminiConnectionState.connected) return;

    final base64Audio = base64Encode(pcmData);
    _sendRaw(jsonEncode({
      'realtime_input': {
        'media_chunks': [
          {
            'data': base64Audio,
            'mime_type': 'audio/pcm;rate=${AppConstants.inputSampleRate}',
          },
        ],
      },
    }));
  }

  /// Send text message
  void sendTextMessage(String text) {
    if (_ws == null || _state != GeminiConnectionState.connected) return;
    if (text.trim().isEmpty) return;

    _sendRaw(jsonEncode({
      'client_content': {
        'turns': [
          {
            'role': 'user',
            'parts': [
              {'text': text.trim()},
            ],
          },
        ],
        'turn_complete': true,
      },
    }));
  }

  /// Signal turn complete
  void sendTurnComplete() {
    if (_ws == null || _state != GeminiConnectionState.connected) return;

    _sendRaw(jsonEncode({
      'client_content': {
        'turn_complete': true,
      },
    }));
  }

  void _setState(GeminiConnectionState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  Future<void> disconnect() async {
    _wsSubscription?.cancel();
    _wsSubscription = null;

    if (_ws is WebSocketChannel) {
      await (_ws as WebSocketChannel).sink.close();
    } else if (_ws is WebSocket) {
      await (_ws as WebSocket).close();
    }
    _ws = null;
    _isModelSpeaking = false;
    _setState(GeminiConnectionState.disconnected);
  }

  void dispose() {
    disconnect();
    _stateController.close();
    _audioController.close();
    _transcriptController.close();
    _userTranscriptController.close();
  }
}
