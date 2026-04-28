---
name: instagram-workflow
description: Instagram 圖文發文（Playwright + CDP，2026-04-27）
category: social-automation
---

# Instagram 圖文發文 workflow

## 環境
- Chromium via `BrowserHijack` (CDP port 9333)
- Playwright Python (uv run)
- 圖片路徑：`/tmp/social*.jpg`

## 核心要點（血淚經驗）

### 1. Caption 輸入框是 `DIV[contenteditable][role=textbox]`，不是 `input[type=text]`！
- DOM 結構：`DIV[contenteditable][role=textbox][aria-label="撰寫說明文字……"]`
- 有兩個 `input[type=text]`（class `x5ur3kl`），它們是別的欄位，不是 caption
- 只找 `[role="dialog"] [role="textbox"]` 才是 caption 輸入框

### 2. Caption 打字：`fill()` 對 contenteditable 有效
- `fill()` 對 `input[type=text]` 無效（React state 收不到）
- `fill()` 對 `DIV[contenteditable][role=textbox]` 有效！
- `press_sequentially()` 也可以但更慢
- 填完後等 3 秒，再按一次 ArrowRight 鍵強迫 React state 同步

```python
textbox = ig.locator('[role="dialog"] [role="textbox"]').first
await textbox.fill(caption)
await asyncio.sleep(3.0)
await ig.keyboard.press("ArrowRight")
await asyncio.sleep(0.5)
```

### 3. 按鈕點擊：只在 dialog 內搜，完整 pointer+mouse 事件鏈
- 全 page 搜尋會點到「捨棄」等錯誤按鈕
- `innerText.trim() === '分享'`（嚴格比對，移除 fallback indexOf）
- 事件鏈：pointerdown → pointerup → mousedown → mouseup → click

### 4. 開頭必須關閉殘留 dialog
-上一次發文失敗後，IG 可能殘留一個未關閉的 dialog
- 再次發文前先按 Escape 關掉殘留 dialog，否則會和新 dialog 衝突

### 5. 流程步驟（實測有效版）
1. **Step 0**: 檢查並按 Escape 關閉殘留 dialog
2. 點「新貼文」（SVG aria-label）
3. 等 2-3s → **此時只會出現一個選擇來源的 dialog**，需再點「從電腦選擇」才會出現 file input
4. File input 出現後 set_input_files 圖片
5. 等 3s → 點兩次「下一步」（CDP JS click）
6. 等 caption 頁出現
7. `fill()` 填 caption → 等 3s → ArrowRight 鍵
8. 點「分享」（CDP pointer+mouse 鏈，在 dialog 內）
9. 等「分享中」→「已分享」
10. 點「完成」（CDP，在 dialog 內）

### 6. IG 新 UI「從電腦選擇」找不到的處理

點擊「新貼文」後，dialog 內的「從電腦選擇」按鈕可能不在常規 DOM 查詢範圍內。處理順序：

```python
# 1. 先試 Playwright locator（最快）
from_computer = ig.locator('button', has_text='從電腦').first
if await from_computer.is_visible(timeout=3000):
    await from_computer.click()

# 2. 再試 CDP Runtime.evaluate（繞過 Playwright 的封裝）
await page.evaluate("""
    () => {
        const targets = [
            () => { const els = document.querySelectorAll('[role="dialog"] button'); for(const e of els) if(e.innerText?.includes('從電腦')) return e; },
            () => { const els = document.querySelectorAll('[role="dialog"] [role="menuitem"]'); for(const e of els) if(e.innerText?.includes('從電腦')) return e; },
            () => { const els = document.querySelectorAll('[role="dialog"] *'); for(const e of els) if(e.innerText?.trim()==='從電腦選擇') return e; },
        ];
        for (const fn of targets) { try { const el = fn(); if(el){ el.click(); return 'ok'; } } catch(e){} }
        return null;
    }
""")

# 3. 等 1.5s 再找一次（dialog 可能異步渲染）
await asyncio.sleep(1.5)
file_input = ig.locator('input[type="file"]').first
```

