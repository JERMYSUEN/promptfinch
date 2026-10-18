'use strict';
const { app, BrowserWindow, protocol, net, ipcMain, dialog, clipboard: systemClipboard, globalShortcut, Menu, Tray, nativeImage, screen, shell } = require('electron');
const { pathToFileURL } = require('node:url');
const path = require('node:path');
const { existsSync } = require('node:fs');
const { ORIGIN, assetPath, trustedSender, validCapture } = require('./security.cjs');
const { captureSelection, startSelectionWatch, verifySelectionSource } = require('./capture.cjs');

protocol.registerSchemesAsPrivileged([{ scheme: 'promptfinch', privileges: { standard: true, secure: true, supportFetchAPI: true } }]);
app.setName('PromptFinch');
if (process.platform === 'linux') app.setDesktopName('org.promptfinch.desktop.desktop');
const smoke = process.argv.includes('--smoke-test');
// Isolated smoke runs never change the user's system clipboard.
let testClipboard = '';
const clipboard = smoke ? { readText: async () => testClipboard, writeText: async text => { testClipboard = text; } } : systemClipboard;
const profileIndex = process.argv.indexOf('--test-profile');
if (smoke && profileIndex >= 0 && process.argv[profileIndex + 1]) app.setPath('userData', path.resolve(process.argv[profileIndex + 1]));
const ownsLock = smoke || app.requestSingleInstanceLock();
if (!ownsLock) { app.quit(); }

let mainWindow, companion, tray, controller, watcher, candidate, result, DesktopErrorType;
let watchStatus = 'disabled', shortcutStatus = 'disabled', quitting = false, candidateTimer;
const root = path.resolve(__dirname, '..');
const linuxX11 = process.platform === 'linux' && !process.env.WAYLAND_DISPLAY && process.env.XDG_SESSION_TYPE !== 'wayland';
const selectionSupport = process.platform === 'win32' ? 'windows-uia' : linuxX11 ? 'x11' : 'clipboard-only';
const helperName = process.platform === 'win32' ? 'SelectionReader.exe' : 'right-click-watcher';
const helperPath = app.isPackaged ? path.join(process.resourcesPath, 'helpers', helperName)
  : path.join(__dirname, 'bin', process.platform, helperName);

const safeError = error => ({ code: typeof error?.code === 'string' && /^[A-Z_]{2,40}$/.test(error.code) ? error.code : 'OPERATION_FAILED',
  message: DesktopErrorType && error instanceof DesktopErrorType ? error.message : 'The operation could not be completed. Check the app settings and try again.' });
