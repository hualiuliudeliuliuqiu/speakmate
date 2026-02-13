# SpeakMate — 可用模型列表

> API Key 类型：Google AI Studio 免费 tier
> 查询时间：2026-02-12
> 总计：45 个模型

## 🎙️ Live API 模型（实时语音对话）

这些模型支持 `bidiGenerateContent`（双向实时流），是 SpeakMate 的核心。

| 模型 | 说明 | SpeakMate 使用 |
|------|------|---------------|
| `gemini-2.5-flash-native-audio-latest` | **最新版 Native Audio** | ✅ **默认使用** |
| `gemini-2.5-flash-native-audio-preview-12-2025` | Native Audio 12月预览版 | ✅ 可选备用 |
| `gemini-2.5-flash-native-audio-preview-09-2025` | Native Audio 9月预览版 | ⚠️ 较旧 |
| `gemini-2.0-flash-exp-image-generation` | 图像生成实验版（也支持 Live） | ❌ 非音频用途 |

### Native Audio 模型能力

- ✅ **原生音频处理**：直接理解音频 token，能感知口音、语调、情绪
- ✅ **音频输出**：生成自然语音（多种声音可选）
- ✅ **音频转写**：自动返回输入/输出的文字版本（字幕功能）
- ✅ **打断支持 (Barge-in)**：用户可随时打断 AI 说话
- ✅ **情感对话**：根据用户语气调整回应风格
- ✅ **24 种语言**
- ✅ **Tool Use / 函数调用**

### 技术参数

- **输入音频**：16-bit PCM, 16kHz, mono, little-endian
- **输出音频**：16-bit PCM, 24kHz, mono, little-endian
- **协议**：WebSocket (WSS)
- **response_modalities**：必须设为 `["AUDIO"]`（Native Audio 模型不支持纯文本模态）
- **字幕/转写**：模型在返回音频的同时也会返回对应的文字转写，无需额外配置

## 📝 文本生成模型

这些模型支持 `generateContent`，可用于文本分析、总结等辅助功能。

| 模型 | 说明 |
|------|------|
| `gemini-2.5-pro` | 最强文本模型，适合复杂分析 |
| `gemini-2.5-flash` | 快速文本模型，日常使用 |
| `gemini-2.5-flash-lite` | 轻量版，更快更省 |
| `gemini-2.0-flash` | 上一代快速模型 |
| `gemini-2.0-flash-lite` | 上一代轻量模型 |
| `gemini-2.5-flash-preview-tts` | TTS 预览版 |
| `gemini-2.5-pro-preview-tts` | TTS Pro 预览版 |
| `gemini-2.5-flash-image` | 图像理解 |
| `gemini-3-pro-preview` | Gemini 3 Pro 预览 |
| `gemini-3-flash-preview` | Gemini 3 Flash 预览 |
| `gemma-3-*` | Gemma 开源系列 (1B/4B/12B/27B) |

## 🔢 Embedding 模型

| 模型 | 说明 |
|------|------|
| `gemini-embedding-001` | 文本嵌入，可用于语义搜索 |

## 💡 关于字幕功能

**Q: response_modalities 只能设 ["AUDIO"]，那怎么显示字幕？**

A: Native Audio 模型在返回音频数据的同时，会**自动附带文字转写**。具体来说：
- 服务端返回的 `serverContent.modelTurn.parts[]` 中，既有 `inlineData`（音频）也有 `text`（转写）
- 这是 Gemini Live API 的内置功能 "Audio Transcriptions"
- 不需要设置 response_modalities 为 TEXT，转写是自动的
- App 只需要解析返回数据中的 text 字段，显示在界面上即可

所以 SpeakMate **完全支持实时字幕**：
1. AI 说话时，音频播放的同时在屏幕上显示对应文字
2. 用户说话时，也可以显示语音识别结果（输入转写）
3. 用户可以通过设置开关字幕显示

## ⚠️ 地域限制

Gemini API 在中国大陆直连会返回 `User location is not supported`。需要通过代理访问：
- 默认代理：`127.0.0.1:7897`（Clash Verge）
- 在 App 设置中可配置代理地址

## 📊 免费额度

AI Studio 免费 tier 限制（大约）：
- RPM (Requests per minute): 有限制
- TPM (Tokens per minute): 有限制  
- 具体限额请查看 [AI Studio 定价页面](https://ai.google.dev/pricing)
