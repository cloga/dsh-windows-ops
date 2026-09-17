# dsh-windows-ops

[![Windows deployment lock](https://github.com/cloga/dsh-windows-ops/actions/workflows/windows-copilot-lock.yml/badge.svg)](https://github.com/cloga/dsh-windows-ops/actions/workflows/windows-copilot-lock.yml)
[![Plugin catalog](https://github.com/cloga/dsh-windows-ops/actions/workflows/plugin-catalog.yml/badge.svg)](https://github.com/cloga/dsh-windows-ops/actions/workflows/plugin-catalog.yml)
[![License](https://img.shields.io/github/license/cloga/dsh-windows-ops)](LICENSE)

[English](README.en.md) | **简体中文**

> DeepSeek Harness（DSH）Windows 部署基线、运维工具箱与社区插件验证目录。

本仓库沉淀在真实 Windows 环境中验证过的 DSH Desktop/Copilot 部署、诊断、修复和集成经验。它不分发 Desktop、DSH 或第三方插件；正式支持范围由精确锁和验收契约定义。

## DSH Core 新版本适配入口

以后要求“做 DSH Core 新版本适配”时，先按[官方优先适配流程](docs/core-upgrade.md)
执行：逐项审视 Core fork、Copilot、cron、Playwright 是否已有官方替代，验证等价后
优先迁移。组件清单在 [`core-upgrade-scope.json`](deployments/core-upgrade-scope.json)；
`node tools/plan-core-upgrade.mjs --tag dsh-v<version> --commit <full-SHA>` 只输出计划，
不安装或重启。此入口不是新版本已通过兼容验证的声明，也不修改当前部署锁。

本次 [0.1.6-alpha.2 官方对照与迁移决定](docs/core-016a2-assessment.md)记录已审视的
官方替代、必须保留的差异和已发现的接口问题；目前仍是源码评估，不是新部署基线。

## Copilot 自动识别路由维护

已有新版 Copilot、需要从两条路由统一到账号自动识别目录时，使用[先检查的配置维护流程](docs/copilot-managed-route.md)与独立的 [`copilot-managed-route.policy.json`](deployments/copilot-managed-route.policy.json)。它只允许经过确认的路径级配置 CAS，不安装组件、不重启、不自动修改 Session 或默认模型；不会为了下述独立部署目标替换或降级现有 Desktop。策略中的 Release 必须已验证、指定插件版本必须实际加载；冷历史影响需明确确认。该维护策略不是新的完整 Desktop/Core 验证声明。

## 当前已发布部署目标（Ops 限定 CI 验证已通过）

机器可执行基线以 [`deployments/windows-copilot.lock.json`](deployments/windows-copilot.lock.json) 为准，当前验证日期为 **2026-09-17**：

| 组件 | 锁定版本 |
|---|---|
| DeepSeek Harness Desktop | fork-owned `0.1.6-alpha.1.cloga.1`，release tag `dsh-desktop-v0.1.6-alpha.1.cloga.1`，commit `fae12b69dcd28413518f68b5770e40f8eb2ff730` |
| Desktop 管理的 DSH runtime | installer 内置 `@deepseek-ai/dsh@0.1.6-alpha.1`，由虚拟路径 `resources\app.asar\dsh\desktop-runtime.json` 及独立 unpacked inventory 证明，descriptor SHA-256 `b388ddee840f7de08ac391d4faf7a526ebd40b3bfe0ced8525cf8ac2c9fab344`；默认 root 是 `%LOCALAPPDATA%\Programs\DeepSeek Harness (cloga)\resources\app.asar\dsh`，Windows Ops 以实际安装 EXE 路径为准 |
| 必需的 `dsh-github-copilot` | 0.4.0-alpha.22；在 `desktopNativeVerifiedRelease` 下由 Desktop native capability 保留/接管，不再由 Windows Ops 外部事务物化 |
| Desktop native capability | `desktopNativeVerifiedRelease`，manifest self SHA-256 `50fa6bf1af2ae94bf7e2a032ec00665760b989c7468e514e0005ed78a616e207`，generic plugin compatibility `automaticProvisioning=false` |
| 可选 Web overlays（非基线必需） | `dsh-playwright-host@0.1.7`、`dsh-cron@0.7.1`；已核验不可变 Release 与产物字节，目标 Core `0.1.6-alpha.1`，不代表本机已启用 |

README、插件目录或历史文档中出现一个项目，**不代表它属于该基线**。默认分支和 deployment lock 是本仓库的发布渠道；本仓库不另行分发 Desktop/DSH/plugin 二进制。Lock 更新表示经过评审的目标基线，不代表某台机器已经执行 `-Apply`；默认 check mode 会如实报告尚未应用的 drift。

Replay uses the installer's lock-selected Desktop discovery and bundled runtime
descriptor checks, with no legacy Tauri fallback. SelfCheck/DryRun exit zero is
not deployment acceptance: inspect their `deployment` evidence and patch
statuses. Plugin markers in Web/headless do not prove Desktop Models readiness.

The published fork checks for managed updates about ten seconds after startup.
After confirmation of the impact on active work, its helper downloads/verifies
the release and starts the interactive installer; Windows/UAC prompts remain.
Restart evidence gates completion. This is not an unattended installation.
Copilot alpha.22 uses required host authorization/schemastery peers rather than
private dependency copies; the newly selected bundled Core is `0.1.6-alpha.1`.
React is a Client external singleton (`dsh.client.external`), not a required
Node peer or private runtime dependency. Alpha.22 corrects that alpha.21 startup
failure; published metadata alone still does not prove live Desktop readiness.

Immutable [Release `390539601`](https://github.com/cloga/deepseek-harness/releases/tag/dsh-desktop-v0.1.6-alpha.1.cloga.1)
(sequence 11) was formally published on 2026-09-17 from merged [PR #45](https://github.com/cloga/deepseek-harness/pull/45),
source `fae12b69dcd28413518f68b5770e40f8eb2ff730`, tree
`3ab1707c85ade70f7df5e33e95eb9991b53229f1`, qualified candidate
`6bf111473593dbd9b69cf50a2651b94172a75bac`. All three jobs of formal run
[`35197577605`](https://github.com/cloga/deepseek-harness/actions/runs/35197577605)
succeeded on attempt 1. Six Release assets and eleven formal fixture files were
independently byte-verified. Source-owned acceptance artifact `10486794570`
records isolated initial/restart Copilot Models UI and graph/ancestor isolation.
**Genuine Ops observer/manual qualification passed** in
[run `35210215981`](https://github.com/cloga/dsh-windows-ops/actions/runs/35210215981)
at exact Ops code head `83b0303c250b62f55424be3d88347bf147c593d8`.
[Artifact `10492165208`](https://github.com/cloga/dsh-windows-ops/actions/runs/35210215981/artifacts/10492165208)
records 9,806 runtime files, the actual archive package's full identity, public
resolver/native-addon/policy proof, one observer call and owned-profile cleanup.
See the [scoped evidence and limits](docs/local-core-desktop-copilot.md#scoped-ops-ci-qualification).
No local installation/activation, real OAuth/model round, or installer upgrade was performed. The stable deployment ID remains
`windows-copilot-2026-09-15`; historical `.cloga.5`/`.cloga.7` evidence is retained,
not rewritten as `.6` proof.
Its legacy-compatible update manifest deliberately
keeps `automaticProvisioning=false`; the separately hash-bound build receipt
and packaged capability declare native startup provisioning with the exact
plan. Do not equate those two compatibility objects or relax local registry TLS.
Native registry acceptance binds `dependencyRegistry` to the exact lock-attested
packaged plan and matching receipts/state, not a fixed endpoint or local npm
configuration.
The `.6` Host uses the exact locked Electron EXE in Node mode
(`ELECTRON_RUN_AS_NODE=1`) and exact `--import` policy file URL, Host entry,
ASAR runtime root and profile argv, bound to its Desktop parent. Packaged pnpm
and the updater helper still use physical bundled upstream Node; that is not the
Host carrier. Full virtual inventory and independent `app.asar.unpacked/dsh`
backing checks precede public resolver imports. No materialized Host links or
unverified fallback runtime is accepted.
The native plugin registry remains `https://packagefeedproxy.microsoft.io/npm/`
with normal TLS and unchanged Copilot plan hash; the frozen source-build registry
remains `https://registry.npmjs.org/`. Core is now `0.1.6-alpha.1`; Copilot remains
alpha.22. Ownership-aware checks retain user extras as `contentsAttested:false`,
not baseline health, while required Copilot proof remains exact even if user-owned.
Formal source ancestor-SDK acceptance passed; its eleven new raw fixture files
are under `formal-cloga016-1`. The separate successful Ops summary is retained
under `ops-cloga016-1`; neither evidence set establishes local OAuth or a model
response, and neither authorizes activation.

Historical `0.1.5-rc.3.cloga.1`/`.cloga.2` copied helpers cannot bootstrap because of an
unresolved `semver` import. They cannot repair themselves by discovering a newer
release. Recovery requires the independently verified current `0.1.6-alpha.1.cloga.1` installer,
explicit interruption consent and a clean Desktop/Host exit, coordinated by the
operator outside the broken helper. Do not patch live files or install missing
dependencies into an update operation. Generic direct registry probe failures
are not evidence that the supported provisioner failed.

Native `Check` separates exact installed files/receipts from functional evidence.
The Electron Host uses parent-owned byte pipes, not `127.0.0.1:3080`; Web checks
cannot prove native Models readiness. `Verify` reports
`manual-verification-required` (exit 2); independently record Desktop UI and real
model-response acceptance outside this CLI. Missing native Remote
access is unknown, never success. Legacy Apply/rollback/restart are blocked for
the native lock; use the native managed updater and its live Session impact
confirmation instead.

## 快速入口

| 目标 | 从这里开始 |
|---|---|
| 检查或安装锁定的 Windows + Copilot 基线 | [`docs/local-core-desktop-copilot.md`](docs/local-core-desktop-copilot.md) |
| 查找 Desktop 持久更新提示并安全使用 **Review update**（保留历史 `.cloga.8` 发布证据；不代表当前 `.6` 本机激活） | [提示位置、使用方式与安全边界](docs/local-core-desktop-copilot.md#persistent-update-notice) |
| 从官方 `dsh-v0.1.5-rc.2` 源码构建并并排安装 Electron Desktop 本地构建；选择默认隔离 Home 或显式复用已有 Home，并了解手动更新通道 | [`docs/official-desktop-local-build.md`](docs/official-desktop-local-build.md) |
| 运行版本、配置、端口、模型和补丁自检 | [`docs/windows-replay-tooling.md`](docs/windows-replay-tooling.md) |
| 诊断安装问题并执行定点修复 | [`tools/README.md`](tools/README.md) |
| 选择或评估社区插件 | [`docs/plugins/choosing-a-plugin.md`](docs/plugins/choosing-a-plugin.md) |
| 区分 Desktop 注册表包、已验证 Release 与已发布但未在本机激活的源码快照安装能力；了解重新安装和损坏快照恢复 | [`docs/plugins/desktop-source-installation.md`](docs/plugins/desktop-source-installation.md) |
| 理解插件验证等级 | [`docs/plugins/plugin-validation.md`](docs/plugins/plugin-validation.md) |
| 评估 Computer Use / 浏览器自动化 | [`docs/plugins/computer-use.md`](docs/plugins/computer-use.md) |
| 运维可选的 Session 定时调度 | [`docs/plugins/scheduling.md`](docs/plugins/scheduling.md) |
| 一次检查或安装 Copilot、Cron 与 Playwright 可选套件 | [`docs/plugins/optional-companion-suite.md`](docs/plugins/optional-companion-suite.md) |
| 查看机器可读插件目录 | [`catalog/plugins.json`](catalog/plugins.json) |
| 查看改进归属、PR 状态和验证证据 | [`docs/improvement-portfolio.md`](docs/improvement-portfolio.md) |
| 提交变更或私密报告安全问题 | [`CONTRIBUTING.md`](CONTRIBUTING.md) / [`SECURITY.md`](SECURITY.md) |

## 三类“验证”不要混淆

1. **插件目录**：[`catalog/plugins.json`](catalog/plugins.json) 记录发现、源码审查、入口兼容、组合挂载、功能冒烟、部署验证和锁定基线等级。
2. **兼容检查**：`tools/dsh-compat-check.mjs` 检查已放入 Profile 的社区插件依赖和 host 入口 import；通过仅表示 **import-compatible**，不证明功能或安全性。
3. **部署锁**：`deployments/*.lock.json` 锁定精确版本、commit、制品哈希、安装步骤、验收和回滚；这是正式支持范围。

安装社区插件前，先使用一次性测试 Profile：

```powershell
node tools\dsh-compat-check.mjs <profile> --probe=<package>
node tools\validate-plugin-catalog.mjs
```

然后在隔离 `DSH_HOME` 中验证 Cordis 激活、工具注册和代表性功能，再提升目录等级。不要直接拿维护中的 `web` Profile 做首次试装。

**用户反馈候选：** [`csyangwen/dsh-memory-evolve`](https://github.com/csyangwen/dsh-memory-evolve/tree/c337dc1af7b5c8a5578e03150bf5c4d6133f66f9) 被用户评价为“对跨会话记忆/演化工作流有用”（User-reported useful for cross-session memory/evolution workflows），但本仓库仅对 commit `c337dc1af7b5c8a5578e03150bf5c4d6133f66f9` / tag `v26091501` 完成 `L1` 源码审查，目录推荐为 `experimental`。其 Release 无资产/校验清单，未声明 DSH peer 范围，也未完成隔离挂载或功能/安全验证；详见[插件选择指南](docs/plugins/choosing-a-plugin.md#user-reported-high-privilege-candidates)。它涉及长期记忆、后台演化、技能/提示词修改、自更新及可选外部 CLI、Git 同步和消息发送，首次使用必须隔离 Profile 并审查数据保留与自动修改边界；不属于 Windows locked baseline、Desktop 必需插件或默认自动安装。

[Desktop 源码快照安装说明](docs/plugins/desktop-source-installation.md)保留核心 [issue #50](https://github.com/cloga/deepseek-harness/issues/50) / PR #53 首次随历史 Desktop `.cloga.7`（sequence 9、PR #57）发布的证据。当前 lock 已选择 `.6` 的 `0.1.6-alpha.1.cloga.1`，且限定范围的 Ops observer CI 验证已通过 run `35210215981`；本机仍未安装或激活。固定 Memory Evolve commit 的原始获取/打包、隔离 renderer 与 pnpm fixture 不会因此变成 `.6` 运行证据或插件激活，也不提升 `L1`/`experimental` 等级；使用前仍须完成目标机器的检查和单独授权的原生安装流程。

## 工具地图

| 类别 | 主要工具 | 用途 |
|---|---|---|
| 部署 | `tools/install-windows-copilot.ps1` | 默认只读检查；当前 native lock 拒绝外部 Apply/重启，原生安装须另行授权 |
| 官方源码本地 Desktop | `tools/install-official-desktop-local.ps1` | Check by default; explicit `-Apply -AcknowledgeUnsignedLocalBuild` runs the exact `PackageLocal` flow and installs side-by-side. The single `desktopProvisioning` adapter preserves native delegation; Windows Ops does not populate the reserved profile. New installs use an isolated Harness home; `-SharedHome <existing-home>` opts into an existing home and Electron user data remains separate |
| 本地 Desktop 更新通道 | `tools/manage-official-desktop-update-channel.ps1` | `Check` 只读检查远端 manifest；一次显式 `Install` 自动下载、验证并暂存后启动交互式 NSIS 安装器，保留 Windows/UAC 确认，再严格 `Complete` 回读并运行同一插件 provisioning adapter；不是 silent/automatic update，仍不发布、不嵌入 `app-update.yml`，并保留独立 Package/Stage/Complete 恢复路径 |
| Bootstrap | `tools/enable-copilot-search-vision.ps1`（历史兼容文件名） | 安装直连 Copilot 插件、选择 hosted search，并报告 UI 登录要求；不安装视觉 fallback |
| 可选套件 | `tools/install-optional-companion-suite.ps1` | 依据已安装 Core/Cordis/API 而非 Desktop 补丁版本，单独 Check/Apply/Verify 锁定的 Copilot、Cron 与 Playwright Bundle；不替换 Desktop/Core、全局包或运行中进程 |
| 重放与验收 | `tools/dsh-replay.ps1` | 自检、严格标记补丁、dry-run、备份和回滚 |
| 插件兼容 | `tools/dsh-compat-check.mjs` | 静态依赖清单和真实 host import probe |
| 插件目录 | `tools/validate-plugin-catalog.mjs` | 验证 schema 关键约束、证据引用和基线一致性 |
| 诊断与修复 | `tools/dsh-doctor.mjs` | 安装健康检查、定点修复、隔离启动和插件清单 |
| 会话安全 | `tools/check-session-duplicates.ps1`、`tools/dsh-move-session.mjs` | 重复 ID 检查和原子迁移 |
| Agent-native 运维 | `tools/dsh-dev-tools/` | 会话内状态、补丁、构建、升级和 doctor 工具 |

所有脚本的详细参数以文件头和对应文档为准。

**ASAR 入口边界（限定 Ops CI 验证已通过）：** 可选 Web 安装器针对 ASAR 默认目标会明确要求一个已存在、兼容的物理 `-RuntimeRoot`，不会额外安装或复制 Core；已有用户 Agent Presets 的 ASAR target 校验会明确报告未支持，不会跳过并宣称通过。Replay 使用受审计的只读原生状态，并拒绝不可变归档补丁和原生变更。详见[工具边界](tools/README.md#asar-entrypoint-boundaries)；`.6` 正式 Release、来源验收和限定范围的 [Ops observer CI `35210215981`](https://github.com/cloga/dsh-windows-ops/actions/runs/35210215981) 已通过，以上未支持的入口仍保持未支持，本说明不代表本机安装或激活。

## 文档地图

- **部署与集成**：`local-core-desktop-copilot.md`、`vision-dual-channel.md`（当前为 DSH 原生附件与 `read_image` 架构）
- **官方源码本地 Desktop**：`official-desktop-local-build.md`（`PackageLocal` 默认无更新通道；另有远端 Check、显式 one-click Install 和 Package/Stage/Complete 恢复流程）
- **插件治理与可选 overlays**：`docs/plugins/`（包括 `computer-use.md`、`scheduling.md`、`better-sidebar.md`）及 `catalog/`
- **诊断与迁移**：`tools/README.md`、`windows-replay-tooling.md`、`session-move-workspace-groups.md`
- **事故与平台问题**：`startup-60s-timeout.md`、`powershell-5.1-pitfalls.md`、`github-network.md`
- **维护状态**：`improvement-portfolio.md`、`windows-replay-tooling.md`

## 安全铁律

- GitHub 操作默认使用现有 CLI 登录，`.env` 可选，不是前置条件。额外凭据只从用户明确指定的可信来源加载到当前进程或 DSH credential service；绝不打印、跨仓库复制或提交其值。
- 社区 MCP 默认 read-only；明确需要副作用后再启用写操作。
- Computer Use、真实浏览器控制和视觉插件可能接触屏幕、Cookie、聊天、密码和本机应用；推荐状态必须与功能验证等级分开。
- 所有 runtime/配置改动先备份，补丁必须幂等并提供回滚。
- 重启 Desktop/Host 前必须查询 live Sessions；存在 running Session 时必须先取得用户对中断列表的明确确认。
- 保留并校验 active lock mode 声明的 Desktop plugin surface；在 `desktopNativeVerifiedRelease` 下，Windows Ops 只做 native delegation，不再物化 reserved Desktop profile。
- 插件分三层治理：locked managed baseline 继续严格失败；用户自行安装的插件只进入 inventory/warning，不能贡献 baseline 健康；仅精确命中目标 Core denylist 且处于活动或状态不明时阻断 cutover。

详见 [`docs/security-notes.md`](docs/security-notes.md)。

## 项目关系与维护状态

本仓库不分发 Desktop、DSH 或 Copilot 插件；它锁定经过验证的版本和 commit，编排安装、迁移、验收与回滚。以下描述当前 fork-owned Desktop release 与受控 Copilot 插件的职责和精确 pin。

| 项目 | 在本仓库部署中的职责 | 当前关系 |
|---|---|---|
| [`cloga/deepseek-harness`](https://github.com/cloga/deepseek-harness) | fork-owned Windows Desktop release channel、生命周期、Desktop-managed bundled DSH runtime，以及 `desktopNativeVerifiedRelease` generic plugin capability | 当前 lock 使用已发布 `dsh-desktop-v0.1.6-alpha.1.cloga.1`，commit `fae12b69dcd28413518f68b5770e40f8eb2ff730`；限定 Ops observer CI `35210215981` 已通过，未本机激活 |
| [`cloga/dsh-github-copilot`](https://github.com/cloga/dsh-github-copilot) | 复用内置 `@deepseek-ai/dsh-llm-pi-ai` 的 Copilot companion：提供登录 UI、Host-only grant 规范化、账号感知的 `models`/strict-mode 叶节点同步、Copilot-scoped Tool Schema 过滤，以及 Responses/Anthropic inline search 与 Responses-only `ctx.web` search；插件保留已有 profile 的非归属字段，Windows deployment 负责清理 legacy connection reference；不包含第二套 adapter、网关或 ACP | PR #133 source/merge/immutable Release commit `479340f965c5be7b4408e4f1e6c9dda6c421d37b`；Release `v0.4.0-alpha.22` |
| [`cloga/dsh-windows-ops`](https://github.com/cloga/dsh-windows-ops) | 精确锁、check-first 安装器、迁移、验收和回滚 | 默认分支维护当前 Windows + Copilot 部署基线 |

历史 ACP 子代理实践仍保留在
[`docs/copilot-acp-subagent.md`](docs/copilot-acp-subagent.md)，但它是独立的可选集成，
不属于 `dsh-github-copilot` 的统一主代理模型路径。

“All-in-one”指一个 DSH 插件复用内置 `llm-pi-ai` 服务，并不表示内嵌网关：
当前基线不需要本地网关进程、端口 7777、粘贴 GitHub token、占位 API key
或独立搜索插件。

改进归属、外部上游状态和验证证据统一维护在 [`docs/improvement-portfolio.md`](docs/improvement-portfolio.md)。发布或升级前以 deployment lock 和兼容矩阵为准，不要根据 README 中的版本字符串自行混搭组件。

## 环境要求

- Windows 10/11；
- 锁定基线要求 Node `^22.19.0 || >=24.0.0`；
- 修改正式基线时必须同步更新 lock、fixture、测试和说明文档。

本仓库的社区插件目录仍会包含实验或历史项目；只有标记为 `baseline` 且能对应到 deployment lock 的组件属于当前正式支持配置。
