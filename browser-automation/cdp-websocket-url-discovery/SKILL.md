---
name: cdp-websocket-url-discovery
description: Chrome DevTools Protocol WebSocket URL discovery — browser vs page level, new_page() fix
category: browser-automation
---

# CDP WebSocket URL Discovery — Browser vs Page Level

## Problem
When using Playwright `connect_over_cdp()` to attach to an existing Chrome/Chromium instance via Chrome DevTools Protocol (CDP), scripts fail with:
- `Cannot read properties of undefined (reading '_page')` when using page-level URL with `new_page()`
- `WebSocket error: ... 404 Not Found` when directly replacing `/page/` with `/browser/` in URLs

## Root Cause
CDP exposes TWO types of WebSocket URLs that are NOT interchangeable:

| Endpoint | URL Pattern | Example | Capabilities |
|----------|-------------|---------|--------------|
| `/json/list` | `/page/{id}` | `ws://host/devtools/page/ABCD...` | Attach to existing page only. `new_page()` fails. |
| `/json/version` | `/browser/{id}` | `ws://host/devtools/browser/ABCD...` | Full browser context. Can call `new_page()` and access all existing pages. |

The IDs are DIFFERENT — you cannot just string-replace `/page/` → `/browser/`.

## Solution
Always get the browser-level URL from `/json/version`:

```python
import urllib.request, json

def get_browser_ws_url(port=9333):
    """Get browser-level CDP WebSocket URL (works with new_page())."""
    with urllib.request.urlopen(f"http://localhost:{port}/json/version", timeout=5) as resp:
        data = json.loads(resp.read().decode())
    return data["webSocketDebuggerUrl"]  # e.g. ws://host/devtools/browser/72f92c07-...

# Usage with Playwright:
browser_ws = get_browser_ws_url(9333)
browser = await p.chromium.connect_over_cdp(browser_ws)
ctx = browser.contexts[0]  # Full context with all pages
pages = ctx.pages         # Access existing pages
# page = await ctx.new_page()  # Now this works
```

## Finding Existing Pages
After connecting with browser-level URL, iterate `ctx.pages` to find by URL:

```python
fb = None
threads = None
for pg in ctx.pages:
    try:
        url = pg.url
        if "facebook.com" in url:
            fb = pg
        elif "threads.net" in url or "threads.com" in url:
            threads = pg
    except:
        pass
```

## Pitfalls
- Do NOT use `/json/list` page URLs with `new_page()` — they only work for attaching to existing pages
- Do NOT string-replace `/page/` → `/browser/` — the IDs are different
- Always use `/json/version` for the browser-level URL
- AIpuss-browser uses port 9333 by default
