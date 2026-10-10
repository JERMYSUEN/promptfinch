#!/usr/bin/env node
import fs from "fs";
import path from "path";
import process from "process";

const root = path.resolve(import.meta.dirname, "..");
const errs = [];
const warn = (m) => errs.push(m);

// ---------- parse nav banner ----------
const parseEntries = (line) => {
  const entries = [];
  const re = /\[([^\]]+)\]\(([^)]+)\)|\*\*([^*]+)\*\*/g;
  let m;
  while ((m = re.exec(line))) {
    if (m[3] !== undefined) entries.push({ label: m[3], lang: null, target: null, bold: true });
    else {
      const langMatch = m[2].match(/README\.([a-zA-Z-]+)\.md$/);
      entries.push({ label: m[1], target: m[2], lang: langMatch ? langMatch[1] : null, bold: false });
    }
  }
  return entries;
};
// The nav is the first line containing at least two Markdown links referencing a README file.
const parseNav = (text) => {
  for (const line of text.split(/\r?\n/)) {
    const links = line.match(/\]\([^)]*README[^)]*\.md\)/g);
    if (links && links.length >= 2) return parseEntries(line);
  }
  return parseEntries(text.split(/\r?\n/)[0]);
};

const base = parseNav(fs.readFileSync(path.join(root, "README.md"), "utf8"));
const canonicalOrder = base.map((e) => e.lang);
const canonicalLabels = {};
for (const e of base) canonicalLabels[e.lang] = e.label;

if (base.filter((e) => e.bold).length !== 1 || base[0].label !== "English" || base[0].lang !== null)
  warn("README.md: nav must start with bold **English**");
if (canonicalOrder.length !== 29) warn(`README.md: expected 29 nav entries, found ${canonicalOrder.length}`);
if (new Set(canonicalOrder).size !== canonicalOrder.length) warn("README.md: duplicate languages in nav");
const set29 = new Set(canonicalOrder);
if (!fs.readFileSync(path.join(root, "README.md"), "utf8").includes("logo.svg")) warn("README.md: missing header logo");
for (const e of base)
  if (e.target && !fs.existsSync(path.join(root, e.target))) warn(`README.md: nav target missing: ${e.target}`);

// ---------- localized files ----------
const expected = canonicalOrder.filter((l) => l !== null); // 28 localized langs
const dir = path.join(root, "docs/readme");
const found = fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => f.startsWith("README.") && f.endsWith(".md")).map((f) => f.slice(7, -3)) : [];
for (const l of expected) if (!found.includes(l)) warn(`missing localized file: docs/readme/README.${l}.md`);
for (const l of found) if (!set29.has(l)) warn(`unexpected localized file: docs/readme/README.${l}.md`);

// base heading counts
const headingCount = (text, prefix) => text.split(/\r?\n/).filter((l) => l.startsWith(prefix)).length;
const baseText = fs.readFileSync(path.join(root, "README.md"), "utf8");
const baseH3 = headingCount(baseText, "### ");
const baseH4 = headingCount(baseText, "#### ");
const baseH2 = headingCount(baseText, "## ");



const fullStyle = ["zh-CN", "zh-TW"];
const versionRe = /\b\d+\.\d+\.\d+\b(?<!\.\d)(?!\.\d)/g;
const staleVersions = [];
const rows = [];

for (const lang of expected) {
  const file = `docs/readme/README.${lang}.md`;
  const text = fs.readFileSync(path.join(root, file), "utf8");
  const entries = parseNav(text);
  const ok = [];
  if (!text.includes("logo.svg")) ok.push("missing header logo");
  if (entries.length !== canonicalOrder.length) ok.push(`nav entries ${entries.length} != ${canonicalOrder.length}`);
  if (entries.length === canonicalOrder.length) {
    const langs = entries.map((e, i) => (e.bold ? lang : e.lang));
    for (let i = 0; i < langs.length; i++) {
      if (langs[i] !== canonicalOrder[i]) ok.push(`nav order drift at slot ${i + 1}: expected ${canonicalOrder[i]}, found ${langs[i] || "??"}`);
      if (!entries[i].bold && entries[i].label !== canonicalLabels[canonicalOrder[i]]) ok.push(`nav label drift at slot ${i + 1}: expected "${canonicalLabels[canonicalOrder[i]]}", found "${entries[i].label}"`);
    }
    if (entries.filter((e) => e.bold).length !== 1) ok.push("nav must have exactly one bold (own language) entry");
    for (const e of entries) {
      if (e.target && e.lang !== lang) {
        const resolved = e.target === "../../README.md" ? "README.md" : path.join("docs/readme", e.target);
        if (!fs.existsSync(path.join(root, resolved))) ok.push(`nav target missing: ${e.target}`);
      }
    }
  }
  const h2 = headingCount(text, "## ");
  const h3 = headingCount(text, "### ");
  const h4 = headingCount(text, "#### ");
  const content = text.split(/\r?\n/).slice(1).join("").replace(/\s/g, "").length;
  if (fullStyle.includes(lang)) {
    if (h2 !== baseH3 + 1) ok.push(`h2 ${h2} != base h3 sections + zh title (${baseH3}+1=${baseH3 + 1})`);
    if (h3 !== baseH4) ok.push(`h3 ${h3} != base h4 (${baseH4})`);
    if (content < 3000) ok.push(`content ${content} chars < 3000 (full reference drifted)`);
  } else {
    if (h2 > 1) ok.push(`summary file gained structure: h2 ${h2} > 1`);
    if (content < 150) ok.push(`content ${content} chars < 150`);
    for (const m of text.matchAll(versionRe)) staleVersions.push({ file, version: m[0] });
  }
  rows.push({ file, h2, h3, content, ok });
}

// ---------- version parity ----------
const pkg = JSON.parse(fs.readFileSync(path.join(root, "package.json"), "utf8"));
const changelog = fs.readFileSync(path.join(root, "CHANGELOG.md"), "utf8");
const relRe = /^## \[(\d+\.\d+\.\d+)\]/gm;
const rel = [...changelog.matchAll(relRe)];
const unreleased = changelog.indexOf("[Unreleased]");
const latest = rel.length ? rel[0][1] : null;
if (pkg.version !== latest) warn(`package.json version ${pkg.version} != CHANGELOG latest ${latest}`);
if (unreleased >= 0 && latest && rel[0].index > unreleased) warn("CHANGELOG: [Unreleased] must precede the latest release (Keep a Changelog order)");
for (const m of fs.readFileSync(path.join(root, "README.md"), "utf8").matchAll(versionRe)) staleVersions.push({ file: "README.md", version: m[0] });
for (const { file, version } of staleVersions) if (version !== latest) warn(`${file}: stale version ${version} (latest ${latest})`);

// ---------- summary ----------
let bad = 0;
for (const r of rows) {
  if (r.ok.length) {
    bad++;
    console.log(`DRIFT ${r.file}`);
    for (const m of r.ok) console.log(`  - ${m}`);
  }
}
console.log(`\n${rows.length} editions checked (full-style: ${fullStyle.join(", ")}), base h2=${baseH2} h3=${baseH3} h4=${baseH4}`);
console.log(`version: package.json ${pkg.version}, CHANGELOG latest ${latest}`);
if (errs.length) {
  console.log(`\n${errs.length} other issue(s):`);
  for (const m of errs) console.log(`  - ${m}`);
  bad += errs.length;
}
console.log(bad === 0 ? `\nREADME sync: OK` : `\nREADME sync: ${bad} drift(s)`);
process.exit(bad === 0 ? 0 : 1);
