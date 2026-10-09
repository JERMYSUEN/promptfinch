import { test, expect } from '@playwright/test';
import { mkdir } from 'node:fs/promises';

test.beforeEach(async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('button', { name: '優化 Prompt', exact: true })).toBeEnabled();
});

test('桌面操作：驗證、範例、生成、真正複製、更新提醒與清除', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await expect(page.locator('#mode-badge')).toHaveText('示範模式');
  await page.getByRole('button', { name: '優化 Prompt', exact: true }).click();
  await expect(page.getByRole('alert')).toContainText('請先輸入');
  await page.getByRole('button', { name: '邀請信', exact: true }).click();
  const original = await page.locator('#original-prompt').inputValue();
  await page.getByLabel('目標模型').fill('Claude');
  await page.getByLabel('Prompt 指令語言').selectOption('zh-Hant');
  await page.getByRole('button', { name: '優化 Prompt', exact: true }).click();
  await expect(page.locator('#optimized-prompt')).toHaveValue(new RegExp('原始需求'));
  const output = await page.locator('#optimized-prompt').inputValue();
  expect(output).toContain(original);
  await expect(page.locator('#result-tag')).toHaveText('示範結果');
  await expect(page.locator('#explanation')).toBeVisible();
  await page.getByRole('button', { name: '複製 Prompt', exact: true }).click();
  await expect(page.locator('#action-status')).toContainText('已複製 Prompt');
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(output);
  await mkdir('artifacts', { recursive: true });
  await page.screenshot({ path: 'artifacts/desktop-result.png', fullPage: true });
  await page.locator('#original-prompt').fill('新的需求');
  await expect(page.locator('#result-tag')).toHaveText('上次結果');
  await page.getByRole('button', { name: '清除', exact: true }).click();
  await expect(page.locator('#original-prompt')).toHaveValue('');
  await expect(page.locator('#optimized-prompt')).toHaveValue('');
  await expect(page.locator('#explanation')).toBeHidden();
  await expect(page.getByRole('button', { name: '複製 Prompt', exact: true })).toBeDisabled();
  expect(errors).toEqual([]);
});

test('英文入口保留韓俄與組合字元；輸出語言切換、RTL及mock提示明確', async ({ page }) => {
  const source = '한국어 Привет Cafe\u0301 👩🏽‍💻 ${user_name} https://example.com/a?x=1&y=2';
  await expect(page.getByLabel('Prompt 指令語言')).toHaveValue('en');
  await page.locator('#original-prompt').fill(source);
  const request = page.waitForRequest(r => r.url().endsWith('/api/optimize'));
  await page.getByRole('button', { name: '優化 Prompt', exact: true }).click();
  expect((await request).postDataJSON()).toMatchObject({ prompt: source, promptLanguage: 'en' });
  await expect(page.locator('#optimized-prompt')).toHaveValue(new RegExp('NOT been translated'));
  expect(await page.locator('#optimized-prompt').inputValue()).toContain(source);
  await page.getByLabel('Prompt 指令語言').selectOption('zh-Hant');
  await expect(page.locator('#result-tag')).toHaveText('上次結果');
  await page.getByRole('button', { name: '優化 Prompt', exact: true }).click();
  await expect(page.locator('#optimized-prompt')).toHaveValue(/原始需求/);
  await page.locator('#original-prompt').fill('اكتب رسالة عربية قصيرة');
  expect(await page.locator('#original-prompt').evaluate(el => getComputedStyle(el).direction)).toBe('rtl');
  await page.locator('#original-prompt').fill('😀한국어');
  await expect(page.locator('#character-count')).toHaveText('5 / 12,000 UTF-16 單位');
});

test('超長emoji輸入完整保留並在送出前拒絕，不由maxlength靜默截斷', async ({ page }) => {
  const sent = [];
  page.on('request', request => { if (request.url().endsWith('/api/optimize')) sent.push(request); });
  const source = '😀'.repeat(6000) + 'x';
  await page.locator('#original-prompt').focus();
  await page.keyboard.insertText(source);
  await expect(page.locator('#original-prompt')).toHaveValue(source);
  await expect(page.locator('#character-count')).toHaveText('12,001 / 12,000 UTF-16 單位');
  await page.getByRole('button', { name: '優化 Prompt', exact: true }).click();
  await expect(page.getByRole('alert')).toContainText('超過 12,000');
  await expect(page.locator('#original-prompt')).toHaveValue(source);
  expect(sent).toHaveLength(0);
});

test('複製遭瀏覽器拒絕時，選取文字並提供手動操作提示', async ({ page }) => {
  await page.getByRole('button', { name: '資料分析', exact: true }).click();
  await page.getByRole('button', { name: '優化 Prompt', exact: true }).click();
  await expect(page.locator('#result-state')).toBeVisible();
  await page.evaluate(() => { Object.defineProperty(navigator, 'clipboard', { value: { writeText: async () => { throw new Error('denied'); } }, configurable: true }); });
  await page.getByRole('button', { name: '複製 Prompt', exact: true }).click();
  await expect(page.locator('#action-status')).toContainText('無法自動複製，已選取 Prompt');
  expect(await page.locator('#optimized-prompt').evaluate(element => element.selectionEnd - element.selectionStart)).toBeGreaterThan(0);
});

