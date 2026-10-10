# Changelog

All notable changes to PromptFinch are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-10-10

First public release.

### Added

- **Web workspace** (`server.js` + `public/`): multilingual prompt editor and optimizer.
  - Interface and output languages: 繁體中文、简体中文、English.
  - Six task types: general, coding, reasoning, creative, rewrite, API docs.
  - Structured output standard: objective, context, requirements, steps, output format, and explicit `[PLACEHOLDER]` markers for missing information.
  - Optimizer modes: `live` (LLM-backed) and `mock` (offline demonstration), selected via `.env`.
- **macOS selection assistant** (native Swift/AppKit, macOS 13+):
  - Floating action bar appears over selected text in most applications.
  - Capture controls: `⇧Space` manual capture, auto-capture on selection up/down, `⇧D` capture from keyboard, right-click capture.
  - One-click conversion to an English prompt runs in the background; the result window offers paste-back into the original application and clipboard restore when paste-back is not possible.
  - Settings window with watcher controls and interface language switching.
- **Backend contract**: versioned backend files with a deterministic content ID (`scripts/backend-release.js`), used by build, install, and in-app update tooling.
- **Documentation**: READMEs in 29 languages with top-level navigation, plus architecture and verification guides under `docs/`.
- **Testing & CI**: 55 Node test cases (`npm test`), 190 Swift checks (`npm run test:mac`), syntax checks (`npm run check`), and GitHub Actions workflows that lint, test, build the macOS app, and publish release artifacts.

### Security

- Optimizer credentials are read exclusively from a local `.env` file; the API key is never sent to the browser.
- Explicit origin checks for `127.0.0.1:3210`, hardened selection-payload and API validation.
- Reference `.env.example` for all supported configuration; no secrets are committed.

## [Unreleased]

- New versions of PromptFinch will be documented here. The changelog is only started as of v1.0.0; earlier development history is available in the commit log.
