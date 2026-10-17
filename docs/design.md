# 架構、設計與參考紀錄

本頁前半描述目前 `main` 的結構；後半是 2026-10-05 的初始設計與參考網站觀察，保留當時的可觀察範圍，不代表今天重新驗證該站。安裝與操作請從[文件索引](README.md)、[主 README](../README.md)及 [macOS 指南](macos.md)開始。

## 目前架構（2026-10-15 文件核對）

```text
原生 macOS 工作台／選取助手 ─→ App 管理的 Node 後端（127.0.0.1:3210）
可選瀏覽器工作台／HTTP 用戶端 ─→ 獨立 Node 後端（預設 127.0.0.1:3000）
                                      ↓
                            輸入與來源驗證 → optimizer
                                      ├─ mock：明示固定範例，無模型呼叫
                                      └─ live：伺服器呼叫自備的相容模型
```

兩個入口共用同一套後端程式；獨立執行的服務有各自的設定與生命週期。原生 App 會啟動、驗證及停止自己的後端，不會把埠上任意既有服務當成可信任子程序。

| 元件 | 責任與邊界 |
| --- | --- |
| [server.js](../server.js) | Node.js 22+ 原生 HTTP 服務、明確靜態檔案清單、`GET /api/config`、`POST /api/optimize`、Host／Origin 與大小限制、取消及每程序最多 4 個優化請求；沒有資料庫、帳號或一般內容歷史。 |
| [lib/optimizer.js](../lib/optimizer.js) | 設定、輸入與模型回應驗證，繁中／英文編輯規則，mock，以及 OpenAI 相容 Chat Completions adapter。更換 API 協定時從這個 adapter 著手；同協定供應商通常只需環境設定。 |
| [public/](../public/) | 無前端框架的 HTML／CSS／JavaScript；繁中介面、英文／繁中指令切換、範例、取消、清除、複製與狀態。無遠端字型、追蹤或內容儲存。 |
| [macos/Sources/App.swift](../macos/Sources/App.swift)、[Localization.swift](../macos/Sources/Localization.swift) | SwiftUI／AppKit 手動工作台、設定、狀態與生成協調；繁中、英文、日文、韓文介面。新生成的說明依介面語言送出 `notesLanguage`；不重寫原文或既有模型結果。對照功能使用生成時原文快照，只標示文字差異。 |
| [Selection.swift](../macos/Sources/Selection.swift)、[Watcher.swift](../macos/Sources/Watcher.swift) | Accessibility 選取、全域快捷鍵、獨立右鍵附加選單與結果浮窗；明確操作後再次核對來源。已辨識終端只複製，其他可靠可編輯來源才允許要求貼回。 |
| [Backend.swift](../macos/Sources/Backend.swift)、[Core.swift](../macos/Sources/Core.swift) | App 管理的本機服務與 API 契約；讀取設定檔路徑，核對後端內容 ID 與本次程序識別，原生請求固定英文指令。App 包含後端來源，另需本機 Node 執行環境。 |
| [scripts/](../scripts/) | 建置／安裝、個人本機簽章、公開來源封裝、乾淨副本的 ad-hoc App 封裝、內容定址的本機後端更新及明示 live 測例工具；沒有自動下載 GitHub release 的更新器。 |
| [tests/](../tests/)、[macos/Tests/](../macos/Tests/)、[CI](../.github/workflows/check.yml) | 受控 API／錯誤測試、可選瀏覽器流程、合成原生狀態檢查。CI 執行語法、Node、原生測試與 macOS 建置；瀏覽器／付費模型與真人宿主驗收需另外執行。 |

用途 ID 為 `general`、`writing`、`analysis`、`coding`、`summary`、`marketing`。目標模型欄位是編輯提示；真正呼叫的模型來自伺服器 `LLM_MODEL`，不會因選取該欄就切換供應商。輸入上限為 12,000 個 UTF-16 code units，不等於可見字元數。

模型回應固定分成 `prompt`、`improvements`、`assumptions`，複製僅使用 `prompt`。英文模式直接回傳整理過的英文任務指令，繁中 live 模式會保留完整原文並加上生成的補充指引；這兩種組裝方式不同。模型必須改善同一任務的可執行性，不能執行原任務、捏造事實或強制套用固定章節；這是模型規則及人工覆核目標，程式格式驗證本身不能證明語意正確。

