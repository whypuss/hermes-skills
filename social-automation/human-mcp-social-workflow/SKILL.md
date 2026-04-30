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
Gemini (CDP) 生成 caption
       ↓
post_facebook.py / post_threads.py / post_ig_human.py
```

## ⚠️ 架構更新（2026-04-29）：獨立 Chromium Profile

**舊版（CDP 模式，已廢除）**：`connect_over_cdp()` 連接用戶 Chrome，需要提前開瀏覽器、CDP port、browser-hijack MCP。

**新版（獨立 Profile）**：每個腳本用自己的 Chromium，放在專用 profile 目錄，完全獨立。

| 腳本 | Profile | 登入 |
|------|---------|------|
| `post_facebook.py` | `/tmp/fb-chromium-profile/` | 第一次手動登入 |
| `post_threads.py` | `/tmp/threads-chromium-profile/` | 第一次手動登入 |
| `post_ig_human.py` | `/tmp/ig-chromium-profile/` | 第一次手動登入 |

不再需要：CDP port、`.cdp_port` 文件、提前打開瀏覽器。

### 語義點擊架構（Semantic Clicking）

按鈕點擊不再用座標，改用 DOM 語義定位 + 自癒重試：

```
DOM 定位（getByRole / getByText）
       ↓ 找不到
JS dispatchEvent（React 兼容性）
       ↓ 點了沒反應
結果驗證（verify_after 關鍵字）
       ↓ 按鈕還在（UI 變了）
自動重試（最多 3 次）
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

result = asyncio.run(post_facebook(caption, image_path))
# → "✅ Facebook 發文成功"
```

### 3. Threads 發文
```python
import asyncio
from post_threads import post_threads

result = asyncio.run(post_threads(caption, image_path))
# → "✅ Posted to Threads in 45.3s"
```

### 4. Instagram 發文
```python
import asyncio
from post_ig_human import post_ig_human

result = asyncio.run(post_ig_human(caption, image_path))
# → "✅ Instagram 發文成功"
```
流程：新貼文(+) → 從電腦選擇 → 圖片注入(JS DataTransfer) → 裁切下一步×2 → caption輸入 → 分享

## 關鍵坑點（已踩過）

### Google Trends 讀 shadow DOM 要用 inner_text()
Google Trends 的 topic 列表藏在 shadow DOM 裡，`querySelectorAll` 拿不到。
用 `page.locator("body").inner_text()` 然後解析純文字，過濾導航關鍵字和數字行。

### Gemini Caption 解析 Bug
千萬不要在檢查 `"【正文】" in clean` 之前先 `clean = clean[len("【正文】"):]`
會導致檢查永遠為 False，整個回應被當作 body。應該用 `clean.find("【正文】")` 和 `clean.find("【關鍵詞】")` 取得位置，再切片。

### Gemini 回應要截斷 1000+ 字
截斷在 500 字可能剛好切在「【關鍵詞】」區域中間，導致解析失敗。統一用 1000。

### Instagram 圖片注入（CDP mode）
CDP mode（connect_over_cdp）沒有 OS file dialog，必須用 JS DataTransfer：
```javascript
const blob = new Blob([bytes], {type:'image/jpeg'});
const file = new File([blob], 'upload.jpg');
const dt = new DataTransfer(); dt.items.add(file);
Object.defineProperty(inp, 'files', {value: dt.files, writable: true, configurable: true});
inp.dispatchEvent(new Event('change', {bubbles: true, composed: true}));
```

### Instagram expect_file_chooser() API
Playwright 1.58+：`page.expect_file_chooser()` 是 async context manager。
要 `async with ig.expect_file_chooser(timeout=3000) as fc_info`，然後 `fc = await fc_info.value`（value 本身是 coroutine），最後 `await fc.set_files(path)`。

### Python 3.9 asyncio 兼容性
`asyncio.timeout()`（Python 3.11+）不存在。用 `await asyncio.wait_for(coro(), timeout=45)` 代替。

### Threads URL 要用 threads.net
threads.com 已失效，會顯示「頁面不存在」。統一用 `https://www.threads.net/`

### Threads Tab 必須先打開（已廢除）
> ❌ 2026-04-29 起，post_threads.py 用獨立 Chromium Profile，不再需要預先打開 Threads tab。

### Threads 兩步發文流程（語義點擊）
1. 點「新增到串文」→「發佈」
現在用 `SemanticClicker`（DOM getByRole + verify_after 重試），不再用座標 `mouse.click()`。

### Threads 圖片上傳方式不同
FB 用 DataTransfer API（base64→Blob→File→DataTransfer）。
Threads 用 `set_input_files()`：先點「附加影音內容」SVG → Playwright `set_input_files()` 直接設檔案（8s 等上傳）。

### Threads 打字用 keyboard.type
FB 用 `execCommand("insertText")`。
Threads 用 `keyboard.type(message, delay=40-80ms)` 擬人速度，避免被判定機器人。

### Facebook Dialog 狀態
有時 Dialog 已打開（殘留狀態），再次點擊 composer 會失敗。
程式要檢查 `dialog.is_visible()` 再決定是否要點擊。

## CDP Port 追蹤架構（已廢除）

> ❌ 2026-04-29 起廢除。請使用上方「獨立 Chromium Profile」架構。

## 安裝

```bash
cd ~/human-mcp
pip install fastapi uvicorn playwright
npx playwright install chromium
uv run python server.py
```

## 執行 Social Workflow（全自動三平台）

```bash
cd ~/human-mcp
# 來源 1=HK Trends, 2=Weibo, 3=US Trends
python3 social_workflow.py 3
```

## 檔案

- `server.py` — FastAPI HTTP API（搜圖 + CDP port）
- `scraper.js` — Node.js Playwright 無頭爬蟲
- `post_facebook.py` — FB 圖文發文
- `post_threads.py` — Threads 圖文發文
- `post_ig_human.py` — Instagram 圖文發文（CDP 模式）
- `social_workflow.py` — 主流程：Trends → 搜圖 → Gemini caption → FB+Threads+IG 全發
