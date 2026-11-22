import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { redactSecrets, restoreSecrets } from '../extension/background.js';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');

test('browser extension manifest follows Manifest V3, icon requirements, and minimal permission scope', () => {
  const manifest = JSON.parse(readFileSync(resolve(root, 'extension/manifest.json'), 'utf8'));
  const pkg = JSON.parse(readFileSync(resolve(root, 'package.json'), 'utf8'));
  assert.equal(manifest.manifest_version, 3);
  assert.equal(manifest.version, pkg.version);
  assert.deepEqual(manifest.permissions, ['storage']);
  assert.equal(manifest.background.service_worker, 'background.js');
  assert.equal(manifest.action.default_popup, 'popup.html');
  for (const size of ['16', '32', '48', '128']) {
    assert.equal(manifest.icons[size], `icons/icon-${size}.png`);
    assert.equal(manifest.action.default_icon[size], `icons/icon-${size}.png`);
    const file = resolve(root, 'extension', manifest.icons[size]);
    assert.ok(existsSync(file), `missing icon ${manifest.icons[size]}`);
    const bytes = readFileSync(file);
    assert.equal(bytes[0], 0x89);
    assert.equal(bytes[1], 0x50);
    assert.equal(bytes[2], 0x4e);
    assert.equal(bytes[3], 0x47);
  }
  assert.ok(Array.isArray(manifest.content_scripts) && manifest.content_scripts.length === 1);
  assert.ok(manifest.content_scripts[0].matches.includes('https://chatgpt.com/*'));
  assert.ok(manifest.content_scripts[0].matches.includes('https://claude.ai/*'));
  assert.ok(manifest.content_scripts[0].matches.includes('https://gemini.google.com/*'));
});

test('browser extension local secret shield masks and restores secrets verbatim', () => {
  const input = 'Use sk-proj-ExampleSecretKey1234567890 and ghp_ExampleGitHubToken1234567890 here.';
  const { masked, tokens } = redactSecrets(input);
  assert.equal(tokens.length, 2);
  assert.doesNotMatch(masked, /sk-proj-ExampleSecretKey1234567890|ghp_ExampleGitHubToken1234567890/);
  assert.equal(restoreSecrets(`Prompt: ${masked}`, tokens), `Prompt: ${input}`);
});

test('browser extension settings include curated model selector and live model discovery hooks', () => {
  const popupHtml = readFileSync(resolve(root, 'extension/popup.html'), 'utf8');
  const popupJs = readFileSync(resolve(root, 'extension/popup.js'), 'utf8');
  const bgJs = readFileSync(resolve(root, 'extension/background.js'), 'utf8');
  assert.match(popupHtml, /id="model-preset"/);
  assert.match(popupHtml, /id="fetch-models"/);
  assert.match(popupHtml, /id="model-hint"/);
  assert.match(popupJs, /DeepSeek-V4\.1-Flash/);
  assert.match(popupJs, /deepseek-v4-pro/);
  assert.match(popupJs, /PROMPTFINCH_LIST_MODELS/);
  assert.match(bgJs, /PROMPTFINCH_LIST_MODELS/);
});
