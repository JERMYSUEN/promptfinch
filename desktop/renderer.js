import { LANGUAGES, translate } from './locales.js';

const $ = id => document.getElementById(id);
const api = window.promptfinch;
const companion = new URL(location.href).searchParams.get('window') === 'companion';
let state = { language: 'zh-TW', mode: 'mock', ready: false, busy: false };
let result = null;
let resultInput = '';
let statusKey = '';
let statusKind = '';
let lastError = null;
let submitting = false;
let clearing = false;
let generationToken = 0;
const t = (key, values) => translate(state.language, key, values);

document.body.classList.toggle('companion', companion);
$('companion-menu').hidden = !companion;

const CUSTOM_MODEL_VALUE = '__custom__';
const PRESET_DEFAULTS = {
  deepseek: {
    baseUrl: 'https://api.deepseek.com',
    model: 'deepseek-flash',
    models: [
      { id: 'deepseek-flash', label: 'deepseek-flash — DeepSeek-V4.1-Flash (快速・推薦)', note: 'DeepSeek-V4.1-Flash 官方高速版（1M 上下文，支援非思考／思考模式）。' },
      { id: 'deepseek-v4-pro', label: 'deepseek-v4-pro — DeepSeek-V4-Pro (旗艦進階)', note: 'DeepSeek-V4-Pro 進階旗艦版（1M 上下文，適合複雜長指令）。' },
      { id: 'deepseek-chat', label: 'deepseek-chat — DeepSeek Chat (V3 相容)', note: 'DeepSeek 通用對話別名（相容舊版 V3 介面）。' },
      { id: 'deepseek-reasoner', label: 'deepseek-reasoner — DeepSeek Reasoner (深度推理)', note: 'DeepSeek 深度推理模型（鏈式思考專用，回應時間較長）。' },
    ],
  },
  openai: {
    baseUrl: 'https://api.openai.com/v1',
    model: 'gpt-4.1-mini',
    models: [
      { id: 'gpt-4.1-mini', label: 'gpt-4.1-mini — GPT-4.1 Mini (快速・推薦)', note: '高速高性價比，適合日常即時 Prompt 潤飾。' },
      { id: 'gpt-4.1', label: 'gpt-4.1 — GPT-4.1 (精準指令遵循)', note: '強化長上下文與精細規格遵守。' },
      { id: 'gpt-4.1-nano', label: 'gpt-4.1-nano — GPT-4.1 Nano (極速輕量)', note: '最低延遲與成本的輕量版本。' },
      { id: 'gpt-5-mini', label: 'gpt-5-mini — GPT-5 Mini (輕量推理)', note: 'GPT-5 輕量版，兼顧速度與推理解析。' },
      { id: 'gpt-5', label: 'gpt-5 — GPT-5 (旗艦統一模型)', note: 'GPT-5 旗艦模型，處理複雜多步驟需求。' },
      { id: 'gpt-4o-mini', label: 'gpt-4o-mini — GPT-4o Mini (經典輕量)', note: '經典低延遲輕量模型。' },
    ],
  },
  anthropic: {
    baseUrl: 'https://api.anthropic.com/v1',
    model: 'claude-haiku-4-5',
    models: [
      { id: 'claude-haiku-4-5', label: 'claude-haiku-4-5 — Claude Haiku 4.5 (極速・推薦)', note: '支援 Prompt 快取，速度最快且保留原文細節精準。' },
      { id: 'claude-sonnet-4-5', label: 'claude-sonnet-4-5 — Claude Sonnet 4.5 (均衡品質)', note: '寫作與程式指令潤飾的均衡主力。' },
      { id: 'claude-haiku-5-5', label: 'claude-haiku-5-5 — Claude Haiku 5.5 (新一代極速)', note: '新一代高吞吐低延遲版本。' },
      { id: 'claude-sonnet-5-5', label: 'claude-sonnet-5-5 — Claude Sonnet 5.5 (新一代均衡)', note: '新一代速度與深度的最佳平衡。' },
      { id: 'claude-opus-5-5', label: 'claude-opus-5-5 — Claude Opus 5.5 (旗艦深度)', note: '最高階複雜規格與長篇任務專用。' },
    ],
  },
  gemini: {
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
    model: 'gemini-2.5-flash-lite',
    models: [
      { id: 'gemini-2.5-flash-lite', label: 'gemini-2.5-flash-lite — Gemini 2.5 Flash-Lite (低延遲)', note: '輕量高速且成本極低，適合即時潤飾。' },
      { id: 'gemini-2.5-flash', label: 'gemini-2.5-flash — Gemini 2.5 Flash (穩定高速)', note: '穩定通用版本，支援原生 JSON 輸出。' },
      { id: 'gemini-2.5-pro', label: 'gemini-2.5-pro — Gemini 2.5 Pro (進階推理)', note: '高複雜度分析與程式任務適用。' },
      { id: 'gemini-3.5-flash-lite', label: 'gemini-3.5-flash-lite — Gemini 3.5 Flash-Lite (新一代輕量)', note: '新一代高吞吐輕量版本。' },
      { id: 'gemini-3.6-flash', label: 'gemini-3.6-flash — Gemini 3.6 Flash (新一代均衡)', note: '新一代速度與理解力均衡版。' },
    ],
  },
  ollama: {
    baseUrl: 'http://127.0.0.1:11434/v1',
    model: 'qwen2.5:7b',
    models: [
      { id: 'qwen2.5:7b', label: 'qwen2.5:7b — Qwen 2.5 7B (中英俱佳・預設)', note: '離線本機執行，中文與英文指令結構表現均衡。' },
      { id: 'qwen2.5:14b', label: 'qwen2.5:14b — Qwen 2.5 14B (更高品質)', note: '離線本機執行，複雜條件與細節保留更佳。' },
      { id: 'llama3.2:latest', label: 'llama3.2:latest — Llama 3.2 (輕量快速)', note: '輕量快速通用本機模型。' },
      { id: 'deepseek-r1:8b', label: 'deepseek-r1:8b — DeepSeek-R1 8B (本機推理)', note: '本機輕量推理模型。' },
      { id: 'gemma3:4b', label: 'gemma3:4b — Gemma 3 4B (極輕量)', note: '低記憶體佔用的輕巧本機模型。' },
    ],
  },
  custom: { baseUrl: 'https://api.openai.com/v1', model: '', models: [] },
};
let fetchedModelsByPreset = {};
let statusValues = {};

