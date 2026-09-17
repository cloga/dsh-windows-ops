# Immutable Desktop release evidence

Files in each formal release directory are original published or release-run bytes. The deployment lock binds their raw hashes; JSON-equivalent text with different line endings is not equivalent evidence.

The scoped `.gitattributes` disables text conversion for this tree. Do not normalize, format, or regenerate old evidence files to accommodate a Windows checkout, and do not replace expected hashes with hashes of converted text. Add a new directory for a new independently verified formal release.

`tests/repository-content.test.mjs` exercises a real Git checkout with `core.autocrlf=true`: protected evidence must retain the locked hash, while an unprotected control must differ. The native release verifier remains unchanged and must reject altered bytes.

Rehearsal artifacts, synthetic test inputs, source builds and installed-machine observations have separate evidence scopes. None may be relabeled as formal published release evidence.

## Evidence directories

| Directory | Scope |
|---|---|
| `formal-cloga5/` | Historical `.cloga.5` formal release bytes; retained unchanged for regression evidence |
| `formal-cloga7/` | Historical `.cloga.7` formal release bytes; retained unchanged for regression evidence |
| `formal-cloga016-1/` | Actual immutable `0.1.6-alpha.1.cloga.1` Release, sequence 11; eleven original release/run JSON files |

The `.6` directory comes from [formal run 35197577605](https://github.com/cloga/deepseek-harness/actions/runs/35197577605), attempt 1, and [immutable Release 390539601 / tag `dsh-desktop-v0.1.6-alpha.1.cloga.1`](https://github.com/cloga/deepseek-harness/releases/tag/dsh-desktop-v0.1.6-alpha.1.cloga.1). Source PR45 merged as `fae12b69dcd28413518f68b5770e40f8eb2ff730`, tree `3ab1707c85ade70f7df5e33e95eb9991b53229f1`, from qualified candidate `6bf111473593dbd9b69cf50a2651b94172a75bac`. All eleven files were checked against independently recorded SHA-256 values before copying and again at the destination; they were not reformatted or synthesized.

| Raw file | SHA-256 |
|---|---|
| `release.json` | `20e546c5ca5cb9152d931be023e67de1472b7a6fd6e078f97806888d57ee0d32` |
| `build-receipt.json` | `402cfe07a52832e87faca6754cc7a8a1ed3258480966e973160eaa46b1e56b83` |
| `capability.json` | `a5b980de2540bf3c5ae036a41a6e380c4f4de7394ea57b1069a62cb58bdcaf68` |
| `desktop-provisioning.json` | `81ebdcc3ed17b46ed2f794986e905ace3bfd3843bcef8e5e0a62341ed945914a` |
| `helper-acceptance.json` | `871a618edbb7029779616df6dfec893518f96f88e5cf941d3162790c6f8b335b` |
| `acceptance.json` | `a50bbd79054a679fb013b603521e3497e33b45b233c455fabd01405d2a8f31d6` |
| `initial-desktop-plugin-provisioning-state.json` | `23b7b299146fbb517ad7c78e7e2a5ebb3a891db9a68dc21430412a3f6e38a492` |
| `initial-desktop-plugin-receipts.json` | `f78f9856e08874b1cf81d962179cc18777748f5e99a038b13bb30ec84aad5b70` |
| `initial-package.json` | `bb999f468d2015fe9b1d89415182779b2a68e0675cd651d20b8bdfe7916bae40` |
| `initial-packaged-graph.json` | `94bf996e09e8b6e42f5237e70bf4b97211da961f1737a8bb8f5241992ac9cd18` |
| `restart-packaged-graph.json` | `94bf996e09e8b6e42f5237e70bf4b97211da961f1737a8bb8f5241992ac9cd18` |

These are **actual formal release/source-acceptance evidence**, not rehearsal data. They do not establish the separate Windows Ops observer qualification, which remains pending its explicit CI run against these artifacts. No local Desktop installation/upgrade, restart, real OAuth or model round is claimed. Runtime descriptor `schemaVersion` is 1; nested `release.hostProtocolVersion` is 3. The logical `app.asar/dsh` package/file pins come from the separately hash-attested formal runtime descriptor; historical physical-wrapper hashes are not a `.6` wrapper identity.
