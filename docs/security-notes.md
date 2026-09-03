# 安全注意事项（本机实践沉淀）

## 铁律

1. **凭据只进当前进程环境或 DSH credential store**：优先使用用户明确指定的集中式可信 `.env`，读取后只写入当前进程；不得打印、复制到其它仓库、写入 patch 或文档。仓库本地 `.env` 仅在用户明确指定且 `git check-ignore` 验证成功时使用；`.credentials.yaml` 只允许通过 DSH credential API 访问安全元数据。
   - MCP 子进程会剥掉名字含 `TOKEN/KEY/SECRET` 的环境变量（dsh-subprocess 的 `scrubbedParentEnv`）——如需显式注入，只能使用经过审查的 wrapper 从同一可信来源加载，仍不得记录值。
2. **asar 只能用官方工具改**（*2026-08-25 注：仅历史有效——Tauri 壳无 app.asar，该项已作废，保留给旧源码树参考*）（`@electron/asar`）：手写 asar 字节布局会把 main 放错位置 → Electron 静默退出（实测）。改前备份（`.bak-<日期>`）+ 改后四重验证（布局/入口/main 字段/标记）。
3. **所有 runtime/配置文件改动先备份再改**，补丁幂等（重复跑不破坏，输出 `already`）。

## 贴士

- GitHub token 建议 **fine-grained**（最小权限 + 有效期），别用 repo 全权 classic token 给 agent
- MCP server 默认 **read-only** 启动（`--read-only` flag），确认要写操作再放开
- 不要提交 `.env`、`.credentials.yaml`、`*.bak-*` 或私钥；集中式可信 `.env` 应位于用户控制的非仓库位置。仓库本地 ignored `.env` 只是显式选择时的兼容方案，不得在仓库间复制
- `danger-full-access` 是机器/Session 级策略，不属于部署基线。检查器只能报告安全元数据和风险提示，不得擅自降低或改写用户权限设置
- DSH 崩溃保护会禁用出问题的插件（WD-DISABLED）甚至写坏 patch 文件——改 patch 前先备份，改后 yaml 解析验证