function mergedModelsForPreset(presetId) {
  const curated = PRESET_DEFAULTS[presetId]?.models || [];
  const fetched = fetchedModelsByPreset[presetId] || [];
  const seen = new Set(curated.map(item => item.id));
  const combined = [...curated];
  for (const item of fetched) {
    if (!item?.id || seen.has(item.id)) continue;
    seen.add(item.id);
    combined.push({ id: item.id, label: item.label && item.label !== item.id ? `${item.id} — ${item.label}` : item.id, note: '' });
  }
  return combined;
}

function renderProviderModels() {
  const select = $('provider-model-preset');
  const input = $('provider-model');
  const hint = $('provider-model-hint');
  if (!select || !input) return;
  const presetId = $('provider-preset')?.value || 'deepseek';
  const options = mergedModelsForPreset(presetId);
  const current = input.value.trim();
  select.replaceChildren();
  for (const item of options) {
    const opt = document.createElement('option');
    opt.value = item.id;
    opt.textContent = item.label;
    select.appendChild(opt);
  }
  const customOpt = document.createElement('option');
  customOpt.value = CUSTOM_MODEL_VALUE;
  customOpt.textContent = t('customModelOption');
  select.appendChild(customOpt);
  const matched = options.find(item => item.id === current);
  select.value = matched ? matched.id : CUSTOM_MODEL_VALUE;
  if (hint) hint.textContent = matched?.note || t('customModelHint');
}

function inputValue() {
  return {
    prompt: $('original-prompt').value,
    task: $('task-select').value,
    style: $('style-select')?.value || 'balanced',
    targetModel: $('target-model').value,
    redactSecrets: Boolean($('redact-secrets')?.checked),
  };
}

function setStatus(key, kind = '', values = {}) {
  statusKey = key;
  statusKind = kind;
  statusValues = values;
  lastError = null;
  renderStatus();
}

