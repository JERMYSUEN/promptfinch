import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { lstatSync, mkdtempSync, readFileSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { parseEnv } from 'node:util';
import { BACKEND_FILES, computeBackendID } from './backend-release.js';
import { validateMacApp } from './app-install.js';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const version = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')).version;
const releaseIndex = process.argv.indexOf('--release-dir');
if (releaseIndex >= 0 && !process.argv[releaseIndex + 1]) throw new Error('--release-dir needs a directory.');
const release = releaseIndex < 0 ? join(root, 'release') : resolve(process.argv[releaseIndex + 1]);
const sourceOnly = process.argv.includes('--source-only');
const artifactsOnly = process.argv.includes('--artifacts-only');
const sourceName = `PromptFinch-source-v${version}`;
const sourceArchiveName = `${sourceName}.zip`;
const sha256 = path => createHash('sha256').update(readFileSync(path)).digest('hex');
const privatePathPatterns = [['', 'Users', ''], ['', 'private', 'var', 'folders', ''], ['', 'var', 'folders', '']].map(parts => parts.join('/'));
const templates = new Set(['.env.example', '.env.deepseek.example', 'deepseek.env.example']);

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { cwd: root, encoding: 'utf8', ...options });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} failed (${result.status}).\n${result.stdout || ''}${result.stderr || ''}`);
  return `${result.stdout || ''}${result.stderr || ''}`;
}

function auditTree(directory) {
  const files = [];
  function visit(current, prefix = '') {
    for (const name of readdirSync(current)) {
      const path = join(current, name);
      const relative = prefix ? `${prefix}/${name}` : name;
      const info = lstatSync(path);
      assert.ok(!info.isSymbolicLink(), `Archive symlink: ${relative}`);
      assert.ok(!['node_modules', '.git', '.DS_Store', '.brooks-lint-history.json', 'artifacts', 'settings.env', 'code-signing.json'].includes(name)
        && !/\.log$/.test(name) && !(name.startsWith('.env') && !templates.has(name))
        && !(/\.env(?:\.|$)/.test(name) && !templates.has(name)), `Private/generated archive file: ${relative}`);
      if (info.isDirectory()) visit(path, relative);
      else {
        assert.ok(info.isFile(), `Nonregular archive file: ${relative}`);
        const content = readFileSync(path);
        for (const pattern of privatePathPatterns) assert.ok(!content.includes(Buffer.from(pattern)), `Private path in ${relative}`);
        if (templates.has(name)) {
          for (const [key, value] of Object.entries(parseEnv(content.toString('utf8')))) {
            if (/(?:API_KEY|TOKEN|SECRET|PASSWORD)$/.test(key)) assert.equal(value.trim(), '', `Credential in ${relative}`);
          }
        }
        files.push(relative);
      }
    }
  }
  visit(directory);
  return files.sort();
}

function unpack(archive, destination, expectedParent) {
  const entries = run('unzip', ['-Z', '-1', archive]).trim().split('\n');
  assert.ok(entries.length > 0 && entries.every(entry => !entry.startsWith('/') && !entry.includes('\\')
    && !entry.split('/').some(part => part === '..' || part === '.')
    && (entry === `${expectedParent}/` || entry.startsWith(`${expectedParent}/`))), 'Unexpected ZIP path.');
  assert.ok(!/^l/m.test(run('unzip', ['-Z', '-l', archive])), 'ZIP symlinks are not allowed.');
  run('unzip', ['-q', archive, '-d', destination]);
  return join(destination, expectedParent);
}

async function smoke(source) {
  // Explicit config plus importing the module avoids npm start and .env loading.
  const { createApp } = await import(pathToFileURL(join(source, 'server.js')).href);
  const { readConfig } = await import(pathToFileURL(join(source, 'lib/optimizer.js')).href);
  const id = await computeBackendID(source);
  const server = createApp(readConfig({ OPTIMIZER_MODE: 'mock', HOST: '127.0.0.1', PORT: '0', PROMPT_STUDIO_BACKEND_ID: id }));
  try {
    await new Promise((accept, reject) => {
      server.once('error', reject);
      server.listen(0, '127.0.0.1', accept);
    });
    const base = `http://127.0.0.1:${server.address().port}`;
    const configResponse = await fetch(`${base}/api/config`);
    assert.equal(configResponse.status, 200);
    const config = await configResponse.json();
    assert.equal(config.mode, 'mock');
    assert.equal(config.ready, true);
    assert.equal(config.backendID, id);
    const page = await fetch(base);
    assert.equal(page.status, 200);
    assert.match(await page.text(), /PromptFinch/);
    const invalid = await fetch(`${base}/api/optimize`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ prompt: '   ' }),
    });
    assert.equal(invalid.status, 400);
    const response = await fetch(`${base}/api/optimize`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ prompt: 'Create ACME-42 setup instructions. Answer in Traditional Chinese.', task: 'writing', targetModel: '', promptLanguage: 'en' }),
    });
    assert.equal(response.status, 200);
    const result = await response.json();
    assert.equal(result.mode, 'mock');
    assert.match(result.prompt, /ACME-42/);
    assert.match(result.prompt, /NOT been translated/);
  } finally {
    server.closeAllConnections();
    if (server.listening) await new Promise(accept => server.close(accept));
  }
}

