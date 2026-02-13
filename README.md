# SpeakMate 🎙️

AI-powered English speaking coach that can actually **hear your accent**.

Unlike traditional language apps that convert speech to text first (losing all pronunciation details), SpeakMate uses **Gemini Live API's native audio processing** to directly understand your speech — including accent, intonation, tone, and pronunciation errors.

## Features

### 🗣️ Native Audio Mode
- Real-time voice conversation with AI coach
- **Pronunciation correction** — AI hears your accent and gently corrects
- Native audio processing via Gemini Live API (no ASR pipeline)
- Live transcription of AI responses (via `output_audio_transcription`)
- Audio replay — tap 🔊 Replay on any AI message to hear it again

### 💬 Standard Chat Mode
- Text-based conversation with persistent session
- Unlimited context (no WebSocket session limits)
- System TTS for AI responses with replay support
- Grammar and vocabulary correction

### Common Features
- 📝 **Selectable text** — long press to copy any message
- 🎨 **Customizable avatars** — change AI and user avatars in Settings
- 🔑 **API key from .env** — pre-configure via `.env` file (gitignored)
- 🌐 **Proxy support** — optional, disabled by default (for regions that need it)
- 📱 **Conversation history** — persisted locally with audio files for replay

## Tech Stack

- **Flutter** 3.32+ (Android-first)
- **Gemini Live API** (`gemini-2.5-flash-native-audio-latest`) — Native Audio mode
- **Gemini REST API** (`gemini-2.5-flash`) — Standard Chat mode
- WebSocket real-time streaming
- Native PCM audio capture/playback
- `audioplayers` for WAV playback and replay
- `image_picker` for avatar customization

## Getting Started

### Prerequisites

- Flutter SDK 3.32+
- Android SDK 36+ (compileSdk 36)
- A Gemini API key (free at [AI Studio](https://aistudio.google.com/))

### Setup

```bash
git clone https://github.com/hualiuliudeliuliuqiu/speakmate.git
cd speakmate

# Configure API key (optional — can also set in app Settings)
echo "GEMINI_API_KEY=your_key_here" > .env

flutter pub get
flutter run
```

### Build Release APK

```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk (~51MB)
```

## Architecture

See [DESIGN.md](./DESIGN.md) for detailed design document.

### Key Architecture Decisions

- **No streaming playback** — AI audio is collected during the model turn and played as a complete WAV after turn ends. This eliminates audio truncation issues at the cost of slight delay.
- **Audio files persisted** — Each AI response's audio is saved to `app_documents/audio/{messageId}.wav` for replay, even after app restart.
- **output_audio_transcription** — Enabled in Gemini setup to get real speech transcription (not the model's thinking text).

## License

MIT
