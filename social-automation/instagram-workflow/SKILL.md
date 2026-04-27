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
3. 等初始 dialog → 點「從電腦選擇」（Playwright locator）
4. FileChooser set_files 圖片
5. 等 3s → 點兩次「下一步」（CDP JS click）
6. 等 caption 頁出現
7. `fill()` 填 caption → 等 3s → ArrowRight 鍵
8. 點「分享」（CDP pointer+mouse 鏈，在 dialog 內）
9. 等「分享中」→「已分享」
10. 點「完成」（CDP，在 dialog 內）

### 6. 禁用方法
- `keyboard.type()` 對任何元素 ❌（React state 收不到）
- `fill()` 對 `input[type=text]` ❌（要對 contenteditable DIV）
- CDP JS `element.value = caption` ❌
- CDP JS `_valueTracker.setValue('')` ❌
- CDP JS `dispatchEvent(new Event('input'))` 單獨使用 ❌
- 全 page 範圍搜尋按鈕 ❌
- `.click()` 簡單事件（只用 mousedown/mouseup/click）❌

## CDP 連線相容性（重要）

### Chrome 146 + Playwright `connect_over_cdp`  hang 問題

Chrome 146 (2025-06) 與 Playwright 1.50-1.58 的 `connect_over_cdp()` 在瀏覽器層級端點（`/devtools/browser/...`）存在已知 hang 問題。

**徵狀：**
- WebSocket 連線成功（log: `<ws connected>`）
- 但 Playwright 在 `CRBrowser.connect()` 內部初始化時 hang 住
- Timeout 60s 後仍無回應

**已驗證工作正常的方案：**
```python
# ✅ 方案A：直接用原始 CDP over websockets（通用，繞過 Playwright 連線）
import asyncio, websockets, json

async def cdp_send(ws_url, method, params={}):
    msg = {'id': 1, 'method': method, 'params': params}
    async with websockets.connect(ws_url, open_timeout=10, close_timeout=5) as ws:
        await ws.send(json.dumps(msg))
        resp = json.loads(await asyncio.wait_for(ws.recv(), timeout=10))
    return resp['result']

# 用法：
result = await cdp_send('ws://localhost:9333/devtools/page/xxx', 'Page.captureScreenshot')

# ✅ 方案B：Page-level connect_over_cdp（單一頁面可用）
browser = await p.chromium.connect_over_cdp(
    'ws://localhost:9333/devtools/page/xxx',  # 直接 page WS URL
    timeout=20000
)
```

**確定失敗的方案：**
```python
# ❌ 瀏覽器層級 HTTP endpoint — hang
browser = await p.chromium.connect_over_cdp('http://localhost:9333', timeout=60000)

# ❌ 瀏覽器層級 WS URL — hang
browser = await p.chromium.connect_over_cdp(
    'ws://localhost:9333/devtools/browser/xxx',
    timeout=60000
)

# ❌ Playwright 的 connect()（非 CDP，是 Playwright 專有協議）
browser = await p.chromium.connect(ws_url, timeout=60000)
```

**底層原因：** Playwright Node.js driver 的 `CRBrowser.connect()` 在 `session.send("Browser.getVersion")` 和 `Target.setAutoAttach` 階段與 Chrome 146 的 CDP 实现有兼容性问题。

## CLI 用法
```bash
uv run python -m social_mcp.post_ig "caption text" /tmp/social.jpg
```

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