function errorText(error) {
  const code = String(error?.code || '').toUpperCase();
  if (/ABORT|CANCEL/.test(code)) return t('cancelled');
  if (/BUSY/.test(code)) return t('errorBusy');
  if (/TIMEOUT/.test(code)) return t('errorTimeout');
  if (code === 'INPUT_TOO_LONG') return t('lengthError');
  if (/CLIPBOARD/.test(code)) return t('errorClipboard');
  if (/SELECT|CAPTURE|STALE|UNSUPPORTED/.test(code)) return t('errorSelection');
  if (/CONFIG|SETTINGS|TEMPLATE/.test(code)) return t('errorConfig');
  if (/NO_RESULT/.test(code)) return t('errorNoResult');
  if (/MODEL|PROVIDER|UPSTREAM|NETWORK|AUTH|RATE_LIMIT/.test(code)) return t('errorModel');
  if (/TRANSPORT|IPC|CONNECTION|CLOSED|ACCESS_DENIED/.test(code)) return t('connectionError');
  // The main process exposes only bounded, safe error messages; provider strings
  // and exception stacks must never cross the preload boundary.
  return typeof error?.message === 'string' && error.message.trim()
    ? error.message.slice(0, 500) : t('genericError');
}

function renderStatus() {
  const target = companion ? $('companion-status') : $('action-status');
  target.textContent = lastError ? errorText(lastError) : (statusKey ? t(statusKey, statusValues) : '');
  if (!companion) target.className = `action-status ${lastError ? 'error' : statusKind}`;
}

function showError(error) {
  lastError = error;
  statusKey = '';
  renderStatus();
}

async function call(method, value, { silent = false } = {}) {
  try {
    if (!api || typeof api[method] !== 'function') throw new Error('bridge unavailable');
    const reply = await api[method](value);
    if (!reply || typeof reply.ok !== 'boolean') throw new Error('invalid bridge response');
    if (!reply.ok && !silent) showError(reply.error);
    return reply;
  } catch {
    const error = { code: 'TRANSPORT_UNAVAILABLE' };
    if (!silent) showError(error);
    return { ok: false, error };
  }
}

function updateCount() {
  $('character-count').textContent = `${$('original-prompt').value.length.toLocaleString('en-US')} / 12,000`;
}

function resultIsStale() {
  return Boolean(result) && resultInput !== JSON.stringify(inputValue());
}

function renderResultLabels() {
  if (!result) return;
  $('result-tag').textContent = t(resultIsStale() ? 'staleTag' : result.mode === 'mock' ? 'mockTag' : 'liveTag');
  $('result-source').textContent = t(result.mode === 'mock' ? 'mockSource' : 'liveSource', { model: result.generationModel || state.model || '' });
  const notesLanguage = LANGUAGES.includes(result.notesLanguage) ? result.notesLanguage : state.language;
  $('no-improvement').textContent = translate(notesLanguage, 'noImprovement');
}

function renderBusy() {
  const busy = Boolean(state.busy || submitting || clearing);
  for (const id of ['original-prompt', 'target-model', 'task-select', 'style-select', 'choose-config', 'create-config', 'save-provider-config', 'test-provider-connection', 'use-demo', 'import-clipboard', 'capture-selection']) {
    if ($(id)) $(id).disabled = busy;
  }
  $('capture-selection').disabled = busy || state.selectionSupport === 'clipboard-only';
  // Clicking this button would focus our own window before Windows UIA reads.
  // External Windows selections use the companion or global shortcut instead.
  $('capture-selection').hidden = state.selectionSupport === 'windows-uia';
  $('language-select').disabled = busy;
  $('generate-button').disabled = busy || !state.ready;
  $('generate-button').textContent = t(busy && !clearing ? 'working' : 'generate');
  $('cancel-button').hidden = !busy || clearing;
  $('cancel-button').disabled = clearing;
  $('clear-button').disabled = clearing;
  $('copy-button').disabled = busy || !result;
  document.querySelector('.output-pane').setAttribute('aria-busy', String(busy));
  $('empty-state').hidden = busy || Boolean(result);
  $('loading-state').hidden = !busy || clearing;
  $('result-state').hidden = busy || !result;
  $('explanation').hidden = busy || !result;
  $('comparison').hidden = busy || !result;
  $('result-tag').hidden = !result;
  $('companion-run').disabled = busy || !state.ready;
}

