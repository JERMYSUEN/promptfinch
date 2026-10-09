import { createHash, randomUUID } from 'node:crypto';
import { copyFile, lstat, mkdir, readFile, readdir, readlink, rename, rm, stat, symlink, writeFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { dirname, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

export const BACKEND_FILES = [
  'server.js',
  'lib/optimizer.js',
  'public/index.html',
  'public/app.js',
  'public/style.css',
  'public/favicon.svg',
];

export async function computeBackendID(sourceRoot) {
  const hash = createHash('sha256');
  for (const relative of BACKEND_FILES) {
    const content = await readFile(resolve(sourceRoot, relative));
    hash.update(relative);
    hash.update('\0');
    hash.update(content);
    hash.update('\0');
  }
  return hash.digest('hex');
}

async function verifyBackend(root, id) {
  for (const relative of BACKEND_FILES.filter(file => file.endsWith('.js'))) {
    const checked = spawnSync(process.execPath, ['--check', resolve(root, relative)], { encoding: 'utf8' });
    if (checked.error) throw checked.error;
    if (checked.status !== 0) throw new Error(`後端語法檢查失敗：${relative}`);
  }

  const serverURL = `${pathToFileURL(resolve(root, 'server.js')).href}?backend=${id}`;
  const optimizerURL = `${pathToFileURL(resolve(root, 'lib/optimizer.js')).href}?backend=${id}`;
  const { createApp } = await import(serverURL);
  const { readConfig } = await import(optimizerURL);
  const config = readConfig({
    OPTIMIZER_MODE: 'mock', HOST: '127.0.0.1', PORT: '0',
    PROMPT_STUDIO_BACKEND_ID: id,
  });
  const server = createApp(config);
  await new Promise((resolveListen, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolveListen);
  });
  try {
    const address = server.address();
    const origin = `http://127.0.0.1:${address.port}`;
    const configResponse = await fetch(`${origin}/api/config`);
    const responseConfig = await configResponse.json();
    if (!configResponse.ok || responseConfig.service !== 'prompt-studio' || responseConfig.backendID !== id
        || responseConfig.mode !== 'mock' || responseConfig.ready !== true) {
      throw new Error('外部後端設定端點驗證失敗。');
    }
    const optimizeResponse = await fetch(`${origin}/api/optimize`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ prompt: '隔離後端更新檢查', task: 'general', targetModel: '', promptLanguage: 'en' }),
    });
    const output = await optimizeResponse.json();
    if (!optimizeResponse.ok || output.mode !== 'mock' || !output.prompt.includes('NOT been translated')) {
      throw new Error('外部後端 mock 生成流程驗證失敗。');
    }
  } finally {
    server.closeAllConnections();
    await new Promise(resolveClose => server.close(resolveClose));
  }
}

export async function stageBackendRelease(sourceRoot, backendRoot) {
  const id = await computeBackendID(sourceRoot);
  const releasesRoot = join(backendRoot, 'releases');
  await mkdir(releasesRoot, { recursive: true, mode: 0o700 });
  const stagingRoot = join(releasesRoot, `.staging-${process.pid}-${randomUUID()}`);
  const releaseRoot = join(releasesRoot, id);
  await mkdir(stagingRoot, { mode: 0o700 });
  try {
    for (const relative of BACKEND_FILES) {
      const destination = join(stagingRoot, relative);
      await mkdir(dirname(destination), { recursive: true, mode: 0o700 });
      await copyFile(resolve(sourceRoot, relative), destination);
    }
    await writeFile(join(stagingRoot, 'package.json'), JSON.stringify({ type: 'module', engines: { node: '>=22' } }), { mode: 0o600 });
    await writeFile(join(stagingRoot, '.backend-id'), `${id}\n`, { mode: 0o600 });
    await verifyBackend(stagingRoot, id);

    let existingRelease = false;
    try { await lstat(releaseRoot); existingRelease = true; }
    catch (error) { if (error?.code !== 'ENOENT') throw error; }
    if (existingRelease) {
      const existingID = (await readFile(join(releaseRoot, '.backend-id'), 'utf8')).trim();
      const actualID = await computeBackendID(releaseRoot);
      if (existingID !== id || actualID !== id) throw new Error('同版本外部後端目錄內容與版本識別不符，未覆蓋任何可用版本。');
      await rm(stagingRoot, { recursive: true, force: true });
    } else {
      await rename(stagingRoot, releaseRoot);
    }
    return { id, releaseRoot, relativeTarget: `releases/${id}` };
  } catch (error) {
    await rm(stagingRoot, { recursive: true, force: true });
    throw error;
  }
}

export async function currentBackendTarget(backendRoot) {
  const current = join(backendRoot, 'current');
  try {
    const info = await lstat(current);
    if (!info.isSymbolicLink()) throw new Error('外部後端 current 不是受管理的符號連結，為保護現有資料不會覆蓋。');
    const target = await readlink(current);
    if (!/^releases\/[a-f0-9]{64}$/.test(target)) throw new Error('外部後端 current 指向非預期位置，未變更。');
    return target;
  } catch (error) {
    if (error?.code === 'ENOENT') return null;
    throw error;
  }
}

export async function activateBackendTarget(backendRoot, target) {
  if (target !== null && !/^releases\/[a-f0-9]{64}$/.test(target)) throw new Error('拒絕切換至非預期的後端路徑。');
  const previous = await currentBackendTarget(backendRoot);
  const current = join(backendRoot, 'current');
  const temporary = join(backendRoot, `.current-${process.pid}-${randomUUID()}`);
  if (target === null) {
    if (previous !== null) await rm(current);
    return previous;
  }
  await symlink(target, temporary);
  try { await rename(temporary, current); }
  catch (error) { await rm(temporary, { force: true }); throw error; }
  return previous;
}

export async function pruneBackendReleases(backendRoot, keep = 2, preserve = []) {
  const releasesRoot = join(backendRoot, 'releases');
  const active = await currentBackendTarget(backendRoot);
  const activeID = active?.slice('releases/'.length);
  const entries = await Promise.all((await readdir(releasesRoot, { withFileTypes: true }))
    .filter(entry => entry.isDirectory() && /^[a-f0-9]{64}$/.test(entry.name))
    .map(async entry => ({ id: entry.name, modified: (await stat(join(releasesRoot, entry.name))).mtimeMs })));
  entries.sort((a, b) => b.modified - a.modified);
  const retain = new Set(entries.slice(0, keep).map(entry => entry.id));
  if (activeID) retain.add(activeID);
  for (const target of preserve) if (target) retain.add(target.slice('releases/'.length));
  for (const { id } of entries) if (!retain.has(id)) await rm(join(releasesRoot, id), { recursive: true, force: true });
}
