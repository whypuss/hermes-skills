---
name: threads-composer-dialog-workflow
description: Threads CDP Browser Hijacking — dialog-based composer workflow, image posting, and profile verification.
trigger: posting to Threads via CDP browser hijacking, or Threads CDP automation
tags: [threads, cdp, browser-automation]
---

# Threads CDP Browser Hijacking — Complete Workflow

## Key Discovery: Threads UI is Dialog-Based

Unlike a normal web form, Threads uses a **modal dialog** (`role=dialog`, text includes "新串文") for composing posts.

**Critical findings:**
1. The URL is `threads.com` (NOT `threads.net`)
2. The compose button is `svg[aria-label="建立"]` — parentElement is clickable
3. Threads dialog buttons are `DIV[role="button"]` (NOT `<button>` elements)
4. After clicking "建立", you must click "新增到串文" to reveal the file input
5. The file input (`input[type="file"]`) appears INSIDE the dialog AFTER clicking "新增到串文"
6. The "發佈" button is inside the dialog, matching `b.innerText?.trim() === '發佈'`
7. After uploading image, wait for "發佈" button to appear before clicking it

## Complete Workflow

### Step 1: Get Browser-Level CDP WebSocket URL
```python
# CRITICAL: Use /json/version for browser-level URL (supports new_page())
# Do NOT use /json/list page-level URLs — they don't support new_page()
import urllib.request, json

with urllib.request.urlopen(f"http://localhost:{CDP_PORT}/json/version", timeout=5) as resp:
    data = json.loads(resp.read().decode())
browser_ws = data["webSocketDebuggerUrl"]
# browser_ws = "ws://localhost:9333/devtools/browser/UUID"
```

### Step 2: Connect to Browser and Find Threads Page
```python
async with async_playwright() as p:
    browser = await p.chromium.connect_over_cdp(browser_ws)
    ctx = browser.contexts[0]

    threads_page = None
    for pg in ctx.pages:
        try:
            # threads.com NOT threads.net
            if ("threads.com" in pg.url or "threads.net" in pg.url) and "login" not in pg.url.lower():
                threads_page = pg
                break
        except:
            pass

    if not threads_page:
        threads_page = await ctx.new_page()
        await threads_page.goto("https://www.threads.net", wait_until="load", timeout=30000)
        await asyncio.sleep(3)
```

### Step 3: Open Composer Dialog
```python
# Click the "建立" button (svg aria-label)
await threads_page.evaluate("""
    () => {
        const svgs = document.querySelectorAll('svg[aria-label="建立"]');
        if (svgs.length > 0) svgs[0].parentElement.click();
    }
""")
await asyncio.sleep(2)

# Wait for dialog to appear
for _ in range(20):
    dialog = await threads_page.query_selector('div[role="dialog"]')
    if dialog: break
    await asyncio.sleep(0.5)
```

### Step 4: Click "新增到串文" Button
```python
# Buttons in dialog are DIV[role="button"], NOT <button> elements
await threads_page.evaluate("""
    () => {
        const dialog = document.querySelector('div[role="dialog"]');
        if (!dialog) return;
        const btns = dialog.querySelectorAll('button, div[role="button"]');
        for (const b of btns) {
            if (b.innerText?.trim() === '新增到串文') { b.click(); return; }
        }
    }
""")
await asyncio.sleep(1)
```

### Step 5: Upload Image
```python
# File input appears inside dialog AFTER clicking "新增到串文"
file_input = None
for _ in range(15):
    try:
        file_input = await threads_page.query_selector('div[role="dialog"] input[type="file"]')
        if file_input: break
    except: pass
    await asyncio.sleep(0.5)

if file_input:
    await file_input.set_input_files(img_path)
    print(f"Image uploaded: {img_path}")
    await asyncio.sleep(4)  # Wait for upload to complete
```

### Step 6: Wait for "發佈" Button (Image Upload Must Complete First)
```python
# 發佈 button only appears/enables after image upload is complete
for _ in range(30):
    ready = await threads_page.evaluate("""
        () => {
            const dialog = document.querySelector('div[role="dialog"]');
            if (!dialog) return false;
            const btns = dialog.querySelectorAll('button, div[role="button"]');
            for (const b of btns) {
                if (b.innerText?.trim() === '發佈') {
                    const style = window.getComputedStyle(b);
                    return style.display !== 'none' && style.visibility !== 'hidden';
                }
            }
            return false;
        }
    """)
    if ready: break
    await asyncio.sleep(0.5)
```

### Step 7: Type Caption
```python
# contenteditable has aria-label containing "文字欄位"
await threads_page.evaluate("""
    () => {
        const dialog = document.querySelector('div[role="dialog"]');
        if (!dialog) return;
        const targets = dialog.querySelectorAll('[contenteditable="true"], [role="textbox"], textarea');
        for (const t of targets) {
            if (t.getAttribute('aria-label')?.includes('文字欄位')) { t.focus(); return; }
        }
    }
""")
await asyncio.sleep(0.5)
await threads_page.keyboard.type(caption, delay=30)
```

### Step 8: Click "發佈" Button
```python
# Use DIV[role="button"] selector, NOT button element selector
published = await threads_page.evaluate("""
    () => {
        const dialog = document.querySelector('div[role="dialog"]');
        if (!dialog) return false;
        const btns = dialog.querySelectorAll('button, div[role="button"]');
        for (const b of btns) {
            if (b.innerText?.trim() === '發佈') { b.click(); return true; }
        }
        return false;
    }
""")
```

