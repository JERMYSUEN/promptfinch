import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createApp } from '../server.js';
import { readConfig, validateInput, MAX_PROMPT_LENGTH } from '../lib/optimizer.js';

async function listen(server, t) {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  return `http://127.0.0.1:${server.address().port}`;
}

async function app(t, env = {}) {
  return listen(createApp(readConfig({ ...env, PORT: '0' })), t);
}

async function post(url, value, headers = {}) {
  const response = await fetch(`${url}/api/optimize`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify(value),
  });
  return { status: response.status, data: await response.json() };
}

async function providerApp(t, handler, env = {}) {
  const provider = await listen(createServer(handler), t);
  return app(t, { OPTIMIZER_MODE: 'live', LLM_API_KEY: 'test-secret-key', LLM_MODEL: 'test-model', LLM_BASE_URL: `${provider}/v1`, ...env });
}

function sendCompletion(response, result, finishReason = 'stop') {
  response.writeHead(200, { 'Content-Type': 'application/json' });
  response.end(JSON.stringify({ choices: [{ message: { content: typeof result === 'string' ? result : JSON.stringify(result) }, finish_reason: finishReason }] }));
}

const validResult = { prompt: '依指定格式完成任務，並核對字數。', improvements: ['補上核對步驟。'], assumptions: [] };

test('設定預設為 mock，不會因金鑰存在而自動傳送內容', () => {
  assert.equal(readConfig({ LLM_API_KEY: 'a-key' }).mode, 'mock');
  for (const env of [
    { OPTIMIZER_MODE: 'other' }, { PORT: '-1' }, { LLM_TIMEOUT_MS: 'abc' },
    { LLM_JSON_MODE: 'yes' }, { LLM_BASE_URL: 'file:///tmp/a' },
    { LLM_THINKING_MODE: 'unknown' },
    { LLM_BASE_URL: 'https://user:pass@example.com/v1' },
  ]) assert.throws(() => readConfig(env));
});

test('輸入保留空白、程式碼縮排與原始內容', () => {
  const prompt = '  請整理\n    const a = 1;\n';
  assert.equal(validateInput({ prompt }).prompt, prompt);
});

test('多語 Unicode 原文不受來源語言限制且逐字保留', () => {
  const prompt = '日本語の依頼。Escribe un aviso breve en español. أجب بالعربية. Keep the literal 「設定変更」 exactly.';
  assert.equal(validateInput({ prompt, promptLanguage: 'en' }).prompt, prompt);
});

test('設定 API 不洩漏金鑰或服務商網址，且前端文件不載入外部資源', async t => {
  const url = await app(t, { LLM_API_KEY: 'private-key', LLM_BASE_URL: 'https://secret-provider.invalid/v1' });
  const response = await fetch(`${url}/api/config`);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  const data = await response.json();
  assert.equal(data.mode, 'mock');
  assert.equal(data.ready, true);
  assert.equal(data.maxPromptLength, MAX_PROMPT_LENGTH);
  assert.ok(!JSON.stringify(data).includes('private-key'));
  assert.ok(!JSON.stringify(data).includes('secret-provider'));
  const page = await fetch(url);
  assert.equal(page.status, 200);
  assert.ok(page.headers.get('content-security-policy').includes("connect-src 'self'"));
  assert.ok((await page.text()).includes('lang="zh-Hant"'));
  assert.equal((await fetch(`${url}/.env`)).status, 404);
  assert.equal((await fetch(`${url}/lib/optimizer.js`)).status, 404);
});

test('原生 App 可用版本及執行個體識別拒絕連到舊後端程序', async t => {
  const backendID = 'a'.repeat(64);
  const backendInstanceID = '3f5dbd86-9ae6-43a1-a938-02d6739f5e36';
  const url = await app(t, { PROMPT_STUDIO_BACKEND_ID: backendID, PROMPT_STUDIO_BACKEND_INSTANCE: backendInstanceID });
  const config = await (await fetch(`${url}/api/config`)).json();
  assert.equal(config.backendID, backendID);
  assert.equal(config.backendInstanceID, backendInstanceID);
});

