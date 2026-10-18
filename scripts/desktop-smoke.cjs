'use strict';
const { _electron: electron, expect } = require('@playwright/test');
const assert = require('node:assert/strict');
const { mkdtemp, readFile, readdir, rm, mkdir } = require('node:fs/promises');
const { tmpdir } = require('node:os');
const path = require('node:path');

(async () => {
  const root = path.resolve(__dirname, '..');
  const profile = await mkdtemp(path.join(tmpdir(), 'promptfinch-desktop-smoke-'));
  const index = process.argv.indexOf('--packaged');
  if (index >= 0 && !process.argv[index + 1]) throw new Error('--packaged requires an executable path.');
  const executablePath = index >= 0 ? path.resolve(process.argv[index + 1]) : require('electron');
  const args = [...(index >= 0 ? [] : [root]), '--smoke-test', '--test-profile', profile];
  let application;
  let passed = 0;
  const check = (condition, label) => { assert.ok(condition, label); passed++; };
  try {
    const env = { ...process.env, OPTIMIZER_MODE: 'live', LLM_API_KEY: 'synthetic-do-not-inherit', LLM_MODEL: 'not-used' };
    delete env.ELECTRON_RUN_AS_NODE;
    application = await electron.launch({ executablePath, args, cwd: root, env, timeout: 45000 });
    await application.firstWindow();
    // Two windows start together; renderer scheduling can expose the companion
    // first. Identify the workspace by its owned URL, never by event order.
    await expect.poll(() => application.windows().some(page => page.url() === 'promptfinch://app/'), { timeout: 30000 }).toBe(true);
    const page = application.windows().find(page => page.url() === 'promptfinch://app/');
    await expect(page.locator('body')).toHaveClass(/ready/);
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    let state = await page.evaluate(() => window.promptfinch.getState());
    check(state.ok && state.value.mode === 'mock' && state.value.ready, 'fresh isolated launch must use demo despite inherited live variables');
    check(state.value.language === 'zh-TW', 'default language');
    check(!/synthetic-do-not-inherit|apiKey|baseUrl/.test(JSON.stringify(state)), 'no provider secret in renderer');
    check(await page.evaluate(() => typeof window.require === 'undefined' && typeof window.process === 'undefined'), 'renderer must not have Node access');
    const prefs = await application.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].webContents.getLastWebPreferences());
    check(prefs.sandbox && prefs.contextIsolation && !prefs.nodeIntegration && prefs.webSecurity, 'sandbox configuration');
    const empty = await page.evaluate(() => window.promptfinch.generate({ prompt: ' ' }));
    check(!empty.ok && empty.error.code === 'INPUT', 'empty input rejected by main process');
    await expect(page.locator('#optimized-prompt')).toHaveValue('');
    const source = '請修正 ACME-42，保留 exact_name，並使用繁體中文回答。';
    await page.locator('#original-prompt').fill(source);
    await page.locator('#task-select').selectOption('coding');
    await page.locator('#target-model').fill('Claude');
    await page.locator('#generate-button').click();
    await expect(page.locator('#optimized-prompt')).toHaveValue(/ACME-42/);
    const prompt = await page.locator('#optimized-prompt').inputValue();
    check(prompt.includes(source) && /NOT been translated/.test(prompt), 'mock preserves literal source and labels its limits');
    await expect(page.locator('#result-tag')).toBeVisible();
    check((await page.locator('#improvements li').count()) > 0, 'notes are separate');
    await page.locator('#copy-button').click();
    const copied = await application.evaluate(({ app }) => new Promise(resolve => app.emit('promptfinch-test-read-clipboard', null, resolve)));
    check(copied === prompt, 'copy includes only prompt, using isolated in-memory clipboard');
    await page.locator('#clear-button').click();
    await expect(page.locator('#original-prompt')).toHaveValue('');
    await expect(page.locator('#optimized-prompt')).toHaveValue('');
    const noCopy = await page.evaluate(() => window.promptfinch.copyResult());
    check(!noCopy.ok && noCopy.error.code === 'NO_RESULT', 'clear removes main-process result');
    for (const language of ['en', 'ja', 'ko', 'zh-TW']) {
      await page.locator('#language-select').selectOption(language);
      await expect(page.locator('html')).toHaveAttribute('lang', language);
      state = await page.evaluate(() => window.promptfinch.getState());
      check(state.value.language === language, `language ${language}`);
    }
    await application.evaluate(({ app }) => app.emit('promptfinch-test-clipboard', null, 'Synthetic clipboard ACME-93'));
    await page.locator('#import-clipboard').click();
    await expect(page.locator('#original-prompt')).toHaveValue('Synthetic clipboard ACME-93');
    await expect(page.locator('#optimized-prompt')).toHaveValue('');
    passed++;
    // Simulate only the helper message and button action, not a physical OS click.
    await application.evaluate(({ app, BrowserWindow }) => {
      BrowserWindow.getAllWindows().find(w => w.webContents.getURL() === 'promptfinch://app/').hide();
      app.emit('promptfinch-test-capture', null, { ok: true, text: 'Synthetic right-click request ACME-94.', x: 200, y: 160, capturedAt: Date.now(), sourceId: 'synthetic' });
    });
    const companion = application.windows().find(window => window.url().includes('window=companion'));
    assert.ok(companion, 'companion window exists');
    await expect(companion.locator('#companion-run')).toBeVisible();
    await expect(page.locator('#optimized-prompt')).toHaveValue('');
    check((await page.evaluate(() => window.promptfinch.getState())).value.busy === false, 'right click alone does not generate');
    await companion.evaluate(() => document.querySelector('#companion-run').click());
    await expect(page.locator('#optimized-prompt')).toHaveValue(/ACME-94/);
    check((await page.locator('#original-prompt').inputValue()).includes('ACME-94'), 'explicit companion action generates from captured text');
    await page.locator('#clear-button').click();
    const settings = await readFile(path.join(profile, 'preferences.json'), 'utf8');
    check(!/ACME-|synthetic-do-not-inherit|exact_name|prompt|result/i.test(settings), 'preferences contain no prompt, result or secret');
    check(errors.length === 0, 'no renderer script errors');
    await mkdir(path.join(root, 'artifacts', 'desktop'), { recursive: true });
    await page.screenshot({ path: path.join(root, 'artifacts', 'desktop', `workspace-${process.platform}.png`), fullPage: true });
    console.log(`Desktop smoke passed: ${passed} checks (${index >= 0 ? 'packaged' : 'development'}, ${process.platform}/${process.arch}). Only synthetic mock content; no system clipboard writes or model calls.`);
  } finally {
    if (application) await application.close();
    await rm(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 150 });
  }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
