---
name: meta-workflow-cdp-post
description: 用 CDP Playwright 操控 Chromium 發布 Facebook 和 Instagram 帖子，含指紋驗證
category: browser-automation
---

# Facebook CDP 發布流程 — 透過 Chromium CDP 操控 Facebook

## ⚠️ 重要：驗證方法

**千萬不要只靠「對話框關閉」判斷成功。** Facebook 對話框關閉可能是網路錯誤、帖子被過濾等原因。

正確做法：
1. 發布前：取文章開頭 50 字當「指紋」
2. 點擊發佈
3. 刷新頁面 + 滾動
4. 在動態消息中搜尋指紋
5. **只有找到指紋才說成功**

## 背景

用戶的 Chromium（ungoogled-chromium）已安裝在 `/Applications/Chromium.app`，CDP 端口 9333，profile 目錄 `~/Library/Application Support/Chromium/FacebookMCP`。Chromium 已經登入 Facebook（帳號：Whyme Ym）。

## CDP 連線方式

Chromium 啟動時自動暴露 CDP 接口，Playwright 透過 WebSocket 連線操控瀏覽器。

```python
import asyncio
from playwright.async_api import async_playwright

WS_URL = "ws://localhost:9333/devtools/browser/65653279-e223-4f87-b6ff-ebd30cd96b2b"

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp(WS_URL)
        ctx = browser.contexts[0]
        pages = ctx.pages
        fb = pages[0]  # 第一個 Facebook 分頁
```

## 完整發布流程（Step by Step）

### Step 1: 關閉殘留對話框 + 刷新頁面

如果上次操作殘留了 composer 對話框，先關閉它。

```python
# 關閉按鈕在對話框右上角
await fb.evaluate("""
    () => {
        const closeBtn = document.querySelector('[aria-label="關閉撰寫工具對話框"]');
        if (closeBtn) closeBtn.click();
    }
""")
await asyncio.sleep(1)

# 刷新到乾淨狀態
await fb.goto("https://www.facebook.com", wait_until="load", timeout=30000)
await asyncio.sleep(3)
```

驗證：頁面應該在 `https://www.facebook.com/`，能看到動態消息。

### Step 2: 點擊「在想什麼」打開 Composer

Facebook 首頁有一個藍色連結「Whyme Ym，你在想什麼？」，點擊後會彈出發帖對話框。

```python
await fb.evaluate("""
    () => {
        const spans = document.querySelectorAll('span');
        for (const s of spans) {
            if (s.textContent.includes('在想什麼')) {
                s.click();
                return;
            }
        }
    }
""")
await asyncio.sleep(2)
```

驗證：`fb.query_selector('div[role="dialog"]')` 應該不為 None（對話框已打開）。

### Step 3: 找到正確的編輯框並打字

**重要（2025 年更新）：** Facebook Composer 的編輯器已改用 `role="textbox"`（不是 `role="presentation"`），只有一個，空的時候高度是 **28**（不是 21），top 約 222。

**識別方式：**
- `role="textbox"`，`contenteditable="true"`
- 高度 ≈ 28，top ≈ 222
- 只有一個編輯框（不是多個）

```python
# 在對話框內找空的 contenteditable div
result = await fb.evaluate("""
    () => {
        const dialog = document.querySelector('div[role="dialog"]');
        if (!dialog) return {found: false, error: 'no dialog'};

        // 優先找 role="textbox" 的編輯器（2025 年新結構）
        const editors = dialog.querySelectorAll('div[contenteditable="true"][role="textbox"]');

        for (const ed of editors) {
            const h = ed.offsetHeight;
            const rect = ed.getBoundingClientRect();
            // 空編輯框：h=28, top ≈ 222
            if (h > 20 && h < 40) {
                ed.click();
                return {found: true, height: h, top: rect.top, role: 'textbox'};
            }
        }

        // fallback：如果找不到 role="textbox"，找任意空的 contenteditable
        const anyEditable = dialog.querySelectorAll('[contenteditable="true"]');
        for (const ed of anyEditable) {
            const h = ed.offsetHeight;
            const rect = ed.getBoundingClientRect();
            if (h > 15 && h < 40) {
                ed.click();
                return {found: true, height: h, top: rect.top, fallback: true};
            }
        }

        return {found: false};
    }
""")
print(f"Editor: {result}")
await asyncio.sleep(0.5)
```

