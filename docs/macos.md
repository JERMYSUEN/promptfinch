# PromptFinch

原生 macOS 工具：選取或貼上任何語言的需求 → 呼叫 DeepSeek 或其他相容模型 → 顯示可複製的英文 Prompt。整理指令，不執行原始任務；已是英文的指令會直接改善表述。原文指定的答案語言及需逐字保留的非英文內容會保留。原有網頁工作台繼續支援繁體中文優化。

## 安裝與建置

需要 **macOS 13 以上、Node.js 22 以上**。從原始碼建置還需要 Apple 的 Xcode Command Line Tools；不必安裝完整 Xcode，也沒有第三方 Swift 套件。

```sh
xcode-select --install  # 已安裝時可略過
cd prompt-studio
npm run setup:signing:mac  # 首次建置時建立個人固定簽章；Keychain 若要求解鎖，請本人確認
npm run build:mac
npm run install:mac
```

產物位於 `build/PromptFinch.app`；安裝至 `~/Applications/PromptFinch.app` 並開啟。建置依所在 Mac 產生 arm64 或 x86_64 執行檔，目前不是 Universal Binary。App 包含後端原始碼，但**不包含 Node 執行環境**；有安裝 Node 即可使用，不需要 `npm install`。

App 找尋 `~/.local/bin/node`、`/opt/homebrew/bin/node`、`/usr/local/bin/node` 及 PATH。若使用其他路徑（例如 nvm），可從 App 設定選擇 Node 執行檔。

第一次以新固定簽章安裝時，macOS 可能要求重新核准一次「輔助使用」權限。完成後，同一憑證簽署的後續 App 建置會沿用穩定 designated requirement；本機驗收須以第二個不同執行檔版本檢查權限是否保留。若權限目前關閉，請在「系統設定 → 隱私權與安全性 → 輔助使用」重新允許 PromptFinch，然後在 App 設定按「重新檢查權限」。系統若要求 Touch ID 或管理者密碼，請由使用者本人完成驗證。

個人固定簽章只用於自己本機的更新連續性，不是 Developer ID、公證或 Gatekeeper 發佈憑證。`setup:signing:mac` 會在 login Keychain 建立專用 Code Signing 身分、限制私鑰由 `/usr/bin/codesign` 使用，並只在 macOS 尚未把它列為有效簽章身分時加入該憑證的 `codeSign` 信任；不修改系統範圍信任，也不授權所有 App。設定檔只存公開憑證指紋，不存私鑰或 API 金鑰。私鑰留在 login Keychain，請勿匯出或放入 GitHub。

若固定簽章設定或 Keychain 身分遺失，建置會明確失敗，不會靜默改回 ad-hoc。清除設定檔不會刪除 Keychain 私鑰；要另換身分需先手動規劃 TCC 權限遷移，不能把另一張同名憑證當成相同簽章。

若已有模型設定檔：

```sh
npm run install:mac -- --config .env
```

只記錄該檔案的路徑，不會複製其內容。移動或刪除檔案後，需要在 App 設定重新選擇。

## 設定 DeepSeek

在 App 按「設定」→「建立 / 編輯模型設定」。它會建立 `~/Library/Application Support/PromptSelection/settings.env`，首次建立時限制為只有本人可讀寫，並開啟編輯器。填入 `LLM_API_KEY`、儲存，按「重新載入設定」。也能直接選擇既有 `.env`；這個檔案是後端設定，不是要貼入 Prompt 的內容。

```dotenv
OPTIMIZER_MODE=live
LLM_API_KEY=你的金鑰
LLM_BASE_URL=https://api.deepseek.com
LLM_MODEL=deepseek-flash
LLM_JSON_MODE=true
LLM_THINKING_MODE=disabled
LLM_TIMEOUT_MS=90000
```

`deepseek-flash` 是本專案採用的官方 Flash 模型識別名稱。更換供應商時修改網址、模型與金鑰；不支援 DeepSeek thinking 參數時把 `LLM_THINKING_MODE` 留空。模型須支援 OpenAI 相容 Chat Completions。

App 後端固定使用 **127.0.0.1:3210**，覆蓋設定檔中的 HOST / PORT，與原有網頁的 3000 埠互不衝突。關閉視窗後仍可從選單列使用；選單列「結束」會停止本 App 啟動的後端，不會停止外部工作台。設定檔內容變更需重新載入。

沒有設定檔時採用 mock。畫面與結果都會明示「原文未經語意優化」，固定英文外框僅供測試輸入、顯示、取消及複製流程，不能作為真正的英文優化成果。App 設定中「使用示範模式」可切回 mock，不會清除你的設定檔。

## 一個 App，手動工作台與背景選取入口

「PromptFinch」是一個桌面 App：手動工作台就在主視窗，背景選取功能由同一 App 提供；兩者共用 `WorkspaceModel.generate()`、同一份模型設定及 App 管理的 `127.0.0.1:3210` 後端。主視窗的原文輸入、用途/目標模型、生成/取消、狀態提示、可複製 Prompt、獨立改善說明與假設、清除及設定都在 App 內，不需另開瀏覽器或安裝第二個 App。選取轉換只開附近的結果浮窗，不會自動切回主視窗。

