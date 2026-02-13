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

## 💡 关于转写功能

### 双向转写

在 setup message 中同时启用两个转写：

```json
{
  "setup": {
    "model": "models/gemini-2.5-flash-native-audio-latest",
    "generation_config": {
      "response_modalities": ["AUDIO"],
      "speech_config": { ... }
    },
    "output_audio_transcription": {},
    "input_audio_transcription": {},
    "system_instruction": { ... }
  }
}
```

- **`output_audio_transcription`** → AI 语音字幕（`serverContent.outputTranscription.text`）
- **`input_audio_transcription`** → 用户语音转写（`serverContent.inputTranscription.text`）
  - ⚠️ AI Studio API 将 `inputTranscription` 放在 `serverContent` 内部（非顶层）
  - ⚠️ 转写语言自动推断，无法手动指定
  - ⚠️ 流式到达，第一个 chunk 可能是空格，需 `trim()` 过滤

**⚠️ 重要区分**：
- `serverContent.modelTurn.parts[].text` — 这是模型的**思考/规划文本**（类似 CoT），不是语音转写！
- `serverContent.outputTranscription.text` — 这才是**真正的语音转写**

### 音频播放策略

SpeakMate 采用**实时播放 + 完整保存**策略：
- 实时播放：`mp_audio_stream` 接收 PCM 数据即时播放（低延迟）
- 完整保存：turn 结束后将全部 PCM 合成 WAV 保存供重播

### Standard 模式的语音输入

Standard 模式通过 Gemini REST API 的 multimodal 能力处理语音：
- 录音 PCM → WAV → base64 → `inlineData`（`audio/wav`）
- 并行发送：主回复请求 + 独立转写请求（`Future.wait`）
- 转写完成后更新用户消息气泡
- 发送后将 history 中的 audio 数据替换为文本摘要节省 tokens

## ⚠️ 地域限制

Gemini API 在中国大陆直连会返回 `User location is not supported`。需要通过代理访问：
- 默认代理：`127.0.0.1:7897`（Clash Verge）
- 在 App 设置中可配置代理地址

## 📊 免费额度

AI Studio 免费 tier 限制（大约）：
- RPM (Requests per minute): 有限制
- TPM (Tokens per minute): 有限制  
- 具体限额请查看 [AI Studio 定价页面](https://ai.google.dev/pricing)
