---
name: cdp-websocket-url-debug
category: browser-automation
description: Debug Playwright CDP WebSocket URL issues — page-level vs browser-level CDP connection
---

# CDP WebSocket URL Debug — Playwright CDP Connection

## 核心問題
用 Playwright 的 `connect_over_cdp()` 連接 CDP 時，**page-level URL (`/page/...`) 和 browser-level URL (`/browser/...`) 的行為完全不同**。

| URL 類型 | 來源 | 可用操作 |
|----------|------|---------|
| `/page/...` | `/json/list` 的 `webSocketDebuggerUrl` | 只能調用該 page 的 CDP，只能 `page.evaluate()`，不能 `new_page()` |
| `/browser/...` | `/json/version` 的 `webSocketDebuggerUrl` | 可以管理 browser contexts，可以 `new_page()` |

## 錯誤癥狀
```
playwright._impl._errors.Error: BrowserContext.new_page: Cannot read properties of undefined (reading '_page')
```
或
```
WebSocket error: ws://localhost:9333/devtools/browser/XXXXX 404 Not Found
```

第一個錯誤：用了 page-level URL 嘗試 `new_page()`
第二個錯誤：頁面已關閉，ID 無效

## 正確做法

### Step 1: 從 `/json/version` 取得 browser-level URL
```bash
curl -s "http://localhost:9333/json/version"
# 回傳: {"webSocketDebuggerUrl": "ws://localhost:9333/devtools/browser/72f92c07-5a67-48a0-9d5f-87d7644024c9"}
```

### Step 2: 連接到 browser-level URL
```python
import urllib.request, json
with urllib.request.urlopen("http://localhost:9333/json/version") as resp:
    data = json.loads(resp.read().decode())
browser_ws = data["webSocketDebuggerUrl"]

browser = await p.chromium.connect_over_cdp(browser_ws)
ctx = browser.contexts[0]

# 找現有的目標頁面
page = None
for pg in ctx.pages:
    try:
        if "facebook.com" in pg.url:
            page = pg
            break
    except:
        pass

# 沒有就新建
if not page:
    page = await ctx.new_page()
```

## 千萬不要這樣做
```python
# ❌ 錯：直接用 page-level URL new_page()
ws_url = page_data["webSocketDebuggerUrl"]  # /page/XXX
browser = await p.chromium.connect_over_cdp(ws_url)
ctx = browser.contexts[0]
page = await ctx.new_page()  # 崩：Cannot read properties of undefined

# ❌ 錯：直接替換 /page/ -> /browser/
# 不同頁面的 /page/ ID 對應到不同的 /browser/ ID，不能直接替換！
browser = await p.chromium.connect_over_cdp(ws_url.replace("/page/", "/browser/"))
```

## 其他 CDP Endpoint
- `/json/list` — 列出所有 page-level CDP URLs（用於探索，不用於連接）
- `/json/version` — 取得 browser-level WS URL（只用這個連接）
- `/json/protocol` — CDP protocol definition

## 驗證腳本
```python
import asyncio
from playwright.async_api import async_playwright
import urllib.request, json

async def verify_cdp():
    with urllib.request.urlopen("http://localhost:9333/json/version") as resp:
        data = json.loads(resp.read().decode())
    browser_ws = data["webSocketDebuggerUrl"]
    print(f"Browser WS: {browser_ws}")
    
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp(browser_ws)
        ctx = browser.contexts[0]
        pages = ctx.pages
        print(f"Pages: {len(pages)}")
        for pg in pages:
            print(f"  {pg.url[:80]}")
        await browser.close()
```
