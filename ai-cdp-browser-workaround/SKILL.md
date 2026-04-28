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

---

# CDP Mode 圖片上傳與 DOM 讀取（2025-04 實測）

## 1. Shadow DOM 讀取：用 inner_text() 而非 JS evaluate

 CDP mode 下 `document.querySelectorAll()` 無法穿透 shadow DOM（返回空陣列）。正確做法：

```python
# ❌ 錯誤：JS evaluate 讀不到 shadow DOM 內容
raw = await page.evaluate("""() => {
    return Array.from(document.querySelectorAll('a[href*="trending"]'))
        .map(el => el.innerText.trim());
}""")

# ✅ 正確：用 Playwright locator 的 inner_text() 讀取渲染後文字
body_text = await page.locator("body").inner_text()
lines = [l.strip() for l in body_text.split("\n") if l.strip()]
```

適用於：Google Trends（shadow DOM）、微博熱搜等動態內容。

## 2. CDP Mode 圖片上傳：JS DataTransfer 繞過 OS File Dialog

 CDP mode（`connect_over_cdp`）下 `page.context.wait_for_file_chooser()` 不存在（`BrowserContext` 沒有這個方法）。OS file dialog 不會出現，所以 `set_input_files` 無法觸發 React onChange。

### 正確流程：

```python
# 策略1：攔截 OS file_chooser（適用非 CDP 模式或 context-level 連接）
try:
    async with page.expect_file_chooser(timeout=3000) as fc_info:
        fc = await fc_info.value  # 注意：fc_info.value 是 coroutine，要 await
        await fc.set_files(image_path, timeout=20000)
except Exception:
    pass  # CDP mode 會 timeout

# 策略2（CDP mode）：JS DataTransfer 注入
import base64
with open(image_path, "rb") as f:
    b64 = base64.b64encode(f.read()).decode()

result = await page.evaluate("""(b64) => {
    try {
        const binaryString = atob(b64);
        const bytes = new Uint8Array(binaryString.length);
        for (let i = 0; i < binaryString.length; i++) {
            bytes[i] = binaryString.charCodeAt(i);
        }
        const blob = new Blob([bytes], { type: 'image/jpeg' });
        const file = new File([blob], 'upload.jpg', { type: 'image/jpeg', lastModified: Date.now() });

        const d = document.querySelector('[role="dialog"]');
        if (!d) return 'no_dialog';
        const inputs = d.querySelectorAll('input[type=file]');
        if (!inputs.length) return 'no_file_input';

        const inp = inputs[0];
        const dt = new DataTransfer();
        dt.items.add(file);
        Object.defineProperty(inp, 'files', {
            value: dt.files,
            writable: true,
            configurable: true
        });
        const tracker = inp._valueTracker;
        if (tracker) tracker.setValue('');
        inp.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
        inp.dispatchEvent(new Event('change', { bubbles: true, composed: true }));
        return { ok: true, files: dt.files.length };
    } catch(e) {
        return { error: e.message };
    }
}""", b64)

if not result.get("ok"):
    raise Exception(f"JS inject failed: {result}")
```

### 關鍵點：
- `page.expect_file_chooser()` 是 async context manager，要 `async with` + `await fc_info.value`
- `fc_info.value` 是 coroutine，**不能**直接 `fc_info.value.set_files(...)`，要先 `await fc_info.value` 拿到 FileChooser
- Instagram 圖片上傳後需等 3s 再點「下一步」（IG 處理圖片）
- CDP mode 每次 `connect_over_cdp` 都是獨立 session，同一時間只能有一個 CDP 連接活跃（否則 `Page.reload: Connection closed`）

## 3. Python 3.9 兼容性

```python
# ❌ 錯誤：asyncio.timeout 為 Python 3.11+才有
async with asyncio.timeout(45):
    ...

# ✅ 正確：
try:
    raw = await asyncio.wait_for(loop.run_in_executor(None, _fetch), timeout=45)
except asyncio.TimeoutError:
    ...
```

## 4. import 修補（從 ai-cdp 環境拷貝腳本後）

從 `social_mcp` 拷貝的腳本常有 `from social_mcp.browser_hijack import get_active_cdp_port`，需要替換為本地定義：

```python
from pathlib import Path

def _get_active_cdp_port() -> int:
    """讀取目前 active CDP port。"""
    try:
        with open(Path.home() / ".cdp_port", "r") as f:
            return int(f.read().strip())
    except Exception:
        return 9333
```

## 5. CDP 同時連接限制

CDP mode 對同一 browser 的 `connect_over_cdp` 有並發限制。同時從多個腳本/線程連接會導致 `Connection closed while reading from the driver`。

解決：使用獨立的 CDP port（如 9223）给需要穩定連接的腳本（Threads、FB 各用自己啟動的 Chromium），不要都擠在 9333。