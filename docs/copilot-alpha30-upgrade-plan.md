# Copilot alpha.30 managed-upgrade acceptance and formal pin

This is the Ops acceptance contract and formal release record for Issue
[#200](https://github.com/cloga/dsh-windows-ops/issues/200). The deployment lock
now selects the independently verified immutable Desktop Release described below.
It does not install, activate or restart Desktop on this machine.

## Published target and provenance

- Desktop `0.1.6-alpha.1.cloga.12`, sequence 22, bundled Core
  `0.1.6-alpha.1`, required `dsh-github-copilot@0.4.0-alpha.30`.
- Immutable [Desktop Release `392534651`](https://github.com/cloga/deepseek-harness/releases/tag/dsh-desktop-v0.1.6-alpha.1.cloga.12),
  source `d19be3ff5524948c40cb9929cdd4d67d5cb35059`, tree
  `681980cf0d3448679529628477d9ff79ea927cc4`, PR 87, qualified candidate
  `3e277c3f0821264d4becca825636b5fcd8112bcd` retained through the normal merge.
- Installer asset `577349351`, 171,323,022 bytes, SHA-256
  `f1fadab2922b9a2f56d72e07b3072c8b871d5ccce9696b82fcc62c22824fcd16`,
  SHA-512 base64
  `AgU39uOIxrFFAmvNZxfE2Qa7kec2/teEURT84zVzn+SFfNu2HmRYLWcpdG/OJm+rYM+/EvCuOnb2hGFuNxIC+A==`.
  Installed runtime descriptor SHA-256 is
  `3e20cd0ace516569c9ead2403acffe16ed0a3e99b1ef45d17e0bca3cc7bd06f3`;
  installed EXE SHA-256 is
  `ef6d3b63d2e495d7fb421327c5f7d9fb48970dbb44f55b1ff245890b52d4dada`.
- Copilot alpha.30 is immutable Release `392419629`, source/merge
  `b75eac570cd418497c52e80a3ce47958cdcc6b26`, PR 151 reviewed head
  `c4d7e0d19a26a775472d34d4d499340c67a24ea3`. It remains a plugin; it is
  not “official Core”.
- Formal Desktop run [`35528552640`](https://github.com/cloga/deepseek-harness/actions/runs/35528552640),
  attempt 1, passed all three jobs. The independently acquired original Actions
  ZIPs are build artifact `10611295774` (171,332,866 bytes, SHA-256
  `9dd85c8506f2a0834f012ad6d0f9cd08f2c384d877fe03d687b8005c9fe1341e`),
  acceptance `10610892333` (787,967 bytes,
  `ceeae28830a41317366a7e80590974397ef7e3f0d8b810ebccc0c0625b1610f7`)
  and observer canary `10610569879` (787,007 bytes,
  `f00af1309c63ad3a8f4460915336f8173ff22720ec9f440e5a835453724f3f8f`).
  All 66 extracted entries were byte-bound to those originals.

The 18 files in
[`formal-cloga016-12`](../tests/fixtures/desktop-native-verified-release/formal-cloga016-12)
are byte-exact authenticated entries: three build files and fifteen acceptance
files. They include initial/restart settings and version-menu evidence. Existing
formal and Ops fixtures remain historical and unchanged. Live GitHub Release JSON,
tag/commit/tree and remote asset digests remain authoritative; there is no new
formal ZIP transport requirement.

## Schema 2 read-only acceptance

`components.desktop.releaseChannel.nativeProvisioning.settingsAcceptance.schemaVersion`
is `2`. It hash-binds both phases and requires:

| Evidence | Required values |
|---|---|
| Main `acceptance.json` | `modelRolesViewLoaded:true`, `searchProviderCatalogLoaded:true`, `manageCompatibilityDisclosureAbsent:true`, `providerOnlySearchRouting:true`; `realOAuth:false`, `verificationNavigationExercised:false`, `manualVerificationAddressObserved:false`, `realModelRound:false`, `realSearch:false` |
| Each settings JSON | `modelRolesViewLoaded:true`, `currentWorkspaceReadOnly:true`, `searchProviderCatalogLoaded:true`, `providerOnlySearchRouting:true`, `fallbackProviderLabel:true`, `realSearch:false` |
| Provider IDs | non-empty strings, unique within a phase, equal across phases, including `github-copilot-hosted` |
| Each version-menu JSON | `Application`; exact `About Desktop 0.1.6-alpha.1.cloga.12…`; exact version; one synthetic dispatch; no native modal; identical phases |
| Fresh exact-source run | the main semantics and exact hash-bound settings/version-menu leaves must be reproduced before native qualification |

The false navigation fields mean the signed-out read-only run did not initiate
OAuth or exercise/observe a verification address. The source-owned packaged DOM
assertions remain part of fresh acceptance. They do not prove same-window external
navigation succeeds. Parent visual review covered the formal Model roles and Search
screenshots after byte binding, but PNG signatures alone are not visual acceptance.

## Executed and synthetic boundaries

| Feature lineage | Packaged acceptance boundary |
|---|---|
| alpha.28 budgets and compaction | Synthetic/contract and downstream coverage only; no live budget exhaustion, compaction rescue or paid model turn. |
| alpha.29 routing CAS and search-model selection | Synthetic/downstream routing coverage only; no live competing CAS operation or real search-model call. |
| alpha.30 navigation and provider-only Manage | Initial/restart packaged Electron version menu, Models/Manage navigation, read-only workspace/catalog and provider-only routing executed. OAuth, verification navigation, model response, search/fallback and save/create were not executed. |

External-navigation repair PR 96 had a successful rehearsal but failed source CI and
remained unmerged. Alpha.30 retains a manually selectable verification URL; this
Release does not qualify same-window external navigation.

## Native Ops qualification transaction

The registered same-commit caller workflow `345664659` must run against the exact
PR head and `.cloga.12` lock after local validators/tests pass. Record the exact
Ops commit, run/attempt/job/artifact identities and byte hashes in a follow-up
commit. A green state alone is insufficient. Until that record exists, formal
source acceptance is complete but genuine current native Ops qualification is
pending. Parent release operations own the watcher and final activation.

Never run a current-machine Check against this future lock while the installed
managed Desktop remains `.cloga.10`; that expected drift is not a release defect.
No installation, activation or restart is authorized here.

## Official-first decision record

Official Core alpha.2 support advertised by Copilot alpha.30 is compatibility
scope, not authority to promote Core. Desktop alpha.2 PR 68 is separately owned,
draft and unqualified. This paired Release keeps bundled Core alpha.1.

| Requirement / owner | Official or delegated primitive | Decision and retained gap | Retirement condition |
|---|---|---|---|
| Packaged ASAR/Core launch and public profile generations / Desktop | Official Core/Desktop primitives are already consumed. | Keep official primitives; retain final-byte inventory, isolation and managed-provisioning guards. | Official distribution proves the same byte, isolation, ownership and rollback guarantees. |
| Settings slots, Remote factories, OAuth/chat/subagent / Core | Official extension, transport and lifecycle primitives are already delegated to; alpha.30 also adopts alpha.2 `create()` Remote factories while retaining an older-Core parser bridge. | Keep using official APIs; do not add a Core shim or label the plugin official Core. | Retire the compatibility bridge only after older admitted Cores are dropped and packaged alpha.2 acceptance passes. |
| Account discovery and provider-only search routing / plugin | Official transport/catalog primitives are reused; authenticated account refresh, owner proof and one distinct final fallback remain plugin-owned gaps. | Retain alpha.30 provider identity, CAS/routing and cancellation/disclosure coverage. | A reviewed official provider supplies equivalent migration and packaged initial/restart behavior. |
| Read-only Manage and verification handoff / plugin + fixture | Official navigation primitives are reused. | Retain negative no-OAuth/no-navigation evidence and manual selectable recovery; same-window success remains unqualified. | Equivalent official UI behavior and observable positive/negative navigation acceptance pass. |
| Immutable acquisition, ownership and rollback / Desktop fork | Official mutation path does not establish this deployment’s verified-source transaction. | Retain Release plan, receipts, staged swap/recovery and native ASAR verification. | Official path meets exact source/checksum, ownership, recovery, rollback and active-Session safety requirements. |
| Compaction/recovery / Core + plugin | Official bounded compaction/rebuild is authoritative; plugin retains provider-specific prompt/I-O admission and summary defaults. | Keep official recovery signaling and narrow provider admission/defaults. | Retire only after equivalent provider budgets pass oversized-history cases without silent deletion/model switching. |

Re-evaluate against the exact official release before any future Core change.
Similar labels are not parity; unverified is not absent, and this pin authorizes
neither Core promotion nor removal of retained safety coverage.
