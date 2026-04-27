---
name: cdp-existing-chromium-control
description: 用 Python CDP 直接控制已運行的 Chromium（port 9222），繞過 MCP/Playwright 崩潰問題。適用於已有登入狀態的瀏覽器應用。
tags: [cdp, chromium, python, browser-automation]
---

# Python CDP 直接控制已運行 Chromium

## 核心發現

當 MCP 的 Playwright (`mcp_personal_social`) 崩潰，且 aipuss-browser daemon 的 extension 未連接時，
**Python CDP + websocket 可以直接控制已運行的 Chromium**，保持其登入狀態不變。

## 關鍵環境參數

- Chromium 必須用 `--remote-debugging-port=9222` 啟動
- 瀏覽器 profile 位於 `/tmp/chromium-cdp-profile`
- 已運行且有登入狀態的 tab 不能重啟

## 連接方式

### 兩種 CDP URL 的選擇

```python
import urllib.request, json, websocket

HOST, PORT = "localhost", 9222

# 方式A：Page-level（控制現有頁面，推薦）
with urllib.request.urlopen(f"http://{HOST}:{PORT}/json") as r:
    pages = json.loads(r.read())
ws_url = pages[0]["webSocketDebuggerUrl"]

# 方式B：Browser-level（可以 new_page()，但響應不穩定）
with urllib.request.urlopen(f"http://{HOST}:{PORT}/json/version") as r:
    data = json.loads(r.read())
ws_url = data["webSocketDebuggerUrl"]
# ws_url = "ws://localhost:9222/devtools/browser/{uuid}"
```

| URL 類型 | from /json | from /json/version | 支持 new_page() | 穩定性 |
|---------|-----------|-------------------|----------------|--------|
| Page-level | ✅ | ❌ | ❌ | ✅ 推薦 |
| Browser-level | N/A | ✅ | ✅ | ⚠️ 有超時 |

## WebSocket CDP 包裝器

```python
import websocket, threading, time, random, json

results, lock = {}, threading.Lock()

def recv_loop(ws):
    while True:
        try:
            data = json.loads(ws.recv())
            if "id" in data and data["id"] in results:
                with lock: results[data["id"]] = data
        except: break

def cdp(ws, method, params=None, timeout=20):
    """同步 CDP 調用包裝器"""
    with lock: mid = random.randint(1000, 9999); results[mid] = None
    ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
    for _ in range(timeout * 10):
        time.sleep(0.1)
        with lock:
            if results[mid] is not None:
                return results.pop(mid)
    raise TimeoutError(f"{method} timed out")

# 使用
ws = websocket.create_connection(ws_url, timeout=10)
t = threading.Thread(target=recv_loop, args=(ws,)); t.daemon = True; t.start()
r = cdp(ws, "Page.navigate", {"url": "https://example.com"})
ws.close()  # 每次操作後關閉，下次重新連接
```

**重要：每個操作序列後關閉 WS，再需要時重新連接。**

## 頁面枚舉和選擇

```python
with urllib.request.urlopen(f"http://{HOST}:{PORT}/json") as r:
    pages = json.loads(r.read())

# 找到特定平台的已登入頁面
for p in pages:
    if "facebook.com" in p.get("url","") and "login" not in p.get("url","").lower():
        fb_page = p
        break

print(f"Open pages: {len(pages)}")
for p in pages:
    print(f"  [{p['id'][:20]}] {p.get('title','')[:30]} | {p.get('url','')[:45]}")
```

## 實用 CDP 命令

```python
# 導航
cdp(ws, "Page.navigate", {"url": "https://x.com/explore/tabs/trending"})
time.sleep(5)  # 等待載入

# 截圖
r = cdp(ws, "Page.captureScreenshot", {"format": "png"})
img_data = r["result"]["data"]
with open("/tmp/screenshot.png", "wb") as f:
    import base64; f.write(base64.b64decode(img_data))

# 執行 JS 並取返回值
r = cdp(ws, "Runtime.evaluate", {
    "expression": "document.body.innerText.substring(0, 1000)",
    "returnByValue": True
})
text = r["result"]["result"]["value"]

# 點擊坐標（當元素被遮擋時）
await page.mouse.click(x, y)
```

## Playwright async_api 連接方式

當 websocket CDP 不夠用時，可用 Playwright async_api 連接同一瀏覽器：

```python
import urllib.request, json, asyncio
from playwright.async_api import async_playwright

with urllib.request.urlopen("http://localhost:9222/json/version") as r:
    browser_ws = json.loads(r.read())["webSocketDebuggerUrl"]

async with async_playwright() as p:
    browser = await p.chromium.connect_over_cdp(browser_ws)
    ctx = browser.contexts[0]
    
    for pg in ctx.pages:
        if "facebook.com" in pg.url and "login" not in pg.url.lower():
            fb_page = pg
            break
    
    # 使用 Playwright 的強大選擇器
    composer = fb_page.locator('[aria-label="建立帖子"]')
    await composer.first.click(force=True)
```

## 關閉多餘頁面

避免打開過多頁面（目標 ≤6個）：

```python
# Browser-level WS 才能關閉頁面
with urllib.request.urlopen(f"http://{HOST}:{PORT}/json/version") as r:
    browser_ws = json.loads(r.read())["webSocketDebuggerUrl"]

ws = websocket.create_connection(browser_ws, timeout=10)
# ...
r = cdp(ws, "Target.closeTarget", {"targetId": target_id})
ws.close()
```

## 已知的攔截元素問題

Facebook 等 React UI 有時有遮擋層導致點擊失敗。解決方案：

```python
# 方案1：使用 force=True
await element.click(force=True)

# 方案2：找上層可點擊元素
await fb_page.locator('[aria-label="建立帖子"]').first.click(force=True)

# 方案3：使用坐標點擊
await page.mouse.click(x, y)
```

## 已知極限

1. **async_playwright 連接有時超時** — 50-60秒，需要優化等待邏輯
2. **Facebook React UI** — 點擊展開後 textbox 可能 not visible，需用坐標點擊
3. **不能共享 page-level CDP ws 連接** — 每個操作序列後重連
