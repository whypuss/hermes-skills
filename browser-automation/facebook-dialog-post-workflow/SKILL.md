---
name: facebook-dialog-post-workflow
description: Facebook 發文 — CDP Browser Hijacking，dialog 內滾動容器 + 鍵盤輸入 + 雙按鈕確認流程
trigger: post to Facebook via browser automation, CDP click fails on blue button
tags: ['browser-automation', 'facebook', 'cdp', 'playwright']
tools: ['playwright', 'websockets', 'httpx']
---

# Facebook Dialog Post Workflow

## ✅ 成功流程（2025-04 實測）

Facebook 的帖子 Composer 是**兩頁對話框**，不是滾動容器：

1. **Facebook 選單** → **帖子**（進入第一頁）
2. **打字** → **相片/影片**（用戶手動上傳）
3. **下一頁**（進入第二頁）
4. **發佈**

**驗證**：檢查 `document.body.innerText` 中「動態消息帖子」區塊是否包含發布內容。

## 完整流程（Python + CDP WebSocket）

### Dialog 兩頁按鈕結構（視窗 1280px 寬）

| 頁 | 按鈕 | aria-label | 位置 |
|----|------|-----------|------|
| 1 | 關閉 | 關閉撰寫工具對話框 | (418, 96) |
| 1 | 返回 | 返回 | (486, 96) |
| 1 | 相片/影片 | 相片／影片 | (707, 488) |
| 1 | 下一頁 | 下一頁 | (486, 551) |
| 2 | 排程/發佈 | — | (478, 377) |
| 2 | **發佈** | 發佈 | (726, 646) |

### Step 1: Facebook 選單
```python
await cdp(ws, 1, 'Runtime.evaluate', {
    'expression': 'document.querySelector(\'[aria-label="Facebook 選單"]\').click()',
    'returnByValue': True
})
await asyncio.sleep(2)
```

### Step 2: 帖子（座標點擊）
aria-label 點擊在 menu 區域可能不靠譜，用座標：
```python
cx, cy = 1272, 168  # 視窗 1280px 寬時 menu 區域
await cdp(ws, 10, 'Input.dispatchMouseEvent', {'type': 'mouseMoved', 'x': cx, 'y': cy})
await asyncio.sleep(0.3)
await cdp(ws, 11, 'Input.dispatchMouseEvent', {'type': 'mousePressed', 'x': cx, 'y': cy, 'button': 'left', 'clickCount': 1})
await asyncio.sleep(0.05)
await cdp(ws, 12, 'Input.dispatchMouseEvent', {'type': 'mouseReleased', 'x': cx, 'y': cy, 'button': 'left', 'clickCount': 1})
await asyncio.sleep(2)
```

### Step 3: 打字（execCommand insertText）
`Input.dispatchKeyEvent` 無法輸入到 React contenteditable。用 `execCommand`：
```python
await cdp(ws, 1, 'Runtime.evaluate', {
    'expression': '''(function() {
        var e = document.querySelector("[role=dialog]").querySelector("[contenteditable]");
        if (!e) return "no_editor";
        e.focus();
        document.execCommand("insertText", false, "你的文字內容");
        return "done";
    })()''',
    'returnByValue': True
})
```

### Step 4: 相片/影片（用戶手動）
OS 層級 file chooser，CDP 無法自動化。用戶手動選圖。

### Step 5: 下一頁（aria-label）
```python
await cdp(ws, 1, 'Runtime.evaluate', {
    'expression': 'document.querySelector(\'[aria-label="下一頁"]\').click()',
    'returnByValue': True
})
await asyncio.sleep(3)
```

### Step 6: 發佈
```python
await cdp(ws, 1, 'Runtime.evaluate', {
    'expression': 'document.querySelector(\'[aria-label="發佈"]\').click()',
    'returnByValue': True
})
await asyncio.sleep(5)
```

### Step 7: Verify
```python
r = await cdp(ws, 99, 'Runtime.evaluate', {
    'expression': 'document.body.innerText',
    'returnByValue': True
})
body = r.get('result', {}).get('result', {}).get('value', '')
idx = body.find('動態消息帖子')
# 檢查 idx 以後的文字是否包含發布內容
```

## 已知問題

| 問題 | 原因 | 解法 |
|------|------|------|
| **CDP 看不到用戶正在操作的按鈕** | CDP session 和用戶視窗是**兩個獨立渲染實例** | 不要嘗試用 CDP 追蹤用戶操作；讓用戶告知座標，或操作完成後驗證結果 |
| 文字打不进去 | `Input.dispatchKeyEvent` / DOM innerText 都不觸發 React 事件 | 用 `document.execCommand("insertText", false, text)` |
| 圖片上傳失敗 | OS file chooser，CDP 無法自動化 | 用戶手動選圖 |
| 點擊 Facebook 選單後 menu 不出現 | CDP session 視窗和用戶視窗是**兩個獨立渲染實例** | 等待後用 DOM 變化判斷，不要靠用戶視窗截圖 |
| aria-label 點擊導致 dialog 關閉 | 某些按鈕的 JS click 行為與預期不同 | 改用座標 `Input.dispatchMouseEvent` |
| 帖子找不到（CDP 回空）| menu 內多個重疊元素（同一文字多個嵌套 DIV/SPAN） | 用座標 (1272, 168) 點擊 menu 區域 |

## 截圖時機

每個步驟後截圖確認狀態：
- `step1_composer.png` — composer 打開後
- `step2_image.png` — 圖片設定後
- `step3_typed.png` — 打字完成後
- `step4_scrolled.png` — 滾動到按鈕可見後
- `step5_after_next.png` — 點下一頁後
- `step6_final.png` — 點發佈後