const fail = code => { const error = new Error(code); error.code = code; throw error; };
function emit(window, name, value) {
  if (window && !window.isDestroyed() && !window.webContents.isDestroyed()) window.webContents.send(`promptfinch:${name}`, value);
}
function state() { return { ...controller.snapshot(), platform: process.platform, selectionSupport, watchStatus, shortcutStatus }; }
function companionState() { return { ...state(), selectionPreview: candidate?.text.slice(0, 70).replace(/\s+/g, ' ') || '' }; }
function sendState() { const value = state(); emit(mainWindow, 'state', value); emit(companion, 'state', companionState()); updateTray(); return value; }
function showWorkspace() { mainWindow.show(); mainWindow.focus(); }
function dropCandidate() { clearTimeout(candidateTimer); candidate = null; if (companion && !companion.isDestroyed()) companion.hide(); }
function appIcon() {
  const pixels = Buffer.alloc(32 * 32 * 4);
  for (let y = 0; y < 32; y++) for (let x = 0; x < 32; x++) {
    const white = (x >= 9 && x < 14 && y >= 7 && y < 26)
      || (x >= 14 && x < 23 && ((y >= 7 && y < 12) || (y >= 16 && y < 20)))
      || (x >= 19 && x < 24 && y >= 11 && y < 17);
    const index = (y * 32 + x) * 4;
    pixels[index] = white ? 255 : 103; pixels[index + 1] = white ? 255 : 134;
    pixels[index + 2] = white ? 255 : 41; pixels[index + 3] = 255;
  }
  return nativeImage.createFromBitmap(pixels, { width: 32, height: 32, scaleFactor: 1 });
}
function buildWindow(extra = {}) {
  const window = new BrowserWindow({ width: 1180, height: 860, minWidth: 600, minHeight: 520,
    show: false, backgroundColor: '#151917', title: 'PromptFinch', autoHideMenuBar: true, icon: appIcon(),
    ...extra, webPreferences: { preload: path.join(__dirname, 'preload.cjs'), nodeIntegration: false,
      contextIsolation: true, sandbox: true, webSecurity: true, devTools: smoke,
      partition: 'promptfinch-session', spellcheck: false } });
  window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  window.webContents.on('will-navigate', event => event.preventDefault());
  window.webContents.on('will-attach-webview', event => event.preventDefault());
  window.webContents.on('did-finish-load', () => { if (controller) emit(window, 'state', window === companion ? companionState() : state()); });
  return window;
}
async function generate(input) {
  dropCandidate(); result = null;
  const pending = controller.generate(input);
  sendState();
  try {
    const value = await pending;
    result = { ...value, sourcePrompt: input.prompt, sourceTask: input.task || 'general', sourceTargetModel: input.targetModel || '' };
    showWorkspace(); emit(mainWindow, 'result', result);
    return result;
  } finally { sendState(); }
}
async function capture(source) {
  dropCandidate();
  let text;
  if (source === 'clipboard') text = await clipboard.readText();
  else {
    const captured = await captureSelection({ platform: process.platform, clipboard, helperPath });
    if (!captured.ok) fail(captured.code || 'SELECTION_UNAVAILABLE');
    text = captured.text;
  }
  if (typeof text !== 'string' || !text.trim()) fail('EMPTY_SELECTION');
  if (text.length > 12000) fail('INPUT_TOO_LONG');
  showWorkspace(); emit(mainWindow, 'capture', { text, source });
  return { imported: true };
}
function offerSelection(value) {
  if (!validCapture(value) || controller.snapshot().busy || mainWindow.isFocused() || companion.isFocused()) return;
  dropCandidate(); candidate = value;
  let point = { x: value.x, y: value.y };
  if (process.platform === 'win32') point = screen.screenToDipPoint(point);
  const area = screen.getDisplayNearestPoint(point).workArea;
  companion.setPosition(Math.max(area.x, Math.min(point.x + 18, area.x + area.width - 310)),
    Math.max(area.y, Math.min(point.y + 16, area.y + area.height - 140)));
  emit(companion, 'state', companionState());
  companion.showInactive();
  candidateTimer = setTimeout(dropCandidate, 10000);
}
function startWatcher() {
  if (smoke) return;
  if (selectionSupport === 'clipboard-only') { watchStatus = 'unsupported'; return; }
  if (!existsSync(helperPath)) { watchStatus = 'unavailable'; return; }
  watchStatus = 'running';
  watcher = startSelectionWatch({ platform: process.platform, clipboard, helperPath, excludePid: process.pid,
    onSelection: offerSelection, onError: () => { watchStatus = 'unavailable'; dropCandidate(); sendState(); } });
}
function updateTray() {
  if (!tray) return;
  const copy = {
    'zh-TW': ['開啟工作台', '匯入剪貼簿', '結束 PromptFinch'],
    en: ['Open workspace', 'Import clipboard', 'Quit PromptFinch'],
    ja: ['ワークスペースを開く', 'クリップボードを取り込む', 'PromptFinch を終了'],
    ko: ['작업 공간 열기', '클립보드 가져오기', 'PromptFinch 종료'],
  }[controller.snapshot().language] || ['Open workspace', 'Import clipboard', 'Quit PromptFinch'];
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: copy[0], click: showWorkspace }, { label: copy[1], click: () => capture('clipboard').catch(error => emit(mainWindow, 'error', safeError(error))) },
    { type: 'separator' }, { label: copy[2], click: () => app.quit() },
  ]));
}
function registerIPC() {
  const handlers = {
    getState: () => state(),
    setLanguage: async value => { await controller.setLanguage(value); return sendState(); },
    chooseConfig: async () => {
      const selected = await dialog.showOpenDialog(mainWindow, { title: 'Select model configuration', properties: ['openFile'],
        filters: [{ name: 'Configuration', extensions: ['env', 'txt'] }, { name: 'All files', extensions: ['*'] }] });
      if (!selected.canceled && selected.filePaths[0]) { await controller.selectConfig(selected.filePaths[0]); result = null; }
      return sendState();
    },
    createConfig: async () => { const file = await controller.createTemplate(); const error = await shell.openPath(file); if (error) { shell.showItemInFolder(file); } return { created: true }; },
    useDemo: async () => { await controller.useDemo(); result = null; return sendState(); },
    generate: input => generate(input), cancel: async () => { await controller.cancel(); return sendState(); },
    clear: async () => { dropCandidate(); result = null; await controller.cancel(); return sendState(); },
    copyResult: async () => { if (!result?.prompt) fail('NO_RESULT'); await clipboard.writeText(result.prompt); return { copied: true }; },
    importClipboard: () => capture('clipboard'), captureSelection: () => capture('selection'),
    hideCompanion: () => { dropCandidate(); return true; },
    runCompanion: async () => {
      if (!candidate || Date.now() - candidate.capturedAt > 10000) { dropCandidate(); fail('SELECTION_EXPIRED'); }
      const chosen = candidate; dropCandidate();
      if (!smoke) {
        if (process.platform === 'win32') {
          const verified = await verifySelectionSource({ platform: process.platform, helperPath, sourceId: chosen.sourceId });
          if (!verified.ok) fail('SELECTION_EXPIRED');
        } else {
          const verified = await captureSelection({ platform: process.platform, clipboard, helperPath });
          if (!verified.ok || verified.text !== chosen.text) fail('SELECTION_EXPIRED');
        }
      }
      if (Date.now() - chosen.capturedAt > 10000) fail('SELECTION_EXPIRED');
      const text = chosen.text;
      showWorkspace(); emit(mainWindow, 'capture', { text, source: 'selection' });
      return generate({ prompt: text, task: 'general', targetModel: '' });
    },
    quit: () => { app.quit(); return true; },
  };
  const companionMethods = new Set(['getState', 'hideCompanion', 'runCompanion']);
  for (const [name, action] of Object.entries(handlers)) {
    ipcMain.handle(`promptfinch:${name}`, async (event, input) => {
      if (!trustedSender(event, [mainWindow, companion]) || (event.sender === companion?.webContents && !companionMethods.has(name))) return { ok: false, error: { code: 'ACCESS_DENIED', message: 'Access denied.' } };
      try { return { ok: true, value: name === 'getState' && event.sender === companion?.webContents ? companionState() : await action(input) }; }
      catch (error) { sendState(); const value = safeError(error); if (event.sender === companion?.webContents) { showWorkspace(); emit(mainWindow, 'error', value); } return { ok: false, error: value }; }
    });
  }
}

