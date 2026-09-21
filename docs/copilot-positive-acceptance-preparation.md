# Copilot positive usage acceptance: preparation and formal proof

Tracking: [Ops #210](https://github.com/cloga/dsh-windows-ops/issues/210) /
[PR #211](https://github.com/cloga/dsh-windows-ops/pull/211).
The initial verifier-preparation stage changed no deployment target, catalog, version
fixtures or formal hashes. That stage and the subsequent `.cloga.16` repin are
historical: the release owner independently authenticated Desktop `.cloga.16` /
sequence 27 / Copilot alpha.33 formal proof and authorized that repin, with bundled
Core unchanged at `0.1.6-alpha.1`. See its [formal upgrade record](copilot-alpha33-upgrade-record.md).
That historical target's fresh hosted Native Ops qualification separately passed in run `35575187267`
at exact Ops code head `a59f586df4e329c3bc8b3f885013fdb5493f4970`; formal proof
alone is not that qualification. This later documentation/evidence-only follow-up
records that code-head result, not a native rerun of its own head. The
[deployment lock](../deployments/windows-copilot.lock.json) and [authoritative guide](local-core-desktop-copilot.md#authoritative-baseline)
define the current published target; the [`.cloga.18` owning record](desktop-inline-composer-18.md)
records verified publication and **new independent hosted Native Ops qualification PENDING**.
Historical [`.17` qualification](desktop-external-links-17.md) remains target-bound.
No `.cloga.16` or `.17` success receipt transfers to `.18`. No live profile,
Core, installed Desktop or running Session is modified.

## Official selector contract, not a Core workaround

Official `0.1.6-alpha.1` source `0a15e36e7f82b6ed45af6fa9759f29b40dcd965d`
and `0.1.6-alpha.2` source `ddefc45fbc7f8e46dd73185e68295696d1297887`
require a selector argument for the Session snapshot hook:

- [alpha.1 SnapshotSelectorHook](https://github.com/deepseek-ai/deepseek-harness/blob/0a15e36e7f82b6ed45af6fa9759f29b40dcd965d/packages/client/store/src/contract.ts#L15-L20)
  and [renderer binding](https://github.com/deepseek-ai/deepseek-harness/blob/0a15e36e7f82b6ed45af6fa9759f29b40dcd965d/packages/client/ui-renderer/src/client/bind.ts#L21-L25).
- [alpha.2 SnapshotSelectorHook](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/client/store/src/contract.ts#L15-L20)
  and [renderer binding](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/client/ui-renderer/src/client/bind.ts#L21-L25).
- The keyed `useProjection('modelSelection')` overload is separate from this
  required-selector contract; see the official [projection store](https://github.com/deepseek-ai/deepseek-harness/blob/0a15e36e7f82b6ed45af6fa9759f29b40dcd965d/packages/api/session-controller/src/client/sessions/projection-store.ts).

Decision: consume the official selector primitive. Plugin alpha.33 source
`aa90fe434da8b2172faa1446afa0a0fd006afe00` corrects its Session-hook invocation;
[Plugin PR #157](https://github.com/cloga/dsh-github-copilot/pull/157) consumes
that official contract. Ops neither adds a selector fallback nor patches Core. Full official parity applies
only to this primitive, not to live Copilot quota or a complete feature replacement.
The plugin-owned account/quota UI and regression remain until an official equivalent
is verified against its requirements; no persistent data migration is introduced here.

## Optional hash-bound contract

Only an explicit `components.desktop.releaseChannel.nativeProvisioning.usagePositiveAcceptance`
object enables the new gate. It has three required fields:

| Field | Meaning |
| --- | --- |
| `schemaVersion` | Number `1`, not a string |
| `sha256` | Authenticated raw SHA-256 of the single `positive-usage.json` |
| `installedClientSha256` | Authenticated SHA-256 of the actual installed plugin `lib/client.js` |

Do not fill these hashes from unit inputs. For the historical authenticated `.cloga.16` /
alpha.33 formal target, schema 1 pins positive-file SHA-256
`a1515b7ee5af44ff8e7ad86fa07ce8faedaa13f157d02ad99e4a4f99ee174b45`
and installed Client SHA-256
`6d6a7df36c377b7485b31d45511a8b582f5b745a1030a7f6e4c35a181ad52435`.
The release owner's independent artifact authentication completed after initial
preparation; these hashes are no longer pending. The hashes alone do not establish
fresh Ops native qualification or local activation; the separate successful run
and its exact qualified driver are recorded below.
The formal verifier hashes the positive file; the fresh-source verifier independently
hashes newly produced output against the same reviewed proof. Its read-only observer also
hashes the actual isolated profile's Client bytes before source-owned cleanup.
The positive file binds the runtime descriptor and exact plugin source, and its `cases`
must equal `acceptance.json`'s `positiveCopilotUsage`.

The inspected Desktop producer consists of
`apps/desktop/tests/fixtures/copilot-usage-positive-smoke.ts`,
`copilot-usage-positive-browser.ts`, and their `copilot-release-smoke.ts` integration.
It runs positive cases **once, after the restart packaged-graph check**. There are no
initial/restart positive files or invented per-phase positive equality requirements.
The timeline must order restart account, signed-out usage, packaged graph, positive
usage and close, with one occurrence of each required event.

Each ordered canonical/preview case must report the actual producer fields:
`scope = packaged-renderer-released-client-synthetic-session-and-quota`, eligible
`provider`, `usageText` containing `7 used`, numeric `quotaReads = 2`, boolean
`sessionSubscribed`, `removedSessionHidesUsage`, `otherProviderHidesUsage`,
`clientDisposalRemovesUsage`, `applicationMountPreserved` and
`syntheticSiblingPreserved`, all exactly `true`; numeric `selectorErrors = 0`
and `forbiddenRemoteCalls = 0`; and
`hostTransport = not-provided-to-isolated-fixture`.
The top-level positive file must assert `originalSignedOutApplicationRestored === true`
and the same Host boundary, also matched by `acceptance.positiveUsageHostTransport`.
Truthy strings or numbers do not satisfy boolean requirements.

## Evidence boundary and remaining release work

The producer uses the actual shipped renderer, selector binding, SessionProvider/Slot
error boundary and released Client. Session snapshots, model selections, quota and the
mount are test-owned. It verifies both Copilot routes, hiding after removal or switching
to a non-Copilot provider, subscription/disposal, sibling preservation, and restoration
of the original signed-out application. No Host transport is supplied to the isolated
fixture. This is **not live account proof**, OAuth, a real model/search round, installer
upgrade qualification, or authorization to restart.

Existing signed-out usage schema 1, settings schema 2 and version-menu gates remain
required alongside positive proof. Signed-out initial/restart observations must be
deterministically equal and match the main acceptance leaves. Positive proof does not
replace those checks or claim packaged Host quota-network instrumentation.

The owning Node tests keep synthetic/rehashed negative inputs in temporary copies,
separate from the byte-exact authenticated formal fixtures. No synthetic result is
represented as published evidence. Run:

```text
node tools/validate-repository-content.mjs
node tools/validate-plugin-catalog.mjs
node --test tests/native-desktop-acceptance.test.mjs tests/native-asar-release-smoke.test.mjs
```

The initial preparation deliberately left baseline pins and README entry points
unchanged. The subsequent historical `.cloga.16` authorized repin synchronized that
formal target, optional positive-proof hashes and then-current bilingual guides. Formal run
`35569892548` attempt 2 succeeded; attempt 1's `EBUSY` copied-helper cleanup failure
remains history, not an explained or erased failure. Fresh hosted run `35575187267`
attempt 1 succeeded at code head `a59f586df4e329c3bc8b3f885013fdb5493f4970`,
including native job `106255672689` and all four jobs. Its authenticated 1,073-byte
raw summary has SHA-256
`26c85a04e6be4616168bba93d08e838e21c45077dd3043e27855c2b51ba096d1`.
Fresh positive proof was enforced by that exact qualified driver, not by invented
positive flags in the summary. The summary retains `wholeCarrierAttested:false`,
`modelResponseVerified:false` and `installerUpgradeVerified:false`.
The chosen outcome is **stage-only**: no local installation, activation or restart;
live account verification is deferred until a future human request. Neither this
proof nor its repin changes Core or authorizes local activation.
