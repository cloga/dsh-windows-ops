# Durable Windows replay and self-heal tooling

`tools/dsh-replay.ps1` inventories the local integration, verifies known patches,
applies compatible patches idempotently, and restores the exact pre-change files.
It never reads or prints token values, `.env` contents, or arbitrary configuration
content. Configuration checks report only path, parse state, and SHA-256.

For a complete Desktop + Copilot installation, first use the locked,
check-by-default `tools\install-windows-copilot.ps1` workflow. Replay tooling
repairs exact known markers after installation; it is not a substitute for the
locked component, route, plugin-materialization, and smoke contracts.

## Quick start

```powershell
Copy-Item tools\dsh-replay.config.example.json $env:LOCALAPPDATA\dsh-replay.json

# Point only to component roots that exist on this computer.
$env:DSH_DESKTOP_ROOT = 'C:\Path\To\DeepSeek Harness'
$env:DSH_WEB_SEARCH_PROVIDER_ROOT = 'C:\Path\To\dsh-web-search-provider'
$env:COPILOT2API_ROOT = 'C:\Path\To\copilot2api'
$env:PI_AI_ROOT = 'C:\Path\To\pi-ai'

powershell.exe -File tools\dsh-replay.ps1 -Action Preflight -Config $env:LOCALAPPDATA\dsh-replay.json
powershell.exe -File tools\dsh-replay.ps1 -Action SelfCheck -Config $env:LOCALAPPDATA\dsh-replay.json
powershell.exe -File tools\dsh-replay.ps1 -Action Apply -DryRun -Config $env:LOCALAPPDATA\dsh-replay.json
powershell.exe -File tools\dsh-replay.ps1 -Action Apply -Config $env:LOCALAPPDATA\dsh-replay.json
```

The example configuration uses environment variables and standard install
locations. Keep local paths in the copied configuration, not in this repository.
`rootEnv`, `rootCandidates`, `versionProbes`, `fileVersionProbes`, and
`baseUrlEnv` are optional. Minimal local configurations may omit them; the module
must remain valid under `Set-StrictMode`.

If local execution policy blocks `.ps1` files, use a process-scoped override:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\dsh-replay.ps1 `
  -Action SelfCheck -Config $env:LOCALAPPDATA\dsh-replay.json
```

This does not change the user or machine execution policy.

## Commands

| Action | Behavior |
|---|---|
| `Preflight` | Detect Desktop, `dsh-web-search-provider`, `copilot2api`, and `pi-ai`; report versions and patch compatibility. |
| `SelfCheck` | Add process/port checks, JSON/YAML/profile hashes, local and HTTP model catalog discovery, explicit image-capability metadata, and active-core SlotOutlet compatibility. |
| `Verify` | Report each patch as `already-applied`, `applicable`, `incompatible`, `target-not-found`, or `component-not-found`. |
| `Apply -DryRun` | Show what would change without creating state or touching files. |
| `Apply` | Back up each target, write through a temporary file, and record a rollback inventory. Re-running is a no-op. |
| `Rollback [-OperationId ...]` | Restore an operation atomically; without an ID, restore the newest recorded operation. Refuses stale or tampered files by SHA-256. Supports `-DryRun`. |
| `RecoverDesktop -DryRun` | Resolve the configured executable and show the recovery action. |
| `RecoverDesktop` | Stop only processes whose executable path exactly matches the configured Desktop executable, restart it, and wait for the configured service check. |

Backups default to `%LOCALAPPDATA%\dsh-windows-ops\backups`. Override with
`DSH_OPS_STATE_ROOT` or `-StateRoot`. Backups are never stored inside
`DSH_HOME\sessions`.

## Patch lifecycle

`tools/dsh-replay.patches.json` is intentionally strict. A patch applies only
when both the component root and an exact known source marker match. Unknown
versions are reported as `incompatible`; the tool never guesses or performs a
broad regular-expression rewrite.

Copilot bootstrap additionally invokes
`tools/dsh-sandbox-regression-probe.mjs` against the active Core. The probe
does not implement sandbox policy: it calls the installed shared escalation
helper and verifies the pwsh/bash delegation contract. Pre-fix Core builds are
reported as an external `expected-fail`; `-SandboxGate Require` turns that
status into a fail-closed prerequisite after the Core fix is installed.

Each entry labels its lifecycle:

- `upstreamed`: an upstream release or linked pull request contains the durable fix.
- `temporary`: a local compatibility patch that should be removed after the
  compatibility matrix confirms the installed version includes the upstream fix.

The active-core renderer entry verifies the exact `SlotOutlet` export used by
`dsh-tauri-ui`; it does not patch an unknown renderer. The replay-ID, sandbox
sanitization, image bypass, and dynamic Copilot model
discovery entries verify behavior already present in
`dsh-web-search-provider 0.2.3-cloga.1`; they are labeled `upstreamed`. The Desktop
recovery entry remains a temporary exact-marker patch. Do not put credentials or
complete local configuration files in the manifest.

## Compatibility matrix

| Component | Detection | Replay/self-heal coverage | Validated baseline | Patch lifecycle |
|---|---|---|---|---|
| DSH Desktop / local core | Runtime or unpacked package version plus `DSH_CORE_ROOT` or npm flat global layout | Process/port health, active renderer SlotOutlet verification, `--no-open` recovery verification, exact-path restart | Runtime `0.1.0-rc.8`, `0.1.1-rc.2` | Temporary Desktop compatibility marker; remove when upstream exports SlotOutlet. |
| `dsh-web-search-provider` | `package.json` plus exported `deployment-baseline.json` under `DSH_WEB_SEARCH_PROVIDER_ROOT` or DSH profile | Replay ID, grounded sandbox sanitization, image bypass, Copilot model discovery, and orphan filtering | `0.2.3-cloga.1` / exact commit `f7fc5adfebaf87a3f2d56cfdf5e60601961edcb0` | Fork deployment baseline; installer verifies all required capability IDs and the tarball SHA-256. |
| `copilot2api` | Package or executable under `COPILOT2API_ROOT`; `/v1/models` endpoint | Port/process and model catalog checks | Local service on port `7777` | Verification only; no binary rewriting. |
| `pi-ai` | `package.json` under `PI_AI_ROOT` or DSH profile | Package version plus model/image catalog data consumed by the provider | Installed `@earendil-works/pi-ai` profile package | Verification only. |

“Marker-driven” means the tool refuses to modify an unrecognized build. This is
safer than claiming compatibility from a package version alone.

## Tests

```powershell
Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser
Import-Module Pester -RequiredVersion 5.7.1
Invoke-Pester tests
node tools\dsh-move-session.selftest.mjs
```

The Pester suite uses only temporary fixture trees. It proves dry-run has no side
effects, repeated application is idempotent, rollback restores the original
bytes, component versions are detected, omitted optional configuration properties
remain valid under StrictMode, and traversal outside a component root is rejected.
`WindowsCopilotInstaller.Tests.ps1` adds fixture-only coverage for source/version
locks, release hashes, the single global npm transaction, both route protocols,
pnpm allowBuilds, profile bundle insertion, all four physical plugin directories,
composed configuration, backups outside sessions, and hosted-search evidence.
