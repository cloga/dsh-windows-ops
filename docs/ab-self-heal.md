# A/B 适配 Tauri（dsh-tauri-desk v0.8.2）+ doctor 自愈体系（2026-08-25）

旧壳（Electron）时代的事务化升级（staging/commit/rollback/asar 补丁）已被替代：
- Tauri 壳自带 core 版本管理（下载/切换/完整性校验/原子安装）
- 升级前置验证 = `node dsh-doctor.mjs --fix`；事故首发 = `node dsh-doctor.mjs --fix`；兜底 = `dsh-rescue.ps1`（B 快照 + DSH_HOME 传参给新壳）

工具清单（本机 ~/.dsh/tools/）：
- `dsh-doctor.mjs`：11 项体检（shell/core/patches/config-YAML/plugin-links/dup-insert/banned-plugins/git/vendor-zstd/B-home/shell-proc）+ `--fix` 自动修复（补丁重打、断链 junction 重建、重复 insert 禁用、禁用插件隔离、vendor 恢复）+ `--smoke` 隔离 boot + `--list-plugins`（B 快照清单）+ `--json`（agent/工具）
- `dsh-rescue.ps1`：新壳启动（DSH_HOME=B 传参）+ node bin.js 健康检测
- `dsh-restart-detached.ps1` + `dsh-restart-worker.ps1`：脱树重启壳（WMI）
- `dsh-restart-patched.ps1`：doctor --fix 前置 + 脱树重启（"补丁"=自愈体检，不再 asar）
- `dsh-backup.ps1`：Find-Web 新条件 + promote 写 `B/plugins-manifest.json`（doctor --list-plugins）
- 退役：`dsh-swap.ps1`（事务升级器）→ `.RETIRED`；asar 工具链仅供旧源码树备用

日常流程：
1. 装插件/改配置/换 core 后：`node dsh-doctor.mjs`
2. 出事：`node dsh-doctor.mjs --fix` → 仍不行：全停 A → `dsh-rescue.ps1`
3. 每日 03:00 `DSH Backup Promote` 照常（晋升前提是 A 健康，新 Find-Web 条件）
