---
name: facebook-ai-cdp-workflow
description: AI Agent 全自動 Facebook 圖文發文工作流 — Google Trends 抓關鍵字 → human-mcp 搜圖 → ai-cdp-browser post_facebook
category: social-automation
---

# Facebook AI-CDP 全自動發文 Workflow

## 完整流程
```
Google Trends US 熱搜
    → human-mcp /scrape 自動搜圖下載
    → ai-cdp-browser post_facebook 圖文發布
```

## Step 1: 抓 Google Trends US 熱搜關鍵字

```python
import asyncio
from playwright.async_api import async_playwright
from social_mcp.browser_hijack import get_active_cdp_port

async def get_gtrends():
    port = get_active_cdp_port()
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp(f"http://localhost:{port}", timeout=15000)
        ctx = browser.contexts[0]
        blank = await ctx.new_page()
        await blank.goto("https://trends.google.com.tw/trending?geo=US",
                         wait_until="domcontentloaded", timeout=30000)
        await asyncio.sleep(6)  # JS 重渲染，需要等 6s
        
        body_text = await blank.evaluate('() => document.body.innerText')
        # 解析趨勢：從 "目前的熱門趨勢" 到 "依名稱排序" 之間的文字
        trends_section = body_text.split("目前的熱門趨勢")[1].split("依名稱排序")[0]
        # 過濾：非純數字、長度 3-40、有字母、非導航關鍵字
        ...
        await blank.close()
        await browser.close()
```

注意：
- **不要等 `networkidle`** — Google Trends 會一直有 long-polling 请求
- **需要 sleep 6s** — 頁面 JS 重渲染trend列表需要時間
- 趨勢出現在 `rotary clipper` 圖標後面，格式如：`"pistons vs magic\n20萬+\n1,000%\n2 小時前"`

## Step 2: human-mcp 全自動搜圖下載

```bash
# 確認 server 在跑
curl -s http://localhost:8080/

# 全自動搜圖下載（用 Bing，AIpuss-browser Chromium 是閒置分頁）
curl -s "http://localhost:8080/scrape?query=pistons+vs+magic+basketball&engine=bing&max_images=3"
# 返回: {"downloaded": 3, "images": [{"local_path": "/Users/.../img.jpg", "url": "..."}]}
```

**不需要參數發給 AIpuss-browser**，直接 HTTP request 到 human-mcp server。

## Step 3: ai-cdp-browser post_facebook 圖文發布

```bash
cd /Users/whypuss/.kimaki/projects/ai-cdp-browser
source .venv/bin/activate
python -m social_mcp.post_facebook \
  "🏀 Pistons vs Magic — 激烈 NBA 對決！🔥" \
  "/Users/whypuss/Downloads/mcp_images/img_xxx.jpg"
```

## 關鍵修復記錄（FB 2025 DOM 大改）

### 1. Composer 點擊目標
舊：`querySelector('[role="button"]')` + `innerText.includes('想')`
新：`querySelectorAll('[role=button]')` 遍歷，找 `text.includes('新鮮事')` 或 `text.includes('在想什麼')`

### 2. Dialog 檢測（區分打開/關閉）
```javascript
// 壞的：所有 dialog 都匹配（包含關閉的）
var d = document.querySelector('[role="button"][aria-label*="發佈"]');

// 好的：只檢測有 editor 的（打開的 dialog）
var d = document.querySelector('[role="button"][aria-label*="發佈"]');
var hasEditor = d?.querySelector('[contenteditable="true"]') !== null;
if (!hasEditor) d = null;
```

### 3. Text Editor 位置
新版 FB：editor **不在 dialog 內**，是頁面上的獨立元素：
```javascript
var allCE = document.querySelectorAll('[contenteditable="true"][role="textbox"]');
var e = allCE.length > 0 ? allCE[0] : null;
```

### 4. 圖片注入方式
**舊（壞的）**：DataTransfer + base64 注入 → React input.files 不接受
**新的（正確的）**：
```python
file_input = fb.locator('input[type="file"]').first
await file_input.set_input_files(image_path)  # Playwright 原生方法
```

### 5. 圖片預覽檢測位置
新版 FB：blob URL **在 page 層級**，不在 dialog 內：
```javascript
// 先在 dialog 內找
var blobUrl = null;
// ...
// 新版 FB: blob img 在 page 層級
if (!blobUrl) {
    var pageBlobs = document.querySelectorAll('img[src^="blob:"]');
    if (pageBlobs.length > 0) blobUrl = pageBlobs[0].src;
}
```

### 6. 強制刷新乾淨狀態
每次 post 前強製刷新，確保 dialog 是關閉狀態：
```python
await fb.goto("https://www.facebook.com", wait_until="load", timeout=20000)
await asyncio.sleep(3)
```

### 7. Dialog 等待關鍵字（新版 aria-label）
新版 FB 的 dialog 關鍵字在 `aria-label` 不在 `innerText`：
```javascript
var text = (d.innerText || '') + '|' + (d.getAttribute('aria-label') || '');
if (keywords.some(k => text.includes(k))) return true;
```

### 8. 圖上傳後 **不要按 Escape**
OS 文件選擇框會自動關閉，按 Escape 可能干擾 FB 事件鏈。直接等 blob 預覽出現即可（3-5s）。

## 驗證方法

成功後在 CDP browser 確認：
```python
result = await fb.evaluate('''() => {
    const articles = document.querySelectorAll("article");
    for (const a of articles) {
        if (a.innerText.includes("Pistons")) {
            return { found: true, imgs: a.querySelectorAll("img").length };
        }
    }
}''')
```

## 陷阱
1. **不要等 networkidle** — FB 和 Trends 都會一直有請求
2. **不要用 DataTransfer base64** — FB React 不接受，必須用 `set_input_files`
3. **dialog 可能是關閉狀態** — 頁面載入就存在，需檢查 `hasEditor`
4. **blob 在 page 不在 dialog** — 檢測預覽要查 page 層級
5. **human-mcp 用 localhost:8080** — AIpuss-browser 是 AIpuss-browser，human-mcp 是另一個 server
6. **上傳後不要按 Escape** — OS 選擇框會自動關，Escape 干擾事件鏈

## Article 生成（待完成）
目前流程：關鍵字 → 圖片 → **手動寫文**（Gemini API 未設定）

**需要設定 Gemini API Key** 才能全自動：
```bash
# 方案A：設定環境變數
export GEMINI_API_KEY=your_key_here

# 方案B：用 curl 呼叫 Gemini API
curl -X POST "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${GEMINI_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"contents":[{"parts":[{"text":"以「{關鍵字}」為主題，寫一篇100字中文Facebook貼文，包含5個hashtag"}]}]}'
```

**注意**：CDP browser (port 9333) 無 Google 登入，無法透過 AI Studio 網頁自動化生成文章。
