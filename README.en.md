# dsh-windows-ops

> Windows deployment baselines, operations tooling, and a community-plugin validation catalog for DeepSeek Harness (DSH).
>
> [English](README.en.md) / [简体中文](README.md)

This repository captures DSH Desktop/Core/Copilot deployments, diagnostics, recovery procedures, and integrations verified on real Windows systems. It does not redistribute Desktop, Core, gateways, or third-party plugins. Exact locks and acceptance contracts define the supported baseline.

## Current supported baseline

[`deployments/windows-copilot.lock.json`](deployments/windows-copilot.lock.json) is authoritative. Its current verification date is **2026-08-30**.

| Component | Locked version |
|---|---|
| DeepSeek Harness Desktop | 0.9.2 |
| `@deepseek-ai/dsh` Core | 0.1.1-rc.2 |
| Copilot2API | 0.6.1 |
| `dsh-github-copilot` | 0.3.0-cloga.1 |
| Desktop internal plugins | five official 0.4.9 components |

A project appearing in a README, catalog, or historical incident does **not** mean it belongs to this baseline.

## Start here

| Goal | Guide |
|---|---|
| Check or install the locked Windows + Copilot baseline | [`docs/local-core-desktop-copilot.md`](docs/local-core-desktop-copilot.md) |
| Check versions, configuration, services, models, and replay patches | [`docs/windows-replay-tooling.md`](docs/windows-replay-tooling.md) |
| Diagnose installation problems and apply targeted repairs | [`tools/README.md`](tools/README.md) |
| Choose or evaluate a community plugin | [`docs/plugins/choosing-a-plugin.md`](docs/plugins/choosing-a-plugin.md) |
| Understand plugin validation levels | [`docs/plugins/plugin-validation.md`](docs/plugins/plugin-validation.md) |
| Evaluate Computer Use and browser automation | [`docs/plugins/computer-use.md`](docs/plugins/computer-use.md) |
| Read the machine-readable plugin catalog | [`catalog/plugins.json`](catalog/plugins.json) |
| Track improvements, ownership, PR status, and evidence | [`docs/improvement-portfolio.md`](docs/improvement-portfolio.md) |

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
| Bootstrap | `tools/enable-copilot-search-vision.ps1` | Fail-closed Copilot search and vision configuration |
| Replay and acceptance | `tools/dsh-replay.ps1` | Self-check, strict-marker patches, dry-run, backup, and rollback |
| Plugin compatibility | `tools/dsh-compat-check.mjs` | Static dependency inventory and real host import probe |
| Plugin catalog | `tools/validate-plugin-catalog.mjs` | Validate catalog constraints, evidence references, and baseline consistency |
| Recovery | `tools/dsh-doctor.mjs` | Installation health, repair, isolated boot, and plugin inventory |
| Session safety | `tools/check-session-duplicates.ps1`, `tools/dsh-move-session.mjs` | Duplicate-ID checks and atomic migration |
| Agent-native operations | `tools/dsh-dev-tools/` | In-session status, patch, build, upgrade, and doctor tools |

Use each script's header and linked guide for full parameters.

## Documentation map

- **Deployment and integration:** `local-core-desktop-copilot.md`, `vision-dual-channel.md`
- **Plugin governance:** `docs/plugins/`, `catalog/`
- **Diagnostics and migration:** `tools/README.md`, `windows-replay-tooling.md`, `session-move-workspace-groups.md`
- **Incidents and platform issues:** `startup-60s-timeout.md`, `powershell-5.1-pitfalls.md`, `github-network.md`
- **Maintenance status:** `improvement-portfolio.md`, `windows-replay-tooling.md`

## Security rules

- Inject credentials only from `.env`, environment variables, or the DSH credential service. Never place them in patches, docs, fixtures, or commits.
- Start community MCP servers read-only; enable side effects only when explicitly required.
- Computer Use, real-browser control, and vision plugins may expose screens, cookies, messages, passwords, and native applications. Recommendation policy must remain separate from functional validation.
- Back up runtime/configuration changes, keep patches idempotent, and document rollback.
- Preserve and attest Desktop's five official internal-plugin links; do not replace them with guessed registry packages.

See [`docs/security-notes.md`](docs/security-notes.md).

## Project relationships and maintenance

This repository does not redistribute Desktop, Core, gateways, or the search provider. It pins reviewed versions and commits and orchestrates installation, migration, acceptance, and rollback. The `cloga/*` repositories are controlled deployment forks, so this table describes default-branch capability and the current deployment pin rather than internal PR workflow state.

| Project | Deployment responsibility | Current relationship |
|---|---|---|
| [`dsh-tauri-desk/deepseek-harness-desktop`](https://github.com/dsh-tauri-desk/deepseek-harness-desktop) | Official Windows shell, lifecycle, and five internal plugins | Current lock uses official 0.9.2 |
| [`cloga/deepseek-harness`](https://github.com/cloga/deepseek-harness) | Local Core, model/vision metadata, receipt installation, and sandbox policy | Deployment pin `bd520d6e` |
| [`cloga/dsh-web-search-provider`](https://github.com/cloga/dsh-web-search-provider) | `dsh-github-copilot` main-agent model routes, capability discovery, hosted search, traditional Search bridge, Responses replay, image bypass, reasoning, and SSE streaming; no ACP | Deployment pin `78745478` / `0.3.0-cloga.1` |
| [`cloga/copilot2api`](https://github.com/cloga/copilot2api) | Maintains the DSH integration guide and receives changes not yet accepted upstream | Deployed artifact remains official upstream 0.6.1 |
| [`cloga/dsh-windows-ops`](https://github.com/cloga/dsh-windows-ops) | Exact lock, check-first installer, migration, acceptance, and rollback | Default branch maintains the Windows + Copilot deployment baseline |

The historical ACP subagent practice remains in
[`docs/copilot-acp-subagent.md`](docs/copilot-acp-subagent.md), but it is a
separate optional integration and not part of the `dsh-github-copilot`
unified main-agent model path.

[`docs/improvement-portfolio.md`](docs/improvement-portfolio.md) is the single status index for ownership, external-upstream status, and validation evidence. Before publishing or upgrading, follow the deployment lock and compatibility matrix rather than mixing versions from README strings.

## Requirements

- Windows 10/11;
- Node `^22.19.0 || >=24.0.0` for the locked baseline;
- any baseline change must update the lock, fixtures, tests, and explanatory guide together.

The community catalog intentionally includes experimental and historical projects. Only entries marked `baseline` and matching a deployment lock are part of the currently supported configuration.
