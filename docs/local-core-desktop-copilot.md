# Locked DSH Desktop and direct GitHub Copilot

## Newer account-discovered route maintenance

For the V3 account/Session model separation and removal of an existing extra native Copilot route, use [the separate config-only managed-route procedure](copilot-managed-route.md). Do not recreate native model definitions from this pinned full-deployment guide or run its installer merely to migrate a newer Desktop. The maintenance command performs no component installation, Session/default selection, credentials access or restart; it requires fresh live evidence and explicit configuration approvals. Its policy does not replace the full deployment lock below.

## Identify the running Desktop version

**First verified release:** the native version-menu feature from
[Desktop PR #91](https://github.com/cloga/deepseek-harness/pull/91) ships in
[Desktop `0.1.6-alpha.1.cloga.12`](https://github.com/cloga/deepseek-harness/releases/tag/dsh-desktop-v0.1.6-alpha.1.cloga.12).
[Formal run `35528552640`](https://github.com/cloga/deepseek-harness/actions/runs/35528552640)
passed build, immutable publication, and remote managed discovery from merged source
`d19be3ff5524948c40cb9929cdd4d67d5cb35059`. All six published assets were independently
verified against their sizes, remote digests, both checksum manifests, and source
records. That historical verification was release evidence, not an Ops baseline
promotion; the current lock is described below. No installer execution or local
activation accompanied that verification.

On a Desktop build containing that feature, open **Application → About Desktop
`<version>`…** (Chinese: **应用 → 关于 Desktop `<version>`…**). The menu shows the
running Electron application's full version, including every prerelease and fork
suffix; selecting it opens the native About panel. Record the whole value, not
just `0.1.6`. This shell-owned entry needs no network or healthy Host page.

Keep these observations separate:

- **About Desktop** identifies the running Desktop application.
- **Check for Updates** or an update notice identifies an available replacement,
  not proof that it is installed or running.
- **Core/CLI version** identifies that Core or CLI runtime, not the Desktop shell.
  A separate CLI on PATH may not be Desktop's bundled runtime at all.
- **Windows file metadata** identifies a selected executable on disk, not the
  already-running process or a completed managed update.

For an older build without the menu entry, inspect the actual installed
`cloga-deepseek-harness.exe` through Windows **Properties → Details**, or use this
read-only PowerShell command without starting Desktop:

```powershell
$desktopExe = Read-Host 'Full path to the installed cloga-deepseek-harness.exe'
(Get-Item -LiteralPath $desktopExe).VersionInfo |
    Select-Object FileVersion, ProductVersion
```

Preserve any suffix that is present. Some releases expose only a numeric PE
version: the historical `.cloga.2` executable has ProductVersion `0.1.6.0`.
Do not reconstruct a missing semantic suffix from that value; use verified
installed-file hashes matched to the immutable release manifest/build receipt
for an exact older release identity. A newly installed file can also differ from
an application that has not yet been restarted. Version identification does not
authorize installation, activation, or interruption of live Sessions.

The formal release's isolated initial/restart acceptance records the full
`About Desktop 0.1.6-alpha.1.cloga.16…` menu label and one About callback dispatch
in each phase. The modal call is intercepted (`nativeModalOpened: false`): this
proves neither native About window rendering nor an installer upgrade or activation
of the operator's live application.

## Authoritative baseline

[`deployments/windows-copilot.lock.json`](../deployments/windows-copilot.lock.json)
is the machine-readable deployment contract. The published target and formal proof
were independently verified on **2026-09-21**. Fresh hosted Native Ops run
`35575187267` attempt 1 passed at exact code head
`a59f586df4e329c3bc8b3f885013fdb5493f4970`; the later documentation/evidence-only
follow-up records that result and is not itself a newly native-qualified head.
The stable deployment ID remains `windows-copilot-2026-09-15`; this date update
identifies the reviewed published target, not a new local installation.

| Component | Locked identity |
|---|---|
| Desktop | fork-owned `0.1.6-alpha.1.cloga.16`, sequence 27, immutable Release `392765616`, tag `dsh-desktop-v0.1.6-alpha.1.cloga.16`, source `2c4f20904887240f83f776c79d8d69a42ce6c1e6` |
| Desktop artifact | [`cloga-deepseek-harness-0.1.6-alpha.1.cloga.16-win-x64.exe`](https://github.com/cloga/deepseek-harness/releases/download/dsh-desktop-v0.1.6-alpha.1.cloga.16/cloga-deepseek-harness-0.1.6-alpha.1.cloga.16-win-x64.exe), 171,319,113 bytes, SHA-256 `575d74a4c0ac36ee25e8ac604e10f4bc93fbfddf5644ea8eacb4765f4cfdba71` |
| Desktop-managed runtime | virtual root `%LOCALAPPDATA%\Programs\DeepSeek Harness (cloga)\resources\app.asar\dsh`; Windows Ops follows the actual installed EXE path |
| Expected installed Desktop identity | executable SHA-256 `96922b7871947f6a4bbc9c3c5108329dd2030b3b1baff3a8033d9eb98f3f159a`; virtual descriptor SHA-256 `b5b9b31ce34871ab320f63a91254ba601fd71edc447609d261360d84e4b929e8`; formal source evidence, not local installation |
| Runtime attestation | release manifest schema 3, self SHA-256 `239b9af198a4f854d603db9501e3e307dfeb7baaa4e91a2ee058132c2685cd14`, raw SHA-256 `6fadba25f0d81b70c3ac2daefd54cb35b9c810bbbf80db35d58c709ad61b8be9`; bundled `@deepseek-ai/dsh@0.1.6-alpha.1`, Host protocol 3 |
| Copilot plugin | immutable `dsh-github-copilot@0.4.0-alpha.33`, source `aa90fe434da8b2172faa1446afa0a0fd006afe00`; not official Core |
| Plugin artifact | [`dsh-github-copilot-0.4.0-alpha.33.tgz`](https://github.com/cloga/dsh-github-copilot/releases/download/v0.4.0-alpha.33/dsh-github-copilot-0.4.0-alpha.33.tgz), 724,820 bytes, SHA-256 `b293d40351f2e732969bac88c3906280b50c47a011bbeac1dc68bc4a8b0de480`, SRI `sha512-fMONh2Thsu3YTv26DnGWFDlNg2vx3tYE6Cqm4/Aq5LmLwJo71weRZHTkJpRnenDbWkzcu4yNmk7u+GUJxb0bQw==`; checksum digest `f81df10b7fd6e40b2319a42de1f04c3b7f7eccc57809b51623c9145f2a3df076` |
| Desktop native capability | `desktopNativeVerifiedRelease`; `automaticProvisioning=false` remains manifest compatibility, while exact startup provisioning is bound separately |

Do not independently upgrade or substitute a locked component. Update the lock,
catalog, fixtures, tests, and explanatory guides together only after a new
baseline is verified. The installer consumes the official Desktop artifact and
immutable Copilot Release; it does not distribute either one.

Desktop owns the supported bundled runtime; Windows Ops never builds, installs
or selects another Core to satisfy this lock. Native CHECK attests the exact
installed EXE and complete ASAR-backed `dsh` inventory, including an independent
header-driven audit of `resources/app.asar.unpacked/dsh` so orphan backing files
cannot be hidden by virtual enumeration. Runtime package/policy imports occur
only after byte attestation. This does not independently attest every adjacent
Electron DLL/snapshot or prove a live Host/model response.

The `.6` Host carrier is the locked Electron EXE in Node mode
(`ELECTRON_RUN_AS_NODE=1`), not `resources/runtime/node/node.exe`. That physical
bundled upstream Node remains for packaged pnpm and the updater helper. Host
binding requires the exact Desktop parent and argv: Electron EXE, `--import`,
the attested policy's exact file URL, Host entry, virtual runtime root, and
`profiles/desktop`. No extra flags, private runtime, materialized Host links,
plain-Node ASAR fallback or port-3080 ownership claim is accepted. Historical
`.5` physical-runtime checks remain separately version/layout-scoped.
The formal EXE has PE ProductVersion `0.1.6.0`, CompanyName `GitHub, Inc.` and
Authenticode `NotSigned`; its semantic release is `0.1.6-alpha.1.cloga.16`.

**Current published pair; hosted Native Ops qualification passed at the exact code head:**
[Formal run `35569892548` attempt 2](https://github.com/cloga/deepseek-harness/actions/runs/35569892548/attempts/2)
succeeded for source `2c4f20904887240f83f776c79d8d69a42ce6c1e6`, tree
`3329051dfb8ac3681f155f403a902848db13ba37`, matching qualified candidate
`eb4789e49bce9e8d9c98b7c71d52c8dde5f20b1d`. Parent verification authenticated
all six public assets and formal evidence, with a separate original ZIP audit.
The optional schema-1 `usagePositiveAcceptance` binds positive-file SHA-256
`a1515b7ee5af44ff8e7ad86fa07ce8faedaa13f157d02ad99e4a4f99ee174b45`
and installed Client SHA-256
`6d6a7df36c377b7485b31d45511a8b582f5b745a1030a7f6e4c35a181ad52435`.
The actual renderer/released Client/SessionProvider/Slot consume a synthetic
Session/quota/test mount, canonical and preview once after the restart graph;
no Host transport or live account/network proof is supplied. Signed-out usage,
settings and version-menu gates remain independent. Plugin PR #157 follows the
official required-selector contract, without a Core change. Formal release attempt 1's `EBUSY`
copied-helper cleanup failure remains history. See the [alpha.33 record](copilot-alpha33-upgrade-record.md).
Fresh hosted Ops run `35575187267` attempt 1 passed at exact code head
`a59f586df4e329c3bc8b3f885013fdb5493f4970`; see the [authenticated qualification](#scoped-ops-ci-qualification).
The explicit choice remains **stage-only**, with no local installation, activation
or restart. Live account verification is deferred until a future human request;
no live OAuth/model/search is claimed.

### Historical `.cloga.14` / alpha.32 evidence

**Historical published paired source and genuine native Ops qualification:**
formal run [`35549412610`](https://github.com/cloga/deepseek-harness/actions/runs/35549412610)
at source `a0f0144f4cddc90c45f8be93c61c0cd6cec470c7` passed build, immutable
publication and packaged read-only acceptance on attempt 1. All 70 original ZIP
entries were independently byte-bound; 20 authoritative JSON files are tracked
under [`formal-cloga016-14`](../tests/fixtures/desktop-native-verified-release/formal-cloga016-14).
Schema 2 binds initial/restart settings and version-menu evidence; usage schema 1
binds signed-out absence after account readiness without Host request instrumentation.
Registered native run [`35553019059`](https://github.com/cloga/dsh-windows-ops/actions/runs/35553019059)
passed at exact Ops head `68a1218ef6a50f06870bae483d64f52d6de244aa`; its raw
summary is tracked under `ops-cloga016-14`. No live quota, OAuth, verification
navigation, model/search, install or restart occurred. Publication does not install
or activate this target locally. See the [alpha.32 formal record](copilot-alpha32-upgrade-plan.md).

### Historical `.cloga.2` / alpha.24 evidence

The historical immutable [Release](https://github.com/cloga/deepseek-harness/releases/tag/dsh-desktop-v0.1.6-alpha.1.cloga.2)
is ID `391052820`, sequence 12, published on 2026-09-17 from source
`65a236bd65f2971f98b11a0efd020b8860144924`, tree
`b219bd1baa93433e9449dc72905d7980e7943a05`, following qualified candidate
`c8af5b6cb3ccf651a5ff1a285ff7bf0ac95f487a` and merged [PR #63](https://github.com/cloga/deepseek-harness/pull/63).
Formal run [`35271210350`](https://github.com/cloga/deepseek-harness/actions/runs/35271210350)
succeeded on attempt 1. Independent verification matched all six Release assets
to their original bytes and checked exact source/tag, manifest/receipt and plan
bindings. This is actual formal release evidence, not candidate or synthetic
replacement data. Historical `formal-cloga016-1` and `ops-cloga016-1` fixtures
remain untouched; no current Ops observer summary is inferred from them.
No installer execution or local Desktop change accompanied this repin.

The published build receipt has raw SHA-256
`09307d85f8679308c424a9ea98aba89b1a80d97e914ea6cba385d7265170666c`
and canonical self SHA-256
`ec0229f180feb40afcd1da652cabf750f68dce823f525fc243d215b9c27e4fc8`.
The helper SHA-256 is `2ca23e66cdf456645e1622d57759c9a37e735f758bacd93ed2c7de6af6bae424`;
capability SHA-256 is `d098b882ddf95d3ad14a3d518b993d7f2dab46074950f348c7176028314f1437`.
The historical `.cloga.5` recovery Release `390292533` (sequence 6, run
`35152173707`, attempt 1) incorporated ancestor module isolation from
`cloga/deepseek-harness#49`, the registry repair from `cloga/deepseek-harness#47`,
and earlier helper/test fixes from `cloga/deepseek-harness#43` and
`cloga/deepseek-harness#44`. Those fixes remain inherited by later releases; their
historical acceptance, including preserved `.cloga.7` fixtures, is not relabeled as current evidence. That schema-3
update manifest retained `automaticProvisioning=false` so the old
installed update client can parse it. Do not change this field or insert new
manifest keys. Native startup provisioning is separately declared by the
build receipt (`automaticProvisioning=true`) and packaged managed capability
schema 3, both binding canonical plan SHA-256
`d93e340df7169d5fa11558f6c4ab41171aa7cbf7cb564f177dd125d4076be01c`.
The two compatibility objects must not be equated wholesale. Windows Ops
checks their shared capability, exact published hashes, canonical self hashes,
and plan binding; installation checks additionally require actual profile
receipts, state, inventory and artifact bytes.

Native dependency registry acceptance follows the exact packaged plan, bound to
both the locked release plan digest and managed capability, rather than a
hard-coded endpoint. Profile receipts and provisioning state must preserve that
same source, including `dependencyRegistry`. Changing a local plan, registry or
receipt does not authorize another endpoint; a baseline change requires newly
verified release evidence. This check neither changes npm configuration nor
performs dependency downloads.

The published `.6.cloga.2` plan preserves plugin `dependencyRegistry`
`https://packagefeedproxy.microsoft.io/npm/` but updates the exact Copilot source
to alpha.24 and therefore changes the plan hash. Historically, `.cloga.4`/`.cloga.5`
replaced the `.cloga.3` npmjs endpoint after native dependency provisioning
failed TLS checks locally. The frozen workspace build still declares
`build.packageRegistry=https://registry.npmjs.org/` in the release manifest
and corresponding receipt build inputs. Do not rewrite that build field, patch
a live plan, disable TLS verification or run a separate profile install.
Managed Core remains `0.1.6-alpha.1`; the plugin and packaged provisioning plan
must be upgraded coherently, not as an independent live profile replacement.

The historical `.cloga.4` registry repair exposed legacy ancestor `node_modules`
redirecting an optional SDK outside owned packages. The `.cloga.5` runtime added
the Host-owned module-resolution preload. The current `.6` policy is separately byte-attested and used with public runtime resolution generations. Current formal
polluted-home acceptance records `ancestorSdkJunction=true` and
`ancestorSdkLoaded=false` with matching initial and restart graphs; those exact
current evidence files are hash-bound in the lock. Historical acceptance fixtures
remain historical, not rewritten as a new run. Do not delete or disable ancestor
packages as an implicit recovery step. Packaged regression success is separate
from operator-verified local startup and model acceptance.

Historical `.cloga.2` source acceptance artifact `10518683372` from run `35271210350`
records helper bootstrap/ACK/cancel and isolated packaged Electron initial/restart
provisioning, signed-out Copilot Models account UI and graph/ancestor isolation.
It additionally exercises the actual Model roles and search-routing settings DOM:
`modelRolesViewLoaded:true`, `searchProviderCatalogLoaded:true`, and the same
registered providers `deepseek-official` / `github-copilot-hosted` in both phases.
These are positive read-only view/catalog observations, not proof of provider
availability or a real search. Alpha.24 repairs alpha.23's missing Client
`remote.githubCopilotSearchRouting` injection; do not stop at manifest peer
admission or green tests when the real packaged card can still be absent.
No real search, OAuth/model round, local installation/activation or installed-app
upgrade/restart was performed. PNG signatures alone are not visual inspection;
artifact archive/entry byte provenance is a separate gate, completed for this
formal run by authenticated API size/SHA-256 readback and streamed comparison of
all 62 ZIP entry byte sequences. The original archive identities are:

| Formal artifact | ID | Bytes | Original ZIP SHA-256 |
|---|---:|---:|---|
| Build | `10518653463` | `171311097` | `39fd5253f006956e3633cf86bdbe4490a446a34a7287ce90d7d65b873adf8840` |
| Acceptance | `10518683372` | `784649` | `a7af7d0991a53ec2ce739e2090ae570a8928b89fc46e0e7a1efa6ec726b0a839` |
| Observer canary | `10518608606` | `783993` | `00d280d24594ba11356bb164e5972bb817567cb791f7052e947039761d5c1548` |

All 13 committed JSON fixtures in
[`formal-cloga016-2`](../tests/fixtures/desktop-native-verified-release/formal-cloga016-2)
match those authenticated entry bytes: three Release JSON files from the build
archive and ten acceptance files, including both settings observations. The Ops
workflow consumes these tracked raw fixtures and enforces their locked hashes
before runtime execution; it independently reacquires the three Release JSON
files, not the formal Actions ZIPs. Its fresh source-owned settings observations
must match both locked deterministic settings digests. This acquisition history
is not a claim of local application activation or a fresh model response.

The [Copilot alpha.33 formal acceptance record](copilot-alpha33-upgrade-record.md)
extends the [historical alpha.32 record](copilot-alpha32-upgrade-plan.md) with the
official selector fix and authenticated positive usage proof. The current paired
`.cloga.16` release keeps bundled Core alpha.1; hosted Ops qualification passed
in run `35575187267` at exact code head `a59f586df4e329c3bc8b3f885013fdb5493f4970`.
Separately owned draft Desktop alpha.2 PR 68 remains unqualified and out of scope.

The build toolchain remains Node `24.13.0` / pnpm `11.7.0`, not the Host engine
identity. Current native Ops qualification must independently bind this exact
paired release. Historical acceptance stays historical, not activation permission.

## Official-first upgrade checklist

This checklist is mandatory whenever a new Core, Desktop or plugin version is
considered. Record it in the upgrade Issue/PR and synchronize the relevant guide;
prefer official behavior when it satisfies the user's actual requirements.

1. **Fix the target and evidence.** Record the exact official version/tag/commit,
   release notes and relevant source/API contracts. Compare against that target,
   not a moving default branch or similar feature names. Distinguish official
   Core from the maintained Desktop release and plugin being paired with it.
2. **Inventory custom requirements.** For each relevant customization, state the
   purpose, owner and user-visible/safety requirements before deciding whether
   the official implementation replaces it. Do not delete needed behavior just
   to reduce a fork diff.
3. **Classify parity and decide.** Use `full`, `partial`, `absent` or `unverified`,
   citing exact evidence. `Unverified` is not absence. Choose `migrate`, `retain`
   (temporarily), or `retire`; every retained customization needs a concrete gap
   and a testable condition for returning to official support. If evidence is
   incomplete, record the unresolved comparison and obtain it before claiming
   absence, compatibility or safe removal.
4. **Plan the transition.** Review configuration and data migration, API and
   behavioral compatibility, credentials/data ownership, safety guarantees,
   failure cleanup and rollback. Preserve required user behavior and acceptance
   tests; remove redundant adapters and obsolete-path tests only after a verified
   replacement is available.
5. **Qualify the actual runtime.** Separate static metadata, unit/contract tests,
   packaged UI/graph acceptance, Ops qualification and target-machine functional
   evidence. Test the changed interaction, not merely its label or registration.
   Keep unperformed OAuth/model/search and local-upgrade checks explicit.
6. **Publish without implicit activation.** Use the owning project's Issue →
   branch → PR → qualified merge → established release workflow. Verify immutable
   assets/source/checksums before synchronizing lock/catalog/fixtures/guides.
   Never overwrite an immutable release, weaken a gate, or restart/replace a
   running application to finish this checklist. Query live Sessions and obtain
   the required direct interruption consent separately before activation.

### Decision-table template

Use one row per customization; placeholders below are a template, not findings.

| Customization / purpose / owner | Exact official target and evidence (notes + source/contracts) | Parity: full / partial / absent / unverified | Decision: migrate / retain / retire | Concrete retained gap + sunset condition | Config/data/API/behavior/safety migration + rollback | Required runtime acceptance / result |
|---|---|---|---|---|---|---|
| `<feature and required behavior>` | `<version/tag/commit; evidence links>` | `<classification with reasons>` | `<decision and rationale>` | `<gap; condition that permits official replacement, or n/a>` | `<preservation, migration and rollback steps>` | `<exact test/runtime evidence; pending limits>` |

The current exact-target source review is recorded in [Desktop decisions](official-first-desktop-016.md)
and [Copilot decisions](official-first-copilot-024.md): official
`dsh-v0.1.6-alpha.1` / commit `0a15e36e7f82b6ed45af6fa9759f29b40dcd965d`,
compared with the published paired Desktop/Copilot sources above. ASAR, Electron
Node-mode Host, public profile generations, Settings/Remote contracts, OAuth,
normal chat and subagent primitives are already official and consumed—not fork
inventions. Official Desktop README execution-path prose is stale relative to
that exact code. The reviews retain only documented gaps with migration/sunset
conditions; prefer ordinary official OAuth/chat/subagent configuration where it
meets requirements. Source parity findings do not establish an official-only
runtime replacement or authorize unconditional feature removal or activation.

## Scoped Ops CI qualification

**Current `.cloga.16` / alpha.33 qualification passed** in
[run `35575187267`](https://github.com/cloga/dsh-windows-ops/actions/runs/35575187267),
attempt 1, at exact Ops **code head**
`a59f586df4e329c3bc8b3f885013fdb5493f4970`. Native
[job `106255672689`](https://github.com/cloga/dsh-windows-ops/actions/runs/35575187267/job/106255672689)
and all four jobs passed. The later documentation/evidence-only follow-up records
this result; it does not claim a native rerun or qualification of its own head.

Artifact `10627584525` is the original **733-byte ZIP**, SHA-256
`8997486b787bbadbf7995ecf7d46f81870f813cb80488bc1008a1eea1de8b23f`.
Its sole raw `qualification.json` entry is **1,073 bytes**, SHA-256
`26c85a04e6be4616168bba93d08e838e21c45077dd3043e27855c2b51ba096d1`.
Parent verification independently authenticated the metadata, original archive and
entry bytes; this later record does not rewrite those bytes.

The summary binds the exact Desktop source/tree and installer/EXE/descriptor
above, **9,806 runtime files**, and the observed archive package
`cloga-deepseek-harness-desktop@0.1.6-alpha.1.cloga.16`, SHA-256
`fc4fda43a8921ebfaccc2c07b41cd79c69c0f2b38edba8f3ba6152273501a446`.
It records `metadata-cjs-esm`, `observerCalls:1`, `profileRemoved:true` and three
rejected request copies (descriptor digest, version and home). Fresh positive
usage proof is enforced by the exact qualified driver at the code head above,
**not by new positive-proof flags in the summary**. `wholeCarrierAttested`,
`modelResponseVerified` and `installerUpgradeVerified` remain false.
This is isolated hosted evidence, not an independent local package extraction or
live-account test. The user chose **stage-only**, without local installation,
activation or restart; live account verification awaits a future human request.

The following `.cloga.2` and `.cloga.1` receipts remain historical and cannot
certify the new pair; `.cloga.14`/alpha.32 history is linked above.

### Historical `.cloga.2` qualification

**Historical `.cloga.2` / alpha.24 qualification passed** in registered manual
[run `35278350619`](https://github.com/cloga/dsh-windows-ops/actions/runs/35278350619),
workflow `345664659`, attempt 1, at exact Ops code head
`243c33d286f19d9e4c608e238a52de2b9a136b9e`.
Called [job `105394672036`](https://github.com/cloga/dsh-windows-ops/actions/runs/35278350619/job/105394672036)
passed every step, including private cleanup. This is the same-commit reusable
callee through the registered `plugin-catalog.yml` caller, with read-only
permissions and non-cancelling qualification concurrency.

[Artifact `10521682863`](https://github.com/cloga/dsh-windows-ops/actions/runs/35278350619/artifacts/10521682863)
is the original 733-byte ZIP, SHA-256
`8cda9c1657242cefd8a0634d1b9f8f600107e80b668497008ee81700f7c4f184`.
Its sole [raw summary](../tests/fixtures/desktop-native-verified-release/ops-cloga016-2/qualification.json)
is copied byte-for-byte: 1,071 bytes, SHA-256
`6fcbe781c367d33d62351c40a9fd3edfdb5d0ac372dd2986f9884cc470f80524`.
Authenticated API metadata, original ZIP bytes and the single entry were bound
independently; no reformatting or later run is substituted.

The summary binds historical exact source `65a236bd65f2971f98b11a0efd020b8860144924`,
tree `b219bd1baa93433e9449dc72905d7980e7943a05`, and that release's installer/EXE/descriptor,
and **9,806 runtime files**. Actual `app.asar/package.json` is
`cloga-deepseek-harness-desktop@0.1.6-alpha.1.cloga.2`, raw SHA-256
`56552190b076e3f38425bac96cbd2ba20412c3957b00433181e0b9eb7d127cbe`.
The shipped public resolver/native addon/production policy passed
`metadata-cjs-esm`; `observerCalls:1`, `profileRemoved:true`, and all three invalid
**request copies** (descriptor digest, version, absent home) were rejected.
The qualified driver also checked fresh initial/restart settings JSON against
the exact locked formal digests; those assertions are not invented additional
summary fields.

Scope remains `wholeCarrierAttested:false`, `modelResponseVerified:false`,
`installerUpgradeVerified:false`: no real OAuth/model/search, local installation,
activation or installed-app upgrade. Advanced private-peer/custom-home/missing-addon
negative coverage, user-extra contents and unsupported Web/preset entrypoints
are not promoted. Final documentation/catalog/proof-only changes preserve the
qualified executable code and lock; fresh ordinary CI checks their publication.

### First attempt remains unexplained

First genuine
[run `35276462350`](https://github.com/cloga/dsh-windows-ops/actions/runs/35276462350)
at Ops head `afcfff500823b7a234796582fc7d29839d53cc4c` failed before the observer:
`native-evidence-unreadable`, `observerCalls:0`, `profileRemoved:null`. The original
failure artifact `10521525818` is 288 bytes, SHA-256
`6507bc9e41510622b57b870f14b751ae581aa7aa8a79c3504a8e439e1042e025`.
This does not establish a settings-digest mismatch, failed cleanup or payload
corruption. `profileRemoved:null` means no observer-owned home was observed.

Failure summaries now preserve only fixed-vocabulary driver stage, error category,
source-failure-file presence/readability and last recognized source phase. The
private source JSON is read with a 128 KiB bound and at most 64 timeline records;
raw error/visible text, paths, credentials and arbitrary fields never enter the
summary. Source-owned cleanup and the summary-only artifact boundary remain.
This is diagnostic instrumentation for one new qualified head, not an unchanged
blind retry, a bypass of settings proof or a modification of the immutable source.
The later success at the diagnostic head does not retrospectively prove what
caused the first failure or that a product defect was repaired.

### Historical `.cloga.1` qualification

The following is the retained historical `.cloga.1` / alpha.22 result; its hashes,
counts, source and code head must not be relabeled as proof of the new pair.

Historical genuine manual [run `35210215981`](https://github.com/cloga/dsh-windows-ops/actions/runs/35210215981)
passed at exact Ops code head `83b0303c250b62f55424be3d88347bf147c593d8`.
Its actual called job [`105165989138`](https://github.com/cloga/dsh-windows-ops/actions/runs/35210215981/job/105165989138)
completed every step, including controlled selected-payload NSIS **data**
extraction, archive-root package identity, source-owned initial/restart UI and
the awaited read-only Ops observer, summary upload and private cleanup. No
installer was executed. This historical result retains its exact qualified code
identity; neither later publication nor the current repin changes that scope.

The retained [raw Ops summary](../tests/fixtures/desktop-native-verified-release/ops-cloga016-1/qualification.json)
reports `valid:true` / `locked-release-ops-observer` and binds the unchanged
source `fae12b69dcd28413518f68b5770e40f8eb2ff730`, tree
`3ab1707c85ade70f7df5e33e95eb9991b53229f1` and the historical `.cloga.1`
installer/EXE/descriptor hashes in that raw summary—not the current target hashes above.
[Artifact `10492165208`](https://github.com/cloga/dsh-windows-ops/actions/runs/35210215981/artifacts/10492165208),
`native-asar-qualification-35210215981-1`, is a 731-byte ZIP with independently
verified SHA-256 `67a5221217841b94a4a7699a6f6db5b6b0949fea19d9e23a5b4f7eff496abb96`;
its raw 1,071-byte summary SHA-256 is
`c6066e0d632bb5777c44da193ebd695a7094195319b6835ef94ddb86031df648`.
These are evidence identities, not new release or component pins.

The summary establishes:

- **9,806 runtime files** in the completed runtime proof, with public resolver
  mode `metadata-cjs-esm`. The real shipped `PluginPackages`, its native addon,
  and the production resolution policy were exercised—not inert API stubs.
- Actual `app.asar/package.json` name `cloga-deepseek-harness-desktop` and full
  version `0.1.6-alpha.1.cloga.1`, with raw package SHA-256
  `0949ee2efc88442461c4ff9d31a8c9a5c7e747da0e7323744f1a09c3f820272b`.
  Numeric PE `ProductVersion` alone did not establish that full release identity.
- `observerCalls:1` and `profileRemoved:true`: the observer ran once after the
  source fixture's initial/restart acceptance, and its owned profile was cleaned.
- Exactly three additional invalid **request copies**—descriptor digest, version
  and absent home—were rejected against the unchanged actual fixture. These are
  not mutations of the real observer profile/runtime.

The scope remains limited: `wholeCarrierAttested:false`,
`modelResponseVerified:false` and `installerUpgradeVerified:false` are retained.
No real OAuth/model round, local installation/activation/restart, or installed
upgrade was performed. The three invalid requests do **not** establish advanced
private-peer, custom-home/generation routing or missing-addon negative cases;
source-owned ancestor-bait evidence and separately reviewed tests remain distinct.
Existing user-preset ASAR validation is still explicitly unsupported, optional
Web still requires an existing compatible physical runtime, and immutable replay
refusals remain. The successful CI run does not broaden those entrypoints or
attest user-extra package contents.

## Managed Desktop update behavior

### Persistent update notice

**Historical notice-publication evidence, not local activation:** immutable
[Desktop `0.1.5-rc.3.cloga.8`](https://github.com/cloga/deepseek-harness/releases/tag/dsh-desktop-v0.1.5-rc.3.cloga.8),
sequence 10, Release ID `390444859`, was published on **2026-09-17** from
[source `2ecd65dc2205d89c878dbe19f9b1663f9c9ffc46`](https://github.com/cloga/deepseek-harness/commit/2ecd65dc2205d89c878dbe19f9b1663f9c9ffc46).
It includes [feature PR #58](https://github.com/cloga/deepseek-harness/pull/58)
and the test-only [PR #61](https://github.com/cloga/deepseek-harness/pull/61).
[Formal run `35183054212`](https://github.com/cloga/deepseek-harness/actions/runs/35183054212)
passed packaged acceptance and the source-owned remote channel Check, which
confirmed `.cloga.8` / sequence 10 discovery.

Independent downloads verified all six assets' sizes and GitHub digests,
[`SHA256SUMS`](https://github.com/cloga/deepseek-harness/releases/download/dsh-desktop-v0.1.5-rc.3.cloga.8/SHA256SUMS),
base64 `SHA512SUMS`, canonical manifest/receipt hashes, commit/tree/tag provenance,
and source plan/lock bindings. The Windows x64 installer is **180,220,653 bytes**,
SHA-256 `a972f49279a4427e0b47b4d3fa376e29e892689937b18a10e7d948d19803ea49`.
The [`build-receipt.json`](https://github.com/cloga/deepseek-harness/releases/download/dsh-desktop-v0.1.5-rc.3.cloga.8/build-receipt.json)
SHA-256 is `34a56d9d8bf8d2ffcd584b90b4af1e1140c388eb5c7ddb35e99c02f00600d27b`.

At the time of that additive notice guidance, the [deployment lock](../deployments/windows-copilot.lock.json)
selected the separate `.cloga.7` baseline from [ops PR #178](https://github.com/cloga/dsh-windows-ops/pull/178).
The current target is published `0.1.6-alpha.1.cloga.16`; the `.cloga.8` record
above remains historical and is not relabeled as current Ops observer proof.
[Run `35210215981`](#scoped-ops-ci-qualification) remains historical `.cloga.1`
proof, and native Ops run `35278350619` is historical `.cloga.2`/alpha.24 proof.
Hosted Ops qualification for `.cloga.16`/alpha.33 passed in run `35575187267`
at exact code head `a59f586df4e329c3bc8b3f885013fdb5493f4970`, without local activation.
An existing `.cloga.5` installation does not gain the notice from
publication alone: a verified Desktop containing the change must first be safely
installed and activated by explicit user action. That Desktop can then show the
persistent notice for future available updates. This documentation update does
not authorize local activation.

- **Find it:** in a qualified Desktop containing this change, an available-update
  notice is a narrow strip at the top of the center main content, above the chat
  header. It survives navigation and renderer reload; it is not a transient toast.
  Idle state and non-Desktop Web reserve no space for it.
- **Use it:** choose **Review update** to enter Desktop's native confirmation and
  active-work checks. Review the interruption impact before consenting; seeing
  the strip or clicking Review is not blanket permission to interrupt Sessions.
  Cancelling confirmation must not start an installation.
- **Background behavior:** checks run about 10 seconds after startup and every
  6 hours. Discovery does not automatically download, install, restart, or take
  focus. An absent strip in an idle or non-Desktop view is not a failed update.
- **Safety:** publication is separate from activation. Do not install over or
  restart a running Desktop just to see this notice. Preserve other live Sessions;
  follow the consent-gated native update flow and the restart rules below.

Any later baseline promotion must separately synchronize the lock, exact-pin
validators, new formal fixtures, tests, and current guides using that release's
verified evidence; preserve historical fixtures. Simulated updater screenshots
verify only layout and state handling, not real discovery, download, installation,
or installed-app acceptance. The formal remote Check above proves channel
visibility, not an upgrade of a running Desktop. Live activation and restart
still need separate consent.

**Older-helper recovery:** historical `0.1.5-rc.3.cloga.1` and `.cloga.2` copied helpers have an
unresolved `semver` import and fail before ACK without `node_modules`. A new
release cannot repair an already installed broken helper. Use the independently
verified formal current `0.1.6-alpha.1.cloga.16` installer only after required target checks
(hosted Ops qualification passed at code head `a59f586df4e329c3bc8b3f885013fdb5493f4970`), explicit interruption
consent and a clean Desktop/Host exit, with normal interactive Windows/UAC
handling. Do not reuse the failed handoff, patch live helper files, add operation
dependencies or bypass session protection. The historical `.cloga.2` repaired
helper hash remains `2ca23e66cdf456645e1622d57759c9a37e735f758bacd93ed2c7de6af6bae424`;
the current formal helper hash is
`9819e8f7c7ee8ed6343b412cab4456a1eed13e04dc7764666de0ef7ceb8a1b70`.
Synthetic ACK tests are not proof of a completed live installer upgrade.
Generic direct registry probes do not establish a supported provisioner failure
and do not justify registry/CA/VPN/TLS changes.

The fork-owned Desktop checks for managed updates about ten seconds after
startup. This is automatic discovery, not unattended installation. After the
user confirms the impact on active work, the helper downloads and verifies the
release, waits for the exact handed-off Desktop/Host processes, and launches
the interactive NSIS installer. Windows warnings and UAC remain user-controlled;
no silent installer arguments or name-wide process termination are permitted.
Completion requires matching installed evidence and provisioning plan/receipt
on restart, not merely a successful download or installer exit.

The local-build Package/Check/Stage/Complete recovery tools remain a separate
explicit flow; they do not enable the signed native Electron updater. Before a
coordinated Web-host upgrade, re-read live `session/list` and obtain acknowledgement
of the exact running Session IDs. Native Desktop has no external Session API;
use its existing UI impact assessment and consent-gated helper. External
restart/Apply/rollback must fail closed while native session evidence is
unavailable, not treat an absent 3080 listener as zero Sessions.
Dependency downloads must pass normal TLS
verification against the release's registry. A cache-only run is not evidence
that first-install provisioning can reach its dependencies.

## What “all-in-one” means

`dsh-github-copilot` is one required DSH plugin that composes existing DSH
services. It reuses built-in `@deepseek-ai/dsh-llm-pi-ai` and pi-ai for:

- GitHub OAuth/device authorization;
- account-available Copilot model discovery through the plugin-owned managed
  provider, separate from an optional legacy canonical profile;
- credential record `llm-pi-ai/github-copilot`;
- serialized token refresh and direct Copilot model transport.

The plugin adds the authorization UI and direct provider-hosted search. Its
built client entry hands the plugin id, injected `require`, and materialized
exports to Desktop's `window.__ModuleLoader__.load` contract. Client Remote
calls use strict Zod result codecs so malformed authorization views fail closed.
Managed model metadata comes from the owning account snapshot. An intentionally
absent canonical profile remains absent. Existing canonical profiles retain
their models, APIs, and headers; legacy repair changes only the owned
strict-mode compatibility leaf and honors ownership-journal conflicts.

The plugin removes top-level `sandbox_permissions` and `justification` only from
tool schemas assembled for canonical `github-copilot` or a verified plugin-owned
`github-copilot-preview`; every other provider retains DSH's native escalation
surface. Inline hosted search supports Responses and
Anthropic Messages, while `github-copilot-hosted` through `ctx.web` is
Responses-only. Capability probing is fail-closed by default; `probe: false`
bypasses only capability proof. Requests go directly to validated GitHub-hosted
or signed-in Enterprise Copilot endpoints. There is no active local gateway,
port 7777 dependency, pasted GitHub token, placeholder API key, or separate
search-provider package.

The thirty-two required plugin capabilities are copied from the immutable
artifact's exported `deployment-baseline.json`, including
`desktop-shared-package-ownership`. Authorization and schemastery are required
host peers, not plugin-owned runtime dependencies; private or optional copies
fail the Windows Ops package contract. The plugin retains its own
`@earendil-works/pi-ai@0.85.1` and `zod@^4.4.3` runtime dependencies.
The peer range admits `0.1.6-alpha.1`, now selected as the locked
Desktop-bundled ASAR Core. Package admission is not live Models
validation and never authorizes an independent Core upgrade.

ACP subagents remain separate; see
[`copilot-acp-subagent.md`](copilot-acp-subagent.md).

## Core 0.1.3-alpha.1 readiness record

[`core-0.1.3-alpha.1-desktop-cutover.md`](core-0.1.3-alpha.1-desktop-cutover.md)
records reviewed companion-plugin evidence and local risk reduction. It is a
non-executable readiness record: the cutover remains blocked until an official
Desktop-managed target and the complete lock/catalog/fixture/test baseline are
updated together. It does not change the locked baseline on this page.

## Check first

### User preset Config compatibility (managed entrypoints only)

A preset can remain on disk but stop mounting after an official runtime schema
change. The September 2026 persona incident was **not file loss**: the persisted
`config.text` still held the instructions, while upstream
`deepseek-ai/deepseek-harness@40792330c0d534ef382bbf1fb44c9289323bbb27`
changed the persona contract to required `prefix` and optional `suffix`.
A cold resume then failed on missing `prefix`. Recovering a reviewed key while
preserving its content restored the affected tasks and model UI; copying a
default preset over the user's instructions is not a safe recovery.

Check and Verify now run `Test-DshUserPresetConfig` before other runtime checks.
The locked Apply implementation runs the same gate before Desktop inspection,
artifact extraction, backup creation, npm, process or Profile mutations.
`-SkipRuntimeChecks` does **not** disable this gate. Incompatibility or an
uncheckable scope returns `checks.userPresetConfig.valid = false` and exit code
**2** from Check/Verify; Apply throws `user-preset-config-blocked`.
The direct installation health report also includes `profile.userPresetConfig`.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-windows-copilot.ps1 `
  -Action Check -DshHome (Join-Path $HOME '.dsh') -SkipRuntimeChecks
```

The scope is direct child directories of the explicitly resolved, fully qualified local
`<DshHome>\.agent-presets`, each containing `agent.cordis.yml`. Missing
compositions, reparse points, malformed YAML, conflicting metadata, unresolved
plugins and dynamic **config** fail closed. Non-config `!!js` control predicates
are left unevaluated; even disabled rows are conservatively checked. Nested
literal `group` lists are checked recursively. Custom preset roots, relative/file
plugins, package subpaths, custom loader hooks and include/tree-carrier plugins
are unsupported rather than guessed healthy. Limits are 128 manifests, 1 MiB
each / 8 MiB total, 4,096 rows, 32 group levels and 256 diagnostics.
An absent or empty user roster reports `no-user-presets` without creating it or
requiring target artifacts; it does not attest an absent target runtime.

For a nonempty roster, the target is the lock's `acceptance.runtimeSchema`, not
the current process, global npm packages or Profile overlays. **The selected `.6`
ASAR target does not support this historical whole-wrapper preset validator.**
It reports `user-preset-config-blocked` with
`unsupported-asar-target-validation` before physical target reads or imports;
existing user presets are not skipped and cannot be reported valid. The empty
roster success above does not establish ASAR preset-schema validation. Do not
extract/copy Core or replace a running runtime to evade this boundary.

For a separately supported physical target only, the historical validator uses
an isolated Node subprocess and its attested `entryListSchema` / published
Standard Schema `Config` contract. It does not start Cordis or invoke plugin
apply, boot, resume, model or provider APIs. A plugin without `Config` reports
`schema-less-passthrough`, not application-level config validity. Conflicting
exports, malformed schemas and async validators block it; normalized values are
discarded without migration/write-back. Those physical-worker mechanics are not
an implemented ASAR validation path.

That physical-target child runs with Node read-only filesystem permissions, no inherited
credentials/Node preload environment, no child processes/native addons/workers,
and disabled network entrypoints. Imports or validators needing those facilities
are unsupported. This is isolation for reviewed, attested code, not a sandbox
for hostile plugins. The worker has a 20-second default deadline (maximum 60),
192 MiB V8 heap and bounded output. Diagnostics contain only preset-relative
paths, positional rows, plugin/version, schema-declared key paths (unproven
segments become `*`), stable codes and review actions. Parser buffers, schema
messages, prompt values and child stdout/stderr are never forwarded.
Input hashes are rechecked before reporting; the result is a point-in-time
assessment, not a lock against concurrent external edits.

**Boundary:** this protects these managed entrypoints only. It cannot intercept
arbitrary official Desktop GUI updates, and does not claim that it does.
It does not rewrite presets, change scheduler tasks, migrate credentials,
install dependencies, patch Core or restart Desktop/Host.

The one-command check is read-only:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-windows-copilot.ps1
```

Check mode validates the lock, fork-owned Desktop release, installed executable
hash, Desktop-managed runtime descriptor, native provisioning capability and
actual reserved-profile release inventory. It binds the exact active Electron
parent/Node-mode Electron Host relationship rather than a Web listener. Missing evidence, wrong
paths, stale processes and payload drift cannot pass. Its JSON keeps
`valid=false` because native live Remote/model evidence is unavailable to this
CLI; `staticValid` describes structural evidence only.

In the legacy Web mode only, check compares the Copilot dependency in
`package.json`, the matching `pnpm-lock.yaml` importer and tarball, the installed
package manifest, exported deployment baseline, and artifact SHA-256. A mismatch
is reported as `profile-manifest-lock-installed-drift`; check mode never repairs
it. A missing `llm-pi-ai/github-copilot` grant is reported as
`sign-in-required`. Credential payloads are never included in output.

To preflight an exact local plugin artifact without applying:

```powershell
Import-Module .\tools\WindowsCopilotDeployment.psm1
$lock = Read-WindowsCopilotLock .\deployments\windows-copilot.lock.json
Test-ProviderDeploymentContract -Lock $lock `
  -ArtifactPath C:\artifacts\dsh-github-copilot-0.4.0-alpha.24.tgz
```

## Apply the locked Desktop and plugin

For the current native lock, use Desktop's existing managed update UI and its
consent-gated interactive installer helper. The packaged exact plan provisions
alpha.24 at startup. Windows Ops `-Apply`, `-RestartDesktop`, rollback and
`-IncludeCompanionSuite` cannot stand in for native Session assessment and are
rejected by this entrypoint. Do not manually materialize `profiles\desktop`,
copy `node_modules`, or run a profile-local package install.

The legacy `windowsOpsVerifiedRelease` mode retains its explicit Apply/backup
contract and exact `session/list` acknowledgement. Those legacy commands are
not a recipe for this native lock. Optional companions remain Web-only and
must not be added to the required native plan. Dry-run never stops a process.

## Bootstrap, sign in, and accept

For the current native Desktop, use the real Models account UI to sign in and
select an account-available model, then obtain an actual model response.
The following historical wrapper applies only to its supported physical
`desktop-official` / `desktop-managed-download` Web/headless contract. It rejects
the current native fork before CLI/renderer/schema mutation; it does not
configure or verify this Electron/ASAR Host:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\enable-copilot-search-vision.ps1 `
  -CopilotIntegrationPackage C:\artifacts\dsh-github-copilot-0.4.0-alpha.24.tgz
```

The package argument may be the exact locked GitHub Release URL or a local copy
whose SHA-256 matches the lock; npm is not a distribution channel. The wrapper
installs `dsh-github-copilot` in `web` and `headless`, configures only the
plugin and `github-copilot-hosted` search selection, removes reviewed legacy
route references, and reports credential metadata without exposing grant
payloads. It does not write provider routes, model lists, base URLs, or API-key
references. Despite its historical file name, it does not install
`dsh-vision-any` or another visual fallback. Image-capable models receive
uploaded attachments through DSH's native image channel, and Agents use the
built-in `read_image` tool to open workspace image files. Text-only models must
be switched to an image-capable route rather than silently delegating the image
to a second provider.

Open **Models → GitHub Copilot**, complete the displayed device flow, and choose
only a model present in the account-filtered route. Then run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\enable-copilot-search-vision.ps1 `
  -Action Verify `
  -Model '<account-available-model-id>'
```

Acceptance requires all of the following:

1. direct sign-in succeeds and the shared Copilot grant remains payload-redacted;
2. a direct model response succeeds with the selected account-available model;
3. direct hosted search succeeds without a local gateway endpoint;
4. a reasoning response renders nonempty reasoning without blank Think cards;
5. a fresh Session accepts the Copilot-scoped Tool Schema while non-Copilot
   providers retain the native schema;
6. native Desktop has exact installed/Host identity plus independently observed
   UI/model evidence; only a separate Web deployment requires its owning IPv4
   listener at `127.0.0.1:3080`.

## Optional Web-profile overlays

`dsh-playwright-host@0.1.7` and `dsh-cron@0.7.1` are reviewed immutable optional Web
overlays for Core `0.1.6-alpha.1`. Source and artifact-byte verification do not
establish local activation or a live browser/scheduler smoke. The selected
Desktop ASAR runtime is not a physical Web import/junction target: the current
optional installer requires an already-existing compatible physical
`-RuntimeRoot` or reports `physical-web-runtime-required` before downloads,
imports or its mutex. It does not install a second/private Core or offer an
invented Electron CLI resolution mode. `-IncludeCompanionSuite` applies only to
legacy Web provisioning; the current native entry rejects it. For supported
Web targets, exact source, artifact, closure and bundle state remain strict gates. When not selected, a
configured-source mismatch is inventory/warning data rather than base-baseline
health. `dsh-github-copilot` remains required and cannot be removed by
optional-overlay removal. See
[`computer-use.md`](plugins/computer-use.md) and
[`scheduling.md`](plugins/scheduling.md).

The native baseline validates the reserved `profiles\desktop` profile through
the packaged plan and actual receipts/state/inventory. Separate `profiles\web`
and `profiles\headless` installations are not native success evidence.
Do not install ordinary plugin dependencies into that profile with profile-local
`pnpm install`: it can hoist reserved host packages such as
`@deepseek-ai/cordis` into `profiles\desktop\node_modules` and make Desktop
reject the profile at startup. Desktop UI visibility must come from a Desktop-native plugin
provisioning path, not from mutating the reserved profile as an ordinary DSH
profile. Static inventory alone still does not prove an authenticated account,
active Session model selection, or successful model response.

## Legacy migration and rollback

This section applies only to legacy Web operations and their receipts. Native
external rollback is blocked; use the supported native recovery path with
live impact assessment, never these commands against a running native Host.

Legacy gateway facts remain migration signatures only, never active components
or success criteria. Run check mode first, retain its redacted result, and apply
only when detected files or configuration match the reviewed migration
contract. Unknown binaries or references fail closed.

Every mutation is backed up before profile, route, credential-reference, or
legacy cleanup. When Apply installs Desktop, the same operation also snapshots
the install directory, uninstall registry key, and user Desktop/Start Menu
shortcuts. Roll back an installer operation with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\install-windows-copilot.ps1 `
  -Action Rollback `
  -OperationId '<operation-id>' `
  -BackupRoot C:\dsh-ops-backups
```

The bootstrap has its own receipt-backed rollback:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\enable-copilot-search-vision.ps1 `
  -Action Rollback `
  -OperationId '<bootstrap-operation-id>'
```

Rollback does not waive restart safety. If a restart is requested, query live
Sessions and acknowledge the exact running IDs as described above.

## Verification

Repository-only checks do not touch the active deployment:

```powershell
node tools\validate-repository-content.mjs
node tools\validate-plugin-catalog.mjs
Invoke-Pester -Path tests
```

Machine-state verification needs no DSH path:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\install-windows-copilot.ps1 -Action Verify
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\dsh-replay.ps1 -Action SelfCheck
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\dsh-replay.ps1 -Action Apply -DryRun
```

Inspect explicit unsupported/not-ready statuses; neither exit zero nor a
synthetic fixture proves native readiness. The historical physical runtime-schema
validator does not validate the selected ASAR target. Browser smoke is only for
an independently existing Web surface, never a replacement native Host:

```powershell
python tools\dsh-web-smoke.py --expect-text "New Session" `
  --fail-on-console-error --fail-on-request-failure --fail-on-http-error
```

### Native structural versus functional acceptance

The published alpha.24 metadata retains React through `dsh.client.external`
as a Client static singleton. React must not reappear in root dependencies,
optional dependencies or peers: alpha.21 failed real Desktop startup when its
React peer was evaluated against the Node Host graph, corrected in alpha.22.
Authorization and schemastery remain required Host-owned peers; plugin-owned
pi-ai/zod checks remain exact. Alpha.24 additionally declares the Client
`remote.githubCopilotSearchRouting` dependency missing in alpha.23. Actual
packaged Model roles/search-routing DOM and read-only catalog acceptance are
required alongside metadata; neither establishes a real search/model response.

Native Check/Verify verifies the lock-selected installed PE identity, the exact
descriptor-attested runtime inventory, the release-owned provisioning plan and
capability, the reserved Desktop profile, immutable local plugin artifact,
receipt/reconciliation state and every published required-plugin JavaScript
entrypoint. The active Host must be a direct child of that Desktop executable,
using the same locked Electron EXE in Node mode with the exact policy preload,
Host script, ASAR runtime root and `profiles\desktop` arguments. Physical bundled
upstream Node is reserved for pnpm/helper work, not substituted as this Host.
No global npm root, Web profile, credential record or canonical route is used
as native evidence.

Ownership metadata preserves user extras: explicit owners are a complete
receipt-key map of `user`/`release`; absent legacy ownership is inferred only in
memory from matching plan/state/receipt/spec evidence, otherwise user-owned.
Required Copilot may remain user-owned after an exact same-source reinstall,
but all required source/archive/receipt/enabled-state/peer proofs remain exact.
Off-plan release-owned receipts fail. Valid user verified/registry/snapshot
metadata is allowed with `userExtras.contentsAttested=false`, not declared
healthy or baseline-attested. Source-snapshot metadata alone does not prove its
archive exists or is intact. Four raw metadata hashes, including optional-file
absence, bind outer and inner checks; no check-time migration is performed.

Replay and higher-level Desktop identity obtain ASAR runtime identity from the
bounded native audit, with the caller's explicit Harness home, not PowerShell
reads of virtual descriptor paths. EXE bytes, PE metadata/signature and exact
audited version/root/descriptor correlation remain mandatory. This fixes a false
structural failure and its propagated Host-binding failure without weakening
Host argv matching or upgrading/reloading a plugin. Archive and canonical
`resources/app.asar.unpacked/dsh` patch targets remain immutable/unsupported even
in Verify/DryRun; Native Apply/Rollback remains delegated. The [historical Ops
qualification](#scoped-ops-ci-qualification) in run `35210215981` applies only to
`.cloga.1`/alpha.22. Historical `.cloga.2`/alpha.24 qualification passed in run
`35278350619`; current `.cloga.16`/alpha.33 hosted Ops run `35575187267` passed at
exact code head `a59f586df4e329c3bc8b3f885013fdb5493f4970`.
Read-only replay neither substitutes for qualification nor broadens its scope.

The Electron Host uses parent-owned byte pipes and `dsh-app://`, not an HTTP
listener on port 3080. The Web smoke command above applies only to a separately
running Web/headless surface. No replacement HTTP Host is started. Native
functional acceptance remains `manual-verification-required`; Verify exits 2
and does not count unknown Remote evidence as success. Independently inspect
the real Electron Models/account UI and obtain a real model response. That
operator evidence is separate; it does not make this CLI return a functional
pass.

The plugin's strict read-only `githubCopilot.status()` and
`githubCopilot.migrationStatus()` projections require the exact loaded plugin
version, protocol 1, complete provider registration, a signed-in non-in-flight
authorization state, a ready account model projection and the exact model.
Requested live Session selections must also match, including the recorded
request selection for running Sessions. `nativeConfigured=false` and canonical
`route.state=not-configured` are valid for the managed provider
`github-copilot-preview`; do not recreate a canonical profile. The pure
projection assessment helper is not a live transport or a full-baseline proof.
Do not call `ensureModels`/`discoverModels`, which may refresh OAuth or network
state, merely to perform a read-only check.

External native Remote attachment is not available in the current public
Desktop contract. Therefore legacy external Apply, rollback and restart cannot
use Web `session/list` or a missing port 3080 as proof of zero native Sessions.
Those operations fail closed in native mode. Use the existing native updater's
live impact assessment and exact interruption acknowledgement, followed by
interactive installer/UAC handling and post-restart evidence.
