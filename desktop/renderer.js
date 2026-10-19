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

function inputValue() {
  return { prompt: $('original-prompt').value, task: $('task-select').value, targetModel: $('target-model').value };
}

function setStatus(key, kind = '') {
  statusKey = key;
  statusKind = kind;
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
  target.textContent = lastError ? errorText(lastError) : (statusKey ? t(statusKey) : '');
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
  for (const id of ['original-prompt', 'target-model', 'task-select', 'choose-config', 'create-config', 'use-demo', 'import-clipboard', 'capture-selection']) {
    $(id).disabled = busy;
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
  for (const id of ['original-prompt', 'target-model', 'task-select']) $(id).addEventListener('input', inputChanged);
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
  $('choose-config').addEventListener('click', async () => {
    const reply = await call('chooseConfig');
    if (reply.ok) { forgetResult(); renderState(); }
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
