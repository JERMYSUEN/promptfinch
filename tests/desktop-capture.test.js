import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { EventEmitter } from 'node:events';
const { captureSelection, startSelectionWatch, verifySelectionSource } = createRequire(import.meta.url)('../desktop/capture.cjs');
const helperPath = '/synthetic/SelectionReader.exe';
const turn = () => new Promise(resolve => setImmediate(resolve));
function fakeProcess() {
  const child = new EventEmitter(); child.stdout = new EventEmitter(); child.stdout.setEncoding = () => {};
  child.kill = () => { child.killed = true; return true; }; return child;
}

test('Windows capture reads only a bounded native helper response without shell/copy actions', async () => {
  let invocation;
  const captured = await captureSelection({ platform: 'win32', helperPath, clipboard: { readText() { throw new Error('Ordinary clipboard must not be read'); } },
    execFileFn(path, args, options, callback) { invocation = { path, args, options }; callback(null, JSON.stringify({ ok: true, text: '  Keep Cafe\u0301 and ACME-42.\n' })); } });
  assert.equal(captured.text, '  Keep Cafe\u0301 and ACME-42.\n'); assert.deepEqual(invocation.args, ['--read']);
  assert.equal(invocation.options.timeout, 2000); assert.equal(invocation.options.shell, undefined); assert.ok(invocation.options.maxBuffer <= 131072);
});

test('Windows helper timeouts, malformed/oversized/empty results fail without stale clipboard fallback', async () => {
  for (const [output, code] of [['not json', 'HELPER_ERROR'], ['{"ok":false,"code":"PASSWORD"}', 'PASSWORD'],
    [JSON.stringify({ ok: true, text: 'x'.repeat(12001) }), 'TOO_LONG'], [JSON.stringify({ ok: true, text: '  ' }), 'NO_SELECTION'],
    ['{"ok":false,"code":"synthetic-secret-provider-response"}', 'HELPER_ERROR']]) {
    const captured = await captureSelection({ platform: 'win32', helperPath, execFileFn(_p, _a, _o, callback) { callback(null, output); } });
    assert.deepEqual(captured, { ok: false, code });
  }
  assert.deepEqual(await captureSelection({ platform: 'win32', helperPath, execFileFn(_p, _a, _o, callback) { callback({ killed: true }); } }), { ok: false, code: 'TIMEOUT' });
});

test('Linux explicitly supports only X11 selection clipboard, never the ordinary clipboard', async () => {
  let ordinary = 0, selected = 0;
  const clipboard = { readText() { ordinary++; return 'Old text'; }, selection: { async readText() { selected++; return 'Selected synthetic text'; } } };
  assert.equal((await captureSelection({ platform: 'linux', env: { XDG_SESSION_TYPE: 'x11' }, clipboard })).text, 'Selected synthetic text');
  assert.deepEqual(await captureSelection({ platform: 'linux', env: { XDG_SESSION_TYPE: 'wayland', DISPLAY: ':1', WAYLAND_DISPLAY: 'wayland-0' }, clipboard }), { ok: false, code: 'UNSUPPORTED' });
  assert.deepEqual(await captureSelection({ platform: 'darwin', clipboard }), { ok: false, code: 'UNSUPPORTED' });
  assert.equal(selected, 1); assert.equal(ordinary, 0);
});

test('Windows watch validates bounded JSONL events and stops its own helper', async () => {
  const child = fakeProcess(), selections = [], errors = []; let args;
  const watcher = startSelectionWatch({ platform: 'win32', helperPath, excludePid: 42, onSelection: e => selections.push(e), onError: e => errors.push(e),
    spawnFn(_path, arguments_) { args = arguments_; return child; } });
  assert.deepEqual(args, ['--watch', '--exclude-pid', '42']);
  const event = { ok: true, text: 'Synthetic chosen text', x: -120, y: 300, capturedAt: Date.now(), sourceId: '99:1001' };
  const json = JSON.stringify(event); child.stdout.emit('data', json.slice(0, 15)); assert.equal(selections.length, 0);
  child.stdout.emit('data', `${json.slice(15)}\n`); assert.deepEqual(selections[0], event);
  child.stdout.emit('data', `${JSON.stringify({ ...event, capturedAt: Date.now() - 2000 })}\n`);
  child.stdout.emit('data', `${JSON.stringify({ ...event, sourceId: 'unsafe identifier' })}\n`);
  child.stdout.emit('data', `${JSON.stringify({ ...event, text: 'x'.repeat(12001) })}\n`);
  assert.equal(selections.length, 1); assert.deepEqual(errors, []);
  watcher.stop(); watcher.stop(); assert.equal(child.killed, true);
  child.stdout.emit('data', `${json}\n`); assert.equal(selections.length, 1);
});

