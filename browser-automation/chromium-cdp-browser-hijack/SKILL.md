---
name: chromium-cdp-browser-hijack
description: "用 CDP + Playwright 接管已運行的 Chromium，讀取登入狀態、發文、讀通知。繞過 Graph API 審核限制，直接操作 Facebook 個人帳號。"
tags: ["browser", "facebook", "playwright", "cdp", "social"]
author: Hermes
license: MIT
metadata:
  hermes:
    tags: [browser, facebook, playwright, cdp, social]
---

# Chromium CDP Browser Hijack for Facebook

## 核心問題

Facebook Graph API 不支援個人帳號私訊/通知讀取，且審核極嚴。必須用瀏覽器劫持。

## 關鍵發現

### 陷阱：launch_persistent_context 不能跨 Chromium 版本共享 session

Playwright 自帶的 Chromium (`Google Chrome for Testing`) 和系統安裝的 ungoogled-chromium 的 cookie 加密鑰匙不同。即使指定相同的 `--user-data-dir`，雙方也無法互相解密對方的 cookies。

症狀：`BrowserType.launch_persistent_context: Target page, context or browser has been closed` — Chromium 進程啟動後立即崩潰。

### 正確方案：ungoogled-chromium + CDP pipe

1. 用系統的 ungoogled-chromium 啟動 remote debugging
2. Playwright 用 `connect_over_cdp()` 接管那個瀏覽器

## 步驟

### 1. 啟動 Chromium（remote debugging + 專用 profile）

⚠️ 重要：不要用你日常的 Chromium profile。必須建立**獨立目錄**，否則與常規 Chromium 進程衝突（`USE_PROFILE_DIR` 錯誤）。

```bash
# 建立專用 CDP profile（與你日常 Chromium 完全不同）
mkdir -p "$HOME/Library/Application Support/Chromium/FacebookMCP"

# 啟動 CDP server
"/Applications/Chromium.app/Contents/MacOS/Chromium" \
  --remote-debugging-port=9333 \
  --user-data-dir="$HOME/Library/Application Support/Chromium/FacebookMCP" \
  --profile-directory="Default" \
  --no-first-run \
  --no-default-browser-check \
  --window-size=1280,720 \
  >> /tmp/chromium-fb.log 2>&1 &
sleep 8
```

⚠️ 若 Chromium 提示 `USE_PROFILE_DIR` 衝突，表示已有相同 profile 的 Chromium 進程在運行（可能是常規 Chrome）。先關掉所有 Chromium 視窗再重試。

### 2. 確認 Chromium 正在運行

```bash
kill -0 $! && echo "alive"
lsof -i :9333 | grep LISTEN
```

### 3. 發現 Facebook 頁面的 CDP WebSocket URL

```python
import urllib.request, json

resp = urllib.request.urlopen('http://localhost:9333/json', timeout=5)
targets = json.loads(resp.read())
for t in targets:
    if 'facebook' in t.get('title', '').lower():
        print(t['webSocketDebuggerUrl'])
        # 例如: ws://localhost:9333/devtools/page/XXXX
```

### 4. CDP 接管並讀取狀態

```python
async def check():
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp('http://localhost:9333')
        ctx = browser.contexts[0]
        for page in ctx.pages:
            if 'facebook' in page.url:
                await page.goto('https://www.facebook.com', wait_until='domcontentloaded')
                await asyncio.sleep(3)
                body = await page.inner_text('body')
                # 登入判斷
                if '動態' in body or '動態時報' in body:
                    print('LOGGED IN')
                elif '登入' in body[:400]:
                    print('NOT LOGGED IN')
```

### 5. 發布 Facebook 貼文

