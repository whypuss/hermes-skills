---
name: cantonese-tts-model-comparison
description: Cantonese TTS model options, Qwen3-TTS limitations, Coqui TTS install workarounds on Mac
category: ai-tts
---

# Cantonese TTS Model Comparison

## Key Insight
Qwen3-TTS (`language: yue`) does NOT produce Cantonese phonemes. It reads Cantonese characters using Mandarin-trained phonemes with modified prosody. Result sounds like Mandarin spoken with Cantonese rhythm — NOT real Cantonese.

## Verified Cantonese TTS Options

### 1. hgneng/coqui-cantonese-model
- **Size:** 5.61 GB (model.pth)
- **Format:** Coqui TTS v2 (not compatible with latest TTS library API)
- **Voices:** demo_female.wav, demo_male.wav (downloadable without full model)
- **Demo URLs:**
  - `https://huggingface.co/hgneng/coqui-cantonese-model/resolve/main/demo_female.wav`
  - `https://huggingface.co/hgneng/coqui-cantonese-model/resolve/main/demo_male.wav`
- **Status:** Model files too large + Coqui API compatibility issues with latest TTS lib

### 2. FragmentedSword/Cosyvoice_cantonese
- **Base:** FunAudioLLM/CosyVoice2-0.5B
- **Type:** Finetuned for Cantonese
- **Status:** CosyVoice requires conda + complex C++ dependencies, heavy install

### 3. GPT-SoVITS Cantonese (undocumented)
- Search HuggingFace for `gpt-sovits+cantonese` — may have community finetunes

### 4. Fun-CosyVoice3-0.5B-2512
- Supports 18+ Chinese dialects including Cantonese
- `https://huggingface.co/FunAudioLLM/Fun-CosyVoice3-0.5B-2512`
- Covers 9 languages + Cantonese in one model
- Heavy (0.5B LLM-based)

## TTS Library (Coqui) Install Pitfalls on Mac

```bash
# Python 3.14 — fails, TTS requires <3.12
/opt/homebrew/bin/python3 -m venv /tmp/tts_venv  # fails

# Python 3.13 — venv creation broken on this Mac
/opt/homebrew/bin/python3.13 -m venv /tmp/tts_venv  # fails

# Python 3.11 — WORKS (qwen3-tts venv uses this)
/opt/homebrew/bin/python3 -m venv /tmp/tts_venv --python 3.11  # may fail
# Use uv instead:
uv venv /tmp/tts_venv --python 3.13 --clear
uv pip install TTS --python /tmp/tts_venv/bin/python --system
```

Or use existing venv:
```bash
source ~/.kimaki/venvs/qwen3-tts/bin/activate  # Python 3.11
pip install TTS  # works
```

## Download Demo Audio (No Full Model Needed)
```bash
curl -sL "https://huggingface.co/hgneng/coqui-cantonese-model/resolve/main/demo_female.wav" -o demo_female.wav
curl -sL "https://huggingface.co/hgneng/coqui-cantonese-model/resolve/main/demo_male.wav" -o demo_male.wav
```

## Recommendation
For real Cantonese TTS in a podcast app:
1. **Best quality:** CosyVoice2 Cantonese finetune — but heavy dependency install
2. **Fastest path:** Fun-CosyVoice3 base model which natively supports Cantonese dialect
3. **Quick test:** Download the demo files first before committing to full model install
