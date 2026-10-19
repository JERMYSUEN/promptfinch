import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

const runner = fileURLToPath(new URL('../scripts/verify-multilingual.js', import.meta.url));
const sourceMarker = 'synthetic-source-content-that-must-not-reach-console';
const resultMarker = 'synthetic-result-content-that-must-not-reach-console';
const keyMarker = 'synthetic-key-that-must-not-reach-console';

function fixture(id, overrides = {}) {
  return { id, prompt: `${sourceMarker} ${id}`, task: 'writing',
    expected: { literals: ['ACME-42'] }, ...overrides };
}

async function setup(t, fixtures, respond = () => ({
  mode: 'live', promptLanguage: 'en', prompt: `${resultMarker} ACME-42`,
})) {
  const directory = await mkdtemp(join(tmpdir(), 'promptfinch-multilingual-runner-'));
  const cases = join(directory, 'cases.json');
  const output = join(directory, 'output.json');
  await writeFile(cases, typeof fixtures === 'string' ? fixtures : JSON.stringify(fixtures));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const requests = [];
  const server = createServer(async (request, response) => {
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    const body = chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : null;
    requests.push({ path: request.url, body });
    response.setHeader('Content-Type', 'application/json');
    if (request.url === '/api/config') {
      response.end(JSON.stringify({ service: 'prompt-studio', mode: 'live', ready: true,
        generationModel: 'controlled-runner-test-model', backendID: 'controlled-server-backend-id' }));
    } else {
      const data = await respond(body, { output, response, requests });
      if (!response.writableEnded && !response.destroyed) response.end(JSON.stringify(data));
    }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  return { cases, output, requests, server, url: `http://127.0.0.1:${server.address().port}` };
}

async function run(context, extra = [], live = true) {
  const child = spawn(process.execPath, [runner, ...(live ? ['--live'] : []),
    '--url', context.url, '--cases', context.cases, '--output', context.output, ...extra],
  { env: {}, stdio: ['ignore', 'pipe', 'pipe'] });
  let stdout = '', stderr = '';
  child.stdout.setEncoding('utf8').on('data', text => { stdout += text; });
  child.stderr.setEncoding('utf8').on('data', text => { stderr += text; });
  const timer = setTimeout(() => child.kill(), 15000);
  try {
    const code = await new Promise((resolve, reject) => {
      child.once('error', reject);
      child.once('close', (code, signal) => signal ? reject(new Error(`Runner stopped: ${signal}`)) : resolve(code));
    });
    for (const marker of [sourceMarker, resultMarker, keyMarker]) {
      assert.ok(!stdout.includes(marker), 'console must not print source, result, or credentials');
      assert.ok(!stderr.includes(marker), 'errors must not print source, result, or credentials');
    }
    return { code, stdout, stderr };
  } finally { clearTimeout(timer); }
}

test('live runner 精確篩選 ID，逐筆保存並只傳公開 API 欄位', async t => {
  let active = 0, calls = 0;
  const context = await setup(t, [fixture('case-a', { privateMetadata: keyMarker }), fixture('case-ab'), fixture('case-c')],
    async (body, { output }) => {
      assert.equal(++active, 1, 'model requests must be sequential');
      const saved = JSON.parse(await readFile(output, 'utf8'));
      assert.deepEqual(saved.results.map(entry => entry.id), calls++ ? ['case-a'] : []);
      assert.equal(saved.status, 'running');
      assert.equal(saved.semanticStatus, 'pending');
      await new Promise(resolve => setTimeout(resolve, 10));
      active--;
      return { mode: 'live', promptLanguage: 'en', prompt: `${resultMarker} ACME-42` };
    });
  const result = await run(context, ['--ids', 'case-c,case-a']);
  assert.equal(result.code, 0, result.stderr);
  const optimized = context.requests.filter(request => request.path === '/api/optimize');
  assert.deepEqual(optimized.map(request => request.body.prompt), [`${sourceMarker} case-a`, `${sourceMarker} case-c`]);
  for (const { body } of optimized) {
    assert.deepEqual(Object.keys(body), ['prompt', 'task', 'targetModel', 'promptLanguage']);
    assert.equal(body.task, 'writing');
    assert.equal(body.targetModel, '');
    assert.equal(body.promptLanguage, 'en');
  }
  const saved = JSON.parse(await readFile(context.output, 'utf8'));
  assert.deepEqual(saved.results.map(entry => entry.id), ['case-a', 'case-c']);
  assert.ok(saved.results.every(entry => entry.semanticReview === 'pending'));
  assert.equal(saved.semanticStatus, 'pending');
  assert.ok(saved.results.every(entry => entry.semanticStatus === 'pending'));
  assert.deepEqual(saved.totals, { attempted: 2, succeeded: 2, failed: 0, unattempted: 0 });
  assert.deepEqual(saved.unattemptedIDs, []);
  assert.equal(saved.status, 'completed');
  assert.equal(saved.stopReason, null);
  const localSource = await readFile(new URL('../lib/optimizer.js', import.meta.url));
  assert.equal(saved.localOptimizerSourceSHA256, createHash('sha256').update(localSource).digest('hex'));
  assert.equal(saved.backendID, 'controlled-server-backend-id');
  assert.match(saved.sourceEvidence, /local.*does not prove.*deployed/);
  assert.match(saved.evidence, /not semantic quality/);
  assert.ok(saved.results.every(entry => entry.literalChecks[0].preserved));
  assert.ok(!result.stdout.includes('case-ab:'));
});

test('字面遺漏令 runner 失敗但保留完整結果、後續案例與待覆核狀態', async t => {
  const context = await setup(t, [fixture('missing'), fixture('preserved')], body => ({
    mode: 'live', promptLanguage: 'en', prompt: body.prompt.endsWith('missing') ? resultMarker : `${resultMarker} ACME-42`,
  }));
  const result = await run(context);
  assert.equal(result.code, 1);
  assert.match(result.stdout, /missing: HTTP 200;.*literalFailures=1/);
  const saved = JSON.parse(await readFile(context.output, 'utf8'));
  assert.equal(saved.results.length, 2);
  assert.deepEqual(saved.results.map(entry => entry.semanticReview), ['pending', 'pending']);
  assert.equal(saved.results[0].result.prompt, resultMarker);
  assert.equal(saved.results[0].literalChecks[0].preserved, false);
  assert.equal(saved.results[1].literalChecks[0].preserved, true);
});

test('runner 在任何 HTTP 請求前拒絕不明、重複或空白的 ID 與無效選項', async t => {
  const context = await setup(t, [fixture('case-a'), fixture('case-ab')]);
  for (const extra of [
    ['--ids', 'case'], ['--ids', 'case-a,case-a'], ['--ids', 'case-a,'],
    ['--ids', 'case-a', '--ids', 'case-ab'], ['--ids'], ['--unknown', keyMarker],
  ]) {
    const result = await run(context, extra);
    assert.equal(result.code, 1);
    assert.equal(context.requests.length, 0);
  }
});

test('runner 請求前檢查案例結構、重複 ID 及最多 60 例的邊界', async t => {
  for (const cases of [
    [], [null], [fixture('duplicate'), fixture('duplicate')],
    [fixture('bad-task', { task: 'unknown' })], [fixture('bad-prompt', { prompt: ' ' })],
    [fixture('bad-literals', { expected: { literals: ['ACME-42', 42] } })],
    [fixture('bad-expected', { expected: [] })],
    [fixture(`bad-id\n${sourceMarker}`)],
    Array.from({ length: 61 }, (_, index) => fixture(`case-${index}`)),
    `{${sourceMarker}`,
  ]) {
    const context = await setup(t, cases);
    const result = await run(context);
    assert.equal(result.code, 1);
    assert.equal(context.requests.length, 0);
  }
  const context = await setup(t, Array.from({ length: 60 }, (_, index) => fixture(`case-${index}`)));
  const result = await run(context, ['--ids', 'case-59']);
  assert.equal(result.code, 0, result.stderr);
  assert.equal(context.requests.filter(request => request.path === '/api/optimize').length, 1);
});

test('runner 保留 --live 門檻與本機 URL 限制，錯誤不洩露網址內容', async t => {
  const context = await setup(t, [fixture('one')]);
  const missingLive = await run(context, [], false);
  assert.equal(missingLive.code, 1);
  assert.match(missingLive.stderr, /--live/);
  assert.equal(context.requests.length, 0);
  for (const url of [`https://example.com/${keyMarker}`, `http://${keyMarker}@127.0.0.1/`, keyMarker]) {
    const { url: original } = context;
    context.url = url;
    const result = await run(context);
    context.url = original;
    assert.equal(result.code, 1);
    assert.equal(context.requests.length, 0);
  }
});

test('runner 拒絕 mock 設定且不送出優化請求', async t => {
  const context = await setup(t, [fixture('one')]);
  context.server.removeAllListeners('request');
  context.server.on('request', (request, response) => {
    context.requests.push({ path: request.url });
    response.setHeader('Content-Type', 'application/json');
    response.end(JSON.stringify({ service: 'prompt-studio', mode: 'mock', ready: true }));
  });
  const result = await run(context);
  assert.equal(result.code, 1);
  assert.match(result.stderr, /mock/);
  assert.deepEqual(context.requests.map(request => request.path), ['/api/config']);
});

test('HTTP 錯誤與非 live 回應均失敗，console 不含服務回傳內容', async t => {
  const context = await setup(t, [fixture('http-error'), fixture('mock-result')], (body, { response }) => {
    if (body.prompt.endsWith('http-error')) {
      response.statusCode = 502;
      return { error: `${keyMarker} ${sourceMarker}` };
    }
    return { mode: 'mock', promptLanguage: 'en', prompt: resultMarker };
  });
  const result = await run(context);
  assert.equal(result.code, 1);
  const saved = JSON.parse(await readFile(context.output, 'utf8'));
  assert.ok(saved.results.every(entry => entry.error));
  assert.ok(saved.results.every(entry => entry.semanticReview === 'pending'));
  assert.ok(!JSON.stringify(saved).includes(keyMarker), 'raw provider error messages are not saved');
});

test('runner 預設在兩次連續請求失敗後停止，保存總數、未嘗試 ID 與原因', async t => {
  const context = await setup(t, ['first', 'second', 'third', 'fourth'].map(id => fixture(id)), (_body, { response }) => {
    response.statusCode = 502;
    return { error: `${keyMarker} ${sourceMarker}` };
  });
  const result = await run(context);
  assert.equal(result.code, 1);
  assert.match(result.stderr, /已停止/);
  assert.equal(context.requests.filter(request => request.path === '/api/optimize').length, 2);
  const saved = JSON.parse(await readFile(context.output, 'utf8'));
  assert.deepEqual(saved.totals, { attempted: 2, succeeded: 0, failed: 2, unattempted: 2 });
  assert.deepEqual(saved.unattemptedIDs, ['third', 'fourth']);
  assert.deepEqual(saved.stopReason, { code: 'consecutive_request_failures', count: 2, limit: 2 });
  assert.equal(saved.status, 'stopped');
  assert.equal(saved.semanticStatus, 'pending');
  assert.ok(saved.results.every(entry => entry.failureKind === 'http' && entry.semanticStatus === 'pending'));
  assert.ok(!JSON.stringify(saved).includes(keyMarker));
});

test('有效回應即使遺漏字面內容也會重置連續請求失敗，不會提早跳過案例', async t => {
  const context = await setup(t, ['http-a', 'literal-a', 'http-b', 'literal-b', 'ok', 'http-c', 'http-d', 'unattempted'].map(id => fixture(id)),
    (body, { response }) => {
      if (body.prompt.includes(' http-')) { response.statusCode = 503; return { error: keyMarker }; }
      return { mode: 'live', promptLanguage: 'en', prompt: body.prompt.endsWith('ok') ? `${resultMarker} ACME-42` : resultMarker };
    });
  const result = await run(context);
  assert.equal(result.code, 1);
  const saved = JSON.parse(await readFile(context.output, 'utf8'));
  assert.deepEqual(saved.results.map(entry => entry.id), ['http-a', 'literal-a', 'http-b', 'literal-b', 'ok', 'http-c', 'http-d']);
  assert.deepEqual(saved.totals, { attempted: 7, succeeded: 1, failed: 6, unattempted: 1 });
  assert.deepEqual(saved.unattemptedIDs, ['unattempted']);
  assert.equal(saved.results[1].failureKind, undefined, 'literal mismatch is not a request failure');
  assert.equal(saved.results[1].literalChecks[0].preserved, false);
});

test('runner 的明確連續失敗上限可設為 1 或 10', async t => {
  for (const limit of [1, 10]) {
    const context = await setup(t, Array.from({ length: 11 }, (_, index) => fixture(`case-${index}`)), () => ({
      mode: 'mock', promptLanguage: 'en', prompt: resultMarker,
    }));
    const result = await run(context, ['--max-consecutive-failures', String(limit)]);
    assert.equal(result.code, 1);
    const saved = JSON.parse(await readFile(context.output, 'utf8'));
    assert.equal(saved.maxConsecutiveFailures, limit);
    assert.equal(saved.totals.attempted, limit);
    assert.equal(saved.totals.unattempted, 11 - limit);
    assert.ok(saved.results.every(entry => entry.failureKind === 'response'));
  }
});

test('連線中斷與無效 JSON 也會觸發上限，原始錯誤內容不進入紀錄', async t => {
  for (const failureKind of ['connection', 'response']) {
    const context = await setup(t, ['first', 'second', 'unattempted'].map(id => fixture(id)), (_body, { response }) => {
      if (failureKind === 'connection') response.destroy();
      else response.end(`invalid-json ${keyMarker}`);
    });
    const result = await run(context);
    assert.equal(result.code, 1);
    const saved = JSON.parse(await readFile(context.output, 'utf8'));
    assert.deepEqual(saved.totals, { attempted: 2, succeeded: 0, failed: 2, unattempted: 1 });
    assert.deepEqual(saved.unattemptedIDs, ['unattempted']);
    assert.ok(saved.results.every(entry => entry.failureKind === failureKind));
    assert.ok(!JSON.stringify(saved).includes(keyMarker));
  }
});
