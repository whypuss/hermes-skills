---
name: social-workflow-image-search
description: Social workflow 三來源全自動發文——Bing 圖片 + Gemini caption + FB/Threads（2026-04-28 更新）
category: social-automation
---

# Social Workflow — 三來源圖文自動發文

## 架構
- 腳本：`~/.kimaki/projects/ai-cdp-browser/scripts/social_workflow_3source.py`
- 來源 1：Google Trends HK（`python3 ...py 1`）
- 來源 2：微博熱搜（`python3 ...py 2`）
- 來源 3：Google Trends US（`python3 ...py 3`）
- 發布平台：Facebook + Threads（無 IG）
- 圖片：Bing Images（Google Images captcha 無法繞過，改用 Bing）
- Caption：Gemini（每個話題生成 100 字正文 + 5 個關鍵詞）

## 常見錯誤與修復

### 1. 圖片下載全部 Timeout
**現象**：`APIRequestContext.get: Timeout 15ms exceeded`（全部失敗）
**原因**：Playwright `timeout=15` 是 15 毫秒，不是 15 秒
**修復**：改用 `requests` library，timeout=10 秒
```python
import requests
r = requests.get(img_url, timeout=10, headers={"User-Agent": "Mozilla/5.0"}, allow_redirects=True)
```

### 2. Bing 圖片 URL 解析
Bing 結果的 URL 在 link 的 `href` 參數 `mediaurl` 裡，不是直接屬性：
```javascript
const links = Array.from(document.querySelectorAll('a[href*="mediaurl"]'));
for (const link of links) {
    const params = new URLSearchParams(link.href.split('?')[1] || '');
    const mediaUrl = params.get('mediaurl');
}
```

### 3. Threads post 需要已打開的 Threads 標籤
**原因**：`post_threads()` 會遍歷 `ctx.pages` 找 `threads.net` URL，找不到就失敗
**修復**：在 workflow Step 5 發布前，先開 Threads 標籤
```python
threads_tab = None
for pg in ctx.pages:
    if "threads.net" in pg.url and "settings" not in pg.url:
        threads_tab = pg
        break
if not threads_tab:
    threads_tab = await ctx.new_page()
    await threads_tab.goto("https://www.threads.net/", wait_until="domcontentloaded", timeout=20000)
    await asyncio.sleep(3)
```

### 4. 微博話題過濾（只發有數字排序的話題）
**需求**：置頂/熱門/推薦帖不發，只發有數字排名的
```javascript
// 只取有數字排序的話題
if (!/^\d/.test(text)) continue;
// 置頂/熱門/推薦跳過
if (cleaned.includes('置顶') || cleaned.includes('热') || cleaned.includes('荐')) continue;
```

### 5. Gemini Caption 正文提取失敗（正文為空）
**現象**：正文只剩關鍵詞，`【正文】` 沒被去掉
**原因**：正則 `re.sub(r"^(Gemini[^\\n]*\\n*|...))"` 無效（`\\n` 是兩個字元不是換行符）
**修復**：直接用字串操作
```python
if clean.startswith("【正文】"):
    clean = clean[len("【正文】"):].strip()
```
**Fallback**：如果正文為空，用話題標題生成一句話
```python
if not body_text and keywords_text:
    body_text = f"針對「{topic}」的熱門討論引發關注。"
```

## IG 發文
- 使用 `post_ig_human.py`（CDP port 9333，FacebookMCP Chromium）
- 流程：trends → human-mcp scrape → Gemini caption → post_ig_human

## human-mcp FB 發文（推薦）
- 腳本：`~/human-mcp/post_facebook.py`（獨立 Python，無外部依賴）
- 特色：DataTransfer API 注入圖片 + execCommand 打字 + CDP JS 按鈕匹配
- 流程：trends → human-mcp /scrape → AI caption → post_facebook.py → FB
- CLI 用法：
```bash
python3 ~/human-mcp/post_facebook.py "caption文字" "/path/to/image.jpg" [cdp_port]
# CDP port 預設讀 ~/.cdp_port（無則 9333）
```

### post_facebook.py 內部流程
1. `connect_over_cdp` 復用 Chromium session（不啟動新瀏覽器）
2. 找已登入 FB 頁面（`facebook.com/` 且非 `/login`）
3. 點擊「在想什麼」composer（找不到會自動重試 3 次）
4. DataTransfer API 注入圖片（base64→Blob→File→DataTransfer，繞過 React input.files 限制）
5. `execCommand("insertText")` 打字進 contenteditable
6. CDP JS `innerText` 匹配點擊「下一頁」→「發佈」
7. 等 dialog 消失（輪詢最多 20s）

### 已知問題：MiniMax 推理模型 content 永遠為空
- `MiniMax-M2.1` / `MiniMax-M2.5` 回覆的 `content` 欄位是空的
- 實際輸出在 `reasoning_content`（推理過程），不適合文案生成
- **解決**：Caption 直接用 AI 自己寫，或用 OpenRouter/Gemini API
- 測試指令：
```bash
curl -s -X POST "https://api.minimax.chat/v1/text/chatcompletion_v2" \
  -H "Authorization: Bearer $MINIMAX_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "MiniMax-M2.1", "messages": [...], "max_tokens": 300}' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['choices'][0]['message']['content'])"
# → 輸出為空！用 head -100 確認
```
- Gemini API key 未設定，需用 Gemini 網頁版（via CDP）

### Gemini 網頁版呼叫注意事項
- CDP 模式下 Gemini 頁面可能有多個分頁，各自殘留對話歷史
- prompt 會被舊對話 context 污染，回覆常不符合預期
- `processing-state-visible` 狀態可能永不解除，但文字內容已完成（chars > 200）
- **不要等 processing 狀態消失**：直接檢查 `len(text) > 阈值`
- 檢查所有 Gemini 分頁的 `.model-response-text`，找最新相關回覆
- 每個新 caption 任務最好開新分頁或重啟 Gemini 對話

### Gemini 電腦版當機徵兆
- prompt 送出後連續 20 次 polling 都是 `proc` 且 char 數不變
- 解決：直接取 `.model-response-text` 最新內容使用

## human-mcp CDP Port 追蹤
- `server.py` 提供 `/cdp-port?port=N` 和 `/active-cdp-port` 端點
- `post_facebook.py` 自動讀取 `~/.cdp_port` 文件取得當前 active CDP port
- 確保 AIpuss-browser 的 CDP 和 human-mcp 腳本共用同一 port

## 驗證端口
```bash
lsof -i :9222 -i :9333
cat ~/.cdp_port
curl -s http://localhost:8080/active-cdp-port
```

## Crons 排程（每小時分散）
- 來源 1：`45m`
- 來源 2：`65m`
- 來源 3：`95m`
每個 cron 只跑一次，跑完就沒了（不是重複循環）。

## 依賴
```bash
source .venv/bin/activate
uv pip install requests -q
```
