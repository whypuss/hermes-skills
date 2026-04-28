---
name: human-mcp-scraper
description: AI Agent 自動搜圖下載工具 — Playwright 無頭渲染 Bing/Google，無需人工干預
category: browser-automation
---

# Human MCP — AI Agent 搜圖工具

## 觸發條件
AI Agent 需要自動搜尋、下載圖片到本地，無需人工干預。

## 架構
```
AI Agent (Hermes)
  → HTTP: POST /search        → Chrome 開啟視覺瀏覽（可選）
  → HTTP: GET  /scrape        → Playwright 無頭渲染 → 全自動下載 → 返回本地路徑
  → HTTP: GET  /download      → 直接下載 URL 到本地
  → HTTP: GET  /batch-download → 批量下載
  → HTTP: GET  /list          → 列出已下載圖片

Python FastAPI server (port 8080)
  → Node.js scraper.js (Playwright headless)
     └─ Chromium 無頭瀏覽器執行 JS，提取 Bing/Google 圖片 URL
```

## 核心發現
- Bing/Google/DuckDuckGo 的圖片搜尋頁面全靠 JavaScript 渲染
- Python HTTP 請求（urllib, requests, httpx）全部拿不到真實圖片 URL
- 解決方案：Playwright (Node.js) headless browser + Python FastAPI subprocess

## 關鍵文件
- `~/human-mcp/server.py` — FastAPI server（有 `/scrape` 端點，綁定 GitHub）
- `~/human-mcp/scraper.js` — Node.js Playwright 爬蟲（不可刪）
- `~/human-mcp/post_ig.js` — Instagram CDP 發文腳本
- `~/.kimaki/projects/human-mcp/` — 舊備份（無 `/scrape`），不要混淆

## 重要：正確的 ~/human-mcp/
- `~/human-mcp/` 是綁定 GitHub 的真正版本，有 `/scrape` + `/download` 端點
- 運行：`cd ~/human-mcp && uv run python server.py`
- `~/.kimaki/projects/human-mcp/` 是舊備份，沒有 `/scrape` 端點

## 啟動方式
```bash
cd ~/human-mcp && uv run python server.py
# 或後台：uv run python server.py > /tmp/human-mcp.log 2>&1 &
```

## API 端點

### GET /scrape — 全自動搜圖下載
```
GET /scrape?query=關鍵字&engine=bing&max_images=6
Response: {
  "query": "...",
  "engine": "bing",
  "found": 6,
  "downloaded": 4,
  "save_dir": "~/Downloads/mcp_images",
  "images": [{"index": 0, "url": "...", "local_path": "/Users/...img.jpg", "title": "..."}]
}
```

### POST /search — Chrome 視覺瀏覽
```json
POST /search
{"query": "台北夜景", "engine": "bing"}
```

### GET /download — 直接下載
```
GET /download?url=https://example.com/image.jpg
```

### GET /list — 列出本地圖片
```
GET /list
```

### GET /batch-download — 批量下載
```
GET /batch-download?urls=url1,url2&prefix=taipei
```

## 陷阱
1. **不能用 Python HTTP 解析 Bing/Google** — 它們用 JS 渲染，response 是空的或 base64 嵌入
2. **scraper.js 是 Node.js** — 不能用 Python playwright（因為要用真實 Chrome profile 的 cookies）
3. **URL 要 URL-encode** — query 參數傳給 subprocess 時需確保編碼正確
4. **下載超時** — 某些圖片 CDN 403/timeout，scraper.js 會 skip 並繼續
5. **不要用 CDP 控制 Chrome** — `/json/new` 要用 PUT 不是 GET，且有 WS 重連問題

## 驗證步驟
```bash
# 1. 確認 server 運行
curl -s http://localhost:8080/ | python3 -m json.tool

# 2. 測試全自動搜圖下載
curl -s "http://localhost:8080/scrape?query=cherry+blossom&engine=bing&max_images=3"

# 3. 確認圖片已下載
ls -la ~/Downloads/mcp_images/*.jpg | tail -5
```
