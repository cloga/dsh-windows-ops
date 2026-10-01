# DSH Core 新版本适配 / Official-first Core upgrades

## 一句话入口 / Entry point

用户说“做 DSH Core 新版本适配”时，从本页和
[`core-upgrade-scope.json`](../deployments/core-upgrade-scope.json) 开始。
范围包括 Core fork/Desktop、Copilot、cron、Playwright Host 和 Windows Ops。
这是一份适配范围清单，不是安装清单，也不替代已验证的 deployment lock。

When asked to adapt to a new DSH Core release, start here and use the inventory
above. It identifies maintained components, not permission to install all of them.
Cron and Playwright remain optional unless the qualified deployment explicitly changes.

```powershell
node tools/plan-core-upgrade.mjs --tag dsh-v0.1.6-alpha.2 --commit ddefc45fbc7f8e46dd73185e68295696d1297887
```

命令只读取仓库清单并向 stdout 输出未执行计划；不联网、不读取凭据、不写文件、
不启动或停止进程。示例固定本次目标，不表示适配已完成。以后提供新的精确 tag/SHA，
先核验两者对应；输出中的 `verified: false` 不能当作兼容证据。

The planner reads the inventory and emits an unexecuted plan. It performs no
network, credential, file-write, install or restart operations. The example is
this task's target, not a qualification claim or a mutable latest-version alias.

本次版本记录 / Version-specific assessment:
[0.1.6-alpha.2](core-016a2-assessment.md) — source review, not deployment qualification.
Later publication and scoped acceptance: [delivery evidence](core-016a2-delivery.md).

## 必须先比较官方实现 / Official-first gate

不要只提高 peer 版本或修到编译通过。逐项比较自有功能和精确官方目标的
Release notes、源码、公开契约及测试。名字相似不代表等价；未知不等于不支持。

Before carrying custom code forward, compare every relevant customization with
the exact official release. Similar names do not prove parity; unverified support
must not be reported as absent. Prefer official code only after user requirements,
safety, behavior, configuration/data migration and runtime acceptance are covered.

Each upgrade Issue/PR must contain a compact decision table:

| Customization / purpose | Official tag + commit + source evidence | Parity | Decision | Gap + retirement condition | Migration / rollback | Acceptance |
|---|---|---|---|---|---|---|
| One row per feature | Exact links/contracts, not only release titles | complete / partial / absent / unverified | migrate / retain-temporarily / retire | Required for retained code | Settings, credentials, history, jobs, recovery | Tests and scoped runtime evidence |

- **完整覆盖**：验证后改用官方实现，安全移除重复适配器及过时路径测试，保留用户需求验收。
- **部分覆盖**：尽量只留薄适配层，明确缺口和移回官方的条件。
- **缺失或未验证**：暂留必要实现；记录证据或待查项，不编造兼容结论。
- **Complete**: migrate after verification; remove redundant code safely while retaining requirement-level acceptance tests.
- **Partial**: keep only necessary glue and specify the exact remaining gap and retirement condition.
- **Absent/unverified**: retain needed behavior temporarily and record evidence or missing checks explicitly.

## 执行顺序 / Delivery sequence

1. **协调**：确认各仓库默认分支、干净工作树、开放 Issue/PR、并行 Session 与发布任务；不得覆盖已有分支工作。
2. **固定目标**：核验官方 release tag、commit、协议和依赖版本；记录当前已发布基线，不以本机旧 checkout 代替远端事实。
3. **官方优先审视**：完成上面的决策表，优先检查插件管理/来源安装、生命周期、浏览器、调度、模型和搜索能力。
4. **迁移评审**：说明设置、凭据引用、Session 历史、定时任务和回滚影响。不自动删除用户数据，不迁移未授权的运行环境。
5. **适配与验证**：每个代码仓库遵循其 Issue → 非默认分支 → 测试 → PR → merge → 既有发布流程；运行精确目标的集成测试，不能只改版本范围。UI 使用现有 Harness GUI 验证，隔离 fixture 需单独标注。
6. **制品核验**：独立核验 commit/version、Release 资产、哈希和适用的 registry channel；CI 成功不等于已发布，发布不等于本机已安装。
7. **同步 Ops**：全部必要证据合格后更新 deployment lock、插件目录、fixtures/tests 和双语入口。未合格的目标保留为 candidate，不抬高支持声明。
8. **激活另行授权**：安装、重启和中断会话仍需要明确授权。没有重启权限不能阻碍安全的制品发布，也不能绕过 Electron/profile 所有权。

