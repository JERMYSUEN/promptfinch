import { open, mkdir, rename, unlink, lstat } from 'node:fs/promises';
import { basename, dirname, isAbsolute } from 'node:path';
import { randomUUID } from 'node:crypto';
import { parseEnv } from 'node:util';
import { optimize, readConfig, validateInput, NOTES_LANGUAGES, AppError } from '../lib/optimizer.js';

const messages = Object.freeze({
  CLOSED: 'The desktop workspace has closed.',
  BUSY: 'Wait for the current operation to finish or cancel it.',
  SETTINGS_READ: 'The desktop settings could not be read. Choose a model configuration again.',
  SETTINGS_WRITE: 'The desktop settings could not be saved.',
  CONFIG_READ: 'The selected configuration could not be read. Choose a readable configuration file.',
  CONFIG_INVALID: 'The selected model configuration is invalid. Check its settings and reload it.',
  CONFIG_INCOMPLETE: 'Live mode requires both LLM_API_KEY and LLM_MODEL. No demo result was substituted.',
  CONFIG_PATH: 'Choose a model configuration using an absolute local file path.',
  LANGUAGE: 'Choose English, Traditional Chinese, Japanese, or Korean.',
  INPUT: 'Enter a non-empty prompt of at most 12,000 characters and check the task and target model.',
  CANCELLED: 'Generation was cancelled. No result was copied or pasted.',
  PROVIDER: 'The model request could not be completed. Check the model configuration or try again.',
  RATE_LIMIT: 'The model service is busy or its usage limit has been reached. Try again later.',
  TIMEOUT: 'The model request timed out. Try again or shorten the prompt.',
  TEMPLATE: 'The configuration template could not be created.',
});

export class DesktopError extends Error {
  constructor(code) { super(messages[code] || messages.PROVIDER); this.name = 'DesktopError'; this.code = code; }
}

// A template is public configuration, never a copy of the user's active file.
const TEMPLATE = `# PromptFinch model configuration. Keep this file outside the source repository.
# Change mock to live only after entering your own provider settings.
OPTIMIZER_MODE=mock
LLM_BASE_URL=https://api.deepseek.com
LLM_MODEL=deepseek-flash
LLM_API_KEY=
LLM_JSON_MODE=true
LLM_THINKING_MODE=disabled
# Optional review is off by default; unset/false uses editing only (1 call, up to 2 with format retry).
# Set true for same-model independent review: usually 2 calls, up to 4 with repair/retries; adds paid usage and latency.
LLM_QUALITY_REVIEW=false
# Shared deadline for all editing, review, repair, and format retry calls.
LLM_TIMEOUT_MS=45000
`;
const CONFIG_LIMIT = 64 * 1024;
const SETTINGS_LIMIT = 16 * 1024;

async function boundedFile(path, limit) {
  const handle = await open(path, 'r');
  try {
    const stat = await handle.stat();
    if (!stat.isFile() || stat.size > limit) throw new Error('Not a bounded regular file');
    const buffer = Buffer.alloc(limit + 1);
    let length = 0;
    while (length < buffer.length) {
      const { bytesRead } = await handle.read(buffer, length, buffer.length - length, length);
      if (bytesRead === 0) break;
      length += bytesRead;
    }
    if (length > limit) throw new Error('File too large');
    return buffer.subarray(0, length).toString('utf8');
  } finally { await handle.close(); }
}

export class DesktopController {
  #preferencesPath; #templatePath; #optimize; #language = 'zh-TW'; #configFilePath = null;
  #config = null; #error = null; #active = null; #closed = false; #changing = false;

  constructor({ preferencesPath, templatePath, optimizeFn = optimize }) {
    if (![preferencesPath, templatePath].every(p => typeof p === 'string' && isAbsolute(p))
      || preferencesPath === templatePath || typeof optimizeFn !== 'function') throw new TypeError('Absolute, separate settings and template paths are required.');
    this.#preferencesPath = preferencesPath; this.#templatePath = templatePath; this.#optimize = optimizeFn;
  }