function renderState() {
  document.documentElement.lang = state.language;
  for (const element of document.querySelectorAll('[data-i18n]')) element.textContent = t(element.dataset.i18n);
  for (const element of document.querySelectorAll('[data-i18n-placeholder]')) element.placeholder = t(element.dataset.i18nPlaceholder);
  $('language-select').value = state.language;
  $('language-select').setAttribute('aria-label', t('language'));
  const miniButton = $('mini-mode-button');
  if (miniButton) {
    const isMini = Boolean(state.miniMode);
    document.body.classList.toggle('mini-mode', isMini);
    miniButton.textContent = t(isMini ? 'fullMode' : 'miniMode');
    miniButton.setAttribute('aria-pressed', String(isMini));
  }
  const live = state.mode === 'live';
  const badgeKey = !state.ready ? 'modeUnavailable' : live ? 'modeLive' : 'modeMock';
  $('mode-badge').textContent = t(badgeKey, { model: state.model || '' });
  $('mode-badge').className = `mode-badge ${live ? 'live' : 'mock'}`;
  $('mode-notice').textContent = t(!state.ready ? 'unavailableNotice' : live ? 'liveNotice' : 'mockNotice');
  $('mode-notice').className = `mode-notice ${!state.ready ? 'error' : live ? '' : 'mock'}`;
  $('config-name').textContent = state.configName ? t('configName', { name: state.configName }) : t('noConfig');
  $('selection-description').textContent = t(state.selectionSupport === 'windows-uia' ? 'selectionWindows' : state.selectionSupport === 'x11' ? 'selectionX11' : 'selectionClipboard');
  const watchKey = { running: 'watchRunning', unsupported: 'watchUnsupported', unavailable: 'watchUnavailable', disabled: 'watchDisabled' }[state.watchStatus] || 'watchUnavailable';
  const shortcutKey = { registered: 'shortcutRegistered', 'clipboard-only': 'shortcutClipboardOnly', unavailable: 'shortcutUnavailable', disabled: 'shortcutDisabled' }[state.shortcutStatus] || 'shortcutUnavailable';
  $('watch-status').textContent = t(watchKey);
  $('shortcut-status').textContent = t(shortcutKey);
  $('selection-preview').textContent = typeof state.selectionPreview === 'string' ? state.selectionPreview : '';
  $('selection-preview').setAttribute('aria-label', `${t('original')}: ${$('selection-preview').textContent}`);
  renderProviderModels();
  renderResultLabels();
  renderBusy();
  renderStatus();
  updateCount();
}

function fillList(id, values) {
  $(id).replaceChildren(...(Array.isArray(values) ? values : []).map(value => {
    const item = document.createElement('li');
    item.textContent = String(value);
    return item;
  }));
}

function renderComparison(source, output) {
  const before = source.split('\n'), after = output.split('\n');
  const oldView = $('comparison-source'), newView = $('comparison-result');
  if (before.length > 200 || after.length > 200) {
    oldView.textContent = source;
    newView.textContent = output;
    return;
  }
  const table = Array.from({ length: before.length + 1 }, () => new Uint16Array(after.length + 1));
  for (let i = before.length - 1; i >= 0; i--) {
    for (let j = after.length - 1; j >= 0; j--) table[i][j] = before[i] === after[j] ? table[i + 1][j + 1] + 1 : Math.max(table[i + 1][j], table[i][j + 1]);
  }
  const unchangedBefore = new Set(), unchangedAfter = new Set();
  let i = 0, j = 0;
  while (i < before.length && j < after.length) {
    if (before[i] === after[j]) { unchangedBefore.add(i++); unchangedAfter.add(j++); }
    else if (table[i + 1][j] >= table[i][j + 1]) i++;
    else j++;
  }
  for (const [container, lines, unchanged, added] of [[oldView, before, unchangedBefore, false], [newView, after, unchangedAfter, true]]) {
    container.replaceChildren(...lines.map((line, index) => {
      const node = document.createElement('span');
      node.className = unchanged.has(index) ? 'line-unchanged' : added ? 'line-added' : 'line-removed';
      node.textContent = `${unchanged.has(index) ? '  ' : added ? '+ ' : '− '}${line}${index < lines.length - 1 ? '\n' : ''}`;
      return node;
    }));
  }
}

function showResult(data) {
  if (clearing || !data || typeof data.prompt !== 'string') return;
  result = data;
  const source = typeof data.sourcePrompt === 'string' ? data.sourcePrompt : $('original-prompt').value;
  // Companion results may arrive while another request is still in the editor.
  // Show the actual captured source so the comparison is never mislabelled.
  if (typeof data.sourcePrompt === 'string') $('original-prompt').value = source;
  if (['general', 'writing', 'analysis', 'coding', 'summary', 'marketing'].includes(data.sourceTask)) $('task-select').value = data.sourceTask;
  if (typeof data.sourceTargetModel === 'string') $('target-model').value = data.sourceTargetModel;
  resultInput = JSON.stringify(inputValue());
  $('optimized-prompt').value = data.prompt;
  fillList('improvements', data.improvements);
  const noImprovement = Array.isArray(data.improvements) && data.improvements.length === 0;
  $('improvements').hidden = noImprovement;
  $('no-improvement').hidden = !noImprovement;
  fillList('assumptions-list', data.assumptions);
  $('no-assumptions').hidden = Array.isArray(data.assumptions) && data.assumptions.length > 0;
  renderComparison(source, data.prompt);
  setStatus('completed');
  renderState();
}

