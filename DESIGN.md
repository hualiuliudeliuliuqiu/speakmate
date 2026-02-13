# SpeakMate — AI 英语口语教练

> 基于 Gemini Live API 的原生音频对话应用，能感知口音、语调和发音问题

## 项目概述

现有的英语口语练习工具都走 ASR→文字→LLM→TTS 管道，导致发音细节在第一步就丢失了。SpeakMate 利用 Gemini Live API 的原生音频处理能力，跳过 ASR 中间步骤，直接处理音频 token，从而感知用户的口音、语调、情绪和发音问题。

## 双模式架构

### Native Audio 模式
- **协议**：WebSocket (WSS) 双向实时流
- **模型**：`gemini-2.5-flash-native-audio-latest`
- **输入**：实时 PCM 音频流（`realtime_input`）
- **输出**：PCM 音频 + 文字转写
- **转写**：双向 — `input_audio_transcription`（用户语音→文字）+ `output_audio_transcription`（AI 语音→文字）
- **语音检测**：Gemini 内置 VAD（Voice Activity Detection），自动检测用户停顿
- **特点**：能感知口音/语调/情绪，低延迟实时对话，但 session 有时长限制

### Standard Chat 模式
- **协议**：REST API（`generateContent`）
- **模型**：`gemini-2.5-flash`（对话）+ `gemini-2.5-flash-preview-tts`（语音合成）
- **文字输入**：直接发送文本
- **语音输入**：录音 PCM → WAV → base64 → 作为 `inlineData` multimodal 输入发送
- **转写**：并行发送独立的 transcribe 请求（不影响主回复延迟）
- **特点**：session 无限长，完整上下文保持，适合长对话

## 技术架构

### 核心技术

- **前端**: Flutter (Android-first)
- **AI 引擎**: Gemini Live API + Gemini REST API + Gemini TTS API
- **音频格式**: 输入 16-bit PCM, 16kHz mono | 输出 16-bit PCM, 24kHz mono

### 架构图

```
┌──────────────────────────────────────────────────────┐
│                    Flutter App                        │
│                                                       │
│  ┌─────────────┐  ┌─────────────┐  ┌──────────────┐ │
│  │ AudioService │  │  Recording  │  │  Playback    │ │
│  │ PCM capture  │  │  Visualizer │  │  WAV replay  │ │
│  │ + level      │  │  (pulsing)  │  │  audioplayers│ │
│  └──────┬───────┘  └─────────────┘  └──────▲───────┘ │
│         │                                   │         │
│  ┌──────▼──────────────────────────────────┴───────┐ │
│  │              Mode Router                         │ │
│  │                                                  │ │
│  │  ┌─────────────────┐   ┌──────────────────────┐ │ │
│  │  │ GeminiLiveService│   │ GeminiTextService    │ │ │
│  │  │ WebSocket (WSS) │   │ REST generateContent │ │ │
│  │  │ realtime_input  │   │ + transcribeAudio()  │ │ │
│  │  │ input/output    │   │                      │ │ │
│  │  │ transcription   │   │ TtsService           │ │ │
│  │  │                 │   │ Gemini TTS SSE API   │ │ │
│  │  └────────┬────────┘   └──────────┬───────────┘ │ │
│  └───────────┼───────────────────────┼─────────────┘ │
│              │                       │                │
│  ┌───────────▼───────────────────────▼─────────────┐ │
│  │            ConversationService                   │ │
│  │  SharedPreferences JSON persistence              │ │
│  │  + audio files in app_documents/audio/           │ │
│  └─────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────┘
            │                       │
            ▼                       ▼
┌────────────────────┐  ┌────────────────────────┐
│ Gemini Live API    │  │ Gemini REST API         │
│ WSS bidirectional  │  │ generateContent         │
│ native-audio model │  │ streamGenerateContent   │
│                    │  │ (TTS SSE)               │
└────────────────────┘  └────────────────────────┘
```

### 直连 vs 后端代理

**当前采用直连方案**：Flutter App 直接连接 Gemini API。原因：
1. 简化架构，个人使用足够
2. API Key 存储在 App 本地
3. 减少额外延迟

中国大陆需要配置 HTTP/HTTPS 代理（默认 Clash Verge 127.0.0.1:7897）。

## Gemini Live API 能力边界

