# A/B 适配 Tauri (2026-08-25)

## 迁移了哪些
- dsh-rescue.ps1 / dsh-restart-detached.ps1 + dsh-restart-worker.ps1 / dsh-restart-patched.ps1
  -> 全部改走 Tauri 新壳（deepseek-harness-desktop.exe + node bin.js 健康检测）
- dsh-backup.ps1 -promote -> 健康检测改新 web 条件 + 额外写 B/plugins-manifest.json（doctor --list-plugins）
- 核心诊断/自愈 = dsh-doctor.mjs（体检 11 项 + --fix 自动修复 + --smoke + --list-plugins）

## 退役了什么
- dsh-swap.ps1 (RESEIRET) - 事务化升级器：核心升级已由 Tauri 壳内置管理
  （下载/切换/完整性校验/原子安装），staging/commit/rollback 不再需要。
- dsh-patch-asar-official.mjs / @electron/asar 工具链：无 app.asar 后作废（保留为源码树备用）。
- e2e 验证链变化：升级前置验证 = node dsh-doctor.mjs --fix；启动前 = preflight-check.mjs。

## 推荐日常流程
1. 每次装插件/改配置/换 core 后：node dsh-doctor.mjs （30 秒体检）
2. 出事：node dsh-doctor.mjs --fix；仍不行：确认 A 全停 -> powershell -File dsh-rescue.ps1（B 快照）
3. 每日 03:00 DSH Backup Promote 照常（进度不变）
