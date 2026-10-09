# PromptFinch

**Select. Refine. Paste.**

A general-purpose prompt editor and optimizer for writing, coding, research, summarization, and planning. Turn a rough request into clearer instructions for the model you plan to use.

The macOS app combines a manual workspace with a selection assistant: select text in a compatible app, right-click, choose **Convert to an English Prompt** in the companion action menu, and review the result in a nearby panel. Right-clicking alone does not generate or send content to a model. An optional browser workspace and HTTP API use the same backend.

The macOS app and the API's English mode produce English prompts from multilingual input. They are designed to retain explicit requirements, the requested answer language, and exact literals. This edits the instructions; it does not perform the original task. Review generated prompts before using them.

## Languages

English is the shared technical reference. The localized introductions below cover 29 language/script editions, including English and both Chinese scripts. These are documentation translations; the current app interface is Traditional Chinese. Documentation coverage does not mean every input language or host app has been tested. Translation improvements are welcome.

[English](#english) · [繁體中文](#lang-zh-hant) · [简体中文](#lang-zh-hans) · [Español](#lang-es) · [Français](#lang-fr) · [Deutsch](#lang-de) · [Português](#lang-pt) · [Italiano](#lang-it) · [Русский](#lang-ru) · [Türkçe](#lang-tr) · [Nederlands](#lang-nl) · [Polski](#lang-pl) · [Українська](#lang-uk) · [日本語](#lang-ja) · [한국어](#lang-ko) · [हिन्दी](#lang-hi) · [বাংলা](#lang-bn) · [Bahasa Indonesia](#lang-id) · [Tiếng Việt](#lang-vi) · [ไทย](#lang-th) · [தமிழ்](#lang-ta) · [తెలుగు](#lang-te) · [मराठी](#lang-mr) · [العربية](#lang-ar) · [اردو](#lang-ur) · [فارسی](#lang-fa) · [Kiswahili](#lang-sw) · [ਪੰਜਾਬੀ](#lang-pa) · [Filipino](#lang-fil)

For English output, use the macOS app, choose **英文 Prompt** in the browser's **Prompt 指令語言** control (the browser default), or set `promptLanguage: "en"` in an API request. The browser also offers Traditional Chinese output. Existing API clients that omit this field still receive `zh-Hant` output. Localized introductions do not change the app interface language.

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

## Localized introductions

The introductions below describe the English-prompt workflow. The shared installation and API reference is [above](#english). The browser offers English/Traditional Chinese instructions, while API requests without `promptLanguage` retain their `zh-Hant` default. The app interface remains Traditional Chinese.

<a id="lang-zh-hant"></a>
<details>
<summary>繁體中文</summary>

### 關於 PromptFinch

PromptFinch 是通用的 Prompt 編輯與優化工具，適用於寫作、程式開發、研究、摘要與規劃。以任意語言輸入或選取需求，即可請已設定的模型產生英文 Prompt；明確的限制、指定答案語言與引號內固定字串應予保留。模型可能出錯，使用前請檢視結果。

macOS App 將手動工作台與選取助手整合在一起：在相容 App 選取文字後按右鍵，直接查看結果浮窗；另有瀏覽器工作台與 API。真實生成需要設定模型 API 金鑰，示範模式僅供預覽流程，不翻譯或實際優化。介面目前為繁體中文；README 的多語介紹不代表介面已完成多語翻譯。

**流程：** 輸入或選取需求 → 產生英文 Prompt → 檢視結果 → 複製或貼回。安裝與設定請參閱[共用英文說明](#english)。

</details>

<a id="lang-zh-hans"></a>
<details>
<summary>简体中文</summary>

### 关于 PromptFinch

PromptFinch 是通用的 Prompt 编辑与优化工具，适用于写作、程序开发、研究、摘要和规划。使用任意语言输入或选择需求，即可请求已配置的模型生成英文 Prompt；明确的限制、指定答案语言和引号内固定字符串应予保留。模型可能出错，使用前请检查结果。

macOS App 将手动工作台与选择助手整合在一起：在兼容 App 中选择文字后点击右键，直接查看结果浮窗；另有浏览器工作台和 API。真实生成需要配置模型 API 密钥，演示模式仅预览流程，不翻译或实际优化。界面目前为繁体中文；README 的多语介绍不代表界面已完成多语翻译。

**流程：** 输入或选择需求 → 生成英文 Prompt → 检查结果 → 复制或贴回。安装与配置请参阅[共用英文说明](#english)。

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
