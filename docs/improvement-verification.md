# Improvement verification — 2026-10-17

This record covers the v1.1.0 preparation after the whole-project review. Historical reports describe their own versions and remain unchanged. The app/package version is 1.1.0, native build 12.

## Reliability and delivery changes

- Native configuration responses must match the exact expected backend instance. Missing, null, empty and different IDs are rejected; an optional standalone client can still omit the ownership expectation.
- Owned-child shutdown yields the main actor, waits for a bounded grace period, then signals only that child if necessary. Stop/start share cleanup work and stale startup callbacks cannot overwrite a newer lifecycle.
- A bundled-backend switch stages and verifies before stopping the old child. Startup failure restores the previous selection; cancelling while health verification is pending restores the prior pointer before a new lifecycle can start. A concurrent external update is preserved.
- Source installation validates the original and staged bundle before closing the installed app. The complete bundle replaces the old bundle without merging, and failed replacement attempts restore the old app. If recovery itself fails, the backup is retained and its location is reported.
- Public release packaging uses a clean source allowlist and ad-hoc signing. Source/App ZIPs, the build-input manifest and SHA256SUMS are verified from the delivered archives. CI includes this verification, rather than merely compiling the checkout.
- Result comparison retains the source captured for the generated result, uses bounded whole-line highlighting, renders content as text, and never changes what Copy returns. Browser comparison survives input edits and failed retries until the result is cleared.
- New notes use a separately validated notesLanguage setting. Native UI language and browser notes selection remain independent of the English instructions and the eventual task-answer language. Provider retries share one total deadline.

## Checks

The following checks completed against the final implementation and delivered archive contents. They use synthetic data and isolated stores, preferences, pasteboards and subprocesses. They do not operate the installed personal app, its permissions or its private configuration.

- JavaScript syntax checks and README synchronization across 28 localized editions.
- Node suite: 80 tests, including 8 installation transaction cases, independent notes-language behavior, conflict assembly, shared retry deadlines, cancellation and runner options.
- Native suite: 318 checks, including exact process ownership, unresponsive child shutdown, caller cancellation, concurrent stop/restart, switching, rollback and cancellation during candidate health checks.
- Browser suite: 11 Chrome tests, including clipboard behavior, 320/390px layouts, error/cancellation paths, no persistence, text-only rendering, notes-language requests and immutable comparison snapshots.
- Public app/source packaging passed: 112 explicitly allowed source files, an arm64 app targeting macOS 13.0, strict ad-hoc signature, matching backend content ID and public build-input hashes, blank credential templates, no private paths or runtime configuration, and extracted-package mock HTTP. SHA256SUMS covers both ZIPs and the manifest; Node.js is not bundled. The full archive check also re-runs syntax, documentation and Node tests from extracted source.

## Actual model samples

[Machine-readable samples and review](improvement-live-results.json) preserve 12 samples before the final policy refinement and 16 afterward. Both stages used the configured deepseek-flash model, synthetic inputs and an isolated local server with a 20-second total request deadline. The source fixtures are [optimization-value.json](../tests/fixtures/optimization-value.json) and [release-quality.json](../tests/fixtures/release-quality.json). Notes-language checks include zh-TW, English, Japanese and Korean; instruction modes include English and Traditional Chinese.

All 16 final requests returned HTTP 200 and all listed required literals were present. These are mechanical results, not 16 semantic passes. Manual review found observable improvements in lowercase email preservation, several incorrect assumption labels, and Japanese notes. It also found remaining errors:

1. Answer-language assumptions remain inconsistent. Some explicit language requests are mislabeled as inferred, while two English-source samples omit the inferred answer-language instruction and assumption.
2. A comparison sample loses the rule to ask questions when supplied criteria are insufficient. A coding sample has an overly absolute inspection-reporting prohibition, and one improvement note overstates its corresponding prompt.
3. One Traditional Chinese conflict sample initially restates the impossible task before directing a brief conflict notice. English-mode conflict samples directly prohibit drafting it.

This comparison is between two policies during v1.1.0 preparation, not a controlled v1.0.0 baseline. No downstream writing, coding or analysis task was executed to measure performance gains. The samples support partial observed improvements and continued human review, not universal semantic correctness or equality across languages. The synthetic Codex GIF remains an illustration rather than model evidence.

## Remaining verification limits

Cross-app interaction has not been physically re-tested on every host/CLI version in this run. Intel and the minimum macOS 13 target have not been tested on physical hardware. The public app is Apple Silicon, ad-hoc signed, not notarized, and requires a separately installed Node.js 22+ runtime. Browser UI translations beyond Traditional Chinese, OCR, a customizable global shortcut and automatic network updates remain outside this release.
