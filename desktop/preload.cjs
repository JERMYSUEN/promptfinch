'use strict';
const { contextBridge, ipcRenderer } = require('electron');

const invoke = (method, value) => ipcRenderer.invoke(`promptfinch:${method}`, value);
const subscribe = (name, callback) => {
  if (typeof callback !== 'function') throw new TypeError('A callback is required.');
  const listener = (_event, value) => callback(value);
  ipcRenderer.on(`promptfinch:${name}`, listener);
  return () => ipcRenderer.removeListener(`promptfinch:${name}`, listener);
};

contextBridge.exposeInMainWorld('promptfinch', Object.freeze({
  getState: () => invoke('getState'),
  setLanguage: language => invoke('setLanguage', language),
  chooseConfig: () => invoke('chooseConfig'),
  createConfig: () => invoke('createConfig'),
  useDemo: () => invoke('useDemo'),
  generate: input => invoke('generate', input),
  cancel: () => invoke('cancel'),
  clear: () => invoke('clear'),
  copyResult: () => invoke('copyResult'),
  importClipboard: () => invoke('importClipboard'),
  captureSelection: () => invoke('captureSelection'),
  runCompanion: () => invoke('runCompanion'),
  hideCompanion: () => invoke('hideCompanion'),
  quit: () => invoke('quit'),
  onState: callback => subscribe('state', callback),
  onCapture: callback => subscribe('capture', callback),
  onResult: callback => subscribe('result', callback),
  onError: callback => subscribe('error', callback),
}));
