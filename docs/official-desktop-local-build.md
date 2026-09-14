# Build the official Electron Desktop locally on Windows

Issue #143 adds a check-first, source-verifying path for organizations that can
reach GitHub and the normal package/runtime sources used by the upstream build,
but cannot retrieve the vendor release from `download.deepseek.com`.

This procedure builds **unmodified official**
`deepseek-ai/deepseek-harness` source. It does not redistribute binaries, fork or
vendor Core, bypass an endpoint, weaken pnpm's supply-chain policy, install an
application, stop a process, or touch an existing DSH profile.

## Pinned official identity

| Field | Required value |
|---|---|
| Repository | `https://github.com/deepseek-ai/deepseek-harness.git` |
| Tag | `dsh-v0.1.5-rc.2` |
| Commit | `fb2c4b9e698e30edb738bca4cf0618587db7d203` |
| Tree | `bd7dd6d90010a35d3d6ff9f12c1f6207d5b6fe38` |
| Root/Desktop/Desktop Host version | `0.1.5-rc.2` |
| Package manager | exact direct `pnpm@11.7.0`, auto-resolved or selected with `-PnpmPath` |
| Node engine | `^22.19.0 || >=24.0.0` |

The commit and tree were resolved from the official GitHub tag/ref and commit
objects on **September 14, 2026**. The script independently runs local
`git ls-remote --refs` and refuses a tag that does not resolve to the pinned
commit. After checkout it also requires the exact tree and a clean worktree.

## Storage boundary

All source, dependency state, downloads, caches, build output, isolated DSH home,
and receipts belong below a caller-selected, local, non-cloud-synchronized root.
The default is:

```text
C:\tmp\dsh-official-desktop-build\work
```

The tool rejects relative paths, UNC/network or non-fixed drives, a root equal
to, inside, or containing this operations repository, the community Desktop
AppData tree, `$HOME\.dsh`, an active `DSH_HOME`, known
OneDrive/Dropbox/Google Drive environment roots, and path segments that look
cloud synchronized. It walks existing ancestors plus the root, source,
tool-state, and receipt paths and rejects reparse points. A newly created root
must be empty and becomes tool-owned. Choose another local root if corporate
folder redirection makes `C:\tmp` synchronized.

## Actions

### Check (default, read-only)

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\build-official-desktop.ps1
```

Check validates the embedded manifest and policy, safe build root, Git, Node,
the selected direct pnpm runner, exact pnpm 11.7.0, Node engine, and the official remote tag-to-commit mapping. It uses an explicitly supplied absolute `-PnpmPath` or auto-resolves `pnpm`; if no direct executable is available it reports `exact-pnpm-unavailable` without invoking Corepack. It reports
only whether the existing community Desktop data directory is present; it does
not enumerate private data, inspect or stop live processes, clone, install,
build, launch, or write the build root.

### Prepare

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\build-official-desktop.ps1 -Action Prepare `
  -BuildRoot C:\tmp\dsh-official-desktop-build\work
```

Prepare requires a new source directory, clones/fetches the exact tag with the
resolved system/community-bundled Git executable, disables system/global Git
configuration and hooks for each Git command, checks out the pinned commit
detached, verifies the canonical worktree/Git directory and exact origin, and
invokes the exact direct package manager reported by Check as `pnpm.cmd install --frozen-lockfile`.
Every pnpm 11 operation receives the approved `-Registry` through
`PNPM_CONFIG_REGISTRY`; `npm_config_registry` alone is ignored by this pnpm
version. Store, cache, state, and user-config paths also use the supported
`PNPM_CONFIG_*` names. The npm-compatible variables are retained for child tools,
while the pinned seed source routing remains temporary and separately attested.

No portable Git/Node/pnpm download is introduced by this repository. Writable
home, AppData, Corepack, pnpm store/home, npm cache/config, XDG state/cache, and
temporary locations are redirected below the selected root. Dangerous inherited
Node, npm script-shell, Corepack-integrity, Git repository/config-injection, SSH,
and askpass variables are removed before every child process; existing proxy and
TLS environment variables remain available, but command output and receipts do
not record their values. The isolated environment sets `CI=true`, which the
pinned upstream `scripts/install-lefthook.mjs` explicitly recognizes to skip hook
installation, so the frozen install cannot modify repository hooks or local Git
configuration. Upstream's own preparation may later download its
pinned Node runtime and package content; those operations retain upstream TLS,
checksum, lockfile, release-age, lifecycle-script, and integrity policies.

### Verify

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\build-official-desktop.ps1 -Action Verify `
  -BuildRoot C:\tmp\dsh-official-desktop-build\work
```

Verify performs no fetch, install, or configuration writes. It requires the
prepared checkout to be clean and pinned to the expected commit/tree, validates
its canonical Git directory, exact origin and lack of custom hooks, checks all
three versioned manifests plus package-manager/engine declarations, hashes
`pnpm-lock.yaml`, and compares the complete current Windows-target inventory to
the newest existing Prepare or Build receipt. It fails if no receipt exists and
never overwrites or creates a verification baseline.

### Build preparation (no GUI, installer, or installation)

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\build-official-desktop.ps1 -Action Build `
  -BuildRoot C:\tmp\dsh-official-desktop-build\work
