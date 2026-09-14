# 安全注意事项（本机实践沉淀）

## 铁律

1. **复用现有登录，不强制 `.env`**：GitHub 操作默认使用现有 CLI 登录；写入前运行 `gh api user --jq .login`，确认身份为 `cloga`。不要求创建或复制 `.env`，缺少该文件不构成阻断。需要额外凭据时，只从用户指定的可信来源加载到当前进程或 DSH credential store；不得打印、复制到其它仓库、写入 patch 或文档。`.credentials.yaml` 只允许通过 DSH credential API 访问安全元数据。
   - MCP 子进程会剥掉名字含 `TOKEN/KEY/SECRET` 的环境变量（dsh-subprocess 的 `scrubbedParentEnv`）——如需显式注入，只能使用经过审查的 wrapper 从同一可信来源加载，仍不得记录值。
2. **asar 只能用官方工具改**（*2026-08-25 注：仅历史有效——Tauri 壳无 app.asar，该项已作废，保留给旧源码树参考*）（`@electron/asar`）：手写 asar 字节布局会把 main 放错位置 → Electron 静默退出（实测）。改前备份（`.bak-<日期>`）+ 改后四重验证（布局/入口/main 字段/标记）。
3. **所有 runtime/配置文件改动先备份再改**，补丁幂等（重复跑不破坏，输出 `already`）。

## 临时工具、证书文件与云同步

- 下载或解压便携 Git、工具链、浏览器测试配置和缓存之前，先检查目标是否位于 OneDrive 等同步目录。不要直接使用当前工作区；优先选择公司允许的非同步目录，例如 `C:\tmp\dsh-tools\<工具>-<版本>`。临时目录可能被清理，长期工具应使用 IT 批准的持久位置。
- `.tmp-tools` 这样的隐藏命名和 `.gitignore` 只影响显示或 Git 跟踪，不会阻止 OneDrive 上传。下载的 ZIP 与解压后的目录都要考虑同步范围。
- Git 随包提供的 `cert.pem` 通常是 HTTPS 服务器验证用的公共 CA 证书集合，不等于 SSH 私钥或访问 Token。PEM 也能保存私钥，因此不能仅凭扩展名判定；只检查必要的区块标记、官方来源和哈希，不展示秘密内容。安全告警是否属于误报，应由公司安全团队确认。
- 使用非同步目录是减少不必要的云上传，不是规避端点扫描或 DLP。不得关闭 TLS 验证或安全监控、改名/压缩隐藏文件，或盲目删除证书库。使用 Windows Schannel 系统证书库也不会自动删除发行包中的 PEM，不能承诺消除告警。
- 已有工具迁移需先获批准并确认正在使用它的任务：复制到获准位置并校验，更新调用路径，保持证书验证开启并测试成功，最后才清理获准删除的旧工具副本和 ZIP。不得顺带移动项目仓库或修改全局 PATH。

## 贴士

- GitHub token 建议 **fine-grained**（最小权限 + 有效期），别用 repo 全权 classic token 给 agent
- MCP server 默认 **read-only** 启动（`--read-only` flag），确认要写操作再放开
- 不要提交 `.env`、`.credentials.yaml`、`*.bak-*` 或私钥；若自愿使用凭据文件，仓库内文件必须被 Git 忽略，不得在仓库间复制。无需为 GitHub 操作准备 `.env`
- `danger-full-access` 是机器/Session 级策略，不属于部署基线。检查器只能报告安全元数据和风险提示，不得擅自降低或改写用户权限设置
- DSH 崩溃保护会禁用出问题的插件（WD-DISABLED）甚至写坏 patch 文件——改 patch 前先备份，改后 yaml 解析验证
