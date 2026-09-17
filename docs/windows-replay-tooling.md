# Windows replay tooling

For the native Desktop lock, replay is a read-only inspection surface:
SelfCheck and exact-marker DryRun remain available, but real Apply, Rollback and
RecoverDesktop delegate to the native updater and fail before file/process
mutation. RecoverDesktop DryRun reports that native Session evidence is
unavailable; it does not promise a restart. Service/config/endpoint diagnostics
describe the separate Web/headless surface, never the Electron byte-pipe Host.

`tools\dsh-replay.ps1` inventories official Desktop, its managed DSH runtime,
`dsh-github-copilot`, and pi-ai packages and verifies exact source markers. It
does not mutate the active deployment in `SelfCheck`, `Inventory`, or
`Preflight`.

## Configuration

The default config delegates Desktop discovery and bundled runtime descriptor
verification to the same lock-selected functions used by the installer.
It follows the actual installed executable (including the installer package
directory), never the old Tauri registry entries. `-LockPath` defaults to
`deployments\windows-copilot.lock.json`. A missing locked shell remains missing;
another installed shell is not a fallback.

Use `-Config <path>` only for explicit diagnostic overrides. A Desktop root must
pass the locked executable/descriptor identity checks; a runtime override must
match that Desktop's bundled runtime. Conflicting old environment values,
executable names, or configured roots fail explicitly. For a custom installation:

```powershell
$env:DSH_HOME = "$HOME\.dsh"
$env:DSH_DESKTOP_ROOT = "C:\custom-install\DeepSeek Harness (cloga)"
```

Set `DSH_HOME` to the home selected by Desktop, not a different Web installation.
The default plugin inventory reads `profiles\desktop\node_modules`; Web and
headless config files remain separate diagnostic surfaces. An explicit
`DSH_GITHUB_COPILOT_ROOT` is diagnostic only: markers passing in a Web profile
do not establish that Desktop loaded the plugin or that Models works.

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
promoted lock. Inspect `deployment.valid`, `deployment.desktop.status`,
`deployment.runtime.status`, component paths, and every patch `status`.
SelfCheck and DryRun include the same deployment evidence. Real Apply,
Rollback, and recovery fail closed if Desktop/runtime do not match the lock;
real Apply still requires exact source markers and backs up changed files.

## Direct Copilot markers

The `0.4.0-alpha.22` baseline checks:

| Component | Evidence |
|---|---|
| Client loader | Desktop `window.__ModuleLoader__.load` handoff with the exact plugin id, injected `require`, and returned exports |
| Remote codecs | strict Zod validation for plugin-owned authorization view results |
| OAuth grant normalization | provider-owned Copilot grant fields rebuilt as validated plain JSON before credential storage |
| Legacy profile repair | validates the shared grant and only repairs an existing canonical profile's strict-mode leaf; an absent profile is not recreated |
| Per-model API routes | managed route facts use the owning account snapshot's exact model protocol and endpoint |
| Shared routing chunk | exact alpha.22 `lib\search-routing-pFLux0W7.js` preserves canonical route-level API precedence and hostname-gated `X-Initiator`/`Openai-Intent` metadata |
| Copilot tool-schema filter | prompt assembly removes `sandbox_permissions` and `justification` for canonical Copilot or the plugin-owned preview route only; non-Copilot schemas remain unchanged, and packaged current/fresh Session probes must pass after restart |
| `dsh-github-copilot` host | shared `llm-pi-ai/github-copilot` credential record and `Models.getAuth()` refresh |
| Authorization service | existing official Desktop service reuse without duplicate registration |
| Direct hosted search | request-owned auth and managed protocol/endpoint mismatch checks fail closed; Responses/Anthropic inline search, Responses-only `ctx.web`, and bounded proof remain separate acceptance requirements |
| Client UI | official DSH Models provider-card authorization |
| Desktop-managed DSH | bundled `@deepseek-ai/dsh@0.1.5-rc.2`, attested by the locked `resources\dsh\desktop-runtime.json`; no separate Core installation |
| Desktop | fork-owned `0.1.5-rc.3.cloga.7`, sequence 9, source `293b5a79f533005d99cd60cb00b9ecf810187401`; executable bytes, metadata, and descriptor are checked by the installer's discovery implementation |
| Desktop plugins | `desktopNativeVerifiedRelease` delegates ownership to Desktop; Windows Ops does not populate the reserved profile or copy its dependencies |

The legacy SlotOutlet and no-open recovery patches explicitly select the
`desktop-official` runtime and report `not-applicable` for the current
`desktop-fork-managed` release (`unsupported` without a resolved selector).
They are not positive acceptance evidence. Applicable patch targets still
require their exact markers; do not inject old renderer code or select an older
shell to make replay green.

The authoritative plugin is `dsh-github-copilot@0.4.0-alpha.22`, PR #133,
source/merge/release commit `479340f965c5be7b4408e4f1e6c9dda6c421d37b`.
Its immutable `v0.4.0-alpha.22` Release artifact SHA-256 is
`e749d982ac55752eeca4cf4819b9751144cda1c2dc06033e4b42240151e40e0e`.
Local Desktop install/update additionally verifies the SHA-512/SRI contract and
delegates this artifact through the single Desktop-native provisioning adapter.

The current target is immutable [Release `390421989`](local-core-desktop-copilot.md#authoritative-baseline), published `2026-09-17T03:51:36Z`. Formal run `35178158751` built and published on attempt 1; only the remote-check job initially received HTTP 403 and succeeded on its failed-job-only rerun, attempt 2. No artifact was rebuilt or overwritten. Archived formal acceptance artifact `10479574730` proves isolated packaged Electron initial/restart Copilot Models account UI, graph/ancestor isolation, and standalone helper ACK/cancel. It does not prove OAuth, a model response, a local installer upgrade, or source-plugin activation. Publication and the updated lock are not evidence that the local machine has applied `.cloga.7`; replay must report older installed bytes as drift, not silently accept them. See the [baseline identities and evidence boundaries](local-core-desktop-copilot.md#authoritative-baseline).

Replay checks package/source markers only. Credential acceptance is performed
by the deployment/bootstrap modules and reports record key, kind, and status
without exposing the grant payload.

The installer `-Action Verify` requires no DSH path. It attests the official
Desktop executable/runtime descriptor and the exact Electron parent/bundled Node
Host arguments. Native mode does not require port 3080 and returns
`manual-verification-required` rather than a functional pass. Only separate
Web/headless diagnostics inspect HTTP listeners. Native Apply is blocked;
it never builds, installs, or selects another DSH runtime.
Complete deployment acceptance also requires direct sign-in, model response,
hosted search, nonempty reasoning rendering, fresh-Session Copilot Tool Schema
acceptance, and rollback evidence.
