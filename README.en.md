# dsh-windows-ops

[![Windows deployment lock](https://github.com/cloga/dsh-windows-ops/actions/workflows/windows-copilot-lock.yml/badge.svg)](https://github.com/cloga/dsh-windows-ops/actions/workflows/windows-copilot-lock.yml)
[![Plugin catalog](https://github.com/cloga/dsh-windows-ops/actions/workflows/plugin-catalog.yml/badge.svg)](https://github.com/cloga/dsh-windows-ops/actions/workflows/plugin-catalog.yml)
[![License](https://img.shields.io/github/license/cloga/dsh-windows-ops)](LICENSE)

**English** | [简体中文](README.md)

> Windows deployment baselines, operations tooling, and a community-plugin validation catalog for DeepSeek Harness (DSH).

This repository captures DSH Desktop/Copilot deployments, diagnostics, recovery procedures, and integrations verified on real Windows systems. It does not redistribute Desktop, DSH, or third-party plugins. Exact locks and acceptance contracts define the supported baseline.

## Current supported baseline

[`deployments/windows-copilot.lock.json`](deployments/windows-copilot.lock.json) is authoritative. Its current verification date is **2026-09-04**.

| Component | Locked version |
|---|---|
| DeepSeek Harness Desktop | official 0.10.3 |
| Desktop-managed DSH runtime | `deepseek-harness-pkg@0.1.2-alpha.5` wrapper with official inner `@deepseek-ai/dsh@0.1.2-rc.1`; complete 10,347-file wrapper tree is hash-locked with no reparse directories |
| Required `dsh-github-copilot` | 0.3.0-cloga.15 |
| Desktop internal plugins | eight official 0.6.7 Profile links, including `dsh-tauri-panel-scheduler`, plus one non-bundled panel placeholder under `resources\node_modules` |
| Optional Web overlays (not baseline requirements) | `dsh-playwright-host@0.1.2`, `dsh-cron@0.4.1` |

A project appearing in a README, catalog, or historical incident does **not** mean it belongs to this baseline. The default branch and deployment lock are this repository's publication channel; this repository does not redistribute Desktop/DSH/plugin binaries. A lock update defines the reviewed target baseline, not proof that a particular machine already ran `-Apply`; default check mode reports unapplied drift truthfully.

## Start here

| Goal | Guide |
|---|---|
| Check or install the locked Windows + Copilot baseline | [`docs/local-core-desktop-copilot.md`](docs/local-core-desktop-copilot.md) |
| Check versions, configuration, services, models, and replay patches | [`docs/windows-replay-tooling.md`](docs/windows-replay-tooling.md) |
| Diagnose installation problems and apply targeted repairs | [`tools/README.md`](tools/README.md) |
| Choose or evaluate a community plugin | [`docs/plugins/choosing-a-plugin.md`](docs/plugins/choosing-a-plugin.md) |
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

## Tool map

| Category | Primary tool | Purpose |
|---|---|---|
| Deployment | `tools/install-windows-copilot.ps1` | Check by default; install the locked baseline only with explicit `-Apply` |
| Bootstrap | `tools/enable-copilot-search-vision.ps1` | Install the direct plugin, select hosted search, and report UI sign-in requirements |
| Optional suite | `tools/install-windows-copilot.ps1 -IncludeCompanionSuite` | Include locked Copilot, Cron, and Playwright bundles in one baseline Apply/rollback transaction; the narrow optional-suite wrapper uses the same lock |
| Replay and acceptance | `tools/dsh-replay.ps1` | Self-check, strict-marker patches, dry-run, backup, and rollback |
| Plugin compatibility | `tools/dsh-compat-check.mjs` | Static dependency inventory and real host import probe |
| Plugin catalog | `tools/validate-plugin-catalog.mjs` | Validate catalog constraints, evidence references, and baseline consistency |
| Recovery | `tools/dsh-doctor.mjs` | Installation health, repair, isolated boot, and plugin inventory |
| Session safety | `tools/check-session-duplicates.ps1`, `tools/dsh-move-session.mjs` | Duplicate-ID checks and atomic migration |
| Agent-native operations | `tools/dsh-dev-tools/` | In-session status, patch, build, upgrade, and doctor tools |

Use each script's header and linked guide for full parameters.

## Documentation map

- **Deployment and integration:** `local-core-desktop-copilot.md`, `vision-dual-channel.md`
- **Plugin governance and optional overlays:** `docs/plugins/`, including `computer-use.md` and `scheduling.md`, plus `catalog/`
- **Diagnostics and migration:** `tools/README.md`, `windows-replay-tooling.md`, `session-move-workspace-groups.md`
- **Incidents and platform issues:** `startup-60s-timeout.md`, `powershell-5.1-pitfalls.md`, `github-network.md`
- **Maintenance status:** `improvement-portfolio.md`, `windows-replay-tooling.md`

## Security rules

- Load credentials only from a user-designated trusted source into the current process or DSH credential service. Prefer one centralized `.env`; never print, copy between repositories, or commit values.
- Start community MCP servers read-only; enable side effects only when explicitly required.
- Computer Use, real-browser control, and vision plugins may expose screens, cookies, messages, passwords, and native applications. Recommendation policy must remain separate from functional validation.
- Back up runtime/configuration changes, keep patches idempotent, and document rollback.
- Before any Desktop/Host restart, query live Sessions; require direct acknowledgement before interrupting any running Session.
- Preserve and attest Desktop's eight official 0.6.7 Profile links, including `dsh-tauri-panel-scheduler`, and the non-bundled panel placeholder; do not replace them with guessed registry packages.

See [`docs/security-notes.md`](docs/security-notes.md).

## Project relationships and maintenance

This repository does not redistribute Desktop, DSH, or the Copilot plugin. It pins reviewed versions and commits and orchestrates installation, migration, acceptance, and rollback. This table describes the current official Desktop and controlled Copilot plugin identities.

| Project | Deployment responsibility | Current relationship |
|---|---|---|
| [`dsh-tauri-desk/deepseek-harness-desktop`](https://github.com/dsh-tauri-desk/deepseek-harness-desktop) | Official Windows shell, lifecycle, Desktop-managed official DSH, eight Profile plugins, and one shipped placeholder | Current lock uses official 0.10.3 at release/tag commit `113dc8f77095e765f4f55e233d8455e7ad9204ae` |
| [`cloga/dsh-github-copilot`](https://github.com/cloga/dsh-github-copilot) | A companion to built-in `@deepseek-ai/dsh-llm-pi-ai`: sign-in UI, Host-only grant normalization, account-aware `models`/strict-mode leaf reconciliation, Copilot-scoped Tool Schema filtering, Responses/Anthropic inline search, and Responses-only `ctx.web` search. The plugin preserves unowned existing-profile fields; the Windows deployment removes legacy connection references. No second adapter, gateway, or ACP. | PR #56 source commit `4e095196197570776515423929ddb72e8299c1db`; merge/immutable Release commit `473b8aa174eb47a323b026c098b73bf7d716772c`; Release `v0.3.0-cloga.15` |
| [`cloga/dsh-windows-ops`](https://github.com/cloga/dsh-windows-ops) | Exact lock, check-first installer, migration, acceptance, and rollback | Default branch maintains the Windows + Copilot deployment baseline |

The historical ACP subagent practice remains in
[`docs/copilot-acp-subagent.md`](docs/copilot-acp-subagent.md), but it is a
separate optional integration and not part of the `dsh-github-copilot`
unified main-agent model path.

“All-in-one” means one DSH plugin reusing the built-in `llm-pi-ai` services. It
does **not** mean an embedded gateway: there is no local gateway process, port
7777, pasted GitHub token, placeholder API key, or separate search plugin.

[`docs/improvement-portfolio.md`](docs/improvement-portfolio.md) is the single status index for ownership, external-upstream status, and validation evidence. Before publishing or upgrading, follow the deployment lock and compatibility matrix rather than mixing versions from README strings.

## Requirements

- Windows 10/11;
- Node `^22.19.0 || >=24.0.0` for the locked baseline;
- any baseline change must update the lock, fixtures, tests, and explanatory guide together.

The community catalog intentionally includes experimental and historical projects. Only entries marked `baseline` and matching a deployment lock are part of the currently supported configuration.
