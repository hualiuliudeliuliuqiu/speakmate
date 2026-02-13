import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../prompts/scenarios.dart';
import '../services/storage_service.dart';
import 'chat_screen.dart';
import 'standard_chat_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _openChat(BuildContext context) {
    final storage = context.read<StorageService>();
    if (storage.apiKey.isEmpty) {
      _showApiKeyDialog(context);
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(scenario: defaultScenarios.first),
      ),
    );
  }

  void _showApiKeyDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        ),
        icon: Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            color: AppTheme.accentSurface,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.key_rounded, color: AppTheme.accent, size: 28),
        ),
        title: const Text(
          'API Key Required',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Set your Gemini API key in Settings to start practicing.',
          style: AppTheme.bodySm.copyWith(color: AppTheme.textSecondary),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _openSettings(context);
            },
            icon: const Icon(Icons.settings_outlined, size: 18),
            label: const Text('Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _openSettings(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingLg),
          child: Column(
            children: [
              // ─── Header ───
              Padding(
                padding: const EdgeInsets.only(
                  top: AppTheme.spacingLg,
                  bottom: AppTheme.spacingMd,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.primary, AppTheme.primaryLight],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      ),
                      child: const Center(
                        child: Text('🎙️', style: TextStyle(fontSize: 22)),
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacingMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('SpeakMate', style: AppTheme.headingLg),
                          const SizedBox(height: 2),
                          Text(
                            'Your AI English Coach',
                            style: AppTheme.caption.copyWith(
                              color: AppTheme.textMuted,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Material(
                      color: AppTheme.backgroundAlt,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        onTap: () => _openSettings(context),
                        child: Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.settings_outlined,
                            color: AppTheme.textSecondary,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ─── Center content: Two mode cards ───
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Native Audio mode
                      _buildModeCard(
                        context,
                        icon: Icons.mic_rounded,
                        gradient: const [AppTheme.primary, Color(0xFF0EA5E9)],
                        title: 'Native Audio',
                        subtitle: 'AI hears your accent & pronunciation',
                        tags: const ['🎯 Pronunciation', '⚡ Low latency'],
                        onTap: () => _openChat(context),
                      ),
                      const SizedBox(height: AppTheme.spacingMd),
                      // Standard mode
                      _buildModeCard(
                        context,
                        icon: Icons.chat_rounded,
                        gradient: const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        title: 'Standard Chat',
                        subtitle: 'Persistent session, unlimited conversation',
                        tags: const ['💬 Long session', '🔄 Context kept'],
                        onTap: () => _openStandardChat(context),
                      ),
                    ],
                  ),
                ),
              ),

              // ─── Bottom tip ───
              Padding(
                padding: const EdgeInsets.only(bottom: AppTheme.spacingLg),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingMd,
                    vertical: AppTheme.spacingMd - 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accentSurface.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('💡', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: AppTheme.spacingSm),
                      Flexible(
                        child: Text(
                          'Speak naturally. AI hears your accent and gently corrects pronunciation.',
                          style: AppTheme.bodySm.copyWith(
                            fontSize: 13,
                            color: AppTheme.accent,
                          ),
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
    );
  }

  void _openStandardChat(BuildContext context) {
    final storage = context.read<StorageService>();
    if (storage.apiKey.isEmpty) {
      _showApiKeyDialog(context);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StandardChatScreen(scenario: defaultScenarios.first),
      ),
    );
  }

  Widget _buildModeCard(
    BuildContext context, {
    required IconData icon,
    required List<Color> gradient,
    required String title,
    required String subtitle,
    required List<String> tags,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppTheme.spacingLg),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
          boxShadow: [
            BoxShadow(
              color: gradient[0].withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.8),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingMd),
                  Row(
                    children: tags
                        .map((tag) => Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius:
                                    BorderRadius.circular(AppTheme.radiusFull),
                              ),
                              child: Text(
                                tag,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppTheme.spacingMd),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
          ],
        ),
      ),
    );
  }
}
