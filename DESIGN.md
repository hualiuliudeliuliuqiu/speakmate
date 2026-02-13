# SpeakMate — AI 英语口语教练

> 基于 Gemini Live API 的原生音频对话应用，能感知口音、语调和发音问题

## 项目概述

现有的英语口语练习工具都走 ASR→文字→LLM→TTS 管道，导致发音细节在第一步就丢失了。SpeakMate 利用 Gemini Live API 的原生音频处理能力，跳过 ASR 中间步骤，直接处理音频 token，从而感知用户的口音、语调、情绪和发音问题。

## 技术架构

### 核心技术

- **前端**: Flutter (Android + iOS)
- **AI 引擎**: Gemini Live API (`gemini-live-2.5-flash-native-audio`)
- **协议**: WebSocket (WSS) 双向实时流
- **音频格式**: 输入 16-bit PCM, 16kHz | 输出 16-bit PCM, 24kHz

### 架构图

```
┌──────────────────────────────────┐
│          Flutter App             │
│  ┌────────────┐  ┌────────────┐ │
│  │ 麦克风录音  │  │ 音频播放    │ │
│  │ PCM 16kHz  │  │ PCM 24kHz  │ │
│  └─────┬──────┘  └─────▲──────┘ │
│        │               │        │
│  ┌─────▼───────────────┴──────┐ │
│  │    WebSocket 管理器         │ │
│  │  - 音频流发送/接收          │ │
│  │  - 会话状态管理             │ │
│  │  - 重连机制                │ │
│  └─────┬───────────────▲──────┘ │
│        │               │        │
│  ┌─────▼───────────────┴──────┐ │
│  │    对话管理器               │ │
│  │  - System Prompt 管理       │ │
│  │  - 转写文本显示             │ │
│  │  - 发音反馈解析             │ │
│  └────────────────────────────┘ │
└──────────┬───────────────▲──────┘
           │               │
           ▼               │
┌──────────────────────────────────┐
│    Gemini Live API (WSS)         │
│  gemini-live-2.5-flash-native-   │
│  audio                           │
│                                  │
│  能力:                           │
│  ✅ 原生音频理解（口音/语调/情绪）│
│  ✅ 音频转写（实时字幕）         │
│  ✅ 情感对话（匹配用户情绪）     │
│  ✅ 打断支持（barge-in）         │
│  ✅ 24 种语言                    │
│  ✅ Tool Use（函数调用）         │
└──────────────────────────────────┘
```

### 直连 vs 后端代理

**MVP 阶段采用直连方案**：Flutter App 直接通过 WebSocket 连接 Gemini Live API。原因：
1. 简化架构，快速验证核心体验
2. API Key 存储在 App 本地（个人使用足够）
3. 减少额外延迟

**后续如果要上线**，再加一层后端代理保护 API Key。

## Gemini Live API 能力边界

### ✅ 能做的
| 能力 | 对口语练习的价值 |
|------|-----------------|
| 原生音频处理 | 感知口音、发音错误，不只是听"说了什么" |
| 情感对话 (Affective Dialog) | 根据用户的语气调整回应风格，紧张时给鼓励 |
| 打断支持 (Barge-in) | 自然对话体验，用户随时可以打断 |
| 音频转写 | 同步显示文字，方便用户回看 |
| 多语言 | 支持 24 种语言，可以做中英双语教练 |
| Tool Use | 可扩展词汇查询、语法解释等工具 |
| 主动音频 (Proactive Audio) | 控制何时回应，支持静默倾听模式 |

### ❌ 不能做 / 局限
| 局限 | 影响 | 应对策略 |
|------|------|---------|
| 没有精确的音素级评分 | 不能像 ELSA 那样给每个音标打分 | 靠 prompt 引导模型给出定性反馈 |
| 不能持久记忆（会话级） | 每次连接是新会话 | App 端存储学习记录，每次连接注入历史摘要 |
| 会话时长限制 | 长对话可能断开 | 实现自动重连 + 上下文恢复 |
| 不能输出结构化评分 | 没有 JSON 格式的发音评分 | 用 Tool Use 让模型调用自定义函数输出结构化反馈 |
| 音频输入只支持 PCM | 需要在 App 端处理音频编码 | Flutter 音频录制直出 PCM |

