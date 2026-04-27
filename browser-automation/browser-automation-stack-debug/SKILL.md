---
name: browser-automation-stack-debug
description: Debug multi-component browser automation environments — discover which process owns which CDP port, which profile each browser uses, and whether the architecture matches expectations. Used when you need to understand the actual running setup vs the expected one.
category: browser-automation
---

# Browser Automation Stack Debug — CDP Port + Process Discovery

## When to Use
When debugging a multi-component browser automation environment (social-mcp, AIpuss-browser, opencli-host, etc.) and you need to understand which component is actually running, which port serves which purpose, and whether the expected architecture matches reality.

## Debug Sequence

### Step 1: Discover all listening ports
```bash
lsof -i -P | grep "LISTEN"
```
Output shows: `aipuss-br`, `autocli`, `Chromium`, `Google`, `Python` processes with their ports.

### Step 2: Identify each browser's tabs via CDP
For each CDP port (e.g. 9333, 9222, 63348):
```python
import urllib.request, json
req = urllib.request.Request(f'http://localhost:{PORT}/json/list', headers={'User-Agent': 'Mozilla/5.0'})
with urllib.request.urlopen(req, timeout=5) as r:
    tabs = json.loads(r.read())
for tab in tabs:
    print(f"[{tab['id'][:16]}] {tab['type']} | {tab['url'][:70]} | {tab['title'][:40]}")
```

### Step 3: Identify process by user-data-dir
```bash
ps aux | grep "Chromium\|Google Chrome\|remote-debugging"
```
The `--user-data-dir=` flag reveals which profile each browser is using.

### Step 4: Check CDP session from Python/Playwright
```python
from social_mcp.browser_hijack import CDP_PORTS
# CDP_PORTS = [9333, 9222]
PORT = None
for port in CDP_PORTS:
    try:
        req = urllib.request.Request(f'http://localhost:{port}/json/version', timeout=3)
        with urllib.request.urlopen(req) as r:
            if r.status == 200: PORT = port; break
    except: pass
```

## Key Insight (from whypuss setup)
```
aipuss-br  PID xxx  →  localhost:58890  (AIpuss daemon WebSocket)
autocli    PID xxx  →  localhost:19925  (opencli-host Node.js)
Chromium   PID xxx  →  localhost:9333   (social-mcp's FacebookMCP profile)
Python     PID xxx  →  localhost:8899   (APK server)
```

## Architecture Reality Check
- **social-mcp** (Chromium port 9333) handles: Facebook, Instagram, Threads, **X.com search**
- **AIpuss-browser** daemon is running but may be idle/not needed for current workflows
- **Google Chrome for Testing** (port 63348) is NOT needed — social-mcp's Chromium covers X.com
- The **FacebookMCP profile** (`~/Library/Application Support/Chromium/FacebookMCP`) is the core asset — contains all login states

## Extension-free Insight
AutoCLI's Chrome Extension (Service Worker) is NOT needed. `--remote-debugging-port` directly exposes CDP. Any external tool (Python websocket, Playwright, Puppeteer) can connect directly. This is how social-mcp works — it does NOT load AutoCLI Extension.

---

# CDP Anti-Flood & Anti-Detection Rules (LEARNED THE HARD WAY)

## Why This Matters
Flooding CDP with rapid commands crashes the Chromium CDP server thread, blocking ALL connections. Rate-limit triggering gets accounts banned. These are NOT edge cases — they are the DEFAULT failure mode if you optimize for speed.

## The Core Rule: CDP ≠ Fast API
CDP is a browser automation protocol, not a high-throughput API. Treat it like a human using a browser.

### DO: Single JS Injection for Text
```python
# CORRECT — one CDP call, done
expr = 'document.querySelector("textarea").innerText = "text here"; document.querySelector("textarea").dispatchEvent(new Event("input", {bubbles:true}));'
await cdp.ws.send(json.dumps({"id":1,"method":"Runtime.evaluate","params":{"expression":expr}}))
```
### DON'T: Character-by-Character Key Events
```python
# WRONG — 200 chars × 2 (keyDown+keyUp) = 400 CDP calls = renderer overload
for ch in text:
    await cdp.ws.send(json.dumps({"id":i,"method":"Input.dispatchKeyEvent",...}))
    await asyncio.sleep(0.02)  # Still too fast!
```
Result: CDP server thread blocks, ALL connections lost, account session potentially dead.

### DO: Human Typing Pacing (if you must simulate typing)
```python
# If text injection doesn't work (React-controlled divs), use 0.15-0.2s between chars
# This simulates real human typing speed (~40-60 WPM)
for ch in text:
    await cdp.ws.send(json.dumps({"id":i,"method":"Input.dispatchKeyEvent",...}))
    await asyncio.sleep(0.15)  # Human speed
```
But prefer JS injection first — it's more reliable and faster.

## Pacing Rules
| Action | Wait After | Retry Wait |
|--------|-----------|------------|
| Click button | 2-3 seconds | 30+ seconds |
| Page navigation | 3-5 seconds | 60+ seconds |
| Dialog open | 3 seconds | Stop (don't re-open) |
| Upload file | 4 seconds | 30+ seconds |

## Anti-Detection Rules
1. **Never open/close/reopen a dialog** — pick one path and commit. Reopening the same dialog repeatedly = instant rate-limit trigger
2. **Max 3 retry attempts per operation** — if it fails 3 times, redesign the approach, don't keep hammering
3. **Max ~6 browser tabs** — more causes Chromium instability
4. **Never kill Chromium process** — `pkill -f Chromium` or closing the main window orphans all renderers and kills CDP access. If Chromium crashes, you lose the session.
5. **One platform at a time for complex flows** — don't parallel-bomb the same CDP server with 3 subagents simultaneously

## If CDP Connection is Lost
- Check if main Chromium process is still alive: `ps aux | grep "Chromium.app/Contents/MacOS/Chromium" | grep -v grep`
- If main process is gone but renderers exist: renderer CPU will be 100%+ (processing stalled requests) but no CDP available
- If CDP HTTP returns empty (0 bytes): CDP server thread is blocked, wait 60+ seconds
- Resolution: Chromium must be restarted with same `--user-data-dir` to restore session state

## Chromium Process Rules
- **NEVER** `pkill -f Chromium` or `kill <pid>` — this kills the main process and orphans renderers
- **NEVER** close the Chromium window directly — use CDP's `Page.close()` on individual tabs
- If Chromium needs restart: restart with same `--user-data-dir` flag to preserve login sessions
- Default user-data-dir for social-mCP: `~/Library/Application Support/Chromium/FacebookMCP`
