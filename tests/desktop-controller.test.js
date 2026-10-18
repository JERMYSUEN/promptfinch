import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile, stat, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DesktopController } from '../desktop/controller.mjs';

async function workspace(t, optimizeFn) {
  const root = await mkdtemp(join(tmpdir(), 'promptfinch-controller-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const preferencesPath = join(root, 'settings.json'), templatePath = join(root, 'model.env');
  const controller = new DesktopController({ preferencesPath, templatePath, ...(optimizeFn ? { optimizeFn } : {}) });
  t.after(() => controller.dispose());
  await controller.init();
  return { root, preferencesPath, templatePath, controller };
}

test('desktop starts in explicit demo mode without inheriting provider environment', async t => {
  const { controller, root } = await workspace(t);
  assert.deepEqual(controller.snapshot(), { mode: 'mock', ready: true, model: null, configName: null, language: 'zh-TW', busy: false });
  const result = await controller.generate({ prompt: 'Keep ACME-42 exactly and answer in Japanese.', task: 'writing' });
  assert.equal(result.mode, 'mock'); assert.equal(result.promptLanguage, 'en'); assert.equal(result.notesLanguage, 'zh-TW');
  assert.match(result.prompt, /NOT been translated/); assert.deepEqual(await readdir(root), []);
});

test('desktop persists only language and configuration path, never prompt, result or key', async t => {
  const captured = [];
  const { root, preferencesPath, templatePath, controller } = await workspace(t, async (input, config) => {
    captured.push({ input, config }); return { prompt: 'Synthetic optimized output.', mode: config.mode };
  });
  const configPath = join(root, 'provider.env');
  await writeFile(configPath, 'OPTIMIZER_MODE=live\nLLM_MODEL=synthetic-model\nLLM_API_KEY=synthetic-private-key\n');
  await controller.selectConfig(configPath); await controller.setLanguage('ja');
  const body = { prompt: 'Synthetic original request ACME-42.', task: 'coding', targetModel: ' Claude ', promptLanguage: 'zh-Hant', notesLanguage: 'ko' };
  await controller.generate(body);
  assert.equal(captured[0].input.promptLanguage, 'en'); assert.equal(captured[0].input.notesLanguage, 'ja');
  assert.equal(captured[0].input.targetModel, 'Claude'); assert.equal(captured[0].config.apiKey, 'synthetic-private-key');
  const preferences = await readFile(preferencesPath, 'utf8');
  assert.deepEqual(JSON.parse(preferences), { language: 'ja', configFilePath: configPath });
  assert.doesNotMatch(preferences, /synthetic-private-key|ACME-42|optimized output/);
  assert.doesNotMatch(JSON.stringify(controller.snapshot()), /synthetic-private-key|apiKey|baseUrl/);
  const restored = new DesktopController({ preferencesPath, templatePath }); t.after(() => restored.dispose());
  await restored.init(); assert.equal(restored.snapshot().language, 'ja'); assert.equal(restored.snapshot().mode, 'live');
  if (process.platform !== 'win32') assert.equal((await stat(preferencesPath)).mode & 0o777, 0o600);
});

test('invalid selected live config blocks generation across restart instead of substituting demo', async t => {
  let calls = 0;
  const { root, preferencesPath, templatePath, controller } = await workspace(t, async () => { calls++; });
  const path = join(root, 'broken.env'); await writeFile(path, 'OPTIMIZER_MODE=live\nLLM_API_KEY=synthetic-key\n');
  await assert.rejects(controller.selectConfig(path), { code: 'CONFIG_INCOMPLETE' });
  assert.equal(controller.snapshot().mode, 'live'); assert.equal(controller.snapshot().ready, false);
  await assert.rejects(controller.generate({ prompt: 'Do not send.' }), { code: 'CONFIG_INCOMPLETE' }); assert.equal(calls, 0);
  const restored = new DesktopController({ preferencesPath, templatePath }); t.after(() => restored.dispose());
  await restored.init(); assert.equal(restored.snapshot().ready, false); assert.equal(restored.snapshot().mode, 'live');
  await restored.useDemo(); assert.equal(restored.snapshot().ready, true); assert.equal(restored.snapshot().mode, 'mock');
});

test('configuration parsing, malformed preferences and provider failures do not expose raw content', async t => {
  const { root, controller, preferencesPath, templatePath } = await workspace(t, async () => { throw new Error('synthetic-provider-secret-response'); });
  const path = join(root, 'invalid.env'); await writeFile(path, 'OPTIMIZER_MODE=live\nLLM_BASE_URL=https://secret:synthetic-key@provider.invalid/v1\n');
  await assert.rejects(controller.selectConfig(path), { code: 'CONFIG_INVALID' });
  assert.doesNotMatch(JSON.stringify(controller.snapshot()), /synthetic-key|provider\.invalid/);
  await controller.useDemo();
  await assert.rejects(controller.generate({ prompt: 'Request.' }), error => error.code === 'PROVIDER' && !error.message.includes('synthetic-provider-secret-response'));
  await writeFile(preferencesPath, '{ malformed synthetic-private-key');
  const restored = new DesktopController({ preferencesPath, templatePath }); t.after(() => restored.dispose());
  await restored.init(); assert.equal(restored.snapshot().ready, false); assert.equal(restored.snapshot().error.code, 'SETTINGS_READ');
});

test('generation validates input and serializes changes before starting provider work', async t => {
  let finish; let calls = 0;
  const { controller } = await workspace(t, async () => { calls++; return new Promise(resolve => { finish = resolve; }); });
  for (const body of [null, [], { prompt: ' ' }, { prompt: 'x'.repeat(12001) }, { prompt: 'ok', task: 'invalid' }, { prompt: 'ok', targetModel: 'a\nb' }]) {
    await assert.rejects(controller.generate(body), { code: 'INPUT' });
  }
  assert.equal(calls, 0);
  const operation = controller.generate({ prompt: 'Original.' });
  assert.equal(controller.snapshot().busy, true);
  await assert.rejects(controller.generate({ prompt: 'Second.' }), { code: 'BUSY' });
  await assert.rejects(controller.setLanguage('en'), { code: 'BUSY' });
  await assert.rejects(controller.useDemo(), { code: 'BUSY' });
  finish({ prompt: 'Result.' }); await operation; assert.equal(controller.snapshot().busy, false);
});

test('cancellation aborts provider work and discards even a late successful response', async t => {
  let finish, signal;
  const { controller } = await workspace(t, async (_input, _config, cancellation) => {
    signal = cancellation; return new Promise(resolve => { finish = resolve; });
  });
  const operation = controller.generate({ prompt: 'Cancel this synthetic request.' });
  await controller.cancel(); assert.equal(signal.aborted, true); assert.equal(controller.snapshot().busy, true);
  finish({ prompt: 'Late result must not be delivered.' });
  await assert.rejects(operation, { code: 'CANCELLED' }); assert.equal(controller.snapshot().busy, false);
});

test('disposing cancels active work and prevents later generation', async t => {
  let signal, finish;
  const { controller } = await workspace(t, async (_input, _config, cancellation) => {
    signal = cancellation; return new Promise(resolve => { finish = resolve; });
  });
  const operation = controller.generate({ prompt: 'Synthetic input.' }); await controller.dispose();
  assert.equal(signal.aborted, true); assert.equal(controller.snapshot().ready, false);
  finish({ prompt: 'Do not deliver.' }); await assert.rejects(operation, { code: 'CANCELLED' });
  await assert.rejects(controller.generate({ prompt: 'No.' }), { code: 'CLOSED' });
});

test('template is private, public-key-free and created without overwriting edits', async t => {
  const { controller, templatePath } = await workspace(t);
  assert.equal(await controller.createTemplate(), templatePath);
  const template = await readFile(templatePath, 'utf8'); assert.match(template, /^LLM_API_KEY=$/m); assert.match(template, /^OPTIMIZER_MODE=mock$/m);
  if (process.platform !== 'win32') assert.equal((await stat(templatePath)).mode & 0o777, 0o600);
  await writeFile(templatePath, 'User configuration must be retained.');
  assert.equal(await controller.createTemplate(), templatePath); assert.equal(await readFile(templatePath, 'utf8'), 'User configuration must be retained.');
});

test('unsupported UI languages and relative model paths are rejected', async t => {
  const { controller } = await workspace(t);
  await assert.rejects(controller.setLanguage('zh-CN'), { code: 'LANGUAGE' });
  await assert.rejects(controller.selectConfig('relative.env'), { code: 'CONFIG_PATH' });
  assert.equal(controller.snapshot().mode, 'mock');
});
