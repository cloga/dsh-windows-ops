# tools/dsh-updater

- `patch-worker.mjs` - the core patcher (worker.cjs + applyBrand + applyAdapterPatches).
  Called by `dsh-doctor.mjs --fix` (patches check). Invoke directly:
  `node patch-worker.mjs "<CORE_NM>\@deepseek-ai\dsh-host-directory-picker-native\lib\worker.cjs"`
- `dsh-patch-asar-official.mjs` - LEGACY (Tauri shell has no app.asar). Kept for the
  old source-tree build only. Requires the `@electron/asar` tool (tools/asar-tool) which
  is NOT bundled here - install it separately if you ever need the legacy path.
- apply-update / swap-commit / run-update-visible - retired with dsh-swap.ps1 (core
  upgrades are managed by the Tauri shell itself).
