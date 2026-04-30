---
name: social-automation-playwright-gotchas
description: Playwright CDP 社交平台自動化踩坑指南（Facebook/Instagram/Threads）
category: browser-automation
tags: [playwright, facebook, instagram, threads, social-automation, cdp]
---

# Social Automation — Playwright CDP 自動化踩坑指南

## 觸發條件
當你需要用 Playwright CDP 模式自動化社交平台（Facebook/Instagram/Threads）圖文發文時參考。

---

## 1. CDP Mode 的 File Chooser 攔截（Instagram 關鍵）

**問題**：在 CDP mode（`connect_over_cdp`）下，`page.context.wait_for_file_chooser` 不存在，`set_input_files` 無法觸發 IG 上傳流程。

**根因**：CDP 模式下，OS file dialog 由 Chrome 主進程處理，Playwright 的 BrowserContext 不知道 dialog 存在。

**修復方案 A**（推薦）：JS DataTransfer 直接注入繞過 OS dialog
```python
import base64

with open(image_path, "rb") as f:
    b64 = base64.b64encode(f.read()).decode()

result = await page.evaluate("""(b64) => {
    const binaryString = atob(b64);
    const bytes = new Uint8Array(binaryString.length);
    for (let i = 0; i < binaryString.length; i++) {
        bytes[i] = binaryString.charCodeAt(i);
    }
    const blob = new Blob([bytes], { type: 'image/jpeg' });
    const file = new File([blob], 'upload.jpg', { type: 'image/jpeg', lastModified: Date.now() });

    const d = document.querySelector('[role="dialog"]');
    const inp = d ? d.querySelector('input[type=file]') : null;
    if (!inp) return 'no_input';

    const dt = new DataTransfer();
    dt.items.add(file);
    Object.defineProperty(inp, 'files', { value: dt.files, writable: true, configurable: true });
    const tracker = inp._valueTracker;
    if (tracker) tracker.setValue('');
    inp.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
    inp.dispatchEvent(new Event('change', { bubbles: true, composed: true }));
    return { ok: true, files: dt.files.length };
}""", b64)
```

**修復方案 B**：`expect_file_chooser()` 是 async context manager
```python
# ✅ 正確用法（Playwright 1.58+）
async with page.expect_file_chooser(timeout=3000) as fc_info:
    fc = await fc_info.value  # await coroutine
    await fc.set_files(image_path, timeout=20000)

# ❌ 錯誤：fc_info.value 是 coroutine，直接 await 用
fc = await fc_info.value  # 先 await
await fc.set_files(...)   # 再用
```

---

## 2. OS File Picker 不關閉（一般 Playwright）

**問題**：點擊「附加影音」按鈕後，OS file picker 彈出但不會自動關閉。

**原因**：`set_input_files()` 在點擊按鈕之後執行，race condition。

**修復**：在點擊按鈕**之前**，先註冊 filechooser 事件監聽器：

```python
file_chooser_future = asyncio.Future()

async def on_file_chooser(fd):
    fd.set_files([])  # 直接取消（用 set_input_files 繞過 OS dialog）

page.on("filechooser", on_file_chooser)

# 然後再點擊按鈕
await page.locator(_svg_btn("附加影音內容")).last.click(timeout=3000, force=True)
await asyncio.sleep(0.3)

# 再 set_input_files
inp = page.locator('[role="dialog"] input[type="file"]').last
await inp.set_input_files(image_path, timeout=5000)
```

---

## 3. shadow DOM — 用 inner_text() 繞過

Google Trends（熱搜榜）和微博熱搜使用 shadow DOM 封裝動態內容，`querySelector` 無法抓到元素。

**症狀**：Trends 頁面打開了，但 `document.querySelectorAll()` 返回空陣列。

**修復**：用 Playwright locator 的 `inner_text()` 讀取 shadow DOM 內容，再文字解析。

```python
# ❌ querySelector 無法穿透 shadow DOM
raw = await page.evaluate("""() => {
    return Array.from(document.querySelectorAll('.trending-item a'))
        .map(el => el.innerText.trim());
}""")

# ✅ 用 inner_text() 讀取 shadow DOM 封裝的內容
body_text = await page.locator("body").inner_text()
lines = [l.strip() for l in body_text.split("\n") if l.strip()]

# 然後用關鍵字過濾 + 數字出現判斷 topic 行
for i, line in enumerate(lines):
    if any(c.isdigit() for c in line) and "Google" not in line:
        if i + 1 < len(lines) and any(c.isdigit() for c in lines[i + 1]):
            topics.append(line)
```

---

## 4. Python 3.9 兼容性

`asyncio.timeout`（Python 3.11+）在 Python 3.9 不可用。

```python
# ❌ asyncio.timeout — Python 3.11+
async with asyncio.timeout(45):
    raw = await loop.run_in_executor(None, fetch)

# ✅ asyncio.wait_for — 所有版本
raw = await asyncio.wait_for(loop.run_in_executor(None, fetch), timeout=45)
```

---

## 5. CDP Port 動態偵測（2026-04+ Chrome 实测）

Chrome 可能跑在任何動態端口（如 49462），不是固定的 9333/9222。**不要硬編碼**，用自動偵測：

