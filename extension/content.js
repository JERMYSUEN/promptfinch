(() => {
  if (window.__promptfinchExtMounted) return;
  window.__promptfinchExtMounted = true;

  const host = document.createElement('div');
  host.id = 'promptfinch-ext-host';
  const shadow = host.attachShadow({ mode: 'closed' });
  shadow.innerHTML = `
    <style>
      :host { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
      .pill, .card {
        position: fixed;
        pointer-events: auto;
        box-sizing: border-box;
        color: #161b26;
        background: rgba(255, 255, 255, 0.96);
        border: 1px solid rgba(41, 110, 230, 0.25);
        box-shadow: 0 8px 24px rgba(15, 23, 42, 0.16);
        backdrop-filter: blur(12px);
      }
      @media (prefers-color-scheme: dark) {
        .pill, .card {
          color: #eef3ff;
          background: rgba(25, 31, 42, 0.96);
          border-color: rgba(139, 177, 255, 0.28);
          box-shadow: 0 10px 28px rgba(0, 0, 0, 0.45);
        }
      }
      .pill {
        display: none;
        align-items: center;
        gap: 6px;
        height: 28px;
        padding: 0 11px;
        border-radius: 999px;
        font-size: 12px;
        font-weight: 600;
        cursor: pointer;
        user-select: none;
      }
      .pill:hover { border-color: #296ee6; color: #296ee6; }
      .dot { width: 7px; height: 7px; border-radius: 50%; background: #296ee6; flex-shrink: 0; }
      .card {
        display: none;
        width: 360px;
        max-width: calc(100vw - 24px);
        border-radius: 12px;
        padding: 12px;
        font-size: 12.5px;
      }
      .card-head { display: flex; align-items: center; justify-content: space-between; margin-bottom: 8px; font-weight: 600; }
      .close-btn { border: none; background: transparent; color: inherit; opacity: 0.65; cursor: pointer; font-size: 14px; padding: 2px 5px; }
      .close-btn:hover { opacity: 1; }
      .output {
        width: 100%;
        min-height: 78px;
        max-height: 200px;
        resize: vertical;
        box-sizing: border-box;
        padding: 8px;
        border-radius: 8px;
        border: 1px solid rgba(128, 140, 165, 0.28);
        background: rgba(128, 140, 165, 0.08);
        color: inherit;
        font: inherit;
        line-height: 1.45;
      }
      .notes { margin-top: 6px; font-size: 11.5px; opacity: 0.85; }
      .notes summary { cursor: pointer; color: #296ee6; font-weight: 500; }
      .notes ul { margin: 4px 0 0 16px; padding: 0; }
      .status { margin-top: 6px; font-size: 11.5px; opacity: 0.78; min-height: 15px; }
      .status.err { color: #d9463e; opacity: 1; }
      .actions { display: flex; gap: 8px; margin-top: 8px; }
      .btn {
        border: 1px solid rgba(128, 140, 165, 0.35);
        border-radius: 7px;
        padding: 5px 11px;
        font-size: 12px;
        font-weight: 500;
        cursor: pointer;
        background: transparent;
        color: inherit;
      }
      .btn.primary { background: #296ee6; border-color: #296ee6; color: #ffffff; }
      .btn:disabled { opacity: 0.5; cursor: default; }
    </style>
    <button type="button" class="pill" id="pf-pill"><span class="dot"></span><span>Refine</span></button>
    <div class="card" id="pf-card" role="dialog" aria-label="PromptFinch">
      <div class="card-head">
        <span>PromptFinch</span>
        <button type="button" class="close-btn" id="pf-close" aria-label="Close">✕</button>
      </div>
      <textarea class="output" id="pf-output" spellcheck="false"></textarea>
      <details class="notes" id="pf-notes" hidden><summary id="pf-notes-summary"></summary><ul id="pf-notes-list"></ul></details>
      <div class="status" id="pf-status"></div>
      <div class="actions">
        <button type="button" class="btn primary" id="pf-replace">Replace</button>
        <button type="button" class="btn" id="pf-copy">Copy</button>
      </div>
    </div>
  `;
  document.documentElement.appendChild(host);

  const pill = shadow.getElementById('pf-pill');
  const card = shadow.getElementById('pf-card');
  const output = shadow.getElementById('pf-output');
  const notes = shadow.getElementById('pf-notes');
  const notesSummary = shadow.getElementById('pf-notes-summary');
  const notesList = shadow.getElementById('pf-notes-list');
  const status = shadow.getElementById('pf-status');
  const replaceBtn = shadow.getElementById('pf-replace');
  const copyBtn = shadow.getElementById('pf-copy');
  const closeBtn = shadow.getElementById('pf-close');

  let activeSelection = null;

  function clampPosition(x, y, width, height) {
    const left = Math.max(8, Math.min(x, window.innerWidth - width - 8));
    const top = Math.max(8, Math.min(y, window.innerHeight - height - 8));
    return { left, top };
  }

  function hideAll() {
    pill.style.display = 'none';
    card.style.display = 'none';
  }

  function readCurrentSelection() {
    const el = document.activeElement;
    if (el && (el.tagName === 'TEXTAREA' || (el.tagName === 'INPUT' && /^(text|search|url)$/i.test(el.type)))) {
      const start = el.selectionStart ?? 0;
      const end = el.selectionEnd ?? 0;
      const text = el.value.slice(start, end).trim();
      if (!text) return null;
      const rect = el.getBoundingClientRect();
      return { kind: 'input', el, start, end, text, rect };
    }
    const sel = window.getSelection();
    if (!sel || sel.rangeCount === 0 || sel.isCollapsed) return null;
    const text = sel.toString().trim();
    if (!text) return null;
    const range = sel.getRangeAt(0).cloneRange();
    const rect = range.getBoundingClientRect();
    const editableRoot = range.commonAncestorContainer.nodeType === 1
      ? range.commonAncestorContainer.closest('[contenteditable="true"]')
      : range.commonAncestorContainer.parentElement?.closest('[contenteditable="true"]');
    return { kind: editableRoot ? 'contenteditable' : 'readonly', range, editableRoot, text, rect };
  }

  function replaceSelectionText(newText) {
    if (!activeSelection) return false;
    if (activeSelection.kind === 'input') {
      const { el, start, end } = activeSelection;
      el.focus();
      el.setRangeText(newText, start, end, 'select');
      el.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertReplacementText', data: newText }));
      return true;
    }
    if (activeSelection.kind === 'contenteditable' && activeSelection.editableRoot) {
      activeSelection.editableRoot.focus();
      const sel = window.getSelection();
      sel.removeAllRanges();
      sel.addRange(activeSelection.range);
      if (document.execCommand) {
        document.execCommand('insertText', false, newText);
        return true;
      }
      activeSelection.range.deleteContents();
      activeSelection.range.insertNode(document.createTextNode(newText));
      activeSelection.editableRoot.dispatchEvent(new InputEvent('input', { bubbles: true }));
      return true;
    }
    return false;
  }

  document.addEventListener('mouseup', event => {
    if (event.composedPath().includes(host)) return;
    setTimeout(() => {
      if (card.style.display === 'block') return;
      const captured = readCurrentSelection();
      if (!captured || captured.text.length < 3) {
        pill.style.display = 'none';
        return;
      }
      activeSelection = captured;
      const pos = clampPosition(event.clientX + 8, event.clientY - 36, 108, 30);
      pill.style.left = `${pos.left}px`;
      pill.style.top = `${pos.top}px`;
      pill.style.display = 'inline-flex';
    }, 20);
  });

  document.addEventListener('mousedown', event => {
    if (event.composedPath().includes(host)) return;
    hideAll();
  });

  document.addEventListener('keydown', event => {
    if (event.key === 'Escape') hideAll();
  });

  pill.addEventListener('click', () => {
    if (!activeSelection) return;
    const pillRect = pill.getBoundingClientRect();
    pill.style.display = 'none';
    const pos = clampPosition(pillRect.left, pillRect.bottom + 6, 360, 220);
    card.style.left = `${pos.left}px`;
    card.style.top = `${pos.top}px`;
    card.style.display = 'block';
    output.value = '';
    notes.hidden = true;
    status.className = 'status';
    status.textContent = 'Refining prompt…';
    replaceBtn.hidden = activeSelection.kind === 'readonly';
    replaceBtn.disabled = true;
    copyBtn.disabled = true;

    chrome.runtime.sendMessage({
      type: 'PROMPTFINCH_OPTIMIZE',
      payload: { prompt: activeSelection.text },
    }, response => {
      if (chrome.runtime.lastError || !response?.ok) {
        status.className = 'status err';
        status.textContent = response?.error || chrome.runtime.lastError?.message || 'Unable to refine prompt.';
        return;
      }
      output.value = response.result.prompt;
      const allNotes = [...(response.result.improvements || []), ...(response.result.assumptions || [])];
      if (allNotes.length > 0) {
        notesSummary.textContent = `✦ ${allNotes.length} editing notes`;
        notesList.replaceChildren(...allNotes.map(note => {
          const li = document.createElement('li');
          li.textContent = note;
          return li;
        }));
        notes.hidden = false;
      }
      status.className = 'status';
      status.textContent = `Ready · ${response.result.model || 'PromptFinch'}`;
      replaceBtn.disabled = false;
      copyBtn.disabled = false;
    });
  });

  replaceBtn.addEventListener('click', () => {
    if (replaceSelectionText(output.value)) {
      hideAll();
    } else {
      status.className = 'status err';
      status.textContent = 'Field changed. Click Copy instead.';
    }
  });

  copyBtn.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(output.value);
      status.className = 'status';
      status.textContent = 'Copied to clipboard.';
    } catch {
      status.className = 'status err';
      status.textContent = 'Copy failed. Select and press ⌘C / Ctrl+C.';
    }
  });

  closeBtn.addEventListener('click', hideAll);
})();
