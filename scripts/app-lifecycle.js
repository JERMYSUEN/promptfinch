import { spawnSync } from 'node:child_process';
import { resolve } from 'node:path';

function run(command, args, message) {
  const result = spawnSync(command, args, { encoding: 'utf8', stdio: 'pipe' });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(message || `${command} 無法完成。`);
  return result.stdout;
}

export function installedAppPIDs(appPath) {
  const executable = resolve(appPath, 'Contents/MacOS/PromptSelection');
  const output = run('ps', ['-axo', 'pid=,comm='], '無法確認本工具 App 的執行狀態。');
  return output.split('\n').flatMap(line => {
    const match = line.match(/^\s*(\d+)\s+(.+)$/);
    return match && match[2].trim() === executable ? [Number(match[1])] : [];
  });
}

export function terminateInstalledApp({ appPath, bundleID, helperSource, helperBinary }) {
  const executable = resolve(appPath, 'Contents/MacOS/PromptSelection');
  const pids = installedAppPIDs(appPath);
  if (!pids.length) return;

  run('xcrun', ['swiftc', '-swift-version', '5', '-framework', 'AppKit', helperSource, '-o', helperBinary],
    '無法編譯 App 正常退出 helper；未改動執行中的 App。');
  for (const pid of pids) {
    run(helperBinary, [String(pid), bundleID, executable], `App PID ${pid} 無法正常結束；未覆蓋安裝。`);
  }
  if (installedAppPIDs(appPath).length) throw new Error('App 尚未結束，未覆蓋安裝。');
}