驗證：`result['found']` 應為 True，`result['role']` 應為 `'textbox'`。

### Step 4: 輸入帖子內容

聚焦後，用 `keyboard.type()` 輸入文字。

```python
await fb.keyboard.type(
    "🌏 日本旅遊安全必備APP！\n\n"
    "日本觀光局推出針對外國遊客的安全App「Safety tips」！\n\n"
    "✅ 十二大防災安全功能（地震資訊超詳細）\n"
    "✅ 全繁體中文\n"
    "✅ 可設定預報地點\n"
    "✅ 多國語言災害應變會話（有繁中！）\n"
    "✅ 緊急聯絡處資訊（可直接App點擊撥打緊急電話）\n\n"
    "非常建議近期要前往日本或已經在當地的人使用！\n\n"
    "#日本旅遊 #日本安全 #地震對策 #訪日外國人"
, delay=50)
await asyncio.sleep(1)
```

驗證：對話框內應該能看到打進去的文字。

### Step 5: 滾動對話框到底，點「下一頁」

Composer 對話框上半部是編輯區，下半部是功能按鈕。「發佈」按鈕在最底部，需要滾動才能看到。

```python
# 滾動對話框到最底
await fb.evaluate("""
    () => {
        const dialog = document.querySelector('div[role="dialog"]');
        dialog.scrollTop = dialog.scrollHeight;
    }
""")
await asyncio.sleep(0.5)

# 點擊「下一頁」按鈕（藍色按鈕，文字是「下一頁」）
await fb.evaluate("""
    () => {
        const dialog = document.querySelector('div[role="dialog"]');
        const allDivs = dialog.querySelectorAll('div[role="button"]');
        for (const d of allDivs) {
            if (d.textContent?.trim() === '下一頁') {
                d.click();
                return;
            }
        }
    }
""")
await asyncio.sleep(2)
```

驗證：點擊後對話框內容會變化，應該出現「發佈」相關的按鈕。

### Step 6: 點擊「發佈」按鈕

「下一頁」點擊後，對話框下半部變成最終確認介面。此時找 `aria-label="發佈"` 的按鈕，用 JS evaluate 點擊。

**千萬不要用 `keyboard.press("Meta+Enter")`！** Facebook 會把帖子當草稿儲存，不會實際發佈。

```python
await fb.evaluate("""
    () => {
        const dialog = document.querySelector('div[role="dialog"]');
        const allDivs = dialog.querySelectorAll('div[role="button"]');
        for (const d of allDivs) {
            if (d.getAttribute('aria-label') === '發佈') {
                d.click();
                return;
            }
        }
    }
""")
await asyncio.sleep(3)
```

驗證：對話框關閉（`fb.query_selector('div[role="dialog"]')` 為 None）= 發佈成功。

### Step 7: 刷新驗證（對比內容，不是只靠對話框關閉）

**千萬不要只靠「對話框關閉」判斷成功。** 對話框關閉可能是因為其他原因（網路錯誤、帖子被過濾等）。

正確做法：發布前抓關鍵內容指紋 → 發布後在動態消息中搜尋這個指紋。

```python
import hashlib

# ====== 發布前：抓內容指紋 ======
# 取文章前 50 字當指紋
post_snippet = post_text[:50].strip()
print(f"Post fingerprint: 「{post_snippet}」")
post_hash = hashlib.md5(post_snippet.encode()).hexdigest()[:8]

# ====== 點擊發佈 ======
# ... (點擊發佈按鈕) ...
await asyncio.sleep(4)

# ====== 發布後：驗證指紋存在 ======
# 方法：刷新 → 滾動找帖子 → 比對指紋
await fb.goto("https://www.facebook.com", wait_until="load", timeout=30000)
await asyncio.sleep(3)

# 滾動頁面讓帖子出現
for _ in range(5):
    await fb.evaluate("window.scrollBy(0, 500)")
    await asyncio.sleep(0.5)

# 在頁面 text 中找指紋
page_text = await fb.inner_text("body")
if post_snippet in page_text:
    print(f"✅ 帖子已發布！指紋「{post_snippet}」在動態消息中找到")
    # 找到帖子位置
    idx = page_text.find(post_snippet)
    post_preview = page_text[max(0, idx-20):idx+len(post_snippet)+50]
    print(f"驗證片段: ...{post_preview}...")
else:
    print(f"❌ 發佈可能失敗！指紋「{post_snippet}」未在頁面中找到")
    print(f"頁面內容前500字:\n{page_text[:500]}")
```

