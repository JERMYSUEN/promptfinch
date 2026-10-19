import test from 'node:test';
import assert from 'node:assert/strict';
import { restoreLiteralEncoding } from '../lib/optimizer.js';

const nfd = 'Cafe\u0301';
const nfc = 'Café';

test('apostrophes in contractions do not hide later quoted exact literals', () => {
  for (const [source, output] of [
    [`Don't change '${nfd}'.`, `Don't change '${nfc}'.`],
    [`L'utilisateur conserve '${nfd}'.`, `Retain '${nfc}' exactly.`],
    [`The users' label is '${nfd}'.`, `Use '${nfc}' as the label.`],
  ]) assert.equal(restoreLiteralEncoding(output, source), output.replace(nfc, nfd));
});

test('every normalized copy is restored when another exact copy already exists', () => {
  const source = `Use the exact label "${nfd}" in the title and body.`;
  const output = `Use "${nfd}" as the title and "${nfc}" in the body; retain ${nfc} in the footer.`;
  assert.equal(restoreLiteralEncoding(output, source), output.replaceAll(nfc, nfd));
});

test('an unrelated word containing the canonical value does not create ambiguity', () => {
  const source = 'Keep the isolated key "e\u0301" unchanged. Explain the word café.';
  const output = 'Keep the isolated key "é" unchanged. Explain the word café.';
  assert.equal(restoreLiteralEncoding(output, source), 'Keep the isolated key "e\u0301" unchanged. Explain the word café.');
});

test('explicit NFC and NFD source alternatives remain ambiguous and unchanged', () => {
  for (const source of [
    `Keep "${nfd}" and "${nfc}" distinct.`,
    `Keep '${nfd}' and '${nfc}' distinct.`,
    `Keep "${nfd}". Discuss ${nfc} separately.`,
  ]) {
    const output = `Use "${nfc}" and "${nfd}".`;
    assert.equal(restoreLiteralEncoding(output, source), output);
  }
  const first = 's\u0323\u0307';
  const second = 's\u0307\u0323';
  assert.equal(first.normalize('NFC'), second.normalize('NFC'));
  const output = `Use "${first.normalize('NFC')}".`;
  assert.equal(restoreLiteralEncoding(output, `Keep "${first}" and "${second}" distinct.`), output);
});

test('escaped quotation marks and apostrophes remain part of complete literals', () => {
  const literals = [
    `"${nfd} \\"quoted\\""`,
    `'don\\'t ${nfd}'`,
    `“don’t ${nfd}”`,
    `‘don’t ${nfd}’`,
  ];
  for (const literal of literals) {
    const source = `Keep ${literal} exactly.`;
    const output = `Return ${literal.normalize('NFC')} unchanged.`;
    assert.equal(restoreLiteralEncoding(output, source), `Return ${literal} unchanged.`);
  }
});

test('complete code fences and inline code keep their combining marks', () => {
  for (const literal of [
    `\`\`\`js\nconst ${nfd} = "value";\n\`\`\``,
    `\`\`const ${nfd} = \`value\`;\`\``,
    `\`${nfd}\``,
  ]) {
    const source = `Keep this code unchanged:\n${literal}`;
    const output = `Use this code:\n${literal.normalize('NFC')}`;
    assert.equal(restoreLiteralEncoding(output, source), `Use this code:\n${literal}`);
  }
});

test('Unicode token boundaries prevent changes inside unrelated identifiers', () => {
  const source = `Keep "${nfd}" exactly.`;
  const protectedTokens = [
    `${nfc}teria`, `pre${nfc}`, `_${nfc}`, `${nfc}_suffix`,
    `${nfc}42`, `42${nfc}`, `𐐀${nfc}`, `${nfc}𐐀`,
    `${nfc}\u0300`, `${nfc}\u200dName`,
    `${nfc}-based`, `${nfc}.json`, `https://${nfc}/path`, `/tmp/${nfc}`, `${nfc}@example.com`,
  ];
  const output = `Keep ${nfc}. Leave ${protectedTokens.join(', ')} unchanged.`;
  const restored = restoreLiteralEncoding(output, source);
  assert.equal(restored, `Keep ${nfd}. Leave ${protectedTokens.join(', ')} unchanged.`);
});

test('literal restoration is idempotent and never guesses absent or unquoted literals', () => {
  const source = `Keep "${nfd}" in both places.`;
  const output = `Keep "${nfc}" and ${nfc}.`;
  const once = restoreLiteralEncoding(output, source);
  assert.equal(restoreLiteralEncoding(once, source), once);
  assert.equal(restoreLiteralEncoding(`Discuss ${nfc}.`, `Discuss ${nfd}.`), `Discuss ${nfc}.`);
  assert.equal(restoreLiteralEncoding('Use "different".', source), 'Use "different".');
  assert.equal(restoreLiteralEncoding(output, `Keep "${nfd}`), output);
});

test('complete literals near the input and output size boundaries are retained', () => {
  const sourcePrefix = `Keep "${nfd}" exactly. `;
  const source = sourcePrefix + 'x'.repeat(12000 - sourcePrefix.length);
  const output = `${nfc} `.repeat(4800);
  const restored = restoreLiteralEncoding(output, source);
  assert.equal(source.length, 12000);
  assert.equal(restored, `${nfd} `.repeat(4800));
  assert.equal(restored.length, 28800); // The caller revalidates expanded output; this helper never truncates.
});
