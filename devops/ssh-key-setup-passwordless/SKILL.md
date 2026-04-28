---
name: ssh-key-setup-passwordless
description: 從零開始設定 SSH key 並達成無密碼登入 remote server，包含常見失敗模式與繞過方法。適用於 macOS + Homebrew 環境。
---

# SSH Key 設定：從零到無密碼登入

## 情境
用戶執行 `ssh-copy-id user@host` 回报 "No identities found"，需要建立 SSH key 並複製到遠程伺服器。

## 標准流程

### Step 1: 生成 key
```bash
ssh-keygen -t ed25519 -C "描述" -f ~/.ssh/id_ed25519 -N ""
```

### Step 2: 複製到伺服器
```bash
ssh-copy-id -i ~/.ssh/id_ed25519 user@host
# 系統會提示輸入密碼
```

### Step 3: 驗證
```bash
ssh -i ~/.ssh/id_ed25519 user@host echo "✅ 無密碼登入成功"
```

---

## 失敗模式與繞過

### 失敗1: "No identities found"
原因：本地沒有任何 SSH key。
處理：執行 Step 1 生成 key。

### 失敗2: "Too many authentication failures"
症狀：即使輸入正確密碼仍然失敗，伺服器斷開連接。
原因：ssh-agent 累積了多把 key，伺服器在第一個 packet 就達到認證次數上限。
診斷：
```bash
ssh-add -l  # 查看 ssh-agent 內的 key
ls ~/.ssh/  # 查看所有 key 檔案
```
處理：加 `-o IdentitiesOnly=yes` 強製只用指定的那把 key。
```bash
ssh-copy-id -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes user@host
```

### 失敗3: "read_passphrase: can't open /dev/tty"
症狀：SSH debug 輸出看到此訊息，密碼輸入永遠無法彈出。
原因：終端環境（如 Hermes CLI remote session）沒有 /dev/tty，無法互動輸入密碼。
診斷：
```bash
ssh -v -o PubkeyAuthentication=no user@host 2>&1 | grep "read_passphrase"
```

處理：使用 sshpass 在同一行輸入密碼。
```bash
brew install sshpass
sshpass -p '密碼' ssh-copy-id -i ~/.ssh/id_ed25519 user@host
```

### 失敗4: 伺服器 IP 被鎖定
症狀：伺服器完全拒絕任何 SSH 連線（不只是密碼）。
原因：短時間內太多認證失敗，伺服器臨時封鎖該 IP（通常 5-15 分鐘後自動解除）。
處理：等一段時間再試，或親自到伺服器旁邊操作解除封鎖。

---

## 驗證命令
```bash
# 確認 key 已存在
ls -la ~/.ssh/id_ed25519

# 確認 key 已複製到伺服器
ssh -i ~/.ssh/id_ed25519 user@host "cat ~/.ssh/authorized_keys" | grep ed25519

# 確認無密碼登入成功
ssh -i ~/.ssh/id_ed25519 user@host echo "ok"
```
