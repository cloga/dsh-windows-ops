# UI fixture appendix: native composer and evidence snapshots

The operational entrypoint is the maintained [bounded release-debugging checklist](core-upgrade.md#bounded-release-debugging).
That guide owns scope, check ordering, retry classification, diagnostics, artifact
reuse and final release/activation policy. This subordinate appendix adds concrete
UI fixture checks only; it introduces no competing release process or new universal gate.

## Actual renderer fixture checklist

- **Navigation and identity:** cover restored/collapsed sidebars and cold versus
  materialized Session titles. Use unique public ARIA/role selectors; verify
  identity/count instead of concealing ambiguity with `.first()`. Check the fixture's
  actual loading/serialization path, not only extracted callbacks or synthetic DOM.
- **Physical layout owner:** a Slot wrapper using `display: contents` has no physical
  bounding box. Resolve and assert the real layout owner rather than a guessed parent.
  Cover retained empty Slot anchors as well as populated controls so an empty anchor
  cannot reserve an unwanted gap. Exercise actual InputBar/StatsPills/Slot components,
  including wide same-row placement and bounded, non-overlapping narrow wrapping.
- **Observation lifetime:** retain **every** error through the final awaited
  interaction/check. Remove only owned named listeners and seal an owned immutable
  snapshot before deliberate teardown. Test in-scope failure rejection, failed
  inspection cleanup, preservation of unrelated listeners and post-scope immutability.
  Never clear/filter errors to manufacture acceptance.
- **Same-run evidence:** bind source/runtime/Client identities and require main and
  standalone receipts to agree within the same run. Authenticate original formal
  bytes, but validate fresh dynamic geometry semantically—not by comparing pixel
  hashes against another run. Preserve all original contradictory receipts. See the
  [composer evidence contract and observer regression](native-composer-acceptance-preparation.md).

Use the canonical guide's [failure triage](core-upgrade.md#triage-an-entire-attempt-before-retrying)
when these checks fail. No artifact-reuse/resume optimization is implemented by this
appendix; any such future design requires the review and bindings in the canonical guide.

## Compact evidence anchors and ownership lesson

[Desktop PR #110](https://github.com/cloga/deepseek-harness/pull/110) exposed avoidable
fixture/lint iterations: navigation assumptions, layout-neutral/empty Slot anchors
and aliased observer arrays belonged in cheaper faithful checks. These were
engineering/fixture shortcomings—not solely external failures or the user's fault.

- [CI `35635724164` attempt 1](https://github.com/cloga/deepseek-harness/actions/runs/35635724164/attempts/1)
  failed; [attempt 2](https://github.com/cloga/deepseek-harness/actions/runs/35635724164/attempts/2)
  passed at the same `0456147862aeee1bc1a7f317f54f99d1a5101f02` source. Both remain
  evidence; a later pass alone does not establish the earlier failure's cause.
- [Rehearsal `35641275751`](https://github.com/cloga/deepseek-harness/actions/runs/35641275751)
  and independent actual producer→Ops checks passed. This does not retroactively
  qualify the earlier [contradictory green rehearsal](native-composer-acceptance-preparation.md#practice-seal-observation-evidence-before-owned-shutdown),
  whose individual shutdown-message origins were not timestamped.
- [Formal run `35644657949`](https://github.com/cloga/deepseek-harness/actions/runs/35644657949),
  source `b1bf04d0faf455fe208dabbe267fd44fa95078b8`, passed main acceptance but failed
  required observer-canary acquisition with HTTP 403 before observation. Publication
  and discovery were skipped; it remains a failed run, not standalone release proof.
  [PR #112](https://github.com/cloga/deepseek-harness/pull/112) scopes an approved
  sanitized diagnostic, not an authentication/download-policy change. A 403 alone
  does not establish rate limiting or recovery of an anonymous hosted request.

These are fixed evidence anchors, not a rolling execution log. Publication, later
baseline repins and local activation retain the canonical guide's separate requirements.
