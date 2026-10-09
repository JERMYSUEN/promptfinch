const $ = id => document.getElementById(id);
const form = $('optimizer-form');
const original = $('original-prompt');
const target = $('target-model');
const promptLanguage = $('prompt-language');
const submitButton = $('optimize-button');
const copyButton = $('copy-button');
const controls = [original, target, promptLanguage, ...form.querySelectorAll('input[name="task"], [data-example]')];
let config = null;
let result = null;
let lastInput = '';
let busy = false;
let requestId = 0;
let controller = null;

const EXAMPLES = {
  writing: '請幫我寫一封客戶邀請信，邀請客戶參加 11 月 20 日下午 2 點的線上產品發表會。對象是現有企業客戶，語氣專業但親切，內文 200 字以內。請提供主旨與信件內文，最後保留報名連結佔位符 [報名連結]。',
  analysis: '分析以下三個月的銷售資料：7 月 120 萬、8 月 135 萬、9 月 128 萬。請用繁體中文列出月增減百分比、觀察到的趨勢與兩個需要進一步確認的問題。請用表格呈現數據，不要把推測當成事實，也不要捏造其他資料。',
  coding: '請用原生 JavaScript 寫一個驗證台灣手機號碼的函式，接受字串、回傳布林值。格式必須是 09 開頭的 10 位數字，不接受空白或符號。不要使用外部套件，請提供函式與成功、失敗、空字串的測試範例。',
};

function inputValue() {
  return { prompt: original.value, task: form.querySelector('input[name="task"]:checked').value, targetModel: target.value, promptLanguage: promptLanguage.value };
}

function status(message, kind = '') {
  $('action-status').textContent = message;
  $('action-status').className = `action-status ${kind}`;
}

function showError(message) {
  $('input-error').textContent = message;
  $('input-error').hidden = false;
}

function setBusy(value) {
  busy = value;
  controls.forEach(control => { control.disabled = value; });
  submitButton.disabled = value || !config;
  copyButton.disabled = value || !result;
  $('optimize-label').textContent = value ? '正在優化…' : '優化 Prompt';
  $('clear-button').textContent = value ? '取消並清除' : '清除';
  document.querySelector('.output-pane').setAttribute('aria-busy', String(value));
  $('loading-state').hidden = !value;
  $('empty-state').hidden = value || Boolean(result);
  $('result-state').hidden = value || !result;
  $('explanation').hidden = value || !result;
}

function updatedInput() {
  $('character-count').textContent = `${original.value.length.toLocaleString('en-US')} / 12,000 UTF-16 單位`;
  $('input-error').hidden = true;
  original.removeAttribute('aria-invalid');
  if (result && JSON.stringify(inputValue()) !== lastInput) {
    $('result-tag').textContent = '上次結果';
    status('輸入已更新。目前顯示上一次結果，請重新優化取得新版本。', 'neutral');
  } else if (result) {
    $('result-tag').textContent = result.mode === 'mock' ? '示範結果' : '模型結果';
    status('');
  } else status('');
}

function fillList(id, values) {
  const list = $(id);
  list.replaceChildren(...values.map(value => {
    const item = document.createElement('li');
    item.textContent = value; // Provider and user strings must never be interpreted as HTML.
    return item;
  }));
}

function renderResult(data) {
  result = data;
  $('optimized-prompt').value = data.prompt;
  fillList('improvements', data.improvements);
  fillList('assumptions-list', data.assumptions);
  $('no-assumptions').hidden = data.assumptions.length > 0;
  $('result-tag').hidden = false;
  $('result-tag').textContent = data.mode === 'mock' ? '示範結果' : '模型結果';
  $('result-source').textContent = data.mode === 'mock'
    ? '固定範本示範，未呼叫語言模型。複製時只包含上方 Prompt。'
    : `由 ${data.generationModel} 生成。複製時只包含上方 Prompt。`;
}