test('malformed or oversized watcher output is stopped without exposing its content', () => {
  for (const line of ['synthetic-secret-invalid-json\n', 'x'.repeat(131073)]) {
    const child = fakeProcess(), errors = [];
    startSelectionWatch({ platform: 'win32', helperPath, spawnFn() { return child; }, onError: e => errors.push(e) });
    child.stdout.emit('data', line); assert.equal(child.killed, true); assert.deepEqual(errors, [{ ok: false, code: 'HELPER_ERROR' }]);
    assert.doesNotMatch(JSON.stringify(errors), /synthetic-secret/);
  }
});

test('Linux right-click watcher reads selection on demand and discards superseded captures', async () => {
  const child = fakeProcess(), selections = []; const finishes = [];
  const watcher = startSelectionWatch({ platform: 'linux', helperPath: '/synthetic/x11-watch', env: { XDG_SESSION_TYPE: 'x11' },
    clipboard: { selection: { readText() { return new Promise(resolve => finishes.push(resolve)); } } },
    spawnFn(_path, arguments_) { assert.deepEqual(arguments_, []); return child; }, onSelection: e => selections.push(e) });
  const event = { event: 'right-click', x: 1, y: 2, capturedAt: Date.now() };
  child.stdout.emit('data', `${JSON.stringify(event)}\n${JSON.stringify({ ...event, x: 3 })}\n`);
  finishes[0]('Old selection'); finishes[1]('New selection'); await turn();
  assert.equal(selections.length, 1); assert.equal(selections[0].text, 'New selection'); assert.equal(selections[0].x, 3);
  watcher.stop();
});

test('Wayland watcher reports unsupported without spawning or reading selection', async () => {
  const errors = [];
  startSelectionWatch({ platform: 'linux', helperPath: '/synthetic/x11-watch', env: { XDG_SESSION_TYPE: 'wayland' },
    spawnFn() { throw new Error('Must not spawn'); }, onError: e => errors.push(e) });
  await turn(); assert.deepEqual(errors, [{ ok: false, code: 'UNSUPPORTED' }]);
});

test('Windows source verification uses a validated source identity and bounded native check', async () => {
  let invocation;
  const verified = await verifySelectionSource({ platform: 'win32', helperPath, sourceId: '42:901',
    execFileFn(path, args, options, callback) { invocation = { path, args, options }; callback(null, '{"ok":true}'); } });
  assert.deepEqual(verified, { ok: true }); assert.deepEqual(invocation.args, ['--verify-source', '42:901']);
  assert.equal(invocation.options.timeout, 2000); assert.equal(invocation.options.maxBuffer, 1024);
  const changed = await verifySelectionSource({ platform: 'win32', helperPath, sourceId: '42:901',
    execFileFn(_p, _a, _o, callback) { callback(null, '{"ok":false,"code":"FOCUS_CHANGED"}'); } });
  assert.deepEqual(changed, { ok: false, code: 'FOCUS_CHANGED' });
  for (const sourceId of ['0:1', '1:0', 'x:1', '--other', '1:2\nsecret']) {
    assert.deepEqual(await verifySelectionSource({ platform: 'win32', helperPath, sourceId,
      execFileFn() { assert.fail('Invalid identity must not start the helper'); } }), { ok: false, code: 'FOCUS_CHANGED' });
  }
});
