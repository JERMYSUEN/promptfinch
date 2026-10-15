// Explicit, sequential live evaluation with synthetic fixtures; never part of npm test.
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
class EvaluationError extends Error {}

async function main() {
  if (!args.includes('--live')) throw new EvaluationError('真實模型測試可能產生 API 費用；請明確傳入 --live。');
  const options = new Map();
  const valueOptions = new Set(['--url', '--cases', '--output', '--ids']);
  for (let index = 0; index < args.length; index++) {
    const name = args[index];
    if (name !== '--live' && !valueOptions.has(name)) throw new EvaluationError('包含不支援的測試選項。');
    if (options.has(name)) throw new EvaluationError('測試選項不得重複。');
    if (name === '--live') { options.set(name, true); continue; }
    const value = args[++index];
    if (!value || value.startsWith('--')) throw new EvaluationError(`${name} 缺少值。`);
    options.set(name, value);
  }
  const option = (name, fallback) => options.get(name) ?? fallback;
  let base;
  try { base = new URL(option('--url', 'http://127.0.0.1:3210')); }
  catch { throw new EvaluationError('測試網址格式無效。'); }
  if (!['http:', 'https:'].includes(base.protocol) || !['127.0.0.1', 'localhost', '[::1]'].includes(base.hostname)
      || base.username || base.password || base.search || base.hash || base.pathname !== '/') {
    throw new EvaluationError('測試只接受沒有帳密或其他參數的本機工作台網址。');
  }
  let fixtures;
  try { fixtures = JSON.parse(await readFile(resolve(option('--cases', resolve(root, 'tests/fixtures/multilingual-inputs.json'))), 'utf8')); }
  catch { throw new EvaluationError('無法讀取或解析案例檔案。'); }
  const tasks = new Set(['general', 'writing', 'analysis', 'coding', 'summary', 'marketing']);
  if (!Array.isArray(fixtures) || !fixtures.length || fixtures.length > 60
      || fixtures.some(c => !c || typeof c !== 'object' || Array.isArray(c)
        || typeof c.id !== 'string' || !/^[a-zA-Z0-9][a-zA-Z0-9._-]*$/.test(c.id)
        || typeof c.prompt !== 'string' || !c.prompt.trim() || c.prompt.length > 12000
        || (c.task !== undefined && !tasks.has(c.task))
        || (c.expected !== undefined && (!c.expected || typeof c.expected !== 'object' || Array.isArray(c.expected)))
        || (c.expected?.literals !== undefined && (!Array.isArray(c.expected.literals)
          || c.expected.literals.some(text => typeof text !== 'string' || !text.length))))) {
    throw new EvaluationError('案例格式無效；請提供 1 到 60 個有效案例。');
  }
  const fixtureIDs = new Set(fixtures.map(c => c.id));
  if (fixtureIDs.size !== fixtures.length) throw new EvaluationError('案例 ID 不得重複。');
  if (options.has('--ids')) {
    const ids = option('--ids').split(',').map(id => id.trim());
    if (ids.some(id => !id) || new Set(ids).size !== ids.length) throw new EvaluationError('--ids 必須是非空且不重複的逗號分隔 ID。');
    if (ids.some(id => !fixtureIDs.has(id))) throw new EvaluationError('--ids 包含未知的案例 ID。');
    const selected = new Set(ids);
    fixtures = fixtures.filter(c => selected.has(c.id));
  }
  const destination = resolve(option('--output', resolve(root, 'artifacts/multilingual-live-results.json')));
  const response = await fetch(new URL('/api/config', base), { signal: AbortSignal.timeout(5000) });
  const config = await response.json();
  if (!response.ok || config.service !== 'prompt-studio' || config.mode !== 'live' || !config.ready) {
    throw new EvaluationError('請先啟動已設定完成的真實模型工作台；不能把 mock 當語意測試。');
  }
  await mkdir(dirname(destination), { recursive: true });
  const run = { date: new Date().toISOString(), generationModel: config.generationModel, backendID: config.backendID || null,
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
  if (run.results.some(r => r.error || r.literalChecks?.some(check => !check.preserved))) process.exitCode = 1;
}

main().catch(error => {
  // Never print raw parse/network/filesystem errors, which may contain inputs.
  console.error(error instanceof EvaluationError ? error.message : '驗證執行失敗；請檢查本機服務與輸出路徑。');
  process.exitCode = 1;
});
