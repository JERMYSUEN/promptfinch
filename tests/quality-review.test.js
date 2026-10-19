import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { optimize, readConfig, validateInput, AppError } from '../lib/optimizer.js';

const input = validateInput({ prompt: 'Write two friendly welcome sentences in Korean.', promptLanguage: 'en', notesLanguage: 'en' });
const candidate = { prompt: 'Write exactly two friendly welcome sentences in Korean.', improvements: ['Clarified the sentence count.'], assumptions: [] };
const approval = { approved: true, issues: [] };

async function provider(t, handler, env = {}) {
  const calls = [];
  const timers = [];
  const server = createServer(async (request, response) => {
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    const call = { body: JSON.parse(Buffer.concat(chunks)), authorization: request.headers.authorization, path: request.url };
    calls.push(call);
    const result = await handler(call, calls.length);
    if (result === undefined) return;
    const send = () => response.end(JSON.stringify({ choices: [{ message: { content: typeof result.content === 'string'
      ? result.content : JSON.stringify(result.content) }, finish_reason: result.finishReason || 'stop' }] }));
    if (result.delay) timers.push(setTimeout(send, result.delay));
    else send();
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => { timers.forEach(clearTimeout); server.closeAllConnections(); return new Promise(resolve => server.close(resolve)); });
  const config = readConfig({ OPTIMIZER_MODE: 'live', LLM_API_KEY: 'synthetic-review-secret', LLM_MODEL: 'synthetic-review-model',
    LLM_BASE_URL: `http://127.0.0.1:${server.address().port}/v1`, LLM_QUALITY_REVIEW: 'true', ...env });
  return { calls, config };
}

test('explicit live fidelity review uses separate context and the same private provider', async t => {
  assert.equal(readConfig({}).qualityReview, false);
  const { calls, config } = await provider(t, (_, count) => ({ content: count === 1 ? candidate : approval }));
  assert.equal(config.qualityReview, true);
  const result = await optimize(input, config);
  assert.equal(calls.length, 2);
  assert.deepEqual(result.modelReview, { status: 'approved', revisionCount: 0 });
  assert.equal(result.prompt, candidate.prompt);
  for (const call of calls) {
    assert.equal(call.path, '/v1/chat/completions');
    assert.equal(call.authorization, 'Bearer synthetic-review-secret');
    assert.equal(call.body.model, 'synthetic-review-model');
    assert.equal(call.body.messages.length, 2);
    assert.deepEqual(call.body.response_format, { type: 'json_object' });
  }
  assert.notEqual(calls[0].body.messages[0].content, calls[1].body.messages[0].content);
  const reviewData = JSON.parse(calls[1].body.messages[1].content);
  assert.equal(reviewData.originalPrompt, input.prompt);
  assert.deepEqual(reviewData.candidate, candidate);
  assert.equal(reviewData.promptInstructionLanguage, 'English');
  assert.equal(reviewData.uiNotesLanguage, 'English');
  assert.ok(!JSON.stringify(result).includes('synthetic-review-secret'));
  assert.ok(!JSON.stringify(result).includes('approved":true'));
});

test('omitted fidelity review setting makes only one live provider call', async t => {
  const { calls, config } = await provider(t, () => ({ content: candidate }), { LLM_QUALITY_REVIEW: undefined });
  assert.equal(config.qualityReview, false);
  assert.deepEqual((await optimize(input, config)).modelReview, { status: 'disabled', revisionCount: 0 });
  assert.equal(calls.length, 1);
  const legacyConfig = { ...config };
  delete legacyConfig.qualityReview;
  assert.deepEqual((await optimize(input, legacyConfig)).modelReview, { status: 'disabled', revisionCount: 0 });
  assert.equal(calls.length, 2);
});

test('a rejected edit gets one repair and a new independent review', async t => {
  const bad = { ...candidate, prompt: 'Write three welcome sentences in Korean.' };
  const issue = 'The original requires two sentences, not three.';
  const { calls, config } = await provider(t, (_, count) => ({ content: [bad, { approved: false, issues: [issue] }, candidate, approval][count - 1] }));
  const result = await optimize(input, config);
  assert.equal(calls.length, 4);
  assert.equal(result.prompt, candidate.prompt);
  assert.deepEqual(result.modelReview, { status: 'approved', revisionCount: 1 });
  const repairData = JSON.parse(calls[2].body.messages[1].content);
  assert.deepEqual(repairData.priorCandidate, bad);
  assert.deepEqual(repairData.reviewIssues, [issue]);
  assert.equal(repairData.originalPrompt, input.prompt);
  assert.ok(!JSON.stringify(result).includes(issue));
});

test('a second semantic rejection returns a safe error and no partial result', async t => {
  const issue = 'private reviewer text with synthetic-review-secret';
  const { calls, config } = await provider(t, (_, count) => ({ content: count % 2 ? candidate : { approved: false, issues: [issue] } }));
  await assert.rejects(optimize(input, config), error => error instanceof AppError && error.status === 502
    && !error.message.includes(issue) && !error.message.includes('synthetic-review-secret'));
  assert.equal(calls.length, 4);
});

for (const malformed of [
  'not JSON', { approved: true, issues: ['contradiction'] }, { approved: false, issues: [] },
  { approved: 'true', issues: [] }, { approved: true, issues: [], extra: 'not schema' },
  { approved: false, issues: Array(7).fill('issue') }, { approved: false, issues: ['x'.repeat(501)] },
]) {
  test(`malformed reviewer result fails closed: ${JSON.stringify(malformed).slice(0, 60)}`, async t => {
    const { calls, config } = await provider(t, (_, count) => ({ content: count === 1 ? candidate : malformed }));
    await assert.rejects(optimize(input, config), error => error instanceof AppError && error.status === 502);
    assert.equal(calls.length, 2);
  });
}

test('review shares the original total deadline rather than receiving a new budget', async t => {
  const { calls, config } = await provider(t, (_, count) => ({ content: count === 1 ? candidate : approval, delay: 100 }), { LLM_TIMEOUT_MS: '170' });
  await assert.rejects(optimize(input, config), error => error.status === 504);
  assert.equal(calls.length, 2);
});

test('cancellation while reviewing stops without repair or a returned candidate', async t => {
  const cancellation = new AbortController();
  const { calls, config } = await provider(t, (_, count) => {
    if (count === 2) { setTimeout(() => cancellation.abort(), 10); return undefined; }
    return { content: candidate };
  });
  await assert.rejects(optimize(input, config, cancellation.signal), error => error.status === 504);
  assert.equal(calls.length, 2);
});

test('review can be explicitly disabled and mock always makes zero model calls', async t => {
  const { calls, config } = await provider(t, () => ({ content: candidate }), { LLM_QUALITY_REVIEW: 'false' });
  assert.equal(config.qualityReview, false);
  const result = await optimize(input, config);
  assert.equal(calls.length, 1);
  assert.deepEqual(result.modelReview, { status: 'disabled', revisionCount: 0 });
  const mock = await optimize(input, { ...config, mode: 'mock', qualityReview: true });
  assert.equal(calls.length, 1);
  assert.equal(mock.mode, 'mock');
  assert.ok(!Object.hasOwn(mock, 'modelReview'));
  for (const value of ['yes', 'TRUE', '', '0']) assert.throws(() => readConfig({ LLM_QUALITY_REVIEW: value }), /LLM_QUALITY_REVIEW/);
});

test('editor format retries share the two-edit budget and truncated edits are never reviewed', async t => {
  const { calls, config } = await provider(t, (_, count) => ({ content: count === 1 ? 'not JSON' : count === 2 ? candidate : approval }));
  assert.equal((await optimize(input, config)).modelReview.status, 'approved');
  assert.equal(calls.length, 3);
  const truncated = await provider(t, () => ({ content: candidate, finishReason: 'length' }));
  await assert.rejects(optimize(input, truncated.config), error => error.status === 502 && /截斷/.test(error.message));
  assert.equal(truncated.calls.length, 1);
});

test('truncated reviewer approval is rejected without repair or partial output', async t => {
  const { calls, config } = await provider(t, (_, count) => ({ content: count === 1 ? candidate : approval,
    finishReason: count === 1 ? 'stop' : 'length' }));
  await assert.rejects(optimize(input, config), error => error instanceof AppError && error.status === 502);
  assert.equal(calls.length, 2);
});

test('Unicode repair runs before review and a rejected second edit cannot trigger a third editor call', async t => {
  const source = validateInput({ prompt: 'Keep "Cafe\u0301" exactly.', promptLanguage: 'en', notesLanguage: 'en' });
  const { calls, config } = await provider(t, (call, count) => {
    if (count === 1) return { content: 'not JSON' };
    if (count === 2) return { content: { ...candidate, prompt: 'Keep "Café" exactly.' } };
    const reviewed = JSON.parse(call.body.messages[1].content).candidate;
    assert.equal(reviewed.prompt, 'Keep "Cafe\u0301" exactly.');
    return { content: { approved: false, issues: ['The candidate omitted an essential instruction.'] } };
  });
  await assert.rejects(optimize(source, config), error => error.status === 502);
  assert.equal(calls.length, 3);
});
