# dsh-windows-ops

> DeepSeek Harness (DSH) Windows 打包版实战运维经验 + 工具集。
>  English: [README.en.md](README.en.md) / [简体中文](README.md)

本仓库收录在 **Windows 桌面版 DeepSeek Harness**（社区打包 `hairyf/deepseek-harness-desktop`，runtime `@deepseek-ai/dsh` 0.1.x）上实机踩坑、验证、修复后的经验与可复用脚本。

## 改进项目总览

完整的 DSH + GitHub Copilot 集成改进、上游/分叉归属、状态和验证证据统一维护在英文目录：
**[Improvement portfolio](docs/improvement-portfolio.md)**。

## 收录内容

| 类别 | 内容 | 文件 |
|---|---|---|
| 启动稳定性 | 首次启动 60s 超时根因（MCP launcher 网络阻塞）+ 修复 | `docs/startup-60s-timeout.md` |
| 品牌/版本 | 窗口标题品牌 + **版本号**（`DeepSeek Harness v<version>`）补丁 —— **[历史]**：Tauri 壳下由 `patch-worker.mjs applyBrand` 覆盖（3 文件），窗口标题由壳/dsh-tauri 管理，`patch-brand-title.mjs` 仅保留思路参考 | `tools/patch-brand-title.mjs`（历史）、`tools/dsh-updater/patch-worker.mjs` |
| 视觉双通道 | 模型感知双通道（官方 + vision 兜底）设计 + admission 判定铁律 | `docs/vision-dual-channel.md` |
| A/B 自愈 | 配置快照 + 数据 junction + 救援/晋升 —— 版本与修复细节见下方「自愈体系（Tauri 适配）」 | `docs/ab-self-heal.md`、`docs/ab-tauri-adapt.md` |
| 插件安装 | 桌面版插件铁律（junction 必崩 → 物化拷贝）+ compat-check | `tools/dsh-compat-check.mjs` |
| PowerShell 坑 | 5.1 下 HttpClient 需 Add-Type（计划任务健康检查恒失败） | `docs/powershell-5.1-pitfalls.md` |
| GitHub 网络 | ghfast 镜像 git 配置 + release/raw 下载脚本 | `tools/gh-dl.ps1`、`docs/github-network.md` |
| 安全 | 敏感凭据只进 `.env`/环境变量，不进 patch/仓库；asar 只走官方工具 | `docs/security-notes.md` |
| **Agent-native 开发** | **`dsh-dev-tools` 插件**：`dsh_status`/`dsh_patch`/`dsh_build`/`dsh_upgrade` 四工具，agent 会话内 native 操作开发/升级链路 | `tools/dsh-dev-tools/` |
| **可重放/自愈工具** | 组件版本、端口/服务/配置/模型/图片能力自检；严格标记补丁；安全备份、回滚和桌面恢复 | `tools/dsh-replay.ps1`、`docs/windows-replay-tooling.md` |
| **本地 Core + Desktop + Copilot** | 机器锁定、默认只检查的安装流程：Desktop、分叉 core、Copilot2API、loader、四个物理插件、双协议路由、备份和验收契约 | `deployments/windows-copilot.lock.json`、`tools/install-windows-copilot.ps1`、`docs/local-core-desktop-copilot.md` |
| **Copilot ACP 子代理** | 保留原生 spawn/fork，同时把 GitHub Copilot CLI 接成独立 ACP coding agent；记录确定性路由、权限边界、验证与回滚 | `docs/copilot-acp-subagent.md` |
| **Copilot 搜索/视觉一键启用** | 单命令 fail-closed bootstrap：活动本地 core、双 profile Responses provider、搜索冲突禁用、模型/视觉元数据、SlotOutlet/flat-layout、备份与回滚 | `tools/enable-copilot-search-vision.ps1` |
| **会话数据安全** | 重复会话 ID 扫描器 + **原子迁移工具**（官方帧读写、备份在 sessions 外、header 归属校验、验证后删旧）+ **启动预检 preflight**（--smoke 隔离 home 冒烟起 backend）+ 运维脚本 `Set-StrictMode` 加固 | `tools/check-session-duplicates.ps1`、`tools/dsh-move-session.mjs`、`tools/preflight-check.mjs`、`docs/ab-self-heal.md` |
| **会话迁移/侧边栏分组** | 侧边栏按 Host Workspace 注册表（`storages/workspace.json`）分组而非 header.cwd；**标准迁移工具 v2**（文件+注册表一步同步，幂等）、**事后修复**（定点/`--auto` 全量对账）、**运行时修复**（动态 Cordis 插件模板，DSH 运行中无需重启）、**全链路自测**（隔离 home 16 断言） | `tools/dsh-move-session.mjs`、`tools/dsh-workspace-fix.mjs`、`tools/workspace-fix-plugin.template.js`、`tools/dsh-workspace-lib.mjs`、`tools/dsh-move-session.selftest.mjs`、`docs/session-move-workspace-groups.md` |
| **自愈体系（Tauri 适配）** | **`dsh-doctor`** 11 项体检 + `--fix` 自动修复（补丁重打/断链重建/重复 insert 禁用/禁用插件隔离/vendor 恢复）+ `--smoke` 隔离启动 + `--list-plugins`；**A/B 新壳化**（rescue=DSH_HOME=B 传参给 Tauri 壳、restart=脱树外壳重启+doctor 前置、promote=新健康条件+静态插件清单）；旧式 swap 事务升级器退役（core 升级由壳管理）；`dsh-dev-tools` 新增 **`dsh_doctor`** agent 工具 | `tools/dsh-doctor.mjs`、`tools/dsh-rescue.ps1`、`tools/dsh-restart-detached.ps1`、`tools/dsh-restart-worker.ps1`、`tools/dsh-restart-patched.ps1`、`tools/dsh-backup.ps1`、`tools/dsh-dev-tools/`、`tools/vendor/dsh-zstd/`、`docs/ab-tauri-adapt.md` |

