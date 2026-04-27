---
name: aipuss-browser-cdp-attach
description: 連接到 AIpuss-browser 運行中的 Chrome for Testing，繞過 CDP pipe mode 限制
category: browser-automation
---

# AIpuss-browser CDP Attach — 連接到運行中的 Chrome for Testing

## 觸發條件

需要對 AIpuss-browser 的 Chrome 進行 CDP 操控（讀取 cookies、執行 JS、截圖等），但**不需要** kill 掉現有的 Chrome session。

## 核心發現

- AIpuss-browser 的 Chrome 用 `--remote-debugging-port=0`（動態端口），**不是 pipe mode**
- Chrome 進程在 localhost 監聽一個真實 TCP 端口（可用 `lsof -p <pid> | grep TCP.*LISTEN` 找到）
- WebSocket Debugger URL 從 `http://localhost:<PORT>/json/version` 的 `webSocketDebuggerUrl` 欄位取得
- Playwright 可用 `connect_over_cdp(ws_url)` 直接連接，繞過 `--user-data-dir` 被佔用的問題

## 步驟

### 1. 找到 Chrome for Testing 的 CDP port

```bash
# 找 Chrome for Testing 主進程 PID（不是 Helper）
ps aux | grep "Google Chrome for Testing.app" | grep -v "Helper\|grep\|--type=" | awk '{print $2}'

# 例如得到 81359，然後找監聽端口
lsof -p 81359 2>/dev/null | grep -E "TCP.*LISTEN"
# 輸出例如：Google 81359 whypuss 54u IPv4 ... TCP localhost:52704 (LISTEN)
```

### 2. 取得 WebSocket URL

```bash
curl -s http://localhost:52704/json/version
# 回傳 {"webSocketDebuggerUrl": "ws://localhost:52704/devtools/browser/..."}
```

### 3. Playwright CDP 連線

```python
import asyncio
from playwright.async_api import async_playwright

async def attach_to_chrome():
    WS_URL = "ws://localhost:52704/devtools/browser/62c27288-..."  # 從步驟2取得

    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp(WS_URL)
        ctx = browser.contexts[0]

        # 開新分頁操作
        page = await ctx.new_page()
        await page.goto("https://www.messenger.com", ...)
        # ...你的操作...

        await page.close()
```

## 已知限制

| 問題 | 說明 |
|------|------|
| Cookies 不在 ~/Library | AIpuss Chrome 用 temp profile（`/var/folders/...`），沒有 Facebook cookies |
| ~/Library Profile 3 也沒 FB cookies | 用戶的 Facebook 登入不在標準 Chrome |
| macOS Keychain 鎖住 | Chrome cookies SQLite 加密，無法自動解密 |
| AIpuss session 斷不掉 | 若需要綁定固定 port 的 Chrome，AIpuss 需要重啟 |

## Profile 衝突問題（Chrome for Testing vs 普通 Chrome）

Chrome for Testing 和普通 Chrome 共享同一個 `~/Library/Application Support/Google/Chrome` 時，會搶 `SingletonLock`，導致雙方都無法啟動。

**徵兆：** Chrome 無法打開，提示 "It is already running, but is not responding"

**解決方法：**
```bash
# 1. Kill Chrome for Testing
pkill -f "Chrome for Testing"

# 2. 刪除 stale locks（Chrome 崩掉後 lock 還在）
rm -f ~/Library/Application\ Support/Google/Chrome/SingletonLock
rm -f ~/Library/Application\ Support/Google/Chrome/SingletonCookie
rm -f ~/Library/Application\ Support/Google/Chrome/SingletonSocket

# 3. 才能重啟普通 Chrome
open -a "Google Chrome"
```

## FacebookMCP Chromium — 另一個 CDP 目標

除了 AIpuss-browser 的 Chrome for Testing，還有**另一個重要的 CDP 實例**：

**FacebookMCP Chromium** 運行在端口 9333，profile 目錄：
```
~/Library/Application Support/Chromium/FacebookMCP
```

