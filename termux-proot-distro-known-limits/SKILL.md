---
name: termux-proot-distro-known-limits
description: Termux + proot-distro 已知限制——哪些服務可以跑、哪些不行（1Panel、CasaOS 等需要 systemd 的面板已確認失敗）
category: android
---

# Termux + proot-distro 已知限制

## 觸發條件
在 Termux 環境（Android）上透過 proot-distro 安裝 Linux 發行版後，嘗試運行需要 systemd 的服務。

## 已知不可行的項目（實測失敗）

### 1Panel（Linux 服務管理面板）
- **原因**：1Panel 需要 systemd 來管理 Docker、Nginx 等系統服務，proot-distro 的 Debian 沒有真正的 systemd
- **錯誤日誌**：`error 'BASE_DIR' find in /usr/local/bin/1pctl`（部分路徑問題）+ systemd 依賴
- **嘗試過程**：
  1. SSH 連線：port 8022（不是 22），用戶 `u0_a409`
  2. 安裝 proot-distro → `pkg install proot-distro`
  3. 安裝 Debian → `proot-distro install debian`
  4. 手動傳輸 1Panel 二進制（Mac → Termux → proot Debian）
  5. 1panel-core 能啟動但核心功能無法運作
- **結論**：放棄

### 其他需要 systemd 的面板（推斷）
- CasaOS（需要 systemd）
- 類似的一鍵建站面板

## Termux + proot-distro 可行的項目

- ✅ SSH Server（已有，port 8022）
- ✅ Docker（Termux 有 docker 包：`pkg install docker`）
- ✅ 各種命令行工具（curl、wget、python、node 等）
- ✅ Docker + Portainer（輕量級容器管理，比 1Panel 更適合 Termux）
- ✅ Cloudflare Tunnel（cloudflared）
- ✅ 反向代理（sing-box、frp、socat）

## SSH 連線資訊（設備：192.168.31.93）

- Port: 8022（不是標準 22）
- 用戶: `u0_a409`
- 密碼: `1234`
- 連線方式：`sshpass -p '1234' ssh -o StrictHostKeyChecking=no -p 8022 u0_a409@192.168.31.93`
- proot-distro Debian：`proot-distro login debian`

## 關鍵陷阱

1. **DNS 在 proot 內不工作**：Termux 本身 DNS 正常，但 proot 環境無法解析某些域名（如 `get.1panel.cn`）。解決：從 Termux 下載文件再 `cp` 進 proot rootfs
2. **proot 警告`can't sanitize binding`**：正常的，不影响运行
3. **文件傳輸**：SCP 在低速網路容易超時，改用 `cat file | ssh ... "cat > dest"` 管道方式

## 驗證步驟

```bash
# 確認 systemd 是否存在
which systemctl  # 如果返回空 = 無 systemd

# 嘗試啟動 1Panel（僅娛樂）
proot-distro login debian
cd /root/1panel-*-linux-arm64
./1panel-core  # 會失敗
```

## 更新日誌
- 2026-05-02：初版，確認 1Panel 在 Termux/proot 不可用
