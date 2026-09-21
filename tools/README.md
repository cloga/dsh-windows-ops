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
| Check the locked Desktop/Copilot target | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-windows-copilot.ps1` | Read-only | Published target is Desktop `0.1.6-alpha.1.cloga.17` / sequence 28 / Core `0.1.6-alpha.1` / Copilot alpha.33; audits EXE, runtime descriptor, ASAR inventory and native profile proofs. Fresh hosted Native Ops run `35595040585` attempt 1 passed at exact code head `bb7a0a366e789b19918be6d8a6e40266c46a94f9`; this is not qualification of a later evidence commit or merge, and historical `.16` runs cannot transfer. Do not run this future-lock machine Check while installed Desktop remains `.cloga.10`. [Source-bound formal evidence](../docs/desktop-external-links-17.md) is not local activation or live account/network/OAuth/model/search proof |
| Legacy Web deployment Apply only | Legacy-mode installer with `-Apply`, exact artifacts and optional `-IncludeCompanionSuite`; restart needs exact live-Session acknowledgement | High in supported legacy mode | The current native lock rejects external Apply/restart/companion inclusion and delegates to Desktop's separately authorized native flow. Never build, install or select a second Core to bypass this boundary |
| Verify the Desktop-managed runtime | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-windows-copilot.ps1 -Action Verify` | None | Published `.17` descriptor SHA-256 `eca8a91da4737f625716323d0be8a51156b24934183904a41d06599ffafe36bd`; exact installed EXE/custom `$INSTDIR` controls the ASAR root. Functional evidence remains `manual-verification-required`/exit 2, never a Web-listener substitute |
| Roll back a legacy installer operation | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-windows-copilot.ps1 -Action Rollback -OperationId <id>` | Backup restore only in supported legacy mode | Current native external rollback is refused; use the native consent-gated recovery flow. Legacy rollback never bypasses live-Session restart safety |
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

## ASAR entrypoint boundaries

**Alpha.2 preparation is not promotion.** `native-runtime-integrity.mjs` selects
Host protocol 4 only from the independently pinned exact Core version
`0.1.6-alpha.2`, never from the descriptor or a generic `[3, 4]` allowlist.
Other versions retain protocol 3; `0.1.6-synthetic-local.1` remains synthetic-only.
Both native ASAR preflight and Electron probe reuse that validator. Release and
fresh-source acceptance require alpha.2 initial/restart read-only settings proof,
without changing `installerUpgradeVerified:false` or runtime trust. Descriptor/release
schemas remain 1, provisioning plan/state/store 1, managed capability/manifest 3.
See [pre-publication limits and later promotion](../docs/core-016a2-assessment.md#strict-native-compatibility-preparation).
Historical alpha.2 [combined packaged-evidence preparation](../docs/core-016a2-assessment.md#alpha2-combined-packaged-evidence-preparation)
keeps two contracts separate: imported combined-format functional/failure/observer/suite
records require ordinary acceptance to be absent; a fresh Ops successful resolver
observer still uses genuine ordinary acceptance after cleanup. Selection must be
explicitly reviewed for the exact version and format, never inferred from files
or a failed ordinary parse. The explicit `combined-suite-v2` path requires
functional/ordinary schema 2 and mandatory original `positive-usage.json` bytes,
bound by raw hash and the reviewed Copilot alpha.33 source/Client-byte policy in
both imported and fresh evidence. Both routes must cover inherited/absent Session
scope, removal/closure and provider restoration, and visible Client disposal;
synthetic Client unit tests are not hosted released-Client proof. V1 and legacy
alpha.1 readers and original evidence remain intact. The fresh caller keeps genuine Ops job identity
separate from the verified Core checkout: an archived private Ops source has no
`.git` or derived Ops tree. Alpha.2 passes `expectedCoreSource` with seven lock-bound,
independently preflight-verified Core facts (commit, tree, Desktop/upstream versions,
executable/runtime/plan hashes), then checks the Core owner's returned observations.
The actual Ops environment, including `GITHUB_SHA`, remains present and unchanged
through import, invocation and failure; no SHA omission or spoofing is allowed.
Historical alpha.1 invocation is unchanged and does not receive this future API.
The caller contract is separate from the dual-proof adapter below; neither alone
qualifies alpha.2. Original Core CI qualification summaries attest
unarchived installed checks only within their bound source/run scope; missing
root ownership/validation records prevent complete offline replay. These are
internal evidence adapters, not new public assets, deployment pins or activation
permission. Alpha.2 remains unpublished and unqualified.

The new explicit [`dual-ordinary-canary-v1` preparation](../docs/core-016a2-assessment.md#alpha2-independent-dual-proof-preparation)
uses the final immutable Core `3ca51d61bdf39f8c63c26125674cd92fdcf6ed98` contract:
PRIMARY ordinary originals at the formal root, independent canary originals under
`canary/`, and the exact 45-input qualification plus authenticated API snapshots
under `core-qualification/`. Public build objects use Core's six fields, not Ops
runUrl/attempt. Both graphs require schema2 positive cases (21 keys, quotaReads4)
and the fixed reviewed Client policy; the fresh Ops ordinary run is a third run
with its own identity, menus and paths. This adapter does not promote alpha.2;
historical readers remain unchanged. The offline reader verifies pinned API/original-JSON consistency only:
its Ops-owned limits explicitly report ZIP bytes/member membership unverified.
Promotion must separately authenticate all four original ZIPs and audit safe,
byte-exact selected-member acquisition before real evidence/pins are committed.
No new download lane, archive parser or activation permission is introduced.

The current published Ops target is Desktop `0.1.6-alpha.1.cloga.17`,
sequence 28, with unchanged bundled Core `0.1.6-alpha.1` and Copilot `0.4.0-alpha.33`.
[Formal run `35583602522` attempt 1](../docs/desktop-external-links-17.md) succeeded;
Release `392847203` and all six published assets are source-bound and independently
verified. Initial/restart settings, version-menu, signed-out usage and synthetic
released-Client positive usage remain scoped packaged evidence. The external-link
fixture uses actual Electron DOM activation with a substituted OS opener, not real
browser navigation or OAuth. **Fresh hosted Native Ops run `35595040585` attempt 1 passed**
at exact code head `bb7a0a366e789b19918be6d8a6e40266c46a94f9`; native job `106318363183`
and all four jobs succeeded. The [raw summary](../tests/fixtures/desktop-native-verified-release/ops-cloga016-17/qualification.json)
and [provenance](../tests/fixtures/desktop-native-verified-release/ops-cloga016-17/README.md)
bind the authenticated original artifact, not a later docs/evidence commit or merge.
First native failure `35590167413` retains its unknown startup cause and original
not-ready evidence; later diagnostics did not prove a repair. Ordinary CI `35593395998`
was a separate LF/CRLF test-extraction defect, fixed test-only at `bb7a0a3…`, not a runtime failure.

Historical `.cloga.16` formal run `35569892548` attempt 2 and Ops runs `35575187267`
at `a59f586df4e329c3bc8b3f885013fdb5493f4970` and `35577921833` at
`cd384495ac2fd0c850b3c8cd93223d35c4bc83a0` remain in the
[alpha.33 owning record](../docs/copilot-alpha33-upgrade-record.md), including attempt 1's
`EBUSY` helper-cleanup failure. Neither those nor `.cloga.14`/alpha.32 run `35553019059`
qualify `.17`. Delivery is runtime-only and **stage-only**, without local installation,
activation or restart; it does not qualify Core alpha.2, live account/network,
OAuth, model/search, whole-carrier integrity or installer upgrades.
Apply the [official-first upgrade checklist](../docs/local-core-desktop-copilot.md#official-first-upgrade-checklist)
before carrying custom code forward; preserve required behavior until parity is verified.
For the selected ASAR runtime:

- The native file checker remains read-only and inventory/peer proof is not a
  live Host/model response. Host execution uses the locked Electron EXE in Node
  mode; packaged pnpm/helper execution still uses physical bundled upstream Node.
  User ownership metadata is preserved without migrations, and permitted user
  extras remain `contentsAttested:false`, not baseline health. Replay runtime identity uses that audited checker,
  not PowerShell reads of virtual files; failed prerequisites remain not-ready.
- Higher-level Desktop identity also projects the bounded ASAR audit using the
  caller's explicit Harness home, rather than treating a virtual descriptor as
  a missing physical file. EXE bytes, metadata, signature and exact audited
  version/root/descriptor identity must all pass. This removes a false structural
  failure and its propagated Host-binding failure; it does not bypass either
  guard, change the exact Host argv contract, or upgrade/reload a plugin.
- The optional Web installer requires an explicit **existing compatible physical
  Web runtime** (`-RuntimeRoot`) or reports `physical-web-runtime-required`
  before downloads, import probes or its mutex. It never supplies another Core.
  See the [optional suite boundary](../docs/plugins/optional-companion-suite.md#physical-web-runtime-boundary).
- Existing user Agent Presets are not silently skipped: ASAR target-wrapper
  validation is explicitly `unsupported-asar-target-validation`/not-ready.
  The successful no-user-presets path does not prove this unsupported validation.
- Archive patch targets, including native `resources/app.asar.unpacked/dsh` backing files,
  are immutable/unsupported for replay Verify and DryRun; native Apply/Rollback
  refusal remains. No archive patching, physical fallback,
  private boot wrapper, invented CLI flag or read-only `--dump-config` claim is made.
- `enable-copilot-search-vision.ps1` stays historical official-only; its guard is
  not loosened into an unqualified native Electron/ASAR launcher.

The [qualification recipe](../tests/fixtures/native-asar-synthetic/README.md)
separates synthetic checks, actual-release observer proof and outstanding cases.
These entrypoint limits do not authorize installing, restarting or replacing a
running Desktop, Host, Web runtime or Profile.

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
