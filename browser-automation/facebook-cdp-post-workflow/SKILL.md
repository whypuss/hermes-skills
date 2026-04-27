---
name: facebook-cdp-post-workflow
description: Facebook CDP Browser Automation Workflow — FB 發文完整流程，按鈕識別，文字輸入
---

# Facebook CDP Browser Automation Workflow

## Trigger
FB 發文、Facebook 自動化操作

## 環境
- AIpuss-browser Chromium (port 9333)
- CDP WebSocket: ws://localhost:9333/devtools/page/{TAB_ID}
- 主分頁: 0806A244B435FA698BD105E80549F91C

## 實測修正（2025-04-26 完整流程驗證）

### 測試成功的完整流程：
1. `aria-label="Facebook 選單"` → JS .click() ✓
2. 「帖子」→ 座標 (1272, 168) ✓（aria-label 不存在）
3. 「相片/影片」→ 座標 (707, 488) ✓（JS .click() 會觸發 OS 文件選擇器並關閉 dialog）
4. 打字 → `execCommand("insertText")` ✓（key event 無效）
5. `aria-label="下一頁"` → JS .click() ✓
6. `aria-label="發佈"` → JS .click() ✓

### 關鍵修正：
- `aria-label="相片/影片"` 用 JS `.click()` 會關閉 dialog！必須用座標。
- 打字不可用 `Input.dispatchKeyEvent`，用 JS `execCommand("insertText")`。

## 核心按鈕識別法
Facebook 的按鈕幾乎全是 `DIV` + `role=button`，用 `aria-label` 區分功能。

**aria-label 一覽：**
| aria-label | 功能 |
|-------------|------|
| Facebook 選單 | 側邊欄頂部選單按鈕 |
| 相片／影片 | 打開文件選擇器（位於 dialog 底部工具列）|
| 下一頁 | 進入帖子預覽頁 |
| 發佈 | 確認發布 |
| 關閉撰寫工具對話框 | 關閉 dialog |

## 完整發文流程

### Step 1: 點擊「Facebook 選單」
```python
await cdp(ws, 1, 'Runtime.evaluate', {
    'expression': 'document.querySelector(\'[aria-label="Facebook 選單"]\').click()',
    'returnByValue': True
})
```

### Step 2: 點擊「帖子」
⚠️ aria-label="帖子" **不存在**，用座標：
```python
cx, cy = 1272, 168
await cdp(ws, 10, 'Input.dispatchMouseEvent', {'type': 'mouseMoved', 'x': cx, 'y': cy})
await asyncio.sleep(0.3)
await cdp(ws, 11, 'Input.dispatchMouseEvent', {'type': 'mousePressed', 'x': cx, 'y': cy, 'button': 'left', 'clickCount': 1})
await asyncio.sleep(0.05)
await cdp(ws, 12, 'Input.dispatchMouseEvent', {'type': 'mouseReleased', 'x': cx, 'y': cy, 'button': 'left', 'clickCount': 1})
```
等待 3 秒確認 dialog 打開。

### Step 3: 點擊「相片/影片」
⚠️ aria-label 點擊會觸發 OS 文件選擇器（需用戶手動選圖）後再點擊會關閉 dialog。
用**座標**點擊：
```python
cx, cy = 707, 488
await cdp(ws, 10, 'Input.dispatchMouseEvent', {'type': 'mouseMoved', 'x': cx, 'y': cy})
await asyncio.sleep(0.5)
await cdp(ws, 11, 'Input.dispatchMouseEvent', {'type': 'mousePressed', 'x': cx, 'y': cy, 'button': 'left', 'clickCount': 1})
await asyncio.sleep(0.05)
await cdp(ws, 12, 'Input.dispatchMouseEvent', {'type': 'mouseReleased', 'x': cx, 'y': cy, 'button': 'left', 'clickCount': 1})
```

### Step 4: 輸入文字
用 `document.execCommand("insertText")` 比 `Input.dispatchKeyEvent` 靠譜：
```python
r = await cdp(ws, 1, 'Runtime.evaluate', {
    'expression': '''(() => {
        var e = document.querySelector("[role=dialog]").querySelector("[contenteditable]");
        if (!e) return "not_found";
        e.focus();
        document.execCommand("insertText", false, "TEXT_HERE");
        return "done";
    })()''',
    'returnByValue': True
})
```
每個字符間隔 0.08 秒。**嚴禁批量轟炸 CDP。**

### Step 5: 點擊「下一頁」
```python
await cdp(ws, 1, 'Runtime.evaluate', {
    'expression': 'document.querySelector(\'[aria-label="下一頁"]\').click()',
    'returnByValue': True
})
```
等待 3 秒進入預覽頁。

