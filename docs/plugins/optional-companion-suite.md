# Optional DSH companion suite on Windows

The optional companion suite is a single **installation entry**, not a merged plugin. It stages three independently versioned Web Profile Bundles:

| Bundle | Responsibility | Important boundary |
|---|---|---|
| [`dsh-github-copilot`](https://github.com/cloga/dsh-github-copilot) | GitHub Copilot sign-in, account-aware route reconciliation, Copilot tool-schema compatibility, and provider-hosted search | Does not own DSH's general model adapter or unrelated automation |
| [`dsh-cron`](https://github.com/cloga/dsh-cron) | Session-owned scheduled prompts and Web task/history UI | Every run is a real model turn with the Session's standing tool permissions |
| [`dsh-playwright-host`](https://github.com/cloga/dsh-playwright-host) | Host-scope Microsoft Playwright MCP over isolated Edge | One shared MCP browser process is visible to concurrent DSH Sessions |

Keeping the packages separate preserves focused security review, independent upgrades and rollback, and compatibility evidence. The suite installer only coordinates their installation into one Profile. It does not copy source between repositories, replace Core, or make Cron and Playwright part of the locked Copilot baseline.

The authoritative end-to-end deployment path is
`tools\install-windows-copilot.ps1 -IncludeCompanionSuite`, which includes all
three packages in the main installer backup and rollback transaction. This
narrow script remains useful for Profile-only maintenance but reads the same
deployment lock and owns no independent version pins.

## Check first

The default action is read-only:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-optional-companion-suite.ps1
```

It reads component names, versions, source identities, immutable artifact metadata, and the required three-member suite shape from `deployments/windows-copilot.lock.json`. The script carries no independent package pins. It reports the derived release identity, bundle layer, lockfile evidence, and resolved installed package version for each component. A locally referenced suite tarball is hash-checked; a canonical Release URL declaration is identified but cannot be byte-hashed without downloading it. Check mode does not access GitHub, install packages, or restart DSH.

Use a non-default DSH home or Profile explicitly when needed:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-optional-companion-suite.ps1 `
  -DshHome C:\path\to\.dsh -Profile web
```

`-ManifestPath` can point to an explicitly reviewed copy of the deployment lock for replay or testing. Missing, malformed, mutable, or incomplete component metadata fails closed.

## Stage all three bundles

After reviewing the check result, first ensure the target Web Profile already exists and its official Desktop-managed runtime is healthy. The installer deliberately refuses to bootstrap an absent Profile because doing so can introduce unrelated package build approvals.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-optional-companion-suite.ps1 -Apply
```

The installer:

1. downloads each Release artifact selected by the deployment lock into `$DSH_HOME/downloads`;
2. verifies every artifact's size and SHA-256 plus the identity and matching entry of its pinned `SHA256SUMS`;
3. snapshots the Profile manifest, lockfile, and pnpm workspace policy under `$DSH_HOME/suite-backups`;
4. installs the three verified local artifacts in one coordinated `dsh plugin --profile web add ...` operation;
5. verifies the exact dependency sources and all three bundle layers;
6. restores the previous Profile files and reconciles `node_modules` from the prior lockfile if installation or post-check fails;
7. returns a JSON status document, including the backup path after mutation.

The authoritative deployment lock owns the complete pinned set. Top-level `companionSuite.members` must declare exactly one required member sourced from `components.copilotIntegration` and two optional members sourced from `profile.optionalOverlays`; names, roles, and `identitySource` values are cross-checked before any action. Changing that contract requires independent compatibility review. The installer does not silently track a tag, default branch, or `latest` label.

## Activation safety

Installation only stages Profile changes. The script never stops or restarts Desktop or DSH. Before activation:

1. inspect `dsh --profile web --dump-config`;
2. enumerate running Sessions;
3. do not restart while another Session is running unless the user explicitly accepts interruption of the exact listed Sessions;
4. after an authorized restart, create a new Session and verify Copilot sign-in/model selection, `cron_list`, and `mcp__playwright__browser_snapshot` separately.

Playwright's `--isolated` flag protects the user's everyday Edge profile, but all DSH Sessions still share the Host-owned MCP browser process. Use it from one Session at a time and avoid consequential authenticated flows.

## Remove the optional overlays

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-optional-companion-suite.ps1 -Action Remove
```

Removal is idempotent for complete, partial, or already-absent optional-overlay installs. It removes only `dsh-cron` and `dsh-playwright-host` dependencies that are present, cleans only their stale bundle entries, keeps a rollback backup, and never restarts the Host. The required `dsh-github-copilot` dependency and bundle are outside removal scope; its artifact and credentials are also preserved. If post-removal verification detects any change to the required Copilot state, the Profile backup is restored. Removal does not delete Cron task/history data, npm/pnpm caches, or browser artifacts.
