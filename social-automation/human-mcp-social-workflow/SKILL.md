---
name: human-mcp-social-workflow
description: Human MCP 全自動社群發文 workflow — Google Trends → 搜圖 → FB/Threads 自動發文
category: social-automation
---

# Human MCP — Social Workflow (FB + Threads)

## 觸發條件

當需要完成以下任務時觸發：
- Google Trends 關鍵字 → AI 搜圖 → 社群發文（全自動）
- Facebook 圖文自動發文
- Threads 圖文自動發文
- 從 ai-cdp-browser port 腳本到 human-mcp

## 核心流程

```
Google Trends (關鍵字)
       ↓
human-mcp /scrape (自動下載圖片到 ~/Downloads/mcp_images/)
       ↓
AI 生成 caption（自己寫，或找可用 LLM）
       ↓
post_facebook.py / post_threads.py (CDP 自動發文)
```

## Human MCP 工具

### 1. 搜圖下載
```bash
curl "http://localhost:8080/scrape?query=關鍵字&engine=bing&max_images=3"
# → JSON: {"images": [{"local_path": "/Users/xxx/Downloads/mcp_images/img_xxx_0.jpg", ...}]}
```

### 2. Facebook 發文
```python
import asyncio
from post_facebook import post_facebook

result = asyncio.run(post_facebook(caption, image_path, cdp_port=9333))
# → "✅ Facebook 發文成功"
```

### 3. Threads 發文（需先開 Threads tab）
```python
import asyncio
from post_threads import post_threads

result = asyncio.run(post_threads(caption, image_path, cdp_port=9333))
# → "✅ Posted to Threads in 45.3s"
```

### 4. CDP Port 追蹤
```bash
# server.py 寫入：GET /cdp-port?port=9333
# post_*.py 讀取：~/.cdp_port 文件
```

## 關鍵坑點（已踩過）

### Threads URL 要用 threads.net
threads.com 已失效，會顯示「頁面不存在」。統一用 `https://www.threads.net/`

### Threads Tab 必須先打開
`post_threads.py` 會找現成的 Threads tab，找不到就失敗。
Social workflow 中記得確保 Threads tab 存在。

### Threads 兩步發文流程
1. 點「新增到串文」→ 進入 caption 審查頁
2. 點「發佈」→ 正式發出
按鈕要用 `getBoundingClientRect` → `mouse.click()` 座標，Playwright locator 有時觸發不了 React onClick。

### Threads 圖片上傳方式不同
FB 用 DataTransfer API（base64→Blob→File→DataTransfer）。
Threads 用 `set_input_files()`：先點「附加影音內容」SVG → Playwright `set_input_files()` 直接設檔案（8s 等上傳）。

### Threads 打字用 keyboard.type
FB 用 `execCommand("insertText")`。
Threads 用 `keyboard.type(message, delay=40-80ms)` 擬人速度，避免被判定機器人。

### MiniMax 是推理模型
MiniMax-M2.1/M2.5 的 `content` 永遠為空，實際輸出在 `reasoning_content`。
不適合簡單文案生成，用 AI 自己寫 caption。

### Facebook Dialog 狀態
有時 Dialog 已打開（殘留狀態），再次點擊 composer 會失敗。
程式要檢查 `dialog.is_visible()` 再決定是否要點擊。

### Gemini API Key 可能不存在
hermes 環境只有 MINIMAX_API_KEY，沒有 GEMINI_API_KEY。
不要依賴 Gemini API，直接用 AI 自己寫 caption。

## CDP Port 追蹤架構

```
server.py (寫入 CDP port)
    ↓ GET /cdp-port?port=9333
~/.cdp_port 文件
    ↑ read
post_facebook.py / post_threads.py (connect_over_cdp)
```

## 安裝

```bash
cd ~/human-mcp
pip install fastapi uvicorn playwright
npx playwright install chromium
uv run python server.py
```

## 檔案

- `server.py` — FastAPI HTTP API（搜圖 + CDP port）
- `scraper.js` — Node.js Playwright 無頭爬蟲
- `post_facebook.py` — FB 圖文發文
- `post_threads.py` — Threads 圖文發文
