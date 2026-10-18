const { execFile, spawn } = require('node:child_process');
const { isAbsolute, win32 } = require('node:path');

const MAX_TEXT = 12000;
const MAX_LINE = 128 * 1024;
const MAX_EVENT_AGE = 1500;
const SAFE_CODES = new Set(['UNSUPPORTED', 'NO_SELECTION', 'PASSWORD', 'FOCUS_CHANGED', 'TOO_LONG', 'HELPER_ERROR', 'TIMEOUT']);

function failure(code) { return { ok: false, code: SAFE_CODES.has(code) ? code : 'HELPER_ERROR' }; }
function isX11(env) { return env.XDG_SESSION_TYPE?.toLowerCase() === 'x11' || (!env.WAYLAND_DISPLAY && Boolean(env.DISPLAY) && env.XDG_SESSION_TYPE?.toLowerCase() !== 'wayland'); }
function textResult(text) {
  if (typeof text !== 'string' || !text.trim() || text.includes('\0')) return failure('NO_SELECTION');
  if (text.length > MAX_TEXT) return failure('TOO_LONG');
  return { ok: true, text };
}
function helperResult(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return failure('HELPER_ERROR');
  if (value.ok !== true) return failure(value.code);
  const result = textResult(value.text);
  if (result.ok && typeof value.sourceId === 'string' && /^[0-9]+:[0-9]+$/.test(value.sourceId)) result.sourceId = value.sourceId;
  return result;
}
function validPath(path) { return typeof path === 'string' && (isAbsolute(path) || win32.isAbsolute(path)); }
function fresh(value) { const age = Date.now() - value; return Number.isSafeInteger(value) && age >= -250 && age <= MAX_EVENT_AGE; }
function coordinates(value) { return Number.isSafeInteger(value.x) && Number.isSafeInteger(value.y) && Math.abs(value.x) < 1000000 && Math.abs(value.y) < 1000000; }

async function captureSelection({ platform = process.platform, clipboard, helperPath, execFileFn = execFile, env = process.env }) {
  if (platform === 'linux') {
    if (!isX11(env)) return failure('UNSUPPORTED');
    if (!clipboard?.selection?.readText) return failure('UNSUPPORTED');
    try { return textResult(await clipboard.selection.readText()); } catch { return failure('HELPER_ERROR'); }
  }
  if (platform !== 'win32') return failure('UNSUPPORTED');
  if (!validPath(helperPath)) return failure('HELPER_ERROR');
  return new Promise(resolve => {
    try {
      execFileFn(helperPath, ['--read'], { windowsHide: true, timeout: 2000, maxBuffer: MAX_LINE, encoding: 'utf8' }, (error, stdout) => {
        if (error) { resolve(failure(error.killed || error.code === 'ETIMEDOUT' ? 'TIMEOUT' : 'HELPER_ERROR')); return; }
        try { resolve(helperResult(JSON.parse(stdout))); } catch { resolve(failure('HELPER_ERROR')); }
      });
    } catch { resolve(failure('HELPER_ERROR')); }
  });
}

async function verifySelectionSource({ platform = process.platform, helperPath, sourceId, execFileFn = execFile }) {
  if (platform !== 'win32') return failure('UNSUPPORTED');
  if (!validPath(helperPath) || typeof sourceId !== 'string' || !/^[1-9][0-9]{0,9}:[1-9][0-9]{0,18}$/.test(sourceId)) return failure('FOCUS_CHANGED');
  return new Promise(resolve => {
    try {
      execFileFn(helperPath, ['--verify-source', sourceId], { windowsHide: true, timeout: 2000, maxBuffer: 1024, encoding: 'utf8' }, (error, stdout) => {
        if (error) { resolve(failure(error.killed || error.code === 'ETIMEDOUT' ? 'TIMEOUT' : 'HELPER_ERROR')); return; }
        try { const parsed = JSON.parse(stdout); resolve(parsed?.ok === true ? { ok: true } : failure(parsed?.code)); }
        catch { resolve(failure('HELPER_ERROR')); }
      });
    } catch { resolve(failure('HELPER_ERROR')); }
  });
}

function startSelectionWatch({ platform = process.platform, clipboard, helperPath, spawnFn = spawn,
  onSelection = () => {}, onError = () => {}, excludePid, env = process.env }) {
  let child; let stopped = false; let buffer = ''; let latest = 0;
  const report = code => { if (!stopped) onError(failure(code)); };
  const stop = () => {
    if (stopped) return;
    stopped = true; latest++; buffer = '';
    if (child && !child.killed) child.kill();
  };
  if (!['win32', 'linux'].includes(platform) || platform === 'linux' && !isX11(env)) {
    queueMicrotask(() => report('UNSUPPORTED')); return { stop };
  }
  if (!validPath(helperPath)) { queueMicrotask(() => report('HELPER_ERROR')); return { stop }; }
  const arguments_ = platform === 'win32' ? ['--watch'] : [];
  if (platform === 'win32' && Number.isSafeInteger(excludePid) && excludePid > 0) arguments_.push('--exclude-pid', String(excludePid));
  try {
    child = spawnFn(helperPath, arguments_, { windowsHide: true, stdio: ['ignore', 'pipe', 'ignore'] });
    child.stdout.setEncoding('utf8');
    child.stdout.on('data', chunk => {
      if (stopped) return;
      buffer += chunk;
      if (buffer.length > MAX_LINE) { report('HELPER_ERROR'); stop(); return; }
      let boundary;
      while ((boundary = buffer.indexOf('\n')) !== -1) {
        const line = buffer.slice(0, boundary).trim(); buffer = buffer.slice(boundary + 1);
        if (!line) continue;
        const sequence = ++latest;
        let event;
        try { event = JSON.parse(line); } catch { report('HELPER_ERROR'); stop(); return; }
        if (!event || typeof event !== 'object' || !fresh(event.capturedAt) || !coordinates(event)) continue;
        if (platform === 'win32') {
          const captured = helperResult(event);
          if (!captured.ok || typeof event.sourceId !== 'string' || !/^[0-9]+:[0-9]+$/.test(event.sourceId)) continue;
          onSelection({ ...captured, x: event.x, y: event.y, capturedAt: event.capturedAt, sourceId: event.sourceId });
        } else if (event.event === 'right-click') {
          Promise.resolve(captureSelection({ platform, clipboard, env })).then(captured => {
            if (!stopped && sequence === latest && fresh(event.capturedAt) && captured.ok) {
              onSelection({ ...captured, x: event.x, y: event.y, capturedAt: event.capturedAt,
                sourceId: typeof event.sourceId === 'string' ? event.sourceId.slice(0, 100) : 'x11-selection' });
            }
          }).catch(() => report('HELPER_ERROR'));
        }
      }
    });
    child.on('error', () => { report('HELPER_ERROR'); stop(); });
    child.on('exit', () => { if (!stopped) { report('HELPER_ERROR'); stop(); } });
  } catch { queueMicrotask(() => report('HELPER_ERROR')); }
  return { stop };
}

module.exports = { captureSelection, startSelectionWatch, verifySelectionSource };
