# dsh-windows-ops

[![Windows deployment lock](https://github.com/cloga/dsh-windows-ops/actions/workflows/windows-copilot-lock.yml/badge.svg)](https://github.com/cloga/dsh-windows-ops/actions/workflows/windows-copilot-lock.yml)
[![Plugin catalog](https://github.com/cloga/dsh-windows-ops/actions/workflows/plugin-catalog.yml/badge.svg)](https://github.com/cloga/dsh-windows-ops/actions/workflows/plugin-catalog.yml)
[![License](https://img.shields.io/github/license/cloga/dsh-windows-ops)](LICENSE)

[English](README.en.md) | **简体中文**

> DeepSeek Harness（DSH）Windows 部署基线、运维工具箱与社区插件验证目录。

本仓库沉淀在真实 Windows 环境中验证过的 DSH Desktop/Copilot 部署、诊断、修复和集成经验。它不分发 Desktop、DSH 或第三方插件；正式支持范围由精确锁和验收契约定义。

## 当前正式基线

机器可执行基线以 [`deployments/windows-copilot.lock.json`](deployments/windows-copilot.lock.json) 为准，当前验证日期为 **2026-09-04**：

| 组件 | 锁定版本 |
|---|---|
| DeepSeek Harness Desktop | 官方 0.10.3 |
| Desktop 管理的 DSH runtime | `%APPDATA%\io.github.hairyf.deepseek-harness-desktop\dependencies\dsh` 中的 `deepseek-harness-pkg@0.1.2-alpha.5` wrapper + 内层官方 `@deepseek-ai/dsh@0.1.2-rc.1`；完整 10,347 文件 wrapper tree 锁定哈希且禁止 reparse directory |
| 必需的 `dsh-github-copilot` | 0.3.0-cloga.15 |
| Desktop internal plugins | 官方 8 个 0.6.7 Profile 链接（包括 `dsh-tauri-panel-scheduler`）及 1 个不直接挂载的 panel placeholder，位于 `resources\node_modules` |
| 可选 Web overlays（非基线必需） | `dsh-playwright-host@0.1.2`、`dsh-cron@0.4.1` |

README、插件目录或历史文档中出现一个项目，**不代表它属于该基线**。默认分支和 deployment lock 是本仓库的发布渠道；本仓库不另行分发 Desktop/DSH/plugin 二进制。Lock 更新表示经过评审的目标基线，不代表某台机器已经执行 `-Apply`；默认 check mode 会如实报告尚未应用的 drift。

## 快速入口

| 目标 | 从这里开始 |
|---|---|
| 检查或安装锁定的 Windows + Copilot 基线 | [`docs/local-core-desktop-copilot.md`](docs/local-core-desktop-copilot.md) |
| 运行版本、配置、端口、模型和补丁自检 | [`docs/windows-replay-tooling.md`](docs/windows-replay-tooling.md) |
| 诊断安装问题并执行定点修复 | [`tools/README.md`](tools/README.md) |
| 选择或评估社区插件 | [`docs/plugins/choosing-a-plugin.md`](docs/plugins/choosing-a-plugin.md) |
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

## 工具地图

| 类别 | 主要工具 | 用途 |
|---|---|---|
| 部署 | `tools/install-windows-copilot.ps1` | 默认只检查；显式 `-Apply` 才安装锁定基线 |
| Bootstrap | `tools/enable-copilot-search-vision.ps1`（历史兼容文件名） | 安装直连 Copilot 插件、选择 hosted search，并报告 UI 登录要求；不安装视觉 fallback |
| 可选套件 | `tools/install-optional-companion-suite.ps1` | 依据已安装 Core/Cordis/API 而非 Desktop 补丁版本，单独 Check/Apply/Verify 锁定的 Copilot、Cron 与 Playwright Bundle；不替换 Desktop/Core、全局包或运行中进程 |
| 重放与验收 | `tools/dsh-replay.ps1` | 自检、严格标记补丁、dry-run、备份和回滚 |
| 插件兼容 | `tools/dsh-compat-check.mjs` | 静态依赖清单和真实 host import probe |
| 插件目录 | `tools/validate-plugin-catalog.mjs` | 验证 schema 关键约束、证据引用和基线一致性 |
| 诊断与修复 | `tools/dsh-doctor.mjs` | 安装健康检查、定点修复、隔离启动和插件清单 |
| 会话安全 | `tools/check-session-duplicates.ps1`、`tools/dsh-move-session.mjs` | 重复 ID 检查和原子迁移 |
| Agent-native 运维 | `tools/dsh-dev-tools/` | 会话内状态、补丁、构建、升级和 doctor 工具 |

所有脚本的详细参数以文件头和对应文档为准。

## 文档地图

- **部署与集成**：`local-core-desktop-copilot.md`、`vision-dual-channel.md`（当前为 DSH 原生附件与 `read_image` 架构）
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
- 保留并校验 Desktop 的 8 个官方 0.6.7 Profile 链接（包括 `dsh-tauri-panel-scheduler`）及不直接挂载的 panel placeholder，不用猜测的 registry 包替换。

详见 [`docs/security-notes.md`](docs/security-notes.md)。

## 项目关系与维护状态

本仓库不分发 Desktop、DSH 或 Copilot 插件；它锁定经过验证的版本和 commit，编排安装、迁移、验收与回滚。以下描述当前官方 Desktop 与受控 Copilot 插件的职责和精确 pin。

| 项目 | 在本仓库部署中的职责 | 当前关系 |
|---|---|---|
| [`dsh-tauri-desk/deepseek-harness-desktop`](https://github.com/dsh-tauri-desk/deepseek-harness-desktop) | 官方 Windows 壳、生命周期、Desktop 管理的官方 DSH，以及 8 个 Profile plugins 和 1 个 shipped placeholder | 当前 lock 使用官方 0.10.3，release/tag commit `113dc8f77095e765f4f55e233d8455e7ad9204ae` |
| [`cloga/dsh-github-copilot`](https://github.com/cloga/dsh-github-copilot) | 复用内置 `@deepseek-ai/dsh-llm-pi-ai` 的 Copilot companion：提供登录 UI、Host-only grant 规范化、账号感知的 `models`/strict-mode 叶节点同步、Copilot-scoped Tool Schema 过滤，以及 Responses/Anthropic inline search 与 Responses-only `ctx.web` search；插件保留已有 profile 的非归属字段，Windows deployment 负责清理 legacy connection reference；不包含第二套 adapter、网关或 ACP | PR #56 source commit `4e095196197570776515423929ddb72e8299c1db`；merge/immutable Release commit `473b8aa174eb47a323b026c098b73bf7d716772c`；Release `v0.3.0-cloga.15` |
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
