/// AI Provider / Engine selection
enum AIProvider {
  gemini('Gemini', 'Google Gemini (via proxy)'),
  volcengine('VolcEngine', '火山引擎 / 豆包'),
  minimax('MiniMax', 'MiniMax / 海螺AI');

  final String displayName;
  final String description;
  const AIProvider(this.displayName, this.description);
}

class AppConstants {
  AppConstants._();

  // Gemini API
  static const String geminiModel = 'models/gemini-2.5-flash-native-audio-latest';
  static const String geminiTextModel = 'gemini-2.5-flash';
  static const String geminiWsBaseUrl =
      'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent';

  // VolcEngine / Doubao API (placeholder URLs — update when keys are ready)
  static const String volcTextModel = 'doubao-pro-256k';
  static const String volcWsBaseUrl = 'wss://openspeech.bytedance.com/api/v3/sauc/bigmodel';
  static const String volcTtsBaseUrl = 'https://openspeech.bytedance.com/api/v1/tts';
  static const String volcTextBaseUrl = 'https://ark.cn-beijing.volces.com/api/v3';

  // MiniMax API (placeholder URLs — update when keys are ready)
  static const String minimaxTextModel = 'abab6.5s-chat';
  static const String minimaxBaseUrl = 'https://api.minimax.chat/v1';
  static const String minimaxRealtimeUrl = 'wss://api.minimax.chat/v1/realtime';

  // Audio config
  static const int inputSampleRate = 16000; // 16kHz for mic input
  static const int outputSampleRate = 24000; // 24kHz for model output
  static const int bitsPerSample = 16;
  static const int numChannels = 1; // mono

  // Default proxy
  static const String defaultProxyHost = '127.0.0.1';
  static const int defaultProxyPort = 7897;

  // Storage keys
  static const String keyApiKey = 'gemini_api_key';
  static const String keyProxyHost = 'proxy_host';
  static const String keyProxyPort = 'proxy_port';
  static const String keyProxyEnabled = 'proxy_enabled';
  static const String keyVoiceName = 'voice_name';

  // Multi-engine storage keys
  static const String keyAIProvider = 'ai_provider';
  static const String keyVolcApiKey = 'volc_api_key';
  static const String keyVolcAppId = 'volc_app_id';
  static const String keyMinimaxApiKey = 'minimax_api_key';
  static const String keyMinimaxGroupId = 'minimax_group_id';

  // Available voices
  static const List<String> availableVoices = [
    'Kore',
    'Charon',
    'Fenrir',
    'Aoede',
    'Puck',
    'Leda',
  ];

  static const String defaultVoice = 'Kore';

  // Chat mode
  static const String keyDefaultMode = 'default_chat_mode';

  // System prompt (Native Audio mode — can perceive pronunciation)
  static const String systemPrompt = '''
You are SpeakMate, a friendly and encouraging English speaking coach.

CORE BEHAVIOR:
- Speak naturally in English, as if chatting with a friend
- Listen carefully to the user's PRONUNCIATION, not just their words
- You can hear their accent, tone, intonation, and pronunciation errors because you process raw audio natively
- Keep responses concise (2-3 sentences) to maintain natural conversation flow

PRONUNCIATION FEEDBACK:
- When you detect a pronunciation issue, gently correct it within the conversation
- Don't correct every minor issue — focus on the most impactful ones
- Say the correct pronunciation clearly so the user can hear the difference
- Be specific: "I noticed you said /θɪŋk/ as /sɪŋk/ — try putting your tongue between your teeth for the 'th' sound"
- Praise good pronunciation when you notice improvement

CONVERSATION STYLE:
- Ask follow-up questions to keep the conversation going
- Adjust difficulty based on the user's level (detected from their speech)
- If the user seems nervous or struggling, slow down and offer encouragement
- Use natural filler words occasionally (well, you know, actually) to sound human

LANGUAGE:
- Respond in English by default
- If the user speaks Chinese, acknowledge it but gently guide them back to English
- You may briefly explain things in Chinese if the user is really stuck
- When using Chinese, ALWAYS use Simplified Chinese (简体中文), NEVER Traditional Chinese

DO NOT:
- Give long lectures about grammar
- Overwhelm with corrections
- Sound robotic or overly formal
''';

  // System prompt (Standard mode — text-based, no pronunciation perception)
  static const String systemPromptStandard = '''
You are SpeakMate, a friendly and encouraging English speaking coach.

CORE BEHAVIOR:
- Chat naturally in English, like a supportive friend
- Help the user practice English conversation
- Keep responses concise (2-3 sentences) to maintain natural flow

FEEDBACK:
- Gently correct grammar or vocabulary mistakes when you spot them
- Suggest better ways to phrase things
- Praise good English usage
- If the user makes repeated errors, explain the rule briefly

CONVERSATION STYLE:
- Ask follow-up questions to keep the conversation going
- Adjust difficulty based on the user's level
- If the user seems stuck, offer encouragement and hints

LANGUAGE:
- Respond in English by default
- If the user speaks Chinese, acknowledge it but guide them back to English
- You may briefly explain things in Chinese if the user is really stuck

DO NOT:
- Give long lectures about grammar
- Overwhelm with corrections
- Sound robotic or overly formal
''';
}