test('載入狀態、取消與過期回應不會重新填入已清除的結果', async ({ page }) => {
  let release;
  const waiting = new Promise(resolve => { release = resolve; });
  await page.route('**/api/optimize', async route => {
    await waiting;
    await route.fulfill({ json: { prompt: '過期結果', improvements: ['測試'], assumptions: [], mode: 'mock' } });
  });
  await page.locator('#original-prompt').fill('請幫我整理需求');
  await page.getByRole('button', { name: '優化 Prompt', exact: true }).click();
  await expect(page.locator('#loading-state')).toBeVisible();
  await expect(page.getByRole('button', { name: '正在優化…' })).toBeDisabled();
  await page.getByRole('button', { name: '取消並清除' }).click();
  release();
  await expect(page.locator('#empty-state')).toBeVisible();
  await expect(page.locator('#optimized-prompt')).toHaveValue('');
  await expect(page.locator('#action-status')).toContainText('已清除');
});

test('伺服器錯誤保留輸入及上次結果，下一次可重試', async ({ page }) => {
  await page.locator('#original-prompt').fill('第一次需求');
  await page.getByRole('button', { name: '優化 Prompt', exact: true }).click();
  await expect(page.locator('#result-state')).toBeVisible();
  const oldResult = await page.locator('#optimized-prompt').inputValue();
  await page.locator('#original-prompt').fill('第二次需求');
  await page.route('**/api/optimize', route => route.fulfill({ status: 504, json: { error: '模型回應逾時，請稍後再試。' } }));
  await page.getByRole('button', { name: '優化 Prompt', exact: true }).click();
  await expect(page.getByRole('alert')).toContainText('模型回應逾時');
  await expect(page.locator('#original-prompt')).toHaveValue('第二次需求');
  await expect(page.locator('#optimized-prompt')).toHaveValue(oldResult);
  await expect(page.locator('#result-tag')).toHaveText('上次結果');
  await page.unroute('**/api/optimize');
  await page.getByRole('button', { name: '優化 Prompt', exact: true }).click();
  await expect(page.locator('#optimized-prompt')).toHaveValue(/第二次需求/);
});

test('手機 390px 與小螢幕 320px 可操作且沒有橫向溢出', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.reload();
  await page.getByRole('button', { name: '程式開發', exact: true }).click();
  await page.getByRole('button', { name: '優化 Prompt', exact: true }).click();
  await expect(page.locator('#result-state')).toBeVisible();
  await mkdir('artifacts', { recursive: true });
  await page.screenshot({ path: 'artifacts/mobile-result.png', fullPage: true });
  for (const width of [390, 320]) {
    await page.setViewportSize({ width, height: 844 });
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
    await expect(page.getByRole('button', { name: '複製 Prompt', exact: true })).toBeVisible();
  }
});

test('重新整理不保留內容；頁面不使用本機儲存或第三方請求', async ({ page }) => {
  const externalRequests = [];
  page.on('request', request => { if (!request.url().startsWith('http://127.0.0.1:3187/')) externalRequests.push(request.url()); });
  await page.locator('#original-prompt').fill('我的私人資料');
  await page.getByRole('button', { name: '優化 Prompt', exact: true }).click();
  await expect(page.locator('#result-state')).toBeVisible();
  expect(await page.evaluate(() => [localStorage.length, sessionStorage.length])).toEqual([0, 0]);
  await page.reload();
  await expect(page.locator('#original-prompt')).toHaveValue('');
  await expect(page.locator('#optimized-prompt')).toHaveValue('');
  expect(externalRequests).toEqual([]);
});

test('生成內容與使用者文字都當作純文字呈現', async ({ page }) => {
  const malicious = '<img src=x onerror="window.executed=true">';
  await page.route('**/api/optimize', route => route.fulfill({ json: { prompt: malicious, improvements: [malicious], assumptions: [malicious], mode: 'live', generationModel: 'test' } }));
  await page.locator('#original-prompt').fill(malicious);
  await page.getByRole('button', { name: '優化 Prompt', exact: true }).click();
  await expect(page.locator('#optimized-prompt')).toHaveValue(malicious);
  await expect(page.locator('#improvements')).toContainText(malicious);
  expect(await page.locator('#explanation img').count()).toBe(0);
  expect(await page.evaluate(() => window.executed)).toBeUndefined();
});

test('服務設定失敗會停用優化並提供明確指引', async ({ page }) => {
  await page.route('**/api/config', route => route.abort());
  await page.reload();
  await expect(page.locator('#mode-notice')).toContainText('請確認伺服器已啟動');
  await expect(page.getByRole('button', { name: '優化 Prompt', exact: true })).toBeDisabled();
});
