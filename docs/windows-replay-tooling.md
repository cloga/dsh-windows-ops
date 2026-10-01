# Windows replay tooling

For the native Desktop lock, replay is a read-only inspection surface:
SelfCheck and DryRun remain read-only, with ASAR/archive-backed patch targets
explicitly unsupported rather than readable marker files. Real Apply, Rollback and
RecoverDesktop delegate to the native updater and fail before file/process
mutation. RecoverDesktop DryRun reports that native Session evidence is
unavailable; it does not promise a restart. Service/config/endpoint diagnostics
describe the separate Web/headless surface, never the Electron byte-pipe Host.

`tools\dsh-replay.ps1` inventories official Desktop, its managed DSH runtime,
`dsh-github-copilot`, and pi-ai packages and verifies exact source markers. It
does not mutate the active deployment in `SelfCheck`, `Inventory`, or
`Preflight`.

## Configuration

The default config delegates Desktop discovery and runtime identity to the
lock-selected functions. For the selected `.6` ASAR target, it uses the bounded,
read-only native JS audit rather than PowerShell Test-Path/Get-Content against
virtual files. Validated root/version/count and descriptor SHA are projected as
leaves; missing profile/audit prerequisites remain explicitly not-ready, never
fake runtime success or an invented runnable descriptor/CLI path.
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
SelfCheck and DryRun include the same deployment evidence. ASAR and canonical
`resources/app.asar.unpacked/dsh` backing targets report
`unsupported-immutable-asar-target` before marker/state reads, including Verify
and Apply/Rollback DryRun. Native real Apply/Rollback/recovery remain delegated
and refused; only the separate supported physical legacy path uses exact-marker
writes and backups. Do not extract Core or invent an Electron CLI mode to bypass
these limits.

## Direct Copilot markers

The `0.4.0-alpha.33` baseline checks:

| Component | Evidence |
|---|---|
| Client loader | Desktop `window.__ModuleLoader__.load` handoff with the exact plugin id, injected `require`, and returned exports |
| Remote codecs | strict Zod validation for plugin-owned authorization view results |
| OAuth grant normalization | provider-owned Copilot grant fields rebuilt as validated plain JSON before credential storage |
| Legacy profile repair | validates the shared grant and only repairs an existing canonical profile's strict-mode leaf; an absent profile is not recreated |
| Per-model API routes | managed route facts use the owning account snapshot's exact model protocol and endpoint |
| Shared routing chunk | exact alpha.33 published entrypoints/shared routing chunk are pinned; preserve canonical route API precedence, provider-only CAS and hostname-gated request metadata |
| Copilot tool-schema filter | prompt assembly removes `sandbox_permissions` and `justification` for canonical Copilot or the plugin-owned preview route only; non-Copilot schemas remain unchanged, and packaged current/fresh Session probes must pass after restart |
| `dsh-github-copilot` host | shared `llm-pi-ai/github-copilot` credential record and `Models.getAuth()` refresh |
| Authorization service | existing official Desktop service reuse without duplicate registration |
| Direct hosted search | request-owned auth and managed protocol/endpoint mismatch checks fail closed; Responses/Anthropic inline search, Responses-only `ctx.web`, and bounded proof remain separate acceptance requirements |
| Client UI | official DSH Models provider-card authorization |
| Desktop-managed DSH | bundled `@deepseek-ai/dsh@0.1.6-alpha.1`, virtual descriptor SHA-256 `eca8a91da4737f625716323d0be8a51156b24934183904a41d06599ffafe36bd`; audited virtual plus unpacked backing inventory, no separate Core |
| Desktop | published fork-owned `0.1.6-alpha.1.cloga.17`, sequence 28, source `f25506b4ad190ce090b8a4e9602c7ad36179db6b`; formal run `35583602522` attempt 1 SUCCESS; **fresh hosted Native Ops run `35595040585` attempt 1 SUCCESS at exact code head `bb7a0a366e789b19918be6d8a6e40266c46a94f9`**, not a later evidence commit/merge (no local installation/activation/restart) |
| Desktop plugins | `desktopNativeVerifiedRelease` delegates ownership to Desktop; Windows Ops does not populate the reserved profile or copy its dependencies |

The legacy SlotOutlet and no-open recovery patches explicitly select the
`desktop-official` runtime and report `not-applicable` for the current
`desktop-fork-managed` release (`unsupported` without a resolved selector).
They are not positive acceptance evidence. Applicable patch targets still
require their exact markers; do not inject old renderer code or select an older
shell to make replay green.

The authoritative plugin is `dsh-github-copilot@0.4.0-alpha.33`, immutable
Release source `aa90fe434da8b2172faa1446afa0a0fd006afe00`; artifact SHA-256 is
`b293d40351f2e732969bac88c3906280b50c47a011bbeac1dc68bc4a8b0de480`.
Desktop delegates it through the single native provisioning adapter.

