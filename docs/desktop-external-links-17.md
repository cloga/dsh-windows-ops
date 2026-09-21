# Desktop cloga.17 external-link qualification

Issue [#214](https://github.com/cloga/dsh-windows-ops/issues/214) synchronizes the published [Core PR #96](https://github.com/cloga/deepseek-harness/pull/96) release into the Windows Ops deployment contract. Companion Core PR #108 reconciled the released baseline without changing the intended link behavior.

## Target and scope

The lock selects immutable [Desktop `0.1.6-alpha.1.cloga.17`](https://github.com/cloga/deepseek-harness/releases/tag/dsh-desktop-v0.1.6-alpha.1.cloga.17), sequence **28**, Release **392847203**, source `f25506b4ad190ce090b8a4e9602c7ad36179db6b`, tree `24f46ed7803bcafdebc326da5c469712868481bc`. The reviewed PR head is `49d22a555429e1c08efbd4af5f04878b3628b28d`; its tree is identical to the release tree.

Bundled Core stays `0.1.6-alpha.1` and the complete Copilot `0.4.0-alpha.33` source/artifact/checksum lock is unchanged. This is not an alpha.2 promotion or adoption of separately published Copilot alpha.34. The latter's removal of Model roles is not included in this Desktop pin.

The shell sends user-requested HTTP(S) links to the system browser while retaining popup denial, owned application documents, recovery checks and other-scheme rejection. Browser handoff failures use redacted localized advice. Source acceptance drives real Electron DOM anchors/window.open with a substituted OS opener; it does not establish real default-browser page loading or successful OAuth.

## Original publication evidence

[Formal run `35583602522`, attempt 1](https://github.com/cloga/deepseek-harness/actions/runs/35583602522) succeeded through build, protected publication and shipped managed-update discovery. The exact six-file public inventory is the Windows installer plus `desktop-provisioning.json`, `build-receipt.json`, `release.json`, `SHA256SUMS` and `SHA512SUMS`. Independent readback checked the immutable release/tag/source, sizes, all remote asset digests, both checksum manifests and raw/canonical metadata hashes.

| Item | Exact original identity |
|---|---|
| Installer | asset `578750120`, `cloga-deepseek-harness-0.1.6-alpha.1.cloga.17-win-x64.exe`, 171,319,360 bytes |
| Installer SHA-256 | `2201f5f513cb68bd699fca0c8fa7d254a3baf2a63e53be21f3ddc6d3d5e9e22f` |
| Manifest | asset `578750249`; raw SHA-256 `9464b33190d77a54cfa6ef944caf123bdc5e7147efd5bcbfad780c3c64043045`; canonical self-hash `534998fd1838176a1f5114ae47db59048c8da1f1f889eb5193823423edd30af8` |
| Build receipt | asset `578750102`; raw SHA-256 `08682b27ed6fb6e32c3348ad3c89bbd688e1420e7fcc347c39e9ed45ac3cf585`; canonical self-hash `7adbc4f2b32640caf714e43a490dceb5d7d1b54f31440f5338f3b1a86c0bc984` |
| Provisioning | asset `578750240`; SHA-256 `05a115d633d56fb1c8e99df012884028955958f6193ec2f480f40245f447d6ad`; complete alpha33 plan preserved |
| SHA256SUMS | asset `578750075`, 380 bytes; SHA-256 `b391d23c64939aa404677f3a04e8ea6d01dd8cdb46a602286cfc14175c0230cc` |
| SHA512SUMS | asset `578750091`, 476 bytes; SHA-256 `8492b75bbfae62f495c44fcb71753ef2074df3c9da2aae07979048ce82b247ab` |
| Inner application EXE | SHA-256 `43854b829594b742df3810045779cd89f552257a484611a5a6a0aa7ddc6cbe66` |
| Runtime descriptor | SHA-256 `eca8a91da4737f625716323d0be8a51156b24934183904a41d06599ffafe36bd` |

The inner application's numeric PE product version is `0.1.6.0`, company `GitHub, Inc.`, product/file description `DeepSeek Harness (cloga)`, and signature state `NotSigned`. These are distinct from the installer's full SemVer metadata. Do not derive inner PE facts from the installer version.

The [new formal fixture generation](../tests/fixtures/desktop-native-verified-release/formal-cloga016-17/acceptance.json) contains byte-exact files from that publication and its formal acceptance artifact, not the rehearsal. Source-bound initial/restart graph, account/settings/version-menu, signed-out usage, positive synthetic Session/quota, copied-helper and separate failure-cleanup evidence passed. The unchanged Core entrypoint and three required built-file hashes/sizes are compared to the actual new descriptor, not inferred from version equality. Existing .14/.16 fixtures remain untouched.

## Fresh Windows Ops qualification

**Passed at exact Ops code head `bb7a0a366e789b19918be6d8a6e40266c46a94f9`.** Registered caller [run `35595040585`, attempt 1](https://github.com/cloga/dsh-windows-ops/actions/runs/35595040585), including native job `106318363183` and all four jobs, succeeded for `confirm_version=0.1.6-alpha.1.cloga.17`. It verified source/lock/asset identity, extracted the installer as data, and ran the maintained isolated observer and source-owned checks. The [original new summary and acquisition record](../tests/fixtures/desktop-native-verified-release/ops-cloga016-17/README.md) are retained separately from all prior generations.

Authenticated artifact `10636930492` is a 731-byte original ZIP, SHA-256 `bde376fbf0325e81b30748478b8de365f26097ecb936919e4d8e6fa8babaa9e5`. Its sole raw `qualification.json` is 1,073 bytes, SHA-256 `6ad0298788578353c6ef306ddeec225c785d335631f06b7d38c1f879cc526fee`. It reports 9,806 runtime files, exact application package `cloga-deepseek-harness-desktop@0.1.6-alpha.1.cloga.17` with SHA-256 `9dbc8d4f5239e17db08be4745accc48661396bbe538ce5cf5be461d461cde7e4`, public metadata/CJS/ESM resolution, one observer call, private-profile cleanup and three rejected descriptor-digest/version/absent-home requests. Whole-carrier, model-response and installer-upgrade flags remain false.

This documentation/evidence-only follow-up records native execution at `bb7a0a3`, not at its later commit or eventual merge SHA. Runtime, test, workflow, lock and all 21 formal files remain byte-equal to that qualified head. Final-head ordinary CI and parent review are required before merge; no prior .16 run or receipt is relabeled as .17 evidence.

The prior approved .16/alpha33 native qualification, including run `35577921833` at `cd384495ac2fd0c850b3c8cd93223d35c4bc83a0`, remains historical in the [alpha33 record](copilot-alpha33-upgrade-record.md). Alpha.2 adapters and their negative tests remain retained but do not promote Core.

## First Ops attempt and failure-only diagnostics

[Ops run `35590167413`, attempt 1](https://github.com/cloga/dsh-windows-ops/actions/runs/35590167413) used exact combined code head `f74c18aa86a2d22efee19c6145cf2275803bcb8d`. Its three prerequisite jobs passed; native job `106303100301` failed during the source-owned startup fixture before the observer. The original summary remains [not-ready failure evidence](evidence/desktop-links-17-initial-failure/qualification.json), not .17 qualification: `observerCalls: 0`, `profileRemoved: null`, code `desktop-startup`, recorded phase `initial:launch`.

Parent acquisition authenticated artifact `10634880734`, `native-asar-qualification-35590167413-1`: original ZIP 365 bytes, SHA-256 `8d6847a87416f29317ed96028bc4ea32f6d025aa58dad1b49ac0ff2993da993e`. Its sole safe `qualification.json` is 352 bytes, SHA-256 `99441ece9619e6329ce5410c549293cdf54110f6c14f06e4534966ffccdf96bf`; the committed file preserves those original bytes. No rewritten field or successful .16 receipt supplies missing .17 evidence.

The earlier diagnostic vocabulary omitted the fixture's version-menu and usage markers, so `initial:launch` is only its last recognized event, not proof that launch or menu observation failed. The underlying startup cause is unknown. Failure-only Ops diagnostics now recognize the source's actual version-menu/usage markers and restart-only positive-usage marker. They report only fixed categories for complete owned GitHub HTTP/redirect/policy messages inside the exact startup wrapper, or the exact generic `fetch failed` message. HTTP403 does not establish rate limiting or an authentication cause; generic fetch failure exposes no DNS/TLS/reset cause. Existing higher-priority locator, launch, module, native, access and missing-file classifications retain precedence. Messages not admitted by these exact new rules keep the existing classification; conflicting new categories do not select an arbitrary category. Raw errors, URLs, paths, headers and body text are never emitted.

Producer inspection is pinned to released Core `f25506b4ad190ce090b8a4e9602c7ad36179db6b`: `apps/desktop/src/github-release.ts` supplies the bounded status message; `plugin-source.ts` supplies its fixed subject; `startup-error.ts` flattens error messages; `renderer/startup.js` displays them; `tests/fixtures/copilot-release-smoke.ts` wraps startup text and records phases. No Core/release bytes, settings, credentials, timing, retry policy or acceptance assertions change. New diagnostics require reviewed new code and a separately approved fresh qualifier; a subsequent pass cannot retroactively diagnose this failed attempt.

Ordinary Windows CI `35593395998` on diagnostic head `c0bc3646c6ae9533bd56c17096a7aad1f23d7d4e` failed the LF-only test boundary assertion before the PowerShell guard executed; 1,150 other tests passed. A controlled reproduction failed with CRLF and passed with LF; the original CI checkout bytes were not retained. The `bb7a0a3` correction normalizes only the in-memory workflow test input, checks identical LF/CRLF guard statements, retains both missing-marker negatives and executes unchanged privacy/type/unknown-field controls for both variants. Workflow, diagnostic and publication/evidence bytes were not normalized or changed. Its ordinary checks passed before the newly approved native run. The later native success does not prove that diagnostics or this test correction repaired the first startup failure.

## Installation and evidence limits

`installerUpgradeVerified=false`; real OAuth, model rounds, search and live account quota are not established. A source-owned packaged startup/restart and isolated native-ASAR observer are not execution of NSIS or the operator's installed profile. The installer remains unsigned by the established fork channel, not a weakened signature exception.

This synchronization changes source-controlled pins and evidence only. It does not run the installer, launch local Desktop, write its reserved profile, install/activate plugins or restart any Session. Follow the [authoritative deployment guide](local-core-desktop-copilot.md) only after qualification/approval, and preserve the separate interruption consent required for an eventual installation.

## 中文摘要

本次将 Ops 锁同步至已发布的 Desktop `.cloga.17`／序号 28，保留 Core alpha.1 和 Copilot alpha.33；不提升 alpha.2，也不采用另行发布的 alpha.34。正式发布 run `35583602522` attempt 1 已通过，六个不可变制品及校验和已独立核验；新增 formal-cloga016-17 原始证据，不重写旧证据。新的 Native Ops run `35595040585` attempt 1 已在精确 code head `bb7a0a366e789b19918be6d8a6e40266c46a94f9` 通过四个 jobs；原始 ZIP 与唯一 summary 的大小、哈希和内容已认证，新增 ops-cloga016-17 保留原件。

链接测试通过真实 Electron 点击路径，但替换系统浏览器打开函数；不证明真实浏览器加载、OAuth 或安装升级。首次 run `35590167413` 的原始 not-ready 失败记录保留不变，根因仍未知；固定词汇诊断改进和后续通过不能证明它被修复。另一次普通 Windows CI 在只识别 LF 的测试边界断言失败；受控复现中 CRLF 失败而 LF 通过，未保留原始 CI checkout 字节。修正仅规范化内存中的测试输入并实测两种行尾，不改变产品或证据字节。本次后续提交仅记录 qualified code head `bb7a0a3` 的成功，不宣称其自身或 merge SHA 执行了 Native Ops；仍须最终普通 CI 和父代理审核。当前不安装、不启动 Desktop、不写 profile、不激活或重启。
