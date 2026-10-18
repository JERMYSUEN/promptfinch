import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { join } from 'node:path';
const { trustedURL, assetPath, trustedSender, validCapture } = createRequire(import.meta.url)('../desktop/security.cjs');

test('desktop only trusts its two owned documents, never remote or nested frames', () => {
  assert.equal(trustedURL('promptfinch://app/'), true);
  assert.equal(trustedURL('promptfinch://app/?window=companion'), true);
  for (const url of ['https://app/', 'file:///app/index.html', 'promptfinch://evil/', 'promptfinch://app/foo', 'promptfinch://user@app/', 'promptfinch://app/?window=other', 'promptfinch://app/#x']) assert.equal(trustedURL(url), false, url);
  const mainFrame = { url: 'promptfinch://app/' };
  const sender = { mainFrame };
  const win = { isDestroyed: () => false, webContents: sender };
  assert.equal(trustedSender({ sender, senderFrame: mainFrame }, [win]), true);
  assert.equal(trustedSender({ sender, senderFrame: { url: mainFrame.url } }, [win]), false);
  assert.equal(trustedSender({ sender, senderFrame: mainFrame }, []), false);
});

test('desktop static routing cannot expose environment files or arbitrary paths', () => {
  assert.equal(assetPath('promptfinch://app/base.css', '/safe'), join('/safe', 'public/style.css'));
  for (const url of ['promptfinch://app/.env', 'promptfinch://app/desktop/main.cjs', 'promptfinch://app/../../package.json', 'promptfinch://app/%2e%2e/.env', 'https://app/', 'promptfinch://user@app/']) assert.equal(assetPath(url, '/safe'), null, url);
});

test('right click offers only bounded, fresh, nonempty captures', () => {
  const value = { ok: true, text: 'synthetic request', x: 12, y: -42, capturedAt: 10000 };
  assert.equal(validCapture(value, 11000), true);
  for (const change of [{ text: ' ' }, { text: 'x'.repeat(12001) }, { capturedAt: 0 }, { capturedAt: 20000 }, { x: NaN }, { ok: false }]) assert.equal(validCapture({ ...value, ...change }, 11000), false);
});