Coordinate first; pin the official target; record parity decisions; review migration;
qualify each owning repository and publish through its established channel; verify
artifacts; then synchronize qualified Ops locks/catalog/tests and bilingual docs.
Installation and restart are separate approvals. Never rewrite immutable releases,
weaken integrity/TLS gates, patch a live Core, or silently interrupt Sessions.

## Desktop release boundary

`cloga/deepseek-harness` 默认公开交付是 `dsh-desktop-v<version>` 通道的 Windows
Desktop installer，连同既有 manifest、receipt 和校验文件。先对照用户批准的产品与通道，
再验哈希：raw Core/Web tarball、制品自述或资产数量不能授权替代；CI artifacts 不是安装交付。
非 Desktop 类型和通道需要用户单独明确授权，并记录在 Issue/PR 或 release plan。
此规则只约束该 Core fork；独立维护的插件保留各自已定发布渠道。

For `cloga/deepseek-harness`, public delivery defaults to the Windows Desktop installer
under `dsh-desktop-v<version>`, with its existing manifest, receipts and checksums.
Check the user-approved product and channel before hashes: raw Core/Web tarballs,
an artifact's self-description or asset count cannot authorize a substitute; CI
artifacts are not installer delivery. A non-Desktop type/channel needs separate,
explicit user authorization recorded in its Issue/PR or release plan. Independently
maintained plugins retain their own agreed channels; this rule is specific to the Core fork.

确认交付类型错误后，先在标题/说明标记 `WITHDRAWN`，保留并记录原 source、tag 和资产证据。
[GitHub 不可变 Release 规则](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases)
允许改标题/说明以及删除整个 Release，但不能修改或单独删除资产，也不能在 Release 存在时移动 tag。
先独立验证合格的 Desktop 替代，再按已获授权删除错误 Release；保留原 tag/source，
不移动或复用 tag，不覆盖资产、不绕过 immutable 保护。此流程不授权本机安装或重启。

