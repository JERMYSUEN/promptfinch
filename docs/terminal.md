# Terminal and CLI selection workflow

Use the existing PromptFinch macOS app alongside Claude Code or Codex CLI in macOS's built-in **Terminal**. Select displayed text with the mouse, right-click, and choose **Convert to English prompt** in PromptFinch's companion menu. No new shell command or CLI plugin is required.

The generated text is an edited set of instructions, not an answer to the selected request. The optimizer is asked to clarify the task and its constraints and, when useful, organize its approach and checks without adding new requirements. English is the prompt's instruction language; a requested answer language such as Japanese or Traditional Chinese should remain in those instructions. Review the output: this behavior is a model policy, not a guarantee that every result preserves every detail.

Terminal selection identifies displayed text, including scrollback. It does not identify an editable range in the running program's input. PromptFinch therefore converts and copies terminal selections for manual use; it does not replace the highlighted text or inject a paste into the terminal.

## Setup

1. Build and install the macOS app using the [quick start](../README.md#build-and-install-the-macos-app). Updating native selection support requires a rebuild and reinstall. If an installed app already has an external backend, also run `npm run update:mac-backend` from your updated source checkout; reinstalling the app alone keeps that existing backend. See the [update procedure](macos.md#僅更新後端不重建-app).
2. Open PromptFinch and allow it in **System Settings → Privacy & Security → Accessibility**. Use **Check permission again** in the app if needed.
3. In Settings, enable **Show an action menu when right-clicking selected text**.
4. Select and reload your existing model configuration. The app starts its own local backend on `127.0.0.1:3210`; you do not need to start the browser service.
5. For real English optimization, configure your own model API as described in [Model configuration](../README.md#model-configuration). Keep the API key in the private configuration file, outside the repository.

Without a model key, use the clearly labeled mock mode to check selection, menu, result, cancellation, and deliberate copying. Mock output does not translate or semantically optimize the input and is not automatically pasted back.

## Basic usage

1. Open macOS Terminal and run Claude Code or Codex CLI as usual.
2. Use the mouse to highlight the request you want to refine. Selected text can come from an input display or earlier output; check that it contains the intended request.
3. Right-click the highlighted text. The host context menu remains available, and PromptFinch offers **Convert to English prompt** and **Cancel** nearby when the selection is readable.
4. Choose **Convert to English prompt**. Right-clicking alone does not generate a result or send text to the model. PromptFinch checks the source and selection again before starting.
5. Review the English prompt and status in the nearby result panel. A successful live terminal conversion copies only the prompt; the status reports whether copying succeeded. The separate improvement and assumption notes are available in PromptFinch's manual workspace. Those notes are currently requested in Traditional Chinese regardless of the selected interface language.
6. Return to the intended Claude Code or Codex CLI input, remove any earlier draft you intend to replace, and paste manually. Review the complete input, then submit it yourself.

The terminal copy-only policy applies even when automatic paste-back is enabled for editable fields elsewhere. PromptFinch does not send a paste key, Enter, or a shell command to recognized terminal sources. Choosing conversion can send Escape to dismiss the host's context menu before the selection is checked again; this is not a terminal paste. The panel's Copy action remains available; if clipboard writing fails, the result remains visible for another deliberate attempt.

Use an AI CLI input when pasting the result. A shell prompt treats pasted text as shell input, and line breaks can have immediate effects; [Apple documents this behavior for Terminal](https://support.apple.com/guide/terminal/trml1019/mac).

## Compatibility boundary

| Source | Policy and requirements |
| --- | --- |
| Apple Terminal (primary workflow) | Recognized as a terminal application and uses copy-only delivery. Selection still depends on readable macOS Accessibility text. |
| iTerm2 | Also recognized for copy-only delivery, but selection compatibility requires a separate host/version test. |
| Identified embedded xterm.js terminal controls | Terminal controls use copy-only delivery. A fresh read after right-click allows a host's context-menu selection helper to become available. |
| Other terminal apps or custom terminal controls | Readable selection access and terminal identification must be checked for that host/version. Do not assume compatibility from another terminal's result. |
| CLI/TUI applications with mouse reporting | The application may consume mouse selection or right-click events. Use the terminal's documented selection override or disable mouse reporting if appropriate; there is no universal modifier-key rule. |

Embedded terminal handling is bounded by recognizable terminal control metadata. PromptFinch does not treat every IDE text field as a terminal, scrape the whole accessibility tree, inspect terminal buffers, or change Claude Code or Codex CLI.

The copy-only restriction depends on that positive identification. Other terminal apps and custom controls do not automatically inherit it. Before trying an unverified host, turn off automatic paste-back in PromptFinch and use synthetic text to confirm that no **Paste back** action is offered. For a host that cannot be identified reliably, use explicit Copy followed by PromptFinch's clipboard or manual workspace instead of selection-based paste-back.

The timing matters for xterm.js: its official [clipboard implementation](https://github.com/xtermjs/xterm.js/blob/master/src/browser/Clipboard.ts) moves and focuses a helper textarea on right-click, then fills it with the selected display text. Its paste path sends data to the terminal input handler. This is why a later selection read can help and why that helper must not be treated as an editable prompt replacement target.

## Troubleshooting

- **Only the host menu appears:** Confirm PromptFinch is running, Accessibility permission is enabled, and the right-click option is on. Make a new selection before trying again.
- **Accessibility activation notice:** Wait about two seconds, then select the text again and right-click. Do not reuse an earlier offered action.
- **Selection changed or could not be verified:** Reselect the intended text. Switching apps, typing, changing the selection, or waiting beyond the action timeout invalidates the old action.
- **No readable selected text:** Explicitly copy the selection using the terminal's own Copy command, then choose **Generate English prompt from clipboard** from PromptFinch's menu bar. You can also paste into the manual workspace and generate there.
- **Mouse selection does not work:** Consult the terminal and CLI/TUI settings for mouse reporting and selection overrides. Test plain terminal text first to distinguish host selection access from CLI behavior.
- **Result did not replace the highlight:** This is expected for terminal sources. Paste into the intended CLI input yourself.
- **The model reports a connection, authorization, or format error:** Check the selected configuration and provider access in PromptFinch. The CLI's own provider or login is separate; PromptFinch does not inherit Claude Code or Codex CLI credentials or use their model sessions. Mock checks local flow only.

PromptFinch does not monitor clipboard contents in the background, use OCR, or force-copy terminal text with simulated keys. The fallback clipboard read is a separate action you choose. A successful copy replaces the current system clipboard text; no clipboard history is saved.

Selection actions use the task and optional target-model hint last chosen in PromptFinch's workspace. The hint does not switch the generation provider or model. Live mode sends the selected text and editing context to your separately configured provider; do not select shell history, secrets, or unrelated output that you do not want sent there. Closing the PromptFinch workspace leaves its menu-bar assistant active; use **Quit** to stop it and its owned backend.

## Manual acceptance check

Use synthetic text in a test session. Do not select API keys or private terminal output. For example:

```text
請撰寫 ACME-42 的產品更新通知，對象是既有用戶，語氣友善專業。
介紹新增快速搜尋功能，不要承諾上線日期。
答案請用繁體中文，限制在 180 個中文字以內，產品名稱「ACME-42」必須逐字保留。
```

With your live model configuration, verify all of the following using a physical mouse:

- Right-clicking offers a choice and makes no model request until conversion is chosen; Cancel leaves the terminal input unchanged.
- Conversion produces English instructions that retain `ACME-42`, Traditional Chinese as the answer language, the 180-character limit, the audience, tone, feature, and no promised launch date.
- The result reports copying success, and manual paste contains only the prompt, without the explanatory notes.
- Nothing is pasted into or submitted to the terminal automatically, including when automatic paste-back is enabled for other apps.
- Changing the source selection or switching apps before choosing conversion rejects or dismisses the stale action.
- Repeat separately for the terminal host and each CLI/TUI configuration you intend to use. Record host versions and results rather than assuming all terminals behave alike.

## Verification status

On 2026-10-11, JavaScript syntax checks, 55 Node tests, 233 native checks, README consistency and local documentation links passed. The macOS build and signature checks passed, and the updated app was installed and opened with the existing model configuration. Native checks use synthetic selections and mocked operations to cover terminal classification, context-menu capture timing, source revalidation, copy-only delivery and clipboard failure. They do not establish end-to-end compatibility with real terminals or CLI programs. Browser flow tests were not rerun for this native change.

The user confirmed a physical-mouse test in macOS's built-in Terminal: the companion menu appeared, and choosing conversion produced an English result. The reply did not identify which CLI was running. Separate Claude Code and Codex CLI versions, clipboard contents, manual paste, cancellation, unchanged terminal input and output fidelity were not recorded as verified.

Native computer-use automation was blocked from Apple Terminal with `Computer Use is not allowed ... com.apple.Terminal`, so that user report is the real-host evidence. Complete the remaining manual checks above for each CLI and terminal configuration you intend to use. iTerm2 and embedded xterm.js host compatibility remain unverified.
