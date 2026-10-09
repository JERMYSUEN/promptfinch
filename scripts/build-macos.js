import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { BACKEND_FILES, computeBackendID } from './backend-release.js';

if (process.platform !== 'darwin') throw new Error('原生 App 必須在 macOS 建置。');
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const build = resolve(root, 'build');
const app = resolve(build, 'PromptFinch.app');
const contents = resolve(app, 'Contents');
const resources = resolve(contents, 'Resources');
const cache = resolve(build, 'swift-cache');
const bundleID = 'org.promptstudio.selection';
const signingConfig = process.env.PROMPT_STUDIO_SIGNING_CONFIG
  || resolve(homedir(), 'Library/Application Support/PromptSelection/code-signing.json');

function run(command, args) {
  const result = spawnSync(command, args, { cwd: root, stdio: 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} 建置失敗 (${result.status})。`);
}

// Remove only our generated bundle; never touch user configuration or installed apps.
rmSync(app, { recursive: true, force: true });
mkdirSync(resolve(contents, 'MacOS'), { recursive: true });
mkdirSync(resources, { recursive: true });
mkdirSync(cache, { recursive: true });
cpSync(resolve(root, 'macos/Info.plist'), resolve(contents, 'Info.plist'));
if (process.env.PROMPT_STUDIO_BUILD_NUMBER) {
  if (!/^\d+$/.test(process.env.PROMPT_STUDIO_BUILD_NUMBER)) throw new Error('PROMPT_STUDIO_BUILD_NUMBER 必須是整數。');
  run('plutil', ['-replace', 'CFBundleVersion', '-string', process.env.PROMPT_STUDIO_BUILD_NUMBER, resolve(contents, 'Info.plist')]);
}
const architecture = process.arch === 'arm64' ? 'arm64' : 'x86_64';
const compile = ['swiftc', '-swift-version', '5', '-O', '-module-cache-path', cache, '-target', `${architecture}-apple-macosx13.0`];
run('xcrun', [...compile, '-parse-as-library', ...['Localization', 'Core', 'Backend', 'Selection', 'Watcher', 'App'].map(name => resolve(root, `macos/Sources/${name}.swift`)), '-o', resolve(contents, 'MacOS/PromptSelection')]);

// Explicit allowlist: .env, logs, tests, artifacts and dependencies are never bundled.
const backend = resolve(resources, 'backend');
mkdirSync(backend, { recursive: true });
for (const name of BACKEND_FILES) {
  const target = resolve(backend, name);
  mkdirSync(dirname(target), { recursive: true });
  cpSync(resolve(root, name), target);
}
writeFileSync(resolve(backend, 'package.json'), JSON.stringify({ type: 'module', engines: { node: '>=22' } }, null, 2));
const backendID = await computeBackendID(root);
writeFileSync(resolve(backend, '.backend-id'), `${backendID}\n`);
cpSync(resolve(root, '.env.deepseek.example'), resolve(resources, 'deepseek.env.example'));

const iconset = resolve(build, 'AppIcon.iconset');
mkdirSync(iconset, { recursive: true });
run('xcrun', [...compile, resolve(root, 'macos/Icon.swift'), '-o', resolve(build, 'make-icon')]);
run(resolve(build, 'make-icon'), [iconset]);
run('iconutil', ['-c', 'icns', iconset, '-o', resolve(resources, 'AppIcon.icns')]);
run('plutil', ['-lint', resolve(contents, 'Info.plist')]);

let signing = null;
if (existsSync(signingConfig)) {
  let config;
  try { config = JSON.parse(readFileSync(signingConfig, 'utf8')); }
  catch { throw new Error('本機簽章設定檔無法讀取；為避免授權失效，停止 ad-hoc 建置。'); }
  const fingerprint = String(config.certificateSHA1 || '').replaceAll(':', '').toUpperCase();
  if (config.bundleID !== bundleID || !/^[A-F0-9]{40}$/.test(fingerprint)) {
    throw new Error('本機簽章設定不完整或 App bundle ID 不符。');
  }
  const identities = spawnSync('security', ['find-identity', '-v', '-p', 'codesigning'], { encoding: 'utf8' });
  if (identities.error) throw identities.error;
  if (identities.status !== 0 || !identities.stdout.includes(fingerprint)) {
    throw new Error(`固定簽章憑證 ${fingerprint} 不在有效的本機 Code Signing 身分中。請先修復 login Keychain；不會退回 ad-hoc 簽章。`);
  }
  const requirement = `designated => identifier "${bundleID}" and certificate leaf = H"${fingerprint}"\n`;
  const requirementFile = resolve(tmpdir(), `prompt-selection-requirement-${process.pid}.txt`);
  writeFileSync(requirementFile, requirement, { mode: 0o600 });
  try { run('codesign', ['--force', '--sign', fingerprint, '-r', requirementFile, app]); }
  finally { rmSync(requirementFile, { force: true }); }
  const detail = spawnSync('codesign', ['-d', '-r', '-', app], { encoding: 'utf8' });
  const requirementOutput = `${detail.stdout}\n${detail.stderr}`;
  if (detail.status !== 0 || !requirementOutput.toLowerCase().includes(`certificate leaf = h"${fingerprint.toLowerCase()}"`)) {
    throw new Error('簽章完成但 designated requirement 未綁定固定憑證，拒絕使用這個建置。');
  }
  signing = `固定本機簽章 ${fingerprint}`;
} else {
  run('codesign', ['--force', '--sign', '-', app]);
  console.warn(`尚未設定固定簽章 (${signingConfig})；這次使用 ad-hoc 簽章，可能使 macOS 輔助使用授權失效。`);
}
run('codesign', ['--verify', '--deep', '--strict', app]);
console.log(`已建置 ${app}\n後端版本：${backendID}\n簽章：${signing || 'ad-hoc'}`);
