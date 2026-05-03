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
- **Secret 名稱是 `u`（不是 `UUID`）**：代碼中 `env.u || env.U || at` 讀取 UUID，所以 secret 要設為 `u`

## 部署步驟

### 1. Wrangler 登入
```bash
export CLOUDFLARE_API_TOKEN="你的API Token"
export CLOUDFLARE_ACCOUNT_ID="你的Account ID"
wrangler whoami  # 驗證
```

### 2. 檢查 KV Namespace
```bash
# 先檢查是否已存在 KV
wrangler kv namespace list
# 如果存在，記下 id，否則創建新的
wrangler kv namespace create "cfnew_kv"
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

### 6. 設定 Secret 並部署
```bash
# Secret 名稱是 "u"，不是 "UUID"
echo $UUID | wrangler secret put u
wrangler deploy
```

### 7. 確認 KV 綁定到 Worker
部署完成後，去 Cloudflare Dashboard → Workers → cfnew → **Bindings** 確認有 KV Namespace 綁定，否則 Worker 會 500。

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
| `error code: 1101` Worker threw exception | KV 未綁定、或原始碼 Runtime 問題 | 確認 Bindings 頁面有 KV、檢查 Logs |
| 500 但 KV 已綁定 | 原始碼本身有 Bug（常見於 GitHub 下載的版本） | 去 Cloudflare Logs 看堆疊錯誤 |

## 疑難排斷 Protocol（1101 錯誤）

當 Worker 返回 `error code: 1101` 時，**即使 KV 已正確綁定、程式碼本地 dev 正常、Logs 顯示 0 事件**：

### Step 1：確認不是 KV 綁定問題
Cloudflare Dashboard → Workers → cfnew → Bindings → 確認有 `C` 的 KV Namespace。

### Step 2：用不同名稱測試
```bash
# 用不同 worker 名稱部署同一份程式碼
wrangler deploy --name cfnew-test-alt
curl https://cfnew-test-alt.{account}.workers.dev/
```
如果新名稱正常 → **Worker 名稱本身有殘留狀態**（不是程式碼問題）。

### Step 3：根因 + 解法（！）
**Worker 名稱在 Cloudflare 系統內有損壞的內部狀態**，可能來自：
- 之前刪除 KV binding 或變更 binding 設定
- 早期部署殘留的元數據衝突
- 同名 worker 刪除後未完全清理

**解法：完全刪除再重建（不能只靠 redeploy）**
```bash
wrangler delete cfnew --force
# 然後重新部署（wrangler deploy 會自動創建新的）
echo $UUID | wrangler secret put u --name cfnew
wrangler deploy
```
實測：同一份 worker_fixed.js，刪除重建後 HTTP 200，直接 deploy（不刪）還是 1101。

### Step 4：本地 dev 驗證
```bash
wrangler dev --name cfnew --port 8787
# 另外終端
curl http://localhost:8787/
```
本地正常 = 程式碼沒問題，問題在雲端部署狀態。

### Step 5：其他已知 1101 原因
- KV 未綁定 → 綁定後重建
- `cloudflare:sockets` 在不支援的 plan 上使用 → 確認 Workers 付費計劃
- Worker 腳本過大（>10MB compressed）→ 檢查上傳大小

### Step 6：根因確認——Worker 名稱本身狀態損壞（！）【2026-05-03 實測】
如果同一份程式碼：
- wrangler dev 本地運行 → 正常
- 部署到新 worker 名稱（如 cfnew-test-alt）→ 正常
- 部署到舊 worker 名稱（cfnew）→ 1101

結論：Worker 名稱在 Cloudflare 內部有損壞狀態（可能來自之前刪除 KV binding、變更 binding、或不完整刪除殘留）。**不是程式碼問題，是 worker 名稱狀態問題。**

解法：必須完全刪除 worker 再重建（wrangler delete --force + 重新 deploy，單純 redeploy 不夠）。

實測刪除重建後 200，直接 deploy（不刪）還是 1101。

## 重要：wrangler.toml 的位置

`wrangler deploy` 會讀取**當前工作目錄**下的 `wrangler.toml`，不是吃指令碼同目錄的設定。
每次部署前確認你在正確路徑：
```bash
pwd  # 確認在 wrangler.toml 所在目錄
ls wrangler.toml worker_fixed.js  # 確認兩個檔案都在
```

## Cloudflare 面板需手動開啟
1. **gRPC**：域名 → 網路 → 開啟 gRPC
2. **自訂域名**：Workers → cfnew → 觸發器 → 添加自訂網域
