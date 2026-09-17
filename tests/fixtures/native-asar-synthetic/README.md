# Synthetic ASAR CHECK fixtures — not release acceptance

`app.asar` and its sidecar are generated **synthetic local negative/integrity data**.
They contain neither working app-boot/Cordis APIs nor a production isolation
policy. `identity.json` explicitly says `runtimeProof:false`. Passing their
header/sidecar tests is not DSH 0.1.6 compatibility or formal-release acceptance.
No lock-selected deployment artifact is replaced by these files.

Regenerate only using an existing source checkout's maintained writer:

```powershell
node tests/fixtures/native-asar-synthetic/build.mjs <source-checkout> <approved-private-temp-directory>
```

The writer is `@electron/asar@3.4.1` `createPackageWithOptions`, with
`unpack:'**/*.node'`; its source is the same pinned maintained package as the
Ops-owned reader. No tool/runtime installation or download is performed. The
`.node` fixture is plain inert synthetic text, not a native binary.

## Self-contained checks

```powershell
node --test tests/native-desktop-acceptance.test.mjs
```

These preserve legacy physical `.5` checks and test ASAR schema/header/sidecar,
path/reparse/executable preconditions, zero-child rejection, bounded child
protocol and sanitized diagnostics. Mocked child failures are explicitly named.
No mocked child success stands in for real resolver compatibility.

An explicit optional developer command tests the **actual existing Electron
carrier** only against these nonfunctional synthetic archives:

```powershell
node tests/native-asar-carrier-negative.mjs <exact-physical-existing-electron.exe> <approved-private-temp-directory>
```

Both arguments are required; missing arguments fail. Resolve an approved source
Electron locator to its physical path first (the source's `node_modules/electron`
may be a junction); do not `require('electron')`, install or download a carrier.
The script hashes and checks that exact ordinary EXE, uses only scrubbed Node
mode, 30-second child timeout, 16-KiB output cap and 512-MiB V8 heap cap. Only
Electron's observed ASAR `fs.Stats` deprecation (`DEP0180`) is disabled with a
fixed flag; other stderr is rejected, not relayed or silently accepted. It checks
that the complete synthetic tree fails for absent public APIs and that packed or
unpacked corruption fails before importing runtime code. It never boots Desktop,
Host, a composition, a Worker, provisioning, or any live profile.

## Required external real-runtime qualification (parent/release owner)

```powershell
node tests/native-asar-integration.mjs <external-real-fixture-input.json>
```

This is a separate, explicit integration entry, **not a skipped unit test**.
Omitting its input, passing synthetic fixtures, a failed resolver, or missing
public APIs fails with nonzero exit. Input is bounded to 1 MiB and shaped as:

```json
{
  "fixtureKind": "external-real-runtime",
  "lock": { "components": "THE COMPLETE REVIEWED LOCK OBJECT, not this placeholder" },
  "installRoot": "ABSOLUTE_PHYSICAL_ISOLATED_INSTALLED_LAYOUT",
  "dshHome": "ABSOLUTE_PHYSICAL_ISOLATED_FIXTURE_HOME",
  "diagnosticRoot": "ABSOLUTE_EXISTING_NON_SYNCED_PRIVATE_TEMP_DIRECTORY"
}
```

`fixtureKind` selects the integration route only; it is **not provenance**.
The entry checks the supplied lock's hashes, not the origin of that lock or
fixture. The parent must independently obtain/review the actual release lock,
installer digest, source/receipt identities and fixture provenance before
invocation. No synthetic label or boolean establishes formal release identity.

Supply all of the following from one actual release/rehearsal fixture:

- Exact locked installed Electron EXE and normal adjacent carrier dependencies.
  The EXE and audited installation/archive/sidecar paths must be ordinary
  physical paths without symlinks, junctions, UNC/device/ADS aliases. **Only the
  EXE is carrier-hash-attested** (`executableSha256`). Adjacent DLLs, snapshots
  and support files are not independently inventoried, path-checked or hashed
  by this implementation; their presence is needed for OS loading, not evidence
  of their identity. This is not whole-carrier attestation or an OS-enforced
  defense against a hostile concurrent installer.