```python
async def post_facebook(message: str) -> str:
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp('http://localhost:9333')
        ctx = browser.contexts[0]
        # 找到已開啟的 Facebook 分頁
        fb_page = None
        for pg in ctx.pages:
            if 'facebook.com' in pg.url:
                fb_page = pg
                break
        if not fb_page:
            return "❌ No Facebook page found."

        await fb_page.goto("https://www.facebook.com", wait_until="domcontentloaded")
        await asyncio.sleep(3)

        # ── 登入判斷 ──
        body = await fb_page.inner_text("body")
        if "登入" in body[:400] and "電子郵件" in body[:400]:
            return "❌ Not logged in. Run open_login_window() first."

        # ── 點擊發文框（aria-label 已改為「建立帖子」） ──
        try:
            composer = fb_page.locator('[aria-label="建立帖子"]').first
            await composer.click(timeout=8000)
            await asyncio.sleep(2)
        except Exception as e:
            return f"❌ Could not open composer: {e}"

        # ── 輸入文字 ──
        await fb_page.keyboard.type(message, delay=20)
        await asyncio.sleep(1)

        # ── 多步 composer：有些帳號會有「下一頁」按鈕 ──
        try:
            next_btn = fb_page.locator('[aria-label="下一頁"]').first
            await next_btn.click(timeout=5000)
            await asyncio.sleep(2)
        except Exception:
            pass  # 有些帳號不需要

        # ── 點擊發布 ──
        try:
            post_btn = fb_page.locator('[aria-label="發佈"]').first
            await post_btn.click(timeout=8000)
            await asyncio.sleep(4)
        except Exception as e:
            return f"❌ Could not click post button: {e}"

        # ── 驗證 ──
        body = await fb_page.inner_text("body")
        if "Hermes" in body or "自動發文" in body or "發佈" in body:
            return "✅ Post published successfully!"
        else:
            return "⚠️ Post may have been published. Check your Facebook wall."

asyncio.run(post_facebook("Hello from Hermes Agent! 🚀"))
```

### Threads 發文 — 優化版（CDP + Playwright 混合，6-7秒完成）

```python
"""
CDP + Playwright 混合：CDP 負責快速連接+輸入，Playwright.mouse.click() 負責可靠點擊
速度：~6-7秒（vs 純 Playwright 的 ~60秒）
關鍵發現：CDP Input.dispatchMouseEvent 在 Lexical modal 下無效，必須用 Playwright
"""
import asyncio, json, time
from playwright.async_api import async_playwright
import httpx, websockets

async def post_threads_fast(message: str, unique_id: str = None) -> str:
    t0 = time.time()
    if unique_id is None:
        unique_id = f"TS_{int(time.time())}"
    
    # === CDP: 快速連接 + text input ===
    async with httpx.AsyncClient() as client:
        resp = await client.get("http://localhost:9333/json/version", timeout=10)
        browser_ws = resp.json().get("webSocketDebuggerUrl")
        resp = await client.get("http://localhost:9333/json", timeout=10)
        tabs = resp.json()
    
    tab_ws = None
    for t in tabs:
        if t.get("url", "") == "https://www.threads.com/":
            tab_ws = t.get("webSocketDebuggerUrl")
            break
    
    if not tab_ws:
        return "❌ No threads.com/ tab found"
    
    async with websockets.connect(tab_ws, max_size=20*1024*1024) as ws:
        async def cdp_send(method, params=None):
            await ws.send(json.dumps({"id": 1, "method": method, "params": params or {}}))
            return json.loads(await ws.recv())
        
        async def js(code):
            r = await cdp_send("Runtime.evaluate", {"expression": code, "returnByValue": True})
            return r.get("result", {}).get("result", {}).get("value")
        
        # 點擊 composer
        await js('''document.querySelector('[aria-label="文字欄位空白。請輸入內容以撰寫新貼文。"]').click()''')
        await asyncio.sleep(0.3)
        
        # focus editor
        await js('''(document.querySelector('[contenteditable="true"]') || {focus:()=>{}}).focus()''')
        
        # 用 CDP Input.dispatchKeyEvent 輸入（比 Playwright keyboard.type 快）
        async def send_key(ch):
            if ch == " ":
                code, kc = "Space", 32
            elif ch.isalpha():
                code, kc = f"Key{ch.upper()}", ord(ch.upper())
            else:
                code, kc = ch, 0
            for t in ["keyDown", "keyUp"]:
                await cdp_send("Input.dispatchKeyEvent", {
                    "type": t, "text": ch, "key": ch.upper() if ch.isalpha() else ch,
                    "code": code, "windowsVirtualKeyCode": kc
                })
        
        for ch in message:
            await send_key(ch)
            await asyncio.sleep(0.006)  # ~166 char/s
        
        # 找 modal 發佈按鈕座標（y 最大的那個 = modal 內的）
        btn = await js('''
            (() => {
                let best = null;
                for (const d of document.querySelectorAll("div")) {
                    if (d.innerText?.trim() === "發佈" && d.getAttribute("role") === "button") {
                        const r = d.getBoundingClientRect();
                        if (r.width > 0 && r.height > 0 && r.height < 50 && r.width < 100) {
                            if (!best || r.top > best.top) {
                                best = { x: r.left + r.width/2, y: r.top + r.height/2, top: r.top };
                            }
                        }
                    }
                }
                return best;
            })()
        ''')
    
    # === Playwright: 可靠的座標點擊（CDP Input.dispatchMouseEvent 無法穿透 Lexical overlay）===
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp("http://localhost:9333", timeout=10000)
        ctx = browser.contexts[0]
        
        threads_page = None
        for pg in ctx.pages:
            if pg.url == "https://www.threads.com/":
                threads_page = pg
                break
        
        if btn and threads_page:
            await threads_page.mouse.click(btn["x"], btn["y"])
        
        await asyncio.sleep(4)
        
        # 驗證
        body = await threads_page.inner_text("body")
        if unique_id in body or any(kw in body for kw in ["CDP", "Hermes", "social-mcp"]):
            print(f"✅ 成功 ({time.time()-t0:.1f}s)")
            return f"✅ Threads 文章已發佈 ({time.time()-t0:.1f}s)"
        return f"⚠️ 完成但未確認 ({time.time()-t0:.1f}s)"
```

