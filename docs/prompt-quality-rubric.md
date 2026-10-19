# Prompt quality regression rubric

This guide defines a synthetic semantic review for the prompt editor. It evaluates the instructions the editor produces, not the downstream model's completed answer. The [16-case corpus](../tests/fixtures/prompt-quality.json) is compatible with the existing [live evaluation runner](../scripts/verify-multilingual.js).

**Evidence status: live synthetic samples have been collected and manually reviewed, with known issues remaining.** See the [current verification report](prompt-quality-verification.md) for tested configurations, recorded source versions, results and limits. Adding these fixtures, checking JSON, or passing unit tests does not establish semantic acceptance. No downstream task execution or performance gain is established by this rubric. Historical model outputs remain in [the earlier improvement record](improvement-live-results.json); do not relabel those outputs as results of this corpus or a revised policy.

## What a useful improvement means

A useful edit makes the same task easier to execute: it may resolve a reference, bind a limit to the correct field, organize dependencies, define a needed calculation, or connect verification to the requested behavior. Fluency, English output, a longer prompt, extra headings, or a successful HTTP response do not prove improvement.

Preservation is the first requirement. An apparently helpful addition is a regression if it invents facts, technologies, audiences, deadlines, output formats, or deliverables. Operational methods can be added when they serve the stated task; they must not override explicit constraints. An already complete small task can be returned unchanged, with no claimed edit and an empty `improvements` array.

Keep three language decisions separate:

- **Instruction language:** the requested `--prompt-language`, either English (`en`) or Traditional Chinese (`zh-Hant`). Translate operative instructions once; preserve source documents and required literals as data.
- **Task answer language:** preserve an explicit language. If a prose answer language is inferred from the operative request, state the choice in the prompt and in `assumptions`. Source documents and interface labels do not determine that language. A code-only task does not require inventing a prose-language requirement.
- **UI notes language:** the requested `--notes-language`, independently applied to `improvements` and `assumptions`.

## Coverage

| Case ID | Main check |
| --- | --- |
| `quality-coding-zh-csv-behavior` | Inspect, fix and verify the specific requested behavior; allow truthful future execution reports. |
| `quality-analysis-en-rates` | Define the relevant rate calculation and percentage-point comparison without doing the calculation. |
| `quality-writing-en-clear-noop` | Accept an unchanged, complete small prompt without manufacturing an improvement. |
| `quality-marketing-ko-confirmed-fact` | Retain the confirmed feature and the exact scope of prohibited marketing claims. |
| `quality-summary-ja-decisions` | Preserve the supplied source, decisions, uncertainty, owner and three-bullet format. |
| `quality-analysis-mixed-insufficient-criteria` | Distinguish absent criteria from supplied but decision-insufficient criteria. |
| `quality-summary-zh-missing-no-questions` | Missing required source plus no questions yields a limitation path, not invented content or an ask-first template. |
| `quality-general-mixed-language-no-questions` | Do not guess an unresolved answer language or ask a forbidden clarification. |
| `quality-writing-zh-conflict-no-questions` | Replace an impossible task with one conflict-only path; do not reactivate contradictory requirements in a wrapper. |
| `quality-summary-zh-source-supplied-late` | Read the complete request and use the source supplied at its end instead of asking for it again. |
| `quality-analysis-en-research-tools` | Use available research tools before asking for the findings; acknowledge inaccessible sources. |
| `quality-coding-en-workspace-first` | Inspect accessible workspace code before requesting pasted files; keep code-only delivery. |
| `quality-coding-ja-template-placeholders` | Preserve intentional reusable path placeholders and clearly synthetic examples. |
| `quality-writing-zh-exact-field-limits` | Preserve identifier case, exact numbers, inclusive endpoints, field scope, units and JSON-only output. |
| `quality-summary-en-hostile-quote` | Keep a fake SYSTEM line as quoted source data without obeying it. |
| `quality-general-ko-bounded-order` | Offer useful task instructions without inventing possessions or blocking on a nonessential inventory. |

All product names, messages, project facts and source documents in the corpus are synthetic. The `example.com` pricing URLs are illustrative fixture inputs, not verified vendor pages. Do not turn this corpus into actual product-price research. The marker in the hostile quoted log is not a real credential.

## Review procedure and pass criteria

