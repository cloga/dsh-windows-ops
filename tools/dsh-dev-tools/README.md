# dsh-dev-tools

Agent-native development tools for DeepSeek Harness (DSH), aimed at a **Windows packaged edition** with a local source tree. Registers four tools so the agent can inspect and drive the dev/upgrade workflow **from inside the session**:

| Tool | What it does |
|---|---|
| `dsh_status` | Source-tree version/branch/dirty state, runtime version, patch state, A/B backup state. |
| `dsh_patch` | Manage local patches: `list` / `apply` / `rollback` (backup before change, idempotent). |
| `dsh_build` | Build a staging runtime (`<runtimeDir>.new`) from the source tree - does NOT touch the running app. |
| `dsh_upgrade` | `check` new upstream versions + `apply` a full upgrade (builds + deploys + patches + restarts via the existing updater). |

## Why

The packaged DSH on this machine installs into a source tree (`D:\deepseek-harness`) whose `resources/runtime` is built from that tree. Local customizations live as **patches** re-applied after every upgrade. Doing all of this from a terminal is awkward mid-session; these tools hand the agent a native handle on status/patch/build/upgrade.

## Configuration

Paths are resolved in this order: environment override -> `updater-config.json` -> sensible default. Env vars:

- `DSH_SOURCE_TREE` - git source tree root (default `updater-config.json:sourceTree`)
- `DSH_RUNTIME_DIR` - installed runtime dir (default `updater-config.json:runtimeDir`)
- `DSH_NODE_BIN` - node executable (default `node` from PATH)
- `DSH_GIT_BIN` - git executable, e.g. `D:\Git\cmd\git.exe` (default `git`)
- `DSH_HOME` - DSH home (default `~/.dsh`)

`updater-config.json` (if present at `$DSH_HOME/tools/dsh-updater/updater-config.json`) supplies `sourceTree`, `appDir`, `runtimeDir`, `gitExecutable`, `nodeExecutable`, `pnpmExecutable`, `bashExecutable`, `buildScript`.

## Patches

`dsh_patch` reads `$DSH_HOME/tools/dsh-updater/patches.json` (see `patches.example.json` in this package). Each entry:

```json
{
  "id": "brand-title",
  "file": "relative/path/under/DSH_SOURCE_TREE", 
  "find": "literal or regex (string is literal search; leading ~ makes it regex)",
  "replace": "replacement text"
}
```

`apply` backs up each touched file (`<file>.dshpatch-bak`) before patching, skips files that already contain the replacement (idempotent), and reports per-patch status. `rollback` restores from those backups. `list` shows the current resolved patch set from disk without touching anything.

## Install

Copy (materialized, NOT a junction) into `$DSH_HOME/profiles/web/node_modules/dsh-dev-tools/`, enable in `$DSH_HOME/cordis.patch.yml`:

```yaml
- insert:
    - id: dsh-dev-tools
      name: dsh-dev-tools
```

Run `dsh-compat-check.mjs --probe=dsh-dev-tools` before restarting, then restart the app (patches/plugins load at startup). See `tools/dsh-compat-check.mjs` in this repo for the checker.

## Lifecycle

All changes happen while the app is running are staging-only (`dsh_build` -> `<runtimeDir>.new`); the running instance is untouched. Anything that would restart the app (`dsh_upgrade apply`) uses the detached-scheduled-task pattern documented in `docs/ab-self-heal.md` - never a raw in-process restart.