Historical `.cloga.2`/alpha.24 evidence remains immutable Release `391052820`, sequence 12, from source PR #63; it is not the current target. Formal run `35271210350` passed on attempt 1; six Release assets were independently byte-verified. Source acceptance artifact `10518683372` records isolated initial/restart account UI, actual Model roles/search-routing DOM readiness, read-only provider catalogs, graph/ancestor isolation and helper ACK/cancel. Alpha.24 repairs alpha.23's missing Client `remote.githubCopilotSearchRouting` injection. Both catalog phases include `deepseek-official` and `github-copilot-hosted`; this does not establish a real search or provider availability. **Historical `.cloga.2` native Ops qualification passed** in [run `35278350619`](https://github.com/cloga/dsh-windows-ops/actions/runs/35278350619) at exact head `243c33d286f19d9e4c608e238a52de2b9a136b9e`; its independently byte-bound [raw summary](../tests/fixtures/desktop-native-verified-release/ops-cloga016-2/qualification.json) records 9,806 runtime files, full archive-package identity, `metadata-cjs-esm`, one observer/profile cleanup and three request-copy rejections. Whole-carrier/model-response/installed-upgrade flags remain false. First pre-observer failure `35276462350` remains unexplained; the successful diagnostic head does not prove its cause was repaired. Historical [run `35210215981`](https://github.com/cloga/dsh-windows-ops/actions/runs/35210215981) and its [raw summary](../tests/fixtures/desktop-native-verified-release/ops-cloga016-1/qualification.json) qualify only `.cloga.1`/alpha.22; its public resolver/native-addon/policy and three request-copy negatives must not be relabeled as current release proof or advanced private-peer/custom-home/missing-addon coverage. No real search/OAuth/model round, local installer upgrade or local activation was performed; replay must report old installed bytes as drift. See the [exact target and evidence boundaries](local-core-desktop-copilot.md#authoritative-baseline) and mandatory [official-first upgrade checklist](local-core-desktop-copilot.md#official-first-upgrade-checklist).

Current `.cloga.17` / sequence 28 is a runtime-only maintenance target preserving Core `0.1.6-alpha.1` and Copilot `0.4.0-alpha.33`. [The owning release record](desktop-external-links-17.md) binds immutable Release `392847203`, formal run `35583602522` attempt 1 SUCCESS, source/tree and all six assets. The Electron DOM external-link fixture substitutes the OS opener; real browser navigation/OAuth are not established. Fresh hosted Native Ops run `35595040585` attempt 1 **passed** for this target at exact code head `bb7a0a366e789b19918be6d8a6e40266c46a94f9`; native job `106318363183` and all four jobs succeeded. The [raw summary](../tests/fixtures/desktop-native-verified-release/ops-cloga016-17/qualification.json) and [provenance](../tests/fixtures/desktop-native-verified-release/ops-cloga016-17/README.md) bind the original artifact. Later evidence commits/merges are not that qualified head; historical `.16` run `35577921833` at `cd384495ac2fd0c850b3c8cd93223d35c4bc83a0` does not transfer. First native failure `35590167413` remains unexplained; later diagnostics did not prove a startup-cause repair. Ordinary CI `35593395998` instead exposed an LF/CRLF test-extraction defect, fixed test-only at `bb7a0a3…`, not a runtime failure. Keep stage-only: no local installation, activation or restart.

**Historical `.cloga.16` qualification (not `.17` evidence):** `.cloga.16` formal run `35569892548` attempt 2 succeeded; six Release assets and formal proof were independently authenticated, with a separate original Actions ZIP audit. Schema-2 initial/restart evidence covers read-only workspace/catalog, provider-only routing/Fallback label and exact Desktop version menu; schema-1 usage evidence binds absent signed-out quota UI after account readiness without Host request instrumentation. The optional schema-1 positive usage proof uses actual renderer/released Client/SessionProvider/Slot with synthetic Session/quota/test mount, canonical+preview once after the restart graph and no Host transport. It is authenticated evidence, not live account/network proof. **Hosted Native Ops run `35575187267` attempt 1 passed** at exact code head `a59f586df4e329c3bc8b3f885013fdb5493f4970`, including native job `106255672689` and all four jobs. The later documentation/evidence-only follow-up records that result, not native qualification of its own head. Fresh positive proof is enforced by that exact qualified driver, not new summary flags; whole-carrier/model-response/installer-upgrade flags remain false. Historical `.cloga.14`/alpha.32 run `35553019059` cannot qualify this pair. The chosen outcome is stage-only with no local installation, activation or restart; live account verification awaits a future human request. Formal release run `35569892548` attempt 1's `EBUSY` cleanup failure remains history. See the [exact source, hashes and limits](copilot-alpha33-upgrade-record.md). No OAuth, same-window navigation, provider availability, live quota, real search or local activation is claimed.

Replay projects audited native runtime identity and read-only marker status;
it does not read credentials or establish live account/model readiness. User
extras permitted by ownership metadata remain `contentsAttested:false`, not
baseline health. Historical physical deployment/bootstrap credential checks are
a separate surface and must never expose grant payloads.

The installer `-Action Verify` requires no DSH path. It attests the official
Desktop executable/runtime descriptor and the exact Electron parent/Node-mode
Electron Host argv. Physical bundled upstream Node remains the pnpm/helper carrier,
not the Host. Native mode does not require port 3080 and returns
`manual-verification-required` rather than a functional pass. Only separate
Web/headless diagnostics inspect HTTP listeners. Native Apply is blocked;
it never builds, installs, or selects another DSH runtime.
Complete deployment acceptance also requires direct sign-in, model response,
hosted search, nonempty reasoning rendering, fresh-Session Copilot Tool Schema
acceptance, and rollback evidence.
