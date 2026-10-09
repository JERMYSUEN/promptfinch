**English** · [简体中文（zh-CN）](docs/readme/README.zh-CN.md) · [繁體中文（zh-TW）](docs/readme/README.zh-TW.md) · [Español](docs/readme/README.es.md) · [Français](docs/readme/README.fr.md) · [Deutsch](docs/readme/README.de.md) · [Português](docs/readme/README.pt.md) · [Italiano](docs/readme/README.it.md) · [Русский](docs/readme/README.ru.md) · [Türkçe](docs/readme/README.tr.md) · [Nederlands](docs/readme/README.nl.md) · [Polski](docs/readme/README.pl.md) · [Українська](docs/readme/README.uk.md) · [日本語](docs/readme/README.ja.md) · [한국어](docs/readme/README.ko.md) · [हिन्दी](docs/readme/README.hi.md) · [বাংলা](docs/readme/README.bn.md) · [Bahasa Indonesia](docs/readme/README.id.md) · [Tiếng Việt](docs/readme/README.vi.md) · [ไทย](docs/readme/README.th.md) · [தமிழ்](docs/readme/README.ta.md) · [తెలుగు](docs/readme/README.te.md) · [मराठी](docs/readme/README.mr.md) · [العربية](docs/readme/README.ar.md) · [اردو](docs/readme/README.ur.md) · [فارسی](docs/readme/README.fa.md) · [Kiswahili](docs/readme/README.sw.md) · [ਪੰਜਾਬੀ](docs/readme/README.pa.md) · [Filipino](docs/readme/README.fil.md)

# PromptFinch

**Select. Refine. Paste.**

A prompt editor for writing, coding, research, summarization, and planning. Turn a rough request in your preferred language into clearer English instructions, then review and paste them into the model you plan to use.

Use the **macOS app** as a manual workspace or a selection assistant: select text in a compatible app, right-click, choose **Convert to English prompt** in the companion action menu, and review the result nearby. Right-clicking alone does not send text to a model. An optional **browser workspace and HTTP API** use the same backend.

PromptFinch edits instructions; it does not carry out the task described in them. It is designed to retain your requirements, requested answer language and exact strings. Real optimization requires your own model API configuration. Without a key, a clearly labeled mock mode lets you try the workflow without translating or optimizing the text.

## Documentation languages

The links at the top switch between README pages. English is the source; Simplified Chinese (zh-CN) and Traditional Chinese (zh-TW) include the full reference. The other 26 editions contain translated introductions and link to the English setup instructions. These links change the documentation, not the app's language.

In the macOS app, **Settings → Interface language** offers Traditional Chinese (default), English, Japanese and Korean. The browser interface remains Traditional Chinese. Improvement and assumption notes are requested in Traditional Chinese and are not translated by the interface.

The macOS app generates English prompt instructions. The browser defaults to English instructions and also offers Traditional Chinese. API clients use `promptLanguage: "en"` for English; omitting it retains the `zh-Hant` default. The language of the eventual answer is a separate requirement in your original prompt. Unicode input is accepted, but documentation translations do not certify model quality in every language.

<a id="english"></a>

## English technical reference

