---
name: semantic-clicking-browser-automation
description: Playwright 腳本用 DOM 語義定位 + 自癒重試，取代座標點擊。UI 改版後依然有效。
category: browser-automation
---

# Semantic Clicking — 語義自癒瀏覽器自動化

## 解決什麼問題？

傳統 RPA 用 `mouse.click(x, y)`，按鈕換位置/顏色/樣式就掛。

語義點擊做法：DOM 定位為主，錯了自動重試。

## 核心架構

```
DOM 定位（getByRole / getByText）
       ↓ 找不到
JS dispatchEvent（React 兼容性 fallback）
       ↓ 點了沒反應
結果驗證（verify_after 關鍵字）
       ↓ 按鈕還在（UI 變了）
自動重試（最多 N 次）→ Self-Correction Loop
```

## Python Playwright 實現

### SemanticClicker 類

```python
class SemanticClicker:
    def __init__(self, page, vision_fn=None):
        self.page = page
        self.vision_fn = vision_fn  # 可選視覺定位 (label -> x, y)

    async def click(
        self,
        label: str,
        role: str = "button",
        parent: str = "dialog",
        verify_after: str = None,  # 點完驗證的關鍵字
        max_retries: int = 3,
    ) -> bool:
        for attempt in range(1, max_retries + 1):
            # 1. Playwright getByRole（最靠譜）
            elem = await self._find_by_role(label, role, parent)

            if not elem:
                # 2. JS dispatchEvent（React）
                elem = await self._find_by_js(label, parent)

            if not elem:
                continue  # 重試

            try:
                await elem.click(timeout=5000)
            except:
                await elem.click(timeout=3000, force=True)

            # 3. 驗證結果
            if verify_after:
                found = await self._verify_dialog_text_contains(verify_after)
                if found:
                    return True
                await asyncio.sleep(1.0)
                continue  # 重試
            return True
        return False

    async def _find_by_role(self, label, role, parent):
        container = self.page.locator('[role="dialog"]') if parent == "dialog" else self.page
        for exact in [True, False]:
            loc = container.get_by_role(role, name=label, exact=exact)
            if await loc.count() > 0 and await loc.first.is_visible(timeout=1000):
                return loc.first
        return None

    async def _verify_dialog_text_contains(self, keyword, timeout=5):
        for _ in range(int(timeout * 5)):
            try:
                dt = await self.page.evaluate(
                    "() => { var d = document.querySelector('[role=\"dialog\"]'); "
                    "return d ? d.innerText.slice(0, 500) : ''; }"
                )
                if keyword in dt:
                    return True
            except: pass
            await asyncio.sleep(0.2)
        return False
```

### 調用示例

```python
ok = await clicker.click(
    label="發佈",
    role="button",
    parent="dialog",
    verify_after="已發佈",  # 點完期望看到的關鍵字
    max_retries=3,
)
```

## 為何比座標靠譜？

| 方法 | UI 變了怎麼辦 |
|------|--------------|
| `mouse.click(x, y)` | 必掛 |
| `getByRole(name="發佈")` | 按鈕改名才掛 |
| `getByText("發佈")` | 文字改了才掛 |
| DOM + verify_after 重試 | 都能撐住 |

## 適用場景

- Instagram / Threads / Facebook 發文腳本
- 任何 React/Vue SPA（按鈕用 role + aria-label）
- UI 改版頻繁的 Web 應用

## 預留 Vision Fallback

如果 DOM 也找不到，可以接入 `browser_vision` MCP：
```python
coords = await self.vision_fn(screenshot_path, label)  # (x, y)
await self.page.mouse.click(x, y)
```