**永遠不要按 Escape 來關 OS 文件選擇窗口** — 設完 `set_input_files()` 後等 3s，OS 窗口會自動關閉，IG 自己處理。

### 6. 禁用方法
- `keyboard.type()` 對任何元素 ❌（React state 收不到）
- `fill()` 對 `input[type=text]` ❌（要對 contenteditable DIV）
- CDP JS `element.value = caption` ❌
- CDP JS `_valueTracker.setValue('')` ❌
- CDP JS `dispatchEvent(new Event('input'))` 單獨使用 ❌
- 全 page 範圍搜尋按鈕 ❌
- `.click()` 簡單事件（只用 mousedown/mouseup/click）❌

## CDP 連線相容性（重要）

### Chromium CDP 連線方式（2026-05 實測）

**徵狀：** 舊腳本用硬編碼 WS URL（如 `ws://localhost:9333/devtools/browser/xxx`），Chromium 重啟後 URL 失效，playwright 連線失敗。

**✅ 唯一確定有效方案：HTTP endpoint（自動解析）**
```python
# ✅ 這樣連 — HTTP URL，Playwright 自動解析
browser = await p.chromium.connect_over_cdp('http://localhost:9333', timeout=30000)
ctx = browser.contexts[0]
page = await ctx.new_page()          # 可以開新分頁
await page.goto('...')

# ❌ 硬編碼 WS URL（Chromium 重啟後失效）
browser = await p.chromium.connect_over_cdp(
    'ws://localhost:9333/devtools/page/xxx',  # 舊分頁 WS URL，重啟後無效
    timeout=30000
)

# ❌ 瀏覽器層級 WS URL（hang）
browser = await p.chromium.connect_over_cdp(
    'ws://localhost:9333/devtools/browser/xxx',
    timeout=60000
)
```

**底層原因：** Chromium 重啟後，`/devtools/page/xxx` 的 WS URL 全部更換。HTTP endpoint (`http://localhost:9333`) 是 Chromium 的 CDP 入口，Playwright 自動從中取得目前有效的 WS URL 並連線。

**驗證 Chromium 是否在跑：**
```bash
lsof -i :9333  # 應有 Chromium LISTEN
curl -s http://localhost:9333/json  # 返回 tab 清單，說明 CDP 正常
```

## CLI 用法
```bash
uv run python -m social_mcp.post_ig "caption text" /tmp/social.jpg
```

## 腳本 WS URL 陷阱

`scripts/post_instagram.py` 內的 WS URL 是**啟動時動態決定的**（不能寫死）：
```python
# ✅ 動態（正確）
async with async_playwright() as p:
    browser = await p.chromium.connect_over_cdp('http://localhost:9333')
    # Playwright 自動處理 WS URL 解析

# ❌ 硬編碼（Chromium 重啟後失效）
WS_URL = "ws://localhost:9333/devtools/page/xxx"  # 不要這樣寫
```

每次 Chromium 重啟（如系統睡眠喚醒），`/devtools/page/xxx` 和 `/devtools/browser/xxx` 都會更換，寫死在代碼裡的 WS URL 一定會在幾次後失效。

## 社交發文 Cron 故障排查

**徵狀：** social-source1 (gtrends-hk) cron job `last_run_at: null`，從未執行過；CDP connect timeout

**檢查 Chromium 是否在跑：**
```bash
lsof -i :9333  # 應該有 Chromium LISTEN
curl -s http://localhost:9333/json | head -3  # 應該返回 WS URL
```

**確認 Playwright CDP 連線（測試腳本）：**
```python
# social_workflow.py 用的 connect_over_cdp(http://localhost:9333) 會 hang
# 解決：確認 Chromium 已在運行，workflow 只做 connect，不 kill Chromium
# 問題通常是 Chromium 被重啟導致 WS URL 失效
```

## Google Images captcha 問題（2026-04-27）

**徵狀：** social-workflow 所有話題都 `no suitable images`，Google 返回 captcha 頁

