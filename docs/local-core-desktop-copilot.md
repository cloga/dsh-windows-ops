# Local DSH Core, Desktop, and direct GitHub Copilot

## Authoritative baseline

[`deployments/windows-copilot.lock.json`](../deployments/windows-copilot.lock.json)
is the machine-readable deployment contract.

| Component | Locked identity |
|---|---|
| Desktop | official `0.10.2`, commit `2bb8f6b8e75c7e6e61b9bf5da7abbe53f9e93c63` |
| Controlled CLI | `@deepseek-ai/dsh@0.1.1-rc.2`, fork commit `a772dbbde82780bff2b9394427e9f0a24cafa1d5`, maintenance branch `cloga-pi-ai-model-api` |
| Desktop runtime | either the controlled fork above or Desktop 0.10.2's managed wrapper `deepseek-harness-pkg@0.1.2-alpha.4` containing inner `@deepseek-ai/dsh@0.1.2-rc.1` under `%APPDATA%\io.github.hairyf.deepseek-harness-desktop\dependencies\dsh`; the inner package contains 10 files with tree SHA-256 `4f5b21b9a7f0aee7908e8ebf915903f39cb85b755d6cb2ef200fc0afd6d602ea` |
| Copilot plugin | `dsh-github-copilot@0.3.0-cloga.15`, source commit `4e09519f40430b021a06871bf7ed7313bb9a292f`, merge commit `473b8aa174eb47a323b026c098b73bf7d716772c`, PR #50 |
| Plugin artifact | Immutable Release [`dsh-github-copilot-0.3.0-cloga.15.tgz`](https://github.com/cloga/dsh-github-copilot/releases/download/v0.3.0-cloga.15/dsh-github-copilot-0.3.0-cloga.15.tgz), SHA-256 `7486d2c062c7fcdd5ee36505ff9320eaec634497c1ea2481b335ea67e85a25b1`; verify with the same Release's [`SHA256SUMS`](https://github.com/cloga/dsh-github-copilot/releases/download/v0.3.0-cloga.15/SHA256SUMS) |
| Desktop artifact | [`Deepseek.Harness.Desktop_0.10.2_x64-setup.exe`](https://github.com/dsh-tauri-desk/deepseek-harness-desktop/releases/download/v0.10.2/Deepseek.Harness.Desktop_0.10.2_x64-setup.exe), SHA-256 `54d4c4a5718e5b1bb1276c256dbea8dccac6c36835f195f98b711b850e6488fa` |
| Desktop internal plugins | the seven official Profile `0.6.7` links plus the non-bundled panel placeholder into `resources\node_modules` |

Do not independently upgrade one component. Update the lock, fixtures, tests,
catalog, and this guide together after a new baseline is verified. The source
commit is the reviewed PR head; the lock separately records the externally
reviewed merge/tag target and immutable Release evidence. Apply validates the
source checkout plus the tarball hash and packaged metadata, then installs only
the locked Release bytes. Repository review—not the Apply command—attests the
merge/tag relationship and Release immutability.

## What “all-in-one” means

`dsh-github-copilot` is one DSH plugin that composes existing DSH services. It
reuses built-in `@deepseek-ai/dsh-llm-pi-ai` and pi-ai for:

- GitHub OAuth/device authorization;
- account-available Copilot model discovery;
- the reference-free `llm-pi-ai.providers.github-copilot` route;
- credential record `llm-pi-ai/github-copilot`;
- serialized token refresh and direct Copilot model transport.

At the Core credential-adapter boundary, `llm-pi-ai` rebuilds every provider's
OAuth grant as detached strict JSON. Undefined object members are omitted,
undefined array entries become `null`, and cyclic or non-JSON values are
rejected without exposing their values. JSON extension fields remain intact
because each provider owns its grant schema.

The controlled rc.2 Core also accepts a supported `api` on each model entry.
Model-level protocol wins over the route default and installed catalog, so one
reference-free Copilot route can safely contain both Responses and Chat
Completions models without connection fields on the route.

The plugin adds the authorization UI and direct provider-hosted search. Its
built client entry hands the plugin id, injected `require`, and materialized
exports to Desktop's `window.__ModuleLoader__.load` contract. Client Remote
calls use strict Zod result codecs so malformed authorization views fail closed.
When the shared `llm-pi-ai/github-copilot` grant is valid, activation reconciles
an absent, empty, or stale account model list without waiting for another OAuth
completion. A missing profile is created without connection references. For an
existing profile, the plugin changes only `providers.github-copilot.models` and
`providers.github-copilot.compat.supportsStrictMode`; it deliberately preserves
unowned fields. The Windows migration/bootstrap layer removes reviewed legacy
`baseURL` and `apiKeyEnv` references so the locked deployed route remains
reference-free. Every account-available model retains its installed `id` and
`api`, including mixed Responses and Chat Completions protocols.

The plugin removes top-level `sandbox_permissions` and `justification` only from
tool schemas assembled for `github-copilot`; every other provider retains DSH's
native escalation surface. Inline hosted search supports Responses and
Anthropic Messages, while `github-copilot-hosted` through `ctx.web` is
Responses-only. Capability probing is fail-closed by default; `probe: false`
explicitly bypasses only capability proof, not route, account, protocol,
endpoint, or authentication checks. Requests go directly to validated
GitHub-hosted or signed-in Enterprise Copilot endpoints.

Before storage or reuse, the Host rebuilds Copilot OAuth grants from validated
provider-owned fields as a fresh plain JSON object; unrelated extension fields
are discarded and malformed owned fields fail without exposing their values.
It does not embed or launch a gateway. The active baseline has no local gateway
URL, port 7777 listener, placeholder API key, pasted GitHub token, or separate
search-provider package.

The fourteen required plugin capabilities are copied exactly from its exported
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

The plugin has runtime dependencies on `@deepseek-ai/dsh-authorization` across
the supported `0.1.1-rc.2` and `0.1.2-rc.1` ranges and on `zod@^4.4.3` for
strict client Remote result validation. It bootstraps the authorization service
before integration activation on rc.2 and reuses the existing rc.1 service
without duplicate registration. ACP subagents remain separate; see
[`copilot-acp-subagent.md`](copilot-acp-subagent.md).

## Check first

The installer is read-only unless `-Apply` is explicit:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-windows-copilot.ps1
```

To preflight the exact source metadata and downloaded Release bytes without
applying them, supply both paths in the same default check mode:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\install-windows-copilot.ps1 `
  -CopilotIntegrationSourceRoot C:\src\dsh-github-copilot `
  -CopilotIntegrationArtifactPath C:\artifacts\dsh-github-copilot-0.3.0-cloga.15.tgz
```

Check mode validates the lock, Desktop, the controlled Core receipt and
installed-file attestation, official Desktop plugin links, the direct plugin
payload, composed configuration, credential-record metadata, the reference-free
Copilot route, complete per-model `{id, api}` entries with mixed protocol
coverage, and Desktop listener ownership. The running Desktop backend must select
either the exact receipted fork entrypoint or Desktop 0.10.2's exact managed
official `0.1.2-rc.1` entrypoint. The latter is accepted only at the locked
AppData dependency root with the exact alpha.4 wrapper, rc.1 inner package, file count, and tree hash; an absent runtime,
unknown version, unrelated bundled Core, or legacy gateway fails closed.

For both `web` and `headless`, check mode compares the Copilot dependency in
`package.json`, the matching `pnpm-lock.yaml` importer and tarball, the installed
package manifest, exported deployment baseline, and artifact SHA-256. A mismatch
is reported as `profile-manifest-lock-installed-drift`; check mode never repairs
it. Regenerate both locks with the controlled CLI before accepting an upgrade.
A missing `llm-pi-ai/github-copilot` grant is reported as
`sign-in-required`. Credential payloads are never included in output.

## Apply the locked Desktop, Core, and plugin

Use the exact source checkouts, locked Desktop installer, and immutable Copilot
Release tarball. The plugin checkout must be at source commit
`4e09519f40430b021a06871bf7ed7313bb9a292f`; it supplies independently reviewed
source metadata, while the installed bytes come from the release artifact whose
name and SHA-256 are locked above.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\install-windows-copilot.ps1 `
  -Apply `
  -HarnessSourceRoot C:\src\deepseek-harness `
  -CopilotIntegrationSourceRoot C:\src\dsh-github-copilot `
  -CopilotIntegrationArtifactPath C:\artifacts\dsh-github-copilot-0.3.0-cloga.15.tgz `
  -DesktopArtifactPath C:\artifacts\Deepseek.Harness.Desktop_0.10.2_x64-setup.exe `
  -CoreInstallPrefix C:\.tools\dsh-cloga `
  -CoreInstallTimeoutSeconds 900 `
  -BackupRoot C:\dsh-ops-backups
```

Apply builds and installs the receipted controlled CLI, verifies commit
`a772dbbd` and the three installed executable hashes, independently validates
the Copilot source checkout, verifies the immutable Release tarball hash and
packaged metadata, installs the reviewed loader packages, preserves the seven
official Desktop Profile links plus the non-bundled panel placeholder,
physically materializes only the Copilot plugin, and activates the local CLI
through `DSH_CLI_PATH`. It never substitutes a locally repacked plugin archive
for the locked Release bytes.

Desktop 0.10.2 may nevertheless use its own managed official `0.1.2-rc.1`
runtime; restart acceptance attests that selector from the Desktop process tree
and locked on-disk package metadata rather than requiring Desktop to honor
`DSH_CLI_PATH`.
`-CoreInstallTimeoutSeconds` bounds Core's internal package installation and
defaults to 900 seconds; it is separate from the 90-second Desktop/runtime
`-TimeoutSeconds` control.

`-RestartDesktop` is fail-closed: it queries the live `session/list` API before
stopping any process. Running Sessions block the restart unless the user has
directly accepted the listed interruptions and the command includes
`-AcknowledgeLiveSessionIds <exact listed IDs>`. Stale, missing, or extra IDs block the restart. Dry-run mode reports `would-block-live-sessions`
without stopping anything; an unavailable or malformed session response also
blocks a restart while Desktop is running.
It does not install, start, stop, or verify a gateway. `-GatewayArtifactPath`
is a retired compatibility parameter and is never an apply requirement.
`-GatewayInstallRoot` is migration-only: if supplied, apply recognizes only
the exact reviewed legacy binary, backs it up, and removes it. An unknown
binary fails closed.

## Bootstrap and sign in

The historical script name remains as a compatibility wrapper:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\enable-copilot-search-vision.ps1 `
  -CopilotIntegrationPackage C:\artifacts\dsh-github-copilot-0.3.0-cloga.15.tgz
```

The package argument may be the exact locked GitHub Release URL or a local copy
whose SHA-256 matches the lock; npm is not a distribution channel. The wrapper
installs the plugin in the `web` and `headless` profiles, configures only the
plugin and `github-copilot-hosted` search selection, removes reviewed legacy
route references, and reports credential metadata. It does not write provider
routes, model lists, base URLs, or API-key references. Despite its historical
file name, it does not install `dsh-vision-any` or another visual fallback.
Image-capable models receive uploaded attachments through DSH's native image
channel, and Agents use the built-in `read_image` tool to open workspace image
files. Text-only models must be switched to an image-capable route rather than
silently delegating the image to a second provider.

The wrapper reads `deployments\windows-copilot.lock.json` by default and
requires the exact locked Desktop executable. It always uses the receipted
controlled CLI for plugin commands, while the active Desktop backend may use
either the controlled selector or the exact lock-attested Desktop-managed
`0.1.2-rc.1` selector. Override `-DeploymentLockPath` or
`-DesktopExecutablePath` only for an equivalent reviewed deployment.

The shell does not automate the interactive device flow:

- on `0.1.1-rc.2`, open **Settings → GitHub Copilot**;
- on `0.1.2-rc.1`, open **Models**, then the **GitHub Copilot** provider
  card.

Complete the displayed GitHub device flow. DSH writes the shared grant and an
account-filtered, reference-free route whose model entries retain their exact
installed `api`. If the grant already exists but Desktop saved an empty or
incomplete route, plugin activation self-heals the route without another device
flow. After sign-in, an optional model may be selected only if it already
appears in the complete mixed-protocol route:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\enable-copilot-search-vision.ps1 `
  -Action Verify `
  -Model '<account-available-model-id>'
```

## Optional Web-profile overlays

The current reviewed machine overlay may include `dsh-playwright-host@0.1.2`
from immutable commit `2cf6edfd52b5a70b3f6af7b1f502c58718a6f5ac` and
`dsh-cron@0.4.1` from tag `v0.4.1` (commit
`5f99313e110932195821d924259b2836947271f3`). They are reported as known
optional additions and are not required by the Windows Copilot baseline. See
[`computer-use.md`](plugins/computer-use.md) and
[`scheduling.md`](plugins/scheduling.md). Unknown additions remain visible and
must not be silently promoted into `requiredBundles`.
## Legacy migration procedure

The lock retains legacy facts only under `migration.legacyGateway`; they are
not active components or acceptance criteria.

1. Run the default installer check and save its JSON. Confirm any reported
   binary, listener, routes, or credential reference matches the reviewed
   migration contract.
2. Before closing Desktop, query live `session/list`. Running Sessions require
   direct user acknowledgement of the exact IDs before any interruption; an
   unavailable or malformed response blocks the stop. If the legacy gateway
   process or scheduled task is still running, stop or disable it manually only
   after that preflight. Repository scripts intentionally do not terminate it.
3. Preserve the installer backup root. For a known legacy install directory,
   pass its parent as `-GatewayInstallRoot`; apply backs up and removes only
   the exact reviewed binary.
4. Run locked `-Apply` with the Core/plugin source checkouts, immutable Copilot
   Release tarball, and Desktop artifact shown above. Do not pass a gateway
   artifact or model catalog.
5. Run the compatibility bootstrap with the currently locked tarball. It
   removes superseded `.1` through `.12` or search-plugin dependencies,
   backed-up local route blocks, and the legacy credential reference; it never
   deletes the new DSH grant.
6. When the result is `sign-in-required`, complete sign-in from the correct
   Desktop UI for the installed DSH version.
7. Optionally run wrapper `-Action Verify -Model <id>` to select an
   account-available model. Never paste a token into settings.
8. Run the default installer check again. Success requires the exact lock-selected plugin,
   credential grant metadata, reference-free route, direct search composition,
   official internal-plugin links, receipted controlled CLI, an exact supported
   Desktop runtime selector, and only the Desktop loopback listener contract.
9. Perform a user-initiated model and hosted-search smoke in Desktop. No local
   endpoint probe is part of the direct contract.

Every mutation is backed up before route, credential-reference, profile, or
binary cleanup. Use the returned operation ID for rollback:

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

## Verification

Repository-only checks do not touch the active deployment:

```powershell
Invoke-Pester -Path tests
node tools\validate-repository-content.mjs
node tools\validate-plugin-catalog.mjs
node --test tests\plugin-catalog.test.mjs tests\host-playwright-bundle.test.mjs tests\repository-content.test.mjs
```

Machine-state checks below remain read-only; the browser smoke uses an isolated
browser profile and the existing DSH URL:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\install-windows-copilot.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\dsh-replay.ps1 -Action SelfCheck
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\dsh-replay.ps1 -Action Preflight
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\dsh-replay.ps1 -Action Apply -DryRun
python tools\dsh-web-smoke.py --expect-text "New Session" `
  --fail-on-console-error --fail-on-request-failure --fail-on-http-error
```

The check command may report drift or `sign-in-required` on an un-migrated
machine. That is expected fail-closed behavior, not a success-shaped fallback.
Packaged current/fresh-Session Tool Schema evidence requires a separately
authorized Host restart; repository-only verification does not claim to produce
new runtime evidence.

## Historical standalone runtime-schema diagnostic

`tools\test-dsh-runtime-schema.ps1` is a development-only probe for the reviewed
`0.1.2-alpha.1` / PR #10 schema fix. It follows the first command returned by
`Get-Command dsh -All`, validates the exact package and compiled symbols, and
issues a short-lived challenge that requires a newly started DSH process and
session before behavior evidence can be accepted.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\test-dsh-runtime-schema.ps1
```

The probe detects stale Pwsh schemas and returns `STALE_RUNTIME_SCHEMA` instead
of a success-shaped result. Its positive session fields remain user-supplied,
so it cannot attest or gate the current locked controlled `0.1.1-rc.2` or
Desktop-managed `0.1.2-rc.1` deployment health.
The current rc.1 acceptance path is separate: the locked `.14` Copilot
package removes `sandbox_permissions` and `justification` only from
`github-copilot` assemblies, preserves other providers, requires a Host restart,
and records both packaged current-Session and fresh-Session success markers in
`acceptance.copilotToolSchema`. The historical alpha.1 probe must not be used as
proof of that provider-scoped behavior.
