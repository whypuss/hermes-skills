---
name: personomorphic-mcp
description: 擬人化瀏覽器控制 MCP — 視覺感知+行為混淆+狀態管理+安全隔離四層架構，解決 Web 自動化被檢測為機器人的問題
category: browser-automation
tags: [mcp, browser, automation, stealth, social-media]
created: 2026-04-27
---

# Personomorphic Browser MCP — 擬人化瀏覽器控制

## 觸發條件
- 需要自動化操作 Web 界面但標準 CDP/Playwright 被檢測為機器人
- 需要「人類化」的操作軌跡、指紋、行爲模式
- 任務包括：社交媒體發文、資料抓取、頁面交互

## 核心架構：四層模型

```
┌─────────────────────────────────────────────┐
│  Hermes Agent (意圖下達者)                   │
│  "去 Facebook 發佈這張圖"                    │
└──────────────────┬────────────────────────┘
                   │ MCP Tool Call
┌──────────────────▼────────────────────────┐
│  A. 視覺感知層 (The Eyes)                  │
│  - get_screenshot (縮放+灰度+坐標標註)      │
│  - find_element (模板匹配/OpenCV)           │
│  - ocr_read (EasyOCR 本地文字識別)           │
└──────────────────┬────────────────────────┘
                   │
┌──────────────────▼────────────────────────┐
│  B. 行為混淆層 (The Muscle Memory)          │
│  - humanoid_move(x, y) [S型曲線+高斯偏移]   │
│  - humanoid_click(label) [先感知後移動]     │
│  - humanoid_type(text) [非線性打字間隔]     │
│  - random_human_delay() [500ms-2000ms]     │
└──────────────────┬────────────────────────┘
                   │
┌──────────────────▼────────────────────────┐
│  C. 狀態管理層 (The Brain)                 │
│  - get_system_state() [窗口/焦點/上下文]     │
│  - operation_history [最近N次操作記錄]       │
│  - session_context [登入狀態/Cookies]       │
└──────────────────┬────────────────────────┘
                   │
┌──────────────────▼────────────────────────┐
│  D. 安全隔離層 (The Shield)                │
│  - whitelist [白名單網址/操作]               │
│  - sensitive_ops [需二次確認的危險操作]     │
│  - rate_limiter [頻率限制保護]              │
└─────────────────────────────────────────────┘
```

## 技術棧

| 層 | 工具 | 備註 |
|----|------|------|
| MCP Server | FastAPI + mcp-sdk | 與 Hermes 通訊 |
| 視覺感知 | Pillow, OpenCV, EasyOCR | 本地 OCR，不需網路 |
| 行為模擬 | pytweening, pyautogui, pynput | 曲線移動+隨機偏移 |
| 執行引擎 | AIpuss-browser (Rust) | 高性能 Chromium 控制 |
| 狀態儲存 | SQLite / Dexie | 操作歷史+Session |

## 實作階段

### Phase 1: MCP Server 骨架
```bash
# 專案位置
~/personomorphic-mcp/

# 依賴
pip install fastapi uvicorn mcp python-pptx pillow opencv-python pytweening pyautogui easyocr
```

### Phase 2: 核心工具實作順序

#### Step 1: get_screenshot
```python
@mcp.tool()
def get_screenshot(scale: float = 0.5) -> str:
    """截圖並標註坐標系。scale=0.5 減少 token 消耗"""
    # 1. 全屏截圖
    # 2. 縮放 + 灰度處理
    # 3. 保存並返回路徑
```

#### Step 2: humanoid_click(label: str)
```python
async def humanoid_click(label: str):
    """先用視覺模型找到 label 位置，再 S型移動+隨機偏移，最後點擊"""
    # 1. find_element(label) → (x, y)
    # 2. 計算 S 型曲線路徑 (pytweening)
    # 3. 加入高斯隨機偏移 σ=2
    # 4. pyautogui.moveTo + click
```

#### Step 3: humanoid_type(text: str)
```python
async def humanoid_type(text: str):
    """模擬人手打字，每字符間隔 0.1s + random(-0.05, 0.1)"""
    for char in text:
        pyautogui.typewrite(char)
        delay = 0.1 + random.uniform(-0.05, 0.1)
        await asyncio.sleep(delay)
```

#### Step 4: observe_and_act 循環
```python
async def observe_and_act(instruction: str, max_retries: int = 3):
    """Hermes 下達意圖 → 截圖解析畫面 → 決策 → 執行"""
    for attempt in range(max_retries):
        screenshot = get_screenshot()
        # 用視覺模型分析當前畫面
        analysis = await vision_model.analyze(screenshot, instruction)
        if analysis["ready"]:
            await execute_action(analysis["action"])
        else:
            await humanoid_delay()
```

### Phase 3: 整合 AIpuss-browser (Rust)
MCP Server 通過 CLI/API 調用 Rust 二進制：
```bash
# MCP 發送命令
subprocess.run(["./target/release/aipuss", "goto", "https://instagram.com"])
subprocess.run(["./target/release/aipuss", "click", "#username"])
subprocess.run(["./target/release/aipuss", "type", "mytext"])
```

## 與現有 social-mcp 的差異

| 維度 | social-mcp (現有) | personomorphic-mcp (新建) |
|------|------------------|--------------------------|
| 瀏覽器控制 | CDP 遙控已有 Chromium | 自建隔離 Chromium 實例 |
| 移動軌跡 | 瞬間直線 (被檢測) | S型曲線+高斯偏移 |
| 打字速度 | 固定間隔 | 人類隨機間隔 |
| 截圖處理 | 無 | 縮放+灰度+坐標標註 |
| 狀態追蹤 | 無 | 完整上下文記錄 |
| 頻率限制 | 無 | MCP 內部 rate limiter |
| 依賴現況 | 依賴外部 Chromium 狀態 | 完全自包含 |

## 初始目標任務

1. **IG/Threads 圖文發文** — 取代 social-mcp 的 IG posting（解決 captcha 問題）
2. **Google Images 搜圖** — 通過 humanoid 行爲繞過 captcha
3. **Facebook 自動回覆** — 監控 Messenger 並按規則回覆

## 當前任務：Phase 1 骨架

首先在 `~/personomorphic-mcp/` 建立專案結構：
```
personomorphic-mcp/
├── server.py              # FastAPI + MCP 入口
├── tools/
│   ├── vision.py          # 視覺感知層
│   ├── behavior.py        # 行為混淆層
│   ├── state.py           # 狀態管理層
│   └── shield.py          # 安全隔離層
├── aipuss_wrapper.py      # 調用 Rust AIpuss
├── requirements.txt
└── README.md
```

## 驗證步驟

1. `python server.py` 啟動成功，port 8080
2. `get_screenshot` 返回標註過的截圖
3. `humanoid_type` 在文字框輸入，無 captcha
4. 觀察 Chromium 的 JS 指紋不再被檢測為自動化工具
