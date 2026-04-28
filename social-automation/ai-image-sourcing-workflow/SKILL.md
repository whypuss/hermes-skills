---
name: ai-image-sourcing-workflow
description: AI Agent 透過人類視覺輔助完成「搜圖→本地保存→上傳」的流程。核心原則：AI 擅長決策和上傳，人類擅長視覺選擇。
category: social-automation
---

# AI Image Sourcing Workflow

## 核心原則
- **AI 擅長**：發送指令、調用工具、下載檔案、決策上傳
- **人類擅長**：視覺識別、理解語境、選擇合適圖片
- **流程**：Chrome 視覺瀏覽（人類）→ URL 回傳 AI → AI 下載本地 → AI 上傳社交平台

## 為何不能無頭爬蟲
所有主流搜索引擎（Bing Images、Google Images、DuckDuckGo）在 2024+ 都用 JavaScript 動態載入縮圖，純 HTTP 請求返回的不是真實圖片 URL。嘗試 headless scraping 是浪費時間。

## human-mcp 工具

運行：`cd ~/human-mcp && uv run python server.py`
端點（base: `http://localhost:8080`）：

| 方法 | 端點 | 功能 |
|------|------|------|
| POST | /search?query=xxx&engine=bing | Chrome 開啟視覺搜圖 |
| GET | /download?url=xxx&filename=xxx | 下載圖片到 ~/Downloads/mcp_images/ |
| GET | /list | 列出已下載圖片（含路徑） |
| GET | /batch-download?urls=url1,url2 | 批量下載 |

## 實作 workflow（與 social-mcp 聯動）

### 流程圖
```
1. AI: POST /search {"query": "曼城奪冠", "engine": "bing"}
   → Chrome 自動開啟 Bing Images

2. 人類: 視覺瀏覽 → 右鍵 → Copy image address → 貼給 AI

3. AI: GET /download?url=<人類貼的URL>
   → {"path": "/Users/whypuss/Downloads/mcp_images/img_xxx.jpg", ...}

4. AI: social-mcp.post_facebook(image_path=<local_path>, message="...")

5. AI: GET /list 確認已上傳
```

### 範例指令序列
```bash
# Step 1: 開 Chrome 視覺搜圖
curl -X POST http://localhost:8080/search \
  -H 'Content-Type: application/json' \
  -d '{"query": "曼城奪冠", "engine": "bing"}'

# Step 2: 人類複製 URL 後，下載
curl -s "http://localhost:8080/download?url=https%3A%2F%2Fexample.com%2Fimage.jpg"

# Step 3: 確認
curl -s http://localhost:8080/list | python3 -c "import sys,json; ..."
```

## 與 social-mcp 整合要點

social-mcp 的 `post_facebook` / `post_instagram` 等工具吃本地檔案路徑。
human-mcp 的 `/download` 返回 `path` 欄位可直接作為 social-mcp 的 `image_path` 參數。

```
human-mcp.download → path: "/Users/.../mcp_images/img_xxx.jpg"
                                        ↓
                           social-mcp.post_facebook(image_path=path, ...)
```

## 已知限制
- `/scrape`（無頭解析搜索引擎）對現代 Bing/Google 無效，不需要再嘗試
- 搜索引擎返回 base64 嵌入圖片或延遲載入，無法從 HTML 提取真實 URL
- 解決方案：人類視覺選擇是正確的分工，不需要繞過

## Chrome DevTools Protocol 注意（過去踩過的坑）
- `/json/new` 需要 **PUT** method，不是 GET
- URL 包含中文必須 `urllib.parse.quote()` 編碼
- `urllib.request.Request` 變數名不要覆蓋 FastAPI 的 `req` model（用 `cdp_req` 而非 `req`）
