# Optional settings retirement and native composer acceptance preparation

Tracking: [Ops #217](https://github.com/cloga/dsh-windows-ops/issues/217).
This is version-independent verifier preparation against the inspected source-owned
producer in [Desktop draft PR #110](https://github.com/cloga/deepseek-harness/pull/110),
not promotion of a new Desktop/plugin version. Current deployment lock, catalog,
PowerShell pins and original formal evidence remain unchanged. No installer, Core,
profile, activation or restart is changed by this work.

## Explicit settings schema 3

`nativeProvisioning.settingsAcceptance.schemaVersion: 3` explicitly selects the
retirement contract. It retains the four existing initial/restart settings and
version-menu SHA-256 pins, to be filled only from independently authenticated
artifacts during a separate reviewed repin. Schema 2 and older evidence keep their
existing meanings; a filename or absent old control never selects schema 3.

The actual `copilot-settings-smoke.ts` producer reports `schemaVersion: 3`,
`accountViewLoaded`, `retiredModelRolesAbsent`, `searchProviderCatalogLoaded`,
`providerOnlySearchRouting`, `fallbackProviderLabel`, `registeredSearchProviders`,
and `realSearch`. The first five boolean observations must be exactly `true`, and
`realSearch` exactly `false`. Both phase objects must be equal, hash-bound, and
match the main receipt's **`settingsAcceptance` array**. Do not invent a top-level
`accountViewLoaded` field. Retired `modelRolesViewLoaded` and
`currentWorkspaceReadOnly` claims do not belong to schema 3. Version-menu, signed-out
usage and existing positive usage gates remain separate and required when selected.

## Optional native composer proof

Only explicit `nativeProvisioning.nativeComposerAcceptance` enables this additional
ordinary-acceptance gate. Its minimal contract is:

- numeric `schemaVersion: 1`;
- `sha256`: authenticated formal `native-composer-geometry.json` raw-file digest;
- `installedClientSha256`: authenticated released Client bytes, matching the existing
  `usagePositiveAcceptance` proof. The fresh source observer already independently
  hashes the actual isolated profile's `lib/client.js` for that proof.

No new formal digest is provided or invented by this preparation. The gate requires
settings schema 3, signed-out usage schema 1 and the existing positive proof. It does
not reinterpret alpha.2 combined/dual evidence; those adapters remain intact.
An absent native-composer proof leaves the historical path unchanged. A future target
can require the new proof only when its real release is authenticated and repinned.

The inspected producer files are `apps/desktop/tests/fixtures/copilot-release-smoke.ts`,
`native-composer-geometry.ts`, `seed-native-composer.mjs`, and
`copilot-settings-smoke.ts`. After initial/restart signed-out and existing positive
acceptance, the producer starts a third isolated application phase. A fresh
nonce-authorized home is seeded through packaged public JSONL Session persistence
and WorkspaceRegistry, not a real account or model request. Native InputBar/StatsPills
and the released Client render synthetic settled history/token counts; the real
signed-out Host supplies quota state without credentials.

The actual native record contains:

- schema 1; `scope: actual-packaged-native-composer-and-released-client`;
- exact `sourceCommit` shared with main acceptance, `runtimeSha256`, complete
  `pluginSource`, and `installedClientSha256`;
- `sessionHistory: synthetic-persisted-in-isolated-home` and
  `quota: signed-out-host-response-no-credentials`;
- exactly two ordered geometry cases at numeric viewport widths **1280 and 400**;
  each contains `dock`, `time`, `usage`, `copilot` rectangles and
  `nativeStyle`/`copilotStyle` (`fontSize`, `lineHeight`, `color`);
- `nativeDialogs.time` and `.usage`, each with exactly true observed `opened`,
  `closedOnEscape`, `focusReturned`;
- `copilotDialog` with exactly true `signedOutObserved`/`focusReturned` and numeric
  zero `sessionCreditsCount`, `resetCount`, `epochTextCount`;
- empty `rendererErrors`, false `realModelRound` and false `realOAuth`.

The verifier checks finite positive dimensions and finite bounds, horizontal dock
and viewport containment, non-overlap, and wide-layout same-row placement with the
Copilot control after native Cache hit. Narrow wrapping is allowed without overlap
or horizontal overflow. Pixel font size/line height and nonempty text color must
match the native control. Lifecycle types are exact, not truthy coercions. The record
must match this run's main `nativeComposer`, with unique ordered restart-close,
native-seed and native-close timeline observations.

## Formal hashes are not fresh pixel equality

Formal acceptance authenticates the exact original geometry file using `sha256`.
A **fresh run does not compare its geometry file hash or rectangles to another run**.
It verifies the new file's semantic constraints, immutable source/runtime/Client
bindings and same-run main-receipt correlation instead. Coordinates and matching
computed styles may legitimately differ. Deterministic settings/menu files retain
their existing hash gates. Tests prove both valid cross-run geometry drift and rejection
of tampering, identity mismatch, numeric/boolean type errors, overlap, overflow,
incorrect typography, dialog failures, epoch text and ordering failures.

Tests use temporary synthetic/rehashed data copies, never fabricated published
artifacts. The existing native qualification summary remains schema 1 with its
original fields; no geometry/role-retirement success flags are added. Source-owned
geometry acceptance is not live quota, real Session billing, OAuth/model/search,
installer-upgrade or local activation proof. All future pins, hosted native qualification
and merge remain separate parent-owned work after authenticated assets arrive.

## Practice: seal observation evidence before owned shutdown

A green workflow is not sufficient acceptance. [Rehearsal `35631408693`](https://github.com/cloga/deepseek-harness/actions/runs/35631408693),
source `c912a01bf123d456bf64d5b9159cf1c4a3199595`, passed its packaged native
wide/narrow/dialog observations, but independent review rejected the authenticated
receipts: standalone `native-composer-geometry.json` had `rendererErrors: []`, while
main `acceptance.json.nativeComposer.rendererErrors` contained five later errors.
Anonymous listeners still referenced one mutable array across the first serialization
and the awaited owned `app.close()`, so the second serialization recorded different
contents. The same-run equality guard correctly failed despite workflow success.
Event timestamps were not retained: individual shutdown-message origins, or whether
each message was caused by teardown, are **not** established by this evidence.

The source repair at [`0456147862aeee1bc1a7f317f54f99d1a5101f02`](https://github.com/cloga/deepseek-harness/commit/0456147862aeee1bc1a7f317f54f99d1a5101f02)
uses an explicit observation boundary covering interactions and final receipt checks,
named callbacks removed with owner-specific cleanup, and an immutable owned snapshot
before shutdown. Its regression coverage preserves every page/console error delivered
inside that scope (including the same transport-error text), rejects failed inspection,
and verifies that later events cannot mutate the snapshot or remove unrelated listeners.
Do not filter generic error strings, clear observations to obtain success, or weaken
strict same-run equality. Source repair is not fresh packaged qualification.

Keep the old artifacts unchanged: they cannot be retroactively edited or requalified.
Require complete, independently authenticated acceptance from the corrected exact
source before promotion; rehearsal publication remains disabled and later formal
release verification is still a prerequisite. This lesson changes no Ops code, pins,
artifact bytes, test expectations or local installation/activation policy.

Preparation checks (no dependency installation):

```text
node tools/validate-repository-content.mjs
node tools/validate-plugin-catalog.mjs
node --test tests/native-desktop-acceptance.test.mjs tests/native-asar-release-smoke.test.mjs tests/native-packaged-evidence.test.mjs
```

README entry points are intentionally unchanged: this unselected internal adapter
changes neither the current supported target nor user commands. A real target repin
must synchronize the full deployment/docs contract through its own reviewed evidence.
