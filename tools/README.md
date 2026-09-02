# Tool index

Use the narrowest tool for the job. The deployment lock remains authoritative; diagnostics and catalog tools do not modify it.

## Which command should I run?

| Need | Command | Mutation | Evidence / rollback |
|---|---|---:|---|
| Check the locked Desktop/Core/Copilot deployment | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-windows-copilot.ps1` | None by default | Produces a plan; no changes without `-Apply` |
| Apply and activate the exact locked fork Core | Same command with required source/artifact arguments, `-Apply -RestartDesktop` | High | Receipt-backed controlled CLI, persisted `DSH_CLI_PATH`, quarantined conflicting official npm shims, rollback receipt, and an exact supported Desktop runtime selector |
| Verify the locked rc.2 controlled CLI and Desktop runtime | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-windows-copilot.ps1 -Action Verify -CoreInstallPrefix C:\.tools\dsh-cloga` | None | Requires fork receipt URL/commit/bytes, zero-approval same/narrower probe, and Desktop selecting either that fork or its exact locked official alpha.4 download |
| Roll back Core selection | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-windows-copilot.ps1 -Action Rollback -RestartDesktop` | Environment and shim restore | Restores the previous user `DSH_CLI_PATH` and exact backed-up npm global shims |
| Install/select the direct Copilot plugin and search integration | `powershell.exe -File tools\enable-copilot-search-vision.ps1 [-CopilotIntegrationPackage '<tgz>'] [-DeploymentLockPath '<lock>'] [-DesktopExecutablePath '<exe>']` | Configuration | Uses the receipted controlled CLI for plugin commands, accepts only a lock-defined active Desktop runtime selector, upgrades both profiles to the exact locked plugin, and returns `sign-in-required` until UI authorization completes |
| Check versions and direct-provider/Core replay markers | `powershell.exe -File tools\dsh-replay.ps1 -Action SelfCheck` | None | Includes built `llm-pi-ai` OAuth JSON normalization and per-model API route evidence; no local gateway endpoint |
| Preview replay patches | `powershell.exe -File tools\dsh-replay.ps1 -Action Apply -DryRun` | None | Exact-marker plan only |
| Diagnose or repair the installation | `node tools\dsh-doctor.mjs` / `--fix` / `--smoke` | None / targeted | Read the report before `--fix`; repairs back up or quarantine where supported |
| Check community-plugin host imports | `node tools\dsh-compat-check.mjs <profile> --probe=<package>` | Executes plugin top-level code | `--json` emits L2 evidence; not a functional test |
| Validate plugin catalog metadata | `node tools\validate-plugin-catalog.mjs` | None | Rejects invalid evidence and false baseline claims |
| Detect duplicate sessions | `powershell.exe -File tools\check-session-duplicates.ps1` | None | Report only |
| Smoke-test the existing DSH Web GUI from any coding session | `python tools\dsh-web-smoke.py --expect-text "New Session"` | Browser read/isolated profile only | Screenshot plus JSON summary with document, Console, request, and HTTP evidence |
| Move a session safely | `node tools\dsh-move-session.mjs ...` | Session data | Backup and post-write verification |

## Tool families

- **Deployment:** `install-windows-copilot.ps1`, `WindowsCopilotDeployment.psm1`, `enable-copilot-search-vision.ps1`
- **Diagnostics and replay:** `dsh-replay.ps1`, `DshWindowsOps.psm1`, `dsh-replay.patches.json`, `dsh-sandbox-regression-probe.mjs`
- **Browser verification:** `dsh-web-smoke.py` (pinned Python Playwright with installed Edge; task-specific flows require an additional temporary Playwright script)
- **Diagnostics and targeted repair:** `dsh-doctor.mjs`, `preflight-check.mjs`
- **Plugin governance:** `dsh-compat-check.mjs`, `validate-plugin-catalog.mjs`
- **Sessions/workspaces:** `check-session-duplicates.ps1`, `dsh-move-session.mjs`, `dsh-workspace-fix.mjs`
- **Agent-native maintenance:** `dsh-dev-tools/`
- **Vendored session implementation:** `vendor/dsh-zstd/`
- **Historical helpers:** scripts whose guides explicitly mark them historical, such as `patch-brand-title.mjs`

Existing paths are intentionally retained so tested commands and links do not break. A future physical reorganization should leave wrappers at old paths until consumers migrate.
`enable-copilot-search-vision.ps1` is therefore retained as a compatibility
path even though it now configures the broader `dsh-github-copilot`
integration. For deployment apply, prefer `-CopilotIntegrationSourceRoot`;
the old `-ProviderSourceRoot` spelling remains an alias.

The direct baseline is one DSH plugin reusing built-in `llm-pi-ai`, not an
embedded gateway. The wrapper never writes provider routes, endpoints, API-key
references, or model lists. Use **Settings → GitHub Copilot** on rc.2 or the
**Models** provider card on alpha.4 for the interactive device flow.

## Plugin validation boundary

`dsh-compat-check.mjs` reports:

- `import-compatible`: dependency analysis has no known load failure;
- `import-warning`: dynamic, missing-dependency, native, engine, or client-injection risk remains;
- `load-fatal`: the host entry has an unresolved top-level static import.

Even with `--probe`, this is only the catalog's **L2** boundary. It does not prove Cordis activation, tool registration, cleanup, function, or security. Probe unknown plugins only in a disposable Profile and isolated `DSH_HOME`.

## Safety and contribution rules

- Run check/dry-run before apply/fix.
- Treat `-Action Verify` exit code `0` as success and `2` as failed fork activation evidence.
- Never expose credentials in output or evidence.
- Preserve deployment-lock identities and the five official Desktop internal-plugin links.
- Use synthetic fixtures; do not test browser/desktop controllers against personal profiles or arbitrary real applications.
- Functional tests must assert an outcome and verify cleanup.
- New tools must document purpose, mutation level, prerequisites, evidence, rollback, and tests.

## Test entry points

- Plugin catalog: `node tools\validate-plugin-catalog.mjs`
- JavaScript syntax: `node --check <script>`
- Browser smoke tool: `python -m py_compile tools\dsh-web-smoke.py`; with the existing GUI running, `python tools\dsh-web-smoke.py --expect-text "New Session" --fail-on-console-error --fail-on-request-failure --fail-on-http-error`
- Windows fixtures: Pester 5.7.1+ against `tests/`
- Locked installer: `tests/WindowsCopilotInstaller.Tests.ps1`
- Replay/operations: `tests/DshWindowsOps.Tests.ps1`
- Copilot bootstrap: `tests/DshCopilotBootstrap.Tests.ps1`

See `catalog/README.md`, `docs/plugins/plugin-validation.md`, and `docs/security-notes.md`. Issue #33 tracks this information-architecture and plugin-governance change.

As of 2026-08-30, no Computer Use executor belongs to the locked Windows Copilot baseline.
