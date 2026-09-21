# DSH 0.1.6-alpha.2 official-first assessment

## Scope and evidence limits

Tracking: [Ops #181](https://github.com/cloga/dsh-windows-ops/issues/181).
Official target: [dsh-v0.1.6-alpha.2](https://github.com/deepseek-ai/deepseek-harness/releases/tag/dsh-v0.1.6-alpha.2), exact commit `ddefc45fbc7f8e46dd73185e68295696d1297887`.

This is a source-review assessment and migration worklist, **not** a qualified
deployment lock, installed-state report or runtime acceptance. The existing
`deployments/windows-copilot.lock.json` remains authoritative until replacement
artifacts are independently qualified. No installation or restart is authorized
by this document. Follow [the upgrade workflow](core-upgrade.md).

本页记录源码对照和迁移决定，不代表 alpha.2 已适配、已部署或可直接升级。
优先官方实现，但不能因为功能同名就丢失日历调度、冷会话恢复、完整性校验或账号权限保证。
现有部署锁保持不变；安装和重启仍另行授权。

## Strict native compatibility preparation

Ops #181 prepares the shared native descriptor validator for exact Core
`0.1.6-alpha.2` → Host protocol **4**, matching the exact official
[host-protocol source](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/apps/desktop/src/host-protocol.ts).
The independently pinned caller version selects the expectation; the descriptor
cannot select its own policy. Alpha.1/protocol 3 remains valid, alpha.1/4 and
alpha.2/3 fail closed, and future versions do not inherit protocol-4 acceptance.
The `0.1.6-synthetic-local.1`/3 fixture proves only synthetic integrity, not a
release or runtime. Hash/version rejection still occurs before child launch.

Descriptor and embedded release schemas stay **1**, provisioning plan/state/store
stay **1**, and managed capability/release manifest stay **3**. Both
`native-asar-runtime.mjs` and `native-electron-probe.mjs` share the validator;
public resolution APIs and the existing Host/PluginManager ownership are unchanged.
The formal evidence verifier and fresh release smoke require alpha.2's initial
and restart read-only Model roles/search-provider evidence regardless of sequence;
alpha.1's historical sequence-12 threshold is preserved. Settings readiness is not
real search, OAuth or model proof; `installerUpgradeVerified:false` stays false.
No legacy rc.2 build/install tooling or runtime trust boundary is changed.

**This is pre-publication preparation, not a qualified or deployed alpha.2 baseline.**
The current candidate Ops target is published Desktop `0.1.6-alpha.1.cloga.17` /
sequence 28 / Core `0.1.6-alpha.1` / Copilot `0.4.0-alpha.33`. Its published artifacts
and source-bound formal run `35583602522` attempt 1 SUCCESS are independently verified;
**fresh hosted Native Ops qualification is pending** ([owning record](desktop-external-links-17.md)).
This runtime-only maintenance does not promote Core alpha.2 or authorize local installation/restart.
Historical `.cloga.16` Ops runs `35575187267` at `a59f586df4e329c3bc8b3f885013fdb5493f4970`
and `35577921833` at `cd384495ac2fd0c850b3c8cd93223d35c4bc83a0` stay in the
[alpha.33 record](copilot-alpha33-upgrade-record.md); neither these nor `.cloga.14`/alpha.32
qualification transfers to `.17`. Earlier `.cloga.2`/alpha.24 records
remain historical Ops evidence and the separately owned Core installer-upgrade
fixture baseline, not the current Ops deployment. Unit tests use temporary inert
copies, never relabeled formal evidence. After alpha.2 publication, a separate
reviewed promotion must independently verify immutable assets/source/hashes,
update `deployments/windows-copilot.lock.json`, `catalog/plugins.json`, formal
release fixtures and their dependent assertions/docs, and obtain fresh hosted
Native Ops qualification. Old source/qualification receipts cannot certify the
new pair. This preparation neither installs/activates/restarts nor changes
profiles or state.

本节仅记录发布前严格兼容准备，不宣称 alpha.2 已发布、已通过正式验收或已部署。
当前候选 Ops 目标为 alpha.1.cloga.17/sequence 28/Core alpha.1/Copilot alpha.33；
发布制品与正式 run `35583602522` attempt 1 SUCCESS 已独立认证，但全新 hosted Native Ops
qualification **仍待执行**，不能继承 `.16` 或 `.14` 的记录，详见[外链维护记录](desktop-external-links-17.md)。
保持 stage-only，不安装、激活或重启，live account 验证留待后续人类请求；
旧 `.cloga.2`/alpha.24 仍是历史 Ops 证据和 Core 安装升级 fixture 基线，而非当前 Ops 部署。
Alpha.2 发布后仍须另行核验制品、评审提升 lock/catalog/fixtures，并执行新的 hosted qualification。

## Alpha2 combined packaged evidence preparation

Ops #181 prepares an explicit adapter for the alpha.2 candidate's combined
packaged evidence. This is source compatibility work, not qualification or
promotion of an unpublished release. Historical ordinary acceptance and original
formal/Ops fixtures remain unchanged. This alpha.2 preparation does not replace
the current candidate `.cloga.17`/alpha.33 target or substitute for its separate,
still-pending fresh hosted Native Ops qualification. That independent runtime-only
maintenance preserves bundled Core alpha.1; it does not qualify alpha.2. Historical
`.cloga.16` qualification remains in its [owning record](copilot-alpha33-upgrade-record.md).

Historical combined-format formal evidence requires the complete original `functional-results.json`,
finalized `failure.json`, `observer-cleanup.json` and last-written
`packaged-suite.json` graph, with ordinary `acceptance.json` absent. Provisional
functional observations are not ordinary acceptance or suite success. The reviewed
exact version and declared format select the adapter; file existence, broad
version ranges and catch/fallback cannot select another interpretation. Source,
tree, run/attempt, plan and raw artifact/receipt hashes must remain bound to the
same independently reviewed evidence. Never rename or reinterpret one receipt as
another.

The explicitly reviewed `combined-suite-v2` format requires schema-2 functional
observations and schema-2 fresh ordinary acceptance, with mandatory
`positive-usage.json`. It does not replace `combined-suite-v1` or legacy alpha.1
readers, tests or original evidence. Do not infer v2 from a filename, plugin
version or extra field, and do not fall back from an unknown or invalid format.

Both imported and fresh v2 paths hash the bounded original positive record and
bind its runtime, plugin source and installed Client digest to the independently
reviewed original Copilot alpha.33 artifact policy. Positive cases must agree with
the functional/ordinary receipt, and the formal summary binds the raw positive
hash as `packaged.positiveUsage`. A well-formed digest alone is not original-byte
parity; production evidence cannot select another Client policy.

The required observations exercise `github-copilot` and `github-copilot-preview`
through the actual renderer and Session/Slot APIs with synthetic Session/quota
data and no Host transport. They cover inherited Session scope, explicit absence,
removed and closed Sessions hiding and restoring usage, provider switching and
restoration, visible Client disposal, subscription cleanup and restoration of the
original signed-out application. Hidden signed-out controls alone cannot prove a
working eligible Session. Fresh window IDs, timings and receipt bytes belong to
that run and must not be compared byte-for-byte with another formal run.

Pure unit tests use explicitly synthetic Client bytes and real hashing under a
test-only admission policy; they exercise parsing and rejection, not the hosted
released Client or original-archive parity. Only the separately qualified hosted
run can supply that released-Client renderer evidence. Neither scope establishes
live quota, OAuth, model/search, Session billing or installed upgrade acceptance.
This v2 work remains source preparation. The separately reviewed current candidate
is `.cloga.17`/Core alpha.1/Copilot alpha.33; fresh hosted Ops qualification is pending.
Historical `.cloga.16` qualification at `a59f586…` remains bound to that code head.
After merging the v2 adapter/test changes, historical run `35577921833` passed at exact
combined head `cd384495ac2fd0c850b3c8cd93223d35c4bc83a0`. That verifies only the then-unchanged
`.cloga.16` alpha.1 target, not `.cloga.17` or promotion/hosted qualification of alpha.2.

Fresh Ops qualification is a different contract. `tests/native-asar-release-smoke.mjs`
uses the real ordinary Core owner with a successful read-only resolver observer,
not the throwing combined canary. Its ordinary acceptance is finalized only after
cleanup. Resolver, request-copy, snapshot and removal checks remain required; a
formal combined suite cannot substitute for that fresh run.

The fresh run preserves two independent source identities: the genuine Ops caller
repository/commit/run/attempt and the actual Core checkout. Private Ops source is
provided as a Git archive without `.git`; it supplies no locally derived Ops
source-tree claim. The dedicated caller validates Core checkout identity before
and after invoking its ordinary fixture. Alpha.2 passes the explicit seven-field
`expectedCoreSource`: `commit`, `tree`, `version`, `upstreamVersion`,
`executableSha256`, `runtimeSha256` and `planSha256`, from the acquisition/source-
verified lock, and checks the owner's independently observed returned facts.
The genuine Ops `GITHUB_SHA`, repository, run ID and attempt remain present and
unchanged during import, invocation, success and failure; no omission, spoofing
or environment restoration shim is used. Workflow validation still binds caller
evidence back to the actual Ops job. Historical alpha.1 calls omit this API option
and retain their existing behavior. The caller-only preparation under #181 is
separate from the explicitly selected dual-proof adapter below. Neither adapter
preparation promotes a lock or establishes alpha.2 qualification.

The exact successful Core CI qualification summary attests the installed-record
checks for its bound source/run and listed input hashes. Current hosted archives
retain phase evidence and baseline acquisition metadata, but omit root
`owner.json`, `validated.json` and `retained.json`. Ops can verify retained bytes
and the successful bound CI verifier, not fully replay the original ownership,
validation and retained-home graph offline. Do not fabricate missing records,
rewrite observed paths or probe deleted hosted directories on an operator machine.
This limit neither demonstrates a publisher bypass nor permits broadening the
packaged/fresh-Ops `installerUpgradeVerified:false` scope.

The six public release assets stay unchanged: qualification summaries and combined
receipts are internal evidence, not a seventh asset. Same-version plugin choices
are not cross-installer retention; native popup/modal rendering, live quota,
OAuth, model/search and Session billing remain outside these observations.
Synthetic adapter tests are not hosted or installed qualification. Alpha.2 remains
unpublished and unqualified, with no installation, activation or restart authorized.

显式 `combined-suite-v2` 要求功能／普通验收 schema 2 和必需的原始 `positive-usage.json`，
以原始哈希及已独立评审的 alpha.33 来源／Client 字节策略绑定；v1 和旧 alpha.1 读取器与历史保留。
两条 route 的正向证据须涵盖 Session 继承／显式缺席、删除／关闭后的隐藏与恢复、provider 恢复、
可见 Client 释放和原应用恢复。合成 Client 单元测试不等于实际已发布 Client 的托管 renderer 证明，
也不证明真实额度、Session 计费或安装升级。独立评审的当前候选为 `.cloga.17`/Core alpha.1/alpha.33，
全新 hosted Ops qualification 仍待执行。历史 `.16` 的 `a59f586…` Ops 成功仅属于该精确 code head；
合入 v2 adapter/test 后的历史 run `35577921833` 独立验收了精确组合 head
`cd384495ac2fd0c850b3c8cd93223d35c4bc83a0` 的 `.cloga.16` alpha.1 目标，不能转作 `.17` 或 alpha.2 验收。

组合格式只适用于经过明确评审的正式导入证据；全新 Ops resolver observer 仍成功走普通验收路径，
清理后才提交普通 acceptance。Ops 调用方身份来自实际 job，与调用前后核验的 Core 检出身份分开；
私有 Ops 归档没有 `.git`，不宣称本地派生的 Ops tree。alpha.2 通过显式 `expectedCoreSource`
传入经 acquisition/source 预检的锁定 Core commit/tree、Desktop/upstream 版本及 executable/runtime/plan 哈希，
再核验 Core 返回的实际观察值。import、调用及成功／失败期间始终保留真实 Ops `GITHUB_SHA`、repository、run/attempt，
不删除、不伪造，也不使用环境还原 shim。历史 alpha.1 不接收此 API 参数，调用行为保持不变。
#181 caller-only 准备与下文显式选择的普通主验收／独立 outer-canary 双证据 adapter 分开；两者均不提升锁或宣称 alpha.2 已验收。
Core CI 的精确成功摘要可以证明执行过安装检查，但归档缺少
根 owner/validated/retained 记录，不能完整离线重放。六资产公开契约、独立 Ops 目标和历史原始字节
不受此 alpha.2 准备工作影响；该准备不等于发布、安装或激活。

## Alpha2 independent dual-proof preparation

The new Ops declaration `dual-ordinary-canary-v1` follows the final immutable
[Core qualifier](https://github.com/cloga/deepseek-harness/blob/3ca51d61bdf39f8c63c26125674cd92fdcf6ed98/apps/desktop/scripts/verify-fork-qualification.ts)
and its [two-run workflow](https://github.com/cloga/deepseek-harness/blob/3ca51d61bdf39f8c63c26125674cd92fdcf6ed98/.github/workflows/desktop-fork-release.yml).
This is an explicit new Ops reader format, not a new Core receipt schema and not
an automatic reinterpretation of `combined-suite-v1/v2` or historical alpha.1.
Unknown formats and mixed declarations fail closed. No current production lock,
catalog, original fixture or PowerShell lock-admission policy is changed.

The exact `nativeProvisioning.packagedAcceptance` declaration has `schemaVersion:1`,
`format`, `runId`, `runAttempt`, `suiteSha256`, `qualificationSha256`,
`workflowRunSha256`, `workflowJobSha256`, **`ordinaryAcceptanceSha256`** and
**`workflowArtifactsSha256`**. The ordinary hash must equal the existing ancestor
acceptance pin; all settings/usage/menu/ancestor phase pins continue to describe
PRIMARY. The legacy alpha.1 `usagePositiveAcceptance` quota2 declaration is not
accepted alongside this dual quota4 format. Real hashes are supplied only during
separately reviewed promotion, never placeholder pins in this preparation.

Fixed locations under the existing formal root:

- Root: original public `release.json`, `build-receipt.json`,
  `desktop-provisioning.json`; PRIMARY `acceptance.json`, original provisional
  `functional-results.json`, `helper-acceptance.json`, positive/runtime/capability/
  provisioning/executable JSON and initial/restart observations.
- `canary/`: original canary functional/failure/observer/suite plus its own positive,
  runtime/capability/provisioning/executable JSON and initial/restart observations.
  Ordinary acceptance, helper and copied public release metadata are forbidden here.
- `core-qualification/`: original `qualification.json`, `workflow-run.json`,
  `workflow-job.json`, `workflow-artifacts.json`, and seven original installed
  records under `installed/` (acquisition, installer-upgrade, baseline, candidate,
  candidate-restart, profile-cleanup and package-acceptance).

Each family's raw edges and owner UUID agree internally. Independent PRIMARY and
canary UUIDs, menu IDs, timing and temporary profile paths are not forced equal;
shared Core source/tree/run/attempt and release identities are. Normal PRIMARY
acceptance is required after cleanup, whereas canary normal completion remains
false with finalized failure/observer cleanup. Both positive files require the
reviewed alpha33 source/Client digest and two ordered 21-key cases: fourteen true
observations, quotaReads4, bounded `7 used`/`13 left`, zero selector/forbidden-Remote
errors and synthetic/no-Host scope. Fresh Ops ordinary remains a third run using
actual Ops run/attempt and its own observed phase bytes. The merged explicit
seven-field Core caller is retained unchanged; no Ops SHA omission is permitted.

The qualifier summary remains Core schema1 with
`normalPackagedAcceptanceCompleted:true` and `canaryNormalAcceptanceCompleted:false`.
Its **45 exact input labels** are checked without inventing PRIMARY inputs:

- `ordinary.helper`, `ordinary.acceptance`, `ordinary.positiveUsage` only;
- `packaged.runtime`, `.provisioning`, `.capability`, `.executable`, `.functional`,
  `.failure`, `.observer`, `.suite`, `.positiveUsage`;
- `packaged.initial` and `packaged.restart` each with `.settings`, `.menu`, `.usage`,
  `.graph`, `.receipts`, `.provisioning`, `.profile`;
- `plan`, `candidate.manifest`, `.receipt`, `.installer`, `.provisioning`;
- CI-attested-only `baselinePin`, `baseline.manifest`, `.receipt`, `.installer`,
  `upgrade.owner`, `.validated`, `.retained`;
- Archived `baseline.acquisition`, `upgrade.result`, `.baseline`, `.candidate`,
  `.candidate-restart`, `.cleanup`, `.packages`.

PRIMARY's other original files receive their own lock/semantic/identity checks;
they are **not** falsely described as additional Core summary inputs. Public
manifest/receipt build objects are exactly Core's six fields (`workflow`,
`lockfileSha256`, `planSha256`, `nodeVersion`, `pnpmVersion`, `packageRegistry`).
Ops-only `runUrl`/`attempt` are checked separately against original workflow
metadata, never added to or reserialized into the public receipts.

The pinned original artifacts API response must be one complete page (at most100
records); incomplete pagination needs a separately reviewed format. Four exact
selected names bind IDs, API ZIP digests/sizes, repository/source/run and expiry:
`desktop-copilot-acceptance-<version>`, `desktop-copilot-observer-canary-<version>`,
`desktop-fork-qualification-<version>-<source>-<attempt>` and
`desktop-installer-upgrade-<version>`. No nonexistent artifact `run_attempt` field
is invented. Original job metadata must show one successful PRIMARY, independent
observer, installed qualification, complete qualification and qualified-summary
upload in order.

**Offline boundary:** this reader checks pinned API metadata plus original JSON
consistency, not archive bytes or ZIP-member membership. The Ops-owned result's
`formalEvidenceLimits` states `archiveBytesVerified:false`,
`archiveMembershipVerified:false`, `unarchivedInstalledRootsReplayed:false`, scope
`pinned-api-and-original-json-consistency`. These are Ops result limits, not fields
inserted into Core evidence. An API digest alone cannot prove imported JSON was a
member of that archive. At promotion, an independent authenticated audit **must**
download all four original ZIPs, verify API size/digest, reject unsafe/duplicate/
linked/traversal members, compare selected original member bytes exactly and retain
reviewable acquisition provenance before committing real proof or pins. Missing
original archives cannot be replaced with synthetic fixtures or reconstructed
receipts. No collector, broader token, ZIP parser, runtime command or workflow lane
is added by this preparation. Seven unavailable installed root/baseline inputs
remain explicitly CI-attested, not offline replayed.

新增 `dual-ordinary-canary-v1` 严格遵循上述 Core3ca51d 最终契约：普通 PRIMARY 原件位于根目录，
独立 canary 原件位于 `canary/`，摘要／API 元数据及安装记录位于固定 `core-qualification/`。
两组内部身份和原始哈希各自闭合，不强行比较跨运行 UUID、窗口 ID、时间或临时目录。
Core 摘要精确45个 input，不伪造额外 `ordinary.*`；公开 build 只有6字段，Ops runUrl/attempt 另验。
两组均强制21键／14真值／quotaReads4／固定已评审 Client 策略；fresh Ops 是第三次普通验收。
离线 reader **不证明 ZIP 原字节或成员来源**，输出明确 false 限制；正式提升前必须独立下载4个原始 ZIP，
核验 API 大小／哈希、安全成员及逐字节来源，再提交真实证据和锁。此准备只使用惰性测试数据，
保留旧格式、当前 alpha.1 锁、原 fixtures 和真实 Ops SHA；不发布、提升、安装或激活。

## Audited starting points

| Component | Audited source | Starting release | Adaptation tracking |
|---|---|---|---|
| Core fork/Desktop | `65a236bd65f2971f98b11a0efd020b8860144924` | `dsh-desktop-v0.1.6-alpha.1.cloga.2` | [Core #67](https://github.com/cloga/deepseek-harness/issues/67) |
| Copilot | `e49bf7c9307cf22dd9ea720bed8750101fc986ed` | `v0.4.0-alpha.24` | [Copilot #139](https://github.com/cloga/dsh-github-copilot/issues/139) |
| cron | `6f5f9f77e00c2f18838ec48c26543eb608bbc441` | `v0.7.2` | [cron #49](https://github.com/cloga/dsh-cron/issues/49) |
| Playwright Host | `fdec939b48d14d66d14bef3d8f12ec68411d58fb` | `v0.1.7` | [Playwright #20](https://github.com/cloga/dsh-playwright-host/issues/20) |

Source pins above are review inputs, not automatic promotion of those versions to
alpha.2 compatibility. Open Core #59 and Ops #180 are separate work and must not be
silently included or declared qualified by this upgrade.

## Decisions by customization

| Purpose / customization | Official parity | Decision and concrete gap | Retirement condition / migration safeguards |
|---|---|---|---|
| Desktop Plugin Manager UI, live enable/disable | Complete management primitives; fork integration unverified | Migrate to official management/UI; do not carry the old fork renderer unchanged | Preserve user-installed plugins, settings and exact profile lock ownership; qualify disable/re-enable, rollback and deferred replacement |
| Verified GitHub Release installation and source snapshots | Partial: official accepts git/path/tarball syntax, not equivalent reviewed Release identity | Retain only narrow acquisition/integrity adapters integrated with the official transaction owner | Retire after official supports pinned asset/commit/hash validation, safe immutable snapshot acquisition and equivalent rollback; no plain URL/name parity claims |
| Desktop Host and runtime resolution | Official architecture changed | Migrate to official `runProfile` and runtime-resolution model, reattach justified integrity/update hooks | Qualify Electron/Host start, authentication, external dependency resolution, native addons, user plugin preservation and restart; old byte-pipe/link tests do not certify new topology |
| Plugin ancestor-SDK isolation | Partial: official runtime/link/dual resolver still has native ancestor fallback | Use official resolution generation and retain only fork import-policy guard | Retire when official prevents unintended ancestor SDK imports in ESM/CJS and nested Workers while preserving Host shared class identity; no parallel resolver or profile-link rebuilding |
| Windows filesystem identity and multiline goal editing | Absent from inspected official implementations | Retain Windows birthtime-based stability and multiline goal/pending-edit guards | Retire after official stable Windows file-version tests and multiline Ctrl/Cmd+Enter plus pending-Escape acceptance pass |
| Copilot OAuth/native transport | Complete primitives, partial account UX | Reuse official OAuth/adapter; retain narrow account controller and dynamic entitlement metadata | Retire custom glue when native current-account models, supported protocols, TTL/cancellation and unknown-model behavior meet acceptance; preserve credential and Session ownership |
| Planner/executor model roles | Partial: official persists/inherits allowed-model delegation policy | Retain fixed-role policy, dedicated roots and creation recovery on official subagent primitives | Official equivalent must preserve session-local role seeding without altering global chat defaults, restrictions and cold recovery |
| Copilot/native/independent search routing | Partial: native exact search-provider dispatch exists | Retain explicit routing, independent account model, proof/cancellation and backend/charge disclosure; reuse official search implementation | Retire when official supplies equivalent chat association, explicit disabled/default/final-fallback semantics and account proof; similar provider IDs are insufficient |
| Ordinary root-owned live reminder followups | Complete for the narrow common subset | Prefer official scheduler for new reminders that satisfy its limits | Preserve owner, due instant, pending/consumed state and no dual dispatch; no bulk JSON-to-Session-log rewriting |
| Interval scheduling | Partial: official >=300s creation-anchored fixed-rate/latest-only; cron >=10s last-delivery anchored | Retain non-equivalent cron interval behavior | Migrate only after explicit phase/rate/missed-run/batching semantics are accepted or official equivalence is available |
| Calendar/IANA cron and unattended cold owner wake | Absent from inspected official scheduler contract | Retain calendar recurrence and cold-session resume | Retire after equivalent timezone/DST and durable cold-owner resume without fallback-owner substitution are verified |
| Task editing, pause/run-now, history/transfer and notifications | Partial/absent in official scheduler | Retain required management features; official active catalog is not execution history | Preserve IDs, owner/preset/model and receipts. Do not claim Windows OS notifications: current cron native notification code covers macOS/Linux only |
| Playwright Session/browser isolation and lifecycle | Complete source support; Windows runtime acceptance unverified | Prefer official Browser Use foundation, not new custom session-isolation machinery | Qualify simultaneous Sessions, tabs/cookies/refs, one-owner disposal, attached-browser survival, namespace/allowlist migration and first native/PTC catalogs |
| Edge/headed/caps/viewport expectations | Partial: explicit executablePath/headless exists; legacy caps and viewport controls absent | Retain the thin existing entry temporarily until required testing/devtools/vision and viewport behavior is accepted | Compare actual tool catalog and screenshot/console/network behavior; do not silently remove capabilities just to shrink the fork |
| Browser automatic reconnect | Intentionally absent officially | Prefer failure-transparent official lifecycle over copying reconnect flags | Migrate only with clear state-loss reporting and user-visible recovery; never reuse stale snapshot references |
| Bundled Cordis skills through Electron/ASAR | Partial: official alpha.2 has the bundled reader, but its preset row classifies deployment-owned skills as custom | Correct only the deployment-owned row to use the existing official `bundledSkillDir` reader; do not add a parallel reader or widen user custom-root trusted-host access | Retire after the official row is corrected and packaged discovery/tool execution plus user-root precedence pass; preserve user skills and profile ownership |

## Exact official evidence

All links below point to the same immutable target commit, not mutable master:

- [Plugin Manager](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/boot/plugin-manager/README.md): profile-wide installation/removal and HMR limits; package replacement still needs a new code generation/restart.
- [Desktop Host](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/apps/desktop-host/src/index.ts), [Host process](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/apps/desktop/src/host-process.ts), [profile migration](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/apps/desktop/src/profile-packages.ts): official Web-backed `runProfile` topology and legacy-link migration.
- [Native model discovery](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/llm/llm-pi-ai/src/discovery.ts): installed-provider catalog discovery is not current-account entitlement refresh.
- [Subagent descriptor](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/subagent/subagent/src/descriptor.ts) and [model-selection state](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/subagent/tool-subagent/src/model-selection-state.ts).
- [Remote codec types](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/typert/protocol/src/types.ts) and [registry validation](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/typert/registry/src/service.ts).
- [Scheduler runtime](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/schedule/schedule/src/runtime.ts), [types](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/schedule/schedule/src/types.ts), [semantics](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/docs/subsystems/schedule.md).
- [Official Playwright provider](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/experimental/browser-use-playwright-mcp/src/index.ts), [browser runtime](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/experimental/browser-use-runtime/src/index.ts), [MCP lifecycle](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/experimental/browser-use-runtime/src/mcp.ts).

The bundled-skill decision compares the exact official
[Cordis preset](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/preset/agent-presets/presets/cordis/agent.cordis.yml)
(`customSkillDirs`) with its existing
[skill-filesystem reader](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/skill/skill-filesystem/src/index.ts)
(`bundledSkillDir`). Source classification is not itself packaged acceptance; see
the [later checkpoint](core-016a2-delivery.md#later-source-bound-checkpoint).

## Native loader dependency and mirror qualification

`node-addon-require-builtin` belongs to official Core boot/module resolution, not
an extra dependency introduced by the maintained cron, Copilot or Playwright
plugins. At the exact alpha.2 target:

- [app-boot](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/boot/app-boot/package.json#L34-L39)
  and [CLI](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/apps/cli/package.json#L104)
  declare the direct dependency `^0.1.6`.
- [Cordis Loader](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/vendor/loader/package.json#L32-L39)
  declares an optional peer. Its optional internal-loader path does **not** make
  the entire DSH boot dependency optional.
- [Profile resolution](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/boot/app-boot/src/profile-resolution/resolver.ts#L520-L549)
  directly loads the addon to reach Node internal ESM/CJS loaders and helpers;
  this path has no missing-addon fallback.
- Comparing those three manifests with official alpha.1 commit
  `0a15e36e7f82b6ed45af6fa9759f29b40dcd965d` confirms the same `^0.1.6`
  declarations already existed. Do not describe this as an alpha.2-new dependency.

During local qualification, the configured approved mirror returned E404 for
`0.1.6`, while its version metadata listed versions through `0.1.5`. This is a
point-in-time mirror availability observation, not evidence that upstream never
published `0.1.6` or that every CI environment is blocked. The official lock pins
`0.1.6` with SRI
`sha512-P9ZGMDkloktirLJSggfpxsJ9jog5FItE1Omxpj50UBn3LhD6TS6/yx0jEBXsCGK3P9EtW1EpQVA1QL5gb11GaQ==`.

Prefer approved mirror synchronization or an approved original artifact verified
against that integrity. **Do not substitute `0.1.5` for this Desktop target:**
subsequent isolated testing established an actual Electron compatibility failure,
not merely an unmet `^0.1.6` range. The entry, shared native loader and Windows x64
platform archives were obtained from the approved mirror, checked against their
metadata SHA-1 values, and left unmodified in a disposable test fixture. No Core
or live-profile dependency was replaced.

| Isolated carrier | Result for addon 0.1.5 | Actual coverage |
|---|---|---|
| Standalone Node 24.13.0, Windows x64, module ABI 137 | PASS, exit 0 | Main plus two Workers: native binding/cache hash, five DSH internal modules, ESM v2 shape and actual `node:path` resolution; worker exits awaited |
| Electron 44.0.0 in Node mode, Node 24.18.1, Windows x64, module ABI 149 | FAIL, natural exit 1 | Native binding/cache hash passed; first `requireBuiltin('path')` failed. Five internal-module calls and Workers were **not reached** |

The Electron error was:
`Unsupported/no-realm (no compatible GetAlignedPointerFromEmbedderData symbol found)`.
The tested carrier was an existing hash-verified cloga.1 executable; this is an
embedding smoke test, not a complete official alpha.2 application test. No
existing Desktop/Host process was stopped. The
[owned probe summary](evidence/core-016a2-addon-015.json) records runtime identities,
artifact hashes, actual results and limits without private paths or raw stack data.
It is not an independent publisher attestation.

The [official bump](https://github.com/deepseek-ai/deepseek-harness/commit/0bade5a01012f0355837f556b75adcab27f2c3c9)
changed the locked version from 0.1.4 to 0.1.6 without a detailed native-change
explanation. The later [addon-managed cache change](https://github.com/deepseek-ai/deepseek-harness/commit/c3a66d9cd23f149370e45ae8e114173c0d2eff3c)
is not proof of a 0.1.6-only capability: reviewed 0.1.5 loader source already has
native-cache management. The initial 0.1.5-only probe record did not establish
0.1.6 behavior. Subsequent comparison below supplies actual positive evidence,
while the native implementation/source-level reason remains unavailable.

### Subsequent attested 0.1.6 comparison

The existing cloga.1 installation already contained the 0.1.6 entry, shared loader
and Windows x64 platform package. Its `dsh/desktop-runtime.json` SHA-256 matched
`b388ddee840f7de08ac391d4faf7a526ebd40b3bfe0ced8525cf8ac2c9fab344`, pinned by the
[historically qualified Ops lock](https://github.com/cloga/dsh-windows-ops/blob/529d3f26ffb2a0379ea230ee5e66d2e06b352d8d/deployments/windows-copilot.lock.json).
All 14 selected package files, including the unpacked native binary, matched
that descriptor's byte counts and hashes, then matched again after copying into
an isolated test fixture. This is stronger than trusting an adjacent ASAR header
or package version string alone. Native 0.1.6 is 343552 bytes, SHA-256
`e23ba1b0c33c63940625aa954011b53c66d855f7dfac75b29c829b25e06f20df`.

| Same isolated Windows x64 carrier | Mirror-original 0.1.5 | Attested deployed 0.1.6 |
|---|---|---|
| Standalone Node 24.13.0 | PASS: main + two Workers | PASS: main + two Workers |
| Electron 44.0.0 Node mode / Node 24.18.1 | FAIL on first native require | PASS: main + two Workers |

Both 0.1.6 runs verified all five DSH internal modules, ESM v2 methods, actual
builtin resolution through ESM and CJS, the exact native-cache hash and shared
cache-path identity, and natural process/Worker exit 0. The entry, shared loader
and platform-entry JavaScript were byte-identical across the two reviewed
versions; their native binaries differed. Therefore retain 0.1.6 for this target:
its tested native bytes work where 0.1.5 fails in the **same** Electron embedding.
The [separate comparison summary](evidence/core-016a2-addon-comparison.json) records
this later evidence; the earlier 0.1.5-only record remains historical.

These are **attested deployed runtime bytes**, not reconstructed npm archives or
proof of original npm SRI equivalence. No registry tarball was supplied by this
comparison, no package-manager store populated, and no Core or live profile
modified. The mirror install problem is not thereby fixed. Node 22/26, full
Profile resolver/Worker bootstrap/HMR, Electron browser/main-process behavior
and complete alpha.2 packaged activation remain outside the probes. Never
relabel an archive, bypass registry/TLS policy or silently rewrite the lock.

中文摘要：同一载体的对照已完成：0.1.5 在 Electron 44 / Node 24.18.1 失败，
而逐文件匹配历史已验证描述符的 0.1.6 在该环境的主线程与两个 Worker 均通过。
因此保留 0.1.6 不只是遵循版本声明，也有实际兼容性证据。该证据来自现有部署文件，
不等于拿到了 npm 原始包，也没有恢复镜像缺失依赖；未改正式依赖或运行环境。

### Distinguish optional test closure from runtime requirements

`@trycua/cua-driver@0.28.0` is a separate dependency of the
[experimental native computer-use provider](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/experimental/computer-use-cua-driver-native/README.md),
which requires an explicit composition choice. It is pulled into the repository's
root development closure, not declared as a direct Desktop-shell dependency.
The approved mirror returned E404 for 0.28.0 and exposed 0.26.1 during this review;
no replacement compatibility is established or downgrade performed.

An explicit `pnpm --filter @deepseek-ai/dsh-desktop install --frozen-lockfile`
still requested that root dependency. The installed pnpm 11.7.0 implementation
(`dist/pnpm.mjs`, recursive install, lines 194818-194822 in the inspected build)
adds the workspace-root importer even when it is outside the filter under the
shared-lockfile path. This does **not** prove CUA is required to run Desktop.
The failed root-only and Desktop-only attempts retained the exact lock hash.
Do not keep retrying the same filters or rewrite the lock to make them succeed.

Also, pnpm 11 `run`/`exec` attempted automatic dependency materialization before
starting checks in this incomplete workspace. A timeout there is **not a test
failure or a test pass**: no selected tests ran. Inspect the intended scope and
use an already available direct tool entry where legitimate; keep any exact-cache
scoped resolver evidence separate from full dependency, typecheck and pre-push
qualification. No unavailable dependency may be silently substituted. A local
hook exception still requires explicit user agreement; none was granted here.

### pnpm 11.7 dispatch and offline-policy boundaries

Two additional assumptions were disproved by actual candidate tests and inspection
of the pinned pnpm 11.7.0 `dist/pnpm.mjs`. These are tool-version-specific findings,
not new authorization to install or relax policy:

- **`pm` must be the first pnpm argument.** `parseCliArgs2` checks
  `inputArgv[0] === 'pm'` (lines 285469-285471). Prepending even a notifier setting
  before this sentinel loses built-in-only dispatch. In the adaptation candidate,
  that mistake caused source packing to enter fallback `run` and dependency
  materialization, attempting public-registry requests for fixture dependencies.
  The runner was corrected to keep `pm` first. Actual pinned-pnpm regressions then
  packed sources with an unavailable dependency and `pm`/lifecycle traps without
  running those scripts or creating source `node_modules`/lock files. A successful
  dependency-free pack alone would not have caught this bug. This is scoped test
  evidence, not publication of the candidate Core implementation.
- **`--offline` does not prove zero registry traffic.** A later, separate test
  successfully packed and seeded a private package store, then printed both
  `Already up to date` and registry GET/retry diagnostics before its 60-second
  deadline. The package store and ordinary metadata cache were present. The pinned
  verifier performs tarball-URL binding before optional age/trust checks
  (`createNpmResolutionVerifier`, lines 64293-64310), calling
  `runTarballUrlCheck` -> `fetchAbbreviatedMeta` -> `fetchMetadataCached`.
  That last function reads disk headers but performs a conditional registry GET
  before using a cached body after HTTP 304 (lines 64224-64242). The verifier's
  construction does not forward the install's offline option. A valid verification
  cache can avoid rechecking; ordinary cached package bytes/metadata alone do not
  establish that condition. The verification promise runs alongside installation,
  so progress output is not a successful process exit or completed policy check.

Do not respond by disabling TLS/integrity/supply-chain checks, automatically adding
`--trust-lockfile`, fabricating verifier-cache records, or extending timeouts to
hide the cause. If zero egress is required, do not rely on a CLI flag alone: use an
approved environment that enforces the restriction, or stop until the required
policy evidence can be obtained without violating it. Registry restrictions remain
in force even when ordinary package files are locally available.

A controlled test may instead keep an explicitly trusted **nonproduction HTTPS
loopback registry** available for policy metadata, while verifying that package
archives are read from its private cache and are not fetched after seeding. Such
a result must be labelled "cached artifact materialization with local policy
metadata traffic", not "all requests offline" or external-registry acceptance.
Any fixture CA is child-process-only, never system/global trust; TLS verification
stays enabled. It does not supply missing approved-registry artifacts or qualify
real packaged Electron/ASAR behavior.

中文：pnpm 11.7 的 `pm` 必须放在参数首位，前置配置参数可能误走脚本/依赖安装路径。
`--offline` 也不等于绝对不联网：锁文件供应链校验仍可能发起 registry 元数据请求。
应核对实际退出结果和请求范围，不能关闭校验、伪造缓存或把进度输出当作成功。
测试中的本地 HTTPS 元数据流量与包内容离线缓存必须分开说明。

## Findings at the audited starting points

These findings describe the starting sources above. Later adaptation, publication
and remaining qualification limits are recorded in the [delivery evidence](core-016a2-delivery.md).
A fixed plugin issue does not by itself qualify the new Core/Desktop deployment.

1. Copilot handwritten strict Remote codecs require `create()` on alpha.2; merely widening peer ranges leaves Client `$mount` broken. Preserve explicit owned view validation because Gateway success is not result-schema validation.
2. Copilot role child descriptor parsing expects version 1 while official emits version 3. This predates alpha.2 (also present in alpha.1): label it as a pre-existing mismatch, rebuild the plugin projection cache safely, and do not invent migration of old durable children.
3. Cron's module-global active Session from header mount/unmount is unsafe with coexisting main/embedded Session views. Bind actions to the correct instance/owner and qualify simultaneous views. `openSession(SessionTarget)` still accepts SessionId; update exact contract tests rather than claim the API disappeared.
4. Browser migration needs actual Windows/Edge tool capability acceptance, not only `--version` or synthetic RPC tests. Never mount legacy global MCP and official Browser Use simultaneously as a silent transition.
5. Neither scheduler has established exactly-once crash delivery. Official documents at-least-once behavior; cron queue-before-persist also has a crash window. Clean-restart tests are not crash-safety evidence.
6. Core merge preview reports substantial Desktop/Host conflicts and upstream deletion of the old plugin-manager renderer/preload. Resolve against the official architecture and retained requirements, not blanket ours/theirs.

Each component's implementation Issue/PR must attach actual checks, release/artifact
identities and migration limits before Ops promotes a new lock. Source review is
useful progress, not permission to report alpha.2 deployment complete.