test('mock 完整保留原意、明示模式，並區隔 Prompt 與說明', async t => {
  const url = await app(t);
  const prompt = '翻譯為英文，不要摘要。名字「林小明」、價格 NT$1,280 不得改變。只輸出 JSON。';
  const { status, data } = await post(url, { prompt, task: 'writing', targetModel: 'Claude' });
  assert.equal(status, 200);
  assert.equal(data.mode, 'mock');
  assert.equal(data.generationModel, null);
  assert.ok(data.prompt.includes(prompt));
  assert.ok(data.prompt.includes('以原始需求為準'));
  assert.ok(data.improvements.some(item => item.includes('沒有進行語意分析')));
  assert.ok(data.improvements.some(item => item.includes('不提供模型專屬調整')));
  assert.deepEqual(data.assumptions, []);
});

for (const task of ['general', 'writing', 'analysis', 'coding', 'summary', 'marketing']) {
  test(`用途 ${task} 可產生示範結果`, async t => {
    const { status, data } = await post(await app(t), { prompt: '請處理我的需求', task });
    assert.equal(status, 200);
    assert.ok(data.prompt.includes('請處理我的需求'));
  });
}

test('拒絕空白、過長、錯誤型別、不合法用途與目標模型', async t => {
  const url = await app(t);
  for (const input of [
    null, [], {}, { prompt: ' \n\t' }, { prompt: 1 }, { prompt: 'x'.repeat(12001) },
    { prompt: 'a', task: 'invalid' }, { prompt: 'a', task: '__proto__' },
    { prompt: 'a', targetModel: 'x'.repeat(81) }, { prompt: 'a', targetModel: '\nignore' },
    { prompt: 'a', targetModel: 123 },
    { prompt: 'a', promptLanguage: 'fr' }, { prompt: 'a', promptLanguage: null },
  ]) {
    const result = await post(url, input);
    assert.equal(result.status, 400, JSON.stringify(input).slice(0, 80));
    assert.equal(typeof result.data.error, 'string');
  }
  assert.equal((await post(url, { prompt: '字'.repeat(12000) })).status, 200);
});

test('英文 mock 明示原文尚未翻譯，與既有繁體中文模式分離', async t => {
  const url = await app(t);
  const prompt = '用繁體中文寫信，日期 10 月 15 日，100 字內。';
  const english = await post(url, { prompt, promptLanguage: 'en' });
  assert.equal(english.status, 200);
  assert.equal(english.data.promptLanguage, 'en');
  assert.equal(english.data.mode, 'mock');
  assert.ok(english.data.prompt.includes('NOT been translated'));
  assert.ok(english.data.prompt.includes(prompt));
  assert.ok(english.data.improvements.some(item => item.includes('沒有進行語意整理')));
  const traditional = await post(url, { prompt });
  assert.equal(traditional.data.promptLanguage, 'zh-Hant');
  assert.ok(traditional.data.prompt.includes('【原始需求，優先遵循】'));
  const config = await (await fetch(`${url}/api/config`)).json();
  assert.equal(config.service, 'prompt-studio');
  assert.equal(config.apiVersion, 2);
  assert.deepEqual(config.promptLanguages, ['zh-Hant', 'en']);
});

