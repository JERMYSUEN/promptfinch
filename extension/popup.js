const CUSTOM_MODEL = '__custom__';
const PRESET_DEFAULTS = {
  deepseek: {
    baseUrl: 'https://api.deepseek.com',
    model: 'deepseek-flash',
    models: [
      { id: 'deepseek-flash', label: 'deepseek-flash — DeepSeek-V4.1-Flash (Fast)', note: 'DeepSeek-V4.1-Flash (1M context, fast default).' },
      { id: 'deepseek-v4-pro', label: 'deepseek-v4-pro — DeepSeek-V4-Pro (Flagship)', note: 'DeepSeek-V4-Pro (1M context, complex prompts).' },
      { id: 'deepseek-chat', label: 'deepseek-chat — DeepSeek Chat (V3 alias)', note: 'DeepSeek general chat alias.' },
      { id: 'deepseek-reasoner', label: 'deepseek-reasoner — DeepSeek Reasoner', note: 'DeepSeek chain-of-thought reasoning model.' },
    ],
  },
  openai: {
    baseUrl: 'https://api.openai.com/v1',
    model: 'gpt-4.1-mini',
    models: [
      { id: 'gpt-4.1-mini', label: 'gpt-4.1-mini — GPT-4.1 Mini (Fast)', note: 'Fast and cost-effective for prompt refinement.' },
      { id: 'gpt-4.1', label: 'gpt-4.1 — GPT-4.1 (Precision)', note: 'Strong instruction following and long context.' },
      { id: 'gpt-4.1-nano', label: 'gpt-4.1-nano — GPT-4.1 Nano (Ultra-fast)', note: 'Lowest-latency lightweight model.' },
      { id: 'gpt-5-mini', label: 'gpt-5-mini — GPT-5 Mini', note: 'Lightweight GPT-5 reasoning model.' },
      { id: 'gpt-5', label: 'gpt-5 — GPT-5 (Flagship)', note: 'Unified flagship GPT-5 model.' },
      { id: 'gpt-4o-mini', label: 'gpt-4o-mini — GPT-4o Mini', note: 'Classic lightweight multimodal model.' },
    ],
  },
  anthropic: {
    baseUrl: 'https://api.anthropic.com/v1',
    model: 'claude-haiku-4-5',
    models: [
      { id: 'claude-haiku-4-5', label: 'claude-haiku-4-5 — Claude Haiku 4.5 (Fast)', note: 'Fastest Claude with prompt caching.' },
      { id: 'claude-sonnet-4-5', label: 'claude-sonnet-4-5 — Claude Sonnet 4.5', note: 'Balanced quality and speed.' },
      { id: 'claude-haiku-5-5', label: 'claude-haiku-5-5 — Claude Haiku 5.5', note: 'Next-gen low-latency Claude.' },
      { id: 'claude-sonnet-5-5', label: 'claude-sonnet-5-5 — Claude Sonnet 5.5', note: 'Next-gen balanced Claude.' },
      { id: 'claude-opus-5-5', label: 'claude-opus-5-5 — Claude Opus 5.5', note: 'Flagship deep reasoning Claude.' },
    ],
  },
  gemini: {
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
    model: 'gemini-2.5-flash-lite',
    models: [
      { id: 'gemini-2.5-flash-lite', label: 'gemini-2.5-flash-lite — Flash-Lite', note: 'Ultra-low latency & cost-efficient.' },
      { id: 'gemini-2.5-flash', label: 'gemini-2.5-flash — Gemini 2.5 Flash', note: 'Stable fast general model.' },
      { id: 'gemini-2.5-pro', label: 'gemini-2.5-pro — Gemini 2.5 Pro', note: 'Advanced coding and reasoning.' },
      { id: 'gemini-3.5-flash-lite', label: 'gemini-3.5-flash-lite — 3.5 Flash-Lite', note: 'Next-gen lightweight high-throughput model.' },
      { id: 'gemini-3.6-flash', label: 'gemini-3.6-flash — Gemini 3.6 Flash', note: 'Next-gen balanced fast model.' },
    ],
  },
  ollama: {
    baseUrl: 'http://127.0.0.1:11434/v1',
    model: 'qwen2.5:7b',
    models: [
      { id: 'qwen2.5:7b', label: 'qwen2.5:7b — Qwen 2.5 7B (Local)', note: 'Strong bilingual offline local model.' },
      { id: 'qwen2.5:14b', label: 'qwen2.5:14b — Qwen 2.5 14B (Local)', note: 'Higher fidelity offline local model.' },
      { id: 'llama3.2:latest', label: 'llama3.2:latest — Llama 3.2 (Local)', note: 'Fast general local model.' },
      { id: 'deepseek-r1:8b', label: 'deepseek-r1:8b — DeepSeek-R1 8B', note: 'Local reasoning model.' },
      { id: 'gemma3:4b', label: 'gemma3:4b — Gemma 3 4B (Local)', note: 'Compact low-RAM local model.' },
    ],
  },
  local: {
    baseUrl: 'http://127.0.0.1:3210',
    model: 'local-backend',
    models: [
      { id: 'local-backend', label: 'local-backend — Configured Server Model', note: 'Uses the model configured on your local PromptFinch server.' },
    ],
  },
};
const fetchedByPreset = {};

