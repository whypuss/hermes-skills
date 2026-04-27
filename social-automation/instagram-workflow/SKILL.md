---
name: instagram-workflow
description: Instagram 圖文發文（Playwright + CDP，2026-04-27）
category: social-automation
---

# Instagram 圖文發文 workflow

## 環境
- Chromium via `BrowserHijack` (CDP port 9333)
- Playwright Python (uv run)
- 圖片路徑：`/tmp/social*.jpg`

## 核心要點（血淚經驗）

### 1. Caption 打字：`press_sequentially()` 是唯一有效方法
- `keyboard.type()` 打得進 DOM（肉眼可見文字），但 React state 沒收到，按分享後文字消失
- `keyboard.type()` 底層用 CDP `Input.dispatchKeyEvent`,沒有觸發 React 的 `onChange`/input 事件鏈
- `press_sequentially()` 底層每個字元都觸發完整 keydown/keyup/input 事件鏈，React 能正確收到
- 每個字元 delay=80ms

```python
textbox = ig.locator('[role="dialog"] [role="textbox"]').first
await textbox.click(force=True)  # 先點一下 focus
await textbox.press_sequentially(caption, delay=80)
await asyncio.sleep(2.0)
```

### 2. 按鈕點擊：只在 dialog 內搜，完整 pointer+mouse 事件鏈
- 全 page 搜尋會點到「捨棄」等錯誤按鈕
- `innerText.trim() === '分享'`（嚴格比對，移除 fallback indexOf）
- 事件鏈：pointerdown → pointerup → mousedown → mouseup → click

### 3. 流程步驟（實測有效版）
1. 點「新貼文」（SVG aria-label）
2. 等初始 dialog → 點「從電腦選擇」（Playwright locator）
3. FileChooser set_files 圖片
4. 等 4s 讓圖片載入
5. 點兩次「下一步」（CDP JS click + 等 2s）
6. 等 caption 頁出現
7. `press_sequentially()` 打字（delay=80）
8. 等 2s → 點「分享」（CDP pointer+mouse 鏈，在 dialog 內）
9. 等「分享中」→「已分享」（每 2s 輪詢 DOM）
10. 等 2s → 點「完成」（CDP，在 dialog 內）

### 4. 禁用方法
- `keyboard.type()` ❌（React state 收不到）
- CDP JS `element.value = caption` ❌
- CDP JS `_valueTracker.setValue('')` ❌
- CDP JS `dispatchEvent(new Event('input'))`（單獨使用無效）❌
- 全 page 範圍搜尋按鈕 ❌
- `.click()` 簡單事件（只用 mousedown/mouseup/click）❌

## CLI 用法
```bash
uv run python -m social_mcp.post_ig "caption text" /tmp/social.jpg
```
