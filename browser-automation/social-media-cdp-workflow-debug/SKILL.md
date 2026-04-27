---
name: social-media-cdp-workflow-debug
description: Debug aipuss-browser CDP social media workflows — opencli strategies, common script bugs, Threads realities
category: browser-automation
---

# Social Media CDP Workflow Debug

Debugging aipuss-browser CDP-based social media posting workflows (Threads → Facebook cross-posting).

## opencli Command Strategies (Critical Distinction)

opencli has three command modes - knowing which applies is essential:

- `[public]` — RSS/API only, **no browser needed**, works immediately
- `[cookie]` — needs browser cookies (usually also requires extension)
- `[intercept]` — needs Chrome Bridge extension + browser open, most social media commands

Commands that worked without extension:
```
v2ex hot, v2ex latest        ✅
hackernews top, best, new     ✅
google news                   ✅
bbc news                      ✅ (RSS)
```

Commands that timed out or failed (need extension or blocked):
```
twitter search                ❌ intercept (needs extension)
reddit hot, search            ❌ intercept (needs extension)
weibo hot, search             ❌ timeout
36kr hot                      ❌ timeout
tieba hot                     ❌ timeout
hupu search                   ❌ timeout
threads (any)                 ❌ NO ADAPTER EXISTS
```

## Common workflow_a.py Bugs

1. **Navigation via `window.location.href` breaks CDP session** — page actually unloads, subsequent CDP commands fail silently. Use `oc(["open", url])` instead.

2. **NameError from mismatched function names** — script called `find_x_post()` but function was `find_x_fallback()`. Also `post_fb()` vs `post_facebook()`. Always verify function name matches call.

3. **X.com login wall** — even with CDP, the FacebookMCP Chromium profile may not be logged into X.com. Check with snapshot before scraping.

## Workflow Script Structure

```python
OPENCLI = "/Users/whypuss/.local/bin/aipuss-browser"
FB_CDP  = "ws://localhost:9333/devtools/browser/6EB059EE1549FEE82BE0B4335B7BEEAB"
TH_CDP  = "ws://localhost:9333/devtools/browser/72f92c07-5a67-48a0-9d5f-87d7644024c9"

def oc(args, timeout=30):
    r = subprocess.run([OPENCLI]+args, capture_output=True, text=True, timeout=timeout)
    return r.stdout.strip(), r.returncode

def ss(ms):
    time.sleep(ms / 1000)  # Python sleep, NOT CDP wait
```

Each function should `oc(["open", "about:blank"])` before starting to reset session state.

## Facebook Composer Dialog Structure (Critical)

Facebook's post composer has **THREE separate dialogs** after clicking "在想什麼":

| Dialog | aria-label | file inputs | contenteditable | purpose |
|--------|------------|-------------|-----------------|---------|
| dialog[0] | `_r_N_` (aria-labelledby) | 2 (hidden) | 1 | Main composer — **THIS ONE** |
| dialog[1] | 建立帖子 | 0 | 0 | Header/close only |
| dialog[2] | 新增到帖子 | 0 | 0 | Media picker — **NOT USEFUL** |

**Key findings:**

1. **File input is in dialog[0]** — the hidden `<input type="file">` (display:none, accept="image/*") is inside dialog[0], NOT inside the "新增到帖子" dialog. Clicking "新增到帖子" opens a SEPARATE media picker that doesn't contain the file input.

2. **Submit button is always `display:none`** — `input[type=submit]` inside dialog[0] has `display:none`. Facebook's real submit is triggered by:
   ```javascript
   // CORRECT — dispatch submit event to form
   const submit = mainDlg.querySelector("input[type=submit]");
   const form = submit.closest("form");
   form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
   ```

3. **Image file extension matters** — Twitter images downloaded via `?format=png&name=medium` return PNG data but Chrome saves them as `.jpg`. Facebook's file input accepts `image/*` but Playwright's `set_input_files()` needs the actual binary format. Ensure downloaded images have the correct extension matching their actual MIME type.

**Correct Facebook image upload sequence:**
```python
# Open composer
composer = page.locator('div[role="button"]').filter(has_text="在想什麼").first
await composer.click()
await asyncio.sleep(2)

# Type text — use dialog[0]'s contenteditable
editor = page.locator('[role="dialog"]').nth(0).locator('[contenteditable="true"]').first
await editor.click()
await page.keyboard.type(message, delay=30)

# Upload image — file input is in dialog[0], NOT in "新增到帖子" dialog
file_input = page.locator('[role="dialog"]').nth(0).locator('input[type="file"]').first
await file_input.set_input_files(correct_image_path, timeout=15000)
await asyncio.sleep(3)  # Wait for Facebook to process image

# Submit via form.submit (submit button is display:none)
result = await page.evaluate('''
    () => {
        const mainDlg = document.querySelectorAll("[role=dialog]")[0];
        const submit = mainDlg?.querySelector("input[type=submit]");
        const form = submit?.closest("form");
        if (form) { form.dispatchEvent(new Event("submit", {bubbles:true, cancelable:true})); return "ok"; }
        return "fail";
    }
''')
await asyncio.sleep(3)
```

## One Profile to Rule Them All

**FacebookMCP profile covers EVERYTHING:**
- Facebook ✅
- Instagram ✅
- Threads ✅ (via Facebook login)
- Google/Gemini ✅
- X.com — anonymous, no login needed

Copy the entire `~/Library/Application Support/Chromium/FacebookMCP/` directory to a new machine — no re-login needed for any platform above.

## Instagram Posting Flow (Desktop Web — Updated 2026-04-25)

Instagram UI changed in 2026. Key differences:

| Old (2024) | New (2026) |
|------------|------------|
| "下一步" button | "繼續" or "下一步" (both exist) |
| `contenteditable` for caption | `<textarea>` for caption |
| URL: `/create/...` | URL: `/create/details` for caption page |

**Instagram composer flow (updated):**
1. Click create button → upload image
2. **URL判斷**：wait for `/create/style` or `/create/crop` → click "繼續" or "下一步"
3. Wait for `/create/details` URL → this is the caption page
4. Caption input is now `<textarea>` (not contenteditable):
   ```python
   textarea = page.query_selector('textarea')
   await textarea.fill(caption_text)
   ```
5. Click "分享" button

**Caption selector (updated):**
```python
# OLD (2024):
editable = page.locator('[contenteditable="true"], [role="textbox"]')

# NEW (2026):
textarea = page.locator('textarea')
await textarea.fill(caption_text)
```

**Button text compatibility:**
```python
# Both "繼續" and "下一步" may appear — check for either:
btns = document.querySelectorAll('button')
for (const b of btns) {
    const t = b.innerText?.trim()
    if (t === '繼續' || t === '下一步') { b.click(); return; }
}
```

**IG left sidebar links** (no aria-labels, use href + position):

| y position | href | Purpose |
|-----------|------|---------|
| 110 | `/reels/` | Reels |
| 162 | `/direct/inbox/` | Messages |
| 214 | `/#` | **Home** (main feed) |
| 266 | `/explore/` | Explore |
| 318 | `/#` | Notifications |
| 370 | `/#` | **Create post (+)** |
| 422 | `/whypuss_fun/` | Profile |
| 475 | `/#` | Settings |
| 527 | `/#` | Logout |

**Full post flow:**
1. Click create button at `x=12, y=370` (href=`https://www.instagram.com/#`)
2. Dialog appears → click "從電腦選擇" (file input inside dialog)
3. Click `下一步` (top-right) ×2
4. Enter caption text
5. Click "分享" (top-right)
6. Click "完成"

**Caption input**: aria-label not yet confirmed — needs CDP inspection during the post flow.

## Threads Realities (CRITICAL — React Event Handler Issue)

- No opencli adapter exists for Threads — must use CDP directly via social-mcp
- **CRITICAL**: Threads' React synthetic event system intercepts ALL pointer events. Using `locator.click(force=True)` dispatches raw mouse events that bypass React's onClick handler — the dialog **never opens**.
- **CORRECT**: Always use `page.evaluate()` to click:
  ```python
  click_result = await threads_page.evaluate("""
      () => {
          const els = document.querySelectorAll("[aria-label]");
          for (const el of els) {
              if (el.getAttribute("aria-label").includes("文字欄位空白")) {
                  el.click(); return "clicked";
              }
          }
          return "not found";
      }
  """)
  ```
- `window.location.href` in eval breaks CDP → use Playwright's `page.goto()` instead
- Threads search pages load dynamically, need 5+ second sleeps after navigation
- **PNG images with Mode P (palette)** do NOT display — convert to RGBA before uploading:
  ```python
  from PIL import Image
  img = Image.open(path)
  if img.mode == 'P':
      img = img.convert('RGBA')
  rgb_path = path.replace('.png', '_rgba.png')
  img.save(rgb_path)
  ```

## X.com Scraping (via social-mcp — NO AIpuss Needed)

X.com works WITHOUT login. Use social-mcp's Chromium (FacebookMCP profile) — no separate browser needed.

```python
# Trending topics — 20ms fetch time
await page.goto("https://x.com/explore/tabs/trending")
await asyncio.sleep(2)
trending = await page.evaluate("""() => {
    const cells = document.querySelectorAll("[data-testid='cellInnerDiv']");
    return Array.from(cells)
        .map(c => c.innerText)
        .filter(t => t.length > 20 && t.length < 500);
}""")
# Returns: ["#TermMaxPuzzleChallenge", "#SECAwards", ...]
```

X.com selectors (verified 2026-04-25):
- `data-testid='cellInnerDiv'` — trending topic cells
- `data-testid='primaryColumn'` — main column (count: 1)
- No login required for trending pages

## Gemini Capabilities (via social-mcp)

Gemini web works with Google login in FacebookMCP profile. Verified 2026-04-25.

**What works (free tier):**
- Text conversation and analysis
- GitHub project analysis
- Code explanation

**What does NOT work (free tier):**
- Image generation (needs Google AI Plus)
- Conversation sharing (needs Google AI Plus)

**Gemini chat input (2026 UI — uses contenteditable, NOT textarea):**
```python
# Click "撰寫任何內容" button first to open chat mode
buttons = page.query_selector_all("button")
for btn in buttons:
    if "撰寫任何內容" in await btn.inner_text():
        await btn.click()
        break

# Type in the contenteditable div (class includes "ql-editor")
ce_div = page.locator("div.ql-editor")
await ce_div.click()
await page.keyboard.type("your prompt here")

# Send via button with SVG arrow icon
buttons = page.query_selector_all("button")
for btn in buttons:
    html = await btn.inner_html()
    if "svg" in html.lower() and await btn.is_visible():
        await btn.click()
        break
```

**Gemini conversation URL format:** `https://gemini.google.com/app/{conversation_id}`
- Note: Free tier share links don't work — shows "連結不存在"

## Common Image Download Issues

- **Twitter images**: URL `?format=png&name=medium` returns PNG binary but often saved as `.jpg`. Always verify with `PIL.Image.open(path).format` — if PIL reports `format='PNG'` but extension is `.jpg', FB/IG will reject it. Re-save with correct extension before uploading.
- **Format check**: `python3 -c "from PIL import Image; img=Image.open(f); print(img.format, img.mode)"`