function forgetResult() {
  result = null;
  resultInput = '';
  $('optimized-prompt').value = '';
  $('comparison-source').replaceChildren();
  $('comparison-result').replaceChildren();
  $('improvements').replaceChildren();
  $('improvements').hidden = true;
  $('no-improvement').hidden = true;
  $('no-improvement').textContent = '';
  $('assumptions-list').replaceChildren();
  $('comparison').open = false;
}

function showValidation(key, field = $('original-prompt')) {
  $('input-error').textContent = t(key);
  $('input-error').hidden = false;
  field.setAttribute('aria-invalid', 'true');
  field.focus();
}

function clearValidation() {
  $('input-error').hidden = true;
  $('original-prompt').removeAttribute('aria-invalid');
  $('target-model').removeAttribute('aria-invalid');
}

async function generate(event) {
  event?.preventDefault();
  if (state.busy || submitting || clearing || !state.ready) return;
  clearValidation();
  const input = inputValue();
  if (!input.prompt.trim()) return showValidation('emptyError');
  if (input.prompt.length > 12000) return showValidation('lengthError');
  if (input.targetModel.length > 80 || /[\r\n]/.test(input.targetModel)) return showValidation('targetError', $('target-model'));
  forgetResult();
  const token = ++generationToken;
  submitting = true;
  setStatus('working', 'neutral');
  renderBusy();
  const reply = await call('generate', input, { silent: true });
  if (token !== generationToken) return;
  if (!reply.ok) showError(reply.error);
  submitting = false;
  renderBusy();
}

async function clear() {
  generationToken++;
  submitting = false;
  clearing = true;
  renderBusy();
  const reply = await call('clear');
  if (reply.ok) {
    forgetResult();
    $('original-prompt').value = '';
    clearValidation();
    setStatus('cleared');
  }
  clearing = false;
  renderState();
  $('original-prompt').focus();
}

function inputChanged() {
  clearValidation();
  updateCount();
  renderResultLabels();
  setStatus(resultIsStale() ? 'stale' : '', 'neutral');
}

