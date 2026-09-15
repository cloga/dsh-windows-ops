# Official Desktop plugin provisioning removal

`deployments/windows-copilot.lock.json` owns the single versioned
`desktopProvisioning` contract. The current mode is
`desktopNativeVerifiedRelease`: Windows Ops validates the native capability and
keeps the historical adapter only as a compatibility/delegation surface. It no
longer mutates the reserved Desktop profile through the external workaround.

## Native capability gate

The mode switch is complete for the fork-owned
`dsh-desktop-v0.1.5-rc.3.cloga.1` release. Future switches must not proceed
until one reviewed Core/Desktop pair proves all of the following with a
committed fixture:

1. Desktop accepts an exact immutable Release artifact or equivalent
   cryptographically locked local package without resolving the root package
   from a mutable registry.
2. Root artifact name, version, release commit, size, SHA-256, SHA-512/SRI,
   archive paths, manifest, and lifecycle-hook policy are verified before use.
3. Transitive dependencies use the approved explicit registry and installation
   runs only in a complete staging project while Desktop/Host are closed.
4. Official internal links and valid existing third-party bundles survive;
   conflicting application bundles fail before activation.
5. Staged and active Host health checks, journaled atomic activation, rollback,
   and crash recovery have automated tests.
6. Shared Home Sessions, settings, credentials, workspaces, and unrelated
   profiles are neither read nor changed.
7. First install, existing isolated Home upgrade, explicit shared Home upgrade,
   and managed update completion all use the same native transaction.

Record the exact Core commit, Desktop commit, and fixture path in
`nativeCapability`, set `verified=true`, and change `mode` to
`desktopNativeVerifiedRelease` in the same pull request. Policy tests reject
native mode without this evidence and reject simultaneous Windows Ops/native
provisioning.

## Compatibility transition

For at least the receipt schema named by `compatibilityReadUntilSchema`, native
Desktop must recognize the Windows Ops provisioning receipt as historical
evidence. It may replace the reserved profile only after validating the current
profile and contract; it must not delete the artifact cache, rollback evidence,
or receipt merely because native support exists.

The transition pull request must update the lock, catalog/schema, fixtures,
build/install/update tests, replay/self-check policy, README.md, README.en.md,
the local build guide, tools README, AGENTS.md, and pull request checklist.

## Windows Ops removal

After no build/install/update entry point can still select the compatibility
adapter:

1. Remove install/update calls to the Windows Ops adapter and make PackageLocal
   receipts identify native delegation only.
2. Remove `tools/DshOfficialDesktopPluginProvisioning.psm1`,
   `tools/dsh-official-desktop-plugin-health.mjs`, and their focused tests.
3. Remove Windows Ops-only receipt fields after the compatibility-read window.
4. Keep the immutable artifact contract and Release sync/check command unless
   Desktop native release metadata provides an equally strict, independently
   testable source.
5. Run repository validators, focused and full Pester, replay SelfCheck,
   exact-marker dry run, and update-channel completion tests.

Do not remove the adapter while any build/install/update entry point can still
select it, and do not retain both provisioners as fallback paths. In the current
native-delegated state, Check/Apply report delegation without profile mutation.
A native failure must fail closed rather than silently invoking the retired
adapter.
