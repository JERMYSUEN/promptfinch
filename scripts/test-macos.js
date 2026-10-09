import { spawn, spawnSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createApp } from '../server.js';
import { readConfig } from '../lib/optimizer.js';

if (process.platform !== 'darwin') throw new Error('Swift 檢查需要 macOS。');
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
mkdirSync(resolve(root, 'build/swift-cache'), { recursive: true });
const binary = resolve(root, 'build/core-tests');
const compile = spawnSync('xcrun', ['swiftc', '-swift-version', '5', '-D', 'PROMPTFINCH_TESTS', '-parse-as-library', '-module-cache-path', resolve(root, 'build/swift-cache'), ...['Localization', 'Core', 'Backend', 'Selection', 'Watcher', 'App'].map(name => resolve(root, `macos/Sources/${name}.swift`)), resolve(root, 'macos/Tests/CoreTests.swift'), resolve(root, 'macos/Tests/WorkspaceTests.swift'), '-o', binary], { stdio: 'inherit' });
if (compile.error) throw compile.error;
if (compile.status !== 0) process.exit(compile.status || 1);
const server = createApp(readConfig({
  OPTIMIZER_MODE: 'mock', PORT: '0',
  PROMPT_STUDIO_BACKEND_ID: 'a'.repeat(64),
  PROMPT_STUDIO_BACKEND_INSTANCE: '3f5dbd86-9ae6-43a1-a938-02d6739f5e36',
}));
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
try {
  const child = spawn(binary, [`http://127.0.0.1:${server.address().port}`], { stdio: 'inherit' });
  const status = await new Promise((resolve, reject) => {
    child.on('error', reject);
    child.on('exit', code => resolve(code ?? 1));
  });
  process.exitCode = status || 0;
} finally {
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
}
