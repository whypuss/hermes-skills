---
name: data-gov-mo-api
description: 澳門政府開放數據平台 data.gov.mo API 抓取與 Obsidian 整合流程
category: note-taking
---

# data-gov-mo-api

澳門政府開放數據平台 data.gov.mo API 抓取與 Obsidian 整合流程。

## API 架構（已破解）

### 端點
- **Search**: `POST https://api.data.gov.mo/datadir/search` (body: `{"keyword": "", "pageSize": 1000, "pageNum": 1, "lang": "TC"}`)
  → 回傳 `{data: {items: [...]}}`，不是 `result`！`result` 欄位永遠是空陣列
- **Detail**: `GET https://api.data.gov.mo/datadir/detail/{uuid}?token={TOKEN}&lang=TC`
  → 回傳 `{data: {apis: [{apiId: "5054", ...}], ...}}`
  → uuid 從 `directory_api` URL 中解析：`api_url.split('/')[-1].split('?')[0]`
- **API Result**: `GET https://api.data.gov.mo/api/{apiId}?token={TOKEN}&lang=TC`
  → 回傳 `{data: {resultSample: "<double-encoded-json>"}}`
  → 內層解析: `inner = json.loads(resultSample)` → `data_val = json.loads(inner['data'])` → `data_val['value']['values']`
  → **只返回最多 24 行預覽**（非完整歷史）
- **File Download**: `GET https://api.data.gov.mo/document/download/{docId}?token={TOKEN}&isNeedFile=1&lang=TC`
  → **必須加 `isNeedFile=1`**，否則返回 HTML
  → 返回 **ZIP 格式**（需用 Python `zipfile` 解壓）
  → `lang` 參數: `TC`=繁體，`CHS`=簡體，`PT`=葡萄牙文

### Token (data.gov.mo)
```
3h9ZRUS05oZoA0v4cUl6Lwe7kg8LClUP
```

### DSEC Time Series API（需 cookies，**無需登入**）

**目標：** 澳門統計暨普查局時間序列數據庫（`https://www.dsec.gov.mo/ts/`）

**關鍵陷阱：`types=VAL` vs `dataPeriods=Yearly`**
- `types=VAL` 是**值類型**（VAL = 標準數值；還有 SPV/PPV/POT/PPD）
- `dataPeriods=Yearly` 才是**時間週期**（Yearly/Quarterly/Monthly 等）
- 用 `types=Yearly` 會返回錯誤 — 這個混淆是主要踩坑點

**端點：**
| 操作 | 方法 | URL |
|------|------|-----|
| 指標樹（根） | `GET` | `https://www.dsec.gov.mo/TimeSeriesApi/App/Indicatorv3` |
| 子節點 | `GET` | `https://www.dsec.gov.mo/TimeSeriesApi/App/Indicatorv3/{indicatorID}` |
| 時間序列數據 | `POST` | `https://www.dsec.gov.mo/TimeSeriesApi/App/IndicatorValue/LatestSameEndPeriodv3` |
| 參數格式 | form-urlencoded | `indicator_ids={ID}&language=zh-MO&types=VAL&dataPeriods=Yearly&num=50` |

**全自動取 Cookies（無需登入）：** DSEC session 在第一次訪問 `https://www.dsec.gov.mo/ts/` 時自動產生，**完全不需要帳號密碼**。訪問順序：`dsec.gov.mo/zh-MO/` → `dsec.gov.mo/ts/`。

**AngularJS 陷阱：** headless Playwright 環境下 Angular digest loop 不觸發，點擊 UI 不會發 API。必須從 Playwright 直接提取 cookies 再用 urllib。

**資料結構陷阱：**
- `IsLeafNode` 幾乎全部返回 True，不可信
- `description` 欄位很短（如 "男"、"女"），**搜尋必須用 `indicator_path`**（格式：`分類 -- 子類 -- 指標名`）
- 20 個頂層分類：人口、旅遊及服務、對外商品貿易、建築及不動產交易、勞動力、國民經濟、分銷及價格等