## 發布圖文帖子（圖片 + 文字）

### 重要：順序不能錯

1. 打字
2. 滾到底，按「相片／影片」（**不是**按「下一頁」）
3. 上傳圖片檔案
4. 等待圖片處理（約 3 秒）
5. 點「下一頁」
6. 點「發佈」

### Step A: 打字 + 點「相片／影片」

```python
# ...打字步驟同上（Step 4）...

# 滾到按鈕區，按「相片／影片」
await fb.evaluate("""
    () => {
        const dialog = document.querySelector('div[role="dialog"]');
        dialog.scrollTop = dialog.scrollHeight;
    }
""")
await asyncio.sleep(0.5)

await fb.evaluate("""
    () => {
        const dialog = document.querySelector('div[role="dialog"]');
        for (const d of dialog.querySelectorAll('div[role="button"]')) {
            if (d.getAttribute('aria-label') === '相片／影片') {
                d.click();
                return;
            }
        }
    }
""")
await asyncio.sleep(2)
```

### Step B: 上傳圖片

```python
# 找到 file input 並上傳
file_input = await fb.query_selector('div[role="dialog"] input[type="file"]')
if file_input:
    await file_input.set_input_files("/path/to/image.png")

# 等待圖片處理完成
await asyncio.sleep(3)

# 確認圖片已上傳（有 img 標籤出現）
result = await fb.evaluate("""
    () => {
        const dialog = document.querySelector('div[role="dialog"]');
        const imgs = dialog.querySelectorAll('img');
        return {imgCount: imgs.length};
    }
""")
print(f"Images in dialog: {result['imgCount']}")
```

### Step C: 點下一頁 → 發佈

```python
# 點下一頁
await fb.evaluate("""
    () => {
        const dialog = document.querySelector('div[role="dialog"]');
        for (const d of dialog.querySelectorAll('div[role="button"]')) {
            if (d.textContent?.trim() === '下一頁') {
                d.click();
                return;
            }
        }
    }
""")
await asyncio.sleep(2)

# 點發佈
await fb.evaluate("""
    () => {
        const dialog = document.querySelector('div[role="dialog"]');
        for (const d of dialog.querySelectorAll('div[role="button"]')) {
            if (d.getAttribute('aria-label') === '發佈') {
                d.click();
                return;
            }
        }
    }
""")
await asyncio.sleep(3)
```

### 從網頁裁剪圖片（CDN 封鎖 curl 時）

Instagram/Threads CDN 會封鎖 curl/wget 下載。需要用 Playwright CDP 截圖並裁剪目標區域：

```python
# 找到圖片元素的位置
result = await page.evaluate("""
    () => {
        const img = document.querySelector('img');  // 或更具體的選擇器
        const rect = img.getBoundingClientRect();
        return {x: rect.x, y: rect.y, width: rect.width, height: rect.height};
    }
""")

# 截圖裁剪
await page.screenshot(path="/tmp/cropped.png", clip={
    "x": result["x"],
    "y": result["y"],
    "width": result["width"],
    "height": result["height"]
})
```

## Facebook 個人主頁 URL

Facebook 個人主頁的 URL 是 `profile.php?id=61577306841427`（不是 `/WhymeYm`）。驗證指紋時要去：
```
https://www.facebook.com/profile.php?id=61577306841427
```
而不是直接去 `/WhymeYm/posts`（會顯示「目前無法查看此內容」）。

## 已知問題

### Facebook 指紋驗證可能因預覽截斷而失敗

Facebook Feed 中的帖子預覽會將長文字截斷為 `⋯`，導致指紋（前 50 字）匹配失敗。

**判斷方法：**
- 對話框關閉 + 頁面刷新後滾動尋找 → 如果能找到包含指紋片段的帖子（即使被截斷），仍算成功
- 如果完全找不到任何相關內容，才算失敗

### AIpuss-browser 多 workflow CDP session 衝突（2025-04 關鍵發現）

**問題**：多個 workflow 腳本共享同一個 CDP WebSocket URL，同時執行時會互相覆蓋對方的瀏覽器狀態，導致頁面不停刷新、死循環。

**根本原因**：
- 腳本 A、B、C 同時連線同一個 CDP session
- 其中一個 script 執行 `window.location.href` 導航，其他 script 的下一個 CDP 命令會作用在已離開的頁面
- 迴圈：舊 CDP 命令作用在新頁面 → 頁面跳轉 → 更多 CDP 命令作用在新頁面 → 無限循環

