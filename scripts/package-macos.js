import { createHash } from 'node:crypto';
import {
  cpSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync,
  readdirSync, renameSync, rmSync, writeFileSync,
} from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { parseEnv } from 'node:util';
import { BACKEND_FILES, computeBackendID } from './backend-release.js';

if (process.platform !== 'darwin') throw new Error('Public macOS packaging requires macOS.');
if (!['arm64', 'x64'].includes(process.arch)) throw new Error('Unsupported macOS build architecture.');

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const release = join(root, 'release');
const packageInfo = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'));
const version = packageInfo.version;
if (!/^\d+\.\d+\.\d+$/.test(version)) throw new Error('A three-part release version is required.');
const architecture = process.arch === 'arm64' ? 'arm64' : 'x86_64';
const archiveArchitecture = process.arch === 'arm64' ? 'arm64' : 'x64';
const sourceName = `PromptFinch-source-v${version}`;
const archiveName = `PromptFinch-${version}-macos-${archiveArchitecture}.zip`;
const manifestName = `PromptFinch-${version}-macos-${archiveArchitecture}.verification.json`;
const sourceArchiveName = `${sourceName}.zip`;
const artifactNames = [archiveName, sourceArchiveName, manifestName];
mkdirSync(release, { recursive: true });
// The checksum list is a completion marker for one verified artifact set. Drop
// old same-version outputs before attempting a rebuild, including on failure.
for (const name of [...artifactNames, 'SHA256SUMS']) rmSync(join(release, name), { force: true });

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { cwd: root, encoding: 'utf8', ...options });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    if (result.stdout) process.stderr.write(result.stdout);
    if (result.stderr) process.stderr.write(result.stderr);
    throw new Error(`${command} failed (${result.status}).`);
  }
  return `${result.stdout || ''}${result.stderr || ''}`;
}

function readPlist(path) {
  return JSON.parse(run('plutil', ['-convert', 'json', '-o', '-', path]));
}