**這個 Chromium 實例已經有：**
- Facebook 登入（Whyme Ym 身份）
- Threads 登入
- 其他 Meta 相關 session

**如何找到並連接：**

```bash
# 方法1：直接查 port 9333（FacebookMCP 固定端口）
curl -s http://localhost:9333/json/version | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['webSocketDebuggerUrl'])"

# 方法2：找 Chromium 程序
ps aux | grep "Chromium.app" | grep -v "grep"

# 方法3：找所有 Chrome/Chromium 的 LISTEN 端口
lsof -i :9333 2>/dev/null | grep LISTEN
```

**連接並操作（Python）：**

```python
import asyncio
from playwright.async_api import async_playwright

WS_URL = "ws://localhost:9333/devtools/browser/..."  # 從上面取得

async def use_facebook_mcp_chromium():
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp(WS_URL)
        ctx = browser.contexts[0]
        
        pages = ctx.pages
        print(f"Pages: {[pg.url for pg in pages]}")
        
        # 操作已有的 Facebook 或 Threads 頁面
        for pg in pages:
            if "facebook.com" in pg.url:
                await pg.bring_to_front()
                # ... 操作 ...
```

**實測可用操作（2026-04-25）：**
- Threads 瀏覽熱門內容（日文/中文）
- Facebook 發帖（使用 Composer + Cmd+Enter）
- 跨平台轉發內容

**限制：**
- 這是 Facebook MCP 的專用瀏覽器，不要關閉它
- 如果 Chromium 崩掉重啟，CDP port 可能改變

---

## ⚠️ /page/ vs /browser/ URL 重要區別

`/json/list` 返回 page-level URLs (`/page/...`) — 只能用於附接現有分頁，`new_page()` 會失敗。  
`/json/version` 返回 browser-level URL (`/browser/...`) — 可用 `new_page()` 和訪問所有分頁。

詳見 skill `cdp-websocket-url-discovery`。

## Facebook MCP 的 Cookies 需求

Facebook 登入的關鍵 cookie 是 **`c_user`**，沒有它就等於沒登入。

**檢查方法（Python）：**
```python
import sqlite3, os
cookie_db = os.path.expanduser('~/Library/Application Support/Google/Chrome/Profile 2/Cookies')
conn = sqlite3.connect(cookie_db)
c = conn.cursor()
c.execute("SELECT name FROM cookies WHERE name='c_user'")
print("c_user found!" if c.fetchone() else "NOT LOGGED IN")
conn.close()
```

**Facebook MCP 隔離 profile 方案：**

1. **千萬不要**讓 Chrome for Testing 和普通 Chrome 共用同一個 profile
2. 替 MCP 建一個專屬隔離目錄：
   ```bash
   mkdir -p ~/chrome-mcp-profile
   ```
3. 啟動時指定這個隔離目錄：
   ```bash
   "/path/to/Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing" \
     --remote-debugging-port=0 \
     --user-data-dir="$HOME/chrome-mcp-profile" \
     --profile-directory="Default" \
     ...
   ```
4. 用戶在普通 Chrome 的某個閒置 profile（如 Profile 3）登入 Facebook
5. 手工複製該 profile 的 Cookies + Login Data 到隔離目錄（需要 macOS Keychain 密碼解密 encrypted_value）

## 驗證步驟

```python
# 確認連線成功
browser = await p.chromium.connect_over_cdp(WS_URL)
assert len(browser.contexts) >= 1
print(f"Connected! {len(browser.contexts)} contexts, {len(browser.contexts[0].pages)} pages")

# 確認 Facebook session
cookies = await ctx.cookies(['https://www.facebook.com'])
has_c_user = any(c['name'] == 'c_user' for c in cookies)
print("FB Logged in!" if has_c_user else "FB NOT logged in")
```

## 參考代碼

見 `~/.kimaki/projects/social-mcp/scripts/test_playwright_cdp.py`
