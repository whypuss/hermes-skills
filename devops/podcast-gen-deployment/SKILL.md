---
name: podcast-gen-deployment
description: Deploy Vue UI + FastAPI backend for mobile access via TailScale using pure Python serve.py proxy
category: devops
---

# Podcast Gen — serve.py + TailScale Mobile Deployment

## Context
Vue UI (Vite build) + FastAPI backend. macOS runs both.
Mobile (Android/iOS) needs to access via TailScale.

## Problem
Node.js `vite` dev server binds to `utun` interface on macOS, making it unreachable from mobile via TailScale IP. Mobile browsers see white screen or "cannot connect".

## Solution
Use pure Python HTTP server (`serve.py`) as proxy/static file server on port 5174. It works reliably over TailScale because Python binds to `0.0.0.0`.

## Architecture
```
Mobile (Android/iOS)
  → http://100.77.249.63:5174 (serve.py)
    → /models/*, /generate/*  → proxy to http://127.0.0.1:8765 (FastAPI)
    → /*.{js,css,html}         → static files from dist/
```

## Backend (port 8765) — Quick Commands
```bash
# Kill backend
kill $(lsof -ti :8765) 2>/dev/null

# Restart backend (model loads in background thread, server accepts requests immediately)
cd ~/.kimaki/projects/podcast-gen/backend && .venv-tts/bin/python -m uvicorn main:app --port 8765 --host 0.0.0.0 &
# Or with uv:
cd ~/.kimaki/projects/podcast-gen/backend && uv run python -m uvicorn main:app --port 8765 --host 0.0.0.0 &
```

## Backend Startup — Background Model Loading
## TTS Engine
**qwen3 tts**（Qwen TTS），不是 SherpaTTS。代碼：
```python
from qwen3_tts_engine import Qwen3TTSEngine, get_engine
```

main.py uses FastAPI `lifespan` event with a daemon thread to load the model. Server accepts requests immediately while model downloads (~40s on first run).

```python
@asynccontextmanager
async def lifespan(app: FastAPI):
    def _load():
        try:
            eng = get_engine(device="cpu", dtype=torch.float32)
            log.info(f"[Startup] 模型已就緒: {eng.is_loaded}")
        except Exception as e:
            log.error(f"[Startup] 模型加載失敗: {e}")

    thread = threading.Thread(target=_load, daemon=True)
    thread.start()
    log.info("[Startup] 模型後台加載中，server 已就緒接受請求...")
    yield
    global _engine
    _engine = None

app = FastAPI(title="Podcast Gen API", version="2.0.0", lifespan=lifespan)
```

If server starts but `/models/status` returns "加載失敗", wait 40s and retry — model is downloading in background.
# Test backend directly
curl http://127.0.0.1:8765/health
curl http://127.0.0.1:8765/models/status
```

## Languages Supported
- **普通話 (mandarin)**: language="mandarin" → "Chinese"
- **粵語 (cantonese)**: language="cantonese" → "Chinese" + tone="用標準粵語（廣東話）說話，語氣親切自然"
  - Cantonese uses instruct-based tone control; instruct is injected in `main.py` generate loop

## serve.py Key Code

```python
# serve.py — Pure Python static file server + API proxy
PORT = 5174
DIST_DIR = Path(__file__).parent / "dist"
API_BASE = "http://127.0.0.1:8765"
API_PATHS = ("/generate", "/models", "/health", "/download", "/api/")

class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        # Pass directory explicitly to parent — fixes 404 on subpaths
        super().__init__(*args, directory=str(DIST_DIR), **kwargs)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Max-Age", "86400")
        self.end_headers()

    def do_GET(self):
        if self.path.startswith(API_PATHS):
            self.proxy()
        else:
            super().do_GET()

    def do_POST(self):
        if self.path.startswith(API_PATHS):
            self.proxy()
        else:
            self.send_error(404, "Not Found")

    def proxy(self):
        target = API_BASE + self.path
        headers = {k: v for k, v in self.headers.items()
                   if k.lower() not in ("host", "connection")}
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length) if content_length > 0 else None
        req = urllib.request.Request(target, data=body, headers=headers, method=self.command)
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                response_body = resp.read()
                response_headers = dict(resp.headers)
                self.send_response(resp.status)
                for k, v in response_headers.items():
                    if k.lower() not in ("transfer-encoding", "connection"):
                        self.send_header(k, v)
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                if response_body:
                    self.wfile.write(response_body)
        except urllib.error.HTTPError as e:
            body = e.read() if e.fp else b""
            self.send_response(e.code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            if body:
                self.wfile.write(body)
        except Exception:
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(json.dumps({"error": str(ex)}).encode())
```

## Deployment Steps

```bash
# 1. Kill old servers
lsof -ti :5174 | xargs kill -9 2>/dev/null
lsof -ti :8765 | xargs kill -9 2>/dev/null
sleep 1

# 2. Build Vue UI
cd ~/.kimaki/projects/podcast-gen/vue-ui && npm run build

# 3. Start backend (model loads in background, server immediately ready)
cd ~/.kimaki/projects/podcast-gen/backend && .venv-tts/bin/python -m uvicorn main:app --port 8765 --host 0.0.0.0 > /tmp/podcast-backend.log 2>&1 &

# 4. Start serve.py
cd ~/.kimaki/projects/podcast-gen/vue-ui && python3 serve.py > /tmp/serve.log 2>&1 &

# 5. Wait ~40s for model to download, then verify
sleep 40 && curl http://127.0.0.1:8765/models/status
```

## Debug Commands

```bash
# Check server is running
lsof -i :5174

# Test API via proxy (local)
curl http://localhost:5174/models/status

# Test API via TailScale IP (from Mac)
curl http://100.77.249.63:5174/models/status

# Check TailScale
/Applications/Tailscale.app/Contents/MacOS/Tailscale status

# Kill server
lsof -ti :5174 | xargs kill -9
```

## TailScale Connection Issues
If mobile shows white screen:
1. Check `curl http://100.77.249.63:5174/models/status` from Mac — if fails, server is down
2. Check TailScale status — mobile device must show "online", not "offline"
3. Mobile needs to be connected to same TailScale network

## Pitfalls
- `directory` class attribute on `SimpleHTTPRequestHandler` doesn't work in Python 3.9+ — must pass `directory=` to `__init__` super()
- Port 5174 may be taken by previous process — always `kill -9` before restart
- API paths must start with items in `API_PATHS` tuple, exact prefix match
- serve.py can hang with no output (CLOSE_WAIT connection) — kill by PID, not port
- Two backend instances can run simultaneously (ports 8080 and 8765) — kill both before restart
- Android/iOS browsers kill fetch requests when screen is off — user must keep screen on during TTS generation
- Backend proxy timeout must be ≥ 300s (TTS generation takes 20-60s on CPU)
- Vue `generate()` timeout must be ≥ 120000ms (2min)
- Model first-load takes ~40s (downloading from HuggingFace). Backend accepts requests immediately via lifespan/threading. `/models/status` returns "加載失敗" during download — wait and retry.