For each completed response, read the complete original request and the **entire copied prompt**, including wrappers, rather than judging a snippet or its improvement notes. Apply the following checks manually. Each fixture supplies additional `constraints`, `valueCriteria`, `criticalChecks` and a case-specific `review`.

1. **Fidelity — pass/fail.** Can the future task model follow the edited prompt while satisfying every compatible original requirement? Check who acts, conditions, exceptions, prohibitions, uncertainty, number-to-field relationships, exact identifiers and final output format. Required literal presence is necessary, but text can contain every literal and still bind it to the wrong field or turn a prohibition into a different rule.
2. **Dependencies and role boundary — pass/fail.** Can work proceed when its real inputs or tools are available? Are only essential missing details blocking? Are supplied-but-insufficient details still checked? Respect no-question limits for missing sources, conflicts and ambiguous language. The editor must not perform the original task, claim it already inspected files, or prohibit the future executor from truthfully reporting work it later performs.
3. **Task value — 0, 1 or 2.** Use the fixture's criteria. `0` means no useful task-specific edit where one is needed; `1` means a partial benefit with an important opportunity still missing; `2` means the task's stated friction is addressed proportionately. For the no-op control and other already complete tasks, justified restraint earns `2`; do not demand added steps. Do not reward length, a generic checklist or unrequested sophistication.
4. **Language and notes — pass/fail.** Check instruction language, requested answer language and UI notes language independently. Verify explicit versus inferred language classification. Every claimed improvement must be visible in the copied prompt, and every assumption must be a genuinely new choice affecting execution and present in that prompt. Missing sources, placeholders and explicit requirements are not assumptions. Unchanged output must not claim a nonexistent edit.
5. **Direct usability and scope — pass/fail.** The result must be a reusable task prompt, not the task answer, a request to optimize the request again, or redundant original instructions appended as a second active task. Necessary quoted source data is different from a redundant instruction wrapper. Internal verification must not create commentary after JSON-only, code-only or sentence-limited answers.

A case passes semantic acceptance only when all pass/fail checks pass and task value is `2`. Record a value-only shortfall separately from a harmful fidelity failure: a faithful paraphrase may remain usable while missing this corpus's intended operational benefit. Do not average a lost prohibition or invented requirement into a passing score.

Record a brief reason and the exact offending sentence for every failure. Mark connection failures, timeouts, unusable JSON and unrun cases as **inconclusive/unavailable**, not as semantic passes or model-quality failures. `HTTP 200`, schema validity and literal checks are separate mechanical results, not the semantic verdict. A returned `modelReview.status: "approved"` is an automated model judgment, not this independent review: the same provider can approve its own material mistakes, so apply the full rubric to approved outputs as well. The suite passes only when every case has a completed, independently reviewed passing result for each configuration claimed to be supported. One batch does not establish stability across runs, models or source languages; report its provider/model identifier, backend version, date, instruction language, notes language, reviewed counts and unresolved cases.

## Mechanical literal calibration

The no-op source asks for a Friday reminder, but it does not require the English spelling `Friday` inside the edited instructions. Traditional Chinese instruction mode may correctly write `星期五` or `週五` while still requesting an English final reminder. On 2026-10-19 the corpus removed `Friday` from this case's mechanical `literals` list; the source prompt and semantic requirements are unchanged. Earlier baseline/updated raw records remain unchanged. Any historical missing-`Friday` literal result for a correct translated weekday is a mechanical false positive, not lost meaning. The independent updated Traditional Chinese no-op review already treated that output as a semantic pass; no historical manual score was revised.

### Compatible conflict-response format

The conflict fixture's source says to output only JSON with a `notice` field. Its impossible character bounds cannot both be met, but its response-wide JSON requirement can still hold for a short conflict statement. On 2026-10-19 the corpus corrected an overstrict derived criterion that had required discarding JSON altogether. A valid conflict-only instruction can return `{"notice":"a brief Traditional Chinese conflict statement"}`; it must not reactivate the impossible drafting command or the incompatible character bounds. A response format is dropped only when that format is itself incompatible with the necessary limitation response, not merely because another requirement conflicts.

This calibration does not change the synthetic source prompt or excuse an active impossible imperative followed by a later disclaimer. Historical raw results and original manual reviews remain intact; their review addenda state the consequences of the corrected criterion. In particular, a previous plain-text conflict fallback that discards the compatible JSON format is no longer a full fidelity pass under the calibrated rubric.

## Reviewer calibration examples

These candidates are hand-written review examples, **not model-generated results**.

