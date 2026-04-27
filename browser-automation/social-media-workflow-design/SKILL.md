---
name: social-media-workflow-design
description: Python + aipuss-browser CDP 跨平台發文workflow的設計陷阱與修復
tags: [browser-automation, python, CDP, social-media]
---

# Social Media Cross-Posting Workflow Design

## 情境
用 Python + aipuss-browser CDP 遙控 Chromium，自動從 A 平台抓內容翻譯後發到 B 平台。

## 已知陷阱

### 1. 頁面導航後等待策略
`networkidle` 不靠譜，用固定等待 + scroll：
```python
await page.goto(url, wait_until="domcontentloaded", timeout=30000)
await asyncio.sleep(5)  # 固定 5 秒
# 然後 scroll 觸發 lazy load
for _ in range(5):
    await page.evaluate("window.scrollBy(0, 600)")
    await asyncio.sleep(0.5)
```

### 2. 共享 Chromium Context 是安全的
不同於舊版的多 WebSocket session，現在所有平台共用同一 Chromium context（同一組 tabs）。只要在 workflow 前後做頁面整理（關閉多餘 Google Images/GitHub tabs），就不會衝突。

### 3. Query 數量決定總時間
每個 query 要 5-10 秒導航。36 個 query = 6+ 分鐘直接 timeout。

**修復**：每個 workflow 只留 8-10 個核心 query。

### 4. asyncio foreground 任務超時
用 `timeout=N` 參數在 terminal() 級別設定超時。

### 5. stdout 緩衝
`python3 script.py > output.log` 加 `-u` 參數：`PYTHONUNBUFFERED=1 python3 -u script.py`

## CDP Session 管理（單一 CDP 連接）
用 `playwright.async_api` + CDP 連接到運行中的 Chromium：
```python
browser = await p.chromium.connect_over_cdp("http://localhost:9333", timeout=20000)
ctx = browser.contexts[0]  # 共享同一 context
```

**關閉多餘頁面**（保持 ≤ 6 個避免內存問題）：
```python
for pg in ctx.pages:
    if "tbm=isch" in pg.url:  # Google Images
        await pg.close()
    if "github.com" in pg.url.lower():
        await pg.close()
```

**CDP Port 發現**：
```python
import urllib.request, json
with urllib.request.urlopen("http://localhost:9333/json", timeout=5) as r:
    tabs = json.loads(r.read())  # 自動發現可用 tabs
```

## CDP Session 分配（舊）
- FB_CDP: `ws://localhost:9333/devtools/browser/...` （已廢棄，用單一 CDP 模式）
- TH_CDP: `ws://localhost:9333/devtools/browser/...`
- IG_CDP: `ws://localhost:9333/devtools/browser/...`

## 順序執行原則
不要並行跑三個 workflow——共享同一 Chromium 進程。順序跑或獨立 CDP port。

---

# Anti-Flood & Anti-Detection (CRITICAL — most common failure mode)

## The Core Rule: CDP ≠ High-Speed API
CDP is a browser automation protocol, NOT a high-throughput API. Treating it like a fast execution engine causes: (1) Chromium CDP server thread crashes, blocking ALL connections; (2) Social media account rate-limit bans. The default failure mode of optimizing for speed is account ban + lost session.

### DON'T: Rapid-Fire CDP Commands
- 400+ CDP calls in sequence (e.g., character-by-character typing) → Chromium CDP server thread crashes
- All CDP connections to that Chromium instance are lost
- Recovery: wait 60+ seconds OR restart Chromium (loses login session)

### DO: Single JS Injection for Text Input
```python
# CORRECT — one CDP call, done
expr = 'document.querySelector("textarea").innerText = "text here"; document.querySelector("textarea").dispatchEvent(new Event("input", {bubbles:true}));'
await cdp.ws.send(json.dumps({"id":1,"method":"Runtime.evaluate","params":{"expression":expr}}))
```

### DO: Human Pacing (if JS injection doesn't work for React divs)
```python
# Human typing: ~40-60 WPM = 0.1-0.15s per character
# NOT 0.02s which is 7x faster than any human
for ch in text:
    await cdp.ws.send(json.dumps({"id":i,"method":"Input.dispatchKeyEvent",...}))
    await asyncio.sleep(0.15)  # Human speed
```

