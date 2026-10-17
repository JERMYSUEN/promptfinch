# Documentation index

Start with the [English README](../README.md), or the complete [Simplified Chinese](readme/README.zh-CN.md) / [Traditional Chinese](readme/README.zh-TW.md) reference. The other 26 localized README editions translate the introduction and link to the English technical reference. Documentation languages are separate from the four native interface languages and from model language-quality coverage.

The guides describe current `main`. The [v1.1.0 release notes](releases/v1.1.0.md) describe the new downloadable snapshot and its upgrade steps. The original [v1.0.0 release](releases/v1.0.0.md) and dated verification records retain their own scope; changing documentation does not rebuild an older download or rerun those tests.

## Using PromptFinch

| Goal | Guide | Language |
| --- | --- | --- |
| Choose browser/API or macOS, install and configure a model | [Quick start and settings](../README.md#quick-start) | English; full Chinese editions above |
| Set up the native app, permissions, signing and updates | [macOS guide](macos.md) | Traditional Chinese |
| Use selected text in Apple Terminal with Claude Code/Codex CLI | [Terminal workflow](terminal.md) | English |
| Diagnose configuration, model, selection and copy errors | [Troubleshooting](troubleshooting.md) | English |
| Integrate the local service | [HTTP API reference](api.md) | English |
| Understand data handling and report a security issue | [Security policy](../SECURITY.md) | English |
| Download, upgrade or identify a release snapshot | [v1.1.0 notes](releases/v1.1.0.md), [changelog](../CHANGELOG.md), [original release](releases/v1.0.0.md) | English |

PromptFinch uses your configured model API; it does not bundle a model or reuse a Codex/Claude login. Mock checks the local workflow without translating or optimizing. Selection support depends on the source app; recognized terminals receive copy-only results. Read the workflow's limits before relying on paste-back.

## Development and evidence

| Document | Scope |
| --- | --- |
| [Contributing](../CONTRIBUTING.md) | Commands, documentation changes, synthetic examples and bug reports |
| [Architecture and original design](design.md) | Current module boundaries, followed by the dated reference-site analysis |
| [Branding and migration](branding.md) | Current name, stable bundle identity and older app-name migration |
| [Reliability record](reliability-verification.md) | 2026-10-09 checks and known follow-up debt; not current test counts |
| [Companion-menu record](context-menu-verification.md) | 2026-10-09 interaction checks and limits of physical mouse evidence |
| [Initial multilingual record](multilingual-verification.md) | Transport and limited live samples; [raw synthetic results](multilingual-live-results.json) |
| [Paired multilingual record](multilingual-parity-verification.md) | Shared requirements across locales, version-specific review and remaining errors; [raw results](multilingual-parity-results.json) |
| [Task-optimization record](optimization-value-verification.md) | Intended value beyond translation, eight-case rubric and unsuccessful live attempts; [failure records](optimization-value-results.json) |
| [Documentation audit](documentation-audit.md) | Gaps corrected and checks performed in the 2026-10-15 documentation pass |

The [Codex demo GIF](media/demo-selection.gif) is a synthetic, hand-authored illustration. It is not a real screen recording or successful model-quality evaluation. A passing build, a valid JSON response, a preserved literal and a semantically faithful optimization are different kinds of evidence.

Internal handoff notes, local artifacts, private configurations and original recordings are not public documentation or release inputs. Do not copy them into an issue or source archive.

The [2026-10-17 improvement verification](improvement-verification.md) records current reliability checks, archive verification and synthetic live-model findings, including remaining semantic errors.
