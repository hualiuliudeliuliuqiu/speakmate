import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../config/constants.dart';
import 'gemini_live_service.dart' show GeminiConnectionState;

/// VolcEngine (火山引擎) end-to-end realtime voice service.
///
/// Protocol doc: https://www.volcengine.com/docs/6561/1594356
/// Binary frames: 4-byte header + optional(event/session_id/connect_id) + payload_size + payload
///
/// Client events:
///   1  StartConnection   (connect-level)
///   2  FinishConnection  (connect-level)
///  100 StartSession      (session-level, carries session_id)
///  102 FinishSession     (session-level)
///  200 TaskRequest       (session-level, audio data)
///  501 ChatTextQuery     (session-level)
///
/// Server events:
///   50 ConnectionStarted (connect-level, carries connect_id)
///  150 SessionStarted    (session-level, carries session_id)
///  152 SessionFinished   (session-level)
///  350 TTSSentenceStart  (session-level)
///  351 TTSSentenceEnd    (session-level)
///  352 TTSResponse       (session-level, mt=0xB audio)
///  359 TTSEnded          (session-level)
///  450 ASRInfo           (session-level)
///  451 ASRResponse       (session-level, user speech text)
///  459 ASREnded          (session-level)
///  550 ChatResponse      (session-level, model reply text)
///  559 ChatEnded         (session-level)
///  599 DialogCommonError (session-level)
class VolcLiveService {
  WebSocket? _ws;
  StreamSubscription? _wsSubscription;

  final _stateController =
      StreamController<GeminiConnectionState>.broadcast();
  final _audioController = StreamController<Uint8List>.broadcast();
  final _transcriptController = StreamController<String>.broadcast();
  final _userTranscriptController = StreamController<String>.broadcast();
  final _ttsEndedController = StreamController<void>.broadcast();

  GeminiConnectionState _state = GeminiConnectionState.disconnected;

  Stream<GeminiConnectionState> get onStateChanged => _stateController.stream;
  Stream<Uint8List> get onAudioReceived => _audioController.stream;
  Stream<String> get onTranscriptReceived => _transcriptController.stream;
  Stream<String> get onUserTranscriptReceived =>
      _userTranscriptController.stream;
  Stream<void> get onTTSEnded => _ttsEndedController.stream;
  GeminiConnectionState get state => _state;

  String? _appId;
  String? _accessKey;
  String _systemPrompt = AppConstants.systemPrompt;
  bool _isModelSpeaking = false;
  bool get isModelSpeaking => _isModelSpeaking;

  String _sessionId = '';
  String _connectId = '';
  Completer<bool>? _setupCompleter;
  Completer<bool>? _sessionCompleter;
  Future<bool> get setupComplete =>
      (_setupCompleter ?? Completer<bool>()).future;

  static const _wsUrl =
      'wss://openspeech.bytedance.com/api/v3/realtime/dialogue';
  static const _fixedAppKey = 'PlgvMymc7f3tQnJ6';
  static const _resourceId = 'volc.speech.dialog';
  static const _uuid = Uuid();

  // ─── Client Event IDs ───
  static const _evStartConnection = 1;
  static const _evFinishConnection = 2;
  static const _evStartSession = 100;
  static const _evFinishSession = 102;
  static const _evTaskRequest = 200;
  static const _evChatTextQuery = 501;

  // ─── Server Event IDs ───
  static const _evConnectionStarted = 50;
  static const _evConnectionFailed = 51;
  static const _evConnectionFinished = 52;
  static const _evSessionStarted = 150;
  static const _evSessionFinished = 152;
  static const _evSessionFailed = 153;
  static const _evTTSSentenceStart = 350;
  static const _evTTSSentenceEnd = 351;
  static const _evTTSResponse = 352;
  static const _evTTSEnded = 359;
  static const _evASRInfo = 450;
  static const _evASRResponse = 451;
  static const _evASREnded = 459;
  static const _evChatResponse = 550;
  static const _evChatEnded = 559;
  static const _evDialogError = 599;