### ✅ 能做的
| 能力 | 对口语练习的价值 |
|------|-----------------|
| 原生音频处理 | 感知口音、发音错误，不只是听"说了什么" |
| 双向转写 | 用户和 AI 的语音都实时转成文字显示 |
| 情感对话 (Affective Dialog) | 根据用户的语气调整回应风格，紧张时给鼓励 |
| 打断支持 (Barge-in) | 自然对话体验，用户随时可以打断 |
| VAD 自动检测 | 不需要手动发 turn_complete，Gemini 自动检测停顿 |
| 多语言 | 支持 24 种语言，可以做中英双语教练 |
| Tool Use | 可扩展词汇查询、语法解释等工具 |

### ❌ 局限
| 局限 | 影响 | 应对策略 |
|------|------|---------|
| 没有精确的音素级评分 | 不能像 ELSA 那样给每个音标打分 | 靠 prompt 引导模型给定性反馈 |
| 会话级记忆 | 每次 WebSocket 连接是新会话 | App 端存储记录，连接时注入历史摘要 |
| 会话时长限制 | 长对话可能断开 | Standard 模式无此限制 |
| input transcription 语言自动推断 | 无法手动指定转写语言 | System prompt 提示用简体中文 |
| 免费 tier 速率限制 | RPM/TPM 有上限 | 合理控制请求频率 |

## System Prompt 设计

### Native Audio 模式

针对能感知发音的原生音频场景：
- 重点：发音纠正、口音感知
- 简短回复（2-3 句）保持对话流畅
- 中文场景使用简体中文（`ALWAYS use Simplified Chinese`）

### Standard Chat 模式

针对文字为主的场景：
- 重点：语法纠正、词汇建议
- 支持文字和语音双输入
- 同样简短回复

详细 prompt 见 `lib/config/constants.dart`。

## 技术实现进度

### Phase 1: 基础框架 ✅
- [x] Flutter 项目初始化
- [x] 基本 UI 骨架（对话界面、录音按钮）
- [x] 音频录制模块（PCM 16kHz）
- [x] 音频播放模块（实时 PCM push + WAV 重播）

### Phase 2: Gemini 对接 ✅
- [x] WebSocket 连接管理器（含代理支持）
- [x] 音频流发送/接收
- [x] 会话建立（setup message + system prompt）
- [x] AI 语音转写（output_audio_transcription）
- [x] 用户语音转写（input_audio_transcription）
- [x] 打断检测处理 + VAD
- [x] Standard Chat 模式（REST API）
- [x] Gemini TTS API 集成（SSE streaming）

### Phase 3: 口语教练功能 ✅
- [x] 场景对话模板
- [x] System Prompt 管理（Native Audio / Standard 两套）
- [x] 对话记录存储（SharedPreferences + JSON）
- [x] 对话历史持久化 + 上下文恢复

### Phase 4: 体验优化 ✅
- [x] 连接状态指示
- [x] 音频波形可视化（脉冲环 + 音量级别）
- [x] 设置页面（API Key、代理、语音、头像）
- [x] 音频重播功能（持久化 WAV 文件）
- [x] 自定义头像（AI + 用户）
- [x] 文本可复制
- [x] 键盘弹出自动滚动
- [x] AppTheme 设计系统（浅色主题）
- [x] Standard 模式语音输入（multimodal audio）
- [x] 语音消息并行转写（不增加延迟）
- [x] 按压反馈（卡片缩放动画 + InkWell 水波纹）
- [x] 语音消息 UI（Voice 标签 + 转写文字 + 加载态）

### Phase 5: 待做
- [ ] 发音评估报告（Tool Use 结构化输出）
- [ ] 学习计划/进度追踪
- [ ] 词汇本（对话中生词收集）
- [ ] 对话导出
- [ ] 更多场景模板

## 目录结构