- `resources/app.asar/dsh/desktop-runtime.json` selected by the lock, whose raw
  digest and `release.version` equal the reviewed lock descriptor and
  `releaseChannel.upstreamVersion`. Runtime descriptor `schemaVersion` is 1;
  nested `release.hostProtocolVersion` is 3.
  Include **every** real runtime file; do not materialize `resources/dsh` or
  manufacture a descriptor for an incomplete tree.
- Exact physical `app.asar.unpacked/dsh` backing set, equal to maintained-reader
  header unpack metadata; no missing, orphan, shadow, link or special entries.
  Sidecar entries outside this runtime scope fail closed.
- Real shipped public app-boot root exports `createProfileResolutionGeneration`,
  `resolveBundleDir`, `PluginPackages`; byte-attested Cordis and compatible
  native addon. No checkout/internal resolver subpath is used.
- The actual shipped `register-module-resolution-policy.mjs`, imported after
  all bytes are verified, before generation installation, with the exact
  validated runtime/profile argv and explicit fixture home. No permissive Ops
  replacement policy is supplied.
- The isolated, already-provisioned reserved profile: canonical plan/capability/
  helper bytes, exact release source/receipts/state, profile and plugin manifests,
  locked archive `.desktop-plugin-artifacts/<sha256>.tgz` and installed plugin
  package. Do not include credentials, `.env`, settings, user sessions or live
  profile data. Shared profile links are unnecessary; predecessor links are not
  changed. Do not install/provision from this CHECK command.

The public resolver is mounted in a bare Context with `{generation,
behavior:'enforce'}`. Required shared peers must have the exact attested runtime
root/version in generation and `packageOf`, then identical host/plugin entries
under **both** CJS and ESM conditions (`--experimental-import-meta-resolve`).
All mounted effects are disposed in `finally`; pre/post resolution snapshots
must match. Explicit `dshHome` binds both the generation and production policy;
no ambient DSH override or config/env loader is used.

This direct entry still does **not** prove a live Host/session/model round or
formal release acceptance. The manual bridge below combines it with the actual
source-owned initial/restart UI and ancestor-SDK-bait acceptance; its additional
Ops negatives are exactly descriptor-digest, version and absent-home **request
copies**. Private same-version shared targets, unresolved-peer failures, wrong
generation/custom-home routing, missing-addon/API failures and induced source
drift are **not covered by that manual summary**. Retain separately reviewed
source/unit evidence for those cases, or mark their genuine `.6` coverage pending;
neither inert fixtures nor legacy `.5` negatives establish it. The genuine
positive does exercise the shipped public `PluginPackages` native-addon path,
without an extra private API probe.

### `.6` receipt ownership and user-extra boundary

The `.6` checker accepts the source receipt store's `schemaVersion:1`, `receipts`
and complete one-to-one `owners` map (`user` or `release`). Required Copilot may
remain user-owned after an exact same-source reinstall: its locked source,
receipt/state, archive bytes, installed identity, enabled bundle and required
shared-peer proof remain mandatory. Off-plan **release-owned** receipts fail.
The `.5` physical checker retains its prior exact inventory behavior.

Absent legacy `owners` are inferred only in memory: default to user, assigning
release ownership only when the canonical active state plan hash, normalized
receipt and profile artifact spec agree. Incomplete evidence never grants
release ownership; it also cannot satisfy the required current baseline. CHECK
never migrates, writes, removes or reconstructs profile data.

Bundles must start with the built-in base/Web pair, contain valid unique names,
and keep required Copilot enabled somewhere in the tail. User tail order is
preserved when constructing the real public resolution generation. User-owned
verified receipts, exact registry dependencies, and source-snapshot metadata may
coexist. Their metadata must match the inspected source codec, but acceptance is
**not** a health/content proof: `userExtras.contentsAttested` remains `false`.
Receipt artifact dependency specs require ordinary backing-file presence, not
user-extra byte verification; source-snapshot dependency specs follow the source's
metadata-only branch and do not establish that the snapshot archive exists or is
healthy. Missing required Copilot bytes still fail full locked attestation.

The shared builtins-only helper bounds each of four metadata files to 4 MiB and
binds their raw hashes: `package.json`, `desktop-plugin-receipts.json`,
`desktop-plugin-provisioning-state.json`, and optional
`desktop-plugin-package-locks.json` (explicitly `null` when absent). Both outer
verification and inner Electron proof use the same ownership validation and
raw-hash/presence aggregate, plus canonical plan identity. Rereads and the
post-disposal check reject inconsistent snapshots; no user package code, patches,
settings or credentials are loaded to validate ownership. Synthetic metadata
cases and load-counter negatives are not actual `.6` runtime qualification.

