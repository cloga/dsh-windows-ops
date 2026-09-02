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
  -File tools\dsh-replay.ps1 -Action Apply -DryRun
```

`Apply` remains exact-marker based and backs up changed files. Use dry-run
before mutation.

## Direct Copilot markers

The `.8` baseline checks:

| Component | Evidence |
|---|---|
| Client loader | rc.2 Desktop `window.__ModuleLoader__.load` handoff with the exact plugin id, injected `require`, and returned exports |
| Remote codecs | strict Zod validation for plugin-owned authorization view results |
| OAuth grant normalization | provider-owned Copilot grant fields rebuilt as validated plain JSON before credential storage |
| Per-model API routes | account models materialize their installed protocol and model selection prefers it over a route fallback |
| `dsh-github-copilot` host | shared `llm-pi-ai/github-copilot` credential record and `models.getAuth()` refresh |
| Authorization service | rc.2 bootstrap before plugin activation and alpha.4 existing-service reuse |
| Direct hosted search | Copilot request metadata, two-round bounded probe, `github-copilot-hosted`, and direct Copilot endpoint boundary |
| Client UI | alpha.4 Models provider-card and rc.2 Settings fallback |
| Core | renderer `SlotOutlet` compatibility, sandbox regression, and built `llm-pi-ai` strict OAuth JSON normalization plus model-level protocol markers |
| Desktop | official 0.10.2 `deepseek-harness-desktop.exe` inventory and no-open recovery marker where still required |

The authoritative plugin is `dsh-github-copilot@0.3.0-cloga.8`, source commit
`94d921dc7bad4d5035c27ed9543d638694cb7391`, artifact SHA-256
`b37e7621628e10d2a33f4cb7e4692c4fcd1348c7d7e8eb92467f250bbaa4ae32`.

Replay checks package/source markers only. Credential acceptance is performed
by the deployment/bootstrap modules and reports record key, kind, and status
without exposing the grant payload.