首次啟動會由 App 隨附來源建立外部後端；存在 `current` 後，單純替換 App 仍保留先前的選擇。設定中的「使用此 App 隨附後端」是明確採用目前 App 種子的入口：先暫存與驗證，切換自身服務，失敗時嘗試回復，不修改模型檔案或 Node／介面偏好。原始碼更新指令則可部署可信任工作目錄的後端，兩者都不是網路自動更新。

一般內容只留在記憶體，live 明確生成後送往所設定的模型服務。App 另保存介面／操作偏好及設定路徑，私有環境檔存金鑰；使用者選擇複製後，結果也會存在系統剪貼簿。明示測試工具會把測例與結果寫到指定輸出檔，與一般工作台不同。Host／Origin 保護不是公開服務的登入或授權機制，部署前請閱讀 [SECURITY.md](../SECURITY.md)。

相容性與品質以具體版本證據為準：[終端](terminal.md)、[跨語言對照](multilingual-parity-verification.md)、[任務優化](optimization-value-verification.md)。附加選單不會修改 Codex、Claude Code 或宿主的原生選單，GIF 是合成示意。[v1.1.0](releases/v1.1.0.md)另提供對應的新下載；既有 `v1.0.0` tag 與資產保持原樣，不會自動包含新版變更。

## 初始設計紀錄（2026-10-05）

### 檢視結果

2026-10-05 檢查專案：工作目錄只有 AGENTS.md 與空的 sources/，沒有套件、既有程式或執行方式。未更動同步參考資料。新增獨立 prompt-studio/，採 Node.js 22 原生 HTTP / fetch、HTML / CSS / JavaScript。無執行期套件、資料庫或建置步驟。

### 參考網站

實際以網頁閱讀工具與 Chrome 瀏覽 https://promptessor.com/ai-prompt-generator 的公開頁面，並讀取 https://promptessor.com/docs/prompt-generator 文件。公開頁面可觀察到模型選擇、需求文字輸入、輸出語言與生成按鈕、範例填入；工作區預覽展示用途、聊天式修訂、可直接使用的 Prompt / 可重用範本、版本切換、獨立 Prompt 文字與 context / variables / usage notes，以及複製和保存的流程。文件描述進一步優化、歷史與範本重用。實際公開頁面使用黑底與集中式表單；本專案採不同的明亮工作台布局。

公開預覽與文件不代表已驗證每項互動；完整工作區連結在網頁閱讀工具中存取失敗。沒有提交任何使用者資料，也沒有驗證該站真正生成結果的品質。

採用：先選用途與目標模型、貼入需求後產生結果；輸入與輸出分區；Prompt 與補充說明分離；範例、一鍵複製。

未採用：品牌、原站文案、圖片、程式碼與視覺樣式；圖片/影片生成、登入、聊天、版本庫、雲端歷史、推估 token、模型排名。個人使用以一次優化、容易設定、預設不保存為核心。

### 實作前的視覺計畫

- 色彩：紙白 #FFFFFF、工作台灰 #F3F5F8、墨藍 #1C2C48、操作藍 #2855C5、次要灰 #5E6B80、示範琥珀 #8A5A10。
- 字體：本機 PingFang TC / Microsoft JhengHei 為介面主體；結果同樣使用易讀中文字體，保留換行。無遠端字型請求。
- 版面：全頁左對齊，頂部名稱與模式、簡短標題、用途與目標模型、桌面雙欄編輯區、底部隱私提示；手機依序輸入、結果、說明。

```text
名稱                                     執行模式
把需求說清楚，讓 AI 更好理解。
用途選擇                         目標模型（選填）
┌ 原始 Prompt ─────────┐  ┌ 優化結果 ── 複製 ───┐
│ 文字編輯             │  │ 空白提示 / 結果文字   │
│ 範例 / 字數          │  │ 明確的生成模式標示    │
│ 清除      優化 Prompt│  └──────────────────────┘
└──────────────────────┘    優化重點與假設
不保存內容 / 示範或模型傳送說明
```

自我檢視後採用單一工作台，避免多張相同卡片、行銷大圖、裝飾漸層或無意義數據。唯一具辨識度的圖形是表示文字整理的原創三行標誌。標示、分隔線與色彩只用於輸入、輸出、模式及操作層級。複製與優化的詞彙保持一致。