### Bounds and trust boundary

The outer synchronous CHECK validates header length (16 MiB maximum) before
calling the maintained reader. Descriptor is capped at 32 MiB; inventory at
200,000 entries, depth 128, 512 MiB per file and 16 GiB total. Physical hashing is
chunked; virtual Electron hashing uses sequential ASAR-aware `readFileSync`, not
`openSync` (which may extract packed files). Child stdout/stderr and heap/time
are bounded. A heap bound is not a Windows Job Object total-RSS limit. Archive,
carrier and metadata identities are rechecked after probing. Concurrent changes
invalidate evidence, but pre/post checks do not prevent a hostile writer changing
header allocation bytes between file opens; use the existing serialized,
no-mutation deployment scope. No archive extraction or filesystem mutation is
performed by the verifier itself.

## Manual actual-release observer bridge (prepared; execution pending)

`.github/workflows/native-asar-release.yml` permits **manual execution only** and
requires `confirm_version` to exactly match the checked-in Desktop lock. It also
exposes `workflow_call` to the already-registered `plugin-catalog.yml` manual
entrypoint, with explicit manual-event guards in caller and callee. Legacy
physical `.5` inputs still fail before acquisition. The current target is the
actual immutable `0.1.6-alpha.1.cloga.1` release (formal run `35197577605`), with
11 byte-preserved formal fixtures; source-owned UI/restart/ancestor acceptance is
published evidence, not yet the separate Ops observer qualification. Never use
synthetic `.6` data to make the workflow green. Dispatch and final qualification
belong to the reviewed release flow; repinning alone is not qualification.

Before PR176 merges, dispatch the **registered** Plugin catalog validation
workflow (`345664659`) at the exact reviewed `cloga-dsh-0-1-6-baseline` ref, with
`qualify_native_asar=true` and `confirm_version=0.1.6-alpha.1.cloga.1`, through the
approved `cloga` GitHub identity gate. Its relative reusable-workflow reference
uses the same commit as the caller. Default manual runs and all PR/push events
skip the genuine job; qualifying runs have a separate non-canceling concurrency
group. No default-branch bootstrap, premature PR merge or inherited personal
secrets are required. Record and verify the returned run's head SHA and called
qualification job; an API rejection is a real blocker, not qualification.
See GitHub's [manual branch dispatch](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)
and [same-commit reusable workflow](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows) contracts.

Offline gate and inert validation tests:

```powershell
node tests/native-asar-release-smoke.mjs --plan --lock deployments/windows-copilot.lock.json --confirm-version <exact-locked-version>
node --test tests/native-asar-release-smoke.test.mjs
```

The workflow uses `contents:read` and the Actions token **only in acquisition
steps**—no personal secrets, credential files or source `.env`. It verifies the
locked immutable release ID/tag, bounded annotated-tag chain to the exact source
commit/tree, selected asset IDs/names/URLs/sizes/API digests and downloaded
SHA-256/SHA-512. Downloaded release/receipt/plan bytes must also agree with the
full locked formal evidence (`nativeProvisioning.fixtureRoot`). Existing runner
7-Zip is used only as a data decoder, forced to `-tNsis` for the outer installer.
Every outer record still requires one Path/Size field and passes type, link,
alias, count and depth checks. A blank NSIS Size is **unknown**, not zero; even
known solid sizes are informational estimates, not output bounds. Only the one
validated non-directory `app-64.7z` is selected, with literal `-spd`/`--` arguments
and stdout-only decoding. No other outer record is extracted.

The raw byte sink creates one fixed private file with `wx`, a 4-GiB actual-byte
cap checked **before every write** using overflow-safe counters, 64-KiB buffers
and backpressure. Commands have a 180-second deadline and bounded/drained stderr;
success requires exit zero, EOF and sink completion. Failure checks owned PID/tree
termination (including its termination helper) and removes only its own partial
file. Capture-only output is capped at 32 MiB using fixed-size pages. These are
output/parent-buffer limits, **not decoder RSS or CPU limits**; disposable CI
runner resources and the deadline remain the execution boundary.

