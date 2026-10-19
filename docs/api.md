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
  "qualityReviewEnabled": false,
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
  "promptLanguages": [
    "zh-Hant",
    "en"
  ],
  "notesLanguages": [
    "zh-TW",
    "en",
    "ja",
    "ko"
  ]
}
```

`service: "prompt-studio"` is the retained protocol identifier, despite the product name PromptFinch. Clients should use the task keys rather than treating their Traditional Chinese labels as identifiers. Backend and instance IDs are opaque version/ownership metadata; standalone values can be null.

In live mode, `ready` only checks that a key and model identifier are present. It does not contact the provider, validate the key, confirm model access, or establish output quality. The endpoint never returns the key, full environment, or provider response body.

Current servers also return `qualityReviewEnabled`, a public boolean that is true only in live mode with `LLM_QUALITY_REVIEW=true` explicitly configured. The setting defaults to `false`; unset or `false` uses editing only. It describes the configured review path, not a completed provider call or a quality guarantee. Mock mode reports false and does not call a model regardless of this setting. Older API version 2 servers may omit this field; clients should tolerate optional metadata and ignore unknown fields.

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
| `notesLanguage` | Optional `zh-TW`, `en`, `ja`, or `ko`. Default: `zh-TW`. Controls only improvement and assumption notes, independently of instruction and downstream answer languages. |
| `promptLanguage` | Optional `en` or `zh-Hant`. Default when omitted: `zh-Hant`. It controls prompt instructions, not the downstream answer language specified in `prompt`. |

Omit an optional field to use its default; `null` is not a valid substitute. Use `LLM_MODEL` in the server configuration to select the model that edits prompts. There is no streaming, file-upload or batch endpoint; clients submit one request at a time or manage their own bounded queue.

For the request above, the default mock response is:

```json
{
  "prompt": "DEMO ONLY — the source below has NOT been translated or semantically optimized.\n\nTask requirements (untranslated source):\nWrite a short greeting.\n\nPreserve all facts, constraints, tone, and the requested answer language and format. Ask for missing critical information before executing the task.",
  "improvements": [
    "流程示範：只加入固定英文外框，沒有進行語意整理；原文未翻譯。",
    "加入一般執行提醒；尚未判斷原文的矛盾或關鍵缺漏。",
    "請設定真實模型以取得優化結果；示範模式不提供模型專屬調整。"
  ],
  "assumptions": [],
  "mode": "mock",
  "generationModel": null,
  "promptLanguage": "en",
  "notesLanguage": "zh-TW"
}
```

A successful live response has the same fields, `mode: "live"`, the configured `generationModel`, and model-generated content. Copy only `prompt`. Improvement notes contain 0–4 strings; assumptions contain 0–4, with each note at most 500 UTF-16 code units. An already clear request can return an empty improvements array; the workspace then displays a separate no-additional-edits notice. Do not require `improvements[0]` or append that notice to the prompt. Notes use `notesLanguage`; the native app sends its interface language, and the browser offers a separate selector. Existing results are not translated when the preference changes. A live format failure is an error, not a silent fallback to mock.

Both English and Traditional Chinese modes return a complete rewritten instruction in `prompt`, with required task data and literals retained. Compatible requirements remain binding; impossible combinations require clarification or a brief conflict notice when questions are forbidden, rather than simultaneously instructing the model to perform the impossible task. The complete live prompt is limited to 24,000 UTF-16 code units. A narrow literal repair can restore unambiguous quoted/code text altered only by canonical NFC normalization in either language; it does not reconstruct omitted or translated content. Review names, quantities, conditional requirements, output format and answer language before using a result.

This changes the Traditional Chinese result's text composition: the backend no longer appends an original-request wrapper. API version 2 and the request fields remain unchanged, but clients that parsed wrapper headings or expected the source to be appended must migrate. Keep the submitted source separately, display the returned prompt as a whole, accept empty note arrays, and tolerate additional response metadata.

Successful live responses include review metadata. The default editing-only path reports:

```json
{
  "modelReview": { "status": "disabled", "revisionCount": 0 }
}
```

`status` is `approved` when an explicitly enabled model-review path accepted the candidate, or `disabled` when `LLM_QUALITY_REVIEW` is unset or `false`. `revisionCount` is 0 or 1 and counts the semantic repair, not format retries or paid calls. An approval reports the model's judgment; it is not proof of semantic fidelity or better downstream task performance. Mock output does not use the live review path.

## Live review and usage

Live mode defaults to editing only (`LLM_QUALITY_REVIEW` unset or `false`), normally one provider call or at most two if a format retry is needed. Model review is optional: explicitly set `LLM_QUALITY_REVIEW=true` to enable it. Current evidence does not justify enabling its added cost automatically. When enabled, the same configured provider and model receive the original requirements and candidate in a separate request context after editing. A normal successful reviewed operation uses two provider calls. If the reviewer rejects a candidate, one repair and another review are allowed; editing, review, repair, and format retries together are bounded to four calls. The reviewer is instructed to check requirement scope, contradictions, assumptions, literals and whether the editing notes describe actual changes. This is still a fallible model check.

When review is enabled, failure to complete or pass it returns an error; the rejected candidate is not delivered and a mock result is not substituted. Optional review increases latency and billed input/output tokens on the configured account. Set `LLM_QUALITY_REVIEW=false`, or remove that setting, to return to the default editing-only path. Clients cannot switch this server setting through the optimization request. Mock remains a zero-model-call interface demo. See the [current quality-verification record](prompt-quality-verification.md) for evidence and remaining limitations.

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
| `502` | Provider authorization/configuration/service/connection error, truncated output, unusable response, or unsuccessful model review. Read the safe error message; provider `401`/`403` are mapped to this status. |
| `503` | Live mode lacks a configured API key or model. Configure them or deliberately choose mock. |
| `504` | The shared provider deadline expired or the request was aborted. Check provider availability and the timeout setting. |
| `500` | Unexpected internal failure; only a generic message is returned. |

Every request requires an allowed `Host`. API requests with `Origin` must also match an allowed host and port. Cross-site browser requests are rejected; no general cross-origin access is provided. Native and command-line clients can omit Origin. Reverse proxies must preserve an explicitly allowed Host; forwarded host headers are not trusted.

`LLM_TIMEOUT_MS` is the total upstream time budget shared by editing, any explicitly enabled review/repair, and format retries. Another call does not restart the timer. The default editing-only flow allows at most two calls; optional reviewed operations allow at most four calls. An invalid structured response can use an available retry within that shared deadline and call budget; HTTP failures are not generally retried. The browser aborts at about 195 seconds, and the native client has request/resource limits around 190/195 seconds.

Closing or cancelling the client request propagates an abort to the upstream request. It does not guarantee that the provider stops processing or refunds usage. Request-body and header receive timeouts are separate from model execution. No prompt content or raw provider errors are written to server logs.

For setup failures and status examples, see [Troubleshooting](troubleshooting.md). Model compatibility and available identifiers are determined by your provider; see [model configuration](../README.md#model-configuration).
