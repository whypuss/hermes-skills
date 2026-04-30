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

## 架構（非阻塞 + 輪詢）

```
Vue3 UI (port 5174) ←→ Python Proxy Server ←→ FastAPI Backend (port 8765)
                                                 ←→ Qwen3-TTS Model
                                                    ↓ ThreadPoolExecutor
                                                 /jobs/{job_id} 輪詢端點
```

### 非同步流程（關鍵！）
1. `POST /generate` — 立即返回 `{job_id, status: "running"}`（< 0.1s）
2. 後端 `ThreadPoolExecutor(max_workers=2)` 在後台執行 TTS 生成（2-5 分鐘）
3. 前端每 3 秒輪詢 `GET /jobs/{job_id}` 直到 `status: "done"` 或 `"failed"`
4. `GET /jobs/{job_id}?format=json` — 返回 `{job_id, status, segments, output_path, success}`

**為什麼這樣設計：** iPhone 移動網路 HTTP 請求超時 30-60 秒，而 Qwen3 CPU 生成需 2-5 分鐘。非阻塞才能避免斷連。

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
→ 立即返回 `{"job_id": "abc123", "status": "running"}`

## jobs GET 回應
```json
// running 時：
{"job_id": "abc123", "status": "running"}

// done 時：
{"job_id": "abc123", "status": "done", "segments": [...], "output_path": "/tmp/...", "success": true}

// failed 時：
{"job_id": "abc123", "status": "failed", "error": "所有段落生成失敗"}
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

## Timeout 設置

由於非同步輪詢設計，不再需要長 HTTP timeout：
- **Vue App poll** — 每 3 秒輪詢，fetch 本身 < 5 秒
- **serve.py proxy** — urlopen timeout 120 秒（夠輪詢間隔用）

### 進程管理
每次重啟 backend 前，必須 kill 乾淨：
```bash
lsof -i :8765 -i :5174 | grep LISTEN | awk '{print $2}' | sort -u | xargs kill -9 2>/dev/null
sleep 1
```

### serve.py 穩定性
serve.py 在後端處理慢或重啟時會卡死（CLOSE_WAIT 僵屍連接）。跡象：
- `curl http://localhost:5174/` 超時
- `lsof -i :5174` 顯示 `CLOSE_WAIT` 狀態

解決：kill 掉舊的 serve.py，確認 port free，再重啟。

### 驗證服務正常
```bash
# 1. proxy 活著
curl http://localhost:5174/health

# 2. backend 活著
curl http://localhost:8765/health

# 3. 模型已載入（第一次可能 30 秒，之後 instant）
curl http://localhost:8765/models/status

# 4. generate 測試（立即返回 job_id）
curl -X POST http://localhost:8765/generate \
  -H "Content-Type: application/json" \
  -d '{"script":"[男] 測試","language":"mandarin","speed":1,"male_voice":"uncle_fu","female_voice":"vivian"}'

# 5. 輪詢結果（等待 30 秒後）
curl http://localhost:8765/jobs/<job_id>
```

## 已知的坑

### Bug: seg 變量名錯誤（main.py line ~161）
❌ 錯誤：`speaker=speaker, text=text`（未定義變量）  
✅ 正確：`speaker=seg["speaker"], text=seg["text"]`

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
