# Security and data handling

PromptFinch is a personal local tool. Each user configures their own model provider and pays that account's charges. The project supplies no shared key, hosted model, account system or multi-user isolation. Security-sensitive changes should identify the source commit or release tag; old downloads are not automatically updated when `main` changes.

## Reporting a vulnerability

As checked on 2026-10-15, this repository's GitHub private vulnerability reporting is disabled, and no dedicated security email is published. Do not post credentials, private data or a working exploit in a public issue. Ask the maintainer for a private reporting channel through a non-sensitive [contact request](https://github.com/JERMYSUEN/promptfinch/issues), then share details through the channel they provide. If GitHub private reporting is later enabled, its **Security → Report a vulnerability** entry provides that route. Ordinary non-sensitive bugs follow [Contributing](CONTRIBUTING.md).

## Credentials and local storage

- Only the Node.js backend reads model credentials from its environment, optionally loaded from a private `.env`. The frontend and API configuration response do not expose the key. The native app retains a configuration-file path rather than copying the key into its bundle.
- Model keys remain in a plain-text file, not Keychain. Restrict a private file's permissions, for example `chmod 600 .env`, and keep it out of Git, screenshots and support reports. The app creates its own settings file with owner-only permissions. This is separate from the personal code-signing key, which lives in the login Keychain.
- Normal prompt input, result and explanation text stay in process memory; there is no database or prompt-history feature. Native UserDefaults persist interface/selection preferences, task type, target-model hint, Node path and configuration path. Do not put private prompt content into a model-name hint.
- Native status diagnostics append to `~/Library/Application Support/PromptSelection/debug.log`. They record events, application/process identifiers, roles, lengths and window geometry, not prompt/result text, key contents or typed characters. There is no automatic log rotation. Review metadata before sharing excerpts; logs are not anonymous just because prompt text is absent.
- Explicit live-evaluation scripts intentionally save synthetic cases and results. These files are different from normal workspace behavior. Do not substitute private inputs and then commit the output.

The browser uses no application cookies, browser storage, analytics or remote fonts. Clearing/reloading a workspace does not erase clipboard-manager history, provider-side data, local preferences or a file the user deliberately saved.

## Release packages and backend selection

The v1.1.0 public app ZIP is Apple Silicon only, ad-hoc signed and not Developer ID signed or notarized. It targets macOS 13+ without a completed physical minimum-OS or Intel validation. Node.js 22+ is required separately. Download checksums and a verification manifest help compare files and public source inputs; they do not establish publisher identity, notarization or semantic model quality.

`npm run package:mac` builds from a clean copy of an explicit public-input list, without reading the real `.env`, local app preferences or personal signing configuration. Its manifest records relative input paths and SHA-256 hashes. Packaging is not publication, and private files are not release inputs. Keep the original release snapshots identifiable rather than silently replacing historical tags or assets.

The app runs versioned backend files in the user's Application Support folder. Replacing the app preserves an already selected external backend. **Settings → Use this app’s bundled backend** explicitly stages, validates and adopts the installed app's bundled source; a startup failure attempts rollback. Model settings, Node selection and user preferences are retained. The operation makes no network download or model request. A source checkout can also update the backend with `npm run update:mac-backend`; only use source you trust. External backend files are not continuously protected by the app's code signature.

## Network boundary

The native app binds its owned backend to `127.0.0.1:3210` and clears `ALLOWED_HOSTS`. The standalone server defaults to `127.0.0.1:3000`. Local processes can call a reachable local API without authenticating, so Host/Origin protections do not isolate users or processes.

Each request must have one valid, allowed Host. By default, loopback names and the non-wildcard configured bind hostname must use the actual listening port. Binding to `0.0.0.0` or `::` does not trust arbitrary hosts. API Origin, when present, must match the allowed Host and port; cross-site browser requests are rejected. Native callers may omit Origin. The server does not trust forwarded host headers.

A standalone reverse proxy can use an explicit `ALLOWED_HOSTS` list such as `prompts.example.com,proxy.example.com:8443`. Entries are hostnames/IP authorities, not URLs or wildcards; IPv6 uses brackets. Omitted ports allow no port or standard 80/443, while nonstandard ports must match. This list is not an access-control system. A public deployment needs separately implemented HTTPS, authentication and isolation; Docker and remote deployment have not been validated. Do not assume that a working local service is safe to expose publicly.

Live mode sends the selected/manual request and editing context, including the optional target-model hint, to the configured provider. Provider retention and billing policies apply. PromptFinch does not reuse Codex/Claude account credentials or silently switch to another paid provider. Mock mode makes no model call and explicitly states that it does not translate or semantically optimize.

The server bounds requests and provider responses, validates input/output structure, limits active optimization calls, and returns safe errors without raw provider bodies. It does not establish semantic correctness of a generated prompt. Client cancellation propagates an abort but cannot guarantee that a provider stops processing or charging. See the [API reference](docs/api.md).

## Selection and clipboard access

With Accessibility permission and selection features enabled, the native app uses a listen-only event monitor to inspect currently accessible selected text. Keyboard events invalidate pending actions; typed character content is not read or logged. There is no background clipboard monitor, OCR or forced-copy operation.

If a safe editable field exposes a nonempty selected range but no selected-text attribute, capture may temporarily read the field value and extract that range. Values above 65,536 UTF-16 code units are rejected; full field contents are not logged. A right-click alone only offers the companion action. Text is sent to a model after an explicit conversion choice or another deliberate generation entry point.

For a new preference profile, the selection button, right-click menu and automatic paste-back are enabled. Turn off automatic paste-back to review before replacing editable source text. Paste-back requires a valid range and rechecks the foreground app, field and selection. Known read-only fields and recognized terminals do not receive generated paste-back; unknown/custom terminal controls need separate identification checks. The tool may dismiss a host context menu after an explicit choice, but it does not submit a chat message or terminal command.

Copy and paste-back use the system clipboard. Before temporary paste content, the app requires a complete clipboard backup; restoration protects a newer user copy. A paste status reports a requested operation, not proof of a successful host edit. Clipboard failure paths retain the visible result for deliberate copying rather than silently overwriting the clipboard. Clearing the workspace does not clear copied text. Review the [terminal limits](docs/terminal.md) and [troubleshooting guide](docs/troubleshooting.md).
