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
| Authorization service | rc.2 bootstrap before plugin activation and alpha.3 existing-service reuse |
| Direct hosted search | Copilot request metadata, two-round bounded probe, `github-copilot-hosted`, and direct Copilot endpoint boundary |
| Client UI | alpha.3 Models provider-card and rc.2 Settings fallback |
| Core | renderer `SlotOutlet` compatibility and sandbox regression |
| Desktop | no-open recovery marker where still required |

The authoritative plugin is `dsh-github-copilot@0.3.0-cloga.3`, source commit
`d6da9f4a0b64cdf18ab3e25581d84b55b8421076`, artifact SHA-256
`d7e9c262e2a53cef7f46a7d37b93f9d11bef7ea398fac143c9f588deb5011f1c`.

Replay checks package/source markers only. Credential acceptance is performed
by the deployment/bootstrap modules and reports record key, kind, and status
without exposing the grant payload.
