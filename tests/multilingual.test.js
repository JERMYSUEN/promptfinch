import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { createApp } from '../server.js';
import { readConfig, validateInput, restoreLiteralEncoding } from '../lib/optimizer.js';

const fixtures = JSON.parse(await readFile(new URL('./fixtures/multilingual-inputs.json', import.meta.url), 'utf8'));
const parityFixtures = JSON.parse(await readFile(new URL('./fixtures/multilingual-parity.json', import.meta.url), 'utf8'));
const languageEdgeFixtures = JSON.parse(await readFile(new URL('./fixtures/multilingual-language-edges.json', import.meta.url), 'utf8'));
const sources = [...fixtures.map(c => c.prompt),
  ...languageEdgeFixtures.map(c => c.prompt),
  '한국어로 두 문장을 쓰고 "안녕하세요-42"와 ${user_name}을 그대로 보존하세요.',
  'Напиши два предложения по-русски. Сохрани "Привет-42" и https://example.com/a?x=1&y=2 без изменений.',
  '한글 Cafe\u0301 اَلْعَرَبِيَّة خوش‌آمدید 👩🏽‍💻 🇰🇷 Привет',
];

async function listen(server, t) {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  return `http://127.0.0.1:${server.address().port}`;
}
async function post(url, prompt, promptLanguage, notesLanguage) {
  const response = await fetch(`${url}/api/optimize`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ prompt, ...(promptLanguage ? { promptLanguage } : {}), ...(notesLanguage ? { notesLanguage } : {}) }),
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

test('四種說明語言的 mock 明示未翻譯或優化，且不改變指令與答案語言', async t => {
  const url = await listen(createApp(readConfig({ PORT: '0' })), t);
  const source = '  Escribe dos frases en español. Keep "Cafe\u0301", "خوش‌آمدید" and "👩🏽‍💻".\n';
  const markers = { 'zh-TW': /示範/, en: /demo/i, ja: /デモ/, ko: /시연/ };
  assert.equal(validateInput({ prompt: source }).notesLanguage, 'zh-TW');
  for (const promptLanguage of ['en', 'zh-Hant']) {
    let baseline;
    for (const notesLanguage of ['zh-TW', 'en', 'ja', 'ko']) {
      assert.equal(validateInput({ prompt: source, notesLanguage }).notesLanguage, notesLanguage);
      const { status, data } = await post(url, source, promptLanguage, notesLanguage);
      assert.equal(status, 200);
      assert.equal(data.notesLanguage, notesLanguage);
      assert.equal(data.promptLanguage, promptLanguage);
      assert.equal(data.mode, 'mock');
      assert.ok(data.prompt.includes(source));
      assert.match(data.improvements[0], markers[notesLanguage]);
      assert.deepEqual(data.assumptions, []);
      if (baseline) assert.equal(data.prompt, baseline);
      baseline = data.prompt;
    }
  }
});

