import test from 'node:test';
import assert from 'node:assert/strict';
import { cp, mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { activateBackendTarget, computeBackendID, currentBackendTarget, stageBackendRelease } from '../scripts/backend-release.js';

const projectRoot = resolve(fileURLToPath(new URL('..', import.meta.url)));

async function isolatedProject(t) {
  const root = await mkdtemp(join(tmpdir(), 'prompt-studio-backend-test-'));
  const source = join(root, 'source');
  const backend = join(root, 'support', 'backend');
  await mkdir(source, { recursive: true });
  for (const item of ['server.js', 'lib/optimizer.js', 'public/index.html', 'public/app.js', 'public/style.css', 'public/favicon.svg']) {
    const from = join(projectRoot, item);
    const to = join(source, item);
    await mkdir(join(to, '..'), { recursive: true });
    await cp(from, to);
  }
  t.after(() => rm(root, { recursive: true, force: true }));
  return { root, source, backend };
}

test('後端版本在隔離目錄完成語法、mock HTTP 流程與原子切換', async t => {
  const { source, backend } = await isolatedProject(t);
  const staged = await stageBackendRelease(source, backend);
  assert.match(staged.id, /^[a-f0-9]{64}$/);
  assert.equal(await readFile(join(staged.releaseRoot, '.backend-id'), 'utf8'), `${staged.id}\n`);
  assert.equal(await currentBackendTarget(backend), null);

  await activateBackendTarget(backend, staged.relativeTarget);
  assert.equal(await currentBackendTarget(backend), staged.relativeTarget);

  const originalID = await computeBackendID(source);
  await writeFile(join(source, 'public/style.css'), `${await readFile(join(source, 'public/style.css'), 'utf8')}\n/* staged update */\n`);
  const updated = await stageBackendRelease(source, backend);
  assert.notEqual(updated.id, originalID);
  await activateBackendTarget(backend, updated.relativeTarget);
  assert.equal(await currentBackendTarget(backend), updated.relativeTarget);

  await activateBackendTarget(backend, staged.relativeTarget);
  assert.equal(await currentBackendTarget(backend), staged.relativeTarget);
});

test('不合法候選後端不能影響 current 版本', async t => {
  const { source, backend } = await isolatedProject(t);
  const good = await stageBackendRelease(source, backend);
  await activateBackendTarget(backend, good.relativeTarget);
  await writeFile(join(source, 'server.js'), 'export function {');
  await assert.rejects(stageBackendRelease(source, backend), /語法檢查失敗/);
  assert.equal(await currentBackendTarget(backend), good.relativeTarget);
});

test('不覆寫被竄改的同識別版本資料夾', async t => {
  const { source, backend } = await isolatedProject(t);
  const staged = await stageBackendRelease(source, backend);
  await writeFile(join(staged.releaseRoot, 'public/style.css'), 'unexpected');
  await assert.rejects(stageBackendRelease(source, backend), /內容與版本識別不符/);
});