async function requestOptimization(event) {
  event?.preventDefault();
  if (busy || !config) return;
  $('input-error').hidden = true;
  const input = inputValue();
  if (!input.prompt.trim()) {
    showError('請先輸入想優化的 Prompt，或選一個範例開始。');
    original.setAttribute('aria-invalid', 'true');
    original.focus();
    return;
  }
  if (input.prompt.length > config.maxPromptLength) {
    showError('Prompt 超過 12,000 字，請縮短後再試。');
    return;
  }
  const currentId = ++requestId;
  const requestController = new AbortController();
  controller = requestController;
  // Keep the browser responsive even if the server or network stalls.
  const timeout = setTimeout(() => requestController.abort(), 195000);
  setBusy(true);
  status('正在優化，請稍候。', 'neutral');
  try {
    const response = await fetch('/api/optimize', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(input), signal: requestController.signal,
    });
    const data = await response.json().catch(() => null);
    if (currentId !== requestId) return;
    if (!response.ok) throw new Error(data?.error || '服務暫時無法完成優化，請稍後再試。');
    if (!data || typeof data.prompt !== 'string' || !Array.isArray(data.improvements) || !Array.isArray(data.assumptions) || !['mock', 'live'].includes(data.mode)) {
      throw new Error('服務回傳的結果不完整，請重新嘗試。');
    }
    renderResult(data);
    lastInput = JSON.stringify(input);
    status(data.mode === 'mock' ? '示範整理完成。這是固定範本結果，未呼叫 AI。' : '優化完成。可以複製 Prompt，或調整輸入後再優化。');
  } catch (error) {
    if (currentId !== requestId) return;
    const message = error.name === 'AbortError' ? '等待時間過長，請檢查連線後再試。'
      : error instanceof TypeError ? '無法連線到服務，請確認伺服器仍在執行後再試。' : error.message;
    showError(message);
    status(result ? '本次優化失敗，仍保留上一次結果。' : '優化未完成，請依提示重新嘗試。', 'error');
    if (result) $('result-tag').textContent = '上次結果';
  } finally {
    clearTimeout(timeout);
    if (currentId === requestId) { controller = null; setBusy(false); }
  }
}

form.addEventListener('submit', requestOptimization);
form.addEventListener('input', updatedInput);
promptLanguage.addEventListener('change', updatedInput);
original.addEventListener('keydown', event => {
  if ((event.metaKey || event.ctrlKey) && event.key === 'Enter' && !event.isComposing) requestOptimization(event);
});

$('clear-button').addEventListener('click', () => {
  ++requestId;
  controller?.abort();
  controller = null;
  original.value = '';
  $('optimized-prompt').value = '';
  result = null;
  lastInput = '';
  $('result-tag').hidden = true;
  $('result-source').textContent = '';
  fillList('improvements', []);
  fillList('assumptions-list', []);
  updatedInput();
  setBusy(false);
  status('已清除輸入與結果。', 'neutral');
  original.focus();
});

document.querySelectorAll('[data-example]').forEach(button => button.addEventListener('click', () => {
  original.value = EXAMPLES[button.dataset.example];
  form.querySelector(`input[name="task"][value="${button.dataset.example}"]`).checked = true;
  updatedInput();
  original.focus();
}));

copyButton.addEventListener('click', async () => {
  if (!result || busy) return;
  try {
    if (!navigator.clipboard?.writeText) throw new Error('Clipboard unavailable');
    await navigator.clipboard.writeText(result.prompt);
    status('已複製 Prompt。優化說明未包含在內。');
  } catch {
    const output = $('optimized-prompt');
    output.focus();
    output.select();
    status('無法自動複製，已選取 Prompt。請按 ⌘ / Ctrl + C，或長按選取內容並複製。', 'error');
  }
});

$('help-toggle').addEventListener('click', () => {
  const expanded = $('help-toggle').getAttribute('aria-expanded') === 'true';
  $('help-toggle').setAttribute('aria-expanded', String(!expanded));
  $('help-panel').hidden = expanded;
});

async function initialize() {
  try {
    const response = await fetch('/api/config', { signal: AbortSignal.timeout(10000) });
    if (!response.ok) throw new Error();
    const data = await response.json();
    if (!['mock', 'live'].includes(data.mode) || typeof data.maxPromptLength !== 'number') throw new Error();
    config = data;
    const mock = data.mode === 'mock';
    $('mode-badge').textContent = mock ? '示範模式' : '模型模式';
    $('mode-badge').className = `mode-badge ${data.mode}`;
    $('mode-notice').className = `mode-notice ${mock ? 'mock' : data.ready ? '' : 'error'}`;
    $('mode-notice').textContent = mock
      ? '目前為示範模式：使用固定範本整理 Prompt，未呼叫 AI，也不會傳送內容到外部。'
      : data.ready ? `目前為模型模式，使用 ${data.generationModel}。按下優化後，內容會傳送到你設定的模型服務。`
      : '模型設定尚未完成。請在伺服器 .env 設定 LLM_API_KEY 與 LLM_MODEL，或切換 mock 模式後重新啟動。';
    $('privacy-text').textContent = mock
      ? '本服務不保存輸入與結果；示範模式不向外傳送內容。重新整理後，內容便會清空。'
      : '本服務不保存輸入與結果；優化時僅傳送到設定的模型服務。服務商的資料政策另行適用。';
    setBusy(false);
  } catch {
    $('mode-badge').textContent = '服務未連線';
    $('mode-notice').className = 'mode-notice error';
    $('mode-notice').textContent = '無法取得服務設定。請確認伺服器已啟動，再重新整理頁面。';
    submitButton.disabled = true;
  }
}

// No localStorage, cookies, analytics or user-content persistence.
// Defeat browser form restoration so reload always starts a fresh workspace.
form.reset();
$('optimized-prompt').value = '';
initialize();
