import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/scenario.dart';
import '../services/audio_service.dart';
import '../services/conversation_service.dart';
import '../services/gemini_text_service.dart';
import '../services/storage_service.dart';
import '../services/tts_service.dart';
import '../widgets/audio_visualizer.dart';
import '../widgets/transcript_bubble.dart';

class StandardChatScreen extends StatefulWidget {
  final Scenario scenario;

  const StandardChatScreen({super.key, required this.scenario});

  @override
  State<StandardChatScreen> createState() => _StandardChatScreenState();
}

class _StandardChatScreenState extends State<StandardChatScreen> {
  final GeminiTextService _gemini = GeminiTextService();
  final TtsService _tts = TtsService();
  final AudioService _audio = AudioService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();

  late Conversation _conversation;
  final List<Message> _messages = [];
  bool _isLoading = false;
  bool _isRecording = false;
  bool _isSpeaking = false;
  double _audioLevel = 0.0;
  String? _errorMessage;
  bool _isReady = false;

  // Collect PCM data during recording
  final List<int> _recordingBuffer = [];
  StreamSubscription<double>? _audioLevelSub;
  StreamSubscription<bool>? _ttsSpeakingSub;

  @override
  void initState() {
    super.initState();
    _textController.addListener(() {
      setState(() {}); // rebuild to update send button color
    });
    _initServices();
  }

  void _initServices() {
    final storage = context.read<StorageService>();
    final apiKey = storage.apiKey;

    if (apiKey.isEmpty) {
      setState(() {
        _errorMessage = 'API key not configured. Please check Settings.';
      });
      return;
    }

    // Configure Gemini text service
    final scenarioContext = widget.scenario.systemPromptAddition;
    _gemini.configure(
      apiKey: apiKey,
      proxyHost: storage.proxyHost,
      proxyPort: storage.proxyPort,
      proxyEnabled: storage.proxyEnabled,
      systemPromptAddition:
          scenarioContext.isNotEmpty ? scenarioContext : null,
    );

    // Initialize Gemini TTS with shared AudioService for streaming playback
    _tts.setAudioService(_audio);
    _tts.configure(
      apiKey: apiKey,
      proxyHost: storage.proxyHost,
      proxyPort: storage.proxyPort,
      proxyEnabled: storage.proxyEnabled,
      voiceName: storage.voiceName,
    );

    // Listen to TTS playing state
    _ttsSpeakingSub = _tts.onPlayingChanged.listen((playing) {
      if (mounted) setState(() => _isSpeaking = playing);
    });

    // Load conversation
    _loadConversation();

    setState(() {
      _isReady = true;
    });
  }

