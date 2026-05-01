#!/bin/bash
set -e
echo "========== TG 發卡機器人 一鍵搭建 =========="

# 1. 安裝依賴
echo "[1/5] 安裝系統依賴..."
apk add --no-cache python3 py3-pip wget

# 2. 創建 venv
echo "[2/5] 創建 Python 虛擬環境..."
python3 -m venv /opt/venv

# 3. 安裝 Python 庫
echo "[3/5] 安裝 Python 庫..."
/opt/venv/bin/pip install --quiet aiogram==3.13.1 aiosqlite==3.1.2 python-dotenv==1.0.1

# 4. 創建 bot 目錄
echo "[4/5] 創建 Bot 文件..."
mkdir -p /root/tg-card-bot

cat > /root/tg-card-bot/bot.py << 'PYEOF'
import asyncio, aiosqlite, os, random
from aiogram import Bot, Dispatcher, F
from aiogram.types import Message, InlineKeyboardMarkup, InlineKeyboardButton
from aiogram.filters import Command
from dotenv import load_dotenv

load_dotenv()
BOT_TOKEN = os.getenv("BOT_TOKEN", "")
ADMIN_ID = int(os.getenv("ADMIN_ID", "0"))
bot = Bot(token=BOT_TOKEN)
dp = Dispatcher()
DB_PATH = "/root/tg-card-bot/cards.db"

async def init_db():
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute("CREATE TABLE IF NOT EXISTS products (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, price REAL, stock INTEGER, description TEXT, card_content TEXT, category TEXT DEFAULT '軟件')")
        await db.execute("CREATE TABLE IF NOT EXISTS orders (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER, product_id INTEGER, paid INTEGER DEFAULT 0, created_at TEXT)")
        await db.commit()

async def get_products(category=None):
    async with aiosqlite.connect(DB_PATH) as db:
        if category:
            return await (await db.execute("SELECT id,name,price,stock,description FROM products WHERE category=? AND stock>0", (category,))).fetchall()
        return await (await db.execute("SELECT id,name,price,stock,description FROM products WHERE stock>0")).fetchall()

async def get_product(pid):
    async with aiosqlite.connect(DB_PATH) as db:
        return await (await db.execute("SELECT id,name,price,stock,description,card_content FROM products WHERE id=?", (pid,))).fetchone()

async def deduct_stock(pid):
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute("UPDATE products SET stock=stock-1 WHERE id=? AND stock>0", (pid,))
        await db.commit()

AW = {}

def menu_kb():
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="📦 軟件", callback_data="cat_軟件"), InlineKeyboardButton(text="⭐ 會員訂閱", callback_data="cat_會員訂閱")],
        [InlineKeyboardButton(text="🛒 所有商品", callback_data="all_products")],
    ])

@dp.message(Command("start"))
async def s(m): await init_db(); await m.answer("👋 歡迎！選分類：", reply_markup=menu_kb())

@dp.message(Command("admin"))
async def a(m):
    if m.from_user.id != ADMIN_ID: await m.answer("❌"); return
    await m.answer("📦 /add 新增 | /stock 庫存 | /orders 訂單")

@dp.message(Command("add"))
async def ad(m):
    if m.from_user.id != ADMIN_ID: return
    AW[m.from_user.id] = {"s":"name"}; await m.answer("商品名稱：")

@dp.message(Command("stock"))
async def st(m):
    if m.from_user.id != ADMIN_ID: return
    ps = await get_products()
    await m.answer("📦 庫存：\n" + "\n".join(f"{p[0]}. {p[1]} x{p[3]} ¥{p[2]}" for p in ps) if ps else "無商品")

@dp.message(Command("orders"))
async def o(m):
    if m.from_user.id != ADMIN_ID: return
    async with aiosqlite.connect(DB_PATH) as db:
        rs = await db.execute_fetchall("SELECT id,user_id,product_id,paid,created_at FROM orders ORDER BY id DESC LIMIT 20")
    await m.answer("\n".join(f"#{r[0]} uid:{r[1]} pid:{r[2]} paid:{r[3]}" for r in rs) if rs else "無訂單")

