// Check only explicitly current release sections; dated release evidence stays valid.
export const currentDownloadFiles = [
  'README.md', 'docs/readme/README.zh-CN.md', 'docs/readme/README.zh-TW.md', 'docs/macos.md',
];

export function releaseDocumentationErrors(version, files) {
  const errors = [];
  const releaseURL = `https://github.com/JERMYSUEN/promptfinch/releases/tag/v${version}`;
  const guide = `docs/releases/v${version}.md`;
  const guideText = files[guide];
  if (!guideText) errors.push(`${guide}: missing current release guide`);

  for (const file of currentDownloadFiles) {
    const text = files[file] ?? '';
    const start = '<!-- current-release-downloads:start -->';
    const end = '<!-- current-release-downloads:end -->';
    if (text.split(start).length !== 2 || text.split(end).length !== 2 || text.indexOf(end) < text.indexOf(start)) {
      errors.push(`${file}: expected one ordered current-release-downloads block`);
      continue;
    }
    const block = text.slice(text.indexOf(start) + start.length, text.indexOf(end));
    if (!block.includes(`](${releaseURL})`)) errors.push(`${file}: current download must link to v${version}`);
    if (!block.includes(`PromptFinch-${version}-macos-arm64.zip`)) errors.push(`${file}: current macOS package must match v${version}`);
    // Every release/versioned package mentioned as current must match metadata.
    for (const match of block.matchAll(/(?:releases\/(?:tag|download)\/v|PromptFinch-(?:source-v)?)(\d+\.\d+\.\d+)/g)) {
      if (match[1] !== version) errors.push(`${file}: stale current release ${match[1]} (expected ${version})`);
    }
    if (guideText) {
      for (const match of block.matchAll(/`(PromptFinch-[^`\s]+\.(?:zip|exe|AppImage|tar\.gz))`/g)) {
        if (!guideText.includes(`\`${match[1]}\``)) errors.push(`${file}: package missing from current release guide: ${match[1]}`);
      }
    }
  }

  const changelog = files['CHANGELOG.md'] ?? '';
  const references = new Map();
  const normalizeLabel = label => label.trim().replace(/\s+/g, ' ').toLowerCase();
  const isReleaseLabel = label => /^(?:unreleased|\d+\.\d+\.\d+)$/.test(label);
  for (const line of changelog.split(/\r?\n/)) {
    const start = /^ {0,3}\[([^\]]+)\]:([^\r\n]*)$/.exec(line);
    if (!start) continue;
    const label = normalizeLabel(start[1]);
    // Support a single-line CommonMark destination with an optional title.
    // Fail closed for release definitions outside this subset (for example,
    // a destination on the next line), rather than letting a later definition
    // hide the first one that Markdown would use.
    const definition = /^[ \t]*(?:<([^<>\r\n]+)>|([^\s<>]+))(?:[ \t]+(?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\((?:\\.|[^)\\])*\)))?[ \t]*$/.exec(start[2]);
    if (!definition && isReleaseLabel(label)) errors.push(`CHANGELOG.md: unsupported release reference [${start[1]}]; use a single-line destination and optional title`);
    if (references.has(label)) errors.push(`CHANGELOG.md: duplicate reference [${start[1]}]`);
    else references.set(label, definition?.[1] ?? definition?.[2]); // Markdown uses the first definition.
  }
  for (const match of changelog.matchAll(/^## \[([^\]]+)\]/gm)) {
    const label = normalizeLabel(match[1]);
    if (!isReleaseLabel(label)) continue;
    const expected = label === 'unreleased'
      ? `https://github.com/JERMYSUEN/promptfinch/compare/v${version}...main`
      : `https://github.com/JERMYSUEN/promptfinch/releases/tag/v${label}`;
    if (references.get(label) !== expected) errors.push(`CHANGELOG.md: [${match[1]}] must resolve to ${expected}`);
  }
  return errors;
}
