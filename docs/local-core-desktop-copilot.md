# Locked DSH Desktop and direct GitHub Copilot

## Newer account-discovered route maintenance

For the V3 account/Session model separation and removal of an existing extra native Copilot route, use [the separate config-only managed-route procedure](copilot-managed-route.md). Do not recreate native model definitions from this pinned full-deployment guide or run its installer merely to migrate a newer Desktop. The maintenance command performs no component installation, Session/default selection, credentials access or restart; it requires fresh live evidence and explicit configuration approvals. Its policy does not replace the full deployment lock below.

## Authoritative baseline

[`deployments/windows-copilot.lock.json`](../deployments/windows-copilot.lock.json)
is the machine-readable deployment contract, verified on **2026-09-17**.
The stable deployment ID remains `windows-copilot-2026-09-15`; this date update
identifies the reviewed published target, not a new local installation.

| Component | Locked identity |
|---|---|
| Desktop | fork-owned `0.1.6-alpha.1.cloga.2`, sequence 12, release tag `dsh-desktop-v0.1.6-alpha.1.cloga.2`, commit `65a236bd65f2971f98b11a0efd020b8860144924` |
| Desktop artifact | [`cloga-deepseek-harness-0.1.6-alpha.1.cloga.2-win-x64.exe`](https://github.com/cloga/deepseek-harness/releases/download/dsh-desktop-v0.1.6-alpha.1.cloga.2/cloga-deepseek-harness-0.1.6-alpha.1.cloga.2-win-x64.exe), 171,301,229 bytes, SHA-256 `cf140d49b8df9096b52fba365066ef4eeee06eed57ca0f16c2fc319f1e5f0970` |
| Desktop-managed runtime | virtual root `%LOCALAPPDATA%\Programs\DeepSeek Harness (cloga)\resources\app.asar\dsh`; the interactive installer may use a different `$INSTDIR`, so Windows Ops follows the actual installed `cloga-deepseek-harness.exe` path |
| Expected installed Desktop identity | executable SHA-256 `3406cf490050168cc3b38f78c354bafabf7b7a05f3ded2331d82b55300f2bb88`; virtual descriptor `resources\app.asar\dsh\desktop-runtime.json` SHA-256 `f0de4a61ead7105c41f1576a2f01617908e80e214c6c5383c9b79a13d50a14d1`; formal source evidence, with current native Ops qualification pending, not local installation |
| Runtime attestation | release manifest schema 3, self SHA-256 `52a2f43210cd694c06ff38452353473fc0cea47ba758959c573d1fbb66324090`, raw SHA-256 `724214036567ddea1d6fb79bbfd4daa6c87eada4c00022ef4b0fa9170d93ff59`; bundled `@deepseek-ai/dsh@0.1.6-alpha.1`, runtime descriptor schema 1 / Host protocol 3 |
| Copilot plugin | `dsh-github-copilot@0.4.0-alpha.24`, immutable Release source commit `e49bf7c9307cf22dd9ea720bed8750101fc986ed` |
| Plugin artifact | Immutable Release [`dsh-github-copilot-0.4.0-alpha.24.tgz`](https://github.com/cloga/dsh-github-copilot/releases/download/v0.4.0-alpha.24/dsh-github-copilot-0.4.0-alpha.24.tgz), 660,977 bytes, SHA-256 `f28dd95e136e203948be8af43745c43ed32bd0bb9b84a44107c4b11ebf7e75cd`, SHA-512 SRI `sha512-F0kqe2wy2kHgodDw69Ouz1Gm/MSWEkkNloNs2yiskYH0790rMntvRO8ytJFSr33OsGbJkyXGx/oWl5xXlPTnGg==`; verify with the same Release's [`SHA256SUMS`](https://github.com/cloga/dsh-github-copilot/releases/download/v0.4.0-alpha.24/SHA256SUMS), digest `2480327ffa2b6154ad8d151db97329c26b680f898a0c823f9706ec1131b6c0aa` |
| Desktop native capability | `desktopNativeVerifiedRelease`; generic plugin compatibility evidence is present, `automaticProvisioning=false`, and Windows Ops no longer mutates the Desktop profile through the external workaround |

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
Authenticode `NotSigned`; its semantic release is `0.1.6-alpha.1.cloga.2`.

**Published paired source target; native Ops qualification pending:** source-owned
formal acceptance passed for `.cloga.2`/alpha.24. The previous `.cloga.1` Ops run
is retained [below](#scoped-ops-ci-qualification) as historical evidence only;
it cannot qualify this changed release. Publication does not install or activate it locally.

The current immutable [Release](https://github.com/cloga/deepseek-harness/releases/tag/dsh-desktop-v0.1.6-alpha.1.cloga.2)
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
`cloga/deepseek-harness#44`. Those fixes remain in the current release; their
historical acceptance, including preserved `.cloga.7` fixtures, is not relabeled as `.6` evidence. The current schema-3
update manifest intentionally retains `automaticProvisioning=false` so the old
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

Current formal source acceptance artifact `10518683372` from run `35271210350`
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

**Current `.cloga.2` / alpha.24 qualification is pending.** The following is the
retained historical `.cloga.1` / alpha.22 result; its hashes, counts, source and
code head must not be relabeled as proof of the new paired release.

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
The current target is published `0.1.6-alpha.1.cloga.2`; the `.cloga.8` record
above remains historical and is not relabeled as current Ops observer proof.
[Run `35210215981`](#scoped-ops-ci-qualification) also remains historical `.cloga.1`
proof; current native Ops qualification is pending. An existing `.cloga.5` installation does not gain the notice from
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
verified formal current `0.1.6-alpha.1.cloga.2` installer only after required target checks, explicit interruption
consent and a clean Desktop/Host exit, with normal interactive Windows/UAC
handling. Do not reuse the failed handoff, patch live helper files, add operation
dependencies or bypass session protection. The repaired helper hash is
`2ca23e66cdf456645e1622d57759c9a37e735f758bacd93ed2c7de6af6bae424`;
its synthetic ACK test is not proof of a completed live installer upgrade.
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
`.cloga.1`/alpha.22. Current `.cloga.2`/alpha.24 qualification remains pending;
read-only replay does not substitute for that proof or broaden its scope.

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
