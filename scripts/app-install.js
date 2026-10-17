import {
  accessSync, constants, cpSync, existsSync, lstatSync, mkdirSync, mkdtempSync,
  renameSync, rmSync,
} from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const bundleID = 'org.promptstudio.selection';

function command(name, args) {
  const result = spawnSync(name, args, { encoding: 'utf8' });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${name} 驗證失敗 (${result.status})。`);
  return result.stdout;
}

// Injectable platform checks keep the transaction tests independent of macOS,
// signing identities, running apps and the user's Applications directory.
export function validateMacApp(appPath, {
  metadata = path => JSON.parse(command('plutil', ['-convert', 'json', '-o', '-', path])),
  signature = path => command('codesign', ['--verify', '--deep', '--strict', path]),
  inspect = lstatSync, executable = path => accessSync(path, constants.X_OK),
} = {}) {
  const directory = inspect(appPath);
  if (!directory.isDirectory() || directory.isSymbolicLink()) throw new Error('App 必須是完整資料夾，不能是符號連結。');
  const plist = join(appPath, 'Contents/Info.plist');
  const plistInfo = inspect(plist);
  if (!plistInfo.isFile() || plistInfo.isSymbolicLink()) throw new Error('App 缺少有效的 Info.plist。');
  const info = metadata(plist);
  if (info.CFBundleIdentifier !== bundleID || info.CFBundlePackageType !== 'APPL'
      || info.CFBundleExecutable !== 'PromptSelection'
      || !/^\d+\.\d+\.\d+$/.test(info.CFBundleShortVersionString)
      || !/^\d+$/.test(info.CFBundleVersion)) {
    throw new Error('App 的身分、版本或可執行檔設定不正確，未進行安裝。');
  }
  const binary = join(appPath, 'Contents/MacOS', info.CFBundleExecutable);
  const binaryInfo = inspect(binary);
  if (!binaryInfo.isFile() || binaryInfo.isSymbolicLink() || binaryInfo.size === 0) {
    throw new Error('App 缺少完整的可執行檔，請重新建置。');
  }
  executable(binary);
  signature(appPath);
  return info;
}

const filesystem = {
  exists: existsSync, mkdir: mkdirSync, temporary: mkdtempSync,
  copy: (from, to) => cpSync(from, to, { recursive: true, errorOnExist: true, force: false }),
  rename: renameSync, remove: path => rmSync(path, { recursive: true, force: true }),
};

export function installValidatedApp({ source, destination, existing = null }, {
  fs = filesystem, validate = validateMacApp, terminate = () => {},
} = {}) {
  source = resolve(source);
  destination = resolve(destination);
  existing = existing ? resolve(existing) : null;
  if (source === destination || source === existing) throw new Error('建置來源與安裝位置不能相同。');
  if (existing && dirname(existing) !== dirname(destination)) throw new Error('舊 App 與目標位置必須位於相同資料夾。');
  if (fs.exists(destination) && destination !== existing) throw new Error('安裝位置已存在未指定的 App，未覆蓋。');
  // A failed/partial build must not close or move a usable installed app.
  validate(source);
  if (existing) validate(existing);
  fs.mkdir(dirname(destination), { recursive: true });
  const staging = fs.temporary(join(dirname(destination), '.promptfinch-install-'));
  const candidate = join(staging, basename(destination));
  const backup = join(staging, 'previous.app');
  let oldMoved = false;
  let newMoved = false;
  let preserveStaging = false;
  try {
    fs.copy(source, candidate);
    validate(candidate);
    if (existing) terminate(existing);
    if (existing) {
      fs.rename(existing, backup);
      oldMoved = true;
    }
    fs.rename(candidate, destination);
    newMoved = true;
    validate(destination);
    // Deleting the old bundle happens only after complete replacement validates.
    return { destination };
  } catch (cause) {
    try {
      if (newMoved) fs.rename(destination, candidate);
      if (oldMoved) fs.rename(backup, existing);
    } catch (recovery) {
      preserveStaging = true;
      throw new Error(`安裝失敗，而且自動還原未完成。舊 App 備份保留於 ${backup}。請保留此資料夾並手動還原。`, { cause: new AggregateError([cause, recovery]) });
    }
    const error = new Error(oldMoved ? '安裝失敗，已還原舊 App。' : '安裝失敗，原有 App 未被覆蓋。', { cause });
    if (oldMoved) error.restoredPath = existing;
    throw error;
  } finally {
    if (!preserveStaging) fs.remove(staging);
  }
}
