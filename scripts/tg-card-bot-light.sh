#!/bin/bash
set -e
echo "========== TG 發卡機器人 輕量版 一鍵搭建 =========="

echo "[1/4] 安裝系統依賴..."
apk add --no-cache python3 py3-pip wget

echo "[2/4] 安裝 Python 庫..."
pip3 install requests python-dotenv --break-system-packages --quiet

echo "[3/4] 創建 Bot 文件..."
mkdir -p /root/tg-card-bot

cat > /root/tg-card-bot/bot.py << 'PYEOF'
import os, sqlite3, time, random, requests
from dotenv import load_dotenv

load_dotenv()
TOKEN = os.getenv("BOT_TOKEN", "")
ADMIN_ID = int(os.getenv("ADMIN_ID", "0"))
DB = "/root/tg-card-bot/cards.db"

def get_db():
    c = sqlite3.connect(DB)
    c.row_factory = sqlite3.Row
    return c

def init_db():
    with get_db() as db:
        db.execute("CREATE TABLE IF NOT EXISTS products (id INTEGER PRIMARY KEY, name TEXT, price REAL, stock INTEGER, card TEXT)")
        db.execute("CREATE TABLE IF NOT EXISTS orders (id INTEGER PRIMARY KEY, uid INTEGER, pid INTEGER, ts TEXT)")
        db.commit()

def get_updates(offset=0):
    r = requests.get(f"https://api.telegram.org/bot{TOKEN}/getUpdates?offset={offset}&timeout=1", timeout=5)
    return r.json().get("result", [])

def send_message(chat_id, text):
    requests.post(f"https://api.telegram.org/bot{TOKEN}/sendMessage", json={"chat_id": chat_id, "text": text})

init_db()
print("Bot 啟動，開始輪詢...")

offset = 0
state = {}

while True:
    try:
        updates = get_updates(offset)
        for u in updates:
            offset = u["update_id"] + 1
            msg = u.get("message")
            if not msg:
                continue
            cid = msg["chat"]["id"]
            text = msg.get("text", "")

            if text == "/start":
                send_message(cid, "👋 歡迎！\n\n📦 軟件\n⭐ 會員訂閱\n🛒 所有商品\n\n直接發數字ID購買")
            elif text == "/admin":
                if cid != ADMIN_ID:
                    send_message(cid, "❌ 無權限")
                    continue
                ps = get_db().execute("SELECT * FROM products").fetchall()
                send_message(cid, "📦 商品：\n" + "\n".join(f"{p['id']}. {p['name']} x{p['stock']} ¥{p['price']}" for p in ps) if ps else "無商品")
            elif text.startswith("/add") and cid == ADMIN_ID:
                state[cid] = "name"
                send_message(cid, "商品名稱：")
            elif text == "/stock" and cid == ADMIN_ID:
                ps = get_db().execute("SELECT * FROM products").fetchall()
                send_message(cid, "📦 庫存：\n" + "\n".join(f"{p['id']}. {p['name']}剩{p['stock']}" for p in ps) if ps else "無")
            elif cid in state:
                s = state[cid]
                if s == "name":
                    state[cid] = {"n": text, "s": "price"}
                    send_message(cid, f"📦 {text}\n價格：")
                elif isinstance(s, dict) and s.get("s") == "price":
                    try:
                        state[cid] = {"n": s["n"], "p": float(text), "s": "stock"}
                        send_message(cid, "庫存：")
                    except:
                        send_message(cid, "❌ 數字")
                elif isinstance(s, dict) and s.get("s") == "stock":
                    try:
                        state[cid] = {"n": s["n"], "p": s["p"], "st": int(text), "s": "card"}
                        send_message(cid, "卡密（每行一組）：")
                    except:
                        send_message(cid, "❌ 整數")
                elif isinstance(s, dict) and s.get("s") == "card":
                    with get_db() as db:
                        db.execute("INSERT INTO products (name,price,stock,card) VALUES (?,?,?,?)", (s["n"], s["p"], s["st"], text.strip()))
                        db.commit()
                    send_message(cid, f"✅ 已添加！{s['n']} x{s['st']} ¥{s['p']}")
                    del state[cid]
            else:
                try:
                    pid = int(text)
                    with get_db() as db:
                        p = db.execute("SELECT * FROM products WHERE id=? AND stock>0", (pid,)).fetchone()
                    if p:
                        db.execute("UPDATE products SET stock=stock-1 WHERE id=?", (pid,))
                        db.commit()
                        cards = [c for c in (p["card"] or "").split("\n") if c.strip()]
                        card = random.choice(cards) if cards else "聯繫客服"
                        send_message(cid, f"🎉 購買成功！\n\n📦 {p['name']}\n\n🔑 {card}")
                    else:
                        send_message(cid, "❌ 商品不存在或無庫存")
                except:
                    ps = get_db().execute("SELECT * FROM products WHERE stock>0").fetchall()
                    send_message(cid, "📦 商品：\n" + "\n".join(f"{p['id']}. {p['name']} ¥{p['price']}" for p in ps) if ps else "無商品")
        time.sleep(1)
    except Exception as e:
        print(f"錯誤：{e}")
        time.sleep(5)
PYEOF

cat > /root/tg-card-bot/.env << 'ENVEOF'
BOT_TOKEN=你的BOT_TOKEN
ADMIN_ID=你的TG用戶ID
ENVEOF

echo "[4/4] 完成！"
echo ""
echo "=========================================="
echo "下一步："
echo "1. nano /root/tg-card-bot/.env 填入 TOKEN 和 ID"
echo "2. cd /root/tg-card-bot && python3 bot.py"
echo "=========================================="
