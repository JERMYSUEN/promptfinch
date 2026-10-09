[English](../../README.md) · [简体中文（zh-CN）](README.zh-CN.md) · **繁體中文（zh-TW）** · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português](README.pt.md) · [Italiano](README.it.md) · [Русский](README.ru.md) · [Türkçe](README.tr.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Українська](README.uk.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [हिन्दी](README.hi.md) · [বাংলা](README.bn.md) · [Bahasa Indonesia](README.id.md) · [Tiếng Việt](README.vi.md) · [ไทย](README.th.md) · [தமிழ்](README.ta.md) · [తెలుగు](README.te.md) · [मराठी](README.mr.md) · [العربية](README.ar.md) · [اردو](README.ur.md) · [فارسی](README.fa.md) · [Kiswahili](README.sw.md) · [ਪੰਜਾਬੀ](README.pa.md) · [Filipino](README.fil.md)

# PromptFinch

**選取。潤飾。貼上。**

PromptFinch 是通用的 Prompt 編輯與優化工具，適用於寫作、程式開發、研究、摘要與規劃。將粗略需求整理成更清楚的指令，供你選擇的模型使用。

macOS App 結合手動工作台與選取助手：在相容 App 選取文字後按右鍵，於輔助操作選單選擇 **Convert to an English Prompt**，再於附近面板檢視結果。單純按右鍵不會生成或傳送內容給模型。另有使用相同後端的瀏覽器工作台與 HTTP API。

macOS App 與 API 的英文模式會將多語輸入整理為英文 Prompt，並以保留明確需求、指定答案語言與固定字串為設計目標。它只會編輯指令，不會執行原始任務。使用前請檢查生成結果。

## 功能

- 接受原始 Prompt、任務類型，以及可選的下游目標模型名稱。
- 產生可複製的 Prompt，並將優化說明與假設分開呈現；複製及貼回只會使用 Prompt 欄位。
- macOS App 提供手動輸入、選取操作、結果面板、模型設定及可選的貼回功能。
- 處理空白輸入、長度限制、載入、取消與易懂的錯誤訊息。
- 可在明確標示的 mock 模式下免金鑰檢查流程，或由 Node.js 後端呼叫已設定的 OpenAI 相容模型。

GitHub 專案名稱建議為 `promptfinch`。請參閱[更名與相容性說明](../branding.md)。任務類型包括通用、寫作、分析、程式開發、摘要與行銷；研究與規劃可選分析或通用。可選的**目標模型**只作為編輯 Prompt 的提示，不會切換後端生成模型；後端模型由 `LLM_MODEL` 設定。

目前介面及優化／假設說明主要使用繁體中文。本專案文件提供 29 種語言／文字版本，但不包含 App 介面的翻譯，也不代表所有輸入語言均已通過驗證。

## 系統需求

| 用途 | 需求 |
| --- | --- |
| 瀏覽器工作台／HTTP API | Node.js 22 或更新版本；不需第三方執行階段套件。 |
| macOS 原生 App | macOS 13 或更新版本作為編譯目標，並安裝 Node.js 22+ 執行階段。App 不內含 Node。 |
| 建置 macOS App | Apple Xcode Command Line Tools，包含 Swift 與 Apple 簽署工具；不需要完整 Xcode。 |
| 開發與瀏覽器測試 | `npm ci` 安裝開發依賴；Playwright 需要已安裝的測試瀏覽器。 |

原生建置會依 Node 程序架構產生 `arm64` 或 `x86_64`，不是 Universal Binary。已記錄的原生檢查是在 Apple Silicon 上執行；尚未在實體 Intel 裝置或最低 macOS 13 版本上驗證。

以下指令請在專案根目錄、macOS 或常見 Linux 環境提供的 POSIX shell 執行。

## 快速開始

### 瀏覽器示範（不需 API 金鑰）

```sh
# Create a local configuration only if one does not already exist.
cp -n .env.example .env
npm start
```

開啟 [http://127.0.0.1:3000](http://127.0.0.1:3000)。若 `.env` 已存在，請先檢查內容，並設定 `OPTIMIZER_MODE=mock` 進行本機示範，不要覆寫原檔。執行服務不需要 `npm install`。

**Mock 輸出不會翻譯，也不會進行語意優化。**它是用來檢查輸入、載入、結果顯示及複製流程的範本，不會呼叫模型或將 Prompt 傳送給供應商。

瀏覽器預設使用英文指令。選擇 **繁體中文 Prompt** 可使用原本的中文優化流程。這只控制指令語言；原始需求中明確指定的答案語言仍會保留。Mock 模式會清楚說明內容並未真正翻譯。

### 建置並安裝 macOS App

```sh
xcode-select --install  # Skip if Command Line Tools are already installed.
npm run setup:signing:mac
npm run build:mac
npm run install:mac
```

建置結果為 `build/PromptFinch.app`。安裝程式會將 App 放入使用者的 `~/Applications` 並開啟。無須另外啟動瀏覽器伺服器：App 會在 `http://127.0.0.1:3210` 啟動自己的後端。

安裝程式會將既有的 `Prompt 選取助手.app` 遷移為 `PromptFinch.app`，並保留簽署身分、設定路徑與已儲存的偏好設定；詳見[更名說明](../branding.md)。

`setup:signing:mac` 是每台電腦各自執行一次的本機簽署身分設定。私密簽署金鑰會存放在登入鑰匙圈；macOS 可能要求確認存取。這有助於本機重建時維持輔助使用身分。這不是 Developer ID 簽署或公證，且不得發布簽署金鑰。若既有簽署設定無效，建置會停止，不會暗中取代身分。

若未選取模型設定，App 會使用 mock 模式。在「設定」中建立或選取模型設定檔、填入供應商設定並重新載入設定。若 App 找不到 Node，請在「設定」中選擇其執行檔。

也可在安裝時指定既有設定：

```sh
npm run install:mac -- --config .env
```

更多 macOS 設定請參閱目前以繁體中文撰寫的 [macOS 指南](../macos.md)。

## 模型設定

即時生成使用 **OpenAI 相容的 Chat Completions** 端點。後端會在 `LLM_BASE_URL` 後附加 `/chat/completions`。使用者需自行提供模型供應商帳號並負擔該帳號產生的費用。

新設定可參考 [.env.deepseek.example](../../.env.deepseek.example)：

```dotenv
OPTIMIZER_MODE=live
LLM_API_KEY=YOUR_MODEL_API_KEY
LLM_BASE_URL=https://api.deepseek.com
LLM_MODEL=deepseek-flash
LLM_JSON_MODE=true
LLM_THINKING_MODE=disabled
LLM_TIMEOUT_MS=90000
HOST=127.0.0.1
PORT=3000
```

請在私人本機設定中以自己的金鑰取代 `YOUR_MODEL_API_KEY`。修改既有 `.env`，不要覆寫它。瀏覽器伺服器的設定變更後需重新啟動；Mac App 則需重新載入所選設定。

其他相容供應商可替換基本 URL、金鑰與模型識別碼。若供應商不接受 DeepSeek 思考參數，請將 `LLM_THINKING_MODE` 留空。若供應商不接受 JSON 模式，請設定 `LLM_JSON_MODE=false`；但它仍必須回傳優化器要求的有效 JSON。原生 Claude 或 Gemini 端點需要介接器或相容閘道，不能直接填入 Chat Completions URL。

不需驗證的本機相容服務可以 `LLM_API_KEY=local-only` 作為非機密佔位值，並設定該服務實際的基本 URL 與已載入模型名稱。這不會啟動或隨附本機模型。

| 變數 | 預設值 | 說明 |
| --- | --- | --- |
| `OPTIMIZER_MODE` | `mock` | `mock` 使用範本；`live` 呼叫模型。 |
| `LLM_API_KEY` | 空白 | 僅供後端使用的 Bearer 認證；即時模式必填。 |
| `LLM_BASE_URL` | `https://api.openai.com/v1` | 相容 API 基本 URL；不得含內嵌認證、查詢或片段。 |
| `LLM_MODEL` | 空白 | 供應商模型識別碼；即時模式必填。 |
| `LLM_JSON_MODE` | `true` | 傳送 `response_format: {type: "json_object"}`。 |
| `LLM_THINKING_MODE` | 空白 | 留空時不傳送；可用 `enabled` 或 `disabled`。 |
| `LLM_TIMEOUT_MS` | `45000` | 請求／回應逾時；整數範圍 10 至 180000 毫秒。 |
| `HOST` | `127.0.0.1` | 獨立伺服器的監聽位址。 |
| `PORT` | `3000` | 獨立伺服器連接埠。 |

Mac App 無論所選設定檔中的值為何，都會將 `HOST` 與 `PORT` 設為 `127.0.0.1:3210`。獨立瀏覽器伺服器可使用另一個連接埠。

即時設定或供應商呼叫失敗時會回報錯誤，不會默默改用 mock 結果。`/api/config` 的 `ready` 表示設定已填妥，不代表已成功連上上游模型。

## 範例：Prompt 語言與答案語言

原始需求：

> 撰寫一段簡短邀請。保持 ACME-42 不變。請用西班牙文回答。

以下是示意優化結果，並非記錄到的模型回應：

```text
Write a brief invitation in Spanish. Preserve the exact text "ACME-42" wherever it occurs.
```

指令本身為英文，但要求下游模型撰寫的邀請仍為西班牙文。優化器回傳的是指令，而不是代為撰寫邀請。模型收到的指示包括保留明確需求與固定字串、標示合理假設並避免改變任務意圖；仍應檢查遺漏或誤譯。

## 多語輸入與涵蓋範圍

- 輸入、JSON 傳輸及原生選取均支援 Unicode。12,000 字元上限以 UTF-16 code unit 計算，與 JavaScript 及 Swift 的 UTF-16 視圖一致，並非可見字母或字素叢集數。超過上限會拒絕請求，不會截斷。選取範圍不能切開 surrogate pair。參閱 [JavaScript length](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String/length) 與 [Swift UTF16View](https://developer.apple.com/documentation/swift/string/utf16view)。
- 韓語諺文、俄語西里爾字母、由右至左文字、組合附加符號、連接符、表情符號及混合文字皆可輸入，不會正規化文字或按字母系統過濾。瀏覽器輸入欄會自動調整文字方向。介面與審閱備註仍為繁體中文；這不代表 App 介面已翻譯成 28 種語言。
- 英文模式會分開處理指令語言與下游答案語言。模型必須保留明確答案語言要求、否定範圍、固定字串、變數、程式碼與 URL。若引號或程式碼中的固定字串僅因 NFC 正規化而被更動，後端會以有限規則修復明確可判定的情況。若字串被省略、翻譯或改為語意相近但拼法不同，後端無法重建；重要字串請自行檢查。
- 涵蓋目標包括英語、繁體／簡體中文、西班牙語、法語、德語、葡萄牙語、義大利語、俄語、土耳其語、荷蘭語、波蘭語、烏克蘭語、日語、韓語、印地語、孟加拉語、印尼語、越南語、泰語、泰米爾語、泰盧固語、馬拉地語、阿拉伯語、烏爾都語、波斯語、斯瓦希里語、旁遮普語與菲律賓語。這不是共通的 GitHub 語言標準，也不代表模型有通用品質保證。
- 2026-10-09 的即時樣本使用既有 `deepseek-flash` 設定：韓語和俄語各有短、中、長案例；其他樣本涵蓋英語、兩種中文、日語、西班牙語、法語、德語、葡萄牙語、義大利語、烏克蘭語、阿拉伯語、波斯語、印地語、孟加拉語、泰語、越南語和印尼語。另有一個英文指令案例檢查混合韓／俄字串、NFD 重音、表情符號、變數與 URL；它不能取代韓語／俄語語意測試。
- 總計是 18 種語言的 24 個獨立合成案例，並依發現的問題進行定向重測。最終 Prompt 樣本符合審閱的核心限制；一項日文優化說明仍不夠精確。其他目標語言、其他模型、複雜領域輸入、原生 RTL 顯示及所有宿主 App 工作流程都尚未認證。完整 Prompt 與審閱結果記錄於[公開驗證紀錄](../multilingual-verification.md)。

## HTTP API

獨立伺服器預設為 `http://127.0.0.1:3000`。原生 App 管理的後端使用 `http://127.0.0.1:3210`。

```sh
curl --fail --silent --show-error http://127.0.0.1:3000/api/config

curl --fail --silent --show-error http://127.0.0.1:3000/api/optimize \
  -H 'Content-Type: application/json' \
  --data '{"prompt":"Write a brief invitation. Keep ACME-42 unchanged. Answer in Spanish.","task":"writing","targetModel":"","promptLanguage":"en"}'
```

| 請求欄位 | 行為 |
| --- | --- |
| `prompt` | 必填且不可空白；最多 12,000 個 UTF-16 code unit。 |
| `task` | `general`（預設）、`writing`、`analysis`、`coding`、`summary` 或 `marketing`。 |
| `targetModel` | 可選的下游模型提示；單行，最多 80 個 UTF-16 code unit。 |
| `promptLanguage` | `en` 表示英文指令；未提供時預設 `zh-Hant`。 |

成功時回傳 `prompt`、`improvements`、`assumptions`、`mode`、`generationModel` 與 `promptLanguage`。重用結果時只複製 `prompt`；優化說明與假設是獨立的審閱備註。英文模式的備註仍使用繁體中文。

API 會驗證輸入與模型回應結構、限制同時進行的優化請求，並回報設定、供應商、格式錯誤及逾時問題。取消操作會關閉上游請求；供應商端的處理及計費仍由供應商控制。

## macOS 操作流程

1. 開啟 App 手動工作台，輸入或貼上需求，選擇任務與可選目標模型，再產生英文 Prompt。
2. 檢視 Prompt 與分開顯示的備註。可複製 Prompt，或清空工作區以移除輸入與結果。
3. 使用選取操作時，依提示在系統設定中啟用「輔助使用」。在相容的輸入欄選取文字並按右鍵，再於輔助選單選 **Convert to an English Prompt**；結果會顯示在附近。宿主 App 原有的情境選單仍可使用。按取消、點擊其他位置、鍵盤輸入、切換 App 或等待 12 秒，都會關閉操作提示而不生成結果。只有在明確選擇操作後，助手才會再次檢查選取內容。也可使用選取按鈕。部分 Electron App 可能顯示啟用提示：等待約兩秒、重新選取文字後再試。
4. 其他入口包括預設的 Option-Command-P 快捷鍵、支援的 macOS 服務，以及明確的剪貼簿操作。宿主 App 必須提供可用的文字選取功能，因此不保證所有 App 都相容。
5. 可選的自動貼回會檢查來源 App、焦點欄位、文字與選取範圍後才取代已選文字。若無法再確認來源，則改為複製結果。面板也提供複製及手動貼回。貼回不會送出聊天訊息，並可在設定中停用。Mock 結果不會貼回。

關閉工作區視窗後，選取助手仍會在選單列運作；結束 App 則會停止由它啟動的後端。輔助選單是獨立且不會啟用宿主 App 的操作面板，不會插入宿主 App 原有的情境選單。詳見[右鍵操作驗證](../context-menu-verification.md)。

### 僅更新原生後端

變更可信任的後端或瀏覽器程式碼後，可只更新已安裝 App 的外部後端，不必重建已簽署的原生執行檔：

```sh
npm run update:mac-backend
```

更新程式會先暫存並以 mock HTTP 檢查候選版本，正常關閉 App、檢查連接埠，再切換後端版本並重新啟動 App。若啟動失敗會嘗試復原。它不會更改所選模型設定，也不會終止無關的連接埠監聽程序。Swift 或原生 UI 變更仍須執行 `build:mac` 與 `install:mac`。

## 架構

```text
Native macOS workspace / selection result panel
  -> SwiftUI + AppKit client
  -> app-managed Node.js backend on 127.0.0.1:3210

Optional browser workspace / HTTP API client
  -> standalone Node.js backend on 127.0.0.1:3000

Either backend
  -> labeled mock template, or configured model provider
  -> prompt + separate improvements / assumptions
```

主要原始碼：

- [server.js](../../server.js)：HTTP API、靜態檔案、請求驗證與錯誤處理。
- [lib/optimizer.js](../../lib/optimizer.js)：設定、mock／即時模型介接器、編輯指示與回應驗證。
- [public/](../../public)：支援響應式版面的繁體中文瀏覽器工作台。
- [macos/Sources/](../../macos/Sources)：原生工作台、後端生命週期、選取、結果面板與貼回功能。
- [scripts/](../../scripts)：原生建置、本機簽署、安裝、後端更新與開發檢查。

## 隱私與資料處理

- API 金鑰由 Node.js 後端從本機設定讀取，不會暴露在前端程式碼或封裝進 App。目前金鑰以純文字環境檔保存；尚未整合 Keychain 金鑰儲存。
- 輸入、結果與說明在記憶體中處理，不使用資料庫或 Prompt 歷史紀錄。原生偏好設定及設定路徑會儲存在本機。原生診斷記錄狀態中繼資料與長度，不記錄 Prompt 內容。
- 即時模式會將請求與編輯指示傳送至已設定的模型供應商，並受該供應商的資料保留政策約束。Mock 不會呼叫模型。
- 瀏覽器介面不使用 Cookie、瀏覽器儲存、分析工具或遠端字型；重新載入會清空工作區。原生工作區可透過清除操作或結束記憶體工作階段清空。
- 啟用選取操作後，App 會監聽滑鼠事件並讀取可存取的文字選取內容。若安全的可編輯欄位提供非空選取範圍但沒有選取文字屬性，助手可能暫時讀取欄位值。超過 65,536 個 UTF-16 code unit 的值會被拒絕；只會回傳選取範圍，也不會記錄欄位內容。
- 複製、貼回及備援複製會使用系統剪貼簿。復原操作會先確認使用者沒有複製新內容。清空工作區不會刪除已複製到系統剪貼簿的文字。

這是供個人本機使用的工具，沒有帳號驗證或多使用者隔離。獨立伺服器支援部署設定，但公開部署需自行設定 HTTPS 與存取控制。遠端部署及 Docker 執行尚未驗證。

## 驗證結果與限制

以下檢查結合 2026-10-09 的多語更新與明確右鍵選單修正。瀏覽器與即時模型證據屬於多語更新，沒有在此次僅涉及原生程式碼的修改中重跑。

| 已記錄檢查 | 範圍 |
| --- | --- |
| JavaScript 語法與 Node HTTP 測試 | 語法通過；49 個後端測試通過，涵蓋 Unicode 傳輸、UTF-8 分塊邊界、NFC 固定字串修復與不截斷長度驗證。 |
| 原生核心／API／剪貼簿檢查 | 81 項通過：原有 66 項，加上明確選單選擇、取消／關閉、AppKit 按鈕操作只執行一次，以及來源變更、逾期、忙碌或停用時的保護。 |
| 瀏覽器流程測試 | 10 項 Chrome 測試通過，包含英文／中文切換、混合 Unicode、RTL 方向、超長 emoji 插入不會靜默截斷、複製、錯誤、取消及 390／320px 視窗。 |
| 即時模型樣本 | 18 種語言共 24 個案例，包含韓語／俄語短、中、長案例。人工審閱的核心 Prompt 通過；一項日文優化說明仍不夠精確。 |
| 原生工作區與 IDE（既有證據） | 曾手動觀察生成及清除流程。使用者確認 Codex 面板恢復正常，並在新版選單修改前回報 Claude 也可使用；這不代表新版每項操作都已認證。 |
| 新版右鍵選單（使用者驗收） | 使用者確認原情境選單仍存在、輔助選單出現時不會自動生成，並在明確點擊後取得英文結果。 |

新版選單已由使用者確認可顯示並以一次點擊生成；各宿主 App 中完整的複製／貼回／取消測試仍有限。先前 Codex／Claude 的成功經驗不代表新版所有操作均已認證。未測試的語言與其他宿主 App 仍未驗證。瀏覽器視窗尺寸測試不等同實體 iOS 或 Android 測試。HTTP 成功及受控供應商 Unicode 往返測試都不代表翻譯品質。

尚未提供或驗證：OCR、可設定的全域快捷鍵、內含 Node、功能自動更新、Universal Binary、Developer ID 簽署、公證、下載二進位檔的 Gatekeeper 行為、其他實體 macOS／CPU 組合及公開二進位發行版。專案包含 GitHub 檢查工作流程，但尚未驗證遠端執行。README 不宣稱提供預先建置下載檔或成功的 CI 徽章。

## 開發

```sh
npm ci
npm run check
npm test

# Browser checks: install the test browser once.
npx playwright install chromium
npm run test:ui

# Alternatively, use an installed Google Chrome.
PLAYWRIGHT_CHANNEL=chrome npm run test:ui

# macOS-only checks and native build.
npm run test:mac
npm run build:mac
```

`npm run dev` 會以 Node watch 模式執行獨立伺服器。API 測試使用本機假模型服務，不代表真實模型翻譯品質。原生測試不能取代在各宿主 App 中以實體操作測試文字選取及右鍵流程。專案包含 [GitHub workflow](../../.github/workflows/check.yml)，涵蓋 Node 檢查與 macOS 原生檢查／建置，但不代表已發布或已確認遠端 CI 執行結果。

## 貢獻與授權

開發慣例請參閱 [CONTRIBUTING.md](../../CONTRIBUTING.md)。歡迎修正翻譯，以及使用可分享合成輸入的可重現問題報告。請勿在貢獻中放入 API 金鑰、本機環境檔、私人 Prompt、剪貼簿內容或個人簽署資料。

PromptFinch 使用 [MIT License](../../LICENSE)。模型供應商帳號及任何模型費用由各使用者自行負責。