**GitHub Repo（完整腳本）：** `github.com/whypuss/macau-dsec-scraper`
```bash
pip3 install playwright && playwright install chromium
python3 fetch_dsec_timeseries.py --auto-cookies  # 一鍵全自動
```
- `fetch_dsec_timeseries.py`：主爬蟲（帶 `--auto-cookies` 內建自動取 cookie）
- `get_cookies.py`：獨立 cookie 獲取器
- `key_indicators.json`：5 個核心指標（可直接使用）

**本地路徑：**
- 爬蟲腳本：`~/projects/history-knowledge-base-obsidian/dsec-time-series/fetch_dsec_timeseries.py`
- SQLite DB：`~/projects/history-knowledge-base-obsidian/dsec-time-series/dsec_timeseries.db`
- 成效：7,911 指標，154,050 條時間序列（1976–2025）

**數據驗證（2025）：** 人均GDP 607,263 MOP / 75,617 USD；總人口 689,000；失業率 1.9%

### 重要發現（trial & error）
1. **CKAN API (`data.gov.mo/api/3/action/*`) 已完全停用**，返回 404/HTML
2. **`lang=CHT` 無效**，有效值只有 `TC` / `CHS` / `PT`
3. **`datadir/search` 回傳在 `items` 不是 `result`** — 常見踩坑點
4. **DSEC 官網 `dsec.apigateway.data.gov.mo` 返回 400**，需要瀏覽器 cookies/session
5. **DSEC Time Series API (`dsec.gov.mo/TimeSeriesApi/App/KeyIndicatorv3/...`) 需登入**，browser 也回 400
6. **File download ZIP 可能只有 `readme.json`（空數據集）**，不是真正數據
7. **resultSample 最多 24 行**是 API 設計上限，不是 bug

8. **LLM Wiki 模式對 DSEC 數值數據價值有限**：Karpathy 的 LLM Wiki 適用於非結構化文本（論文/文章），每個新 source 需要 LLM 自動分類/摘要。但 DSEC 指標已有 `indicator_path` 分類體系，wiki 頁面之間的「相關性」來自經濟邏輯（GDP↔旅遊↔博彩），LLM 難以補充額外洞見。**真正有價值的 LLM 應用**：對新發佈的數據做文字分析（"澳門Q1 GDP出來了，分析同比變化"）而非自動生成 wiki 頁面。

### 數據集分類
- **文件型** (CSV/XLSX/JSON): 用 `document/download` 下載 ZIP，解壓後解析
- **API型**: `directory_api` → UUID → `datadir/detail/{uuid}` → 取 `apiId` → `api/{apiId}`（最多 24 行）
- **純API無預覽**: ~400 個，API 和 download 都拿不到數據（可能是機構未實際上傳）

### HTML Dashboard 部署
- 最佳實踐: **直接 embed JSON 在 HTML**（`window.__DATA__ = {...}`），避免 SQLite/WASM 問題
- **jsdelivr CDN 在 server 端被封**（timeout），可用 unpkg 或直接 embed
- 部署: `cd sqlite && VERCEL_TOKEN=vcp_xxx npx vercel --yes --prod`
- Deploy URL: `https://sqlite-nu.vercel.app`

## DSEC GitHub Repo
- `github.com/whypuss/macau-dsec-scraper` — 完整爬蟲腳本、get_cookies.py、key_indicators.json


- Vault: `~/projects/history-knowledge-base-obsidian/data.gov.mo/`
- DB: `data.gov.mo/sqlite/data.gov.mo.sqlite` (1370 總數，970 有數據)
- HTML Dashboard: `https://sqlite-nu.vercel.app` (直接 embed JSON，無需 SQLite)
- 重抓腳本: `data.gov.mo/sqlite/rescrape.py`
- build_db.py: `data.gov.mo/sqlite/build_db.py`
- build_html.py: `data.gov.mo/sqlite/build_html.py`
- index.html: `data.gov.mo/sqlite/index.html` (CSS + JS + embed JSON)

## 已知限制
- resultSample 最多 24 行是 API 上限，不是 bug
- 2008-2022 歷史數據無法透過 resultSample 取得
- DSEC 官網完整數據需另找出路（DSEC 官網 `dsec.gov.mo` 有完整下載，但 API 需要 session/cookies）
- ~400 個數據集無論如何都拿不到數據（機構未實際上傳）
