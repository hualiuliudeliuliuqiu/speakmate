import 'package:flutter_tts/flutter_tts.dart';

/// System TTS service for Standard mode
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  Future<void> init() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45); // Slightly slower for learners
    await _tts.setPitch(1.0);

    _tts.setCompletionHandler(() {
      _isPlaying = false;
    });
    _tts.setCancelHandler(() {
      _isPlaying = false;
    });
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    _isPlaying = true;
    await _tts.speak(text);
  }

  Future<void> stop() async {
    _isPlaying = false;
    await _tts.stop();
  }

  void dispose() {
    _tts.stop();
  }
}
