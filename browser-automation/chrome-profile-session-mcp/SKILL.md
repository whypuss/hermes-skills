---
name: chrome-profile-session-mcp
description: 設定獨立的 Chrome for Testing profile 給 MCP 使用，避免與普通 Chrome 的 SingletonLock 衝突，並正確接管 Facebook 等需要登入的網站 session。
trigger: 你需要讓 MCP（如 Playwright CDP）控制一個需要登入的網站（Facebook、Instagram、LinkedIn 等），但無法直接讀取普通 Chrome 的加密 cookies。
platform: macOS
---

# Chrome for Testing 專屬 Profile + MCP Session 接管

## 核心發現（實驗得來）

1. **普通 Chrome 和 Chrome for Testing 共享同一個 `~/Library/Application Support/Google/Chrome/`** → 兩者搶 SingletonLock，只能選一個運行
2. **Facebook session cookie 是 `c_user`**（+ `xs` + `datr`）→ 沒有 `c_user` 就不是真正登入，Facebook 會顯示公開內容假裝已登入
3. **macOS Chrome cookies 有加密層（Keychain）** → 無法直接把一個 profile 的 cookies 複製到另一個目錄
4. **正確流程：建立乾淨的專屬目錄 → Chrome for Testing 獨家使用 → 用戶登入一次 → CDP 接管**

## 步驟

### 1. 創建乾淨的隔離目錄

```bash
rm -rf /tmp/chrome-fb-mcp
mkdir -p /tmp/chrome-fb-mcp
```

### 2. 啟動 Chrome for Testing（獨家使用該目錄）

```bash
"/Users/whypuss/.agent-browser/browsers/chrome-147.0.7727.56/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing" \
  --remote-debugging-port=0 \
  --user-data-dir=/tmp/chrome-fb-mcp \
  --profile-directory="Default" \
  --no-first-run \
  --no-default-browser-check \
  --headless=new \
  --enable-unsafe-swiftshader \
  --window-size=1280,720 \
  >> /tmp/cft-fb.log 2>&1 &
echo "PID: $!"
sleep 8
```

### 3. 取得 CDP 端口

```bash
PORT=$(lsof -i -P | grep "Chrome for Testing" | grep LISTEN | awk -F: '{print $2}' | head -1)
echo "CDP port: $PORT"
# 或從日誌：cat /tmp/cft-fb.log | grep "DevTools listening"
```

### 4. 用戶登入

用戶需要：
1. 打開 Finder，進入 `~/.agent-browser/browsers/chrome-147.0.7727.56/`
2. 雙擊 `Google Chrome for Testing.app`（不是普通 Chrome）
3. 在地址欄輸入目標網站（如 `facebook.com`），登入
4. **保持該窗口開著**，不要關閉

### 5. CDP 接管測試

```python
import asyncio
from playwright.async_api import async_playwright

async def test():
    ws_url = 'ws://127.0.0.1:<PORT>/devtools/browser/<ID>'
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp(ws_url)
        ctx = browser.contexts[0]
        page = await ctx.new_page()
        await page.goto('https://www.facebook.com', wait_until='networkidle', timeout=30000)
        await asyncio.sleep(5)
        
        cookies = await ctx.cookies(['https://www.facebook.com'])
        has_c_user = any(c['name'] == 'c_user' for c in cookies)
        print(f'c_user cookie: {has_c_user}')
        
        body = await page.inner_text('body')
        if 'c_user' in cookies or 'xs' in cookies:
            print('✅ LOGGED IN')
        else:
            print('❌ NOT LOGGED IN')
        
        await page.close()

asyncio.run(test())
```

### 6. 以後重啟 Chrome for Testing

只要 `/tmp/chrome-fb-mcp` 目錄還在，session 就還在（除非用戶主動登出）。每次重啟時：

```bash
pkill -f "Chrome for Testing" 2>/dev/null
sleep 2

"/Users/whypuss/.agent-browser/browsers/chrome-147.0.7727.56/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing" \
  --remote-debugging-port=0 \
  --user-data-dir=/tmp/chrome-fb-mcp \
  --profile-directory="Default" \
  --no-first-run \
  --no-default-browser-check \
  --headless=new \
  --enable-unsafe-swiftshader \
  --window-size=1280,720 \
  >> /tmp/cft-fb.log 2>&1 &
```

## 驗證方法

檢查 `c_user` cookie 是否存在：
```bash
python3 -c "
import sqlite3
conn = sqlite3.connect('/tmp/chrome-fb-mcp/Default/Cookies')
c = conn.cursor()
c.execute(\"SELECT name, host_key FROM cookies WHERE name='c_user'\")
print(conn.execute(\"SELECT name, host_key FROM cookies WHERE name='c_user'\").fetchall())
conn.close()
"
```

## 已知限制

- **千萬不要** kill 掉 Chrome for Testing 後又重啟覆蓋同一個目錄（cookies 來不及寫入磁盤就會丟失）
- 如果用戶在 Chrome for Testing 登入後立馬重啟，session 會消失
- Facebook 可能要求滑塊驗證（第一次登入時）
