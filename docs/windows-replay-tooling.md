# Windows replay tooling

`tools\dsh-replay.ps1` inventories the installed Desktop, local Core,
`dsh-github-copilot`, and pi-ai packages and verifies exact source markers. It
does not mutate the active deployment in `SelfCheck`, `Inventory`, or
`Preflight`.

## Configuration

Copy `tools\dsh-replay.config.example.json` and override roots only when
auto-discovery cannot find them:

```powershell
$env:DSH_HOME = "$HOME\.dsh"
$env:DSH_DESKTOP_ROOT = "$env:LOCALAPPDATA\Deepseek Harness Desktop"
$env:DSH_CORE_ROOT = 'C:\.tools\dsh-cloga\node_modules\@deepseek-ai\dsh'
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

The `.13` baseline checks:

| Component | Evidence |
|---|---|
| Client loader | controlled rc.2 Desktop `window.__ModuleLoader__.load` handoff with the exact plugin id, injected `require`, and returned exports |
| Remote codecs | strict Zod validation for plugin-owned authorization view results |
| OAuth grant normalization | provider-owned Copilot grant fields rebuilt as validated plain JSON before credential storage |
| Account model reconciliation | only the managed `models` and strict-mode leaves are synchronized; deployment migration removes legacy connection references |
| Per-model API routes | account models materialize their installed protocol and model selection prefers it over a route fallback |
| Copilot tool-schema filter | prompt assembly removes `sandbox_permissions` and `justification` only when the selected provider is `github-copilot`; non-Copilot schemas remain unchanged, and packaged current/fresh Session probes must pass after restart |
| `dsh-github-copilot` host | shared `llm-pi-ai/github-copilot` credential record and `Models.getAuth()` refresh |
| Authorization service | rc.2 bootstrap before plugin activation and alpha.5 existing-service reuse |
| Direct hosted search | Responses/Anthropic inline search, Responses-only `ctx.web`, default bounded proof with explicit `probe: false` bypass, and validated GitHub-hosted/Enterprise endpoints |
| Client UI | alpha.5 Models provider-card and rc.2 Settings fallback |
| Core | renderer `SlotOutlet` compatibility, sandbox regression, and built `llm-pi-ai` strict OAuth JSON normalization plus model-level protocol markers |
| Desktop | official 0.10.2 `deepseek-harness-desktop.exe` inventory and no-open recovery marker where still required |

The authoritative plugin is `dsh-github-copilot@0.3.0-cloga.13`, source commit
`6236330414eeac021d8c8bf57b9aa08cd76a04e8`, immutable Release artifact SHA-256
`fbe7861382d2e32be50c37696ffb806a7b2bce3817efc01cac28c6c51e45b957`.

Replay checks package/source markers only. Credential acceptance is performed
by the deployment/bootstrap modules and reports record key, kind, and status
without exposing the grant payload.