```python
import urllib.request
import json

def _get_active_cdp_port() -> int:
    """自動找到第一個有活跃 Chrome CDP 的端口。"""
    # 先查 ~/.cdp_port 文件（可選）
    from pathlib import Path
    try:
        with open(Path.home() / ".cdp_port", "r") as f:
            return int(f.read().strip())
    except Exception:
        pass

    # 列舉常見端口 + 動態端口
    ports_to_try = [49462, 9333, 9222, 9223]
    for port in ports_to_try:
        try:
            req = urllib.request.Request(
                f"http://localhost:{port}/json/version",
                headers={"User-Agent": "Mozilla/5.0"}
            )
            with urllib.request.urlopen(req, timeout=3) as r:
                if r.status == 200:
                    return port
        except Exception:
            pass
    return 9333  # fallback

port = _get_active_cdp_port()
browser = await p.chromium.connect_over_cdp(f"http://localhost:{port}", timeout=30000)
```

**注意**：同一瀏覽器執行 `connect_over_cdp` 後，`browser.contexts[0]` 就是瀏覽器當前所有分頁，不需要重新創建 context。

---

## 6. Gemini 提問打字未完成就提交

**問題**：輸入 prompt 到 Gemini，`keyboard.press("Enter")` 在打字還沒完全結束時就執行，導致 Gemini 只收到部分 prompt。

**原因**：`type(delay=40)` 每字 40ms，對長 prompt 來說很快，但非同步執行還沒完成就按 Enter。`fill("")` 清空後 DOM 還沒穩定。

**修復**：

```python
inp = page.locator(GEMINI_INPUT)
await inp.click()
await inp.fill("")
await asyncio.sleep(1.0)   # 等 fill 完全生效，DOM 穩定
await inp.type(prompt, delay=60)  # 60ms/字，更擬人
await asyncio.sleep(1.5)   # 等 React state 完全更新後才按 Enter
await page.keyboard.press("Enter")
```

### Gemini UI 變更（2026-04+）

**問題**：點擊輸入框時，Angular CDK overlay（全屏暗色背景 + 彈窗）一直攔截 pointer events，30秒後超時。

**根因**：Gemini 右上角彈出「探索資訊卡」提示窗，aria-label 為 `確認同關閉探索資訊卡。`，擋住點擊。

**修復**：在點擊輸入框之前，先嘗試關閉此 dialog：

```python
async def call_gemini(page, prompt: str, timeout=90) -> str:
    # 先關閉可能阻擋的 feature dialog
    try:
        close_btn = page.locator('button[aria-label="確認同關閉探索資訊卡。"]')
        if await close_btn.count() > 0:
            await close_btn.click(timeout=3000)
            await asyncio.sleep(1)
    except Exception:
        pass

    inp = page.locator('div[aria-label="向 Gemini 輸入提示"]')  # 2026-04+ 的 aria-label
    await inp.click()
    await inp.fill("")
    await asyncio.sleep(1.0)
    await inp.type(prompt, delay=60)
    await asyncio.sleep(1.5)
    await page.keyboard.press("Enter")
    # ... 後面的等待邏輯
```

**注意**：`div[aria-label="請輸入 Gemini 提示詞"]` 是舊版 selector，2026-04+ 已改為 `向 Gemini 輸入提示`。用 `[aria-label*="Gemini"]` 或 `[aria-label*="輸入"]` 更穩健。

---

## 7. Threads 兩步發文流程

Threads 發文是獨特的兩步流程，其他平台不同：

```
Step 1: 點 composer → dialog 開
Step 2: 打字 → 圖片
Step 3: 點「新增到串文」（不是「發佈」！）
Step 4: 進入 caption 審查頁
Step 5: 點「發佈」（第二步的按鈕）
```

**易錯點**：直接找「發佈」按鈕在第一步是找不到的，必須先點「新增到串文」。

按鈕點擊用 `getBoundingClientRect → mouse.click` 座標，不要用 Playwright locator.click（React onClick 不觸發）。

---

## 4. CDP 操作速率限制

**問題**：短時間內 CDP 操作（evaluate/click/type）太密集，Chrome 分頁崩潰或開啟垃圾頁面。

**修復**：每次 CDP 操作後間隔至少 0.5-1 秒。

```python
await page.evaluate("...")  # CDP
await asyncio.sleep(0.5)    # 等一下
await page.mouse.click(...)  # CDP
await asyncio.sleep(0.5)    # 等一下
```

---

## 5. Threads / Facebook tab 必須預先開啟

`post_threads.py` 和 `post_facebook.py` 依賴已存在的社交平台 tab，如果 tab 不存在會直接失敗。

在 workflow 中，確保在 call 發文函數之前有：

```python
async def ensure_social_tabs(ctx):
    """確保 Threads 和 Facebook tab 已開啟。"""
    # Threads
    threads_tab = None
    fb_tab = None
    for pg in ctx.pages:
        if "threads.net" in pg.url and "settings" not in pg.url:
            threads_tab = pg
        if "facebook.com" in pg.url or "fb.com" in pg.url:
            fb_tab = pg

    if not threads_tab:
        threads_tab = await ctx.new_page()
        await threads_tab.goto("https://www.threads.net/", wait_until="domcontentloaded", timeout=20000)
        await asyncio.sleep(3)

    if not fb_tab:
        fb_tab = await ctx.new_page()
        await fb_tab.goto("https://www.facebook.com/", wait_until="domcontentloaded", timeout=20000)
        await asyncio.sleep(3)

    return threads_tab, fb_tab
```

**重要**：執行 `post_threads()` 或 `post_facebook()` 時，必須保證 tab 已在瀏覽器中開啟且已登入。

---

## 驗證清單（每次發文後必查）

- [ ] Dialog 是否已關閉（`locator('[role="dialog"]').wait_for(state="hidden")`）
- [ ] 文字是否出現在編輯框（`inner_text()` 確認）
- [ ] 圖片 blob URL 是否生成（`img.src.startsWith('blob:')`）
- [ ] Reload 後內容是否還在（最可靠的驗證方式）
