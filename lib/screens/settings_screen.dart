import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../config/constants.dart';
import '../config/theme.dart';
import '../services/storage_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _apiKeyController;
  late TextEditingController _proxyHostController;
  late TextEditingController _proxyPortController;
  bool _proxyEnabled = true;
  String _selectedVoice = AppConstants.defaultVoice;
  bool _obscureApiKey = true;

  @override
  void initState() {
    super.initState();
    final storage = context.read<StorageService>();
    _apiKeyController = TextEditingController(text: storage.apiKey);
    _proxyHostController = TextEditingController(text: storage.proxyHost);
    _proxyPortController =
        TextEditingController(text: storage.proxyPort.toString());
    _proxyEnabled = storage.proxyEnabled;
    _selectedVoice = storage.voiceName;
  }

  Future<void> _save() async {
    final storage = context.read<StorageService>();
    await storage.setApiKey(_apiKeyController.text.trim());
    await storage.setProxyHost(_proxyHostController.text.trim());
    await storage.setProxyPort(
      int.tryParse(_proxyPortController.text.trim()) ??
          AppConstants.defaultProxyPort,
    );
    await storage.setProxyEnabled(_proxyEnabled);
    await storage.setVoiceName(_selectedVoice);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Settings saved'),
            ],
          ),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _proxyHostController.dispose();
    _proxyPortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        title: const Text('Settings', style: AppTheme.headingSm),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text(
              'Save',
              style: TextStyle(
                color: AppTheme.primary,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        children: [
          // ─── API Key Section ───
          _buildSectionHeader('API Configuration', Icons.key_rounded),
          const SizedBox(height: AppTheme.spacingSm),
          _buildCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Gemini API Key', style: AppTheme.headingSm.copyWith(fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  'Get yours free at aistudio.google.com',
                  style: AppTheme.caption,
                ),
                const SizedBox(height: AppTheme.spacingMd),
                TextField(
                  controller: _apiKeyController,
                  obscureText: _obscureApiKey,
                  style: const TextStyle(
                    fontSize: 14,
                    fontFamily: 'monospace',
                    color: AppTheme.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'AIzaSy...',
                    filled: true,
                    fillColor: AppTheme.backgroundAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureApiKey
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 20,
                        color: AppTheme.textMuted,
                      ),
                      onPressed: () =>
                          setState(() => _obscureApiKey = !_obscureApiKey),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppTheme.spacingLg),

          // ─── Proxy Section ───
          _buildSectionHeader('Network Proxy', Icons.vpn_key_rounded),
          const SizedBox(height: AppTheme.spacingSm),
          _buildCard(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Enable Proxy', style: AppTheme.headingSm.copyWith(fontSize: 14)),
                          const SizedBox(height: 2),
                          Text(
                            'Required in mainland China',
                            style: AppTheme.caption,
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: _proxyEnabled,
                      onChanged: (v) => setState(() => _proxyEnabled = v),
                      activeColor: AppTheme.primary,
                    ),
                  ],
                ),
                if (_proxyEnabled) ...[
                  const SizedBox(height: AppTheme.spacingMd),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _proxyHostController,
                          style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'Host',
                            labelStyle: AppTheme.caption,
                            filled: true,
                            fillColor: AppTheme.backgroundAlt,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppTheme.spacingSm),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _proxyPortController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'Port',
                            labelStyle: AppTheme.caption,
                            filled: true,
                            fillColor: AppTheme.backgroundAlt,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: AppTheme.spacingLg),

          // ─── Voice Section ───
          _buildSectionHeader('AI Voice', Icons.record_voice_over_rounded),
          const SizedBox(height: AppTheme.spacingSm),
          _buildCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose how SpeakMate sounds',
                  style: AppTheme.caption,
                ),
                const SizedBox(height: AppTheme.spacingMd),
                Wrap(
                  spacing: AppTheme.spacingSm,
                  runSpacing: AppTheme.spacingSm,
                  children: AppConstants.availableVoices.map((voice) {
                    final isSelected = voice == _selectedVoice;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedVoice = voice),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.primary : AppTheme.backgroundAlt,
                          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                          border: Border.all(
                            color: isSelected
                                ? AppTheme.primary
                                : AppTheme.border,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          voice,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            color: isSelected ? Colors.white : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppTheme.spacingLg),

          // ─── Avatar Section ───
          _buildSectionHeader('Avatars', Icons.face_rounded),
          const SizedBox(height: AppTheme.spacingSm),
          _buildCard(
            child: Column(
              children: [
                _buildAvatarRow(
                  label: 'AI Avatar',
                  currentPath: context.read<StorageService>().aiAvatarPath,
                  defaultWidget: ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    child: Image.asset(
                      'assets/images/ai_avatar.jpeg',
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                    ),
                  ),
                  onPick: () => _pickAvatar(isAi: true),
                ),
                const Divider(height: 24),
                _buildAvatarRow(
                  label: 'My Avatar',
                  currentPath: context.read<StorageService>().userAvatarPath,
                  defaultWidget: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.primarySurface,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.person_rounded, size: 24, color: AppTheme.primary),
                  ),
                  onPick: () => _pickAvatar(isAi: false),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppTheme.spacingXl),

          // ─── About ───
          Center(
            child: Column(
              children: [
                Text(
                  'SpeakMate v1.0',
                  style: AppTheme.caption.copyWith(color: AppTheme.textMuted),
                ),
                const SizedBox(height: 4),
                Text(
                  'Powered by Gemini Live API',
                  style: AppTheme.caption.copyWith(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppTheme.spacingXl),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.primary),
        const SizedBox(width: AppTheme.spacingSm),
        Text(
          title,
          style: AppTheme.label.copyWith(
            color: AppTheme.primary,
            fontSize: 12,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        boxShadow: AppTheme.shadowSm,
      ),
      child: child,
    );
  }

  Widget _buildAvatarRow({
    required String label,
    required String? currentPath,
    required Widget defaultWidget,
    required VoidCallback onPick,
  }) {
    final hasCustom = currentPath != null && File(currentPath).existsSync();

    return Row(
      children: [
        // Avatar preview
        hasCustom
            ? ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                child: Image.file(
                  File(currentPath),
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  // Bust image cache by using the file's modified time
                  cacheWidth: 96,
                ),
              )
            : defaultWidget,
        const SizedBox(width: AppTheme.spacingMd),
        // Label
        Expanded(
          child: Text(label, style: AppTheme.headingSm.copyWith(fontSize: 14)),
        ),
        // Pick button
        TextButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.image_rounded, size: 16),
          label: const Text('Change'),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.primary,
            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  Future<void> _pickAvatar({required bool isAi}) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 256,
      maxHeight: 256,
      imageQuality: 85,
    );
    if (image == null) return;

    // Copy with unique name to bust image cache
    final appDir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final fileName = isAi ? 'ai_avatar_$ts.jpg' : 'user_avatar_$ts.jpg';
    final savedFile = await File(image.path).copy('${appDir.path}/$fileName');

    final storage = context.read<StorageService>();

    // Delete old file
    final oldPath = isAi ? storage.aiAvatarPath : storage.userAvatarPath;
    if (oldPath != null) {
      try { await File(oldPath).delete(); } catch (_) {}
    }

    if (isAi) {
      await storage.setAiAvatarPath(savedFile.path);
    } else {
      await storage.setUserAvatarPath(savedFile.path);
    }

    // Clear Flutter image cache
    imageCache.clear();
    imageCache.clearLiveImages();
    setState(() {});
  }
}
