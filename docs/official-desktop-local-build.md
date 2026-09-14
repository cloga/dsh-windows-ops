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

## PackageLocal (unsigned, local identity, update channel not configured)

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

This packaging choice does **not** mean the official product lacks updates.
At the pinned commit, `apps/desktop/src/main.ts` exposes **Check for Updates**.
`DesktopUpdateCoordinator` in `apps/desktop/src/update-coordinator.ts` enables
the coordinator only for a packaged application containing `app-update.yml`;
`autoDownload` and `autoInstallOnAppQuit` are both false. This local overlay uses
`publish: null` and deliberately contains no `app-update.yml`. The menu can
therefore remain visible without a configured release stream. This installer
does not add a feed, change signing, or enable automatic downloads.

## dsh-windows-ops managed update channel (explicit one-click install)

The existing `PackageLocal` and one-command install defaults remain unchanged:
they do not configure an updater. A separate operations-owned workflow can
prepare and validate an update feed without claiming the vendor identity or
silently installing unsigned code. The primary user flow is a read-only remote
manifest check followed by one explicit install trigger:

```powershell
# Build one reviewed local package and an unpublished generic-provider bundle.
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\manage-official-desktop-update-channel.ps1 -Action Package `
  -Sequence 1 `
  -FeedBaseUrl https://github.com/cloga/dsh-windows-ops/releases/download/dsh-local-0.1.5-rc.2.local.1/

# Read-only remote manifest comparison with the installed schema-3 receipt.
# This downloads only release.json into a temporary directory.
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\manage-official-desktop-update-channel.ps1 -Action Check `
  -ManifestUrl https://github.com/cloga/dsh-windows-ops/releases/download/dsh-local-0.1.5-rc.2.local.1/release.json

# One explicit user trigger: download, verify, stage, launch the interactive
# NSIS installer, wait for it, and perform strict completion readback.
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\manage-official-desktop-update-channel.ps1 -Action Install `
  -ManifestUrl https://github.com/cloga/dsh-windows-ops/releases/download/dsh-local-0.1.5-rc.2.local.1/release.json `
  -AcknowledgeManifestSha256 sha256:<release.json-manifestSha256>