function registerEvents() {
  $('optimizer-form').addEventListener('submit', generate);
  $('clear-button').addEventListener('click', clear);
  $('cancel-button').addEventListener('click', async () => {
    const reply = await call('cancel');
    if (reply.ok) setStatus('cancelled', 'neutral');
  });
  $('copy-button').addEventListener('click', async () => {
    const reply = await call('copyResult');
    if (reply.ok) setStatus('copied');
  });
  for (const id of ['original-prompt', 'target-model', 'task-select', 'style-select']) $(id)?.addEventListener('input', inputChanged);
  $('provider-preset')?.addEventListener('change', event => {
    const preset = PRESET_DEFAULTS[event.target.value];
    if (!preset) return;
    $('provider-base-url').value = preset.baseUrl;
    $('provider-model').value = preset.model;
    renderProviderModels();
  });
  $('provider-model-preset')?.addEventListener('change', event => {
    if (event.target.value !== CUSTOM_MODEL_VALUE) {
      $('provider-model').value = event.target.value;
    } else {
      $('provider-model').focus();
    }
    renderProviderModels();
  });
  $('provider-model')?.addEventListener('input', () => {
    renderProviderModels();
  });
  $('fetch-provider-models')?.addEventListener('click', async () => {
    const presetId = $('provider-preset').value;
    setStatus('fetchingModels', 'neutral');
    const button = $('fetch-provider-models');
    button.disabled = true;
    const reply = await call('listModels', {
      preset: presetId,
      baseUrl: $('provider-base-url').value,
      model: $('provider-model').value,
      apiKey: $('provider-api-key').value,
    });
    button.disabled = false;
    if (reply.ok && reply.value && Array.isArray(reply.value.models)) {
      fetchedModelsByPreset[presetId] = reply.value.models;
      if (!$('provider-model').value.trim() && reply.value.models[0]?.id) {
        $('provider-model').value = reply.value.models[0].id;
      }
      renderProviderModels();
      setStatus('fetchedModelsOk', '', { count: reply.value.models.length });
    }
  });
  $('save-provider-config')?.addEventListener('click', async () => {
    const reply = await call('saveProviderConfig', {
      preset: $('provider-preset').value,
      baseUrl: $('provider-base-url').value,
      model: $('provider-model').value,
      apiKey: $('provider-api-key').value,
    });
    if (reply.ok) {
      $('provider-api-key').value = '';
      forgetResult();
      setStatus('providerSaved');
      renderState();
    }
  });
  $('test-provider-connection')?.addEventListener('click', async () => {
    setStatus('connectionTesting', 'neutral');
    const reply = await call('testConnection');
    if (reply.ok && reply.value) {
      setStatus('connectionOk', '', { latency: reply.value.latencyMs ?? 0 });
    }
  });
  $('language-select').addEventListener('change', async event => {
    const previous = state.language;
    const language = event.target.value;
    if (!LANGUAGES.includes(language)) return;
    const reply = await call('setLanguage', language);
    if (!reply.ok) { $('language-select').value = previous; return; }
    // State events are authoritative. Applying this preference also supports a
    // bridge that returns before its event reaches this window.
    state = { ...state, language };
    renderState();
  });
  $('settings-button').addEventListener('click', () => {
    const open = $('settings-panel').hidden;
    $('settings-panel').hidden = !open;
    $('settings-button').setAttribute('aria-expanded', String(open));
  });
  $('mini-mode-button')?.addEventListener('click', async () => {
    const reply = await call('toggleMiniMode');
    if (reply.ok && reply.value && typeof reply.value === 'object') {
      state = { ...state, ...reply.value };
      renderState();
    }
  });
  $('choose-config').addEventListener('click', async () => {
    const reply = await call('chooseConfig');
    if (reply.ok && reply.value.changed) { forgetResult(); renderState(); }
  });
  $('create-config').addEventListener('click', async () => {
    const reply = await call('createConfig');
    if (reply.ok && reply.value) setStatus('configCreated', 'neutral');
  });
  $('use-demo').addEventListener('click', async () => {
    const reply = await call('useDemo');
    if (reply.ok) { forgetResult(); renderState(); }
  });
  $('import-clipboard').addEventListener('click', () => call('importClipboard'));
  $('capture-selection').addEventListener('click', () => call('captureSelection'));
  $('companion-run').addEventListener('click', async () => {
    submitting = true;
    renderBusy();
    await call('runCompanion');
    submitting = false;
    renderBusy();
  });
  $('companion-cancel').addEventListener('click', () => call('hideCompanion'));
  document.addEventListener('keydown', event => {
    if ((event.ctrlKey || event.metaKey) && event.key === 'Enter' && !companion) {
      event.preventDefault();
      void generate();
    } else if (event.key === 'Escape') {
      if (companion) void call('hideCompanion');
      else if (state.busy || submitting) void call('cancel');
      else {
        $('settings-panel').hidden = true;
        $('settings-button').setAttribute('aria-expanded', 'false');
      }
    }
  });
  api?.onState?.(value => {
    if (!value || typeof value !== 'object') return;
    if (value.busy && !state.busy) forgetResult();
    state = { ...state, ...value, language: LANGUAGES.includes(value.language) ? value.language : state.language };
    renderState();
    if (!state.ready && state.error) showError(state.error);
  });
  api?.onCapture?.(value => {
    if (companion || !value || typeof value.text !== 'string' || clearing) return;
    $('original-prompt').value = value.text;
    clearValidation();
    updateCount();
    renderResultLabels();
    setStatus(value.source === 'clipboard' ? 'capturedClipboard' : 'capturedSelection', 'neutral');
    if (value.text.length > 12000) showValidation('lengthError');
    else $('original-prompt').focus();
  });
  api?.onResult?.(value => { if (!companion) showResult(value); });
  api?.onError?.(showError);
}

registerEvents();
renderState();
document.body.classList.add('ready');
const initial = await call('getState');
if (initial.ok && initial.value && typeof initial.value === 'object') {
  state = { ...state, ...initial.value, language: LANGUAGES.includes(initial.value.language) ? initial.value.language : 'zh-TW' };
  renderState();
  if (!state.ready && state.error) showError(state.error);
}
