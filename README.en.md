# dsh-windows-ops

[![Windows deployment lock](https://github.com/cloga/dsh-windows-ops/actions/workflows/windows-copilot-lock.yml/badge.svg)](https://github.com/cloga/dsh-windows-ops/actions/workflows/windows-copilot-lock.yml)
[![Plugin catalog](https://github.com/cloga/dsh-windows-ops/actions/workflows/plugin-catalog.yml/badge.svg)](https://github.com/cloga/dsh-windows-ops/actions/workflows/plugin-catalog.yml)
[![License](https://img.shields.io/github/license/cloga/dsh-windows-ops)](LICENSE)

**English** | [简体中文](README.md)

> Windows deployment baselines, operations tooling, and a community-plugin validation catalog for DeepSeek Harness (DSH).

This repository captures DSH Desktop/Copilot deployments, diagnostics, recovery procedures, and integrations verified on real Windows systems. It does not redistribute Desktop, DSH, or third-party plugins. Exact locks and acceptance contracts define the supported baseline.

## UI fixture appendix

Start with the canonical [bounded release-debugging checklist](docs/core-upgrade.md#bounded-release-debugging).
Its [UI fixture appendix](docs/small-ui-change-validation.md) covers actual renderer
navigation, physical Slot layout owners and immutable same-run evidence. It is not a
second release process or permission to install, activate or restart.

## Offline original-ZIP audit tooling

The [offline ZIP/member audit guide](docs/artifact-zip-audit.md) documents the
read-only, stdlib-only auditor and its 59 inert tests in the existing Linux
repository-content CI job. [Run 35648331069](https://github.com/cloga/dsh-windows-ops/actions/runs/35648331069/job/106494196178)
passed **59/59** on Linux with Python 3.12.10/zlib 1.3 at tested head `88cc734`
(tree `e558600`); the guide records the exact checkout and hashes. This is not
qualification of the later documentation commit. **Windows validation failed
and remains HOLD USE**; Linux evidence neither qualifies Windows/the product
nor approves real-artifact use. The tool does not download, extract, install,
execute archive code or activate Desktop.

## DSH Core upgrade entrypoint

For "adapt to a new DSH Core release", start with the [official-first upgrade
workflow](docs/core-upgrade.md). Review Core fork, Copilot, cron and Playwright
customizations against exact official source/contracts before carrying them forward;
prefer official replacements after parity and migration acceptance are proven.
[`core-upgrade-scope.json`](deployments/core-upgrade-scope.json) defines the scope.
`node tools/plan-core-upgrade.mjs --tag dsh-v<version> --commit <full-SHA>` only emits
an unexecuted plan. It does not install/restart or change the qualified deployment lock.

See the [Desktop release boundary](docs/core-upgrade.md#desktop-release-boundary) for product/channel-first acceptance and safe immutable-release withdrawal.
Use the [bounded release-debugging checklist](docs/core-upgrade.md#bounded-release-debugging)
to freeze candidate scope, diagnose a whole failed attempt, verify real UI/native
prerequisites and preserve separate qualification stages before another expensive run.
It documents process lessons, not a new qualified release, artifact-reuse workflow or activation permission.

The [0.1.6-alpha.2 assessment](docs/core-016a2-assessment.md) records exact official
replacement evidence, retained differences and concrete API issues. It remains
source-review evidence, not a new qualified deployment baseline.
[Native combined-v3 reader preparation](docs/core-016a2-assessment.md#alpha2-native-combined-v3-reader-preparation)
explicitly supports settings3/Copilot35 and same-run native evidence while preserving
historical formats; it neither promotes the lock nor claims qualification.
Later merges, releases, hashes and acceptance limits are recorded in the
[delivery evidence](docs/core-016a2-delivery.md). Historical Cron 0.7.3, Playwright
0.1.8 and Copilot alpha.25 publication receipts remain intact.
[Copilot alpha.28 publication](docs/core-016a2-delivery.md#copilot-alpha28-publication-checkpoint)
remains historical. The current published Ops target is published Desktop
`0.1.6-alpha.1.cloga.17` / sequence 28 / bundled Core alpha.1 / Copilot alpha.33.
Published artifacts are independently verified; fresh hosted Native Ops run `35595040585`
attempt 1 passed at exact code head `bb7a0a366e789b19918be6d8a6e40266c46a94f9`.
See the [external-link maintenance release record](docs/desktop-external-links-17.md).
Alpha.33 admits official Core alpha.2, but separately owned draft Desktop PR 68
is unqualified and is not promoted by this maintenance release. Publication and
formal source acceptance do not install or activate the pair locally and do not
prove live compaction rescue, OAuth, model or search behavior.
See also [native loader dependency and mirror qualification](docs/core-016a2-assessment.md#native-loader-dependency-and-mirror-qualification):
`node-addon-require-builtin@0.1.6` belongs to official boot. Candidate 0.1.5 passed
standalone Node smoke but failed an actual native call under Electron 44. Historically
attested deployed 0.1.6 bytes passed main/two-Worker probes in the same carrier,
supporting retention of 0.1.6—not npm-archive equivalence or full Core qualification.
The same section distinguishes optional
CUA test dependencies and pnpm 11's workspace-root inclusion during filtered installs.

See [pnpm 11.7 dispatch and offline-policy boundaries](docs/core-016a2-assessment.md#pnpm-117-dispatch-and-offline-policy-boundaries):
`pm` must be the first argument, and `--offline` does not guarantee that supply-chain
verification avoids registry metadata requests. Do not disable verification to hide failures.

Use the [remote qualification checklist](docs/core-upgrade.md#remote-qualification-checklist)
for company-restricted local npm: do not repeatedly retry or ask users to unblock
access/supply packages; use approved CI for dependency checks and publication.
Standing authorization narrowly defers demonstrated environment-blocked local
hooks/checks per PR to equivalent required remote checks, never source failures or
remote gates. Preserve complete lint, exact-head/lock artifact evidence and native
acceptance. Desktop still ships its installer, not substitute tarballs or hidden
startup access to restricted public npm; local restrictions alone do not block release.
The [Core candidate evidence](docs/core-016a2-delivery.md#core-candidate-remote-evidence)
is not release-qualified; it authorizes no lock promotion or current Desktop install/restart.

**Alpha.2 compatibility preparation remains separate:** the native descriptor
validator requires Host protocol 4 only for exact Core `0.1.6-alpha.2`; legacy
protocol 3 and synthetic-only checks remain intact. The current published Ops target
Desktop `.cloga.17` keeps bundled Core alpha.1. Alpha.33's alpha.2 admission does not
qualify or deploy the draft alpha.2 Desktop. See [strict preparation boundaries](docs/core-016a2-assessment.md#strict-native-compatibility-preparation).

**Combined-evidence preparation is not promotion:** [Ops #181 preparation](docs/core-016a2-assessment.md#alpha2-combined-packaged-evidence-preparation)
separates imported formal functional/failure/observer/suite evidence, with ordinary
acceptance absent, from a fresh Ops resolver observer that succeeds through the
ordinary acceptance path after cleanup. Explicit `combined-suite-v2` preparation
requires functional/ordinary schema 2 and original-hash-bound `positive-usage.json`
under the reviewed Copilot alpha.33 Client policy; v1 and legacy alpha.1 readers
and history remain intact. Synthetic Client unit tests are not hosted execution
of the actual released Client. Genuine Ops caller identity stays separate
from verified Core checkout identity; the private Ops source archive is not a Git
checkout. The exact successful Core CI summary can
attest installed checks whose root records were not archived; it does not enable
full offline replay. This alpha.2 preparation changes neither the six-asset public
contract nor the Core alpha.1 scope of the current `.cloga.17`/alpha.33
target, qualified by fresh hosted Native Ops run `35595040585` attempt 1 at exact
code head `bb7a0a366e789b19918be6d8a6e40266c46a94f9`. Historical `.cloga.16`
formal/Ops proof stays in its [owning record](docs/copilot-alpha33-upgrade-record.md)
and cannot qualify `.cloga.17`. Alpha.2 is unpublished and unqualified; this preparation
does not authorize installation, activation or restart.

See [dual-v2 composer proof preparation](docs/core-016a2-assessment.md#alpha2-dual-v2-composer-proof-preparation):
explicit51 inputs, functional3/settings3/native2/seed6 and fixed alpha35 Client
policy, retaining21-key positives, own raw hashes and genuine fresh Ops identity.
Old formats/current pins stay unchanged; this is not promotion, original-ZIP
verification or activation permission.

## Copilot account-discovered route maintenance

For a newer Copilot installation moving from two routes to the account-discovered directory, use the [check-first configuration maintenance flow](docs/copilot-managed-route.md) and separate [`copilot-managed-route.policy.json`](deployments/copilot-managed-route.policy.json). It permits only explicitly approved path-level settings CAS: no component installation, restart, or automatic Session/default changes. It does not replace or downgrade an existing Desktop to the separate deployment target below. The policy release must be verified, its exact plugin version must be loaded, and cold-history implications require acknowledgement. This is not a new full Desktop/Core attestation.

## Identify the running Desktop version

See [Desktop version identification](docs/local-core-desktop-copilot.md#identify-the-running-desktop-version)
for the complete native About-menu version, the distinction from Core and update
candidates, and read-only executable metadata for older builds. The feature first
ships in verified immutable [Desktop `0.1.6-alpha.1.cloga.12`](https://github.com/cloga/deepseek-harness/releases/tag/dsh-desktop-v0.1.6-alpha.1.cloga.12).
Formal source evidence does not install or activate it locally.

## Current published Ops deployment target (exact code head qualified)

[`deployments/windows-copilot.lock.json`](deployments/windows-copilot.lock.json) is authoritative. Published artifacts and formal proof were independently verified on **2026-09-21**; **fresh hosted Native Ops run `35595040585` attempt 1 passed for `.cloga.17`** at the exact code head below. Earlier target success cannot transfer; later documentation/evidence commits or a merge are not relabeled as native-qualified.

| Component | Target identity |
|---|---|
| DeepSeek Harness Desktop | fork-owned `0.1.6-alpha.1.cloga.17`, sequence 28, immutable Release `392847203`, source `f25506b4ad190ce090b8a4e9602c7ad36179db6b` |
| Desktop-managed DSH runtime | bundled `@deepseek-ai/dsh@0.1.6-alpha.1`; descriptor SHA-256 `eca8a91da4737f625716323d0be8a51156b24934183904a41d06599ffafe36bd`; default ASAR root follows the installed EXE |
| Required `dsh-github-copilot` | immutable `0.4.0-alpha.33`, source `aa90fe434da8b2172faa1446afa0a0fd006afe00`; delegated through `desktopNativeVerifiedRelease` |
| Formal packaged evidence | [run `35583602522`](https://github.com/cloga/deepseek-harness/actions/runs/35583602522), attempt 1 **SUCCESS**; source-bound initial/restart settings/version-menu, signed-out usage and synthetic positive usage proof |
| Native Ops qualification | [run `35595040585`](https://github.com/cloga/dsh-windows-ops/actions/runs/35595040585) attempt 1 **SUCCESS**, exact code head `bb7a0a366e789b19918be6d8a6e40266c46a94f9`; native job `106318363183` and all four jobs passed; independently bound [raw summary](tests/fixtures/desktop-native-verified-release/ops-cloga016-17/qualification.json) and [provenance](tests/fixtures/desktop-native-verified-release/ops-cloga016-17/README.md) |

This runtime-only Desktop external-link maintenance keeps Core and Copilot unchanged;
it adopts neither Core alpha.2 nor Copilot alpha.34. The [owning release record](docs/desktop-external-links-17.md)
binds all six assets, source/hashes and acceptance limits. The new 1,073-byte Ops summary
has SHA-256 `6ad0298788578353c6ef306ddeec225c785d335631f06b7d38c1f879cc526fee`;
whole-carrier/model-response/installer-upgrade flags remain false. First native run
`35590167413` remains an unexplained startup failure with its original not-ready evidence
retained; later diagnostics did not prove its cause was repaired. Ordinary CI `35593395998`
instead exposed an LF/CRLF test-extraction defect, fixed test-only at `bb7a0a3…`, not a runtime failure. The actual Electron DOM
activation fixture substitutes the OS opener; it does not prove real browser navigation
or OAuth. Delivery remains **stage-only**, with no local installation, activation or restart.

### Historical `.cloga.16` / alpha.33 qualification (not `.cloga.17` proof)

Historical [run `35577921833`](https://github.com/cloga/dsh-windows-ops/actions/runs/35577921833), attempt 1 **SUCCESS**, qualified exact combined Ops code head `cd384495ac2fd0c850b3c8cd93223d35c4bc83a0`; native job `106264308921` and all four jobs passed.
Initial qualification at `a59f586…` and evidence-only follow-up `c868c689…` remain
history. After merging protected master `43630e4…` / PR #212, the **combined head
`cd384495…` passed its own fresh native run** above; earlier success was not transferred.
That historical provenance-only follow-up preserves code/lock/raw evidence and is not itself
the native run's head. See the [integration checkpoint](docs/copilot-alpha33-upgrade-record.md#concurrent-master-integration-checkpoint). The 1,073-byte raw summary's
SHA-256 is `26c85a04e6be4616168bba93d08e838e21c45077dd3043e27855c2b51ba096d1`.
Fresh positive proof is enforced by that exact driver, not new summary flags.
Whole-carrier/model-response/installer-upgrade flags remain false; historical
`.cloga.14`/alpha.32 run `35553019059` cannot be transferred.

Formal acceptance verified read-only current-workspace state, Model roles, equal
`deepseek-official`/`github-copilot-hosted` catalogs, provider-only routing,
Fallback labeling, exact Desktop About-menu identity and absent signed-out usage surface after account readiness across restart.
The added schema-1 `usagePositiveAcceptance` uses the released Client and actual
renderer/SessionProvider/Slot with synthetic Session/quota/test mount. Canonical
and preview cases run once after the restart graph. [Formal proof and hashes](docs/copilot-alpha33-upgrade-record.md)
are authenticated, not pending artifacts; they are not live account/network proof.
Formal release run `35569892548` attempt 1's `EBUSY` helper-cleanup failure remains history. Acceptance did not
instrument Host requests or perform live quota, OAuth, verification navigation,
model/search calls, save/create, local installation or restart. External-navigation
success remains unqualified.

### Current target runtime and safety boundaries

A lock update defines the reviewed target, not installed-machine state. The `.cloga.17`
hosted Native Ops success binds only exact code head `bb7a0a366e789b19918be6d8a6e40266c46a94f9`. Do not run
a future-lock current-machine Check while installed Desktop remains `.cloga.10`;
expected drift is not release failure. The managed helper remains interactive and
requires separate active-Session impact confirmation and Windows/UAC interaction.
The explicit choice is **stage-only**: no local installation, activation or restart.
Live account verification is deferred until a future human request, not an
automatic next step after publication or CI success.

The legacy-compatible update manifest keeps `automaticProvisioning=false`; the
separate hash-bound build receipt/capability owns exact startup provisioning.
The native dependency registry remains lock-attested
`https://packagefeedproxy.microsoft.io/npm/` with normal TLS, while the frozen
source build uses `https://registry.npmjs.org/`. Do not patch a live plan or relax
TLS. Historical formal/Ops fixtures and all prior failure records remain unchanged.

Every upgrade follows the [official-first checklist](docs/local-core-desktop-copilot.md#official-first-upgrade-checklist).
The [alpha.33 formal acceptance record](docs/copilot-alpha33-upgrade-record.md)
documents exact source, assets, positive proof and synthetic/downstream boundaries.
PR #157 fixes the plugin through the official `useSession` selector contract,
without changing Core. The [historical alpha.32 record](docs/copilot-alpha32-upgrade-plan.md)
retains official/delegated primitives and plugin/Desktop gaps. Alpha.33 is not
official Core; alpha.2 compatibility does not promote separately owned draft
Desktop PR 68.

Historical `0.1.5-rc.3.cloga.1`/`.cloga.2` copied helpers cannot bootstrap because of an
unresolved `semver` import. They cannot repair themselves by discovering a newer
release. Recovery requires the independently verified lock-selected installer,
that target's exact-head qualification (`.cloga.17` run `35595040585` at `bb7a0a366e789b19918be6d8a6e40266c46a94f9`), explicit interruption consent and a clean Desktop/Host exit, coordinated by the
operator outside the broken helper. Do not patch live files or install missing
dependencies into an update operation. Generic direct registry probe failures
are not evidence that the supported provisioner failed.

Native `Check` separates exact installed files/receipts from functional evidence.
The Electron Host uses parent-owned byte pipes, not `127.0.0.1:3080`; Web checks
cannot prove native Models readiness. `Verify` reports
`manual-verification-required` (exit 2); independently record Desktop UI and real
model-response acceptance outside this CLI. Missing native Remote
access is unknown, never success. Legacy Apply/rollback/restart are blocked for
the native lock; use the native managed updater and its live Session impact
confirmation instead.

## Start here

| Goal | Guide |
|---|---|
| Check or install the locked Windows + Copilot baseline | [`docs/local-core-desktop-copilot.md`](docs/local-core-desktop-copilot.md) |
| Find the persistent Desktop update notice and safely use **Review update** (historical `.cloga.8` release evidence; not local `.6` activation) | [Notification location, use, and safety](docs/local-core-desktop-copilot.md#persistent-update-notice) |
| Build and install a side-by-side Electron Desktop from official `dsh-v0.1.5-rc.2` source; choose the isolated default or an explicit existing Harness home, and understand the manual update channel | [`docs/official-desktop-local-build.md`](docs/official-desktop-local-build.md) |
| Check or explicitly trigger a verified one-click local Desktop update without enabling silent/native updates | [`docs/official-desktop-local-build.md#dsh-windows-ops-managed-update-channel-explicit-one-click-install`](docs/official-desktop-local-build.md#dsh-windows-ops-managed-update-channel-explicit-one-click-install) |
| Check versions, configuration, services, models, and replay patches | [`docs/windows-replay-tooling.md`](docs/windows-replay-tooling.md) |
| Diagnose installation problems and apply targeted repairs | [`tools/README.md`](tools/README.md) |
| Diagnose recurring manual compaction read-only: selection/header routing, output truncation and evidence limits (not a shipped fix) | [`docs/manual-compaction-diagnostics.md`](docs/manual-compaction-diagnostics.md) |
| Choose or evaluate a community plugin | [`docs/plugins/choosing-a-plugin.md`](docs/plugins/choosing-a-plugin.md) |
| Distinguish Desktop registry packages, verified Releases, and published source-snapshot installation not yet locally activated; reinstall or recover a damaged snapshot | [`docs/plugins/desktop-source-installation.md`](docs/plugins/desktop-source-installation.md) |
| Understand plugin validation levels | [`docs/plugins/plugin-validation.md`](docs/plugins/plugin-validation.md) |
| Evaluate Computer Use and browser automation | [`docs/plugins/computer-use.md`](docs/plugins/computer-use.md) |
| Operate the optional Session scheduler | [`docs/plugins/scheduling.md`](docs/plugins/scheduling.md) |
| Check or install the optional Copilot, Cron, and Playwright suite together | [`docs/plugins/optional-companion-suite.md`](docs/plugins/optional-companion-suite.md) |
| Read the machine-readable plugin catalog | [`catalog/plugins.json`](catalog/plugins.json) |
| Track improvements, ownership, PR status, and evidence | [`docs/improvement-portfolio.md`](docs/improvement-portfolio.md) |
| Contribute changes or report security issues privately | [`CONTRIBUTING.md`](CONTRIBUTING.md) / [`SECURITY.md`](SECURITY.md) |

## Do not confuse three kinds of validation

1. **Plugin catalog:** [`catalog/plugins.json`](catalog/plugins.json) records discovery, source review, import compatibility, composition mount, functional smoke, deployment validation, and locked-baseline levels.
2. **Compatibility check:** `tools/dsh-compat-check.mjs` analyzes installed community-plugin dependencies and probes the host entry import. Passing means **import-compatible**, not functionally proven or secure.
3. **Deployment lock:** `deployments/*.lock.json` pins exact versions, commits, artifact hashes, installation, acceptance, and rollback. This defines support.

Evaluate community plugins in a disposable Profile first:

```powershell
node tools\dsh-compat-check.mjs <profile> --probe=<package>
node tools\validate-plugin-catalog.mjs
```

Then use an isolated `DSH_HOME` to verify Cordis activation, tool registration, cleanup, and a representative function before promoting its catalog level. Do not use the maintained `web` Profile for a first-time trial.

**User-reported candidate:** [`csyangwen/dsh-memory-evolve`](https://github.com/csyangwen/dsh-memory-evolve/tree/c337dc1af7b5c8a5578e03150bf5c4d6133f66f9) is user-reported useful for cross-session memory/evolution workflows, but this repository has completed only an `L1` source review of commit `c337dc1af7b5c8a5578e03150bf5c4d6133f66f9` / tag `v26091501` and lists it as `experimental`. The Release has no asset or checksum manifest, the package declares no DSH peer range, and no isolated mount or functional/security validation is recorded; see the [plugin selection guide](docs/plugins/choosing-a-plugin.md#user-reported-high-privilege-candidates). Because it handles long-term memory, background evolution, skill/prompt modification, self-update, and optional external CLI, Git synchronization, and messaging capabilities, first use must stay in an isolated Profile with explicit review of data retention and automatic modification. It is not part of the Windows locked baseline, Desktop required plugins, or default automatic installation.

The [Desktop source-snapshot guide](docs/plugins/desktop-source-installation.md) preserves the initial publication evidence for core [issue #50](https://github.com/cloga/deepseek-harness/issues/50) / PR #53 in historical Desktop `.cloga.7` (sequence 9, PR #57). The historical lock selected `0.1.6-alpha.1.cloga.2` / Core `.6` / Copilot alpha.24, with formal source acceptance passed and that baseline's native Ops qualification passed in run `35278350619`; no local installation/activation is claimed. Original pinned Memory Evolve acquisition/packing and renderer/pnpm fixtures do not become `.6` runtime evidence or plugin activation, nor promote `L1`/`experimental`; complete target-machine checks and the separately authorized native installation before use.

## Tool map

| Category | Primary tool | Purpose |
|---|---|---|
| Deployment | `tools/install-windows-copilot.ps1` | Read-only Check by default; current native lock rejects external Apply/restart, with native installation separately authorized |
| Official local source Desktop | `tools/install-official-desktop-local.ps1` | Check by default; explicit `-Apply -AcknowledgeUnsignedLocalBuild` runs the exact `PackageLocal` flow and installs side-by-side. The single `desktopProvisioning` adapter preserves native delegation; Windows Ops does not populate the reserved profile. New installs use an isolated Harness home; `-SharedHome <existing-home>` opts into an existing home and Electron user data remains separate |
| Local Desktop update channel | `tools/manage-official-desktop-update-channel.ps1` | Explicit local-build Install and Package/Check/Stage/Complete recovery, separate from the published fork's startup discovery. SHA-256/SHA-512 and completion evidence are verified through the same adapter; NSIS and Windows/UAC prompts stay interactive and the signed native updater remains disabled |
| Bootstrap | `tools/enable-copilot-search-vision.ps1` (historical compatibility name) | Install the direct Copilot plugin, select hosted search, and report UI sign-in requirements; no vision fallback is installed |
| Optional suite | `tools/install-optional-companion-suite.ps1` | Check/Apply/Verify the locked Copilot, Cron, and Playwright selection against installed Core/Cordis/API compatibility without replacing Desktop/Core or restarting processes |
| Replay and acceptance | `tools/dsh-replay.ps1` | Self-check, strict-marker patches, dry-run, backup, and rollback |
| Plugin compatibility | `tools/dsh-compat-check.mjs` | Static dependency inventory and real host import probe |
| Plugin catalog | `tools/validate-plugin-catalog.mjs` | Validate catalog constraints, evidence references, and baseline consistency |
| Recovery | `tools/dsh-doctor.mjs` | Installation health, repair, isolated boot, and plugin inventory |
| Session safety | `tools/check-session-duplicates.ps1`, `tools/dsh-move-session.mjs` | Duplicate-ID checks and atomic migration |
| Agent-native operations | `tools/dsh-dev-tools/` | In-session status, patch, build, upgrade, and doctor tools |

Use each script's header and linked guide for full parameters. Desktop identity checks use the bounded native ASAR audit with the explicit Harness home, rather than mistaking an archive child path for a missing physical descriptor. EXE bytes, metadata, signature and exact Host binding remain mandatory; this checker correction does not install, upgrade or reload a plugin.

**ASAR entrypoint boundaries (historical native Ops qualification passed in run `35278350619`):** the optional Web installer explicitly requires an already-existing compatible physical `-RuntimeRoot` for an ASAR default and never installs or copies another Core. ASAR target validation for existing user Agent Presets remains explicitly unsupported, not skipped and reported valid. Replay uses audited read-only native state and refuses immutable archive patches/native mutations. See [tool boundaries](tools/README.md#asar-entrypoint-boundaries); `.cloga.2`/alpha.24 formal source acceptance and genuine Ops run `35278350619` passed within their separate scopes; neither current nor historical Ops proof broadens unsupported entrypoints. No local installation or activation is claimed.

## Documentation map

- **Deployment and integration:** `local-core-desktop-copilot.md`, `vision-dual-channel.md` (now the native DSH attachment and `read_image` architecture)
- **Official local source Desktop:** `official-desktop-local-build.md` (`PackageLocal` has no update channel by default; the separate unsigned flow is Package/Check/Stage/user-run installer/Complete)
- **Plugin governance and optional overlays:** `docs/plugins/`, including `computer-use.md`, `scheduling.md`, and `better-sidebar.md`, plus `catalog/`
- **Diagnostics and migration:** `tools/README.md`, `windows-replay-tooling.md`, `session-move-workspace-groups.md`
- **Incidents and platform issues:** `startup-60s-timeout.md`, `powershell-5.1-pitfalls.md`, `github-network.md`
- **Maintenance status:** `improvement-portfolio.md`, `windows-replay-tooling.md`

## Security rules

- Use the existing GitHub CLI login; `.env` is optional, not a prerequisite. Load additional credentials only from a user-designated trusted source into the current process or DSH credential service; never print, copy between repositories, or commit values.
- Start community MCP servers read-only; enable side effects only when explicitly required.
- Computer Use, real-browser control, and vision plugins may expose screens, cookies, messages, passwords, and native applications. Recommendation policy must remain separate from functional validation.
- Back up runtime/configuration changes, keep patches idempotent, and document rollback.
- Before any Desktop/Host restart, query live Sessions; require direct acknowledgement before interrupting any running Session.
- Preserve and attest the Desktop plugin surface named by the active lock mode; in `desktopNativeVerifiedRelease`, Windows Ops delegates without materializing the reserved Desktop profile.
- Govern plugins in three layers: locked managed baseline drift remains fail-closed; user-installed plugins are inventory/warnings only and never contribute baseline health; only an exact target-Core denylist match that is active or ambiguous blocks cutover.

See [`docs/security-notes.md`](docs/security-notes.md).

## Project relationships and maintenance

This repository does not redistribute Desktop, DSH, or the Copilot plugin. It pins reviewed versions and commits and orchestrates installation, migration, acceptance, and rollback. This table describes the current fork-owned Desktop release and controlled Copilot plugin identities.

| Project | Deployment responsibility | Current relationship |
|---|---|---|
| [`cloga/deepseek-harness`](https://github.com/cloga/deepseek-harness) | Fork-owned Windows Desktop release channel, lifecycle, Desktop-managed bundled DSH runtime, and `desktopNativeVerifiedRelease` generic plugin capability | Historical lock selected published `dsh-desktop-v0.1.6-alpha.1.cloga.2` at `65a236bd65f2971f98b11a0efd020b8860144924`; formal source run `35271210350` and that baseline's native Ops run `35278350619` passed, no local activation; the deployment lock above defines the current target |
| [`cloga/dsh-github-copilot`](https://github.com/cloga/dsh-github-copilot) | A companion to built-in `@deepseek-ai/dsh-llm-pi-ai`: sign-in UI, Host-only grant normalization, account-aware `models`/strict-mode leaf reconciliation, Copilot-scoped Tool Schema filtering, Responses/Anthropic inline search, and Responses-only `ctx.web` search. The plugin preserves unowned existing-profile fields; the Windows deployment removes legacy connection references. No second adapter, gateway, or ACP. | Historical immutable Release source commit `e49bf7c9307cf22dd9ea720bed8750101fc986ed`; Release `v0.4.0-alpha.24`, repairing alpha.23's search-routing Client injection; the deployment lock above defines the current target |
| [`cloga/dsh-windows-ops`](https://github.com/cloga/dsh-windows-ops) | Exact lock, check-first installer, migration, acceptance, and rollback | Default branch maintains the Windows + Copilot deployment baseline |

The optional-suite entrypoint evaluates the installed Core, Cordis, and plugin
APIs rather than requiring the exact locked Desktop patch. Its transaction is
limited to the Web Profile and immutable plugin artifacts; it never replaces
Desktop/Core, changes global packages, or restarts running Sessions.

The historical ACP subagent practice remains in
[`docs/copilot-acp-subagent.md`](docs/copilot-acp-subagent.md), but it is a
separate optional integration and not part of the `dsh-github-copilot`
unified main-agent model path.

“All-in-one” means one DSH plugin reusing the built-in `llm-pi-ai` services. It
does **not** mean an embedded gateway: there is no local gateway process, port
7777, pasted GitHub token, placeholder API key, or separate search plugin.

[`docs/improvement-portfolio.md`](docs/improvement-portfolio.md) is the single status index for ownership, external-upstream status, and validation evidence. Before publishing or upgrading, follow the deployment lock, plugin catalog, and the guide for the selected deployment lane rather than mixing versions from README strings.

## Requirements

- Windows 10/11;
- Node `^22.19.0 || >=24.0.0` for the locked baseline;
- any baseline change must update the lock, fixtures, tests, and explanatory guide together.

The community catalog intentionally includes experimental and historical projects. Only entries marked `baseline` and matching a deployment lock are part of the currently supported configuration.
