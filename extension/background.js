const PRESETS = Object.freeze({
  deepseek: { protocol: 'openai', baseUrl: 'https://api.deepseek.com', model: 'deepseek-chat' },
  openai: { protocol: 'openai', baseUrl: 'https://api.openai.com', model: 'gpt-4.1-mini' },
  anthropic: { protocol: 'anthropic', baseUrl: 'https://api.anthropic.com', model: 'claude-3-5-haiku-latest' },
  gemini: { protocol: 'gemini', baseUrl: 'https://generativelanguage.googleapis.com', model: 'gemini-2.5-flash' },
  ollama: { protocol: 'openai', baseUrl: 'http://127.0.0.1:11434/v1', model: 'qwen2.5:7b' },
  local: { protocol: 'local', baseUrl: 'http://127.0.0.1:3210', model: 'local-backend' },
});

const SECRET_RULES = [
  { label: 'PEM', regex: /-----BEGIN [A-Z0-9 ]+ PRIVATE KEY-----[\s\S]*?-----END [A-Z0-9 ]+ PRIVATE KEY-----/g },
  { label: 'KEY', regex: /\bsk-(?:proj-|ant-[a-z0-9_-]+-)?[A-Za-z0-9_-]{16,}\b/g },
  { label: 'GH_TOKEN', regex: /\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}\b/g },
  { label: 'AWS_KEY', regex: /\b(?:AKIA|ASIA)[0-9A-Z]{16}\b/g },
  { label: 'GOOGLE_KEY', regex: /\bAIza[0-9A-Za-z_-]{30,}\b/g },
  { label: 'JWT', regex: /\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/g },
];

export function redactSecrets(text) {
  let masked = String(text || '');
  const tokens = [];
  for (const { label, regex } of SECRET_RULES) {
    regex.lastIndex = 0;
    masked = masked.replace(regex, match => {
      const token = `[[PF_REDACTED_${label}_${tokens.length + 1}]]`;
      tokens.push([token, match]);
      return token;
    });
  }
  return { masked, tokens };
}

export function restoreSecrets(text, tokens) {
  let output = String(text || '');
  for (const [token, original] of tokens || []) {
    output = output.split(token).join(original);
  }
  return output;
}

function buildSystemPrompt(promptLanguage) {
  if (promptLanguage === 'zh-Hant') {
    return [
      '你是精準的 Prompt 編輯器（不是任務執行器）。',
      '將使用者的原始需求整理為清晰、結構完整且可直接貼上的繁體中文 Prompt。',
      '嚴格保留所有具體事實、ID、程式碼識別字、路徑、數字與指定輸出語言，不可捏造需求或執行任務。',
      '僅輸出 JSON：{"prompt":"...","improvements":["..."],"assumptions":["..."]}。',
    ].join('\n');
  }
  return [
    'You are a precision prompt editor, never a task executor.',
    'Rewrite the user request into a clear, faithful, copy-ready English prompt.',
    'Preserve every literal identifier, URL, code snippet, constraint, and requested downstream answer language without adding invented requirements.',
    'Return strict JSON only: {"prompt":"...","improvements":["..."],"assumptions":["..."]}.',
  ].join('\n');
}

function parseModelJson(raw) {
  let text = String(raw || '').trim();
  const fenced = text.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
  if (fenced) text = fenced[1].trim();
  const parsed = JSON.parse(text);
  if (!parsed || typeof parsed.prompt !== 'string' || !parsed.prompt.trim()) {
    throw new Error('Model returned invalid prompt JSON.');
  }
  return {
    prompt: parsed.prompt.trim(),
    improvements: Array.isArray(parsed.improvements) ? parsed.improvements.map(String).filter(Boolean).slice(0, 6) : [],
    assumptions: Array.isArray(parsed.assumptions) ? parsed.assumptions.map(String).filter(Boolean).slice(0, 6) : [],
  };
}

async function readSettings() {
  const stored = await chrome.storage.local.get({
    preset: 'deepseek',
    baseUrl: PRESETS.deepseek.baseUrl,
    model: PRESETS.deepseek.model,
    apiKey: '',
    promptLanguage: 'en',
    task: 'general',
    redactSecrets: false,
  });
  return stored;
}

