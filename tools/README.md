# Tool index

Use the narrowest tool for the job. The deployment lock remains authoritative; diagnostics and catalog tools do not modify it.

## Which command should I run?

| Need | Command | Mutation | Evidence / rollback |
|---|---|---:|---|
| Review a newer Copilot managed-route migration | `powershell.exe -NoProfile -File tools\migrate-copilot-managed-route.ps1 -Live` | No config writes; no catalog call unless explicitly allowed | Fresh loaded-plugin/live-Agent receipt; passive check remains catalog-unverified. See [maintenance boundaries and explicit Apply](../docs/copilot-managed-route.md). No install/restart/full-baseline attestation |
| Check, prepare, build, or package an isolated Electron Desktop source build | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\build-official-desktop.ps1 [-Action Prepare|Verify|Build|PackageLocal] [-Registry <https-url>]` | None in default Check; source/build files only for explicit actions | Pins official `dsh-v0.1.5-rc.2` commit/tree, defaults dependency routing to `https://packagefeedproxy.microsoft.io/npm/`, and records the single locked Copilot provisioning recipe in PackageLocal receipts. Produces a distinct unsigned/no-update local package without install or launch. See [local build guide](../docs/official-desktop-local-build.md) |
| Check or install the pinned local Desktop side-by-side | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-official-desktop-local.ps1 [-Apply -AcknowledgeUnsignedLocalBuild] [-SharedHome <existing-home>\|-UseIsolatedHome]` | None in default Check; explicit Apply packages and installs locally, transactionally provisions the verified Copilot Release, then writes owned launcher/shortcuts/receipts | New installs use an isolated Harness home by default. Shared/isolated upgrades replace only the validated reserved Desktop profile and private pnpm state; Sessions/settings/credentials are not read or modified. Revalidates PackageLocal, refuses live consumers, preserves the community Desktop, and never launches/restarts/uninstalls. See [local build and install guide](../docs/official-desktop-local-build.md) |
| Check or explicitly trigger an operations-owned local Desktop update | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\manage-official-desktop-update-channel.ps1 -Action Check\|Install ...` | Remote Check downloads only `release.json` to a temporary directory and is read-only for owned state. Explicit Install downloads and revalidates all declared files, atomically stages them, then starts the unsigned NSIS installer interactively with no silent arguments; Windows installer/UAC confirmation remains visible | Reuses strict Stage and Complete validation, invokes the same transactional plugin provisioner before schema-3 completion, and reports recoverable blocked state if readback/provisioning cannot complete. It never publishes, embeds `app-update.yml`, enables `electron-updater`, bypasses warnings, or stops processes. See [managed update channel](../docs/official-desktop-local-build.md#dsh-windows-ops-managed-update-channel-explicit-one-click-install) |
| Compare the locked Copilot artifact with its immutable GitHub Release | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\sync-official-desktop-plugin-release.ps1 -Action Check` | Read-only; `Generate` prints exact follow-up commands but edits nothing | Verifies tag/release immutability, commit, asset/checksum names, sizes, and hashes. Never accepts `latest` or persists credentials |
| Preview or apply the optional community configuration migration | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-official-desktop-local.ps1 -Migrate` / `-Apply -Migrate -AcknowledgeMigrationPlan sha256:<hash>` | Plan is read-only; Apply changes only validated non-secret target settings after exact plan-hash acknowledgement | Never copies secrets, Sessions, workspaces, `node_modules`, or Desktop profile files; plugin entries remain manual intents; requires process/session probes and keeps a target backup. See [migration stage](../docs/official-desktop-local-build.md#optional-configuration-migration-plan-first) |
| Check the locked Desktop/Copilot deployment | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-windows-copilot.ps1` | None by default | Produces a plan; no changes without `-Apply`; attests fork-owned Desktop `0.1.5-rc.3.cloga.1`, its `desktop-runtime.json` descriptor, web/headless package coherence, and the exact active PID owning IPv4 `127.0.0.1:3080` |
| Apply the exact locked Desktop and companion selection | Same command with `-Apply`, plugin source/Release paths, Desktop artifact, and optional `-IncludeCompanionSuite`; add `-RestartDesktop -AcknowledgeLiveSessionIds <exact listed IDs>` only after the user accepts every listed interruption | High | One backup/rollback transaction; Copilot is required, while the switch atomically includes locked Cron 0.7.1 and Playwright Host 0.1.7; never builds, installs, or selects a DSH runtime |
| Verify the Desktop-managed runtime | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-windows-copilot.ps1 -Action Verify` | None | Attests the fork release runtime descriptor for bundled `@deepseek-ai/dsh@0.1.5-rc.2` and the exact active PID owning IPv4 `127.0.0.1:3080`; the installer may use a custom `$INSTDIR`, so explicit Desktop executable paths override the default per-user location |
| Roll back an installer operation | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-windows-copilot.ps1 -Action Rollback -OperationId <id>` (add `-RestartDesktop -AcknowledgeLiveSessionIds <exact listed IDs>` only after explicit interruption approval) | Backup restore | Restores the operation's backed-up Desktop/plugin/profile state without bypassing live-Session restart safety |
| Install/select the direct Copilot plugin and search integration | `powershell.exe -File tools\enable-copilot-search-vision.ps1 [-CopilotIntegrationPackage '<locked-url-or-local-tgz>'] [-DeploymentLockPath '<lock>'] [-DesktopExecutablePath '<exe>']` | Configuration | Historical compatibility path; installs no vision fallback. It resolves the canonical locked Release, hash-checks local tarballs, rejects registry/arbitrary specs, upgrades both profiles through the Desktop-managed official CLI, and returns `sign-in-required` until UI authorization completes |
| Check, stage, or verify the companion suite without replacing Desktop/Core | `powershell.exe -File tools\install-optional-companion-suite.ps1` / `-Apply` / `-Action Verify` | None by default / Web Profile composition | Requires installed Core 0.1.6-alpha.1, compatible Cordis, and the locked API manifests; preserves existing Desktop state and never mutates globals, settings, credentials, gateway, Desktop, Core, or running processes |
| Check versions and direct-provider replay markers | `powershell.exe -File tools\dsh-replay.ps1 -Action SelfCheck` | None | Reuses lock-selected installer discovery and runtime descriptor checks; no Tauri fallback. Reports reserved Desktop plugin markers separately from Web/headless configuration. Inspect `deployment.valid` and patch status, not exit zero alone |
| Preview replay patches | `powershell.exe -File tools\dsh-replay.ps1 -Action Apply -DryRun` | None | Exact-marker plan only |
| Preflight the session store | `node tools\preflight-check.mjs` / `--fix` | None by default / directory quarantine | Scans every `session-*` stable name and strictly validates the first Zstd frame before startup |
| Diagnose or repair the installation | `node tools\dsh-doctor.mjs` / `--fix` / `--smoke` | None / targeted | Read the report before `--fix`; repairs back up or quarantine where supported |
| Check community-plugin host imports | `node tools\dsh-compat-check.mjs <profile> --probe=<package>` | Executes plugin top-level code | `--json` emits L2 evidence; not a functional test |
| Validate repository/lock/doc parity | `node tools\validate-repository-content.mjs` | None | Rejects source, Release, version, fixture, capability, and README drift |
| Validate plugin catalog metadata | `node tools\validate-plugin-catalog.mjs` | None | Rejects invalid evidence, mutable baseline Releases, and false baseline claims |
| Detect duplicate sessions | `powershell.exe -File tools\check-session-duplicates.ps1` | None | Report only |
| Install Playwright MCP tools for every Agent Preset | After the companion check and artifact verification: `dsh plugin --profile web add https://github.com/cloga/dsh-playwright-host/releases/download/v0.1.7/dsh-playwright-host-0.1.7.tgz` | Web Profile composition; activation requires authorized Host restart | `--dump-config`, bundle tests, then post-restart tool discovery and browser smoke; remove with `dsh plugin --profile web remove dsh-playwright-host` |
| Install the optional scheduler overlay | After the companion check and artifact verification: `dsh plugin --profile web add https://github.com/cloga/dsh-cron/releases/download/v0.7.1/dsh-cron-0.7.1.tgz` | Web Profile composition; activation requires restart safety check | Verify `cron_list`, create/remove a disposable task if authorized, and back up task/history files; see `docs/plugins/scheduling.md` |
| Smoke-test the existing DSH Web GUI from any coding session | `python tools\dsh-web-smoke.py --expect-text "New Session"` | Browser read/isolated profile only | Screenshot plus JSON summary with document, Console, request, and HTTP evidence |
| Move a session safely | `node tools\dsh-move-session.mjs ...` | Session data | Backup and post-write verification |

`Test-WindowsCopilotInstallation` reports plugin policy separately under
`profile.pluginInventory`, `profile.pluginWarnings`, and `profile.pluginBlocks`.
Locked managed components remain fail-closed. Unmanaged dependencies are
inventory-only and cannot make the baseline healthy; an exact active match in
the target-Core denylist adds `profile-known-incompatible-plugin-active` and
blocks that cutover.

## Tool families

- **Deployment/build:** `install-windows-copilot.ps1`, `WindowsCopilotDeployment.psm1`, `build-official-desktop.ps1`, `DshOfficialDesktopBuild.psm1`, `install-official-desktop-local.ps1`, `Install-DshOfficialDesktopLocal.psm1`, `DshOfficialDesktopPluginProvisioning.psm1`, `sync-official-desktop-plugin-release.ps1`, `DshOfficialDesktopLocalMigration.psm1`, `manage-official-desktop-update-channel.ps1`, `DshOfficialDesktopUpdateChannel.psm1`, `enable-copilot-search-vision.ps1`
- **Diagnostics and replay:** `dsh-replay.ps1`, `DshWindowsOps.psm1`, `dsh-replay.patches.json`, `dsh-sandbox-regression-probe.mjs`
- **Browser verification:** `dsh-playwright-host/` exposes Host-scope MCP tools to every Preset; `dsh-web-smoke.py` is the independent Python fallback (task-specific flows still require explicit interaction assertions)
- **Diagnostics and targeted repair:** `dsh-doctor.mjs`, `preflight-check.mjs`
- **Plugin governance:** `dsh-compat-check.mjs`, `validate-plugin-catalog.mjs`
- **Sessions/workspaces:** `check-session-duplicates.ps1`, `dsh-move-session.mjs`, `dsh-workspace-fix.mjs`
- **Agent-native maintenance:** `dsh-dev-tools/`
- **Vendored session implementation:** `vendor/dsh-zstd/`
- **Historical helpers:** scripts whose guides explicitly mark them historical, such as `patch-brand-title.mjs`

Existing paths are intentionally retained so tested commands and links do not break. A future physical reorganization should leave wrappers at old paths until consumers migrate.
`enable-copilot-search-vision.ps1` is therefore retained only as a compatibility
path even though it now configures the broader `dsh-github-copilot`
integration. It does not install `dsh-vision-any` or any second vision provider;
image-capable routes use DSH's built-in attachment path and local files use the
built-in `read_image` tool. For deployment Apply, use
`-CopilotIntegrationSourceRoot`; the old `-ProviderSourceRoot` spelling remains
an alias.

The direct baseline is one DSH plugin reusing built-in `llm-pi-ai`, not an
embedded gateway. The wrapper never writes provider routes, endpoints, API-key
references, or model lists. Use the **Models → GitHub Copilot** provider card
for the interactive device flow.

`preflight-check.mjs` scans all `session-*` stable names. Each session log's
first Zstd frame must contain exactly one newline-terminated official v0
session header. The encoded directory must match `header.id`, project placement
must match `cwd`, and duplicates are detected by parsed header identity.
Default mode is read-only; `--fix` moves the entire affected session directory
outside `sessions` into quarantine without rewriting or deleting its contents.

## Plugin validation boundary

`dsh-compat-check.mjs` reports:

- `import-compatible`: dependency analysis has no known load failure;
- `import-warning`: dynamic, missing-dependency, native, engine, or client-injection risk remains;
- `load-fatal`: the host entry has an unresolved top-level static import.

Even with `--probe`, this is only the catalog's **L2** boundary. It does not prove Cordis activation, tool registration, cleanup, function, or security. Probe unknown plugins only in a disposable Profile and isolated `DSH_HOME`.

## Safety and contribution rules

- Run check/dry-run before apply/fix.
- Treat `-Action Verify` exit code `0` as successful Desktop/runtime attestation and `2` as failed evidence.
- Never expose credentials in output or evidence.
- Preserve deployment-lock identities and the single active `desktopNativeVerifiedRelease` delegation mode; do not reintroduce Windows Ops profile mutation unless the lock explicitly returns to `windowsOpsVerifiedRelease`.
- Accept the deployment only after direct sign-in, model response, hosted search, nonempty reasoning, fresh-Session Copilot Tool Schema, rollback, and exact listener-owner checks pass.
- Use synthetic fixtures; do not test browser/desktop controllers against personal profiles or arbitrary real applications.
- Functional tests must assert an outcome and verify cleanup.
- New tools must document purpose, mutation level, prerequisites, evidence, rollback, and tests.

## Test entry points

- Plugin catalog: `node tools\validate-plugin-catalog.mjs`
- Strict session preflight: `node --test tests\preflight-check.test.mjs`
- JavaScript syntax: `node --check <script>`
- Host Playwright bundle: `node --test tests\host-playwright-bundle.test.mjs`
- Browser smoke tool: `python -m py_compile tools\dsh-web-smoke.py`; with the existing GUI running, `python tools\dsh-web-smoke.py --expect-text "New Session" --fail-on-console-error --fail-on-request-failure --fail-on-http-error`
- Windows fixtures: Pester 5.7.1+ against `tests/`
- Locked installer: `tests/WindowsCopilotInstaller.Tests.ps1`
- Replay/operations: `tests/DshWindowsOps.Tests.ps1`
- Copilot bootstrap: `tests/DshCopilotBootstrap.Tests.ps1`

See `catalog/README.md`, `docs/plugins/plugin-validation.md`, and `docs/security-notes.md`. Issue #33 tracks this information-architecture and plugin-governance change.

As of 2026-09-04, no Computer Use executor belongs to the locked Windows Copilot baseline.