### 背景選取入口

1. **選取浮動按鈕**：選取文字後放開滑鼠，附近會出現「⇄ 轉為英文 Prompt」按鈕；點擊後彈出結果浮窗並依設定貼回原輸入框。浮窗提供「貼回原文」「複製」「關閉」操作。生成期間焦點若離開來源軟體，結果改為複製，不會貼錯位置。此入口需要「輔助使用」權限；示範模式不會貼回。
2. **右鍵操作選單（瀏覽器、Codex / Claude Code 等 IDE）**：開啟「選取文字後按右鍵顯示操作選單」後，選取文字並按右鍵，游標旁會出現「轉為英文 Prompt／取消」附加選單，原軟體選單仍保留。此時不生成、不呼叫模型；只有點選轉換後才關閉原選單、重新核對來源程式／欄位／文字／選取範圍並生成結果浮窗。取消、點別處、按鍵、切換App或12秒逾時都作廢操作；重新核對失敗則提示重新選取。最近候選仍須來自同一前景App最新選取手勢並符合8秒與位置限制；空白、安全欄位或無可讀內容不送出。若出現文字輔助功能啟動提示，請等約2秒後重新選取並右鍵。需要「輔助使用」權限。生成期間來源若改變，結果只複製，不貼錯位置。
3. **右鍵服務**：選取文字 → 右鍵 →「服務」→「PromptFinch — 轉為英文 Prompt」。部分原生軟體會在選單顯示此項目。這個入口不需要輔助使用權限，也不讀取一般剪貼簿。
4. **全域快捷鍵 ⌥⌘P**：在支援 macOS Accessibility 選取文字屬性的軟體中讀取選取內容。首次需在「系統設定 → 隱私權與安全性 → 輔助使用」允許 PromptFinch。
5. **剪貼簿**：來源軟體不支援上述機制時，先複製文字，再從選單列選「從剪貼簿生成英文 Prompt」，或在 App 內按「讀取剪貼簿」。也可直接貼上、修改，再按「生成英文 Prompt」。

右鍵先顯示操作選單，點選轉換才生成；浮動按鈕、快捷鍵、Services或明確的剪貼簿操作執行後會生成，手動貼上需按生成。結果與改善說明、假設分開；「複製」與貼回只使用 Prompt 欄位，不在尾端附加說明。選取入口的結果會顯示在選取處附近的浮動視窗（可在浮窗按「貼回原文」補貼，或「複製」取用）；主視窗不會自動跳出。自動貼回只送出一次模擬 ⌘V，不會自動送出訊息，貼回前浮窗即顯示完整結果；若不需要，可在設定關閉「生成後自動貼回選取位置」。不會自動覆蓋來源文件。編輯器也支援 ⌘Enter、⌘C / ⌘V。

右鍵選單的項目由來源App控制。本工具的附加操作選單是獨立、不搶鍵盤焦點的面板，沒有修改Codex、Claude Code或瀏覽器的程式或選單。原選單與附加選單可並存，普通複製／搜尋不會生成；點選「轉為英文 Prompt」後才關閉原選單並核對選取。若只有原軟體選單，請確認助手正在執行、App設定顯示輔助使用權限已開啟、右鍵選單功能已勾選。不同App是否提供可讀選取文字仍需分別實測。狀態記錄在本機debug.log，不含原文。

