---
name: askai
description: Multi-turn Gemini dialogue via browser automation — minimum 3 rounds, explores problems deeply before taking action. No API key needed.
category: browser-automation
---

# AskAI — 多輪對話式 Gemini 顧問

## 命令

```
/askai <你的問題>
```

範例：
```
/askai 我的 Gemma chatbot CORS 一直 blocked，Cloudflare tunnel URL 每次重啟都變，應該怎麼解決？
```

## 流程

```
Round 1: 導航 Gemini → 輸入問題 → 等待回應 → 擷取回應
    ↓
Round 2: 輸入跟進問題 → Gemini 回應 → 擷取
    ↓
Round 3+: 繼續深入 → 直到完整方案出爐
    ↓
Summary: 輸出所有來回關鍵結論
```

## 實現 (`_handle_askai_command` in cli.py)

```python
from tools.browser_tool import browser_navigate, browser_snapshot, browser_type, browser_click, browser_press

browser_navigate(url="https://gemini.google.com/app")
sleep(3)

snap = browser_snapshot(full=False)
tb = re.search(r'\[ref=(e\d+)\].*?Enter a prompt for Gemini', snap).group(1)
browser_type(ref=tb, text=question)

send_ref = re.search(r'\[ref=(e\d+)\].*?Send message', snap).group(1)
browser_click(ref=send_ref)

sleep(12)

snap = browser_snapshot(full=True)
resp = extract_gemini_response(snap)  # "Gemini said" heading 後的文字
```

## 關鍵正規表達式

```python
# 抽 Gemini 回應
re.search(r'Gemini said[:\s]*(.*?)(?=\n\s*(?:You said|Redo|Copy|$))', snap, re.DOTALL)

# 找文字框
re.search(r'\[ref=(e\d+)\].*?Enter a prompt for Gemini', snap)

# 找發送按鈕
re.search(r'\[ref=(e\d+)\].*?Send message', snap)
```

## 設計原則

1. 最少 3 輪對話
2. 每輪顯示 Gemini 回應
3. 輸入 'done' 或 'q' 結束對話
4. 最後輸出總結

## 適用場景

- 複雜技術決策（架構選擇、最佳實踐）
- Debug 問題的多角度分析
- 需要深入探討但不想手動來回複製貼上
- 沒有 API key 時的 fallback

## 限制

- 需要網絡可訪問 gemini.google.com
- Gemini 頁面結構可能隨版本變化，ref 需要動態匹配
- 頁面加載慢時可能需要增加 sleep 時間
