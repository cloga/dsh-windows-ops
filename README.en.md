# dsh-windows-ops

[![Windows deployment lock](https://github.com/cloga/dsh-windows-ops/actions/workflows/windows-copilot-lock.yml/badge.svg)](https://github.com/cloga/dsh-windows-ops/actions/workflows/windows-copilot-lock.yml)
[![Plugin catalog](https://github.com/cloga/dsh-windows-ops/actions/workflows/plugin-catalog.yml/badge.svg)](https://github.com/cloga/dsh-windows-ops/actions/workflows/plugin-catalog.yml)
[![License](https://img.shields.io/github/license/cloga/dsh-windows-ops)](LICENSE)

**English** | [简体中文](README.md)

> Windows deployment baselines, operations tooling, and a community-plugin validation catalog for DeepSeek Harness (DSH).

This repository captures DSH Desktop/Copilot deployments, diagnostics, recovery procedures, and integrations verified on real Windows systems. It does not redistribute Desktop, DSH, or third-party plugins. Exact locks and acceptance contracts define the supported baseline.

## DSH Core upgrade entrypoint

For "adapt to a new DSH Core release", start with the [official-first upgrade
workflow](docs/core-upgrade.md). Review Core fork, Copilot, cron and Playwright
customizations against exact official source/contracts before carrying them forward;
prefer official replacements after parity and migration acceptance are proven.
[`core-upgrade-scope.json`](deployments/core-upgrade-scope.json) defines the scope.
`node tools/plan-core-upgrade.mjs --tag dsh-v<version> --commit <full-SHA>` only emits
an unexecuted plan. It does not install/restart or change the qualified deployment lock.

The [0.1.6-alpha.2 assessment](docs/core-016a2-assessment.md) records exact official
replacement evidence, retained differences and concrete API issues. It remains
source-review evidence, not a new qualified deployment baseline.
Later merges, releases, hashes and acceptance limits are recorded in the
[delivery evidence](docs/core-016a2-delivery.md). Cron 0.7.3, Playwright 0.1.8 and
Copilot alpha.25 are published and verified; the latter's GitHub/npm bytes match.
Plugin publication is not new Core/Desktop qualification or local activation,
and does not promote the deployment lock below.
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

## Copilot account-discovered route maintenance

For a newer Copilot installation moving from two routes to the account-discovered directory, use the [check-first configuration maintenance flow](docs/copilot-managed-route.md) and separate [`copilot-managed-route.policy.json`](deployments/copilot-managed-route.policy.json). It permits only explicitly approved path-level settings CAS: no component installation, restart, or automatic Session/default changes. It does not replace or downgrade an existing Desktop to the separate deployment target below. The policy release must be verified, its exact plugin version must be loaded, and cold-history implications require acknowledgement. This is not a new full Desktop/Core attestation.

## Current published deployment target (native Ops qualification passed in run `35278350619`)

[`deployments/windows-copilot.lock.json`](deployments/windows-copilot.lock.json) is authoritative. Its current verification date is **2026-09-17**.

| Component | Locked version |
|---|---|
| DeepSeek Harness Desktop | fork-owned `0.1.6-alpha.1.cloga.2`, sequence 12, release tag `dsh-desktop-v0.1.6-alpha.1.cloga.2`, commit `65a236bd65f2971f98b11a0efd020b8860144924` |
| Desktop-managed DSH runtime | bundled `@deepseek-ai/dsh@0.1.6-alpha.1`, attested through virtual `resources\app.asar\dsh\desktop-runtime.json` and independent unpacked inventory; descriptor SHA-256 `f0de4a61ead7105c41f1576a2f01617908e80e214c6c5383c9b79a13d50a14d1`; default root is `%LOCALAPPDATA%\Programs\DeepSeek Harness (cloga)\resources\app.asar\dsh`, following the actual installed EXE path |
| Required `dsh-github-copilot` | 0.4.0-alpha.24; preserved/delegated through `desktopNativeVerifiedRelease`, not externally materialized by Windows Ops |
| Desktop native capability | `desktopNativeVerifiedRelease`, manifest self SHA-256 `52a2f43210cd694c06ff38452353473fc0cea47ba758959c573d1fbb66324090`, generic plugin compatibility `automaticProvisioning=false` |
| Optional Web overlays (not baseline requirements) | `dsh-playwright-host@0.1.7`, `dsh-cron@0.7.1`; immutable Releases and artifact bytes verified for target Core `0.1.6-alpha.1`, not proof of local activation |

A project appearing in a README, catalog, or historical incident does **not** mean it belongs to this baseline. The default branch and deployment lock are this repository's publication channel; this repository does not redistribute Desktop/DSH/plugin binaries. A lock update defines the reviewed target baseline, not proof that a particular machine already ran `-Apply`; default check mode reports unapplied drift truthfully.

Replay uses the installer's lock-selected Desktop discovery and bundled runtime
descriptor checks, with no legacy Tauri fallback. SelfCheck/DryRun exit zero is
not deployment acceptance: inspect their `deployment` evidence and patch
statuses. Plugin markers in Web/headless do not prove Desktop Models readiness.

The published fork checks for managed updates about ten seconds after startup.
After confirmation of the impact on active work, its helper downloads/verifies
the release and starts the interactive installer; Windows/UAC prompts remain.
Restart evidence gates completion. This is not an unattended installation.
Copilot alpha.24 retains required host authorization/schemastery peers and the
Client external React singleton (`dsh.client.external`), not private copies or a
Node React peer. Core remains `0.1.6-alpha.1`. Alpha.24 repairs alpha.23's missing
Client `remote.githubCopilotSearchRouting` injection; a compatible manifest or
green unit suite alone did not establish a working packaged search settings card.

Immutable [Release `391052820`](https://github.com/cloga/deepseek-harness/releases/tag/dsh-desktop-v0.1.6-alpha.1.cloga.2)
(sequence 12) was formally published on 2026-09-17 from merged [PR #63](https://github.com/cloga/deepseek-harness/pull/63),
source `65a236bd65f2971f98b11a0efd020b8860144924`, tree
`b219bd1baa93433e9449dc72905d7980e7943a05`, qualified candidate
`c8af5b6cb3ccf651a5ff1a285ff7bf0ac95f487a`. Formal run
[`35271210350`](https://github.com/cloga/deepseek-harness/actions/runs/35271210350)
succeeded on attempt 1; its six Release assets were independently byte-verified.
Source acceptance artifact `10518683372` records isolated initial/restart account
UI, actual Model roles and search-routing DOM readiness, and graph/ancestor
isolation. Both read-only settings phases list `deepseek-official` and
`github-copilot-hosted`. Catalog registration is not provider availability or a
search request. **Genuine native Ops qualification passed** in registered-caller
[run `35278350619`](https://github.com/cloga/dsh-windows-ops/actions/runs/35278350619)
at exact Ops head `243c33d286f19d9e4c608e238a52de2b9a136b9e`.
The independently byte-bound [raw summary](tests/fixtures/desktop-native-verified-release/ops-cloga016-2/qualification.json)
records 9,806 runtime files, the full `.cloga.2` archive-package identity, public
`metadata-cjs-esm` resolution, one observer, profile cleanup and three rejected
request copies. Whole-carrier, model-response and installed-upgrade flags remain false.
First run `35276462350` failed before the observer with an unclassified source error;
success at the new diagnostic head does not establish that error's root cause
or prove it was repaired. Bounded diagnostics do not weaken cleanup/settings guards.
The older [run `35210215981`](https://github.com/cloga/dsh-windows-ops/actions/runs/35210215981)
qualifies only `.cloga.1`/alpha.22; it is retained as historical evidence, not
reused as `.cloga.2` proof. See the [scoped evidence and limits](docs/local-core-desktop-copilot.md#scoped-ops-ci-qualification).
No real search, OAuth/model round, local installation/activation, or installed
application upgrade/restart was performed. The stable deployment ID remains
`windows-copilot-2026-09-15`; earlier release evidence remains historical.
Its legacy-compatible update manifest deliberately
keeps `automaticProvisioning=false`; the separately hash-bound build receipt
and packaged capability declare native startup provisioning with the exact
plan. Do not equate those two compatibility objects or relax local registry TLS.
Native registry acceptance binds `dependencyRegistry` to the exact lock-attested
packaged plan and matching receipts/state, not a fixed endpoint or local npm
configuration.
The `.6` Host uses the exact locked Electron EXE in Node mode
(`ELECTRON_RUN_AS_NODE=1`) and exact `--import` policy file URL, Host entry,
ASAR runtime root and profile argv, bound to its Desktop parent. Packaged pnpm
and the updater helper still use physical bundled upstream Node; that is not the
Host carrier. Full virtual inventory and independent `app.asar.unpacked/dsh`
backing checks precede public resolver imports. No materialized Host links or
unverified fallback runtime is accepted.
The native plugin registry remains `https://packagefeedproxy.microsoft.io/npm/`
with normal TLS; the alpha.24 provisioning plan has the new exact hash
`d93e340df7169d5fa11558f6c4ab41171aa7cbf7cb564f177dd125d4076be01c`.
The frozen source-build registry remains `https://registry.npmjs.org/`.
Ownership-aware checks retain user extras as `contentsAttested:false`, not
baseline health, while required Copilot proof remains exact even if user-owned.
Historical `formal-cloga016-1` and `ops-cloga016-1` fixtures remain unchanged;
source acceptance and the successful current Ops qualification are distinct, and
neither authorizes local activation.

Every upgrade must follow the [official-first checklist and decision table](docs/local-core-desktop-copilot.md#official-first-upgrade-checklist). Current exact `.6` [Desktop](docs/official-first-desktop-016.md) and [Copilot](docs/official-first-copilot-024.md) source reviews credit official ASAR/public resolution, OAuth/chat/subagent and extension primitives already consumed, retaining only documented gaps with sunset conditions. Prefer official behavior where requirements are met; unverified official-only runtime parity is not absence, and no feature is automatically deleted.

Historical `0.1.5-rc.3.cloga.1`/`.cloga.2` copied helpers cannot bootstrap because of an
unresolved `semver` import. They cannot repair themselves by discovering a newer
release. Recovery requires the independently verified current `0.1.6-alpha.1.cloga.2` installer,
explicit interruption consent and a clean Desktop/Host exit, coordinated by the
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

The [Desktop source-snapshot guide](docs/plugins/desktop-source-installation.md) preserves the initial publication evidence for core [issue #50](https://github.com/cloga/deepseek-harness/issues/50) / PR #53 in historical Desktop `.cloga.7` (sequence 9, PR #57). The current lock selects `0.1.6-alpha.1.cloga.2` / Core `.6` / Copilot alpha.24, with formal source acceptance passed and current native Ops qualification passed in run `35278350619`; no local installation/activation is claimed. Original pinned Memory Evolve acquisition/packing and renderer/pnpm fixtures do not become `.6` runtime evidence or plugin activation, nor promote `L1`/`experimental`; complete target-machine checks and the separately authorized native installation before use.

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

**ASAR entrypoint boundaries (current native Ops qualification passed in run `35278350619`):** the optional Web installer explicitly requires an already-existing compatible physical `-RuntimeRoot` for an ASAR default and never installs or copies another Core. ASAR target validation for existing user Agent Presets remains explicitly unsupported, not skipped and reported valid. Replay uses audited read-only native state and refuses immutable archive patches/native mutations. See [tool boundaries](tools/README.md#asar-entrypoint-boundaries); `.cloga.2`/alpha.24 formal source acceptance and genuine Ops run `35278350619` passed within their separate scopes; neither current nor historical Ops proof broadens unsupported entrypoints. No local installation or activation is claimed.

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
| [`cloga/deepseek-harness`](https://github.com/cloga/deepseek-harness) | Fork-owned Windows Desktop release channel, lifecycle, Desktop-managed bundled DSH runtime, and `desktopNativeVerifiedRelease` generic plugin capability | Current lock selects published `dsh-desktop-v0.1.6-alpha.1.cloga.2` at `65a236bd65f2971f98b11a0efd020b8860144924`; formal source run `35271210350` passed, current native Ops qualification passed in run `35278350619`, no local activation |
| [`cloga/dsh-github-copilot`](https://github.com/cloga/dsh-github-copilot) | A companion to built-in `@deepseek-ai/dsh-llm-pi-ai`: sign-in UI, Host-only grant normalization, account-aware `models`/strict-mode leaf reconciliation, Copilot-scoped Tool Schema filtering, Responses/Anthropic inline search, and Responses-only `ctx.web` search. The plugin preserves unowned existing-profile fields; the Windows deployment removes legacy connection references. No second adapter, gateway, or ACP. | Immutable Release source commit `e49bf7c9307cf22dd9ea720bed8750101fc986ed`; Release `v0.4.0-alpha.24`, repairing alpha.23's search-routing Client injection |
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
