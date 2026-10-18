# Windows and Linux desktop guide

The Windows and Linux editions add a local desktop workspace and an experimental selection assistant. They share the prompt optimizer with the native macOS app and the browser/API. The desktop packages include their own Electron runtime; end users do not need to install Node.js.

Download only the package that matches your operating system and processor from [GitHub Releases](https://github.com/JERMYSUEN/promptfinch/releases). A source archive is for development, and a macOS ZIP cannot run on Windows or Linux. The existing [native macOS guide](macos.md) still applies to the Swift app.

## Support and limits

| Environment | Desktop workspace | External selection action | Result handling |
| --- | --- | --- | --- |
| Windows x64 | Supported | Experimental: Windows UI Automation text selection and a companion action beside the host context menu | Review, copy, and paste manually |
| Linux x64, X11 with RECORD extension | Supported | Experimental: observes right-button presses and reads the X11 PRIMARY selection | Review, copy, and paste manually |
| Linux x64, Wayland | Supported when the distribution supports the bundled Electron runtime | Global right-click capture is unavailable; paste text or import text you explicitly copied | Review, copy, and paste manually |
| macOS | Use the native Swift edition | See the [macOS](macos.md) and [Terminal](terminal.md) guides | Native edition's documented behavior |

The external companion is separate from the source app's native context menu. It does not modify Codex, Claude Code, browsers, terminals, or their menu definitions. Right-clicking alone does not generate a prompt or send text to a model. Select the companion's conversion action to start a request. Closing or cancelling the companion does not submit the captured text.

Windows compatibility depends on the source app exposing its selected range through UI Automation. Legacy Chromium accessibility modes can lack the required TextPattern; the isolated Chromium check explicitly enables its native UIA provider and does not certify every default Chrome/Electron configuration. Some custom editors, protected fields, elevated apps, remote desktops and terminal renderers do not expose that range. The assistant does not send synthetic Copy keystrokes or use old clipboard text as a substitute. Use the manual workspace if selection capture is unavailable.

On X11, the PRIMARY selection is separate from the ordinary Copy/Paste clipboard. It can outlive visible highlighting in some applications, and a right-click is not proof that the pointer is inside the highlighted range. Read the source shown in the workspace before using the generated prompt. The assistant does not promise that every right-click corresponds to a fresh selection. Empty selections are ignored. A missing X11 RECORD extension disables the companion without preventing manual use.

Wayland intentionally restricts global input observation and cross-app selection access. Running an XWayland application does not make selections in native Wayland apps accessible. PromptFinch does not add a compositor extension or bypass those restrictions. Do not change system security settings to make the selection helper run.

## Install and run

### Windows

Use the `windows-x64-setup.exe` installer for a normal per-user installation. It does not request administrator access. Alternatively, extract the Windows x64 ZIP into a folder you control and run `PromptFinch.exe` from that folder. Keep all extracted runtime files together.

The initial packages are unsigned. Windows may show publisher or reputation warnings. Verify the published SHA-256 checksum and source before deciding whether to run a download. This project does not ask you to disable SmartScreen or antivirus protection.

### Linux

Use the Linux x64 AppImage, or extract the Linux x64 `tar.gz` archive and run its `promptfinch` executable from the extracted folder. An AppImage may need its executable permission enabled:

```sh
chmod u+x PromptFinch-*-linux-x64.AppImage
./PromptFinch-*-linux-x64.AppImage
```

The Linux packages are built and tested on Ubuntu 22.04 x86_64 and require a compatible glibc-based distribution. AppImage and tarball packages do not bundle every host library. Older distributions and musl-based systems such as Alpine have not been validated.

Some distributions need the FUSE 2 compatibility library to mount AppImages. If mounting is unavailable, use the `tar.gz` package. Keep the extracted Chromium sandbox files with the app and run it as your normal user. The project does not ship `--no-sandbox` launch flags.

X11 selection capture additionally needs the distribution's X11 and Xtst runtime libraries, an active X11 session, and the X server's RECORD extension. Ubuntu package names are `libx11-6` and `libxtst6`. If an observer stops or a provider times out, quit and reopen PromptFinch to restart observation. Manual input remains available. The workspace remains available on Wayland; paste or import copied text there.

## First use and model settings

1. Open the desktop workspace. A new installation starts in clearly labelled demo mode.
2. Paste a rough request, choose its purpose, and optionally name the target model.
3. Generate and review the English prompt, the changes, and any assumptions.
4. Copy the prompt using the result's copy button and paste it into the intended app yourself.

Demo mode checks the interface without calling a model. It does not translate or optimize text and must not be used to judge output quality.

To enable a model, open Settings and create a configuration template, edit that local file, then choose or reload it in the app. The template starts in demo mode and contains no API key. A live configuration needs your own provider key and an exact model identifier accepted by that provider:

```dotenv
OPTIMIZER_MODE=live
LLM_BASE_URL=https://api.deepseek.com
LLM_MODEL=deepseek-flash
LLM_API_KEY=your-own-provider-key
LLM_JSON_MODE=true
LLM_THINKING_MODE=disabled
LLM_TIMEOUT_MS=45000
```

The model adapter uses an OpenAI-compatible Chat Completions API. The example model name is a configuration value, not a bundled or free model. Provider access, naming, availability and fees depend on your account. A Codex or Claude subscription/login is not an API key for this app. See the [main settings reference](../README.md#model-configuration) for the shared provider options.

An invalid or incomplete live configuration stops generation and displays an error. It does not silently replace a failed model call with a demo result. Switching explicitly back to demo mode is available in Settings.

The interface and explanation language can be Traditional Chinese, English, Japanese, or Korean. Generated instructions stay in English while preserving an explicitly requested answer language and exact literals from the source. Review generated prompts before using them: model output can still omit or alter requirements.

## Selection workflow

Leave PromptFinch running, select synthetic or non-sensitive text in a compatible source app, and right-click. If capture succeeds, a nearby companion offers conversion or cancellation. Choose conversion, review the source and result in PromptFinch, then copy and paste the result manually. The Windows/Linux editions do not overwrite text or send Return to another app, including a shell or a CLI input field.

If no companion appears, check the support table above and the app's selection status. On Windows, try a standard editable text control before testing a custom terminal or editor. On Linux, check that the login session is X11 rather than Wayland. A shortcut may also fail when another app already owns it or the desktop portal does not allow it; the manual workspace remains the fallback.

Use synthetic test text such as `Write a short guide for ACME-42. Answer in Traditional Chinese.` Do not put private chat contents, API keys, documents, or customer information into compatibility reports.

## Privacy and security

Model requests run in Electron's main process, using the same server-side optimizer module as the other editions. The renderer receives no model API key and cannot access Node.js. The workspace does not open an HTTP listener or expose a model proxy to other apps.

The app stores only the interface language and chosen configuration file location in its preferences. It does not keep prompt history, model responses, captured selections, clipboard history or diagnostic text logs. Your API key remains in the configuration file you choose, which must be kept outside the repository and out of shared/cloud folders unless you intend that exposure. The app reads that file in its main process and retains the active provider settings in memory while it runs.

The Windows observer reads accessible selected text after a right-button press. The Linux observer emits button coordinates and time only; Electron reads the current PRIMARY selection locally. A supported right-click may therefore capture text locally before you choose conversion. Sending text to a model happens only after an explicit generation/conversion action. Closing the app ends observation. Review the [security policy](../SECURITY.md) for reporting a vulnerability.

## Development and packaging

Use Node.js 22.12 or newer and a matching native x64 build host. Install dependencies and run the desktop workspace:

```sh
npm ci
node scripts/build-desktop-helpers.cjs
npm run desktop
```

Windows builds use the .NET Framework 4.x C# compiler and UI Automation assemblies included with Windows. No NuGet package or PowerShell execution-policy exception is required. On an Ubuntu 22.04 X11 build host, install the development packages first:

```sh
sudo apt-get install build-essential libx11-dev libxtst-dev xvfb xauth
```

Build on Windows for Windows, and on Linux for Linux:

```sh
npm run build:desktop -- --publish never
```

Packages are written under `desktop-dist/<version>/`. Windows outputs an NSIS installer and ZIP. Linux outputs an AppImage and a `tar.gz` archive. Public packages use a file allowlist and include only the matching compiled helper; private `.env` files, original recordings, local test artifacts and development captures are excluded. The macOS Electron shell is a development aid; the supported macOS distribution is the native Swift app.

Run the normal checks and the desktop mock smoke check:

```sh
npm run check
npm test
npm run test:desktop
```

On a headless Linux host, run the desktop check through `xvfb-run --auto-servernum npm run test:desktop`. The check launches an isolated temporary profile in demo mode, without touching installed app preferences, enabling selection observation, or calling a provider. A packaged executable can be checked with `node scripts/desktop-smoke.cjs --packaged <absolute-path-to-executable>`.

The [desktop build workflow](../.github/workflows/desktop.yml) compiles and packages each edition on its native x64 runner, checks both development and packaged workspaces in demo mode, and records per-platform SHA-256 hashes and build provenance. Its Windows check reads a synthetic selection from a standard text control through UI Automation. Its X11 test exercises the observer on a virtual display and confirms that left clicks are ignored and Wayland is rejected. A separate macOS job checks only the Electron development workspace; macOS downloads still use Swift. A successful workflow does not establish physical right-click compatibility with every external app, live model quality, ARM support, code signing, or installation on every Linux distribution. Treat the Windows/Linux selection action as experimental until the intended host app and desktop session have been tested.

Implementation references: [X11 RECORD library](https://www.x.org/releases/current/doc/libXtst/recordlib.pdf), [Electron security](https://www.electronjs.org/docs/latest/tutorial/security), [Electron clipboard](https://www.electronjs.org/docs/latest/api/clipboard), and [electron-builder](https://www.electron.build/).
