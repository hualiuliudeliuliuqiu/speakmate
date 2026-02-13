import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/message.dart';

class TranscriptBubble extends StatelessWidget {
  final Message message;

  const TranscriptBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;

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
            // AI avatar
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primary, AppTheme.primaryLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              alignment: Alignment.center,
              child: const Text('🎯', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(width: AppTheme.spacingSm),
          ],
          // Bubble
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
                  Text(
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
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: AppTheme.spacingSm),
            // User avatar
            Container(
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
            ),
          ],
        ],
      ),
    );
  }
}
