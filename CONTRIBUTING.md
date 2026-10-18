# Contributing

Start with the [documentation index](docs/README.md) and [architecture](docs/design.md). The backend uses Node.js built-ins without third-party runtime packages; the native client uses Swift, AppKit and SwiftUI without Swift package dependencies. Keep changes focused and explain any new dependency.

## Development checks

Use Node.js 22 or later. Native checks/builds also need macOS 13+ and Apple's Xcode Command Line Tools.

```sh
npm ci
npm run check
npm run check:docs
npm test

# Install a test browser once, then run browser checks.
npx playwright install chromium
npm run test:ui

# Or use an installed Google Chrome.
PLAYWRIGHT_CHANNEL=chrome npm run test:ui

# macOS only
npm run test:mac
npm run build:mac

# Source archive with the explicit public-file allowlist.
npm run package:source
```

Run checks appropriate to the change and report what actually ran. The GitHub workflow runs syntax/documentation checks, Node tests, native checks and a native build. Browser flows and physical mouse acceptance are separate; CI does not publish releases or prove live-model quality.

For existing native installations, installing a new app preserves the active external backend. Native-plus-backend changes need `build:mac`, `install:mac`, then `update:mac-backend` from the trusted updated checkout. Backend-only changes use `update:mac-backend`. See the [macOS guide](docs/macos.md) for stable local signing and permissions. Do not commit private signing material.

## Prompt-editing changes

Use [optimization-value cases](tests/fixtures/optimization-value.json) to assess useful execution guidance and restraint on already-clear requests. Also review source intent, facts, Unicode literals, units, numerical bounds, conditional scope, answer language, output format, supplied sources and necessary clarification. Preserve the requested task rather than answering it or adding arbitrary requirements.

Fake-provider tests establish transport and schema behavior, not semantic quality. Live evaluation is explicit, uses the contributor's own model account, can incur charges and deliberately saves its results. Use synthetic inputs only, review outputs separately from literal checks, and preserve failed attempts. A newer prompt policy cannot inherit a prior revision's live-quality score. Never replace a provider failure with an unlabeled mock result or use the demo GIF as model evidence.

## Documentation and translations

English `README.md` is the source. Localized pages use `docs/readme/README.<locale>.md`; keep `zh-CN` and `zh-TW` separate. There are 29 documentation editions, representing 28 languages with separate Chinese scripts. The two Chinese editions contain the full reference; the other 26 translations are introduction-only and must say so.

Preserve commands, API field names, identifiers and example literals when translating. Resolve relative links from each document's own directory. A language link changes the documentation page; it does not switch app language or certify model coverage. For a new locale, update every language banner and the `readmeLocales` allowlist in `scripts/package-source.js`. Obtain language review where possible; structural checks do not certify a translation.

When adding a public guide, link it from `docs/README.md` and add it to `scripts/package-source.js` if it belongs in the source archive. Keep dated test records labeled with their source revision and limitations. Do not rewrite raw synthetic evidence to make a result look successful. Current release-note source is [docs/releases/v1.1.0.md](docs/releases/v1.1.0.md); the [original notes](docs/releases/v1.0.0.md) keep the older snapshot identifiable. Updating release text does not rebuild a download. `npm run package:mac` builds public ad-hoc app/source packages and input-hash evidence from a clean public copy on macOS; it does not read real private configuration, notarize or publish. Run and record appropriate checks against the actual release commit and packaged files before publication.

`npm run check:docs` checks navigation, README structure and changelog ordering. Also check local links, anchors, image paths, commands and factual claims against the relevant implementation. Avoid personal absolute paths and do not publish ignored handoff notes, local artifacts or original private recordings.

## Bug reports and pull requests

Use [GitHub Issues](https://github.com/JERMYSUEN/promptfinch/issues) for ordinary bugs. Include:

- Source commit or release tag; macOS/Node version and architecture where relevant.
- Browser or source app/terminal and version; for CLI workflows, the CLI version separately.
- Entry point, relevant settings and whether Accessibility permission is enabled.
- A small synthetic request, reproduction steps, expected result and actual behavior.
- For quality reports, the generated prompt and notes from that synthetic case, plus the configuration's non-secret model identifier and prompt language.
- The checks you ran, and any provider error status, without raw provider bodies or credentials.

Do not attach `.env`, API keys, real user prompts, clipboard contents, native preferences, signing keys or an unreviewed diagnostic log. Native diagnostics omit prompt text but contain application/process and timing metadata. Sensitive vulnerabilities follow [SECURITY.md](SECURITY.md), not a public exploit report.

Pull requests should describe the resulting behavior and relevant verification. Keep generated media clearly labeled as synthetic or recorded. PromptFinch uses the [MIT License](LICENSE); retain required third-party notices and use compatible contributions.

## Windows and Linux desktop development

The Electron workspace shares `lib/optimizer.js` with the API. Run `npm ci`, `node scripts/build-desktop-helpers.cjs`, then `npm run desktop`. Native selection helpers and distributable packages must be built on the matching x64 Windows/Linux host. `npm run test:desktop` launches an isolated mock workspace with synthetic text and an in-memory clipboard. See [desktop development and support limits](docs/desktop.md) before changing platform behavior. Do not weaken the sandbox or simulate automatic paste into terminals.
