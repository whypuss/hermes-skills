---
name: chromium-direct-cdp-automation
description: 直接用 --remote-debugging-port 啟動 Chromium，通過原生 CDP WebSocket 控制瀏覽器。繞過 aipuss-browser/autocli 的 Chrome Extension 依賴。
metadata:
  author: hermes
  version: "1.0.0"
  created: 2026-04-25
---

# Chromium Direct CDP Automation

## 核心發現

aipuss-browser/autocli 需要 Chrome Extension 才能控制瀏覽器。但 Chromium（開源版本）支持 `--remote-debugging-port`，直接暴露 CDP WebSocket，不需要任何 extension。

## 啟動 Chromium

```bash
# Kill existing Chromium processes
pkill -f "Chromium" 2>/dev/null; sleep 2

# Launch with CDP debug port
"/Applications/Chromium.app/Contents/MacOS/Chromium" \
  --remote-debugging-port=9222 \
  --user-data-dir=/tmp/chromium-test-profile \
  --no-first-run \
  --no-default-browser-check \
  --remote-allow-origins=* \
  --headless=new \
  2>/dev/null &
sleep 5
```

**必須參數：**
- `--remote-debugging-port=9222` — 暴露 CDP
- `--remote-allow-origins=*` — 允許 WebSocket 跨 origin 連接（否則 403 Forbidden）

## Python CDP 客戶端

```python
import urllib.request, json, websocket, threading, time, random

HOST, PORT = "localhost", 9222

def cdp_send_recv(ws, method, params=None, timeout=20):
    """Send CDP command, return response dict."""
    results, lock = {}, threading.Lock()
    def recv_loop(ws):
        while True:
            try:
                msg = ws.recv()
                data = json.loads(msg)
                if "id" in data and data["id"] in results:
                    with lock: results[data["id"]] = data
            except: break
    t = threading.Thread(target=recv_loop, args=(ws,)); t.daemon = True; t.start()
    with lock: mid = random.randint(1000, 9999); results[mid] = None
    ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
    for _ in range(timeout * 10):
        time.sleep(0.1)
        with lock:
            if results[mid] is not None:
                return results.pop(mid)
    raise TimeoutError(f"{method} timed out")

# Step 1: Get WebSocket URL
with urllib.request.urlopen(f"http://{HOST}:{PORT}/json", timeout=10) as r:
    pages = json.loads(r.read())
ws_url = pages[0]["webSocketDebuggerUrl"]

# Step 2: Connect
ws = websocket.create_connection(ws_url, timeout=10)

# Step 3: Navigate
cdp_send_recv(ws, "Page.navigate", {"url": "https://twitter.com"}, timeout=30)
time.sleep(3)

# Step 4: Evaluate JS
r = cdp_send_recv(ws, "Runtime.evaluate", {"expression": "document.title"})
print(r["result"]["result"]["value"])

ws.close()
```

## 依賴

```bash
pip3 install websocket-client
```

## 已知限制

- Twitter 顯示登入牆，但頁面內容可以抓取
- 任何需要登入的網站都無法通過這種方式自動化（CDP 只能控制瀏覽器，無法填表單+認證）
- 如果需要登入後操作，必須先手動登入一次並保存 Chromium profile（`--user-data-dir` 持久化 session）

## 重要教訓：導航後必須重建 WebSocket

`Page.navigate` 後 WebSocket 會斷開。**不要在導航後繼續使用同一個 WS 連接**，必須重新獲取 WS URL：

```python
# ❌ 錯誤：導航後繼續用舊連接
cdp(ws, "Page.navigate", {"url": "https://x.com/explore/tabs/trending"})
time.sleep(5)
r = cdp(ws, "Runtime.evaluate", ...)  # 連接已失效

# ✅ 正確：導航後重建連接
cdp(ws, "Page.navigate", {"url": "https://x.com/explore/tabs/trending"})
time.sleep(5)
ws.close()                          # 關閉舊連接
ws = get_fresh_ws()                 # 重新獲取 WS URL
t = threading.Thread(target=recv_loop, args=(ws,)); t.daemon = True; t.start()
r = cdp(ws, "Runtime.evaluate", ...)
```

## 平台可用性實測

| 平台 | Trending 可抓 | 圖片可抓 | 備註 |
|------|------|------|------|
| Twitter/X | ✅ | ✅ | 需要登入（用持久化 profile） |
| Reddit | ❌ | ❌ | "Prove your humanity" CAPTCHA 無法繞過 |
| Gemini | ❌ | ❌ | 是聊天機器人，無 trending 頁面 |
| V2EX | ✅ | N/A | opencli 可用 |

## Facebook 發文自動化（失敗記錄）

Facebook UI 是 React 動態渲染，通過 CDP `Runtime.evaluate` 執行 JS 查詢 DOM 的方式**不可靠**：
- `[role="button"]` 等無障礙屬性在 React 下查不到
- Accessibility tree 深度大，熱門元素不在前 500 nodes

**需要嘗試的其他方法：**
- `Input.dispatchMouseEvent` + `Mouse.click` 的絕對坐標點擊（需截圖校準）
- CDP Dialog 捕獲（Facebook 有些操作在 dialog 內）
- 直接調 Facebook Graph API（需 access token）

## autocli daemon extension 問題

autocli daemon 狀態：
```
{"daemon": true, "extension": false, "extensionConnected": false}
```
需要用 `--extension` flag 啟動 daemon 才能啟用 extension bridge。Extension 本身路徑：`/tmp/autocli-extension`

## 維護日誌

- 2026-04-25: 創建。發現 Chromium 開源版本直接支持 CDP，繞過了整個 aipuss-browser/autocli 生態。
- 2026-04-25: 新增：導航後必須重建 WebSocket 的發現。
- 2026-04-25: 新增：平台實測結果（Twitter ✅ / Reddit ❌ / Gemini ❌）。
- 2026-04-25: 新增：Facebook 發文自動化失敗記錄。