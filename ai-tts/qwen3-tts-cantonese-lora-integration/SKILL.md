---
name: qwen3-tts-cantonese-lora-integration
description: Qwen3 TTS CustomVoice + Cantonese LoRA 整合與生成流程（Megatron/PEFT 混合架構）
category: ai-tts
tags: [qwen3, tts, cantonese, lora, peft, sherpa-onnx]
version: 2026-04-30
---

# Qwen3 TTS Cantonese LoRA Integration

## 背景

Qwen3-TTS-12Hz-0.6B-CustomVoice 的 Megatron 訓練 LoRA 輸出其實是 PEFT 格式（adapter_model.safetensors + adapter_config.json），可以直接用 `PeftModel.from_pretrained(...).merge_and_unload()` 合併到 HuggingFace base model。

## 核心問題

Qwen3 TTS 有兩層 speaker 校驗：

1. **第一層**（Qwen3TTSModel 級別）：`get_supported_speakers()` → 來自 `model.config.spk_id`
2. **第二層**（Talker 級別）：`talker.generate()` → 來自 `talker.config.spk_id` 和 `talker.config.spk_is_dialect`

LoRA merge 後，必須 patch **兩處** config 否則會陸續遇到：
- `Speaker hk_cantonese not implemented`（來自 talker.generate）
- `KeyError: 'hk_cantonese'`（來自 spk_is_dialect）

## 完整生成代碼

```python
import torch
from qwen_tts import Qwen3TTSModel
from peft import PeftModel
import soundfile as sf

# 1. 載入 base model
model = Qwen3TTSModel.from_pretrained(
    "/path/to/Qwen3-TTS-12Hz-0.6B-CustomVoice",
    device_map="cpu",
    torch_dtype=torch.bfloat16,
)

# 2. 合併 LoRA
model_base = model.model
model_with_lora = PeftModel.from_pretrained(
    model_base,
    "/path/to/cantonese_lora_adapter"  # adapter_model.safetensors + adapter_config.json
)
model_with_lora.merge_and_unload()
model.model = model_with_lora

# 3. 關鍵補丁：patch 兩層 config
model.model.talker.config.spk_id['hk_cantonese'] = 3000
model.model.talker.config.spk_is_dialect['hk_cantonese'] = False

# 4. 生成
wavs, sr = model.generate_custom_voice(
    text="你好，你今日過得點呀？",
    speaker="hk_cantonese",
    language="chinese",
)
sf.write("output.wav", wavs[0], sr)
```

## 為什麼 Megatron 輸出是 PEFT 格式

Megatron 訓練腳本只是初始化了 LoRA 結構（target_modules: q/k/v/o_proj + gate/up/down_proj），最終 checkpoint 保存時用了 HuggingFace 的 state_dict 格式。所以：
- **不需要** Megatron 才能用 LoRA
- **不需要** 轉換格式
- 直接用 PEFT library 合併即可

## spk_is_dialect 的語言override邏輯

在 `modeling_qwen3_tts.py:2118-2122`：

```python
if (language.lower() in ["chinese", "auto"] and 
    speaker != "" and speaker is not None and 
    self.config.talker_config.spk_is_dialect[speaker.lower()] != False):
    dialect = self.config.talker_config.spk_is_dialect[speaker.lower()]
    language_id = self.config.talker_config.codec_language_id[dialect]
```

這段邏輯：
- 當 language 是 `chinese` 或 `auto` 時
- 如果 speaker 的 `spk_is_dialect` 不是 `False`（即有值如 `sichuan_dialect`、`beijing_dialect`）
- 會把 language 覆寫成那個 dialect

對於普通 speaker（如 `hk_cantonese`），必須設為 `False` 否則會去 `codec_language_id` 找 `'False'` 這個 key。

## 訓練建議（PEFT 格式）

如果要從頭訓練 cantonese LoRA：
1. Base model：`Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice`
2. 格式：PEFT/QLoRA（直接用 HuggingFace trainer 或 peft library）
3. Target modules：`['q_proj', 'k_proj', 'v_proj', 'o_proj', 'gate_proj', 'up_proj', 'down_proj']`
4. 訓練數據的 speaker 標籤：用 `hk_cantonese`（需和推理時一致）
5. Merge：`PeftModel.from_pretrained(...).merge_and_unload()`
