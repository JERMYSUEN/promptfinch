import { createHash } from 'node:crypto';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const releaseDir = resolve(root, 'release');
const extRoot = resolve(root, 'extension');
const pkg = JSON.parse(readFileSync(resolve(root, 'package.json'), 'utf8'));
const manifest = JSON.parse(readFileSync(resolve(extRoot, 'manifest.json'), 'utf8'));

if (manifest.manifest_version !== 3) throw new Error('Extension must use Manifest V3.');
if (manifest.version !== pkg.version) {
  throw new Error(`Extension manifest version (${manifest.version}) must match package.json (${pkg.version}).`);
}

const files = [
  'manifest.json',
  'background.js',
  'content.js',
  'content.css',
  'popup.html',
  'popup.css',
  'popup.js',
  'icons/icon-16.png',
  'icons/icon-32.png',
  'icons/icon-48.png',
  'icons/icon-128.png',
];

const staging = mkdtempSync(join(tmpdir(), 'promptfinch-ext-pkg-'));
try {
  for (const relative of files) {
    const src = resolve(extRoot, relative);
    if (!existsSync(src)) throw new Error(`Missing extension asset: extension/${relative}`);
    if (!relative.endsWith('.png')) {
      const text = readFileSync(src, 'utf8');
      if (/\/Users\/[^/]+\//.test(text)) throw new Error(`Private path found in extension/${relative}`);
    }
    const dst = join(staging, relative);
    mkdirSync(dirname(dst), { recursive: true });
    cpSync(src, dst);
  }
  mkdirSync(releaseDir, { recursive: true });
  const archive = resolve(releaseDir, `PromptFinch-extension-v${pkg.version}.zip`);
  rmSync(archive, { force: true });
  const tool = process.platform === 'darwin' ? 'ditto' : 'zip';
  const args = process.platform === 'darwin'
    ? ['--norsrc', '--noextattr', '-c', '-k', staging, archive]
    : ['-q', '-r', archive, '.'];
  const result = spawnSync(tool, args, { cwd: staging, stdio: 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error('Failed to package extension archive.');
  const sha = createHash('sha256').update(readFileSync(archive)).digest('hex');
  console.log(`Packaged ${files.length} extension files: ${archive}\nSHA-256: ${sha}`);
} finally {
  rmSync(staging, { recursive: true, force: true });
}
