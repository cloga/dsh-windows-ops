# Optional DSH companion suite on Windows

The optional companion suite is a single **installation entry**, not a merged plugin. It stages three independently versioned Web Profile Bundles:

| Bundle | Responsibility | Important boundary |
|---|---|---|
| [`dsh-github-copilot`](https://github.com/cloga/dsh-github-copilot) | GitHub Copilot sign-in, account-aware route reconciliation, Copilot tool-schema compatibility, and provider-hosted search | Does not own DSH's general model adapter or unrelated automation |
| [`dsh-cron`](https://github.com/cloga/dsh-cron) | Session-owned scheduled prompts and Web task/history UI | Every run is a real model turn with the Session's standing tool permissions |
| [`dsh-playwright-host`](https://github.com/cloga/dsh-playwright-host) | Host-scope Microsoft Playwright MCP over isolated Edge | One shared MCP browser process is visible to concurrent DSH Sessions |

Keeping the packages separate preserves focused security review, independent upgrades and rollback, and compatibility evidence. The suite installer only coordinates their installation into one Profile. It does not copy source between repositories, replace Core, or make Cron and Playwright part of the locked Copilot baseline.

The authoritative whole-machine deployment path remains
`tools\install-windows-copilot.ps1 -IncludeCompanionSuite`, with its exact
Desktop lock. For an already installed Desktop, the authoritative plugin-only
path is `tools\install-optional-companion-suite.ps1`. It calls the same
deployment module and lock, but deliberately does not install, downgrade, or
attest an exact Desktop build; replace Core; mutate global packages or legacy
gateway state; change settings or credentials; or restart a process.

## Check first

The default action is read-only:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-optional-companion-suite.ps1
```

It reads component names, versions, source identities, immutable artifact
metadata, and the required three-member suite shape from
`deployments/windows-copilot.lock.json`. The script carries no independent
package pins. Compatibility is evaluated against the installed
`@deepseek-ai/dsh` Core, `@deepseek-ai/cordis`, and required authorization,
pi-ai provider, Web-tool, and MCP-client package APIs. Apply also reads each
packed plugin's peer declarations and evaluates them with prerelease-aware
SemVer rules; unsupported range syntax fails closed. The Desktop version is not
part of this decision, so a newer Desktop patch does not block plugins when it
still carries the reviewed Core/API set. Check mode does not access GitHub,
install packages, or restart DSH.

Use a non-default DSH home or Profile explicitly when needed:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-optional-companion-suite.ps1 `
  -DshHome C:\path\to\.dsh -Profile web
```

To preflight exact artifacts already downloaded from their immutable Releases:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-optional-companion-suite.ps1 `
  -Action Check -ArtifactDirectory C:\path\to\locked-artifacts
```

`-ManifestPath` can point to an explicitly reviewed copy of the deployment lock for replay or testing. Missing, malformed, mutable, or incomplete component metadata fails closed.

## Stage all three bundles

After reviewing the check result, first ensure the target Web Profile already exists and its official Desktop-managed runtime is healthy. The installer deliberately refuses to bootstrap an absent Profile because doing so can introduce unrelated package build approvals.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-optional-companion-suite.ps1 `
  -Apply -ArtifactDirectory C:\path\to\locked-artifacts `
  -AcknowledgeLiveSessionIds <exact-running-session-id>
```

Apply is a maintenance operation: it briefly parks the Web Profile's complete
`node_modules` tree, so lazy imports in a running Host would be temporarily
unavailable. Enumerate `session/list` immediately before Apply and obtain direct
user approval for the exact running Session IDs. The installer fails closed
when the live set and `-AcknowledgeLiveSessionIds` differ; pass no IDs only when
the live set is empty. It still does not stop or restart Desktop or the Host.

The plugin-only installer:

1. verifies installed Core, Cordis, and required plugin API manifests;
2. stages each immutable Release artifact before taking a Profile snapshot;
3. verifies every artifact's size and SHA-256 plus its pinned `SHA256SUMS` identity and matching entry;
4. snapshots only the Web Profile manifest, lockfile, workspace policy, three package directories, and artifact targets;
5. records and protects the eight official Desktop Profile links;
6. parks the complete original `node_modules`, lets pnpm update only the Profile
   manifest/lockfile against a fresh layout, restores the original tree, and
   physically materializes only the three exact packages;
7. verifies all three packages' complete byte closure, activation entries, and
   actual Copilot/Cron/MCP-client module imports through the restored
   Profile/runtime dependency resolution;
8. restores the complete snapshot if package installation, link preservation, or post-check fails;
9. returns a JSON receipt without restarting Desktop or the Host.

Run the same compatibility and installed-closure checks without mutation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-optional-companion-suite.ps1 -Action Verify
```

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
