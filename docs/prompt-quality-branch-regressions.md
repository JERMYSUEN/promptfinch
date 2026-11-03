# Execution-branch and language regression supplement

The [eight synthetic cases](../tests/fixtures/prompt-quality-branch-regressions.json) target failures documented in the [historical verification report](prompt-quality-verification.md). The first two requests are copied exactly from the original corpus. The remaining six are controls: stronger blocking rules must not prevent a supported task or erase an explicit fallback. All names, sources and product facts are synthetic.

The candidate policy distinguishes available information from information sufficient for the actual decision. It also tells the reviewer to accept necessary limitation notices, and tells a revision to correct discrepancies against the original request rather than blindly following reviewer suggestions. UI notes must describe the original-to-final change. Review remains optional and disabled by default.

The fixtures and controlled-provider tests establish corpus integrity and request-context isolation. They do not establish that a live model follows these policies, that review improves quality, or that the final task answer improves. Keep results tied to the exact tested source, provider configuration and language settings. This document defines the checks; use an independently reviewed live report for acceptance claims.

## Cases and acceptance checks

Apply all five dimensions in the [main rubric](prompt-quality-rubric.md#review-procedure-and-pass-criteria) to the complete source, copied prompt and notes. The following checks add branch-specific requirements.

| Case ID | Decisive check |
| --- | --- |
| `branch-mixed-insufficient-criteria` | Product names and facts are supplied, but the company retention rule is unknown. Ask only for the needed rule and wait before the dependent comparison or recommendation. Once sufficient criteria are available, allow the short Korean table and one reasoned choice. |
| `branch-missing-source-no-questions` | No minutes are supplied and questions are forbidden. Direct a brief Traditional Chinese limitation notice without inventing minutes, asking for them, or retaining an unconditional summary command. The three-point summary format applies to the unavailable artifact, not automatically to the limitation notice. |
| `branch-sufficient-criteria-proceed-control` | All retention facts and the inclusive 14-day rule are supplied. Allow the future model to compare and choose. Do not force questions or invent a blocker, and do not perform the comparison during editing. |
| `branch-source-supplied-late-control` | The actual source appears after an outdated missing-source note. Preserve that complete source and allow its two-point Traditional Chinese summary. Do not invent names or dates, or replace the task with a missing-source notice. |
| `branch-missing-source-explicit-json-fallback` | Preserve the user's own missing-source fallback: JSON only, fixed keys `status` and `message`, `status` value `missing_source`, brief Korean message. Do not replace it with plain text, perform the fallback while editing, or treat the explicit Korean answer language as inferred. |
| `branch-code-template-no-questions-control` | An intentional reusable Python/CSV template needs no private CSV contents. Preserve both path placeholders, case-insensitive `email` deduplication, first-row retention, header/order, no questions and code-only task output. Do not invent a prose answer-language assumption. |
| `branch-explicit-language-not-assumption-control` | Korean is explicitly requested. Preserve the single friendly reminder sentence, tomorrow's meeting and no-heading/no-explanation format; do not write the reminder, add workflow, or list Korean as a new assumption. Minimal editing is sufficient. |
| `branch-inferred-language-source-exclusion-control` | The operative request is Spanish; its source data is English. Infer Spanish for the future one-sentence answer and state that choice in the prompt and assumptions. Keep the complete English source as data. Do not perform the summary during editing. |

For every case, instruction language and UI notes language remain separate from the future task's answer language. Improvements must describe visible original-to-final edits. Reject notes about fixing a prior draft, preserving an explicit language as an assumption, or an alleged change absent from the final prompt. Empty assumptions are valid when no new execution choice was made.

The fixture-integrity test checks the two historical sources byte-for-byte, verifies source literals originate in the request, and runs all eight sources through both instruction-language settings and all four notes-language settings. It sends no provider requests:

```sh
node --test tests/quality-branch-fixtures.test.js tests/quality-review.test.js tests/multilingual.test.js
```

## Live sampling

Use a configured local service, as described in the [main evaluation instructions](prompt-quality-rubric.md#run-an-explicit-live-evaluation-when-authorized). Adjust the loopback port below. Each optimization makes one provider call with review disabled; review can require up to four calls in total when it rejects and revises a candidate. Review-enabled samples must be recorded separately from the default configuration.

Start with the two historical failures:

```sh
node scripts/verify-multilingual.js --live \
  --url http://127.0.0.1:3000 \
  --cases tests/fixtures/prompt-quality-branch-regressions.json \
  --ids branch-mixed-insufficient-criteria,branch-missing-source-no-questions \
  --prompt-language en --notes-language ko \
  --output artifacts/prompt-quality/branch-smoke-en-ko.json
```

Review the complete outputs before running all eight cases. A second instruction/notes combination checks the branch rules independently from the language settings:

```sh
node scripts/verify-multilingual.js --live \
  --url http://127.0.0.1:3000 \
  --cases tests/fixtures/prompt-quality-branch-regressions.json \
  --prompt-language zh-Hant --notes-language ja \
  --output artifacts/prompt-quality/branch-all-zh-Hant-ja.json
```

Use new output paths for each run. Do not overwrite historical raw results or silently change their scores. Record which server source was loaded, review setting, model identifier, date, instruction and notes languages, completed/failed/unattempted counts and independent verdicts with offending text. HTTP success, literal presence, unit tests and automated approval remain distinct from semantic acceptance. Run both instruction languages and additional provider configurations before making broader claims; one eight-case sample does not prove stability or cross-language parity.

## Initial live sample: 2026-10-25

A bounded direct-adapter evaluation collected 12 synthetic samples from `deepseek-flash` at `api.deepseek.com`, using 24 provider calls. The first four cases were paired between baseline commit `e7c501aea8e0029a02a5d91694dc8a98d1fe1bc4` and the initial candidate, with review explicitly enabled. The last four cases tested only the candidate's default path, with review disabled. English instructions used Korean notes; Traditional Chinese instructions used Japanese notes. Each condition had one sample.

The recorded optimizer hashes were:

- Baseline: `240adc4a9a37b689982531dda61d356eff27c93d6ede134f15871df29b8a9cc2`.
- Initial candidate: `f72c3228390ea2b3cb3e26827e727cde7c1b15c8c197c447f90bfd0d15404b12`.

Independent full-output review found 2/4 strict passes in the paired baseline and 3/4 in the paired candidate. The four candidate default-path controls yielded 2/4 strict passes, making 5/8 for the candidate overall. These small counts describe this sample, not a quality-rate estimate. Two rejected results had only minor inaccurate editing notes; those are separated from harmful task-instruction failures.

The candidate retained the supplied-but-insufficient execution gate and the no-question missing-source notice in the reviewed samples. Remaining failures were:

- The Japanese CSV template returned Japanese operative instructions despite `promptLanguage=zh-Hant`. The code placeholders and no-question/code-only restrictions survived, but correct response metadata did not establish the instruction language.
- The Spanish operative request with English source data produced the correct copied prompt, but its notes falsely called the Spanish answer language explicit and omitted that inferred choice from `assumptions`.
- One candidate note claimed a relative instruction-position change that did not occur. A baseline note similarly claimed a one-paragraph layout absent from its output.

The CSV source lists the first row and header separately, while the candidate collapses them into “first row (header).” Interpreting the fixture's first-row retention check as first-occurrence retention for each duplicate group goes beyond what the Japanese source unambiguously states. That core item is recorded as inconclusive rather than treating an ambiguous source as a proven requirement. Seven candidate core-fidelity judgments passed and this one remains inconclusive; language and notes failures still prevent acceptance.

All eight reviewed samples received automated approval, yet three failed the independent strict checks: one baseline execution-gate/assumption error and two minor inaccurate-note cases. Review therefore remains optional and disabled by default. There is no evidence of downstream task improvement or stability across repeated runs. This sample applies only to the recorded hashes, not subsequent edits. Historical raw outputs and scores were not rewritten. Local raw evidence and detailed manual assessments are kept separately under ignored `artifacts/repair-2026-10-25/`; the summary here does not make those local files published release assets.

## Final-source sample: 2026-10-25

After the initial sample, the editing policy received an explicit final instruction-language contract, a distinction between explicit and inferred answer languages, and a rule against merging separately stated requirements without source support. The final optimizer SHA-256 is `497034f491a633d5c2175afc68970a3379f21ec47b402de3209db236a13c30a4`. Earlier samples do not validate this hash.

The same provider and model produced ten final-source samples in 16 provider calls. Eight repeated the initial candidate's conditions: the first four with review enabled, the last four with review disabled, alternating English instructions/Korean notes and Traditional Chinese instructions/Japanese notes. Two additional default-path controls used English instructions and English notes for the CSV and Spanish-request cases. They were not paired baseline comparisons. The initial and final batches together used 40 provider calls for 22 synthetic optimizations.

All ten final samples passed response-schema and checked-literal tests. Separate full-output semantic inspection by an analysis agent, outside the provider's automated reviewer, found five strict passes, four failures and one inconclusive result. This was not a blinded human study. A strict pass requires every applicable dimension to pass; HTTP success and metadata alone do not qualify.

| Conditions | Samples | Strict pass | Fail | Inconclusive |
| --- | --- | --- | --- | --- |
| Repeated, review enabled | 4 | 3 | 1 | 0 |
| Repeated, review disabled | 4 | 2 | 2 | 0 |
| Additional English/English, review disabled | 2 | 0 | 1 | 1 |
| Total | 10 | 5 | 4 | 1 |

The repeated eight conditions still yielded five strict passes, the same count as the initial candidate, with different failure types. These one-sample conditions do not establish improvement, stability, review benefit or language parity. Review-enabled and default-path aggregates use different requests and must not be compared as an estimate of review effectiveness.

| Dimension | Pass | Fail | Inconclusive |
| --- | --- | --- | --- |
| Core requirements | 7 | 2 | 1 |
| Execution branch | 10 | 0 | 0 |
| Prompt instruction language | 10 | 0 | 0 |
| Future task answer language | 8 | 2 | 0 |
| UI notes language | 9 | 1 | 0 |
| Notes describe actual edits | 9 | 1 | 0 |
| Assumptions | 7 | 3 | 0 |
| Direct usability and scope | 8 | 2 | 0 |

The remaining failures are concrete:

- The missing-minutes result retained a coherent no-question limitation branch, but one Japanese note began with an unquoted Chinese clause. Its failure concerns notes localization, not the copied prompt's execution branch. Automated review approved it.
- The CSV result with Traditional Chinese instructions added a requirement to use Japanese for code comments and messages. The original code-only request did not require that choice. Listing it as an assumption did not make the added restriction necessary.
- The Spanish-request result with Traditional Chinese instructions recognized Spanish in `assumptions`, but omitted it from the copied prompt. Its notes falsely claimed that the language was stated there. UI notes cannot restore instructions absent from the text the user copies.
- The English/English Spanish-request control produced a usable copied prompt specifying Spanish, but returned empty `assumptions` despite making an inferred answer-language choice. This is an assumption-recording failure, separated from harmful core instruction errors.

The English/English CSV control preserved the requested template, identifiers, placeholders, row order, no-question restriction and code-only output without adding a Japanese comment-language requirement. However, it still merged the separately listed first row and header as “first row (the header).” The source's first-row wording does not unambiguously establish first-occurrence retention for each duplicate group. That core item remains inconclusive; neither a full pass nor a proven loss of an explicit first-occurrence requirement is justified. Future unambiguous controls should be new versioned cases, not rewrites of this source or its raw evidence.

All four review-enabled final samples were approved; one still failed the independent notes-language check. Approval remains a fallible model verdict. The policy changes and all sampled instruction-language successes do not establish that semantic problems are resolved. A future language-contract revision could restate the code-only exception next to the final language decision, but this sample cannot show that paragraph caused the invented comment-language choice. Further changes should use broader, repeated evaluation rather than chase these ten outputs.

The raw final evidence SHA-256 is `b4201d1ca6cc68e2d4dea6c14492b95a99de28a8f07d5bf9e462850c282ae255`. Local `live-final.json` and `final-semantic-review.json` remain in the ignored artifact directory, with earlier evidence preserved. These direct-adapter experiments did not test HTTP/browser/native delivery, real OS selection, or downstream task results. The final source therefore has documented residual model limitations, not complete semantic acceptance.