### 關鍵技術發現（2025-04）

1. **CDP `Input.dispatchMouseEvent` 在 Lexical editor modal 失效**
   - Threads 的 composer 是 Lexical editor（React-based rich text）
   - 點擊事件被 `data-lexical-text` span 攔截
   - **解決：Playwright `mouse.click(x, y)` 可以可靠穿透**（Playwright 底層用更底層的 input 注入）

2. **Threads `/compose` URL 是假的（404）**
   - 真正的 composer 是在 threads.com/ 主頁上用 JS 動態打開的 modal
   - 不要尝试导航到 `/compose`

3. **發佈按鈕座標 `y` 值會變化**
   - Threads 頁面滾動位置不同，modal 按鈕的絕對座標也會變
   - 解決：每次動態用 JS `getBoundingClientRect()` 查詢，並取 `y` 最大的那個（modal 按鈕）

**關鍵發現（2025-04 更新）：AIpuss-browser CDP session 與用戶視窗是獨立的**

AIpuss-browser 啟動的 Chrome 有自己獨立的所有 page instance。當用 Playwright `connect_over_cdp()` 連接時：
- CDP 看到的是 AIpuss-browser 創建的 page 實例
- 這些實例**與用戶在普通 Chrome 視窗中看到的 page 完全獨立**
- 常見問題：某些 page（如 Instagram）在 CDP session 中可能是舊狀態（dialog 卡住、file input 失效等）

**解決方案：每個 workflow 開始前，強制關閉所有可能的 dialog，確保乾淨狀態**
```python
# 開始任何操作前，先關閉所有 dialog
for page in ig_candidates:
    await page.evaluate("""
        () => {
            const closeBtn = document.querySelector('button[aria-label="關閉"]');
            if (closeBtn) closeBtn.click();
        }
    """)
await asyncio.sleep(1)
```

**實驗確認：CDP Playwright 連接到 AIpuss-browser 時**
- CDP session 內有 4+ 個 Instagram pages，其中一些處於損壞狀態（有 dialog 但無 file input）
- 用戶實際瀏覽器窗口和 CDP 看到的 page 實例是**不同的物件**
- 因此：永遠不要假設 CDP 看到的狀態等於用戶看到的狀態

**已知問題/限制：**
- `Meta+Enter` 鍵盤快捷鍵不可靠
- Threads 對自動化 click 有 DOM 層級的防範（`data-lexical-text` span 會截斷事件），必須用座標點擊
- 個人主頁 URL 格式：`https://www.threads.net/@{username}`（username 需從 DOM 中自己發現）
- 每次操作需要用戶親自在 CDP Chromium 中登入一次（macOS Keychain 加密）
- AIpuss-browser 的 CDP session 和用戶視窗狀態可能不一致，開始操作前必須先清理 dialog
- Instagram 可以用 Facebook 帳號登入（`/accounts/login/` → 找 FB link → 提交），失敗時 graceful skip 不要直接 exit

## Facebook 進階發現（2025-04 更新）