```
speakmate/
├── lib/
│   ├── main.dart                    # 入口，.env 加载，服务初始化
│   ├── app.dart                     # MaterialApp 配置
│   ├── config/
│   │   ├── constants.dart           # API 地址、音频参数、System Prompt
│   │   └── theme.dart               # AppTheme 设计系统
│   ├── models/
│   │   ├── conversation.dart        # 对话数据模型
│   │   ├── message.dart             # 消息模型（UUID, isVoice 标记）
│   │   └── scenario.dart            # 场景模板模型
│   ├── services/
│   │   ├── gemini_live_service.dart  # WebSocket + Native Audio 核心
│   │   │                            #   - input/output transcription
│   │   │                            #   - VAD (无需手动 turn_complete)
│   │   ├── gemini_text_service.dart  # REST API (Standard Chat)
│   │   │                            #   - sendMessage() 文字对话
│   │   │                            #   - sendAudioMessage() 语音对话
│   │   │                            #   - transcribeAudio() 独立转写
│   │   ├── audio_service.dart       # 录音 + 实时 PCM 播放 + WAV 重播
│   │   ├── tts_service.dart         # Gemini TTS API (SSE streaming)
│   │   ├── conversation_service.dart # 对话持久化 (SharedPreferences)
│   │   └── storage_service.dart     # 设置存储 (API key, proxy, avatars)
│   ├── screens/
│   │   ├── home_screen.dart         # 主页（双模式卡片 + 按压动画）
│   │   ├── chat_screen.dart         # Native Audio 对话界面
│   │   ├── standard_chat_screen.dart # Standard Chat（文字+语音输入）
│   │   └── settings_screen.dart     # 设置页
│   ├── widgets/
│   │   ├── audio_visualizer.dart    # 录音脉冲环 + AI Speaking 指示器
│   │   ├── transcript_bubble.dart   # 消息气泡（语音/文字、重播、流式）
│   │   └── scenario_card.dart       # 场景选择卡片
│   └── prompts/
│       └── scenarios.dart           # 场景 prompt 集合
├── assets/images/
│   └── ai_avatar.jpeg               # 默认 AI 头像
├── .env                             # API key（gitignored）
├── pubspec.yaml
├── DESIGN.md                        # 本文件
├── MODELS.md                        # 可用模型列表
└── README.md
```

## 依赖

```yaml
dependencies:
  web_socket_channel: ^3.0.3    # WebSocket 通信 (Live API)
  record: ^5.1.2                # 麦克风录音（PCM 输出）
  mp_audio_stream: ^0.2.2       # 实时 PCM push 播放
  audioplayers: ^6.1.0          # WAV 音频重播
  path_provider: ^2.1.5         # 文件路径（音频持久化）
  provider: ^6.1.2              # 状态管理
  shared_preferences: ^2.3.3    # 配置/对话存储
  permission_handler: ^11.3.1   # 麦克风权限
  uuid: ^4.5.1                  # 消息唯一标识
  flutter_dotenv: ^5.2.1        # .env 文件加载
  http: ^1.2.0                  # REST API 调用
  image_picker: ^1.1.2          # 头像选择

dependency_overrides:
  record_linux: ^1.3.0          # Linux 兼容性修复
```

## 关键实现细节

### Native Audio — 用户语音转写

Gemini Live API 的 `input_audio_transcription` 在 `serverContent` 中返回（AI Studio API），字段为 `inputTranscription`。转写是流式到达的（一个字一个字），第一个 chunk 可能是空格需要过滤。

**重要**：转写数据在用户**说话过程中**就开始到达，因此 voice message 必须在 `startRecording` 时就创建，否则转写到达时找不到目标消息。

### Standard — 语音输入

录音 PCM → 封装 WAV header → base64 → 作为 `inlineData`（`audio/wav`）发给 `generateContent`。Gemini 2.5 Flash 支持 multimodal 输入，直接"听"音频并理解内容。

**并行转写**：主回复和独立转写请求同时发出（`Future.wait`），转写完成后更新用户气泡文字，不增加响应延迟。

**历史压缩**：发送后将 history 中的 audio inlineData 替换为 `[Voice message from user]` 文本，避免后续请求携带巨大的 base64 数据。

### 音频播放策略

Native Audio 模式使用 `mp_audio_stream` 实时 push PCM 数据播放（低延迟）。Turn 结束后将完整 PCM 保存为 WAV 文件供重播。

Standard 模式的 TTS 使用 Gemini TTS API（SSE streaming），收集全部 PCM 后写 WAV 一次性播放。

### VAD vs turn_complete

Native Audio 的 `realtime_input` 模式依赖 Gemini 内置 VAD 检测用户停顿。**不要**手动发送 `client_content.turn_complete`，这会导致连接异常断开。
