# Copilot alpha.30 managed-upgrade acceptance plan

This is the Ops planning and version-independent acceptance contract for Issue
[#200](https://github.com/cloga/dsh-windows-ops/issues/200). It does **not**
select a new deployment baseline. The authoritative lock remains unchanged until
the parent release lane supplies authenticated, immutable formal Release assets.
Do not copy candidate or rehearsal bytes into the lock or formal fixture tree.

## Current and candidate states

- The installed/latest managed baseline reported to this lane is Desktop
  `0.1.6-alpha.1.cloga.10`, sequence 20, bundled Core `0.1.6-alpha.1`, Copilot
  alpha.27. This report is context, not a new Ops lock assertion or local
  inspection result.
- Standalone Copilot alpha.30 is independently reported verified. It remains a
  plugin; do not describe it as “official Core”.
- Desktop candidate moved to `0.1.6-alpha.1.cloga.12`, sequence 22, bundled Core
  `0.1.6-alpha.1`, Copilot alpha.30, exact candidate commit
  `11de96bca5ecf3e4da0cd56ba07ea5e20c9e33b1`. Concurrent PR #84 was found to
  own `.cloga.11` / sequence 21, so this lane advanced rather than racing its
  version/tag. Prior run `35519234773` successfully rehearsed the same alpha.30
  UI/receipt behavior at the superseded `.cloga.11` identity; it is historical
  evidence only. Fresh `.cloga.12` CI/rehearsal remains required before merge.
- The repository lock/catalog/formal fixtures therefore remain on their existing
  historical baseline. No version, URL, asset ID, checksum or raw formal fixture
  is predicted in this planning change.

## Version-independent evidence schema

A future formal lock opts in by setting
`components.desktop.releaseChannel.nativeProvisioning.settingsAcceptance.schemaVersion`
to `2` and supplying the exact initial/restart SHA-256 values. Schema 2 preserves
all legacy checks and additionally requires:

| Evidence | Required values |
|---|---|
| Main `acceptance.json` | `modelRolesViewLoaded:true`, `searchProviderCatalogLoaded:true`, `manageCompatibilityDisclosureAbsent:true`, `providerOnlySearchRouting:true`, and `realOAuth:false`, `realModelRound:false`, `realSearch:false` |
| Each `initial-settings-readonly.json` and `restart-settings-readonly.json` | `modelRolesViewLoaded:true`, `currentWorkspaceReadOnly:true`, `searchProviderCatalogLoaded:true`, `providerOnlySearchRouting:true`, `fallbackProviderLabel:true`, `realSearch:false` |
| Provider IDs | non-empty strings; unique within each phase; identical across phases; includes `github-copilot-hosted` |
| Binding | byte-exact settings files match the lock hashes; fresh exact-source acceptance emits the same bytes and main fields |

The packaged source fixture also asserts that read-only **Manage** does not start
OAuth and does not expose or initiate a verification URL. Those are executed DOM
assertions, not fields currently emitted by `acceptance.json` or the per-phase
settings JSON. Ops must execute the exact fresh source fixture and retain its
screenshots/settings artifact for review, but must not invent JSON fields or
claim that a screenshot signature alone is visual acceptance.

Schema 1/historical evidence remains accepted under its original contract. The
new tests use synthetic temporary copies only; historical fixture bytes, proofs
and current native ASAR checks remain untouched.

## What packaged acceptance does and does not execute

| Feature lineage | Packaged acceptance boundary |
|---|---|
| alpha.28 budgets and compaction | Synthetic/contract and downstream coverage only; not a live budget exhaustion, compaction rescue or paid model turn in packaged acceptance. |
| alpha.29 routing CAS and search-model selection | Synthetic/downstream routing coverage only; not a live competing CAS operation or real search-model call in packaged acceptance. |
| alpha.30 navigation and provider-only Manage | Initial/restart packaged Electron navigation, read-only workspace/catalog state and provider-only routing are executed. OAuth, verification flow, real model response and real search remain forbidden/unperformed. |

`realSearch:false` is a required safety boundary, not a skipped assertion to be
silently upgraded to success. Installation, activation, restart and installed
machine acceptance remain outside this lane.

## Formal pin transaction after assets exist

Only after authenticated formal Release assets are available and independently
verified, update the lock, catalog, fixtures and bilingual/current docs together:

1. Bind the immutable Release/tag/commit/tree, installer and every required
   companion asset to authenticated IDs, sizes, SHA-256, SHA-512/SRI and remote
   digests. Keep live GitHub Release JSON/tag-chain binding; do not add a new
   formal ZIP transport requirement.
2. Copy each formal JSON fixture byte-for-byte from the parent authenticated
   proof, calculate and review its exact hash, add a new fixture directory, and
   preserve every historical fixture/proof unchanged.
3. Opt the new lock into `settingsAcceptance.schemaVersion:2`, bind exact
   initial/restart settings hashes and run fresh acceptance from the exact locked
   source. Fresh output must equal the formal deterministic leaves while the
   existing native ASAR inventory, graph, resolution and mutation guards remain.
4. Run the registered same-commit caller workflow `345664659`; record its exact
   Ops commit, run/attempt/job/artifact identities and byte hashes. A workflow
   green state alone is insufficient.
5. Run repository validators, Node tests and Pester. Parent release operations
   own GHA watchers and final activation; this lane performs neither.

## Official-first decision record

Official Core alpha.2 support advertised by Copilot alpha.30 is compatibility
scope, not authority to promote Core. Desktop alpha.2 PR 68 is separately owned,
draft and unqualified; this plan neither touches it nor changes the bundled Core
from alpha.1.

| Requirement / owner | Official or delegated primitive | Decision and retained gap | Retirement condition |
|---|---|---|---|
| Packaged ASAR/Core launch and public profile generations / Desktop | Official Core/Desktop primitives are already consumed. | Keep official primitives; retain release byte inventory, isolation and managed-provisioning guards. | Official distribution proves the same final-byte, isolation, ownership and rollback guarantees. |
| Settings slots, Remote transport, ordinary OAuth/chat/subagent / Core | Official extension and transport primitives are already delegated to. | Keep using them; do not add a Core shim or label the Copilot plugin official Core. | No custom feature implementation is retained for primitives already complete. |
| Copilot model-role/catalog and provider-only search routing / plugin | Built on official slots/Remote; provider behavior and safe fallback policy are plugin-owned. | Retain alpha.30 navigation, provider identity and provider-only routing acceptance. | A reviewed official provider supplies equivalent behavior, migration and packaged initial/restart acceptance. |
| Read-only Manage safety / plugin + packaged fixture | Official navigation primitives are reused; no-OAuth/no-verification interaction is a retained acceptance requirement. | Retain DOM assertions and schema-2 read-only evidence without inventing JSON leaves. | Equivalent official UI behavior and observable negative assertions pass in the qualified packaged runtime. |
| Immutable plugin acquisition, ownership and rollback / Desktop fork | Official mutation path does not establish this deployment’s verified-source transaction. | Retain the managed Release plan, receipts, staged swap/recovery and native ASAR verification. | Official path meets exact source/checksum, ownership, recovery, rollback and active-Session safety requirements. |

Re-evaluate against the exact official release before any future Core change.
Similar labels are not parity; unverified is not absent, and this plan authorizes
neither Core promotion nor removal of retained safety coverage.