## 产品功能设计

### MVP（第一版）

#### 1. 自由对话模式
- 用户打开 App 直接和 AI 英语对话
- AI 扮演友好的英语教练角色
- 实时双向语音，支持打断
- 底部显示实时转写文字

#### 2. 发音纠正
- AI 在对话中自然地指出发音问题
- 不是每句都纠正（太烦），而是发现明显问题时温和指出
- 示范正确发音（AI 语音输出）

#### 3. 场景对话
- 预设对话场景：日常闲聊、餐厅点餐、面试模拟、旅行问路等
- 每个场景有不同的 System Prompt
- 场景内 AI 会扮演相应角色

#### 4. 对话记录
- 保存每次对话的转写文本
- 标记 AI 给出的发音纠正建议
- 可以回看历史对话

### 未来版本

- **发音评估报告**：通过 Tool Use 输出结构化评分
- **学习计划**：根据历史数据推荐练习重点
- **词汇本**：对话中遇到的生词自动收集
- **社区**：分享学习进度
- **离线模式**：缓存常用场景的 AI 回复

## System Prompt 设计

```
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

DO NOT:
- Give long lectures about grammar
- Overwhelm with corrections
- Sound robotic or overly formal
```

## 技术实现计划

### Phase 1: 基础框架（1-2 天）
- [ ] Flutter 项目初始化
- [ ] 基本 UI 骨架（对话界面、录音按钮）
- [ ] 音频录制模块（PCM 16kHz）
- [ ] 音频播放模块（PCM 24kHz）

### Phase 2: Gemini 对接（2-3 天）
- [ ] WebSocket 连接管理器
- [ ] 音频流发送/接收
- [ ] 会话建立（setup message + system prompt）
- [ ] 音频转写接收和显示
- [ ] 打断检测处理

### Phase 3: 口语教练功能（1-2 天）
- [ ] 场景对话模板
- [ ] System Prompt 管理
- [ ] 发音反馈高亮显示
- [ ] 对话记录存储（SQLite）

### Phase 4: 体验优化（1-2 天）
- [ ] 连接状态指示
- [ ] 自动重连
- [ ] 音频波形可视化
- [ ] 设置页面（API Key 配置、语音语速偏好）

## 目录结构

```
speakmate/
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── config/
│   │   └── constants.dart          # API 地址、音频参数等
│   ├── models/
│   │   ├── conversation.dart       # 对话数据模型
│   │   ├── message.dart            # 消息模型（文字+音频）
│   │   └── scenario.dart           # 场景模板模型
│   ├── services/
│   │   ├── gemini_live_service.dart # WebSocket + 音频流核心
│   │   ├── audio_service.dart      # 录音+播放
│   │   └── storage_service.dart    # 本地存储
│   ├── screens/
│   │   ├── home_screen.dart        # 主页（场景列表）
│   │   ├── chat_screen.dart        # 对话界面
│   │   ├── history_screen.dart     # 历史记录
│   │   └── settings_screen.dart    # 设置
│   ├── widgets/
│   │   ├── audio_visualizer.dart   # 音频波形
│   │   ├── transcript_bubble.dart  # 转写气泡
│   │   └── scenario_card.dart      # 场景卡片
│   └── prompts/
│       ├── base_prompt.dart        # 基础教练 prompt
│       └── scenarios.dart          # 场景 prompt 集合
├── assets/
│   └── scenarios/                  # 场景图标等
├── test/
├── pubspec.yaml
├── DESIGN.md
└── README.md
```

## 依赖

```yaml
dependencies:
  flutter:
    sdk: flutter
  web_socket_channel: ^3.0.0    # WebSocket 通信
  record: ^5.0.0                # 麦克风录音（PCM 输出）
  audioplayers: ^6.0.0          # 音频播放
  sqflite: ^2.3.0               # 本地数据库
  path_provider: ^2.1.0         # 文件路径
  provider: ^6.1.0              # 状态管理
  shared_preferences: ^2.2.0    # 配置存储
  permission_handler: ^11.0.0   # 权限管理
  uuid: ^4.0.0                  # 唯一标识
```
