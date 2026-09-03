# PowerShell 5.1 坑（Windows 计划任务/运维脚本）

> 本机为 Windows + PowerShell 5.1（计划任务默认 `powershell.exe`）+ 偶尔 pwsh 7。以下坑在 DSH 运维脚本中实测踩中。

## 1. HttpClient 类型缺失（最坑）

```powershell
# ❌ PowerShell 5.1 下运行报错：
#    Cannot find type [System.Net.Http.HttpClient]: verify that the assembly containing this type is loaded.
#    （.NET Framework 4.5+ 的类型，5.1 默认不加载 System.Net.Http 程序集）
$client = New-Object System.Net.Http.HttpClient

# ✅ 正确：先显式加载（PowerShell 7 下 no-op）
try { Add-Type -AssemblyName System.Net.Http -ErrorAction Stop } catch { }
$client = New-Object System.Net.Http.HttpClient
$client.Timeout = [TimeSpan]::FromSeconds(6)
$resp = $client.GetAsync('http://127.0.0.1:' + $port + '/').Result
```

**症状**：`Test-Healthy` 恒返回 false，导致健康检查或旧式重启脚本误判实例不可用（日志能查到，但 Web 实际健康）。仓库现已移除依赖该判断的双 Home 快照、晋升和救援工具。

## 2. .ps1 编码（UTF-8 无 BOM 按 GBK 解码）

PowerShell 5.1（右键"使用 PowerShell 运行"）对 UTF-8 无 BOM 的 `.ps1` **按 GBK 解码**，含中文注释/字符串会乱码导致**脚本解析崩溃**。

- 生成 `.ps1` 一律**纯 ASCII**（英文注释/输出）或**带 BOM**
- `.bat`/`.cmd` 本身用 ASCII 编码

## 3. 提权脚本配 .bat 启动器

需要 UAC 提权运行的清理脚本，配一个 `.bat` 启动器（`powershell Start-Process -Verb RunAs`）让用户双击自动弹 UAC，比右键菜单稳。

## 4. PowerShell 保留变量

`$pid` 不能赋值用于循环追踪（会被忽略，永远打印当前进程号）。

## 5. 脚本内的内部命令解析

- `curl.exe` 调用时参数**带引号/空格会干扰**；用数组/管道或 `2>$null | Out-Null` 时注意 `$ErrorActionPreference`
- `npx.cmd` / `npm` 在无 `AppData\Roaming\npm` 目录的机器上恒报 `ENOENT: lstat ...Roaming\npm`（见 startup-60s 文档）——**优先直跑本地包/二进制，别依赖 npx**

## 6. 计划任务电池限制

`schtasks /Create` 默认生成的 XML 含：

```xml
<DisallowStartIfOnBatteries>true</DisallowStartIfOnBatteries>
<StopIfGoingOnBatteries>true</StopIfGoingOnBatteries>
```

**笔记本电池供电时任务被跳过**（状态 Queued 但不执行）。用 `/Create /XML` 重建时显式设 false。

## 7. DSH 安装 Agent 的用户级缓解规则

DSH 支持从 `$DSH_HOME/AGENTS.md` 加载用户级指令；默认路径是
`~/.dsh/AGENTS.md`。如果安装环境中的 Agent 反复错误请求 PowerShell
sandbox escalation，可在该文件中合并以下可复用的英文片段：

```markdown
## Mandatory PowerShell payload preflight

Before emitting every `pwsh` tool call:

1. Read the current runtime sandbox mode and approval status.
2. For an initial call, omit `sandbox_permissions` and `justification` entirely.
3. If approval prompts are disabled, the payload MUST NOT contain either key.
4. If the current sandbox mode is `danger-full-access`, the payload MUST NOT contain either key.
5. Add both keys only when retrying the exact same command once after a real sandbox denial, approval is available, and the requested mode is strictly wider than the current mode.
6. Omit the keys themselves; never send them as `null`, empty strings, or the current sandbox mode.
```

安装器应把这段规则**合并**到已有用户指令中，而不是覆盖整个文件；未经用户明确同意，不得静默创建或修改用户的 `AGENTS.md`。

## 8. DSH 子进程继承了不完整的 Git 临时配置

Git 用成组环境变量传递一次性配置：`GIT_CONFIG_COUNT=N` 必须同时存在从
`GIT_CONFIG_KEY_0` / `GIT_CONFIG_VALUE_0` 到 `N-1` 的完整键值对。如果 DSH
启动的 PowerShell 只继承了 `COUNT` 和 `VALUE_*`，任何 `git` 命令都会在读取
仓库前失败：

```text
error: missing config key GIT_CONFIG_KEY_0
fatal: unable to parse command-line config
```

先只检查变量名；不要输出值，因为合法的临时 Git 配置可能携带认证 header：

```powershell
Get-ChildItem Env:GIT_CONFIG_* | Select-Object -ExpandProperty Name
```

确认键值组确实不完整后，仅在当前 PowerShell 进程清除两种临时配置传递方式，
再重试原 Git 命令：

```powershell
Remove-Item Env:GIT_CONFIG_COUNT,Env:GIT_CONFIG_PARAMETERS -ErrorAction SilentlyContinue
Remove-Item Env:GIT_CONFIG_KEY_*,Env:GIT_CONFIG_VALUE_* -ErrorAction SilentlyContinue

git status
```

这不会修改用户或系统环境，也不会改写 Git 配置文件；下一个 PowerShell 进程仍会
重新继承启动方提供的环境，所以自动化脚本应在每个 Git 入口执行同一项有界检查。
如果 `KEY_*` / `VALUE_*` 组完整，则不要清除它们：那些值可能是调用方有意设置的
代理、TLS 或认证边界。