### Step 6: 點擊「發佈」
```python
await cdp(ws, 1, 'Runtime.evaluate', {
    'expression': 'document.querySelector(\'[aria-label="發佈"]\').click()',
    'returnByValue': True
})
```
等待 5 秒確認發布成功。

## Dialog 常用 aria-label 按鈕（座標參考）
| aria-label | x | y | w | h |
|------------|---|---|---|---|
| 關閉撰寫工具對話框 | 418 | 96 | 36 | 36 |
| 返回 | 486 | 96 | 36 | 36 |
| 編輯私隱設定 | 37 | 183 | 87 | 17 |
| 表情符號 | 425 | 212 | 36 | 36 |
| 相片／影片 | 707 | 488 | 36 | 36 |
| 標註用戶 | 747 | 488 | 36 | 36 |
| 感受／活動 | 787 | 488 | 36 | 36 |
| 下一頁 | 486 | 551 | 468 | 36 |
| 發佈 | 726 | 646 | 228 | 36 |

## 已知限制
1. **文件上傳**：OS 級文件選擇器，CDP 無法自動化。用戶需手動選圖後，再繼續自動化後續步驟。
2. **aria-label="相片／影片"** 點擊後會觸發 OS 文件選擇器，導致 dialog 狀態丟失。此按鈕只能用座標點擊。
3. **嚴禁**在 1 秒內發送多個 CDP 指令，會導致 Chromium 分頁崩潰或開啟垃圾頁面。

## 驗證方法
```python
r = await cdp(ws, 1, 'Runtime.evaluate', {
    'expression': 'document.body.innerText',
    'returnByValue': True
})
body = r.get('result', {}).get('result', {}).get('value', '')
idx = body.find('動態消息帖子')
print(body[idx:idx+500])
```

## Instagram CDP 發文流程

### 環境
- IG tab ID: `ABDA8E4B0656D4CBD72A72C573D7FCD0`
- WebSocket: ws://localhost:9333/devtools/page/ABDA8E4B0656D4CBD72A72C573D7FCD0

### 完整流程（6步）

| 步驟 | 操作 | DOM 定位 |
|------|------|---------|
| 1 | 按「建立」→「從電腦選擇」→ 選圖 | BUTTON "從電腦選擇" (x=667, y=461) |
| 2 | 選圖後按「下一步」| DIV[role=button] "下一步" (x=1112, y=100) |
| 3 | 濾鏡頁再按「下一步」| 同上 |
| 4 | **打字**：點擊 `DIV[role=textbox][aria-label="撰寫說明文字……"]` 輸入 | x=831, y=191 |
| 5 | 按「分享」| DIV[aria-label=""] + txt="分享" (x=1126, y=100) |
| 6 | 按「完成」| DIV._ac7b._ac7d (x=940, y=88) → 確認 dialog 關閉 |

### 關鍵按鈕一覽

| 按鈕 | class / 定位方式 | 座標 |
|------|----------------|------|
| 從電腦選擇 | BUTTON `_aswp _aswr _aswu _asw_ _asx2` | x=667, y=461 |
| 下一步 | DIV[role=button] `x1i10hfl xjqpnuy xc5r6h4...` | x=1112, y=100, w=42, h=18 |
| 分享 | DIV[aria-label=""] txt="分享" | x=1126, y=100 |
| 完成 | DIV `._ac7b._ac7d` | x=940, y=88 |

### 文字輸入
- 元素：`document.querySelector("div[role=textbox][aria-label*='說明文字']")`
- 打字方法：`focus()` → `document.execCommand("insertText", false, text)`
- 計數器：`DIV[aria-label=""]` txt="4/2200" 確認已輸入

### 發文成功關鍵修正（2026-04-27 實測）
- **下一步**：不能用座標（裁切頁 x=1112，濾鏡頁 x=942），要用 JS `querySelectorAll` 遍歷點擊
- **分享**：不在 dialog 內，必須用 `querySelectorAll('*')` 遍歷整個頁面
- **完成**：在「已分享你的貼文」dialog 內，同樣用 JS 遍歷點擊
- **圖片上傳**：`dialog.locator('input[type=file]').set_input_files()` 可以自動注入，不需要 OS 選框

### 已知限制
1. **文件上傳**：Playwright `set_input_files()` 可自動注入，圖片需 > 1KB
2. **圖片裁切頁**：選圖後直接進入裁切/濾鏡頁，需按兩次「下一步」才能到打字頁
3. 打字頁後無需再按「下一步」，直接「分享」→「完成」

## CDP 操作安全規則
- 每次操作最多 1-2 個指令
- 間隔至少 0.5 秒
- 批量轟炸（幾十/幾百次）會導致 Chromium 分頁崩潰
- 永久記憶：CDP 操作規則：絕對不能一秒內轟炸 CDP 幾十或幾百次
