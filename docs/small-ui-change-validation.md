# Small UI changes: fast feedback, bounded release debugging

Use this checklist for a scoped Desktop/plugin UI change. It orders existing checks
by cost; it does **not** add universal gates for every minor edit, remove required
CI, authorize a release-channel change, or permit local installation/restart.

## Before spending a packaged run

1. **Bound the change.** Record the owning issue, source commit, intended behavior,
   retained behavior and acceptance scope. Inspect actual public renderer contracts;
   do not turn a small layout fix into unrelated Core/version work.
2. **Get cheap feedback first.** Run whitespace/lint/types and focused unit tests,
   then actual source-component/renderer browser tests. Include the fixture itself
   and its actual serialization/loading path. When local dependencies are demonstrably
   unavailable, use the approved frozen-CI equivalent—no npm retry loop, dependency
   copies or reconstructed tree. Retain normal hooks and required final CI.
3. **Exercise actual navigation and layout.** Cover restored/collapsed sidebars and
   cold versus materialized Session titles. Use unique public ARIA/role selectors;
   verify identity/count instead of hiding ambiguity with `.first()`. A Slot wrapper
   with `display: contents` has no physical bounding box: resolve and assert the real
   layout owner. Check retained empty Slot anchors as well as populated content so
   an empty anchor cannot reserve an unwanted gap. Synthetic DOM is not the actual
   InputBar/StatsPills/Slot contract.
4. **Define the observation lifetime.** Collect **all** errors through the final
   awaited interaction/check, remove only owned named listeners, and seal an owned
   immutable snapshot before deliberate teardown. Test both in-scope rejection and
   post-scope immutability. Never clear/filter errors to obtain a passing receipt.
5. **Package a stable candidate.** Keep source-browser observations, packaged
   acceptance, formal publication and local activation distinct. Validate same-run
   receipt equality and source/runtime/Client identities. Authenticate a formal
   file's original bytes, but validate fresh dynamic geometry semantically—not by
   comparing pixel hashes against another run. See the [composer evidence contract](native-composer-acceptance-preparation.md).

## Diagnose before retrying

For each failed expensive run, retain commit, run/attempt/job, failed step, original
logs/artifacts and the smallest relevant observation. Do not relabel a failed run
when a later run passes.

| Evidence/classification | Next bounded action | Not justified |
|---|---|---|
| Lint/type/code or deterministic assertion failure | Fix source; rerun the cheap owning checks; qualify the new exact commit | Rebuild unchanged source hoping it passes; skip the test |
| Fixture navigation/selector/geometry failure | Capture relevant DOM, selector count, state and screenshot; inspect the real owner/semantics | `.first()`, guessed parent rectangles, timeout inflation |
| Receipt disagreement or observer mutation | Preserve both original receipts; repair ownership/lifetime with a regression; keep strict equality | Editing old artifacts, filtering error text, calling green CI acceptance |
| Evidenced transient transport/environment or unrelated existing-test failure | Diagnose and record why it is transient; at most **one bounded failed-job-only retry** may be appropriate on the **same source and bytes**, using supported workflow behavior | Blind full-build loop, unrelated source edits, removal of required checks |
| Repeated same failure, unknown cause, or HTTP 403 | Stop retries; capture targeted approved DOM/header diagnostics or concrete recovery evidence first | Inferring rate limiting from 403, claiming authenticated CLI success proves anonymous-runner recovery |

An unrelated existing test is still a required failure: isolate its cause, preserve
its original result, and fix or qualify it through the owning process. A retry is
not evidence of the first failure's cause. Repetition needs diagnostics, not a second
blind retry or a larger timeout.

For anonymous acquisition failures, keep diagnostics on the actual failing path:
only the smallest approved sanitized route/status and allowlisted safe header facts.
Do not retain secrets, signed URL queries, response bodies or arbitrary raw errors;
do not inject operator authentication into anonymous acceptance, change credentials,
or weaken TLS, integrity, registry or approval policy. Diagnose first, then choose
an evidence-supported remedy within authorization.

## Release and artifact reuse boundary

- Final publication uses the established Desktop installer channel from the **exact
  qualified merged source**. Run all required release gates, including independent
  canary scopes; one passing main receipt cannot substitute for a failed canary.
- Independently verify source/tag/tree, full asset inventory, identities, sizes,
  checksums, provenance and internally consistent acceptance. Green workflow alone
  is insufficient. A rehearsal success is not a formal Release or installed upgrade.
- **Future design, not an implemented optimization:** splitting expensive build and
  acceptance stages or reusing a packaged artifact may reduce rework. Reuse is allowed
  only through an established or separately reviewed workflow that binds exact
  source/runtime/lockfile/hash/provenance and reruns the same required gates. This
  runbook implements no cache, resume, artifact-reuse or release shortcut; never
  relabel an older artifact as a newer candidate.
- Published is not installed. Stage and report verified artifacts; installation,
  activation, Session interruption and restart require their separate authorization.
  A stage-only choice leaves live-account UI validation deferred, not silently done.

## Compact evidence anchors and ownership lesson

[Desktop PR #110](https://github.com/cloga/deepseek-harness/pull/110) exposed avoidable
fixture/lint iterations: navigation assumptions, layout-neutral/empty Slot anchors,
and aliased observer arrays should have been caught in cheaper layers. These were
engineering/fixture shortcomings—not solely external failures and not the user's fault.

- [CI `35635724164` attempt 1](https://github.com/cloga/deepseek-harness/actions/runs/35635724164/attempts/1)
  failed; [attempt 2](https://github.com/cloga/deepseek-harness/actions/runs/35635724164/attempts/2)
  passed at the same `0456147862aeee1bc1a7f317f54f99d1a5101f02` source. Preserve both;
  a later pass alone does not diagnose the earlier failure.
- [Rehearsal `35641275751`](https://github.com/cloga/deepseek-harness/actions/runs/35641275751)
  passed and independently consistent actual producer→Ops acceptance checks passed.
  That does not retroactively qualify the earlier [contradictory green rehearsal](native-composer-acceptance-preparation.md#practice-seal-observation-evidence-before-owned-shutdown),
  whose individual shutdown-message origins were not timestamped.
- [Formal run `35644657949`](https://github.com/cloga/deepseek-harness/actions/runs/35644657949)
  at merged source `b1bf04d0faf455fe208dabbe267fd44fa95078b8` passed main acceptance
  but failed required observer-canary acquisition with HTTP 403 before observation;
  publication/discovery were skipped. Keep it failed, not a standalone release proof.
  [PR #112](https://github.com/cloga/deepseek-harness/pull/112) scopes the approved
  sanitized acquisition diagnostic without changing authentication or download policy.

Source fixes and independently scoped diagnostics require fresh receipts at their
actual identities. Durable documentation can ship through its own reviewed Ops PR
without waiting for or inventing a product release; later baseline repins still need
real verified assets.
