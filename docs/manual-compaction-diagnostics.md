# Manual compaction: stale model routes and truncated summaries

Use this guide when manual `/compact` fails again after a UI model change, or
reports that it "could not produce useful summary". Diagnose the summary call
before attributing the failure to conversation input size or changing limits.
This is read-only troubleshooting, not an installation or recovery command.

## Verified scope, not a fixed-version claim

The behavior below was verified in inspected Core `0.1.6-alpha.1` and exact
official `0.1.6-alpha.2` commit
`ddefc45fbc7f8e46dd73185e68295696d1297887`. It is not a claim about every past or
future Core version. The owning investigation is
[Core issue #86](https://github.com/cloga/deepseek-harness/issues/86).
At this documentation checkpoint, its Core repair is uncommitted and under
qualification, **not shipped**; no fixed version is established here.

The verified recurrence had two manual summary failures classified as output
`MAX_TOKENS`, not provider input overflow. That classification is specific to
those failures; diagnose another incident from its own evidence. Private Session
identifiers, request contents, paths and extraction data are intentionally omitted.

## Why a new selection can still summarize on the old route

In the inspected Core, the default manual summarizer resolves its route in this
order:

1. An explicit configured summarization target, when present.
2. The last durable request header's configuration.
3. Seed `AgentOptions` when that header is absent.

A UI model selection is not itself a new conversation request/header. If the
selection changes after the last durable header and manual compaction runs before
a new header is written, the summary can still use the old route. Record both
selection and request/header chronology; do not equate the model currently shown
in the UI with the route used by the auxiliary summary call. This explains the
recurrence, but is not a recommendation to send a synthetic request merely to
change the header.

## Classify the evidence before choosing a remedy

| Observation | Supported interpretation | Do not infer |
|---|---|---|
| Core summary termination is `finish.kind = max-tokens`, or its owned diagnostic says "summarization truncated at the token cap (incomplete checkpoint)" | The summary output was truncated at its output limit | An arbitrary provider error/abort with code `MAX_TOKENS` alone proves truncation; input overflow, exact failed prompt size, or hidden reasoning-token consumption |
| Provider explicitly reports input/context overflow | Investigate that request's input budget and route | Every compaction failure has the same cause |
| Generic "could not produce useful summary" message | Compaction did not yield an accepted usable result; inspect its underlying error | A semantic-quality evaluator rejected an otherwise complete summary |
| `compactionRetries` is configured | It repeats **successful reductions** that still leave context above the threshold | Failed or truncated summaries are automatically retried or rescued |
| A package is published or its version is present on disk | Publication or installed-file evidence only | That code is loaded in the running Host or used by this summary |
| Frozen dependencies are unavailable during qualification | A separate build/test verification condition; follow [CI-first qualification](core-upgrade.md#remote-qualification-checklist) for expected local npm restrictions, which alone do not block release | Evidence of the cause of a live compaction failure, or permission to ignore required CI failures |

Failing summary requests do not carry full independent request/usage records in
the inspected evidence. Nearby ordinary-request token counts are not measurements
of the failed summary prompt. Missing usage is unknown, not zero: do not derive
hidden reasoning consumption, exact prompt size or a safe replacement output cap
from the generic message or a neighboring request.

## Safe read-only diagnostic sequence

1. **Bound the runtime claim.** Record the Core/provider version and source identity
   that can actually be established. Keep published, installed and loaded evidence
   separate; if loaded activation cannot be attested, say so. Do not restart to
   make an assumed version match the files on disk.
2. **Identify the highest canonical Session format generation.** Read the relevant
   version's persistence contract first. Use a matching read-only reader; official
   in-memory logical migration is acceptable, but do not publish migrated
   descendants, repair/rewrite source logs or replay/import live history. If the
   highest canonical generation is unsupported or corrupt, report that evidence
   gap; do not downgrade to an older generation or stale export as current state,
   or treat a parse failure as a compaction failure.
3. **Extract only selected leaves.** Inspect the manual compaction event, its
   underlying error classification/message and available route metadata, plus the
   immediately relevant selection and durable request/header records. Keep raw
   prompts, responses, credentials and whole Session objects out of reports. No
   private log-extraction scripts or datasets belong in this repository.
4. **Correlate before compaction.** Order the last durable request/header, later
   explicit model selection(s), and the manual compaction attempt. Check whether
   an explicit summarization target overrides the default. Record the route as
   observed or inferred from the verified precedence, and label which it is;
   missing failed-call metadata must stay missing.
5. **Separate result from hypothesis.** Report output truncation, explicit input
   overflow, another classified error, or an unclassified failure. Note absent
   failed-call usage and any independent dependency/qualification blocker. Do not
   silently substitute ordinary-request usage or assume the wrapper error proves
   semantic rejection.
6. **Preserve the original history and stop at the evidence boundary.** Do not
   delete headers, edit Session state, accept partial summaries as checkpoints,
   repeatedly retry without new evidence, or prescribe ad hoc live configuration
   edits/blindly higher caps. A repair must be qualified in its owning repository;
   this guide authorizes no installation, automatic restart or interruption of
   another Session. Follow the existing [restart-safety rules](../AGENTS.md#restart-and-browser-verification-safety).

A portable incident note needs only: inspected version/source scope; what is known
about loaded activation; canonical format/generation selection method; relative
selection/header/compaction ordering; observed versus inferred summary route;
selected error classification; missing usage/evidence; and repair tracking status.
Keep original evidence private and unchanged. Do not publish Session IDs, local
paths, employer/device identifiers or request bodies.

## What the Copilot alpha.28 fix does—and does not—cover

[Copilot PR #147](https://github.com/cloga/dsh-github-copilot/pull/147) and
`dsh-github-copilot@0.4.0-alpha.28` address **provider-scoped budgeting and summary
policy**. They are not a generic Core manual-model-selection fix, a rescue for
truncated summary output, or a guarantee of chunked rescue for oversized history.
Output truncation remains failure, not a partial successful checkpoint. For its
independently verified publication evidence, see the
[alpha.28 publication checkpoint](core-016a2-delivery.md#copilot-alpha28-publication-checkpoint).
Publication does not establish loaded activation, and recurrence alone does not
show that provider-budget protection regressed.

Track Core route-selection/truncation diagnostics through issue #86 separately
from provider publication and dependency qualification. This page changes no
deployment lock, version pin, supported baseline or live configuration.
