---
name: social-news-public-cli
description: 用 opencli 獲取公開社交/新聞平台的熱門資訊（無需瀏覽器或登錄）
metadata:
  author: hermes
  version: "1.0.0"
---

# 社交/新聞公開資訊 CLI

## 快速測試

```bash
# V2EX 熱門
opencli v2ex hot

# BBC 新聞
opencli bbc news

# 36氪 熱門
opencli 36kr hot

# Bloomberg Tech
opencli bloomberg tech

# Bluesky Trending
opencli bluesky trending
```

## 已知限制

- 小红书 — IP 風控，無解
- Facebook/Instagram — 需要 cookie extension

## 重要發現：Twitter/X 不需要 extension

Twitter 可以用直接啟動 Chromium + CDP WebSocket 繞過，不需要任何 Browser Bridge extension。見 skill: `chromium-direct-cdp-automation`

## 維護日誌

- 2026-04-25: 創建。V2EX/BBC/36kr 全部正常。
- 2026-04-25: 更新——Twitter 不需要 extension，直接 CDP 可用。