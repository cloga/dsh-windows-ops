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
  `releaseChannel.upstreamVersion`. Protocol schema is the source's version 3.
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

Qualification still does **not** prove a live Host/session/model round or formal
release acceptance. The parent must retain actual source-owned initial/restart/
ancestor-isolation release tests, and qualify Ops separately on that real
fixture. Required integration counterexamples include private same-version
shared targets, unresolved peers, wrong generation/home, ancestor SDK bait,
missing native-addon/public APIs and source drift. Those real-runtime cases
cannot be proved by the inert local fixture.

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
