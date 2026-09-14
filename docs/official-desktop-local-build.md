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
| Package manager | `pnpm@11.7.0` through Corepack |
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
to, inside, or containing this operations repository, known
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
Corepack, Node engine, and the official remote tag-to-commit mapping. It reports
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
invokes the exact package manager through Corepack with:

```text
pnpm@11.7.0 install --frozen-lockfile
```

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
failure, and an exact retry passed 9 of 9.

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
- product name `DSH Local Build`;
- packaged metadata name `dsh-local-build` and product name `DSH Local Build`, preventing Electron user-data identity from falling back to `@deepseek-ai/dsh-desktop`;
- artifact name `dsh-local-build-${version}-win-${arch}.${ext}`;
- `publish: null`;
- `win.forceCodeSigning: false`; and
- `win.signtoolOptions: undefined`.

The command sets the local app ID and a non-routable test origin so upstream's
default import can evaluate, clears target and signing variables, and invokes
exactly `corepack pnpm@11.7.0 exec electron-builder --config <overlay> --win
--x64 --publish never`. It never calls an official package wrapper or signer.
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

This is a local derivative package from official source, not a vendor-signed or
officially branded release. The tool does not install or launch it, touch a live
DSH home, or write outside the isolated build root.

## Later reviewed phases (not implemented here)

1. A human reviewer may run `dev:desktop` with an isolated source-owned
   `DSH_HOME` and verify startup without using any live user profile.
2. DeepSeek's release owner may run the unmodified official Windows package
   command with the vendor EV signing environment and qualify signed artifacts.
3. Installation, restart, uninstall, profile migration, and live-data acceptance
   require a separate approved phase with the repository's live-Session safety
   rules. The existing community Tauri Desktop remains untouched.
