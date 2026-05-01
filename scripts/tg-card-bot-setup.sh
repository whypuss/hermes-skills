#!/bin/bash
set -e

echo "=========================================="
echo "  TG 發卡機器人一鍵搭建"
echo "=========================================="

# 檢測系統
if command -v python3 &>/dev/null; then
    PYTHON=python3
elif command -v python &>/dev/null; then
    PYTHON=python
else
    echo "[1/6] 安裝 Python3..."
    apk add --no-cache python3 py3-pip || apt-get update && apt-get install -y python3 python3-pip
fi

$PYTHON --version

echo "[2/6] 安裝依賴..."
pip3 install aiogram==3.13.1 aiosqlite==3.1.2 python-dotenv==1.0.1 --quiet

echo "[3/6] 創建工作目錄..."
BOTDIR="/root/tg-card-bot"
mkdir -p $BOTDIR && cd $BOTDIR

echo "[4/6] 寫入 Bot 代碼..."

cat > bot.py << 'PYEOF'
import asyncio
import aiosqlite
import os
from aiogram import Bot, Dispatcher, F
from aiogram.types import Message, InlineKeyboardMarkup, InlineKeyboardButton, FSInputFile
from aiogram.filters import Command
from dotenv import load_dotenv

load_dotenv()

BOT_TOKEN = os.getenv("BOT_TOKEN", "")
ADMIN_ID = int(os.getenv("ADMIN_ID", "0"))

bot = Bot(token=BOT_TOKEN)
dp = Dispatcher()

DB_PATH = "/root/tg-card-bot/cards.db"

# ---- 資料庫初始化 ----
async def init_db():
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute("""
            CREATE TABLE IF NOT EXISTS products (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                price REAL NOT NULL,
                stock INTEGER NOT NULL,
                description TEXT,
                card_content TEXT,
                category TEXT DEFAULT '軟件'
            )
        """)
        await db.execute("""
            CREATE TABLE IF NOT EXISTS orders (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER,
                product_id INTEGER,
                paid INTEGER DEFAULT 0,
                created_at TEXT
            )
        """)
        await db.commit()

# ---- 工具函數 ----
async def get_products(category=None):
    async with aiosqlite.connect(DB_PATH) as db:
        if category:
            rows = await db.execute(
                "SELECT id,name,price,stock,description FROM products WHERE category=? AND stock>0",
                (category,)
            )
        else:
            rows = await db.execute(
                "SELECT id,name,price,stock,description FROM products WHERE stock>0"
            )
        return await rows.fetchall()

async def get_product(pid):
    async with aiosqlite.connect(DB_PATH) as db:
        row = await db.execute(
            "SELECT id,name,price,stock,description,card_content FROM products WHERE id=?",
            (pid,)
        )
        return await row.fetchone()

async def deduct_stock(pid):
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute("UPDATE products SET stock=stock-1 WHERE id=? AND stock>0", (pid,))
        await db.commit()

# ---- 用戶按鈕 ----
def main_menu_kb():
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="📦 軟件", callback_data="cat_軟件")],
        [InlineKeyboardButton(text="⭐ 會員訂閱", callback_data="cat_會員訂閱")],
        [InlineKeyboardButton(text="🛒 所有商品", callback_data="all_products")],
    ])

def product_kb(pid, price):
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text=f"💰 立即購買 (¥{price})", callback_data=f"buy_{pid}")],
        [InlineKeyboardButton(text="◀️ 返回主菜單", callback_data="back_menu")],
    ])

def confirm_kb(pid):
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="✅ 確認付款", callback_data=f"confirm_{pid}")],
        [InlineKeyboardButton(text="◀️ 取消", callback_data="back_menu")],
    ])

# ---- 發送卡密給用戶 ----
async def send_card(user_id, product_name, card_content):
    msg = f"🎉 購買成功！\n\n📦 商品：{product_name}\n\n🔑 卡密/序號：\n<code>{card_content}</code>\n\n感謝購買！"
    await bot.send_message(user_id, msg, parse_mode="HTML")

# ---- 處理詢問ADMIN_ID ----
AWAITING_ADMIN = {}

# ---- 命令處理 ----
@dp.message(Command("start"))
async def cmd_start(m: Message):
    await init_db()
    await m.answer(
        "👋 歡迎來到發卡商店！\n\n請選擇商品分類：",
        reply_markup=main_menu_kb()
    )

