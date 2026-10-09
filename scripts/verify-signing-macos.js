import { resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

if (process.platform !== 'darwin') throw new Error('簽章連續性驗證需要 macOS。');
const [firstArg, secondArg] = process.argv.slice(2);
if (!firstArg || !secondArg) throw new Error('用法：node scripts/verify-signing-macos.js <舊版本.app> <新版本.app>');
const firstPath = resolve(firstArg);
const secondPath = resolve(secondArg);

function run(args) {
  const result = spawnSync('codesign', args, { encoding: 'utf8' });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`codesign 驗證失敗：${(result.stderr || result.stdout).trim()}`);
  return `${result.stdout}\n${result.stderr}`;
}

function inspect(path) {
  run(['--verify', '--deep', '--strict', path]);
  const detail = run(['-dv', '--verbose=4', path]);
  const display = run(['-d', '-r', '-', path]);
  const cdhash = detail.match(/\bCDHash=([a-f0-9]+)/i)?.[1];
  const identifier = detail.match(/\bIdentifier=(\S+)/)?.[1];
  const requirement = display.match(/designated => (.+)$/m)?.[1]?.trim();
  if (!cdhash || !identifier || !requirement) throw new Error(`無法讀取簽章識別：${path}`);
  return { path, cdhash, identifier, requirement };
}

const first = inspect(firstPath);
const second = inspect(secondPath);
if (first.identifier !== second.identifier) throw new Error('兩個版本的 bundle ID 不相同。');
if (first.cdhash === second.cdhash) throw new Error('兩個版本 CDHash 相同；請先產生不同的 App 執行檔。');
run(['--verify', '--deep', '--strict', `-R=${first.requirement}`, secondPath]);
run(['--verify', '--deep', '--strict', `-R=${second.requirement}`, firstPath]);
console.log(`兩版簽章都有效，bundle ID 相同，CDHash 不同，且 designated requirement 雙向相符。\n舊版 CDHash：${first.cdhash}\n新版 CDHash：${second.cdhash}\n權限實際留存仍須在新版 App 內確認 AX 狀態及取字監聽。`);