The selected data must have the 7z magic signature and is listed/extracted only
with `-t7z`. Its exhaustive inner listing still requires known nonnegative file
sizes and a nonoverflowing 16-GiB total. The unchanged archive is hashed before/
after the single controlled extraction; 7-Zip's regular-file writer clamps to the
same item sizes exposed by its listing. Post-extraction paths/types/sizes are
checked, with no new per-file process or quota machinery. Inner unknown sizes,
links and unsafe paths are never accepted. The installer and NSIS helpers are
never executed. Before the source fixture runs,
the existing maintained read-only reader independently reads **`app.asar/package.json`**
as data after full header bounds/path/offset checks. Its packed root entry is
limited to 1 MiB; `name` and the **full** `version` must match the locked release
identity, not numeric PE `ProductVersion`. The observed name, full version and
raw package SHA-256 are rechecked after the observer and included as bounded
`applicationPackageName`, `applicationPackageVersion` and
`applicationPackageSha256` summary fields. This does not attest adjacent loaded
DLLs or execute the package/CLI.

All acquisition, source checkout, dependencies, extraction and fixture output
live in a restricted, non-synchronized `RUNNER_TEMP` tree. The exact locked source
HEAD/tree must match, with no tracked drift or nonignored untracked source
shadows before/after build and acceptance. Raw `pnpm-lock.yaml` and release-plan
hashes, manifest versions, Node and pnpm toolchain must match. Source dependencies
use the locked HTTPS source-build registry and `pnpm install --frozen-lockfile`,
followed only by `pnpm run build:lib:host`. Ignored dependencies/generated libraries
remain frozen-install/source-build-derived, not independently byte-attested as
an entire checkout; ignored caches are not scanned globally.
No `node_modules` copy, browser download or source Electron download is needed;
Playwright drives the actual extracted Electron renderer. Standard Node/pnpm
setup actions are used at independently reviewed immutable action commit SHAs.

The workflow runs this command **from the verified source checkout**, using its
installed `tsx/esm` loader (not `NODE_OPTIONS` or an Ops/ambient loader):

```powershell
node --import tsx/esm <private-ops>/tests/native-asar-release-smoke.mjs --run --lock <private-ops>/deployments/windows-copilot.lock.json --confirm-version <exact-locked-version> --source-root <private-source> --application <verified-extracted-exe> --output <private-output> --evidence-root <verified-release-assets>
```

`--run` requires Windows CI and validated `RUNNER_TEMP` containment. This prevents
accidental local/live use; `GITHUB_ACTIONS` is **not authentication or provenance**.
There is no local-run escape. The driver imports the locked source's
`runPackagedCopilotAcceptance({application,output,inspectProfile})`. The real
source fixture creates its own isolated profile, passes initial and restart
Models/account UI checks, closes both application processes, and compares
receipts before invoking the awaited observer with five frozen read-only paths.

Inside that observer, the existing `native-asar-integration.mjs` must genuinely
pass full runtime integrity and public resolver/native-addon/production-policy
proof. Deliberately wrong descriptor-digest, version and home **request copies**
must then fail against the unchanged actual fixture. Ops does not modify its
profile or runtime for negatives, load credentials/settings, or retain profiles.
The source owns cleanup in `finally`; successful qualification requires its
observed home to be gone. Advanced private-peer/ancestor/custom-home semantics
are not established by these invalid-request tests; retain the source/unit
matrix and separate real cases rather than overclaiming coverage.

Only the bounded, owned `qualification.json` summary is uploaded, for seven days.
Raw source evidence, receipts, screenshots, process/build logs, downloaded assets
and dependencies are private runner data, never artifact-upload inputs; cleanup
removes the run payload. Source-side failure before the observer may yield no
summary, and missing summaries fail the upload rather than fabricate success.
No real OAuth/model round or installer-upgrade acceptance is claimed. The earlier
EXE-only carrier/DLL and concurrency boundaries still apply: installer acquisition
provides archive provenance, not a new per-DLL loaded-image attestation.

**Actual-run gates remain:** the published immutable `.6` target and complete
formal fixtures now exist, but the Ops run must still verify its exact source
checkout/build, Actions-token access to the selected source/release (no private
cross-repository token fallback), existing runner 7-Zip NSIS listing/extraction,
actual archive-root package identity, credential-free native provisioning, and
the public resolver/native addon/Electron proof. Inert unit tests substitute for
none of these execution gates; actual Ops observer execution is still pending.
