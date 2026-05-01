---
name: tg-card-bot-alpine-vps
description: 在 Incudal Alpine Linux VPS 上部署 Telegram 發卡機器人（aiogram + SQLite），解決 pip externally-managed 問題
category: devops
---

# TG 發卡機器人 - Alpine VPS 部署流程

## 背景
在 Incudal Alpine Linux VPS（256MB RAM，無 GPU）上部署 Telegram 發卡機器人（軟件 + 會員訂閱）。

---

## 踩坑記錄（真機實測）

### 1. SSH 連接
- IP: `149.56.18.147`，Port: `22`
- 預設只接受 SSH Key 登入，不接受密碼
- 用戶需通過雲後台（Incudal web console）開通密碼登入

### 2. Alpine Linux 特性
- **沒有 curl**，只有 wget
- **PEP 668**: Python externally-managed，直接 pip install 會被拒絕
  - 解法: `pip3 install ... --break-system-packages`
  - venv 方式也可：`python3 -m venv /opt/venv && /opt/venv/bin/pip install ...`

### 3. aiosqlite 不存在
- Alpine 的 PyPI 中 aiosqlite 最新是 `0.22.1`（不是 3.1.2）
- **解法**: 用 Python 內建 `sqlite3`

### 4. 成功部署案例（2025-05-01）
- **Bot Token**: `8220575198:AAEJK-9BNBIW1qnshUeF4amAisUHPEbiwBA`
- **Admin ID**: `1120349178`
- **VPS**: Incudal Alpine，149.56.18.147，256MB RAM
- **部署方式**：wget 下載 `tg-card-bot-deploy.sh` → 直接運行 → nano 改配置 → nohup 後台啟動
- **記憶體佔用**：約 30MB（requests + sqlite3，無 async）

### 5. ⚠️ 256MB RAM 不够用 aiogram（關鍵！）
- aiogram + aiohttp 在 256MB 上會記憶體不足崩潰（RuntimeError 或 Killed）
- **解法**: 棄用 aiogram，改用極簡方案：`requests` + 內建 `sqlite3` + `time.sleep` 輪詢
  - 不需要 async/await
  - 不需要 aiohttp / aiogram
  - 記憶體佔用極小，256MB 完全够用
  - 輕量版腳本：`scripts/tg-card-bot-light.sh`
  ```bash
  wget -O /tmp/light.sh https://raw.githubusercontent.com/whypuss/hermes-skills/main/scripts/tg-card-bot-light.sh && chmod +x /tmp/light.sh && bash /tmp/light.sh
  ```

## 完整步驟（輕量版 — 256MB RAM 首選）

### 1. 一鍵腳本
```bash
wget -O /tmp/d.sh https://raw.githubusercontent.com/whypuss/tg-card-bot/main/scripts/tg-card-bot-deploy.sh && bash /tmp/d.sh
```

### 2. 配置 Token
```bash
nano /root/tg-card-bot/.env
# 填入 BOT_TOKEN 和 ADMIN_ID
```

### 3. 啟動
```bash
cd /root/tg-card-bot && nohup python3 bot.py > bot.log 2>&1 &
```

### 4. 查看日誌
```bash
tail -f /root/tg-card-bot/bot.log
```

### 5. 殺掉舊進程（如需重啟）
```bash
pkill -f bot.py && sleep 1 && cd /root/tg-card-bot && nohup python3 bot.py > bot.log 2>&1 &
```

### 7. Rust 版部署失敗記錄（不要在這台 VPS 嘗試）
- **Mac 交叉編譯失敗**：Mac (aarch64-apple-darwin) → x86_64-unknown-linux-musl，rust-openssl-sys 找不到 OpenSSL（$HOST = aarch64-apple-darwin）
- **VPS 編譯 OOM**：Alpine 256MB RAM 裝 Rust + cargo build → OOM (Killed)，並且沒有 curl（只有 wget）
- **結論**：這台 VPS 只能跑 Python 輕量版

## Bot 代碼
- GitHub 倉庫：**https://github.com/whypuss/tg-card-bot**
- 輕量版腳本：`scripts/tg-card-bot-deploy.sh`（推薦，requests + sqlite3，無 async，256MB 够用）
- 直接 wget 部署：
```bash
wget -O /tmp/d.sh https://raw.githubusercontent.com/whypuss/tg-card-bot/main/scripts/tg-card-bot-deploy.sh && bash /tmp/d.sh
```

## 已知限制
- 目前購買是「直接發貨」模式，無實際支付集成
- 需要接入真實支付（支付寶/微信/加密貨幣）可後續擴展

## GitHub 倉庫
- https://github.com/whypuss/tg-card-bot
- 包含 bot.py（Light 版）+ 一鍵部署腳本

---

## 🔴 關鍵故障：Bot 收到消息但不回應（試錯記錄）

### 根因：timeout=1 太短
- getUpdates timeout=1 → 每秒發請求 → 超時馬上 sleep(5)
- Bot 98% 時間在 sleep，根本沒機會處理回覆
- 解決：**timeout=30**（Long Polling，Telegram 官方推薦）

### 根因：getUpdates 被其他客戶端消費
- 手動 curl/wget 查 API 時把 /start 消息消費掉了
- Bot 輪詢時 offset 已經跳過那條消息
- 解決：先清空積壓 `getUpdates?offset=-1`，然後馬上啟動 Bot，再發 /start

### 根因：DB 連線未 explicit close
- Alpine + HDD 環境，SQLite 文件鎖反應慢
- `with get_db()` 雖然有 GC，但 HDD 上不及時
- 解決：每次 `db.execute()` 後馬上 `db.close()`

### 根因：ADMIN_ID 類型匹配
- `.env` 讀進來是字串，轉 `int()` 後與 Telegram 回傳的 `cid` 比較
- 要確保兩邊都是 int

### 最終穩定版關鍵參數
| 參數 | 值 | 備註 |
|------|-----|------|
| getUpdates timeout | 30s | Long Polling，不是 1s |
| requests timeout | 35s | 比 Telegram 多 5s |
| sleep between loops | 0.2s | 不是 5s |
| sendMessage timeout | 10s | |
| DB close | 每次操作後 | 顯式 close() |

### 穩定版部署（一行）
```bash
wget -O /tmp/final.sh https://raw.githubusercontent.com/whypuss/hermes-skills/main/scripts/tg-card-bot-final.sh && bash /tmp/final.sh && cd /root/tg-card-bot && python3 bot.py
```
