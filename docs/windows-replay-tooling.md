# Windows replay tooling

`tools\dsh-replay.ps1` inventories official Desktop, its managed DSH runtime,
`dsh-github-copilot`, and pi-ai packages and verifies exact source markers. It
does not mutate the active deployment in `SelfCheck`, `Inventory`, or
`Preflight`.

## Configuration

Copy `tools\dsh-replay.config.example.json` and override roots only when
auto-discovery cannot find them:

```powershell
$env:DSH_HOME = "$HOME\.dsh"
$env:DSH_DESKTOP_ROOT = "$env:LOCALAPPDATA\Deepseek Harness Desktop"
$env:DSH_GITHUB_COPILOT_ROOT = "$HOME\.dsh\profiles\web\node_modules\dsh-github-copilot"
```

There is no active gateway component, service, model endpoint, or port 7777
check. Legacy gateway detection belongs to the explicit migration contract in
`deployments\windows-copilot.lock.json`.

## Commands

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\dsh-replay.ps1 -Action SelfCheck

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\dsh-replay.ps1 -Action Inventory

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\dsh-replay.ps1 -Action Preflight

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\dsh-replay.ps1 -Action Apply -DryRun
```

`SelfCheck`, `Inventory`, `Preflight`, and `Apply -DryRun` are read-only. A zero
process exit means the action completed, not that the machine matches a newly
promoted lock; inspect component `status` values and the installer check's drift
reasons. Real `Apply` remains exact-marker based and backs up changed files.

## Direct Copilot markers

The `0.4.0-alpha.18` baseline checks:

| Component | Evidence |
|---|---|
| Client loader | Desktop `window.__ModuleLoader__.load` handoff with the exact plugin id, injected `require`, and returned exports |
| Remote codecs | strict Zod validation for plugin-owned authorization view results |
| OAuth grant normalization | provider-owned Copilot grant fields rebuilt as validated plain JSON before credential storage |
| Account model reconciliation | only the managed `models` and strict-mode leaves are synchronized; deployment migration removes legacy connection references |
| Per-model API routes | account models materialize their installed protocol and model selection prefers it over a route fallback |
| Copilot tool-schema filter | prompt assembly removes `sandbox_permissions` and `justification` only when the selected provider is `github-copilot`; non-Copilot schemas remain unchanged, and packaged current/fresh Session probes must pass after restart |
| `dsh-github-copilot` host | shared `llm-pi-ai/github-copilot` credential record and `Models.getAuth()` refresh |
| Authorization service | existing official Desktop service reuse without duplicate registration |
| Direct hosted search | Responses/Anthropic inline search, Responses-only `ctx.web`, default bounded proof with explicit `probe: false` bypass, and validated GitHub-hosted/Enterprise endpoints |
| Client UI | official DSH Models provider-card authorization |
| Desktop-managed DSH | `deepseek-harness-pkg@0.1.2-alpha.5`, complete 10,347-file wrapper closure with no reparse directories, inner official `@deepseek-ai/dsh@0.1.2-rc.1`, 10-file inner tree, and exact entrypoint attestations |
| Desktop | official 0.10.3 inventory; exact active PID must own IPv4 `127.0.0.1:3080` |
| Desktop plugins | all eight official 0.6.7 Profile links, including `dsh-tauri-panel-scheduler`, plus the non-bundled panel placeholder |

The authoritative plugin is `dsh-github-copilot@0.4.0-alpha.18`, PR #120,
source/merge/release commit `08bfccc3b5930b93ef2fe31d9cf9e509f34a8704`.
Its immutable `v0.4.0-alpha.18` Release artifact SHA-256 is
`2ca4f604e89eda3000cf2a51d79871cee3cb721fa6f4324fc9a1197926c359a8`.
Local Desktop install/update additionally verifies the SHA-512/SRI contract and
provisions this artifact through the reserved-profile transaction adapter.

Replay checks package/source markers only. Credential acceptance is performed
by the deployment/bootstrap modules and reports record key, kind, and status
without exposing the grant payload.

The installer `-Action Verify` requires no DSH path. It attests the official
Desktop-managed wrapper/tree/entrypoint and the active exact PID owning IPv4
`127.0.0.1:3080`; Apply never builds, installs, or selects another DSH runtime.
Complete deployment acceptance also requires direct sign-in, model response,
hosted search, nonempty reasoning rendering, fresh-Session Copilot Tool Schema
acceptance, and rollback evidence.
