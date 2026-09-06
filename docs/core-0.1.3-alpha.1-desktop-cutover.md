# DSH Core 0.1.3-alpha.1 Desktop readiness advisory

## Decision: blocked pending a locked Desktop baseline

This document records compatibility evidence and local risk reduction. It is
**not an executable Core-cutover procedure** and does not approve changing the
current machine to Core `0.1.3-alpha.1`.

The authoritative contract remains
[`deployments/windows-copilot.lock.json`](../deployments/windows-copilot.lock.json).
It still identifies the reviewed official Desktop-managed runtime with inner
Core `0.1.2-rc.1`. A Core cutover remains blocked until all of these move
through one reviewed change:

- an official Desktop-managed runtime delivery path for the target Core;
- the Desktop artifact and all internal plugin identities;
- immutable companion-plugin Release URLs, versions, SHA-256 values, and
  `SHA256SUMS` identities;
- the deployment lock, plugin catalog, fixtures, tests, and current guides;
- restart-safe Web acceptance evidence.

Do not substitute a private CLI, use Desktop's local-Core action, persist
`DSH_CLI_PATH`, or apply the older lock over the newer installed Desktop.

Target under evaluation:

- release: `0.1.3-alpha.1`
- upstream tag: `dsh-v0.1.3-alpha.1`
- upstream Core commit: `d347e703908d0406b7a7ef80e3a0e594d86b2215`
- latest Windows prebuild tag: `dsh-src-0.1.3-alpha.1-34026101853`
- prebuild wrapper commit: `b907ecdcc7ef6113737788f56e421e790a3e9977`
- prebuild Windows ZIP SHA-256: `a9e4b9c38053860fcb65168afe98fc13b0738d84268d271db5d7b13b3a540c1e`

The latest prebuild uses Node `22.22.0` and supersedes the older Node 24 build
`33889851724`. Its GitHub prerelease is not immutable and provides no
`SHA256SUMS`, so these facts are discovery evidence, not yet a complete locked
runtime identity.

The release changes Session persistence to per-Session handles, replaces
durable `assistant/chunk` events with transient Assistant stream frames and
embedded settlement streams, and adds ordinary file attachments. These are
plugin compatibility boundaries, not merely package-version changes.

## Companion-plugin evidence

This evidence proves source/API compatibility. Deployment approval still
requires immutable artifacts in the updated lock.

| Plugin | Evidence | Deployment requirement |
|---|---|---|
| `dsh-cron` | Installed `0.4.6` uses `list()` snapshots plus `open(id, 'read')`, `read()`, and `close()`; its immutable Release commit `8c8e7f2030b790eff1bacd1d83614b01a770d4d2` passed Windows/Linux and Node 22/24 checks against rc.1 and alpha.1; the installed tarball SHA-256 matches its local `SHA256SUMS` | Pin the immutable `v0.4.6` Release URL, digest, and checksum-manifest identity in the updated lock before treating it as baseline evidence |
| `dsh-github-copilot` | Installed `0.3.1-alpha.2` detects top-level and nested file blocks and returns control to Core; source-equivalent commit `6c33a287c53b45b147077f7d24ba1d48b74d9835` passed all six rc.2/rc.1/alpha.1 Windows/Linux checks | Immutable Release `v0.3.1-alpha.2` is now available at release commit `587d074901d2f7574ffcb175ebfe3aae1e6b8f53`; pin its tarball SHA-256 `1186b86653dd11590389d31b50defd56534abd4d6a2d8881ef6d0c624da3e021` and `SHA256SUMS` SHA-256 `1a6da9e88d0e0d933dfcf965421c01d337ebd5d6eff372a97023593fa2344fe0` in the complete baseline update |
| `dsh-playwright-host` | Source `0.1.3` at merge commit `787ba673b2155b1ba12c9785807c4a70bb2522df` passed Windows/Linux source-seam checks against rc.1 and alpha.1 | It is not currently configured in the Web Profile. Publish and lock an immutable `0.1.3` Release before enabling it as a reviewed overlay |

## Installed incompatible overlays

The following installed versions consume APIs removed by Core alpha.1:

| Plugin | Incompatible use | Expected failure |
|---|---|---|
| `dsh-better-sidebar@0.18.0` | `sessionPersistence.inspect()` and durable `assistant/chunk` | Cold Side Chat/session reads fail; streaming transcript behavior is stale |
| `dsh-tauri-worktree@0.6.7` | `Session.events` and `meta.seedLength` | Worktree creation, inherited history, or checkout handback can lose or reject Session lineage |
| `dsh-tauri-panel-scheduler@0.6.7` | `agent.session.events` | Scheduled-run result summarization can fail after the model turn |

The deployment lock records these exact package/Core combinations in
`profile.pluginPolicy`. Unmanaged packages remain inventory/warning data and do
not contribute managed health. The cutover gate blocks only an exact denylist
match whose entry is active or whose activation state cannot be established.

On the inspected machine these three names have already been removed from the
Web Profile's `dsh.profile.bundles` array. Their dependency entries, Desktop
resources, tasks, worktrees, and Sidebar state remain intact for rollback. A
composed-config dump contains no marker for any of the three.

`dsh-tauri-pet@0.1.0` remains a bundle dependency but both of its composed rows
(`dsh-tauri-pet` and `dsh-tauri-pet-skills`) are explicitly `disabled: true` in
the Profile patch. No removed alpha.1 API marker was found in its installed
bundle, but it has not been promoted to locked alpha.1 compatibility evidence.
It must remain disabled through any future cutover acceptance.

## Evidence collected before any cutover

1. The locked installer was run in default read-only check mode. It reported
   expected drift rather than repairing it: the installed Desktop is newer than
   the lock, the official runtime path is a reparse point, and the installed
   Copilot artifact does not match the old lock. An immutable Copilot alpha.2
   Release now exists, but the lock has not adopted it. These findings block
   `-Apply`; they do not authorize replacing the installed state with the older
   lock.
2. The Web Profile manifest, lockfile, root patch, and root composition were
   backed up before bundle edits.
3. Only the three incompatible bundle names were removed. Dependency entries
   were unchanged.
4. The exact Desktop-managed CLI successfully dumped the composed Web
   configuration. None of the three removed bundle names remained, while
   `dsh-cron` and `dsh-github-copilot` remained composed.
5. Repository validators and all 139 Pester tests passed for the policy and advisory changes.

## Required work before switching Core

1. Obtain an official Desktop-managed target runtime and update the complete
   Windows lock atomically. Do not independently replace the inner Core.
2. Pin the immutable Copilot `v0.3.1-alpha.2` and Cron `v0.4.6` artifacts with
   their canonical URLs, source/release commits, sizes, hashes, and checksum
   manifests. Do not substitute the currently installed local Copilot tarball.
3. Review every official Desktop internal plugin delivered with that Desktop,
   including the Session, Worktree, Scheduler, UI, Panel, Right-click, and Pet
   surfaces. Keeping a row disabled is acceptable risk reduction, not positive
   compatibility evidence.
4. Update catalog entries, fixtures, installer expectations, runtime-schema
   evidence, bilingual/current guides, and rollback receipts together.
5. Run repository validators, the replay self-check, exact-marker dry run, and
   full Pester suite before Apply.
6. Immediately before any operation that can stop or restart Desktop, query
   `session/list`. Every running Session blocks the operation unless the user
   acknowledges the exact current IDs.
7. After an authorized restart, refresh the existing
   `http://127.0.0.1:3080` page and verify Session history, a new model turn,
   Copilot selection/response, Cron list/test behavior, disabled-overlay
   absence, and no activation errors naming removed APIs.

## Rollback ordering

Rollback must not reactivate old overlays on the alpha.1 runtime.

1. Query `session/list` and obtain acknowledgement for the exact live Session
   set before any action that can stop or restart the Host.
2. Restore the prior official Desktop-managed Core through its supported,
   receipt-backed path and verify the restarted old runtime.
3. Only after the old Core is active, restore the backed-up Web Profile files so
   the old overlays can be composed again.
4. Apply the same live-Session gate before the restart that activates the
   restored overlays, then verify each restored surface.

## Re-enable criteria

Re-enable each disabled bundle independently only after its exact delivered
version demonstrates all applicable target contracts:

- persistence consumers use a read handle and close it on every outcome;
- Assistant streaming consumers use `agent/assistant-stream` and replay the
  embedded `assistant/message.stream` / `assistant/attempt.stream` records;
- Session history reads use `snapshotEvents()` rather than `Session.events`;
- seeded Session creation uses `meta.isSeeded: true` plus the top-level
  `inheritedEventCount`;
- Client attachment surfaces use the alpha.1 attachment contract.
