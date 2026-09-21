# Desktop cloga.18 / Copilot alpha.35 delivery record

Tracking: [Ops #228](https://github.com/cloga/dsh-windows-ops/issues/228).
Use [the canonical release checklist](core-upgrade.md#bounded-release-debugging)
and its [UI fixture appendix](small-ui-change-validation.md); this is an exact
published-delivery record, not a second process or local activation authorization.

## Published identity and verification

The authorized target is immutable [Desktop `0.1.6-alpha.1.cloga.18`](https://github.com/cloga/deepseek-harness/releases/tag/dsh-desktop-v0.1.6-alpha.1.cloga.18),
sequence **30**, Release **393339432**, with bundled Core version unchanged at
`0.1.6-alpha.1` and required [Copilot `0.4.0-alpha.35`](https://github.com/cloga/dsh-github-copilot/releases/tag/v0.4.0-alpha.35).
The explicitly authorized Core Client layout change is included; an unchanged
Core version is not a claim that its Client bytes are unchanged. Alpha.35 retains
published alpha.34's Model roles retirement and hides unavailable Session credits
and invalid reset dates. Do not restore the retired role UI.

| Binding | Exact identity |
|---|---|
| Desktop source / tree | `202dd0a2022da939aa424ac1714cd12ce6d902ef` / `108e887e5cb749228a637e0b8577ef23af79901b` |
| Reviewed source | [PR #112](https://github.com/cloga/deepseek-harness/pull/112), head `ec2c2ceb41bdd85f98cf547dacfc08740dfc1997` |
| Formal workflow | [Run `35661128403`](https://github.com/cloga/deepseek-harness/actions/runs/35661128403), attempt **1**, all **3 jobs SUCCESS**, including remote Check |
| Release plan / lockfile SHA-256 | `62712cfc1c913d58e789a5bec520fa1bc5cc66831e30c6c5af0fdc4408efb27b` / `f14668d76eee14646543910878fc400fcbfa2a848b1ea177f2fc1cb2d0f21322` |
| Copilot source / tarball | `6554417dc9a7544865e6c1bbdebf8b9a10e0a7af`; asset `579078676`, 705,000 bytes, SHA-256 `ec4f0fa24b45d94686a396b2558ef6b7fc5d521b9d94e65dcff9f772421f496d` |
| Installed EXE / runtime descriptor SHA-256 | `e2703e24daacfcbaad8347fd00356b39b224c81aa502cf7d54bd06a341af9848` / `15dd038067c58882e2efa6f4465e4f7bcf98f86612e4d5a484d01286080b329d` |
| Released Client / native geometry SHA-256 | `7b4566ef30e1c3c11e64aee527cea8bc5adbf0f22ca356cc8bd3ab07661fd368` / `91f92a072b1c4ef80cba49e0c90fb6b03dc3d8e025dd0c6d9347e3296fff4ad3` |
| Existing positive proof SHA-256 | `931370e7c0d2b7408553d51f0c45d7416955151aa4e06ec8b5757f4671377354` |

The parent authenticated GitHub metadata and acquired original bytes through the
verified `cloga` gate on **2026-09-21**. `collector-final-report.json`,
`parent-formal-verification-alpha35.json`, `independent-expected.json` and
`archive-audit.json` record successful source/metadata/asset verification and original
Actions ZIP/member-to-extracted-byte binding, not merely green CI. The six public
assets remain the installer and its established companion metadata/checksums:

| Public asset | Asset ID | Bytes | SHA-256 |
|---|---|---:|---|
| `cloga-deepseek-harness-0.1.6-alpha.1.cloga.18-win-x64.exe` | `580004399` | 171,318,864 | `b634a518555133ef128c29137329ace16993271fd88c11e458bbee760934eb86` |
| `build-receipt.json` | `580004386` | 3,509 | `723d8ca68fa1b4e413ebb0de787c7d86ba6f87e2a938ec2c4f586d38334c0952` |
| `desktop-provisioning.json` | `580004538` | 1,309 | `bab476be356f11f292f91acedbd04bf0aca737832c5ec3c5da56e89ccd6e7082` |
| `release.json` | `580004557` | 2,565 | `71031e90097c3fff40f943eae7972153fa0a77e0083305a2d023b18f801dba7e` |
| `SHA256SUMS` | `580004361` | 380 | `c2da2517fe01cd41b42ca0f5557e19fe7d46034fa32614accc97126389fc4bf8` |
| `SHA512SUMS` | `580004374` | 476 | `478c63f31e3b5a1f944e47d04c4fe867a972f383256ece278fd6be2fb20b9ce3` |

## Acceptance scope and pending work

- **Current settings schema 3:** initial/restart `accountViewLoaded` and
  `retiredModelRolesAbsent` are true, with read-only search catalog, provider-only
  routing and Fallback labeling. Historical schema-2 workspace/role observations
  retain their meaning only for their historical targets. Signed-out usage and
  exact About-menu identity remain separate gates.
- **Native composer:** actual packaged InputBar/StatsPills and released Client,
  widths **1280 and 400**, native time/token and Copilot dialogs. History is
  **synthetic persisted history in an isolated home**; quota comes from a
  **signed-out Host with no credentials**. This is not live billing or account proof.
- **Separate positive fixture:** actual renderer/released Client/SessionProvider/Slot,
  but synthetic Session/quota and **no Host transport**. Do not conflate it with
  the native composer phase or a real eligible account.
- **Fresh evidence:** enforce semantic geometry and source/runtime/Client bindings,
  not cross-run pixel/hash equality. Strict same-run raw/embedded correlation and
  sealed observer snapshots remain mandatory; no new qualification-summary flags.
- **Independent hosted Native Ops qualification: PENDING.** The formal release's
  packaged acceptance is not this new Ops run; historical `.17` run `35595040585`
  and `.16` successes cannot transfer. Core alpha.2 remains a separate, unqualified
  preparation target.

The contradictory green `c912a01…` rehearsal remains rejected historical evidence
([observer lesson](native-composer-acceptance-preparation.md#practice-seal-observation-evidence-before-owned-shutdown)).
The prior `b1bf04d…` formal canary HTTP 403 remains a failed historical attempt.
The reviewed diagnostic PR #112 merged; the subsequent formal run published the
exact merged source above without authentication or policy weakening. Later success does **not**
establish the 403 root cause or retroactively qualify either earlier attempt.

Delivery is explicitly **stage-only**: no local install, activation, restart,
OAuth, live quota, real model/search call or installer-upgrade claim. Live account
verification awaits a future human request. The interactive Windows installer is
the supported entry point, not a substitute Core tarball; startup provisioning
retains the locked dependency registry and normal TLS, not a blanket offline claim.

## 中文摘要

当前目标为已发布且由父代理独立核验的 Desktop `.cloga.18`／序号 30／Copilot alpha.35；
Core 版本仍为 alpha.1，仅包含明确授权的 Core Client 布局变更。正式 run `35661128403`
attempt 1 的三个 jobs（含 remote Check）成功，六资产及原始 ZIP 字节绑定已核验。
Settings schema 3 确认账号视图就绪和 Model roles 已退役，不恢复旧 role UI；alpha.35
隐藏不可用 Session credits 与无效 reset 日期。真实原生 renderer 的 1280/400 布局与弹窗
使用合成持久历史和无凭据的 signed-out Host；独立正向 fixture 使用合成额度且无 Host transport。
**新的独立 hosted Native Ops 验收仍为 PENDING**，历史成功不可移用。同次证据严格关联，
跨次按动态几何语义验收，不要求像素哈希相等。保持 stage-only，不安装、激活或重启；
真实账号验证另待人类请求，既往失败证据不改写。
