# Official DSH Desktop and direct GitHub Copilot

## Newer account-discovered route maintenance

For the V3 account/Session model separation and removal of an existing extra native Copilot route, use [the separate config-only managed-route procedure](copilot-managed-route.md). Do not recreate native model definitions from this historical full-baseline guide or run its installer merely to migrate a newer Desktop. The maintenance command performs no component installation, Session/default selection, credentials access or restart; it requires fresh live evidence and explicit configuration approvals. Its policy does not replace the full deployment lock below.

## Authoritative baseline

[`deployments/windows-copilot.lock.json`](../deployments/windows-copilot.lock.json)
is the machine-readable deployment contract, verified on **2026-09-15**.

| Component | Locked identity |
|---|---|
| Desktop | fork-owned `0.1.5-rc.3.cloga.3`, release tag `dsh-desktop-v0.1.5-rc.3.cloga.3`, commit `f34f048a6a862046de9b75f2aabf48944819f0d4` |
| Desktop artifact | [`cloga-deepseek-harness-0.1.5-rc.3.cloga.3-win-x64.exe`](https://github.com/cloga/deepseek-harness/releases/download/dsh-desktop-v0.1.5-rc.3.cloga.3/cloga-deepseek-harness-0.1.5-rc.3.cloga.3-win-x64.exe), SHA-256 `10964ad5c668a0513cc3bf79f7cb8d5c091445eca06f629d33d20bcf1dc8eba5` |
| Desktop-managed runtime | default root `%LOCALAPPDATA%\Programs\DeepSeek Harness (cloga)\resources\dsh`, but the installer is interactive and may use a different `$INSTDIR`; Windows Ops follows the actual installed `cloga-deepseek-harness.exe` path |
| Installed Desktop | executable SHA-256 `594f5da5e36109711a55cd556b65b11196b07583b5c6914fcf15c0d83073b0c2`; runtime descriptor `resources\dsh\desktop-runtime.json` SHA-256 `7563c64128ecbd38ea058f0e1b380e87df0691c7dfb42f536f545f15f2333085` |
| Runtime attestation | fork release manifest schema 3, self SHA-256 `8a8fa3a39c355494cc086e0c85d0376271a3b745366620097dfb7f692b15343b`, raw SHA-256 `8c4661f963621e8e97da0490f9e616d635fec217a737d321ae7d7fcc36b1365b`; bundled CLI baseline `@deepseek-ai/dsh@0.1.5-rc.2` |
| Copilot plugin | `dsh-github-copilot@0.4.0-alpha.22`, PR #133, source/merge/release commit `479340f965c5be7b4408e4f1e6c9dda6c421d37b` |
| Plugin artifact | Immutable Release [`dsh-github-copilot-0.4.0-alpha.22.tgz`](https://github.com/cloga/dsh-github-copilot/releases/download/v0.4.0-alpha.22/dsh-github-copilot-0.4.0-alpha.22.tgz), 651,444 bytes, SHA-256 `e749d982ac55752eeca4cf4819b9751144cda1c2dc06033e4b42240151e40e0e`, SHA-512 SRI `sha512-HkGACgfUrTREbtbUgZJ6Sb02hqKseCtldW16ZBounQZahTpeKWW5bqj5TNb1MD6X7y4e5MI0Q5edYLCF71ybnQ==`; verify with the same Release's [`SHA256SUMS`](https://github.com/cloga/dsh-github-copilot/releases/download/v0.4.0-alpha.22/SHA256SUMS), digest `cdc2a7e8df955c9136c6c79c25adaaf929bee815308ff3ceb6c9cfb948c03546` |
| Desktop native capability | `desktopNativeVerifiedRelease`; generic plugin compatibility evidence is present, `automaticProvisioning=false`, and Windows Ops no longer mutates the Desktop profile through the external workaround |

Do not independently upgrade or substitute a locked component. Update the lock,
catalog, fixtures, tests, and explanatory guides together only after a new
baseline is verified. The installer consumes the official Desktop artifact and
immutable Copilot Release; it does not distribute either one.

Desktop owns the only supported DSH runtime. Apply never builds, installs, or
selects another DSH runtime. It attests the installed executable and bundled
runtime descriptor. Native acceptance binds the exact Electron parent and its
bundled Node Host arguments; it does not require a `127.0.0.1:3080` listener.
Matching version text alone is insufficient. The locked executable's actual PE
ProductVersion is `0.1.5.0`, CompanyName is `GitHub, Inc.`, and Authenticode is
`NotSigned`; the semantic release version remains `0.1.5-rc.3.cloga.3`.

The immutable recovery Release is ID `390062857`, incorporating the helper repair
in `cloga/deepseek-harness#43` and test reliability change in
`cloga/deepseek-harness#44`, published by run `35115948742`. Its schema-3
update manifest intentionally retains `automaticProvisioning=false` so the old
installed update client can parse it. Do not change this field or insert new
manifest keys. Native startup provisioning is separately declared by the
build receipt (`automaticProvisioning=true`) and packaged managed capability
schema 3, both binding canonical plan SHA-256
`d381ba004763970ae24991046b5811a958ad1238c8f2c5b862ed8fffc041cfbb`.
The two compatibility objects must not be equated wholesale. Windows Ops
checks their shared capability, exact published hashes, canonical self hashes,
and plan binding; installation checks additionally require actual profile
receipts, state, inventory and artifact bytes.

The formal run verified standalone copied-helper bootstrap, a synthetic
handoff ACK and cancellation, initial/restart provisioning and the signed-out Models
account entry. It did not perform OAuth, a real model round, or a local
old-to-new installer upgrade. Hosted success does not establish local registry
TLS connectivity or authenticated model readiness.

## Managed Desktop update behavior

**Older-helper recovery:** `.cloga.1` and `.cloga.2` copied helpers have an
unresolved `semver` import and fail before ACK without `node_modules`. A new
release cannot repair an already installed broken helper. Use the independently
verified formal `.cloga.3` installer out of band only after explicit interruption
consent and a clean Desktop/Host exit, with normal interactive Windows/UAC
handling. Do not reuse the failed handoff, patch live helper files, add operation
dependencies or bypass session protection. The repaired helper hash is
`54aa5767c9f993f39a21d2a8d4aa23cd8b377301d19de0cd8d379d4fad4d313e`;
its synthetic ACK test is not proof of a completed live installer upgrade.
Generic direct registry probes do not establish a supported provisioner failure
and do not justify registry/CA/VPN/TLS changes.

The fork-owned Desktop checks for managed updates about ten seconds after
startup. This is automatic discovery, not unattended installation. After the
user confirms the impact on active work, the helper downloads and verifies the
release, waits for the exact handed-off Desktop/Host processes, and launches
the interactive NSIS installer. Windows warnings and UAC remain user-controlled;
no silent installer arguments or name-wide process termination are permitted.
Completion requires matching installed evidence and provisioning plan/receipt
on restart, not merely a successful download or installer exit.

The local-build Package/Check/Stage/Complete recovery tools remain a separate
explicit flow; they do not enable the signed native Electron updater. Before a
coordinated Web-host upgrade, re-read live `session/list` and obtain acknowledgement
of the exact running Session IDs. Native Desktop has no external Session API;
use its existing UI impact assessment and consent-gated helper. External
restart/Apply/rollback must fail closed while native session evidence is
unavailable, not treat an absent 3080 listener as zero Sessions.
Dependency downloads must pass normal TLS
verification against the release's registry. A cache-only run is not evidence
that first-install provisioning can reach its dependencies.

## What “all-in-one” means

`dsh-github-copilot` is one required DSH plugin that composes existing DSH
services. It reuses built-in `@deepseek-ai/dsh-llm-pi-ai` and pi-ai for:

- GitHub OAuth/device authorization;
- account-available Copilot model discovery through the plugin-owned managed
  provider, separate from an optional legacy canonical profile;
- credential record `llm-pi-ai/github-copilot`;
- serialized token refresh and direct Copilot model transport.

The plugin adds the authorization UI and direct provider-hosted search. Its
built client entry hands the plugin id, injected `require`, and materialized
exports to Desktop's `window.__ModuleLoader__.load` contract. Client Remote
calls use strict Zod result codecs so malformed authorization views fail closed.
Managed model metadata comes from the owning account snapshot. An intentionally
absent canonical profile remains absent. Existing canonical profiles retain
their models, APIs, and headers; legacy repair changes only the owned
strict-mode compatibility leaf and honors ownership-journal conflicts.

The plugin removes top-level `sandbox_permissions` and `justification` only from
tool schemas assembled for canonical `github-copilot` or a verified plugin-owned
`github-copilot-preview`; every other provider retains DSH's native escalation
surface. Inline hosted search supports Responses and
Anthropic Messages, while `github-copilot-hosted` through `ctx.web` is
Responses-only. Capability probing is fail-closed by default; `probe: false`
bypasses only capability proof. Requests go directly to validated GitHub-hosted
or signed-in Enterprise Copilot endpoints. There is no active local gateway,
port 7777 dependency, pasted GitHub token, placeholder API key, or separate
search-provider package.

The thirty-two required plugin capabilities are copied from the immutable
artifact's exported `deployment-baseline.json`, including
`desktop-shared-package-ownership`. Authorization and schemastery are required
host peers, not plugin-owned runtime dependencies; private or optional copies
fail the Windows Ops package contract. The plugin retains its own
`@earendil-works/pi-ai@0.85.1` and `zod@^4.4.3` runtime dependencies.
The peer range admits `0.1.6-alpha.1`, but this deployment still selects only the
locked Desktop-bundled `0.1.5-rc.2` Core. Package admission is not live Models
validation and never authorizes an independent Core upgrade.

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
hash, Desktop-managed runtime descriptor, native provisioning capability and
actual reserved-profile inventory. It binds the exact active Electron/Node
process relationship rather than a Web listener. Missing evidence, wrong
paths, stale processes and payload drift cannot pass. Its JSON keeps
`valid=false` because native live Remote/model evidence is unavailable to this
CLI; `staticValid` describes structural evidence only.

In the legacy Web mode only, check compares the Copilot dependency in
`package.json`, the matching `pnpm-lock.yaml` importer and tarball, the installed
package manifest, exported deployment baseline, and artifact SHA-256. A mismatch
is reported as `profile-manifest-lock-installed-drift`; check mode never repairs
it. A missing `llm-pi-ai/github-copilot` grant is reported as
`sign-in-required`. Credential payloads are never included in output.

To preflight an exact local plugin artifact without applying:

```powershell
Import-Module .\tools\WindowsCopilotDeployment.psm1
$lock = Read-WindowsCopilotLock .\deployments\windows-copilot.lock.json
Test-ProviderDeploymentContract -Lock $lock `
  -ArtifactPath C:\artifacts\dsh-github-copilot-0.4.0-alpha.22.tgz
```

## Apply the locked Desktop and plugin

For the current native lock, use Desktop's existing managed update UI and its
consent-gated interactive installer helper. The packaged exact plan provisions
alpha.22 at startup. Windows Ops `-Apply`, `-RestartDesktop`, rollback and
`-IncludeCompanionSuite` cannot stand in for native Session assessment and are
rejected by this entrypoint. Do not manually materialize `profiles\desktop`,
copy `node_modules`, or run a profile-local package install.

The legacy `windowsOpsVerifiedRelease` mode retains its explicit Apply/backup
contract and exact `session/list` acknowledgement. Those legacy commands are
not a recipe for this native lock. Optional companions remain Web-only and
must not be added to the required native plan. Dry-run never stops a process.

## Bootstrap, sign in, and accept

For the current native Desktop, use the real Models account UI to sign in and
select an account-available model, then obtain an actual model response.
The following historical wrapper applies only to a separately operated
Web/headless profile; it does not configure or verify the native Desktop Host:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\enable-copilot-search-vision.ps1 `
  -CopilotIntegrationPackage C:\artifacts\dsh-github-copilot-0.4.0-alpha.22.tgz
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
6. native Desktop has exact installed/Host identity plus independently observed
   UI/model evidence; only a separate Web deployment requires its owning IPv4
   listener at `127.0.0.1:3080`.

## Optional Web-profile overlays

`dsh-playwright-host@0.1.2` and `dsh-cron@0.4.1` remain reviewed optional Web
overlays. When `-IncludeCompanionSuite` selects them, their exact source,
artifact, closure, and bundle state are strict gates. When not selected, a
configured-source mismatch is inventory/warning data rather than base-baseline
health. `dsh-github-copilot` remains required and cannot be removed by
optional-overlay removal. See
[`computer-use.md`](plugins/computer-use.md) and
[`scheduling.md`](plugins/scheduling.md).

The native baseline validates the reserved `profiles\desktop` profile through
the packaged plan and actual receipts/state/inventory. Separate `profiles\web`
and `profiles\headless` installations are not native success evidence.
Do not install ordinary plugin dependencies into that profile with profile-local
`pnpm install`: it can hoist reserved host packages such as
`@deepseek-ai/cordis` into `profiles\desktop\node_modules` and make Desktop
reject the profile at startup. Desktop UI visibility must come from a Desktop-native plugin
provisioning path, not from mutating the reserved profile as an ordinary DSH
profile. Static inventory alone still does not prove an authenticated account,
active Session model selection, or successful model response.

## Legacy migration and rollback

This section applies only to legacy Web operations and their receipts. Native
external rollback is blocked; use the supported native recovery path with
live impact assessment, never these commands against a running native Host.

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

### Native structural versus functional acceptance

The published alpha.22 metadata declares React through `dsh.client.external`
as a Client static singleton. React must not reappear in root dependencies,
optional dependencies or peers: alpha.21 failed real Desktop startup when its
React peer was evaluated against the Node Host graph. Authorization and
schemastery remain required Host-owned peers; plugin-owned pi-ai/zod checks
are unchanged. This package correction is necessary but is not a substitute
for actual Desktop startup and committed native provisioning evidence.

Native Check/Verify verifies the lock-selected installed PE identity, the exact
descriptor-attested runtime inventory, the release-owned provisioning plan and
capability, the reserved Desktop profile, immutable local plugin artifact,
receipt/reconciliation state and every published JavaScript entrypoint.
The active Host must be a direct child of that Desktop executable using bundled
Node and the exact Host script, runtime root and `profiles\desktop` arguments.
No global npm root, Web profile, credential record or canonical route is used
as native evidence.

The Electron Host uses parent-owned byte pipes and `dsh-app://`, not an HTTP
listener on port 3080. The Web smoke command above applies only to a separately
running Web/headless surface. No replacement HTTP Host is started. Native
functional acceptance remains `manual-verification-required`; Verify exits 2
and does not count unknown Remote evidence as success. Independently inspect
the real Electron Models/account UI and obtain a real model response. That
operator evidence is separate; it does not make this CLI return a functional
pass.

The plugin's strict read-only `githubCopilot.status()` and
`githubCopilot.migrationStatus()` projections require the exact loaded plugin
version, protocol 1, complete provider registration, a signed-in non-in-flight
authorization state, a ready account model projection and the exact model.
Requested live Session selections must also match, including the recorded
request selection for running Sessions. `nativeConfigured=false` and canonical
`route.state=not-configured` are valid for the managed provider
`github-copilot-preview`; do not recreate a canonical profile. The pure
projection assessment helper is not a live transport or a full-baseline proof.
Do not call `ensureModels`/`discoverModels`, which may refresh OAuth or network
state, merely to perform a read-only check.

External native Remote attachment is not available in the current public
Desktop contract. Therefore legacy external Apply, rollback and restart cannot
use Web `session/list` or a missing port 3080 as proof of zero native Sessions.
Those operations fail closed in native mode. Use the existing native updater's
live impact assessment and exact interruption acknowledgement, followed by
interactive installer/UAC handling and post-restart evidence.