```

`Install` is one-click in the sense that the user performs one explicit update
action after reviewing `Check`. It is not a silent or unattended update. The
script passes no `/S` argument, does not request elevation itself, and does not
use `runAs`; the verified NSIS package and Windows retain their normal installer
and UAC confirmations. The script never dismisses SmartScreen, certificate,
publisher, or operating-system warnings.

`Package` still invokes the strict pinned `PackageLocal` pipeline. It then
creates exactly four channel files below
`BuildRoot\update-channel\<channel-version>`:

- `release.json`, the self-hashed operations manifest;
- `rc.yml`, the electron-updater generic-provider metadata shape;
- the hash-preserving installer copy named with the channel version; and
- `build-receipt.json`, the original strict PackageLocal receipt.

The manifest records the immutable upstream commit/tree through the build
receipt, installer size, SHA-256 and base64 SHA-512, installed executable and
seed SHA-256 values, feed URL, and security mode. `Stage` requires the exact
manifest hash, copies through a unique temporary directory, revalidates every
byte, and uses one atomic directory rename. An identical retry is idempotent; a
conflicting or tampered stage fails closed. No token, authorization header,
credential, Session content, or DSH home content is written to the bundle.

Remote `Check` validates the manifest schema, identity, self-hash, security
boundary, credential-free HTTPS feed URL, and monotonically increasing sequence
without persisting update state. `Install` downloads `release.json`, `rc.yml`,
the installer, and the strict build receipt into a unique temporary directory,
then reuses the same bundle verifier for manifest self-hash, installer
SHA-256/SHA-512/size/signature state, build-receipt hash and provenance, and
installed-evidence hashes before atomically exposing the download. It then
calls the existing `Stage` implementation; validation logic is not duplicated.

The operations channel version is
`0.1.5-rc.2.local.<positive-sequence>`. The immutable upstream package and seed
version remains `0.1.5-rc.2`; the suffix identifies monotonically ordered local
rebuilds without claiming that DeepSeek published another upstream version.
Sequences must increase for each published candidate. Publishing is deliberately
not performed by these tools. A reviewer must create an immutable GitHub Release
or approved static HTTPS feed separately, upload the four exact files, and
confirm that names and hashes match the verified bundle. Concurrent publication
runs should serialize by release tag; an existing tag or differing bundle is a
conflict, not an overwrite.

### Why this does not enable Electron's native Windows updater

The pinned Desktop coordinator enables `electron-updater` only when packaged
resources contain `app-update.yml`, and leaves automatic download and automatic
install disabled
([upstream `update-coordinator.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/fb2c4b9e698e30edb738bca4cf0618587db7d203/apps/desktop/src/update-coordinator.ts)).
The official builder emits a generic provider and requires Windows code signing
([upstream `electron-builder.config.mjs`](https://github.com/deepseek-ai/deepseek-harness/blob/fb2c4b9e698e30edb738bca4cf0618587db7d203/apps/desktop/electron-builder.config.mjs)).
The pinned package uses `electron-updater` 6.8.9
([upstream `package.json`](https://github.com/deepseek-ai/deepseek-harness/blob/fb2c4b9e698e30edb738bca4cf0618587db7d203/apps/desktop/package.json)).
In that version, `NsisUpdater.verifySignature()` returns success without checking
Authenticode when `publisherName` is absent, while a configured publisher name
causes the downloaded installer signature to be checked
([electron-updater 6.8.9 `NsisUpdater.js`](https://unpkg.com/electron-updater@6.8.9/out/NsisUpdater.js)).

Because the local package is intentionally unsigned, embedding a feed without a
usable signing identity would make the manifest SHA-512 an integrity check, not
an application-owner authenticity proof. This workflow therefore preserves
`appUpdatePresent=false`, records `nativeUpdaterEnabled=false`, and never calls
`quitAndInstall`. Do not add `publisherName`, disable signature verification, or
hide Windows warnings as a workaround. Native updates may be enabled only after
an owned Authenticode identity, protected signing service, publisher continuity,
and end-to-end signed upgrade tests are available.

### Interactive installer and schema-3 completion

Close the local Desktop normally before selecting `Install`; this workflow
never stops or restarts it. After exact manifest acknowledgement, the script
revalidates the staged installer immediately before launch and starts it with no
arguments. The user—not the script—accepts or rejects the installer and any
Windows/UAC confirmation. The existing app ID, package name, and install
directory preserve upgrade compatibility, while `DSH_HOME` and Electron
user-data selection remain those stored by the schema-2 receipt.

After the installer exits successfully, `Install` immediately reuses
`Complete`. It verifies the actual executable version and identity fields, exact
executable and seed hashes, seed package versions, uninstall registration,
absence of `app-update.yml`, prior receipt trust, launcher/shortcut ownership,
and archived installer/build-receipt/manifest metadata before writing the
schema-3 receipt.

If Windows has not made the final files observable yet, or another strict
post-install condition blocks immediate completion, the result is
`status=blocked`, `installerRun=true`, and
`reason=update-completion-required:<reason>`. The stage remains intact and the
caller can run the following command during the next launch:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\manage-official-desktop-update-channel.ps1 -Action Complete `
  -StageRoot <DataRoot>\updates\staged\0.1.5-rc.2.local.1 `
  -AcknowledgeManifestSha256 sha256:<release.json-manifestSha256>
```

`Complete` never runs the installer. It rechecks paths and processes, requires
the installed executable and complete seed tree to match the staged manifest,
revalidates the prior receipt and strict build receipt, archives the exact
installer/build receipt/manifest, preserves the recorded shared or isolated
home, rewrites only the owned launcher and shortcuts, and upgrades the install
receipt to schema 3 with channel owner, sequence, feed, manifest, and
`nativeUpdaterEnabled=false`. A failure after the user ran the installer is
manual-review state; it does not claim automatic binary, Core, or data rollback.
The prior installer archive and community Desktop remain the recovery boundary.

The lower-level local-bundle flow remains available for operations and recovery:
`Check -BundleRoot ...`, `Stage -BundleRoot ...`, user-reviewed installer
execution, and `Complete -StageRoot ...`. This does not change the primary
one-click trigger and does not enable background polling, automatic download,
silent install, Electron `quitAndInstall`, or native `electron-updater`.

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
For an already attested installation, Check instead verifies the archived build
receipt and installed evidence; it does not require the old source checkout,
pnpm executable, or a network tag lookup. Its build action is `installed-evidence`
with `sourceRevalidated=false`, not a claim that the source was revalidated.

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

### Opt in to one existing shared Harness home

The follow-up to #147 / #148 adds `-SharedHome <absolute-existing-path>`.
New installations still default to isolated data. To reuse the current
user's existing home without copying data or forcing reauthentication:

```powershell
# Read-only classification and process/path preflight
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\install-official-desktop-local.ps1 -SharedHome "$HOME\.dsh"

# Only after closing all DSH consumers normally and reviewing Check
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\install-official-desktop-local.ps1 -Apply `
  -AcknowledgeUnsignedLocalBuild -SharedHome "$HOME\.dsh"
```

| Boundary | Isolated default | Explicit shared mode |
|---|---|---|
| Application binaries (`InstallRoot`) | `%LOCALAPPDATA%\Programs\DSH Local Build` | Unchanged, separate from community binaries |
| Harness data (`DSH_HOME`) | `<DataRoot>\harness-home` | Exact existing `-SharedHome` |
| Electron browser/shell data | `<DataRoot>\electron-user-data` | Still isolated; never the community Electron directory |
| Receipts and backups | `<DataRoot>` | Still outside the shared home |

Shared mode reuses Sessions, workspaces, `settings.yaml`, and
`.credentials.yaml` in place. The installer neither reads their contents nor
copies, translates, deletes, or merges either home. A supported home must already
contain `settings.yaml` and a `sessions` directory. Its root and existing
Desktop-owned ancestors must belong to the current Windows user, be on a fixed
local non-synchronized drive, and not be reparse points. The build, binary,
receipt/Electron-data, repository, and community Electron roots remain disjoint.
Backups require the same volume as the shared home for an intact directory
rename, not a recursive copy. Unrelated shared profiles are never traversed.

Schema-2 receipts persist the selected home and isolated Electron path alongside
the launcher hash and updated shortcut description. **Later Check/Apply calls
without a home option retain the recorded mode**. Schema-1 isolated receipts can
be upgraded without rerunning NSIS. `-UseIsolatedHome` explicitly switches the
launcher back to `<DataRoot>\harness-home`; it does not copy or remove shared
data. It conflicts with `-SharedHome`. Shared mode and `-Migrate` are mutually
exclusive, including when shared mode is inherited from the receipt.

### Reserved `desktop` profile collision and recovery

At the pinned official commit, `DesktopProjectManager.applyRelease()` calls
`releaseVersion()` whenever `profiles\desktop` exists. An ordinary CLI-created
profile named `dsh-profile-desktop` has no `desktop-release.json` and can cause
ENOENT. Do not fabricate that file or run CLI mutations against the reserved
profile. The official app owns its initialization from the packaged seed.

Check distinguishes absent, unchanged official, exact known blank legacy, and
unsupported profiles. Official reuse requires seed-matching manifests, release,
workspace and lock metadata, the packaged Core tarball tree, and installed
Core/Host `0.1.5-rc.2` identities. Custom plugin graphs, changed patches, corrupt
metadata, or unavailable matching seed evidence fail closed for manual review.

The only automatic collision handling is the observed blank legacy scaffold:
the exact reviewed hashes of `package.json`, `cordis.yml`, `cordis.patch.yml`,
and `pnpm-workspace.yaml`, plus empty `node_modules` and
`.dsh-module-fallback\node_modules`. Extra files, nonempty dependency trees,
reparse points, different ownership, or an unfinished official activation
journal/rollback profile block it. Sizes or package names alone are not proof.
Check is read-only. Apply requires an explicit `-SharedHome` on that invocation,
rechecks state, and moves the **entire** scaffold to
`<DataRoot>\install-backups\shared-profile-<id>\desktop`. No dependencies are
copied and no profile is synthesized. The app initializes from its seed only
when the user later launches it; this installer never auto-launches or restarts.

All possible DSH Desktop/Core/Host consumers must be stopped, including community
Desktop. Unavailable process enumeration or an uninspectable possible Node
consumer blocks shared Apply. The guard is repeated immediately before changes,
including the idempotent path; nothing is killed and no live-session override is
provided. Concurrent applications must remain closed throughout Apply.

Launcher and prior receipt copies are retained under
`install-backups\home-change-<id>`. A `home-change.pending.json` journal blocks
subsequent Apply after an incomplete operation; a profile `backup.json` records
the source, destination, inventory fingerprint and move status. Failures are
`partial-manual-review`, never successful rollback. After closing all consumers,
review those journals and hashes. If restoring the legacy scaffold is intended,
move it back **only if `profiles\desktop` is absent**; if the official app has
already initialized it, preserve that new profile separately and obtain explicit
approval before changing it. Never overwrite or merge profiles. Restore the
recorded launcher/receipt pair and matching shortcut target/description only
after verifying their backup hashes. Preserve the journals for diagnosis; clear
the exact pending file manually only after recovery has been verified.

### Shared settings do not imply shared plugin registrations

Core-wide settings and credentials can be reused in one home, but
`profiles\web`, `profiles\headless`, and Electron's reserved `profiles\desktop`
have distinct plugin dependency/registration graphs. Existing Copilot on
web/headless is **not** installed into Desktop by this operation.
Installed Core packages are not all additive plugin bundles. Adding
`dsh-acp-app`, `dsh-headless`, `dsh-sdk-app`, or `dsh-sdk-minimal` to Desktop's
base/web bundle list can compose mutually exclusive application surfaces;
web plus headless produced `duplicate loader entry id: code-runtime` in the
observed installation. Check reports `shared-official-profile-conflicting-app-bundles`
and blocks rather than silently rewriting the manifest.

The current Windows operations contracts reference checksum-verified Copilot
GitHub Release artifacts. Newer plugin releases may also publish to npm, but
that does not prove that this pinned official Desktop can install or safely
compose them. Its `DesktopProjectManager.packageNameFromSpec()` currently
rejects URL and `file:` specs, while the CLI forbids booting or mutating the
reserved `desktop` profile. Consequently, the reviewed Release tarball still
has **no supported Desktop installation route in this version**, and no npm
route has been accepted by this repository for the corporate Desktop.
Check reports
`copilotDesktopInstall=unsupported-release-tarball-spec`. A supported route
requires a Desktop-owned artifact or package-manager flow with exact version,
registry, dependency, profile-ownership, and runtime acceptance evidence. Do
not copy `node_modules`, edit profile manifests, patch Core, or infer credential
loss or reauthentication from this plugin boundary.

An exact existing receipt/install is idempotently reverified and repairs the
launcher, local shortcuts, and receipt without rerunning the installer. Archived
build evidence is structurally/policy validated separately from live source
verification; archived installer and installed executable/seed hashes are still
checked against it. Owned DataRoot
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
3. Restart, community removal, and Session/workspace copying remain outside this
   workflow. Shared-home reuse is only the explicit guarded mode above. The optional migration stage
   is limited to the explicitly listed settings and manual plugin intents and
   still follows the repository's live-Session safety rules.