## Pacing Rules
| Action | Wait After | Retry Wait |
|--------|-----------|------------|
| Click button | 2-3 seconds | 30+ seconds |
| Page navigation | 3-5 seconds | 60+ seconds |
| Dialog open | 3 seconds | **STOP** (don't re-open) |
| Upload file | 4 seconds | 30+ seconds |
| Max 3 retry attempts | per operation | Redesign if failing |

## Anti-Detection Rules
1. **Never open/close/reopen a dialog** — pick ONE path and commit. Reopening the same dialog = instant rate-limit trigger
2. **Max ~6 browser tabs** — more causes Chromium instability
3. **Never kill Chromium process** — `pkill -f Chromium` or closing main window orphans renderers and kills CDP
4. **One platform at a time** — don't parallel-bomb the same CDP server with 3 subagents simultaneously

## Chromium Process Rules
- **NEVER** `pkill -f Chromium` or `kill <pid>` — kills main process, orphans renderers, loses CDP
- **NEVER** close the Chromium window directly — use CDP's `Page.close()` on individual tabs
- Default user-data-dir for social-mcp: `~/Library/Application Support/Chromium/FacebookMCP`

## If CDP Connection is Lost
- Check main Chromium: `ps aux | grep "Chromium.app/Contents/MacOS/Chromium" | grep -v grep`
- If main process gone: CDP unavailable, restart with same `--user-data-dir` to restore session

## Gemini Caption 生成（CDP 控制已登入的 Gemini）

Gemini 網頁已登入時，可直接用 CDP 操控生成原創 caption。

**CDP Selector**：
- Input: `div[aria-label="請輸入 Gemini 提示詞"]`（Quill 編輯器）
- Send: `button[aria-label="傳送訊息"]` 或 `page.keyboard.press("Enter")`

**等待 Gemini 回應關鍵**：`processing-state-visible` class 消失才表示完成

```python
GEMINI_INPUT = 'div[aria-label="請輸入 Gemini 提示詞"]'

async def call_gemini(page, prompt: str, timeout=90) -> str:
    inp = page.locator(GEMINI_INPUT)
    await inp.click()
    await inp.fill("")
    await asyncio.sleep(0.5)
    await inp.type(prompt, delay=40)
    await asyncio.sleep(1)
    await page.keyboard.press("Enter")
    await asyncio.sleep(6)
    start = time.time()

    for _ in range(15):
        await asyncio.sleep(4)
        response = await page.evaluate("""() => {
            const all = Array.from(document.querySelectorAll('.model-response-text'));
            if (all.length === 0) return { status: 'no-response', text: '' };
            const last = all[all.length - 1];
            const text = (last.innerText || '').trim();
            const isProcessing = last.classList.contains('processing-state-visible');
            return { status: isProcessing ? 'processing' : 'done', text };
        }""")

        elapsed = int(time.time() - start)
        # 實測：text > 80 chars + elapsed > 25s 即可取用（不等 processing 消失）
        if len(response['text']) > 80 and elapsed > 25:
            return response['text'][:500]
        if response['status'] == 'done' and len(response['text']) > 5:
            return response['text'][:500]

    return "[Gemini timeout]"
```

**Prompt 模板（150字原創廣東話 caption）**：
```python
prompt = (
    f"你是一個香港社交媒體內容創作專家。\n"
    f"請為以下話題創作一篇約150字的原創Facebook帖子內容：\n\n"
    f"話題：「{topic}」\n\n"
    f"要求：\n"
    f"1. 以香港廣東話口語撰寫\n"
    f"2. 內容像真人在分享個人觀察或感受，自然地表達\n"
    f"3. 不要加emoji\n"
    f"4. 不要列出關鍵字或hashtag\n"
    f"5. 150字以內\n"
    f"6. 直接輸出內容，不要加標題或「以下是」等前置說明"
)
```

**剝離 Gemini 前綴**：回應有時含 "Gemini說了" → `re.sub(r"^Gemini[^\\n]*\\n*", "", response).strip()`

---

## 防重複：已發布 Topic 追蹤

避免同一個 topic 被重複發布。用 JSON 檔案記錄最近 12 個已發布 topic。

```python
POSTED_TOPICS_FILE = Path.home() / ".hermes/cron/output/posted_topics.json"
MAX_POSTED = 12

def load_posted_topics() -> list:
    if not POSTED_TOPICS_FILE.exists():
        return []
    with open(POSTED_TOPICS_FILE) as f:
        return json.load(f)

def add_posted_topic(topic: str):
    topics = [t for t in load_posted_topics() if t != topic]
    topics.append(topic)
    POSTED_TOPICS_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(POSTED_TOPICS_FILE, "w") as f:
        json.dump(topics[-MAX_POSTED:], f, ensure_ascii=False)

# 抓 topics 時跳過已發布的
topics = await get_gtrends_hk(browser, ctx, skip_topics=load_posted_topics())
```

---

## Google Trends HK 作為話題來源

Google Trends HK 比 X.com 更穩定，無需登入，topic 質量高。

**正確 DOM selector**：
```python
topics = await page.evaluate("""() => {
    const rows = document.querySelectorAll('tr.enOdEe-wZVHld-xMbwt');
    const topics = [];
    for (const row of rows) {
        const text = row.innerText || '';
        const lines = text.split('\\n').map(l => l.trim()).filter(l => l);
        if (lines.length > 0) {
            const topic = lines[0];
            if (topic.length >= 2 && topic.length <= 35) {
                topics.push(topic);
            }
        }
    }
    return [...new Set(topics)];
}""")
```

**注意**：
- Topics 有時包含內部空格：如 "何 守信" → `re.sub(r'\s+', '', t)` 去除
- 太抽象的關鍵詞要過濾：`["1994", "series", "episode", "trailer", "awards"]`
- Google Images 搜尋每個 topic → base64 data URI → 解碼存檔

## 搜索話題（港澳台熱門）
```python
queries = [
    "香港時事", "台灣新聞", "香港演唱會",
    "台灣美食", "香港美食", "台灣旅遊",
    "香港樓市", "台灣房產", "香港天氣", "台灣天氣",
]
```