**修復方法**：
1. 每個 workflow 開始時先 `oc(["open", "about:blank"])` 重置 session 狀態
2. **嚴禁** 用 `oc(["eval", "window.location.href=..."])` 進行導航，會破壞 CDP session
3. 正確導航：`oc(["open", "https://..."])`（走 CDP 的 open 命令）
4. 每個 workflow 必須順序執行，不要並發

**實作範例**：
```python
def find_threads_post():
    oc(["connect", TH_CDP], 10)
    oc(["open", "about:blank"], 15)  # 重置 session
    ss(1000)
    for q in queries:
        # 正確：用 CDP open 導航
        oc(["open", f"https://www.threads.net/search?q={q}&result_filter=topics"], 20)
        ss(5000)  # 等內容載入
        # ... scroll 和 eval ...
```

**實測教訓**：
- Threads 改了架構後很難找到文章（CDP eval 回傳 null）
- X.com 有登入牆，FacebookMCP profile 未登入 X.com，搜尋結果頁面顯示「建立帳戶」而非內容
- 函式名拼錯（`find_x_post` vs `find_x_fallback`、`post_fb` vs `post_facebook`）會導致 NameError，要先編譯檢查

### AIpuss-browser 與 Playwright CDP 衝突（2025-04 關鍵發現）

如果 Chromium 是由 AIpuss-browser（`agent-browser`）啟動並處於活跃控制狀態，Playwright CDP 連線會因為 ProtocolError 而中斷（`Connection closed while reading from the driver`）。

**千萬不要 kill AIpuss-browser 來釋放 CDP！** AIpuss-browser 和 Chromium 主進程是同一个进程树的成员。kill AIpuss-browser 會導致 Chromium 主進程（`/Applications/Chromium.app/Contents/MacOS/Chromium`）也被終結，所有 renderer helpers 變成孤兒，CDP 端口完全無響應。

**正確做法：在 Chromium 啟動前就確認 AIpuss-browser 已關閉**

```bash
# 確認沒有 AIpuss-browser 在運行
ps aux | grep agent-browser-darwin | grep -v grep
# 如果有，CDP 已被獨佔，不能使用 Playwright

# 確認 Chromium CDP 可用
curl -s --max-time 3 "http://localhost:9333/json/version"
# 正常返回 JSON 表示 CDP 可用
```

**流程：**
1.  cron job 運行前 → 確認 `agent-browser-darwin-arm64` 未運行
2.  如果正在運行 → **不能執行 Playwright CDP 腳本**，直接退出並報告
3.  如果未運行 → 可安全執行 Playwright CDP 操作
4.  Playwright 腳本執行完後 → 可重新啟動 AIpuss-browser（如果需要的話）
## 執行前檢查清單

每次執行 Playwright CDP 腳本前，必須確認：

```bash
# 1. AIpuss-browser 未運行（否則 CDP 被獨佔）
ps aux | grep agent-browser-darwin | grep -v grep && echo "BLOCKED" || echo "OK"

# 2. CDP 端口響應
curl -s --max-time 3 "http://localhost:9333/json/version" | grep -q "WebKit-Version" && echo "CDP OK" || echo "CDP DEAD"
```

如果任一檢查失敗，腳本應立即退出並報告狀態，不要嘗試重試。

## 不要用 just_facebook_mcp