  void _loadConversation() {
    final convService = context.read<ConversationService>();
    // Use a different scenarioId prefix so standard mode has its own conversations
    _conversation = convService.getOrCreate(
      scenarioId: 'standard_${widget.scenario.id}',
      scenarioTitle: widget.scenario.title,
    );

    // Restore previous messages
    if (_conversation.messages.isNotEmpty) {
      _messages.addAll(_conversation.messages);
      // Restore history in the text service so API has context
      _gemini.restoreHistory(_conversation.messages);
      // Preload TTS audio cache
      final assistantIds = _messages
          .where((m) => m.role == MessageRole.assistant)
          .map((m) => m.id)
          .toList();
      _tts.preloadAudioCache(assistantIds).then((_) {
        if (mounted) setState(() {});
      });
      // Scroll to bottom after frame
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  // ─── Send message ───

  Future<void> _sendTextMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isLoading) return;

    if (!_isReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Service not ready. Please check settings.'),
          backgroundColor: AppTheme.accent,
        ),
      );
      return;
    }

    // Grab the service reference before any async gaps
    final convService = context.read<ConversationService>();

    // Stop any current TTS playback
    await _tts.stop();

    // Add user message
    final userMsg = Message(role: MessageRole.user, text: text);
    setState(() {
      _messages.add(userMsg);
      _isLoading = true;
      _errorMessage = null;
    });
    _textController.clear();
    _scrollToBottom();

    // Persist user message
    await convService.addMessage(_conversation.id, userMsg);

    try {
      // Call Gemini text API
      final responseText = await _gemini.sendMessage(text);

      if (!mounted) return;

      // Add assistant message
      final assistantMsg =
          Message(role: MessageRole.assistant, text: responseText);
      setState(() {
        _messages.add(assistantMsg);
        _isLoading = false;
      });
      _scrollToBottom();

      // Persist assistant message
      await convService.addMessage(_conversation.id, assistantMsg);

      // Speak via Live API WebSocket — real-time streaming like Native Audio
      _tts.speak(responseText, messageId: assistantMsg.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to get response: $e';
      });
    }
  }

  // ─── Voice input ───

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecordingAndSend();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (_isLoading || !_isReady) return;

    _textFocusNode.unfocus();

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

    // Stop any TTS playback
    await _tts.stop();

    _recordingBuffer.clear();
    _audio.onAudioChunk = (chunk) {
      _recordingBuffer.addAll(chunk);
    };

    _audioLevelSub?.cancel();
    _audioLevelSub = _audio.onAudioLevel.listen((level) {
      if (mounted) setState(() => _audioLevel = level);
    });

    try {
      await _audio.startRecording();
      setState(() => _isRecording = true);
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

  Future<void> _stopRecordingAndSend() async {
    await _audio.stopRecording();
    _audioLevelSub?.cancel();

    final pcmData = Uint8List.fromList(_recordingBuffer);
    _recordingBuffer.clear();

    setState(() {
      _isRecording = false;
      _audioLevel = 0.0;
    });

    if (pcmData.isEmpty) return;

    // Calculate duration for display
    final durationSec = pcmData.length / (16000 * 2); // 16kHz, 16-bit
    final durStr = durationSec >= 60
        ? '${(durationSec / 60).floor()}:${(durationSec % 60).floor().toString().padLeft(2, '0')}'
        : '${durationSec.toStringAsFixed(0)}s';

    final convService = context.read<ConversationService>();

    // Add user voice message (will be updated with transcription)
    final userMsg = Message(
      role: MessageRole.user,
      text: '',
      isVoice: true,
    );
    setState(() {
      _messages.add(userMsg);
      _isLoading = true;
      _errorMessage = null;
    });
    _scrollToBottom();
    await convService.addMessage(_conversation.id, userMsg);

    try {
      // Run transcription and AI response in parallel
      final results = await Future.wait([
        _gemini.sendAudioMessage(pcmData),
        _gemini.transcribeAudio(pcmData).then((v) => v ?? ''),
      ]);

      final responseText = results[0];
      final transcription = results[1];

      if (!mounted) return;

      // Update user voice message with transcription
      if (transcription.isNotEmpty) {
        setState(() {
          userMsg.text = transcription;
        });
        convService.updateLastUserMessage(_conversation.id, transcription);
      } else {
        // Fallback: show duration if transcription failed
        setState(() {
          userMsg.text = durStr;
        });
        convService.updateLastUserMessage(_conversation.id, durStr);
      }

      final assistantMsg =
          Message(role: MessageRole.assistant, text: responseText);
      setState(() {
        _messages.add(assistantMsg);
        _isLoading = false;
      });
      _scrollToBottom();

      await convService.addMessage(_conversation.id, assistantMsg);

      // Speak the response
      _tts.speak(responseText, messageId: assistantMsg.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to get response: $e';
      });
    }
  }

  // ─── New chat ───

  void _startNewChat() {
    _tts.stop();
    final convService = context.read<ConversationService>();
    setState(() {
      _conversation = convService.startNew(
        scenarioId: 'standard_${widget.scenario.id}',
        scenarioTitle: widget.scenario.title,
      );
      _messages.clear();
      _errorMessage = null;
    });
    _gemini.clearHistory();
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
  void dispose() {
    _tts.dispose();
    _gemini.dispose();
    _audio.dispose();
    _audioLevelSub?.cancel();
    _ttsSpeakingSub?.cancel();
    _scrollController.dispose();
    _textController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  // ─── Build ───

  @override
  Widget build(BuildContext context) {
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
                    padding: const EdgeInsets.symmetric(
                        vertical: AppTheme.spacingMd),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      return TranscriptBubble(
                        message: msg,
                        ttsService: msg.role == MessageRole.assistant
                            ? _tts
                            : null,
                      );
                    },
                  ),
          ),

          // AI speaking indicator
          if (_isSpeaking)
            Container(
              padding: const EdgeInsets.symmetric(
                vertical: AppTheme.spacingSm,
                horizontal: AppTheme.spacingMd,
              ),
              child: AISpeakingIndicator(isSpeaking: _isSpeaking),
            ),

          // Recording visualizer
          if (_isRecording)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingSm),
              child: AudioVisualizer(
                level: _audioLevel,
                isActive: true,
                size: 100,
                color: const Color(0xFF6366F1),
              ),
            ),

          // Loading indicator
          if (_isLoading)
            Container(
              padding: const EdgeInsets.symmetric(
                vertical: AppTheme.spacingSm,
                horizontal: AppTheme.spacingMd,
              ),
              child: Row(
                children: [
                  const SizedBox(width: 40), // align with AI avatar
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primaryLight,
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacingSm),
                  Text(
                    'Thinking...',
                    style: AppTheme.caption.copyWith(
                      color: AppTheme.primaryLight,
                    ),
                  ),
                ],
              ),
            ),

          // Bottom input bar
          _buildBottomBar(),
        ],
      ),
    );
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
              color: const Color(0xFFEEF2FF), // Indigo 50 for standard mode
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            alignment: Alignment.center,
            child: Text(widget.scenario.icon,
                style: const TextStyle(fontSize: 18)),
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
                _buildStatusIndicator(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator() {
    final color = _isReady ? AppTheme.success : AppTheme.textMuted;
    final text = _isReady ? 'Standard' : 'Not configured';

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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMd,
        vertical: AppTheme.spacingMd - 4,
      ),
      decoration: BoxDecoration(
        color: AppTheme.dangerSurface,
        border: Border(
          bottom:
              BorderSide(color: AppTheme.danger.withValues(alpha: 0.15)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              color: AppTheme.danger, size: 18),
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
        ],
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
              decoration: const BoxDecoration(
                color: Color(0xFFEEF2FF), // Indigo 50
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
              'Ready to chat!',
              style: AppTheme.headingMd.copyWith(
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: AppTheme.spacingSm),
            Text(
              'Type a message below to start practicing.\n'
              'AI will respond with text and voice.',
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
                    'Tip: Tap any AI message\nto hear it again!',
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
          // Mic button (placeholder for now)
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
                enabled: !_isLoading && !_isRecording,
                decoration: InputDecoration(
                  hintText: _isRecording
                      ? 'Recording...'
                      : (_isLoading ? 'Waiting for response...' : 'Type in English...'),
                  hintStyle: const TextStyle(
                      color: AppTheme.textMuted, fontSize: 15),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _toggleRecording,
        borderRadius: BorderRadius.circular(24),
        splashColor: const Color(0xFF6366F1).withValues(alpha: 0.2),
        highlightColor: const Color(0xFF6366F1).withValues(alpha: 0.1),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isRecording
                ? const Color(0xFF6366F1)
                : (_isReady ? AppTheme.backgroundAlt : AppTheme.backgroundAlt),
            boxShadow: _isRecording
                ? [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
            color: _isRecording ? Colors.white : (_isReady ? const Color(0xFF6366F1) : AppTheme.textMuted),
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
        splashColor: const Color(0xFF6366F1).withValues(alpha: 0.2),
        highlightColor: const Color(0xFF6366F1).withValues(alpha: 0.1),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isLoading
                ? AppTheme.backgroundAlt
                : (hasText ? const Color(0xFF6366F1) : AppTheme.backgroundAlt),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.textMuted,
                  ),
                )
              : Icon(
                  Icons.send_rounded,
                  color: hasText ? Colors.white : AppTheme.textMuted,
                  size: 20,
                ),
        ),
      ),
    );
  }
}
