---
name: personomorphic-mcp
description: 擬人化瀏覽器控制 MCP — 視覺感知+行為混淆+狀態管理+安全隔離四層架構，解決 Web 自動化被檢測為機器人的問題
category: browser-automation
tags: [mcp, browser, automation, stealth, social-media]
created: 2026-04-27
---

# Personomorphic MCP — 精簡版

## 觸發條件
瀏覽器搜圖 + 下載圖片，標準 CDP 被 captcha 時使用

## 核心功能

### 1. search_images
打開瀏覽器搜圖，返回截圖
- `POST /search_images`
- Body: `{"query": "關鍵詞", "engine": "bing"}` (engine 可選 bing/google)
- 返回截圖路徑，讓你看到結果

### 2. download_image
下載圖片到本地（curl 偽造 referer 繞防盜鏈）
- `POST /download_image`
- Body: `{"url": "https://...", "filename": "可選"}`
- 保存到 `~/Downloads/mcp_images/`

### 3. click_image_result
點擊搜圖結果第 N 張圖（需你提供坐標）

## 啟動
```bash
cd ~/personomorphic-mcp
uv run python server.py
```

## 流程
1. Hermes 呼叫 `search_images` → 瀏覽器打開 Bing/Google 圖片搜尋
2. 返回截圖 → 你看到結果 → 告訴我下載哪張
3. 我呼叫 `download_image` 把圖片拉到本地

## 依賴
只有 FastAPI + uvicorn，無其他外來庫

### 實際專案結構
```
~/personomorphic-mcp/
├── server.py              # FastAPI 入口（port 8080）
├── aipuss_wrapper.py      # Rust AIpuss CLI 封裝
├── requirements.txt       # 依賴
└── tools/
    ├── vision.py          # 截圖+灰度+OpenCV模板匹配+EasyOCR
    ├── behavior.py        # S型曲線移動+高斯偏移σ=2+pyautogui
    ├── state.py          # 操作歷史deque+Session單例
    └── shield.py         # 白名單+滑動窗口頻率限制
```

### 啟動方式
```bash
cd ~/personomorphic-mcp
uv pip install -r requirements.txt  # 首次
uv run python server.py             # 啟動 server
```

### 驗證步驟
```bash
# 1. 健康檢查
curl http://localhost:8080/health

# 2. 截圖測試
curl -X POST http://localhost:8080/tools/screenshot \
  -H "Content-Type: application/json" \
  -d '{"scale": 0.5}'

# 3. 操作歷史
curl http://localhost:8080/tools/operation_history

# 4. 頻率限制狀態
curl http://localhost:8080/tools/shield_check \
  -X POST -H "Content-Type: application/json" \
  -d '{"operation": "click", "target": "test"}'
```

## 重要經驗（本次 session 學到）

### social-mcp Chromium 過載問題
- social-mcp Chromium 累積 20+ 頁面後 CDP 請求開始超時
- 徵兆：`playwright._impl._errors.TimeoutError: BrowserType.connect_over_cdp`
- 解決：手動重啟 `pkill -f "Chrome for Testing" && sleep 3`
- MCP tool `open_login_window()` 無法從這種狀態恢復，必須走 terminal kill

### Google Images captcha 根本原因
- social-mcp Chromium 的 JS 指紋被 Google 檢測為自動化工具
- 即使用 CDP 操縱也會觸發 captcha（Google 有看不見的 reCAPTCHA worker）
- 解決方案：換 Bing Images（已驗證可行）

### 依賴問題
- `pyautogui`、`pytweening` 不在 uv 默認環境，需單獨 `uv pip install`
- 首次 import 會卡住（pyautogui FAILSAFE 初始化），非阻塞

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
