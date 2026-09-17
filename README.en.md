# dsh-windows-ops

[![Windows deployment lock](https://github.com/cloga/dsh-windows-ops/actions/workflows/windows-copilot-lock.yml/badge.svg)](https://github.com/cloga/dsh-windows-ops/actions/workflows/windows-copilot-lock.yml)
[![Plugin catalog](https://github.com/cloga/dsh-windows-ops/actions/workflows/plugin-catalog.yml/badge.svg)](https://github.com/cloga/dsh-windows-ops/actions/workflows/plugin-catalog.yml)
[![License](https://img.shields.io/github/license/cloga/dsh-windows-ops)](LICENSE)

**English** | [简体中文](README.md)

> Windows deployment baselines, operations tooling, and a community-plugin validation catalog for DeepSeek Harness (DSH).

This repository captures DSH Desktop/Copilot deployments, diagnostics, recovery procedures, and integrations verified on real Windows systems. It does not redistribute Desktop, DSH, or third-party plugins. Exact locks and acceptance contracts define the supported baseline.

## Copilot account-discovered route maintenance

For a newer Copilot installation moving from two routes to the account-discovered directory, use the [check-first configuration maintenance flow](docs/copilot-managed-route.md) and separate [`copilot-managed-route.policy.json`](deployments/copilot-managed-route.policy.json). It permits only explicitly approved path-level settings CAS: no component installation, restart, or automatic Session/default changes. It does not downgrade a newer Desktop to the older full baseline below. The policy release must be verified, its exact plugin version must be loaded, and cold-history implications require acknowledgement. This is not a new full Desktop/Core attestation.

## Current supported baseline

[`deployments/windows-copilot.lock.json`](deployments/windows-copilot.lock.json) is authoritative. Its current verification date is **2026-09-15**.

| Component | Locked version |
|---|---|
| DeepSeek Harness Desktop | fork-owned `0.1.5-rc.3.cloga.5`, release tag `dsh-desktop-v0.1.5-rc.3.cloga.5`, commit `29f1863f5457470bacd12de00e987b8bdd6f4b2f` |
| Desktop-managed DSH runtime | bundled `@deepseek-ai/dsh@0.1.5-rc.2`, attested by installed `resources\dsh\desktop-runtime.json` descriptor SHA-256 `f21d8b8fb67ed04554290acf3a48c91ea163bef7772842fd0796e0e97788d72d`; default per-user root is `%LOCALAPPDATA%\Programs\DeepSeek Harness (cloga)\resources\dsh`, but Windows Ops follows the actual installed EXE path |
| Required `dsh-github-copilot` | 0.4.0-alpha.22; preserved/delegated through `desktopNativeVerifiedRelease`, not externally materialized by Windows Ops |
| Desktop native capability | `desktopNativeVerifiedRelease`, manifest self SHA-256 `2e5b8efbabd812b07258e0fa794ffa04a7084f84a86ac6ee3ca534c034221152`, generic plugin compatibility `automaticProvisioning=false` |
| Optional Web overlays (not baseline requirements) | `dsh-playwright-host@0.1.2`, `dsh-cron@0.4.1` |

A project appearing in a README, catalog, or historical incident does **not** mean it belongs to this baseline. The default branch and deployment lock are this repository's publication channel; this repository does not redistribute Desktop/DSH/plugin binaries. A lock update defines the reviewed target baseline, not proof that a particular machine already ran `-Apply`; default check mode reports unapplied drift truthfully.

Replay uses the installer's lock-selected Desktop discovery and bundled runtime
descriptor checks, with no legacy Tauri fallback. SelfCheck/DryRun exit zero is
not deployment acceptance: inspect their `deployment` evidence and patch
statuses. Plugin markers in Web/headless do not prove Desktop Models readiness.

The published fork checks for managed updates about ten seconds after startup.
After confirmation of the impact on active work, its helper downloads/verifies
the release and starts the interactive installer; Windows/UAC prompts remain.
Restart evidence gates completion. This is not an unattended installation.
Copilot alpha.22 uses required host authorization/schemastery peers rather than
private dependency copies; the locked bundled Core remains unchanged.
React is a Client external singleton (`dsh.client.external`), not a required
Node peer or private runtime dependency. Alpha.22 corrects that alpha.21 startup
failure; published metadata alone still does not prove live Desktop readiness.

Recovery Release `390292533` (sequence 6) passed standalone copied-helper
bootstrap, synthetic ACK/cancel, packaged initial/restart
provisioning and signed-out Models UI acceptance, not OAuth, a model round or a
local installer upgrade. Its legacy-compatible update manifest deliberately
keeps `automaticProvisioning=false`; the separately hash-bound build receipt
and packaged capability declare native startup provisioning with the exact
plan. Do not equate those two compatibility objects or relax local registry TLS.
Native registry acceptance binds `dependencyRegistry` to the exact lock-attested
packaged plan and matching receipts/state, not a fixed endpoint or local npm
configuration.
Host command checks require the exact `--import` file URL only when the
hash-verified runtime inventory contains the owned module-resolution policy;
extra files or arbitrary Node flags cannot enable this mode.
The `.cloga.5` plan pins plugin dependency downloads to
`https://packagefeedproxy.microsoft.io/npm/` with normal TLS verification.
The frozen workspace build registry remains `https://registry.npmjs.org/`;
these are distinct contracts. Core `0.1.5-rc.2` and Copilot alpha.22 are unchanged.
The formal ancestor-SDK junction regression passed with
`ancestorSdkJunction=true` and `ancestorSdkLoaded=false`; initial/restart graph
evidence is hash-bound in the lock. This is not local OAuth or model acceptance.

Older `.cloga.1`/`.cloga.2` copied helpers cannot bootstrap because of an
unresolved `semver` import. They cannot repair themselves by discovering a newer
release. Recovery requires the independently verified current `.cloga.5` installer,
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
| Find the persistent Desktop update notice and safely use **Review update** (merged implementation; publication/baseline verification pending) | [Notification location, use, and safety](docs/local-core-desktop-copilot.md#persistent-update-notice) |
| Build and install a side-by-side Electron Desktop from official `dsh-v0.1.5-rc.2` source; choose the isolated default or an explicit existing Harness home, and understand the manual update channel | [`docs/official-desktop-local-build.md`](docs/official-desktop-local-build.md) |
| Check or explicitly trigger a verified one-click local Desktop update without enabling silent/native updates | [`docs/official-desktop-local-build.md#dsh-windows-ops-managed-update-channel-explicit-one-click-install`](docs/official-desktop-local-build.md#dsh-windows-ops-managed-update-channel-explicit-one-click-install) |
| Check versions, configuration, services, models, and replay patches | [`docs/windows-replay-tooling.md`](docs/windows-replay-tooling.md) |
| Diagnose installation problems and apply targeted repairs | [`tools/README.md`](tools/README.md) |
| Choose or evaluate a community plugin | [`docs/plugins/choosing-a-plugin.md`](docs/plugins/choosing-a-plugin.md) |
| Distinguish Desktop registry packages, verified Releases, and unreleased source snapshots; reinstall or recover a damaged snapshot | [`docs/plugins/desktop-source-installation.md`](docs/plugins/desktop-source-installation.md) |
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

The [Desktop source-snapshot guide](docs/plugins/desktop-source-installation.md) records the unreleased capability from core [issue #50](https://github.com/cloga/deepseek-harness/issues/50), acquisition/packing validation of the pinned Memory Evolve commit, and the limits of isolated-renderer and real-pnpm fixture evidence. These results do not activate that plugin, promote its catalog level, or change the baseline. A qualified complete Desktop build containing the feature is required before using its native transaction flow.

## Tool map

| Category | Primary tool | Purpose |
|---|---|---|
| Deployment | `tools/install-windows-copilot.ps1` | Check by default; install the locked baseline only with explicit `-Apply` |
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

Use each script's header and linked guide for full parameters.

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
| [`cloga/deepseek-harness`](https://github.com/cloga/deepseek-harness) | Fork-owned Windows Desktop release channel, lifecycle, Desktop-managed bundled DSH runtime, and `desktopNativeVerifiedRelease` generic plugin capability | Current lock uses `dsh-desktop-v0.1.5-rc.3.cloga.5` at commit `29f1863f5457470bacd12de00e987b8bdd6f4b2f` |
| [`cloga/dsh-github-copilot`](https://github.com/cloga/dsh-github-copilot) | A companion to built-in `@deepseek-ai/dsh-llm-pi-ai`: sign-in UI, Host-only grant normalization, account-aware `models`/strict-mode leaf reconciliation, Copilot-scoped Tool Schema filtering, Responses/Anthropic inline search, and Responses-only `ctx.web` search. The plugin preserves unowned existing-profile fields; the Windows deployment removes legacy connection references. No second adapter, gateway, or ACP. | PR #133 source/merge/immutable Release commit `479340f965c5be7b4408e4f1e6c9dda6c421d37b`; Release `v0.4.0-alpha.22` |
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
