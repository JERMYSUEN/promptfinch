import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { currentDownloadFiles, releaseDocumentationErrors } from '../scripts/docs-contract.js';

const root = new URL('../', import.meta.url);
const { version } = JSON.parse(readFileSync(new URL('package.json', root), 'utf8'));
const guide = `docs/releases/v${version}.md`;
const source = Object.fromEntries([...currentDownloadFiles, 'CHANGELOG.md', guide].map(file => [file, readFileSync(new URL(file, root), 'utf8')]));

test('current release documentation and changelog references agree', () => {
  assert.deepEqual(releaseDocumentationErrors(version, source), []);
});

test('a stale current download in any maintained installation guide fails', () => {
  for (const file of currentDownloadFiles) {
    const files = { ...source, [file]: source[file].replace(`PromptFinch-${version}-macos-arm64.zip`, 'PromptFinch-0.0.1-macos-arm64.zip') };
    assert.ok(releaseDocumentationErrors(version, files).some(error => error.startsWith(`${file}:`) && /package|stale/.test(error)), file);
  }
});

test('missing, duplicate, or reversed current release markers fail', () => {
  const file = currentDownloadFiles[0];
  const start = '<!-- current-release-downloads:start -->';
  const end = '<!-- current-release-downloads:end -->';
  for (const text of [source[file].replace(start, ''), `${source[file]}\n${start}`, source[file].replace(start, 'SWAPPED-MARKER').replace(end, start).replace('SWAPPED-MARKER', end)]) {
    assert.ok(releaseDocumentationErrors(version, { ...source, [file]: text }).some(error => error.includes('ordered current-release-downloads')));
  }
});

test('a stale release link, unknown current package, or missing release guide fails', () => {
  const file = currentDownloadFiles[0];
  const staleLink = source[file].replace(`releases/tag/v${version}`, 'releases/tag/v0.0.1');
  assert.ok(releaseDocumentationErrors(version, { ...source, [file]: staleLink }).some(error => error.includes('must link')));
  const unknownPackage = source[file].replace('macos-arm64.zip', 'macos-universal.zip');
  assert.ok(releaseDocumentationErrors(version, { ...source, [file]: unknownPackage }).some(error => error.includes('package missing')));
  assert.ok(releaseDocumentationErrors(version, { ...source, [guide]: '' }).some(error => error.includes('missing current release guide')));
});

test('missing changelog references and stale Unreleased comparison fail', () => {
  const log = source['CHANGELOG.md'];
  const missing = log.replace(new RegExp(`^\\[${version.replaceAll('.', '\\.')}\\]:.*$`, 'm'), '');
  assert.ok(releaseDocumentationErrors(version, { ...source, 'CHANGELOG.md': missing }).some(error => error.includes(`[${version}]`)));
  const stale = log.replace(`compare/v${version}...main`, 'compare/v0.0.1...main');
  assert.ok(releaseDocumentationErrors(version, { ...source, 'CHANGELOG.md': stale }).some(error => error.includes('[Unreleased]')));
});

test('historical release links outside current download sections remain allowed', () => {
  const file = currentDownloadFiles[0];
  const files = { ...source, [file]: `${source[file]}\nHistorical: [v0.0.1](https://github.com/JERMYSUEN/promptfinch/releases/tag/v0.0.1), \`PromptFinch-0.0.1-macos-arm64.zip\`.\n` };
  assert.deepEqual(releaseDocumentationErrors(version, files), []);
});

test('a later correct changelog reference cannot hide an earlier stale definition', () => {
  const text = `[unreleased]: https://github.com/JERMYSUEN/promptfinch/compare/v0.0.1...main\n${source['CHANGELOG.md']}`;
  const errors = releaseDocumentationErrors(version, { ...source, 'CHANGELOG.md': text });
  assert.ok(errors.some(error => error.includes('duplicate reference')));
  assert.ok(errors.some(error => error.includes('[Unreleased] must resolve')));
});

test('CommonMark indentation, angle destinations, and optional titles retain the correct reference', () => {
  const url = `https://github.com/JERMYSUEN/promptfinch/compare/v${version}...main`;
  const original = `[Unreleased]: ${url}`;
  for (const definition of [
    `[Unreleased]: <${url}>`,
    `[Unreleased]: ${url} "Current changes"`,
    `   [Unreleased]: <${url}> 'Current changes'`,
    ` [  UNRELEASED  ]: ${url} (Current changes)`,
    `[Unreleased]: ${url} "Current \\"quoted\\" changes"`,
  ]) {
    const text = source['CHANGELOG.md'].replace(original, definition);
    assert.deepEqual(releaseDocumentationErrors(version, { ...source, 'CHANGELOG.md': text }), [], definition);
  }
});

test('an earlier stale title or indented reference cannot be hidden by the correct definition', () => {
  const wrong = 'https://github.com/JERMYSUEN/promptfinch/compare/v0.0.1...main';
  for (const definition of [
    `[Unreleased]: ${wrong} "Historical comparison"`,
    `   [Unreleased]: ${wrong}`,
    `  [  UNRELEASED  ]: <${wrong}> 'Historical comparison'`,
  ]) {
    const text = `${definition}\n${source['CHANGELOG.md']}`;
    const errors = releaseDocumentationErrors(version, { ...source, 'CHANGELOG.md': text });
    assert.ok(errors.some(error => error.includes('duplicate reference')), definition);
    assert.ok(errors.some(error => error.includes('[Unreleased] must resolve')), definition);
  }
});

test('unsupported release reference syntax fails explicitly and still reserves the first definition', () => {
  const url = `https://github.com/JERMYSUEN/promptfinch/compare/v${version}...main`;
  for (const definition of [
    `[Unreleased]:\n  ${url}`,
    `[Unreleased]: ${url} "Unclosed title`,
  ]) {
    const text = `${definition}\n${source['CHANGELOG.md']}`;
    const errors = releaseDocumentationErrors(version, { ...source, 'CHANGELOG.md': text });
    assert.ok(errors.some(error => error.includes('unsupported release reference')), definition);
    assert.ok(errors.some(error => error.includes('duplicate reference')), definition);
    assert.ok(errors.some(error => error.includes('[Unreleased] must resolve')), definition);
  }
});

test('reference labels collapse whitespace and ignore case before duplicate detection', () => {
  const text = `${source['CHANGELOG.md']}\n[Build \t Notes]: https://example.com/first\n[build notes]: https://example.com/second\n`;
  assert.ok(releaseDocumentationErrors(version, { ...source, 'CHANGELOG.md': text })
    .some(error => error.includes('duplicate reference [build notes]')));
});

test('four-space code indentation does not define a conflicting Markdown reference', () => {
  const text = `${source['CHANGELOG.md']}\n    [Unreleased]: https://example.com/code-example\n`;
  assert.deepEqual(releaseDocumentationErrors(version, { ...source, 'CHANGELOG.md': text }), []);
});
