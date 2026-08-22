# 安全注意事项（本机实践沉淀）

## 铁律

1. **凭据只进环境变量**：`.env`（DEEPSEEK/GITHUB token 等）+ `.credentials.yaml`；**任何 patch 文件、仓库、文档零敏感值**。
   - MCP 子进程会剥掉名字含 `TOKEN/KEY/SECRET` 的环境变量（dsh-subprocess 的 `scrubbedParentEnv`）——如需显式注入，用 wrapper 脚本（`.cmd`/`.ps1` 从 `.env` 读后 `set` 到子进程）
2. **asar 只能用官方工具改**（`@electron/asar`）：手写 asar 字节布局会把 main 放错位置 → Electron 静默退出（实测）。改前备份（`.bak-<日期>`）+ 改后四重验证（布局/入口/main 字段/标记）。
3. **所有 runtime/配置文件改动先备份再改**，补丁幂等（重复跑不破坏，输出 `already`）。

## 贴士

- GitHub token 建议 **fine-grained**（最小权限 + 有效期），别用 repo 全权 classic token 给 agent
- MCP server 默认 **read-only** 启动（`--read-only` flag），确认要写操作再放开
- 不要把 `.env`、`.credentials.yaml`、`*.bak-*`、私钥放进任何 git 仓库（本仓库已 `.gitignore` 掉）
- DSH 崩溃保护会禁用出问题的插件（WD-DISABLED）甚至写坏 patch 文件——改 patch 前先备份，改后 yaml 解析验证