@dp.message(Command("admin"))
async def cmd_admin(m: Message):
    if m.from_user.id != ADMIN_ID:
        await m.answer("❌ 無權限")
        return
    await m.answer(
        "🔧 管理員面板\n\n"
        "/add - 新增商品\n"
        "/stock - 查看庫存\n"
        "/orders - 查看訂單\n"
        "/list - 商品列表"
    )

@dp.message(Command("add"))
async def cmd_add(m: Message):
    if m.from_user.id != ADMIN_ID:
        return
    AWAITING_ADMIN[m.from_user.id] = "add_name"
    await m.answer("📝 新增商品\n\n請輸入商品名稱：")

@dp.message(Command("stock"))
async def cmd_stock(m: Message):
    if m.from_user.id != ADMIN_ID:
        return
    products = await get_products()
    if not products:
        await m.answer("📦 暫無商品")
        return
    text = "📦 商品庫存：\n\n"
    for p in products:
        text += f"{p[0]}. {p[1]} - 庫存：{p[3]} | ¥{p[2]}\n"
    await m.answer(text)

@dp.message(Command("orders"))
async def cmd_orders(m: Message):
    if m.from_user.id != ADMIN_ID:
        return
    async with aiosqlite.connect(DB_PATH) as db:
        rows = await db.execute_fetchall(
            "SELECT id,user_id,product_id,paid,created_at FROM orders ORDER BY id DESC LIMIT 20"
        )
    if not rows:
        await m.answer("📋 暫無訂單")
        return
    text = "📋 最近訂單：\n\n"
    for r in rows:
        text += f"#{r[0]} 用戶:{r[1]} 商品:{r[2]} 支付:{r[3]} {r[4]}\n"
    await m.answer(text)

@dp.message()
async def handle_admin_input(m: Message):
    uid = m.from_user.id
    if uid != ADMIN_ID:
        return
    if uid not in AWAITING_ADMIN:
        return

    step = AWAITING_ADMIN[uid]
    async with aiosqlite.connect(DB_PATH) as db:
        if step == "add_name":
            AWAITING_ADMIN[uid] = {"step": "add_price", "name": m.text}
            await m.answer(f"📝 商品：「{m.text}」\n\n請輸入價格（數字）：")
        elif isinstance(step, dict) and step.get("step") == "add_price":
            try:
                price = float(m.text)
                AWAITING_ADMIN[uid] = {"step": "add_stock", "name": step["name"], "price": price}
                await m.answer("請輸入庫存數量：")
            except:
                await m.answer("❌ 價格必須是數字")
        elif isinstance(step, dict) and step.get("step") == "add_stock":
            try:
                stock = int(m.text)
                AWAITING_ADMIN[uid] = {"step": "add_card", "name": step["name"], "price": step["price"], "stock": stock}
                await m.answer("請輸入卡密/序號內容（每行一組）：\n（支持多行，購買時隨機發送一組）")
            except:
                await m.answer("❌ 庫存必須是整數")
        elif isinstance(step, dict) and step.get("step") == "add_card":
            cards = m.text.strip()
            await db.execute(
                "INSERT INTO products (name,price,stock,card_content,category) VALUES (?,?,?,?,?)",
                (step["name"], step["price"], step["stock"], cards, "軟件")
            )
            await db.commit()
            await m.answer(f"✅ 商品已添加！\n\n📦 {step['name']}\n💰 ¥{step['price']}\n📊 庫存：{step['stock']}\n🔑 卡密：{len(cards.split(chr(10)))}組")
            del AWAITING_ADMIN[uid]

# ---- 內聯按鈕處理 ----
@dp.callback_query(F.data == "back_menu")
async def cb_back_menu(c):
    await c.message.edit_text("👋 歡迎來到發卡商店！\n\n請選擇商品分類：", reply_markup=main_menu_kb())

@dp.callback_query(F.data == "all_products")
async def cb_all(c):
    await init_db()
    products = await get_products()
    if not products:
        await c.answer("📦 暫無商品", show_alert=True)
        return
    text = "🛒 所有商品：\n\n"
    keyboard = []
    for p in products:
        text += f"{p[0]}. {p[1]} - ¥{p[2]} (庫存:{p[3]})\n"
        keyboard.append([InlineKeyboardButton(text=f"購買 {p[1]} - ¥{p[2]}", callback_data=f"buy_{p[0]}")])
    keyboard.append([InlineKeyboardButton(text="◀️ 返回", callback_data="back_menu")])
    await c.message.edit_text(text, reply_markup=InlineKeyboardMarkup(inline_keyboard=keyboard))

