const PRESETS = Object.freeze({
  deepseek: { protocol: 'openai', baseUrl: 'https://api.deepseek.com', model: 'deepseek-flash' },
  openai: { protocol: 'openai', baseUrl: 'https://api.openai.com/v1', model: 'gpt-4.1-mini' },
  anthropic: { protocol: 'anthropic', baseUrl: 'https://api.anthropic.com/v1', model: 'claude-haiku-4-5' },
  gemini: { protocol: 'gemini', baseUrl: 'https://generativelanguage.googleapis.com/v1beta', model: 'gemini-2.5-flash-lite' },
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
    style: 'balanced',
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
  const style = ['balanced', 'concise', 'structured'].includes(payload.style || settings.style) ? (payload.style || settings.style) : 'balanced';
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
        style,
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
  const styleLine = style === 'concise'
    ? 'Style: concise (tight wording, preserve all constraints and literals, drop filler).\n'
    : style === 'structured'
      ? 'Style: structured (clear scannable sections or numbered steps without inventing requirements).\n'
      : '';
  const userMessage = `Task category: ${task}\n${styleLine}${payload.targetModel ? `Target model: ${payload.targetModel}\n` : ''}\nOriginal request:\n${redaction.masked}`;

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

async function fetchModels(settings) {
  const presetInfo = PRESETS[settings.preset] || PRESETS.deepseek;
  const protocol = presetInfo.protocol;
  const baseUrl = String(settings.baseUrl || presetInfo.baseUrl).replace(/\/+$/, '');
  const apiKey = String(settings.apiKey || '').trim();
  if (protocol === 'local') {
    const res = await fetch(`${baseUrl}/api/models`, { method: 'GET' });
    const data = await res.json();
    if (!res.ok) throw new Error(data?.error || `Local backend error (${res.status})`);
    return Array.isArray(data?.models) ? data.models : [];
  }
  if (settings.preset !== 'ollama' && !apiKey) {
    throw new Error('Enter your API key first to fetch available models.');
  }
  let endpoint;
  let headers = {};
  if (protocol === 'anthropic') {
    endpoint = baseUrl.endsWith('/v1') ? `${baseUrl}/models` : `${baseUrl}/v1/models`;
    headers = {
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
      'anthropic-dangerous-direct-browser-access': 'true',
    };
  } else if (protocol === 'gemini') {
    const root = baseUrl.endsWith('/v1beta') ? baseUrl : `${baseUrl}/v1beta`;
    endpoint = `${root}/models`;
    headers = { 'x-goog-api-key': apiKey };
  } else {
    endpoint = `${baseUrl}/models`;
    if (apiKey) headers.Authorization = `Bearer ${apiKey}`;
  }
  const res = await fetch(endpoint, { method: 'GET', headers });
  const data = await res.json();
  if (!res.ok) throw new Error(data?.error?.message || `Failed to fetch models (${res.status})`);
  const seen = new Set();
  const models = [];
  const add = (id, label = '') => {
    const clean = String(id || '').trim();
    if (!clean || seen.has(clean)) return;
    seen.add(clean);
    const title = String(label || '').trim();
    models.push({ id: clean, label: title && title !== clean ? title : clean });
  };
  if (protocol === 'gemini' && Array.isArray(data?.models)) {
    for (const item of data.models) {
      const methods = Array.isArray(item?.supportedGenerationMethods) ? item.supportedGenerationMethods : [];
      if (methods.length && !methods.includes('generateContent')) continue;
      add(String(item?.name || '').replace(/^models\//, ''), item?.displayName || '');
    }
  } else if (Array.isArray(data?.data)) {
    for (const item of data.data) add(item?.id, item?.display_name || item?.name || '');
  } else if (Array.isArray(data?.models)) {
    for (const item of data.models) add(item?.name || item?.id, item?.displayName || '');
  }
  return models.sort((a, b) => a.id.localeCompare(b.id)).slice(0, 200);
}

if (typeof chrome !== 'undefined' && chrome.runtime?.onMessage) {
  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (!message || typeof message !== 'object') return false;
    if (message.type === 'PROMPTFINCH_LIST_MODELS') {
      readSettings()
        .then(settings => fetchModels({ ...settings, ...(message.settings || {}) }))
        .then(models => sendResponse({ ok: true, models }))
        .catch(error => sendResponse({ ok: false, error: error?.message || 'Could not load models.' }));
      return true;
    }
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