### Facebook contenteditable 無法用 JS `innerText` 填充
- `element.innerText = text` 在 FB 的 `[contenteditable=true]` div 內無效（文字進不去）
- **解決：用 `Input.dispatchKeyEvent` 鍵盤逐字輸入**，每次 keyDown + keyUp，delay ~50ms
- 速度：~20 char/s，135 字約需 7 秒

### Facebook `form.submit()` 是最後逃生口
- 當 dialog 打開後，所有 Post 按鈕都找不到（CDP dialog tree 只能看到 form element，無子元素）
- `form.submit()` 可直接提交表單，返回 `submit_attempted:N`（N = 表單內含目標文字的表單數量）
- **注意：`submit_attempted` 只是嘗試了提交，不代表成功**——CDP WS 在提交後會斷開

### Facebook 發文 dialog 結構（2025-04）
- Dialog selector: `[role=dialog]`
- Dialog 內有 `<form>` tag，包含所有 composer 元素
- Form 內 input[type=file] 用於上傳圖片（但 CDP JS 環境無法 `fetch('file://...')`）

### CDP WebSocket 在 Facebook 頁面會全面卡死
- 症狀：HTTP `http://localhost:9333/json` 正常，但 WS 連接後：
  - `Runtime.evaluate` 返回 `{id, error: timeout}` 或 WS 500
  - Playwright `connect_over_cdp` timeout
- 原因：Facebook 大量 React/JS 處理阻塞了 CDP WS 響應線程
- **徵兆判斷**：`curl http://localhost:9333/json/version` OK，但 WS 500 = 頁面已卡死
- **解決：**
  1. 調高 WS timeout 到 20s+
  2. 避免在 FB 頁面做多次 CDP 往返
  3. 推薦：`Page.close` 關閉 FB 頁面，用 Threads/其他頁面操作完成後再重新導航回 FB
- **注意**：FB 頁面 WS 恢復慢（>15秒），不建議等待，換頁面操作

### 文件上傳在 CDP JS 環境永遠失敗
- `fetch('file:///tmp/image.jpg')` 在 CDP `Runtime.evaluate` 內永远 `Failed to fetch`
- 原因：CDP JS 上下文無法訪問本地文件系統
- **解決：**
  1. 用 `Page.setInputFiles` CDP method（如果 CDP 還活著）
  2. 用 Playwright `page.locator('input[type=file]').set_input_files()`（需要 Playwright connect_over_cdp 可用）
  3. 放棄圖片，只發文字

## Facebook 完整發文流程（用戶親自示範版，2025-04）

**重要原則**：CDP 看到的一切可能和用戶視窗完全不同步。操作時用戶在瀏覽器親自操作，觀察學習，不干擾。

### 流程（觀察總結）
1. **Facebook 選單**（左側邊欄頂部，x≈1204-1316, y≈56-75）點擊 → 展開完整功能選單
2. **右側面板「帖子」按鈕**（x≈1272, y≈152-178）點擊 → 打開發文 dialog
3. **打字**（CDP Input.dispatchKeyEvent 可以用，慢但可行）
4. **上傳圖片**：必須用戶手動操作（CDP 無法 fetch file://）
5. **「下一頁」按鈕**：dialog 內，dialog querySelector("[role=dialog]") → 找 innerText === "下一頁"
6. **「立即發佈」按鈕**：在「排定選項」區域展開後出現，約 (x≈800, y≈410) 區域

### 徵兆：CDP 和用戶視窗不同步
- CDP querySelector 找到的元素，用戶視窗可能不存在
- CDP 顯示 dialog closed，用戶視窗 dialog 可能還開著
- CDP 看不到的元素，用戶可能正在操作
- **解法**：每次操作前請用戶告知座標，或用戶操作時安靜觀察不干擾

### CDP 轟炸會開啟垃圾頁面
- 一次性發送大量 CDP 指令（一秒內幾十次），會導致 Chrome 打開 Polymarket 等垃圾廣告分頁
- **規則**：每 CDP 指令間隔至少 0.5-1 秒，嚴禁批量轟炸
- **關閉垃圾分頁**：用 `Target.closeTarget` via browser-level WS，或逐個 page-level WS 調 `Page.close`

### Facebook 圖片上傳另一法：clipboard + paste
如果 CDP WS 還活著，可以試：
```python
# 先截圖或下載圖片到 /tmp
r = await cdp(ws, 98, 'Page.captureScreenshot', {'format': 'png'})
b64 = r['result']['data']
with open('/tmp/fb_upload.png', 'wb') as f:
    f.write(base64.b64decode(b64))

# 嘗試用 paste
await cdp(ws, 10, 'Clipboard.read', {})  # 需要 clipboardRead permission
```

