const PRESET_DEFAULTS = {
  deepseek: { baseUrl: 'https://api.deepseek.com', model: 'deepseek-chat' },
  openai: { baseUrl: 'https://api.openai.com', model: 'gpt-4.1-mini' },
  anthropic: { baseUrl: 'https://api.anthropic.com', model: 'claude-3-5-haiku-latest' },
  gemini: { baseUrl: 'https://generativelanguage.googleapis.com', model: 'gemini-2.5-flash' },
  ollama: { baseUrl: 'http://127.0.0.1:11434/v1', model: 'qwen2.5:7b' },
  local: { baseUrl: 'http://127.0.0.1:3210', model: 'local-backend' },
};

const $ = id => document.getElementById(id);

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
}

$('preset').addEventListener('change', () => {
  const defaults = PRESET_DEFAULTS[$('preset').value];
  if (defaults) {
    $('base-url').value = defaults.baseUrl;
    $('model').value = defaults.model;
  }
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