```

Build repeats the frozen install, runs the official focused Vitest selection
for `apps/desktop` and `apps/desktop-host`, and then runs the official
`prepare:desktop` pipeline. It rechecks HEAD, tree, clean status, and the
lockfile hash after every install/test/build command. This is deliberately a
preparation boundary: it does not launch Electron or
install/restart/uninstall anything. On the reviewed corporate machine, the
unmodified frozen install and full repository build passed; the focused Desktop
run initially passed 81 of 82 tests with one five-second macOS-signature timing
failure. The tool permits one bounded retry only when the captured output proves
that exact test is the sole failure and the summary is exactly 81/82; it then
runs only `apps/desktop/tests/macos-signature.spec.ts --maxWorkers=1`, records
both commands, and requires the focused summary to be exactly 9/9. Every other
failure, or a failed/malformed retry, remains fatal.

The seed preparation routes npm through two exact source literals: the pnpm CLI
`--config.registry` argument and `NPM_CONFIG_REGISTRY`. The default is
`https://registry.npmjs.org/`. An explicit `-Registry` may select another
absolute HTTPS URL with no credentials, query, or fragment. For a non-default
registry the tool requires the pinned `prepare-seed.ts` SHA-256
`2c2050620aa51ae0eabe9e15303c8ceedc08706378c88f2dac4564470201327e` and
exactly two literals, replaces both only around the official `prepare:desktop`
command, records the patched hash, and restores the original bytes in `finally`
on success or failure. It then revalidates HEAD, tree, clean status, and the
lockfile. The receipt labels this as a registry-routing deviation only; frozen
lock and integrity checks remain retained. Any leftover source edit causes the
next run to fail closed.

The JSON receipt records source tag/commit/tree, lockfile SHA-256, Node/pnpm
versions, exact argument arrays and exit codes, artifact hashes, isolated
`DSH_HOME`, and the signing boundary. Its self-hash detects accidental
corruption, not malicious authenticity; Verify independently enforces the pinned
policy, exact command schema, current source state, and complete artifact
inventory.

## PackageLocal (unsigned, local identity, no updater)

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\build-official-desktop.ps1 -Action PackageLocal `
  -BuildRoot C:\tmp\dsh-official-desktop-build\work `
  -Registry https://registry.npmjs.org/
```

`PackageLocal` deliberately performs the complete Build sequence first and then
packages, rather than trusting an ambiguous old build receipt. It removes a
stale artifact directory only after proving that the target is below the pinned
source and contains no reparse points. It writes a deterministic external
configuration below `tool-state` which imports upstream
`apps/desktop/electron-builder.config.mjs`, then overrides only:

- app ID `local.cloga.dsh-official-source-build`;
- visible product/executable/window branding `DeepSeek Harness`;
- packaged metadata name `dsh-local-build`, preserving local provenance and preventing Electron identity from falling back to `@deepseek-ai/dsh-desktop`;
- the official `apps/web/public/favicon.svg` as the Windows package icon;
- artifact name `dsh-local-build-${version}-win-${arch}.${ext}`;
- `publish: null`;
- `win.forceCodeSigning: false`; and
- `win.signtoolOptions: undefined`.

The command sets the local app ID and a non-routable test origin so upstream's
default import can evaluate, clears target and signing variables, and invokes
exactly `pnpm.cmd exec electron-builder --config <overlay> --win --x64 --publish never` using the direct executable pinned in the receipt. It never calls an official package wrapper or signer.
The expected installer is
`dsh-local-build-0.1.5-rc.2-win-x64.exe`.

Before writing a `local-build-complete` receipt, the tool requires a clean pinned
source, unsigned installer and application executable, no embedded
`app-update.yml`, seed release `0.1.5-rc.2`, protocol 3, Node 24.17.0 and pnpm
11.7.0. It records hashes for the installer, `app.asar`, executable, complete
seed tree and overlay, plus the complete safe target inventory. The boundary
flags state `officialIdentityClaim=false`, `officialSignature=false`, and
`updateChannel=false`. `Verify` validates this receipt strictly and never
overwrites it.

This is a local derivative package from official source, not a vendor-signed
release. Its local app ID, package name, artifact name, and receipt retain that
provenance even though its visible branding and icon match DeepSeek Harness.
The packaging command itself does not install or launch it, touch a live DSH
home, or write outside the isolated build root.

## One-command side-by-side install

The supported installation entry point is check-first:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\install-official-desktop-local.ps1
```

Default `Check` calls the build tool's own `Check` and only inspects the selected
paths, existing local install receipt, uninstall registry entries, local
shortcuts, and processes whose executable is below the local install root. It
creates no directory, performs no build or install, and stops no process.

