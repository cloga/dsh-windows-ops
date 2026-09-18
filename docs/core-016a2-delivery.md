# DSH 0.1.6-alpha.2 delivery evidence

Tracking: [Ops #181](https://github.com/cloga/dsh-windows-ops/issues/181).
Official target: `dsh-v0.1.6-alpha.2`, commit
`ddefc45fbc7f8e46dd73185e68295696d1297887`.
Feature-level official-first decisions remain in the
[assessment](core-016a2-assessment.md); this page records later delivery evidence,
not a replacement deployment lock or an installed-state report.

中文：本页区分源码适配、正式发布、制品核验和本机激活。已发布插件不代表新的
Core/Desktop 已合格；现有部署锁仍权威，未执行安装、激活或重启。Cron 和
Playwright 仍是可选 overlays，不自动升级为 Desktop 必需组件。

## Component status

| Component | Reviewed head | Merged source | Delivery |
|---|---|---|---|
| Cron 0.7.3 | `299c10b4990c957cce26956407f52427ef1c6fd8` | `850f80842fc9ae80f8f00e7b96de25fed1af9005` | [PR #50](https://github.com/cloga/dsh-cron/pull/50), [published v0.7.3](https://github.com/cloga/dsh-cron/releases/tag/v0.7.3), independently verified |
| Playwright Host 0.1.8 | `9d07a730add21c5a056cc8b53369447ec3473c32` | `b50457e04181988e4d34b50a61291e7b52d8a417` | [PR #21](https://github.com/cloga/dsh-playwright-host/pull/21), [published v0.1.8](https://github.com/cloga/dsh-playwright-host/releases/tag/v0.1.8), independently verified |
| Copilot 0.4.0-alpha.25 | `df09951dd0f304029d36614e9daa89ae5e1c0f3f` | `5458fda2854d5956e0c8d68a0f0b0a6e55833c8b` | [PR #140](https://github.com/cloga/dsh-github-copilot/pull/140), [GitHub v0.4.0-alpha.25](https://github.com/cloga/dsh-github-copilot/releases/tag/v0.4.0-alpha.25) and [npm alpha.25](https://www.npmjs.com/package/dsh-github-copilot/v/0.4.0-alpha.25) independently verified against the same original bytes |
| Core/Desktop fork | Work in progress | Not yet qualified | [Core #67](https://github.com/cloga/deepseek-harness/issues/67); no alpha.2 fork release or deployment qualification claimed |

## Verified published artifact identities

The following values were checked against downloaded original archive/checksum
bytes and authenticated GitHub Release metadata. Annotated tags dereference to
the exact merged sources above. Both Releases are immutable, non-draft and stable;
`latest` pointed to these versions at verification time. Their established release
workflows distribute GitHub Release archives, not npm publications. Playwright
also declares a private npm manifest; Cron's manifest does not, so its delivery
channel is established by the repository release workflow, not that flag.

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| [dsh-cron-0.7.3.tgz](https://github.com/cloga/dsh-cron/releases/download/v0.7.3/dsh-cron-0.7.3.tgz) | 70047 | `c74b69394b13211ff22dc4b8f3d2964fedc9845dcedff4a7de585fb56e507538` |
| [Cron SHA256SUMS](https://github.com/cloga/dsh-cron/releases/download/v0.7.3/SHA256SUMS) | 85 | `6a9650ca93c599b66e4f6e74698d84ced2108853970f429560cfe2b68b203468` |
| [dsh-playwright-host-0.1.8.tgz](https://github.com/cloga/dsh-playwright-host/releases/download/v0.1.8/dsh-playwright-host-0.1.8.tgz) | 10904 | `52fdc45733ca5006207a5ef760a5750dcfd5f3b15e1b9cd4643e429779f5aabb` |
| [Playwright SHA256SUMS](https://github.com/cloga/dsh-playwright-host/releases/download/v0.1.8/SHA256SUMS) | 96 | `c5a952b2a8ecaf52510ebfa4ee68da3816a0da80c31d55e4d0bfd0a483fb793c` |

Cron's archive has exactly eight intended members. Seven non-manifest files match
merged Git blobs byte-for-byte; the packed manifest matches the release contract
and has no install hook. Playwright's six members all match merged Git blobs.
Its `cordis.patch.yml` SHA-256 remains
`8a1778ebf72491af7716398b7c60d5368cfa309e3a86d6534e72e7efdebc379d`,
identical to v0.1.7; no composition migration was silently introduced.

### Copilot: verified GitHub and npm publication

GitHub Release `391105204` is immutable, non-draft and a **prerelease**. Annotated
tag `73ff8a7f50bc2794289f9f2116cc1474f50dc1f1` points to the exact merged commit
`5458fda2854d5956e0c8d68a0f0b0a6e55833c8b`. Downloaded original archive/checksum
bytes match authenticated GitHub asset digests:

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| [dsh-github-copilot-0.4.0-alpha.25.tgz](https://github.com/cloga/dsh-github-copilot/releases/download/v0.4.0-alpha.25/dsh-github-copilot-0.4.0-alpha.25.tgz) | 671451 | `c11d4b3955ae7a8cd85fbf078e2892c74b192949838cf0cbab4796bf55a7e66f` |
| [Copilot SHA256SUMS](https://github.com/cloga/dsh-github-copilot/releases/download/v0.4.0-alpha.25/SHA256SUMS) | 104 | `c21c8205deaa15385512b3f3a6c6d3faf8353daf69ab198950ef958c344cb7e4` |

Original archive SHA-512 SRI:
`sha512-xDcD9Kxg7Z7hQqLt8opOwmS4mVFppheYmFRpRMIWgKO0r3YkmXHGNx76Ta4C79M8waLTpx5HlmNPEq10m80oLQ==`.
This hash of the downloaded GitHub bytes now matches authoritative public npm
`dist.integrity`; npm SHA-1 is `5ab283d1e1b178a3e9d9e6cfd7aa9c9066058cbe`,
also independently computed from the original archive. The observed `alpha`
dist-tag pointed exactly to `0.4.0-alpha.25`. A local candidate archive is not a
substitute for this original.

The [first publisher attempt](https://github.com/cloga/dsh-github-copilot/actions/runs/35283259283/job/105411047005)
completed GitHub publication but failed npm verification with
`npm version integrity differs or is not yet observable; no overwrite or automatic retry`.
That message alone did not establish write success, absence or conflicting bytes.
The uncertainty was resolved by a separately reviewed **read-only** verifier:
[run 35284938664](https://github.com/cloga/dsh-github-copilot/actions/runs/35284938664),
job `105415082111`, verifier head `ae1b60ece475dae389c55d3377d1a45d35982152`,
completed successfully on 2026-09-17. Its
[original minimal public receipt](evidence/core-016a2-copilot-npm.json) contains the
actual name, version, integrity, shasum and alpha-tag readback. The receipt was
independently compared with the locally downloaded immutable archive, not merely
accepted because the workflow was green. Both publication channels are verified;
**no republish was needed to establish this result**. The first failed pipeline
remains historical evidence, not a current npm-publication failure.

Local direct public-registry reads still failed TLS; the approved mirror's
package-level E404 was not treated as public-version absence. The public GETs ran
in the repository's existing approved publication CI environment with only
`contents: read`, no OIDC/npm credential, install, package-code execution, mutation
or retry capability. No local registry/TLS policy was bypassed. The reusable
verifier and recovery guidance were merged through
[PR #141](https://github.com/cloga/dsh-github-copilot/pull/141), helper commit
`2436552a1a3c07f0d24820f62df9b2e6a569e81a`; this is **not** the package's source
commit. Any later normal reconciliation must retain the original source/tag and
archive and accept only matching existing npm bytes; no blind republish,
immutable-asset replacement or automatic dist-tag repair is permitted.

中文：Copilot alpha.25 的 GitHub/npm 双渠道已经核验，npm SRI、SHA-1 和 alpha
标签与原始 GitHub 制品一致。首次流水线的回读错误已由独立只读证据消除不确定性，
未通过重复发布来试错；这不代表本机已安装，也不证明实时模型或搜索请求。

## Qualification and acceptance scope

- **Cron:** [exact-main CI and publisher](https://github.com/cloga/dsh-cron/actions/runs/35282670418)
  passed after exact-head review. The adaptation binds sidebar actions to retained
  main-view ownership and instance leases rather than a module-global last-mounted
  Session. Local full verification counted 112 tests with no skips, including the
  required isolated Edge sidebar scenarios. Host ownership/HTTP/restart mock tests
  also passed against the extracted published archive. These are isolated tests,
  not live scheduled-task, notification or crash-exactly-once acceptance.
- **Playwright:** [exact-main CI and publisher](https://github.com/cloga/dsh-playwright-host/actions/runs/35282654228)
  passed. Exact official Host and Client libraries are built unchanged for runtime
  fixtures; Linux fixtures include the declared native-system build. Real isolated
  Edge capability tests support temporarily retaining the thin shared MCP entry:
  official Browser Use remains the preferred foundation but does not yet preserve
  the required testing/devtools/vision and viewport behavior. The current overlay
  is shared, **not** Session-isolated. No simultaneous legacy/native migration is
  authorized by this release.
- **Copilot:** [exact-main qualification](https://github.com/cloga/dsh-github-copilot/actions/runs/35283259283)
  passed all 18 Windows/Linux source-baseline rows plus two published-adapter rows
  and the release-ready gate. Independent review found no blockers in all 14
  strict codec factories/legacy bridges or native v3 dedicated-child admission and
  cache-version 2 refolding. Ordinary children, durable history and global defaults
  remain outside the dedicated ownership path. Exact-source fixtures are meaningful
  contract coverage, **not** full native dedicated-root -> child -> cold-resume
  end-to-end qualification, live OAuth/model/search acceptance or installed Desktop
  attestation. Candidate documentation saying CI had not run is a historical
  pre-CI snapshot, not the later state recorded here. Both GitHub Release and npm
  publication are required for this package; both are independently verified
  above. No provenance attestation or installed-runtime acceptance is implied.

Public component receipts: [Cron](https://github.com/cloga/dsh-cron/pull/50#issuecomment-5722223645),
[Playwright](https://github.com/cloga/dsh-playwright-host/issues/20#issuecomment-5722219209).

## Core candidate remote evidence

Snapshot for [Core Issue #67](https://github.com/cloga/deepseek-harness/issues/67)
and [Draft PR #68](https://github.com/cloga/deepseek-harness/pull/68), not a current
release receipt. The planned candidate is `0.1.6-alpha.2.cloga.1`, sequence 13,
with Copilot alpha.25; **not published or installed** at this checkpoint. Separate
plugin publications above do not promote the deployment lock.

| Evidence | What it establishes / limit |
|---|---|
| [Merged-candidate CI 35337031063](https://github.com/cloga/deepseek-harness/actions/runs/35337031063), head `0de805da6063f013764a678c19c924b8f1327cd1` | Successful Windows build, Node 22/24.9/26, benchmarks and Linux/Windows installed-wheel checks; overall **failure**, not release-qualified. “Merged-candidate” is a test description, not proof PR #68 merged. |
| [CI 35343590153](https://github.com/cloga/deepseek-harness/actions/runs/35343590153), head `3fe0f8476950abdd0bafcb68a9e7de12022b0b68` | Actual catalog freshness failure after role fixes; run later cancelled. Source/runtime qualification remained ongoing, not all-green. |
| [Corrected catalog generation 35345437655](https://github.com/cloga/deepseek-harness/actions/runs/35345437655), head `a9dd6bce1cd477c516615a47a5061c4f57ecfc89` | Generator run **success**; artifact not yet accepted at this checkpoint. Neither full CI nor release acceptance follows from generator success. |

Native lint summaries reported **680 vs 467 visible** diagnostics, then **218 vs
3 visible** in a later observation. Pretty-output suppression is not evidence that
all remaining errors were fixed. Use the official JSON runner and preserve its
nonzero exit as specified in the [checklist](core-upgrade.md#remote-qualification-checklist).

Earlier temporary [run 35343590155](https://github.com/cloga/deepseek-harness/actions/runs/35343590155)
was cancelled; its unreviewed artifact `10545991575` was deleted and never used.
Review found boundary defects; this is **not a confirmed sensitive-data leak**.
A replacement artifact must meet the exact-head/input/lock, generated-content,
symlink and log/artifact sentinel checks before acceptance.

## Remaining promotion gates

- [ ] Accept only reviewed official generator output; preserve authored/archived
  notes, remove temporary workflows, and qualify the final exact head.
- [ ] Complete normal frozen install, full source/runtime checks and build/artifact
  qualification; local mirror gaps alone neither fail nor satisfy these gates.
- [ ] Record packaged/module-loading and actual official UI disabled-install ->
  enable/restart acceptance separately on guarded disposable GitHub-hosted Windows.
  `PREPARED`, graph inventory and signed-out Copilot are not active-runtime or
  writable-composer evidence; never use the current Desktop implicitly.
- [ ] Complete Core/Desktop release and independent published-artifact verification.

Then
qualify the intended combined deployment through its normal Ops workflow before
updating deployment locks, catalog and fixtures together. Do not substitute earlier
alpha.1 native qualification or a plugin CI result for alpha.2 Desktop acceptance.
No lower native-loader version was substituted to obtain these results; the
[local mirror limitation](core-016a2-assessment.md#native-loader-dependency-and-mirror-qualification)
remains separate from successful exact-target CI in its approved environment.
