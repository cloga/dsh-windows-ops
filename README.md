# dsh-windows-ops

> DeepSeek Harness (DSH) Windows 打包版实战运维经验 + 工具集。
>  English: [README.en.md](README.en.md) / [简体中文](README.md)

本仓库收录在 **Windows 桌面版 DeepSeek Harness**（社区打包 `hairyf/deepseek-harness-desktop`，runtime `@deepseek-ai/dsh` 0.1.x）上实机踩坑、验证、修复后的经验与可复用脚本。

## 收录内容

| 类别 | 内容 | 文件 |
|---|---|---|
| 启动稳定性 | 首次启动 60s 超时根因（MCP launcher 网络阻塞）+ 修复 | `docs/startup-60s-timeout.md` |
| 品牌/版本 | 窗口标题品牌 + **版本号**（`DeepSeek Harness v<version>`）补丁 | `tools/patch-brand-title.mjs` |
| 视觉双通道 | 模型感知双通道（官方 + vision 兜底）设计 + admission 判定铁律 | `docs/vision-dual-channel.md` |
| A/B 自愈 | 配置快照 + 数据 junction + 脱树计划任务重启 + 事务化升级 | `docs/ab-self-heal.md` |
| 插件安装 | 桌面版插件铁律（junction 必崩 → 物化拷贝）+ compat-check | `tools/dsh-compat-check.mjs` |
| PowerShell 坑 | 5.1 下 HttpClient 需 Add-Type（计划任务健康检查恒失败） | `docs/powershell-5.1-pitfalls.md` |
| GitHub 网络 | ghfast 镜像 git 配置 + release/raw 下载脚本 | `tools/gh-dl.ps1`、`docs/github-network.md` |
| 安全 | 敏感凭据只进 `.env`/环境变量，不进 patch/仓库；asar 只走官方工具 | `docs/security-notes.md` |
| **Agent-native 开发** | **`dsh-dev-tools` 插件**：`dsh_status`/`dsh_patch`/`dsh_build`/`dsh_upgrade` 四工具，agent 会话内 native 操作开发/升级链路 | `tools/dsh-dev-tools/` |
| **会话数据安全** | 重复会话 ID 扫描器（防 DSH 起不来）+ **原子迁移工具**（五步：唯一性检查→备份→新位置+改cwd→读回验证→删旧）+ 运维脚本 `Set-StrictMode` 加固 | `tools/check-session-duplicates.ps1`、`tools/dsh-move-session.mjs`、`docs/ab-self-heal.md` |

## 使用方式

1. **补丁类**（`tools/*.mjs`）：直接 `node <script>`，路径用环境变量/参数传入（见各文件头注释），不写死本机路径。
2. **文档类**：经验与踩坑记录，含根因分析与验证方式。
3. **compat-check**：0 依赖 Node 脚本，装插件前跑一次（静态 import 清单 + `--probe` 实测加载）。

## 合规说明

- 所有脚本不包含任何 API key / token / 账号信息；凭据一律通过环境变量（如 `GITHUB_PERSONAL_ACCESS_TOKEN`、`DEEPSEEK_API_KEY`）注入，仓库与 patch 零敏感值。
- 修改 runtime/asar 的任何补丁均**先备份**（`.bak-<日期>`）再改，且提供回滚说明。
- 本仓库收录的本地修复中，已有 **PR 提交到上游**的会标注链接；不是所有本地 hack 都值得提交（如特定版本参数），会在对应文档注明。

## 本仓库与上游的关系

- `tianmingwan/dsh-vision-any`：[PR #2](https://github.com/tianmingwan/dsh-vision-any/pull/2)（model-aware admission + 中性 systemPrompt）
- `Harusame64/desktop-touch-mcp`：[PR #586](https://github.com/Harusame64/desktop-touch-mcp/pull/586)（offline-first release + fetch timeout）
- 仓库内其余内容为本机实践沉淀，部分已对标官方（见各文档）。

## 环境要求

- Windows 10/11，`D:\node.exe`（或任意 Node >= 18）位置用 `NODE_BIN` 环境变量覆盖
- DSH 桌面版（runtime 0.1.0-rc.8 / 0.1.1-rc.2 已验证）；其余版本自行验证