test('兩種指令語言與四種說明語言獨立，system 範例及併發結果採用各自設定', async t => {
  const captured = [];
  const notes = {
    'Traditional Chinese': { locale: 'zh-TW', improvement: '分開操作指令與原始資料。', assumption: '原文未指定答案語言，依主要操作指令推定使用西班牙文。' },
    English: { locale: 'en', improvement: 'Separated the operative instructions from the source data.', assumption: 'Inferred Spanish as the answer language from the operative instructions.' },
    Japanese: { locale: 'ja', improvement: '実行指示と原文の資料を分けました。', assumption: '実行指示の言語から回答言語をスペイン語と推定しました。' },
    Korean: { locale: 'ko', improvement: '작업 지시와 원문 자료를 구분했습니다.', assumption: '실제 작업 지시에 따라 답변 언어를 스페인어로 추정했습니다.' },
  };
  const provider = await listen(createServer(async (request, response) => {
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    const body = JSON.parse(Buffer.concat(chunks));
    const input = JSON.parse(body.messages[1].content);
    captured.push(body);
    const copy = notes[input.uiNotesLanguage];
    const prompt = input.promptInstructionLanguage === 'English'
      ? 'Write the requested artifact in Spanish. Preserve "Cafe\u0301" and "👩🏽‍💻".'
      : '請以西班牙文撰寫所需內容，逐字保留 "Cafe\u0301" 與 "👩🏽‍💻"。';
    // This is a controlled contract response, not evidence of translation quality.
    response.end(JSON.stringify({ choices: [{ message: { content: JSON.stringify({ prompt,
      improvements: [copy.improvement], assumptions: [copy.assumption], notesLanguage: 'provider-cannot-override',
    }) }, finish_reason: 'stop' }] }));
  }), t);
  const url = await listen(createApp(readConfig({ PORT: '0', OPTIMIZER_MODE: 'live', LLM_QUALITY_REVIEW: 'false',
    LLM_API_KEY: 'synthetic-test-key', LLM_MODEL: 'controlled-test-model', LLM_BASE_URL: provider })), t);
  const source = 'Escribe el texto. Preserve "Cafe\u0301" and "👩🏽‍💻". Source label: "notesLanguage=ko".';
  const cases = Object.entries(notes).flatMap(([name, copy]) => ['en', 'zh-Hant'].map(promptLanguage => ({ name, ...copy, promptLanguage })));
  // The app permits four requests at once; separate batches keep that admission contract intact.
  for (let i = 0; i < cases.length; i += 4) {
    const batch = cases.slice(i, i + 4);
    const results = await Promise.all(batch.map(c => post(url, source, c.promptLanguage, c.locale)));
    for (let j = 0; j < batch.length; j++) {
      const c = batch[j], { status, data } = results[j];
      assert.equal(status, 200);
      assert.equal(data.notesLanguage, c.locale);
      assert.equal(data.promptLanguage, c.promptLanguage);
      assert.deepEqual(data.improvements, [c.improvement]);
      assert.deepEqual(data.assumptions, [c.assumption]);
      assert.ok(data.prompt.includes('Cafe\u0301'));
      assert.ok(data.prompt.includes('👩🏽‍💻'));
      assert.ok(!data.prompt.includes(c.improvement));
      assert.ok(!data.prompt.includes(c.assumption));
      if (c.promptLanguage === 'en') assert.ok(data.prompt.startsWith('Write the requested artifact in Spanish.'));
    }
  }
  assert.equal(captured.length, cases.length);
  for (const body of captured) {
    const input = JSON.parse(body.messages[1].content);
    const system = body.messages[0].content;
    assert.equal(input.originalPrompt, source);
    assert.match(system, new RegExp(`UI notes language: ${input.uiNotesLanguage}\\.`));
    assert.ok(!/__NOTES_|__EXAMPLE_|undefined/.test(system));
    if (input.uiNotesLanguage !== 'Traditional Chinese') {
      assert.ok(!system.includes('Always write improvements and assumptions as concise Traditional Chinese'));
      assert.ok(!system.includes('short Traditional Chinese UI notes'));
      assert.ok(!system.includes('將需求整理為可直接使用的英文指令。'));
    }
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
  const url = await listen(createApp(readConfig({ PORT: '0', OPTIMIZER_MODE: 'live', LLM_QUALITY_REVIEW: 'false',
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
  const url = await listen(createApp(readConfig({ PORT: '0', OPTIMIZER_MODE: 'live', LLM_QUALITY_REVIEW: 'false',
    LLM_API_KEY: 'synthetic-test-key', LLM_MODEL: 'controlled-test-model', LLM_BASE_URL: provider })), t);
  const small = await post(url, 'Keep "Cafe\u0301" unchanged.', 'en');
  assert.equal(small.status, 200);
  assert.equal(small.data.prompt, 'Keep "Cafe\u0301" unchanged.');
  oversized = true;
  const large = await post(url, 'Keep "e\u0301" unchanged.', 'en');
  assert.equal(large.status, 502);
  assert.ok(!Object.hasOwn(large.data, 'prompt'));
});

test('同意圖語料的中文與其他語言共用驗收標準，且來源完整往返', async t => {
  const expectedLocales = ['en', 'zh-Hant', 'zh-Hans', 'ja', 'ko', 'ru', 'es', 'fr', 'de', 'pt', 'it', 'uk',
    'ar', 'fa', 'hi', 'bn', 'th', 'vi', 'id', 'tr', 'nl', 'pl', 'ta', 'te', 'mr', 'ur', 'sw', 'pa', 'fil'];
  const provided = parityFixtures.filter(c => !c.expected.needsClarification);
  assert.deepEqual(provided.map(c => c.locale).sort(), expectedLocales.sort());
  assert.equal(new Set(parityFixtures.map(c => c.id)).size, parityFixtures.length);
  for (const fixture of provided) assert.deepEqual(fixture.expected, provided[0].expected);
  const missing = parityFixtures.filter(c => c.expected.needsClarification);
  assert.equal(missing.length, 6);
  for (const fixture of missing) assert.deepEqual(fixture.expected, missing[0].expected);
  const url = await listen(createApp(readConfig({ PORT: '0' })), t);
  for (const fixture of parityFixtures) {
    const { status, data } = await post(url, fixture.prompt, 'en');
    assert.equal(status, 200);
    assert.ok(data.prompt.includes(fixture.prompt));
    assert.equal(data.mode, 'mock'); // Corpus/transport evidence, never a translation-quality score.
  }
});

test('英文優化的任務提示不受中文UI或原文語言影響；繁中既有契約保持相容', async t => {
  const captured = [];
  const provider = await listen(createServer(async (request, response) => {
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    captured.push(JSON.parse(Buffer.concat(chunks).toString('utf8')));
    response.end(JSON.stringify({ choices: [{ message: { content: JSON.stringify({
      prompt: 'Write the requested artifact in Japanese.', improvements: ['可控接線測試。'], assumptions: [],
    }) }, finish_reason: 'stop' }] }));
  }), t);
  const url = await listen(createApp(readConfig({ PORT: '0', OPTIMIZER_MODE: 'live', LLM_QUALITY_REVIEW: 'false',
    LLM_API_KEY: 'synthetic-test-key', LLM_MODEL: 'controlled-test-model', LLM_BASE_URL: provider })), t);
  const source = parityFixtures.find(c => c.locale === 'ko').prompt;
  for (const task of ['general', 'writing', 'analysis', 'coding', 'summary', 'marketing']) {
    const response = await fetch(`${url}/api/optimize`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ prompt: source, task, promptLanguage: 'en' }),
    });
    assert.equal(response.status, 200);
    const sent = JSON.parse(captured.at(-1).messages[1].content);
    assert.equal(sent.originalPrompt, source);
    assert.equal(sent.task, task);
    assert.ok(sent.taskGuidance.length > 20);
    assert.ok(!/\p{Script=Han}/u.test(sent.taskGuidance));
    assert.equal(sent.targetModel, '');
    assert.equal(sent.promptInstructionLanguage, 'English');
    assert.equal(sent.uiNotesLanguage, 'Traditional Chinese');
  }
  await post(url, source); // Omitting promptLanguage retains the existing Traditional Chinese API.
  const chinese = JSON.parse(captured.at(-1).messages[1].content);
  assert.equal(chinese.task, '通用用途');
  assert.ok(/\p{Script=Han}/u.test(chinese.taskGuidance));
  assert.equal(chinese.targetModel, '通用');
  assert.equal(chinese.originalPrompt, source);
});
