# dsh-windows-ops

> DeepSeek Harness（DSH）Windows 部署基线、运维工具箱与社区插件验证目录。
>
> English: [README.en.md](README.en.md) / [简体中文](README.md)

本仓库沉淀在真实 Windows 环境中验证过的 DSH Desktop/Core/Copilot 部署、诊断、修复和集成经验。它不分发 Desktop、Core 或第三方插件；正式支持范围由精确锁和验收契约定义。

## 当前正式基线

机器可执行基线以 [`deployments/windows-copilot.lock.json`](deployments/windows-copilot.lock.json) 为准，当前验证日期为 **2026-09-02**：

| 组件 | 锁定版本 |
|---|---|
| DeepSeek Harness Desktop | 0.9.2 |
| `@deepseek-ai/dsh` Core | 0.1.1-rc.2 |
| `dsh-github-copilot` | 0.3.0-cloga.6 |
| Desktop internal plugins | 官方 5 个 0.4.9 组件 |

README、插件目录或历史文档中出现一个项目，**不代表它属于该基线**。

## 快速入口

| 目标 | 从这里开始 |
|---|---|
| 检查或安装锁定的 Windows + Copilot 基线 | [`docs/local-core-desktop-copilot.md`](docs/local-core-desktop-copilot.md) |
| 运行版本、配置、端口、模型和补丁自检 | [`docs/windows-replay-tooling.md`](docs/windows-replay-tooling.md) |
| 诊断安装问题并执行定点修复 | [`tools/README.md`](tools/README.md) |
| 选择或评估社区插件 | [`docs/plugins/choosing-a-plugin.md`](docs/plugins/choosing-a-plugin.md) |
| 理解插件验证等级 | [`docs/plugins/plugin-validation.md`](docs/plugins/plugin-validation.md) |
| 评估 Computer Use / 浏览器自动化 | [`docs/plugins/computer-use.md`](docs/plugins/computer-use.md) |
| 查看机器可读插件目录 | [`catalog/plugins.json`](catalog/plugins.json) |
| 查看改进归属、PR 状态和验证证据 | [`docs/improvement-portfolio.md`](docs/improvement-portfolio.md) |

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
| Bootstrap | `tools/enable-copilot-search-vision.ps1` | 安装直连插件、选择 hosted search，并报告 UI 登录要求 |
| 重放与验收 | `tools/dsh-replay.ps1` | 自检、严格标记补丁、dry-run、备份和回滚 |
| 插件兼容 | `tools/dsh-compat-check.mjs` | 静态依赖清单和真实 host import probe |
| 插件目录 | `tools/validate-plugin-catalog.mjs` | 验证 schema 关键约束、证据引用和基线一致性 |
| 诊断与修复 | `tools/dsh-doctor.mjs` | 安装健康检查、定点修复、隔离启动和插件清单 |
| 会话安全 | `tools/check-session-duplicates.ps1`、`tools/dsh-move-session.mjs` | 重复 ID 检查和原子迁移 |
| Agent-native 运维 | `tools/dsh-dev-tools/` | 会话内状态、补丁、构建、升级和 doctor 工具 |

所有脚本的详细参数以文件头和对应文档为准。

## 文档地图

- **部署与集成**：`local-core-desktop-copilot.md`、`vision-dual-channel.md`
- **插件治理**：`docs/plugins/`、`catalog/`
- **诊断与迁移**：`tools/README.md`、`windows-replay-tooling.md`、`session-move-workspace-groups.md`
- **事故与平台问题**：`startup-60s-timeout.md`、`powershell-5.1-pitfalls.md`、`github-network.md`
- **维护状态**：`improvement-portfolio.md`、`windows-replay-tooling.md`

## 安全铁律

- 凭据只从 `.env`、环境变量或 DSH credential service 注入，绝不写入 patch、文档、fixture 或提交。
- 社区 MCP 默认 read-only；明确需要副作用后再启用写操作。
- Computer Use、真实浏览器控制和视觉插件可能接触屏幕、Cookie、聊天、密码和本机应用；推荐状态必须与功能验证等级分开。
- 所有 runtime/配置改动先备份，补丁必须幂等并提供回滚。
- 保留并校验 Desktop 的 5 个官方 internal-plugin 链接，不用猜测的 registry 包替换。

详见 [`docs/security-notes.md`](docs/security-notes.md)。

## 项目关系与维护状态

本仓库不分发 Desktop、Core 或 Copilot 插件；它锁定经过验证的版本和 commit，编排安装、迁移、验收与回滚。`cloga/*` 是我们控制的部署 fork，以下描述其默认分支能力和当前部署 pin，而不是内部 PR 流程状态。

| 项目 | 在本仓库部署中的职责 | 当前关系 |
|---|---|---|
| [`dsh-tauri-desk/deepseek-harness-desktop`](https://github.com/dsh-tauri-desk/deepseek-harness-desktop) | 官方 Windows 壳、生命周期和五个 internal plugins | 当前 lock 使用官方 0.9.2 |
| [`cloga/deepseek-harness`](https://github.com/cloga/deepseek-harness) | 本地 Core、模型/视觉元数据、receipt 安装、sandbox 策略和严格 pi-ai OAuth JSON 记录规范化 | 部署精确 pin `ec7aa651` |
| [`cloga/dsh-github-copilot`](https://github.com/cloga/dsh-github-copilot) | 一个包含 rc.2 Desktop 客户端 ModuleLoader handoff、严格 Remote 结果 codec 和严格 JSON OAuth grant 规范化的 DSH 插件，复用内置 `@deepseek-ai/dsh-llm-pi-ai` 的 OAuth、账户模型、刷新、Copilot 直连和 hosted search；在 rc.2 中启动 authorization service，并在 alpha.4 中复用已有服务；不包含 ACP | 部署精确 pin `dd562f8a` / `0.3.0-cloga.6` |
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
