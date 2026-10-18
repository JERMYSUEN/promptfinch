const { existsSync } = require('node:fs');
const { join } = require('node:path');

module.exports = {
  appId: 'org.promptfinch.desktop',
  productName: 'PromptFinch',
  copyright: 'Copyright © PromptFinch contributors',
  asar: true,
  npmRebuild: false,
  forceCodeSigning: false,
  publish: null,
  extraMetadata: { desktopName: 'org.promptfinch.desktop.desktop' },
  directories: { output: 'desktop-dist/${version}' },
  artifactName: 'PromptFinch-${version}-${os}-${arch}.${ext}',
  /* Positive allowlists keep private model files, captures, source videos and
   * developer artifacts out of the installed app. Helpers are separate below. */
  files: [
    'desktop/*.cjs', 'desktop/*.mjs', 'desktop/*.js', 'desktop/*.html', 'desktop/*.css', 'desktop/*.svg',
    '!desktop/builder.config.cjs', 'lib/optimizer.js', 'public/style.css', 'public/favicon.svg',
    'package.json', 'LICENSE',
  ],
  beforePack(context) {
    const platform = context.electronPlatformName;
    if (!['win32', 'linux'].includes(platform) || process.platform !== platform || process.arch !== 'x64') {
      throw new Error('Build each x64 Windows/Linux desktop package on its matching native x64 host. Use the native Swift release for macOS.');
    }
    const helper = platform === 'win32' ? 'SelectionReader.exe' : 'right-click-watcher';
    if (!existsSync(join(__dirname, 'bin', platform, helper))) {
      throw new Error('Build the platform selection helper before packaging the desktop app.');
    }
  },
  win: {
    target: [{ target: 'nsis', arch: ['x64'] }, { target: 'zip', arch: ['x64'] }],
    artifactName: 'PromptFinch-${version}-windows-${arch}.${ext}',
    executableName: 'PromptFinch',
    requestedExecutionLevel: 'asInvoker',
    signAndEditExecutable: false,
    extraResources: [{ from: 'desktop/bin/win32/SelectionReader.exe', to: 'helpers/SelectionReader.exe' }],
  },
  nsis: {
    oneClick: false, perMachine: false, allowElevation: false,
    allowToChangeInstallationDirectory: true, createDesktopShortcut: true,
    createStartMenuShortcut: true, runAfterFinish: false,
    artifactName: 'PromptFinch-${version}-windows-x64-setup.${ext}',
  },
  linux: {
    target: [{ target: 'AppImage', arch: ['x64'] }, { target: 'tar.gz', arch: ['x64'] }],
    executableName: 'promptfinch',
    syncDesktopName: true,
    category: 'Utility',
    synopsis: 'Refine selected text into an English prompt',
    description: 'A private desktop prompt workspace with an explicit right-click selection action on supported X11 apps.',
    extraResources: [{ from: 'desktop/bin/linux/right-click-watcher', to: 'helpers/right-click-watcher' }],
  },
};
