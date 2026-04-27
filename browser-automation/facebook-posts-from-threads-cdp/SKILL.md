---
name: facebook-posts-from-threads-cdp
description: Cross-post Threads content to Facebook via CDP Browser Hijack — persistent tabs, Playwright typing, multi-step composer flow
triggers:
  - facebook post from threads
  - cdp browser hijack facebook
  - threads to facebook automation
---

# Facebook Posts from Threads Content via CDP Browser Hijack

## Context
Automate Facebook posting (text + image from Threads trending posts) using persistent browser tabs, without opening/closing new pages.

## Key Findings

- Threads actual URL: `threads.com` (not `threads.net`)
- Facebook composer: multi-step flow — `在想什麼？` button → dialog → image → text → `下一頁` button → `發佈` button
- With image attached, the "下一頁" step may be skipped — publish button appears directly
- Playwright `.type()` reliable for `contenteditable`; CDP `innerText` assignment corrupts non-ASCII chars
- Keep exactly 3 persistent tabs (FB, IG, Threads); navigate between them directly, never open/close temp pages

## Prerequisites
- Browser running at CDP port 9333 (aipuss-browser or Chromium with remote debugging)
- 3 tabs open: `https://www.facebook.com/`, `https://www.instagram.com/`, `https://www.threads.com/@whypuss_fun`
- Video frame screenshot at `/tmp/trending_frame.jpg`

## Workflow

### Step 1: Get Video Frame from Threads (reuse Threads tab)
```python
threads_pg = next((pg for pg in ctx.pages if 'threads.' in pg.url and '/post/' in pg.url), None)
await threads_pg.bring_to_front()
await threads_pg.goto('https://www.threads.net/@trending/post/THREAD_ID', timeout=15000)
await asyncio.sleep(3)
vid = threads_pg.locator('video').first
await vid.wait_for(timeout=3000)
await vid.screenshot(path='/tmp/trending_frame.jpg')
```

### Step 2: Publish to Facebook (reuse FB tab)
```python
fb_pg = next((pg for pg in ctx.pages if 'facebook.com' in pg.url), None)
await fb_pg.bring_to_front()
await fb_pg.reload()
await asyncio.sleep(3)

# Get CDP WS for FB tab
with httpx.Client() as client:
    tabs = client.get('http://localhost:9333/json', timeout=10).json()
fb_ws_url = next(t['webSocketDebuggerUrl'] for t in tabs
                 if t.get('type')=='page' and 'facebook.com' in t.get('url',''))

async with websockets.connect(fb_ws_url, max_size=20*1024*1024) as ws:
    _id = [0]

    # Helper: click by CDP coordinates
    async def cdp_click(ws, x, y, _id):
        _id[0] += 1
        for ev in ('mousePressed', 'mouseReleased'):
            await ws.send(json.dumps({'id': _id[0], 'method': 'Input.dispatchMouseEvent',
                'params': {'type': ev, 'x': x, 'y': y, 'button': 'left', 'clickCount': 1}}))
            json.loads(await ws.recv())

    # 2a. Click composer button (role="button", text="Whyme Ym，你在想什麼？")
    # 2b. Set image via Playwright (handles hidden input[type=file])
    # 2c. Type via Playwright (NOT CDP innerText — corrupts non-ASCII)
    # 2d. Click "下一頁" if present, then "發佈"
```

### Step 3: Verify
```python
body = await fb_pg.inner_text('body')
posted = 'Netflix' in body or 'Chill' in body
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| "在想什麼？" not found | Page not loaded fully — add `sleep(3)` |
| No image input found | Use `dialog.locator('input[type="file"]').first` — may be hidden |
| Publish button not found | With image, step changes — try `下一頁` first, then fallback to coordinates `(760, 637)` |
| Typed text empty/corrupted | Always use Playwright `.type()` on `contenteditable`, never CDP innerText |
| Tab lost after navigation | Use `next(pg for pg in ctx.pages if 'threads.' in pg.url)` — URLs change on nav |

## Pitfalls
- Never `new_page()` for one-off tasks — just navigate existing persistent tabs
- CDP WebSocket sessions conflict if multiple Python processes connect simultaneously
- Facebook `role=dialog` count may include hidden overlays — check actual text content
