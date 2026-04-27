---
name: instagram-cdp-post-workflow
description: Instagram posting via CDP Browser Hijacking — locator.press("Enter") React workaround, Threads profile composer quirk, social workflow architecture
trigger: posting to Instagram via CDP browser hijacking, Instagram CDP automation, Instagram playwright automation
tags: [instagram, cdp, browser-automation, aipuss-browser]
---

# Instagram CDP Browser Hijacking — Posting Workflow (2026 Update)

## ⚠️ CRITICAL: Two Different UI Flows (2026-04 Update)

**重要發現**：Instagram 新 UI 有兩種流程，舊 skill 只記錄了其中一種：

### Flow A（舊 UI）：上傳 → filter 頁 → 下一步 → details/sharing 頁
### Flow B（新 UI，2026-04 實測）：上傳 → 直接跳到 sharing 頁（跳過 filter）

**腳本必須支援兩種流程**，否則在 Flow B 會卡住等待「下一步」按鈕。

---

## ⚠️ CRITICAL: CDP Input.dispatchKeyEvent(Enter) for "下一步"

**This session's key finding (2026-04-26):** Using CDP `Input.dispatchKeyEvent(Enter)` for navigating "下一步" is **more reliable** than JS `element.click()`.

**Why:** JS `.click()` on "下一步" can trigger the "捨棄貼文？" abandonment dialog, especially when React's synthetic event system is involved. CDP `Input.dispatchKeyEvent` simulates a real keyboard event that bypasses this issue.

**The proven workflow (this session):**
```
CDP Enter keyDown+Up on "下一步" (after JS focus) → ✅ Works consistently
JS element.click() on "下一步" → ⚠️ Can trigger abandonment dialog
JS element.click() on "分享" → ✅ Works fine (different element type)
```

```python
# ✅ Proven: CDP Enter for "下一步" navigation
await ig.evaluate("""
    () => {
        const dialog = document.querySelector("[role='dialog']");
        if (!dialog) return;
        const btns = Array.from(dialog.querySelectorAll('button, [role="button"]'));
        for (const btn of btns) {
            if ((btn.textContent || '').trim() === '下一步') {
                btn.focus();
                return;
            }
        }
    }
""")
# Then send CDP Enter
cid = 999
for ch in ['Enter']:
    await ws.send(json.dumps({
        'id': cid, 'method': 'Input.dispatchKeyEvent',
        'params': {'type': 'keyDown', 'key': ch, 'code': 'Enter', 'windowsVirtualKeyCode': 13}
    }))
    json.loads(await ws.recv())
    await ws.send(json.dumps({
        'id': cid, 'method': 'Input.dispatchKeyEvent',
        'params': {'type': 'keyUp', 'key': ch, 'code': 'Enter', 'windowsVirtualKeyCode': 13}
    }))
    json.loads(await ws.recv())

# ✅ JS click for "分享" (div[role=button]) — still works fine
await ig.evaluate("""
    () => {
        const dialog = document.querySelector("[role='dialog']");
        if (!dialog) return;
        const btns = Array.from(dialog.querySelectorAll('[role="button"], button'));
        for (const btn of btns) {
            if ((btn.textContent || '').trim() === '分享') { btn.click(); return; }
        }
    }
""")
```

## Complete Posting Flow (2026 Instagram UI)

### Step 1: Click "新貼文"
```python
await ig.evaluate(
    "() => document.querySelector('svg[aria-label=\"新貼文\"]')?.parentElement?.click()"
)
await asyncio.sleep(3)
```

### Step 2: Upload Image
Instagram requires JPEG. Convert if needed:
```python
from PIL import Image
converted_path = "/tmp/upload_ig.jpg"
img_obj = Image.open(img_path)
if img_obj.mode != 'RGB':
    img_obj = img_obj.convert('RGB')
img_obj.save(converted_path, 'JPEG', quality=92)

for _ in range(10):
    file_input = await ig.query_selector("[role='dialog'] input[type='file']")
    if file_input: break
    await asyncio.sleep(0.5)
else:
    return "❌ 找不到 file input"

await file_input.set_input_files(converted_path)
await asyncio.sleep(5)
```

### Step 3: Handle Filter OR Skip (Two Possible Flows)

