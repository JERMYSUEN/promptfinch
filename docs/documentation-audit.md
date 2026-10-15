# Documentation audit

Date: 2026-10-15. Reviewed the 41 existing public Markdown documents at starting revision `c92c63f`, the `v1.0.0` tag, the published release text/asset listing, workflow configuration and the relevant application source. Five new guides/records bring the public Markdown set to 46. The review browser could not fetch the main page; authenticated GitHub API reads confirmed the repository, branch, release, tag and workflow state. Local source matched the remote starting revision.

## Gaps corrected

- Replaced inaccurate changelog/release descriptions of web UI languages, task types, shortcuts, mandatory prompt outlines, universal app support and automatic release publishing with the tagged implementation's behavior.
- Distinguished the old v1.0.0 Apple Silicon ZIP from newer `main`, separate Node runtime requirements, and the native version-label mismatch. The tag and downloaded asset were not replaced or rebuilt.
- Documented a key update dependency: reinstalling the app preserves an existing external backend. Native and backend changes require build, install and then a backend update; backend-only changes have their own command.
- Added a [documentation index](README.md), [complete API reference](api.md) and [troubleshooting guide](troubleshooting.md), covering readiness versus provider health, error bodies/statuses, per-attempt timeouts, configuration scope and selection/paste behavior.
- Synchronized the English and two full Chinese references, and updated the other 26 introductions to explain task optimization beyond translation, restrained edits and deliberate generation.
- Expanded the English [security](../SECURITY.md) and [contributor](../CONTRIBUTING.md) guides: saved preferences, metadata logs, clipboard behavior, local API limitations, actual vulnerability-reporting status, synthetic bug reports and documentation maintenance.
- Separated current architecture/setup instructions from dated reference analysis and test evidence. Historical raw JSON, test counts and failed live requests were preserved rather than promoted into current verification.
- Added `npm run check:docs` to CI and corrected an inverted changelog-order check that previously accepted Unreleased after the release while rejecting the standard order.

## Verification

- `npm run check`: passed.
- `npm run check:docs`: passed for the English navigation source and 28 localized editions. This checks structure, not native-speaker accuracy.
- `npm test`: all 64 Node tests passed.
- Public-document link checks: 46 Markdown files, 1,067 local link/image targets and 45 Markdown anchors; no missing targets after fixing a security-reporting anchor.
- API example checks: all three documented JSON examples matched a fresh isolated mock server, including the blank-input error. No provider call was made.
- Changelog validator check: an isolated copy accepted Unreleased before the release and rejected the same section moved after it; the real changelog was not modified by the negative check.
- `npm run package:source`: created a 100-file allowlisted archive. Its extracted source passed README checks, all 64 Node tests, and `npm start` plus configuration/optimization requests in isolated mock mode. No private environment file, local artifact or handoff note was included.
- `git diff --check` and public-document personal-path/key-pattern scans: passed.

No new native install, physical mouse acceptance, browser UI suite or live model-quality evaluation is part of this documentation pass. External links were not exhaustively checked; local link checks do not establish continued availability of every provider or third-party documentation site.

## Remaining limits

The native version metadata is still `0.1.0`, build `11`; release/package naming remains `1.0.0`. This audit documents that mismatch without retagging or silently replacing an old download. The release is not a notarized or Universal distribution. Intel/minimum-macOS hardware, all host/CLI combinations, mobile hardware, Docker and remote deployment remain outside the recorded verification scope.

The new optimization policy still has no successful live before/after comparison; previous attempts failed with 502/504. Documentation wording and the synthetic GIF do not resolve that evidence gap. Older multilingual scores belong to their own revisions. Translated introductions received a consistency pass, not independent native-speaker certification across every language.

Private vulnerability reporting was disabled when checked; no private reporting address was invented or security setting changed. Ignored handoff notes, local configuration, raw private recordings and unrelated untracked files were neither published nor included in the source archive.