if (ownsLock) app.whenReady().then(async () => {
  const { DesktopController, DesktopError } = await import('./controller.mjs');
  DesktopErrorType = DesktopError;
  controller = new DesktopController({ preferencesPath: path.join(app.getPath('userData'), 'preferences.json'),
    templatePath: path.join(app.getPath('userData'), 'model-settings.env') });
  await controller.init();
  mainWindow = buildWindow();
  mainWindow.on('closed', () => { if (!quitting) app.quit(); });
  companion = buildWindow({ width: 310, height: 140, minWidth: 310, minHeight: 140, maxWidth: 310, maxHeight: 140,
    frame: false, resizable: false, movable: false, focusable: false, skipTaskbar: true, alwaysOnTop: true });
  companion.setAlwaysOnTop(true, 'pop-up-menu');
  const session = mainWindow.webContents.session;
  session.protocol.handle('promptfinch', async request => {
    const file = assetPath(request.url, root);
    if (!file) return new Response('Not found', { status: 404 });
    const response = await net.fetch(pathToFileURL(file).href);
    const headers = new Headers(response.headers);
    headers.set('Content-Security-Policy', "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'");
    return new Response(response.body, { status: response.status, headers });
  });
  session.setPermissionRequestHandler((_contents, _permission, callback) => callback(false));
  session.setPermissionCheckHandler(() => false);
  session.on('will-download', event => event.preventDefault());
  registerIPC();
  // Test-only app events are never exposed through the renderer bridge.
  if (smoke) {
    app.on('promptfinch-test-capture', (_event, value) => offerSelection(value));
    app.on('promptfinch-test-clipboard', (_event, value) => { testClipboard = typeof value === 'string' ? value : ''; });
    app.on('promptfinch-test-read-clipboard', (_event, callback) => callback(testClipboard));
  }
  Menu.setApplicationMenu(null);
  await mainWindow.loadURL(`${ORIGIN}/`);
  await companion.loadURL(`${ORIGIN}/?window=companion`);
  mainWindow.show();
  if (!smoke) {
    tray = new Tray(appIcon());
    tray.setToolTip('PromptFinch'); tray.on('click', showWorkspace);
    startWatcher();
    const registered = globalShortcut.register('CommandOrControl+Alt+P', () => capture('selection').catch(error => { showWorkspace(); emit(mainWindow, 'error', safeError(error)); }));
    const imported = globalShortcut.register('CommandOrControl+Alt+Shift+P', () => capture('clipboard').catch(error => { showWorkspace(); emit(mainWindow, 'error', safeError(error)); }));
    shortcutStatus = registered && imported ? 'registered' : 'unavailable';
  }
  sendState();
  app.on('second-instance', showWorkspace);
  app.on('activate', showWorkspace);
}).catch(() => { if (!smoke) dialog.showErrorBox('PromptFinch', 'PromptFinch could not start. Check that the app files and settings are accessible.'); app.exit(1); });

app.on('window-all-closed', () => app.quit());
app.on('before-quit', event => {
  if (quitting) return;
  event.preventDefault(); quitting = true; dropCandidate(); watcher?.stop(); globalShortcut.unregisterAll(); tray?.destroy(); tray = null;
  Promise.race([Promise.resolve(controller?.dispose()).catch(() => {}), new Promise(resolve => setTimeout(resolve, 1500))])
    .finally(() => { result = null; for (const window of [mainWindow, companion]) if (window && !window.isDestroyed()) window.destroy(); app.quit(); });
});
