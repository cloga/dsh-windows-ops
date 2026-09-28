# Upgraded Desktop startup and settings recovery

This incident record is specific to one official Desktop `0.2.0-rc.1`
installation. It does not promote or change the Windows Ops deployment lock,
establish general `0.2.0-rc.1` compatibility, or authorize an install or
restart. The locked Windows Ops baseline remains authoritative for supported
deployments.

**Incident recovery verified:** the stale-authorization repair and restoration
of the newest compatible settings snapshot passed the checks below in the
original profile. This is not a general compatibility certification or a
guarantee beyond the observed running instance.

## Incident evidence and limits

The affected window reported `desktop welcome: Web RPC failed`. A bounded
diagnostic found `POST /api/account/getState` returning
`gateway/service-unavailable` because the active `accountController` was
unavailable. Other bounded settings/provider-description requests succeeded.
The original profile contained a profile-local
`@deepseek-ai/dsh-authorization@0.1.2-rc.1`, which shadowed the
Desktop-bundled `0.2.0-rc.1` module. Peer compatibility disabled authorization
and the dependent account plugins. The presence of Copilot in the package did
not establish it as enabled or as the cause.

The original crash and subsequent normal launch used the same official Desktop
executable and the Host command line selected the existing
`~/.dsh/profiles/desktop`; no Home or update-channel switch was found. The
original patch contained only its empty-list scaffold. The newest non-empty
backup of that same profile recorded onboarding as completed, with the step
marked done and completion marked skipped. A prior, older snapshot disagreed
and was not replayed. Restoring the latest snapshot therefore restored
previously persisted completion; it did not create or click a new dismissal.

These observations are incident-specific. A rendered window alone does not
prove the account API works, settings were retained, or the intended account,
models, workspaces, and Sessions are visible; verify each separately.

## Recovery boundary

For this incident, the narrowly scoped startup repair disables the stale
profile-local authorization row and adds one uniquely named row that loads the
unchanged authorization module bundled with Desktop. Keep manifest and peer
compatibility checks enabled. Do not add a version exemption, patch Core,
install another runtime, reset credentials, clear application data, or copy
`node_modules`.

The public patch loader's `name` field is an equality guard, not a replacement
instruction. Use a unique inserted row that points to the unchanged
Desktop-bundled module; retain the enclosing manifest compatibility checks.
The following is a shape-only example. Substitute the actual install root
locally; never publish a user's private path:

```yaml
- id: authorization
  name: '@deepseek-ai/dsh-authorization'
  disabled: true
- insert:
    - id: desktop-bundled-authorization
      name: '<DESKTOP_INSTALL>\resources\app.asar\dsh\node_modules\@deepseek-ai\dsh-authorization\lib\index.js'
```

The module manifest and import were checked against the installed
`0.2.0-rc.1`; the module itself was not changed. The absolute module reference
is install-location-specific and must be rechecked if Desktop moves or changes
layout.

Restore settings separately and only from the newest verified backup of the
same profile. The incident's selected snapshot contains five user-setting
rows covering onboarding, chat, settings UI, theme, and `deepseek-account`
model choices. Preserve the authorization repair and replay these exact rows,
in order and without changing their values; the installer-bundled module's
public `Config` getter validated the restored effective values without
coercion. Do not merge older snapshots or fabricate absent rows. In particular,
do not take older/conflicting provider, default-model, permissions, or
completion values as a reason to reconfigure the profile. Never print or copy
setting values, credential contents, tokens, or private paths into this guide
or diagnostics.

Keep byte-verified backups before each write. The startup patch backup was
verified byte-for-byte against the source before repair. A second backup was
made after the startup repair and before restoring settings. The exact
pre-settings snapshot can undo the settings restoration while preserving
startup recovery; the earliest snapshot restores the original empty patch and
therefore also restores the startup failure. Rollback was not rehearsed because
it would reintroduce the incident. Retain both snapshots; do not merge them or
reset the profile.

The profile's plugin graph is separate from `profiles/web` and
`profiles/headless`. Do not copy or merge those profiles, manually materialize
the reserved `profiles/desktop`, or run ordinary package-manager commands in
it. Desktop-native provisioning owns that profile.

## Safe verification and acceptance

1. Verify the intended executable, Harness Home, and Host profile from the
   running Host command line; do not infer the profile from the window title.
   The incident was confirmed to use the original executable and
   `profiles/desktop`, not a second Home or update channel.
2. Compare the current profile with the newest valid same-profile backup.
   Preserve an exact pre-change backup and exclude older conflicting rows.
3. Validate the patch and settings using the installed Desktop parser and
   public `Config` getter. Confirm the final composition has exactly the
   intended authorization override plus the selected settings, and that
   effective values equal the newest snapshot.
4. Confirm the bounded account `getState` and `productAnalytics/enabled/report`
   requests return `ok=true`. Then verify the normal, non-debugger Desktop
   window no longer shows the startup error or welcome/setup. For this
   incident, hot module reload (HMR) updated the already-running window; no
   restart or onboarding action was needed.
5. Verify the observed existing workspace groups, conversation/history UI,
   account label, model/effort selector, and theme. This was a targeted visual
   check, not an exhaustive account/model capability test. Confirm credential,
   global-patch, and profile package-manifest before/after hashes match; confirm
   Session-file count and aggregate bytes are unchanged (individual Session
   contents were not hashed or inspected). These checks do not prove
   credentials are valid, perform sign-in/out, or establish a successful model
   request.
6. Preserve the backups. If recovery fails, first check live Sessions before
   any restart, then restore only the exact matching rollback snapshot; do not
   copy/merge profiles or reset state. No live Session was stopped or restarted
   during the verified incident recovery.

The repairer's isolated Node 24/Electron-as-Node test fixture passed 3/3
checks: composed patch/import behavior, persisted seven-row state plus retained
rollback snapshots, and equality of saved fields with the official Config
projection. The actual UI was verified using a bounded native window capture;
screenshots, account/workspace names, conversation content, and machine paths
are intentionally not included here. The rollback snapshots were verified
before writing and parsed afterward, but rollback was not executed live.

## Repository compatibility boundaries

The official runtime's ASAR path is not the Harness data Home; the reserved
`profiles/desktop` plugin graph is not `settings.yaml`. A launcher can select
`DSH_HOME` independently from Electron's `--user-data-dir`, and local source
builds may deliberately use isolated Homes. Always verify the actual running
executable, effective Home, and Host profile before concluding that settings
were lost. Those channel differences were ruled out for this incident. The
authorization workaround still relies on an absolute path to a module inside
the installed ASAR, so a changed install root/layout requires revalidation.

Optional installed-package import failures for unrelated vision, developer
tools, or messaging plugins were left untouched. This incident does not prove
those plugins compatible, does not enable Copilot in the Desktop profile, and
does not certify the full Desktop/Core/plugin combination.

This record does not change
[`deployments/windows-copilot.lock.json`](../deployments/windows-copilot.lock.json),
the plugin catalog, or supported Desktop pins. See the [authoritative
integration guide](local-core-desktop-copilot.md), the [local Desktop Home and
profile boundaries](official-desktop-local-build.md#reserved-desktop-profile-collision-and-recovery),
and the repository's [live-Session restart safety
rules](local-core-desktop-copilot.md#apply-the-locked-desktop-and-plugin).
