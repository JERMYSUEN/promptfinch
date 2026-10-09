import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { createApp } from '../server.js';
import { readConfig, validateInput, restoreLiteralEncoding } from '../lib/optimizer.js';

const fixtures = JSON.parse(await readFile(new URL('./fixtures/multilingual-inputs.json', import.meta.url), 'utf8'));
const sources = [...fixtures.map(c => c.prompt),
  '한국어로 두 문장을 쓰고 "안녕하세요-42"와 ${user_name}을 그대로 보존하세요.',
  'Напиши два предложения по-русски. Сохрани "Привет-42" и https://example.com/a?x=1&y=2 без изменений.',
  '한글 Cafe\u0301 اَلْعَرَبِيَّة خوش‌آمدید 👩🏽‍💻 🇰🇷 Привет',
];

async function listen(server, t) {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  return `http://127.0.0.1:${server.address().port}`;
}
async function post(url, prompt, promptLanguage) {
  const response = await fetch(`${url}/api/optimize`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ prompt, ...(promptLanguage ? { promptLanguage } : {}) }),
  });
  return { status: response.status, data: await response.json() };
}

test('主要文字系統、韓俄、RTL、NFD、ZWNJ、emoji 原文不正規化或過濾', () => {
  for (const source of sources) {
    const prompt = ` \t${source}\n`;
    assert.equal(validateInput({ prompt, promptLanguage: 'en' }).prompt, prompt);
    assert.deepEqual([...validateInput({ prompt }).prompt].map(c => c.codePointAt(0)), [...prompt].map(c => c.codePointAt(0)));
  }
});

test('僅還原來源中明確且不歧義的非NFC字面，不猜測或改動一般文字', () => {
  const decomposed = 'Cafe\u0301';
  assert.equal(restoreLiteralEncoding('Keep "Café".', `Keep "${decomposed}".`), `Keep "${decomposed}".`);
  assert.equal(restoreLiteralEncoding('Keep Café and Caféteria.', `Keep 「${decomposed}」.`), `Keep ${decomposed} and Caféteria.`);
  assert.equal(restoreLiteralEncoding('Keep "Café".', `Keep "${decomposed}" and "Café".`), 'Keep "Café".');
  assert.equal(restoreLiteralEncoding('Write about Café.', `Écris sur ${decomposed}.`), 'Write about Café.');
  assert.equal(restoreLiteralEncoding('Keep "Café".', 'Keep "different".'), 'Keep "Café".');
  assert.equal(restoreLiteralEncoding('Return `Café`.', `Keep '${decomposed}'.`), `Return \`${decomposed}\`.`);
});

test('多語 mock 接線完整保存原文；API省略語言仍繁中且英文模式明示未翻譯', async t => {
  const url = await listen(createApp(readConfig({ PORT: '0', OPTIMIZER_MODE: 'mock' })), t);
  for (const source of sources) {
    for (const language of ['en', undefined]) {
      const { status, data } = await post(url, source, language);
      assert.equal(status, 200);
      assert.equal(data.mode, 'mock');
      assert.equal(data.promptLanguage, language || 'zh-Hant');
      assert.ok(data.prompt.includes(source));
      if (language === 'en') assert.ok(data.prompt.includes('NOT been translated'));
    }
  }
});

test('相容服務 JSON/UTF-8 多語往返及分段回應無損；此測試不是翻譯品質證據', async t => {
  const captured = [];
  const output = 'Write two sentences in Korean. Preserve "안녕", "Привет", "Cafe\u0301", "خوش‌آمدید", "👩🏽‍💻", "${user_name}" and https://example.com/a?x=1&y=2 exactly.';
  const provider = await listen(createServer(async (request, response) => {
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    captured.push(JSON.parse(body.messages[1].content).originalPrompt);
    const content = JSON.stringify({ prompt: output, improvements: ['接線測試，沒有語意生成。'], assumptions: [] });
    const bytes = Buffer.from(JSON.stringify({ choices: [{ message: { content }, finish_reason: 'stop' }] }));
    response.writeHead(200, { 'Content-Type': 'application/json' });
    // Small byte chunks intentionally cross UTF-8 character boundaries.
    for (let i = 0; i < bytes.length; i += 7) {
      response.write(bytes.subarray(i, i + 7));
      await new Promise(resolve => setImmediate(resolve));
    }
    response.end();
  }), t);
  const url = await listen(createApp(readConfig({ PORT: '0', OPTIMIZER_MODE: 'live',
    LLM_API_KEY: 'synthetic-test-key', LLM_MODEL: 'controlled-test-model', LLM_BASE_URL: provider })), t);
  for (const source of sources) {
    const { status, data } = await post(url, source, 'en');
    assert.equal(status, 200);
    assert.equal(captured.at(-1), source);
    assert.equal(data.prompt, output);
    assert.deepEqual(data.assumptions, []);
  }
});

test('UTF-16 邊界接受完整內容或拒絕超長輸入，不以語言計數或截短', async t => {
  const url = await listen(createApp(readConfig({ PORT: '0' })), t);
  for (const source of ['😀'.repeat(6000), '한'.repeat(4000), 'Я'.repeat(12000)]) {
    const { status, data } = await post(url, source, 'en');
    assert.equal(status, 200);
    assert.ok(data.prompt.includes(source));
    const over = await post(url, `${source}x`, 'en');
    assert.equal(over.status, 400);
    assert.ok(!Object.hasOwn(over.data, 'prompt'));
  }
});

test('英文live API實際還原NFD字面；還原後過長仍拒絕完整結果而非裁切', async t => {
  let oversized = false;
  const provider = await listen(createServer((request, response) => {
    request.resume();
    const prompt = oversized ? 'é '.repeat(12000) : 'Keep "Café" unchanged.';
    response.end(JSON.stringify({ choices: [{ message: { content: JSON.stringify({ prompt,
      improvements: ['可控接線測試。'], assumptions: [] }) }, finish_reason: 'stop' }] }));
  }), t);
  const url = await listen(createApp(readConfig({ PORT: '0', OPTIMIZER_MODE: 'live',
    LLM_API_KEY: 'synthetic-test-key', LLM_MODEL: 'controlled-test-model', LLM_BASE_URL: provider })), t);
  const small = await post(url, 'Keep "Cafe\u0301" unchanged.', 'en');
  assert.equal(small.status, 200);
  assert.equal(small.data.prompt, 'Keep "Cafe\u0301" unchanged.');
  oversized = true;
  const large = await post(url, 'Keep "e\u0301" unchanged.', 'en');
  assert.equal(large.status, 502);
  assert.ok(!Object.hasOwn(large.data, 'prompt'));
});
