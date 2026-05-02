---
name: eu-org-domain-registration
description: EU.org 免費域名申請流程 — Handle 創建、登入、有效父域、申請表欄位、已知陷阱
category: devops
---

# EU.org Free Domain Registration Workflow

## 背景
EU.org 提供免費頂級域名，但採用審批制。Handle 申請成功後才能申請域名。

## 有效父域（重要！）
只有以下五個父域可以申請：
- `.eu.org`（全球通用）
- `cy.eu.org`（賽普勒斯）
- `gr.eu.org`（希臘）
- `il.eu.org`（以色列）
- `nl.eu.org`（荷蘭）

**`puss.eu.org` 不是有效父域**，無法申請（如 `moggy.puss.eu.org` 無效）。

來源：`https://nic.eu.org/opendomains.html`

## Handle 申請流程
1. 訪問 `https://nic.eu.org/arf/en/contact/create/`
2. name 欄位需要**至少兩個單詞**（Django 驗證：「Enter a valid value」）
3. 密碼需要大小寫 + 數字
4. 成功後收到驗證郵件，點驗證連結

## 登入與域名申請
- 登入：`POST https://nic.eu.org/arf/en/login/`（需要正確 Referer）
- 登入後 session 會話在 Python requests 中正常維持（但不要只靠 curl，CSRF 較嚴）
- 登入後訪問 `https://nic.eu.org/arf/en/domain/new/` 獲取申請表

## 申請表關鍵欄位（POST /domain/new/）
```
fqdn: moggy.eu.org（或候選）
pn1: Moggy Puss          # 必填
ad1: Macau               # 必填
ad2: Some Place          # 必填
ad3: China
ad4: 
ad5: 
ad6: CN                  # 必填！國家代碼（下拉選單），缺少此欄位報 "This field is required"
ph1: 
fx1: 
private: on
th: MP1820-FREE          # 申請人的 Handle
level: 2                 # 級別 1/2/3
f1: ns1.cloudflare.com   # Nameserver #1
i1: 
f2: ns2.cloudflare.com   # Nameserver #2
i2: 
f3:                      # 最多支援 9 個 NS
csrfmiddlewaretoken: <從錶單獲取>
```

### 常見 ad6 國家代碼
- CN（中國）、MO（澳門）、HK（香港）、TW（台灣）、JP（日本）、US（美國）等 ISO 3166-1 alpha-2

### Nameserver 欄位格式
- `f1`~`f9`：NS 主機名（如 `ns1.cloudflare.com`）
- `i1`~`i9`：可選的 IP 地址（通常留空）
- 至少需要一個 NS，否則報 `NS list is empty`

## 重要發現
1. **Session 管理**：需要 JavaScript 支援，瀏覽器自動化比純 curl 更穩
2. **域名欄位名**：不是 `domain`，是 `fqdn`
3. **私人域名**：需要 `private=on`
4. **Handle**：申請表需要自己的 Handle（MP1820-FREE）
5. **表單提交**：Python requests 可以成功（curl 403）

## 自動化方案
Python requests 可以完整走完登入+申請流程，無需瀏覽器。瀏覽器 CDP 方案適合解決 session 過期問題。

## 失敗模式
- `puss.eu.org` not in valid parent domains → `Zone not found or not managed here`
- name 欄位只有一個單詞 → `Enter a valid value`
- CSRF token 過期 → `403 Forbidden`
- 缺少 `private=on` → 申請被拒
- **缺少 `ad6`（Country）→ `This field is required`**
- **缺少 NS（f1）→ `NS list is empty`**