@dp.callback_query(F.data.in_(["cat_軟件", "cat_會員訂閱"]))
async def cb_cat(c):
    category = c.data.replace("cat_", "")
    await init_db()
    products = await get_products(category)
    if not products:
        await c.answer(f"📦 暫無{category}商品", show_alert=True)
        return
    text = f"{category}：\n\n"
    keyboard = []
    for p in products:
        text += f"{p[0]}. {p[1]} - ¥{p[2]} (庫存:{p[3]})\n"
        keyboard.append([InlineKeyboardButton(text=f"購買 {p[1]} - ¥{p[2]}", callback_data=f"buy_{p[0]}")])
    keyboard.append([InlineKeyboardButton(text="◀️ 返回", callback_data="back_menu")])
    await c.message.edit_text(text, reply_markup=InlineKeyboardMarkup(inline_keyboard=keyboard))

@dp.callback_query(F.data.startswith("buy_"))
async def cb_buy(c):
    pid = int(c.data.replace("buy_", ""))
    p = await get_product(pid)
    if not p:
        await c.answer("❌ 商品不存在", show_alert=True)
        return
    text = f"📦 {p[1]}\n💰 價格：¥{p[2]}\n📊 庫存：{p[3]}\n\n{p[4] or ''}\n\n點擊確認即表示同意交易。"
    await c.message.edit_text(text, reply_markup=confirm_kb(pid))

@dp.callback_query(F.data.startswith("confirm_"))
async def cb_confirm(c):
    pid = int(c.data.replace("confirm_", ""))
    uid = c.from_user.id
    p = await get_product(pid)
    if not p or p[3] <= 0:
        await c.answer("❌ 庫存不足", show_alert=True)
        return

    # 示例如動支付 - 這裡直接發貨
    # 實際可接入支付寶/微信/加密貨幣
    await deduct_stock(pid)
    cards = p[5].split("\n") if p[5] else []
    import random
    card = random.choice(cards) if cards else "NO-CARD"

    await send_card(uid, p[1], card)
    await c.answer("✅ 購買成功！")

    # 記錄訂單
    from datetime import datetime
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute(
            "INSERT INTO orders (user_id,product_id,paid,created_at) VALUES (?,?,1,?)",
            (uid, pid, datetime.now().isoformat())
        )
        await db.commit()

async def main():
    await init_db()
    print("🤖 Bot 啟動中...")
    await dp.start_polling(bot)

if __name__ == "__main__":
    asyncio.run(main())
PYEOF

echo "[5/6] 創建配置文件..."
cat > .env << 'ENVEOF'
BOT_TOKEN=YOUR_BOT_TOKEN_HERE
ADMIN_ID=0
ENVEOF

echo "[6/6] 完成！"
echo ""
echo "=========================================="
echo "  設定教學"
echo "=========================================="
echo ""
echo "1️⃣ 拿 BOT TOKEN："
echo "   聯繫 @BotFather，發送 /newbot"
echo "   把得到的 token 替換到 .env 裡的 YOUR_BOT_TOKEN_HERE"
echo ""
echo "2️⃣ 拿 ADMIN_ID："
echo "   聯繫 @userinfobot，發送 /start"
echo "   把數字替換到 .env 裡的 ADMIN_ID"
echo ""
echo "3️⃣ 編輯 .env："
echo "   cd $BOTDIR"
echo "   nano .env"
echo ""
echo "4️⃣ 啟動機器人："
echo "   cd $BOTDIR"
echo "   python3 bot.py"
echo ""
echo "5️⃣ 讓機器人在後台運行："
echo "   pip3 install requests && nohup python3 bot.py > bot.log 2>&1 &"
echo ""
echo "=========================================="
ENVEOF

chmod +x /tmp/tg-card-bot-setup.sh
echo "Script ready"

echo ""
echo "=========================================="
echo "  上傳到 GitHub..."
echo "=========================================="
cd /tmp && git clone --depth 1 https://github.com/whypuss/hermes-skills.git /tmp/hermes-skills-temp 2>/dev/null || (rm -rf /tmp/hermes-skills-temp && git clone --depth 1 https://github.com/whypuss/hermes-skills.git /tmp/hermes-skills-temp)
mkdir -p /tmp/hermes-skills-temp/scripts
cp /tmp/tg-card-bot-setup.sh /tmp/hermes-skills-temp/scripts/
cd /tmp/hermes-skills-temp
git config user.email "hermes@agent.local"
git config user.name "Hermes"
git add scripts/tg-card-bot-setup.sh
git commit -m "Add TG card bot one-click setup script" 2>/dev/null
git push 2>/dev/null && echo "Uploaded!" || echo "Upload skipped (no write access or no changes)"
