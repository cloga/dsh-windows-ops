# Tool index

Use the narrowest tool for the job. The deployment lock remains authoritative; diagnostics and catalog tools do not modify it.

## Which command should I run?

| Need | Command | Mutation | Evidence / rollback |
|---|---|---:|---|
| Check the locked Desktop/Copilot deployment | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-windows-copilot.ps1` | None by default | Produces a plan; no changes without `-Apply`; attests official Desktop 0.10.3, its managed wrapper/tree/entrypoint, web/headless package coherence, and the exact active PID owning IPv4 `127.0.0.1:3080` |
| Apply the exact locked Desktop and companion selection | Same command with `-Apply`, plugin source/Release paths, Desktop artifact, and optional `-IncludeCompanionSuite`; add `-RestartDesktop -AcknowledgeLiveSessionIds <exact listed IDs>` only after the user accepts every listed interruption | High | One backup/rollback transaction; Copilot is required, while the switch atomically includes locked Cron 0.4.1 and Playwright Host 0.1.2; never builds, installs, or selects a DSH runtime |
| Verify the official Desktop-managed runtime | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-windows-copilot.ps1 -Action Verify` | None | Attests `deepseek-harness-pkg@0.1.2-alpha.5`, inner official `@deepseek-ai/dsh@0.1.2-rc.1`, the 10-file tree and exact entrypoint, and the exact active PID owning IPv4 `127.0.0.1:3080` |
| Roll back an installer operation | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-windows-copilot.ps1 -Action Rollback -OperationId <id>` (add `-RestartDesktop -AcknowledgeLiveSessionIds <exact listed IDs>` only after explicit interruption approval) | Backup restore | Restores the operation's backed-up Desktop/plugin/profile state without bypassing live-Session restart safety |
| Install/select the direct Copilot plugin and search integration | `powershell.exe -File tools\enable-copilot-search-vision.ps1 [-CopilotIntegrationPackage '<locked-url-or-local-tgz>'] [-DeploymentLockPath '<lock>'] [-DesktopExecutablePath '<exe>']` | Configuration | Defaults to the canonical locked Release URL, hash-checks any local tarball, rejects registry/arbitrary specs, upgrades both profiles through the Desktop-managed official CLI, and returns `sign-in-required` until UI authorization completes |
| Check or stage the optional companion suite directly | `powershell.exe -File tools\install-optional-companion-suite.ps1` / `-Apply` | None by default / Web Profile composition | Narrow wrapper over the same authoritative deployment lock; the main baseline flow is `install-windows-copilot.ps1 -IncludeCompanionSuite`; never restarts Host |
| Check versions and direct-provider replay markers | `powershell.exe -File tools\dsh-replay.ps1 -Action SelfCheck` | None | Includes Desktop-managed runtime, `llm-pi-ai` OAuth JSON normalization, per-model API route, and direct-integration evidence; no local gateway endpoint |
| Preview replay patches | `powershell.exe -File tools\dsh-replay.ps1 -Action Apply -DryRun` | None | Exact-marker plan only |
| Preflight the session store | `node tools\preflight-check.mjs` / `--fix` | None by default / directory quarantine | Scans every `session-*` stable name and strictly validates the first Zstd frame before startup |
| Diagnose or repair the installation | `node tools\dsh-doctor.mjs` / `--fix` / `--smoke` | None / targeted | Read the report before `--fix`; repairs back up or quarantine where supported |
| Check community-plugin host imports | `node tools\dsh-compat-check.mjs <profile> --probe=<package>` | Executes plugin top-level code | `--json` emits L2 evidence; not a functional test |
| Validate repository/lock/doc parity | `node tools\validate-repository-content.mjs` | None | Rejects source, Release, version, fixture, capability, and README drift |
| Validate plugin catalog metadata | `node tools\validate-plugin-catalog.mjs` | None | Rejects invalid evidence, mutable baseline Releases, and false baseline claims |
| Detect duplicate sessions | `powershell.exe -File tools\check-session-duplicates.ps1` | None | Report only |
| Install Playwright MCP tools for every Agent Preset | `dsh plugin --profile web add github:cloga/dsh-playwright-host#v0.1.2` | Web Profile composition; activation requires authorized Host restart | `--dump-config`, bundle tests, then post-restart tool discovery and browser smoke; remove with `dsh plugin --profile web remove dsh-playwright-host` |
| Install the optional scheduler overlay | `dsh plugin --profile web add github:cloga/dsh-cron#v0.4.1` | Web Profile composition; activation requires restart safety check | Verify `cron_list`, create/remove a disposable task if authorized, and back up task/history files; see `docs/plugins/scheduling.md` |
| Smoke-test the existing DSH Web GUI from any coding session | `python tools\dsh-web-smoke.py --expect-text "New Session"` | Browser read/isolated profile only | Screenshot plus JSON summary with document, Console, request, and HTTP evidence |
| Move a session safely | `node tools\dsh-move-session.mjs ...` | Session data | Backup and post-write verification |

## Tool families

- **Deployment:** `install-windows-copilot.ps1`, `WindowsCopilotDeployment.psm1`, `enable-copilot-search-vision.ps1`
- **Diagnostics and replay:** `dsh-replay.ps1`, `DshWindowsOps.psm1`, `dsh-replay.patches.json`, `dsh-sandbox-regression-probe.mjs`
- **Browser verification:** `dsh-playwright-host/` exposes Host-scope MCP tools to every Preset; `dsh-web-smoke.py` is the independent Python fallback (task-specific flows still require explicit interaction assertions)
- **Diagnostics and targeted repair:** `dsh-doctor.mjs`, `preflight-check.mjs`
- **Plugin governance:** `dsh-compat-check.mjs`, `validate-plugin-catalog.mjs`
- **Sessions/workspaces:** `check-session-duplicates.ps1`, `dsh-move-session.mjs`, `dsh-workspace-fix.mjs`
- **Agent-native maintenance:** `dsh-dev-tools/`
- **Vendored session implementation:** `vendor/dsh-zstd/`
- **Historical helpers:** scripts whose guides explicitly mark them historical, such as `patch-brand-title.mjs`

Existing paths are intentionally retained so tested commands and links do not break. A future physical reorganization should leave wrappers at old paths until consumers migrate.
`enable-copilot-search-vision.ps1` is therefore retained as a compatibility
path even though it now configures the broader `dsh-github-copilot`
integration. For deployment Apply, use `-CopilotIntegrationSourceRoot`;
the old `-ProviderSourceRoot` spelling remains an alias.

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
- Treat `-Action Verify` exit code `0` as successful official Desktop/runtime attestation and `2` as failed evidence.
- Never expose credentials in output or evidence.
- Preserve deployment-lock identities, all eight official Desktop 0.6.7 Profile links (including `dsh-tauri-panel-scheduler`), and the non-bundled panel placeholder.
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