[jackwener/just_facebook_mcp](https://github.com/Livia-Zaharia/just_facebook_mcp) 使用 Facebook Graph API，需要：
- Facebook 開發者帳號
- 粉絲專頁（Personal Account 不行）
- 開發者審批流程

我們的 CDP 方案不需要這些，個人帳號直接操作，**不要被那個 repo 誤導去折騰 Graph API**。

## 禁用鍵盤捷徑

**禁用 Cmd+Enter / Control+Enter**

Facebook 的「發佈」行為需要透過 UI 按鈕的真實點擊事件觸發。鍵盤捷徑只會把內容寫入但觸發草稿儲存邏輯，不會實際發佈到動態消息。

## 完整可運行腳本

```python
import asyncio
from playwright.async_api import async_playwright

WS_URL = "ws://localhost:9333/devtools/browser/65653279-e223-4f87-b6ff-ebd30cd96b2b"

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp(WS_URL)
        ctx = browser.contexts[0]
        pages = ctx.pages
        fb = pages[0]

        # Step 1: 關閉殘留對話框 + 刷新
        await fb.evaluate("""() => {
            const closeBtn = document.querySelector('[aria-label="關閉撰寫工具對話框"]');
            if (closeBtn) closeBtn.click();
        }""")
        await asyncio.sleep(1)
        await fb.goto("https://www.facebook.com", wait_until="load", timeout=30000)
        await asyncio.sleep(3)

        # Step 2: 點擊「在想什麼」
        await fb.evaluate("""() => {
            const spans = document.querySelectorAll('span');
            for (const s of spans) {
                if (s.textContent.includes('在想什麼')) { s.click(); return; }
            }
        }""")
        await asyncio.sleep(2)

        # Step 3: 找空的 editor (role=textbox, h=28) 並點擊
        await fb.evaluate("""() => {
            const dialog = document.querySelector('div[role="dialog"]');
            const editors = dialog.querySelectorAll('div[contenteditable="true"][role="textbox"]');
            for (const ed of editors) {
                const h = ed.offsetHeight;
                if (h > 20 && h < 40) { ed.click(); return; }
            }
            // fallback
            const anyEditable = dialog.querySelectorAll('[contenteditable="true"]');
            for (const ed of anyEditable) {
                const h = ed.offsetHeight;
                if (h > 15 && h < 40) { ed.click(); return; }
            }
        }""")
        await asyncio.sleep(0.5)

        # Step 4: 打字
        await fb.keyboard.type("你的帖子內容", delay=50)
        await asyncio.sleep(1)

        # Step 5: 滾到底 + 點下一頁
        await fb.evaluate("""() => {
            const dialog = document.querySelector('div[role="dialog"]');
            dialog.scrollTop = dialog.scrollHeight;
        }""")
        await asyncio.sleep(0.5)
        await fb.evaluate("""() => {
            const dialog = document.querySelector('div[role="dialog"]');
            for (const d of dialog.querySelectorAll('div[role="button"]')) {
                if (d.textContent?.trim() === '下一頁') { d.click(); return; }
            }
        }""")
        await asyncio.sleep(2)

        # Step 6: 點擊發佈
        await fb.evaluate("""() => {
            const dialog = document.querySelector('div[role="dialog"]');
            for (const d of dialog.querySelectorAll('div[role="button"]')) {
                if (d.getAttribute('aria-label') === '發佈') { d.click(); return; }
            }
        }""")
        await asyncio.sleep(3)

        # ====== 發布前：抓內容指紋 ======
        post_snippet = "💴 日圓匯率跌至34年新低！"  # 取文章開頭關鍵句
        print(f"Post fingerprint: 「{post_snippet}」")

        # ====== 點擊發佈 ======
        await fb.evaluate("""
            () => {
                const dialog = document.querySelector('div[role="dialog"]');
                for (const d of dialog.querySelectorAll('div[role="button"]')) {
                    if (d.getAttribute('aria-label') === '發佈') { d.click(); return; }
                }
            }
        """)
        await asyncio.sleep(4)

        # ====== 發布後：驗證指紋存在 ======
        await fb.goto("https://www.facebook.com", wait_until="load", timeout=30000)
        await asyncio.sleep(3)

        # 滾動讓帖子出現
        for _ in range(5):
            await fb.evaluate("window.scrollBy(0, 500)")
            await asyncio.sleep(0.5)

        page_text = await fb.inner_text("body")
        if post_snippet in page_text:
            idx = page_text.find(post_snippet)
            post_preview = page_text[max(0, idx-20):idx+len(post_snippet)+50]
            print(f"✅ 發佈成功！指紋「{post_snippet}」已找到")
            print(f"驗證片段: ...{post_preview}...")
        else:
            print(f"❌ 發佈可能失敗！指紋「{post_snippet}」未找到")
            print(f"頁面內容前500字:\n{page_text[:500]}")

asyncio.run(main())
```

---

# Instagram 發布流程（CDP Playwright）

## 流程概覽

```
1. 點擊「有什麼新鮮事？」打開 composer dialog
2. 在 caption textbox（role="textbox"）打字
3. 點擊「新增」（添加圖片按鈕，不是「相片/影片」）
4. 上傳圖片
5. 點擊「發佈」按鈕（在 dialog 內的座標約 893, 426，但**必須用 JS evaluate 點擊**，不能用 mouse.click）
6. 等待「已分享你的貼文」確認
7. 指紋驗證
```

## ⚠️ Threads CDP 關鍵陷阱

### 發佈按鈕在 dialog 外部

Threads dialog 邊界約 (330, 131) 到 (950, 469)，但「發佈」按鈕在 (862, 408) 64x36，**右側超出 dialog 邊界**。

`mouse.click(893, 426)` 會點到 dialog 外部，**永遠失敗**。必須用 JS evaluate 在 dialog 內遍歷點擊：

```python
# 正確做法：在 dialog 內用 JS 點擊
await threads_page.evaluate("""
    () => {
        const dialog = document.querySelector('[role="dialog"]');
        const allDivs = dialog.querySelectorAll('div');
        for (const d of allDivs) {
            if (d.innerText?.trim() === '發佈') {
                d.click();  // 直接調用 .click() 不是 dispatchEvent
                return;
            }
        }
    }
""")
```

### 圖片上傳後 dialog 狀態不更新（Threads CDP 已知限制）

`file_input.set_input_files()` 設置圖片後，Threads JS 狀態不會更新，導致：
- 圖片看不見
- 點擊「發佈」後 dialog 關閉但帖子未實際發布

**變通方案**：先發布純文字帖子驗證流程暢通，圖文帖子建議手動發布或用 Meta Threads API。

## 關鍵元素識別

| 頁面 | 識別方式 |
|------|----------|
| File input | `input[type="file"]`，`display:none`，接受 `image/*` |
| Caption 輸入框 | `div[contenteditable="true"][role="textbox"]`，aria-label="撰寫說明文字……" |
| 分享按鈕 | 用 `mouse.click(x, y)` 座標點擊，不要用 aria-label |
| 確認標題 | 「已分享你的貼文」出現在 `document.body.innerText` |

## Step by Step

### Step 1: 點擊「有什麼新鮮事？」打開 composer

Threads 的發布按鈕不是 Instagram 的「新貼文」，而是「有什麼新鮮事？」。

```python
await threads_page.evaluate("""
    () => {
        const btns = document.querySelectorAll('[role="button"]');
        for (const b of btns) {
            if ((b.innerText || '').trim() === '有什麼新鮮事？') {
                b.click();
                return;
            }
        }
    }
""")
await asyncio.sleep(2)
```

### Step 2: 上傳圖片

Threads 的圖片按鈕是「新增」（不是「相片/影片」）。dialog 打開後，caption textbox 已聚焦，先打字，然後點「新增」上傳圖片。

```python
# Step 2a: 打字
await threads_page.evaluate("""
    () => {
        const textbox = document.querySelector('[role="textbox"]');
        if (textbox) textbox.focus();
    }
""")
await asyncio.sleep(0.5)
await threads_page.keyboard.type(caption, delay=30)

# Step 2b: 點擊「新增」上傳圖片
await threads_page.evaluate("""
    () => {
        const dialog = document.querySelector('[role="dialog"]');
        const allDivs = dialog.querySelectorAll('div');
        for (const d of allDivs) {
            if ((d.innerText || '').trim() === '新增') {
                d.click();
                return;
            }
        }
    }
""")
await asyncio.sleep(2)

# Step 2c: 上傳（file input 是 display:none，設到 dialog 內的 input）
file_input = await threads_page.query_selector('[role="dialog"] input[type="file"]')
if file_input:
    await file_input.set_input_files("/path/to/image.png")
await asyncio.sleep(4)
```

### Step 3: 裁切頁面 → 點「下一步」

```python
# 等待裁切 heading
for _ in range(10):
    heading = await ig.evaluate(
        "() => document.querySelector('h1,h2,h3,h4,h5,h6[level=\"1\"]')?.innerText"
    )
    if heading:
        break
    await asyncio.sleep(0.5)

# 點下一步
await ig.evaluate("""
    () => {
        const btns = document.querySelectorAll('button');
        for (const b of btns) {
            if (b.innerText?.trim() === '下一步') { b.click(); return; }
        }
    }
""")
await asyncio.sleep(2)
```

### Step 4: 濾鏡頁面 → 點「下一步」

同樣代碼再執行一次。

### Step 5: 輸入 Caption（Threads 用 role="textbox"）

```python
# 找到並聚焦 caption 輸入框
await threads_page.evaluate("""
    () => {
        const textbox = document.querySelector('[role="textbox"]');
        if (textbox) textbox.focus();
    }
""")
await asyncio.sleep(0.5)

# 打字
await threads_page.keyboard.type(caption, delay=30)
await asyncio.sleep(1)
```

### Step 6: 點擊「發佈」（必須用 JS evaluate）

**千萬不要用 `mouse.click()`！** Threads 的「發佈」按鈕座標在 dialog 外部，mouse.click 會點空。

```python
# 在 dialog 內用 JS 點擊「發佈」
publish_result = await threads_page.evaluate("""
    () => {
        const dialog = document.querySelector('[role="dialog"]');
        if (!dialog) return null;

        // 遍歷 dialog 內所有 div，找文字為「發佈」且大小合理的按鈕
        const allDivs = dialog.querySelectorAll('div');
        for (const d of allDivs) {
            const text = (d.innerText || '').trim();
            if (text === '發佈') {
                const rect = d.getBoundingClientRect();
                // 按鈕大小約 60-80 x 30-40
                if (rect.width > 40 && rect.width < 100 && rect.height > 20 && rect.height < 60) {
                    d.click();  // 直接 .click()，不是 dispatchEvent
                    return {x: rect.x, y: rect.y, w: rect.width, h: rect.height};
                }
            }
        }
        return null;
    }
""")
print(f"Publish clicked: {publish_result}")
await asyncio.sleep(5)
```

### Step 7: 等待「已分享你的貼文」確認

```python
for _ in range(15):
    body = await threads_page.inner_text("body")
    if '已分享你的貼文' in body or 'Your post has been shared' in body or 'Posted' in body:
        print("✅ Threads 確認：已分享你的貼文")
        break
    await asyncio.sleep(1)
else:
    print("❌ 未收到確認訊息")
```

### Step 8: 指紋驗證

```python
# 刷新主頁並搜尋指紋
await ig.goto("https://www.instagram.com/whypuss_fun", wait_until="load", timeout=30000)
await asyncio.sleep(3)

for _ in range(5):
    await ig.evaluate("window.scrollBy(0, 500)")
    await asyncio.sleep(0.5)

page_text = await ig.inner_text("body")
if post_snippet in page_text:
    print(f"✅ 指紋驗證成功！")
else:
    # Instagram 顯示已分享，但 CDN 更新需要時間
    print(f"⚠️ Instagram 顯示已分享，指紋可能需要數分鐘才在主頁出現")
```

## 已知問題

### Instagram 限時動態按鈕干擾

Instagram 首頁左側有 Story 區域，「新貼文」按鈕在最頂部。如果點擊範圍稍微偏移，會點到 Story 而不是新貼文。用 `span` 文字匹配比 aria-label 更可靠。

### Threads 分享按鈕干擾

在標題撰寫頁面，「分享到」預設會打開 Threads 分享面板。確認對話框出現「已分享你的貼文」即可，Threads 分享失敗不影響 Instagram 發布成功。

### Instagram 多 page 狀態處理（關鍵發現 2025-04）

CDP session 中可能有多個 Instagram pages，其中一些處於損壞狀態（如 dialog 卡住但無 file input）。開始操作前**必須**：

1. **先關閉所有 Instagram dialog**（確保乾淨狀態）：
```python
for page in ig_candidates:
    await page.evaluate("""
        () => {
            const closeBtn = document.querySelector('button[aria-label="關閉"]');
            if (closeBtn) closeBtn.click();
        }
    """)
await asyncio.sleep(1)
```

2. **狀態檢測邏輯**（根據當前狀態決定下一步）：
```python
current_state = await ig.evaluate("""
    () => {
        const hasDialog = !!document.querySelector('div[role="dialog"]');
        const fileInput = document.querySelector('input[type="file"]');
        const bodyText = document.body.innerText;
        return {
            hasDialog,
            hasFileInput: !!fileInput,
            isFileSelectPage: bodyText.includes('將相片和影片拖曳到這裡') || bodyText.includes('從電腦選擇'),
            isDetailsPage: window.location.href.includes('/create/details'),
        };
    }
""")
```

3. **三種狀態處理**：
- `hasDialog + hasFileInput + isFileSelectPage` → 直接上傳（dialog 已打開，無需再點新貼文）
- `hasDialog + !hasFileInput` → dialog 處於損壞狀態，需關閉重來
- `!hasDialog` → 點擊「新貼文」按鈕

