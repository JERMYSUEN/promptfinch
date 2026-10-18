# Changelog

Notable changes to PromptFinch are documented here. Entries describe the code at the named tag or commit; a GitHub release asset is not rebuilt when `main` changes.

## [Unreleased]

No changes recorded yet.

## [1.2.0] - 2026-10-19

### Added

- A Windows x64 and Linux x64 Electron desktop edition using the existing optimizer in the main process, without an HTTP listener or a separate Node installation in packaged apps.
- An experimental companion menu that observes a right-click and offers conversion only after an explicit button click. Windows reads the focused UI Automation text selection; Linux X11 reads the selection buffer. Linux Wayland provides manual/clipboard use without a global right-click hook.
- Four interface languages, model-file selection, explicit mock mode, clipboard import, result copy, comparison, cancellation and memory clearing in the new desktop workspace. Results are copy-only on Windows/Linux.
- Native per-platform build jobs, packaged workspace smoke checks and public-artifact checksums. See the [desktop guide](docs/desktop.md) for installation, security boundaries and remaining physical-host verification.

### Preserved

- The macOS Swift edition and its existing selection workflow. Previous release tags/assets retain their original verification scope.
- The model policy, browser workspace and HTTP API. No new live-model quality evaluation is claimed by this platform release.

## [1.1.0] - 2026-10-17

### Added

- Copy-only delivery for recognized terminal selections, including Apple Terminal. A user confirmed that the companion menu and English result worked in Terminal; separate Claude Code and Codex CLI versions and the remaining manual checks are not yet verified. See the [terminal guide](docs/terminal.md).
- An explicit **Use this app’s bundled backend** action in native Settings. Replacing the app retains a separately updated backend; this action adopts the installed app's bundled backend, retains private settings and attempts rollback if startup fails.
- A clean public packaging command, `npm run package:mac`, with an Apple Silicon app ZIP, a source ZIP, SHA-256 checksums and a manifest of relative public-input hashes. It does not read the user's real `.env` or personal signing configuration and does not publish a release.
- A synthetic Codex workflow GIF. Its interface and result are authored examples, not a real model run or an unedited recording of Codex.
- Cross-language parity fixtures covering 29 locales / 28 languages, language-edge cases, a runner that fails on missing required literals, and targeted case selection.

### Fixed

- Reject native backend responses without the expected process instance ID. Stop only the owned child with bounded asynchronous termination; serialize stop/start and delay app exit without blocking the main thread.
- Validate and stage a complete new app before closing the installed app. Replace the bundle transactionally, with rollback instead of merging a partial build into an existing installation.
- Treat conflicting source requirements as reference data rather than overriding conflict-resolution instructions in Traditional Chinese output. Provider retries share one total timeout budget.
- Keep AppKit mouse coordinates for result panels without AX bounds.
- Generate and validate release checksums and archive manifests, with public-package checks in CI.

### Changed

- Improvement and assumption notes support `zh-TW`, `en`, `ja`, and `ko`. Native requests use the interface language; the browser has a separate selector. Prompt instruction language and downstream answer language remain independent.
- Native and browser result comparison retain the source snapshot used for generation and highlight changed lines without changing copied prompt text.

- English-mode task metadata and editing rules now address language inference, supplied facts, conditional requirements and task-specific execution guidance. The intent is to improve the task instructions beyond translation without adding requirements.
- Multilingual and task-optimization reports now distinguish program checks, literal checks and semantic review. Historical task-guidance requests failed with HTTP 502/504. Later synthetic samples produced usable results with partial observed improvements and known remaining semantic errors; neither the old scores nor the new literal checks certify this backend’s general output quality. See the [improvement record](docs/improvement-verification.md). See [task-optimization verification](docs/optimization-value-verification.md).
- Documentation corrections clarify installation, language support, release availability and verification limits. The existing `v1.0.0` tag and download are unchanged.
- Package, release and native bundle version are aligned at `1.1.0`, native build `12`. Public app packaging uses ad-hoc signing, not Developer ID signing or notarization. Node.js 22+ is installed separately.

### Verification scope

Release checks are recorded in the [v1.1.0 notes](docs/releases/v1.1.0.md). The release targets macOS 13+, but physical Intel/minimum-macOS validation and a successful live comparison of the newest editing policy remain outstanding. The synthetic GIF is illustrative.

## [1.0.0] - 2026-10-10

First public release, corresponding to [tag v1.0.0](https://github.com/JERMYSUEN/promptfinch/tree/v1.0.0).

### Added

- An optional browser workspace and native macOS manual workspace using the same Node.js backend. Six task types: general, writing, analysis, coding, summary and marketing.
- Browser UI in Traditional Chinese, with Traditional Chinese or English prompt instructions. The native UI supports Traditional Chinese, English, Japanese and Korean; native prompt instructions use English. The requested downstream answer language is a separate requirement.
- Native selection actions: a selection button, an independent companion action menu beside the host's right-click menu, Services where supported, the global shortcut **⌥⌘P**, and explicit clipboard input. A right-click alone does not generate or send content to a model.
- Nearby result review, copying, and optional paste-back to a verified editable selection. Accessibility support varies by application. Paste-back requests do not submit a chat message, and a sent paste shortcut is not proof that the host accepted it.
- Server-side OpenAI-compatible Chat Completions integration and an explicitly labeled offline mock mode. Live generation requires the user's own provider credentials and model configuration; no model or API key is bundled.
- Structured API responses separating `prompt`, `improvements` and `assumptions`. The copied prompt's layout follows the task; there is no mandatory Objective/Context/Steps template.
- Versioned backend files with deterministic content IDs and a local backend updater. This is not an automatic network updater or an in-app release downloader.
- English README plus 28 localized editions (29 locales / 28 languages), architecture notes and dated verification reports.
- GitHub Actions for JavaScript syntax checks, Node tests, native checks and a macOS build. The workflow does not run browser UI tests, notarize the app or publish release assets.

### Security

- The backend reads credentials from server environment variables (optionally loaded from a local `.env`); it does not return API keys to the browser. Normal input and results are not persisted by the workspace.
- Host validation and API Origin checks, bounded input/response handling, cancellation and limited concurrency. These checks do not provide authentication for a public deployment.
- Native builds exclude private model configuration and signing keys. Personal local signing supports update continuity; it is not Developer ID signing or notarization.

### Release and verification notes

- The published `PromptFinch-1.0.0-macos-arm64.zip` is an Apple Silicon snapshot, requires macOS 13+ and a separately installed Node.js 22+ runtime, and predates the v1.1.0 changes above. Use the newer release or current trusted source for those changes.
- The tag/package release is named `1.0.0`; the tagged native bundle's internal version is `0.1.0`, build `11`. The original tag and artifact have not been rewritten to hide this mismatch.
- Historical pre-release records report 55 Node tests and 190 native checks; these are dated evidence, not a claim that those counts cover current `main` or every host/model. See the [reliability record](docs/reliability-verification.md) and [release notes](docs/releases/v1.0.0.md).
- Source installation requires `npm run build:mac` **before** `npm run install:mac`. Follow the [current macOS guide](docs/macos.md) for prerequisites, permissions and configuration.

[Unreleased]: https://github.com/JERMYSUEN/promptfinch/compare/v1.1.0...main
[1.1.0]: https://github.com/JERMYSUEN/promptfinch/releases/tag/v1.1.0
[1.0.0]: https://github.com/JERMYSUEN/promptfinch/releases/tag/v1.0.0
