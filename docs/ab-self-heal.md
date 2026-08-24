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

### 孤儿进程防治（2026-08-23 实测：首次启动 60s 超时的加重元凶）

`taskkill /IM "DeepSeek Harness.exe" /T /F` **只杀 exe 名**，会漏掉两类常驻孤儿：

1. **node 直跑的 DSH web**：`node --expose-internals <某 runtime>\lib\bin.js web --host ...`（如 `tools-analyze\runtime-test` 的测试实例）——它共享同一 `DSH_HOME`，与正式实例抢资源/锁，导致正式实例启动超时
2. **MCP server 子进程**：`github-mcp-server.exe`、`desktop-touch...server-windows.js`——父进程 DSH 死后遗留，重复占用

`dsh-restart-detached.ps1` 已在杀主进程后**按命令行特征补杀**：

```powershell
$orphanWeb = Get-CimInstance Win32_Process | Where-Object {
  $_.Name -match '^node' -and $_.CommandLine -match 'bin\.js.*\bweb\b' -and $_.CommandLine -match '--host'
}
# ... Stop-Process -Force（不清其他 node 进程）
$orphanMcp = Get-CimInstance Win32_Process | Where-Object {
  ($_.Name -match 'github-mcp-server') -or ($_.CommandLine -match 'desktop-touch-mcp.*server-windows\.js')
}
```

**排查命令**（启动慢/超时先跑这个，找 8-20/昨天起常驻的孤儿）：

```powershell
Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^node|github-mcp' } |
  Select-Object ProcessId,Name,CommandLine | Format-Table -AutoSize
# 对照进程启动时间：`Get-Process -Id <pid>`；父进程已死的孤儿（PID 复用）优先清理
```

**⚠️ Find-Web 的另一个坑**：桌面壳主进程自身命令行也含 `web --host`（spawn 参数），`Where-Object { Name -eq 'DeepSeek Harness.exe' -and CommandLine -match 'web --host' }` 会**抓到壳进程而不是 web 服务进程** → 健康检查恒失败（误报 `FAILED: no healthy web instance`，尽管 web 实际健康）。正确匹配：**`--expose-internals` + `bin\.js` + `web --host`** 三个条件缺一不可。

## 会话数据安全（2026-08-24 事故：重复会话 ID 使 DSH 拒启）

**事故**：同一会话 id `session-xxx` 同时存在于**两个项目目录**（`D:\DeepSeek` 628KB 真实会话 + 一个误生成的 160B 空壳，只含 header）→ DSH 启动报 **"duplicate JSONL session id ... appears in multiple project directories"** → **主 DSH 起不来**（不是代码问题，是数据污染）。

**预防纪律**：

1. **动 `~/.dsh/sessions` 前必须跑唯一性扫描**（工具已提供）：
   ```powershell
   powershell.exe -File tools/check-session-duplicates.ps1 -dshHome $env:USERPROFILE\.dsh
   # clean => "OK: no duplicate session ids." (exit 0)
   # 有重复 => 列出；加 -Quarantine <dir> 自动"留第一个目录、移走多余"（可恢复）
   ```
2. **迁移/删除会话 = 工具化原子流程，禁止手改**：
   ```powershell
   node tools/dsh-move-session.mjs <session-id> "D:\转咪"
   # 内置七步：唯一性检查 → 官方帧解压读取（多帧 zstd，每 JSONL 行一帧！）→
   #            备份到 tools/backups（**绝不放 sessions 内**——DSH 扫描器把
   #            sessions 下每个子目录当活动会话，备份放里面 => 位置 vs header
   #            不符 => corrupt 拒启，2026-08-24 事故 #1）→ 改 header.cwd →
   #            官方逐帧压缩写入 projectKey 目录 → 官方读回验证（行数+cwd）
   #            → 验证通过才删旧（绝不留双份）
   ```
   ⚠️ **多帧 zstd 必须用官方的 `scanZstdFrames`/`decompressZstdFrame`/`compressZstdFrame`**
   ——naive 整体解压（整文件 decompress）**只能解出第一帧**，会误判"会话是空壳"
   （2026-08-24 事故 #2：628KB 真实会话被误当 173B 空壳，因为只解了 header 帧）。
   读写会话文件的任何代码都直接 import `@deepseek-ai/dsh-session-persistence-jsonl/lib/types/zstd.js`。
3. **启动前跑 preflight-check**（把 WorkBuddy/Electron v24 那套"完整起 backend 验证"固化）：
   ```powershell
   node tools/preflight-check.mjs            # 只读：重复/stray/位置-vs-header 一致性
   node tools/preflight-check.mjs --smoke    # + 隔离 DSH_HOME 副本起 backend 冒烟（node≥22）
   node tools/preflight-check.mjs --fix      # + 自动把问题目录隔离（不删）
   ```
   smoke 用**隔离 DSH_HOME 副本**（绝不双开真实 home——im-gateway 实例锁 + 数据禁并发）；
   node 必须 ≥22（zstd），默认用 `.workbuddy` 的 22.22.2（可 `DSH_SMOKE_NODE` 覆盖）。
4. **运维脚本统一 `Set-StrictMode -Version Latest`**（`dsh-rescue/dsh-restart-*/dsh-backup/check-session-duplicates` 均已加）：未定义变量（如曾导致救援挂掉的 `$toolsDir`）**立即报错**而非静默空值。注意：`Set-StrictMode` 必须在 `param` 之后；catch 里引用可能未赋值的变量要 `if ($null -ne $x)` 保护。

## 可复用脚本清单

| 脚本 | 作用 |
|---|---|
| `dsh-backup.ps1 -promote` | A 健康快照 → B（robocopy /MIR /SL + junction 重建） |
| `dsh-backup.ps1 -status` | A/B 状态与最后晋升时间 |
| `dsh-rescue.ps1` | 用 B home 拉起完整实例（A 必须先关） |
| `dsh-restart-detached.ps1` | 脱树重启（杀→起→健康检查） |
| `dsh-restart-patched.ps1` | 脱树重启 + asar 补丁版（杀→打 `--no-open` 补丁→起→健康检查；路径用 `DSH_APP_EXE`/`DSH_NODE_BIN`/`DSH_ASAR_PATCHER`/`DSH_TOOLS_DIR` 环境变量覆盖默认值） |
| `dsh-swap.ps1 -build / -commit` | 事务化升级（准备/提交/回滚） |
| `check-session-duplicates.ps1` | 会话唯一性扫描（防重复 ID 拒启；-Quarantine 自动隔离） |
| `dsh-move-session.mjs` | 会话原子迁移（官方帧读写 + 备份在 sessions 外 + header 归属校验 + 验证后删旧） |
| `preflight-check.mjs` | 启动前预检（重复/stray/位置一致；--smoke 隔离 home 起 backend 冒烟；--fix 自动隔离） |

## 相关文件（可参考实现）

- `tools/dsh-backup.ps1`（promote/status/init）
- `tools/dsh-restart-detached.ps1`（脱树重启 + 5.1 兼容）
- `tools/dsh-updater/swap-commit.ps1`（事务化提交，含降级/回滚/needs-human）
