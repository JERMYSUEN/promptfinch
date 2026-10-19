# Prompt editing and fidelity-review verification — 2026-10-19

This record covers the v1.3.0 changes. Controlled tests, provider approval, literal checks and semantic review are separate evidence. The [16-case corpus](../tests/fixtures/prompt-quality.json) and [rubric](prompt-quality-rubric.md) define the scope; the accompanying [synthetic records](prompt-quality-results.json) retain the comparison and unsuccessful experiments.

## Changes

- One editing policy for complete English and Traditional Chinese task prompts, replacing the live Traditional Chinese original-instruction wrapper.
- Explicit branches for absent or insufficient inputs, unavailable tools, conflicts, no-question restrictions and compatible fallback formats. Editor restrictions do not prevent the future executor from performing or truthfully reporting the task.
- Empty improvement lists for a no-op, with neutral localized interface text. Required code/data remains in the complete prompt; explanations remain separate from copied text.
- Conservative Unicode literal repairs for contractions, repeated copies, canonical substring false-ambiguity, quoting and code fences, shared by both instruction modes.
- A same-provider, separate-context review and at most one revision, with strict verdict validation, bounded calls, a shared deadline/cancellation signal, safe errors and an explicit opt-in. It is disabled by default.
- A sequential evaluator that stops after repeated request failures, preserves unattempted cases and never treats mechanical success as semantic acceptance.

## Controlled checks

The final local source passed 131 Node tests, 12 Chrome browser workflow tests, 324 native Swift checks, syntax checks and validation of 28 README editions. These verify program contracts and mock interactions; they do not prove that a real model follows every editing instruction. The Unicode helper conservatively restores normalized copies of unambiguous quoted non-NFC source literals; it is not a general detector or repair system for all possible literal changes. Native package/archive validation and platform CI are separate release checks.

## Live experiment design

All inputs were newly authored synthetic cases. The configured model identifier remained `deepseek-flash`; the provider/key was unchanged. An isolated baseline host imported the optimizer from commit `d651ea761f7582477570d26ae28e8c7a774b4a09`, whose optimizer SHA-256 was `0b6005cfc20727063df36537c766e9a159c31b18c36a4ba369b459b9400758e3`. The later hosts imported each recorded candidate implementation before its requests started. The runner's local-source hash is not itself proof of deployment; those fields are preserved with that warning, including the baseline local hash that differs from its deliberately pinned server.

The experiment retained 76 workbench requests across baseline, policy-only, initial uncalibrated review and final calibrated review stages, plus six direct reviewer-calibration requests. Source prompts were unchanged across comparisons. Six captured-candidate calibration requests tested reviewer rejection/approval without generating downstream artifacts. Workbench requests and provider calls are different counts because format retries and review/revision may make additional provider calls. Billing was not retrieved; no exact cost or token-saving claim is made.

Semantic inspection was performed by a separate Codex agent and checked against the source by the implementation agent. This is AI-assisted review, not a human-expert or native-speaker certification. Each stage is a limited sample, not a stable success-rate estimate. No downstream tasks were executed.

## Rubric corrections

Two overstrict derived checks were corrected transparently, without deleting source prompts or raw outputs. An English weekday can be translated into Traditional Chinese instructions when its meaning is preserved and no exact spelling was requested. A response-wide JSON format can remain valid for a conflict-only fallback; only impossible drafting/length commands must be inactive. Original review scores and explicit calibrated overrides are retained in the records. Comparisons must use the calibrated criteria consistently, including their unfavorable effect on the baseline.

## Observations and remaining limits

The following strict counts apply the corrected criteria consistently. Strict acceptance includes faithful execution instructions, dependency handling, language/notes accuracy and directly usable output. Task-specific value is separately scored. These are individual samples of difficult cases, not measured product accuracy.

| Stage | Reviewed requests | Strict semantic passes | Notes |
| --- | ---: | ---: | --- |
| Baseline v1.2.0 | 20 | 10 | Historical score was 11; the compatible-JSON correction lowers it to 10. |
| Shared policy, without additional review | 20 | 11 | One historical literal-check failure was a translated weekday, not semantic loss. |
| Initial uncalibrated optional reviewer | 16 | 8 | The provider approved every returned candidate. |
| Calibrated optional reviewer | 20 | 11 | All 20 were provider-approved; four had a revision. |

The final optional-review run still contained two execution-core errors: lost supplied-but-insufficient criteria in an English comparison prompt, and a regressed missing-source/no-questions instruction in Traditional Chinese. Seven cases had language/notes defects, with overlapping categories. The six captured-candidate calibration verdicts matched five expected approvals/rejections, but individual criticism could still be wrong.

**Release decision:** extra review remains optional and disabled by default. The small comparison does not show a reliable overall gain sufficient to enable additional paid calls automatically. The shared policy, literal fixes, honest empty notes and regression tooling ship independently. There is no claim that all semantic problems are fixed.

Case-level findings, raw responses, original scores, calibrated overrides and record hashes are retained in the accompanying JSON. Program and provider-review success do not supersede those findings. The initial reviewer approved known faulty candidates; calibrated negative examples improved rejection of several errors, but did not establish universal fidelity. Remaining issues include assumptions that restate explicit requirements, editing notes that describe a prior draft rather than the original-to-final change, incomplete sufficiency conditions, and a missing-source case that still requires human inspection.

Important requests should still be compared with their source. `modelReview.status: "approved"` means that the configured model approved a candidate, not that the service independently proved it correct. A more reliable model, repeated independent samples, and downstream task-outcome evaluation remain separate follow-up work.

## Reproduction

Use the commands in the [rubric](prompt-quality-rubric.md). Live evaluation sends synthetic inputs to your configured provider and may incur charges. The default tests the editor without additional review. Set `LLM_QUALITY_REVIEW=true` explicitly to test the optional reviewer; `false` disables it. The recorded gated runs predate only the final default-off toggle, so the final source hash differs and that toggle was not retested with paid requests. Preserve partial runs and review every completed copied prompt and its notes, rather than counting HTTP responses.