  // ─── Message Types ───
  static const _mtClientText = 0x01;  // 0b0001
  static const _mtClientAudio = 0x02; // 0b0010
  static const _mtServerText = 0x09;  // 0b1001
  static const _mtServerAudio = 0x0B; // 0b1011
  static const _mtError = 0x0F;       // 0b1111

  void configure({
    required String appId,
    required String accessKey,
    String? systemPromptAddition,
  }) {
    _appId = appId;
    _accessKey = accessKey;
    if (systemPromptAddition != null && systemPromptAddition.isNotEmpty) {
      _systemPrompt =
          '${AppConstants.systemPrompt}\n\nADDITIONAL CONTEXT:\n$systemPromptAddition';
    } else {
      _systemPrompt = AppConstants.systemPrompt;
    }
  }

  Future<void> connect() async {
    if (_appId == null || _accessKey == null) {
      _setState(GeminiConnectionState.error);
      throw Exception('VolcEngine credentials not configured');
    }

    _setState(GeminiConnectionState.connecting);
    _setupCompleter = Completer<bool>();
    _sessionCompleter = Completer<bool>();
    _connectId = _uuid.v4();
    _sessionId = _uuid.v4();
    _audioSendCount = 0;

    try {
      print('SM_VOLC connecting to $_wsUrl');
      print('SM_VOLC appId=$_appId accessKey=${_accessKey?.substring(0, 8)}...');

      _ws = await WebSocket.connect(
        _wsUrl,
        headers: {
          'X-Api-App-ID': _appId!,
          'X-Api-Access-Key': _accessKey!,
          'X-Api-Resource-Id': _resourceId,
          'X-Api-App-Key': _fixedAppKey,
          'X-Api-Connect-Id': _connectId,
        },
      );
      print('SM_VOLC WebSocket connected!');

      _wsSubscription = _ws!.listen(
        _handleBinaryMessage,
        onError: (error) {
          print('SM_VOLC WS error: $error');
          _setState(GeminiConnectionState.error);
        },
        onDone: () {
          print('SM_VOLC WS closed (code=${_ws?.closeCode}, reason=${_ws?.closeReason})');
          if (_state != GeminiConnectionState.disconnected) {
            _setState(GeminiConnectionState.disconnected);
          }
        },
        cancelOnError: false,
      );

      // Step 1: StartConnection (connect-level, no session_id)
      _sendFrame(
        messageType: _mtClientText,
        eventId: _evStartConnection,
        jsonPayload: '{}',
      );

      await _setupCompleter!.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('VolcEngine connection timeout'),
      );

      // Step 2: StartSession (session-level, carries session_id)
      _sendStartSession();

      await _sessionCompleter!.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('VolcEngine session timeout'),
      );