  async init() {
    this.#assertOpen();
    let stored;
    try { stored = JSON.parse(await boundedFile(this.#preferencesPath, SETTINGS_LIMIT)); }
    catch (error) {
      if (error.code === 'ENOENT') { this.#config = readConfig({ OPTIMIZER_MODE: 'mock' }); return this.snapshot(); }
      this.#setError('SETTINGS_READ'); return this.snapshot();
    }
    if (!stored || Array.isArray(stored) || typeof stored !== 'object'
      || !NOTES_LANGUAGES.includes(stored.language)
      || !(stored.configFilePath === null || (typeof stored.configFilePath === 'string' && isAbsolute(stored.configFilePath)))) {
      this.#setError('SETTINGS_READ'); return this.snapshot();
    }
    this.#language = stored.language; this.#configFilePath = stored.configFilePath;
    if (this.#configFilePath === null) this.#config = readConfig({ OPTIMIZER_MODE: 'mock' });
    else {
      try { this.#config = await this.#loadConfig(this.#configFilePath); }
      catch (error) { this.#setError(error.code || 'CONFIG_READ'); }
    }
    return this.snapshot();
  }

  snapshot() {
    return {
      mode: this.#config?.mode || 'live', ready: !this.#closed && Boolean(this.#config),
      model: this.#config?.mode === 'live' ? this.#config.model : null,
      configName: this.#configFilePath ? basename(this.#configFilePath) : null,
      language: this.#language, busy: Boolean(this.#active || this.#changing),
      ...(this.#error ? { error: { ...this.#error } } : {}),
    };
  }

  async setLanguage(language) {
    this.#assertIdle();
    if (!NOTES_LANGUAGES.includes(language)) throw new DesktopError('LANGUAGE');
    return this.#change(async () => {
      await this.#save(language, this.#configFilePath); this.#language = language; return this.snapshot();
    });
  }

  async selectConfig(path) {
    this.#assertIdle();
    if (typeof path !== 'string' || !isAbsolute(path) || path === this.#preferencesPath) throw new DesktopError('CONFIG_PATH');
    return this.#change(async () => {
      // Selecting an invalid live file disables generation instead of silently
      // using the previous demo/live configuration with a misleading label.
      this.#config = null; this.#configFilePath = path; this.#error = null;
      await this.#save(this.#language, path);
      try { this.#config = await this.#loadConfig(path); }
      catch (error) { this.#setError(error.code || 'CONFIG_READ'); throw new DesktopError(error.code || 'CONFIG_READ'); }
      return this.snapshot();
    });
  }

  async useDemo() {
    this.#assertIdle();
    return this.#change(async () => {
      await this.#save(this.#language, null);
      this.#configFilePath = null; this.#config = readConfig({ OPTIMIZER_MODE: 'mock' }); this.#error = null;
      return this.snapshot();
    });
  }

  async generate(body) {
    this.#assertIdle();
    if (!this.#config) throw new DesktopError(this.#error?.code || 'CONFIG_INCOMPLETE');
    let input;
    try {
      if (!body || typeof body !== 'object' || Array.isArray(body)) throw new Error('Invalid input');
      input = validateInput({ prompt: body.prompt, task: body.task, targetModel: body.targetModel,
        promptLanguage: 'en', notesLanguage: this.#language });
    } catch { throw new DesktopError('INPUT'); }
    const active = { abort: new AbortController(), id: randomUUID() };
    this.#active = active; this.#error = null;
    try {
      const result = await this.#optimize(input, this.#config, active.abort.signal);
      if (this.#closed || active.abort.signal.aborted || this.#active !== active) throw new DesktopError('CANCELLED');
      return result;
    } catch (error) {
      const code = this.#closed || active.abort.signal.aborted ? 'CANCELLED'
        : error instanceof DesktopError ? error.code
          : error instanceof AppError && error.status === 429 ? 'RATE_LIMIT'
            : error instanceof AppError && error.status === 504 ? 'TIMEOUT' : 'PROVIDER';
      this.#setError(code); throw new DesktopError(code);
    } finally { if (this.#active === active) this.#active = null; }
  }

  async cancel() { this.#active?.abort.abort(); return this.snapshot(); }
  async dispose() { this.#closed = true; this.#active?.abort.abort(); this.#config = null; }

  async createTemplate() {
    this.#assertOpen();
    try {
      await mkdir(dirname(this.#templatePath), { recursive: true, mode: 0o700 });
      const file = await open(this.#templatePath, 'wx', 0o600);
      try { await file.writeFile(TEMPLATE); } finally { await file.close(); }
    } catch (error) {
      if (error.code === 'EEXIST') {
        try { if ((await lstat(this.#templatePath)).isFile()) return this.#templatePath; } catch { /* Safe fixed error below. */ }
      }
      throw new DesktopError('TEMPLATE');
    }
    return this.#templatePath;
  }

  async #loadConfig(path) {
    let content;
    try { content = await boundedFile(path, CONFIG_LIMIT); } catch { throw new DesktopError('CONFIG_READ'); }
    let config;
    try { config = readConfig(parseEnv(content)); } catch { throw new DesktopError('CONFIG_INVALID'); }
    if (config.mode === 'live' && (!config.apiKey || !config.model)) throw new DesktopError('CONFIG_INCOMPLETE');
    return config;
  }

  async #save(language, configFilePath) {
    const temporary = `${this.#preferencesPath}.${randomUUID()}.tmp`;
    try {
      await mkdir(dirname(this.#preferencesPath), { recursive: true, mode: 0o700 });
      const file = await open(temporary, 'wx', 0o600);
      try { await file.writeFile(`${JSON.stringify({ language, configFilePath })}\n`); } finally { await file.close(); }
      await rename(temporary, this.#preferencesPath);
    } catch {
      await unlink(temporary).catch(() => {}); this.#setError('SETTINGS_WRITE'); throw new DesktopError('SETTINGS_WRITE');
    }
  }

  async #change(action) {
    this.#changing = true;
    try { await action(); } finally { this.#changing = false; }
    return this.snapshot();
  }
  #assertOpen() { if (this.#closed) throw new DesktopError('CLOSED'); }
  #assertIdle() { this.#assertOpen(); if (this.#active || this.#changing) throw new DesktopError('BUSY'); }
  #setError(code) { const error = new DesktopError(code); this.#error = { code: error.code, message: error.message }; }
}
