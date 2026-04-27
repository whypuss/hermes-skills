---
name: ig-automation-accessibility-api
description: Instagram 自動化發文 — CDP 點擊失效根因 + open-codex-computer-use (Accessibility API) 解決方案
category: browser-automation
---

# IG Automation — CDP vs Accessibility API

## 問題背景

用 CDP（Chrome DevTools Protocol）自動化 Instagram 發文時，點擊「下一步」按鈕會失敗。

### 根因

IG 新貼文 dialog（裁切頁/編輯頁）存在多個 dialog 重疊：
- `div[role=dialog]` A：「裁切 / 下一步」
- `div[role=dialog]` B：「捨棄貼文？ / 捨棄 / 取消」（隱藏）

JS `element.click()` 對 `div[role=button]` 的「下一步」會觸發多個 mouse 事件（mousedown → mouseup → click），其中某個事件被 IG 解讀為「返回上一頁」行為，導致 dialog B 彈出覆蓋按鈕，最後整個 dialog 關閉。

CDP `Input.dispatchKeyEvent(type="Enter")` 只傳送單一 key 事件，不會觸發 mouse 事件鏈，所以有效。

### 完整 IG 發文流程（2026-04-26 實測）

1. 點擊「新貼文」→ dialog 出現
2. 選擇圖片 → set_input_files → 按「打開」
3. 裁切頁 → CDP Enter（有效）→ 按「下一步」
4. 編輯/濾鏡頁 → CDP Enter（有效）→ 按「下一步」
5. caption 頁（撰寫說明文字……）→ innerText + dispatchEvent(input)
6. 按「分享」→ JS click（此階段有效）
7. 「已分享你的貼文」→ 按「完成」→ JS click（有效）

### 最終解決方案：open-codex-computer-use

**安裝**：`npm i -g open-computer-use`

**核心工具**：
- `get_app_state("Chromium")` — 截圖 + Accessibility 樹，每個 UI 元素有 index
- `click(app="Chromium", element_index="42")` — 用 Accessibility API 直接點擊 OS 層元素，繞過 JS
- `type_text(app="Chromium", text="...")` — OS 層鍵盤輸入
- `press_key(app="Chromium", key="Return")` — OS 層按鍵

**優勢**：
- Accessibility API 在 OS 層模擬滑鼠/鍵盤，繞過 CDP 的 JS 事件攔截問題
- 不需要 focus 元素，API 直接操作 element

**限制**：
- 需要 macOS Accessibility 權限（System Settings > Privacy & Security > Accessibility）
- 需要 Screen Recording 權限
- `open-computer-use doctor` 可檢查權限狀態

**CDP fallback**（針對 caption 輸入等場景）：
- 輸入 caption：`element.innerText = text + dispatchEvent(new Event("input", {bubbles:true}))`
- 分享按鈕：`element.click()`
- 這些在 caption 頁有效，因為這階段沒有 dialog 重疊問題
