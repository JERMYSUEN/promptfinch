# PromptFinch

原生 macOS 工具：選取或貼上多語言需求 → 呼叫 DeepSeek 或其他相容模型 → 顯示可複製的英文 Prompt。除了翻譯，也按任務需要釐清目標、整理材料與限制、安排執行順序及必要核對；完整的小任務不強制加長。它整理指令，不執行原始任務，也不應擅自新增功能或交付物。已是英文的指令會直接改善表述；原文指定的答案語言及需逐字保留的非英文內容應予保留，但仍須檢視模型結果。網頁工作台另可選繁體中文指令輸出。

本頁是原生 App 的詳細指南；安裝總覽見 [英文 README](../README.md#build-and-install-the-macos-app)，終端使用見 [Terminal 指南](terminal.md)。介面可切換語言，不代表各語言的模型品質已全面等效。[目前的 Prompt 品質驗證](prompt-quality-verification.md)說明這次規則與模型覆核的證據及限制；先前的 [多語驗證範圍](multilingual-parity-verification.md) 與 [任務優化驗證限制](optimization-value-verification.md) 保留各自的歷史結果。

## 安裝與建置

編譯目標為 **macOS 13 以上**，另需安裝 **Node.js 22 以上**。最低 macOS 13 與實體 Intel 裝置尚未完成驗證。從原始碼建置還需要 Apple 的 Xcode Command Line Tools；不必安裝完整 Xcode，也沒有第三方 Swift 套件。

[v1.1.0 發行版](https://github.com/JERMYSUEN/promptfinch/releases/tag/v1.1.0) 提供 Apple Silicon 專用 `PromptFinch-1.1.0-macos-arm64.zip`、`PromptFinch-source-v1.1.0.zip`、`SHA256SUMS` 及公開輸入雜湊 manifest。解壓縮 App 後移至應用程式資料夾；Node 仍需另裝。公開 App 採 ad-hoc 簽章，未做 Developer ID 簽章或公證，macOS 可能阻擋不受信任的下載；請先評估來源並使用系統提供的安全控制。需要自行建置時使用下列指令。

```sh
git clone https://github.com/JERMYSUEN/promptfinch.git
cd promptfinch
xcode-select --install  # 已安裝時可略過
npm run setup:signing:mac  # 首次建置時建立個人固定簽章；Keychain 若要求解鎖，請本人確認
npm run build:mac
npm run install:mac
```

若已取得原始碼，直接在現有專案根目錄執行建置指令，不需再次複製儲存庫。

產物位於 `build/PromptFinch.app`；安裝至 `~/Applications/PromptFinch.app` 並開啟。建置依所在 Mac 產生 arm64 或 x86_64 執行檔，目前不是 Universal Binary。App 包含後端原始碼，但**不包含 Node 執行環境**；有安裝 Node 即可使用，不需要 `npm install`。

App 找尋 `~/.local/bin/node`、`/opt/homebrew/bin/node`、`/usr/local/bin/node` 及 PATH。若使用其他路徑（例如 nvm），可從 App 設定選擇 Node 執行檔。

第一次可先不設定金鑰，在明確標示的 mock 模式確認輸入、生成、取消與複製流程。手動工作台與剪貼簿入口可在沒有輔助使用權限時使用；跨 App 取字、背景選取按鈕與右鍵附加選單需要該權限。來源 App 提供的 Services 文字也可在沒有此權限時生成，但貼回仍需可驗證來源及權限。

第一次以新固定簽章安裝時，macOS 可能要求重新核准一次「輔助使用」權限。完成後，同一憑證簽署的後續 App 建置會沿用穩定 designated requirement；本機驗收須以第二個不同執行檔版本檢查權限是否保留。若權限目前關閉，請在「系統設定 → 隱私權與安全性 → 輔助使用」重新允許 PromptFinch，然後在 App 設定按「重新檢查權限」。系統若要求 Touch ID 或管理者密碼，請由使用者本人完成驗證。

個人固定簽章只用於自己本機的更新連續性，不是 Developer ID、公證或 Gatekeeper 發佈憑證。`setup:signing:mac` 會在 login Keychain 建立專用 Code Signing 身分、限制私鑰由 `/usr/bin/codesign` 使用，並只在 macOS 尚未把它列為有效簽章身分時加入該憑證的 `codeSign` 信任；不修改系統範圍信任，也不授權所有 App。設定檔只存公開憑證指紋，不存私鑰或 API 金鑰。私鑰留在 login Keychain，請勿匯出或放入 GitHub。

若固定簽章設定或 Keychain 身分遺失，建置會明確失敗，不會靜默改回 ad-hoc。清除設定檔不會刪除 Keychain 私鑰；要另換身分需先手動規劃 TCC 權限遷移，不能把另一張同名憑證當成相同簽章。

若已有模型設定檔：

```sh
npm run install:mac -- --config .env
```

只記錄該檔案的路徑，不會複製其內容。移動或刪除檔案後，需要在 App 設定重新選擇。

## 介面語言

在 App 按「設定」→「介面語言」，可選 **繁體中文、English、日本語、한국어**。切換立即更新工作台、設定、App 選單、右鍵附加選單與結果浮窗，不需重啟；不會清除正在編輯的原文或已生成的 Prompt。選擇只存於本機，重開後會保留；首次使用預設繁體中文。

這是介面語言設定，生成的 Prompt 仍使用英文，並保留原文要求的答案語言。模型回傳的改善說明、假設及使用者文字不由介面翻譯機制改寫。macOS 管理的 Services 名稱與系統對話框可能依系統語言顯示；本工具的右鍵附加選單會依 App 的介面語言顯示。

語言文案集中於 `macos/Sources/Localization.swift`，不依賴翻譯服務。切換語言不傳送文字、不呼叫模型，也不改動 API 金鑰或設定檔。

## 設定 DeepSeek

在 App 按「設定」→「建立 / 編輯模型設定」。它會建立 `~/Library/Application Support/PromptSelection/settings.env`，首次建立時限制為只有本人可讀寫，並開啟編輯器。填入 `LLM_API_KEY`、儲存，按「重新載入設定」。也能直接選擇既有 `.env`；這個檔案是後端設定，不是要貼入 Prompt 的內容。

```dotenv
OPTIMIZER_MODE=live
LLM_API_KEY=你的金鑰
LLM_BASE_URL=https://api.deepseek.com
LLM_MODEL=deepseek-flash
LLM_JSON_MODE=true
LLM_THINKING_MODE=disabled
LLM_QUALITY_REVIEW=false
LLM_TIMEOUT_MS=90000
```

`deepseek-flash` 是儲存庫 DeepSeek 範本使用的模型識別；請以自己供應商帳戶當前可用的模型名稱為準。後端會在 `LLM_BASE_URL` 後加上 `/chat/completions`，因此這裡填 API 基底網址，不填完整的 completions 路徑。更換供應商時修改網址、模型與金鑰；不支援 DeepSeek thinking 參數時把 `LLM_THINKING_MODE` 留空。不支援 JSON mode 時改為 `LLM_JSON_MODE=false`，但供應商仍須回傳本工具要求的 JSON 結構。原生 Claude 或 Gemini API 需相容閘道或 adapter，不能直接填入其原生網址。

工作台的「目標模型」只告訴優化器這份 Prompt 預計給哪個模型使用，不會切換負責生成的模型；實際呼叫由 `LLM_MODEL` 決定。「模型模式」或 API 的 `ready` 只表示必要設定已具備，不表示供應商連線已成功。模型錯誤不會靜默切換成 mock。

`LLM_QUALITY_REVIEW` 預設為 `false`；未設定或 `false` 時只編輯，一般呼叫一次，格式重試時最多兩次。模型覆核為可選功能，只有明確設為 `true` 才啟用，使用同一供應商與模型，以獨立請求脈絡對照原文覆核。啟用後一般成功流程為兩次呼叫；若內容被否決，最多修訂一次並再次覆核，含格式重試合計最多四次。全部共用 `LLM_TIMEOUT_MS`，後續呼叫不會重新計時。啟用覆核會增加付費用量與等待時間，覆核失敗則回報錯誤、不交付被否決的內容。目前證據不足以支持預設啟用，模型核准也不保證語意正確；mock 仍完全不呼叫模型。

App 後端固定使用 **127.0.0.1:3210**，覆蓋設定檔中的 HOST / PORT，與原有網頁的 3000 埠互不衝突。關閉視窗後仍可從選單列使用；選單列「結束」會停止本 App 啟動的後端，不會停止外部工作台。設定檔內容變更需重新載入。

沒有設定檔時採用 mock。畫面與結果都會明示「原文未經語意優化」，固定英文外框僅供測試輸入、顯示、取消及複製流程，不能作為真正的英文優化成果。App 設定中「使用示範模式」可切回 mock，不會清除你的設定檔。

App 與 `npm start` 的設定入口不同：在專案根目錄建立 `.env` 不會自動讓桌面 App 使用它，須在 App 設定明確選擇；反過來，App 選取的 `settings.env` 也不會自動套用到獨立的 3000 埠服務。App 啟動後端時會移除繼承的 `LLM_*` 環境設定，使用所選檔案，避免與其他終端環境混用。

## 一個 App，手動工作台與背景選取入口

「PromptFinch」是一個桌面 App：手動工作台就在主視窗，背景選取功能由同一 App 提供；兩者共用 `WorkspaceModel.generate()`、同一份模型設定及 App 管理的 `127.0.0.1:3210` 後端。主視窗的原文輸入、用途/目標模型、生成/取消、狀態提示、可複製 Prompt、獨立改善說明與假設、清除及設定都在 App 內，不需另開瀏覽器或安裝第二個 App。選取轉換只開附近的結果浮窗，不會自動切回主視窗。

首次使用時，選取浮動按鈕、右鍵附加選單及「生成後自動貼回可編輯的選取文字」預設開啟。若想先檢視結果再決定是否貼回，請在設定關閉自動貼回；關閉後，成功的 live 選取轉換仍會複製 Prompt 並顯示結果。手動工作台不自動貼回；已辨識終端固定只複製，不受此偏好影響。設定、用途與目標模型提示保存在本機偏好，原文與生成結果不作歷史保存。

### 背景選取入口

1. **選取浮動按鈕**：選取文字後放開滑鼠，附近會出現「⇄ 轉為英文 Prompt」按鈕；明確點擊時會重新核對前景 App、欄位、文字、範圍與逾時狀態，通過後才生成結果。按鍵、切換 App 或變更選取功能設定會取消舊操作。浮窗提供「貼回原文」「複製」「關閉」操作；無法確認貼回位置時改為複製供手動使用。此入口需要「輔助使用」權限；示範模式不會貼回。
2. **右鍵操作選單（瀏覽器、Codex / Claude Code 等 IDE）**：開啟「選取文字後按右鍵顯示操作選單」後，選取文字並按右鍵，游標旁會出現「轉為英文 Prompt／取消」附加選單，原軟體選單仍保留。此時不生成、不呼叫模型；只有點選轉換後才關閉原選單、重新核對來源程式／欄位／文字／選取範圍並生成結果浮窗。取消、點別處、按鍵、切換App或12秒逾時都作廢操作；重新核對失敗則提示重新選取。最近候選仍須來自同一前景App最新選取手勢並符合8秒與位置限制；空白、安全欄位或無可讀內容不送出。若出現文字輔助功能啟動提示，請等約2秒後重新選取並右鍵。需要「輔助使用」權限。生成期間來源若改變或無可信任範圍，結果改為複製供手動使用。
3. **右鍵服務**：選取文字 → 右鍵 →「服務」→「PromptFinch — 轉為英文 Prompt」。部分原生軟體會在選單顯示此項目。這個入口不需要輔助使用權限，也不讀取一般剪貼簿。
4. **全域快捷鍵 ⌥⌘P**：在支援 macOS Accessibility 選取文字屬性的軟體中讀取選取內容。首次需在「系統設定 → 隱私權與安全性 → 輔助使用」允許 PromptFinch。
5. **剪貼簿**：來源軟體不支援上述機制時，先複製文字，再從選單列選「從剪貼簿生成英文 Prompt」，或在 App 內按「讀取剪貼簿」。也可直接貼上、修改，再按「生成英文 Prompt」。

右鍵先顯示操作選單，點選轉換才生成；浮動按鈕、快捷鍵、Services或明確的剪貼簿操作執行後會生成，手動貼上需按生成。結果與改善說明、假設分開；「複製」與貼回只使用 Prompt 欄位，不在尾端附加說明。選取入口的結果會顯示在選取處附近的浮動視窗；主視窗不會自動跳出。貼回需要有效、非空且符合所選文字 UTF-16 長度的範圍，並重新確認前景 App、欄位與文字；已知唯讀欄位不貼回。只有文字資訊的選取仍可轉換，但需要手動貼上。

自動或手動貼回只送出一次模擬 ⌘V，不會自動送出訊息。畫面會顯示「已送出貼上操作」，請確認來源文字，因為來源軟體可能忽略模擬按鍵。這是貼上請求，不是原子文字替換；在最後一次核對與來源 App 接收按鍵之間仍可能發生焦點或選取競爭。剪貼簿還原結果會在回呼完成後顯示，區分已還原、保留較新的複製內容與還原失敗；關閉、清除或開始新的操作後，舊回呼不會重新開啟浮窗或覆蓋狀態。無法確認貼回位置時只複製結果；若剪貼簿無法完整備份、暫存失敗或立即還原失敗，會停止貼回並顯示結果，請檢查剪貼簿後自行決定是否複製。若不需要自動貼回，可在設定關閉「生成後自動貼回可編輯的選取文字」。編輯器也支援 ⌘Enter、⌘C / ⌘V。

右鍵選單的項目由來源App控制。本工具的附加操作選單是獨立、不搶鍵盤焦點的面板，沒有修改Codex、Claude Code或瀏覽器的程式或選單。原選單與附加選單可並存，普通複製／搜尋不會生成；點選「轉為英文 Prompt」後才關閉原選單並核對選取。若只有原軟體選單，請確認助手正在執行、App設定顯示輔助使用權限已開啟、右鍵選單功能已勾選。不同App是否提供可讀選取文字仍需分別實測。狀態記錄在本機debug.log，不含原文。

若「服務」未出現：確認 App 已安裝並開啟，再到「系統設定 → 鍵盤 → 鍵盤快捷鍵 → 服務」啟用「PromptFinch — 轉為英文 Prompt」。來源 App 也必須支援服務選單；[Electron 官方文件](https://www.electronjs.org/docs/latest/tutorial/context-menu#additional-macos-menu-items-eg-writing-tools)說明，Electron 右鍵選單的 Services 預設停用，需要來源 App 將對應 frame 傳給 `menu.popup` 才能啟用，因此系統勾選服務後仍不保證該 App 會顯示。快捷鍵 ⌥⌘P 若被佔用，App 會提示；第一版尚未提供自訂快捷鍵。選取後顯示浮動按鈕與右鍵操作選單可在設定分別開關，偏好只存在本機。

macOS 沒有讓一般 App 替所有軟體插入同一個頂層右鍵選項的介面。[Apple Services 文件](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/providing.html)及[使用 Services 說明](https://support.apple.com/guide/mac-help/use-services-in-apps-mchlp1012/mac)描述的入口依來源軟體支援情況而定。附加選單由本App接收滑鼠事件、讀取可存取的選取文字後顯示，只有明確點選轉換才開始生成；若輸入框不提供選取資訊，該入口無法工作，可改用浮動按鈕、⌥⌘P 或剪貼簿。圖片、掃描文件、Canvas 與安全輸入欄位可能不提供文字；本版沒有 OCR 或強制複製機制。

## Terminal／CLI 的選取文字

在 macOS 內建 Terminal 中使用 Claude Code 或 Codex CLI，可選取終端顯示的文字、按右鍵，再點選「轉為英文 Prompt」。選取須能透過 macOS Accessibility 讀取；只按右鍵仍不會送出模型請求。部分嵌入式終端是在原選單處理期間才準備可讀取的選取文字，因此右鍵放開後會有限度地重新取得當次選取，不沿用舊文字。

已辨識的終端來源只顯示並複製結果，不自動或手動送出模擬 ⌘V；結果浮窗不提供「貼回原文」。終端的反白範圍可能來自畫面或捲動記錄，不代表可替換的 CLI 輸入範圍。請檢視結果，再貼入 Claude Code／Codex CLI 的輸入區，最後自行送出。這個規則不受其他欄位的自動貼回偏好影響。

詳見 [Terminal 指南與手動驗收清單](terminal.md)。2026-10-11 已通過 233 項原生檢查、55 項 Node 測試及建置／簽章檢查，並安裝新版。桌面操作工具禁止控制 Terminal；使用者以實體滑鼠確認 Apple Terminal 的附加選單出現，且點選後能生成英文結果。回覆未分別記錄 Claude Code／Codex CLI，剪貼簿、手動貼入、取消與無自動輸入等完整驗收仍待確認。無可讀選取時可明確複製後使用選單列剪貼簿入口；不使用 OCR、全畫面文字掃描或強制複製。

## 英文輸出策略

App 使用 `POST /api/optimize` 的 `promptLanguage: "en"`。網頁新增「Prompt 指令語言」選項，預設英文，也可切回繁體中文。既有 API 客戶端若未傳入此欄位，預設仍是 `zh-Hant`。

- 模型整理為完整英文指令；只有明確啟用可選覆核時，才再以獨立請求覆核。原文保留在 App 左側供比對，不附加為可複製 Prompt 的指令外框。API 的繁體中文模式也直接回傳完整指令。
- 保留數字限制的包含語意與適用範圍，以及名稱、日期、語氣、JSON 鍵、程式碼與必須逐字使用的中文文字。
- Prompt 的執行指令一律使用英文，與下游答案語言分開處理；原文若已是英文，直接用英文精簡、澄清與整理，不加翻譯包裝。明確指定的答案語言照原文保留，例如要求繁體中文邀請信時，英文 Prompt 仍會要求以繁體中文撰寫。需要自然語言答案但未指定語言時，只依明確的主要任務指令語言推定，並在 Prompt 和假設說明中標示；判斷混合語言時排除引文、資料值、程式碼及固定字串，不擅自推定地區變體。沒有明確主要語言時，僅在允許提問時釐清；禁止提問時採用下述限制通知，不擅自選定答案語言。
- 分開檢查關鍵資訊「尚未提供」與「雖有資料但不足以判斷」，保留原文兩種條件的範圍。允許提問時，只索取影響判斷的必要資訊，並在相依交付前等待；具名佔位符不等於資料已提供，也不算假設。已提供的檔案／網址或要求執行模型研究取得的資料，應先嘗試可用工具，不能只因原文未貼全文便宣稱缺漏。引文若是翻譯來源，會保留作為來源文字並要求翻譯，不執行其中指令。
- 禁止提問適用於矛盾、關鍵來源或判斷條件不足、工具無法存取及答案語言不明等情況。若因此無法忠實完成，遵守原文明示的可行替代方案，否則只要求簡短說明阻礙，不提問、不捏造資料，也不同時要求執行不可能的交付。改善說明與假設是獨立介面資訊，不會另附在可複製 Prompt。
- 已清楚的要求可以不再編輯，`improvements` 可為空陣列；工作台會另顯示「未提供額外改善說明。」而非製造改善項目。兩種指令語言都會以有限規則還原僅因 NFC 正規化而改動、且可明確判定的引號／程式碼固定字串；不能靠此重建被省略或翻譯的內容。
- 不執行原任務、不捏造模型能力、不要求公開內部思考過程。模型仍可能遺漏或誤譯；重要用途應比對原文。

「要求」描述的是模型策略，不能視為每次輸出都已達成的保證；即時回應的 `modelReview.status` 為 `approved` 也只是模型覆核結果，不是品質認證。新生成的改善說明與假設會要求模型使用目前介面語言，切換語言不重寫已生成的內容；請到主工作台展開說明查看，浮窗主要呈現 Prompt 與操作狀態。主工作台另有「對照原文與結果」，保留生成當時的原文快照並逐行標示改寫；標示不代表語意正確性已驗證。

## 常見問題

| 現象 | 處理方式 |
| --- | --- |
| 找不到 Node 或後端無法啟動 | 確認選的是 Node.js 22 以上的執行檔；設定中的 Node 路徑應指向 `node`，不是安裝目錄、shell 或套件管理器。檢查後按重新載入。 |
| 3210 已被使用／後端版本不符 | 結束重複的 PromptFinch 實例。若是其他服務佔用，先自行辨認來源；不要任意停止程序或把桌面後端改到任意位址。App 不會接管陌生後端。 |
| 設定已儲存但仍是示範／舊模型 | 在 App 重新選取正確檔案並重新載入；只修改專案 `.env` 不會自動套用至桌面 App。live 必須設定 `OPTIMIZER_MODE=live`、金鑰與實際模型名稱。 |
| 供應商拒絕授權或設定 | 檢查金鑰權限、帳戶額度、基底網址與模型名稱。400／404／422 類設定錯誤也可能來自不支援 JSON／thinking 參數。不要把金鑰或原始供應商回應貼進公開 Issue。 |
| 502／504、頻率限制或結果格式／覆核錯誤 | 檢查供應商狀態、網路、額度與共用逾時預算，縮短輸入後再試。預設僅編輯，一般一次、格式重試時最多兩次呼叫；明確啟用可選覆核後通常兩次、含修訂與重試最多四次，會增加費用。已啟用的覆核失敗不交付被否決的結果；取消不保證供應商尚未處理或計費。 |
| 選取後沒有按鈕或右鍵項目 | 確認 App、輔助使用與相應入口已開啟，重新選取後再試。來源可能沒有暴露 Accessibility 文字；改用自己明確執行的複製／手動工作台。 |
| 升級後仍像舊版的優化規則 | 安裝 App 不會覆蓋既有的外部後端 `current`；在新 App 設定按「使用此 App 隨附後端」，或依下方指令更新可信任的原始碼後端。 |

診斷日誌位於 `~/Library/Application Support/PromptSelection/debug.log`。它記錄時間、來源程序／bundle 識別、事件、文字長度與狀態，不記錄 Prompt、結果、金鑰或按鍵內容；沒有自動輪替。回報前請先檢視並遮蔽不想公開的程式與操作資訊。正常結束 App 後可刪除這個日誌，下次執行需要時會重建。一般問題請附合成重現步驟，疑似安全漏洞則依 [安全回報方式](../SECURITY.md#reporting-a-vulnerability)處理。

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

Swift 測試編譯全部原生來源，包含空白、UTF-16 長度、輸入不變、英文 API 參數，以及真正的 URLSession 對本機 mock HTTP 流程。選取與貼回測試使用合成來源及獨立命名剪貼簿，檢查選取變動、範圍缺失、唯讀欄位、焦點切換、暫存／還原失敗與較新的複製內容；`WorkspaceTests.swift` 以假操作驗證貼回狀態、過期回呼、關閉與清除。Node 測試用本機假模型驗證英文輸出 / 假設組裝、原有繁體中文相容性、Host／Origin 白名單與錯誤處理。它們不等同所有 App 的取字相容性測試。

## GitHub 與發佈

```sh
npm run package:source
```

產生 `release/PromptFinch-source-v1.1.0.zip`。使用明確檔案清單，只包含原始碼、測試、文件與空白金鑰範本；排除 `.env`、偏好設定、產物、截圖、node_modules。GitHub 原始碼位於 [JERMYSUEN/promptfinch](https://github.com/JERMYSUEN/promptfinch)；ZIP 也可供離線檢視或依 README 建置。GitHub CI 已提供 Node 測試及 macOS 建置檢查。授權為 MIT，模型費用由各使用者的帳戶支付。

公開 App 套件請在有 Node.js 22+ 與 Xcode Command Line Tools 的 macOS 執行 `npm run package:mac`。它從明確列出的公開檔案建立乾淨副本，以 ad-hoc 簽章建置 Apple Silicon App，不讀取真實 `.env`、本機偏好或個人簽章設定；另產生來源 ZIP、`SHA256SUMS` 與 `PromptFinch-1.1.0-macos-arm64.verification.json`。manifest 記錄相對輸入路徑與 SHA-256，便於核對包內來源；這不是公證或發布者身分保證。指令不會自動上傳 GitHub。

固定本機簽章只供自己的建置與更新使用；公開下載採 ad-hoc 簽章，尚未做 Developer ID 簽章、公證、自動更新、Universal Binary、內附 Node 或 App Store 上架。GitHub 原始碼貢獻者不需要申請付費開發者帳號。沒有設置個人簽章的貢獻者仍可用 ad-hoc 建置，但該機器上的 Accessibility 授權可能在每次建置後失效。

### 僅更新後端（不重建 App）

首次啟動會把簽章 App 內的後端種子複製到 `~/Library/Application Support/PromptSelection/backend/releases/`，之後由 `current` 連結選出實際執行版本。要更新優化指令、頁面或 Node 後端程式時：

```sh
npm run check
npm test
npm run update:mac-backend
```

更新指令會先在隔離的臨時埠驗證候選版本語法與 mock HTTP 流程，再結束本工具、確認 3210 沒有其他程序監聽後原子切換版本，重啟 App 並核對後端版本識別。若啟動失敗，會切回先前版本。它不會重建或改寫已簽章 App，不會讀取或複製 `.env`，也不會停止其他程序。外部後端版本存於使用者資料夾，不能當成經 App 簽章驗證的程式碼；只更新自己信任的來源，並保持 API 金鑰只在 `.env`。

已有 `current` 後，重新建置或安裝 App 仍使用該版本，**不會自動以新 App 內的種子覆蓋外部後端**。下載新版 App 後若要採用它附帶的規則，開啟設定中執行階段區塊的「使用此 App 隨附後端」。這個明確操作會暫存並驗證隨附後端、停止自身服務後切換啟動；失敗時會嘗試恢復原先後端。它保留模型設定檔、Node 路徑與偏好，不會下載檔案或呼叫模型。切換前先保留未完成文字；不要刪除整個支援資料夾來更新。

若從原始碼同時修改 Swift 與後端，先建置／安裝原生 App，再用命令更新後端：

```sh
npm run build:mac
npm run install:mac
npm run update:mac-backend
```

這些安裝／更新動作會正常結束正在執行的 App；執行前先複製任何仍需保留的未完成文字。更新會保留所選模型檔案路徑，並保留目前與上一個版本供回復；若自動回復失敗，先讀取錯誤與檢查埠使用狀態，不要刪除整個 `PromptSelection` 資料夾。該資料夾還含模型設定與本機簽章設定。

這個分層讓日常 prompt/後端更新不必變動負責 Accessibility 的原生執行檔。原生 App 本身若有 Swift 或 UI 改動，仍需 `npm run build:mac && npm run install:mac`，並用「macOS 權限留存驗收」實際確認新版本。

目前這次編輯與覆核的證據見 [Prompt 品質驗證](prompt-quality-verification.md)。多語接線的歷史樣本見 [原始多語驗證紀錄](multilingual-verification.md)、[多語對照驗證](multilingual-parity-verification.md) 與 [任務優化驗證](optimization-value-verification.md)；它們不是目前版本所有語意案例均通過的證明。本機裝置交接與執行日誌沒有放進公開來源套件。

## 移除 App 與本機資料

先從選單列結束 PromptFinch，再移除自己安裝的 `~/Applications/PromptFinch.app`。需要保留金鑰設定或本機簽章身分時，請保留 `~/Library/Application Support/PromptSelection/`；移除 App 不會自動刪除它、其他位置的 `.env`、系統剪貼簿、偏好或 Keychain 內的簽章私鑰。本專案沒有自動清除所有資料的解除安裝程式。

若要清除本機設定，先備份必要資料，再逐項移除自己確認不再需要的 `settings.env`、`debug.log` 與 `backend/`。刪除 `code-signing.json` 並不會刪除 Keychain 身分，反而可能使後續建置改用 ad-hoc 並重新要求輔助使用授權；切勿把整個資料夾刪除當成通用修復方式。系統的輔助使用清單可由使用者移除 PromptFinch；其他軟體、剪貼簿管理器與模型供應商保留的資料不在本工具的清除範圍內。
