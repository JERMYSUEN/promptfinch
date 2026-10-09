// Explicit, sequential live evaluation with synthetic fixtures; never part of npm test.
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
if (!args.includes('--live')) throw new Error('真實模型測試可能產生 API 費用；請明確傳入 --live。');
function option(name, fallback) {
  const index = args.indexOf(name);
  if (index === -1) return fallback;
  if (!args[index + 1] || args[index + 1].startsWith('--')) throw new Error(`${name} 缺少值。`);
  return args[index + 1];
}
const base = new URL(option('--url', 'http://127.0.0.1:3210'));
if (!['http:', 'https:'].includes(base.protocol) || !['127.0.0.1', 'localhost', '[::1]'].includes(base.hostname)
    || base.username || base.password || base.search || base.hash || base.pathname !== '/') {
  throw new Error('測試只接受沒有帳密或其他參數的本機工作台網址。');
}
const fixtures = JSON.parse(await readFile(resolve(option('--cases', resolve(root, 'tests/fixtures/multilingual-inputs.json'))), 'utf8'));
if (!Array.isArray(fixtures) || !fixtures.length || fixtures.length > 30
    || fixtures.some(c => !c.id || typeof c.prompt !== 'string' || !c.prompt.trim())) throw new Error('案例格式無效。');
const response = await fetch(new URL('/api/config', base), { signal: AbortSignal.timeout(5000) });
const config = await response.json();
if (!response.ok || config.service !== 'prompt-studio' || config.mode !== 'live' || !config.ready) {
  throw new Error('請先啟動已設定完成的真實模型工作台；不能把 mock 當語意測試。');
}
const destination = resolve(option('--output', resolve(root, 'artifacts/multilingual-live-results.json')));
await mkdir(dirname(destination), { recursive: true });
const run = { date: new Date().toISOString(), generationModel: config.generationModel,
  evidence: 'live model samples; literal checks are mechanical, semantic review is separate', results: [] };
for (const fixture of fixtures) {
  const start = Date.now();
  const entry = { ...fixture, sourceUTF16Length: fixture.prompt.length, semanticReview: 'pending' };
  try {
    const response = await fetch(new URL('/api/optimize', base), {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ prompt: fixture.prompt, task: fixture.task || 'general', targetModel: '', promptLanguage: 'en' }),
      signal: AbortSignal.timeout(195000),
    });
    const data = await response.json();
    entry.status = response.status;
    if (!response.ok) entry.error = data.error || '模型請求失敗';
    else if (data.mode !== 'live' || data.promptLanguage !== 'en' || typeof data.prompt !== 'string') entry.error = '回應不是英文 live 結果';
    else {
      entry.result = data;
      entry.resultUTF16Length = data.prompt.length;
      entry.literalChecks = (fixture.expected?.literals || []).map(text => ({ text, preserved: data.prompt.includes(text) }));
    }
  } catch (error) {
    entry.error = error.name === 'TimeoutError' ? '測試逾時' : '連線失敗';
  }
  entry.elapsedMs = Date.now() - start;
  run.results.push(entry);
  // No credentials, provider bodies, source text, or prompt output in the console.
  console.log(`${fixture.id}: HTTP ${entry.status || 'error'}; source=${entry.sourceUTF16Length}; result=${entry.resultUTF16Length || 0}; literalFailures=${entry.literalChecks?.filter(c => !c.preserved).length || 0}`);
  await writeFile(destination, JSON.stringify(run, null, 2) + '\n');
}
console.log(`已記錄 ${run.results.length} 個合成案例；請另作語意覆核。`);
if (run.results.some(r => r.error)) process.exitCode = 1;
