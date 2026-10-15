# HTTP API reference

This reference describes API version 2 on current `main`. Start the standalone server using the [README](../README.md#quick-start). It defaults to `http://127.0.0.1:3000`; the macOS app owns a separate backend at `http://127.0.0.1:3210` while it is running. All examples use synthetic text.

The API is a personal local service without client authentication or multi-user isolation. Do not send the model-provider key from a browser or put it in these requests. Only the backend reads that key. Host and Origin checks limit accepted requests; they are not an authentication mechanism. See [Security](../SECURITY.md) before any deployment.

## Read configuration

```sh
curl --fail --silent --show-error http://127.0.0.1:3000/api/config
```

Example for the default standalone mock server:

```json
{
  "service": "prompt-studio",
  "apiVersion": 2,
  "backendID": null,
  "backendInstanceID": null,
  "mode": "mock",
  "ready": true,
  "generationModel": null,
  "maxPromptLength": 12000,
  "tasks": {
    "general": "通用用途",
    "writing": "寫作",
    "analysis": "分析",
    "coding": "程式開發",
    "summary": "摘要",
    "marketing": "行銷"
  },
  "promptLanguages": ["zh-Hant", "en"]
}
```

`service: "prompt-studio"` is the retained protocol identifier, despite the product name PromptFinch. Clients should use the task keys rather than treating their Traditional Chinese labels as identifiers. Backend and instance IDs are opaque version/ownership metadata; standalone values can be null.

In live mode, `ready` only checks that a key and model identifier are present. It does not contact the provider, validate the key, confirm model access, or establish output quality. The endpoint never returns the key, full environment, or provider response body.

## Optimize a prompt

```sh
curl --fail-with-body --silent --show-error http://127.0.0.1:3000/api/optimize \
  -H 'Content-Type: application/json' \
  --data '{"prompt":"Write a short greeting.","task":"writing","targetModel":"","promptLanguage":"en"}'
```

If your curl does not recognize `--fail-with-body`, omit that flag to inspect an error body and check the HTTP status separately. This command uses mock output unless you explicitly configure live mode.

| Field | Type and rule |
| --- | --- |
| `prompt` | Required nonblank string, up to 12,000 UTF-16 code units. Whitespace and code indentation are preserved. |
| `task` | Optional string: `general`, `writing`, `analysis`, `coding`, `summary`, `marketing`. Default: `general`. |
| `targetModel` | Optional single-line string, up to 80 UTF-16 code units. Leading/trailing whitespace is trimmed. It is a wording hint, not the generation model selector. |
| `promptLanguage` | Optional `en` or `zh-Hant`. Default when omitted: `zh-Hant`. It controls prompt instructions, not the downstream answer language specified in `prompt`. |

Omit an optional field to use its default; `null` is not a valid substitute. Use `LLM_MODEL` in the server configuration to select the model that edits prompts. There is no streaming, file-upload or batch endpoint; clients submit one request at a time or manage their own bounded queue.

For the request above, the default mock response is:

```json
{
  "prompt": "DEMO ONLY — the source below has NOT been translated or semantically optimized.\n\nTask requirements (untranslated source):\nWrite a short greeting.\n\nPreserve all facts, constraints, tone, and the requested answer language and format. Ask for missing critical information before executing the task.",
  "improvements": [
    "流程示範：只加入固定英文外框，沒有進行語意整理。",
    "請設定真實模型後取得可直接使用的英文 Prompt。"
  ],
  "assumptions": [],
  "mode": "mock",
  "generationModel": null,
  "promptLanguage": "en"
}
```

A successful live response has the same fields, `mode: "live"`, the configured `generationModel`, and model-generated content. Copy only `prompt`. Improvement notes contain 1–4 strings; assumptions contain 0–4, with each note at most 500 UTF-16 code units. Notes are requested in Traditional Chinese. A live format failure is an error, not a silent fallback to mock.

In English mode, `prompt` is the complete rewritten instruction, with required task data and literals retained. Traditional Chinese mode wraps the complete original request with supplemental execution guidance. The model-generated portion is limited to 24,000 UTF-16 code units; the assembled Traditional Chinese result can be longer because it also contains the original. Schema validation does not prove semantic fidelity, so review names, quantities, conditional requirements, output format and answer language before using a result.

## Errors and limits

Errors return a JSON object such as:

```json
{"error":"請先輸入想優化的 Prompt。"}
```

Messages are user-facing Traditional Chinese, not stable machine-readable error codes. Branch on HTTP status rather than matching their exact wording.

| Status | Meaning and response |
| --- | --- |
| `400` | Invalid JSON, malformed Host/Origin, or invalid fields. Fix the request. |
| `403` | Host/Origin or cross-site policy rejected the caller. Use the correct service origin or an explicitly configured host. |
| `404` | Unknown non-API page. |
| `405` | Unsupported API path or HTTP method, including unknown `/api/...` paths. |
| `413` | JSON request body exceeded 98,304 bytes (96 KiB). No partial input is optimized. |
| `415` | Request did not use `Content-Type: application/json`. |
| `429` | Four optimizations are already active in this server process, or the provider returned a rate/usage limit. Avoid immediate retry loops. |
| `502` | Provider authorization/configuration/service/connection error, truncated output or unusable response. Read the safe error message; provider `401`/`403` are mapped to this status. |
| `503` | Live mode lacks a configured API key or model. Configure them or deliberately choose mock. |
| `504` | Provider attempt timed out or was aborted. Check provider availability and the timeout setting. |
| `500` | Unexpected internal failure; only a generic message is returned. |

Every request requires an allowed `Host`. API requests with `Origin` must also match an allowed host and port. Cross-site browser requests are rejected; no general cross-origin access is provided. Native and command-line clients can omit Origin. Reverse proxies must preserve an explicitly allowed Host; forwarded host headers are not trusted.

`LLM_TIMEOUT_MS` limits each provider attempt. An invalid structured response can cause one further attempt; HTTP failures are not generally retried. The setting is not a total-operation budget. The browser aborts at about 195 seconds, and the native client has its own request/resource limits around 190/195 seconds. Setting a very large per-attempt timeout does not guarantee both attempts can complete within a client budget.

Closing or cancelling the client request propagates an abort to the upstream request. It does not guarantee that the provider stops processing or refunds usage. Request-body and header receive timeouts are separate from model execution. No prompt content or raw provider errors are written to server logs.

For setup failures and status examples, see [Troubleshooting](troubleshooting.md). Model compatibility and available identifiers are determined by your provider; see [model configuration](../README.md#model-configuration).