### 驗證 FB 發文成功的正確方式
- `form.submit()` 後 URL 會保持 `facebook.com/`，dialog 會 close
- 最可靠的驗證：**讓用戶親自確認**，或者：
  1. 在文字中加入 unique identifier（如 `CDP_{timestamp}`）
  2. `Page.close` 关闭当前 tab
  3. 重新 `page.goto('https://www.facebook.com/')` 並搜索 unique identifier
  4. 若找到 = 成功

### CDP WS 500 時的緊急逃生
```python
# 1. 確認 WS 真的死了
import urllib.request
try:
    with urllib.request.urlopen('http://localhost:9333/json/version', timeout=3) as r:
        print('HTTP OK')  # HTTP OK 但 WS 可能 500
except:
    print('HTTP dead')

# 2. WS 500 = 嘗試強制導航到其他頁面恢復 CDP
# 從 HTTP JSON 找到其他存活的 page（如 Threads/IG），用該 page 的 WS URL
# 如果所有 WS 都死了 → CDP 全面重啟 → 必須重啟 Chromium

# 3. 測試新 page 的 WS
async with websockets.connect(tab_ws, open_timeout=5, max_size=50*1024*1024) as ws:
    await ws.send(json.dumps({'id':1,'method':'Page.close','params':{}}))
    r = await asyncio.wait_for(ws.recv(), timeout=5)  # 馬上嘗試 receive
    print('WS alive')
```

## Profile 管理

- 放在 `~/Library/Application Support/Chromium/FacebookMCP`
- 使用 `--profile-directory="Default"`
- 需要清除鎖檔：SingletonLock、SingletonSocket、SingletonCookie
- 加密 cookies 無法跨 Chromium 版本共享，必須用同一個 Chromium binary

## 常見錯誤

| 錯誤 | 原因 | 解法 |
|------|------|------|
| `USE_PROFILE_DIR` | 相同 profile 的 Chromium 已在運行 | 關閉所有 Chromium 視窗，或使用專用 CDP profile 目錄 |
| `TargetClosedError` + `kill ESRCH` | Playwright 試圖啟動自己的 Chromium，與系統 Chrome 衝突 | 確保系統 Chromium 未運行，並用 CDP pipe 模式 |
| `sqlite3` 讀不到 c_user | Chromium cookies 是 OS 加密的 | 不要試圖讀 SQLite，直接讓瀏覽器開啟 |
| 每次 CDP URL 都變 | Chromium 重新啟動後 WS URL 會變 | 每次從 `http://localhost:9333/json` 重新發現 |
| 找不到發文框 | Facebook UI 更新，selector 變了 | 用 `page.locator('[role="dialog"]')` 或 `browser_vision` 確認當前 DOM |
| 永遠未登入 | 使用的 profile 與你日常 Chromium 不同 | 必須在 CDP Chromium 視窗親自登入一次 |
| IG `isLoggedIn` 誤判 | `html.includes('login')` 在已登入頁面也會命中（DOM 含 "login" 字樣） | 用 `!html.includes('loginForm') && !html.includes('form[data-ng-submit]')` 或檢查 `html.includes('nav')` 等正向指標 |
| IG 未登入時直接崩潰 | 發現未登入就 exit，浪費一次 workflow | 加 login_ig_via_fb() 嘗試 FB 帳號登入，仍失敗則 graceful skip |

## 禁用 killswitch

macOS 上的 Chromium 有 killswitch 防止被自動化框架綁定。確保：
- Chromium 不是從 App Store 版本
- `--no-sandbox` 已在啟動參數中（默認已有）

## 重要：macOS Chromium Cookie 加密

macOS 上的 Chromium（無論是 Chrome 還是 ungoogled-chromium）會把 cookies 加密存在 `login keychain` 裡。這意味著：

1. **外部程式無法直接讀取 cookies**（例如 `sqlite3 browser.db` 讀到的 c_user 是加密的）
2. **解決方案**：讓 Chromium 自己解密——即用 CDP 接管瀏覽器後操作，這樣 cookies 天然處於解密狀態
3. **根本原則**：永遠不要嘗試偷 cookies，全部讓瀏覽器自己做
