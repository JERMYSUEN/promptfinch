const { execFileSync } = require('node:child_process');
const { existsSync, mkdirSync } = require('node:fs');
const { join, resolve } = require('node:path');

const root = resolve(__dirname, '..');
const output = join(root, 'desktop', 'bin', process.platform);
if (process.platform === 'darwin') {
  process.stdout.write('The macOS release uses its native Swift app; no Electron selection helper is built.\n');
} else if (process.platform === 'linux') {
  mkdirSync(output, { recursive: true });
  execFileSync('cc', ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror',
    join(root, 'desktop', 'linux', 'RightClickWatcher.c'), '-o', join(output, 'right-click-watcher'),
    '-lX11', '-lXtst'], { stdio: 'inherit', cwd: root });
  process.stdout.write('Built the Linux X11 right-click observer.\n');
} else if (process.platform === 'win32') {
  mkdirSync(output, { recursive: true });
  const windows = process.env.SystemRoot || 'C:\\Windows';
  const framework = join(windows, 'Microsoft.NET', 'Framework64', 'v4.0.30319');
  const compiler = join(framework, 'csc.exe');
  const wpf = join(framework, 'WPF');
  const references = ['UIAutomationClient.dll', 'UIAutomationTypes.dll', 'WindowsBase.dll'];
  if (![compiler, ...references.map(file => join(wpf, file))].every(existsSync)) {
    throw new Error('The Windows helper requires the built-in .NET Framework 4.x C# compiler and WPF UI Automation assemblies.');
  }
  execFileSync(compiler, ['/nologo', '/target:exe', '/platform:x64', '/optimize+', '/warn:4', '/warnaserror+',
    `/out:${join(output, 'SelectionReader.exe')}`,
    ...references.map(file => `/reference:${join(wpf, file)}`),
    '/reference:System.dll', '/reference:System.Core.dll', '/reference:System.Windows.Forms.dll',
    join(root, 'desktop', 'windows', 'SelectionReader.cs')], { stdio: 'inherit', cwd: root, windowsHide: true });
  process.stdout.write('Built the Windows UI Automation selection helper.\n');
} else {
  throw new Error('Desktop selection helpers are available only for Windows and Linux X11.');
}