**根因：** 伺服器 IP（206.119.151.149）被 Google 全面封鎖，所有 Chromium（無論哪個 CDP port）一律 captcha

**診斷：**
```bash
# 檢查 IP 是否被封
curl -s --max-time 5 "https://api.ipify.org"
# 如果返回 206.119.151.149 = 被封

# 測試 Google Images（會 captcha）
curl -sL "https://www.google.com/search?q=test&tbm=isch" \
  -H "User-Agent: Mozilla/5.0 (Linux; Android 14; Pixel 8)..." \
  | grep -i "sorry\|unusual traffic"  # 有輸出 = captcha
```

**解決方案：將 social_workflow_3source.py 的 Google Images 改用 Bing Images**

social_workflow_3source.py 的 `search_google_image()` 函數：
1. 原本用 `https://www.google.com/search?q=...&tbm=isch` + JS 提取 data:image base64
2. Google captcha 後改為 Bing Images
3. Bing 的圖片 URL 在 `<a href="...?mediaurl=...">` 的 mediaurl 參數裡

**關鍵代碼（Bing Images）：**
```python
async def search_google_image(ctx, topic: str) -> str:
    """用 Bing Images 搜尋 topic，回傳圖片路徑"""
    search_q = urllib.parse.quote(topic[:50])
    
    b_page = await ctx.new_page()
    await b_page.goto(
        f"https://www.bing.com/images/search?q={search_q}&first=1&cw=1280&ch=720",
        wait_until="domcontentloaded", timeout=30000
    )
    await asyncio.sleep(3)
    
    # Bing 的圖片 URL 在 link 的 mediaurl 參數裡
    media_urls = await b_page.evaluate("""() => {
        const links = Array.from(document.querySelectorAll('a[href*="mediaurl"]'));
        const urls = [];
        for (const link of links) {
            const href = link.href;
            try {
                const params = new URLSearchParams(href.split('?')[1] || '');
                const mediaUrl = params.get('mediaurl');
                if (mediaUrl && mediaUrl.startsWith('http')) {
                    urls.push(decodeURIComponent(mediaUrl));
                }
            } catch(e) {}
            if (urls.length >= 8) break;
        }
        return urls;
    }""")
    
    # 直接下載
    for img_url in media_urls:
        async with b_page.context.request.get(img_url, timeout=15) as resp:
            if resp.status == 200 and len(await resp.body()) > 5000:
                ext = "jpg"
                ct = resp.headers.get("content-type", "")
                if "webp" in ct.lower(): ext = "webp"
                elif "png" in ct.lower(): ext = "png"
                out_path = f"/tmp/social3_{int(time.time())}_{random.randint(100,999)}.{ext}"
                with open(out_path, "wb") as f:
                    f.write(await resp.body())
                return out_path
    return None
```

**注意：** 永遠不要嘗試「右鍵另存為」的 CDP 方案：
- CDP `page.mouse.click(button='right')` 無法讀取原生 context menu
- `page.give_files()` 只用於上傳，無法攔截下載對話框
- Google captcha 是 IP 級別的，無瀏覽器指紋繞過可能（除非用代理）

---

## Threads（threads.net）圖文發文（2026-05）

Threads 和 Instagram 共用同一個 Chromium session（threads.com = threads.net）。但 CDP 連線行為不同。

### CDP 連線：browser-level WS URL（Threads 專用）

```python
import urllib.request, json
from playwright.async_api import async_playwright

def get_browser_ws():
    """取得 browser-level WS URL，不要用 page-level WS URL"""
    req = urllib.request.Request(
        "http://localhost:9333/json/version",
        headers={"User-Agent": "Mozilla/5.0 Chrome-CDP-Client"}
    )
    with urllib.request.urlopen(req, timeout=5) as resp:
        return json.loads(resp.read()).get('webSocketDebuggerUrl')

async def _post_threads():
    browser_ws = get_browser_ws()  # ws://localhost:9333/devtools/browser/xxx
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp(browser_ws, timeout=20000)
        # ✅ browser.contexts[0].pages 有內容
        th = browser.contexts[0].pages[0]
        await th.goto('https://www.threads.net', wait_until='load', timeout=30000)
        await asyncio.sleep(5)
        # ... 繼續 workflow
```

