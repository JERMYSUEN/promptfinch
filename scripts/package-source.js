import { cpSync, mkdirSync, rmSync, readFileSync, existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { parseEnv } from 'node:util';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const release = resolve(root, 'release');
const name = 'PromptFinch-source-v1.0.0';
const destination = resolve(release, name);
const files = [
  'README.md', 'LICENSE', 'CONTRIBUTING.md', 'SECURITY.md', '.gitignore', '.dockerignore',
  '.env.example', '.env.deepseek.example', 'package.json', 'package-lock.json', 'Dockerfile',
  'server.js', 'lib/optimizer.js', 'public/index.html', 'public/app.js', 'public/style.css', 'public/favicon.svg',
  'playwright.config.js', 'tests/server.test.js', 'tests/backend-release.test.js', 'tests/multilingual.test.js', 'tests/ui/workspace.spec.js',
  'tests/fixtures/multilingual-inputs.json', 'tests/fixtures/multilingual-ko-ru.json',
  'scripts/build-macos.js', 'scripts/setup-signing-macos.js', 'scripts/verify-signing-macos.js', 'scripts/install-macos.js', 'scripts/app-lifecycle.js', 'scripts/terminate-macos-app.swift', 'scripts/update-macos-backend.js', 'scripts/backend-release.js', 'scripts/test-macos.js', 'scripts/package-source.js', 'scripts/verify-multilingual.js',
  'macos/Info.plist', 'macos/Icon.swift', 'macos/Sources/Core.swift', 'macos/Sources/Backend.swift',
  'macos/Sources/Selection.swift', 'macos/Sources/Watcher.swift', 'macos/Sources/App.swift', 'macos/Tests/CoreTests.swift', 'macos/Tests/ServiceSmoke.swift',
  'docs/design.md', 'docs/macos.md', 'docs/multilingual-verification.md', 'docs/multilingual-live-results.json', 'docs/context-menu-verification.md', 'docs/branding.md', '.github/workflows/check.yml',
];
// Audit before copying, not after a private file could enter a release.
const localEnv = existsSync(resolve(root, '.env')) ? parseEnv(readFileSync(resolve(root, '.env'), 'utf8')) : {};
const localKey = localEnv.LLM_API_KEY || '';
for (const file of files) {
  if (!existsSync(resolve(root, file))) throw new Error(`缺少原始碼檔案：${file}`);
  const text = readFileSync(resolve(root, file), 'utf8');
  if (/\/Users\/[^/]+\//.test(text)) throw new Error(`仍有個人絕對路徑：${file}`);
  if (localKey.length > 8 && text.includes(localKey)) throw new Error(`檔案含本機金鑰，不能封裝：${file}`);
  if (/^(?:LLM_API_KEY|OPENAI_API_KEY|DEEPSEEK_API_KEY)[ \t]*=[ \t]*\S+/m.test(text)
      && ['.env.example', '.env.deepseek.example'].includes(file)) throw new Error(`金鑰範本不是空白：${file}`);
}
mkdirSync(release, { recursive: true });
rmSync(destination, { recursive: true, force: true });
for (const file of files) {
  const target = resolve(destination, file);
  mkdirSync(dirname(target), { recursive: true });
  cpSync(resolve(root, file), target);
}
const archive = resolve(release, `${name}.zip`);
rmSync(archive, { force: true });
const tool = process.platform === 'darwin' ? 'ditto' : 'zip';
const args = process.platform === 'darwin' ? ['--norsrc', '--noextattr', '-c', '-k', '--keepParent', destination, archive] : ['-q', '-r', archive, name];
const result = spawnSync(tool, args, { cwd: release, stdio: 'inherit' });
if (result.error) throw result.error;
if (result.status !== 0) throw new Error('原始碼封裝失敗。');
console.log(`已封裝 ${files.length} 個檔案：${archive}\n未包含 .env、偏好設定、App、node_modules 或截圖。`);
