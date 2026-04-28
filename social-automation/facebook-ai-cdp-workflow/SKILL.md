---
name: facebook-ai-cdp-workflow
description: AI Agent 全自動 Facebook 圖文發文工作流 — Google Trends 抓關鍵字 → human-mcp 搜圖 → ai-cdp-browser post_facebook
category: social-automation
---

### Threads 圖文發文（Playwright + CDP，2026-05-01）

## 重要：兩步發布流程
Threads 發文分兩步，錯誤會導致 dialog 永遠不關閉：
- **第 1 步**：填 caption → 加圖片 → 點「新增到串文」（進入第 2 步）
- **第 2 步**（caption 頁）：坐標點擊「發佈」→ 正式發出
- 關鍵：Playwright `locator.click()` 無法觸發 Threads React onClick，必須用 `page.mouse.click(x, y)` 坐標點擊
- URL：使用 `threads.net`（`threads.com` 已失效，顯示「頁面不存在」）

## 實作片段
```python
# 6a: 點「新增到串文」進第 2 步
pub_btn_info = await threads_page.evaluate("""() => {
    const d = document.querySelector('[role="dialog"]');
    const btns = d.querySelectorAll('[role="button"]');
    for (const b of btns) {
        if ((b.innerText || '').includes('新增到串文')) {
            const r = b.getBoundingClientRect();
            return { x: Math.round(r.left + r.width / 2), y: Math.round(r.top + r.height / 2) };
        }
    }
    return null;
}""")
await threads_page.mouse.click(pub_btn_info["x"], pub_btn_info["y"])
await asyncio.sleep(2.5)

# 6b: 在第 2 步坐標點擊「發佈」
pub2_info = await threads_page.evaluate("""() => {
    const d = document.querySelector('[role="dialog"]');
    const btns = d.querySelectorAll('[role="button"]');
    for (const b of btns) {
        if ((b.innerText || '').includes('發佈')) {
            const r = b.getBoundingClientRect();
            return { x: Math.round(r.left + r.width / 2), y: Math.round(r.top + r.height / 2) };
        }
    }
    return null;
}""")
await threads_page.mouse.click(pub2_info["x"], pub2_info["y"])
```

## 圖片上傳：filechooser 優先於 DataTransfer
Threads React 不接受 JS DataTransfer 注入的虛擬 File（Blob URL），必須用 filechooser.set_files() 給予真實作業系統檔案句柄：
```python
fc_set = {"done": False}
def _on_fc(fc):
    asyncio.create_task(_handle(fc))
async def _handle(fc):
    await fc.set_files(image_path)
    fc_set["done"] = True

threads_page.on("filechooser", _on_fc)
await threads_page.locator('[role="dialog"] svg[aria-label="附加影音內容"]').last.click(timeout=3000, force=True)
# wait for fc_set["done"]
```

## Tab 檢測
```python
if ("threads.com/" in pg.url or "threads.net/" in pg.url) and "settings" not in pg.url:
```

## 初始導航（threads.net 而非 threads.com）
```python
await threads_page.goto("https://www.threads.net/", wait_until="domcontentloaded", timeout=30000)
```

---

### Facebook 圖文發文（Playwright + CDP，2026-04-27）

## 流程
1. 打開 Chromium（9333 port，CDP mode）
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

### 4. 圖片注入方式（2026-04-28 實測確認）

**Facebook 不接受 `set_input_files`** — Playwright 的 `set_input_files` 無法觸發 Facebook React 的 `onChange` handler，導致 dialog 內 `imgs: 0`（圖片從未上傳）。

**✅ 正確方式（commit 9ebd64b 實測成功）：base64→Blob→File→DataTransfer 注入**

✅ 驗證成功信號：`blob:https://www.facebook.com/...` URL 出現在 dialog 內 img 標籤，確認 FB 已收到並處理圖片。
✅ 發文成功驗證：文章出現 `scontent-hkg1-*.xx.fbcdn.net` CDN 網址，確認圖片真正上傳到 Facebook。

```python
import base64 as _b64
with open(image_path, "rb") as f:
    b64_data = _b64.b64encode(f.read()).decode()

inject_r = await fb.evaluate("""(b64) => {
    const binaryString = atob(b64);
    const bytes = new Uint8Array(binaryString.length);
    for (let i = 0; i < binaryString.length; i++) {
        bytes[i] = binaryString.charCodeAt(i);
    }
    const blob = new Blob([bytes], { type: 'image/jpeg' });
    const file = new File([blob], 'upload.jpg', { type: 'image/jpeg', lastModified: Date.now() });
    const inputs = document.querySelectorAll('input[type=file]');
    for (let i = 0; i < inputs.length; i++) {
        const inp = inputs[i];
        const dt = new DataTransfer();
        dt.items.add(file);
        Object.defineProperty(inp, 'files', {
            value: dt.files, writable: true, configurable: true
        });
        const tracker = inp._valueTracker;
        if (tracker) { tracker.setValue(''); }
        inp.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
        inp.dispatchEvent(new Event('change', { bubbles: true, composed: true }));
    }
    return { ok: true, inputsUpdated: inputs.length };
}""", b64_data)
```

