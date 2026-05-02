---
name: cfnew-cloudflare-workers-deploy
description: 部署 cfnew 2.9.6 到 Cloudflare Workers 的完整流程（從空白到上線）
category: devops
---

# cfnew 2.9.6 — Cloudflare Workers 部署流程

## 前置條件
- Cloudflare 帳號（需要 Workers 權限）
- API Token（Wrangler CLI 使用）
- 自己的域名（托管在 Cloudflare，可選但建議）
- Cloudflare 帳號 ID

## 技術關鍵點
- **不能用「少年你相信光嗎」**（混淆後的瀏覽器版代碼，target: browser，有 `window is not defined` 錯誤）
- **要用「明文源嗎」**（原始源碼，342KB，含 `cloudflare:sockets`）
- **混淆流程**：原始碼 → GitHub Actions (javascript-obfuscator) → 混淆版（用於部署者直接使用）
- 但 wrangler deploy 需要 Workers 相容代碼，所以**直接拿原始碼部署**是正確做法
- **KV 變量名必須大寫 `C`**

## 部署步驟

### 1. Wrangler 登入
```bash
export CLOUDFLARE_API_TOKEN="你的API Token"
export CLOUDFLARE_ACCOUNT_ID="你的Account ID"
wrangler whoami  # 驗證
```

### 2. 建立 KV Namespace
```bash
wrangler kv namespace create "cfnew_kv"
# 輸出會給 id，例如: 1d8d85c982a141ada33098ff80cee3bc
```

### 3. 下載原始碼
```bash
curl -s https://raw.githubusercontent.com/byJoey/cfnew/main/明文源吗 -o worker.js
```

### 4. 產生 UUID 並替換（避免用內建默認值）
```bash
UUID=$(python3 -c "import uuid; print(str(uuid.uuid4()))")
sed "s/351c9981-04b6-4103-aa4b-864aa9c91469/$UUID/g" worker.js > worker_fixed.js
```

### 5. 建立 wrangler.toml
```toml
name = "cfnew"
main = "worker_fixed.js"
compatibility_date = "2024-01-20"

kv_namespaces = [
  { binding = "C", id = "你的KV_ID" }
]
```

### 6. 設定 UUID Secret 並部署
```bash
echo $UUID | wrangler secret put UUID
wrangler deploy
```

## 部署後標記
- Worker URL: https://cfnew.{account}.workers.dev
- 管理後台: https://cfnew.{account}.workers.dev/{UUID}
- 兼容性日期: 2024-01-20（不是 2026-01-20）

## 常見錯誤
| 錯誤 | 原因 | 解決 |
|------|------|------|
| `window is not defined` | 用了混淆後的瀏覽器版代碼 | 改用「明文源嗎」原始碼 |
| KV 讀不到 | 變量名 binding 未設為 `C`（大寫） | wrangler.toml 確認 binding = "C" |
| deployment 10021 | 代碼包含瀏覽器 API | 同上，用正確源碼 |

## Cloudflare 面板需手動開啟
1. **gRPC**：域名 → 網路 → 開啟 gRPC
2. **自訂域名**：Workers → cfnew → 觸發器 → 添加自訂網域