      _setState(GeminiConnectionState.connected);
      print('SM_VOLC fully connected, ready for audio');
    } catch (e) {
      print('SM_VOLC connect failed: $e');
      _setState(GeminiConnectionState.error);
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════
  //  Binary Protocol — Frame Builder
  // ═══════════════════════════════════════════════════

  /// Generic frame builder.
  /// [messageType] : _mtClientText(0x01) or _mtClientAudio(0x02)
  /// [eventId]     : event number (1, 100, 200, etc.)
  /// [sessionId]   : for session-level events (100+)
  /// [connectId]   : for connect-level events (1-2)
  /// [jsonPayload] : JSON string payload (for text frames)
  /// [audioPayload]: raw PCM bytes (for audio frames)
  void _sendFrame({
    required int messageType,
    required int eventId,
    String? jsonPayload,
    Uint8List? audioPayload,
    String? sessionId,
    String? connectId,
  }) {
    if (_ws == null) return;

    final builder = BytesBuilder();

    // Byte 0: version(1) | headerSize(1) → 0x11
    builder.addByte(0x11);

    // Byte 1: messageType(4bit) | flags(4bit)
    // flags = 0b0100 (has event)
    builder.addByte((messageType << 4) | 0x04);

    // Byte 2: serialization(4bit) | compression(4bit)
    final isAudio = messageType == _mtClientAudio;
    builder.addByte(isAudio ? 0x00 : 0x10); // raw:0x00, JSON:0x10

    // Byte 3: reserved
    builder.addByte(0x00);

    // Event ID (4 bytes BE)
    builder.add(_int32BE(eventId));

    // Connect ID (for connect-level client events: 1, 2)
    if (connectId != null) {
      final cidBytes = utf8.encode(connectId);
      builder.add(_int32BE(cidBytes.length));
      builder.add(cidBytes);
    }

    // Session ID (for session-level client events: 100+)
    if (sessionId != null) {
      final sidBytes = utf8.encode(sessionId);
      builder.add(_int32BE(sidBytes.length));
      builder.add(sidBytes);
    }

    // Payload
    final Uint8List payload;
    if (jsonPayload != null) {
      payload = Uint8List.fromList(utf8.encode(jsonPayload));
    } else if (audioPayload != null) {
      payload = audioPayload;
    } else {
      payload = Uint8List(0);
    }

    builder.add(_int32BE(payload.length));
    builder.add(payload);

    _ws!.add(builder.toBytes());
  }

  Uint8List _int32BE(int value) {
    final bd = ByteData(4);
    bd.setInt32(0, value, Endian.big);
    return bd.buffer.asUint8List();
  }

  int _readInt32BE(Uint8List data, int offset) {
    return (data[offset] << 24) |
        (data[offset + 1] << 16) |
        (data[offset + 2] << 8) |
        data[offset + 3];
  }

  // ═══════════════════════════════════════════════════
  //  Send Commands
  // ═══════════════════════════════════════════════════

  void _sendStartSession() {
    final config = jsonEncode({
      'dialog': {
        'bot_name': 'SpeakMate',
        'system_role': _systemPrompt,
        'speaking_style':
            'Speak naturally like a friendly English teacher. Be encouraging and patient.',
        'extra': {
          'model': 'O',
          'strict_audit': false,
        },
      },
      'tts': {
        'audio_config': {
          'channel': AppConstants.numChannels,
          'format': 'pcm_s16le',
          'sample_rate': AppConstants.outputSampleRate,
        },
        'speaker': 'zh_female_vv_jupiter_bigtts',
      },
      'asr': {
        'audio_info': {
          'format': 'pcm',
          'sample_rate': AppConstants.inputSampleRate,
          'channel': AppConstants.numChannels,
        },
      },
    });

    _sendFrame(
      messageType: _mtClientText,
      eventId: _evStartSession,
      jsonPayload: config,
      sessionId: _sessionId,
    );
  }

  int _audioSendCount = 0;

  /// Send microphone PCM audio (TaskRequest, event 200)
  void sendAudio(Uint8List pcmData) {
    if (_ws == null || _state != GeminiConnectionState.connected) {
      if (_audioSendCount == 0) {
        print('SM_VOLC sendAudio BLOCKED: ws=${_ws != null}, state=$_state');
      }
      return;
    }
    _audioSendCount++;
    if (_audioSendCount <= 3 || _audioSendCount % 100 == 0) {
      print('SM_VOLC sendAudio #$_audioSendCount: ${pcmData.length}B');
    }

    _sendFrame(
      messageType: _mtClientAudio,
      eventId: _evTaskRequest,
      audioPayload: pcmData,
      sessionId: _sessionId,
    );
  }

  /// Send text query (ChatTextQuery, event 501)
  void sendTextMessage(String text) {
    if (_ws == null || _state != GeminiConnectionState.connected) return;
    if (text.trim().isEmpty) return;

    _sendFrame(
      messageType: _mtClientText,
      eventId: _evChatTextQuery,
      jsonPayload: jsonEncode({'content': text.trim()}),
      sessionId: _sessionId,
    );
  }

  // ═══════════════════════════════════════════════════
  //  Binary Protocol — Parsing Server Messages
  // ═══════════════════════════════════════════════════

  void _handleBinaryMessage(dynamic rawData) {
    try {
      Uint8List data;
      if (rawData is List<int>) {
        data = Uint8List.fromList(rawData);
      } else if (rawData is String) {
        print('SM_VOLC unexpected text frame: ${rawData.substring(0, rawData.length.clamp(0, 100))}');
        return;
      } else {
        return;
      }

      if (data.length < 4) return;

      final messageType = (data[1] >> 4) & 0x0F;
      final flags = data[1] & 0x0F;
      final serialization = (data[2] >> 4) & 0x0F;

      int offset = 4;

      // ─── Error code (mt=0x0F only) ───
      int? errorCode;
      if (messageType == _mtError) {
        if (offset + 4 > data.length) return;
        errorCode = _readInt32BE(data, offset);
        offset += 4;
      }

      // ─── Sequence (flags bit0-1) ───
      int? sequence;
      final seqBits = flags & 0x03;
      if (seqBits == 0x01 || seqBits == 0x03) {
        if (offset + 4 > data.length) return;
        sequence = _readInt32BE(data, offset);
        offset += 4;
      }

      // ─── Event ID (flags bit2 = 0x04) ───
      int? eventId;
      if (flags & 0x04 != 0) {
        if (offset + 4 > data.length) return;
        eventId = _readInt32BE(data, offset);
        offset += 4;
      }

      // ─── Connect ID / Session ID (based on event range) ───
      // Connect-level events (1-99, 50-99): may carry connect_id
      // Session-level events (100+, 150+): may carry session_id
      if (eventId != null) {
        if (eventId >= 100) {
          // Session-level → skip session_id if present
          offset = _skipOptionalId(data, offset);
        } else if (eventId >= 1 && eventId < 100) {
          // Connect-level → skip connect_id if present
          offset = _skipOptionalId(data, offset);
        }
      }

      // ─── Payload size + payload ───
      if (offset + 4 > data.length) return;
      final payloadSize = _readInt32BE(data, offset);
      offset += 4;

      Uint8List payload;
      if (payloadSize > 0 && offset + payloadSize <= data.length) {
        payload = data.sublist(offset, offset + payloadSize);
      } else {
        payload = Uint8List(0);
      }

      _processMessage(messageType, eventId, payload, serialization, sequence, errorCode);
    } catch (e) {
      print('SM_VOLC parse error: $e');
    }
  }

  /// Skip a variable-length ID field (4-byte size + N bytes).
  /// Returns updated offset. Only skips if it looks like a UUID-sized field.
  int _skipOptionalId(Uint8List data, int offset) {
    if (offset + 4 > data.length) return offset;
    final idLen = _readInt32BE(data, offset);
    // UUID = 36 chars. Accept up to 128 for safety.
    // Also verify that after skipping, there's still room for payload_size(4).
    if (idLen > 0 && idLen <= 128 && offset + 4 + idLen + 4 <= data.length) {
      return offset + 4 + idLen;
    }
    return offset; // Not a valid ID field, treat current position as payload_size
  }

  void _processMessage(int messageType, int? eventId, Uint8List payload,
      int serialization, int? sequence, int? errorCode) {

    // ─── Server audio (TTSResponse, event 352) ───
    if (messageType == _mtServerAudio) {
      if (payload.isNotEmpty) {
        _isModelSpeaking = true;
        _audioController.add(payload);
      }
      return;
    }

    // ─── Server text (JSON events) ───
    if (messageType == _mtServerText) {
      Map<String, dynamic> json = {};
      if (serialization == 0x01 && payload.isNotEmpty) {
        try {
          json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
        } catch (e) {
          print('SM_VOLC JSON decode error: $e');
        }
      }
      _handleServerEvent(eventId, json);
      return;
    }

    // ─── Error ───
    if (messageType == _mtError) {
      String errorMsg = 'code=$errorCode';
      if (payload.isNotEmpty) {
        try {
          final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
          errorMsg = json['error']?.toString() ?? errorMsg;
        } catch (_) {
          errorMsg = utf8.decode(payload, allowMalformed: true);
        }
      }
      print('SM_VOLC error (event=$eventId): $errorMsg');
      return;
    }
  }

  void _handleServerEvent(int? eventId, Map<String, dynamic> json) {
    if (eventId == null) return;

    switch (eventId) {
      // ─── Connection lifecycle ───
      case _evConnectionStarted:
        print('SM_VOLC event: ConnectionStarted');
        if (_setupCompleter != null && !_setupCompleter!.isCompleted) {
          _setupCompleter!.complete(true);
        }
        break;

      case _evConnectionFailed:
        print('SM_VOLC event: ConnectionFailed ${json['error']}');
        if (_setupCompleter != null && !_setupCompleter!.isCompleted) {
          _setupCompleter!.completeError(Exception(json['error']));
        }
        break;

      case _evConnectionFinished:
        print('SM_VOLC event: ConnectionFinished');
        break;

      // ─── Session lifecycle ───
      case _evSessionStarted:
        print('SM_VOLC event: SessionStarted (dialog_id=${json['dialog_id']})');
        if (_sessionCompleter != null && !_sessionCompleter!.isCompleted) {
          _sessionCompleter!.complete(true);
        }
        break;

      case _evSessionFinished:
        print('SM_VOLC event: SessionFinished');
        break;

      case _evSessionFailed:
        print('SM_VOLC event: SessionFailed ${json['error']}');
        break;

      // ─── TTS events ───
      case _evTTSSentenceStart:
        _isModelSpeaking = true;
        final ttsText = json['text'] as String?;
        print('SM_VOLC TTS start: ${ttsText ?? "(no text)"}');
        // Don't send to transcript here — ChatResponse(550) handles text
        break;

      case _evTTSSentenceEnd:
        // Sentence boundary, no action needed
        break;

      case _evTTSResponse:
        // Audio data — but this event uses mt=0xB (audio), not 0x09 (text).
        // If we get it here, the payload might be empty (audio handled above).
        break;

      case _evTTSEnded:
        print('SM_VOLC TTS ended');
        _isModelSpeaking = false;
        if (!_ttsEndedController.isClosed) {
          _ttsEndedController.add(null);
        }
        break;

      // ─── ASR events (user speech recognition) ───
      case _evASRInfo:
        print('SM_VOLC ASR info (user started speaking)');
        // User started speaking — can interrupt playback
        _isModelSpeaking = false;
        break;

      case _evASRResponse:
        // {results: [{text: "...", is_interim: true/false}]}
        final results = json['results'] as List<dynamic>?;
        if (results != null) {
          for (final r in results) {
            if (r is Map<String, dynamic>) {
              final text = r['text'] as String? ?? '';
              if (text.trim().isNotEmpty) {
                print('SM_VOLC ASR: "$text" (interim=${r['is_interim']})');
                _userTranscriptController.add(text);
              }
            }
          }
        }
        break;

      case _evASREnded:
        print('SM_VOLC ASR ended (user stopped speaking)');
        break;

      // ─── Chat events (model text reply) ───
      case _evChatResponse:
        final content = json['content'] as String? ?? '';
        if (content.trim().isNotEmpty) {
          print('SM_VOLC Chat: "$content"');
          _transcriptController.add(content);
        }
        break;

      case _evChatEnded:
        print('SM_VOLC Chat ended');
        break;

      // ─── Error ───
      case _evDialogError:
        final msg = json['message'] ?? json['error'] ?? 'unknown';
        final code = json['status_code'];
        print('SM_VOLC dialog error: code=$code msg=$msg');
        break;

      default:
        print('SM_VOLC unknown event $eventId: ${jsonEncode(json).substring(0, (jsonEncode(json).length).clamp(0, 300))}');
        break;
    }
  }

  void _setState(GeminiConnectionState newState) {
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
  }

  Future<void> disconnect() async {
    if (_ws != null && _state == GeminiConnectionState.connected) {
      try {
        _sendFrame(
          messageType: _mtClientText,
          eventId: _evFinishSession,
          jsonPayload: '{}',
          sessionId: _sessionId,
        );
        _sendFrame(
          messageType: _mtClientText,
          eventId: _evFinishConnection,
          jsonPayload: '{}',
          connectId: _connectId,
        );
      } catch (_) {}
    }

    _wsSubscription?.cancel();
    _wsSubscription = null;

    try {
      await _ws?.close();
    } catch (_) {}
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
    _ttsEndedController.close();
  }
}
