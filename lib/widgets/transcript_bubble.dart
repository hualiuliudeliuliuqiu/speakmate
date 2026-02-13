import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../models/message.dart';
import '../services/audio_service.dart';
import '../services/storage_service.dart';

class TranscriptBubble extends StatefulWidget {
  final Message message;
  final AudioService? audioService;
  /// For standard mode: callback to replay via TTS
  final VoidCallback? onTtsReplay;

  const TranscriptBubble({
    super.key,
    required this.message,
    this.audioService,
    this.onTtsReplay,
  });

  @override
  State<TranscriptBubble> createState() => _TranscriptBubbleState();
}

class _TranscriptBubbleState extends State<TranscriptBubble>
    with SingleTickerProviderStateMixin {
  bool _isReplaying = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  StreamSubscription<bool>? _replaySub;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Listen to replay state changes from AudioService
    if (widget.audioService != null) {
      _replaySub = widget.audioService!.onReplayStateChanged.listen((playing) {
        if (!mounted) return;
        // Only react if we initiated the replay
        if (_isReplaying && !playing) {
          _pulseController.stop();
          _pulseController.reset();
          setState(() => _isReplaying = false);
        }
      });
    }
  }

  @override
  void dispose() {
    _replaySub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _onReplay() async {
    if (_isReplaying) return;

    if (widget.audioService != null) {
      setState(() => _isReplaying = true);
      _pulseController.repeat(reverse: true);
      // Don't await — the stream listener handles completion
      widget.audioService!.replayAudio(widget.message.id);
    } else if (widget.onTtsReplay != null) {
      widget.onTtsReplay!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isUser = message.role == MessageRole.user;
    final isAssistant = message.role == MessageRole.assistant;
    final hasNativeAudio = isAssistant &&
        !message.isStreaming &&
        widget.audioService != null &&
        widget.audioService!.hasAudio(message.id);
    final hasTtsReplay = isAssistant &&
        !message.isStreaming &&
        widget.onTtsReplay != null;
    final canReplay = hasNativeAudio || hasTtsReplay;
    final storage = context.read<StorageService>();

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMd,
        vertical: AppTheme.spacingXs,
      ),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            _buildAiAvatar(storage),
            const SizedBox(width: AppTheme.spacingSm),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? AppTheme.primary : AppTheme.surface,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
                boxShadow: AppTheme.shadowSm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    message.text,
                    style: TextStyle(
                      fontSize: 15,
                      color: isUser ? Colors.white : AppTheme.textPrimary,
                      height: 1.5,
                    ),
                  ),
                  if (message.isStreaming)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: isUser
                                  ? Colors.white.withValues(alpha: 0.7)
                                  : AppTheme.primaryLight,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'speaking...',
                            style: TextStyle(
                              fontSize: 11,
                              color: isUser
                                  ? Colors.white.withValues(alpha: 0.6)
                                  : AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (canReplay)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: GestureDetector(
                        onTap: _onReplay,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _isReplaying
                                ? AnimatedBuilder(
                                    animation: _pulseAnimation,
                                    builder: (context, child) => Opacity(
                                      opacity: _pulseAnimation.value,
                                      child: const Icon(
                                        Icons.volume_up_rounded,
                                        size: 16,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                  )
                                : const Icon(
                                    Icons.volume_up_rounded,
                                    size: 16,
                                    color: AppTheme.primaryLight,
                                  ),
                            const SizedBox(width: 4),
                            Text(
                              _isReplaying ? 'Playing...' : 'Replay',
                              style: TextStyle(
                                fontSize: 12,
                                color: _isReplaying
                                    ? AppTheme.primary
                                    : AppTheme.primaryLight,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: AppTheme.spacingSm),
            _buildUserAvatar(storage),
          ],
        ],
      ),
    );
  }

  Widget _buildAiAvatar(StorageService storage) {
    final customPath = storage.aiAvatarPath;
    if (customPath != null && File(customPath).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Image.file(
          File(customPath),
          width: 32,
          height: 32,
          fit: BoxFit.cover,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: Image.asset(
        'assets/images/ai_avatar.jpeg',
        width: 32,
        height: 32,
        fit: BoxFit.cover,
      ),
    );
  }

  Widget _buildUserAvatar(StorageService storage) {
    final customPath = storage.userAvatarPath;
    if (customPath != null && File(customPath).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Image.file(
          File(customPath),
          width: 32,
          height: 32,
          fit: BoxFit.cover,
        ),
      );
    }
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: AppTheme.primarySurface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.person_rounded,
        size: 18,
        color: AppTheme.primary,
      ),
    );
  }
}
