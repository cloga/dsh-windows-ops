# Optional DSH companion suite on Windows

The optional companion suite is a single **installation entry**, not a merged plugin. It stages three independently versioned Web Profile Bundles:

| Bundle | Responsibility | Important boundary |
|---|---|---|
| [`dsh-github-copilot`](https://github.com/cloga/dsh-github-copilot) | GitHub Copilot sign-in, account-aware route reconciliation, Copilot tool-schema compatibility, and provider-hosted search | Does not own DSH's general model adapter or unrelated automation |
| [`dsh-cron`](https://github.com/cloga/dsh-cron) | Session-owned scheduled prompts and Web task/history UI | Every run is a real model turn with the Session's standing tool permissions |
| [`dsh-playwright-host`](https://github.com/cloga/dsh-playwright-host) | Host-scope Microsoft Playwright MCP over isolated Edge | One shared MCP browser process is visible to concurrent DSH Sessions |

Keeping the packages separate preserves focused security review, independent upgrades and rollback, and compatibility evidence. The suite installer only coordinates their installation into one Profile. It does not copy source between repositories, replace Core, or make Cron and Playwright part of the locked Copilot baseline.

## Check first

The default action is read-only:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-optional-companion-suite.ps1
```

It reports the declared source, bundle layer, lockfile evidence, and resolved installed package version for each component. A locally cached Copilot tarball is also hash-checked; a canonical Release URL declaration is identified but cannot be byte-hashed without downloading it. Check mode does not access GitHub, install packages, or restart DSH.

Use a non-default DSH home or Profile explicitly when needed:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-optional-companion-suite.ps1 `
  -DshHome C:\path\to\.dsh -Profile web
```

## Stage all three bundles

After reviewing the check result, first ensure the target Web Profile already exists and its normal Desktop/Core setup is healthy. The installer deliberately refuses to bootstrap an absent Profile because doing so can introduce unrelated package build approvals.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-optional-companion-suite.ps1 -Apply
```

The installer:

1. downloads the pinned `dsh-github-copilot` Release tarball into `$DSH_HOME/downloads`;
2. verifies its committed SHA-256 before installation;
3. snapshots the Profile manifest, lockfile, and pnpm workspace policy under `$DSH_HOME/suite-backups`;
4. installs Cron and Playwright from reviewed commit SHAs in one coordinated `dsh plugin --profile web add ...` operation;
5. verifies the exact dependency sources, Copilot artifact hash, and all three bundle layers;
6. restores the previous Profile files and reconciles `node_modules` from the prior lockfile if installation or post-check fails;
7. returns a JSON status document, including the backup path after mutation.

The pinned set is deliberately conservative:

- `dsh-github-copilot` `0.3.0-cloga.15` from its immutable GitHub Release;
- `dsh-cron` `0.3.3` at commit `f5e8df45496523c98874e6f484b886941683f7d6`;
- `dsh-playwright-host` `0.1.1` at commit `86ca74d4fdf89d6aa6036f273eb8acab4adae34f`.

Changing these pins requires independent compatibility review of each repository. The installer does not silently track a tag, default branch, or `latest` label.

## Activation safety

Installation only stages Profile changes. The script never stops or restarts Desktop or DSH. Before activation:

1. inspect `dsh --profile web --dump-config`;
2. enumerate running Sessions;
3. do not restart while another Session is running unless the user explicitly accepts interruption of the exact listed Sessions;
4. after an authorized restart, create a new Session and verify Copilot sign-in/model selection, `cron_list`, and `mcp__playwright__browser_snapshot` separately.

Playwright's `--isolated` flag protects the user's everyday Edge profile, but all DSH Sessions still share the Host-owned MCP browser process. Use it from one Session at a time and avoid consequential authenticated flows.

## Remove the optional suite

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-optional-companion-suite.ps1 -Action Remove
```

Removal is idempotent for complete, partial, or already-absent suite installs. It removes only suite dependencies that are present, cleans stale suite bundle entries, keeps a rollback backup, and never restarts the Host. It does not delete Cron task/history data, Copilot credentials, the persisted Copilot tarball, npm/pnpm caches, or browser artifacts.