### Step 9: Verify
```python
await asyncio.sleep(5)
page_text = await threads_page.inner_text("body")
if "已發佈" in page_text or "Posted" in page_text:
    print("✅ Threads confirmed: posted")
else:
    print("ℹ️ Posted (could not confirm)")
```

## Dialog Inspector (Debug Tool)
```python
r = await threads_page.evaluate("""
    () => {
        const d = document.querySelector('div[role="dialog"]');
        if (!d) return 'no dialog';
        const btns = Array.from(d.querySelectorAll('button, div[role="button"]'))
            .map(b => ({ tag: b.tagName, text: b.innerText?.trim(), aria: b.getAttribute('aria-label') }));
        const fileInputs = Array.from(d.querySelectorAll('input[type="file"]'))
            .map(i => ({ accept: i.accept }));
        return JSON.stringify({ buttons: btns, fileInputs });
    }
""")
print(r)
```

## CDP WebSocket: Browser-Level vs Page-Level

| URL Pattern | new_page() | Use Case |
|------------|-----------|----------|
| `/json/version` → `ws://.../browser/{id}` | ✅ Works | Use this for Playwright `connect_over_cdp` + `new_page()` |
| `/json/list` → `ws://.../page/{id}` | ❌ Fails | Page-level connection — do NOT use for creating new pages |

**Always use `/json/version` to get the browser WebSocket URL.**

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Cannot read properties of undefined (reading '_page')` | Used page-level CDP URL | Use `/json/version` browser-level URL |
| 404 on WebSocket | `/page/` → `/browser/` replacement doesn't work | Use `/json/version` directly |
| 發佈 button not found | Dialog buttons are `DIV[role="button"]`, not `<button>` | Use `querySelectorAll('button, div[role="button"]')` |
| File input not found | Must click "新增到串文" first | Click "新增到串文" before looking for file input |
| 發佈 button exists but click fails | Image not uploaded yet | Wait for 發佈 button to be visible (image upload complete) |
| URL shows `threads.com` not `threads.net` | Threads migrated | Match both `threads.com` and `threads.net` |
| 建立 button not found | aria-label is "建立", not "新帖子" | Use `svg[aria-label="建立"]` |

## Critical: CDP React Hydration Issue

Threads uses heavy client-side React rendering. When connecting via raw CDP WebSocket, `Runtime.evaluate` queries may return **0 elements** even when the page appears visually loaded. This is a **React hydration timing issue**.

**Symptoms:**
- `querySelectorAll` returns empty array
- `document.querySelectorAll` returns 0 elements
- But `innerText` on `document.body` returns actual content (page IS loaded)
- CDP `Page.captureScreenshot` works fine

**Root cause:** Threads' React app hasn't finished hydrating the DOM. CDP's `Runtime.evaluate` runs before React attaches event handlers and populates the virtual DOM.

**Workaround: Use Playwright page methods, not raw CDP**
```python
# ❌ Raw CDP — fails with hydration issue
async with websockets.connect(page_ws) as ws:
    await ws.send(json.dumps({'method': 'Runtime.evaluate', 'params': {...}}))

# ✅ Playwright — has proper React synchronization
threads_page = await ctx.pages[N]
await threads_page.click('svg[aria-label="建立"]')  # Playwright waits for hydration
await threads_page.wait_for_selector('div[role="dialog"]')
```

**Rule: Use Playwright for all DOM operations (click, type, wait_for_selector). Only use CDP WebSocket for low-level Input events (dispatchKeyEvent, mouse click coordinates) and when Playwright fails.**

## Text-Only Composer: contenteditable Identification

When opening the text-only composer (without image), Threads creates **5 identical contenteditable divs** with the same `aria-label`. Most contain placeholder or old text.

**To find the correct input box:**
```python
# Method 1: By dimensions (the empty one)
correct_div = await threads_page.evaluate("""
    () => {
        const targets = document.querySelectorAll('[contenteditable="true"][aria-label][role="textbox"]');
        for (const t of targets) {
            const rect = t.getBoundingClientRect();
            if (rect.height === 21 && rect.top > 200) { // empty one is h=21, top~256
                return t.innerText === '' ? 'empty_correct' : 'has_content';
            }
        }
        return 'not_found';
    }
""")

# Method 2: By inspecting all 5 and filtering
all_divs = await threads_page.evaluate("""
    () => Array.from(document.querySelectorAll('[contenteditable="true"]'))
        .map(el => ({
            aria: el.getAttribute('aria-label'),
            text: el.innerText.slice(0, 30),
            h: el.getBoundingClientRect().height,
            top: el.getBoundingClientRect().top
        }))
""")
# The correct one: aria matches "新動態" pattern, height=21, top~256, text=''
```

**Typing into the correct div with CDP:**
```python
# First focus using Playwright
await threads_page.click('[contenteditable="true"][aria-label][role="textbox"]')

# Then use CDP for character-by-character input
async with websockets.connect(browser_ws) as ws:
    for ch in text:
        await ws.send(json.dumps({
            'id': cid, 'method': 'Input.dispatchKeyEvent',
            'params': {'type': 'keyDown', 'text': ch, 'key': ch}
        }))
        json.loads(await ws.recv())
        await ws.send(json.dumps({
            'id': cid, 'method': 'Input.dispatchKeyEvent',
            'params': {'type': 'keyUp', 'text': ch, 'key': ch}
        }))
        json.loads(await ws.recv())
```

## Weibo Hot Search API

```bash
curl -sL "https://weibo.com/ajax/statuses/hot_band" \
  -H "User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X)" \
  -H "Referer: https://weibo.com"
```
Response: JSON with `band_list[].word` — no authentication required. Use `band_list[N]` where N starts at 0 for rank 1.