**驗證成功信號**：dialog 內出現 `blob:https://www.facebook.com/...` URL，說明 FB 已收到圖片並建立 blob URL。

### 5. 圖片預覽檢測位置
新版 FB：blob URL **在 dialog 內**（commit 9ebd64b 實測確認）：
```javascript
var d = document.querySelector('[role=dialog]');
if (!d) return null;
var imgs = d.querySelectorAll('img[src]');
for (var img of imgs) {
    var src = img.src || '';
    if (src.startsWith('blob:')) return src.slice(0, 80);
}
return null;
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
2. **不要用 `set_input_files`** — Facebook React 不響應 `set_input_files`，必須用 `base64→Blob→File→DataTransfer` 注入
3. **dialog 可能是關閉狀態** — 頁面載入就存在，需檢查 `hasEditor`
4. **blob 在 dialog 內** — 圖片預覽 blob URL 在 dialog 內，不在 page 層級（實測確認）
5. **human-mcp 用 localhost:8080** — AIpuss-browser 是 AIpuss-browser，human-mcp 是另一個 server
6. **上傳後不要按 Escape** — OS 選擇框會自動關，Escape 干擾事件鏈
## Article 生成（已解決 — CDP Browser Gemini 無需登入）

**重要發現（2026-04-28）**：Gemini 網頁版**不需要 Google 登入**就能免費使用。CDP browser (port 9333) 的 Chromium 可以直接打開 `https://gemini.google.com/app` 並使用。

### 完整自動化流程
```
關鍵字 → CDP Gemini 生成文章 → human-mcp 搜圖 → post_facebook 圖文發布
```

### Step 2a（新增）: CDP Browser 開 Gemini 並生成文章

```python
import asyncio
from playwright.async_api import async_playwright
from social_mcp.browser_hijack import get_active_cdp_port

async def gemini_generate(topic: str) -> str:
    port = get_active_cdp_port()
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp(f"http://localhost:{port}", timeout=15000)
        ctx = browser.contexts[0]

        # 找 Gemini 分頁，或新建
        gemini = None
        for pg in ctx.pages:
            if "gemini.google.com" in pg.url:
                gemini = pg
                break
        if not gemini:
            gemini = await ctx.new_page()
            await gemini.goto("https://gemini.google.com/app", wait_until="domcontentloaded", timeout=20000)
            await asyncio.sleep(5)

        await gemini.bring_to_front()

        # 定位編輯區域（新版是 contenteditable div，不是 textarea）
        await gemini.click('[contenteditable="true"]', timeout=5000)
        await asyncio.sleep(1)

        # 清空舊內容
        await gemini.keyboard.press('Control+A')
        await asyncio.sleep(0.3)
        await gemini.keyboard.press('Delete')
        await asyncio.sleep(0.5)

        # 構造 prompt
        prompt = f"""請用繁體中文為 Facebook 粉絲專頁撰寫一篇 100 字以內的貼文，內容關於：{topic}

要求：
- 吸引眼球的內容
- 100字以內
- 加入5個相關hashtag
- 活潑的語氣
- 不要用emoji

直接給我文章內容即可。"""

        # 用 keyboard.type 打字（比 execCommand insertText 可靠）
        await gemini.keyboard.type(prompt, delay=30)
        await asyncio.sleep(1)

        # 按 Enter 發送
        await gemini.keyboard.press('Enter')
        print("已發送，等待 Gemini 回覆...")

        # 等候回覆（檢測 "Gemini 說了" 出現）
        for i in range(20):
            await asyncio.sleep(2)
            try:
                body = gemini.frame.inner_text() if gemini.frame else await gemini.evaluate("() => document.body.innerText")
                user_idx = body.rfind('你說了')
                if user_idx >= 0:
                    rest = body[user_idx + 20:]
                    gemini_idx = rest.find('Gemini 說了')
                    if gemini_idx >= 0:
                        response = rest[gemini_idx + 20:].split('要求：')[0].strip()
                        # 清理殘留 prompt
                        if len(response) > 30:
                            await browser.close()
                            return response
            except Exception:
                pass
            print(f"[{2*(i+1)}s] waiting...")

        await browser.close()
        return None
```

### 關鍵技術細節

| 項目 | 發現 |
|------|------|
| 編輯區域 | `contenteditable="true"` DIV（不是 textarea） |
| 打字方式 | `keyboard.type()` + `Control+A` `Delete` 清空 |
| 發送方式 | `keyboard.press('Enter')` |
| 用戶消息標記 | `你說了`（出現在消息上方） |
| AI 回覆標記 | `Gemini 說了` |
| 登入需求 | **不需要**，免費版 Gemini 即可用 |
| 回覆解析 | `document.body.innerText`（非標準 message bubble selector） |

### 陷阱

1. **不要用 CDP JS execCommand insertText** — 對 `contenteditable` div 無效，必須用 `keyboard.type()`
2. **不要等 `[data-message-author-role]`** — 新版 Gemini 不使用這個屬性
3. **不要用 `continue=https://gemini.google.com/` 登入** — CDP browser 無 Google session，直接跳過登入
4. **耐心等回覆** — Gemini 生成需要 5-15 秒
