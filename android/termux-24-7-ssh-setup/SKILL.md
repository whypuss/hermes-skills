---
name: termux-24-7-ssh-setup
description: Termux SSH 24/7 持久化——開機自動啟動 SSH + watchdog 防斷線 + wake lock
category: android
---

# Termux SSH 24/7 持久化設置

## 觸發條件
需要在 Android 上讓 SSH 永久在線，無論 Termux 是否打開。

## 前置需求
- Termux 已在運行 SSH：`pkg install openssh`（Termux SSH 預設 port 8022，不是 22）
- `termux-wake-lock` 可用：`pkg install termux-api`

## 步驟

### 1. 安裝 Termux:Boot（開機自啟關鍵）

```bash
# 在 Mac/PC 下載 termux-boot APK
curl -L "https://github.com/termux/termux-boot/releases/download/v0.8.1/termux-boot-app_v0.8.8.1+github.debug.apk" -o /tmp/termux-boot.apk

# 傳到手機
cat /tmp/termux-boot.apk | sshpass -p 'PASSWORD' ssh -o StrictHostKeyChecking=no -p 8022 user@host "cat > ~/downloads/termux-boot.apk"

# 在手機上 SSH 觸發安裝介面
ssh ... "am start -a android.intent.action.VIEW -d 'file:///data/data/com.termux/files/home/downloads/termux-boot.apk' -t application/vnd.android.package-archive"
```

**用戶需要手動點確認安裝 Termux:Boot。**

### 2. 創建 SSH watchdog 腳本

```bash
cat > ~/.sshd-watchdog.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
LOG=~/.ssh_watchdog.log
exec >> $LOG 2>&1
echo "[$(date)] SSH watchdog started"
termux-wake-lock 2>/dev/null
while true; do
    if ! pgrep -x sshd > /dev/null 2>&1; then
        echo "[$(date)] sshd not running, starting..."
        /data/data/com.termux/files/usr/bin/sshd
    fi
    sleep 30
done
EOF
chmod +x ~/.sshd-watchdog.sh
```

### 3. 設置 Termux:Boot 開機腳本

```bash
mkdir -p ~/.termux/boot
cat > ~/.termux/boot/01-sshd.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
termux-wake-lock
nohup bash ~/.sshd-watchdog.sh > ~/.ssh_watchdog.log 2>&1 &
EOF
chmod +x ~/.termux/boot/01-sshd.sh
```

### 4. 每次 Termux 啟動也自動運行（保險）

```bash
cat >> ~/.bash_profile << 'EOF'
if ! pgrep -x "sshd-watchdog" > /dev/null 2>&1; then
    nohup bash ~/.sshd-watchdog.sh > ~/.ssh_watchdog.log 2>&1 &
fi
EOF
```

### 5. 立即啟動並驗證

```bash
nohup bash ~/.sshd-watchdog.sh > ~/.ssh_watchdog.log 2>&1 &
sleep 2
cat ~/.ssh_watchdog.log
pgrep -la sshd
```

## 驗證方法

```bash
# 測試 watchdog 是否正常
pgrep -la sshd-watchdog

# 測試 wake lock
termux-wake-lock

# 手機重啟後，等 1-2 分鐘，SSH 應該可以連上
ssh -p 8022 user@host
```

## Android 必要設置（用戶需手動做）

1. **開啟 Termux:Boot**：安裝完成後打開一次 Termux:Boot
2. **允許後台運行**：設定 → 應用 → Termux → 電池 → 設為「無限制」
3. **保持 WiFi 连接**：建議使用穩定 WiFi，行動網絡 IP 可能會變

## 已知問題

- **公網 IP 變動**：如果手機用行動網絡，IP 每次連線可能不同（可用 Cloudflare Tunnel 固定域名）
- **Android 殺進程**：部分 Android 廠商（華為、小米）會自動殺後台應用，需額外設定白名單
- Termux:Boot 依賴 Termux app 被系統喚醒，不是真正的開機自啟（但效果接近）

## 更新日誌
- 2026-05-02：初版，適用於 Termux 持久化 SSH 設置
