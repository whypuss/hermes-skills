---
name: qwen3-tts-setup
description: Qwen3 TTS 環境架設與正確 API 用法（Python 3.14 + qwen-tts 官方套件）

---

## Qwen3 TTS 模型版本對照

| 模型 | 參數 | Cantonese 質量 |
|------|------|----------------|
| Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice | 0.6B | 摻雜普通話口音 |
| Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice | 1.7B | 待測試（預期更好）|

切換方式：修改 `MODEL_ID = "Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice"`

粵語 instruct：tone="用標準粵語（廣東話）說話，語氣親切自然"，需配合 language="Chinese"

模型下載約 3.4GB，用 snapshot_download() 後台下載
category: ai-audio
---

# Qwen3 TTS 環境架設

## 觸發條件
用戶想做 Qwen3 TTS 語音合成，特別是輕量模型方案

## 關鍵發現（試錯過程）

### ❌ 錯誤路徑
1. **llama-cpp-python + GGUF**：Qwen3 TTS GGUF 無法被 llama-cpp-python 正確加載（Magic OK，但 `ValueError: Failed to load model`）
2. **transformers + Qwen/Qwen3-TTS-12Hz-0.6B-Base**：transformers 4.x 不認識 `qwen3_tts` model type；升級到 5.7.0.dev0 仍不支援
3. **Base 模型不支援 VoiceDesign**：即使 transformers 支持，Base 型號也只有 `generate_voice_clone`，沒有 `generate_voice_design`

### ✅ 正確路徑
1. **官方 `qwen-tts` 套件**：pip install qwen-tts（不是 transformers）
2. **CustomVoice 型號**：`Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice`（不是 Base）
3. **Python 3.10+ 必需**：系統 Python 3.9.6 無法運行 qwen-tts，用 uv 建立虛擬環境

## 環境架設步驟

```bash
cd ~/.kimaki/projects/podcast-gen/backend

# 1. 用 uv 建立 Python 3.14 環境
uv venv --python 3.14 .venv-tts

# 2. 安裝 qwen-tts
uv pip install --python .venv-tts/bin/python qwen-tts soundfile

# 3. 確認模型（CustomVoice，約 1.8GB，首次使用自動下載）
```

## 正確 API 用法

```python
from qwen_tts import Qwen3TTSModel

model = Qwen3TTSModel.from_pretrained(
    "Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice",
    device_map="cpu",
    dtype=torch.float32,
)

# CustomVoice 內建 9 種音色，直接用 speaker= 名稱切換男女聲
# Male:   Uncle_Fu（沉穩）, Dylan（京腔）, Eric（四川）
# Female: Vivian（亮麗）, Serena（溫柔）
# English: Ryan, Aiden / Japanese: Ono_Anna / Korean: Sohee

wavs, sr = model.generate_custom_voice(
    text="你好，這是一個測試。",
    speaker="Uncle_Fu",   # 換成 Vivian 就是女聲
    language="Chinese",
    instruct="用沉穩有力的語氣朗讀。",
    non_streaming_mode=True,
)

# VoiceClone 模式（需要參考音頻）
wavs, sr = model.generate_voice_clone(
    text="你好，這是一個測試。",
    ref_audio="path/to/reference.wav",
    ref_text="參考音頻的原文",
    language="Chinese",
    non_streaming_mode=True,
)
```

## 重要參數
- `instruct`：音色描述（英文），用於 VoiceDesign
- `language`：中文用 "Chinese"
- `non_streaming_mode=True`：同步生成
- `speed`：目前 qwen-tts 內部不支援 speed 參數，設了也無效

## 限制
- CPU 推理慢（約 0.5x 即時率），10 秒音頻需 20+ 秒
- Mac 上 flash-attn 不可用，會有 warning 但不影響運行
- SoX 找不到會有 warning 但不影響運行

## 陷阱
- **千萬不要**用 `Qwen/Qwen3-TTS-12Hz-0.6B-Base`（Base 型號不支援 VoiceDesign / CustomVoice 功能）
- **千萬不要**用 transformers 直接加載（不支持 qwen3_tts model type）
- CustomVoice 型號不支援 `generate_voice_design` → 應用 `generate_custom_voice(speaker=NAME, instruct=TONE)`
- `instruct` 是**語氣指令**（中文也可），不是音色描述；音色由 `speaker=` 參數指定

## 項目整合
- 引擎封裝：`~/.kimaki/projects/podcast-gen/backend/qwen3_tts_engine.py`
- 虛擬環境：`~/.kimaki/projects/podcast-gen/backend/.venv-tts/`
- 模型緩存：`~/.cache/huggingface/hub/models--Qwen--Qwen3-TTS-12Hz-0.6B-CustomVoice/`
