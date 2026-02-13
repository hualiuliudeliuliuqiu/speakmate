import 'package:flutter/material.dart';

import 'config/theme.dart';
import 'screens/home_screen.dart';

class SpeakMateApp extends StatelessWidget {
  const SpeakMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SpeakMate',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const HomeScreen(),
    );
  }
}
