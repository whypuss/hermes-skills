---
name: ig-human-post
description: Instagram 擬人發文流程（post_ig_human.py）— CDP Playwright 模式，繞過 OS dialog，React 事件觸發
---

# IG 擬人發文流程

## 觸發條件
每次 social workflow 需要發 Instagram 時使用。

## 完整流程（post_ig_human）
1. CDP 連接 IG 頁面
2. 點擊 `svg[aria-label="新貼文"]` → 等「建立新帖子」dialog
3. `set_input_files()` 直接注入圖片到 `input[type=file]`（繞過 OS dialog）
4. 等裁切頁（dialog text 含「裁切」）
5. Playwright `.click()` 點擊「下一步」(裁切→濾鏡)
6. Playwright `.click()` 點擊「下一步」(濾鏡→Caption)
7. 找 `[role="dialog"] [role="textbox"]` → `fill(caption)`
8. Playwright `.click()` 點擊「分享」
9. 等 dialog 內「已分享」
10. Playwright `.click()` 點擊「完成」

## 關鍵發現（調試精華）

### 按鈕都是 DIV（不是 button）
- `下一步`、`分享`、`完成` 都是 `<DIV>` 元素，`textContent === "下一步"`
- 不能用 `querySelectorAll('button')`
- aria-label 通常是空字串，不可靠

### 正確定位策略（4 層 fallback）
```python
# 策略1: Playwright :text-is (完全匹配) — 最優先
locator = page.locator(f'[role="dialog"] :text-is("{target}")').first
if await locator.count() > 0:
    await locator.click(timeout=5000)

# 策略2: Playwright :text (包含匹配)
locator = page.locator(f'[role="dialog"] :text("{target}")').first

# 策略3: aria-label
targets = dialog.querySelectorAll(`[aria-label="{target}"]`)

# 策略4: CDP evaluate + MouseEvent（已失效，React 不響應）
```

### Playwright locator 是首選（而非 CDP JS）
- `下一步`、`分享`、`完成` 都是 `<DIV>`，`textContent === "下一步"`
- 用 Playwright `:text("下一步")` locator，最可靠：
  ```python
  locator = page.locator('[role="dialog"] :text-is("下一步")').first
  await locator.click(timeout=5000)
  ```
- CDP `dispatchEvent(new MouseEvent('click'))` 無法觸發 React synthetic event，**千萬不要用**

### Gemini 處理狀態不可靠
- Gemini 回覆文字已存在時，`processing-state-visible` class 可能仍為 true
- 每次輪詢都應該拿文字內容，不要等 `status == 'done'`
- 實測：等待超過 20 個 cycle（80s）還是 proc，但文字已完整（255+ chars）
- 解決：每 4s 輪詢，直接取 `innerText`，不用等狀態

### CDP 分頁管理（重要）
- CDP Chromium 9333 累積過多分頁會導致效能問題和 prompt 污染
- **永遠保持 ≤ 6 個分頁**，及時關閉不需要的
- 關閉策略：只保留 `instagram.com`、`threads.com`、`trends.google.com`、`facebook.com`
- Gemini 網頁介面無乾淨 session，每次請求會吃到歷史 context → prompt 容易被污染

### 兩個人類-mcp 目錄（容易混淆）
- `~/human-mcp/` — 真正在跑、有 `/scrape` 端點的版本（綁定 GitHub）
- `~/.kimaki/projects/human-mcp/` — 舊備份，無 `/scrape`
- human-mcp 技能綁定 GitHub：`https://github.com/whypuss/human-mcp`

## 文件位置
`/Users/whypuss/.kimaki/projects/ai-cdp-browser/social_mcp/post_ig_human.py`
- `dispatchEvent` 繞過了 React 的事件系統
- Playwright `.click()` 會調用 React 的事件處理函數

## 文件位置
`/Users/whypuss/.kimaki/projects/ai-cdp-browser/social_mcp/post_ig_human.py`

## 使用方式
```python
import asyncio
from social_mcp.post_ig_human import post_ig_human

result = asyncio.run(post_ig_human("caption text 🌸", "/path/to/image.jpg"))
print(result)  # "✅ Instagram 發文成功" 或 "❌ 錯誤描述"
```

## 依賴
- `social_mcp.browser_hijack.get_active_cdp_port()`
- `playwright.async_api.async_playwright`
- CDP port 9333（FacebookMCP Chromium）