const staging = mkdtempSync(join(tmpdir(), 'promptfinch-package-check-'));
try {
  let manifest;
  let manifestName;
  if (!sourceOnly) {
    assert.equal(process.platform, 'darwin', 'Full app artifact verification requires macOS.');
    const matches = readdirSync(release).filter(name => new RegExp(`^PromptFinch-${version.replaceAll('.', '\\.')}\\-macos-(arm64|x64)\\.verification\\.json$`).test(name));
    assert.equal(matches.length, 1, 'Expected one manifest for the current release.');
    [manifestName] = matches;
    manifest = JSON.parse(readFileSync(join(release, manifestName), 'utf8'));
    assert.equal(manifest.version, version);
    assert.ok(['arm64', 'x64'].includes(manifest.architecture));
    assert.equal(manifest.sourceArchive.name, sourceArchiveName);
    const appName = `PromptFinch-${version}-macos-${manifest.architecture}.zip`;
    assert.equal(manifest.appArchive.name, appName);
    const expectedNames = [appName, sourceArchiveName, manifestName].sort();
    const checksums = readFileSync(join(release, 'SHA256SUMS'), 'utf8').trim().split('\n').map(line => {
      const match = /^([a-f0-9]{64})  ([A-Za-z0-9_.-]+)$/.exec(line);
      assert.ok(match, 'Invalid checksum line.');
      return { sha: match[1], name: match[2] };
    });
    assert.deepEqual(checksums.map(entry => entry.name).sort(), expectedNames);
    for (const entry of checksums) assert.equal(sha256(join(release, entry.name)), entry.sha, `Checksum mismatch: ${entry.name}`);
    assert.equal(manifest.sourceArchive.sha256, sha256(join(release, sourceArchiveName)));
    assert.equal(manifest.appArchive.sha256, sha256(join(release, appName)));
  }
  const source = unpack(join(release, sourceArchiveName), join(staging, 'source'), sourceName);
  const files = auditTree(source);
  assert.ok(files.length > 50, 'The source package is incomplete.');
  const packageInfo = JSON.parse(readFileSync(join(source, 'package.json'), 'utf8'));
  assert.equal(packageInfo.version, version);
  assert.equal(packageInfo.engines.node, '>=22.12.0');
  const lock = JSON.parse(readFileSync(join(source, 'package-lock.json'), 'utf8'));
  assert.equal(lock.version, version);
  assert.equal(lock.packages[''].version, version);
  if (manifest) {
    assert.equal(manifest.backendID, await computeBackendID(source));
    for (const required of [
      'package.json', 'package-lock.json', 'macos/Info.plist', 'macos/Icon.swift',
      ...['Localization', 'Core', 'Backend', 'Selection', 'Watcher', 'App'].map(name => `macos/Sources/${name}.swift`),
      'scripts/build-macos.js', 'scripts/package-macos.js', 'scripts/package-source.js', ...BACKEND_FILES,
    ]) assert.ok(manifest.sourceInputsSHA256[required], `Missing build input hash: ${required}`);
    for (const [relative, hash] of Object.entries(manifest.sourceInputsSHA256)) {
      assert.ok(files.includes(relative), `Manifest input missing from source ZIP: ${relative}`);
      assert.equal(sha256(join(source, relative)), hash, `Manifest source input mismatch: ${relative}`);
    }
    const app = unpack(join(release, manifest.appArchive.name), join(staging, 'app'), 'PromptFinch.app');
    const appFiles = auditTree(app);
    const expectedAppFiles = [
      'Contents/Info.plist', 'Contents/MacOS/PromptSelection', 'Contents/Resources/AppIcon.icns',
      'Contents/Resources/deepseek.env.example', 'Contents/Resources/backend/package.json',
      'Contents/Resources/backend/.backend-id', 'Contents/_CodeSignature/CodeResources',
      ...BACKEND_FILES.map(path => `Contents/Resources/backend/${path}`),
    ].sort();
    assert.deepEqual(appFiles, expectedAppFiles, 'App resource allowlist mismatch.');
    const plist = validateMacApp(app);
    assert.equal(plist.CFBundleShortVersionString, version);
    assert.equal(plist.CFBundleVersion, manifest.build);
    assert.equal(plist.LSMinimumSystemVersion, manifest.minimumMacOS);
    assert.equal(manifest.minimumMacOS, '13.0');
    assert.equal(manifest.bundleIdentifier, 'org.promptstudio.selection');
    assert.equal(manifest.signing, 'ad-hoc');
    assert.equal(manifest.notarized, false);
    assert.equal(manifest.nodeRuntimeBundled, false);
    assert.equal(manifest.nodeRequirement, '>=22');
    const binary = join(app, 'Contents/MacOS/PromptSelection');
    assert.equal(run('lipo', ['-archs', binary]).trim(), manifest.architecture === 'arm64' ? 'arm64' : 'x86_64');
    const buildMetadata = run('vtool', ['-show-build', binary]);
    assert.match(buildMetadata, /platform\s+MACOS\b/);
    assert.match(buildMetadata, /minos\s+13\.0(?:\.0)?(?:\s|$)/);
    const signature = run('codesign', ['-d', '--verbose=4', app]);
    assert.match(signature, /^Signature=adhoc$/m);
    assert.doesNotMatch(signature, /^Authority=/m);
    const backend = join(app, 'Contents/Resources/backend');
    assert.deepEqual(JSON.parse(readFileSync(join(backend, 'package.json'), 'utf8')), { type: 'module', engines: { node: '>=22' } });
    assert.equal(readFileSync(join(backend, '.backend-id'), 'utf8').trim(), manifest.backendID);
    assert.equal(await computeBackendID(backend), manifest.backendID);
    await smoke(backend);
  }
  if (!artifactsOnly) {
    for (const args of [['run', 'check'], ['run', 'check:docs'], ['test']]) run('npm', args, { cwd: source, stdio: 'inherit' });
  }
  await smoke(source);
  console.log(`Verified delivered ${sourceOnly ? 'source ZIP' : 'source/App ZIPs, SHA256SUMS and manifest'}; isolated mock HTTP passed. No model API or installed app was used.`);
} finally {
  rmSync(staging, { recursive: true, force: true });
}
