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

## 完成标准 / Completion evidence

报告每个组件的处理结论、Issue/PR、源码提交、发布版本/链接、哈希和测试范围。
若官方已经完整替代某插件，退役计划和需求验收可以是适配结果，不要求为了凑数继续发插件。
只改运维说明/清单不需要虚构二进制 Release 或无意义版本号；本仓库的默认分支是该说明的交付渠道。

Report per-component decisions, Issue/PR, qualified source commit, release link,
integrity and evidence limits. Safe retirement is a valid outcome when official
parity is proven. Documentation/planning-only changes need no artificial binary
release; this repository's reviewed default branch delivers the operational entrypoint.
