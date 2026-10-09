**English** · [简体中文（zh-CN）](docs/readme/README.zh-CN.md) · [繁體中文（zh-TW）](docs/readme/README.zh-TW.md) · [Español](docs/readme/README.es.md) · [Français](docs/readme/README.fr.md) · [Deutsch](docs/readme/README.de.md) · [Português](docs/readme/README.pt.md) · [Italiano](docs/readme/README.it.md) · [Русский](docs/readme/README.ru.md) · [Türkçe](docs/readme/README.tr.md) · [Nederlands](docs/readme/README.nl.md) · [Polski](docs/readme/README.pl.md) · [Українська](docs/readme/README.uk.md) · [日本語](docs/readme/README.ja.md) · [한국어](docs/readme/README.ko.md) · [हिन्दी](docs/readme/README.hi.md) · [বাংলা](docs/readme/README.bn.md) · [Bahasa Indonesia](docs/readme/README.id.md) · [Tiếng Việt](docs/readme/README.vi.md) · [ไทย](docs/readme/README.th.md) · [தமிழ்](docs/readme/README.ta.md) · [తెలుగు](docs/readme/README.te.md) · [मराठी](docs/readme/README.mr.md) · [العربية](docs/readme/README.ar.md) · [اردو](docs/readme/README.ur.md) · [فارسی](docs/readme/README.fa.md) · [Kiswahili](docs/readme/README.sw.md) · [ਪੰਜਾਬੀ](docs/readme/README.pa.md) · [Filipino](docs/readme/README.fil.md)

# PromptFinch

**Select. Refine. Paste.**

A general-purpose prompt editor and optimizer for writing, coding, research, summarization, and planning. Turn a rough request into clearer instructions for the model you plan to use.

The macOS app combines a manual workspace with a selection assistant: select text in a compatible app, right-click, choose **Convert to an English Prompt** in the companion action menu, and review the result in a nearby panel. Right-clicking alone does not generate or send content to a model. An optional browser workspace and HTTP API use the same backend.

The macOS app and the API's English mode produce English prompts from multilingual input. They are designed to retain explicit requirements, the requested answer language, and exact literals. This edits the instructions; it does not perform the original task. Review generated prompts before using them.

## Documentation languages

Use the language links at the very top of each README to open the corresponding language page. English is the source reference. Simplified Chinese (zh-CN) and Traditional Chinese (zh-TW) include the full technical reference; the other 26 language editions currently provide translated introductions with a link to the English technical reference. These are documentation translations; the current app interface is Traditional Chinese. Documentation coverage does not mean every input language or host app has been tested. Translation improvements are welcome.

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

The interface and improvement/assumption notes are currently primarily Traditional Chinese. The documentation provides 29 language/script editions across 28 languages; it does not add translated app interfaces or certify all input languages.

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
