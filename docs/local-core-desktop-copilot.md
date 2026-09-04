# Official DSH Desktop and direct GitHub Copilot

## Authoritative baseline

[`deployments/windows-copilot.lock.json`](../deployments/windows-copilot.lock.json)
is the machine-readable deployment contract, verified on **2026-09-04**.

| Component | Locked identity |
|---|---|
| Desktop | official `0.10.3`, release tag `v0.10.3`, commit `113dc8f77095e765f4f55e233d8455e7ad9204ae` |
| Desktop artifact | [`Deepseek.Harness.Desktop_0.10.3_x64-setup.exe`](https://github.com/dsh-tauri-desk/deepseek-harness-desktop/releases/download/v0.10.3/Deepseek.Harness.Desktop_0.10.3_x64-setup.exe), SHA-256 `ce4328448a948e6df904548455a32b81f9905908f3b8562f8e8fdfdbac3bfb90` |
| Desktop-managed runtime | root `%APPDATA%\io.github.hairyf.deepseek-harness-desktop\dependencies\dsh`; wrapper `deepseek-harness-pkg@0.1.2-alpha.5`; inner official `@deepseek-ai/dsh@0.1.2-rc.1` |
| Installed Desktop | executable 23,059,456 bytes, SHA-256 `d191cb2729f53c4fa889fab62c48af38979812f5560d0bb8f8ad4cadeff8b5df`; `resources` 1,765 files / 13,008,656 bytes, tree SHA-256 `29323493802cc7d75fd02a762066d7be8f0da1ac86e1fe1f8f44e2ea15d074ef` |
| Runtime attestation | complete wrapper closure 10,347 files / 134,066,533 bytes, tree SHA-256 `b0f32889536e1bce92a6bc032b11a6865e946015b44de5db4397f080e309c86d`, zero reparse directories; inner package 10 files, tree SHA-256 `4f5b21b9a7f0aee7908e8ebf915903f39cb85b755d6cb2ef200fc0afd6d602ea`; entrypoint 8,021 bytes, SHA-256 `dc23f6c5dd7df8834e3e38bdb9609d77b459834681ae9b7133b417b0c35f3166` |
| Copilot plugin | `dsh-github-copilot@0.3.0-cloga.15`, PR #56 source commit `4e095196197570776515423929ddb72e8299c1db`, merge commit `473b8aa174eb47a323b026c098b73bf7d716772c` |
| Plugin artifact | Immutable Release [`dsh-github-copilot-0.3.0-cloga.15.tgz`](https://github.com/cloga/dsh-github-copilot/releases/download/v0.3.0-cloga.15/dsh-github-copilot-0.3.0-cloga.15.tgz), release commit `473b8aa174eb47a323b026c098b73bf7d716772c`, SHA-256 `7486d2c062c7fcdd5ee36505ff9320eaec634497c1ea2481b335ea67e85a25b1`; verify with the same Release's [`SHA256SUMS`](https://github.com/cloga/dsh-github-copilot/releases/download/v0.3.0-cloga.15/SHA256SUMS) |
| Desktop internal plugins | eight official `0.6.7` Profile links, including `dsh-tauri-panel-scheduler`, plus the non-bundled panel placeholder under `resources\node_modules` |

Do not independently upgrade or substitute a locked component. Update the lock,
catalog, fixtures, tests, and explanatory guides together only after a new
baseline is verified. The installer consumes the official Desktop artifact and
immutable Copilot Release; it does not distribute either one.

Desktop owns the only supported DSH runtime. Apply never builds, installs, or
selects another DSH runtime. It attests the Desktop-managed wrapper, inner
package tree, and exact entrypoint, then confirms that the active exact Desktop
PID owns the IPv4 listener at `127.0.0.1:3080`. A same-version executable,
resource tree, wrapper closure, or hoisted dependency modification fails closed.

## What “all-in-one” means

`dsh-github-copilot` is one required DSH plugin that composes existing DSH
services. It reuses built-in `@deepseek-ai/dsh-llm-pi-ai` and pi-ai for:

- GitHub OAuth/device authorization;
- account-available Copilot model discovery;
- the reference-free `llm-pi-ai.providers.github-copilot` route;
- credential record `llm-pi-ai/github-copilot`;
- serialized token refresh and direct Copilot model transport.

The plugin adds the authorization UI and direct provider-hosted search. Its
built client entry hands the plugin id, injected `require`, and materialized
exports to Desktop's `window.__ModuleLoader__.load` contract. Client Remote
calls use strict Zod result codecs so malformed authorization views fail closed.
When the shared grant is valid, activation reconciles an absent, empty, or stale
account model list. Missing profiles are created without connection references;
existing profiles retain fields the plugin does not own. Every available model
keeps its installed `id` and `api`.

The plugin removes top-level `sandbox_permissions` and `justification` only from
tool schemas assembled for `github-copilot`; every other provider retains DSH's
native escalation surface. Inline hosted search supports Responses and
Anthropic Messages, while `github-copilot-hosted` through `ctx.web` is
Responses-only. Capability probing is fail-closed by default; `probe: false`
bypasses only capability proof. Requests go directly to validated GitHub-hosted
or signed-in Enterprise Copilot endpoints. There is no active local gateway,
port 7777 dependency, pasted GitHub token, placeholder API key, or separate
search-provider package.

The fourteen required plugin capabilities are copied from its exported
`deployment-baseline.json`:

1. `client-module-loader-handoff`
2. `strict-remote-result-codecs`
3. `authorization-service-bootstrap`
4. `models-provider-card-authorization`
5. `path-level-account-model-reconciliation`
6. `copilot-optional-tool-arguments`
7. `per-model-api-route-materialization`
8. `existing-grant-route-self-healing`
9. `shared-copilot-credential-refresh`
10. `strict-json-oauth-grant-normalization`
11. `direct-provider-hosted-search`
12. `traditional-search-bridge`
13. `dsh-supported-baselines-fail-loud-guard`
14. `dsh-rc2-models-settings-fallback`

ACP subagents remain separate; see
[`copilot-acp-subagent.md`](copilot-acp-subagent.md).

## Check first

The one-command check is read-only:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-windows-copilot.ps1
```

Check mode validates the lock, official Desktop, Desktop-managed wrapper/tree/
entrypoint, all eight official Profile links and the non-bundled placeholder,
the direct Copilot package and composed profiles, credential-record metadata,
the reference-free route, and the exact active Desktop PID owning IPv4
`127.0.0.1:3080`. An absent runtime, unknown package, wrong path, stale process,
non-owning PID, IPv6-only listener, or legacy gateway fails closed.

For both `web` and `headless`, check mode compares the Copilot dependency in
`package.json`, the matching `pnpm-lock.yaml` importer and tarball, the installed
package manifest, exported deployment baseline, and artifact SHA-256. A mismatch
is reported as `profile-manifest-lock-installed-drift`; check mode never repairs
it. A missing `llm-pi-ai/github-copilot` grant is reported as
`sign-in-required`. Credential payloads are never included in output.

To preflight optional local copies of the exact plugin inputs without applying:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\install-windows-copilot.ps1 `
  -CopilotIntegrationSourceRoot C:\src\dsh-github-copilot `
  -CopilotIntegrationArtifactPath C:\artifacts\dsh-github-copilot-0.3.0-cloga.15.tgz
```

## Apply the locked Desktop and plugin

Use only the plugin source checkout at
`4e095196197570776515423929ddb72e8299c1db`, the immutable plugin Release
tarball, and the official Desktop 0.10.3 artifact:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\install-windows-copilot.ps1 `
  -Apply `
  -CopilotIntegrationSourceRoot C:\src\dsh-github-copilot `
  -CopilotIntegrationArtifactPath C:\artifacts\dsh-github-copilot-0.3.0-cloga.15.tgz `
  -DesktopArtifactPath C:\artifacts\Deepseek.Harness.Desktop_0.10.3_x64-setup.exe `
  -IncludeCompanionSuite `
  -BackupRoot C:\dsh-ops-backups
```

`-BackupRoot` is optional. `-IncludeCompanionSuite` opts the reviewed Cron and
Playwright Host overlays into the same Copilot Apply plan, backup operation, and
rollback receipt. Exact identities come from the deployment lock; the installer
does not invoke a second opaque installer. Without the switch, the base remains
Copilot-only. Apply verifies source metadata and immutable Release bytes,
installs Desktop and the selected companions, preserves the eight official
Profile links and non-bundled placeholder, and attests the official
Desktop-managed runtime. It never builds, installs, or selects a DSH runtime.

Add `-RestartDesktop` only when a restart is intended. Before stopping any
process, the installer queries the live `session/list` API. Every running
Session blocks restart unless the user directly accepts the listed
interruptions and the same command supplies
`-AcknowledgeLiveSessionIds <exact listed IDs>`. Stale, missing, or extra IDs
block restart. Dry-run never stops a process, and an unavailable or malformed
live-session response fails closed while Desktop is running.

## Bootstrap, sign in, and accept

The historical wrapper name remains for plugin configuration:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\enable-copilot-search-vision.ps1 `
  -CopilotIntegrationPackage C:\artifacts\dsh-github-copilot-0.3.0-cloga.15.tgz
```

The package argument may be the exact locked GitHub Release URL or a local copy
whose SHA-256 matches the lock; npm is not a distribution channel. The wrapper
installs `dsh-github-copilot` in `web` and `headless`, selects
`github-copilot-hosted` search, removes reviewed legacy references, and reports
credential metadata without exposing grant payloads.

Open **Models → GitHub Copilot**, complete the displayed device flow, and choose
only a model present in the account-filtered route. Then run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\enable-copilot-search-vision.ps1 `
  -Action Verify `
  -Model '<account-available-model-id>'
```

Acceptance requires all of the following:

1. direct sign-in succeeds and the shared Copilot grant remains payload-redacted;
2. a direct model response succeeds with the selected account-available model;
3. direct hosted search succeeds without a local gateway endpoint;
4. a reasoning response renders nonempty reasoning without blank Think cards;
5. a fresh Session accepts the Copilot-scoped Tool Schema while non-Copilot
   providers retain the native schema;
6. the exact active Desktop PID owns IPv4 `127.0.0.1:3080`.

## Optional Web-profile overlays

`dsh-playwright-host@0.1.2` and `dsh-cron@0.4.1` remain optional Web overlays.
Select both atomically with `-IncludeCompanionSuite`; they are not silently
required by the base Windows Copilot deployment. `dsh-github-copilot` remains
required and cannot be removed by optional-overlay removal. See
[`computer-use.md`](plugins/computer-use.md) and
[`scheduling.md`](plugins/scheduling.md).

## Legacy migration and rollback

Legacy gateway facts remain migration signatures only, never active components
or success criteria. Run check mode first, retain its redacted result, and apply
only when detected files or configuration match the reviewed migration
contract. Unknown binaries or references fail closed.

Every mutation is backed up before profile, route, credential-reference, or
legacy cleanup. When Apply installs Desktop, the same operation also snapshots
the install directory, uninstall registry key, and user Desktop/Start Menu
shortcuts. Roll back an installer operation with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\install-windows-copilot.ps1 `
  -Action Rollback `
  -OperationId '<operation-id>' `
  -BackupRoot C:\dsh-ops-backups
```

The bootstrap has its own receipt-backed rollback:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\enable-copilot-search-vision.ps1 `
  -Action Rollback `
  -OperationId '<bootstrap-operation-id>'
```

Rollback does not waive restart safety. If a restart is requested, query live
Sessions and acknowledge the exact running IDs as described above.

## Verification

Repository-only checks do not touch the active deployment:

```powershell
node tools\validate-repository-content.mjs
node tools\validate-plugin-catalog.mjs
Invoke-Pester -Path tests
```

Machine-state verification needs no DSH path:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\install-windows-copilot.ps1 -Action Verify
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\test-dsh-runtime-schema.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\dsh-replay.ps1 -Action SelfCheck
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\dsh-replay.ps1 -Action Apply -DryRun
python tools\dsh-web-smoke.py --expect-text "New Session" `
  --fail-on-console-error --fail-on-request-failure --fail-on-http-error
```

Verify attests official Desktop 0.10.3, its managed wrapper/tree/entrypoint, the
plugin and Profile contract, and the exact active PID owning IPv4
`127.0.0.1:3080`. It does not install or select another runtime. Check or Verify
may report drift or `sign-in-required` on an unprepared machine; that is
expected fail-closed behavior, not a success-shaped fallback.
