# Local DSH Core, Desktop, and direct GitHub Copilot

## Authoritative baseline

[`deployments/windows-copilot.lock.json`](../deployments/windows-copilot.lock.json)
is the machine-readable deployment contract.

| Component | Locked identity |
|---|---|
| Desktop | official `0.10.2`, commit `2bb8f6b8e75c7e6e61b9bf5da7abbe53f9e93c63` |
| Core | `@deepseek-ai/dsh@0.1.1-rc.2`, fork commit `a772dbbde82780bff2b9394427e9f0a24cafa1d5`, maintenance branch `cloga-pi-ai-model-api` |
| Copilot plugin | `dsh-github-copilot@0.3.0-cloga.8`, source commit `94d921dc7bad4d5035c27ed9543d638694cb7391`, merge commit `eae8b56715e197d5e206a7852bfaa418bbc70dc5`, PR #33 |
| Plugin artifact | [`dsh-github-copilot-0.3.0-cloga.8.tgz`](https://github.com/cloga/dsh-github-copilot/releases/download/v0.3.0-cloga.8/dsh-github-copilot-0.3.0-cloga.8.tgz), SHA-256 `b37e7621628e10d2a33f4cb7e4692c4fcd1348c7d7e8eb92467f250bbaa4ae32` |
| Desktop artifact | [`Deepseek.Harness.Desktop_0.10.2_x64-setup.exe`](https://github.com/dsh-tauri-desk/deepseek-harness-desktop/releases/download/v0.10.2/Deepseek.Harness.Desktop_0.10.2_x64-setup.exe), SHA-256 `54d4c4a5718e5b1bb1276c256dbea8dccac6c36835f195f98b711b850e6488fa` |
| Desktop internal plugins | the five official `0.6.7` links into `resources\node_modules` |

Do not independently upgrade one component. Update the lock, fixtures, tests,
catalog, and this guide together after a new baseline is verified.

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
When the shared `llm-pi-ai/github-copilot` grant is already valid, activation
also repairs an absent, empty, or incomplete provider route instead of waiting
for a new OAuth completion. The repaired route remains reference-free and every
account-available model retains its installed `id` and `api`, including mixed
Responses and Chat Completions protocols.
Before storage or reuse, the Host rebuilds Copilot OAuth grants from validated
provider-owned fields as a fresh plain JSON object; unrelated extension fields
are discarded and malformed owned fields fail without exposing their values.
It does not embed or launch a gateway. The active baseline has no local gateway
URL, port 7777 listener, placeholder API key, pasted GitHub token, or separate
search-provider package.

The thirteen required plugin capabilities are copied exactly from its exported
`deployment-baseline.json`:

1. `client-module-loader-handoff`
2. `strict-remote-result-codecs`
3. `authorization-service-bootstrap`
4. `models-provider-card-authorization`
5. `reference-free-route-mutation`
6. `per-model-api-route-materialization`
7. `existing-grant-route-self-healing`
8. `shared-copilot-credential-refresh`
9. `strict-json-oauth-grant-normalization`
10. `direct-provider-hosted-search`
11. `traditional-search-bridge`
12. `dsh-supported-baselines-fail-loud-guard`
13. `dsh-rc2-models-settings-fallback`

The plugin has runtime dependencies on `@deepseek-ai/dsh-authorization` across
the supported `0.1.1-rc.2` and `0.1.2-alpha.4` ranges and on `zod@^4.4.3` for
strict client Remote result validation. It bootstraps the authorization service
before integration activation on rc.2 and reuses the existing alpha.4 service
without duplicate registration. ACP subagents remain separate; see
[`copilot-acp-subagent.md`](copilot-acp-subagent.md).

## Check first

The installer is read-only unless `-Apply` is explicit:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-windows-copilot.ps1
```

Check mode validates the lock, Desktop, the Core receipt and installed-file
attestation, official Desktop plugin links, the direct plugin payload, composed
configuration, credential-record metadata, the reference-free Copilot route,
complete per-model `{id, api}` entries with mixed protocol coverage, and Desktop
listener ownership. It never treats a legacy gateway as success.

A missing `llm-pi-ai/github-copilot` grant is reported as
`sign-in-required`. Credential payloads are never included in output.

## Apply the locked Desktop, Core, and plugin

Use exact source checkouts and the locked Desktop artifact. The plugin checkout
must be at source commit `94d921dc7bad4d5035c27ed9543d638694cb7391`.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\install-windows-copilot.ps1 `
  -Apply `
  -HarnessSourceRoot C:\src\deepseek-harness `
  -CopilotIntegrationSourceRoot C:\src\dsh-github-copilot `
  -DesktopArtifactPath C:\artifacts\Deepseek.Harness.Desktop_0.10.2_x64-setup.exe `
  -CoreInstallPrefix C:\.tools\dsh-cloga `
  -BackupRoot C:\dsh-ops-backups
```

Apply builds and installs the receipted local Core, verifies commit
`a772dbbd` and the three installed executable hashes, builds and attests the
Copilot plugin, installs the reviewed loader packages, preserves the five
official Desktop internal-plugin junctions, physically materializes only the
Copilot plugin, and activates the local Core through `DSH_CLI_PATH`.

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
  -CopilotIntegrationPackage C:\artifacts\dsh-github-copilot-0.3.0-cloga.8.tgz
```

The package argument may also be a registry spec. The wrapper installs the
plugin in the `web` and `headless` profiles, configures only the plugin and
`github-copilot-hosted` search selection, removes reviewed legacy route
references, and reports credential metadata. It does not write provider
routes, model lists, base URLs, or API-key references.

The shell does not automate the interactive device flow:

- on `0.1.1-rc.2`, open **Settings → GitHub Copilot**;
- on `0.1.2-alpha.4`, open **Models**, then the **GitHub Copilot** provider
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

## Legacy migration procedure

The lock retains legacy facts only under `migration.legacyGateway`; they are
not active components or acceptance criteria.

1. Run the default installer check and save its JSON. Confirm any reported
   binary, listener, routes, or credential reference matches the reviewed
   migration contract.
2. Close Desktop. If the legacy gateway process or scheduled task is still
   running, stop or disable it manually. The repository scripts intentionally
   do not terminate services.
3. Preserve the installer backup root. For a known legacy install directory,
   pass its parent as `-GatewayInstallRoot`; apply backs up and removes only
   the exact reviewed binary.
4. Run locked `-Apply` with the Core/plugin source checkouts and Desktop
   artifact shown above. Do not pass a gateway artifact or model catalog.
5. Run the compatibility bootstrap with the locked `.8` tarball. It removes
   the old `.1` through `.7` or search-plugin dependency, backed-up local route
   blocks, and the legacy credential reference; it never deletes the new DSH
   grant.
6. When the result is `sign-in-required`, complete sign-in from the correct
   Desktop UI for the installed DSH version.
7. Optionally run wrapper `-Action Verify -Model <id>` to select an
   account-available model. Never paste a token into settings.
8. Run the default installer check again. Success requires the `.8` plugin,
   credential grant metadata, reference-free route, direct search composition,
   official internal-plugin links, receipted Core, and only the Desktop
   loopback listener contract.
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

```powershell
Invoke-Pester -Path `
  tests\WindowsCopilotInstaller.Tests.ps1,`
  tests\DshCopilotBootstrap.Tests.ps1

node --test tests\plugin-catalog.test.mjs
node tools\validate-plugin-catalog.mjs
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\install-windows-copilot.ps1
```

The check command may report drift or `sign-in-required` on an un-migrated
machine. That is expected fail-closed behavior, not a success-shaped fallback.
