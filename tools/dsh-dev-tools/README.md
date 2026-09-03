# dsh-dev-tools

Agent-native development tools for a trusted Windows DeepSeek Harness maintenance Session. Version `0.2.0` is certified against official DSH `0.1.2-rc.1` at commit `a66e4702047846cdaa10c66c9d3df3951f5ea70d`, `@deepseek-ai/dsh-tools@0.1.2-rc.1`, and `@deepseek-ai/cordis@4.0.2`.

The plugin registers five tools:

| Tool | What it does |
|---|---|
| `dsh_status` | Reports source-tree version, branch, dirty state, runtime version, patch state, and plugin import-compatibility summary. |
| `dsh_doctor` | Runs the repository doctor in report, fix, or smoke mode. |
| `dsh_patch` | Lists, applies, or rolls back reviewed local patches. |
| `dsh_build` | Builds a staging runtime at `<runtimeDir>.new` without changing the running app. |
| `dsh_upgrade` | Lists upstream versions; the retired `apply` action returns locked-installer migration guidance. |

## Compatibility and lifecycle

DSH rc.1 requires every asynchronous `ToolDefinition.execute(args, exec)` implementation to observe or forward `exec.signal` and settle after owned work reaches quiescence. The plugin delegates every process to the required `ctx.subprocess` service with explicit argv, working directory, ignored stdin, bounded stdout/stderr collection, termination grace, and cancellation signal. It awaits both the direct outcome and whole-tree `waitForExit()` before settling, then rethrows cancellation instead of reporting success.

Tool results use lossless JSON snapshot semantics aligned with `@deepseek-ai/dsh-util-values@0.1.2-rc.1`. Undefined roots or properties, sparse arrays, `-0`, non-finite numbers, symbols, exotic objects, and cycles fail loudly rather than being silently changed. Valid outputs are detached canonical JSON values.

`ctx.tools.register(...)` is already Fiber-owned by the rc.1 ToolRuntime, so registrations are direct and no redundant `ctx.effect` wrapper is added. A real Cordis/ToolRuntime lifecycle test proves all five tools disappear on Fiber disposal. These maintenance tools can modify source files, backups, staging directories, and installation state; use them only in a trusted operator Session.

Requirements:

- Node.js `^22.19.0 || >=24.0.0`.
- DSH `0.1.2-rc.1` with `@deepseek-ai/dsh-tools@0.1.2-rc.1` and `@deepseek-ai/dsh-subprocess@0.1.2-rc.1`.
- `@deepseek-ai/cordis@4.0.2`.

## Configuration

Paths resolve in this order: environment override, `updater-config.json`, then the documented fallback.

- `DSH_SOURCE_TREE` — DSH source root.
- `DSH_RUNTIME_DIR` — installed runtime directory.
- `DSH_NODE_BIN` — Node executable; defaults to `node` from `PATH`.
- `DSH_GIT_BIN` — Git executable; defaults to `git` from `PATH`.
- `DSH_HOME` — DSH home; defaults to `~/.dsh`.

`$DSH_HOME/tools/dsh-updater/updater-config.json` may define `sourceTree`, `appDir`, `runtimeDir`, `gitExecutable`, `nodeExecutable`, `pnpmExecutable`, `bashExecutable`, and `buildScript`.

## Patches

`dsh_patch` reads `$DSH_HOME/tools/dsh-updater/patches.json`. Each entry follows this form:

```json
{
  "id": "brand-title",
  "file": "relative/path/under/DSH_SOURCE_TREE",
  "find": "literal or ~regular expression",
  "replace": "replacement text"
}
```

Patch targets must be non-absolute existing files whose canonical paths remain below the canonical `DSH_SOURCE_TREE`; traversal and symlink escapes are rejected, with case-insensitive containment on Windows. `find` must be non-empty. `apply` creates `<file>.dshpatch-bak` before the first write, skips content that already contains the replacement, and reports every result. `rollback` restores available backups. Every write rechecks cancellation first, and an already-aborted apply or rollback performs no writes. `list` does not modify files.

## Install without activation

Copy a materialized package directory into `$DSH_HOME/profiles/web/node_modules/dsh-dev-tools/` and add its reviewed composition row:

```yaml
- insert:
    - id: dsh-dev-tools
      name: dsh-dev-tools
```

Run `dsh-compat-check.mjs --probe=dsh-dev-tools` and inspect the composed configuration before activation. Do not restart or replace DSH while another Session is running. If a restart is required, enumerate the current running Sessions and obtain explicit approval for that exact interruption set.

## Verification

From the Windows Ops repository root:

```powershell
$env:DSH_RC1_ROOT = 'C:\path\to\deepseek-harness-rc1'
node --test tests\dsh-dev-tools.test.mjs
node --check tools\dsh-dev-tools\index.js
```

The compatibility test requires the exact official rc.1 commit, checks ToolRuntime and subprocess service contracts, boots a real rc.1 Cordis/ToolRuntime lifecycle harness, verifies whole-tree cancellation quiescence, exercises path containment and already-aborted zero-write behavior, and rejects lossy JSON values. The plugin does not require a Host restart for these source-level tests.

## Upgrade safety

`dsh_build` remains staging-only. `dsh_upgrade apply` is intentionally retired; use the check-first locked installer or Desktop core manager. Restart only through the repository's live-Session guard after reviewing the resulting plan.
