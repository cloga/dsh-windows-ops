# Local DSH core, Desktop, and GitHub Copilot practice

This is the maintained deployment baseline for testing
[`cloga/deepseek-harness`](https://github.com/cloga/deepseek-harness) with DSH
Desktop and GitHub Copilot-backed models on Windows.

## Supported architecture

DSH Desktop 0.8.2 supports a local core, but it does not accept a Harness fork
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

## Validated 2026-08-26 baseline

The installation described here was verified with:

| Component | Version or state |
|---|---|
| DSH Desktop | `0.8.2` |
| Local `@deepseek-ai/dsh` | `0.1.1-rc.2` |
| `cloga/deepseek-harness` | `3c8be05b4218fc08da679179b50f75bf8f780cdb` |
| Node / npm / pnpm | `24.19.0` / `11.17.0` / `11.7.0` |
| `copilot2api` | `0.6.1`, loopback `127.0.0.1:7777` |
| Desktop profile plugins | `dsh-tauri@0.2.0`, `dsh-tauri-ui@0.1.0`, `dsh-tauri-worktree@0.1.0` |

Record exact versions and the fork commit for each deployment. Treat this table as
evidence for this installation, not as an unbounded compatibility claim.

## Build and install the fork core

Use the Node and pnpm versions declared by the Harness repository. From a clean
checkout of `cloga/deepseek-harness`:

```powershell
$expectedCommit = '3c8be05b4218fc08da679179b50f75bf8f780cdb'
git switch --detach $expectedCommit
if ((git rev-parse HEAD) -ne $expectedCommit) {
  throw 'Harness checkout does not match the reviewed commit.'
}

corepack enable
pnpm install --frozen-lockfile
pnpm run build
pnpm exec tsx scripts/release/pack.ts --family dsh

$tarball = Get-ChildItem .\dist\npm\deepseek-ai-dsh-*.tgz |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1
npm install --global $tarball.FullName

Get-Command dsh
dsh --version
```

`release/pack.ts` writes the release-family tarballs to `dist/npm` by default
and verifies the package payload before returning.

Keep the tarball and its source commit together in local release notes. That
makes rollback deterministic:

```powershell
npm install --global C:\Path\To\known-good-deepseek-ai-dsh.tgz
```

## Install and select DSH Desktop

1. Install the official Desktop release for Windows.
2. If only one `dsh` is installed, start Desktop and select `local` on the
   **Core** page.
3. If multiple CLIs may resolve, set `DSH_CLI_PATH` to the verified executable
   before launching Desktop:

   ```powershell
   $dsh = (Get-Command dsh).Source
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
8. Install `dsh-web-search-provider` only when Responses/web-search behavior is
   needed. Keep plugin installation profile-scoped and follow the packaged
   Desktop compatibility rules.
9. Re-run `tools\dsh-replay.ps1 -Action SelfCheck` and confirm that service,
   model-catalog, and image-capability checks match the selected model.

Keep all GitHub and provider credentials in ignored local environment files or
the relevant platform credential store. Never copy them into DSH patches,
profiles committed to Git, fixtures, logs, or documentation.

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

If installing the three Desktop plugins globally in the same workflow, include
all six packages in one command so npm cannot prune the loader dependencies:

```powershell
npm install --global `
  @deepseek-ai/cordis-plugin-hmr@1.0.16 `
  @deepseek-ai/cordis-plugin-timer@1.1.3 `
  node-addon-require-builtin@0.1.4 `
  dsh-tauri@0.2.0 `
  dsh-tauri-ui@0.1.0 `
  dsh-tauri-worktree@0.1.0
```

The Desktop error page retains the previous failure. After repairing dependencies,
click **Retry** to start the backend again; merely reopening the window may leave
the old error state visible.

## Materialize Desktop plugins

For the packaged Windows profile, install `dsh-tauri`, `dsh-tauri-ui`, and
`dsh-tauri-worktree` as physical directory copies. Do not use directory junctions:
Node resolves imports from the real target path, which can move dependency lookup
outside the profile's `node_modules`.

The validated packages came from the global npm directory and were copied into
the web profile. Back up existing entries, then replace them with staged physical
copies:

```powershell
$sourceRoot = Join-Path $env:APPDATA 'npm\node_modules'
$profileRoot = Join-Path $HOME '.dsh\profiles\web\node_modules'
$stageRoot = Join-Path $env:TEMP "dsh-tauri-materialized-$PID"
$backupRoot = Join-Path $env:LOCALAPPDATA "dsh-windows-ops\plugin-backups\$(Get-Date -Format yyyyMMdd-HHmmss)"
$plugins = @('dsh-tauri', 'dsh-tauri-ui', 'dsh-tauri-worktree')

New-Item -ItemType Directory -Path $stageRoot, $backupRoot, $profileRoot -Force | Out-Null
foreach ($plugin in $plugins) {
  $source = Join-Path $sourceRoot $plugin
  $staged = Join-Path $stageRoot $plugin
  $target = Join-Path $profileRoot $plugin
  if (-not (Test-Path -LiteralPath (Join-Path $source 'package.json'))) {
    throw "Missing reviewed global package: $plugin"
  }
  Copy-Item -LiteralPath $source -Destination $staged -Recurse
  if (Test-Path -LiteralPath $target) {
    Move-Item -LiteralPath $target -Destination (Join-Path $backupRoot $plugin)
  }
  Move-Item -LiteralPath $staged -Destination $target
}
Remove-Item -LiteralPath $stageRoot -Force
```

Confirm each copied `package.json` matches the pinned versions in the baseline
table before restarting Desktop. Restore the corresponding directory from
`plugin-backups` to roll back.

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
| Desktop listener | `127.0.0.1:3080` |
| Gateway listener | `127.0.0.1:7777`, not a public bind |
| Gateway task | Current-user logon task is running |
| Model endpoint | HTTP 200 and a non-empty catalog; validated run returned 35 models |
| Provider UI | Responses and Chat routes both report configured credentials |
| Text request | A prompt without the expected answer embedded returns the correct result |
| Vision request | A generated test image is identified correctly through the official image path |
| Compatibility | `web --probe` and `headless --probe` report no fatal imports |

The replay tool extracts models from JSON configuration and HTTP responses. For
`settings.yaml`, it currently reports existence and SHA-256 only; do not interpret
an empty local model list as proof that the YAML routes are missing.

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
