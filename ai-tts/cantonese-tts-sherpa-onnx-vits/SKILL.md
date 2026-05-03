---
name: cantonese-tts-sherpa-onnx-vits
description: Run Cantonese TTS using sherpa-onnx + VITS (csukuangfj/vits-cantonese-hf-xiaomaiiwn, 108MB). Real Cantonese pronunciation on macOS/Linux with 8GB RAM.
category: ai-tts
---

# Cantonese TTS — sherpa-onnx VITS (macOS/Linux)

## Situation
Need Cantonese TTS that actually produces Cantonese pronunciation (not Mandarin with yue flag). Qwen3-TTS `language: yue` only adjusts prosody, not pronunciation. Coqui Cantonese (5.61GB) too large for 8GB RAM machines.

## Solution
`csukuangfj/vits-cantonese-hf-xiaomaiiwn` — 108MB ONNX VITS model, fast inference, real Cantonese pronunciation.

## Setup

```bash
pip install sherpa-onnx hf_transfer
HF_HUB_ENABLE_HF_TRANSFER=1 python -c "from huggingface_hub import snapshot_download; print(snapshot_download('csukuangfj/vits-cantonese-hf-xiaomaiiwn'))"
```

Model lands at: `~/.cache/huggingface/hub/models--csukuangfj--vits-cantonese-hf-xiaomaiiwn/snapshots/<hash>/`

Files needed: `vits-cantonese-hf-xiaomaiiwn.onnx`, `lexicon.txt`, `tokens.txt`

## Python API (sherpa-onnx >= 1.12)

```python
import sherpa_onnx, numpy as np, wave, os

model_dir = "/path/to/model/snapshots/<hash>"

tts_config = sherpa_onnx.OfflineTtsConfig(
    model=sherpa_onnx.OfflineTtsModelConfig(
        vits=sherpa_onnx.OfflineTtsVitsModelConfig(
            model=os.path.join(model_dir, "vits-cantonese-hf-xiaomaiiwn.onnx"),
            lexicon=os.path.join(model_dir, "lexicon.txt"),
            tokens=os.path.join(model_dir, "tokens.txt"),
            data_dir="",  # MUST be empty string when using lexicon
        ),
        provider="cpu",
        num_threads=4,
    ),
    rule_fsts="",  # empty string, not omitted
    max_num_sentences=1,
)

tts = sherpa_onnx.OfflineTts(tts_config)
# tts.sample_rate  # 22050
# tts.num_speakers  # 0 (single speaker)

# Generate — sid and speed go directly to generate(), NOT GenerationConfig
audio = tts.generate("你好，我係阿明。今日天氣點樣？", sid=0, speed=1.0)

# Save WAV
samples_int16 = (np.array(audio.samples) * 32767).astype(np.int16)
with wave.open("output.wav", 'wb') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(audio.sample_rate)
    f.writeframes(samples_int16.tobytes())
```

## Known Pitfalls

1. **data_dir must be empty string** — if omitted, validation requires `phontab` which doesn't exist. Use `data_dir=""` when providing `lexicon`.
2. **rule_fsts must be empty string** — not `None` and not omitted. `rule_fsts=""` works fine.
3. **GenerationConfig doesn't accept args** — `sherpa_onnx.GenerationConfig(sid=0, speed=1.0)` raises TypeError. Pass `sid` and `speed` directly to `tts.generate()`.
4. **TTS API via sherpa-onnx/cli** — `sherpa_onnx.OfflineTts(model_dir)` doesn't work; must use the config pattern above.
5. **sherpa-onnx TTS requires OfflineTtsConfig → OfflineTtsModelConfig → OfflineTtsVitsModelConfig** — three-level nesting is mandatory.

## Performance
- Model size: 108MB ONNX
- RTF: ~0.23 (0.5s to generate 2.2s audio on M1)
- Memory: fits easily in 8GB RAM
- No GPU required

## Alternative Models Checked (rejected)
- `hgneng/coqui-cantonese-model` — 5.61GB, too large for constrained machines
- `FragmentedSword/Cosyvoice_cantonese` — CosyVoice2 finetune, no standalone checkpoint
- `FunAudioLLM/CosyVoice3-0.5B-2512` — 9GB total, too large
- `FunAudioLLM/CosyVoice2-0.5B` — 4.5GB, too large
