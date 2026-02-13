import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/scenario.dart';
import '../services/conversation_service.dart';
import '../services/gemini_text_service.dart';
import '../services/storage_service.dart';
import '../services/tts_service.dart';
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
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();

  late Conversation _conversation;
  final List<Message> _messages = [];
  bool _isLoading = false;
  String? _errorMessage;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
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

    // Initialize TTS
    _tts.init();

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
      // Call Gemini API
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

      // Speak the response
      _tts.speak(responseText);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to get response: $e';
      });
    }
  }

  // ─── TTS replay ───

  void _replayTts(String text) {
    _tts.stop();
    _tts.speak(text);
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
    _scrollController.dispose();
    _textController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  // ─── Build ───

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
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
                      if (msg.role == MessageRole.assistant) {
                        return GestureDetector(
                          onTap: () => _replayTts(msg.text),
                          child: TranscriptBubble(message: msg),
                        );
                      }
                      return TranscriptBubble(message: msg);
                    },
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
                enabled: !_isLoading,
                decoration: InputDecoration(
                  hintText:
                      _isLoading ? 'Waiting for response...' : 'Type in English...',
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
    return Tooltip(
      message: 'Voice input coming soon — use text for now',
      child: Container(
        width: 48,
        height: 48,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.backgroundAlt,
        ),
        child: const Icon(
          Icons.mic_rounded,
          color: AppTheme.textMuted,
          size: 24,
        ),
      ),
    );
  }

  Widget _buildSendButton() {
    return GestureDetector(
      onTap: _sendTextMessage,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _isLoading
              ? AppTheme.backgroundAlt
              : const Color(0xFF6366F1), // Indigo to match mode card
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
            : const Icon(
                Icons.send_rounded,
                color: Colors.white,
                size: 20,
              ),
      ),
    );
  }
}
