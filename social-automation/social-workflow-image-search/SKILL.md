---
name: social-workflow-image-search
description: Social workflow Google Images captcha 解決——分開控制平常 Chrome 與 social-mcp Chromium
category: social-automation
---

# Social Workflow — 圖片搜尋與 Google Captcha 解決

## 問題描述
cron job 跑 `social_workflow_3source.py`，Google Images 搜尋一直失敗（[Images] 找不到圖片）。

## 根因
1. social-mcp 的 Chromium 運行在 server IP（data center IP 206.119.151.149），Google 認定是機器人，直接 captcha 封鎖
2. workflow 和 social-mcp 共用同一個 CDP port 9333，無法分開控制兩個瀏覽器
3. Google captcha 與 URL 參數無關，純看 IP + 請求特徵

## 解決方案：分開控制兩個瀏覽器

social-mcp Chromium 繼續用 9333（不改），平常的 Chrome 開 9222 給 workflow 用。

### Step 1: 開啟平常的 Chrome（Remote Debugging Mode）

在終端執行（可封裝成 App 或 script）：
```bash
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --remote-debugging-port=9222
```

### Step 2: 修改 workflow CDP port

`~/.kimaki/projects/ai-cdp-browser/scripts/social_workflow_3source.py`：

```python
CDP_PORT = 9333  # social-mcp Chromium（保持不動）
# 改用平常的 Chrome：
CDP_PORT = 9222
```

### 為什麼分開更好
- 9333 = social-mcp，長期運行，不動
- 9222 = 平常的 Chrome，有 Google 登入，IP 乾淨
- 兩者可以同時運行，互不影響
- 圖片搜尋用 9222 的瀏覽器就能過 Google captcha

## 驗證方法
```bash
lsof -i :9222 -i :9333
```
兩個端口都有監聽就是成功。

## 已知限制
- Chrome 實例關閉後 Remote Debugging 斷開，需重開 Chrome
- 如果 IP（即使是你的 Mac）被 Google 封，一樣 captcha，換瀏覽器無效