**⚠️ 重要差異：**
- 連 `http://localhost:9333`（HTTP endpoint）→ hang，timeout
- 連 page-level WS URL (`/devtools/page/xxx`) → 返回 Browser 物件，但 `contexts[0].pages` 是空的（隔離）
- 連 browser-level WS URL (`/json/version` → `/devtools/browser/xxx`) → 正常，`contexts[0].pages[0]` 是 Threads 分頁

### Threads Composer 步驟

1. 點擊「有什麼新鮮事？」按鈕（`innerText.includes('有什麼新鮮事')`）
2. 等 2s → dialog 出現
3. **圖片上傳（✅正確方式）**：用 `locator.set_input_files()`
   - Threads dialog 的 `input[type=file]` 是 `display:none` + `hidden=False`
   - JS `click()` 這個 input 不會觸發 OS file dialog，Playwright `filechooser` 事件也不會響
   - **正確做法：Playwright `set_input_files()` 直接 CDP 賦值 + 觸發 change 事件**
   ```python
   # 點 SVG 進入選擇媒體狀態（可選，讓 dialog 進入正確狀態）
   await threads_page.locator(
       '[role="dialog"] svg[aria-label="附加影音內容"]'
   ).last.click(timeout=3000, force=True)
   await asyncio.sleep(0.5)

   # 直接用 Playwright set_input_files（CDP setFileInputFiles，繞過 OS dialog）
   inp_locator = threads_page.locator('[role="dialog"] input[type=file]').last
   await inp_locator.set_input_files(image_path, timeout=5000)
   log.debug(f"Image set: {image_path}")

   # 等 Threads 上傳處理（8 秒，blob URL 生成 = 成功信號）
   await asyncio.sleep(8)
   ```
   **千萬不要** 按 Escape 來關 OS 檔案選擇窗口——`set_input_files()` 不觸發 OS dialog，窗口根本不會出現。
4. 等 8s 讓圖片上傳完成（blob URL 出現 = 成功）
5. 打字：找到 `[contenteditable=true]` 或 `[role=textbox]`，`keyboard.type()` 輸入文字
6. 點「新增到串文」（dialog 內，坐標 mouse.click）
7. 等 3s
8. 點「發佈」（dialog 內，坐標 mouse.click）
9. 等 10s → dialog 自動關閉 = 成功

### Threads 驗證 profile URL

用戶名不是 IG 用戶名！要從 Threads 首頁找：
```python
profile_info = await th.evaluate("""() => {
    const links = document.querySelectorAll('a[href*="/@"]');
    const usernames = [];
    for (const l of links) {
        const href = l.getAttribute('href');
        if (href && !href.includes('/repost') && !href.includes('/tag')) {
            usernames.push(href);
        }
    }
    return [...new Set(usernames)].slice(0, 5);
}""")
# 結果：['/@whypuss_fun', '/@is.this.ramen', ...]
# profile URL: https://www.threads.net/@whypuss_fun
```

### Threads 的隱藏 file input 模式

Threads dialog 內的 `input[type=file]` 是 `display:none` + `hidden=False`：
- `hidden=False` 不等於可見，瀏覽器仍然 apply `display:none`
- JS `click()` 這個 input 不會觸發 OS file dialog
- `svg[aria-label="附加影音內容"]` 點了也不會自動觸發 filechooser
- **唯一有效方式：`Playwright locator.set_input_files()`**，原理是 CDP `Page.setFileInputFiles` 直接賦值並觸發 React change 事件，完全繞過 OS dialog

### Threads 發文成功判斷

- Dialog 關閉（`!document.querySelector('[role=dialog]')`) = 發文成功
- 驗證：去 `https://www.threads.net/@<username>` 等 6-8s，檢查 body 內是否有關鍵字
- Threads profile 有延遲，發文後馬上查可能還沒出現
