import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

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

/// Full-screen voice call UI for VolcEngine realtime dialogue.
/// Continuous bidirectional audio — like a phone call.
class VoiceCallScreen extends StatefulWidget {
  final Scenario scenario;

  const VoiceCallScreen({super.key, required this.scenario});

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late LiveServiceWrapper _service;
  final AudioService _audio = AudioService();
  late Conversation _conversation;

  GeminiConnectionState _connectionState = GeminiConnectionState.disconnected;
  bool _isRecording = false;
  bool _isMuted = false;
  bool _isModelSpeaking = false;
  bool _isSpeakerPlaying = false; // true while speaker may still be outputting audio
  double _audioLevel = 0.0;
  String _userText = '';
  String _assistantText = '';
  String _statusText = 'Connecting...';
  Duration _callDuration = Duration.zero;
  Timer? _durationTimer;

  // Conversation messages for persistence
  final List<Message> _messages = [];

  StreamSubscription<GeminiConnectionState>? _stateSub;
  StreamSubscription<List<int>>? _audioSub;
  StreamSubscription<String>? _transcriptSub;
  StreamSubscription<String>? _userTranscriptSub;
  StreamSubscription<double>? _audioLevelSub;
  StreamSubscription<void>? _ttsEndedSub;
  Timer? _speakerCooldownTimer;

