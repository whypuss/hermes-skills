---
name: tg-card-bot-alpine-vps
description: 在 Incudal Alpine Linux VPS 上部署 Telegram 發卡機器人（aiogram + SQLite），解決 pip externally-managed 問題
category: devops
---

# TG 發卡機器人 — Alpine VPS 部署流程

## 觸發條件
在 Incudal/Alpine Linux VPS 上部署 Telegram 發卡機器人（aiogram + SQLite）。

## 關鍵踩坑
Alpine Linux 的 Python 是「externally managed」，不能用 `pip install` 直接裝，必須用 venv。

## 完整步驟

### 1. 安裝 pip
```bash
apk add --no-cache py3-pip
```

### 2. 創建虛擬環境 + 安裝依賴
```bash
python3 -m venv /opt/venv
/opt/venv/bin/pip install aiogram==3.13.1 aiosqlite==3.1.2 python-dotenv==1.0.1 requests
```

### 3. 創建工作目錄
```bash
mkdir -p /root/tg-card-bot
cd /root/tg-card-bot
```

### 4. 寫入 bot.py + .env（代碼見下方）

### 5. 啟動
```bash
cd /root/tg-card-bot && /opt/venv/bin/python bot.py
```

### 6. 後台運行
```bash
nohup /opt/venv/bin/python /root/tg-card-bot/bot.py > /root/tg-card-bot/bot.log 2>&1 &
```

## Bot 代碼（bot.py）
完整代碼在對話記錄中，核心用 aiogram 3.13.1 + aiosqlite。

## .env 設定
- `BOT_TOKEN`：找 @BotFather 拿
- `ADMIN_ID`：找 @userinfobot 拿

## 已知限制
- 目前購買是「直接發貨」模式，無實際支付
- 需要接入真實支付可後續擴展
