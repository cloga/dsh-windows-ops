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

The `.5` baseline checks:

| Component | Evidence |
|---|---|
| Client loader | rc.2 Desktop `window.__ModuleLoader__.load` handoff with the exact plugin id, injected `require`, and returned exports |
| Remote codecs | strict Zod validation for plugin-owned authorization view results |
| `dsh-github-copilot` host | shared `llm-pi-ai/github-copilot` credential record and `models.getAuth()` refresh |
| Authorization service | rc.2 bootstrap before plugin activation and alpha.3 existing-service reuse |
| Direct hosted search | Copilot request metadata, two-round bounded probe, `github-copilot-hosted`, and direct Copilot endpoint boundary |
| Client UI | alpha.3 Models provider-card and rc.2 Settings fallback |
| Core | renderer `SlotOutlet` compatibility and sandbox regression |
| Desktop | no-open recovery marker where still required |

The authoritative plugin is `dsh-github-copilot@0.3.0-cloga.5`, source commit
`5d8d696aabd309602b3b70fd40dbf9b1435f0041`, artifact SHA-256
`f6ddc1c3ba90c3534ad91b0a31ffe0a1bb15b2898155e0e8164ffd95993c825f`.

Replay checks package/source markers only. Credential acceptance is performed
by the deployment/bootstrap modules and reports record key, kind, and status
without exposing the grant payload.