## 使用方式

1. **补丁类**（`tools/*.mjs`）：直接 `node <script>`，路径用环境变量/参数传入（见各文件头注释），不写死本机路径。
2. **文档类**：经验与踩坑记录，含根因分析与验证方式。
3. **compat-check**：0 依赖 Node 脚本，装插件前跑一次（静态 import 清单 + `--probe` 实测加载）。
4. **重放/自愈**：先运行 `powershell.exe -File tools\dsh-replay.ps1 -Action SelfCheck`，再用 `-Action Apply -DryRun` 预览严格标记补丁；若本机 execution policy 禁止脚本，可为该进程添加 `-NoProfile -ExecutionPolicy Bypass`，无需修改系统策略。
5. **Windows Copilot 部署**：运行 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install-windows-copilot.ps1`。默认 check 模式不改文件；计划确认无误后，提供锁定的源码目录、发布制品、模型目录快照，并显式添加 `-Apply`。
6. **Copilot bootstrap**：完整部署后，运行 `powershell.exe -File tools\enable-copilot-search-vision.ps1 -Model '<catalog-model-id>'`；不满足活动 core、模型、视觉或 renderer 前置条件时不会改配置。

## 合规说明

- 所有脚本不包含任何 API key / token / 账号信息；凭据一律通过环境变量（如 `GITHUB_PERSONAL_ACCESS_TOKEN`、`DEEPSEEK_API_KEY`）注入，仓库与 patch 零敏感值。
- 本仓库 GitHub 写操作必须使用本地 `.env` 注入并验证为 `cloga` 身份；所有发布分支使用 `cloga-<task-slug>`，详细硬规则见 [`AGENTS.md`](AGENTS.md)。
- 修改 runtime/asar 的任何补丁均**先备份**（`.bak-<日期>`）再改，且提供回滚说明。
- 本仓库收录的本地修复中，已有 **PR 提交到上游**的会标注链接；不是所有本地 hack 都值得提交（如特定版本参数），会在对应文档注明。

## 本仓库与上游的关系

- `tianmingwan/dsh-vision-any`：[PR #2](https://github.com/tianmingwan/dsh-vision-any/pull/2)（model-aware admission + 中性 systemPrompt）
- `Harusame64/desktop-touch-mcp`：[PR #586](https://github.com/Harusame64/desktop-touch-mcp/pull/586)（offline-first release + fetch timeout）
- 仓库内其余内容为本机实践沉淀，部分已对标官方（见各文档）。

## 环境要求

- Windows 10/11，`D:\node.exe`（或任意 Node >= 18）位置用 `NODE_BIN` 环境变量覆盖
- DSH 桌面版（runtime 0.1.0-rc.8 / 0.1.1-rc.2 已验证）；其余版本自行验证
