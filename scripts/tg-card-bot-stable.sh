#!/bin/bash
set -e
echo "========== TG 發卡機器人 穩定版 v3 =========="

apk add --no-cache python3 py3-pip > /dev/null 2>&1
pip3 install requests python-dotenv --break-system-packages --quiet 2>/dev/null

mkdir -p /root/tg-card-bot

cat > /root/tg-card-bot/bot.py << 'PYEOF'
import os, sqlite3, time, random, requests
from dotenv import load_dotenv

load_dotenv()
TOKEN = os.getenv("BOT_TOKEN", "")
ADMIN_ID = int(os.getenv("ADMIN_ID", "0"))
DB = "/root/tg-card-bot/cards.db"

def get_db():
    conn = sqlite3.connect(DB, timeout=20)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    db = get_db()
    db.execute("CREATE TABLE IF NOT EXISTS products (id INTEGER PRIMARY KEY, name TEXT, price REAL, stock INTEGER, card TEXT)")
    db.execute("CREATE TABLE IF NOT EXISTS orders (id INTEGER PRIMARY KEY, uid INTEGER, pid INTEGER, ts TEXT)")
    db.commit()
    db.close()

def get_updates(offset=0):
    try:
        r = requests.get(
            f"https://api.telegram.org/bot{TOKEN}/getUpdates",
            params={"offset": offset, "timeout": 30},
            timeout=35
        )
        return r.json().get("result", [])
    except Exception as e:
        print(f"網絡錯誤: {e}")
        return []

def send(chat_id, text):
    try:
        requests.post(
            f"https://api.telegram.org/bot{TOKEN}/sendMessage",
            json={"chat_id": chat_id, "text": text},
            timeout=10
        )
    except:
        pass

init_db()
print(f"Bot 啟動，ADMIN_ID={ADMIN_ID}")

offset = 0
state = {}

while True:
    try:
        updates = get_updates(offset)
        for u in updates:
            offset = u["update_id"] + 1
            msg = u.get("message")
            if not msg or "chat" not in msg:
                continue

            cid = msg["chat"]["id"]
            text = msg.get("text", "").strip()

            # === 1. 取消 ===
            if text == "/cancel":
                state.pop(cid, None)
                send(cid, "✅ 已取消")
                continue

            # === 2. Admin 狀態機 ===
            if cid in state:
                s = state[cid]
                if s["step"] == "name":
                    state[cid] = {"n": text, "step": "price"}
                    send(cid, f"📦 {text}\n價格：")
                elif s["step"] == "price":
                    try:
                        state[cid] = {"n": s["n"], "p": float(text), "step": "stock"}
                        send(cid, "庫存：")
                    except:
                        send(cid, "❌ 請輸入數字")
                elif s["step"] == "stock":
                    try:
                        state[cid] = {"n": s["n"], "p": s["p"], "st": int(text), "step": "card"}
                        send(cid, "卡密（每行一組）：")
                    except:
                        send(cid, "❌ 請輸入整數")
                elif s["step"] == "card":
                    try:
                        db = get_db()
                        db.execute("INSERT INTO products (name,price,stock,card) VALUES (?,?,?,?)",
                                   (s["n"], s["p"], s["st"], text.strip()))
                        db.commit()
                        db.close()
                        send(cid, f"✅ 已添加！{s['n']} x{s['st']} ¥{s['p']}")
                    except Exception as e:
                        send(cid, f"❌ 錯誤：{e}")
                    del state[cid]
                continue

            # === 3. 指令 ===
            if text == "/start":
                send(cid, "👋 歡迎！\n發送數字 ID 購買，或發隨意文字看列表。")
            elif text == "/admin":
                if cid != ADMIN_ID:
                    send(cid, "❌ 無權限")
                else:
                    db = get_db()
                    ps = db.execute("SELECT * FROM products").fetchall()
                    db.close()
                    send(cid, "📦 商品：\n" + "\n".join(f"{p['id']}. {p['name']} x{p['stock']} ¥{p['price']}" for p in ps) if ps else "無商品")
            elif text.startswith("/add") and cid == ADMIN_ID:
                state[cid] = {"step": "name"}
                send(cid, "商品名稱：")
            elif text == "/stock" and cid == ADMIN_ID:
                db = get_db()
                ps = db.execute("SELECT * FROM products").fetchall()
                db.close()
                send(cid, "📦 庫存：\n" + "\n".join(f"{p['id']}. {p['name']}剩{p['stock']}" for p in ps) if ps else "無")
            elif text == "/orders" and cid == ADMIN_ID:
                db = get_db()
                os = db.execute("SELECT * FROM orders ORDER BY id DESC LIMIT 20").fetchall()
                db.close()
                send(cid, "📋 訂單：\n" + "\n".join(f"#{o['id']} uid:{o['uid']} pid:{o['pid']}" for o in os) if os else "無訂單")

            # === 4. 購買 ===
            elif text.isdigit():
                db = get_db()
                p = db.execute("SELECT * FROM products WHERE id=? AND stock>0", (int(text),)).fetchone()
                if p:
                    cards = [c for c in (p["card"] or "").split("\n") if c.strip()]
                    if cards:
                        card = cards.pop(0)
                        db.execute("UPDATE products SET stock=stock-1, card=? WHERE id=?", ("\n".join(cards), p["id"]))
                        db.commit()
                        send(cid, f"🎉 購買成功！\n\n📦 {p['name']}\n\n🔑 {card}")
                    else:
                        send(cid, "❌ 卡密格式錯誤")
                else:
                    send(cid, "❌ 商品不存在或無庫存")
                db.close()

            # === 5. 列表 ===
            else:
                db = get_db()
                ps = db.execute("SELECT * FROM products WHERE stock>0").fetchall()
                db.close()
                send(cid, "📦 商品：\n" + "\n".join(f"{p['id']}. {p['name']} ¥{p['price']}" for p in ps) if ps else "無商品")

        time.sleep(0.2)
    except Exception as e:
        print(f"Loop 錯誤: {e}")
        time.sleep(5)
PYEOF

echo "完成。"
echo ""
echo "啟動（後台）："
echo "nohup python3 /root/tg-card-bot/bot.py > /root/tg-card-bot/bot.log 2>&1 &"
