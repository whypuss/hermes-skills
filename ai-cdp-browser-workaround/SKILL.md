---
name: ai-cdp-browser-workaround
description: 當 Chromium CDP port 9333 過載（過多 tab）導致 Playwright connect_over_cdp timeout 時的處理方法
category: social-automation
---

# ai-cdp-browser Playwright CDP 連線問題處理

## 問題徵狀

```
playwright._impl._errors.TimeoutError: BrowserType.connect_over_cdp: Timeout 20000ms exceeded.
Call log:
  - <ws preparing> retrieving websocket url from http://localhost:9333
  - <ws connecting> ws://localhost:9333/devtools/browser/xxx
  - <ws connected> ws://localhost:9333/devtools/browser/xxx
```

WebSocket 連線成功，但 Playwright Node driver 內部初始化 hang 住。

## 常見原因

1. Chromium 9333 上累積太多 tab（正常 21 個就是警訊，web workers 也算 tab）
2. Chrome 146 + Playwright 1.50 在 browser-level WS endpoint 有已知兼容問題

## 解決方案（新 Chromium + 新 Port）

當 9333 過載時，啟動一個乾淨的 headless Chromium 在不同 port：

```bash
nohup /Applications/Chromium.app/Contents/MacOS/Chromium \
  --headless \
  --remote-debugging-port=9223 \
  --user-data-dir=/tmp/chromium-cdp-9223 \
  2>/dev/null &
echo "PID: $!"
sleep 3
curl -s --max-time 5 "http://localhost:9223/json"
```

然後修改 `social_workflow.py` 中的 `_get_cdp_browser()` default port：

```python
# 舊
def _get_cdp_browser(port=9333):
# 新
def _get_cdp_browser(port=9223):
```

## 重要規則

- **禁止** kill Chromium 程序（9333 上可能有多個 session）
- 保持打開的瀏覽器頁面 ≤ 6 個（可用 `browser.pages` 關閉多餘的）
- 修復後建議還原 port 改回 9333（下次 cron 仍用 9333，如果已被其他程序穩定使用）

## 驗證

```bash
# 確認只有 1 個 tab
curl -s "http://localhost:9223/json" | python3 -c "import sys,json; data=json.load(sys.stdin); print(f'Tabs: {len(data)}')"
```

## 預防

定期重啟 9333 上的 Chromium 以避免 tab 累積（但不能 kill 正在使用的浏覽器）。