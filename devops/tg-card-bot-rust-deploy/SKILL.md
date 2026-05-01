---
name: tg-card-bot-rust-deploy
description: TG 發卡機器人 — Rust + teloxide 部署到 256MB Alpine VPS（開發機 Mac 編譯，上傳二進制運行）
category: devops
---

# TG Card Bot — Rust 部署到 256MB Alpine VPS

## 背景
Telegram 發卡機器人。最初用 Python requests 實現，在 OVH Alpine VPS (256MB RAM, HDD) 上因 Long Polling timeout 過短、SQLite 鎖死、狀態機優先級等問題始終無法穩定運行。最後用 Rust + teloxide + sqlx 重寫，編譯成 3.3MB 靜態二進制，內存佔用極低。

## 環境
- 開發機：Mac（已有 Rust 1.94+）
- 目標機：Incudal Alpine Linux VPS，256MB RAM，無 Rust 編譯環境
- Bot Token：`8220575198:AAEJK-9BNBIW1qnshUeF4amAisUHPEbiwBA`
- Admin ID：`1120349178`

## 項目結構（開發機）
```
~/tg-card-bot-rust/
├── Cargo.toml
├── src/main.rs
├── .env
└── target/release/card_bot  ← 編譯好的二進制
```

## 快速開始

### 1. 開發機：編譯
```bash
cd ~/tg-card-bot-rust
cargo build --release
# 輸出：target/release/card_bot（3.3MB）
```

### 2. 上傳到 VPS
```bash
scp target/release/card_bot root@149.56.18.147:/root/tg-card-bot/
scp .env root@149.56.18.147:/root/tg-card-bot/
```

### 3. VPS：部署
```bash
cd /root/tg-card-bot
chmod +x card_bot
nohup ./card_bot > bot.log 2>&1 &
tail -f bot.log
```

### 4. 停止/重啟
```bash
pkill card_bot
nohup ./card_bot > bot.log 2>&1 &
```

## Bot 命令
| 命令 | 用戶 | 說明 |
|------|------|------|
| /start | 所有人 | 歡迎訊息 |
| /admin | Admin | 商品列表 |
| /stock | Admin | 庫存列表 |
| /orders | Admin | 最近 20 筆訂單 |
| /add 商品名 | Admin | 新增商品引導流程 |
| /cancel | Admin | 取消當前新增流程 |
| 數字 ID | 所有人 | 購買 |
| 其他文字 | 所有人 | 查看商品列表 |

## Cargo.toml
```toml
[package]
name = "card_bot"
version = "0.1.0"
edition = "2021"

[dependencies]
teloxide = { version = "0.13", features = ["macros"] }
sqlx = { version = "0.8", features = ["runtime-tokio-rustls", "sqlite"] }
tokio = { version = "1", features = ["rt-multi-thread", "macros"] }
dotenv = "0.15"

[profile.release]
opt-level = "z"
lto = true
codegen-units = 1
strip = true
```

## 常見錯誤與解決

### Python 版問題（已放棄）
- `timeout=1` 太短導致 Bot 不停 sleep(5)：改用 `timeout=30`（Long Polling）
- SQLite `database is locked`：加 `timeout=20` 參數
- Admin ID 不匹配：.env 中 `ADMIN_ID=` 不能有空格
- 狀態機卡死：加 `/cancel`，狀態機邏輯放在一般指令之前

### Rust 版注意
- `UserId` 是 `u64`，HashMap key 要用 `i64`（`.id.0 as i64`）
- `tokio::sync::Mutex` 而非 `std::sync::Mutex`（跨 await 需要 Send）
- 狀態機取 step 時要先 `remove`，釋放鎖再處理，避免 double borrow
- `.env` 文件要放在運行目錄（`/root/tg-card-bot/`）

## 更新流程
1. 開發機修改代碼 → `cargo build --release`
2. `scp target/release/card_bot root@149.56.18.147:/root/tg-card-bot/`
3. VPS：`pkill card_bot && nohup ./card_bot > bot.log 2>&1 &`
