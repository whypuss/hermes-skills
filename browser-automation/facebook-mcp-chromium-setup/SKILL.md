---
name: facebook-mcp-chromium-setup
description: Set up Chromium for Facebook MCP browser automation — separate from Google Chrome, CDP on port 9333, FacebookMCP profile
trigger: user wants Facebook MCP via browser automation (not Graph API)
---

# Facebook MCP Chromium Setup (macOS)

## Key Insight

Use **ungoogled-chromium** (not Google Chrome or Chrome for Testing) for Facebook browser automation:
- Installed via `brew install --cask ungoogled-chromium`
- Lives at `/Applications/Chromium.app` — completely separate from Google Chrome
- **No singleton lock conflicts** with regular Chrome
- Profile lives at `~/Library/Application Support/Chromium/FacebookMCP`

## Installation (already done)

```bash
brew install --cask ungoogled-chromium
# Binary: /Applications/Chromium.app
```

## Launch Chromium with CDP (port 9333)

```bash
"/Applications/Chromium.app/Contents/MacOS/Chromium" \
  --remote-debugging-port=9333 \
  --user-data-dir="$HOME/Library/Application Support/Chromium/FacebookMCP" \
  --no-first-run \
  --no-default-browser-check \
  --window-size=1280,720
```

## Connect via Playwright (Python)

```python
from playwright.async_api import async_playwright

async def fb_connect():
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp('http://localhost:9333')
        ctx = browser.contexts[0]
        page = await ctx.new_page()
        await page.goto('https://www.facebook.com', ...)
        return ctx, page
```

## Launchd Agent (optional — auto-start on boot)

See `~/Library/LaunchAgents/` for plist. Agent should:
1. Launch Chromium with above flags
2. Keep it running headless-visible
3. Hermes connects via CDP port 9333

## Two Facebook MCP Approaches

| | just_facebook_mcp (Graph API) | Browser Automation (Playwright) |
|---|---|---|
| Auth | Facebook Developer + Page + Access Token | Just log in once in browser |
| Scope | Only Page posts/comments | Any account action (personal or Page) |
| Setup | Developer account, app review, token | Just open Chromium, log in |
| Stability | API-based, stable | Cookie-based, session may expire |
| Rate limits | Graph API limits | Browser slower, can trigger anti-bot |

## Profile Directory

- Active CDP profile: `/tmp/chromium-fb` (temporary)
- Backup/持久: `~/Library/Application Support/Chromium/FacebookMCP`

## Troubleshooting

- **Chromium won't start**: Check for lock files in profile dir, remove `.lock` files
- **Login form shows**: Facebook may require re-login; open Chromium manually and log in
- **CDP connects but page blank**: Wait for `networkidle` event, add `await asyncio.sleep(3)` after goto
- **Singleton lock**: With Chromium (not Chrome), this is NOT an issue since it's a different binary
