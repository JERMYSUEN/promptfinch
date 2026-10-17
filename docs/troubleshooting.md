# Troubleshooting

Use this guide with the [quick start](../README.md#quick-start). For detailed native settings, see the [macOS guide](macos.md) in Traditional Chinese. Try synthetic, shareable input when investigating a problem.

## Choose the correct workflow

The browser/API can run with Node.js 22+; cross-app selection requires the native macOS app. A browser tab alone cannot add a system-wide context-menu action. Terminal support is the macOS selection assistant alongside a CLI, not a `promptfinch` shell command, CLI plugin, or use of Claude Code/Codex credentials.

The macOS interface has four languages. The browser interface is Traditional Chinese. New native explanation notes follow the interface language; existing results are kept as generated. The browser has a separate notes-language selector. These settings do not change the generation model or the task’s requested answer language. See [language coverage](../README.md#documentation-languages).

## Startup, installation and updates

| Symptom | What to check |
| --- | --- |
| `node` is missing or the app cannot find it | Install Node.js 22+ separately. The app does not bundle Node. Select its executable in native Settings, particularly for nvm or another version manager. |
| `install:mac` says the app is missing | Run `npm run build:mac` first; installation does not compile the app. Build prerequisites include Apple's Command Line Tools. |
| A downloaded ZIP behaves differently from this README | Check the release tag and [changelog](../CHANGELOG.md). The [v1.1.0 download](releases/v1.1.0.md) includes newer features; the original v1.0.0 asset remains unchanged. No release is a notarized installer. |
| The app's version label says 0.1.0 | That is the original v1.0.0 download's internal version (build 11). The v1.1.0 app uses version 1.1.0 / build 12. App version alone does not identify a separately updated backend; include the source commit and `/api/config` backend ID when reporting a problem. |
| A replaced app still uses old prompt rules | Existing external backend files are retained when the app is replaced. In the new app's Settings, choose **Use this app’s bundled backend** to adopt its included rules. Private model configuration, Node path and preferences are retained, with rollback attempted if startup fails. Source users can instead run `npm run update:mac-backend` from a trusted updated checkout; for native changes, build and install first. |
| Stable signing fails after moving machines | The private signing identity belongs to that machine's Keychain. Follow the macOS signing setup on the new machine; a same-name certificate is not the same identity. |
| Port 3000 is busy | Stop the standalone server you own or change its `PORT` and open that matching URL. Do not terminate an unidentified process. |
| Port 3210 is busy | The native backend uses this fixed port. Quit an older PromptFinch instance normally. If another program owns the port, resolve that conflict before restarting; the updater will not kill it. |
| Closing the window does not stop selection actions | The menu-bar assistant keeps running. Use Quit to stop the app and its owned backend. |

The browser server normally uses port 3000; the app owns port 3210. A model configuration selected in the app is not automatically the standalone server's `.env`. Reload the selected app configuration after saving it; restart the standalone server after changing its environment file.

## Model and configuration errors

`GET /api/config` helps identify the running mode, model and backend. `ready: true` only indicates that live configuration has a key/model, or that the server is in mock mode; it is not an upstream health check. Do not publish configuration files or screenshots containing a key.

| Symptom | What to check |
| --- | --- |
| Output says `DEMO ONLY` or reports mock mode | Mock only exercises the interface. Set `OPTIMIZER_MODE=live`, supply your own key/model/base URL, then reload or restart. Do not delete the mock label to make the result appear real. |
| Changing the target-model text does not switch the API | This field guides prompt wording. Change `LLM_MODEL` and the relevant provider configuration to change the generation model. |
| API returns 503 | The live key or model identifier is missing. The project supplies neither a shared key nor a bundled language model. |
| Error says the provider rejected authorization | Check the private key, account access and provider endpoint. An upstream 401/403 appears as local 502. Claude/Codex login subscriptions are separate. |
| Local API returns 403 | Check the service URL and Host/Origin policy. This is different from provider-key rejection. See the [API status reference](api.md#errors-and-limits). |
| Provider rejects the request format | Use an OpenAI-compatible Chat Completions endpoint. The backend appends `/chat/completions`; do not append it twice. Use `LLM_JSON_MODE=false` if unsupported and leave `LLM_THINKING_MODE` blank outside compatible DeepSeek configurations. The output must still follow the JSON contract. |
| API returns 429 | The local concurrency limit or provider usage limit was reached. Stop automatic retry loops and check account limits. |
| API returns 502/504 or takes too long | Check provider availability and configuration. The initial call and format retry share one `LLM_TIMEOUT_MS` deadline. Increasing a timeout cannot repair an unavailable service. A failure is not replaced with a fake successful result. |

Use the model identifier your provider currently accepts. `.env.deepseek.example` is a configurable example, not a bundled model or guarantee of account access. There is no automatic paid fallback provider.

## Selection, copy and paste-back

For the first run with native selections, allow PromptFinch under **System Settings → Privacy & Security → Accessibility**, then recheck permission in Settings. The manual workspace and an explicit clipboard action are available without cross-app selection access.

The optional selection button, right-click menu and automatic paste-back are enabled by default for a new native preference profile. To review a result before it can replace editable source text, disable automatic paste-back in Settings. Recognized terminal sources always use copy-only delivery regardless of that setting.

| Symptom | What to check |
| --- | --- |
| Only the original right-click menu appears | Keep PromptFinch running, enable its right-click setting and Accessibility permission, then make a fresh readable text selection. The app supplies a separate companion panel, not a new item inside every host's menu. |
| A notice asks you to select again | Some hosts need a brief Accessibility activation interval. Wait about two seconds and make a new selection. |
| Service reload, upgrade or quit reports a stop error | Only the app’s owned child is stopped, with bounded waiting. The app refuses a second service if cleanup fails. Retry after the reported error; do not kill unrelated processes by port or name. |
| The offered action disappears | Switching apps, typing, clicking elsewhere, cancellation and the 12-second action timeout invalidate it. Make a fresh selection rather than reusing the previous one. |
| Selection cannot be read | The host may expose no usable text, for example a protected field, image or canvas. There is no OCR or forced-copy fallback. Deliberately copy the intended text and use the menu-bar clipboard action or manual workspace. |
| The result did not replace selected terminal text | This is expected for recognized terminals. Copy/review and paste into the intended CLI input manually, then submit yourself. Do not assume every custom terminal is identified. See the [Terminal guide](terminal.md). |
| Status says a paste was requested but the source is unchanged | A sent simulated paste is not proof that the host accepted it. Inspect the source and result, then copy manually if needed. The tool never submits the chat message. |
| Copy or clipboard restoration failed | Keep the result visible and read the status. Do not assume an earlier clipboard value was restored. The app protects a newer user copy; failure paths do not silently overwrite it as a fallback. |

Clearing the workspace removes its current input/result, not the system clipboard, saved settings, provider-side data, or files you deliberately saved. A clipboard manager outside PromptFinch can retain copied text under its own policy.

## Output quality and bug reports

Review the copied prompt against the original intent, facts, exact strings, numerical limits, answer language and format. More headings or a longer prompt are not proof of improvement. The optimizer should add useful execution guidance where needed and keep already-clear requests concise; it should not perform the original task.

The Codex GIF is a hand-authored synthetic illustration. Earlier language samples do not validate every subsequent policy version. The newest task-guidance live attempts failed with provider errors; [the record](optimization-value-verification.md) does not claim a successful before/after comparison.

Report ordinary bugs through [GitHub Issues](https://github.com/JERMYSUEN/promptfinch/issues) using the format in [Contributing](../CONTRIBUTING.md). Include the source revision, environment, entry point, expected/actual behavior and a small synthetic case. Do not paste `.env`, real prompts, clipboard contents or an unreviewed diagnostic log. For sensitive vulnerabilities, follow [Security](../SECURITY.md).
