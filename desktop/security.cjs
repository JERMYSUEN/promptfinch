'use strict';
const path = require('node:path');

const ORIGIN = 'promptfinch://app';
const FILES = Object.freeze({
  '/': 'desktop/index.html', '/index.html': 'desktop/index.html',
  '/renderer.js': 'desktop/renderer.js', '/locales.js': 'desktop/locales.js',
  '/desktop.css': 'desktop/desktop.css', '/base.css': 'public/style.css',
  '/icon.svg': 'public/favicon.svg',
});

function trustedURL(value) {
  try {
    const url = new URL(value);
    return url.protocol === 'promptfinch:' && url.hostname === 'app' && !url.port
      && !url.username && !url.password && ['/', '/index.html'].includes(url.pathname)
      && !url.hash && ['', '?window=companion'].includes(url.search);
  } catch { return false; }
}

function assetPath(value, root) {
  try {
    const url = new URL(value);
    if (url.protocol !== 'promptfinch:' || url.hostname !== 'app' || url.port || url.username || url.password) return null;
    return Object.hasOwn(FILES, url.pathname) ? path.join(root, FILES[url.pathname]) : null;
  } catch { return null; }
}

function trustedSender(event, windows) {
  return Boolean(event.senderFrame && event.senderFrame === event.sender.mainFrame
    && trustedURL(event.senderFrame.url)
    && windows.some(win => win && !win.isDestroyed() && win.webContents === event.sender));
}

function validCapture(value, now = Date.now()) {
  return Boolean(value && value.ok === true && typeof value.text === 'string'
    && value.text.trim() && value.text.length <= 12000
    && Number.isFinite(value.x) && Number.isFinite(value.y)
    && Number.isFinite(value.capturedAt) && now - value.capturedAt >= -1000
    && now - value.capturedAt <= 2000);
}

module.exports = { ORIGIN, FILES, trustedURL, assetPath, trustedSender, validCapture };
