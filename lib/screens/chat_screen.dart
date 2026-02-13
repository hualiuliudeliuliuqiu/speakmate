import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/scenario.dart';
import '../config/constants.dart';
import '../services/audio_service.dart';
import '../services/conversation_service.dart';
import '../services/gemini_live_service.dart';
import '../services/live_service_interface.dart';
import '../services/storage_service.dart';
import '../widgets/audio_visualizer.dart';
import '../widgets/transcript_bubble.dart';

class ChatScreen extends StatefulWidget {
  final Scenario scenario;

  const ChatScreen({super.key, required this.scenario});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  late LiveServiceWrapper _gemini;
  final AudioService _audio = AudioService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();

  late Conversation _conversation;
  final List<Message> _messages = [];
  GeminiConnectionState _connectionState = GeminiConnectionState.disconnected;
  bool _isRecording = false;
  bool _isModelSpeaking = false;
  double _audioLevel = 0.0;
  String _currentAssistantText = '';
  String? _errorMessage;
  Timer? _modelTurnTimer;

  StreamSubscription<GeminiConnectionState>? _stateSub;
  StreamSubscription<List<int>>? _audioSub;
  StreamSubscription<String>? _transcriptSub;
  StreamSubscription<String>? _userTranscriptSub;
  StreamSubscription<double>? _audioLevelSub;
  String _currentUserTranscript = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _textController.addListener(() {
      setState(() {}); // rebuild to update send button color
    });
    _loadConversation();
    _initConnection();
  }

  void _loadConversation() {
    final convService = context.read<ConversationService>();
    _conversation = convService.getOrCreate(
      scenarioId: widget.scenario.id,
      scenarioTitle: widget.scenario.title,
    );
    // Restore previous messages
    if (_conversation.messages.isNotEmpty) {
      _messages.addAll(_conversation.messages);
      // Preload audio cache for assistant messages
      final assistantIds = _messages
          .where((m) => m.role == MessageRole.assistant)
          .map((m) => m.id)
          .toList();
      _audio.preloadAudioCache(assistantIds).then((_) {
        if (mounted) setState(() {});
      });
      // Scroll to bottom after frame
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  Future<void> _initConnection() async {
    final storage = context.read<StorageService>();
    final activeKey = storage.activeApiKey;
    if (activeKey.isEmpty) {
      setState(() {
        _errorMessage = 'API key not configured. Please check Settings.';
      });
      return;
    }

    _stateSub?.cancel();
    _audioSub?.cancel();
    _transcriptSub?.cancel();
    _userTranscriptSub?.cancel();

    // Initialize live service based on selected provider
    _gemini = LiveServiceWrapper(storage.aiProvider);

    // Build context from previous conversation for continuity
    final contextSummary = _conversation.buildContextSummary();
    final scenarioContext = widget.scenario.systemPromptAddition;
    final fullAddition = [scenarioContext, contextSummary]
        .where((s) => s.isNotEmpty)
        .join('\n\n');

    _gemini.configure(
      storage: storage,
      systemPromptAddition: fullAddition.isNotEmpty ? fullAddition : null,
    );

    _stateSub = _gemini.onStateChanged.listen((state) {
      if (!mounted) return;
      setState(() {
        _connectionState = state;
        if (state == GeminiConnectionState.error) {
          _errorMessage = 'Connection lost. Tap to reconnect.';
        } else if (state == GeminiConnectionState.connected) {
          _errorMessage = null;
          // VolcEngine requires continuous audio stream for VAD.
          // Auto-start recording on connection.
          if (_gemini.provider == AIProvider.volcengine && !_isRecording) {
            _startRecording();
          }
        }
      });
    });

    _audioSub = _gemini.onAudioReceived.listen((audioData) {
      _audio.addPlaybackData(audioData);
    });

    _transcriptSub = _gemini.onTranscriptReceived.listen((text) {
      if (!mounted) return;
      final convService = context.read<ConversationService>();
      setState(() {
        _isModelSpeaking = true;
        _currentAssistantText += text;
        if (_messages.isNotEmpty &&
            _messages.last.role == MessageRole.assistant &&
            _messages.last.isStreaming) {
          _messages.last.text = _currentAssistantText;
          convService.updateLastMessage(_conversation.id, _currentAssistantText);
        } else {
          final msg = Message(
            role: MessageRole.assistant,
            text: _currentAssistantText,
            isStreaming: true,
          );
          _messages.add(msg);
          convService.addMessage(_conversation.id, msg);
        }
      });
      _scrollToBottom();
    });

    _userTranscriptSub = _gemini.onUserTranscriptReceived.listen((text) {
      if (!mounted) return;
      final convService = context.read<ConversationService>();
      setState(() {
        // VolcEngine sends full ASR text (replace), Gemini sends incremental tokens (append)
        if (_gemini.provider == AIProvider.volcengine) {
          _currentUserTranscript = text; // replace
        } else {
          _currentUserTranscript += text; // append
        }
        // Find the last user voice message and update its transcription
        for (int i = _messages.length - 1; i >= 0; i--) {
          if (_messages[i].role == MessageRole.user && _messages[i].isVoice) {
            _messages[i].text = _currentUserTranscript;
            convService.updateLastUserMessage(
                _conversation.id, _messages[i].text);
            break;
          }
        }
      });
      _scrollToBottom();
    });

    _startModelTurnMonitor();

    try {
      await _gemini.connect();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to connect: $e';
        });
      }
    }
  }

  void _startModelTurnMonitor() {
    _modelTurnTimer?.cancel();
    _modelTurnTimer =
        Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final speaking = _gemini.isModelSpeaking;
      if (_isModelSpeaking && !speaking) {
        // Get the message ID for audio replay
        String? msgId;
        if (_messages.isNotEmpty &&
            _messages.last.role == MessageRole.assistant) {
          msgId = _messages.last.id;
        }
        setState(() {
          _isModelSpeaking = false;
          if (_messages.isNotEmpty &&
              _messages.last.role == MessageRole.assistant &&
              _messages.last.isStreaming) {
            _messages.last.isStreaming = false;
          }
          _currentAssistantText = '';
        });
        _audio.markPlaybackDone();
        _audio.flushRemainingPlayback(messageId: msgId).then((_) {
          if (mounted) setState(() {}); // refresh to show replay button
        });
      }
      if (!_isModelSpeaking && speaking) {
        setState(() {
          _isModelSpeaking = true;
        });
      }
    });
  }

  // ─── Voice input ───

  Future<void> _toggleRecording() async {
    if (_connectionState != GeminiConnectionState.connected) {
      if (_connectionState == GeminiConnectionState.error ||
          _connectionState == GeminiConnectionState.disconnected) {
        _initConnection();
      }
      return;
    }

    if (_isRecording) {
      // VolcEngine: keep recording (VAD auto-detects speech), only stop on disconnect
      if (_gemini.provider == AIProvider.volcengine) {
        // User tapped stop → disconnect entirely
        await _stopRecording();
        await _gemini.disconnect();
        return;
      }
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    _textFocusNode.unfocus();
    _currentUserTranscript = '';

    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Microphone permission is required'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
      return;
    }

    if (_isModelSpeaking) {
      await _audio.stopPlayback();
      setState(() {
        _isModelSpeaking = false;
        if (_messages.isNotEmpty &&
            _messages.last.role == MessageRole.assistant &&
            _messages.last.isStreaming) {
          _messages.last.isStreaming = false;
        }
        _currentAssistantText = '';
      });
    }

    _audio.onAudioChunk = (chunk) {
      _gemini.sendAudio(chunk);
    };

    _audioLevelSub?.cancel();
    _audioLevelSub = _audio.onAudioLevel.listen((level) {
      if (mounted) {
        setState(() {
          _audioLevel = level;
        });
      }
    });

    try {
      await _audio.startRecording();
      // Create voice message immediately so transcriptions can update it
      final convService = context.read<ConversationService>();
      final msg = Message(role: MessageRole.user, text: '', isVoice: true);
      setState(() {
        _isRecording = true;
        _messages.add(msg);
      });
      convService.addMessage(_conversation.id, msg);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start recording: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    await _audio.stopRecording();
    _audioLevelSub?.cancel();

    setState(() {
      _isRecording = false;
      _audioLevel = 0.0;
    });

    // Note: Do NOT send turn_complete for realtime_input audio.
    // Both Gemini and VolcEngine detect end-of-speech automatically via VAD.
    // Voice message was already added in _startRecording.
  }

  // ─── Text input ───

  void _sendTextMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    if (_connectionState != GeminiConnectionState.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Not connected yet. Please wait...'),
          backgroundColor: AppTheme.accent,
        ),
      );
      return;
    }

    if (_isModelSpeaking) {
      _audio.stopPlayback();
      setState(() {
        _isModelSpeaking = false;
        if (_messages.isNotEmpty &&
            _messages.last.role == MessageRole.assistant &&
            _messages.last.isStreaming) {
          _messages.last.isStreaming = false;
        }
        _currentAssistantText = '';
      });
    }

    final msg = Message(role: MessageRole.user, text: text);
    setState(() {
      _messages.add(msg);
    });
    _textController.clear();
    context.read<ConversationService>().addMessage(_conversation.id, msg);
    _scrollToBottom();

    _gemini.sendTextMessage(text);
  }

  // ─── Helpers ───

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (_isRecording) {
        _stopRecording();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stateSub?.cancel();
    _audioSub?.cancel();
    _transcriptSub?.cancel();
    _userTranscriptSub?.cancel();
    _audioLevelSub?.cancel();
    _modelTurnTimer?.cancel();
    _gemini.dispose();
    _audio.dispose();
    _scrollController.dispose();
    _textController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  // ─── Build ───

  @override
  Widget build(BuildContext context) {
    // When keyboard appears, scroll to bottom
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    if (bottomInset > 0) {
      _scrollToBottom();
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      resizeToAvoidBottomInset: true,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // Error banner
          if (_errorMessage != null) _buildErrorBanner(),

          // Transcript area
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMd),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) =>
                        TranscriptBubble(
                          message: _messages[index],
                          audioService: _audio,
                        ),
                  ),
          ),

          // AI speaking indicator
          if (_isModelSpeaking)
            Container(
              padding: const EdgeInsets.symmetric(
                vertical: AppTheme.spacingSm,
                horizontal: AppTheme.spacingMd,
              ),
              child: AISpeakingIndicator(isSpeaking: _isModelSpeaking),
            ),

          // Recording visualizer
          if (_isRecording)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingSm),
              child: AudioVisualizer(
                level: _audioLevel,
                isActive: true,
                size: 100,
                color: AppTheme.danger,
              ),
            ),

          // Bottom input bar
          _buildBottomBar(),
        ],
      ),
    );
  }

  void _startNewChat() {
    final convService = context.read<ConversationService>();
    setState(() {
      _conversation = convService.startNew(
        scenarioId: widget.scenario.id,
        scenarioTitle: widget.scenario.title,
      );
      _messages.clear();
      _currentAssistantText = '';
    });
    // Reconnect with fresh context
    _gemini.disconnect();
    _initConnection();
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppTheme.surface,
      foregroundColor: AppTheme.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      leading: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.arrow_back_rounded, size: 22),
      ),
      actions: [
        if (_messages.isNotEmpty)
          IconButton(
            onPressed: _startNewChat,
            tooltip: 'New conversation',
            icon: const Icon(Icons.refresh_rounded, size: 22),
          ),
      ],
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primaryMuted,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            alignment: Alignment.center,
            child: Text(widget.scenario.icon, style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: AppTheme.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.scenario.title,
                  style: AppTheme.headingSm.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 1),
                _buildConnectionStatus(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionStatus() {
    Color color;
    String text;
    switch (_connectionState) {
      case GeminiConnectionState.connected:
        color = AppTheme.success;
        text = 'Connected';
      case GeminiConnectionState.connecting:
        color = AppTheme.accent;
        text = 'Connecting...';
      case GeminiConnectionState.error:
        color = AppTheme.danger;
        text = 'Error';
      case GeminiConnectionState.disconnected:
        color = AppTheme.textMuted;
        text = 'Disconnected';
    }

    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(text, style: AppTheme.caption.copyWith(fontSize: 11)),
      ],
    );
  }

  Widget _buildErrorBanner() {
    return GestureDetector(
      onTap: _initConnection,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMd,
          vertical: AppTheme.spacingMd - 4,
        ),
        decoration: BoxDecoration(
          color: AppTheme.dangerSurface,
          border: Border(
            bottom: BorderSide(color: AppTheme.danger.withValues(alpha: 0.15)),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.danger, size: 18),
            const SizedBox(width: AppTheme.spacingSm),
            Expanded(
              child: Text(
                _errorMessage!,
                style: AppTheme.bodySm.copyWith(
                  color: AppTheme.danger,
                  fontSize: 13,
                ),
              ),
            ),
            Icon(Icons.refresh_rounded, color: AppTheme.danger, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingXl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Scenario icon in a circle
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.primaryMuted,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                widget.scenario.icon,
                style: const TextStyle(fontSize: 36),
              ),
            ),
            const SizedBox(height: AppTheme.spacingLg),
            Text(
              'Ready to practice!',
              style: AppTheme.headingMd.copyWith(
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: AppTheme.spacingSm),
            Text(
              'Tap the mic to speak, or type a message below.\nAI will respond with voice and text.',
              textAlign: TextAlign.center,
              style: AppTheme.bodySm.copyWith(
                color: AppTheme.textMuted,
                height: 1.6,
              ),
            ),
            const SizedBox(height: AppTheme.spacingXl),
            // Quick tip
            Container(
              padding: const EdgeInsets.all(AppTheme.spacingMd),
              decoration: BoxDecoration(
                color: AppTheme.accentSurface.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('💡', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: AppTheme.spacingSm),
                  Text(
                    'Tip: Speak naturally. AI will\ngently correct pronunciation.',
                    style: AppTheme.bodySm.copyWith(
                      fontSize: 13,
                      color: AppTheme.accent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppTheme.spacingMd,
        AppTheme.spacingMd - 4,
        AppTheme.spacingMd,
        AppTheme.spacingMd - 4 + bottomPadding,
      ),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Mic button
          _buildMicButton(),
          const SizedBox(width: AppTheme.spacingSm),
          // Text field
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: AppTheme.backgroundAlt,
                borderRadius: BorderRadius.circular(AppTheme.radiusXl),
              ),
              child: TextField(
                controller: _textController,
                focusNode: _textFocusNode,
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendTextMessage(),
                enabled: !_isRecording,
                decoration: InputDecoration(
                  hintText: _isRecording ? 'Recording...' : 'Type in English...',
                  hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 15),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                style: const TextStyle(
                  fontSize: 15,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppTheme.spacingSm),
          // Send button
          _buildSendButton(),
        ],
      ),
    );
  }

  Widget _buildMicButton() {
    final isConnected = _connectionState == GeminiConnectionState.connected;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _toggleRecording,
        borderRadius: BorderRadius.circular(24),
        splashColor: (_isRecording ? AppTheme.danger : AppTheme.primary)
            .withValues(alpha: 0.2),
        highlightColor: (_isRecording ? AppTheme.danger : AppTheme.primary)
            .withValues(alpha: 0.1),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isRecording
                ? AppTheme.danger
                : (isConnected ? AppTheme.primary : AppTheme.backgroundAlt),
            boxShadow: _isRecording
                ? [
                    BoxShadow(
                      color: AppTheme.danger.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
            color: _isRecording || isConnected ? Colors.white : AppTheme.textMuted,
            size: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildSendButton() {
    final hasText = _textController.text.trim().isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _sendTextMessage,
        borderRadius: BorderRadius.circular(24),
        splashColor: AppTheme.primary.withValues(alpha: 0.2),
        highlightColor: AppTheme.primary.withValues(alpha: 0.1),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hasText ? AppTheme.primary : AppTheme.backgroundAlt,
          ),
          child: Icon(
            Icons.send_rounded,
            color: hasText ? Colors.white : AppTheme.textMuted,
            size: 20,
          ),
        ),
      ),
    );
  }
}
