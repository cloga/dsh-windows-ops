# Copilot alpha.33 managed Desktop upgrade record

Tracking: [Ops #210](https://github.com/cloga/dsh-windows-ops/issues/210) /
[PR #211](https://github.com/cloga/dsh-windows-ops/pull/211).

## Published pair and qualification status

The reviewed target is immutable [Desktop `0.1.6-alpha.1.cloga.16`](https://github.com/cloga/deepseek-harness/releases/tag/dsh-desktop-v0.1.6-alpha.1.cloga.16),
sequence **27**, Release **392765616**, source
`2c4f20904887240f83f776c79d8d69a42ce6c1e6`, tree
`3329051dfb8ac3681f155f403a902848db13ba37`, merged via
[Desktop PR #107](https://github.com/cloga/deepseek-harness/pull/107).
Qualified candidate `eb4789e49bce9e8d9c98b7c71d52c8dde5f20b1d` has the same tree;
[candidate CI `35567549602`](https://github.com/cloga/deepseek-harness/actions/runs/35567549602)
passed all 17 jobs. Bundled Core remains **`0.1.6-alpha.1`**, Host protocol **3**.
This is not a Core upgrade or qualification of the independently owned draft
alpha.2 Desktop PR #68.

Required [Copilot `0.4.0-alpha.33`](https://github.com/cloga/dsh-github-copilot/releases/tag/v0.4.0-alpha.33)
is immutable source `aa90fe434da8b2172faa1446afa0a0fd006afe00`.
[Plugin PR #157](https://github.com/cloga/dsh-github-copilot/pull/157) fixes the
`useSession` invocation by supplying the selector required by the official
contract. No Core fallback, Core patch or persistent data migration is introduced.

[Formal run `35569892548`, attempt 2](https://github.com/cloga/deepseek-harness/actions/runs/35569892548/attempts/2)
succeeded. Parent verification authenticated the published records/assets and
source-owned acceptance; the original three Actions ZIP bytes were independently
audited. **Fresh hosted Native Ops qualification passed** in
[run `35575187267`, attempt 1](https://github.com/cloga/dsh-windows-ops/actions/runs/35575187267)
at exact Ops code head `a59f586df4e329c3bc8b3f885013fdb5493f4970`.
Historical `.cloga.14`/alpha.32 run `35553019059` is not proof of this target.
Publication and this reviewed repin neither install nor activate it locally.

## Exact artifact bindings

| Evidence | Identity |
|---|---|
| Windows installer | `cloga-deepseek-harness-0.1.6-alpha.1.cloga.16-win-x64.exe`, asset `578511755`, 171,319,113 bytes; SHA-256 `575d74a4c0ac36ee25e8ac604e10f4bc93fbfddf5644ea8eacb4765f4cfdba71` |
| Expected installed executable | SHA-256 `96922b7871947f6a4bbc9c3c5108329dd2030b3b1baff3a8033d9eb98f3f159a` |
| Runtime descriptor | SHA-256 `b5b9b31ce34871ab320f63a91254ba601fd71edc447609d261360d84e4b929e8` |
| `release.json` | raw SHA-256 `6fadba25f0d81b70c3ac2daefd54cb35b9c810bbbf80db35d58c709ad61b8be9`; canonical self SHA-256 `239b9af198a4f854d603db9501e3e307dfeb7baaa4e91a2ee058132c2685cd14` |
| `build-receipt.json` | raw SHA-256 `7897dad36f7cf50d0dffd7f025c35a5ac9743bb2806de5a3ac042e8ed981c09f`; canonical self SHA-256 `ba59d3c6e899b706dab6030f3309ab9866d6da757decffe0752837952e00e0ad` |
| Copilot tarball | `dsh-github-copilot-0.4.0-alpha.33.tgz`, asset `578199183`, 724,820 bytes; SHA-256 `b293d40351f2e732969bac88c3906280b50c47a011bbeac1dc68bc4a8b0de480` |
| Copilot integrity | `sha512-fMONh2Thsu3YTv26DnGWFDlNg2vx3tYE6Cqm4/Aq5LmLwJo71weRZHTkJpRnenDbWkzcu4yNmk7u+GUJxb0bQw==` |
| Copilot `SHA256SUMS` | asset `578199206`, 104 bytes; SHA-256 `f81df10b7fd6e40b2319a42de1f04c3b7f7eccc57809b51623c9145f2a3df076` |
| Release plan / lockfile | SHA-256 `2394abde097149c45506e113a27b28a39ad4d6b7ec3cb93c236d3459dc3a4207` / `f14668d76eee14646543910878fc400fcbfa2a848b1ea177f2fc1cb2d0f21322` |

The six public assets remain the installer, `release.json`, `build-receipt.json`,
`desktop-provisioning.json`, `SHA256SUMS` and `SHA512SUMS`. Acceptance is internal
Actions evidence, not a seventh public asset or a substitute installer.

| Original Actions artifact | ID | Bytes | ZIP SHA-256 |
|---|---:|---:|---|
| Build | `10627540543` | 171,328,996 | `ffa3a84ebe8f722abf22fcf2d5f46bc555f2aae11ab337416ad57755f6a123da` |
| Acceptance | `10627066927` | 844,333 | `1396832b7d67c40a6422ae5f443a2e15cef85637d929fa2962b34ea810b79d07` |
| Observer canary | `10626922480` | 842,888 | `d1b2f9114d5485e3ab01e3c0db8e03044356306bd56106bc3a514a7123788e50` |

## Authenticated positive proof, not a live account

The optional `usagePositiveAcceptance` contract is now selected for this target
with `schemaVersion: 1`, positive-file SHA-256
`a1515b7ee5af44ff8e7ad86fa07ce8faedaa13f157d02ad99e4a4f99ee174b45`
and installed Client SHA-256
`6d6a7df36c377b7485b31d45511a8b582f5b745a1030a7f6e4c35a181ad52435`.
These are authenticated formal evidence identities, not synthetic unit-test hashes
or pending artifacts. See the [contract and initial-preparation history](copilot-positive-acceptance-preparation.md).

The source-owned producer uses the actual packaged renderer, official selector
binding, SessionProvider/Slot and released Client. Session snapshots, model
selection, quota and the test mount are synthetic. It runs canonical
`github-copilot` and `github-copilot-preview` cases **once, after the restart
packaged-graph check**, not once per startup phase. Both display `7 used`, read
quota twice, subscribe, hide on removal/provider change, clean up Client-owned UI,
preserve the application/synthetic sibling and restore the original signed-out
application. Selector errors and forbidden Remote calls are zero; the isolated
fixture has **no Host transport**.

Initial/restart signed-out usage schema 1, settings schema 2 and exact version-menu
proof remain independently required. Positive proof is not live quota/network
instrumentation, a native persisted Session, real account billing, OAuth,
external-navigation success, model/search acceptance or installer-upgrade proof.
It does not authorize a local installation, activation or restart.

## Official-first and preserved history

The [exact official alpha.1/alpha.2 selector contracts](copilot-positive-acceptance-preparation.md#official-selector-contract-not-a-core-workaround)
fully provide this primitive; the plugin now consumes it correctly. Retain the
plugin-owned account/quota UI only until an official equivalent meets its account
semantics and composer requirements. The [alpha.32 decisions and evidence](copilot-alpha32-upgrade-plan.md)
remain historical, including delegated OAuth/token/Context primitives and retained
provider-specific gaps. Alpha.33 is a plugin fix, not official Core replacement.

[Formal attempt 1](https://github.com/cloga/deepseek-harness/actions/runs/35569892548/attempts/1)
failed before publication during copied-helper cleanup: `EBUSY` while unlinking the
temporary copied `node.exe` in `removeOwnedDirectory`. Publication and remote
discovery were skipped. The log proves a locked executable, not the lock owner or
an antivirus/runner cause. Attempt 2 succeeded on the same source without weakening
a release or cleanup gate; that success does not erase or explain attempt 1.
All historical formal/Ops evidence stays historical. Hosted qualification is now
complete at the exact code head below; local activation remains deliberately deferred.

## Authenticated hosted Ops qualification

The registered caller [run `35575187267`](https://github.com/cloga/dsh-windows-ops/actions/runs/35575187267),
attempt 1, completed all four jobs successfully. Its native
[job `106255672689`](https://github.com/cloga/dsh-windows-ops/actions/runs/35575187267/job/106255672689)
qualified **Ops code head `a59f586df4e329c3bc8b3f885013fdb5493f4970`** against the
exact Desktop source/tree and installer/executable/runtime descriptor above.

- Artifact `10627584525`, `native-asar-qualification-35575187267-1`: original ZIP
  **733 bytes**, SHA-256 `8997486b787bbadbf7995ecf7d46f81870f813cb80488bc1008a1eea1de8b23f`.
- The sole ZIP entry, `qualification.json`: **1,073 bytes**, SHA-256
  `26c85a04e6be4616168bba93d08e838e21c45077dd3043e27855c2b51ba096d1`.
  The [committed summary](../tests/fixtures/desktop-native-verified-release/ops-cloga016-16/qualification.json)
  is a byte-exact copy authenticated against the original artifact, not rewritten JSON.
- Its existing schema 1 reports 9,806 runtime files, matching the formal descriptor;
  full application package name/version and observed package SHA-256
  `fc4fda43a8921ebfaccc2c07b41cd79c69c0f2b38edba8f3ba6152273501a446`;
  public `metadata-cjs-esm` resolution; one observer call; owned profile removed;
  and rejected descriptor-digest, version and absent-home request copies.
- Fresh positive usage, signed-out usage, settings and version-menu proof were
  enforced by the driver at **that exact Ops code head**. They are not invented
  fields in the raw summary. Whole-carrier attestation, model response and installer
  upgrade remain `false`. This is not live account/quota, OAuth/model/search or
  local installation/activation proof.

Evidence-recording commit `c868c689b1955992c4958191e278b1c9fa77a2df` changed only
documentation, catalog descriptive evidence and the new raw qualification record.
It was **not** the commit on which native qualification ran: that native provenance
stays bound to `a59f586…`. Its runtime, test, workflow, deployment-lock and existing
formal-evidence bytes were identical to the qualified code head; required PR checks
passed separately on the evidence-recording head.

### Concurrent master integration checkpoint

Protected master subsequently advanced to `43630e4d073de81c0644b24e426a0ae5aed1ccbf`
([Ops PR #212](https://github.com/cloga/dsh-windows-ops/pull/212)), adding explicit
alpha.2 `combined-suite-v2` positive Client evidence preparation. The same PR #211
now merges that work without dropping either stream. This later merge includes
adapter and test changes: it is **not** another documentation-only successor, and
the earlier `a59f586…` success does not qualify the new combined head. Fresh exact-head
hosted native qualification is required before merge; until it succeeds, no combined-head
success is claimed. The `.cloga.16`/sequence-27/Core-alpha.1/alpha.33 deployment lock,
its positive-proof pins and original formal/Ops bytes remain unchanged. Alpha.2
is not promoted. A new run's exact identity and result must be recorded separately,
not by relabeling run `35575187267` or adding fields to its raw summary.

The user explicitly chose **stage only, without interrupting Sessions**. No local
installation, activation or restart was performed; live-account UI validation is
deferred until a future explicit human request.