async function callProvider(settings, payload) {
  const presetInfo = PRESETS[settings.preset] || PRESETS.deepseek;
  const protocol = presetInfo.protocol;
  const baseUrl = String(settings.baseUrl || presetInfo.baseUrl).replace(/\/+$/, '');
  const model = String(settings.model || presetInfo.model).trim();
  const apiKey = String(settings.apiKey || '').trim();
  const task = payload.task || settings.task || 'general';
  const promptLanguage = payload.promptLanguage || settings.promptLanguage || 'en';
  const useRedaction = Boolean(payload.redactSecrets ?? settings.redactSecrets);

  const original = String(payload.prompt || '').trim();
  if (!original) throw new Error('Enter or select a prompt first.');
  if (original.length > 12000) throw new Error('Prompt exceeds 12,000 characters.');

  if (protocol === 'local') {
    const res = await fetch(`${baseUrl}/api/optimize`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        prompt: original,
        task,
        targetModel: payload.targetModel || '',
        promptLanguage,
        notesLanguage: 'zh-TW',
        redactSecrets: useRedaction,
      }),
    });
    const body = await res.json();
    if (!res.ok) throw new Error(body?.error || `Local backend error (${res.status})`);
    return {
      prompt: body.prompt,
      improvements: body.improvements || [],
      assumptions: body.assumptions || [],
      model: body.generationModel || body.mode || 'local',
    };
  }

  if (settings.preset !== 'ollama' && !apiKey) {
    throw new Error('Configure an API key in the PromptFinch extension popup first.');
  }

  const redaction = useRedaction ? redactSecrets(original) : { masked: original, tokens: [] };
  const systemPrompt = buildSystemPrompt(promptLanguage);
  const userMessage = `Task category: ${task}\n${payload.targetModel ? `Target model: ${payload.targetModel}\n` : ''}\nOriginal request:\n${redaction.masked}`;

  let rawText = '';
  if (protocol === 'anthropic') {
    const endpoint = baseUrl.endsWith('/v1') ? `${baseUrl}/messages` : `${baseUrl}/v1/messages`;
    const res = await fetch(endpoint, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'anthropic-dangerous-direct-browser-access': 'true',
      },
      body: JSON.stringify({
        model,
        max_tokens: 1800,
        temperature: 0.2,
        system: [{ type: 'text', text: systemPrompt, cache_control: { type: 'ephemeral' } }],
        messages: [{ role: 'user', content: userMessage }],
      }),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data?.error?.message || `Anthropic error (${res.status})`);
    rawText = (data.content || []).filter(b => b.type === 'text').map(b => b.text).join('');
  } else if (protocol === 'gemini') {
    const root = baseUrl.endsWith('/v1beta') ? baseUrl : `${baseUrl}/v1beta`;
    const endpoint = `${root}/models/${encodeURIComponent(model)}:generateContent`;
    const res = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-goog-api-key': apiKey },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: systemPrompt }] },
        contents: [{ role: 'user', parts: [{ text: userMessage }] }],
        generationConfig: { temperature: 0.2, responseMimeType: 'application/json' },
      }),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data?.error?.message || `Gemini error (${res.status})`);
    rawText = (data.candidates?.[0]?.content?.parts || []).map(p => p.text || '').join('');
  } else {
    const endpoint = baseUrl.endsWith('/chat/completions')
      ? baseUrl
      : baseUrl.endsWith('/v1')
        ? `${baseUrl}/chat/completions`
        : `${baseUrl}/v1/chat/completions`;
    const headers = { 'Content-Type': 'application/json' };
    if (apiKey) headers.Authorization = `Bearer ${apiKey}`;
    const res = await fetch(endpoint, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        model,
        temperature: 0.2,
        response_format: { type: 'json_object' },
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: userMessage },
        ],
      }),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data?.error?.message || `Provider error (${res.status})`);
    rawText = data.choices?.[0]?.message?.content || '';
  }

  const parsed = parseModelJson(rawText);
  return {
    prompt: redaction.tokens.length ? restoreSecrets(parsed.prompt, redaction.tokens) : parsed.prompt,
    improvements: parsed.improvements,
    assumptions: parsed.assumptions,
    model,
  };
}

if (typeof chrome !== 'undefined' && chrome.runtime?.onMessage) {
  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (!message || typeof message !== 'object') return false;
    if (message.type === 'PROMPTFINCH_OPTIMIZE') {
      readSettings()
        .then(settings => callProvider({ ...settings, ...(message.settings || {}) }, message.payload || {}))
        .then(result => sendResponse({ ok: true, result }))
        .catch(error => sendResponse({ ok: false, error: error?.message || 'Optimization failed.' }));
      return true;
    }
    if (message.type === 'PROMPTFINCH_TEST') {
      const started = Date.now();
      readSettings()
        .then(settings => callProvider({ ...settings, ...(message.settings || {}) }, {
          prompt: 'Summarize Q4 metrics in 3 bullets.',
          task: 'general',
          promptLanguage: 'en',
        }))
        .then(result => sendResponse({ ok: true, latencyMs: Date.now() - started, model: result.model }))
        .catch(error => sendResponse({ ok: false, error: error?.message || 'Connection failed.' }));
      return true;
    }
    return false;
  });
}
