---
name: tg-card-bot-alpine-vps
description: 在 Incudal Alpine Linux VPS（256MB RAM）上部署 Telegram 發卡機器人（requests + sqlite3，Light 版）
category: devops
---

# TG 發卡機器人 - Alpine VPS 部署流程

## 背景
- **平台**: Incudal Alpine Linux VPS，256MB RAM
- **Repo**: https://github.com/whypuss/tg-card-bot
- **技術棧**: Python requests + 內建 sqlite3，無 async，30MB 記憶體

---

## 踩坑實測記錄（2025-05-01 實戰）

### 1. wget 下載文件編碼損壞
- 症狀：`bot.py` 中的 `**` 變成亂碼，`sys` 變 `svs`
- 原因：Alpine wget 編碼問題
- 解決：用 Python 下載
```bash
python3 -c "import urllib.request; open('/root/tg-card-bot/bot.py','w',encoding='utf-8').write(urllib.request.urlopen('https://raw.githubusercontent.com/whypuss/tg-card-bot/main/bot.py').read().decode('utf-8'))"
```

### 2. dotenv 沒加載（BOT_TOKEN 一直是假的，404 Not Found）
- 必須：`from dotenv import load_dotenv` + `load_dotenv("/root/tg-card-bot/.env")`
- Alpine 需先：`pip3 install python-dotenv --break-system-packages`

### 3. callback_data 不匹配（按鈕無反應，日誌無錯誤）
- 原因：`product_kb` 返回 `"home"`，但 `handle_callback` 只判斷 `"list_all"`
- 解決：`if data in ("list_all", "home"):`

### 4. 數據庫缺欄位（Bot 崩潰，sqlite3.OperationalError）
- 新版代碼多了：`pay_addr`、`status`、`uname`、`pname`、`card`
- 舊資料庫需迁移，一次性補欄位：
```bash
python3 -c "
import sqlite3
conn = sqlite3.connect('/root/tg-card-bot/cards.db')
c = conn.cursor()
cols_p = [i[1] for i in c.execute('PRAGMA table_info(products)')]
if 'pay_addr' not in cols_p: c.execute('ALTER TABLE products ADD COLUMN pay_addr TEXT DEFAULT \"\"')
cols_o = [i[1] for i in c.execute('PRAGMA table_info(orders)')]
for col, dtype in [('status','pending'),('uname',''),('pname',''),('card','')]:
    if col not in cols_o: c.execute(f'ALTER TABLE orders ADD COLUMN {col} TEXT DEFAULT \"{dtype}\"')
conn.commit(); conn.close(); print('DONE')
"
```

### 5. edit_msg 內容不變被 Telegram 忽略
- 如果編輯後文字和原來完全一樣，Telegram 不會更新
- 按鈕看起來像「卡住」，但日誌無錯誤
- 解決：先用 `answer_cb` 回應確認，或編輯時稍微改動文字

### 6. 256MB RAM 不能跑
- Rust 編譯：OOM
- aiogram + aiohttp：OOM
- 只能用 `requests` + 內建 `sqlite3`，無 async
- `getUpdates timeout=30`，`sleep=0.3`

### 7. print lambda 覆蓋自己造成 RecursionError
- 錯誤代碼：`print = lambda *a,**kw: (print(*a,**kw), sys.stdout.flush())`
- 解決：改用普通函數 `def log(*a,**kw): print(*a,**kw); sys.stdout.flush()`

### 8. 舊訂單數據導致 "已有 pending 訂單"（用戶買不了）
- 解決：`UPDATE orders SET status='cancelled' WHERE status='pending'`

### 9. answerCallbackQuery 10秒超時
- Telegram 要求在 10s 內回應，否則 query 過期
- Long Polling 迴圈太慢會導致按鈕圈圈轉但無反應
- 解決：確保 `time.sleep(0.3)` 不是 `time.sleep(5)`

---

## 部署步驟（全新 VPS）

### 1. 安裝依賴
```bash
apk add --no-cache python3 py3-pip
pip3 install requests python-dotenv --break-system-packages
```

### 2. 下載並配置
```bash
mkdir -p /root/tg-card-bot
python3 -c "import urllib.request; open('/root/tg-card-bot/bot.py','w',encoding='utf-8').write(urllib.request.urlopen('https://raw.githubusercontent.com/whypuss/tg-card-bot/main/bot.py').read().decode('utf-8'))"

cat > /root/tg-card-bot/.env << 'EOF'
BOT_TOKEN=你的BOT_TOKEN
ADMIN_ID=你的TG用戶ID
EOF
```

### 3. 初始化數據庫欄位
```bash
python3 -c "
import sqlite3
conn = sqlite3.connect('/root/tg-card-bot/cards.db')
c = conn.cursor()
cols_p = [i[1] for i in c.execute('PRAGMA table_info(products)')]
if 'pay_addr' not in cols_p: c.execute('ALTER TABLE products ADD COLUMN pay_addr TEXT DEFAULT \"\"')
cols_o = [i[1] for i in c.execute('PRAGMA table_info(orders)')]
for col, dtype in [('status','pending'),('uname',''),('pname',''),('card','')]:
    if col not in cols_o: c.execute(f'ALTER TABLE orders ADD COLUMN {col} TEXT DEFAULT \"{dtype}\"')
conn.commit(); conn.close()
"
```

### 4. 啟動
```bash
cd /root/tg-card-bot && nohup python3 bot.py >> bot.log 2>&1 &
```

### 5. 重啟（如需）
```bash
pkill -9 -f bot.py && rm -f /root/tg-card-bot/cards.db-journal && nohup python3 /root/tg-card-bot/bot.py >> /root/tg-card-bot/bot.log 2>&1 &
```

---

## 常見日誌錯誤

| 日誌 | 原因 | 解決 |
|------|------|------|
| `no such column: pay_addr` | 缺欄位 | ALTER TABLE 補欄位 |
| `no such column: status` | 缺欄位 | ALTER TABLE 補欄位 |
| `404 Not Found` | BOT_TOKEN 假的 | 確認 .env 正確 + load_dotenv |
| `ADMIN=0` | dotenv 未加載 | 加 `from dotenv import load_dotenv` |
| `Network unreachable` | VPS 網絡問題 | `curl -I https://api.telegram.org` |
| `[收到 N個更新]` 但 Bot 無回應 | getUpdates 被其他客戶端消費 | 先 `getUpdates?offset=-1` 清空積壓 |
| 按鈕圈圈一直轉 | query 超時或 edit_msg 內容相同 | 加快輪詢或改文字 |

## 管理員指令
- `/start` - 主介面
- `/admin` - 商品列表
- `/stock` - 庫存
- `/orders` - 訂單
- `/add 名稱` - 逐步添加商品
- `/setprice ID 價格`
- `/setstock ID 數量`
- `/setaddr ID TRC20地址`
- 然後直接回复卡密內容（每行一組）
- `/cancel` - 取消當前操作
