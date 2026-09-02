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
  -File tools\dsh-replay.ps1 -Action Apply -DryRun
```

`Apply` remains exact-marker based and backs up changed files. Use dry-run
before mutation.

## Direct Copilot markers

The `.2` baseline checks:

| Component | Evidence |
|---|---|
| `dsh-github-copilot` host | shared `llm-pi-ai/github-copilot` credential record and `models.getAuth()` refresh |
| Direct hosted search | Copilot request metadata, two-round bounded probe, `github-copilot-hosted`, and direct Copilot endpoint boundary |
| Client UI | alpha.3 Models provider-card and rc.2 Settings fallback |
| Core | renderer `SlotOutlet` compatibility and sandbox regression |
| Desktop | no-open recovery marker where still required |

The authoritative plugin is `dsh-github-copilot@0.3.0-cloga.2`, source commit
`8af7edb70c07e9da4b451e1ae07d73e99040340e`, artifact SHA-256
`deb35365b42dfc353ab094a3da7c1e3560708e97ab0c85a82f571b5c2cd38236`.

Replay checks package/source markers only. Credential acceptance is performed
by the deployment/bootstrap modules and reports record key, kind, and status
without exposing the grant payload.
