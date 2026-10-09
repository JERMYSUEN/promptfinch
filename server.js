import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { AppError, MAX_PROMPT_LENGTH, TASKS, readConfig, validateInput, optimize } from './lib/optimizer.js';

const PUBLIC_DIR = new URL('./public/', import.meta.url);
const STATIC_FILES = new Map([
  ['/', ['index.html', 'text/html; charset=utf-8']],
  ['/app.js', ['app.js', 'text/javascript; charset=utf-8']],
  ['/style.css', ['style.css', 'text/css; charset=utf-8']],
  ['/favicon.svg', ['favicon.svg', 'image/svg+xml']],
]);
const BODY_LIMIT = 98304;

function sendJson(response, status, data) {
  response.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  response.end(JSON.stringify(data));
}

async function readJson(request) {
  if (!/^application\/json(?:\s*;|$)/i.test(request.headers['content-type'] || '')) {
    throw new AppError(415, '請使用 JSON 格式傳送資料。');
  }
  // Drain oversized input without buffering it, allowing a useful HTTP response.
  return new Promise((resolve, reject) => {
    const chunks = [];
    let bytes = 0;
    let exceeded = false;
    request.on('data', chunk => {
      bytes += chunk.length;
      if (bytes > BODY_LIMIT) {
        if (!exceeded) reject(new AppError(413, '輸入資料過大，請縮短 Prompt 後再試。'));
        exceeded = true;
        chunks.length = 0;
      } else if (!exceeded) chunks.push(chunk);
    });
    request.on('end', () => {
      if (exceeded) return;
      try { resolve(JSON.parse(Buffer.concat(chunks).toString('utf8'))); }
      catch { reject(new AppError(400, '輸入格式無法讀取，請重新整理頁面後再試。')); }
    });
    request.on('error', () => reject(new AppError(400, '輸入傳送中斷，請重新嘗試。')));
  });
}

export function createApp(config = readConfig()) {
  let activeRequests = 0;
  const server = createServer(async (request, response) => {
    response.setHeader('Cache-Control', 'no-store');
    response.setHeader('X-Content-Type-Options', 'nosniff');
    response.setHeader('Referrer-Policy', 'no-referrer');
    response.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'");
    try {
      const pathname = new URL(request.url, 'http://localhost').pathname;
      if (pathname === '/api/config' && request.method === 'GET') {
        sendJson(response, 200, {
          service: 'prompt-studio', apiVersion: 2,
          backendID: config.backendID || null,
          backendInstanceID: config.backendInstanceID || null,
          mode: config.mode, ready: config.mode === 'mock' || Boolean(config.apiKey && config.model),
          generationModel: config.mode === 'live' ? config.model || null : null,
          maxPromptLength: MAX_PROMPT_LENGTH, tasks: TASKS, promptLanguages: ['zh-Hant', 'en'],
        });
        return;
      }
      if (pathname === '/api/optimize' && request.method === 'POST') {
        const origin = request.headers.origin;
        // Only same-origin browser submissions; no CORS for unrelated sites.
        if (origin && new URL(origin).host !== request.headers.host) throw new AppError(403, '請從本服務的頁面進行優化。');
        if (request.headers['sec-fetch-site'] === 'cross-site') throw new AppError(403, '請從本服務的頁面進行優化。');
        if (activeRequests >= 4) throw new AppError(429, '目前正在處理其他優化，請稍後再試。');
        activeRequests++;
        const cancellation = new AbortController();
        const cancel = () => cancellation.abort();
        response.on('close', cancel);
        try {
          const input = validateInput(await readJson(request));
          const result = await optimize(input, config, cancellation.signal);
          if (!response.destroyed) sendJson(response, 200, result);
        } finally {
          response.off('close', cancel);
          activeRequests--;
        }
        return;
      }
      if (STATIC_FILES.has(pathname) && ['GET', 'HEAD'].includes(request.method)) {
        const [filename, type] = STATIC_FILES.get(pathname);
        const content = await readFile(new URL(filename, PUBLIC_DIR));
        response.writeHead(200, { 'Content-Type': type });
        response.end(request.method === 'HEAD' ? undefined : content);
        return;
      }
      if (pathname.startsWith('/api/')) throw new AppError(405, '這個 API 路徑或請求方式不受支援。');
      throw new AppError(404, '找不到頁面，請返回首頁。');
    } catch (error) {
      if (!response.headersSent && !response.destroyed) {
        sendJson(response, error instanceof AppError ? error.status : 500, {
          error: error instanceof AppError ? error.message : '服務暫時無法完成請求，請稍後再試。',
        });
      }
      // Intentionally do not log errors containing prompts, provider responses or secrets.
    }
  });
  server.requestTimeout = 15000;
  server.headersTimeout = 10000;
  return server;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  try {
    const config = readConfig();
    const server = createApp(config);
    server.on('error', error => {
      console.error(error.code === 'EADDRINUSE' ? '連接埠已被使用，請在 .env 修改 PORT 後再啟動。' : '服務無法啟動，請檢查 HOST 與 PORT 設定。');
      process.exitCode = 1;
    });
    server.listen(config.port, config.host, () => {
      console.log(`Prompt 工作台：http://${config.host}:${server.address().port}（${config.mode === 'mock' ? '示範模式' : '模型模式'}）`);
    });
    for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => {
      server.closeAllConnections();
      server.close();
    });
  } catch (error) {
    console.error(`設定錯誤：${error.message}`);
    process.exitCode = 1;
  }
}
