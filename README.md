# PromptFinch

**Select. Refine. Paste.**

A general-purpose prompt editor and optimizer for writing, coding, research, summarization, and planning. Turn a rough request into clearer instructions for the model you plan to use.

The macOS app combines a manual workspace with a selection assistant: select text in a compatible app, right-click, choose **Convert to an English Prompt** in the companion action menu, and review the result in a nearby panel. Right-clicking alone does not generate or send content to a model. An optional browser workspace and HTTP API use the same backend.

The macOS app and the API's English mode produce English prompts from multilingual input. They are designed to retain explicit requirements, the requested answer language, and exact literals. This edits the instructions; it does not perform the original task. Review generated prompts before using them.

## Languages

English is the source reference. Full technical references are also available in Simplified Chinese (zh-CN) and Traditional Chinese (zh-TW); the remaining language/script editions provide localized introductions. These are documentation translations; the current app interface is Traditional Chinese. Documentation coverage does not mean every input language or host app has been tested. Translation improvements are welcome.

[English](#english) · [简体中文（zh-CN）](#lang-zh-hans) · [繁體中文（zh-TW）](#lang-zh-hant) · [Español](#lang-es) · [Français](#lang-fr) · [Deutsch](#lang-de) · [Português](#lang-pt) · [Italiano](#lang-it) · [Русский](#lang-ru) · [Türkçe](#lang-tr) · [Nederlands](#lang-nl) · [Polski](#lang-pl) · [Українська](#lang-uk) · [日本語](#lang-ja) · [한국어](#lang-ko) · [हिन्दी](#lang-hi) · [বাংলা](#lang-bn) · [Bahasa Indonesia](#lang-id) · [Tiếng Việt](#lang-vi) · [ไทย](#lang-th) · [தமிழ்](#lang-ta) · [తెలుగు](#lang-te) · [मराठी](#lang-mr) · [العربية](#lang-ar) · [اردو](#lang-ur) · [فارسی](#lang-fa) · [Kiswahili](#lang-sw) · [ਪੰਜਾਬੀ](#lang-pa) · [Filipino](#lang-fil)

For English output, use the macOS app, choose **英文 Prompt** in the browser's **Prompt 指令語言** control (the browser default), or set `promptLanguage: "en"` in an API request. The browser also offers Traditional Chinese output. Existing API clients that omit this field still receive `zh-Hant` output. Localized editions do not change the app interface language.

Input accepts Unicode without an alphabet or source-language allowlist. Korean and Russian are required coverage languages. The 28 documentation languages are a coverage target, not proof of model quality. The [recorded multilingual verification](docs/multilingual-verification.md) distinguishes transport tests, 24 live synthetic cases across 18 languages, semantic review, and remaining limitations.

<a id="english"></a>

## English technical reference

[Quick start](#quick-start) · [Model configuration](#model-configuration) · [HTTP API](#http-api) · [macOS workflow](#macos-workflow) · [Privacy](#privacy-and-data-handling) · [Validation and limitations](#validation-and-limitations) · [Development](#development)

### What it does

- Accept a rough prompt, choose a task type, and optionally name the model that will receive the result.
- Produce a copyable prompt with improvements and assumptions shown separately. Copy and paste-back use the prompt field alone.
- Use one macOS app for manual input, selection actions, result panels, model settings, and optional paste-back.
- Handle blank input, size limits, loading, cancellation, and understandable errors.
- Run without a model key in clearly labeled mock mode, or call a configured OpenAI-compatible model from the Node.js backend.

Suggested GitHub repository name: `promptfinch`. See the [rename and compatibility notes](docs/branding.md).

The task choices are general, writing, analysis, coding, summary, and marketing. Research and planning requests fit the analysis or general workflow. The optional **target model** is a prompt-editing hint, not a switch for the backend generation model; the latter is configured with `LLM_MODEL`.

The interface and improvement/assumption notes are currently primarily Traditional Chinese. This README provides 29 language/script editions across 28 languages; it does not add translated app interfaces or certify all input languages.

### Requirements

| Use | Requirements |
| --- | --- |
| Browser workspace / HTTP API | Node.js 22 or newer. No third-party runtime packages are required. |
| Native macOS app | macOS 13 or newer as the compilation target, plus an installed Node.js 22+ runtime. Node is not bundled with the app. |
| Build the macOS app | Apple Xcode Command Line Tools, including Swift and Apple's signing tools. Full Xcode is not required. |
| Development and browser tests | `npm ci` installs the development dependencies; Playwright needs an installed test browser. |

Native builds target `arm64` when the build's Node process is ARM64, otherwise `x86_64`; they are not Universal Binaries. Recorded native checks were on Apple Silicon. Intel and the minimum macOS 13 target have not been validated on physical machines.

Run the following commands from the project root. The examples use a POSIX shell, as provided by macOS and common Linux environments.

### Quick start

#### Browser demo, no API key

```sh
# Create a local configuration only if one does not already exist.
cp -n .env.example .env
npm start
```

Open [http://127.0.0.1:3000](http://127.0.0.1:3000). If `.env` already exists, review it and set `OPTIMIZER_MODE=mock` for a local demonstration instead of overwriting it. Running the service does not require `npm install`.

**Mock output is not translated and not semantically optimized.** It is a labeled template for checking input, loading, result display, and copy flows. It does not call a model or send prompt content to a provider.

The browser defaults to English prompt instructions. Choose **繁體中文 Prompt** for the original Chinese optimization flow. This controls the instructions' language; an explicit answer language in your original request is retained. Mock mode clearly states that the source has not actually been translated.

#### Build and install the macOS app

```sh
xcode-select --install  # Skip if Command Line Tools are already installed.
npm run setup:signing:mac
npm run build:mac
npm run install:mac
```

The build produces `build/PromptFinch.app`. The installer places it in the user's `~/Applications` directory and opens it. No separate browser server is needed: the app starts its own backend at `http://127.0.0.1:3210`.

An existing `Prompt 選取助手.app` installation is migrated to `PromptFinch.app` by the installer. The signing identity, configuration path and saved preferences are retained; see the [rename notes](docs/branding.md).

`setup:signing:mac` is a per-machine setup for a stable local signing identity. It stores the private signing key in the login Keychain; macOS may ask you to confirm access. This helps maintain the Accessibility identity across local rebuilds. It is not Developer ID signing or notarization, and signing keys must not be published. If an existing signing configuration is invalid, the build stops instead of silently replacing that identity.

Without a selected model configuration, the app uses mock mode. In Settings, create or select a model configuration file, fill in your provider settings, and reload the configuration. If the app cannot locate Node, select its executable in Settings.

An existing configuration can also be selected at installation:

```sh
npm run install:mac -- --config .env
```

For more macOS setup details, see the [macOS guide](docs/macos.md), currently written in Traditional Chinese.

### Model configuration

Live generation uses an **OpenAI-compatible Chat Completions** endpoint. The backend appends `/chat/completions` to `LLM_BASE_URL`. Each user provides their own provider access and pays any charges on that account.

For a new configuration, [.env.deepseek.example](.env.deepseek.example) provides this concrete example:

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

Replace `YOUR_MODEL_API_KEY` with your own key in your private local configuration. Edit an existing `.env` rather than overwriting it. Restart the browser server after configuration changes; in the Mac app, reload the selected configuration.

Other compatible providers can replace the base URL, key, and model identifier. Keep `LLM_THINKING_MODE` blank for providers that do not accept the DeepSeek thinking parameter. If a provider does not accept JSON mode, set `LLM_JSON_MODE=false`; it must still return the valid JSON requested by the optimizer. Native Claude or Gemini endpoints require an adapter or a compatible gateway and cannot simply be entered as Chat Completions URLs.

A local compatible service that does not require authentication can use `LLM_API_KEY=local-only` as a non-secret placeholder, together with that service's actual base URL and loaded model identifier. This does not start or bundle a local model.

| Variable | Default | Meaning |
| --- | --- | --- |
| `OPTIMIZER_MODE` | `mock` | `mock` for templates; `live` for model requests. |
| `LLM_API_KEY` | Empty | Backend-only Bearer credential; required in live configuration. |
| `LLM_BASE_URL` | `https://api.openai.com/v1` | Compatible API base URL; no embedded credentials, query, or fragment. |
| `LLM_MODEL` | Empty | Provider model identifier; required in live configuration. |
| `LLM_JSON_MODE` | `true` | Send `response_format: {type: "json_object"}`. |
| `LLM_THINKING_MODE` | Empty | Omitted when blank; accepts `enabled` or `disabled`. |
| `LLM_TIMEOUT_MS` | `45000` | Request/response timeout; integer from 10 to 180000 milliseconds. |
| `HOST` | `127.0.0.1` | Bind address for the standalone server. |
| `PORT` | `3000` | Standalone server port. |

The Mac app overrides `HOST` and `PORT` to `127.0.0.1:3210`, regardless of their values in the selected configuration. The standalone browser server and native backend can run on their separate ports.

Live configuration or provider failures are reported as errors; they are not silently replaced with mock results. A `ready` value from `/api/config` means configuration is present, not that the upstream model has been successfully contacted.

### Example: prompt language and answer language

Original request:

> Write a brief invitation. Keep ACME-42 unchanged. Answer in Spanish.

Illustrative optimized prompt, not a recorded model response:

```text
Write a brief invitation in Spanish. Preserve the exact text "ACME-42" wherever it occurs.
```

The instructions are English, while the invitation requested from the downstream model remains Spanish. The optimizer returns instructions rather than writing the invitation itself. The model is instructed to retain explicit requirements and exact literals, mark reasonable assumptions, and avoid changing the task's intent; review its result for omissions or mistranslations.

### Multilingual input and coverage

- Input, JSON transport, and native selection use Unicode. The 12,000 input limit counts UTF-16 code units consistently with JavaScript and Swift's UTF-16 view, rather than visible letters or grapheme clusters. Oversized requests are rejected rather than truncated. Selected UTF-16 ranges cannot split surrogate pairs. See [JavaScript length](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String/length) and [Swift UTF16View](https://developer.apple.com/documentation/swift/string/utf16view).
- Korean Hangul, Russian Cyrillic, RTL scripts, combining marks, joiners, emoji, and mixed text are accepted without normalization or alphabet-based filtering. The browser input uses automatic text direction. The interface and review notes remain Traditional Chinese; this is not an app interface translated into 28 languages.
- English mode separates instruction language from the downstream answer language. The model must preserve explicit answer-language requirements, negation scope, exact literals, variables, code and URLs. A narrow backend repair restores an unambiguous quoted/code literal altered only by canonical NFC normalization. It cannot reconstruct omitted or translated literals or resolve ambiguous equivalent spellings; review important strings.
- Coverage targets are English, Chinese (Traditional/Simplified), Spanish, French, German, Portuguese, Italian, Russian, Turkish, Dutch, Polish, Ukrainian, Japanese, Korean, Hindi, Bengali, Indonesian, Vietnamese, Thai, Tamil, Telugu, Marathi, Arabic, Urdu, Persian, Swahili, Punjabi, and Filipino. No shared GitHub language standard or universal model guarantee is implied.
- Live samples on 2026-10-09 used the existing `deepseek-flash` configuration: Korean and Russian each had short, medium and long cases; other samples covered English, both Chinese scripts, Japanese, Spanish, French, German, Portuguese, Italian, Ukrainian, Arabic, Persian, Hindi, Bengali, Thai, Vietnamese and Indonesian. A separate English-instruction case checked mixed Korean/Russian literals, NFD accents, emoji, variables and a URL. It does not substitute for Korean/Russian semantic tests.
- This is 24 unique synthetic cases across 18 languages, with targeted reruns after findings. The final prompt corpus met the reviewed core constraints; one Japanese improvement note remains imprecise. Other target languages, other models, complex domain inputs, native RTL rendering and all host-app workflows have not been certified. Full prompts and review findings are in the [public verification record](docs/multilingual-verification.md).

### HTTP API

The standalone server defaults to `http://127.0.0.1:3000`. The native app's managed backend uses `http://127.0.0.1:3210`.

```sh
curl --fail --silent --show-error http://127.0.0.1:3000/api/config

curl --fail --silent --show-error http://127.0.0.1:3000/api/optimize \
  -H 'Content-Type: application/json' \
  --data '{"prompt":"Write a brief invitation. Keep ACME-42 unchanged. Answer in Spanish.","task":"writing","targetModel":"","promptLanguage":"en"}'
```

| Request field | Behavior |
| --- | --- |
| `prompt` | Required nonblank source text; maximum 12,000 UTF-16 code units. |
| `task` | `general` (default), `writing`, `analysis`, `coding`, `summary`, or `marketing`. |
| `targetModel` | Optional downstream model hint; single line, up to 80 UTF-16 code units. |
| `promptLanguage` | `en` for English instructions; `zh-Hant` by default when omitted. |

A successful optimization returns `prompt`, `improvements`, `assumptions`, `mode`, `generationModel`, and `promptLanguage`. Copy only `prompt` when reusing the result; improvements and assumptions are separate review notes. English-mode notes are still Traditional Chinese.

The API validates input and model response structure, limits concurrent optimization requests, and reports configuration, provider, malformed-output, and timeout errors. Cancellation closes the upstream request; provider-side processing and billing behavior remain under the provider's control.

### macOS workflow

1. Open the app's manual workspace, enter or paste a request, choose a task and optional target model, then generate an English prompt.
2. Review the prompt and separate notes. Copy the prompt, or clear the workspace to remove its input and result.
3. For selection actions, enable Accessibility in System Settings when prompted. In a compatible input field, select text and right-click, then choose **轉為英文 Prompt** in the companion menu; the result appears nearby. The host's original context menu remains available. Cancel, a click elsewhere, keyboard input, switching apps or the 12-second timeout dismisses the offered action without generating. The assistant checks the selection again after an explicit choice. You can also use the optional selection button. Some Electron apps may show an activation notice: wait about two seconds, make a new selection, and try again.
4. Other entry points include the default Option-Command-P shortcut, macOS Services where supported, and an explicit clipboard action. Host applications must expose usable text selection; this is not universal compatibility.
5. Optional automatic paste-back checks the source app, focused field, text, and selection before replacing the selected input. If the source can no longer be verified, the result is copied instead. The panel also offers copy and manual paste-back. Paste-back does not submit the chat message and can be disabled in Settings. Mock results are not pasted back.

Closing the workspace window leaves the selection assistant running in the menu bar. Quitting the app stops the backend it started. The companion menu is a separate, nonactivating action panel; it does not insert items into the host's original context menu. See the [right-click action verification](docs/context-menu-verification.md).

#### Update only the native backend

After changing trusted backend or browser source, an installed app can update its external backend without rebuilding the signed native executable:

```sh
npm run update:mac-backend
```

The updater stages and validates a candidate with a mock HTTP check, closes the app normally, checks the port, switches the backend version, and restarts the app. If startup fails, it attempts rollback. It does not change the selected model configuration or terminate an unrelated port listener. Swift or native UI changes still require `build:mac` and `install:mac`.

### Architecture

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

Main source files:

- [server.js](server.js): HTTP API, static files, request validation, and errors.
- [lib/optimizer.js](lib/optimizer.js): configuration, mock/live adapter, editing instructions, and response validation.
- [public/](public/): Traditional Chinese browser workspace with responsive layout.
- [macos/Sources/](macos/Sources/): native workspace, backend lifecycle, selection, result panel, and paste-back.
- [scripts/](scripts/): native build, local signing, installation, backend update, and development checks.

### Privacy and data handling

- API keys are read by the Node.js backend from local configuration, not exposed in frontend code or bundled with the app. Keys currently live in a plain-text environment file; API-key storage is not integrated with Keychain.
- Input, results, and explanations are processed in memory without a database or prompt-history feature. Native preferences and configuration paths are stored locally. Native diagnostics record status metadata and lengths, not prompt content.
- Live mode sends the request and editing context to the configured model provider. The provider's data retention policy applies. Mock does not make a model request.
- The browser interface uses no cookies, browser storage, analytics, or remote fonts. Reloading clears its workspace. The native workspace is cleared using its clear action or by ending its in-memory session.
- Enabled selection actions observe mouse events and read accessible text selection. Where a safe editable field exposes a nonempty selected range but no selected-text attribute, the assistant may temporarily read the field value. Values over 65,536 UTF-16 code units are rejected; only the selected range is returned, and field contents are not logged.
- Copy, paste-back, and fallback copying use the system clipboard. Restoration is guarded so a newer user copy is not overwritten. Clearing the workspace does not delete text already copied to the system clipboard.

This is a local personal tool without account authentication or multi-user isolation. The standalone server supports deployment configuration, but a public deployment needs its own HTTPS and access control. Remote deployment and Docker execution have not been validated.

### Validation and limitations

The following checks combine the multilingual update and explicit right-click menu fix on 2026-10-09. Browser and live-model evidence belongs to the multilingual update; it was not repeated for this native-only change.

| Recorded check | Scope |
| --- | --- |
| JavaScript syntax and Node HTTP tests | Syntax passed; 49 backend tests passed, including Unicode transport, UTF-8 chunk boundaries, NFC literal restoration and non-truncating length validation. |
| Native core / API / clipboard checks | 81 checks passed: the original 66 plus explicit menu choice, cancel/dismissal, single-use AppKit button actions and changed/expired/busy/disabled source protection. |
| Browser flow tests | 10 Chrome tests passed, including English/Chinese switching, mixed Unicode, RTL direction, oversized emoji insertion without silent truncation, copy, errors, cancellation and 390/320px viewports. |
| Live model samples | 24 unique cases across 18 languages, including Korean/Russian short, medium and long cases. Manually reviewed core prompts passed; one Japanese improvement note remains imprecise. |
| Native workspace and IDEs (prior evidence) | Manual generation and clearing were previously observed. The user confirmed Codex panel recovery and subsequently reported Claude also worked, before the new menu change. This does not certify every operation in the new build. |
| New right-click menu (user acceptance) | The user confirmed the original context menu remained, the companion menu appeared without automatic generation, and one explicit click produced an English result. |

The new menu has user acceptance for display and one-click generation; complete copy/paste-back/cancellation checks in each host remain limited. Earlier Codex/Claude success does not certify every operation in the new build. The untested language targets and other host apps remain unverified. Browser viewport checks are not tests on physical iOS or Android devices. HTTP success and controlled-provider Unicode roundtrips are not evidence of translation quality.

Not delivered or validated: OCR, a configurable global shortcut, bundled Node, automatic updates, Universal Binary builds, Developer ID signing, notarization, downloaded-binary Gatekeeper behavior, other physical macOS/CPU configurations, and a public binary release. A GitHub check workflow is included, but its remote execution has not been verified. This README does not advertise prebuilt downloads or successful release/CI badges.

### Development

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

`npm run dev` runs the standalone server with Node's watch mode. API tests use local fake model services; they do not establish real-model translation quality. Native tests do not substitute for physical selection/right-click interaction in each host app. The included [GitHub workflow](.github/workflows/check.yml) covers Node checks and native macOS checks/builds, without proving publication or remote CI execution.

### Contributing and license

See [CONTRIBUTING.md](CONTRIBUTING.md) for development conventions. Translation corrections and reproducible reports using synthetic, shareable inputs are welcome. Keep API keys, local environment files, private prompts, clipboard contents, and personal signing material out of contributions.

PromptFinch is licensed under the [MIT License](LICENSE). Provider access and any model charges belong to each user's own account.

## Localized editions

The Chinese editions below translate the technical reference, including installation, configuration, API, privacy, and validation details. Other editions provide localized introductions and link to the [shared English reference](#english). The browser offers English/Traditional Chinese instructions, while API requests without `promptLanguage` retain their `zh-Hant` default. The app interface remains Traditional Chinese.

<a id="lang-zh-hant"></a>
<details>
<summary>繁體中文（zh-TW）</summary>

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

GitHub 專案名稱建議為 `promptfinch`。請參閱[更名與相容性說明](docs/branding.md)。任務類型包括通用、寫作、分析、程式開發、摘要與行銷；研究與規劃可選分析或通用。可選的**目標模型**只作為編輯 Prompt 的提示，不會切換後端生成模型；後端模型由 `LLM_MODEL` 設定。

目前介面及優化／假設說明主要使用繁體中文。本 README 提供 29 種語言／文字版本，但不包含 App 介面的翻譯，也不代表所有輸入語言均已通過驗證。

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

安裝程式會將既有的 `Prompt 選取助手.app` 遷移為 `PromptFinch.app`，並保留簽署身分、設定路徑與已儲存的偏好設定；詳見[更名說明](docs/branding.md)。

`setup:signing:mac` 是每台電腦各自執行一次的本機簽署身分設定。私密簽署金鑰會存放在登入鑰匙圈；macOS 可能要求確認存取。這有助於本機重建時維持輔助使用身分。這不是 Developer ID 簽署或公證，且不得發布簽署金鑰。若既有簽署設定無效，建置會停止，不會暗中取代身分。

若未選取模型設定，App 會使用 mock 模式。在「設定」中建立或選取模型設定檔、填入供應商設定並重新載入設定。若 App 找不到 Node，請在「設定」中選擇其執行檔。

也可在安裝時指定既有設定：

```sh
npm run install:mac -- --config .env
```

更多 macOS 設定請參閱目前以繁體中文撰寫的 [macOS 指南](docs/macos.md)。

## 模型設定

即時生成使用 **OpenAI 相容的 Chat Completions** 端點。後端會在 `LLM_BASE_URL` 後附加 `/chat/completions`。使用者需自行提供模型供應商帳號並負擔該帳號產生的費用。

新設定可參考 [.env.deepseek.example](.env.deepseek.example)：

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
- 總計是 18 種語言的 24 個獨立合成案例，並依發現的問題進行定向重測。最終 Prompt 樣本符合審閱的核心限制；一項日文優化說明仍不夠精確。其他目標語言、其他模型、複雜領域輸入、原生 RTL 顯示及所有宿主 App 工作流程都尚未認證。完整 Prompt 與審閱結果記錄於[公開驗證紀錄](docs/multilingual-verification.md)。

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

關閉工作區視窗後，選取助手仍會在選單列運作；結束 App 則會停止由它啟動的後端。輔助選單是獨立且不會啟用宿主 App 的操作面板，不會插入宿主 App 原有的情境選單。詳見[右鍵操作驗證](docs/context-menu-verification.md)。

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

- [server.js](server.js)：HTTP API、靜態檔案、請求驗證與錯誤處理。
- [lib/optimizer.js](lib/optimizer.js)：設定、mock／即時模型介接器、編輯指示與回應驗證。
- [public/](public/)：支援響應式版面的繁體中文瀏覽器工作台。
- [macos/Sources/](macos/Sources/)：原生工作台、後端生命週期、選取、結果面板與貼回功能。
- [scripts/](scripts/)：原生建置、本機簽署、安裝、後端更新與開發檢查。

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

`npm run dev` 會以 Node watch 模式執行獨立伺服器。API 測試使用本機假模型服務，不代表真實模型翻譯品質。原生測試不能取代在各宿主 App 中以實體操作測試文字選取及右鍵流程。專案包含 [GitHub workflow](.github/workflows/check.yml)，涵蓋 Node 檢查與 macOS 原生檢查／建置，但不代表已發布或已確認遠端 CI 執行結果。

## 貢獻與授權

開發慣例請參閱 [CONTRIBUTING.md](CONTRIBUTING.md)。歡迎修正翻譯，以及使用可分享合成輸入的可重現問題報告。請勿在貢獻中放入 API 金鑰、本機環境檔、私人 Prompt、剪貼簿內容或個人簽署資料。

PromptFinch 使用 [MIT License](LICENSE)。模型供應商帳號及任何模型費用由各使用者自行負責。

</details>

<a id="lang-zh-hans"></a>
<details>
<summary>简体中文（zh-CN）</summary>

# PromptFinch

**选择。优化。粘贴。**

PromptFinch 是通用的 Prompt 编辑与优化工具，适用于写作、编程、研究、摘要与规划。将粗略需求整理成更清楚的指令，供你选择的模型使用。

macOS App 结合手动工作台与选择助手：在兼容应用中选中文本并点击右键，于辅助操作菜单选择 **Convert to an English Prompt**，再于附近面板查看结果。仅点击右键不会生成内容，也不会将内容发送给模型。另有使用相同后端的浏览器工作台与 HTTP API。

macOS App 与 API 的英文模式会将多语输入整理为英文 Prompt，并以保留明确需求、指定答案语言与固定字符串为设计目标。它只会编辑指令，不会执行原始任务。使用前请检查生成结果。

## 功能

- 接受原始 Prompt、任务类型，以及可选的下游目标模型名称。
- 生成可复制的 Prompt，并将优化说明与假设分开呈现；复制及贴回只会使用 Prompt 字段。
- macOS App 提供手动输入、文本选择操作、结果面板、模型配置及可选的贴回功能。
- 处理空白输入、长度限制、加载、取消与易懂的错误信息。
- 可在明确标注的 mock 模式下无需密钥检查流程，或由 Node.js 后端调用已配置的 OpenAI 兼容模型。

GitHub 仓库名称建议为 `promptfinch`。请参阅[更名与兼容性说明](docs/branding.md)。任务类型包括通用、写作、分析、编程、摘要与营销；研究与规划可选分析或通用。可选**目标模型**只作为编辑 Prompt 的提示，不会切换后端生成模型；后端模型由 `LLM_MODEL` 配置。

目前的应用界面及优化说明／假设主要使用繁体中文。本 README 提供 29 种语言／文本版本，但不包含 App 界面的翻译，也不代表所有输入语言均已通过验证。

## 系统需求

| 用途 | 需求 |
| --- | --- |
| 浏览器工作台／HTTP API | Node.js 22 或更新版本；不需第三方运行时依赖。 |
| macOS 原生 App | macOS 13 或更新版本作为编译目标，并安装 Node.js 22+ 运行时。App 不包含 Node。 |
| 构建 macOS App | Apple Xcode Command Line Tools，包含 Swift 与 Apple 签名工具；不需要完整 Xcode。 |
| 开发与浏览器测试 | `npm ci` 安装开发依赖；Playwright 需要已安装的测试浏览器。 |

原生构建会依 Node 程序架构产生 `arm64` 或 `x86_64`，不是 Universal Binary。已记录的原生检查是在 Apple Silicon 上运行；尚未在实体 Intel 设备或最低 macOS 13 版本上验证。

以下指令请在项目根目录、macOS 或常见 Linux 环境提供的 POSIX shell 运行。

## 快速开始

### 浏览器演示（不需 API 密钥）

```sh
# Create a local configuration only if one does not already exist.
cp -n .env.example .env
npm start
```

打开 [http://127.0.0.1:3000](http://127.0.0.1:3000)。若 `.env` 已存在，请先检查内容，并配置 `OPTIMIZER_MODE=mock` 进行本地演示，不要覆盖原文件。运行服务不需要 `npm install`。

**Mock 输出不会翻译，也不会进行语义优化。**它是用来检查输入、加载、结果显示和复制流程的模板，不会调用模型或将 Prompt 传送给供应商。

浏览器默认使用英文指令。选择 **繁体中文 Prompt** 可使用原本的中文优化流程。这只控制指令语言；原始需求中明确指定的答案语言仍会保留。Mock 模式会清楚说明内容并未真正翻译。

### 构建并安装 macOS App

```sh
xcode-select --install  # Skip if Command Line Tools are already installed.
npm run setup:signing:mac
npm run build:mac
npm run install:mac
```

构建结果为 `build/PromptFinch.app`。安装程序会将 App 放入用户的 `~/Applications` 并打开。无需另外启动浏览器服务器：App 会在 `http://127.0.0.1:3210` 启动自己的后端。

安装程序会将现有的 `Prompt 選取助手.app` 迁移为 `PromptFinch.app`，并保留签名身份、配置路径与已存储的偏好设置；详见[更名说明](docs/branding.md)。

`setup:signing:mac` 是每台电脑各自执行一次的本地签名身份配置。私密签名密钥会存放在登录钥匙串；macOS 可能要求确认访问。这有助于在本地重建时保持辅助功能权限身份稳定。这不是 Developer ID 签名或公证，且不得发布签名密钥。若现有签名配置无效，构建会停止，不会暗中取代身份。

若未选择模型配置，App 会使用 mock 模式。在 App 的「设置」中建立或选择模型配置文件、填入供应商配置并重新加载配置。若 App 找不到 Node，请在 App 的「设置」中选择其可执行文件。

也可在安装时指定现有配置：

```sh
npm run install:mac -- --config .env
```

更多 macOS 配置请参阅目前以繁体中文编写的 [macOS 指南](docs/macos.md)。

## 模型配置

实时生成使用 **OpenAI 兼容的 Chat Completions** 端点。后端会在 `LLM_BASE_URL` 后附加 `/chat/completions`。用户需自行提供模型供应商账户并承担相关费用。

新配置可参考 [.env.deepseek.example](.env.deepseek.example)：

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

请在私人本地配置中以自己的密钥取代 `YOUR_MODEL_API_KEY`。修改现有 `.env`，不要覆盖它。浏览器服务器的配置更改后需重新启动；Mac App 则需重新加载所选配置。

其他兼容供应商可替换基本 URL、密钥与模型识别码。若供应商不接受 DeepSeek 思考参数，请将 `LLM_THINKING_MODE` 留空。若供应商不接受 JSON 模式，请配置 `LLM_JSON_MODE=false`；但它仍必须返回优化器要求的有效 JSON。原生 Claude 或 Gemini 端点需要适配器或兼容网关，不能直接填入 Chat Completions URL。

不需验证的本地兼容服务可以 `LLM_API_KEY=local-only` 作为非敏感信息占位值，并配置该服务实际的基本 URL 与已加载模型名称。这不会启动或随附本地模型。

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `OPTIMIZER_MODE` | `mock` | `mock` 使用模板；`live` 调用模型。 |
| `LLM_API_KEY` | 空白 | 仅供后端使用的 Bearer 认证；实时模式必填。 |
| `LLM_BASE_URL` | `https://api.openai.com/v1` | 兼容 API 基本 URL；不得含内嵌认证、查询或片段。 |
| `LLM_MODEL` | 空白 | 供应商模型标识符；实时模式必填。 |
| `LLM_JSON_MODE` | `true` | 传送 `response_format: {type: "json_object"}`。 |
| `LLM_THINKING_MODE` | 空白 | 留空时不传送；可用 `enabled` 或 `disabled`。 |
| `LLM_TIMEOUT_MS` | `45000` | 请求／响应超时；整数范围 10 至 180000 毫秒。 |
| `HOST` | `127.0.0.1` | 独立服务器的监听地址。 |
| `PORT` | `3000` | 独立服务器端口。 |

Mac App 无论所选配置文件中的值为何，都会将 `HOST` 与 `PORT` 设为 `127.0.0.1:3210`。独立浏览器服务器可使用另一个端口。

实时配置或供应商调用失败时会报告错误，不会默默改用 mock 结果。`/api/config` 的 `ready` 表示配置已填妥，不代表已成功连上上游模型。

## 示例：Prompt 语言与答案语言

原始需求：

> 编写一段简短邀请。保持 ACME-42 不变。请用西班牙语回答。

以下是示意的优化结果，并非实际记录的模型响应：

```text
Write a brief invitation in Spanish. Preserve the exact text "ACME-42" wherever it occurs.
```

指令本身为英语，但要求下游模型编写的邀请仍为西班牙语。优化器返回的是指令，而不是代为编写邀请。模型收到的指示包括保留明确需求与固定字符串、标示合理假设并避免改变任务意图；仍应检查遗漏或误译。

## 多语输入与涵盖范围

- 输入、JSON 传输及原生选择均支持 Unicode。12,000 字符上限以 UTF-16 code unit 计算，与 JavaScript 及 Swift 的 UTF-16 视图一致，不按可见字母或字素簇计数。超过上限会拒绝请求，不会截断。选择范围不能切开 surrogate pair。参阅 [JavaScript length](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String/length) 与 [Swift UTF16View](https://developer.apple.com/documentation/swift/string/utf16view)。
- 韩语谚文、俄语西里尔字母、由右至左文本、组合附加符号、连接符、表情符号及混合文本皆可输入，不会对文本进行规范化或按字母系统过滤。浏览器输入栏会自动调整文本方向。界面与审阅备注仍为繁体中文；这不代表 App 界面已翻译成 28 种语言。
- 英文模式会分开处理指令语言与下游答案语言。模型必须保留明确答案语言要求、否定范围、固定字符串、变量、代码与 URL。若引号或代码中的固定字符串仅因 NFC 规范化而被更改，后端会以有限规则修复明确可判定的情况。若字符串被省略、翻译或改为语义相近但拼法不同，后端无法重建；重要字符串请自行检查。
- 涵盖目标包括英语、繁体／简体中文、西班牙语、法语、德语、葡萄牙语、义大利语、俄语、土耳其语、荷兰语、波兰语、乌克兰语、日语、韩语、印地语、孟加拉语、印尼语、越南语、泰语、泰米尔语、泰卢固语、马拉地语、阿拉伯语、乌尔都语、波斯语、斯瓦希里语、旁遮普语与菲律宾语。这不是通用的 GitHub 语言标准，也不代表模型有通用质量保证。
- 2026-10-09 的实时示例使用现有 `deepseek-flash` 配置：韩语和俄语各有简短、中等和较长案例；其他示例涵盖英语、两种中文、日语、西班牙语、法语、德语、葡萄牙语、义大利语、乌克兰语、阿拉伯语、波斯语、印地语、孟加拉语、泰语、越南语和印尼语。另有一个英文指令案例检查混合韩／俄字符串、NFD 重音、表情符号、变量与 URL；它不能取代韩语／俄语语义测试。
- 总计是 18 种语言的 24 个独立合成案例，并依发现的问题进行定向重测。最终 Prompt 示例符合审阅的核心限制；一项日文优化说明仍不够精确。其他目标语言、其他模型、复杂领域输入、原生 RTL 显示及所有宿主 App 工作流程都尚未认证。完整 Prompt 与审阅结果见[公开验证记录](docs/multilingual-verification.md)。

## HTTP API

独立服务器默认为 `http://127.0.0.1:3000`。原生 App 管理的后端使用 `http://127.0.0.1:3210`。

```sh
curl --fail --silent --show-error http://127.0.0.1:3000/api/config

curl --fail --silent --show-error http://127.0.0.1:3000/api/optimize \
  -H 'Content-Type: application/json' \
  --data '{"prompt":"Write a brief invitation. Keep ACME-42 unchanged. Answer in Spanish.","task":"writing","targetModel":"","promptLanguage":"en"}'
```

| 请求字段 | 行为 |
| --- | --- |
| `prompt` | 必填且不可空白；最多 12,000 个 UTF-16 code unit。 |
| `task` | `general`（默认）、`writing`、`analysis`、`coding`、`summary` 或 `marketing`。 |
| `targetModel` | 可选下游模型提示；单行，最多 80 个 UTF-16 code unit。 |
| `promptLanguage` | `en` 表示英文指令；未提供时默认 `zh-Hant`。 |

成功时返回 `prompt`、`improvements`、`assumptions`、`mode`、`generationModel` 与 `promptLanguage`。重用结果时只复制 `prompt`；优化说明与假设是独立的审阅备注。英文模式的备注仍使用繁体中文。

API 会验证输入与模型响应结构、限制同时进行的优化请求，并报告配置、供应商、格式错误和超时错误。取消操作会关闭上游请求；供应商端的处理和计费仍由供应商控制。

## macOS 操作流程

1. 打开 App 手动工作台，输入或贴上需求，选择任务与可选目标模型，再生成英文 Prompt。
2. 检视 Prompt 与分开显示的备注。可复制 Prompt，或清空工作区以移除输入与结果。
3. 使用文本选择操作时，依提示在系统设置中启用「辅助功能」。在兼容的输入框中选择文本并按右键，再于辅助菜单选 **Convert to an English Prompt**；结果会显示在附近。宿主 App 原有的上下文菜单仍可使用。按取消、点击其他位置、键盘输入、切换 App 或等待 12 秒，都会关闭操作提示而不生成结果。只有在明确选择该操作后，助手才会再次检查选择内容。也可使用选择按钮。部分 Electron App 可能显示启用提示：等待约两秒、重新选择文本后再试。
4. 其他入口包括默认的 Option-Command-P 快捷键、支持的 macOS 服务，以及明确的剪贴板操作。宿主 App 必须提供可用的文本选择功能，因此不保证所有 App 都兼容。
5. 可选自动贴回会检查来源 App、焦点字段、文本与选择范围后才取代已选文本。若无法再确认来源，则改为复制结果。面板也提供复制及手动贴回。贴回不会送出聊天信息，并可在配置中停用。Mock 结果不会贴回。

关闭工作区窗口后，选择助手仍会在菜单栏运作；结束 App 则会停止由它启动的后端。辅助菜单是独立且不会启用宿主 App 的操作面板，不会插入宿主 App 原有的上下文菜单。详见[右键操作验证](docs/context-menu-verification.md)。

### 仅更新原生后端

更改可信任的后端或浏览器代码后，可只更新已安装 App 的外部后端，不必重建已签名的原生可执行文件：

```sh
npm run update:mac-backend
```

更新程序会先暂存并以 mock HTTP 检查候选版本，正常关闭 App、检查端口，再切换后端版本并重新启动 App。若启动失败会尝试恢复。它不会更改所选模型配置，也不会终止无关的端口监听进程。Swift 或原生 UI 更改仍须运行 `build:mac` 与 `install:mac`。

## 架构

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

主要原始码：

- [server.js](server.js)：HTTP API、静态文件、请求验证与错误处理。
- [lib/optimizer.js](lib/optimizer.js)：配置、mock／实时模型适配器、编辑指示与响应验证。
- [public/](public/)：支持响应式版面的繁体中文浏览器工作台。
- [macos/Sources/](macos/Sources/)：原生工作台、后端生命周期、选择、结果面板与贴回功能。
- [scripts/](scripts/)：原生构建、本地签名、安装、后端更新与开发检查。

## 隐私与数据处理

- API 密钥由 Node.js 后端从本地配置读取，不会暴露在前端代码或封装进 App。目前密钥以纯文本环境文件保存；尚未整合 Keychain 密钥存储。
- 输入、结果与说明在内存中处理，不使用数据库或 Prompt 历史记录。原生偏好设置及配置路径会存储在本地。原生诊断记录状态元数据与长度，不记录 Prompt 内容。
- 实时模式会将请求与编辑指示传送至已配置的模型供应商，并受该供应商的数据保留政策约束。Mock 不会调用模型。
- 浏览器界面不使用 Cookie、浏览器存储、分析工具或远程字体；重新加载会清空工作区。原生工作区可透过清除操作或结束内存会话清空。
- 启用文本选择操作后，App 会监听鼠标事件并读取可访问的文本选择内容。若安全的可编辑字段提供非空选择范围但没有选择文本属性，助手可能暂时读取字段值。超过 65,536 个 UTF-16 code unit 的值会被拒绝；只会返回选择范围，也不会记录字段内容。
- 复制、贴回及备用复制会使用系统剪贴板。恢复操作会先确认用户没有复制新内容。清空工作区不会删除已复制到系统剪贴板的文本。

这是供个人本地使用的工具，没有账户验证或多用户隔离。独立服务器支持部署配置，但公开部署需要自行配置 HTTPS 与访问控制。远程部署及 Docker 运行尚未验证。

## 验证结果与限制

以下检查结合 2026-10-09 的多语更新与明确右键菜单修正。浏览器与实时模型证据属于多语更新，没有在此次仅涉及原生代码的修改中重跑。

| 已记录检查 | 范围 |
| --- | --- |
| JavaScript 语法与 Node HTTP 测试 | 语法通过；49 个后端测试通过，涵盖 Unicode 传输、UTF-8 分块边界、NFC 固定字符串修复与不截断长度验证。 |
| 原生核心／API／剪贴板检查 | 81 项通过：原有 66 项，加上明确菜单选择、取消／关闭、AppKit 按钮操作只执行一次，以及来源更改、逾期、忙碌或停用时的保护。 |
| 浏览器流程测试 | 10 项 Chrome 测试通过，包含英语／中文切换、混合 Unicode、RTL 方向、超长 emoji 插入不会静默截断、复制、错误、取消及 390／320px 窗口。 |
| 实时模型样例 | 18 种语言共 24 个案例，包含韩语／俄语简短、中等和较长案例。人工审阅的核心 Prompt 通过；一项日文优化说明仍不够精确。 |
| 原生工作区与 IDE（现有证据） | 曾手动观察生成及清除流程。用户确认 Codex 面板恢复正常，并在新版菜单修改前提到 Claude 也可使用；这不代表新版每项操作都已认证。 |
| 新版右键菜单（用户验收） | 用户确认原上下文菜单仍存在、辅助菜单出现时不会自动生成，并在明确点击后取得英语结果。 |

新版菜单已由用户确认可显示并以一次点击生成；各宿主 App 中完整的复制／贴回／取消测试仍有限。先前 Codex／Claude 的成功经验不代表新版所有操作均已认证。未测试的语言与其他宿主 App 仍未验证。浏览器窗口尺寸测试不等同实体 iOS 或 Android 测试。HTTP 成功及受控供应商 Unicode 往返测试都不代表翻译质量。

尚未提供或验证：OCR、可配置的全局快捷键、包含 Node、功能自动更新、Universal Binary、Developer ID 签名、公证、下载二进制文件的 Gatekeeper 行为、其他实体 macOS／CPU 组合及公开二进制发行版。项目包含 GitHub 检查工作流程，但尚未验证远程运行。README 不宣称提供预先构建下载文件或成功的 CI 徽章。

## 开发

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

`npm run dev` 会以 Node watch 模式运行独立服务器。API 测试使用本地假模型服务，不代表真实模型翻译质量。原生测试不能取代在各宿主 App 中以实体操作测试文本选择及右键流程。项目包含 [GitHub workflow](.github/workflows/check.yml)，涵盖 Node 检查与 macOS 原生检查／构建，但不代表已发布或已确认远程 CI 运行结果。

## 贡献与授权

开发规范请参阅 [CONTRIBUTING.md](CONTRIBUTING.md)。欢迎修正翻译，以及使用可分享合成输入的可复现的问题报告。请勿在贡献中放入 API 密钥、本地环境文件、私人 Prompt、剪贴板内容或个人签名数据。

PromptFinch 使用 [MIT License](LICENSE)。模型供应商账户及任何模型费用由各用户自行负责。

</details>

<a id="lang-es"></a>
<details>
<summary>Español</summary>

PromptFinch: editor y optimizador general. Introduce o selecciona instrucciones en cualquier idioma; produce prompts en inglés para escribir, programar, investigar, resumir y planificar. Preserva requisitos explícitos, idioma de respuesta solicitado y textos fijos entre comillas.

La aplicación para macOS combina espacio manual y asistente de selección; hay versión web. Generación real: clave API de modelo configurada. Modo simulado: vista previa del flujo, sin traducción ni optimización. Interfaz actual: chino tradicional; estas traducciones son documentación.

**Flujo:** seleccionar texto → clic derecho → panel de resultados (aplicaciones compatibles).

</details>

<a id="lang-fr"></a>
<details>
<summary>Français</summary>

PromptFinch: éditeur et optimiseur polyvalent de consignes. Saisissez ou sélectionnez des consignes dans toute langue pour produire une invite anglaise destinée à écrire, coder, rechercher, résumer ou planifier. Exigences explicites, langue de réponse demandée et textes fixes entre guillemets sont préservés.

L’application macOS associe espace manuel et assistant de sélection; espace web disponible. Génération réelle: clé API de modèle configurée. Mode simulé: aperçu du parcours sans traduction ni optimisation. Interface actuellement en chinois traditionnel; traductions documentaires uniquement.

**Parcours:** sélectionner du texte → clic droit → panneau de résultats (applications compatibles).

</details>

<a id="lang-de"></a>
<details>
<summary>Deutsch</summary>

PromptFinch ist ein vielseitiger Prompt-Editor und -Optimierer. Eingaben oder markierte Anweisungen in jeder Sprache werden zu englischen Prompts für Schreiben, Programmieren, Recherche, Zusammenfassungen und Planung. Explizite Anforderungen, gewünschte Antwortsprache und feste Zeichenfolgen in Anführungszeichen bleiben erhalten.

Die macOS-App verbindet manuellen Arbeitsbereich und Auswahlassistent; ein Browser-Arbeitsbereich ist verfügbar. Echte Generierung benötigt einen konfigurierten API-Schlüssel für ein Modell. Der Simulationsmodus zeigt den Ablauf, ohne zu übersetzen oder zu optimieren. Oberfläche derzeit traditionelles Chinesisch; Übersetzungen nur Dokumentation.

**Ablauf:** Text markieren → Rechtsklick → Ergebnispanel (kompatible Apps).

</details>

<a id="lang-pt"></a>
<details>
<summary>Português</summary>

PromptFinch: editor e otimizador de uso geral. Introduza ou selecione instruções em qualquer idioma: prompts em inglês para escrita, programação, pesquisa, resumos e planeamento. Preserva requisitos explícitos, idioma de resposta solicitado e textos fixos entre aspas.

A aplicação para macOS combina espaço manual e assistente de seleção; há versão web. Geração real: chave API de modelo configurada. Modo simulado: pré-visualização do fluxo, sem tradução nem otimização. Interface atual em chinês tradicional; traduções apenas documentais.

**Fluxo:** selecionar texto → clique direito → painel de resultados (aplicações compatíveis).

</details>

<a id="lang-it"></a>
<details>
<summary>Italiano</summary>

PromptFinch: editor e ottimizzatore di uso generale. Inserisci o seleziona istruzioni in qualsiasi lingua per produrre prompt inglesi per scrittura, programmazione, ricerca, riassunti e pianificazione. Preserva requisiti espliciti, lingua di risposta richiesta e stringhe fisse tra virgolette.

L’app per macOS combina spazio manuale e assistente di selezione; disponibile anche nel browser. Generazione reale: chiave API del modello configurata. Modalità simulata: anteprima del flusso senza traduzione né ottimizzazione. Interfaccia attualmente in cinese tradizionale; traduzioni solo documentali.

**Flusso:** seleziona testo → clic destro → pannello dei risultati (app compatibili).

</details>

<a id="lang-ru"></a>
<details>
<summary>Русский</summary>

PromptFinch — универсальный редактор и оптимизатор запросов. Вводите или выделяйте инструкции на любом языке, чтобы получить английский запрос для написания текстов, программирования, исследований, кратких изложений и планирования. Явные требования, запрошенный язык ответа и фиксированные строки в кавычках сохраняются.

Приложение macOS объединяет ручную рабочую область и помощника выделения; доступна также версия в браузере. Реальная генерация требует настроенного API-ключа модели. Режим имитации показывает процесс без перевода или оптимизации. Интерфейс пока на традиционном китайском; переводы здесь — только документация.

**Процесс:** выделить текст → щёлкнуть правой кнопкой → панель результатов (совместимые приложения).

</details>

<a id="lang-tr"></a>
<details>
<summary>Türkçe</summary>

PromptFinch, genel amaçlı bir istem düzenleyici ve iyileştiricidir. Herhangi bir dilde talimat girin veya seçin; yazma, kodlama, araştırma, özetleme ve planlama için İngilizce istem oluşturun. Açık gereksinimler, istenen yanıt dili ve tırnak içindeki sabit metinler korunur.

macOS uygulaması, elle kullanılan çalışma alanını seçim asistanıyla birleştirir; tarayıcı çalışma alanı da mevcuttur. Üretim için yapılandırılmış model API anahtarı gerekir. Simülasyon modu işleyişi gösterir; çeviri veya iyileştirme yapmaz. Arayüz şimdilik Geleneksel Çincedir; çeviriler yalnızca belgelendirmedir.

**Akış:** metni seçin → sağ tıklayın → sonuç paneli (uyumlu uygulamalar).

</details>

<a id="lang-nl"></a>
<details>
<summary>Nederlands</summary>

PromptFinch is een veelzijdige prompteditor en -optimalisator. Voer instructies in of selecteer ze, in elke taal; maak Engelse prompts voor schrijven, programmeren, onderzoek, samenvattingen en planning. Expliciete eisen, gevraagde antwoordtaal en vaste tekenreeksen tussen aanhalingstekens blijven behouden.

De macOS-app combineert een handmatige werkruimte met een selectieassistent; een browserwerkruimte is beschikbaar. Werkelijke generatie vereist een ingestelde API-sleutel voor het model. De simulatiemodus toont de werkwijze en vertaalt of optimaliseert niet. Interface momenteel in traditioneel Chinees; deze vertalingen dienen alleen als documentatie.

**Werkwijze:** tekst selecteren → rechtsklikken → resultatenpaneel (compatibele apps).

</details>

<a id="lang-pl"></a>
<details>
<summary>Polski</summary>

PromptFinch to uniwersalny edytor i optymalizator promptów. Wpisz lub zaznacz instrukcje w dowolnym języku, aby otrzymać angielski prompt do pisania, programowania, badań, podsumowań i planowania. Zachowuje jawne wymagania, żądany język odpowiedzi oraz stałe ciągi znaków w cudzysłowie.

Aplikacja macOS łączy ręczny obszar roboczy z asystentem zaznaczania; dostępna jest także wersja przeglądarkowa. Rzeczywiste generowanie wymaga skonfigurowanego klucza API modelu. Tryb symulacji pokazuje przebieg bez tłumaczenia i optymalizacji. Interfejs: obecnie chiński tradycyjny; tłumaczenia wyłącznie dokumentacyjne.

**Przebieg:** zaznacz tekst → kliknij prawym przyciskiem → panel wyników (kompatybilne aplikacje).

</details>

<a id="lang-uk"></a>
<details>
<summary>Українська</summary>

PromptFinch — універсальний редактор і оптимізатор запитів. Вводьте або виділяйте інструкції будь-якою мовою, щоб отримати англомовний запит для написання текстів, програмування, досліджень, стислих викладів і планування. Явні вимоги, запитана мова відповіді та фіксовані рядки в лапках зберігаються.

Застосунок macOS поєднує ручний робочий простір і помічника виділення; доступний також простір у браузері. Реальна генерація потребує налаштованого API-ключа моделі. Режим імітації показує процес без перекладу чи оптимізації. Інтерфейс наразі традиційною китайською; ці переклади — лише документація.

**Процес:** виділити текст → клацнути правою кнопкою → панель результатів (сумісні застосунки).

</details>

<a id="lang-ja"></a>
<details>
<summary>日本語</summary>

### PromptFinchについて

PromptFinchは汎用のプロンプト編集・最適化ツールです。任意の言語で指示を入力・選択し、文章作成、プログラミング、調査、要約、計画向けの英語プロンプトを生成します。明示された条件、回答言語、引用された固定文字列を保持します。

macOSでは作業スペースと選択アシスタントを利用でき、対応アプリでテキストを選択して右クリックすると結果パネルが表示されます。ブラウザ版も利用可能です。実際の生成にはモデルのAPIキー設定が必要です。モックモードは操作のプレビューのみで、翻訳・最適化は行いません。UIは繁体字中国語で、この翻訳はREADME用です。

**操作:** 入力・選択 → 英語プロンプトを生成 → 結果を確認

</details>

<a id="lang-ko"></a>
<details>
<summary>한국어</summary>

### PromptFinch 소개

PromptFinch는 범용 프롬프트 편집·최적화 도구입니다. 어떤 언어로든 지시를 입력하거나 선택해 글쓰기, 코딩, 조사, 요약, 계획에 사용할 영어 프롬프트를 생성합니다. 명시한 요구사항, 요청한 답변 언어, 따옴표로 지정한 고정 문자열을 보존합니다.

macOS 작업 공간과 선택 도우미를 제공하며, 호환 앱에서 텍스트를 선택하고 마우스 오른쪽 버튼을 누르면 결과 패널이 표시됩니다. 브라우저 작업 공간도 있습니다. 실제 생성에는 모델 API 키 설정이 필요합니다. 모의 모드는 작업 흐름만 미리 보여주며 번역·최적화하지 않습니다. UI는 중국어 번체이고, 이 번역은 README 문서용입니다.

**사용 흐름:** 입력·선택 → 영어 프롬프트 생성 → 결과 확인

</details>

<a id="lang-hi"></a>
<details>
<summary>हिन्दी</summary>

### PromptFinch परिचय

PromptFinch सामान्य प्रयोजन का प्रॉम्प्ट संपादक और अनुकूलक है। किसी भी भाषा में निर्देश लिखें या चुनें और लेखन, कोडिंग, शोध, सारांश तथा योजना के लिए अंग्रेज़ी प्रॉम्प्ट बनाएँ। स्पष्ट आवश्यकताएँ, उत्तर की माँगी गई भाषा और उद्धृत निश्चित पाठ सुरक्षित रहते हैं।

macOS कार्यक्षेत्र और चयन सहायक देता है: संगत ऐप में पाठ चुनकर दायाँ क्लिक करें और परिणाम पैनल देखें। ब्राउज़र कार्यक्षेत्र भी उपलब्ध है। वास्तविक जनरेशन के लिए मॉडल API कुंजी चाहिए। मॉक मोड केवल प्रक्रिया दिखाता है; अनुवाद या अनुकूलन नहीं करता। UI पारंपरिक चीनी में है; यह अनुवाद केवल README के लिए है।

**प्रक्रिया:** लिखें या चुनें → अंग्रेज़ी प्रॉम्प्ट बनाएँ → परिणाम देखें

</details>

<a id="lang-bn"></a>
<details>
<summary>বাংলা</summary>

### PromptFinch পরিচিতি

PromptFinch একটি সাধারণ উদ্দেশ্যের প্রম্পট সম্পাদক ও উন্নয়নকারী। যেকোনো ভাষায় নির্দেশ লিখুন বা নির্বাচন করুন এবং লেখা, কোডিং, গবেষণা, সারসংক্ষেপ ও পরিকল্পনার জন্য ইংরেজি প্রম্পট তৈরি করুন। স্পষ্ট চাহিদা, উত্তরের অনুরোধকৃত ভাষা এবং উদ্ধৃত নির্দিষ্ট পাঠ সংরক্ষিত থাকে।

macOS-এ কর্মক্ষেত্র ও নির্বাচন সহকারী রয়েছে: সমর্থিত অ্যাপে পাঠ নির্বাচন করে রাইট-ক্লিক করলে ফলাফলের প্যানেল দেখা যায়। ব্রাউজার কর্মক্ষেত্রও আছে। প্রকৃত প্রম্পট তৈরিতে মডেলের API কী প্রয়োজন। মক মোড শুধু কার্যপ্রবাহ দেখায়; অনুবাদ বা উন্নয়ন করে না। UI ঐতিহ্যবাহী চীনা ভাষায়; এই অনুবাদ শুধু README-এর জন্য।

**ধাপ:** লিখুন বা নির্বাচন করুন → ইংরেজি প্রম্পট তৈরি করুন → ফলাফল দেখুন

</details>

<a id="lang-id"></a>
<details>
<summary>Bahasa Indonesia</summary>

### Tentang PromptFinch

PromptFinch adalah editor dan pengoptimal prompt serbaguna. Instruksi dalam bahasa apa pun dapat menjadi prompt bahasa Inggris untuk menulis, pemrograman, riset, ringkasan, dan perencanaan. Persyaratan eksplisit, bahasa jawaban yang diminta, dan teks tetap dalam kutipan dipertahankan.

Tersedia ruang kerja macOS dan browser. Asisten pilihan teks macOS menampilkan panel hasil melalui klik kanan di aplikasi kompatibel. Generasi langsung memerlukan kunci API model. Mode simulasi hanya memperlihatkan alur, tanpa menerjemahkan atau mengoptimalkan. UI menggunakan bahasa Tionghoa Tradisional; terjemahan README ini hanya dokumentasi.

**Alur:** Masukkan atau pilih → Hasilkan prompt Inggris → Tinjau hasil

</details>

<a id="lang-vi"></a>
<details>
<summary>Tiếng Việt</summary>

### Giới thiệu PromptFinch

PromptFinch là công cụ chỉnh sửa và tối ưu prompt đa mục đích. Nhập hoặc chọn chỉ dẫn bằng bất kỳ ngôn ngữ nào để tạo prompt tiếng Anh cho viết lách, lập trình, nghiên cứu, tóm tắt và lập kế hoạch. Công cụ giữ nguyên yêu cầu rõ ràng, ngôn ngữ trả lời được yêu cầu và chuỗi cố định trong dấu ngoặc kép.

Ứng dụng macOS có không gian làm việc và trợ lý văn bản được chọn: chọn văn bản rồi nhấp chuột phải trong ứng dụng tương thích để xem bảng kết quả. Có cả không gian làm việc trên trình duyệt. Tạo nội dung thực tế cần khóa API của mô hình. Chế độ mô phỏng chỉ xem trước quy trình, không dịch hay tối ưu. UI hiện dùng tiếng Trung phồn thể; bản dịch này chỉ dành cho README.

**Quy trình:** Nhập hoặc chọn → Tạo prompt tiếng Anh → Xem kết quả

</details>

<a id="lang-th"></a>
<details>
<summary>ไทย</summary>

### เกี่ยวกับ PromptFinch

PromptFinch คือเครื่องมือแก้ไขและปรับปรุงพรอมป์ต์สำหรับงานทั่วไป ป้อนหรือเลือกคำสั่งภาษาใดก็ได้เพื่อสร้างพรอมป์ต์ภาษาอังกฤษสำหรับการเขียน การเขียนโค้ด การค้นคว้า การสรุป และการวางแผน โดยคงข้อกำหนดที่ระบุชัดเจน ภาษาคำตอบที่ร้องขอ และข้อความตายตัวในเครื่องหมายอัญประกาศไว้

แอป macOS มีพื้นที่ทำงานและผู้ช่วยสำหรับข้อความที่เลือก: เลือกข้อความแล้วคลิกขวาในแอปที่รองรับเพื่อแสดงแผงผลลัพธ์ มีพื้นที่ทำงานบนเบราว์เซอร์ด้วย การสร้างจริงต้องตั้งค่าคีย์ API ของโมเดล โหมดจำลองแสดงตัวอย่างขั้นตอนเท่านั้น ไม่แปลหรือปรับปรุงพรอมป์ต์ UI ใช้ภาษาจีนตัวเต็ม ส่วนคำแปลนี้ใช้สำหรับ README เท่านั้น

**ขั้นตอน:** ป้อนหรือเลือก → สร้างพรอมป์ต์ภาษาอังกฤษ → ตรวจสอบผลลัพธ์

</details>

<a id="lang-ta"></a>
<details>
<summary>தமிழ்</summary>

### PromptFinch அறிமுகம்

PromptFinch என்பது பொதுப் பயன்பாட்டுக்கான ப்ராம்ப்ட் திருத்தி மற்றும் மேம்படுத்தி. எந்த மொழியிலும் வழிமுறைகளை உள்ளிடலாம் அல்லது தேர்ந்தெடுக்கலாம்; எழுத்து, நிரலாக்கம், ஆராய்ச்சி, சுருக்கம், திட்டமிடல் ஆகியவற்றிற்கான ஆங்கில ப்ராம்ப்ட்களை உருவாக்கலாம். வெளிப்படையான தேவைகள், கோரப்பட்ட பதில் மொழி, மேற்கோள்களில் உள்ள நிலையான உரைகள் பாதுகாக்கப்படும்.

macOS செயலியில் பணியிடமும் தேர்வு உதவியாளரும் உள்ளன: இணக்கமான செயலிகளில் உரையைத் தேர்ந்தெடுத்து வலது கிளிக் செய்தால் முடிவுப் பலகம் தோன்றும். உலாவிப் பணியிடமும் உள்ளது. உண்மையான உருவாக்கத்திற்கு மாதிரியின் API விசையை அமைக்க வேண்டும். மாதிரி விளக்கப் பயன்முறை செயல்பாட்டை மட்டும் காட்டும்; மொழிபெயர்க்கவோ மேம்படுத்தவோ செய்யாது. UI பாரம்பரிய சீன மொழியில் உள்ளது; இந்த மொழிபெயர்ப்பு README ஆவணத்திற்கானது மட்டுமே.

**செயல்முறை:** உள்ளிடுக அல்லது தேர்ந்தெடுக்கவும் → ஆங்கில ப்ராம்ப்ட்டை உருவாக்கவும் → முடிவைப் பார்க்கவும்

</details>

<a id="lang-te"></a>
<details>
<summary>తెలుగు</summary>

### PromptFinch పరిచయం

PromptFinch సాధారణ అవసరాల కోసం ప్రాంప్ట్‌లను సవరించి మెరుగుపరిచే సాధనం. ఏ భాషలోనైనా సూచనలను నమోదు చేయండి లేదా ఎంచుకోండి; రచన, కోడింగ్, పరిశోధన, సారాంశాలు, ప్రణాళికల కోసం ఆంగ్ల ప్రాంప్ట్‌లను రూపొందించండి. స్పష్టమైన అవసరాలు, కోరిన సమాధాన భాష, కొటేషన్ గుర్తుల్లోని స్థిరమైన వచనం అలాగే ఉంటాయి.

macOS యాప్‌లో కార్యస్థలం, ఎంపిక సహాయకం ఉన్నాయి: అనుకూల యాప్‌లలో వచనాన్ని ఎంచుకుని కుడి క్లిక్ చేస్తే ఫలితాల ప్యానెల్ కనిపిస్తుంది. బ్రౌజర్ కార్యస్థలం కూడా ఉంది. నిజమైన రూపొందింపుకు మోడల్ API కీని అమర్చాలి. నమూనా మోడ్ ప్రక్రియను మాత్రమే చూపిస్తుంది; అనువాదం లేదా మెరుగుదల చేయదు. UI సంప్రదాయ చైనీస్‌లో ఉంది; ఈ అనువాదం README పత్రం కోసం మాత్రమే.

**ప్రక్రియ:** నమోదు చేయండి లేదా ఎంచుకోండి → ఆంగ్ల ప్రాంప్ట్ రూపొందించండి → ఫలితాన్ని చూడండి

</details>

<a id="lang-mr"></a>
<details>
<summary>मराठी</summary>

### PromptFinch परिचय

PromptFinch हे सर्वसाधारण वापरासाठी प्रॉम्प्ट संपादन आणि सुधारणा करणारे साधन आहे. कोणत्याही भाषेत सूचना लिहा किंवा निवडा आणि लेखन, कोडिंग, संशोधन, सारांश व नियोजनासाठी इंग्रजी प्रॉम्प्ट तयार करा. स्पष्ट आवश्यकता, उत्तराची मागितलेली भाषा आणि अवतरणचिन्हांतील निश्चित मजकूर जतन होतो.

macOS अ‍ॅपमध्ये कार्यक्षेत्र आणि निवड सहाय्यक आहे: सुसंगत अ‍ॅपमध्ये मजकूर निवडून उजवे क्लिक केल्यावर निकाल पॅनेल दिसते. ब्राउझर कार्यक्षेत्रही उपलब्ध आहे. प्रत्यक्ष निर्मितीसाठी मॉडेलची API की आवश्यक आहे. मॉक मोड फक्त प्रक्रिया दाखवतो; भाषांतर किंवा सुधारणा करत नाही. UI पारंपरिक चिनी भाषेत आहे; हे भाषांतर फक्त README दस्तऐवजासाठी आहे.

**प्रक्रिया:** लिहा किंवा निवडा → इंग्रजी प्रॉम्प्ट तयार करा → निकाल पाहा

</details>

<a id="lang-ar"></a>
<details>
<summary>العربية</summary>

<div dir="rtl">

### العربية

PromptFinch محرّر عام للموجّهات ومحسّن لها، للكتابة والبرمجة والبحث والتلخيص والتخطيط. أدخل تعليمات بأي لغة أو حدّدها لإنشاء موجّه بالإنجليزية، مع الحفاظ على المتطلبات الصريحة ولغة الإجابة المطلوبة والنصوص الثابتة بين علامتي اقتباس.

يوفّر تطبيق macOS مساحة للعمل اليدوي ومساعدًا للنص المحدّد؛ انقر بزر الفأرة الأيمن لعرض النتائج في التطبيقات المتوافقة. تتوفّر أيضًا مساحة عبر المتصفح. يتطلّب التوليد الفعلي مفتاح API مُعدًّا للنموذج. يعرض وضع Mock سير العمل دون ترجمة أو تحسين. الواجهة بالصينية التقليدية؛ هذه ترجمة للتوثيق فقط.

**الخطوات:** أدخل التعليمات أو حدّدها، ثم ولّد الموجّه وراجعه وانسخه.

</div>
</details>

<a id="lang-ur"></a>
<details>
<summary>اردو</summary>

<div dir="rtl">

### اردو

PromptFinch لکھنے، کوڈنگ، تحقیق، خلاصوں اور منصوبہ بندی کے لیے پرامپٹ ایڈیٹر اور بہتر بنانے والا ٹول ہے۔ کسی بھی زبان میں ہدایات درج یا منتخب کرکے انگریزی پرامپٹ بنائیں۔ واضح تقاضے، جواب کی مطلوبہ زبان اور اقتباسی علامات میں موجود مقررہ متن برقرار رہتے ہیں۔

macOS ایپ میں دستی ورک اسپیس اور منتخب متن کا معاون ہے؛ مطابقت رکھنے والی ایپس میں منتخب متن پر دایاں کلک کرکے نتائج دیکھیں۔ براؤزر ورک اسپیس بھی دستیاب ہے۔ حقیقی جنریشن کے لیے ماڈل کی API کلید ترتیب دینا ضروری ہے۔ Mock صرف عمل کا پیش منظر دکھاتا ہے، ترجمہ یا بہتری نہیں کرتا۔ انٹرفیس روایتی چینی میں ہے؛ یہ صرف دستاویزات کا ترجمہ ہے۔

**طریقہ:** ہدایات درج یا منتخب کریں، پرامپٹ بنائیں، پھر جائزہ لے کر کاپی کریں۔

</div>
</details>

<a id="lang-fa"></a>
<details>
<summary>فارسی</summary>

<div dir="rtl">

### فارسی

PromptFinch ابزار عمومی ویرایش و بهینه‌سازی پرامپت برای نوشتن، برنامه‌نویسی، پژوهش، خلاصه‌سازی و برنامه‌ریزی است. دستورها را به هر زبانی وارد یا انتخاب کنید تا پرامپتی انگلیسی ساخته شود؛ الزامات صریح، زبان درخواستی پاسخ و عبارت‌های ثابت داخل گیومه حفظ می‌شوند.

برنامهٔ macOS فضای کار دستی و دستیار متن انتخاب‌شده دارد؛ در برنامه‌های سازگار، روی متن انتخاب‌شده راست‌کلیک کنید تا نتایج نمایش داده شوند. فضای کار مرورگر نیز موجود است. تولید واقعی به کلید API پیکربندی‌شدهٔ مدل نیاز دارد. حالت Mock فقط روند کار را نمایش می‌دهد و ترجمه یا بهینه‌سازی نمی‌کند. رابط به چینی سنتی است؛ این ترجمه فقط برای مستندات است.

**روند کار:** دستورها را وارد یا انتخاب کنید، پرامپت بسازید، سپس بازبینی و کپی کنید.

</div>
</details>

<a id="lang-sw"></a>
<details>
<summary>Kiswahili</summary>

### Kiswahili

PromptFinch huhariri na kuboresha prompti za uandishi, programu, utafiti, muhtasari na mipango. Ingiza au chagua maagizo katika lugha yoyote ili kupata prompti ya Kiingereza, huku ukihifadhi mahitaji yaliyobainishwa, lugha ya jibu iliyoombwa na maandishi maalumu ndani ya alama za kunukuu.

Programu ya macOS ina sehemu ya kuandika na msaidizi wa maandishi yaliyochaguliwa; bofya kulia kuona matokeo katika programu zinazooana. Sehemu ya kivinjari pia inapatikana. Uzalishaji halisi unahitaji ufunguo wa API wa modeli uliosanidiwa. Mock huonyesha mchakato bila kutafsiri au kuboresha. Kiolesura ni cha Kichina cha Jadi; hii ni tafsiri ya nyaraka pekee.

**Hatua:** Ingiza/chagua → zalisha → kagua/nakili.

</details>

<a id="lang-pa"></a>
<details>
<summary>ਪੰਜਾਬੀ</summary>

### ਪੰਜਾਬੀ

PromptFinch ਲਿਖਣ, ਕੋਡਿੰਗ, ਖੋਜ, ਸਾਰ ਬਣਾਉਣ ਅਤੇ ਯੋਜਨਾਬੰਦੀ ਲਈ ਪ੍ਰੌਂਪਟ ਸੰਪਾਦਕ ਅਤੇ ਸੁਧਾਰਕ ਹੈ। ਕਿਸੇ ਵੀ ਭਾਸ਼ਾ ਵਿੱਚ ਹਦਾਇਤਾਂ ਦਾਖ਼ਲ ਜਾਂ ਚੁਣ ਕੇ ਅੰਗਰੇਜ਼ੀ ਪ੍ਰੌਂਪਟ ਬਣਾਓ। ਸਪਸ਼ਟ ਲੋੜਾਂ, ਜਵਾਬ ਲਈ ਮੰਗੀ ਭਾਸ਼ਾ ਅਤੇ ਹਵਾਲਾ-ਚਿੰਨ੍ਹਾਂ ਵਿੱਚ ਦਿੱਤਾ ਸਥਿਰ ਟੈਕਸਟ ਬਰਕਰਾਰ ਰਹਿੰਦਾ ਹੈ।

macOS ਐਪ ਵਿੱਚ ਹੱਥੀਂ ਕੰਮ ਕਰਨ ਦੀ ਥਾਂ ਅਤੇ ਚੁਣੇ ਟੈਕਸਟ ਲਈ ਸਹਾਇਕ ਹੈ; ਅਨੁਕੂਲ ਐਪਾਂ ਵਿੱਚ ਚੁਣੇ ਟੈਕਸਟ ਉੱਤੇ ਸੱਜਾ-ਕਲਿੱਕ ਕਰਕੇ ਨਤੀਜੇ ਵੇਖੋ। ਬ੍ਰਾਊਜ਼ਰ ਵਰਕਸਪੇਸ ਵੀ ਉਪਲਬਧ ਹੈ। ਅਸਲ ਜਨਰੇਸ਼ਨ ਲਈ ਮਾਡਲ ਦੀ ਸੰਰਚਿਤ API ਕੁੰਜੀ ਚਾਹੀਦੀ ਹੈ। Mock ਸਿਰਫ਼ ਕਾਰਜ-ਪ੍ਰਵਾਹ ਦਿਖਾਉਂਦਾ ਹੈ, ਅਨੁਵਾਦ ਜਾਂ ਸੁਧਾਰ ਨਹੀਂ ਕਰਦਾ। ਇੰਟਰਫੇਸ ਰਵਾਇਤੀ ਚੀਨੀ ਵਿੱਚ ਹੈ; ਇਹ ਸਿਰਫ਼ ਦਸਤਾਵੇਜ਼ਾਂ ਦਾ ਅਨੁਵਾਦ ਹੈ।

**ਕਦਮ:** ਦਾਖ਼ਲ ਕਰੋ/ਚੁਣੋ → ਪ੍ਰੌਂਪਟ ਬਣਾਓ → ਜਾਂਚੋ/ਕਾਪੀ ਕਰੋ।

</details>

<a id="lang-fil"></a>
<details>
<summary>Filipino</summary>

### Filipino

Pang-edit at pagpapahusay ng prompt ang PromptFinch para sa pagsusulat, coding, pananaliksik, pagbubuod at pagpaplano. Maglagay o pumili ng tagubilin sa anumang wika upang makabuo ng English prompt. Pinapanatili ang tahasang hinihingi, gustong wika ng sagot at takdang tekstong nasa panipi.

May manwal na workspace at selection assistant ang macOS app; mag-right-click sa napiling teksto sa katugmang app para makita ang resulta. May browser workspace din. Kailangan ng naka-configure na model API key para sa aktuwal na generation. Preview lang ang Mock, walang pagsasalin o pagpapahusay. Traditional Chinese ang interface; dokumentasyon lang ang saling ito.

**Hakbang:** Ilagay/piliin → bumuo → suriin/kopyahin.

</details>
