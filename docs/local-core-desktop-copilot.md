# Local DSH Core, Desktop, and direct GitHub Copilot

## Authoritative baseline

[`deployments/windows-copilot.lock.json`](../deployments/windows-copilot.lock.json)
is the machine-readable deployment contract.

| Component | Locked identity |
|---|---|
| Desktop | official `0.9.2`, commit `c7c5a247961b1ca2d7389026ad7194ac108e5437` |
| Core | `@deepseek-ai/dsh@0.1.1-rc.2`, fork commit `ef6b355136af7e9d7f4ed603a5422137c89d44e0` |
| Copilot plugin | `dsh-github-copilot@0.3.0-cloga.3`, source commit `d6da9f4a0b64cdf18ab3e25581d84b55b8421076`, merge commit `da3ee5657a54874eefe35e4133a3d55663c2de36`, PR #21 |
| Plugin artifact | `dsh-github-copilot-0.3.0-cloga.3.tgz`, SHA-256 `d7e9c262e2a53cef7f46a7d37b93f9d11bef7ea398fac143c9f588deb5011f1c` |
| Desktop internal plugins | the five official `0.4.9` links |

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

The plugin adds the authorization UI and direct provider-hosted search. It does
not embed or launch a gateway. The active baseline has no local gateway URL,
port 7777 listener, placeholder API key, pasted GitHub token, or separate
search-provider package.

The eight required plugin capabilities are copied exactly from its exported
`deployment-baseline.json`:

1. `authorization-service-bootstrap`
2. `models-provider-card-authorization`
3. `reference-free-route-mutation`
4. `shared-copilot-credential-refresh`
5. `direct-provider-hosted-search`
6. `traditional-search-bridge`
7. `dsh-supported-baselines-fail-loud-guard`
8. `dsh-rc2-models-settings-fallback`

The plugin has a runtime dependency on `@deepseek-ai/dsh-authorization` across
the supported `0.1.1-rc.2` and `0.1.2-alpha.3` ranges. It bootstraps that
service before integration activation on rc.2 and reuses the existing alpha.3
service without duplicate registration. ACP subagents remain separate; see
[`copilot-acp-subagent.md`](copilot-acp-subagent.md).

## Check first

The installer is read-only unless `-Apply` is explicit:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-windows-copilot.ps1
```

Check mode validates the lock, Desktop, the Core receipt and installed-file
attestation, official Desktop plugin links, the direct plugin payload, composed
configuration, credential-record metadata, the reference-free Copilot route,
and Desktop listener ownership. It never treats a legacy gateway as success.

A missing `llm-pi-ai/github-copilot` grant is reported as
`sign-in-required`. Credential payloads are never included in output.

## Apply the locked Desktop, Core, and plugin

Use exact source checkouts and the locked Desktop artifact. The plugin checkout
must be at source commit `d6da9f4a0b64cdf18ab3e25581d84b55b8421076`.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\install-windows-copilot.ps1 `
  -Apply `
  -HarnessSourceRoot C:\src\deepseek-harness `
  -CopilotIntegrationSourceRoot C:\src\dsh-github-copilot `
  -DesktopArtifactPath C:\artifacts\Deepseek.Harness.Desktop_0.9.2_x64-setup.exe `
  -CoreInstallPrefix C:\.tools\dsh-cloga `
  -BackupRoot C:\dsh-ops-backups
```

Apply builds and installs the receipted local Core, verifies commit
`ef6b3551` and the three installed executable hashes, builds and attests the
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
  -CopilotIntegrationPackage C:\artifacts\dsh-github-copilot-0.3.0-cloga.3.tgz
```

The package argument may also be a registry spec. The wrapper installs the
plugin in the `web` and `headless` profiles, configures only the plugin and
`github-copilot-hosted` search selection, removes reviewed legacy route
references, and reports credential metadata. It does not write provider
routes, model lists, base URLs, or API-key references.

The shell does not automate the interactive device flow:

- on `0.1.1-rc.2`, open **Settings → GitHub Copilot**;
- on `0.1.2-alpha.3`, open **Models**, then the **GitHub Copilot** provider
  card.

Complete the displayed GitHub device flow. DSH writes the shared grant and an
account-filtered, reference-free route. After sign-in, an optional model may be
selected only if it already appears in that route:

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
5. Run the compatibility bootstrap with the locked `.3` tarball. It removes
   the old `.1`, `.2`, or search-plugin dependency, backed-up local route
   blocks, and the legacy credential reference; it never deletes the new DSH
   grant.
6. When the result is `sign-in-required`, complete sign-in from the correct
   Desktop UI for the installed DSH version.
7. Optionally run wrapper `-Action Verify -Model <id>` to select an
   account-available model. Never paste a token into settings.
8. Run the default installer check again. Success requires the `.3` plugin,
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
