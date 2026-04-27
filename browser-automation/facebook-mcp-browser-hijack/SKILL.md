---
name: facebook-mcp-browser-hijack
description: 用 Playwright launch_persistent_context + FastMCP 實現個人 Facebook 帳號的 MCP 工具（免開發者審批、免 Graph API）
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [facebook, mcp, playwright, browser-automation]
    related_skills: [native-mcp, chrome-profile-session-mcp]
---

# Facebook MCP — Browser Hijack 方案

用 Playwright `launch_persistent_context` + FastMCP 直接操作個人 Facebook 帳號，**不需要 Facebook 開發者帳號、不需要 Graph API token**。

## 核心邏輯

- 啟動獨立的 Chromium profile（`~/Library/Application Support/Chromium/FacebookMCP`），與系統 Chrome 完全隔離
- 用 `headless=True` 讓 AI 讀取畫面文字，用 `headless=False` 讓用戶登入
- session 永久保存，只在首次需要手動操作瀏覽器

## 部署流程

### 1. 安裝依賴

```bash
brew install --cask ungoogled-chromium
# 已在 ~/.kimaki/projects/social-mcp/ 安裝了 uv 環境和 mcp/playwright
```

### 2. MCP Server 程式碼

位置：`/Users/whypuss/mcp-servers/social_mcp.py`

```python
import asyncio
import os
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("Personal_Social")
SESSION_DIR = os.path.expanduser("~/Library/Application Support/Chromium/FacebookMCP")

@mcp.tool()
async def open_login_window():
    """Launch visible browser for manual login. Run once only."""
    async with async_playwright() as p:
        browser = await p.chromium.launch_persistent_context(
            SESSION_DIR, headless=False,
            viewport={"width": 1280, "height": 800}
        )
        page = await browser.new_page()
        await page.goto("https://www.facebook.com")
        await browser.wait_for_close()
        return "Browser closed. Session saved."

@mcp.tool()
async def read_messenger():
    """Fetch Messenger conversations as markdown table."""
    ...

@mcp.tool()
async def read_notifications():
    """Fetch Facebook notifications as markdown table."""
    ...

if __name__ == "__main__":
    mcp.run()
```

### 3. Hermes config 設定

在 `~/.hermes/config.yaml` 頂部加入：

```yaml
mcp_servers:
  personal-social:
    command: "uv"
    args: ["run", "--active", "python", "/Users/whypuss/mcp-servers/social_mcp.py"]
```

### 4. 重啟 Hermes Agent

之後以下工具自動可用：
- `mcp_personal-social_open_login_window` — 首次登入用
- `mcp_personal-social_read_messenger` — 讀私訊
- `mcp_personal-social_read_notifications` — 讀通知

## Facebook 圖文發文流程

### 找到 Composer

Facebook 動態牆上的「在想什麼」composer 有多層 overlay 擋住普通點擊。有效方式：

```python
# 方法 1：text locator（最穩定）
composer = fb_page.locator('text=在想').first
await composer.click(timeout=5000, force=True)

# 方法 2：CDP DOM click（備用）
r = await sr('Runtime.evaluate', {
    'expression': '''
        (() => {
            const el = document.querySelector(\'[aria-label*="在想"]\');
            if (el) { el.click(); return \'clicked\'; }
            return \'not found\';
        })()
    '''
})
```

### 上傳圖片

**關鍵發現**：`input[type="file"]` 在 dialog 內是隱藏的（`w=0, h=0`），但 `set_input_files()` 直接設定它有效，不需要點擊任何「相片」按鈕。

```python
# Dialog 已經打開狀態下，直接設定圖片
dialog = fb_page.locator('[role="dialog"]').filter(has_text='在想')
file_input = dialog.locator('input[type="file"]').first
count = await file_input.count()
# count == 1 表示 dialog 已打開
await file_input.set_input_files('/path/to/image.jpg')
await asyncio.sleep(2)  # 等待預覽出現

# 驗證：dialog 內出現多個 preview img
preview_count = await fb_page.evaluate(
    'document.querySelectorAll(\'[role="dialog"] img[src*="fbcdn"], '
    '[role="dialog"] img[src*="scontent"]\').length'
)
print(f'Preview images: {preview_count}')  # > 0 = 成功
```

### 輸入文字（FB 不需要 CDP，用 Playwright 原生）

```python
# 點擊 contenteditable 進入編輯模式
editable = dialog.locator('[contenteditable="true"]').first
await editable.click(timeout=5000)
await editable.type('你的訊息內容', delay=30)
```

### 點擊發布按鈕

**重要發現**：Facebook 的按鈕**全部是 `DIV` + `role=button`**，不是傳統 HTML `button` 或 `input`。

**按鈕識別方式**：用 `aria-label` 而非文字內容：