const $ = id => document.getElementById(id);

function mergedModels(presetId) {
  const curated = PRESET_DEFAULTS[presetId]?.models || [];
  const fetched = fetchedByPreset[presetId] || [];
  const seen = new Set(curated.map(item => item.id));
  const out = [...curated];
  for (const item of fetched) {
    if (!item?.id || seen.has(item.id)) continue;
    seen.add(item.id);
    out.push({ id: item.id, label: item.label && item.label !== item.id ? `${item.id} — ${item.label}` : item.id, note: '' });
  }
  return out;
}

function renderModelOptions() {
  const select = $('model-preset');
  const input = $('model');
  const hint = $('model-hint');
  if (!select || !input) return;
  const presetId = $('preset').value;
  const list = mergedModels(presetId);
  const current = input.value.trim();
  select.replaceChildren();
  for (const item of list) {
    const opt = document.createElement('option');
    opt.value = item.id;
    opt.textContent = item.label;
    select.appendChild(opt);
  }
  const customOpt = document.createElement('option');
  customOpt.value = CUSTOM_MODEL;
  customOpt.textContent = 'Custom model ID…';
  select.appendChild(customOpt);
  const match = list.find(item => item.id === current);
  select.value = match ? match.id : CUSTOM_MODEL;
  if (hint) hint.textContent = match?.note || 'Pick a version above, click Fetch, or type any model ID.';
}

function setStatus(text, isError = false) {
  const el = $('status');
  el.textContent = text;
  el.className = isError ? 'status err' : 'status';
}

function collectSettings() {
  return {
    preset: $('preset').value,
    baseUrl: $('base-url').value.trim(),
    model: $('model').value.trim(),
    apiKey: $('api-key').value.trim(),
    redactSecrets: $('redact-secrets').checked,
    task: $('task').value,
    style: $('style').value,
    promptLanguage: $('prompt-language').value,
  };
}

async function loadState() {
  const stored = await chrome.storage.local.get({
    preset: 'deepseek',
    baseUrl: PRESET_DEFAULTS.deepseek.baseUrl,
    model: PRESET_DEFAULTS.deepseek.model,
    apiKey: '',
    redactSecrets: false,
    task: 'general',
    style: 'balanced',
    promptLanguage: 'en',
  });
  $('preset').value = stored.preset;
  $('base-url').value = stored.baseUrl;
  $('model').value = stored.model;
  $('api-key').value = stored.apiKey;
  $('redact-secrets').checked = Boolean(stored.redactSecrets);
  $('task').value = stored.task;
  $('style').value = stored.style;
  $('prompt-language').value = stored.promptLanguage;
  renderModelOptions();
}