test('英文 live 回傳完整英文指令，假設與改善說明不混入可複製 Prompt', async t => {
  let received;
  const generated = {
    prompt: 'Write an invitation in Traditional Chinese, no more than 100 characters, for October 15. Include the literal title「開發者之夜」and NT$1,280. Do not mention discounts. Output only JSON with the key "content". Ask for [RECIPIENT] before drafting.',
    improvements: ['保留繁體中文答案語言、日期、金額及 JSON 格式。'],
    assumptions: ['The invitation will be sent by email.'],
  };
  const url = await providerApp(t, async (request, response) => {
    let body = '';
    for await (const chunk of request) body += chunk;
    received = JSON.parse(body);
    sendCompletion(response, generated);
  });
  const prompt = '請寫繁體中文邀請信，100 字內，10 月 15 日，標題「開發者之夜」、NT$1,280 不改動，不提折扣。只輸出 JSON，鍵名 content。收件人稍後提供。';
  const result = await post(url, { prompt, task: 'writing', promptLanguage: 'en', targetModel: 'Claude' });
  assert.equal(result.status, 200);
  const system = received.messages[0].content;
  assert.match(system, /^You edit prompts\./);
  assert.equal(JSON.parse(received.messages[1].content).originalPrompt, prompt);
  assert.ok(result.data.prompt.startsWith(generated.prompt));
  assert.deepEqual(result.data.assumptions, generated.assumptions);
  assert.ok(!result.data.prompt.includes(generated.assumptions[0]));
  assert.ok(!result.data.prompt.includes(prompt));
  assert.ok(!result.data.prompt.includes(generated.improvements[0]));
  assert.ok(!result.data.prompt.includes('【原始需求'));
  assert.equal(result.data.promptLanguage, 'en');
  assert.equal(result.data.mode, 'live');
});

test('混合語言 Unicode 原文完整送入英文 Prompt 模型且答案語言 literal 保留', async t => {
  let received;
  const generated = {
    prompt: 'Write a concise announcement in Spanish for the maintenance window on 2026-11-03 from 14:00 to 14:30. Preserve the exact Japanese label 「設定変更」 and Arabic phrase «لا تغيّر». Return exactly three bullet points.',
    improvements: ['明確保留指定的西班牙文答案語言與各語言固定字串。'],
    assumptions: [],
  };
  const url = await providerApp(t, async (request, response) => {
    let body = '';
    for await (const chunk of request) body += chunk;
    received = JSON.parse(body);
    sendCompletion(response, generated);
  });
  const prompt = 'Escribe un aviso breve en español para la ventana de mantenimiento del 2026-11-03 de 14:00 a 14:30. Mantén exactamente la etiqueta japonesa 「設定変更」 y la frase árabe «لا تغيّر». Devuelve exactamente tres viñetas.';
  const result = await post(url, { prompt, task: 'writing', promptLanguage: 'en' });
  assert.equal(result.status, 200);
  const sent = JSON.parse(received.messages[1].content);
  assert.equal(sent.originalPrompt, prompt);
  assert.equal(result.data.prompt, generated.prompt);
  assert.equal(result.data.promptLanguage, 'en');
  assert.equal(result.data.mode, 'live');
});

