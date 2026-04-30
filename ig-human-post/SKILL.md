---
name: ig-human-post
description: Instagram 擬人發文流程（post_ig_human.py）— 獨立 Chromium Profile + 語義點擊架構
---

# IG 擬人發文流程（新版）

## 觸發條件
每次 social workflow 需要發 Instagram 時使用。

## 架構演變

### 舊版（CDP 模式）問題
- 依賴 CDP port 9333 連接用戶 Chrome
- CDP browser 有 captcha，tab 太多會崩潰
- 座標點擊：`mouse.click(x, y)` → UI 變了就掛

### 新版（獨立 Profile + 語義點擊）
- 每個腳本用自己的 Chromium Profile：`/tmp/ig-chromium-profile/`
- 不需要 CDP port、不需要提前打開瀏覽器
- DOM 定位 + 自癒重試 → UI 改版也能運作

## 完整流程（post_ig_human.py）

```
launch_persistent_context → Threads profile 目錄
       ↓
ensure_logged_in（檢查是否在 login 頁）
       ↓
點「新貼文」svg[aria-label="新貼文"]
       ↓
等「從電腦選擇」dialog
       ↓
file_chooser.set_files() 或 JS DataTransfer 注入圖片
       ↓
等 3s（IG 處理圖片）
       ↓
語義點擊「下一步」(裁切頁) → verify_after
       ↓
語義點擊「下一步」(濾鏡頁) → verify_after
       ↓
Caption 頁：找 [role="textbox"] → fill(caption)
       ↓
語義點擊「分享」 → verify_after
       ↓
等「已分享」→「完成」
```

## 語義點擊核心（SemanticBtn 類）

```python
class SemanticBtn:
    """
    三層 fallback：
    1. getByRole(name=label) / locator(:text-is())
    2. JS dispatchEvent（React 兼容性）
    3. 自癒重試（按鈕還在？重試）
    """

    async def click(self, label: str, timeout: float = 10, max_retries: int = 3) -> bool:
        for attempt in range(1, max_retries + 1):
            # 策略1: getByRole
            loc = container.get_by_role("button", name=label, exact=False)
            if await loc.count() > 0 and await loc.first.is_visible():
                await loc.first.click()

            # 策略2: locator(:text-is)
            loc = container.locator(f"button:has-text('{label}')")

            # 策略3: JS 遍歷（textContent / aria-label）
            # mouse.click(x, y) 搭配 dispatchEvent

            # 驗證：按鈕是否消失（dialog 進入下一頁）
            if still_visible_after_click and attempt < max_retries:
                await asyncio.sleep(1.0)
                continue  # 重試

            return True
        return False
```

## 關鍵發現（調試精華）

### 為什麼不用座標 click？
```python
# ❌ 舊：UI 變了就掛
await page.mouse.click(640, 400)

# ✅ 新：DOM 定位，UI 變了只要文字還在就能找到
await page.get_by_role("button", name="下一步").click()
```

### 為什麼不用 CDP？
- CDP Chromium 9333 有 Google captcha（Google 對 CDP browser 態度不同）
- Tab 太多導致崩潰
- CDP port 管理複雜
- 解決：`launch_persistent_context` 每個腳本獨立 Chromium，不影響用戶正常 Chrome

### 為什麼不用 CDP dispatchEvent？
- React 3.x 用 synthetic event，`dispatchEvent` 直接觸發 DOM event，不走 React 事件系統
- 但 Playwright `.click()` 會觸發 React synthetic event
- 所以用 Playwright locator，React 才會響應

### JS DataTransfer 注入圖片（仍然有效）
```python
# OS file chooser 在 headless/CDP mode 無法操作
# 用 JS DataTransfer 繞過：
result = await page.evaluate("""(b64) => {
    const blob = new Blob([bytes], { type: 'image/jpeg' });
    const file = new File([blob], 'upload.jpg', ...);
    const dt = new DataTransfer();
    dt.items.add(file);
    Object.defineProperty(inp, 'files', { value: dt.files, writable: true });
    inp.dispatchEvent(new Event('change', { bubbles: true }));
}""", b64)
```

## 文件位置

- IG: `~/human-mcp/post_ig_human.py`
- FB: `~/human-mcp/post_facebook.py`
- Threads: `~/human-mcp/post_threads.py`

## 使用方式

```bash
# 第一次（需手動登入一次）
python3 post_ig_human.py "測試 caption" "/path/to/image.jpg"

# workflow 調用
python3 social_workflow.py 1  # 自動發 FB + Threads + IG
```

```python
import asyncio
from post_ig_human import post_ig_human

result = asyncio.run(post_ig_human("caption text", "/path/to/image.jpg"))
# "✅ Instagram 發文成功" 或 "❌ 錯誤描述"
```

## 依賴

- `playwright.async_api.async_playwright`
- Chromium Profile: `/tmp/ig-chromium-profile/`
- **無需 CDP port**、無需提前打開瀏覽器
