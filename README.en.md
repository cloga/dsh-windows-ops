# dsh-windows-ops

> Operational experience + reusable tools for the **Windows packaged edition of DeepSeek Harness (DSH)**.

This repository collects lessons learned, root-cause analyses, and reusable scripts from running [`dsh-tauri-desk/deepseek-harness-desktop`](https://github.com/dsh-tauri-desk/deepseek-harness-desktop) with the `@deepseek-ai/dsh` 0.1.x runtime on real Windows hardware.

## Improvement portfolio

See the maintained **[DSH + GitHub Copilot improvement portfolio](docs/improvement-portfolio.md)**
for completed work, upstream-versus-fork ownership, current status, validation
evidence, and compatibility guidance.

## What's inside

| Category | Content | File |
|---|---|---|
| Startup stability | First-launch 60s timeout root cause (MCP launcher network stall) + fixes | `docs/startup-60s-timeout.md` |
| Brand / version | Window-title brand + **engine version** (`DeepSeek Harness v<version>`) patcher — **[historical]**: under the Tauri shell `patch-worker.mjs applyBrand` covers the 3 files and the window title comes from the shell/dsh-tauri | `tools/patch-brand-title.mjs` (historical), `tools/dsh-updater/patch-worker.mjs` |
| Vision dual-channel | Model-aware dual channel (official + vision-tool fallback) design + admission rules | `docs/vision-dual-channel.md` |
| A/B self-heal | Config snapshot + data junctions + detached scheduled-task restart + transactional upgrades | `docs/ab-self-heal.md` |
| **Self-heal (Tauri-adapted)** | **`dsh-doctor`**: 11 health checks + `--fix` auto-repair (patch reapply / broken-link rebuild / duplicate-insert disable / banned-plugin quarantine / vendor restore) + `--smoke` isolated boot + `--list-plugins`; **A/B re-targeted to the Tauri shell** (rescue passes `DSH_HOME=B` to the shell, restart is detached + doctor-first, promote writes a static plugin manifest); legacy swap/asar upgrade tool retired (core upgrades managed by the shell); `dsh-dev-tools` gains **`dsh_doctor`** | `tools/dsh-doctor.mjs`, `tools/dsh-rescue.ps1`, `tools/dsh-restart-*.ps1`, `tools/dsh-backup.ps1`, `tools/dsh-dev-tools/`, `tools/vendor/dsh-zstd/`, `docs/ab-tauri-adapt.md` |
| Plugin install | Preserve and attest official Desktop internal-plugin junctions; materialize external providers; run the compatibility checker before install | `tools/dsh-compat-check.mjs` |
| PowerShell pitfalls | 5.1 needs explicit `Add-Type System.Net.Http` (scheduled-task health checks silently fail) | `docs/powershell-5.1-pitfalls.md` |
| GitHub network | ghfast mirror git config + release/raw download script | `tools/gh-dl.ps1`, `docs/github-network.md` |
| Security | Credentials only via env; asar only via the official tool; read-only MCP by default | `docs/security-notes.md` |
| Agent-native dev | **`dsh-dev-tools` plugin**: `dsh_status` / `dsh_patch` / `dsh_build` / `dsh_upgrade` - the agent drives status/patch/build/upgrade natively inside the session | `tools/dsh-dev-tools/` |
| Durable replay / self-heal | Versioned component inventory, service/config/model/image checks, strict replayable patches, backups, rollback, and Desktop recovery | `tools/dsh-replay.ps1`, `docs/windows-replay-tooling.md` |
| Local core + Desktop + Copilot | Machine-locked, check-first installation of the official Desktop, fork Core, Copilot2API, loader packages, official internal-plugin junctions, a physical search provider, dual-protocol routes, backups, and acceptance contracts | `deployments/windows-copilot.lock.json`, `tools/install-windows-copilot.ps1`, `docs/local-core-desktop-copilot.md` |
| Copilot ACP subagent | Preserve native spawn/fork while adding GitHub Copilot CLI as an independent ACP coding agent; deterministic routing, permission boundaries, validation, and rollback | `docs/copilot-acp-subagent.md` |
| Copilot search/vision bootstrap | One fail-closed command verifies the active local core, configures both profiles, disables conflicting search, checks model/vision metadata and SlotOutlet/flat layout, and provides backup/rollback | `tools/enable-copilot-search-vision.ps1` |

## Usage

1. **Patches** (`tools/*.mjs`): run with `node <script>`; paths come from environment variables / arguments (see header comments). Nothing is hard-coded to one machine.
2. **Docs**: experience and post-mortems, with root-cause analysis and verification steps.
3. **compat-check**: zero-dependency Node script; run before installing any community plugin (static import manifest + `--probe` real import test).
4. **replay/self-heal**: run `powershell.exe -File tools\dsh-replay.ps1 -Action SelfCheck`; use `-Action Apply -DryRun` before applying exact-marker patches. If execution policy blocks scripts, add process-scoped `-NoProfile -ExecutionPolicy Bypass` rather than changing machine policy.
5. **Windows Copilot deployment**: run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-windows-copilot.ps1`. Check mode is the default and makes no changes. Supply the locked source checkouts, release artifacts, model-catalog snapshot, and explicit `-Apply` only after the plan is clean.
6. **Copilot bootstrap**: after the locked deployment, run `powershell.exe -File tools\enable-copilot-search-vision.ps1 -Model '<catalog-model-id>'`; unmet core, model, vision, or renderer prerequisites stop before configuration changes.

## Key findings (short version)

### First-launch "The local service did not start within 60 seconds"
The desktop shell waits 60s for the web service to print `dsh web: http://...`. The `dsh-mcp-client` plugin blocks activation on `await connection.ready`, so any MCP server whose launcher stalls on the network (here: `npx @harusame64/desktop-touch-mcp`, whose launcher fetches a GitHub release **every start**, with no timeout) pushes startup past 60s. A second launch works because the release is already cached. Fix: run the local release entry directly (`node <...>/dist/server-windows.js`), or upstream fix (see PR below).

### Window title shows `— DeepSeek Harness v0.1.1-rc.2`
The official `DocumentTitle.tsx` defaults to `DSH Local Build` (a local-build marker) and supports a build-time `DSH_CLIENT_TITLE` env. `patch-brand-title.mjs` rewrites the shipped default to `DeepSeek Harness v<version>`, with the version read live from the runtime `package.json` — idempotent across upgrades.

### Model-aware vision dual channel
Image-capable models (vision-exp) get images via the official channel; text-only models (flash/pro) get a path hint + `vision` tool fallback. The admission decision must mirror the host gate's own model resolution order (picker > requestHeader > defaults) and never prefer a vision-named candidate across stale sources — a stale vision-exp in `requestHeader` made admission leak the image to the gate, which then rejected it ("model does not support image input") with no fallback ever reached.

## Relationship to dependencies and upstream projects

This repository does not redistribute the Desktop, Core, gateway, or search provider. It pins reviewed versions and commits and orchestrates installation, migration, acceptance, and rollback. [`deployments/windows-copilot.lock.json`](deployments/windows-copilot.lock.json) is the machine-executable baseline; the [improvement portfolio](docs/improvement-portfolio.md) records ownership and external-upstream status. The `cloga/*` repositories are controlled deployment forks, so this table describes their default-branch capabilities and current pins rather than internal PR workflow state.

| Project | Deployment responsibility | Current relationship |
|---|---|---|
| [`dsh-tauri-desk/deepseek-harness-desktop`](https://github.com/dsh-tauri-desk/deepseek-harness-desktop) | Official Windows shell, lifecycle, and five internal plugins | Official 0.9.2; delayed-start recovery [PR #118](https://github.com/dsh-tauri-desk/deepseek-harness-desktop/pull/118) is merged |
| [`cloga/deepseek-harness`](https://github.com/cloga/deepseek-harness) | Local Core, model/vision metadata, receipt installation, and sandbox policy | Default branch contains the current improvements; deployment pin `bd520d6e` |
| [`cloga/dsh-web-search-provider`](https://github.com/cloga/dsh-web-search-provider) | Copilot hosted search, traditional Search bridge, Responses replay, image bypass, and nonempty reasoning | Default branch contains the complete baseline; deployment pin `e47390c7` / `0.2.3-cloga.3` |
| [`cloga/copilot2api`](https://github.com/cloga/copilot2api) | Maintains the DSH integration guide and receives changes not yet accepted upstream | Default branch `5a042b40` contains the DSH guide; the deployed artifact remains the official upstream `whtsky/copilot2api` 0.6.1 release |
| [`cloga/dsh-windows-ops`](https://github.com/cloga/dsh-windows-ops) | Exact lock, check-first one-shot installer, migration, acceptance, and rollback | Default branch maintains the current Desktop 0.9.2 + Copilot deployment baseline |

Historical and optional integrations are tracked separately from the locked Copilot baseline:

- [`tianmingwan/dsh-vision-any` PR #2](https://github.com/tianmingwan/dsh-vision-any/pull/2) remains **Open** and records model-aware admission for the optional vision-tool fallback.
- [`Harusame64/desktop-touch-mcp` PR #586](https://github.com/Harusame64/desktop-touch-mcp/pull/586) was **Merged** on 2026-08-23 and fixes offline-first release resolution and fetch timeout for the optional MCP launcher.

## Compliance

- No API keys / tokens / account info anywhere. Credentials are injected via environment variables (`GITHUB_PERSONAL_ACCESS_TOKEN`, `DEEPSEEK_API_KEY`, ...); repositories and patches carry zero secrets.
- Any runtime/asar edit backs up first (`.bak-<date>`) and includes rollback notes.
- Not every local hack is worth upstreaming (e.g. version-specific parameters); docs say which are.

## Requirements

- Windows 10/11; the locked baseline requires Node `^22.19.0 || >=24.0.0`. Follow the deployment lock for the exact version.
- The current validated baseline is Desktop 0.9.2, Core 0.1.1-rc.2, Copilot2API 0.6.1, and provider 0.2.3-cloga.3. Update the lock and pass acceptance before using another combination.
