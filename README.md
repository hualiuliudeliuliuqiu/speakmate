# SpeakMate 🎙️

AI-powered English speaking coach that can actually **hear your accent**.

Unlike traditional language apps that convert speech to text first (losing all pronunciation details), SpeakMate uses **Gemini Live API's native audio processing** to directly understand your speech — including accent, intonation, tone, and pronunciation errors.

## Features

- 🗣️ **Free Conversation** — Natural English conversation with an AI coach
- 🎯 **Pronunciation Correction** — Real-time accent and pronunciation feedback
- 🎭 **Scenario Practice** — Restaurant, interview, travel, daily chat & more
- 📝 **Live Transcription** — See what you and AI said in real-time
- 📊 **History** — Review past conversations and feedback

## Tech Stack

- **Flutter** (Android + iOS)
- **Gemini Live API** (`gemini-live-2.5-flash-native-audio`)
- WebSocket real-time streaming
- Native PCM audio capture/playback

## Getting Started

### Prerequisites

- Flutter SDK 3.x+
- A Gemini API key (get one free at [AI Studio](https://aistudio.google.com/))

### Setup

```bash
git clone <this-repo>
cd speakmate
flutter pub get
flutter run
```

Enter your Gemini API key in Settings on first launch.

## Architecture

See [DESIGN.md](./DESIGN.md) for detailed design document.

## License

MIT
