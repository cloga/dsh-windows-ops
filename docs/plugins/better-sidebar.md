# DSH Better Sidebar on Windows

[`dsh-better-sidebar`](https://github.com/omdsh-dev/DSH-better-sidebar) is an optional Web-profile workbench for DeepSeek Harness. It adds a right-side and bottom-panel workspace with a file tree, CodeMirror editing, Markdown/Mermaid, image, HTML and PDF preview, Git/file-change views, a terminal, an embedded browser, side chat, and task/subagent views. It is not part of the locked Windows Copilot baseline.

## Reviewed identity

- Source: `omdsh-dev/DSH-better-sidebar`
- Release: `v0.18.0`
- Release commit: `9e1a03452794532cda1f6ac677b72579dff48dfc`
- npm package: `dsh-better-sidebar@0.18.0`
- Locally verified npm tarball SHA-256: `ed721de536421841ecf48bddccd7249aed85473a2cff81c436038f593a4b873b`
- Tested host: DSH `0.1.2-rc.1`, Node `24.19.0`, pnpm `11.7.0`, Windows x64

The packed manifest has no install lifecycle scripts. `node-pty` does run its own dependency install/postinstall scripts and therefore requires an explicit `allowBuilds` entry in the Web profile.

## Installation

Use an exact version rather than an unbounded tag:

```powershell
dsh plugin --profile web add dsh-better-sidebar@0.18.0
```

For pnpm 11, ensure the Web profile's `pnpm-workspace.yaml` contains:

```yaml
allowBuilds:
  node-pty: true
  protobufjs: true
minimumReleaseAgeExclude:
  - dsh-better-sidebar
```

The package declares its own `dsh.bundle.patch`, so the plugin command adds `dsh-better-sidebar` to `dsh.profile.bundles`. Do not also add a manual `better-sidebar` row to `cordis.patch.yml`; duplicate mounts can register the sidebar routes twice.

When the public npm registry is unavailable, preserve the exact package artifact in the DSH artifact store and install that `.tgz` path. Do not silently fall back to `0.17.1`: release `0.18.0` is the package line declaring DSH `0.1.2-rc.1` peers.

A new install includes a Host half. Restart the DSH Host before functional verification. Follow the repository live-session rule: query `session/list`, obtain explicit acknowledgement for every running Session, then restart and hard-refresh the existing `http://127.0.0.1:3080` page.

## Validation recorded here

The Windows profile resolved `dsh-better-sidebar@0.18.0`; its Host entry imported successfully with `node tools/dsh-compat-check.mjs web --probe=dsh-better-sidebar --json`. The composed profile dump contained the package-owned `better-sidebar` row. This is L2 evidence only until a restart permits composition activation and a real file-preview smoke test.

## Security boundary

Treat the plugin as a trusted-operator capability rather than a cosmetic theme:

- The file workbench can read, create, edit, upload, rename, and delete files available to the DSH Host.
- The terminal uses native `node-pty` and can spawn a real shell. Optional model-facing terminal tools must remain disabled unless explicitly needed.
- Git views spawn the system `git` executable for repository operations.
- Reveal/open actions can launch Explorer, VS Code, or another registered system handler.
- The embedded browser and remote Markdown assets can make external network requests. Do not preview untrusted active HTML as if it were inert text.
- The package does not capture the screen or reuse an existing browser profile, but its broad local filesystem and process access justify a `conditional` recommendation.

## Acceptance after restart

1. Confirm the `better-sidebar` Cordis row activates without duplicate route/service errors.
2. Open a harmless text or Markdown fixture from the workspace file tree and verify right-side rendering.
3. Edit and save a disposable fixture, then verify the exact bytes on disk.
4. Open and close a terminal tab and confirm the PTY process exits during cleanup.
5. Stop or remove the plugin and confirm its panel, routes, and services disappear.

Do not promote the catalog entry beyond L2 until those checks are recorded.

## Rollback

```powershell
dsh plugin --profile web remove dsh-better-sidebar
```

Then remove any stale manual `better-sidebar` block from the Web profile's `cordis.patch.yml`, restart the Host under the live-session safety rule, and hard-refresh the existing GUI. Removing the plugin must not delete workspace files; inspect and preserve unsaved editor buffers before rollback.
