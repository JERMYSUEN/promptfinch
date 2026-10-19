import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const execute = promisify(execFile);
const runner = fileURLToPath(new URL('../scripts/verify-multilingual.js', import.meta.url));

test('語意評估器支援獨立指令與說明語言，錯誤選項不會送出請求', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'promptfinch-evaluation-options-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const cases = join(directory, 'cases.json'), output = join(directory, 'result.json');
  await writeFile(cases, JSON.stringify([{ id: 'synthetic-language-check', prompt: '保留 ACME-42', expected: { literals: ['ACME-42'] } }]));
  const bodies = [];
  let requests = 0;
  const server = createServer(async (request, response) => {
    requests++;
    response.setHeader('Content-Type', 'application/json');
    if (request.url === '/api/config') {
      response.end(JSON.stringify({ service: 'prompt-studio', mode: 'live', ready: true, generationModel: 'synthetic-provider' }));
      return;
    }
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    const body = JSON.parse(Buffer.concat(chunks));
    bodies.push(body);
    response.end(JSON.stringify({ mode: 'live', prompt: '保留 ACME-42。', promptLanguage: body.promptLanguage, notesLanguage: body.notesLanguage }));
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  const args = [runner, '--live', '--url', `http://127.0.0.1:${server.address().port}`, '--cases', cases, '--output', output];
  await execute(process.execPath, [...args, '--prompt-language', 'zh-Hant', '--notes-language', 'ja'], { env: {}, timeout: 15000 });
  assert.deepEqual(bodies, [{ prompt: '保留 ACME-42', task: 'general', targetModel: '', promptLanguage: 'zh-Hant', notesLanguage: 'ja' }]);
  const saved = JSON.parse(await readFile(output, 'utf8'));
  assert.equal(saved.promptLanguage, 'zh-Hant');
  assert.equal(saved.notesLanguage, 'ja');
  assert.equal(saved.results[0].semanticReview, 'pending', 'mechanical success must not claim semantic quality');
  assert.equal(saved.results[0].literalChecks[0].preserved, true);
  const priorRequests = requests;
  for (const extra of [
    ['--prompt-language', 'fr'], ['--notes-language', 'fr'],
    ...['0', '11', '-1', '1.5', '1.0', '02', 'NaN', ''].map(value => ['--max-consecutive-failures', value]),
    ['--max-consecutive-failures'], ['--max-consecutive-failures', '2', '--max-consecutive-failures', '3'],
  ]) {
    await assert.rejects(execute(process.execPath, [...args, ...extra], { env: {}, timeout: 15000 }), error => error.code === 1);
  }
  assert.equal(requests, priorRequests, 'invalid options fail before connecting');
});
