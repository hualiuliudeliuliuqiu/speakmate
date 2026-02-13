import 'dart:math';

import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Pulsing ring visualizer for mic recording
class AudioVisualizer extends StatefulWidget {
  final double level; // 0.0 to 1.0
  final bool isActive;
  final Color color;
  final double size;

  const AudioVisualizer({
    super.key,
    required this.level,
    this.isActive = false,
    this.color = AppTheme.primary,
    this.size = 120,
  });

  @override
  State<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<AudioVisualizer>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void didUpdateWidget(AudioVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isActive && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final pulseScale = widget.isActive
            ? 1.0 + (_pulseController.value * 0.1) + (widget.level * 0.25)
            : 1.0;

        return SizedBox(
          width: widget.size * 1.2,
          height: widget.size * 0.8,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer ring
              if (widget.isActive)
                Transform.scale(
                  scale: pulseScale * 1.15,
                  child: Container(
                    width: widget.size * 0.65,
                    height: widget.size * 0.65,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.color.withValues(alpha: 0.12),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              // Inner filled circle
              Transform.scale(
                scale: pulseScale,
                child: Container(
                  width: widget.size * 0.55,
                  height: widget.size * 0.55,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: widget.isActive ? 0.15 : 0.05),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.mic_rounded,
                      size: widget.size * 0.25,
                      color: widget.color,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Animated bars for AI speaking indicator
class AISpeakingIndicator extends StatefulWidget {
  final bool isSpeaking;
  final Color color;

  const AISpeakingIndicator({
    super.key,
    required this.isSpeaking,
    this.color = AppTheme.primary,
  });

  @override
  State<AISpeakingIndicator> createState() => _AISpeakingIndicatorState();
}

class _AISpeakingIndicatorState extends State<AISpeakingIndicator>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(5, (i) {
      return AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 300 + _random.nextInt(400)),
      );
    });
    // Start animation immediately if already speaking
    if (widget.isSpeaking) {
      for (final c in _controllers) {
        c.repeat(reverse: true);
      }
    }
  }

  @override
  void didUpdateWidget(AISpeakingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSpeaking) {
      for (final c in _controllers) {
        if (!c.isAnimating) c.repeat(reverse: true);
      }
    } else {
      for (final c in _controllers) {
        c.stop();
        c.value = 0;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isSpeaking) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primaryMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.volume_up_rounded, color: widget.color, size: 16),
          const SizedBox(width: 8),
          ...List.generate(5, (i) {
            return AnimatedBuilder(
              animation: _controllers[i],
              builder: (context, child) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  width: 3,
                  height: 6 + (_controllers[i].value * 12),
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              },
            );
          }),
          const SizedBox(width: 8),
          Text(
            'AI speaking',
            style: TextStyle(
              color: widget.color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
