---
name: social-media-auto-post-workflow
description: Chromium CDP + Google Trends HK + Gemini 自動生成並發布 FB/IG/Threads 帖子
category: browser-automation
---

# Social Media Auto-Post Workflow

## 觸發條件
使用 Chromium CDP + Google Trends HK + Gemini 自動生成並發布 Facebook / Instagram / Threads 帖子。

## 架構

```
social_workflow.py（主控）
├── Step 1: Google Trends HK → topic（跳過 posted_topics.json）
├── Step 2: Google Images → base64 圖片
├── Step 3: Gemini → 150字原創廣東話 caption（含 2-3 hashtag）
├── Step 4: 整理頁面（關閉多餘分頁）
├── Step 5: 發布 → FB + IG + Threads
└── Step 6: 寫入 posted_topics.json
```

## Step 1: Google Trends HK Topic 提取

URL: `https://trends.google.com.tw/trending?geo=HK&pli=1`

Topic 位於 `<TR class="enOdEe-wZVHld-xMbwt">`，第一行文字為 topic 名稱：

```python
topics = await page.evaluate("""() => {
    const rows = document.querySelectorAll('tr.enOdEe-wZVHld-xMbwt');
    const topics = [];
    for (const row of rows) {
        const lines = row.innerText.split('\\n').map(l => l.trim()).filter(l => l);
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

清理：去除內部空白（`"何 守信" → "何守信"`）、跳過 `posted_topics.json` 已有 topic。

## Step 3: Gemini Caption 生成（CDP 方式）

**前提**：Chromium 已登入 Google Gemini（`https://gemini.google.com/app`）

```python
GEMINI_INPUT = 'div[aria-label="請輸入 Gemini 提示詞"]'

async def call_gemini(page, prompt: str) -> str:
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
            const all = document.querySelectorAll('.model-response-text');
            if (all.length === 0) return { status: 'no-response', text: '' };
            const last = all[all.length - 1];
            const text = (last.innerText || '').trim();
            const isProcessing = last.classList.contains('processing-state-visible');
            return { status: isProcessing ? 'processing' : 'done', text };
        }""")
        
        elapsed = int(time.time() - start)
        if len(response['text']) > 80 and elapsed > 25:
            return response['text'][:500]
        if response['status'] == 'done' and len(response['text']) > 5:
            return response['text'][:500]
    
    return "[Gemini timeout]"
```

**Caption Prompt 範本**：
```
你是一個香港社交媒體內容創作專家。
請為以下話題創作一篇約150字的原創Facebook帖子內容：

話題：「{topic}」

要求：
1. 以香港廣東話口語撰寫
2. 內容像真人在分享個人觀察或感受，自然地表達
3. 內容結尾加2-3個相關hashtag，以#開頭
4. 不要加emoji
5. 全文150字以內（包括hashtag）
6. 直接輸出內容，不要加標題或「以下是」等前置說明
```

## 防重複

檔案：`~/.hermes/cron/output/posted_topics.json`

```python
POSTED_TOPICS_FILE = Path.home() / ".hermes/cron/output/posted_topics.json"
MAX_POSTED = 12

def load_posted_topics() -> list:
    if not POSTED_TOPICS_FILE.exists():
        return []
    return json.loads(POSTED_TOPICS_FILE.read_text())

def add_posted_topic(topic: str):
    topics = load_posted_topics()
    topics = [t for t in topics if t != topic]
    topics.append(topic)
    POSTED_TOPICS_FILE.parent.mkdir(parents=True, exist_ok=True)
    json.dump(topics[-MAX_POSTED:], POSTED_TOPICS_FILE.open("w"), ensure_ascii=False, indent=2)
```

## IG "完成" 按鈕處理

Instagram 發文後 dialog 常自動關閉，「完成」按鈕最多等 5 秒：

```python
try:
    done_btn = ig.get_by_text("完成", exact=True).first
    await done_btn.wait_for(timeout=5000)
    await done_btn.press("Enter")
except Exception:
    pass  # dialog auto-closed, skip
```

## 檔案結構

```
ai-cdp-browser/
├── scripts/
│   └── social_workflow.py      # 主 workflow
└── social_mcp/
    ├── post_ig.py              # Instagram 發文
    ├── post_facebook.py        # Facebook 發文
    └── post_threads.py         # Threads 發文
```

## Cron Job

```python
cronjob(action='create', schedule='every 120m',
    prompt='cd ~/.kimaki/projects/ai-cdp-browser && .venv/bin/python -m scripts.social_workflow')
```

## 已知限制

- Gemini 回應有時包含 "Gemini 說了" 前綴，用 `re.sub(r"^Gemini[^\\n]*\\n*", "", response)` 剝離
- Chromium 不可用 `pkill -f Chromium` 終止，會摧毀 CDP session 和登入狀態
