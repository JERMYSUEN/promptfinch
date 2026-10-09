import { existsSync, mkdirSync, renameSync } from 'node:fs';
import { homedir } from 'node:os';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { terminateInstalledApp } from './app-lifecycle.js';

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
mkdirSync(applications, { recursive: true });
if (existsSync(destination) && existsSync(legacy)) {
  throw new Error('新舊 App 安裝位置同時存在，為避免覆蓋或啟動兩個助手，已停止安裝。請先核對保留版本。');
}
const existing = existsSync(destination) ? destination : existsSync(legacy) ? legacy : null;
if (existing) {
  const id = spawnSync('plutil', ['-extract', 'CFBundleIdentifier', 'raw', '-o', '-', resolve(existing, 'Contents/Info.plist')], { encoding: 'utf8' });
  if (id.stdout.trim() !== 'org.promptstudio.selection') throw new Error('同名 App 不是本工具，請先自行選擇其他安裝位置。');
  run('codesign', ['--verify', '--deep', '--strict', existing]);
  // Request a normal Cocoa termination for only the exact executable in this bundle.
  terminateInstalledApp({
    appPath: existing, bundleID: 'org.promptstudio.selection',
    helperSource: resolve(root, 'scripts/terminate-macos-app.swift'),
    helperBinary: resolve(build, 'terminate-prompt-selection'),
  });
  // Launch Services can briefly retain the old application's quitting state.
  await new Promise(resolve => setTimeout(resolve, 400));
  // Move the owned bundle before updating it, preserving references to its
  // directory. Stable bundle/signing identity and UserDefaults are unchanged.
  if (existing === legacy) renameSync(legacy, destination);
}
run('ditto', [source, destination]);
const args = [destination];
const index = process.argv.indexOf('--config');
if (index >= 0) {
  if (!process.argv[index + 1]) throw new Error('--config 需要設定檔路徑。');
  args.push('--args', '--config', resolve(process.argv[index + 1]));
}
run('open', args);
console.log(`已安裝並開啟 ${destination}`);
