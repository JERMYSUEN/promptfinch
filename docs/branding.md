# PromptFinch

**Select. Refine. Paste.**

國際化顯示名稱：**PromptFinch**。建議 GitHub 儲存庫名稱：`promptfinch`；npm 專案名稱及來源包也使用新名稱。Finch 指小型鳥類，作為輕巧選取助手的名稱。本輪沒有建立或發布儲存庫。

## 更名範圍

- macOS App：`PromptFinch.app`，主視窗、應用程式選單、選單列入口及右鍵附加選單標題。
- macOS Services：`PromptFinch — 轉為英文 Prompt`。
- 可選瀏覽器頁面的名稱、首頁品牌及標題。
- README 保留英文及 28 個其他語言／書寫介紹，只更換品牌名稱；npm 專案名稱為 `promptfinch`。
- 公開來源包：`PromptFinch-source-v1.0.0.zip`。

右鍵仍先顯示操作選單，只有點選轉換才生成。介面維持繁體中文；多語介紹屬於文件。

## 既有安裝與相容性

執行既有建置／安裝指令：

```sh
npm run build:mac
npm run install:mac
```

安裝器會確認舊 `Prompt 選取助手.app` 的 bundle ID 與簽章，正常退出後移至 `~/Applications/PromptFinch.app` 再更新。若新舊安裝位置都已存在，會停止以避免覆蓋不明版本。後端更新器支援新名稱及尚未移轉的舊安裝。

為保留設定與固定簽章，內部 bundle ID `org.promptstudio.selection`、執行檔 `PromptSelection`、Application Support 的 `PromptSelection` 目錄、UserDefaults 鍵與 API 識別 `prompt-studio` 沿用原值。實際專案目錄無需改名；既有 `.env` 路徑及模型設定保持原樣。沒有重設 TCC 或重新建立簽章私鑰。

## 核對

2026-10-09 已完成 build 9 的建置、後端更新與更名安裝，實際核對結果：

- `npm run check` 通過；Node 測試 49/49、macOS 核心測試 81 項、Chrome 瀏覽器測試 10/10 通過。
- 舊新 App 簽章有效、bundle ID 相同，designated requirement 雙向相符；安裝後的執行檔與建置版本一致。
- 新安裝位置為 `~/Applications/PromptFinch.app`，舊安裝位置已移轉。App 名稱及可選網頁標題均為 PromptFinch。
- 原設定檔路徑、設定檔內容及 UserDefaults 匯出內容的 SHA-256 均與更名前一致。
- 唯一已安裝 App 啟動了自己的後端，回報 `live/ready/deepseek-flash`；日誌記錄 `watcher started`，原權限可繼續使用。

這次沒有重新呼叫付費模型，也沒有重做 Codex／Claude 的真人右鍵驗收；前輪使用者已確認附加選單及點一次生成可用。舊來源 ZIP 與歷史驗證記錄保留原名稱。