@dp.message()
async def h(m):
    uid = m.from_user.id
    if uid != ADMIN_ID or uid not in AW: return
    s = AW[uid]
    if s["s"] == "name": AW[uid] = {"s":"price", "n":m.text}; await m.answer(f"📦 {m.text}\n價格：")
    elif s["s"] == "price":
        try: AW[uid] = {"s":"stock","n":s["n"],"p":float(m.text)}; await m.answer("庫存：")
        except: await m.answer("❌ 數字")
    elif s["s"] == "stock":
        try: AW[uid] = {"s":"card","n":s["n"],"p":s["p"],"st":int(m.text)}; await m.answer("卡密（每行一組）：")
        except: await m.answer("❌ 整數")
    elif s["s"] == "card":
        async with aiosqlite.connect(DB_PATH) as db:
            await db.execute("INSERT INTO products (name,price,stock,card_content) VALUES (?,?,?,?)",(s["n"],s["p"],s["st"],m.text.strip()))
            await db.commit()
        await m.answer(f"✅ 已添加！{s['n']} x{s['st']} @ ¥{s['p']}")
        del AW[uid]

@dp.callback_query(F.data == "back_menu")
async def bm(c): await c.message.edit_text("👋 選分類：", reply_markup=menu_kb())

@dp.callback_query(F.data == "all_products")
async def ap(c):
    ps = await get_products()
    if not ps: await c.answer("📦 無商品", show_alert=True); return
    kb = [[InlineKeyboardButton(text=f"{p[1]} ¥{p[2]}", callback_data=f"buy_{p[0]}")] for p in ps]
    kb.append([InlineKeyboardButton(text="◀️", callback_data="back_menu")])
    await c.message.edit_text("🛒 所有商品：\n" + "\n".join(f"{p[0]}. {p[1]} ¥{p[2]} (剩{p[3]})" for p in ps), reply_markup=InlineKeyboardMarkup(inline_keyboard=kb))

@dp.callback_query(F.data.in_(["cat_軟件","cat_會員訂閱"]))
async def cc(c):
    ps = await get_products(c.data.replace("cat_",""))
    if not ps: await c.answer("📦 無此類商品", show_alert=True); return
    kb = [[InlineKeyboardButton(text=f"{p[1]} ¥{p[2]}", callback_data=f"buy_{p[0]}")] for p in ps]
    kb.append([InlineKeyboardButton(text="◀️", callback_data="back_menu")])
    await c.message.edit_text(f"{c.data.replace('cat_','')}：\n" + "\n".join(f"{p[0]}. {p[1]} ¥{p[2]} (剩{p[3]})" for p in ps), reply_markup=InlineKeyboardMarkup(inline_keyboard=kb))

@dp.callback_query(F.data.startswith("buy_"))
async def b(c):
    p = await get_product(int(c.data.replace("buy_","")))
    if not p: await c.answer("❌ 不存在", show_alert=True); return
    kb = InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text=f"✅ 購買 ¥{p[2]}", callback_data=f"pay_{p[0]}")],[InlineKeyboardButton(text="◀️", callback_data="back_menu")]])
    await c.message.edit_text(f"📦 {p[1]}\n💰 ¥{p[2]}\n📊 庫存：{p[3]}\n\n{p[4] or '點確認購買'}", reply_markup=kb)

@dp.callback_query(F.data.startswith("pay_"))
async def p(c):
    pid = int(c.data.replace("pay_","")); uid = c.from_user.id
    p = await get_product(pid)
    if not p or p[3] <= 0: await c.answer("❌ 庫存不足", show_alert=True); return
    await deduct_stock(pid)
    cards = [c for c in (p[5] or "").split("\n") if c.strip()]
    card = random.choice(cards) if cards else "请联系客服"
    await bot.send_message(uid, f"🎉 購買成功！\n\n📦 {p[1]}\n\n🔑 {card}", parse_mode="HTML")
    from datetime import datetime
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute("INSERT INTO orders (user_id,product_id,paid,created_at) VALUES (?,?,1,?)",(uid,pid,datetime.now().isoformat())); await db.commit()
    await c.answer("✅ 成功！")

async def main():
    await init_db()
    print("🤖 Bot 啟動")
    await dp.start_polling(bot)

if __name__ == "__main__": asyncio.run(main())
PYEOF

cat > /root/tg-card-bot/.env << 'ENVEOF'
BOT_TOKEN=你的BOT_TOKEN
ADMIN_ID=你的TG用戶ID
ENVEOF

echo "[5/5] 完成！"
echo ""
echo "=========================================="
echo "下一步："
echo "1. nano /root/tg-card-bot/.env"
echo "   替換 BOT_TOKEN 和 ADMIN_ID"
echo ""
echo "2. 啟動Bot："
echo "   cd /root/tg-card-bot && /opt/venv/bin/python bot.py"
echo ""
echo "3. 後台運行："
echo "   nohup /opt/venv/bin/python bot.py > bot.log 2>&1 &"
echo ""
echo "=========================================="
