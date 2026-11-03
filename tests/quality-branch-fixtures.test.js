import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { validateInput } from '../lib/optimizer.js';

const fixtures = JSON.parse(await readFile(new URL('./fixtures/prompt-quality-branch-regressions.json', import.meta.url), 'utf8'));
const historical = JSON.parse(await readFile(new URL('./fixtures/prompt-quality.json', import.meta.url), 'utf8'));

test('branch regression sources retain both historical failures exactly for comparable evaluation', () => {
  const pairs = [
    ['branch-mixed-insufficient-criteria', 'quality-analysis-mixed-insufficient-criteria'],
    ['branch-missing-source-no-questions', 'quality-summary-zh-missing-no-questions'],
  ];
  for (const [currentID, historicalID] of pairs) {
    const current = fixtures.find(fixture => fixture.id === currentID);
    const original = historical.find(fixture => fixture.id === historicalID);
    assert.ok(current && original);
    assert.equal(current.prompt, original.prompt, `${currentID} must not simplify its historical source`);
    assert.equal(current.task, original.task);
  }
});

test('branch fixtures accept each language setting without altering source bytes or using output expectations as input', () => {
  // Corpus/transport integrity only: no generated output or semantic acceptance is claimed.
  assert.equal(fixtures.length, 8);
  assert.equal(new Set(fixtures.map(fixture => fixture.id)).size, fixtures.length);
  for (const fixture of fixtures) {
    assert.match(fixture.id, /^[a-zA-Z0-9][a-zA-Z0-9._-]*$/);
    assert.ok(fixture.expected.criticalChecks.length > 0);
    for (const literal of fixture.expected.literals) {
      assert.ok(fixture.prompt.includes(literal), `${fixture.id}: expected literals must originate in the source`);
    }
    for (const promptLanguage of ['en', 'zh-Hant']) {
      for (const notesLanguage of ['zh-TW', 'en', 'ja', 'ko']) {
        const source = JSON.parse(JSON.stringify({ prompt: fixture.prompt, task: fixture.task, promptLanguage, notesLanguage }));
        const input = validateInput(source);
        assert.equal(input.prompt, fixture.prompt);
        assert.equal(input.task, fixture.task);
        assert.equal(input.promptLanguage, promptLanguage);
        assert.equal(input.notesLanguage, notesLanguage);
        assert.ok(!Object.hasOwn(input, 'expected'));
        assert.ok(!Object.hasOwn(input, 'answerLanguage'));
      }
    }
  }
});