[Quick start](#quick-start) · [Model configuration](#model-configuration) · [HTTP API](#http-api) · [macOS workflow](#macos-workflow) · [Privacy](#privacy-and-data-handling) · [Validation and limitations](#validation-and-limitations) · [Development](#development)

### What it does

- Accept a rough prompt, choose a task type, and optionally name the model that will receive the result.
- Produce a copyable prompt with improvements and assumptions shown separately. Copy and paste-back use the prompt field alone.
- Use one macOS app for manual input, selection actions, result panels, model settings, four interface languages, and optional paste-back.
- Handle blank input, size limits, loading, cancellation, and understandable errors.
- Run without a model key in clearly labeled mock mode, or call a configured OpenAI-compatible model from the Node.js backend.

The task choices are general, writing, analysis, coding, summary, and marketing. Research and planning requests fit the analysis or general workflow. The optional **target model** is a prompt-editing hint, not a switch for the backend generation model; the latter is configured with `LLM_MODEL`.

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

Get the source, then choose either the browser demo or the macOS app:

```sh
git clone https://github.com/JERMYSUEN/promptfinch.git
cd promptfinch
```

The macOS app is built from source; this repository does not currently provide a ready-made, notarized installer.

#### Browser demo, no API key

```sh
# Create a local configuration only if one does not already exist.
cp -n .env.example .env
npm start
```

Open [http://127.0.0.1:3000](http://127.0.0.1:3000). If `.env` already exists, review it and set `OPTIMIZER_MODE=mock` for a local demonstration instead of overwriting it. Running the service does not require `npm install`.

**Mock output is not translated and not semantically optimized.** It is a labeled template for checking input, loading, result display, and copy flows. It does not call a model or send prompt content to a provider.

The browser's prompt-language selector controls the instructions' language. An explicit answer language in your original request is retained.

#### Build and install the macOS app

```sh
xcode-select --install  # Skip if Command Line Tools are already installed.
npm run setup:signing:mac
npm run build:mac
npm run install:mac
```

The build produces `build/PromptFinch.app`. The installer places it in the user's `~/Applications` directory and opens it. No separate browser server is needed: the app starts its own backend at `http://127.0.0.1:3210`.

The installer also handles migration from the earlier app name; see the [rename notes](docs/branding.md).

`setup:signing:mac` is a per-machine setup for a stable local signing identity. It stores the private signing key in the login Keychain; macOS may ask you to confirm access. This helps maintain the Accessibility identity across local rebuilds. It is not Developer ID signing or notarization, and signing keys must not be published. If an existing signing configuration is invalid, the build stops instead of silently replacing that identity.

Without a selected model configuration, the app uses mock mode. In Settings, create or select a model configuration file, fill in your provider settings, and reload the configuration. You can also select the interface language there. If the app cannot locate Node, select its executable in Settings.

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
| `ALLOWED_HOSTS` | Empty | Optional comma-separated exact host authorities for a reverse proxy, e.g. `prompts.example.com,prompts.example.com:8443`. No wildcards or URLs. |

The Mac app overrides `HOST` and `PORT` to `127.0.0.1:3210` and clears `ALLOWED_HOSTS`, regardless of their values in the selected configuration. The standalone browser server and native backend can run on their separate ports. The standalone server trusts loopback names and its non-wildcard bind hostname on the actual listening port by default. Binding to `0.0.0.0` or `::` does not trust arbitrary Host headers; remote domains and proxy ports must be listed explicitly. Forwarded host headers are not trusted.

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
- Korean Hangul, Russian Cyrillic, RTL scripts, combining marks, joiners, emoji, and mixed text are accepted without normalization or alphabet-based filtering. The browser input uses automatic text direction. Documentation language coverage is separate from the four macOS interface languages.
- English mode separates instruction language from the downstream answer language. The model must preserve explicit answer-language requirements, negation scope, exact literals, variables, code and URLs. A narrow backend repair restores an unambiguous quoted/code literal altered only by canonical NFC normalization. It cannot reconstruct omitted or translated literals or resolve ambiguous equivalent spellings; review important strings.
- The [multilingual verification record](docs/multilingual-verification.md) documents transport checks and 24 synthetic live-model cases across 18 languages using `deepseek-flash`, including short, medium and long Korean/Russian cases. It also records an imprecise Japanese improvement note and untested languages and hosts. These samples do not guarantee translation quality for new inputs or other models.

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
3. For selection actions, enable Accessibility in System Settings when prompted. In a compatible input field, select text and right-click, then choose **Convert to English prompt** in the companion menu (the label follows your app language); the result appears nearby. The host's original context menu remains available. Cancel, a click elsewhere, keyboard input, switching apps or the 12-second timeout dismisses the offered action without generating. The assistant checks the selection again after an explicit choice. You can also use the optional selection button. Some Electron apps may show an activation notice: wait about two seconds, make a new selection, and try again.
4. Other entry points include the default Option-Command-P shortcut, macOS Services where supported, and an explicit clipboard action. Host applications must expose usable text selection; this is not universal compatibility.
5. Optional automatic paste-back requires a trustworthy nonempty selection range and rechecks the source app, focused field and selected text before requesting a paste. If the position cannot be verified, the result is copied for manual use. Text-only selection access still permits conversion, with manual pasting. The status reports that a paste was requested; inspect the source because applications can ignore simulated key events. Clipboard restoration is reported only after its callback completes. An incomplete clipboard backup, failed temporary write or failed immediate recovery stops paste-back without automatic fallback copying; the result stays available for a deliberate copy. The panel also offers copy and manual paste-back. Paste-back does not submit the chat message and can be disabled in Settings. Mock results are not pasted back.

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

[The latest local verification](docs/reliability-verification.md), on 2026-10-09, passed JavaScript syntax checks, 55 Node tests, 190 native checks, 10 Chrome flow tests and the macOS build/signature checks. These tests use mock or controlled providers; they do not establish real-model output quality.

The user previously confirmed that the companion menu appeared without automatic generation and that one explicit click produced an English result. Physical mouse and complete copy/paste-back/cancellation behavior in Codex/Claude still need verification for this build. See the [selection verification](docs/context-menu-verification.md) and [multilingual sample review](docs/multilingual-verification.md) for their separate scopes.

Current limits include host-app selection support, no OCR, no customizable global shortcut, no bundled Node, no automatic updates, and no ready-made notarized or Universal Binary release. Intel/minimum-macOS hardware, physical mobile devices, Docker and remote deployment remain unverified. Known follow-up work includes conflicting requirements in Traditional Chinese output and the total timeout budget for retries.

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

`npm run dev` runs the standalone server with Node's watch mode. API tests use local fake model services; native tests use synthetic targets and named test clipboards. The [GitHub workflow](.github/workflows/check.yml) runs Node checks and native macOS checks/builds. Browser tests currently run locally; check [GitHub Actions](https://github.com/JERMYSUEN/promptfinch/actions) for the result on a particular commit.

### Contributing and license

See [CONTRIBUTING.md](CONTRIBUTING.md) for development conventions. Translation corrections and reproducible reports using synthetic, shareable inputs are welcome. Keep API keys, local environment files, private prompts, clipboard contents, and personal signing material out of contributions.

PromptFinch is licensed under the [MIT License](LICENSE). Provider access and any model charges belong to each user's own account.
