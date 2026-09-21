# Official-first review: Desktop 0.1.6-alpha.1

## Scope and evidence

This bounded source/contract review compares official **`dsh-v0.1.6-alpha.1`**, commit [`0a15e36e7f82b6ed45af6fa9759f29b40dcd965d`](https://github.com/deepseek-ai/deepseek-harness/commit/0a15e36e7f82b6ed45af6fa9759f29b40dcd965d), with published fork **`0.1.6-alpha.1.cloga.2`**, commit [`65a236bd65f2971f98b11a0efd020b8860144924`](https://github.com/cloga/deepseek-harness/commit/65a236bd65f2971f98b11a0efd020b8860144924). The official tag resolves to that official commit, an ancestor of the fork; the fork tree equals qualified PR63's candidate tree. This is not runtime acceptance of an official-only replacement, a new release or activation authorization.

The [official release notes](https://github.com/deepseek-ai/deepseek-harness/releases/tag/dsh-v0.1.6-alpha.1) cover optional-plugin startup handling, module-route recovery and removal of configuration hot-reload rollback. Configuration hot reload is not Desktop package acquisition, staged profile replacement or managed installer recovery; source contracts decide those narrower comparisons.

**Documentation discrepancy:** the official Desktop README still describes upstream Node, `resources/dsh` and shared links as the packaged execution path. Exact executable sources already package ASAR, launch Electron in Node mode and install profile-resolution generations. Follow those sources, not the stale execution description. The README's in-place plugin mutation description is separately corroborated by implementation.

`Full` below means full for the named primitive, not the entire product. `Partial` identifies a concrete gap; `absent in the inspected path` is not a repository-wide absence claim. Later releases, unreviewed packages, paid-provider calls and official installer behavior were not qualified here. Apply the [mandatory upgrade checklist](local-core-desktop-copilot.md#official-first-upgrade-checklist) at each subsequent target.

## Decisions

### 1. ASAR, Electron Host and profile-resolution generations

**Purpose:** one first-party packaged runtime identity without installing Core in a user profile.

**Official parity: full for these primitives, already consumed.** Official [builder lines 60–78](https://github.com/deepseek-ai/deepseek-harness/blob/0a15e36e7f82b6ed45af6fa9759f29b40dcd965d/apps/desktop/electron-builder.config.mjs#L60-L78) packages `dsh` in ASAR with native executable unpacking. [main.ts lines 71–81](https://github.com/deepseek-ai/deepseek-harness/blob/0a15e36e7f82b6ed45af6fa9759f29b40dcd965d/apps/desktop/src/main.ts#L71-L81) selects `process.execPath`, `app.getAppPath()/dsh` and runtime resolution. [Host launch lines 105–123](https://github.com/deepseek-ai/deepseek-harness/blob/0a15e36e7f82b6ed45af6fa9759f29b40dcd965d/apps/desktop/src/host-process.ts#L105-L123) sets `ELECTRON_RUN_AS_NODE=1`; [Desktop Host lines 293–316](https://github.com/deepseek-ai/deepseek-harness/blob/0a15e36e7f82b6ed45af6fa9759f29b40dcd965d/apps/desktop-host/src/index.ts#L293-L316) creates the public generation and mounts `PluginPackages` before normal composition.

**Decision:** consume official primitives; retire claims that they are fork-only innovations, not the primitives themselves. No duplicate loader is justified. Preserve separately reviewed isolation and pnpm/helper executable separation. Before removing related glue, require initial/restart graphs, same first-party generation, private profile dependencies, native imports, import/require selection and correct pnpm/helper carrier behavior.

### 2. Final-byte inventory and packager metadata normalization

**Purpose:** checksums bind actual final runtime bytes, including unpacked backing, without post-pack resealing.

**Official parity: partial.** [runtime-tree.ts lines 116–211](https://github.com/deepseek-ai/deepseek-harness/blob/0a15e36e7f82b6ed45af6fa9759f29b40dcd965d/apps/desktop/src/runtime-tree.ts#L116-L211) already provides final-file inventory/verification. [prepare-dsh.ts lines 123–149](https://github.com/deepseek-ai/deepseek-harness/blob/0a15e36e7f82b6ed45af6fa9759f29b40dcd965d/apps/desktop/scripts/prepare-dsh.ts#L123-L149) copies/signs/seals, runs smoke and verifies again. That sequence does not apply the fork's pre-seal metadata transformer; inspected builder hooks do not perform its actual archive-plus-physical-sidecar check.

**Decision: retain narrow additions temporarily**, not a replacement inventory API: [runtime-package-metadata.mjs](https://github.com/cloga/deepseek-harness/blob/65a236bd65f2971f98b11a0efd020b8860144924/apps/desktop/scripts/runtime-package-metadata.mjs) and [packaged-runtime.mjs](https://github.com/cloga/deepseek-harness/blob/65a236bd65f2971f98b11a0efd020b8860144924/apps/desktop/scripts/packaged-runtime.mjs). **Sunset:** official packaging accounts for pinned packager transformations before sealing and validates final ASAR/unpacked bytes. Require real builder/Electron controls, modified/missing/extra/unpacked rejection, unchanged descriptor bytes and native/Host/browser smoke on the same tree; source-tree inventory alone is insufficient.

### 3. Verified plugin provisioning, manual ownership and rollback

**Purpose:** exact reviewed Copilot acquisition, preservation of unrelated manual plugins and recovery from failed activation.

**Official parity: partial management; required verified-source/transaction guarantees absent in the inspected mutation path.** [project-manager.ts lines 309–381](https://github.com/deepseek-ai/deepseek-harness/blob/0a15e36e7f82b6ed45af6fa9759f29b40dcd965d/apps/desktop/src/project-manager.ts#L309-L381) stops the Host and mutates the active profile in place, leaving partial changes on failure; [lines 384–436](https://github.com/deepseek-ai/deepseek-harness/blob/0a15e36e7f82b6ed45af6fa9759f29b40dcd965d/apps/desktop/src/project-manager.ts#L384-L436) implement pnpm add/update/remove/toggle. This is not checksum-locked Release acquisition, desired release-owned inventory, retained snapshots or journaled staged swap.

**Decision: retain custom transaction/provisioning additions.** Owners: fork [project-manager.ts](https://github.com/cloga/deepseek-harness/blob/65a236bd65f2971f98b11a0efd020b8860144924/apps/desktop/src/project-manager.ts), [github-release.ts](https://github.com/cloga/deepseek-harness/blob/65a236bd65f2971f98b11a0efd020b8860144924/apps/desktop/src/github-release.ts), [plugin-provisioning.ts](https://github.com/cloga/deepseek-harness/blob/65a236bd65f2971f98b11a0efd020b8860144924/apps/desktop/src/plugin-provisioning.ts) and [ownership contract](https://github.com/cloga/deepseek-harness/blob/65a236bd65f2971f98b11a0efd020b8860144924/apps/desktop/README.md#release-owned-plugin-provisioning).

**Sunset/migration:** official replacement must preserve required/optional behavior, immutable asset/checksum/commit identity, user ownership/enabled state, same-source manual reinstall, snapshots, frozen locks, staged peer validation, final-location readiness, rollback and interrupted rename recovery. Review receipt/source-lock/journal/plan conversion, existing and malformed/legacy profiles, optional failure and failed rollback. Never reset a profile to fit an official format; an “install” label is not parity.

### 4. Ancestor/module-resolution confinement

**Purpose:** prevent ancestor SDK/runtime loading outside the private profile or packaged module identity.

**Official parity: partial; broader isolation parity unverified.** Official generations are already consumed. The fork additionally uses [register-module-resolution-policy.mjs](https://github.com/cloga/deepseek-harness/blob/65a236bd65f2971f98b11a0efd020b8860144924/apps/desktop-host/register-module-resolution-policy.mjs) to restrict bare resolutions and carry immutable roots into default/nested Workers. The inspected official launch has no such preload; this difference does not prove every possible ancestor import succeeds officially.

**Decision: retain temporarily. Sunset:** equivalent official packaged ancestor-poison, optional-peer miss, required dependency, ESM/CommonJS, default/nested Worker and fallback-anchor cases pass. Workers discarding preload remain excluded; genuine callers using the exact fallback-anchor URL receive the same restriction. Remove the preload only after equivalent constraints are met without global resolution hacks.

### 5. Signed native update versus unsigned managed channel

**Purpose:** complete verified fork distribution without weakened publisher validation or silent interruption.

**Official parity: partial, a different distribution contract.** Official [update-coordinator.ts](https://github.com/deepseek-ai/deepseek-harness/blob/0a15e36e7f82b6ed45af6fa9759f29b40dcd965d/apps/desktop/src/update-coordinator.ts) uses `electron-updater` only with packaged `app-update.yml`, disables automatic download/install-on-quit and calls `beforeRestart`. [Builder lines 33–54](https://github.com/deepseek-ai/deepseek-harness/blob/0a15e36e7f82b6ed45af6fa9759f29b40dcd965d/apps/desktop/electron-builder.config.mjs#L33-L54) and [official signing/upload guide](https://github.com/deepseek-ai/deepseek-harness/blob/0a15e36e7f82b6ed45af6fa9759f29b40dcd965d/apps/desktop/README.md#upload-updates) describe a signed channel; unsigned test builds omit it. The inspected coordinator does not implement the fork's immutable sequence, copied-helper ACK or provisioning-bound completion.

**Decision: retain official signed and custom managed modes as mutually exclusive paths.** Fork owners: [managed-update-coordinator.ts](https://github.com/cloga/deepseek-harness/blob/65a236bd65f2971f98b11a0efd020b8860144924/apps/desktop/src/managed-update-coordinator.ts), [managed-update-completion.ts](https://github.com/cloga/deepseek-harness/blob/65a236bd65f2971f98b11a0efd020b8860144924/apps/desktop/src/managed-update-completion.ts) and [release workflow](https://github.com/cloga/deepseek-harness/blob/65a236bd65f2971f98b11a0efd020b8860144924/.github/workflows/desktop-fork-release.yml). **Sunset:** official distribution meets channel access, publisher/assets, monotonic versioning and full plugin-plan acceptance. Review app/install/signing identity, old sequence and handoff migration; test busy Sessions/drafts, cancel, pre-ACK failure, interrupted install and post-install inventory. Never disable signing checks to simulate parity.

### 6. Persistent notice and official index injection

**Purpose:** review-only persistent update notice and active-work impact without replacing normal Client initialization.

**Official parity: full injection primitive; partial/unverified notice behavior.** [Official assetHandler lines 199–217](https://github.com/deepseek-ai/deepseek-harness/blob/0a15e36e7f82b6ed45af6fa9759f29b40dcd965d/apps/desktop-host/src/index.ts#L199-L217) already emits `webserver/index-inject` and calls `renderIndexInjections`. The fork consumes this, not a new compatibility API. The inspected coordinator's check/install does not establish timed silent checks, sticky availability, review bridge or impact gathering; repository-wide UI equivalence is unverified.

**Decision: retain narrow notice/impact integration, use official injection.** The fork [notice decision](https://github.com/cloga/deepseek-harness/blob/65a236bd65f2971f98b11a0efd020b8860144924/.agents/notes/implemented/feature/2026-09-17-persistent-desktop-update-notice.md) owns requirements. **Sunset:** official initial/periodic silent checks, coalescing, Later persistence, active-work confirmation, ignored late results and cleanup pass packaged UI acceptance. Then remove redundant glue, not requirement coverage.

### 7. Settings Remote contracts and read-only acceptance

**Purpose:** actual Model roles/search-catalog readiness across restart.

**Official parity: full extension contracts, already consumed; feature replacement unverified.** [Models registration lines 128–142](https://github.com/deepseek-ai/deepseek-harness/blob/0a15e36e7f82b6ed45af6fa9759f29b40dcd965d/packages/client/ui-settings-models/src/client/index.ts#L128-L142) provides `settings.models.footer`; [Settings injection](https://github.com/deepseek-ai/deepseek-harness/blob/0a15e36e7f82b6ed45af6fa9759f29b40dcd965d/packages/client/ui-settings/src/client/index.ts#L43) declares `remote.settings`; [gateway Client](https://github.com/deepseek-ai/deepseek-harness/blob/0a15e36e7f82b6ed45af6fa9759f29b40dcd965d/packages/api/gateway/src/client/index.ts) implements traced Remote namespaces. Exact-tree comparison found no fork changes in those three directories or vendored Cordis.

Alpha.23 lacked a plugin-owned namespace declaration, not an official slot. **Decision: use official APIs; retain alpha.24's declaration fix and [packaged acceptance](https://github.com/cloga/deepseek-harness/blob/65a236bd65f2971f98b11a0efd020b8860144924/apps/desktop/tests/fixtures/copilot-settings-smoke.ts), not a Core shim. Sunset:** an official provider meets retained account/roles/router requirements with data/config migration. Render readiness alone is not provider parity; preserve positive load state, signed-out catalogs, dependency admission and restart checks.

### 8. Composer readiness and fixture reliability

**Purpose:** distinguish pending visible rows from ready current-query results and clean up process-based qualification.

**Official parity: full pending interaction semantics; partial observability/setup.** Official [MenuView](https://github.com/deepseek-ai/deepseek-harness/blob/0a15e36e7f82b6ed45af6fa9759f29b40dcd965d/packages/client/ui-input-trigger/src/client/MenuView.tsx) retains rows during refinement. The [controller](https://github.com/deepseek-ai/deepseek-harness/blob/0a15e36e7f82b6ed45af6fa9759f29b40dcd965d/packages/client/ui-input-trigger/src/client/controller.ts) consumes pending Enter/Tab and is byte-identical between compared trees. Fork [MenuView](https://github.com/cloga/deepseek-harness/blob/65a236bd65f2971f98b11a0efd020b8860144924/packages/client/ui-input-trigger/src/client/MenuView.tsx) adds truthful readiness/query/source attributes; its [browser fixture](https://github.com/cloga/deepseek-harness/blob/65a236bd65f2971f98b11a0efd020b8860144924/apps/web/tests/reference-composer.e2e.ts) waits for the exact reference source, not every provider.

**Decision:** retain observability and reliable acceptance, preserve the official controller. Fork [collection verifier](https://github.com/cloga/deepseek-harness/blob/65a236bd65f2971f98b11a0efd020b8860144924/apps/desktop/scripts/verify-release-test-collection.mjs) and [fixture ownership helper](https://github.com/cloga/deepseek-harness/blob/65a236bd65f2971f98b11a0efd020b8860144924/apps/desktop/tests/fixtures/project-fixture-work.ts) are qualification infrastructure. **Sunset:** equivalent official current-query/source/readiness observability, complete disjoint test discovery and quiescent teardown. Retire redundant instrumentation only with equivalent accessibility/negative controls, not by deleting acceptance or extending production deadlines.

## Outcome and follow-through

No immediately safe unconditional code removal was established. Credit and consume existing official primitives; retain only documented gaps where those requirements apply. Re-evaluate each exact future target, migrate configuration/data safely and pass replacement acceptance before deleting obsolete adapters/path-specific tests; retain user-visible tests.

The fork's [formal run 35271210350](https://github.com/cloga/deepseek-harness/actions/runs/35271210350) and [Release](https://github.com/cloga/deepseek-harness/releases/tag/dsh-desktop-v0.1.6-alpha.1.cloga.2) concern the historical `.cloga.2` fork combination, not an official-only replacement. [Historical `.cloga.2` native Ops qualification](local-core-desktop-copilot.md#historical-cloga2-qualification) separately passed in run `35278350619` at `243c33d286f19d9e4c608e238a52de2b9a136b9e`, without whole-carrier, real search/OAuth/model or installed-upgrade proof. Earlier pre-observer failure `35276462350` remains unexplained; success at the diagnostic head does not prove a root-cause repair. This also does not establish official-only replacement parity. See the [plugin review](official-first-copilot-024.md) for companion-specific decisions. The [deployment lock](../deployments/windows-copilot.lock.json) and [authoritative guide](local-core-desktop-copilot.md#authoritative-baseline) define the current candidate target; the [`.cloga.17` owning record](desktop-external-links-17.md) distinguishes verified publication from still-pending fresh hosted Native Ops qualification. Historical `.cloga.2` success cannot transfer. No local installation, profile edit or restart results from this documentation review.