若「服務」未出現：確認 App 已安裝並開啟，再到「系統設定 → 鍵盤 → 鍵盤快捷鍵 → 服務」啟用「PromptFinch — 轉為英文 Prompt」。來源 App 也必須支援服務選單；[Electron 官方文件](https://www.electronjs.org/docs/latest/tutorial/context-menu#additional-macos-menu-items-eg-writing-tools)說明，Electron 右鍵選單的 Services 預設停用，需要來源 App 將對應 frame 傳給 `menu.popup` 才能啟用，因此系統勾選服務後仍不保證該 App 會顯示。快捷鍵 ⌥⌘P 若被佔用，App 會提示；第一版尚未提供自訂快捷鍵。選取後顯示浮動按鈕與右鍵操作選單可在設定分別開關，偏好只存在本機。

macOS 沒有讓一般 App 替所有軟體插入同一個頂層右鍵選項的介面。[Apple Services 文件](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/providing.html)及[使用 Services 說明](https://support.apple.com/guide/mac-help/use-services-in-apps-mchlp1012/mac)描述的入口依來源軟體支援情況而定。附加選單由本App接收滑鼠事件、讀取可存取的選取文字後顯示，只有明確點選轉換才開始生成；若輸入框不提供選取資訊，該入口無法工作，可改用浮動按鈕、⌥⌘P 或剪貼簿。圖片、掃描文件、Canvas 與安全輸入欄位可能不提供文字；本版沒有 OCR 或強制複製機制。

## 英文輸出策略

App 使用 `POST /api/optimize` 的 `promptLanguage: "en"`。網頁新增「Prompt 指令語言」選項，預設英文，也可切回繁體中文。既有 API 客戶端若未傳入此欄位，預設仍是 `zh-Hant`。

- 模型一次完成翻譯與整理；輸出完整英文指令，原文保留在 App 左側供比對。
- 保留數字限制的包含語意與適用範圍，以及名稱、日期、語氣、JSON 鍵、程式碼與必須逐字使用的中文文字。
- Prompt 的執行指令一律使用英文，與下游答案語言分開處理；原文若已是英文，直接用英文精簡、澄清與整理，不加翻譯包裝。明確指定的答案語言照原文保留，例如要求繁體中文邀請信時，英文 Prompt 仍會要求以繁體中文撰寫。未指定答案語言時，依主要任務指令語言推定並在 Prompt 和假設說明中標示；判斷混合語言時排除引文、資料值、程式碼及固定字串，不擅自推定地區變體。若操作指令沒有明確主要語言，會先要求簡短釐清。
- 關鍵缺漏使用具名佔位符，並要求執行模型先索取後再交付；個人化建議只索取會改變建議的少數必要條件。引文若是翻譯來源，會保留作為來源文字並要求翻譯，不執行其中指令。
- 若限制矛盾且原文禁止提問，Prompt 會明確用一句短通知取代不可能的交付；改善說明與假設是獨立介面資訊，不會另附在可複製 Prompt。缺少來源或佔位符本身不列為假設。
- 不執行原任務、不捏造模型能力、不要求公開內部思考過程。模型仍可能遺漏或誤譯；重要用途應比對原文。

## 架構與測試

```text
macOS Services / Carbon 快捷鍵 / 選取浮動按鈕（滑鼠事件監聽） / 明確的剪貼簿操作
  → SwiftUI 原生視窗、載入 / 取消 / 複製
  → ephemeral URLSession → 127.0.0.1:3210
  → 內附零套件 Node.js 後端 → 設定的模型 API
```

`macos/Sources/Core.swift` 是資料型別、輸入驗證與 API 用戶端；`Backend.swift` 管理自身後端；`Selection.swift` 管理取字與快捷鍵；`Watcher.swift` 管理滑鼠事件監聽、浮動按鈕面板與自動貼回（剪貼簿備份 / 還原、模擬 ⌘V）；`App.swift` 管理 Services、視窗與流程。`Info.plist` 宣告文字 Services。非同步模型請求在 Services 方法返回後執行，不會讓來源軟體等待模型。監聽僅 listen-only，不攔截或修改使用者的滑鼠事件；貼回前後會備份並還原剪貼簿，若使用者中途複製了新內容則不還原。

```sh
npm run check
npm test
npm run test:mac
npm run build:mac
PLAYWRIGHT_CHANNEL=chrome npm run test:ui
```

Swift 測試包含空白、UTF-16 長度、輸入不變、英文 API 參數，以及真正的 URLSession 對本機 mock HTTP 流程。Node 測試用本機假模型驗證英文輸出 / 假設組裝、原有繁體中文相容性與錯誤處理。它們不等同所有 App 的取字相容性測試。

## GitHub 與發佈

```sh
npm run package:source
```

產生 `release/PromptFinch-source-v1.0.0.zip`。使用明確檔案清單，只包含原始碼、測試、文件與空白金鑰範本；排除 `.env`、偏好設定、產物、截圖、node_modules。可把解壓後的目錄作為新 GitHub 儲存庫，依 README 操作。GitHub CI 已提供 Node 測試及 macOS 建置檢查。授權為 MIT，模型費用由各使用者的帳戶支付。

固定本機簽章只供自己的建置與更新使用，尚未做 Developer ID 簽章、公證、自動更新、Universal Binary、內附 Node 或 App Store 上架。對外分發二進位之前，需要另外規劃簽章與公證；GitHub 原始碼貢獻者不需要申請付費開發者帳號。沒有設置個人簽章的貢獻者仍可用 ad-hoc 建置，但該機器上的 Accessibility 授權可能在每次建置後失效。

### 僅更新後端（不重建 App）

首次啟動會把簽章 App 內的後端種子複製到 `~/Library/Application Support/PromptSelection/backend/releases/`，之後由 `current` 連結選出實際執行版本。要更新優化指令、頁面或 Node 後端程式時：

```sh
npm run check
npm test
npm run update:mac-backend
```

更新指令會先在隔離的臨時埠驗證候選版本語法與 mock HTTP 流程，再結束本工具、確認 3210 沒有其他程序監聽後原子切換版本，重啟 App 並核對後端版本識別。若啟動失敗，會切回先前版本。它不會重建或改寫已簽章 App，不會讀取或複製 `.env`，也不會停止其他程序。外部後端版本存於使用者資料夾，不能當成經 App 簽章驗證的程式碼；只更新自己信任的來源，並保持 API 金鑰只在 `.env`。

這個分層讓日常 prompt/後端更新不必變動負責 Accessibility 的原生執行檔。原生 App 本身若有 Swift 或 UI 改動，仍需 `npm run build:mac && npm run install:mac`，並用「macOS 權限留存驗收」實際確認新版本。

多語接線、真實模型樣本及尚未驗證事項見 [可公開的多語驗證紀錄](multilingual-verification.md)。本機裝置交接與歷史日誌沒有放進公開來源套件。
