---
name: podcast-gen-setup
description: Qwen3 TTS Podcast Generator — 後端 FastAPI + Vue3 UI 完整架設流程（多音色）
category: ai-audio
tags: [tts, qwen3, podcast, vue3, fastapi]
---

# Podcast Gen — Qwen3 TTS 多音色 Podcast 生成器

## 項目位置
- 後端：`~/.kimaki/projects/podcast-gen/backend/`
- Vue UI：`~/.kimaki/projects/podcast-gen/vue-ui/`

## 架構

```
Vue3 UI (port 5174) ←→ Python Proxy Server ←→ FastAPI Backend (port 8765)
                                                 ←→ Qwen3-TTS Model
```

## 啟動方式

### 後端（FastAPI + Qwen3 TTS）
```bash
cd ~/.kimaki/projects/podcast-gen/backend
uv run --python .venv-tts/bin/python -m uvicorn main:app --port 8765 --host 0.0.0.0
```

### Vue UI — 必須用 Python Server（不是 Node！）
```bash
cd ~/.kimaki/projects/podcast-gen/vue-ui

# 殺掉舊進程
lsof -i :5174 -t | xargs kill -9 2>/dev/null; sleep 1

# 啟動 Python serve.py（不能用 node server.cjs — 在 TailScale 上 Node.js HTTP server 不工作！）
python3 serve.py
```

## 關鍵文件
- `main.py` — FastAPI 後端（/generate, /models/status, /download）
- `qwen3_tts_engine.py` — Qwen3 TTS 封裝（generate / generate_to_file，接受 `voice=` 參數）
- `script_parser.py` — 腳本解析（支援 [男] [男:uncle_fu] 格式）
- `serve.py` — Python static server + API proxy（**不能**用 Node.js server.cjs）
- `audio_merger.py` — FFmpeg 音頻合併（44.1kHz stereo MP3）

## 腳本格式
```
[男] 文字內容                        → 男預設音色（male_voice 參數）
[男:uncle_fu] 文字                  → 指定音色
[男:dylan] 文字                     → Dylan（京腔青年）
[男:eric] 文字                       → Eric（活潑四川）
[女] 文字內容                        → 女預設音色（female_voice 參數）
[女:serena] 文字                     → Serena（溫柔）
[女:ono_anna] 文字                   → Ono Anna（日語）
```

## 可用音色（Qwen3 CustomVoice）
| 性別 | ID | 名稱 |
|------|----|------|
| 男 | `uncle_fu` | 沉穩大叔（預設） |
| 男 | `dylan` | 京腔青年 |
| 男 | `eric` | 活潑四川 |
| 女 | `vivian` | 亮麗女聲（預設） |
| 女 | `serena` | 溫柔女生 |
| 女 | `ono_anna` | 日語女聲 |

## generate POST body
```json
{
  "script": "[男] 你好\n[女] 你好",
  "language": "mandarin",
  "speed": 1.0,
  "male_voice": "uncle_fu",
  "female_voice": "vivian"
}
```

## TailScale 部署（重要！）

### macOS 上的陷阱
**Node.js HTTP server 無法在 macOS 上透過 TailScale utun 正常運作！**
- TCP 握手成功，但 HTTP 請求永遠超時無 response
- 解決方案：使用 Python `http.server` + 自定義 TCPServer

### serve.py 關鍵實現要點

1. **必須繼承 `http.server.SimpleHTTPRequestHandler` 並設置 `self.directory`**
2. **`guess_type(self, path)`** — 必須接收 `path` 參數，否則與父類簽名衝突導致空響應
3. **API_PATHS 判斷** — 以 `startswith` 匹配 `/generate`, `/models`, `/health`, `/download`
4. **urllib.request.urlopen** — 比 `subprocess` curl 更穩定

## 已知的坑

### FFmpeg concat 格式
❌ 錯誤：`-f concat,separate`
✅ 正確：`-f concat` + concat demuxer + PCM S16LE 中間檔

### Qwen3 speaker 名稱
❌ 不能用 `male` / `female`（會拋 `ValueError`）
✅ 必須用精確名稱：`uncle_fu`, `dylan`, `eric`, `vivian`, `serena`, `ono_anna`

### 合併後清理
刪除分段 WAV 要在 `merge_wav_segments()` 完成**之後**，否則 merge 讀不到文件。

### Cantonese 不支援
Qwen3 TTS 的 `instruct` 參數**無法**讓模型說粵語，粵語需另開 VITS-Cantonese 引擎。

### 模型加載時間
後端重啟後模型需約 30 秒重新加載，這段時間 `/models/status` 返回 `loaded: false`

### TailScale IP 訪問
- 確認 Mac 和目標設備都連著同一個 TailScale 網路
- TailScale App 必須在 Mac 上運行（網絡擴展由 systemextension 處理，非 userspace）
- `100.77.249.63` 是 MacBook Air 的 TailScale IP
- 用 `curl http://100.77.249.63:5174/` 驗證從本機能否訪問（等同外部視角）
