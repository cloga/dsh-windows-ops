# dsh-windows-ops

> Operational experience + reusable tools for the **Windows packaged edition of DeepSeek Harness (DSH)**.

This repository collects lessons learned, root-cause analyses, and reusable scripts from running the community-packaged Windows desktop app ([`hairyf/deepseek-harness-desktop`](https://github.com/hairyf/deepseek-harness-desktop)) with the official `@deepseek-ai/dsh` runtime (0.1.x) on real hardware.

## What's inside

| Category | Content | File |
|---|---|---|
| Startup stability | First-launch 60s timeout root cause (MCP launcher network stall) + fixes | `docs/startup-60s-timeout.md` |
| Brand / version | Window-title brand + **engine version** (`DeepSeek Harness v<version>`) patcher | `tools/patch-brand-title.mjs` |
| Vision dual-channel | Model-aware dual channel (official + vision-tool fallback) design + admission rules | `docs/vision-dual-channel.md` |
| A/B self-heal | Config snapshot + data junctions + detached scheduled-task restart + transactional upgrades | `docs/ab-self-heal.md` |
| Plugin install | Packaged-edition plugin rules (junctions ALWAYS crash → materialized copies) + compat checker | `tools/dsh-compat-check.mjs` |
| PowerShell pitfalls | 5.1 needs explicit `Add-Type System.Net.Http` (scheduled-task health checks silently fail) | `docs/powershell-5.1-pitfalls.md` |
| GitHub network | ghfast mirror git config + release/raw download script | `tools/gh-dl.ps1`, `docs/github-network.md` |
| Security | Credentials only via env; asar only via the official tool; read-only MCP by default | `docs/security-notes.md` |

## Usage

1. **Patches** (`tools/*.mjs`): run with `node <script>`; paths come from environment variables / arguments (see header comments). Nothing is hard-coded to one machine.
2. **Docs**: experience and post-mortems, with root-cause analysis and verification steps.
3. **compat-check**: zero-dependency Node script; run before installing any community plugin (static import manifest + `--probe` real import test).

## Key findings (short version)

### First-launch "The local service did not start within 60 seconds"
The desktop shell waits 60s for the web service to print `dsh web: http://...`. The `dsh-mcp-client` plugin blocks activation on `await connection.ready`, so any MCP server whose launcher stalls on the network (here: `npx @harusame64/desktop-touch-mcp`, whose launcher fetches a GitHub release **every start**, with no timeout) pushes startup past 60s. A second launch works because the release is already cached. Fix: run the local release entry directly (`node <...>/dist/server-windows.js`), or upstream fix (see PR below).

### Window title shows `— DeepSeek Harness v0.1.1-rc.2`
The official `DocumentTitle.tsx` defaults to `DSH Local Build` (a local-build marker) and supports a build-time `DSH_CLIENT_TITLE` env. `patch-brand-title.mjs` rewrites the shipped default to `DeepSeek Harness v<version>`, with the version read live from the runtime `package.json` — idempotent across upgrades.

### Model-aware vision dual channel
Image-capable models (vision-exp) get images via the official channel; text-only models (flash/pro) get a path hint + `vision` tool fallback. The admission decision must mirror the host gate's own model resolution order (picker > requestHeader > defaults) and never prefer a vision-named candidate across stale sources — a stale vision-exp in `requestHeader` made admission leak the image to the gate, which then rejected it ("model does not support image input") with no fallback ever reached.

## Upstream contributions already made

- [`tianmingwan/dsh-vision-any` PR #2](https://github.com/tianmingwan/dsh-vision-any/pull/2): model-aware admission (byName + diagnostics) + neutral system prompt
- [`Harusame64/desktop-touch-mcp` PR #586](https://github.com/Harusame64/desktop-touch-mcp/pull/586): offline-first release resolution + fetch timeout

The rest of this repo is machine-verified practice; some items map to official design seams (notes in each doc).

## Compliance

- No API keys / tokens / account info anywhere. Credentials are injected via environment variables (`GITHUB_PERSONAL_ACCESS_TOKEN`, `DEEPSEEK_API_KEY`, ...); repositories and patches carry zero secrets.
- Any runtime/asar edit backs up first (`.bak-<date>`) and includes rollback notes.
- Not every local hack is worth upstreaming (e.g. version-specific parameters); docs say which are.

## Requirements

- Windows 10/11; any Node >= 18 (override with `NODE_BIN`; tested with `D:\node.exe` layout)
- DSH desktop edition (verified on runtime 0.1.0-rc.8 / 0.1.1-rc.2); other versions verify yourself.
