---
name: social-media-cdp-button-selectors
description: Cross-platform button selector patterns for Facebook, Instagram, Threads CDP browser automation — all verified 2026-04-27
category: browser-automation
tags: [cdp, browser-automation, threads, instagram, facebook, social-media]
created: 2026-04-27
---

# Social Media CDP Button Selectors

Cross-platform button/textbox selectors for Facebook (Chrome 9222), Instagram (Chromium 9333), Threads (Chromium 9333).

## Golden Rule
**Never use fixed coordinates for buttons.** Always use JS `querySelectorAll` traversal with `aria-label`, `role`, or `innerText` matching. Coordinates break across screen sizes, page states, and platform updates.

---

## Threads (threads.com)

**Port**: 9333 (Chromium, NOT Chrome)

### Composer — Open
```javascript
// JS: click "有什麼新鮮事？" anywhere on page
document.querySelectorAll("*").forEach(e => {
    if ((e.innerText||"").trim() === "有什麼新鮮事？") e.click();
});
```

### Composer — Textbox
```javascript
// selector: div[role="textbox"]
// aria-label: "文字欄位空白。請輸入內容以撰寫新貼文。"
const tb = document.querySelector('div[role="textbox"]');
tb.focus();
document.execCommand("insertText", false, text);
```

### Composer — Buttons (all via JS traversal)
```javascript
// Pattern: find element by text or aria-label, then click()
// Opens: svg[aria-label="附加影音內容"]
// GIF: svg[aria-label="新增 GIF"]
// Emoji: svg[aria-label="新增表情符號"]
// Poll: svg[aria-label="新增票選活動"]
// Location: svg[aria-label="新增地點"]
// Cancel: div[role=button] text="取消"
// Post: div[role=button] text="發佈" (inside dialog)
const dialog = [...document.querySelectorAll("[role='dialog']")].find(d => d.innerText?.includes("新串文"));
const btn = [...dialog.querySelectorAll("div[role='button']")].find(b => b.innerText?.trim() === "發佈");
btn?.click();
```

### Threads — Verify Post Success
```javascript
// After clicking 發佈, dialog closes and page stays on feed
// Verify: dialog gone + page URL unchanged
!document.querySelector("[role='dialog']")  // true = success
```

---

## Instagram (instagram.com)

**Port**: 9333 (Chromium)

### Open Composer
```javascript
// svg[aria-label="新貼文"] at (x=24, y=479)
document.querySelectorAll("svg").forEach(e => {
    if (e.getAttribute("aria-label") === "新貼文") e.click();
});
```

### Image Upload
```javascript
// Use Playwright set_input_files on dialog input[type=file]
dialog.locator('input[type=file]').set_input_files(imagePath);
// Image must be > 1KB
```

### Textbox
```javascript
// selector: div[role=textbox][aria-label*='說明文字']
const tb = document.querySelector('div[role=textbox][aria-label*="說明文字"]');
tb.focus();
document.execCommand("insertText", false, text);
```

### Navigation Buttons (crop/filter/share/done)
```javascript
// NEVER use coordinates — they differ per page
// Use JS traversal by innerText
document.querySelectorAll("*").forEach(e => {
    const t = (e.innerText||"").trim();
    if (t === "下一步" || t === "分享" || t === "完成") e.click();
});
```

### Share Button
```javascript
// Share is NOT inside the dialog — scan entire page
document.querySelectorAll("*").forEach(e => {
    if ((e.innerText||"").trim() === "分享") e.click();
});
```

### Verify Post Success
```javascript
// aria-label="已分享貼文" appears in dialog
document.querySelector("[role=dialog]")?.innerText?.includes("已分享你的貼文")
```

---

## Facebook (facebook.com)

**Port**: 9222 (Chrome)

### Composer Open
```javascript
// aria-label contains "建立" on the create button
[...document.querySelectorAll("[aria-label]")].find(e => e.getAttribute("aria-label").includes("建立"))?.click();
```

### Textbox
```javascript
// contenteditable with aria-label
const tb = [...document.querySelectorAll("[contenteditable]")].find(e => 
    e.getAttribute("aria-label")?.includes("說明")
);
tb?.focus();
document.execCommand("insertText", false, text);
```

### Post Button
```javascript
// div[role=button] text="發佈" or "分享"
[...document.querySelectorAll("div[role=button]")].find(b => 
    b.innerText?.trim() === "發佈" || b.innerText?.trim() === "分享"
)?.click();
```

---

## Universal Pattern

```javascript
// Always this pattern — never coordinates:
function clickByText(tag, text) {
    document.querySelectorAll(tag || "*").forEach(e => {
        if ((e.innerText||"").trim() === text) e.click();
    });
}

function clickByAriaLabel(selector, label) {
    document.querySelectorAll(selector).forEach(e => {
        if (e.getAttribute("aria-label") === label) e.click();
    });
}
```

## CDP Verification Checklist

Before running a post workflow, always verify:
1. [ ] `document.querySelector("[role=dialog]")` — dialog actually opened
2. [ ] Text input accepted — check `element.innerText` after typing
3. [ ] Post button found — `return "found"` from JS traversal
4. [ ] Post success — dialog closes or confirmation text appears
