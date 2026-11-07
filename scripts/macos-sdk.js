import { spawnSync } from 'node:child_process';
import { readdirSync, realpathSync } from 'node:fs';
import { dirname, join } from 'node:path';

const swiftUIProbe = `import SwiftUI
struct SDKProbe: View {
    @State private var value = false
    var body: some View { Text(value ? "On" : "Off") }
}`;

export function selectMacOSSDK(cache) {
  const current = spawnSync('xcrun', ['--show-sdk-path'], { encoding: 'utf8' });
  if (current.error) throw current.error;
  if (current.status !== 0 || !current.stdout.trim()) {
    throw new Error(current.stderr.trim() || 'xcrun could not find a macOS SDK. Install Xcode Command Line Tools.');
  }
  const sdk = current.stdout.trim();
  const probe = path => {
    const result = spawnSync('xcrun', ['swiftc', '-sdk', path, '-swift-version', '5',
      '-module-cache-path', cache, '-typecheck', '-'], { input: swiftUIProbe, encoding: 'utf8' });
    if (result.error) throw result.error;
    return result;
  };
  const result = probe(sdk);
  if (result.status === 0) return sdk;

  if (!process.env.SDKROOT && result.stderr.includes("plugin for module 'SwiftUIMacros' not found")) {
    // Some Command Line Tools ship a newer SDK without its SwiftUI macro plugin.
    // Check compatible SDKs in the same developer installation before building.
    const resolved = realpathSync(sdk);
    const sdkFolder = dirname(resolved);
    const candidates = readdirSync(sdkFolder, { withFileTypes: true })
      .filter(entry => entry.isDirectory() && /^MacOSX\d+(\.\d+)*\.sdk$/.test(entry.name))
      .map(entry => entry.name)
      .sort((a, b) => b.localeCompare(a, 'en', { numeric: true }));
    for (const name of candidates) {
      const path = join(sdkFolder, name);
      if (path === resolved || probe(path).status !== 0) continue;
      console.warn(`SwiftUI macro support is missing in ${sdk}. Using compatible SDK ${path}.`);
      return path;
    }
  }

  throw new Error(`SwiftUI SDK check failed for ${sdk}. Update Xcode Command Line Tools or set SDKROOT to a compatible macOS SDK.\n${result.stderr.trim()}`);
}
