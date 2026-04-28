---
name: social-automation-playwright-gotchas
description: Playwright CDP 社交平台自動化踩坑指南（Facebook/Instagram/Threads）
category: browser-automation
tags: [playwright, facebook, instagram, threads, social-automation, cdp]
---

# Social Automation — Playwright CDP 自動化踩坑指南

## 觸發條件
當你需要用 Playwright CDP 模式自動化社交平台（Facebook/Instagram/Threads）圖文發文時參考。

---

## 1. OS File Picker 不關閉

**問題**：點擊「附加影音」按鈕後，OS file picker 彈出但不會自動關閉。

**原因**：`set_input_files()` 在點擊按鈕之後執行，但 OS file chooser 在按鈕點擊時就立即彈出，兩者之間存在 race condition。

**修復**：在點擊任何可能觾發 file picker 的按鈕**之前**，先註冊 filechooser 事件監聽器並阻止默認行為：

```python
# 一定要在點擊按鈕之前設定
file_chooser_future = asyncio.Future()

async def on_file_chooser(fd):
    # 直接取消，不處理（用 set_input_files 繞過 OS dialog）
    fd.set_files([])

page.on("filechooser", on_file_chooser)

# 然後再點擊按鈕
await page.locator(_svg_btn("附加影音內容")).last.click(timeout=3000, force=True)
await asyncio.sleep(0.3)

# 再 set_input_files
inp = page.locator('[role="dialog"] input[type="file"]').last
await inp.set_input_files(image_path, timeout=5000)
```

**千萬不要**：點擊按鈕後馬上 `set_input_files`，中間沒有任何間隔也沒有 event listener 攔截，OS dialog 會搶先彈出。

---

## 2. Gemini 提問打字未完成就提交

**問題**：輸入 prompt 到 Gemini，`keyboard.press("Enter")` 在打字還沒完全結束時就執行，導致 Gemini 只收到部分 prompt。

**原因**：`type(delay=40)` 每字 40ms，對長 prompt 來說很快，但非同步執行還沒完成就按 Enter。`fill("")` 清空後 DOM 還沒穩定。

**修復**：

```python
inp = page.locator(GEMINI_INPUT)
await inp.click()
await inp.fill("")
await asyncio.sleep(1.0)   # 等 fill 完全生效，DOM 穩定
await inp.type(prompt, delay=60)  # 60ms/字，更擬人
await asyncio.sleep(1.5)   # 等 React state 完全更新後才按 Enter
await page.keyboard.press("Enter")
```

---

## 3. Threads 兩步發文流程

Threads 發文是獨特的兩步流程，其他平台不同：

```
Step 1: 點 composer → dialog 開
Step 2: 打字 → 圖片
Step 3: 點「新增到串文」（不是「發佈」！）
Step 4: 進入 caption 審查頁
Step 5: 點「發佈」（第二步的按鈕）
```

**易錯點**：直接找「發佈」按鈕在第一步是找不到的，必須先點「新增到串文」。

按鈕點擊用 `getBoundingClientRect → mouse.click` 座標，不要用 Playwright locator.click（React onClick 不觸發）。

---

## 4. CDP 操作速率限制

**問題**：短時間內 CDP 操作（evaluate/click/type）太密集，Chrome 分頁崩潰或開啟垃圾頁面。

**修復**：每次 CDP 操作後間隔至少 0.5-1 秒。

```python
await page.evaluate("...")  # CDP
await asyncio.sleep(0.5)    # 等一下
await page.mouse.click(...)  # CDP
await asyncio.sleep(0.5)    # 等一下
```

---

## 5. Threads tab 必須預先開啟

`post_threads.py` 依賴現成的 Threads tab（`threads.net`），如果 tab 不存在會直接失敗。

在 workflow 中，確保在 call `post_threads()` 之前有：
```python
threads_tab = None
for pg in ctx.pages:
    if "threads.net" in pg.url and "settings" not in pg.url:
        threads_tab = pg
        break
if not threads_tab:
    threads_tab = await ctx.new_page()
    await threads_tab.goto("https://www.threads.net/", wait_until="domcontentloaded", timeout=20000)
    await asyncio.sleep(3)
```

---

## 驗證清單（每次發文後必查）

- [ ] Dialog 是否已關閉（`locator('[role="dialog"]').wait_for(state="hidden")`）
- [ ] 文字是否出現在編輯框（`inner_text()` 確認）
- [ ] 圖片 blob URL 是否生成（`img.src.startsWith('blob:')`）
- [ ] Reload 後內容是否還在（最可靠的驗證方式）