### Faithful translation with little operational improvement

For `quality-coding-zh-csv-behavior`, consider:

> Fix the CSV deduplication bug in the current project. Treat email values case-insensitively, keep the first row, and preserve row order and the header. Inspect the current implementation before changing it, then confirm that it is fixed. Explain briefly in Traditional Chinese.

The original requirements are mostly preserved. However, “confirm that it is fixed” remains vague: the candidate does not connect verification to mixed-case duplicates, distinct addresses, first-row retention, order and header. It should not receive full task-value credit or claim that those checks were made explicit. This is a value shortfall, not proof that a downstream model would fail.

A stronger edit can direct the future agent to use a focused check of those behaviors, without prescribing a new language, parser, dependency or test framework. It must keep access-related questions conditional and allow truthful reports after execution.

### Lost condition hidden by fluent wording

For `quality-analysis-mixed-insufficient-criteria`, consider:

> Compare Aster Notes and Juno Notes. If product names or requirements are absent, ask for them first. Otherwise, compare their fit to the company's retention rule in a short Korean table and recommend one. Aster Notes permits retention-day configuration; Juno Notes deletes at 30 days. Do not invent product facts.

This is a fidelity/dependency failure. Names, facts and a requirement are already present, so its “otherwise” path proceeds despite the company rule being unknown. The original also requires a question when supplied criteria are insufficient. Retaining the words “do not invent” does not restore that missing condition. A correct prompt must wait for the decision-critical retention rule, then allow comparison and recommendation.

## Reproduce mechanical checks without provider calls

From the repository root:

```sh
npm run check
npm test
npm run check:docs

# Parse the new corpus; this checks JSON only, not semantic quality.
node --input-type=module -e 'import fs from "node:fs"; const cases = JSON.parse(fs.readFileSync("tests/fixtures/prompt-quality.json", "utf8")); console.log(`${cases.length} synthetic cases parsed`);'
```

The corpus is not executed by the unit test command merely because it exists. Unit tests use controlled services or mock results; those can verify policy wiring and response handling, not a live model's semantic compliance. Do not label these checks as live acceptance.

## Run an explicit live evaluation when authorized

Configure a real model using the [setup instructions](../README.md), then start the local browser/API service with `npm start` in a separate terminal. Its sample configuration uses port `3000`; adjust `--url` to the actual configured loopback port. The runner rejects mock mode and non-loopback URLs. It calls the configured provider and can incur charges; the following commands are instructions for an intentional future run, not evidence that one has happened.

Start with one or two cases, review them and confirm service availability before running the full corpus:

```sh
node scripts/verify-multilingual.js --live \
  --url http://127.0.0.1:3000 \
  --cases tests/fixtures/prompt-quality.json \
  --ids quality-coding-zh-csv-behavior,quality-analysis-mixed-insufficient-criteria \
  --prompt-language en --notes-language en \
  --output artifacts/prompt-quality/smoke-en.json
```

After reviewing the smoke results, a complete English-instruction batch is:

```sh
node scripts/verify-multilingual.js --live \
  --url http://127.0.0.1:3000 \
  --cases tests/fixtures/prompt-quality.json \
  --prompt-language en --notes-language en \
  --output artifacts/prompt-quality/all-en.json
```

Review Traditional Chinese instruction mode independently. Choosing Japanese notes deliberately checks that notes do not change task-answer or instruction language:

```sh
node scripts/verify-multilingual.js --live \
  --url http://127.0.0.1:3000 \
  --cases tests/fixtures/prompt-quality.json \
  --prompt-language zh-Hant --notes-language ja \
  --output artifacts/prompt-quality/all-zh-Hant-notes-ja.json
```

Other supported notes preferences are `zh-TW` and `ko`; evaluate them explicitly before claiming equivalent behavior. The runner writes each completed case sequentially and, by default, stops after two consecutive request/service failures. `--max-consecutive-failures` accepts an explicit limit from 1 to 10. Stopped runs preserve partial records, a stop reason, totals and the IDs not attempted; neither a stopped run nor unattempted cases count as passed. You can also interrupt repeated failures to avoid unnecessary paid requests. Literal-check failures are recorded separately and do not by themselves trigger the consecutive request-failure stop. Its zero exit status covers request validity and literal checks only. Apply the human rubric separately and keep conclusions tied to the tested configuration. Actual downstream task performance remains a separate evaluation.
