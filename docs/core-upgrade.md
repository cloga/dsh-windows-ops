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

## 完成标准 / Completion evidence

报告每个组件的处理结论、Issue/PR、源码提交、发布版本/链接、哈希和测试范围。
若官方已经完整替代某插件，退役计划和需求验收可以是适配结果，不要求为了凑数继续发插件。
只改运维说明/清单不需要虚构二进制 Release 或无意义版本号；本仓库的默认分支是该说明的交付渠道。

Report per-component decisions, Issue/PR, qualified source commit, release link,
integrity and evidence limits. Safe retirement is a valid outcome when official
parity is proven. Documentation/planning-only changes need no artificial binary
release; this repository's reviewed default branch delivers the operational entrypoint.
