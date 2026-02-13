import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'services/conversation_service.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load .env file
  await dotenv.load(fileName: '.env');

  // Initialize services
  final storageService = StorageService();
  await storageService.init();

  final conversationService = ConversationService();
  await conversationService.init();

  // Load API key from .env if not set
  if (storageService.apiKey.isEmpty) {
    final envApiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (envApiKey.isNotEmpty) {
      await storageService.setApiKey(envApiKey);
    }
  }

  // Load proxy defaults from .env
  final envProxyHost = dotenv.env['PROXY_HOST'];
  final envProxyPort = dotenv.env['PROXY_PORT'];
  if (envProxyHost != null && envProxyHost.isNotEmpty) {
    if (storageService.proxyHost == '127.0.0.1') {
      await storageService.setProxyHost(envProxyHost);
    }
  }
  if (envProxyPort != null && envProxyPort.isNotEmpty) {
    final port = int.tryParse(envProxyPort);
    if (port != null && storageService.proxyPort == 7897) {
      await storageService.setProxyPort(port);
    }
  }

  runApp(
    MultiProvider(
      providers: [
        Provider<StorageService>.value(value: storageService),
        Provider<ConversationService>.value(value: conversationService),
      ],
      child: const SpeakMateApp(),
    ),
  );
}