For a confirmed delivery-type mismatch, first mark the title/notes `WITHDRAWN` and
retain and record the original source, tag and asset evidence.
[GitHub's immutable-release rules](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases)
permit title/notes edits and deletion of the entire Release, not asset changes or
individual asset deletion, nor moving its tag while the Release exists. Independently
verify a qualified Desktop replacement before authorized deletion of the wrong Release;
retain its original tag/source, never move or reuse the tag, overwrite assets or bypass
immutability. This procedure does not authorize local installation or restart.

## Remote qualification checklist

公司策略限制本机 npm 是预期环境边界，不要求用户解禁或提供包，也不反复本地重试。
正常 frozen install、依赖型生成器、完整检查和发布走获准 GitHub CI；本地继续可运行检查。
长期授权仅允许把有真实环境失败证据的本地依赖型 hook/check 按任务/PR 转到等价必需远端检查，
记录窄范围进程级延后，不必重复求同一权限；代码错误及远端失败仍须修复，不能削弱门禁。
本地受限不单独阻断 release goal；完整诊断、精确来源和制品验收要求保持不变。

- **Expected local boundary:** direct npm access can be intentionally disabled by
  company policy. Local registry/TLS errors or unavailable package versions are
  not proof of global unavailability or failed publication. Do not repeat local
  npm attempts, ask the user to unblock access, or require user-supplied packages.
  Keep source review and locally runnable existing-tool/cache checks moving.
- **CI-first dependency work:** run normal lockfile-frozen installation,
  dependency-consuming generators, full type/tests/build checks, packaging and
  applicable publication in the project's approved GitHub CI/release environment.
  Record local limits separately from actual remote failures. Diagnose and repair
  failed required CI; do not mark a release-inclusive goal blocked solely on local
  npm restrictions. Never fabricate archives, substitute/downgrade dependencies,
  alter locks to hide failure, copy arbitrary `node_modules`, or bypass TLS,
  credentials, registry policy or approved proxy boundaries.
- **Narrow standing hook authorization:** only a demonstrated environment-blocked
  local dependency-consuming hook/check may be deferred for the current task/PR
  to an equivalent **required** GitHub CI check. Record the actual command, failure
  and environmental cause; the exact process-scoped deferral; and the replacing
  remote check/run at the same source head. Retain other local hooks and record
  their results. Do not ask again for this same npm-related permission, but do not
  use it for source failures, blanket hook skips or global configuration changes.
  If no equivalent required check exists, the deferral does not qualify the work:
  establish that coverage through normal reviewed CI policy before merge/release.
  Remote CI, approvals, signing, integrity and release gates are never waived.
- **Complete lint evidence:** native pretty output can suppress diagnostics with
  `File is too long to fit on the screen` / `seems like a minified file`. Run the
  official `scripts/run-oxlint.ts . --format=json` via the repository's declared
  script runner, keeping the whole rule set and actual nonzero process exit.
  Parse machine JSON, not the visible pretty-output count; do not turn parsing or
  log capture into a successful exit for failed lint.
- **Remote generator boundary:** bind a result to exact source head, generator
  inputs and lockfile identity; use real official generators, not synthesized
  replacements. Allowlist actual generated changes and review content as well as
  paths. Preserve authored prose and archived notes. Never upload a rejected whole
  `git diff`, assertion text containing rejected content, or arbitrary sidecar
  bytes; never follow symlinks. Negative tests must assert sentinel absence from
  both artifacts and logs, not merely exit 1. Treat every artifact as unaccepted
  until its identity and allowed diff are reviewed; remove temporary workflows
  before final approval and requalify the resulting exact head.
- **Decoded PowerShell:** parse the decoded `run` scripts with the PowerShell
  parser, not only their surrounding YAML. In double-quoted here-strings,
  Markdown backticks can escape `$` or the closing newline. Prefer literal string
  arrays plus explicit formatting for interpolated values; verify the emitted
  Markdown as well as parser success.
- **Acceptance levels:** report syntax, unit, mock, exact-source fixture, build,
  packaged-runtime and native-installer results separately. `PREPARED` is not
  active/healthy; a graph inventory does not prove module loading. A signed-out
  Copilot state cannot establish a writable composer. Exercise the actual official
  UI install (initially disabled), then enable and restart as a distinct acceptance
  step; source fixtures do not stand in for that transition.
- **Distribution contract before asset integrity:** apply the
  [Desktop release boundary](#desktop-release-boundary) before checking bytes.
  Ordinary Desktop installation/startup must not
  silently gain a requirement for company-blocked public npm. Declare and test
  legitimate external runtime dependencies against the intended contract; an
  archive is not automatically offline, and this is no blanket offline promise
  for all plugins. Verify exact qualified merged source, lockfile and package
  identity, intended assets/channel, provenance, sizes and checksums independently
  after publication. Green CI alone is not release completion.
- **Isolation and activation:** installer tests belong only on guarded, disposable
  GitHub-hosted Windows with an isolated test profile and explicit runner/path
  guards, never implicitly on the current Desktop. Preserve local Sessions and
  data. Remote acceptance does not authorize local install, activation or restart.

Version-bound observations and outstanding gates belong in the existing
[alpha.2 delivery record](core-016a2-delivery.md#core-candidate-remote-evidence),
not in a second competing runbook.

## Bounded release debugging

本节把适配中的重复返工转成阶段检查，不另设发布流程，也不改变部署锁。
目标是缩短失败反馈、一次处理同一根因，而不是减少必需验收。
[交付记录](core-016a2-delivery.md)仍保存具体版本的结论；本节不宣称候选已发布或可激活。

Use this checklist to shorten feedback without weakening release gates. It extends
this upgrade workflow, not the deployment lock or a second publication path.
Version-specific outcomes stay in the delivery record above; these lessons do not
qualify a candidate or authorize activation.

### Freeze and advance one candidate

- [ ] **Freeze scope:** record the official Core tag/full commit, Desktop and plugin
  versions, source/tree, lock/plan hashes, proposed sequence, baseline, included
  changes, explicit non-goals, product/channel, publication owner and agreed cutoff.
  If the actual protected base advances, review and reconcile its necessary maintained
  changes without regressing them or bypassing up-to-date checks.
  Later parallel features default to the next release. Reconcile only necessary
  integration/safety changes explicitly; a changed tree invalidates prior final
  qualification. A proposed sequence is not reserved.
- [ ] **Coordinate each transition:** resolve current head/base, published versions,
  tags, sequences and in-flight releases before dispatch and publication. Use one
  owned branch/worktree per task; never overwrite another Session's work or cancel
  its run to obtain a slot. Batch related fixes into one reviewed candidate.
  Parallelize independent preparation and early risk review, with one writer per
  mutable file scope and final review against an immutable commit/tree. Minor details
  within an approved contract need no repeated approval; changed scope, guarantees,
  credentials or destructive actions require a new decision.
- [ ] **Use cheap feedback first:** whitespace, configured lint, actual aggregate
  TypeScript roots/options, then owning unit and real renderer/component tests.
  Keep strict/composite/project references intact; isolated transpilation or a
  relaxed compiler probe does not establish aggregate type correctness. Confirm
  collected, passed and skipped counts: zero collected tests is not a pass.
- [ ] **Audit the whole interaction chain before packaging:** first-run onboarding
  → provider readiness → workspace selection → prepare → refuse/consent → Host
  replacement/restart → enable/disable/remove → process/profile cleanup. Check
  prerequisites and failure paths together, not one selector per expensive run.
- [ ] **Run final acceptance on a stable source:** required exact-head CI, packaged
  behavior, real installed upgrade and cleanup, formal merged-source publication,
  independent originals/update discovery, then qualified Ops synchronization.
  Keep operator installation/activation as a separate authorized decision.

冻结 Core／插件／源码／序号与交付范围；后续并行功能默认下一版。每次转换前重新核对
分支、tag 和发布顺序，不取消别人的任务。先做便宜检查和真实 renderer 验证，确认实际
收集数量；不要用放松的类型配置或合成 DOM 冒充完整验证。打包前一次审完整交互链，
在稳定候选上执行最终验收，发布与本机激活始终分开。

### Triage an entire attempt before retrying

Retain the exact source, run/attempt/job, failing step, command/exit, originals and
scope of missing evidence. Collect all failed jobs in that attempt and group shared
root causes before patching: seven build jobs with the same type error are one
repair, not seven independent incidents. Follow a bounded diagnostic wait for
still-running jobs; do not keep restarting a failing build while another result
can change the diagnosis.

| Finding | Next action | Stop / do not infer |
|---|---|---|
| Source, type or assertion defect | Reproduce at the smallest faithful owner, correct the cause, batch related fixes, then qualify the new source | Do not retry unchanged source, remove assertions, relax types or raise timeouts to hide it |
| Fixture prerequisite or UI-state mismatch | Read original screenshot/receipts and actual public component/native contracts; fix setup or completion observation | A visible button, guessed control ID or partial phase is not readiness or whole acceptance |
| Evidence-supported transient transport failure, such as HTTP 500/502 during pinned Ubuntu download or 504 during Electron acquisition | One bounded failed-job-only retry may be appropriate with the same source, bytes and gates; retain the first failure | A repeated identical failure needs targeted diagnosis or concrete recovery evidence, not another loop |
| HTTP 403 or unexplained timeout | Keep cause unknown; inspect the relevant request/phase using only necessary sanitized route/status and allowlisted header facts | 403 alone is not rate-limit proof; operator-authenticated success does not prove anonymous runtime recovery; do not inject credentials, expose bodies/signed queries or weaken TLS |
| Local dependency unavailable | Use the existing approved frozen-CI equivalent and record the unexecuted local scope | No repeated registry attempts, version substitution, fabricated archive, copied dependency tree or policy-bypassing proxy |
| Non-required CI failure | Preserve its failing status and assess applicability under the actual repository/branch/release rules before the next transition | A required aggregate pass does not make the whole workflow green; a pass in a different lane does not erase or explain the failure |

先收齐同一次 attempt 的失败，按共同根因归组，再修改源码。只对有证据支持的临时
传输失败作一次有界、失败 job 范围的同源码重试；重复失败或原因不明的超时先诊断。
必需汇总通过与整体 workflow 通过要分别报告，不临时改规则把失败解释成成功。
保持 [CI-first 依赖边界](#remote-qualification-checklist)，不靠依赖替换或关闭校验过关。

### Fixture review before the expensive lane

The subordinate [UI fixture appendix](small-ui-change-validation.md) adds native
composer navigation, physical-layout and same-run snapshot examples; this guide
remains the operational entrypoint and owner of retry/release policy.

| Boundary | Required observation and regression |
|---|---|
| First-run credential UI | The Models join can reveal onboarding after Settings becomes visible. Handle only the exact public dialog and **Configure later** action with APIs verified against the pinned Playwright version. If a phase-owned locator handler is appropriate, own registration/removal and original action deadlines; verify persisted usable-provider configuration plus joined UI readiness before removal. Do not use a one-time presence check, forced click, mask removal or fake credential; never keep automatic dismissal active across restarts and mask lost readiness. |
| Windows folder picker | A private `USERPROFILE` may require its own physical `Desktop` directory. Create required children exclusively under the validated owned home; reject aliases/collisions. Do not fall back to the operator profile, change global known-folder registry state or broaden native selectors merely because a blocking OS dialog appeared. |
| Native process/installer | Validate standard UI Automation provider initialization and actionable owned controls in the earliest existing approved check; add a missing diagnostic through a separately reviewed change, not a claimed existing lane. With pinned Playwright Windows `shell:true`, the launch transport can be CMD, not Electron main. Bind retained handles, actual PID/parent/incarnation/path/hash; launcher exit is not worker or Host-family quiescence. For NSIS acknowledgment, verify the owned modal, exact message and unique valid pushbutton instead of assuming a numeric ID. Never adopt a same-name PID or click an arbitrary OK. |
| Windows path state | Separate physical identity from observable string state. `RUNNER~1` and its long spelling may identify one directory; prove physical ownership, then compare actual entered cwd before/after to test nonmutation. Keep production alias/escape rejection strict and exercise genuine short-path negative controls. |
| Independent settings writes | One card can commit two namespaces independently. Arm both exact request/response observations before Save; require HTTP **and** RPC success with expected persisted/effective values before file and reopened-UI assertions. First namespace appearance is not full-card settlement. |
| Public renderer/layout | Use the real renderer and alpha2 Session binding/disposal contracts. Cover cold/folded navigation, unique ARIA-qualified rows, retained empty Slot anchors, `display: contents`, text/full-width/error entries and ContextMeter-only states. Do not replace these checks with `.first()`, a guessed parent bounding box or hand-built DOM. |
| Observer and teardown | Collect every in-scope error; after the final awaited interaction, seal an owned immutable observation before intentional shutdown. Attempt cleanup of every owned listener/resource, preserving primary `Error`, `undefined` and `null` values separately from failure presence. Cleanup-only errors fail; success records follow cleanup. Never clear errors to obtain a passing receipt. |
| Diagnostics | Keep bounded early **and** late observations so polling cannot evict all causal context. Record missing/truncated scope. `trusted:false` on a synthetic poll says nothing about earlier user input. Source-extracted callbacks, VM probes and synthetic DOM have explicit limits; diagnostics and a later green run do not prove the historical root cause. |

原生与 UI fixture 必须基于实际公开语义及资源所有权。重点检查异步引导、私有
Desktop 目录、CMD/Electron 身份、短路径、多个独立保存回执、空 Slot 锚点，以及
观察器结束和清理顺序。保留所有范围内错误及最初失败值；清理失败不能制造成功。
有界诊断应保留早期原因线索，但不能把诊断或回调探针称为完整组件／原生验收。

### Evidence, artifact reuse and handoff

- Report separate statuses for **implementation**, **source/browser checks**,
  **packaged acceptance**, **installed upgrade**, **formal publication**,
  **independent original assets / update discovery**, and **local activation**.
  A partial pass advances only its own scope; provisional records are not final
  acceptance. Record the next concrete gate, not an unqualified “almost done”.
- Reuse an installer/build artifact only through an established or separately
  reviewed workflow binding exact source/runtime/lockfile/hash/origin and rerunning
  the same required acceptance gates. A proposed diagnostic workflow or an internal
  artifact is not authority to reuse it, relabel an old build or publish it.
  Workflow restructuring belongs to a separate issue/PR, not a release shortcut.
  For diagnosis, record the original package-source identity and diagnostic-script
  commit separately, alongside hashes and ownership. A diagnostic pass does not
  qualify a different source or remove final merged-source acceptance gates.
- Keep source/run/attempt and original-byte hash graphs consistent within a run.
  Do not reserialize originals, rewrite hosted paths, relabel historical formats,
  substitute a later receipt, or compare dynamic pixel hashes across runs. Use
  [original ZIP/member audit guidance](artifact-zip-audit.md) only within its stated
  platform and evidence limits; audit tooling alone is not native qualification.
- Preserve the established six public Desktop assets: installer, `release.json`,
  `build-receipt.json`, `desktop-provisioning.json`, `SHA256SUMS`, `SHA512SUMS`.
  Internal qualification artifacts are not a seventh asset or an installer
  substitute. Apply the [product/channel boundary](#desktop-release-boundary)
  before byte integrity; immutable tags/bytes are never overwritten.
- Keep one current execution handoff linking immutable evidence and one watcher
  per workflow run; reuse terminal results rather than duplicating watchers or
  polling unchanged state. Record implementation, review, queue/setup, CI, packaging
  and acceptance timing when available. Parallel job durations are not end-to-end
  elapsed time; optimize the measured critical path, not tool-call count.
- Reuse a frozen review/test result only while its relevant source and inputs are
  unchanged. After integration, rebind producer/consumer tests to the actual final
  hashes. Assign non-overlapping writers and independent review once, rather than
  repeatedly reviewing unchanged files. Preserve original logs; a reported tool
  result is not an on-disk log unless one was actually retained. End each actual
  defect repair with a regression at the cheapest faithful layer; shared evidence
  parsers also need rehashed semantic counterexamples and valid independent-run
  variation, not only happy-path snapshots.

报告必须分开列出实现、源码／浏览器、打包、安装、正式发布、原始资产／更新发现和
本机激活状态。复用制品要有已经存在或另行评审的精确绑定流程，并重新运行同样的
必需验收；不得临时发明发布捷径。原始字节、历史格式及六项公开资产契约保持不变。
每个 workflow 只保留一个 watcher，并复用终态结果；用一份当前交接链接不可变证据，
按实现、评审、排队／准备、CI、打包及验收记录可获得的耗时，区分并行 job 时长和端到端耗时。
只复用输入未变的冻结评审，最终整合后重新绑定相关证据；每个实际缺陷在最便宜且忠实的
层级保留回归，共享证据解析还要覆盖重新计算哈希后的语义反例与合法独立运行差异。
本清单本身不更改任何锁、workflow、运行环境或发布资格。

### Copyable preflight and handoff

使用同一份交接记录下列字段；约定 cutoff 后若受保护主线推进，明确评审整合；
独立准备与早期风险评审可并行，但每个可变范围只设一个写者。诊断包与脚本分别绑定身份，
不能把诊断成功改称新源码合格。其余规则以上方清单为准，不另建第二份动态状态报告。

```text
Product / channel / baseline / included changes / non-goals:
Candidate commit / tree / lock and plan hashes / agreed cutoff / owner:
Actual protected base / parallel work / exclusive writer scopes:
Focused checks -> source/browser evidence -> required CI/package gates:
Early native checks: existing capability or separately reviewed proposal:
Run / attempt / job / failed step / original evidence links:
Failure class + evidence / next bounded action / stop condition:
Artifact reuse: package source + hashes / diagnostic-script commit / scope:
Observer lifetime / cleanup owner / primary and secondary failure evidence:
Watcher owner / current handoff / immutable final review:
Timing: start-end intervals / queue-setup / parallel overlap / critical path:
Publication evidence / remaining platform limits / activation authorization:
```

## 完成标准 / Completion evidence

报告每个组件的处理结论、Issue/PR、源码提交、发布版本/链接、哈希和测试范围。
若官方已经完整替代某插件，退役计划和需求验收可以是适配结果，不要求为了凑数继续发插件。
只改运维说明/清单不需要虚构二进制 Release 或无意义版本号；本仓库的默认分支是该说明的交付渠道。

Report per-component decisions, Issue/PR, qualified source commit, release link,
integrity and evidence limits. Safe retirement is a valid outcome when official
parity is proven. Documentation/planning-only changes need no artificial binary
release; this repository's reviewed default branch delivers the operational entrypoint.
