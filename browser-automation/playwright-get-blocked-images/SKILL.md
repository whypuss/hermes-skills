---
name: playwright-get-blocked-images
description: 用 Playwright CDP 瀏覽器截圖，繞過 curl/wget 被封鎖的圖片下載問題
triggers:
  - "curl 被封"
  - "wget 返回 HTML"
  - "圖片下載被阻擋"
  - "網站阻擋爬蟲"
category: browser-automation
---

# Playwright: 從被封鎖的網站取得圖片

## 觸發條件

當你需要從某個 URL 下載圖片，但：
- `curl` / `wget` / `httpx` 返回 HTML（不是圖片）
- 伺服器阻擋非瀏覽器 User-Agent
- 網絡策略阻止直接下載

## 核心解法

用 Playwright 連接 CDP 瀏覽器，直接對頁面或元素截圖。

```python
import asyncio
from playwright.async_api import async_playwright

async def get_image_via_browser(cdp_url: str, page_url: str, img_selector: str, out_path: str):
    """從被封鎖的 URL 取得圖片（用瀏覽器截圖）"""
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp(cdp_url)  # e.g. http://localhost:9333
        ctx = browser.contexts[0]
        page = await ctx.new_page()

        await page.goto(page_url, timeout=15000)
        await asyncio.sleep(2)

        # 方案 A：截圖特定 img 元素（推薦，無黑邊）
        img_el = page.locator(img_selector).first
        await img_el.screenshot(path=out_path)

        # 方案 B：截圖整個頁面
        # await page.screenshot(path=out_path)

        await page.close()
        return out_path
```

## 實測成功的流程

目標：從 Wikimedia Commons 下載 SSD 示意圖（curl 被封）

1. **Wikimedia 直接下載** → ❌ 返回 HTML（blocked）
2. **curl + User-Agent** → ❌ HTML
3. **Wikimedia API** → ❌ timeout（網絡被封）
4. **成功：導航到 Wikipedia 文章頁面** → `locator('img').screenshot()` → ✅ JPEG (402x310)

```python
# Wikipedia Solid-state drive 頁面 → 截圖 SSD 相關 img 元素
await new_pg.goto('https://en.wikipedia.org/wiki/Solid-state_drive', timeout=15000)
ssd_img = new_pg.locator('img').first  # 或更具體的 selector
await ssd_img.screenshot(path='/tmp/ssd.jpg')
```

## 關鍵細節

- `locator('img').screenshot()` 截的是瀏覽器渲染後的 `<img>` 元素，不是頁面截圖，無黑邊
- 適用於：`img` 元素在 HTML 中，但 `src` 是 remote URL（被 curl 封鎖）
- 截圖出來是瀏覽器緩存的實際載入的圖片（base64 data URL 或已下載的 blob）
- 缺點：需要 CDP 瀏覽器已開啟 remote-debugging-port

## 驗證截圖

```bash
file /tmp/ssd.jpg
# 期望輸出: JPEG image data, JFIF standard..., components 3
```

## 應用場景

| 場景 | 範例 |
|------|------|
| 論壇/社交平台阻擋爬蟲 | Threads 帖配相關圖（網上找示意圖） |
| Wikimedia Commons 圖片 | curl 被封但瀏覽器能看 |
| 需要登入才能看到的圖片 | CDP 瀏覽器已有 session |
| 網站用 JavaScript 載入圖片 | curl 無法執行 JS，瀏覽器可以 |

## 陷阱

- 不要用 `expect_download()` — 那個適用於真的點擊下載連結，不適用於從已渲染的 img 元素取圖
- 如果 img 是 lazy-load（Intersection Observer），需要先滾動讓它進入 viewport
- 截圖後驗證 `file` 命令確認是有效圖片，不是 HTML 錯誤頁
