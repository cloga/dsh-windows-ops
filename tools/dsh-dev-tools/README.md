# dsh-dev-tools

Agent-native development tools for a trusted Windows DeepSeek Harness maintenance Session. Version `0.3.0` is certified against official DSH `0.1.6-alpha.1` at commit `0a15e36e7f82b6ed45af6fa9759f29b40dcd965d`, `@deepseek-ai/dsh-tools@0.1.6-alpha.1`, `@deepseek-ai/dsh-subprocess@0.1.6-alpha.1`, and `@deepseek-ai/cordis@4.0.2`.

The plugin registers five tools:

| Tool | What it does |
|---|---|
| `dsh_status` | Reports source-tree version, branch, dirty state, runtime version, patch state, and plugin import-compatibility summary. |
| `dsh_doctor` | Runs the repository doctor in report, fix, or smoke mode. |
| `dsh_patch` | Lists, applies, or rolls back reviewed local patches. |
| `dsh_build` | Builds a staging runtime at `<runtimeDir>.new` without changing the running app. |
| `dsh_upgrade` | Lists upstream versions; the retired `apply` action returns locked-installer migration guidance. |

## Compatibility and lifecycle

DSH 0.1.6 keeps the service and package names `ctx.subprocess` and `@deepseek-ai/dsh-subprocess`; the local provider remains the separate `@deepseek-ai/dsh-subprocess-local` package. The seam now describes provider-managed process ranges, removes the ordinary handle's public `pid`, adds an optional control pipe and terminal-environment API, and allows `done`/`waitForExit()` to report provider failures. This plugin uses only the stable collected-output subset. It delegates every process to `ctx.subprocess` with explicit argv, working directory, ignored stdin, bounded stdout/stderr collection, termination grace, and the caller's cancellation signal. It awaits both the direct outcome and unbounded managed-range `waitForExit()` before settling, rethrows cancellation only after quiescence, and fails explicitly if collected output became lossy.

Tool results use lossless JSON snapshot semantics aligned with `@deepseek-ai/dsh-util-values@0.1.6-alpha.1`. Undefined roots or properties, sparse arrays, `-0`, non-finite numbers, symbols, exotic objects, and cycles fail loudly rather than being silently changed. Valid cross-realm plain JSON is accepted, every property is read once, and the iterative walk handles deep values without recursive stack exhaustion.

`ToolRunContext` still carries `exec.signal`, `deferContext(...)`, and `concludeTurn()`. DSH 0.1.6 adds PTC binding-time schema identity and replaces the old `codeRuntime` transport with `ctx.ptcRuntime`; strict sandbox escalation and one-call Host approval are owned by the PTC transport and deployment policy, not by individual tools. A PTC worker sends a lossless-JSON binding call over its control channel; `NodePtcRuntime` invokes the Host binding, and the binding dispatches the registered body through the Host `ToolRuntime` scheduler. The `dsh-dev-tools` module and tool functions therefore execute in the Cordis Host process, not inside the isolated Node PTC worker. The plugin does not add `sandbox_permissions`, Host-grant, PTC, Sandbox, Shell, or workflow dependencies. Calls dispatched through native, PTC, or `workflow-ptc` surfaces retain the same ToolRuntime cancellation signal.

Sandbox `confine(...)` and Shell background `start(...)` are now asynchronous and cancellable. `dsh-dev-tools` does not call either seam: foreground maintenance commands continue to use the lower-level subprocess capability, avoiding an accidental second policy layer. Node PTC's model-visible `process.env` starts empty while native startup paths remain available to the worker. That empty dictionary applies only to model-written code in the worker; it does not replace the Host `process.env` used when the binding invokes this plugin. Child maintenance commands receive the subprocess provider's credential- and `DSH_*`-scrubbed Host environment unless this plugin explicitly supplies an override.

`ctx.tools.register(...)` remains Fiber-owned by the 0.1.6 ToolRuntime, so registrations are direct and no redundant `ctx.effect` wrapper is added. A real Cordis/ToolRuntime lifecycle test proves all five tools disappear on Fiber disposal. The source-seam test also pins `workflow-ptc` cleanup: cancellation aborts the program, waits for pending child startup/disposal, and settles only after every admitted child is disposed. These maintenance tools can modify source files, backups, staging directories, and installation state; use them only in a trusted operator Session.

Requirements:

- Node.js `^22.19.0 || >=24.0.0`.
- DSH `0.1.6-alpha.1` with `@deepseek-ai/dsh-tools@0.1.6-alpha.1` and `@deepseek-ai/dsh-subprocess@0.1.6-alpha.1`.
- `@deepseek-ai/cordis@4.0.2`.

## Configuration

Paths resolve in this order: environment override, `updater-config.json`, then the documented fallback.

These values are Cordis Host plugin configuration. `DSH_HOME`, executable paths, source/runtime paths, and build settings are captured when the Host loads this module; a PTC worker does not evaluate the module or supply its empty `process.env` to these lookups. Reload the plugin after changing an environment override or `updater-config.json`.

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
$env:DSH_016_ROOT = 'C:\path\to\deepseek-harness-0.1.6-alpha.1'
node --test tests\dsh-dev-tools.test.mjs
node --check tools\dsh-dev-tools\index.js
```

The compatibility test requires exact official commit `0a15e36e7f82b6ed45af6fa9759f29b40dcd965d`. It checks ToolRuntime, subprocess, async Sandbox/Shell, Node PTC empty-environment, workflow cleanup, and lossless JSON source contracts; boots a real 0.1.6 Cordis/ToolRuntime lifecycle harness; verifies managed-range cancellation quiescence; exercises path containment and already-aborted zero-write behavior; and rejects lossy JSON or collected subprocess output. The plugin does not require a Host restart for these source-level tests.

## Upgrade safety

`dsh_build` remains staging-only. `dsh_upgrade apply` is intentionally retired; use the check-first locked installer or Desktop core manager. Restart only through the repository's live-Session guard after reviewing the resulting plan.