$('preset').addEventListener('change', () => {
  const defaults = PRESET_DEFAULTS[$('preset').value];
  if (defaults) {
    $('base-url').value = defaults.baseUrl;
    $('model').value = defaults.model;
  }
  renderModelOptions();
});

$('model-preset').addEventListener('change', () => {
  if ($('model-preset').value !== CUSTOM_MODEL) {
    $('model').value = $('model-preset').value;
  } else {
    $('model').focus();
  }
  renderModelOptions();
});

$('model').addEventListener('input', renderModelOptions);

$('fetch-models').addEventListener('click', () => {
  const settings = collectSettings();
  $('fetch-models').disabled = true;
  setStatus('Fetching available models…');
  chrome.runtime.sendMessage({ type: 'PROMPTFINCH_LIST_MODELS', settings }, res => {
    $('fetch-models').disabled = false;
    if (chrome.runtime.lastError || !res?.ok) {
      setStatus(res?.error || chrome.runtime.lastError?.message || 'Could not fetch models.', true);
      return;
    }
    fetchedByPreset[settings.preset] = Array.isArray(res.models) ? res.models : [];
    if (!$('model').value.trim() && fetchedByPreset[settings.preset][0]?.id) {
      $('model').value = fetchedByPreset[settings.preset][0].id;
    }
    renderModelOptions();
    setStatus(`Loaded ${fetchedByPreset[settings.preset].length} available models.`);
  });
});

$('toggle-settings').addEventListener('click', () => {
  $('settings-view').hidden = !$('settings-view').hidden;
});

$('save-settings').addEventListener('click', async () => {
  await chrome.storage.local.set(collectSettings());
  setStatus('Settings saved locally.');
  $('settings-view').hidden = true;
});

$('test-settings').addEventListener('click', async () => {
  const settings = collectSettings();
  await chrome.storage.local.set(settings);
  setStatus('Testing provider connection…');
  chrome.runtime.sendMessage({ type: 'PROMPTFINCH_TEST', settings }, res => {
    if (chrome.runtime.lastError || !res?.ok) {
      setStatus(res?.error || chrome.runtime.lastError?.message || 'Connection failed.', true);
      return;
    }
    setStatus(`${res.model} · OK (${res.latencyMs}ms)`);
  });
});

$('refine').addEventListener('click', async () => {
  const prompt = $('input').value.trim();
  if (!prompt) {
    setStatus('Enter a prompt to refine first.', true);
    return;
  }
  const settings = collectSettings();
  await chrome.storage.local.set({ task: settings.task, style: settings.style, promptLanguage: settings.promptLanguage });
  $('refine').disabled = true;
  setStatus('Refining prompt…');
  chrome.runtime.sendMessage({
    type: 'PROMPTFINCH_OPTIMIZE',
    settings,
    payload: {
      prompt,
      task: settings.task,
      style: settings.style,
      promptLanguage: settings.promptLanguage,
      redactSecrets: settings.redactSecrets,
    },
  }, res => {
    $('refine').disabled = false;
    if (chrome.runtime.lastError || !res?.ok) {
      setStatus(res?.error || chrome.runtime.lastError?.message || 'Optimization failed.', true);
      return;
    }
    $('output').value = res.result.prompt;
    $('result-wrap').hidden = false;
    const allNotes = [...(res.result.improvements || []), ...(res.result.assumptions || [])];
    if (allNotes.length > 0) {
      $('notes-summary').textContent = `✦ ${allNotes.length} editing notes`;
      $('notes-list').replaceChildren(...allNotes.map(item => {
        const li = document.createElement('li');
        li.textContent = item;
        return li;
      }));
      $('notes').hidden = false;
    } else {
      $('notes').hidden = true;
    }
    setStatus(`Ready · ${res.result.model || settings.model}`);
  });
});

$('copy').addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText($('output').value);
    setStatus('Copied prompt to clipboard.');
  } catch {
    setStatus('Copy failed.', true);
  }
});

$('clear').addEventListener('click', () => {
  $('input').value = '';
  $('output').value = '';
  $('result-wrap').hidden = true;
  $('notes').hidden = true;
  setStatus('');
});

void loadState();