function sha256(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

const forbiddenPathPatterns = [
  ['', 'Users', ''], ['', 'private', 'var', 'folders', ''], ['', 'var', 'folders', ''],
].map(parts => parts.join('/'));
const environmentTemplates = new Set(['.env.example', '.env.deepseek.example', 'deepseek.env.example']);

// This inspects only the explicitly packaged public source or the newly built app.
// It never opens the checkout's private .env, user preferences or signing settings.
function auditTree(directory) {
  const files = [];
  function visit(current, prefix = '') {
    for (const entry of readdirSync(current, { withFileTypes: true })) {
      const relative = prefix ? `${prefix}/${entry.name}` : entry.name;
      const path = join(current, entry.name);
      const info = lstatSync(path);
      if (info.isSymbolicLink()) throw new Error(`A public archive may not contain symlinks: ${relative}`);
      if (['node_modules', '.git', 'artifacts', '.DS_Store', 'debug.log', 'settings.env', 'code-signing.json'].includes(entry.name)
          || (entry.name.startsWith('.env') && !environmentTemplates.has(entry.name))
          || (/\.env(?:\.|$)/.test(entry.name) && !environmentTemplates.has(entry.name))) {
        throw new Error(`A private or generated file entered the public archive: ${relative}`);
      }
      if (info.isDirectory()) {
        visit(path, relative);
      } else if (info.isFile()) {
        const content = readFileSync(path);
        for (const pattern of forbiddenPathPatterns) {
          if (content.includes(Buffer.from(pattern))) throw new Error(`A private absolute path remains in: ${relative}`);
        }
        if (environmentTemplates.has(entry.name)) {
          const env = parseEnv(content.toString('utf8'));
          for (const [name, value] of Object.entries(env)) {
            if (/(?:API_KEY|TOKEN|SECRET|PASSWORD)$/.test(name) && value.trim()) {
              throw new Error(`An environment template contains a credential: ${relative}`);
            }
          }
        }
        files.push(relative);
      } else {
        throw new Error(`A public archive contains a nonregular file: ${relative}`);
      }
    }
  }
  visit(directory);
  return files.sort();
}

const sourcePlist = readPlist(join(root, 'macos/Info.plist'));
const buildNumber = sourcePlist.CFBundleVersion;
if (sourcePlist.CFBundleShortVersionString !== version || !/^\d+$/.test(buildNumber)) {
  throw new Error('package.json and macOS bundle versions must agree, with an integer build number.');
}
const lock = JSON.parse(readFileSync(join(root, 'package-lock.json'), 'utf8'));
if (lock.version !== version || lock.packages?.['']?.version !== version) {
  throw new Error('package-lock.json and package.json versions must agree.');
}

const staging = mkdtempSync('/tmp/promptfinch-release-');
const cleanRoot = join(staging, sourceName);
const output = join(staging, 'output');
try {
  // Public-only mode never opens the checkout's private .env. All intermediate
  // artifacts stay outside release until both the source and app validate.
  run(process.execPath, [join(root, 'scripts/package-source.js'), '--public-only', '--output-dir', output], { stdio: 'inherit' });
  const publicSource = join(output, sourceName);
  const sourceArchive = join(output, sourceArchiveName);
  if (!existsSync(publicSource) || !existsSync(sourceArchive)) throw new Error('The public source package was not created.');
  auditTree(publicSource);
  cpSync(publicSource, cleanRoot, { recursive: true });
  const buildEnvironment = { ...process.env };
  for (const name of Object.keys(buildEnvironment)) {
    if (name.startsWith('LLM_') || name === 'OPTIMIZER_MODE' || name.startsWith('PROMPT_STUDIO_BACKEND_')) {
      delete buildEnvironment[name];
    }
  }
  buildEnvironment.PROMPT_STUDIO_SIGNING_CONFIG = join(staging, 'no-personal-signing-config.json');
  buildEnvironment.PROMPT_STUDIO_BUILD_NUMBER = buildNumber;
  run(process.execPath, [join(cleanRoot, 'scripts/build-macos.js')], {
    cwd: cleanRoot, env: buildEnvironment, stdio: 'inherit',
  });

  const app = join(cleanRoot, 'build/PromptFinch.app');
  const contents = join(app, 'Contents');
  const executable = join(contents, 'MacOS/PromptSelection');
  const builtPlist = readPlist(join(contents, 'Info.plist'));
  if (builtPlist.CFBundleShortVersionString !== version || builtPlist.CFBundleVersion !== buildNumber
      || builtPlist.CFBundleIdentifier !== 'org.promptstudio.selection'
      || builtPlist.LSMinimumSystemVersion !== '13.0') {
    throw new Error('The built app has unexpected version, identifier or minimum-macOS metadata.');
  }
  const actualArchitectures = run('lipo', ['-archs', executable]).trim().split(/\s+/);
  if (actualArchitectures.length !== 1 || actualArchitectures[0] !== architecture) {
    throw new Error('The public app has an unexpected binary architecture.');
  }
  const buildMetadata = run('vtool', ['-show-build', executable]);
  if (!/platform\s+MACOS\b/.test(buildMetadata) || !/minos\s+13\.0(?:\.0)?(?:\s|$)/.test(buildMetadata)) {
    throw new Error('The binary must target macOS 13.0.');
  }
  run('codesign', ['--verify', '--deep', '--strict', app]);
  const signature = run('codesign', ['-d', '--verbose=4', app]);
  if (!/^Signature=adhoc$/m.test(signature) || /^Authority=/m.test(signature)) {
    throw new Error('The public app must use an ad-hoc signature, without a personal certificate.');
  }

  const expectedBackendID = await computeBackendID(cleanRoot);
  const backend = join(contents, 'Resources/backend');
  if (readFileSync(join(backend, '.backend-id'), 'utf8').trim() !== expectedBackendID
      || await computeBackendID(backend) !== expectedBackendID) {
    throw new Error('The bundled backend does not match the packaged public source.');
  }
  const expectedAppFiles = [
    'Contents/Info.plist', 'Contents/MacOS/PromptSelection',
    'Contents/Resources/AppIcon.icns', 'Contents/Resources/deepseek.env.example',
    'Contents/Resources/backend/package.json', 'Contents/Resources/backend/.backend-id',
    'Contents/_CodeSignature/CodeResources',
    ...BACKEND_FILES.map(path => `Contents/Resources/backend/${path}`),
  ].sort();
  const actualAppFiles = auditTree(app);
  if (JSON.stringify(actualAppFiles) !== JSON.stringify(expectedAppFiles)) {
    throw new Error('The public app contains unexpected files or is missing required bundle resources.');
  }
  const bundledPackage = JSON.parse(readFileSync(join(backend, 'package.json'), 'utf8'));
  if (bundledPackage.engines?.node !== '>=22' || bundledPackage.type !== 'module'
      || bundledPackage.dependencies || bundledPackage.devDependencies) {
    throw new Error('The bundled backend must require separately installed Node.js 22+, with no bundled dependencies.');
  }

  run('ditto', ['--norsrc', '--noextattr', '-c', '-k', '--keepParent', app, join(output, archiveName)]);
  const sourceInputs = [
    'package.json', 'package-lock.json', 'macos/Info.plist', 'macos/Icon.swift',
    ...['Localization', 'Core', 'Backend', 'Selection', 'Watcher', 'App'].map(name => `macos/Sources/${name}.swift`),
    'scripts/build-macos.js', 'scripts/backend-release.js', 'scripts/package-source.js',
    'scripts/package-macos.js', 'scripts/app-install.js', 'scripts/check-package.js', '.env.deepseek.example', ...BACKEND_FILES,
  ];
  const manifest = {
    version, build: buildNumber, architecture: archiveArchitecture,
    bundleIdentifier: builtPlist.CFBundleIdentifier,
    minimumMacOS: '13.0', backendID: expectedBackendID,
    signing: 'ad-hoc', notarized: false, nodeRequirement: '>=22', nodeRuntimeBundled: false,
    sourceArchive: { name: sourceArchiveName, sha256: sha256(sourceArchive) },
    appArchive: { name: archiveName, sha256: sha256(join(output, archiveName)) },
    sourceInputsSHA256: Object.fromEntries(sourceInputs.map(path => [path, sha256(join(cleanRoot, path))])),
    verified: ['version metadata', 'single binary architecture', 'macOS deployment target',
      'strict ad-hoc code signature', 'backend content ID', 'bundle file allowlist',
      'no private absolute paths', 'blank credential templates'],
    scope: 'Built from the explicit public source package. No installed app, user settings, Keychain or model API was used. Archive bytes are not claimed to be reproducible across builds.',
  };
  writeFileSync(join(output, manifestName), `${JSON.stringify(manifest, null, 2)}\n`);
  const checksums = artifactNames.map(name => `${sha256(join(output, name))}  ${name}`).join('\n') + '\n';
  // Verify the delivered ZIP contents, manifest and mock HTTP from the ZIP,
  // rather than testing only the checkout or its pre-archive copy.
  writeFileSync(join(output, 'SHA256SUMS'), checksums);
  run(process.execPath, [join(root, 'scripts/check-package.js'), '--release-dir', output, '--artifacts-only'], { stdio: 'inherit' });
  for (const name of artifactNames) {
    const temporary = join(release, `.${name}.${process.pid}.tmp`);
    cpSync(join(output, name), temporary);
    renameSync(temporary, join(release, name));
  }
  const checksumTemporary = join(release, `.SHA256SUMS.${process.pid}.tmp`);
  writeFileSync(checksumTemporary, checksums);
  renameSync(checksumTemporary, join(release, 'SHA256SUMS'));
  console.log(`Public macOS archive: ${archiveName}\nVerification manifest: ${manifestName}\nChecksums: SHA256SUMS\nAd-hoc signed; not notarized. Node.js 22+ must be installed separately.`);
} catch (error) {
  for (const name of [...artifactNames, 'SHA256SUMS', ...artifactNames.map(name => `.${name}.${process.pid}.tmp`), `.SHA256SUMS.${process.pid}.tmp`]) {
    rmSync(join(release, name), { force: true });
  }
  throw error;
} finally {
  rmSync(staging, { recursive: true, force: true });
}
