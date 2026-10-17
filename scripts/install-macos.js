import { existsSync, mkdirSync } from 'node:fs';
import { homedir } from 'node:os';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { terminateInstalledApp } from './app-lifecycle.js';
import { installValidatedApp } from './app-install.js';

if (process.platform !== 'darwin') throw new Error('安裝需要 macOS。');
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const build = resolve(root, 'build');
const source = resolve(root, 'build/PromptFinch.app');
if (!existsSync(source)) throw new Error('請先執行 npm run build:mac。');
const applications = resolve(homedir(), 'Applications');
const destination = resolve(applications, 'PromptFinch.app');
const legacy = resolve(applications, 'Prompt 選取助手.app');
function run(name, args) {
  const result = spawnSync(name, args, { stdio: 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${name} 未能完成 (${result.status})。`);
}
const index = process.argv.indexOf('--config');
if (index >= 0 && !process.argv[index + 1]) throw new Error('--config 需要設定檔路徑。');
const launch = path => run('open', [path, ...(index >= 0 ? ['--args', '--config', resolve(process.argv[index + 1])] : [])]);
if (existsSync(destination) && existsSync(legacy)) {
  throw new Error('新舊 App 安裝位置同時存在，為避免覆蓋或啟動兩個助手，已停止安裝。請先核對保留版本。');
}
const existing = existsSync(destination) ? destination : existsSync(legacy) ? legacy : null;
try {
  installValidatedApp({ source, destination, existing }, {
    terminate: appPath => {
      mkdirSync(build, { recursive: true });
      terminateInstalledApp({
        appPath, bundleID: 'org.promptstudio.selection',
        helperSource: resolve(root, 'scripts/terminate-macos-app.swift'),
        helperBinary: resolve(build, 'terminate-prompt-selection'),
      });
    },
  });
} catch (error) {
  if (error.restoredPath) {
    try { launch(error.restoredPath); }
    catch { console.error('舊 App 已還原，但無法自動重新開啟；請手動開啟。'); }
  }
  throw error;
}
// Launch Services can briefly retain the old application's quitting state.
await new Promise(resolve => setTimeout(resolve, 400));
try { launch(destination); }
catch (cause) { throw new Error(`App 已完成安裝，但無法自動開啟。請手動開啟 ${destination}。`, { cause }); }
console.log(`已安裝並開啟 ${destination}`);
