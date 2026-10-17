import { cpSync, mkdirSync, rmSync, readFileSync, existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { parseEnv } from 'node:util';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const outputIndex = process.argv.indexOf('--output-dir');
if (outputIndex >= 0 && !process.argv[outputIndex + 1]) throw new Error('--output-dir needs a directory.');
const release = outputIndex >= 0 ? resolve(process.argv[outputIndex + 1]) : resolve(root, 'release');
const version = JSON.parse(readFileSync(resolve(root, 'package.json'), 'utf8')).version;
if (!/^\d+\.\d+\.\d+$/.test(version)) throw new Error('來源封裝需要有效的三段版本號。');
const name = `PromptFinch-source-v${version}`;
const destination = resolve(release, name);
const readmeLocales = [
  'zh-CN', 'zh-TW', 'es', 'fr', 'de', 'pt', 'it', 'ru', 'tr', 'nl', 'pl', 'uk',
  'ja', 'ko', 'hi', 'bn', 'id', 'vi', 'th', 'ta', 'te', 'mr', 'ar', 'ur', 'fa', 'sw', 'pa', 'fil',
];
const files = [
  'README.md', 'CHANGELOG.md', 'LICENSE', 'CONTRIBUTING.md', 'SECURITY.md', '.gitignore', '.dockerignore',
  '.env.example', '.env.deepseek.example', 'package.json', 'package-lock.json', 'Dockerfile',
  'server.js', 'lib/optimizer.js', 'public/index.html', 'public/app.js', 'public/style.css', 'public/favicon.svg',
  'playwright.config.js', 'tests/server.test.js', 'tests/backend-release.test.js', 'tests/app-install.test.js', 'tests/multilingual.test.js', 'tests/ui/workspace.spec.js',
  'tests/fixtures/multilingual-inputs.json', 'tests/fixtures/multilingual-ko-ru.json',
  'tests/fixtures/multilingual-parity.json', 'tests/fixtures/multilingual-language-edges.json', 'tests/multilingual-runner.test.js', 'tests/evaluation-options.test.js',
  'tests/fixtures/optimization-value.json', 'tests/fixtures/release-quality.json',
  'scripts/build-macos.js', 'scripts/setup-signing-macos.js', 'scripts/verify-signing-macos.js', 'scripts/install-macos.js', 'scripts/app-install.js', 'scripts/app-lifecycle.js', 'scripts/terminate-macos-app.swift', 'scripts/update-macos-backend.js', 'scripts/backend-release.js', 'scripts/test-macos.js', 'scripts/package-source.js', 'scripts/package-macos.js', 'scripts/check-package.js', 'scripts/verify-multilingual.js',
  'macos/Info.plist', 'macos/Icon.swift', 'macos/Sources/Localization.swift', 'macos/Sources/Core.swift', 'macos/Sources/Backend.swift',
  'macos/Sources/Selection.swift', 'macos/Sources/Watcher.swift', 'macos/Sources/App.swift', 'macos/Tests/CoreTests.swift', 'macos/Tests/WorkspaceTests.swift', 'macos/Tests/BackendTests.swift', 'macos/Tests/ClientTests.swift', 'macos/Tests/ProcessTests.swift', 'macos/Tests/ServiceSmoke.swift',
  'docs/design.md', 'docs/macos.md', 'docs/reliability-verification.md', 'docs/multilingual-verification.md', 'docs/multilingual-live-results.json', 'docs/context-menu-verification.md', 'docs/branding.md', '.github/workflows/check.yml',
  'docs/assets/logo.svg', 'scripts/check-readmes.js',
  'docs/media/demo-selection.gif',
  'docs/terminal.md',
  'docs/multilingual-parity-verification.md', 'docs/multilingual-parity-results.json',
  'docs/optimization-value-verification.md', 'docs/optimization-value-results.json',
  'docs/README.md', 'docs/api.md', 'docs/troubleshooting.md', 'docs/documentation-audit.md', 'docs/improvement-verification.md', 'docs/improvement-live-results.json', 'docs/releases/v1.0.0.md', 'docs/releases/v1.1.0.md',
  ...readmeLocales.map((locale) => `docs/readme/README.${locale}.md`),
];
// Audit before copying, not after a private file could enter a release.
const publicOnly = process.argv.includes('--public-only');
const localEnv = !publicOnly && existsSync(resolve(root, '.env')) ? parseEnv(readFileSync(resolve(root, '.env'), 'utf8')) : {};
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
console.log(`已封裝 ${files.length} 個檔案：${archive}\n包含使用合成內容重製的示範 GIF；未包含 .env、偏好設定、App、node_modules 或原始錄影／擷取畫面。`);
