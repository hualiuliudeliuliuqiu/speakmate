# SpeakMate 🎙️

AI-powered English speaking coach that can actually **hear your accent**.

Unlike traditional language apps that convert speech to text first (losing all pronunciation details), SpeakMate uses **Gemini Live API's native audio processing** to directly understand your speech — including accent, intonation, tone, and pronunciation errors.

## Features

### 🗣️ Native Audio Mode
- Real-time voice conversation with AI coach
- **Pronunciation correction** — AI hears your accent and gently corrects
- Native audio processing via Gemini Live API (no ASR pipeline)
- **Live user speech transcription** — see what you said in real-time (`input_audio_transcription`)
- Live AI response transcription (`output_audio_transcription`)
- Audio replay — tap 🔊 Replay on any AI message to hear it again
- Voice Activity Detection (VAD) — AI detects when you stop speaking

### 💬 Standard Chat Mode
- Text **and voice** input with persistent session
- 🎤 Voice messages transcribed via Gemini multimodal API (parallel with AI response)
- Unlimited context (no WebSocket session limits)
- Gemini TTS for AI voice responses with replay support
- Grammar and vocabulary correction

### Common Features
- 📝 **Selectable text** — long press to copy any message
- 🎨 **Customizable avatars** — change AI and user avatars in Settings
- 🔑 **API key from .env** — pre-configure via `.env` file (gitignored)
- 🌐 **Proxy support** — configurable for regions that need it (default: Clash Verge 127.0.0.1:7897)
- 📱 **Conversation history** — persisted locally with audio files for replay
- 🎯 **Press feedback** — scale animations on cards, Material ripple on buttons
- 🎙️ **Recording visualizer** — pulsing ring with audio level during voice input

## Tech Stack

- **Flutter** 3.32+ (Android-first)
- **Gemini Live API** (`gemini-2.5-flash-native-audio-latest`) — Native Audio mode
- **Gemini REST API** (`gemini-2.5-flash`) — Standard Chat mode + voice transcription
- **Gemini TTS API** (`gemini-2.5-flash-preview-tts`) — AI voice in Standard mode
- WebSocket real-time bidirectional streaming
- Native PCM audio capture via `record` package
- Real-time PCM push playback via `mp_audio_stream`
- `audioplayers` for WAV replay

## Getting Started

### Prerequisites

- Flutter SDK 3.32+
- Android SDK 36+ (compileSdk 36, NDK 27)
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
# Output: build/app/outputs/flutter-apk/app-release.apk (~52MB)
```

## Architecture

See [DESIGN.md](./DESIGN.md) for detailed design document.

### Key Architecture Decisions

- **Dual audio transcription** — Native Audio mode enables both `input_audio_transcription` (user speech) and `output_audio_transcription` (AI speech) for real-time subtitles on both sides.
- **Parallel transcription** — Standard mode runs voice transcription and AI response in parallel, no added latency.
- **No streaming playback** — AI audio is collected during the model turn and played as a complete WAV after turn ends. This eliminates audio truncation issues at the cost of slight delay.
- **Audio files persisted** — Each AI response's audio is saved to `app_documents/audio/{messageId}.wav` for replay, even after app restart.
- **VAD-based turn detection** — Native Audio mode relies on Gemini's built-in Voice Activity Detection instead of manual turn_complete signals.
- **History compaction** — Standard mode replaces audio data in conversation history with text summaries after each turn to save tokens.

## License

MIT
