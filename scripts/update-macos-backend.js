import { existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { activateBackendTarget, currentBackendTarget, pruneBackendReleases, stageBackendRelease } from './backend-release.js';
import { installedAppPIDs, terminateInstalledApp } from './app-lifecycle.js';

if (process.platform !== 'darwin') throw new Error('外部後端更新需要 macOS。');
const sourceRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const renamedApp = resolve(homedir(), 'Applications/PromptFinch.app');
const app = existsSync(renamedApp) ? renamedApp : resolve(homedir(), 'Applications/Prompt 選取助手.app');
const backendRoot = resolve(homedir(), 'Library/Application Support/PromptSelection/backend');
const bundleID = 'org.promptstudio.selection';
const origin = 'http://127.0.0.1:3210';
const terminateHelperSource = resolve(sourceRoot, 'scripts/terminate-macos-app.swift');
const terminateHelperBinary = resolve(sourceRoot, 'build/terminate-prompt-selection');

function run(command, args, { quiet = false } = {}) {
  const result = spawnSync(command, args, { encoding: 'utf8', stdio: quiet ? 'pipe' : 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} 未能完成${quiet && result.stderr ? `：${result.stderr.trim()}` : '。'}`);
  return result;
}

function portListener() {
  const result = spawnSync('lsof', ['-nP', '-iTCP:3210', '-sTCP:LISTEN', '-t'], { encoding: 'utf8' });
  if (result.error) throw result.error;
  if (result.status === 0) return result.stdout.trim().split(/\s+/).filter(Boolean);
  if (result.status === 1) return [];
  throw new Error('無法確認 3210 埠是否空閒，未切換後端。');
}

async function waitForBackend(id, timeoutMs = 12000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(`${origin}/api/config`, { signal: AbortSignal.timeout(1000) });
      const config = await response.json();
      if (response.ok && config.service === 'prompt-studio' && config.backendID === id && backendOwnedByApp(id)) return config;
    } catch { /* Keep polling while the app starts its owned backend. */ }
    await new Promise(resolveWait => setTimeout(resolveWait, 200));
  }
  throw new Error(`後端沒有以預期版本 ${id.slice(0, 12)} 啟動。`);
}

function backendOwnedByApp(id) {
  const listeners = portListener();
  const appPIDs = installedAppPIDs(app).map(String);
  if (listeners.length !== 1 || appPIDs.length !== 1) return false;
  const expectedScript = resolve(backendRoot, `releases/${id}/server.js`);
  const detail = spawnSync('ps', ['-p', listeners[0], '-o', 'ppid=,args='], { encoding: 'utf8' });
  if (detail.error || detail.status !== 0) return false;
  const match = detail.stdout.trim().match(/^(\d+)\s+(.+)$/);
  return Boolean(match && match[2].includes(expectedScript) && appPIDs.includes(match[1]));
}

async function quitAppIfRunning() {
  if (!installedAppPIDs(app).length) return;
  terminateInstalledApp({ appPath: app, bundleID, helperSource: terminateHelperSource, helperBinary: terminateHelperBinary });
}

function openApp() { run('open', ['-a', app]); }

if (!existsSync(app)) throw new Error('找不到已安裝的「PromptFinch.app」。請先安裝一次原生 App。');
const installedID = run('plutil', ['-extract', 'CFBundleIdentifier', 'raw', '-o', '-', resolve(app, 'Contents/Info.plist')], { quiet: true }).stdout.trim();
if (installedID !== bundleID) throw new Error('安裝位置中的同名 App 不是本工具，已停止更新。');

// Stage, syntax-check and run a mock HTTP smoke test before stopping the app.
const candidate = await stageBackendRelease(sourceRoot, backendRoot);
const previous = await currentBackendTarget(backendRoot);
await quitAppIfRunning();
const listeners = portListener();
if (listeners.length) throw new Error(`3210 埠仍由 PID ${listeners.join(', ')} 使用。沒有終止該程序，也未切換後端。`);

let switched = false;
try {
  await activateBackendTarget(backendRoot, candidate.relativeTarget);
  switched = true;
  openApp();
  const config = await waitForBackend(candidate.id);
  await pruneBackendReleases(backendRoot, 2, [previous]);
  console.log(`外部後端更新完成：${candidate.id}\n模式：${config.mode}；模型：${config.generationModel ?? '未設定（mock）'}\nApp 主執行檔未重建。`);
} catch (error) {
  if (!switched) throw error;
  try {
    await quitAppIfRunning();
    if (portListener().length) throw new Error('3210 埠被其他程序占用，保留舊版指向但無法自動重啟。');
    await activateBackendTarget(backendRoot, previous);
    openApp();
    if (previous) await waitForBackend(previous.slice('releases/'.length), 12000);
    console.error(`更新失敗，已回復至先前後端：${previous ?? '沒有先前版本'}。`);
  } catch (rollbackError) {
    console.error(`後端更新失敗：${error.message}\n自動回復未完全啟動：${rollbackError.message}\ncurrent 已盡可能回復；請重新開啟 App。`);
  }
  process.exitCode = 1;
}