test('處理壞 JSON、錯誤內容格式、過大請求與不同來源', async t => {
  const url = await app(t);
  assert.equal((await fetch(`${url}/api/optimize`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{' })).status, 400);
  assert.equal((await fetch(`${url}/api/optimize`, { method: 'POST', body: '{}' })).status, 415);
  assert.equal((await post(url, { prompt: 'x'.repeat(100000) })).status, 413);
  assert.equal((await post(url, { prompt: 'a' }, { Origin: 'https://unrelated.example' })).status, 403);
  assert.equal((await post(url, { prompt: 'a' }, { Origin: url })).status, 200);
  assert.equal((await fetch(`${url}/api/optimize`)).status, 405);
});

test('live 設定不完整會回報錯誤，絕不退回 mock', async t => {
  const url = await app(t, { OPTIMIZER_MODE: 'live' });
  const config = await (await fetch(`${url}/api/config`)).json();
  assert.equal(config.ready, false);
  const result = await post(url, { prompt: 'a' });
  assert.equal(result.status, 503);
  assert.ok(result.data.error.includes('LLM_API_KEY'));
  assert.ok(!Object.hasOwn(result.data, 'prompt'));
});

test('live 以伺服器金鑰呼叫相容 API，保留原文並將假設與 Prompt 分開', async t => {
  let received;
  let authorization;
  let path;
  const url = await providerApp(t, async (request, response) => {
    authorization = request.headers.authorization;
    path = request.url;
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    received = JSON.parse(Buffer.concat(chunks));
    sendCompletion(response, { ...validResult, assumptions: ['未指定段落數，採用三段式安排。'] });
  });
  const prompt = '寫一封信，150 字以內。\n  不要提到折扣。';
  const result = await post(url, { prompt, task: 'writing', targetModel: 'Claude' });
  assert.equal(result.status, 200);
  assert.equal(path, '/v1/chat/completions');
  assert.equal(authorization, 'Bearer test-secret-key');
  assert.equal(received.model, 'test-model');
  assert.deepEqual(received.response_format, { type: 'json_object' });
  assert.ok(!Object.hasOwn(received, 'thinking'));
  assert.equal(received.messages[0].role, 'system');
  assert.match(received.messages[0].content, /^你是繁體中文 Prompt 編輯/);
  assert.deepEqual(JSON.parse(received.messages[1].content).originalPrompt, prompt);
  assert.equal(JSON.parse(received.messages[1].content).targetModel, 'Claude');
  assert.equal(result.data.mode, 'live');
  assert.equal(result.data.generationModel, 'test-model');
  assert.ok(result.data.prompt.includes(prompt));
  assert.deepEqual(result.data.assumptions, ['未指定段落數，採用三段式安排。']);
  assert.ok(!result.data.prompt.includes(result.data.assumptions[0]));
  assert.ok(result.data.prompt.includes('【補充執行指引】'));
  assert.ok(!JSON.stringify(result.data).includes('test-secret-key'));
});

test('可關閉 JSON mode 並接受完整 JSON 程式碼區塊', async t => {
  let received;
  const url = await providerApp(t, async (request, response) => {
    let body = '';
    for await (const chunk of request) body += chunk;
    received = JSON.parse(body);
    sendCompletion(response, `\x60\x60\x60json\n${JSON.stringify(validResult)}\n\x60\x60\x60`);
  }, { LLM_JSON_MODE: 'false' });
  assert.equal((await post(url, { prompt: 'a' })).status, 200);
  assert.ok(!Object.hasOwn(received, 'response_format'));
});

test('DeepSeek Flash 設定使用正式模型名稱與 JSON 非思考模式', async t => {
  let received;
  const url = await providerApp(t, async (request, response) => {
    let body = '';
    for await (const chunk of request) body += chunk;
    received = JSON.parse(body);
    sendCompletion(response, validResult);
  }, { LLM_MODEL: 'deepseek-flash', LLM_THINKING_MODE: 'disabled' });
  const result = await post(url, { prompt: '請寫一封邀請信', task: 'writing' });
  assert.equal(result.status, 200);
  assert.equal(received.model, 'deepseek-flash');
  assert.deepEqual(received.thinking, { type: 'disabled' });
  assert.deepEqual(received.response_format, { type: 'json_object' });
  assert.equal(result.data.generationModel, 'deepseek-flash');
  const config = readConfig({ LLM_BASE_URL: 'https://api.deepseek.com', LLM_MODEL: 'deepseek-flash' });
  assert.equal(`${config.baseUrl}/chat/completions`, 'https://api.deepseek.com/chat/completions');
});

for (const providerStatus of [400, 401, 403, 404, 422, 429, 500]) {
  test(`模型 HTTP ${providerStatus} 提供安全錯誤，不回傳服務商內文`, async t => {
    const url = await providerApp(t, (request, response) => {
      response.writeHead(providerStatus);
      response.end('secret-content test-secret-key');
    });
    const result = await post(url, { prompt: 'a' });
    assert.equal(result.status, providerStatus === 429 ? 429 : 502);
    assert.ok(!JSON.stringify(result.data).includes('secret'));
    assert.ok(!Object.hasOwn(result.data, 'prompt'));
  });
}

test('模型逾時回傳 504，並可再次送出', async t => {
  const url = await providerApp(t, () => {}, { LLM_TIMEOUT_MS: '40' });
  assert.equal((await post(url, { prompt: 'a' })).status, 504);
  assert.equal((await post(url, { prompt: 'a' })).status, 504);
});

for (const brokenResult of [
  'not json', {}, { ...validResult, prompt: '' }, { ...validResult, improvements: [] },
]) {
  test(`模型結果驗證：拒絕 ${JSON.stringify(brokenResult).slice(0, 65)}`, async t => {
    const url = await providerApp(t, (request, response) => sendCompletion(response, brokenResult));
    assert.equal((await post(url, { prompt: 'a' })).status, 502);
  });
}

test('模型結果驗證：過長或過多的列表項不會被靜默丟棄或截短', async t => {
  const longItem = 'x'.repeat(501);
  let calls = 0;
  const url = await providerApp(t, (request, response) => {
    calls++;
    sendCompletion(response, {
    ...validResult, improvements: ['a', 'b', 'c', 'd', 'e', 'f', 'g'], assumptions: [123, '', longItem],
    });
  });
  const result = await post(url, { prompt: 'a' });
  assert.equal(result.status, 502);
  assert.equal(calls, 2);
  assert.equal(Object.hasOwn(result.data, 'prompt'), false);
});

test('模型遇到缺少 JSON 結尾時只補齊 EOF 括號，完整欄位通過驗證', async t => {
  const truncatedObject = JSON.stringify(validResult).slice(0, -1);
  const url = await providerApp(t, (request, response) => sendCompletion(response, truncatedObject));
  const result = await post(url, { prompt: 'a', promptLanguage: 'en' });
  assert.equal(result.status, 200);
  assert.equal(result.data.prompt, validResult.prompt);
});

test('模型回應括號衝突時不丟棄字元拼湊 Prompt，且只重試一次', async t => {
  let calls = 0;
  const url = await providerApp(t, (request, response) => {
    calls++;
    sendCompletion(response, '{"prompt":"partial","improvements":["note"}}]');
  });
  const result = await post(url, { prompt: 'a' });
  assert.equal(result.status, 502);
  assert.equal(calls, 2);
  assert.equal(Object.hasOwn(result.data, 'prompt'), false);
});

test('finish_reason=length 即使 JSON 可解析也拒絕並且不重試', async t => {
  let calls = 0;
  const url = await providerApp(t, (request, response) => {
    calls++;
    sendCompletion(response, validResult, 'length');
  });
  const result = await post(url, { prompt: 'a' });
  assert.equal(result.status, 502);
  assert.match(result.data.error, /截斷/);
  assert.equal(calls, 1);
  assert.equal(Object.hasOwn(result.data, 'prompt'), false);
});

test('處理非 JSON 服務回應、截斷與過大的模型回應', async t => {
  const urls = await Promise.all([
    providerApp(t, (request, response) => response.end('not json')),
    providerApp(t, (request, response) => sendCompletion(response, validResult, 'length')),
    providerApp(t, (request, response) => response.end('x'.repeat(270000))),
  ]);
  for (const url of urls) assert.equal((await post(url, { prompt: 'a' })).status, 502);
});

test('同時最多四個優化請求，避免個人服務被大量請求佔用', async t => {
  let started = 0;
  let allStarted;
  const ready = new Promise(resolve => { allStarted = resolve; });
  const pending = [];
  const url = await providerApp(t, (request, response) => {
    pending.push(response);
    if (++started === 4) allStarted();
  });
  const requests = Array.from({ length: 4 }, () => post(url, { prompt: 'a' }));
  await ready;
  assert.equal((await post(url, { prompt: 'a' })).status, 429);
  pending.forEach(response => sendCompletion(response, validResult));
  assert.ok((await Promise.all(requests)).every(result => result.status === 200));
});

test('使用者取消會中斷伺服器對模型的請求', { timeout: 3000 }, async t => {
  let markStarted;
  let markClosed;
  const started = new Promise(resolve => { markStarted = resolve; });
  const closed = new Promise(resolve => { markClosed = resolve; });
  const url = await providerApp(t, (request, response) => {
    response.on('close', markClosed);
    markStarted();
  });
  const cancellation = new AbortController();
  const request = fetch(`${url}/api/optimize`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ prompt: '測試取消' }), signal: cancellation.signal,
  });
  const rejected = assert.rejects(request, { name: 'AbortError' });
  await started;
  cancellation.abort();
  await rejected;
  await closed;
});
