# PromptFinch Browser Extension (Manifest V3)

Zero-OS-permission prompt refinement inside **ChatGPT**, **Claude**, **Gemini**, **GitHub**, **Notion**, and **Perplexity**.

## Features

- **Selection Micro-Pill (`~108×28px`)**: Select text inside any supported web editor and click **Refine** — selecting text alone never calls an API.
- **Direct In-Place Replacement**: Replaces selected text cleanly inside `<textarea>`, `<input>`, and `contenteditable` editors without needing OS Accessibility permissions.
- **Multi-Provider BYOK + Local Backend**: Connect directly to **DeepSeek**, **OpenAI**, **Anthropic Claude**, **Google Gemini**, **Ollama (Local)**, or your local PromptFinch desktop API (`http://127.0.0.1:3210`).
- **Local Secret Shield**: Optional client-side masking of API keys, GitHub tokens, AWS keys, JWTs, and PEM private keys before transmission, restored locally after generation.

## Load Unpacked (Chrome / Edge / Brave / Arc)

1. Open `chrome://extensions` (or `edge://extensions`).
2. Enable **Developer mode** in the top-right corner.
3. Click **Load unpacked** and choose the `extension/` directory of this repository.
4. Click the **PromptFinch** toolbar icon → **Settings** to select a provider preset and save your API key (or choose `Local PromptFinch Server`).
