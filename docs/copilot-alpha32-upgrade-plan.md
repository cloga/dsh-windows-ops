# Copilot alpha.32 managed Desktop upgrade record

## Historical published pair

This record preserves `.cloga.14`/alpha.32 evidence; it is not the current target.
See the [alpha.33 upgrade record](copilot-alpha33-upgrade-record.md) for the
`.cloga.16`/sequence-27 repin and its separately pending hosted Ops qualification.
No historical hashes or success receipts below are transferred to that pair.

The historical managed target is immutable [Windows Desktop `0.1.6-alpha.1.cloga.14`](https://github.com/cloga/deepseek-harness/releases/tag/dsh-desktop-v0.1.6-alpha.1.cloga.14), sequence 24, source `a0f0144f4cddc90c45f8be93c61c0cd6cec470c7`, tree `8e636d110dcbd2e9662deb6d36e6e75b3f3fb0b2`, bundled Core `0.1.6-alpha.1`, and required [Copilot `0.4.0-alpha.32`](https://github.com/cloga/dsh-github-copilot/releases/tag/v0.4.0-alpha.32), source `76d190aed688e073df930adb3c753d2a749519c9`.

Formal Desktop run [`35549412610`](https://github.com/cloga/deepseek-harness/actions/runs/35549412610) attempt 1 passed build, immutable publication and remote managed Check. Installer asset `577940485` is 171,318,565 bytes with SHA-256 `81d73c63541d3b4464e27f1bae1651a3a996dfea4eaf89cc094f70c77b6eea0e`. Installed-runtime evidence binds executable SHA-256 `ff93b2388818f3b935e1bf0433117070ff27d290b26d465a7c8fd0be3f784608` and runtime descriptor SHA-256 `8cee8fcf841cc28235bc561aa89082e910bfc648cbfc953f735910bc19bfbe55`.

The plugin asset (`576880049`, 723,822 bytes) has SHA-256 `8f5b55488fd1bb9949ef8aa23b1bf2d41b3da52584b38497685ce07559290e32`; checksum asset `576880065` has SHA-256 `a8e7dd1906b0478d80d5540217d80bb09837079d46b17c71143597de2726c7c2`.

## Authenticated evidence

Parent verification independently bound all six Release assets to API size/digest and both checksum manifests. The three original Actions ZIPs are:

- build artifact `10617508954`: 171,328,455 bytes, SHA-256 `ed3c4b29bab29a6c7ceb1001c1ae2388a87026cce27fa43ec0fff881f6931e5a`;
- acceptance `10617778584`: 789,063 bytes, SHA-256 `f2e8f6ba810287a291f5e331e0f2c5f2a5b50cfcdd33dc663c668954ea9c5341`;
- observer `10618062861`: 787,871 bytes, SHA-256 `af6f3170790b5fbdb0ec23459fe898ec375638d9e732dfd70e47017fde583b70`.

A locked-handle audit matched all 70 extracted entries to their original ZIP sizes and SHA-256 values. The Ops lock tracks 20 authoritative JSON files under `formal-cloga016-14`: three build files and 17 acceptance files, including both `usage-readonly.json` phases.

Schema-2 settings evidence retains read-only workspace/catalog, provider-only routing, Fallback labels and exact version menus. `usageAcceptance` schema 1 additionally binds the required `account-quota-composer-usage` capability, zero signed-out trigger/text counts, absent usage surface, packaged-smoke instrumentation boundary, equal phases and account-readiness-before-usage ordering. `hostQuotaNoNetworkEvidence` is limited to the immutable plugin CI regression; no Host packet observation or live quota claim is made.

## Official-first decisions

Alpha.31 delegates token renewal and persistence to official `Models.getAuth()` and canonical credentials. The retained companion behavior is bounded Copilot managed-route HTTP-401 proof retirement, identical-token rejection, cooldown and generation-race handling. Retire it when official provider transport exposes equivalent provider-scoped rejected-token renewal and Desktop acceptance.

Alpha.32 reuses official OAuth ownership, strict public Remote codecs and the native Context meter. It retains normalized account quota snapshots and optional Copilot-Session composer presentation because official Core does not expose complete provider-reported quota, credits or Session attribution. Retire that surface when official APIs provide equivalent account semantics and a supported Session composer seam.

The plugin passed exact alpha.1 and alpha.2 Windows/Ubuntu compatibility, but separately owned draft Core alpha.2 Desktop PR68 remains unqualified. This release therefore retains bundled Core alpha.1 and does not call the plugin official Core.

## Native Ops qualification

Registered caller workflow `345664659` run [`35553019059`](https://github.com/cloga/dsh-windows-ops/actions/runs/35553019059) passed at exact Ops head `68a1218ef6a50f06870bae483d64f52d6de244aa`. Native job `106191374011` acquired the exact formal release, qualified the actual release fixture and observer without credentials, and removed private source/diagnostics.

Artifact `10619156852` original ZIP is 733 bytes with SHA-256 `dfc92806f244714b0022ce3e2d51e312f8215101b9ecd7a6b153691a82db15f3`. Its sole byte-bound 1,073-byte `qualification.json` has SHA-256 `bc90877cad62f68e7816d35035a1bbffa9a678b773d79884c2ae680941c3ec00`; it records 9,806 runtime files, exact archive-package identity, public metadata+CJS+ESM resolution, one observer/profile cleanup and three rejected request copies. Settings, version-menu and usage evidence remain driver-enforced locked formal inputs rather than invented summary leaves.

## Safety boundaries

No live OAuth, external-navigation success, model response, search/fallback, live quota, whole-carrier attestation, local installer upgrade, installation, activation or restart is claimed. Do not run current-machine Check against this future lock while the installed Desktop remains `.cloga.10`. Activation requires a fresh live-Session/process impact check and direct operator permission.
