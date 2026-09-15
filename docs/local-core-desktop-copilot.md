# Official DSH Desktop and direct GitHub Copilot

## Newer account-discovered route maintenance

For the V3 account/Session model separation and removal of an existing extra native Copilot route, use [the separate config-only managed-route procedure](copilot-managed-route.md). Do not recreate native model definitions from this historical full-baseline guide or run its installer merely to migrate a newer Desktop. The maintenance command performs no component installation, Session/default selection, credentials access or restart; it requires fresh live evidence and explicit configuration approvals. Its policy does not replace the full deployment lock below.

## Authoritative baseline

[`deployments/windows-copilot.lock.json`](../deployments/windows-copilot.lock.json)
is the machine-readable deployment contract, verified on **2026-09-15**.

| Component | Locked identity |
|---|---|
| Desktop | fork-owned `0.1.5-rc.3.cloga.1`, release tag `dsh-desktop-v0.1.5-rc.3.cloga.1`, commit `87506730d5f511316bac5ea623610e124908c657` |
| Desktop artifact | [`cloga-deepseek-harness-0.1.5-rc.3.cloga.1-win-x64.exe`](https://github.com/cloga/deepseek-harness/releases/download/dsh-desktop-v0.1.5-rc.3.cloga.1/cloga-deepseek-harness-0.1.5-rc.3.cloga.1-win-x64.exe), SHA-256 `432fdc5f438ce4e9d984ff36546c42d4a43bb571f15230bfa127b133623e8367` |
| Desktop-managed runtime | default root `%LOCALAPPDATA%\Programs\DeepSeek Harness (cloga)\resources\dsh`, but the installer is interactive and may use a different `$INSTDIR`; Windows Ops follows the actual installed `cloga-deepseek-harness.exe` path |
| Installed Desktop | executable SHA-256 `f77b28611cba6210f6441318db7453d32ff7b2c4cf58fd58ce0b44e743f25434`; runtime descriptor `resources\dsh\desktop-runtime.json` SHA-256 `210cacaf3842643ef6c124fd23cb3b67caf7008e97868c733550b56ba7a1e836` |
| Runtime attestation | fork release manifest schema 3, self SHA-256 `753ac3ae302e03d85e120742f07e6c5c0ad5c88103c70c78e5b0335fe84e35cc`, raw SHA-256 `234caae905de71144e4dc4b6ecdfebf567c6cfdf7dad546c0d766fa7dd2937b3`; bundled CLI baseline `@deepseek-ai/dsh@0.1.5-rc.2` |
| Copilot plugin | `dsh-github-copilot@0.4.0-alpha.18`, PR #120, source/merge/release commit `08bfccc3b5930b93ef2fe31d9cf9e509f34a8704` |
| Plugin artifact | Immutable Release [`dsh-github-copilot-0.4.0-alpha.18.tgz`](https://github.com/cloga/dsh-github-copilot/releases/download/v0.4.0-alpha.18/dsh-github-copilot-0.4.0-alpha.18.tgz), 538,911 bytes, SHA-256 `2ca4f604e89eda3000cf2a51d79871cee3cb721fa6f4324fc9a1197926c359a8`, SHA-512 SRI `sha512-FZdWZbb/K8jmE64Gwb9ZU+UADAqakAfqLXrru/qpLFSS4qC4LMO0uIcU1Kbsw1Cg55xf0q+ZSbn0y3cdyDzLXw==`; verify with the same Release's [`SHA256SUMS`](https://github.com/cloga/dsh-github-copilot/releases/download/v0.4.0-alpha.18/SHA256SUMS), digest `caf7a63a46764b499df15acd6eca020b449ca34bd868f7064712c29df53a5293` |
| Desktop native capability | `desktopNativeVerifiedRelease`; generic plugin compatibility evidence is present, `automaticProvisioning=false`, and Windows Ops no longer mutates the Desktop profile through the external workaround |

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

## Core 0.1.3-alpha.1 readiness record

[`core-0.1.3-alpha.1-desktop-cutover.md`](core-0.1.3-alpha.1-desktop-cutover.md)
records reviewed companion-plugin evidence and local risk reduction. It is a
non-executable readiness record: the cutover remains blocked until an official
Desktop-managed target and the complete lock/catalog/fixture/test baseline are
updated together. It does not change the locked baseline on this page.

## Check first

### User preset Config compatibility (managed entrypoints only)

A preset can remain on disk but stop mounting after an official runtime schema
change. The September 2026 persona incident was **not file loss**: the persisted
`config.text` still held the instructions, while upstream
`deepseek-ai/deepseek-harness@40792330c0d534ef382bbf1fb44c9289323bbb27`
changed the persona contract to required `prefix` and optional `suffix`.
A cold resume then failed on missing `prefix`. Recovering a reviewed key while
preserving its content restored the affected tasks and model UI; copying a
default preset over the user's instructions is not a safe recovery.

Check and Verify now run `Test-DshUserPresetConfig` before other runtime checks.
The locked Apply implementation runs the same gate before Desktop inspection,
artifact extraction, backup creation, npm, process or Profile mutations.
`-SkipRuntimeChecks` does **not** disable this gate. Incompatibility or an
uncheckable scope returns `checks.userPresetConfig.valid = false` and exit code
**2** from Check/Verify; Apply throws `user-preset-config-blocked`.
The direct installation health report also includes `profile.userPresetConfig`.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-windows-copilot.ps1 `
  -Action Check -DshHome (Join-Path $HOME '.dsh') -SkipRuntimeChecks
```

The scope is direct child directories of the explicitly resolved, fully qualified local
`<DshHome>\.agent-presets`, each containing `agent.cordis.yml`. Missing
compositions, reparse points, malformed YAML, conflicting metadata, unresolved
plugins and dynamic **config** fail closed. Non-config `!!js` control predicates
are left unevaluated; even disabled rows are conservatively checked. Nested
literal `group` lists are checked recursively. Custom preset roots, relative/file
plugins, package subpaths, custom loader hooks and include/tree-carrier plugins
are unsupported rather than guessed healthy. Limits are 128 manifests, 1 MiB
each / 8 MiB total, 4,096 rows, 32 group levels and 256 diagnostics.
An absent or empty user roster reports `no-user-presets` without creating it or
requiring target artifacts; it does not attest an absent target runtime.

For a nonempty roster, the **target** is exclusively
`acceptance.runtimeSchema` in the deployment lock, including its whole-wrapper
hash and exact package/entrypoint identity. The current parent process, global
npm packages, Profile overlays and a newer installed runtime are not substitute
targets. The existing lock still selects wrapper `0.1.2-alpha.5` / Core
`0.1.2-rc.1`; this gate does not certify a live `0.1.5-rc.2` installation against
that older lock. Missing target artifacts on a new installation return
`target-artifacts-unavailable`; differing bytes return
`target-artifacts-unverified`. There is no staged-target installer in this gate:
the exact locked, physical official wrapper must already be available.
Do not replace a running wrapper just to satisfy this precondition.

An isolated Node subprocess resolves every imported file from that attested
target, consumes its exported `entryListSchema`, and uses the plugin's published
Standard Schema `Config` contract without starting a Cordis context or invoking
plugin apply, boot, resume, model or provider APIs. As in published Cordis
`resolveConfig`, a plugin with no `Config` is explicitly reported as
`schema-less-passthrough`, **not** proof of application-level config validity.
Conflicting exports, malformed schemas and async validators block the gate.
Schema-normalized values are discarded; no migration or write-back occurs.

The child runs with Node read-only filesystem permissions, no inherited
credentials/Node preload environment, no child processes/native addons/workers,
and disabled network entrypoints. Imports or validators needing those facilities
are unsupported. This is isolation for reviewed, attested code, not a sandbox
for hostile plugins. The worker has a 20-second default deadline (maximum 60),
192 MiB V8 heap and bounded output. Diagnostics contain only preset-relative
paths, positional rows, plugin/version, schema-declared key paths (unproven
segments become `*`), stable codes and review actions. Parser buffers, schema
messages, prompt values and child stdout/stderr are never forwarded.
Input hashes are rechecked before reporting; the result is a point-in-time
assessment, not a lock against concurrent external edits.

**Boundary:** this protects these managed entrypoints only. It cannot intercept
arbitrary official Desktop GUI updates, and does not claim that it does.
It does not rewrite presets, change scheduler tasks, migrate credentials,
install dependencies, patch Core or restart Desktop/Host.

The one-command check is read-only:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-windows-copilot.ps1
```

Check mode validates the lock, fork-owned Desktop release, installed executable
hash, Desktop-managed runtime descriptor, native provisioning capability, the
direct Copilot package and composed profiles, credential-record metadata, the
reference-free route, and the exact active Desktop PID owning IPv4
`127.0.0.1:3080`. An absent managed runtime, managed identity/payload drift,
wrong path, stale process, non-owning PID, IPv6-only listener, or legacy gateway
fails closed. User-installed plugins are reported separately as unmanaged
inventory and warnings; they never contribute managed-baseline health. An exact
active target-Core denylist match remains a cutover blocker.

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
  -CopilotIntegrationArtifactPath C:\artifacts\dsh-github-copilot-0.4.0-alpha.18.tgz
```

## Apply the locked Desktop and plugin

Use only the plugin source checkout at
`08bfccc3b5930b93ef2fe31d9cf9e509f34a8704`, the immutable plugin Release
tarball, and the fork-owned Desktop artifact:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\install-windows-copilot.ps1 `
  -Apply `
  -CopilotIntegrationSourceRoot C:\src\dsh-github-copilot `
  -CopilotIntegrationArtifactPath C:\artifacts\dsh-github-copilot-0.4.0-alpha.18.tgz `
  -DesktopArtifactPath C:\artifacts\cloga-deepseek-harness-0.1.5-rc.3.cloga.1-win-x64.exe `
  -IncludeCompanionSuite `
  -BackupRoot C:\dsh-ops-backups
```

`-BackupRoot` is optional. `-IncludeCompanionSuite` opts the reviewed Cron and
Playwright Host overlays into the same Copilot Apply plan, backup operation, and
rollback receipt. Exact identities come from the deployment lock; the installer
does not invoke a second opaque installer. Without the switch, the base remains
Copilot-only. Apply verifies source metadata and immutable Release bytes,
installs Desktop and the selected companions, preserves native Desktop
delegation, and attests the fork-owned Desktop-managed runtime descriptor. It
never builds, installs, or selects a second DSH runtime.

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
  -CopilotIntegrationPackage C:\artifacts\dsh-github-copilot-0.4.0-alpha.18.tgz
```

The package argument may be the exact locked GitHub Release URL or a local copy
whose SHA-256 matches the lock; npm is not a distribution channel. The wrapper
installs `dsh-github-copilot` in `web` and `headless`, configures only the
plugin and `github-copilot-hosted` search selection, removes reviewed legacy
route references, and reports credential metadata without exposing grant
payloads. It does not write provider routes, model lists, base URLs, or API-key
references. Despite its historical file name, it does not install
`dsh-vision-any` or another visual fallback. Image-capable models receive
uploaded attachments through DSH's native image channel, and Agents use the
built-in `read_image` tool to open workspace image files. Text-only models must
be switched to an image-capable route rather than silently delegating the image
to a second provider.

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

`dsh-playwright-host@0.1.2` and `dsh-cron@0.4.1` remain reviewed optional Web
overlays. When `-IncludeCompanionSuite` selects them, their exact source,
artifact, closure, and bundle state are strict gates. When not selected, a
configured-source mismatch is inventory/warning data rather than base-baseline
health. `dsh-github-copilot` remains required and cannot be removed by
optional-overlay removal. See
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

Verify attests fork-owned Desktop `0.1.5-rc.3.cloga.1`, its managed runtime
descriptor, the plugin/native delegation contract, and the exact active PID owning IPv4
`127.0.0.1:3080`. It does not install or select another runtime. Check or Verify
may report drift or `sign-in-required` on an unprepared machine; that is
expected fail-closed behavior, not a success-shaped fallback.
