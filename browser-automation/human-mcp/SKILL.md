---
name: human-mcp
description: 打開瀏覽器搜圖，本地保存，人工選圖後直接上傳。解決 Google Images captcha + 自動下載失敗的問題
category: browser-automation
tags: [browser, search, image, human-decision]
created: 2026-04-27
---

# Human MCP

## 問題
Google Images captcha 導致 social-mcp cron job 無法自動搜圖。

## 解決方案
用人工取代 captcha：打開瀏覽器 → 用戶右鍵保存到本地 → 直接拿本地路徑上傳。

## 啟動
```bash
cd ~/human-mcp && uv run python server.py
# 保持後台運行
```

## 流程

### Step 1：搜圖
```
POST http://localhost:8080/search
Body: {"query": "關鍵詞", "engine": "bing"}
```
→ Chrome 自動打開 Bing/Google 圖片搜尋

### Step 2：保存
在瀏覽器裡右鍵圖片 → Save As → 保存到 `~/Downloads/mcp_images/`

### Step 3：上傳
拿本地路徑，丟給 social-mcp 的 `post_instagram()` 或 `post_threads()`

## 為什麼比自動下載好
- 不用擔心防盜鏈（URL 失效）
- 不用處理 captcha
- 用戶確認過圖片內容才上傳
- 不需要 `download_image` endpoint

## 檔案
```
~/human-mcp/
└── server.py    # 只有一個 endpoint
```
