---
name: fastapi-background-init
category: devops
description: FastAPI + uvicorn 同步加載大模型時，用 daemon thread + lifespan 後台加載，server 立即就緒接受請求。
---

# FastAPI 後台模型加載（不 block 啟動）

## 問題
FastAPI + uvicorn 同步加載大模型（如 Qwen3 TTS）時，單綫程被 block ~40 秒，導致 startup 完成前所有請求超時。

## 解決方案
使用 `lifespan` 事件 + `threading.Thread` daemon 後台加載，server 立即接受請求。

## 代碼

```python
import threading
from contextlib import asynccontextmanager
from fastapi import FastAPI

@asynccontextmanager
async def lifespan(app: FastAPI):
    """後台執行緒預加載模型，server 啟動後立即接受請求。"""
    def _load():
        try:
            eng = get_engine(device="cpu", dtype=torch.float32)
            log.info(f"[Startup] 模型已就緒: {eng.is_loaded}")
        except Exception as e:
            log.error(f"[Startup] 模型加載失敗: {e}")

    thread = threading.Thread(target=_load, daemon=True)
    thread.start()
    log.info("[Startup] 模型後台加載中，server 已就緒接受請求...")
    yield  # server 在此運行
    # shutdown
    global _engine
    _engine = None

app = FastAPI(lifespan=lifespan)
```

## 注意
- `daemon=True`：进程退出时不等待线程完成
- 模型加載完成後才接受需模型的請求（加載期間 `/health` 等基礎 endpoint 仍可響應）
- 確保 `get_engine()` 是綫程安全的（推薦單例模式）

## 調試技巧
- 模型首次加載約需 40s（HuggingFace 下載）。加載期間 `/models/status` 會返回 `{"loaded":false,"error":"..."}`——這是正常的，等待後重試即可
- 確認後台線程正常：`tail /tmp/podcast-backend.log` 看 `✅ 加載成功！` 日誌
- 如果模型一直報錯但綫程日志顯示成功，檢查 `get_engine()` 是否有綫程安全問題（全局 state 競爭）