```python
# Wait for dialog to stabilize
for _ in range(20):
    await asyncio.sleep(0.5)
    dialog_text = await ig.evaluate("""() => {
        const d = document.querySelector("[role='dialog']");
        return d ? d.innerText?.slice(0, 300) : '';
    }""")
    if not dialog_text:
        continue
    # Filter page keywords
    if any(kw in dialog_text for kw in ['濾鏡', 'Aden', 'Clarendon', '下一步']):
        print("[IG] 到達 filter 頁")
        break
    # Sharing page keywords (Flow B — no filter)
    if any(kw in dialog_text for kw in ['說明文字', '撰寫說明', '分享到', '分享\n']):
        print("[IG] 到達 sharing 頁（跳過 filter）")
        break
else:
    print(f"[IG] dialog 等待中: {dialog_text[:100]}")

# ── If on filter page: click "下一步" ──
dialog_text = await ig.evaluate("""() => {
    const d = document.querySelector("[role='dialog']");
    return d ? d.innerText?.slice(0, 300) : '';
}""")

if '下一步' in dialog_text:
    print("[IG] 在 filter 頁，點下一步")
    for attempt in range(3):
        # Try JS click first
        result = await ig.evaluate("""() => {
            const dialog = document.querySelector("[role='dialog']");
            if (!dialog) return 'no_dialog';
            const btns = Array.from(dialog.querySelectorAll('button, [role='button']'));
            for (const btn of btns) {
                const text = (btn.textContent || '').trim();
                if (text === '下一步') { btn.click(); return 'js_clicked'; }
            }
            // aria-label approach
            for (const btn of dialog.querySelectorAll('[aria-label="下一步"]')) {
                btn.click(); return 'aria_clicked';
            }
            return 'not_found';
        }""")
        if 'not_found' not in result:
            print(f"[IG] 下一步: {result}")
            break
        await asyncio.sleep(1)
    
    # Wait for details/sharing page
    for _ in range(20):
        await asyncio.sleep(0.5)
        dt = await ig.evaluate("""() => {
            const d = document.querySelector("[role='dialog']");
            return d ? d.innerText?.slice(0, 300) : '';
        }""")
        if '說明文字' in dt or '撰寫說明' in dt or '分享' in dt:
            print("[IG] 到達 caption/sharing 頁")
            break
```

### Step 4: Type Caption (2026-04 实测 — div[contenteditable], NOT textarea)

```python
def _type_caption(ig, text: str) -> str:
    """2026-04 實測：caption 欄位是 div[aria-label='撰寫說明文字……'][contenteditable=true]"""
    return ig.evaluate(
        """([txt]) => {
            const dialog = document.querySelector("[role='dialog']");
            if (!dialog) return 'no_dialog';

            // 找 contenteditable，aria-label 含「撰寫」or「說明文字」
            const ces = Array.from(dialog.querySelectorAll('[contenteditable="true"]'));
            for (const ce of ces) {
                const style = window.getComputedStyle(ce);
                const aria = ce.getAttribute('aria-label') || '';
                if (style.display !== 'none' && (aria.includes('撰寫') || aria.includes('說明文字'))) {
                    ce.focus();
                    ce.innerText = txt;
                    ce.dispatchEvent(new Event('input', { bubbles: true }));
                    return 'caption:' + aria;
                }
            }

            // Fallback: 任意可見的 contenteditable
            for (const ce of ces) {
                const style = window.getComputedStyle(ce);
                if (style.display !== 'none') {
                    ce.focus();
                    ce.innerText = txt;
                    ce.dispatchEvent(new Event('input', { bubbles: true }));
                    return 'contenteditable_fallback';
                }
            }

            return 'no_editor';
        }""",
        [text]
    )

for attempt in range(5):
    type_result = await _type_caption(ig, caption)
    print(f"[IG] caption 嘗試 {attempt+1}: {type_result}")
    if 'no_editor' not in type_result:
        break
    await asyncio.sleep(1)
```

### Step 5: Click "分享" (div[role=button], NOT button element!)

```python
# 2026-04 實測：「分享」是 div[role=button]，非 <button>
# locator.press("Enter") 無法找到，必須用 JS click
async def _click_share_button(ig) -> bool:
    # Method 1: JS click (2026-04 實測有效)
    result = await ig.evaluate("""() => {
        const dialog = document.querySelector("[role='dialog']");
        if (!dialog) return false;
        const buttons = Array.from(dialog.querySelectorAll('[role='button'], button'));
        for (const btn of buttons) {
            const text = (btn.textContent || '').trim();
            if (text === '分享' || btn.getAttribute('aria-label') === '分享') {
                btn.click();
                return 'clicked:' + text;
            }
        }
        return 'not_found';
    }""")
    print(f"[IG] 分享: {result}")
    return 'not_found' not in result

share_ok = await _click_share_button(ig)
if not share_ok:
    return "❌ 找不到分享按鈕"

# 等 dialog 關閉（發布成功後 IG 自動關閉 dialog）
for _ in range(20):
    await asyncio.sleep(1)
    dt = await ig.evaluate("""() => {
        const d = document.querySelector("[role='dialog']");
        return d ? d.innerText?.slice(0, 100) : '';
    }""")
    if not dt or '建立新貼文' not in dt:
        print("[IG] dialog 已關閉，發布成功")
        break
```

## ⚠️ Old Method (CDP Input.dispatchMouseEvent) — Still Works but Obsolete

The old skill documented CDP Input.dispatchMouseEvent as the only working method. It still works but is more complex:

```python
async def _cdp_click(ig, x, y):
    cdp = await ig.context.new_cdp_session(ig)
    await cdp.send('Input.dispatchMouseEvent', {'type': 'mousePressed', 'x': x, 'y': y, 'button': 'left', 'clickCount': 1})
    await cdp.send('Input.dispatchMouseEvent', {'type': 'mouseReleased', 'x': x, 'y': y, 'button': 'left', 'clickCount': 1})
```

The locator.press("Enter") method is simpler and preferred.

## Threads CDP Automation — Profile Page Quirk

Threads does NOT have the React synthetic event problem — `page.evaluate(() => el.click())` works fine.

But Threads has its own quirk: **on profile pages, the composer is hidden**. You must click "建立" first.

```python
# On profile pages (@username), "文字欄位空白" is NOT visible until you click 建立
click_result = await threads_page.evaluate("""
    () => {
        // First check if composer is already open
        const els = document.querySelectorAll("[aria-label]");
        for (const el of els) {
            if (el.getAttribute("aria-label").includes("文字欄位空白")) {
                el.click(); return "composer-clicked";
            }
        }
        // Composer not open — click "建立" button
        for (const svg of document.querySelectorAll('svg[aria-label="建立"]')) {
            const parent = svg.parentElement;
            if (parent) { parent.click(); return "establish-clicked"; }
            const gp = parent?.parentElement;
            if (gp) { gp.click(); return "establish-clicked-gp"; }
        }
        return "not found";
    }
""")
if click_result == "not found":
    return "❌ Composer area not found"

await asyncio.sleep(2)

# Now click the actual textarea
composer_result = await threads_page.evaluate("""
    () => {
        const els = document.querySelectorAll("[aria-label]");
        for (const el of els) {
            if (el.getAttribute("aria-label").includes("文字欄位空白")) {
                el.click(); return "composer-clicked";
            }
        }
        return "not found";
    }
""")
```

## Social Workflow Architecture — Single CDP Connection

When building workflows that use CDP across multiple steps (X trending → Google Images → post to multiple platforms):

1. **Single CDP connection** — connect once, reuse the browser context throughout
2. **Don't call `browser.close()` between steps** — it kills the CDP session for ALL subsequent steps
3. **Each posting function (post_ig, post_facebook, post_threads) opens its own connection** — they all connect to the SAME running Chromium via CDP, so they share pages/cookies. The existing connection is reused.

```python
async with async_playwright() as p:
    port = _get_active_port()
    browser = await p.chromium.connect_over_cdp(f"http://localhost:{port}", timeout=20000)
    ctx = browser.contexts[0]
    
    # All steps use the same ctx...
    # get_x_trending(ctx)
    # search_google_image(ctx)
    # close_extra_pages(ctx)
    # post_facebook(text, img) — internally reconnects to same Chromium
    # post_ig(text, img)
    # post_threads(text, img)
    
    await browser.close()  # Only close at the very end
```

## CDP Port Detection

```python
def _get_active_port():
    for port in [9333, 9222]:
        try:
            req = urllib.request.Request(f"http://localhost:{port}/json/version")
            with urllib.request.urlopen(req, timeout=3) as r:
                if r.status == 200:
                    return port
        except Exception:
            pass
    return 9333
```

## Instagram UI Element Reference (2026-04 實測)

| Element | DOM 類型 | 2026-04 實測 Selector |
| ------- | -------- | --------------------- |
| "新貼文" 按鈕 | SVG + parentElement | `svg[aria-label="新貼文"]` → parentElement |
| 圖片上傳 input | `input[type='file']` | `[role='dialog'] input[type='file']` |
| "下一步" | `button` 或 `div` | JS 遍歷 dialog 找 `text === '下一步'` |
| Caption 輸入框 | `div[contenteditable][aria-label="撰寫說明文字……"]` | `dialog.querySelector('[contenteditable="true"]')` + aria filter |
| "分享" 按鈕 | `div[role='button']`（非 `<button>`！） | JS 遍歷 dialog 找 `text === '分享'` |
| 平臺切換 | `div` | `text === 'Threads'` / `text === 'Facebook'` |

**caption 欄位關鍵**：舊 skill 寫 `textarea[aria-label*="說明文字"]`，2026-04 實測是 `div[aria-label="撰寫說明文字……"][contenteditable=true]`，屬性值結尾有省略號。

## Known Pitfalls

| 症狀 | 原因 | 修復 |
| ---- | ---- | ---- |
| 「分享」點擊後無反應 | 用 `locator.press("Enter")` 找 `div[role=button]` | 必須用 JS `el.click()` |
| caption 輸入無效 | 用了 textarea selector | 改用 `div[contenteditable][aria-label*="撰寫"]` |
| 等待「下一步」超時 | IG 新 UI 跳過 filter 頁 | 自動偵測 dialog 文字，Flow B 直接進 sharing 頁 |
| 圖片上傳後 IG 無響應 | 圖片格式非 JPEG | 用 PIL 轉換成 RGB JPEG |
| dialog 等待超時 | 對話框從未彈出 | 強行 `goto('https://www.instagram.com/')` 重試 |
