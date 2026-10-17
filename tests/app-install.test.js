import test from 'node:test';
import assert from 'node:assert/strict';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { installValidatedApp, validateMacApp } from '../scripts/app-install.js';

const validInfo = {
  CFBundleIdentifier: 'org.promptstudio.selection', CFBundlePackageType: 'APPL',
  CFBundleExecutable: 'PromptSelection', CFBundleShortVersionString: '1.1.0', CFBundleVersion: '12',
};

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'promptfinch-install-test-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const source = join(root, 'build', 'PromptFinch.app');
  const destination = join(root, 'Applications', 'PromptFinch.app');
  function app(path, marker) {
    mkdirSync(join(path, 'Contents/MacOS'), { recursive: true });
    writeFileSync(join(path, 'Contents/Info.plist'), JSON.stringify(validInfo));
    writeFileSync(join(path, 'Contents/MacOS/PromptSelection'), marker, { mode: 0o755 });
    writeFileSync(join(path, 'signed-marker'), marker);
  }
  app(source, 'new');
  app(destination, 'old');
  const validate = path => validateMacApp(path, {
    metadata: plist => JSON.parse(readFileSync(plist, 'utf8')),
    signature: path => assert.ok(existsSync(join(path, 'signed-marker'))),
  });
  const fs = {
    exists: existsSync, mkdir: mkdirSync, temporary: mkdtempSync,
    copy: (from, to) => cpSync(from, to, { recursive: true }),
    rename: renameSync, remove: path => rmSync(path, { recursive: true, force: true }),
  };
  const marker = path => readFileSync(join(path, 'signed-marker'), 'utf8');
  return { root, source, destination, existing: destination, validate, fs, marker };
}

test('安裝先驗來源與完整副本，停止舊 App 後替換整個 bundle，不合併舊檔', t => {
  const f = fixture(t);
  writeFileSync(join(f.destination, 'old-only-file'), 'must not survive');
  const events = [];
  installValidatedApp(f, {
    fs: f.fs,
    validate: path => { f.validate(path); events.push(['validate', path]); },
    terminate: path => events.push(['terminate', path]),
  });
  assert.equal(f.marker(f.destination), 'new');
  assert.equal(existsSync(join(f.destination, 'old-only-file')), false);
  const stop = events.findIndex(([type]) => type === 'terminate');
  assert.equal(stop, 3);
  assert.match(events[2][1], /\.promptfinch-install-/);
  assert.deepEqual(readdirSync(join(f.root, 'Applications')), ['PromptFinch.app']);
});

test('不完整建置、錯誤身分與不可執行來源均不能停止舊 App', t => {
  const f = fixture(t);
  const binary = join(f.source, 'Contents/MacOS/PromptSelection');
  let stopped = false;
  writeFileSync(binary, '');
  assert.throws(() => installValidatedApp(f, { validate: f.validate, terminate: () => { stopped = true; } }), /可執行檔/);
  assert.equal(stopped, false);
  writeFileSync(binary, 'valid');
  writeFileSync(join(f.source, 'Contents/Info.plist'), JSON.stringify({ ...validInfo, CFBundleIdentifier: 'other.app' }));
  assert.throws(() => installValidatedApp(f, { validate: f.validate, terminate: () => { stopped = true; } }), /身分/);
  assert.equal(stopped, false);
  assert.equal(f.marker(f.destination), 'old');
  assert.throws(() => validateMacApp(f.destination, {
    metadata: () => validInfo, signature: () => {},
    executable: () => { throw new Error('not executable'); },
  }), /not executable/);
});

test('副本複製失敗時舊 App 仍然可用且不被停止', t => {
  const f = fixture(t);
  let stopped = false;
  f.fs.copy = () => { throw new Error('disk full'); };
  assert.throws(() => installValidatedApp(f, { fs: f.fs, validate: f.validate, terminate: () => { stopped = true; } }), /未被覆蓋/);
  assert.equal(stopped, false);
  assert.equal(f.marker(f.destination), 'old');
  assert.deepEqual(readdirSync(join(f.root, 'Applications')), ['PromptFinch.app']);
});

test('staged App 簽章驗證失敗不能停止或替換舊 App', t => {
  const f = fixture(t);
  let stopped = false;
  const validate = path => {
    f.validate(path);
    if (path.includes('.promptfinch-install-')) throw new Error('signature mismatch');
  };
  assert.throws(() => installValidatedApp(f, { fs: f.fs, validate, terminate: () => { stopped = true; } }), /未被覆蓋/);
  assert.equal(stopped, false);
  assert.equal(f.marker(f.destination), 'old');
});

test('無法正常結束舊 App 時不改動已安裝 bundle', t => {
  const f = fixture(t);
  assert.throws(() => installValidatedApp(f, { fs: f.fs, validate: f.validate, terminate: () => { throw new Error('still running'); } }), /未被覆蓋/);
  assert.equal(f.marker(f.destination), 'old');
});

test('swap 失敗會把舊 App 還原到原路徑，包含舊名稱遷移', t => {
  const f = fixture(t);
  const legacy = join(f.root, 'Applications', 'Legacy.app');
  renameSync(f.destination, legacy);
  f.existing = legacy;
  f.fs.rename = (from, to) => {
    if (to === f.destination) throw new Error('swap unavailable');
    renameSync(from, to);
  };
  assert.throws(() => installValidatedApp(f, { fs: f.fs, validate: f.validate }), error => {
    assert.equal(error.restoredPath, legacy);
    assert.match(error.message, /已還原/);
    return true;
  });
  assert.equal(f.marker(legacy), 'old');
  assert.equal(existsSync(f.destination), false);
});

test('替換後驗證失敗會移除新候選並還原舊 App', t => {
  const f = fixture(t);
  let destinationChecks = 0;
  const validate = path => {
    f.validate(path);
    if (path === f.destination && ++destinationChecks === 2) throw new Error('post-swap verification failed');
  };
  assert.throws(() => installValidatedApp(f, { fs: f.fs, validate }), /已還原/);
  assert.equal(f.marker(f.destination), 'old');
});

test('回滾也失敗時保留完整舊 App 備份，錯誤提供還原位置', t => {
  const f = fixture(t);
  f.fs.rename = (from, to) => {
    if (to === f.destination) throw new Error('destination blocked');
    renameSync(from, to);
  };
  assert.throws(() => installValidatedApp(f, { fs: f.fs, validate: f.validate }), /自動還原未完成.*previous\.app/);
  const staging = readdirSync(join(f.root, 'Applications')).find(name => name.startsWith('.promptfinch-install-'));
  assert.ok(staging);
  assert.equal(f.marker(join(f.root, 'Applications', staging, 'previous.app')), 'old');
});
