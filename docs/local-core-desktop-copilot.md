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

## Build and install the fork core

Use the Node and pnpm versions declared by the Harness repository. From a clean
checkout of `cloga/deepseek-harness`:

```powershell
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
   powershell.exe -File tools\dsh-replay.ps1 -Action SelfCheck
   ```

Do **not** use Desktop's **Update local core** action while validating the fork.
That action installs `@deepseek-ai/dsh@latest` from npm and can replace the
fork build. Upgrade by packing and globally installing a new reviewed tarball.

## Enable GitHub Copilot models

GitHub Copilot authentication belongs to the gateway, not to Desktop or the DSH
core.

1. Start the approved `copilot2api` deployment and complete its GitHub
   authentication flow.
2. Verify its OpenAI-compatible endpoint and model catalog locally:

   ```powershell
   Invoke-RestMethod http://127.0.0.1:7777/v1/models
   ```

3. In DSH, configure an OpenAI-compatible provider whose base URL targets the
   gateway, normally `http://127.0.0.1:7777/v1`.
4. Refresh model discovery and select a model returned by `/v1/models`.
5. Install `dsh-web-search-provider` only when Responses/web-search behavior is
   needed. Keep plugin installation profile-scoped and follow the packaged
   Desktop compatibility rules.
6. Re-run `tools\dsh-replay.ps1 -Action SelfCheck` and confirm that service,
   model-catalog, and image-capability checks match the selected model.

Keep all GitHub and provider credentials in ignored local environment files or
the relevant platform credential store. Never copy them into DSH patches,
profiles committed to Git, fixtures, logs, or documentation.

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