  // Pulse animation for the avatar
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _initConversation();
    _initCall();
  }

  void _initConversation() {
    final convService = context.read<ConversationService>();
    _conversation = convService.getOrCreate(
      scenarioId: widget.scenario.id,
      scenarioTitle: widget.scenario.title,
    );
  }

  Future<void> _initCall() async {
    final storage = context.read<StorageService>();
    _service = LiveServiceWrapper(storage.aiProvider);

    final contextSummary = _conversation.buildContextSummary();
    final scenarioContext = widget.scenario.systemPromptAddition;
    final fullAddition = [scenarioContext, contextSummary]
        .where((s) => s.isNotEmpty)
        .join('\n\n');

    _service.configure(
      storage: storage,
      systemPromptAddition: fullAddition.isNotEmpty ? fullAddition : null,
    );

    // State changes
    _stateSub = _service.onStateChanged.listen((state) {
      if (!mounted) return;
      setState(() {
        _connectionState = state;
        switch (state) {
          case GeminiConnectionState.connecting:
            _statusText = 'Connecting...';
          case GeminiConnectionState.connected:
            _statusText = 'Connected';
            _startRecording();
            _startDurationTimer();
          case GeminiConnectionState.error:
            _statusText = 'Connection lost';
          case GeminiConnectionState.disconnected:
            _statusText = 'Disconnected';
        }
      });
    });

    // AI audio playback
    _audioSub = _service.onAudioReceived.listen((audioData) {
      if (mounted) {
        setState(() {
          _isModelSpeaking = true;
          _isSpeakerPlaying = true;
        });
        _speakerCooldownTimer?.cancel(); // reset cooldown while audio is flowing
      }
      _audio.addPlaybackData(audioData);
    });

    // TTSEnded: server finished sending audio, but speaker buffer needs ~1.5s to drain
    _ttsEndedSub = _service.onTTSEnded?.listen((_) {
      _speakerCooldownTimer?.cancel();
      _speakerCooldownTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) {
          setState(() {
            _isSpeakerPlaying = false;
            _isModelSpeaking = false;
          });
        }
      });
    });

    // AI text transcript
    _transcriptSub = _service.onTranscriptReceived.listen((text) {
      if (!mounted) return;
      final convService = context.read<ConversationService>();
      setState(() {
        _isModelSpeaking = true;
        _assistantText += text;
      });

      // Update or create assistant message
      if (_messages.isNotEmpty &&
          _messages.last.role == MessageRole.assistant &&
          _messages.last.isStreaming) {
        _messages.last.text = _assistantText;
        convService.updateLastMessage(_conversation.id, _assistantText);
      } else {
        final msg = Message(
          role: MessageRole.assistant,
          text: _assistantText,
          isStreaming: true,
        );
        _messages.add(msg);
        convService.addMessage(_conversation.id, msg);
      }
    });

    // User speech transcript
    _userTranscriptSub = _service.onUserTranscriptReceived.listen((text) {
      if (!mounted) return;
      final convService = context.read<ConversationService>();

      // User is speaking → stop speaker immediately (interruption)
      _speakerCooldownTimer?.cancel();
      if (_isSpeakerPlaying) {
        _audio.stopPlayback();
      }

      setState(() {
        _userText = text; // VolcEngine sends full text (replace)
        _isModelSpeaking = false;
        _isSpeakerPlaying = false;

        // Finalize previous assistant message
        if (_messages.isNotEmpty &&
            _messages.last.role == MessageRole.assistant &&
            _messages.last.isStreaming) {
          _messages.last.isStreaming = false;
          _assistantText = '';
        }
      });

      // Update or create user message
      if (_messages.isNotEmpty &&
          _messages.last.role == MessageRole.user &&
          _messages.last.isVoice &&
          _messages.last.isStreaming) {
        _messages.last.text = _userText;
        convService.updateLastUserMessage(_conversation.id, _userText);
      } else {
        final msg = Message(
          role: MessageRole.user,
          text: _userText,
          isVoice: true,
          isStreaming: true,
        );
        _messages.add(msg);
        convService.addMessage(_conversation.id, msg);
      }
    });

    // Connect
    try {
      await _service.connect();
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusText = 'Failed: $e';
        });
      }
    }
  }

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) return;

    _audio.onAudioChunk = (chunk) {
      // Send silence when:
      // 1. User explicitly muted
      // 2. Speaker is playing AI audio (prevents echo loop)
      if (_isMuted || _isSpeakerPlaying) {
        _service.sendAudio(Uint8List(chunk.length));
      } else {
        _service.sendAudio(chunk);
      }
    };

    _audioLevelSub?.cancel();
    _audioLevelSub = _audio.onAudioLevel.listen((level) {
      if (mounted) setState(() => _audioLevel = level);
    });

    try {
      await _audio.startRecording();
      setState(() => _isRecording = true);
    } catch (e) {
      print('SM_VOLC recording error: $e');
    }
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _callDuration = Duration.zero;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _callDuration += const Duration(seconds: 1);
        });
      }
    });
  }

  Future<void> _endCall() async {
    _durationTimer?.cancel();
    await _audio.stopRecording();
    await _audio.stopPlayback();
    _audioLevelSub?.cancel();

    // Finalize any streaming messages
    for (final msg in _messages) {
      msg.isStreaming = false;
    }

    await _service.disconnect();
    _service.dispose();

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Keep connection alive but mute
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _durationTimer?.cancel();
    _pulseController.dispose();
    _stateSub?.cancel();
    _audioSub?.cancel();
    _transcriptSub?.cancel();
    _userTranscriptSub?.cancel();
    _audioLevelSub?.cancel();
    _ttsEndedSub?.cancel();
    _speakerCooldownTimer?.cancel();
    _audio.stopRecording();
    _audio.stopPlayback();
    _service.disconnect();
    _service.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _connectionState == GeminiConnectionState.connected;
    final scenarioColor =
        AppTheme.scenarioColors[widget.scenario.id.hashCode % AppTheme.scenarioColors.length];

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // ─── Top bar ───
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingMd, vertical: AppTheme.spacingSm),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _endCall,
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: AppTheme.textSecondary,
                  ),
                  const Spacer(),
                  if (isConnected)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.primarySurface,
                        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppTheme.success,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _formatDuration(_callDuration),
                            style: AppTheme.caption.copyWith(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Spacer(),
                  const SizedBox(width: 48), // balance back button
                ],
              ),
            ),

            const Spacer(flex: 2),

            // ─── Avatar + pulse ───
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                final scale = _isModelSpeaking
                    ? _pulseAnimation.value
                    : (_isRecording && _audioLevel > 0.1
                        ? 1.0 + (_audioLevel * 0.15)
                        : 1.0);
                return Transform.scale(
                  scale: scale,
                  child: child,
                );
              },
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: scenarioColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _isModelSpeaking
                        ? scenarioColor
                        : (isConnected ? AppTheme.primary : AppTheme.border),
                    width: 3,
                  ),
                ),
                child: Center(
                  child: Text(
                    widget.scenario.icon,
                    style: const TextStyle(fontSize: 48),
                  ),
                ),
              ),
            ),

            const SizedBox(height: AppTheme.spacingLg),

            // ─── Scenario name ───
            Text(
              widget.scenario.title,
              style: AppTheme.headingMd,
            ),
            const SizedBox(height: AppTheme.spacingXs),
            Text(
              _statusText,
              style: AppTheme.bodySm.copyWith(
                color: isConnected ? AppTheme.success : AppTheme.textMuted,
              ),
            ),

            const Spacer(flex: 1),

            // ─── Live transcript ───
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingXl),
              child: Column(
                children: [
                  // User speech (current)
                  if (_userText.isNotEmpty)
                    _TranscriptLine(
                      label: 'You',
                      text: _userText,
                      color: AppTheme.primary,
                    ),

                  if (_userText.isNotEmpty && _assistantText.isNotEmpty)
                    const SizedBox(height: AppTheme.spacingMd),

                  // AI response (current)
                  if (_assistantText.isNotEmpty)
                    _TranscriptLine(
                      label: 'AI',
                      text: _assistantText,
                      color: scenarioColor,
                    ),

                  if (_userText.isEmpty && _assistantText.isEmpty && isConnected)
                    Text(
                      'Start speaking...',
                      style: AppTheme.bodySm.copyWith(
                        color: AppTheme.textMuted,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),

            const Spacer(flex: 2),

            // ─── Audio level bars ───
            if (isConnected)
              SizedBox(
                height: 40,
                child: _AudioBars(
                  level: _isModelSpeaking ? 0.5 : _audioLevel,
                  isAI: _isModelSpeaking,
                  color: _isModelSpeaking ? scenarioColor : AppTheme.primary,
                ),
              ),

            const Spacer(flex: 1),

            // ─── Controls ───
            Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.spacingXl),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Mute button
                  _CallButton(
                    icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    label: _isMuted ? 'Unmute' : 'Mute',
                    backgroundColor: _isMuted
                        ? AppTheme.textMuted.withValues(alpha: 0.15)
                        : AppTheme.primarySurface,
                    iconColor: _isMuted ? AppTheme.textMuted : AppTheme.primary,
                    onTap: isConnected ? _toggleMute : null,
                  ),

                  // End call button
                  _CallButton(
                    icon: Icons.call_end_rounded,
                    label: 'End',
                    backgroundColor: AppTheme.danger,
                    iconColor: Colors.white,
                    size: 64,
                    onTap: _endCall,
                  ),

                  // Speaker button (placeholder)
                  _CallButton(
                    icon: Icons.volume_up_rounded,
                    label: 'Speaker',
                    backgroundColor: AppTheme.primarySurface,
                    iconColor: AppTheme.primary,
                    onTap: null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Transcript line widget ───

class _TranscriptLine extends StatelessWidget {
  final String label;
  final String text;
  final Color color;

  const _TranscriptLine({
    required this.label,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTheme.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            text,
            style: AppTheme.bodySm.copyWith(
              color: AppTheme.textPrimary,
              height: 1.4,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─── Audio level bars ───

class _AudioBars extends StatelessWidget {
  final double level;
  final bool isAI;
  final Color color;

  const _AudioBars({
    required this.level,
    required this.isAI,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(15, (i) {
        // Create a wave pattern
        final centerDist = (i - 7).abs() / 7.0;
        final baseHeight = 0.2 + (1.0 - centerDist) * 0.8;
        final h = (baseHeight * level * 36).clamp(4.0, 36.0);
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: 4,
          height: h,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.4 + level * 0.6),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}

// ─── Call button widget ───

class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color iconColor;
  final double size;
  final VoidCallback? onTap;

  const _CallButton({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.iconColor,
    this.size = 52,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: size * 0.45),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: AppTheme.caption,
        ),
      ],
    );
  }
}