Apply is explicit and acknowledges the unsigned local package:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\install-official-desktop-local.ps1 -Apply `
  -AcknowledgeUnsignedLocalBuild `
  -BuildRoot C:\tmp\dsh-official-desktop-build\work `
  -Registry https://registry.npmjs.org/
```

Defaults are `%LOCALAPPDATA%\Programs\DSH Local Build` for the application and
`%LOCALAPPDATA%\DSH Local Build` for isolated data. Apply refuses relative,
network, cloud-synchronized, reparse, overlapping, command-metacharacter, live
community-data, or repository paths. It also refuses any running executable
below the local install root; it never stops, restarts, or launches a process.

Apply invokes a fresh `PackageLocal`, validates its receipt again, then reads the
installer path and hashes only from that receipt. It rechecks the exact pinned
source identity, registry, unsigned/no-update local app identity, seed protocol
and Node/pnpm versions, and current installer/unpacked executable bytes. It
preserves a versioned installer copy below `DataRoot\artifacts`, invokes NSIS
with argument array `/S`, `/D=<InstallRoot>` (destination last), and requires
exit code zero. A successful postcheck requires:

- installed `DeepSeek Harness.exe`, unsigned, with ProductName,
  FileDescription, and InternalName `DeepSeek Harness` and FileVersion
  `0.1.5-rc.2`;
- its SHA-256 exactly equal to the packaged `win-unpacked` executable;
- embedded `desktop-release.json` at protocol 3 with Node 24.17.0 and pnpm
  11.7.0, and no `app-update.yml`;
- one or more identical local NSIS entries named `DeepSeek Harness 0.1.5-rc.2`,
  all sharing one uninstall command rooted in the local install directory; and
- any pre-existing community Desktop registration still present.

The tool writes `DeepSeek Harness Local Build.cmd` in the install directory. It
sets `DSH_HOME=<DataRoot>\harness-home` and passes
`--user-data-dir=<DataRoot>\electron-user-data`, but does not launch it. It
replaces only installer-created Desktop/Start Menu shortcuts whose existing
target is already below the local install root, and identifies them as an
unsigned local source build. The atomic install receipt records source/build
receipt identity, installer and installed hashes, roots, local app identity,
unsigned/no-update status, uninstall command, community retention, and its own
hash; it contains no credentials or Session contents.

An exact existing receipt/install is idempotently reverified and repairs only
the launcher and local shortcuts without rerunning the installer. Owned DataRoot
and InstallRoot trees are recursively checked for reparse points before this
fast path and again before writes. Repeated hashes and owned receipt snapshots
detect ordinary concurrent changes. An adversarial same-user process capable of
precisely replacing files between checks (an ABA race) is outside this local
workflow's supported threat model. Any failure
after NSIS reports success returns `partial-manual-review`: the tool does not
uninstall, retry, or roll back automatically. The retained community Desktop is
the primary rollback path. Data may have been forward-migrated, so the receipt
deliberately makes no automatic Core or data rollback claim.

## Optional configuration migration (plan first)

Migration is a separate opt-in phase of the same Windows Ops entry point. It is
never implied by `-Apply` and never copies the community profile or `node_modules`.

```powershell
# Read-only install check plus a redacted migration plan
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\install-official-desktop-local.ps1 -Migrate

# After reviewing the returned plan hash, apply only that exact plan
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\install-official-desktop-local.ps1 -Apply -Migrate `
  -AcknowledgeUnsignedLocalBuild `
  -AcknowledgeMigrationPlan sha256:<reviewed-plan-hash>
```

The plan uses recursively sorted canonical JSON and binds the community settings
fingerprint, target settings/release/install evidence, action set and schema
fingerprint. A changed source, target, receipt, release or process/session state
refuses the apply before a write. `-WriteMigrationPlan` explicitly stores the
redacted plan under the isolated data root; the default plan stays in stdout.

The first migration stage may transform only schema-validated non-secret settings
leaves such as theme, existing permission preset, exact default provider/model and
non-secret provider route metadata. API-key environment-variable names may be
listed, but key values, headers, OAuth/browser credentials and `.credentials.yaml`
secrets are not copied; they require interactive reauthorization. Plugin entries
are exact-version manual install intents only and are not copied into the Desktop
profile. Sessions, workspaces, attachments, cron state, feedback, projection
caches, anonymous identity, stores, caches, staging, rollback, lockfiles and all
`node_modules` remain untouched. Apply takes a target backup and keeps it when a
post-write verification fails; it never stops or restarts either Desktop and never
changes the community source.

## Other reviewed phases

1. A human reviewer may run `dev:desktop` with an isolated source-owned
   `DSH_HOME` and verify startup without using any live user profile.
2. DeepSeek's release owner may run the unmodified official Windows package
   command with the vendor EV signing environment and qualify signed artifacts.
3. Restart, community removal, Session/workspace migration, and shared/live-data
   acceptance remain outside this workflow. The optional migration stage above
   is limited to the explicitly listed settings and manual plugin intents and
   still follows the repository's live-Session safety rules.