| 按鈕 | 元素 | role | aria | 中心座標 |
|------|------|------|------|----------|
| Facebook 選單 | H2 | — | — | 右側面板 |
| 帖子 | H2 | — | — | 右側面板 |
| 發佈 | DIV | button | 發佈 | (840, 646) |
| 下一頁 | DIV | button | 下一頁 | (220, 732) |
| 照片/影片 | DIV | button | 相片／影片 | (225, 669) |
| 打開（文件選擇器）| — | — | 打開 | dialog 內 |
| 關閉 dialog | DIV | button | 關閉撰寫工具對話框 | (436, 96) |

**CDP JS click（推薦）**：
```python
r = await sr('Runtime.evaluate', {
    'expression': '''
        (() => {
            var btns = document.querySelectorAll('[role="button"]');
            for (var b of btns) {
                if (b.getAttribute("aria-label") === "發佈") {
                    b.click(); return "ok";
                }
            }
            return "not_found";
        })()
    '''
})
```

**CDP dispatchMouseEvent（座標備用）**：
```python
for ev in ('mousePressed', 'mouseReleased'):
    await sr("Input.dispatchMouseEvent", {
        "type": ev, "x": 840, "y": 646,
        "button": "left", "clickCount": 1
    })
```
```python
r = await sr('Runtime.evaluate', {
    'expression': '''
        (() => {
            const dialogs = document.querySelectorAll(\'[role="dialog"]\');
            for (const d of dialogs) {
                if (!d.innerText?.includes("在想")) continue;
                const btns = d.querySelectorAll(\'div[role="button"], span[role="button"], button\');
                for (const b of btns) {
                    const t = b.innerText?.trim();
                    if (t === "發布" || t === "發佈") {
                        const r = b.getBoundingClientRect();
                        return {x: Math.round(r.left+r.width/2), y: Math.round(r.top+r.height/2), text: t};
                    }
                }
            }
            return null;
        })()
    '''
})
btn = r["result"]["result"]["value"]
if btn:
    for ev in ('mousePressed', 'mouseReleased'):
        await sr("Input.dispatchMouseEvent", {
            "type": ev, "x": btn["x"], "y": btn["y"],
            "button": "left", "clickCount": 1
        })
    await asyncio.sleep(4)
```

**解法 B**：Playwright `force=True`（有時成功）：
```python
publish_btn = dialog.locator('[role="button"]', has_text='發布').first
await publish_btn.click(timeout=5000, force=True)
```

### 驗證發文

```python
await fb_page.reload()
await asyncio.sleep(3)
body = await fb_page.inner_text('body')
if '關鍵字' in body:
    print('✅ 發文成功')
```

---

## 已知的坑

### Chromium 和 Chrome 衝突

**問題**：系統有 Google Chrome + Chromium（ungoogled）兩種，混用 CDP 會衝突。

**解法**：
- 只用 Chromium（`/Applications/Chromium.app`）
- 用 `launch_persistent_context` 而非 CDP `connect_over_cdp`
- Profile 目錄放在 `~/Library/Application Support/Chromium/FacebookMCP`（與 `~/Library/Application Support/Google/Chrome` 完全分開）

### MCP server 背景執行立馬退出

**現象**：`nohup uv run --active python social_mcp.py &` 馬上退出，報 `ValueError: I/O operation on closed file`。

**原因**：`mcp.run()` 內部用 `anyio.run()` 啟動 asyncio event loop，stdin close 時它就收到 EOF 然後退出。

**解法**：
- **這是正常的，不是錯誤**。Hermes Agent 用 stdio 模式啟動 MCP server，server 會一直運行直到 Hermes 退出
- 測試時直接跑 `uv run --active python social_mcp.py`，5秒後 `kill %1` 就能看到它正常啟動過
- 不要試圖用 `nohup &` 讓它在背景跑成 daemon — 設計上就不是這樣用的

### `uv run` 的 VIRTUAL_ENV 問題

**現象**：`VIRTUAL_ENV=/Users/whypuss/.hermes/hermes-agent/venv does not match the project environment path .venv and will be ignored`

**解法**：使用 `--active` flag 強制使用當前 venv：
```bash
uv run --active python social_mcp.py
```

### CDP 模式干擾 session

**現象**：用 CDP `connect_over_cdp` 連接時，每次連接都會新建 page，干擾用戶的登入 session。

**解法**：完全放棄 CDP 模式，改用 `launch_persistent_context`。每個工具自己啟動 context、操作、關閉，不共享 browser instance。

### Facebook 站內訊息 vs messenger.com

- Facebook 主站已登入就能讀通知牆、私訊（站內回覆）
- messenger.com 需要額外登入，且 session 可能與主站不同
- **實測**：Messenger 不需要單獨登入，Facebook 登入後在 `/messages` 頁面就能操作

## 關於 just_facebook_mcp

該 repo（`Livia-Zaharia/just_facebook_mcp`）是 **Graph API 版本**，不是瀏覽器版本：
- 需要 Facebook 開發者帳號 + 粉絲專頁 + PAGE_ACCESS_TOKEN
- 只能操作粉絲專頁，**無法讀取個人私訊或通知**
- 發 DM 給個人需要 `pages_messaging` 權限（Meta 人工審批）
- **不適用於個人帳號場景**
