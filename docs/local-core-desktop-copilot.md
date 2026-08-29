# Local DSH core, Desktop, and GitHub Copilot practice

This is the maintained deployment baseline for testing
[`cloga/deepseek-harness`](https://github.com/cloga/deepseek-harness) with DSH
Desktop and GitHub Copilot-backed models on Windows.

## Authoritative locked workflow

The executable contract is
[`deployments/windows-copilot.lock.json`](../deployments/windows-copilot.lock.json),
not the command fragments below. Future agents must run the orchestrator in
default check mode first:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\install-windows-copilot.ps1
```

Check mode validates the lock and prints the complete ordered plan without
changing the machine. `-Apply` additionally requires exact core/provider
checkouts, the two release artifacts, and a captured `/v1/models` response.
The installer verifies release SHA-256 values and source commits, builds with
the package managers recorded by each source repository, installs the Core
through its receipt-producing `release:install-local` script, then installs the
three loader dependencies and provider tarball in one global npm transaction.
It preserves and attests Desktop 0.9.2's five official 0.4.9 internal-plugin
links, updates the web profile and routes, and physically materializes only the
reviewed hosted-search provider.
Apply migrates only the prior locked physical `dsh-tauri@0.2.0`,
`dsh-tauri-ui@0.1.0`, and `dsh-tauri-worktree@0.1.0` profile state. It backs
up and removes those exact dependencies before `pnpm install`; any other
physical internal-plugin state fails before Core or global installation.

Every touched settings/profile file and plugin directory is copied under
`%LOCALAPPDATA%\dsh-windows-ops\deployment-backups` before replacement. That
root is rejected if it resolves under `$DSH_HOME\sessions`. The installer does
not persist credentials, user-specific paths, execution-policy changes,
`NODE_OPTIONS`, or any other global environment policy.

Use a catalog captured from the authenticated loopback gateway:

```powershell
Invoke-RestMethod http://127.0.0.1:7777/v1/models |
  ConvertTo-Json -Depth 20 |
  Set-Content $env:TEMP\copilot-models.json -Encoding UTF8

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\install-windows-copilot.ps1 -Apply `
  -HarnessSourceRoot C:\Path\To\deepseek-harness `
  -CoreInstallPrefix C:\.tools\dsh-cloga `
  -ProviderSourceRoot C:\Path\To\dsh-web-search-provider `
  -DesktopArtifactPath C:\Path\To\Deepseek.Harness.Desktop_0.9.2_x64-setup.exe `
  -GatewayArtifactPath C:\Path\To\copilot2api-windows-amd64.exe `
  -ModelCatalogPath $env:TEMP\copilot-models.json
```

The catalog's `supported_endpoints` metadata assigns models independently to
the `openai-responses` and `openai-completions` routes. The installer never
creates the reserved `github-copilot` route ID. Existing unsupported YAML
shapes or an existing forbidden route fail closed before replacement.

The remaining sections explain the locked workflow and recovery rationale.
Do not execute them as a substitute for the manifest and orchestrator.

## Supported architecture

DSH Desktop 0.9.2 supports a local core, but it does not accept a Harness fork
URL in the UI. The supported separation is:

```text
Official DSH Desktop shell
  -> local @deepseek-ai/dsh CLI from cloga/deepseek-harness
     -> OpenAI-compatible provider configuration
        -> copilot2api
           -> GitHub Copilot models
  -> profile-scoped DSH plugins
```

Desktop prefers a detected local CLI over its packaged core. `DSH_CLI_PATH`
can select an exact CLI when PATH contains multiple installations.

The packaged-core download source remains
`dsh-tauri-desk/deepseek-harness-pkg`. Changing that source requires a
separately maintained package-release fork and a Desktop code change; it is not
required for normal fork development.

## Validated 2026-08-28 baseline

The installation described here was verified with:

| Component | Version or state |
|---|---|
| DSH Desktop | `0.9.2`, commit `c7c5a247961b1ca2d7389026ad7194ac108e5437`, setup SHA-256 `F7055155FFDAF1671761D5BA85030009CF3207D4C9C46649C211C2217BB1C1C7` |
| Local `@deepseek-ai/dsh` | `0.1.1-rc.2` |
| `cloga/deepseek-harness` | PR #8, `bd520d6e47e0c9cc690bf6d7211512cb044fd095` |
| Node / npm / pnpm | `24.19.0` / `11.17.0` / `11.7.0` |
| `copilot2api` | `0.6.1`, loopback `127.0.0.1:7777` |
| Desktop profile plugins | Official internal `dsh-tauri`, panel, panel-extension, UI, and worktree links, all `0.4.9` |
| Hosted-search provider | `cloga/dsh-web-search-provider` PR #4, `0.2.3-cloga.3`, commit `e47390c789c4939eaa6660f52e0f3d2e37d554aa`, tarball SHA-256 `5EC9B9A782712E3E05BF8E58583AA86370CED383AB389DF11CDEEBF6AAFEA647` |

Record exact versions and the fork commit for each deployment. Treat this table as
evidence for this installation, not as an unbounded compatibility claim.

The Core pin is PR #8 commit
`bd520d6e47e0c9cc690bf6d7211512cb044fd095`. It descends from the reviewed
receipt-installer commit `d931e5482181f41de0b96a9453de5f2112a4fe47`,
keeps package version `0.1.1-rc.2`, and adds the sandbox same/narrower no-op
fix while retaining `release:install-local` and its Desktop-compatible receipt.

## Build and install the fork core

Use the Node and pnpm versions declared by the Harness repository. From a clean
checkout of `cloga/deepseek-harness`:

```powershell
$expectedCommit = 'bd520d6e47e0c9cc690bf6d7211512cb044fd095'
git switch --detach $expectedCommit
if ((git rev-parse HEAD) -ne $expectedCommit) {
  throw 'Harness checkout does not match the reviewed commit.'
}

corepack enable
pnpm install --frozen-lockfile
pnpm run build:official
pnpm run release:pack --family dsh --out dist/npm
pnpm run release:pack --family vendor --out dist/npm-vendor
pnpm --dir native/landlock-run/packages/entry pack --pack-destination "$PWD/dist/npm-landlock"

$commit = git rev-parse HEAD
$version = node -p "require('./apps/cli/package.json').version"
pnpm run release:install-local -- `
  --from dist/npm `
  --from dist/npm-vendor `
  --from dist/npm-landlock `
  --prefix C:\.tools\dsh-cloga `
  --expect-commit $commit `
  --expect-version $version
```

The Core installer verifies the complete local runtime closure and writes the
base `<prefix>\dsh-local-install.json`. The locked Windows deployment Apply then
augments that receipt with SHA-256 values for the prefix-root shim, npm shim,
and exact `@deepseek-ai/dsh\lib\bin.js` entrypoint. A base receipt without this
installed-file attestation is reported as `installed-bytes-unattested`; changing
any sealed file is reported as `installed-bytes-mismatch`. The receipt also
records schema version, fork repository URL, full commit SHA, npm package
identity/version, the Desktop-compatible prefix-root CLI, release-manifest
SHA-256, and each installed tarball hash. The canonical CLI remains
`<prefix>\node_modules\.bin\dsh.cmd`. The npm package keeps its official
`@deepseek-ai/dsh` name and upstream package metadata; fork provenance comes
only from this receipt.

Before any build or install mutation, Apply rejects a `CoreInstallPrefix` that
equals, contains, or is contained by DSH home/profile, the backup root, either
source checkout, the global npm root or prefix, either locked artifact path, or
the gateway install root. It also rejects any existing reparse-point ancestor
of the Core prefix or any protected path, so junction aliases cannot bypass the
comparison. During a later check, supplying `CoreInstallPrefix` without
`DshCliPath` selects `<CoreInstallPrefix>\dsh.cmd` ahead of environment or
global CLI discovery.

For Desktop compatibility, the installer creates the attested prefix-root
forwarding shim:

```powershell
Set-Content C:\.tools\dsh-cloga\dsh.cmd -Encoding ASCII -Value @'
@echo off
call "%~dp0node_modules\.bin\dsh.cmd" %*
'@
```

## Install and select DSH Desktop

1. Install the official Desktop release for Windows.
2. If only one `dsh` is installed, start Desktop and select `local` on the
   **Core** page.
3. If multiple CLIs may resolve, set `DSH_CLI_PATH` to the verified executable
   before launching Desktop:

   ```powershell
   $dsh = 'C:\.tools\dsh-cloga\dsh.cmd'
   [Environment]::SetEnvironmentVariable('DSH_CLI_PATH', $dsh, 'User')
   ```

4. Restart Desktop and verify the selected core path and version.
5. Run the repository self-check:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\dsh-replay.ps1 `
     -Action SelfCheck -Config $env:LOCALAPPDATA\dsh-replay.json
   ```

   `-ExecutionPolicy Bypass` applies only to this PowerShell process; it does not
   weaken the saved user or machine policy. Copy and adapt the example replay
   configuration first because packaged Tauri paths vary by release.

Do **not** use Desktop's **Update local core** action while validating the fork.
That action installs `@deepseek-ai/dsh@latest` from npm and can replace the
fork build. Upgrade by packing and globally installing a new reviewed tarball.

## Enable GitHub Copilot models

GitHub Copilot authentication belongs to the gateway, not to Desktop or the DSH
core.

Keep two identities deliberately separate:

- Repository operations for this fork and operations repository use the approved
  personal/repository identity.
- Copilot device-flow authorization uses the account that owns the Copilot
  entitlement.

Never copy either credential into DSH settings, logs, fixtures, or documentation.

1. Start the approved `copilot2api` deployment and complete its GitHub
   authentication flow.
2. Verify its OpenAI-compatible endpoint and model catalog locally:

   ```powershell
   Invoke-RestMethod http://127.0.0.1:7777/v1/models
   ```

3. In DSH, configure OpenAI-compatible routes whose base URL targets the gateway,
   normally `http://127.0.0.1:7777/v1`.
4. Use a route ID such as `github-copilot-gateway`, not `github-copilot`.
   `pi-ai` reserves the latter for its built-in OAuth provider; reusing it for a
   local gateway can produce `Provider is not configured: github-copilot`.
5. Keep one wire protocol per route:
   - Responses models: `github-copilot-gateway` with `openai-responses`.
   - Chat-Completions-only models: a separate `github-copilot-chat` route with
     `openai-completions`.
6. A manually declared OpenAI-compatible route still requires an API-key entry at
   the `pi-ai` provider layer even when the loopback gateway does not validate it.
   Store an explicitly non-secret placeholder in the DSH credential store; do not
   put a real token or the placeholder in committed settings.
7. Refresh model discovery and select a model returned by `/v1/models`.
8. Install `dsh-web-search-provider` when Copilot-backed hosted search is
   required. The Harness core improvements do not inject the provider-native
   `web_search` wire; without this plugin, the agent-visible `web_search` tool
   can fall back to built-in `web-search-deepseek` and require
   `DEEPSEEK_API_KEY`.
9. Re-run `tools\dsh-replay.ps1 -Action SelfCheck` and confirm that service,
   model-catalog, and image-capability checks match the selected model.

Keep all GitHub and provider credentials in ignored local environment files or
the relevant platform credential store. Never copy them into DSH patches,
profiles committed to Git, fixtures, logs, or documentation.

## Install the hosted-search provider

Core and plugin improvements are complementary. The local Harness fork owns
generic provider metadata, readiness, and image-capability propagation.
`dsh-web-search-provider` owns endpoint probing, native `web_search` injection,
Responses SSE translation, replay normalization, grounded sandbox escalation,
and image bypass to the official attachment channel.

Use
[`cloga/dsh-web-search-provider` PR #4](https://github.com/cloga/dsh-web-search-provider/pull/4),
exact commit `e47390c789c4939eaa6660f52e0f3d2e37d554aa`. Its exported
`cloga.dsh-windows-copilot.web-search` baseline has exactly seven required
capabilities, including the traditional `copilot-hosted` Search bridge and
nonempty-only Responses/Anthropic reasoning.

Build with the package manager declared by the provider repository. On Windows,
run the cross-platform build stages directly if its `clean` script uses
`rm -rf`:

```powershell
npx --yes pnpm@11.3.0 install --frozen-lockfile
npx --yes pnpm@11.3.0 test
npx --yes pnpm@11.3.0 run typecheck

Remove-Item -LiteralPath .\lib -Recurse -Force -ErrorAction SilentlyContinue
npx --yes pnpm@11.3.0 exec tsc -p tsconfig.json
npx --yes pnpm@11.3.0 exec tsdown
npx --yes pnpm@11.3.0 pack --pack-destination .\dist
```

Install the reviewed tarball into the Desktop web profile, then add
`dsh-web-search-provider` to `dsh.profile.bundles` in
`$DSH_HOME\profiles\web\package.json`:

```powershell
dsh plugin --profile web add .\dist\dsh-web-search-provider-0.2.3-cloga.3.tgz --save-exact
```

pnpm 11 refuses dependency lifecycle scripts until each package is classified.
If installation reports `ERR_PNPM_IGNORED_BUILDS`, inspect the named packages
and add only reviewed entries to the profile's `pnpm-workspace.yaml`; never
apply a global allow:

```yaml
allowBuilds:
  '@google/genai': true
  protobufjs: true
```

The official 0.4.9 Tauri packages are Desktop-internal and are not available
from the configured npm registry. Keep their profile entries as exact links
under Desktop's `resources\internal-plugins`; the installer fails closed if a
link or version differs. Only `dsh-web-search-provider` is replaced with an
attested physical directory.

Validate search in both a new session and a session whose previous search
failed. The latter exercises replay safety: oversized item IDs and orphaned
function-call halves must be dropped or normalized before the next Responses
request. A successful reply must contain provider-native search evidence and
must not request `DEEPSEEK_API_KEY`.

The lock records this as an injectable smoke contract. Save a successful raw
Responses payload and validate it without exposing credentials:

```powershell
tools\install-windows-copilot.ps1 `
  -SearchSmokeResponsePath C:\Path\To\redacted-responses-result.json
```

If no response is supplied, check mode reports the smoke as manual rather than
claiming success.

## Recover missing loader dependencies

### Symptom chain

Desktop may time out on port `3080`, then reveal successive loader errors after
each retry:

```text
Cannot find package '@deepseek-ai/cordis-plugin-timer'
Cannot find package '@deepseek-ai/cordis-plugin-hmr'
```

HMR may then fail while obtaining Node's internal loader. It first attempts the
`--expose-internals` path and then the optional
`node-addon-require-builtin` bridge.

### Root cause

The packages must be resolvable from the real global `dsh-app-boot` /
`cordis-plugin-loader` location. Installing one optional package at a time with
npm is unsafe: a later global install can classify the previous package as
extraneous and remove it. This makes the failure appear to move between timer,
HMR, and the Node-internal bridge.

### Safe repair

Install the tested set together in one npm transaction:

```powershell
npm install --global `
  @deepseek-ai/cordis-plugin-hmr@1.0.16 `
  @deepseek-ai/cordis-plugin-timer@1.1.3 `
  node-addon-require-builtin@0.1.4
```

Do not set global `NODE_OPTIONS=--expose-internals` as a blanket workaround.
Verify all three imports from the actual global loader context before restarting.
Keep the versions together in upgrade records and reinstall them together after
any global npm operation that may prune optional packages.

```powershell
$loaderRoot = Join-Path $env:APPDATA `
  'npm\node_modules\@deepseek-ai\dsh-app-boot\node_modules\@deepseek-ai\cordis-plugin-loader'
Push-Location $loaderRoot
try {
  node --input-type=module -e @'
const packages = [
  '@deepseek-ai/cordis-plugin-hmr',
  '@deepseek-ai/cordis-plugin-timer',
  'node-addon-require-builtin',
];
await Promise.all(packages.map((id) => import(id)));
console.log('loader imports OK');
'@
  if ($LASTEXITCODE -ne 0) { throw 'Loader dependency import failed.' }
} finally {
  Pop-Location
}
```

The Desktop error page retains the previous failure. After repairing dependencies,
click **Retry** to start the backend again; merely reopening the window may leave
the old error state visible.

## Preserve Desktop internal plugins

Desktop 0.9.2 owns five internal plugins under
`resources\internal-plugins`. The locked installer validates their exact 0.4.9
manifests and profile junction targets before and after the provider package
operation. Missing links are recreated only to those verified official
directories; a link to any other target fails closed.

Run both checks after materializing:

```powershell
node tools\dsh-compat-check.mjs web --probe
node tools\dsh-compat-check.mjs headless --probe
```

The validated web profile loaded all three plugins; the validated headless
profile contained no external plugins.

## Acceptance matrix

Do not stop after `/v1/models` responds. Verify each layer independently:

| Check | Expected result |
|---|---|
| Desktop listener | Exact `127.0.0.1:3080` binding, owned by the receipted Node descendant; IPv6-only `::1` is insufficient |
| Active local Core | A Desktop Node descendant executes the sealed `lib\bin.js`, and that same PID owns port 3080 |
| Gateway listener | `127.0.0.1:7777`, not a public bind |
| Gateway task | Current-user logon task is running |
| Model endpoint | HTTP 200 and a non-empty catalog; validated run returned 35 models |
| Provider UI | Responses and Chat routes both report configured credentials |
| Text request | A prompt without the expected answer embedded returns the correct result |
| Vision request | A generated test image is identified correctly through the official image path |
| Compatibility | `web --probe` and `headless --probe` report no fatal imports |

The replay tool extracts models from JSON configuration and HTTP responses. For
`settings.yaml`, it reports profile/configuration state without exposing credentials.

## 2026-08-28 mixed-version drift guard

The default installer check recognizes the observed partial deployment as
`windows-copilot-drift-2026-08-28` instead of treating listener, loader, or
package-version markers as proof of health. The signature correlates all of the
following:

- the exact locked Desktop 0.9.2 shell mixed with a receipt-less older Core;
- the locked copilot2api artifact alongside a receipt-less local Core;
- an absolute profile dependency on the old
  `dsh-web-search-provider-0.2.2-all-fixes-bd40ffb.tgz`, installed provider
  version 0.2.2, and no exported `deployment-baseline.json`;
- the active `web-search-deepseek` entry and legacy
  `searchProvider: deepseek-official` marker, or a `web-search-provider` entry
  without the managed `github-copilot-gateway` route binding.

Desktop 0.9.2 was released on 2026-08-28 from commit
`c7c5a247961b1ca2d7389026ad7194ac108e5437`; its Windows setup asset reports
SHA-256 `f7055155ffdaf1671761d5ba85030009cf3207d4c9c46649c211c2217bb1c1c7`.
The reviewed baseline now preserves that shell and its internal plugins.
Incident remediation is `locked-repair-required`: reinstall the exact pinned
Core through its receipt producer, install and attest provider 0.2.3-cloga.3,
and compose `web` with `searchProvider: copilot-hosted` while disabling only
`web-search-deepseek`. Never synthesize a Core receipt from a version string.

When the gateway is not under the lock's default install directory, check mode
resolves the sole loopback listener on the locked port and hashes that process
image. Missing, public, ambiguous, or hash-mismatched listeners remain invalid.
For the hosted-search provider, check mode hashes `lib\index.js` and compares it
directly with the same raw entry in the SHA-verified locked tarball retained
under `$DSH_HOME\artifacts`; version and file-existence markers alone are not
accepted.

## Agent bootstrap command

Use the repository workflow instead of asking an agent to reproduce the steps
from prose:

```powershell
powershell.exe -File tools\enable-copilot-search-vision.ps1 `
  -Model '<model-id-returned-by-copilot2api>'
```

The command is idempotent and fail-closed. Before changing files, it requires:

- `DSH_CLI_PATH` (or the resolved `dsh`) to identify either the
  Desktop-compatible prefix-root shim or the receipt canonical
  `node_modules\.bin\dsh.cmd`;
- `<prefix>\dsh-local-install.json` to attest schema 1,
  `cloga/deepseek-harness`, a full commit SHA, the installed
  `@deepseek-ai/dsh` name/version, prefix-root CLI consistency, the exact
  forwarding shim and derived canonical CLI, a valid release-manifest SHA-256,
  matching installed package manifests, and the locked deployment's hashes for
  the root shim, npm shim, and exact `lib\bin.js`;
- the active Desktop process tree to run that exact sealed entrypoint, outside
  the packaged Desktop core, with the same Node PID owning loopback port 3080;
- `COPILOT_API_KEY` to resolve from the process environment or
  `$DSH_HOME/.credentials.yaml`, without reading it into output;
- copilot2api `GET /v1/models` to return the selected model with explicit image
  metadata;
- the active renderer and `$DSH_HOME\profiles\node_modules` fallback to expose
  `exports.SlotOutlet = SlotOutlet;`.

It then installs `dsh-web-search-provider` through the public `dsh plugin`
command for both `web` and `headless`, writes a managed
`github-copilot-gateway` OpenAI Responses route, selects
`web.searchProvider: copilot-hosted`, and disables only the built-in
`web-search-deepseek` row. The `web` host and `tool-web` remain mounted, and
the credential value is never copied into settings.

Preview and rollback:

```powershell
powershell.exe -File tools\enable-copilot-search-vision.ps1 `
  -Model '<model-id>' -DryRun

powershell.exe -File tools\enable-copilot-search-vision.ps1 `
  -Action Rollback -OperationId '<operation-id>'
```

Backups cover settings and every profile manifest, patch, workspace, and lock
file the workflow may change. They default to
`%LOCALAPPDATA%\dsh-windows-ops\copilot-backups`.

The default vision check is a deterministic contract check: explicit catalog
metadata plus the configured `openai-responses` image input route. Use
`-VisionProbe Live` only when sending a one-pixel image request to the local
gateway is approved. A model name is never accepted as vision evidence.

The command also runs `tools\dsh-sandbox-regression-probe.mjs` against the
installed Core. It checks the shared behavior used by both `pwsh` and `bash`:
under effective `danger-full-access`, same-mode and `workspace-write` requests
must execute as no-ops without approval and must retain
`danger-full-access`; a real `workspace-write` to `danger-full-access`
escalation must request approval exactly once. The default is now
`-SandboxGate Require`; a pre-fix or incomplete Core blocks verification. A
temporary diagnostic run may explicitly select `Report`, but it cannot satisfy
the locked installation contract:

```powershell
powershell.exe -File tools\enable-copilot-search-vision.ps1 `
  -Model '<model-id>' -SandboxGate Require
```

The behavior belongs to `cloga/deepseek-harness`; this repository only runs
the public shared-helper contract and reports the gate.

The workflow intentionally does not repair product-layer prerequisites.
Renderer patch ownership remains with
[`deepseek-harness-desktop`](https://github.com/dsh-tauri-desk/deepseek-harness-desktop/blob/main/src-tauri/src/service/workflow/renderer_patch.rs);
local-core packaging remains with `cloga/deepseek-harness`; Responses/search
behavior remains with `dsh-web-search-provider`. Missing or incompatible
markers stop the workflow with an actionable failure.

## Core improvements versus plugins

The current fork improvements and the plugin improvements are complementary;
they do not implement the same ownership boundary.

| Capability | Owning layer | Compatibility |
|---|---|---|
| Import optional picker, policy, endpoint, token-limit, reasoning, and model metadata | Harness core | Generic OpenAI-compatible discovery; the provider plugin may expose the metadata but does not mutate Harness settings. |
| Provider readiness and onboarding without a universal credential assumption | Harness core | Independent of plugin loading; benefits custom and local providers. |
| Propagate discovered image capability through registry, RPC, profiles, and editor | Harness core | Complements the provider's rule that image requests stay on DSH's official vision path. |
| Responses replay IDs, grounded sandbox escalation, hosted web search, and image bypass | `dsh-web-search-provider` | Provider-only behavior; no duplicate core patch is required. |
| Core selection, lifecycle, delayed-start recovery, and plugin diagnostics | Desktop shell | Independent of model-provider behavior. |
| Status, patch, build, upgrade, and doctor tools | `dsh-dev-tools` plugin | Agent-facing operations over the selected core; exact API/version compatibility still applies. |

The fork changes are **not limited to GitHub Copilot models**. They are designed
for standard OpenAI-compatible gateways that expose useful `/v1/models`
metadata. GitHub Copilot through `copilot2api` is the validated deployment in
this repository. Copilot-specific hosted web search and gateway authentication
remain provider/gateway features rather than generic Harness-core features.

## Conflict conditions to prevent

The architecture is compatible when each layer keeps its ownership boundary.
Treat these conditions as deployment failures, not as reasons to apply a broad
patch:

- Desktop resolves a different `dsh` executable than the reviewed fork build.
- The local-core updater replaces the fork with the public npm release.
- A plugin targets internal APIs from a different Harness version.
- Two plugins rewrite the same provider configuration or request path.
- An exact-marker replay patch reports `incompatible` against changed source.
- A plugin is installed into a different Desktop profile than the active one.
- Image-capability metadata and the actual gateway behavior disagree.

Use `tools\dsh-compat-check.mjs`, `tools\dsh-replay.ps1 -Action SelfCheck`, and
`-Action Apply -DryRun` before changing a working profile. Unknown source
markers must remain incompatible; never guess a replacement.

## Upgrade sequence

1. Record the current CLI path, version, fork commit, tarball, Desktop version,
   active profile, and plugin versions.
2. Build and pack the new fork commit.
3. Stop Desktop and globally install the new tarball.
4. Restart Desktop with the same `DSH_CLI_PATH`.
5. Verify core selection, then run self-check and plugin compatibility checks.
6. Test model discovery, a text request, an image-capable request when
   applicable, and provider-specific web search.
7. On failure, reinstall the known-good tarball and restore the previous
   profile snapshot.
