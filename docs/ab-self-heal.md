# DSH A/B 自愈架构（配置快照 + 数据直连）

> 面向"自改配置容易把活跃版搞坏"的 DSH 用户：始终保留一个**上一个正常版本**作为救援入口，数据实时共享、配置独立快照。

## 架构

```
A（active） = $DSH_HOME（当前活跃版，经常被加插件/改配置搞坏）
B（backup） = $DSH_HOME-backup（上一个正常版本）
```

B 三层组成：

| 层 | 内容 | 方式 |
|---|---|---|
| 数据 | sessions / memories / storages | **junction 直连 A**（实时数据，救援后会话/记忆全在） |
| 插件代码 | profiles\<web\|headless>\node_modules | **junction 直连 A**（跨 runtime 大版本升级后插件必须匹配当前 runtime——旧快照拷贝的插件层在升级后 B 起不来） |
| 配置 | rootFiles + profiles 非 node_modules 层 | **快照**（晋升时刻拷贝，`robocopy /MIR`） |

`profiles\node_modules` 是 **boot 自愈的符号链接农场**：必须是链接（`/SL` 保持），**物化会报 `exists and is not a symlink`**——robocopy 排除它 + `Ensure-FarmJunction` 重建。

## 核心规则（纪律）

1. **晋升（promote）仅当 A 健康**：先找 web 实例 → HTTP 健康检查（200）→ 才快照。**坏的 A 绝不晋升成 B**
2. **A 与 B 严禁同时运行**（共享数据目录 + 单实例锁）——救援前必须彻底关掉 A
3. **绝不自动强杀 A**（历史教训：常驻看门狗误判连续强杀 App 3 次，2026-08-20 已按用户要求彻底移除；**禁止再引入任何自动重启/守护机制**）
4. 危险操作（升级/换 runtime）要**事务化**：

```
准备阶段（A 运行中零中断）:  promote B←A 健康快照 + 构建新版本到 staging（state=staged）
提交阶段（脱树计划任务执行）:  杀 A → 备份 runtime → 换 runtime → 重打本地补丁 → 以 B 启动 → 健康 90s
                              → 成功 done / 失败降级试 A / 再失败回滚 runtime → needs-human
```

## 健康检查的 PowerShell 5.1 坑（2026-08-22 实测）

所有被计划任务（`powershell.exe` = Windows PowerShell 5.1）调用的 `.ps1` 里：

```powershell
# ❌ 5.1 下直接报 "Cannot find type [System.Net.Http.HttpClient]"，Test-Healthy 恒 false
$client = New-Object System.Net.Http.HttpClient

# ✅ 必须先显式加载程序集（PowerShell 7 下 no-op，兼容）
try { Add-Type -AssemblyName System.Net.Http -ErrorAction Stop } catch { }
$client = New-Object System.Net.Http.HttpClient
```

**症状**：每日 03:00 自动晋升日志恒报 `A unhealthy`（而 A 实际健康）、重启脚本的健康检查恒失败。**验证方式：用 `powershell.exe -File` 跑一遍（不是 pwsh 7）**。

## 脱树重启（杀自己不死）

重启 DSH 应用时，重启脚本如果寄生在 DSH 进程树内，`taskkill` 会连脚本一起杀、没人收尾。正确姿势：

```
计划任务（schtasks /Run，脱离进程树）
  → dsh-restart-detached.ps1:
       taskkill /IM "DeepSeek Harness.exe" /T /F
       → 等进程退出（30s 超时+确认）
       → （可选）跑本地补丁（asar 等，此时文件解锁）
       → Start-Process 启动应用
       → 轮询找 web 实例 + HTTP 健康检查（90s 窗口）
       → 结果写结果文件
```

> ⚠️ 计划任务默认 `DisallowStartIfOnBatteries`/`StopIfGoingOnBatteries` 为 true——**笔记本电池供电时任务被跳过（Queued 不执行）**！用 XML 重建任务时显式置 false（`schtasks /Create /XML`）。

## 可复用脚本清单

| 脚本 | 作用 |
|---|---|
| `dsh-backup.ps1 -promote` | A 健康快照 → B（robocopy /MIR /SL + junction 重建） |
| `dsh-backup.ps1 -status` | A/B 状态与最后晋升时间 |
| `dsh-rescue.ps1` | 用 B home 拉起完整实例（A 必须先关） |
| `dsh-restart-detached.ps1` | 脱树重启（杀→起→健康检查） |
| `dsh-swap.ps1 -build / -commit` | 事务化升级（准备/提交/回滚） |

## 相关文件（可参考实现）

- `tools/dsh-backup.ps1`（promote/status/init）
- `tools/dsh-restart-detached.ps1`（脱树重启 + 5.1 兼容）
- `tools/dsh-updater/swap-commit.ps1`（事务化提交，含降级/回滚/needs-human）
