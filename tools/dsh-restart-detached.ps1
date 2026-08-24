# dsh-restart-detached.ps1 - clean app restart, run OUTSIDE the app process
# tree (scheduled task) so killing the app cannot kill this script.
# Steps: kill all DeepSeek Harness -> wait -> start desktop shell -> wait for
# the web instance to come up healthy. Result written to dsh-auto-restart.out
# and logged to dsh-auto-restart.log.
# 2026-08-24 加固：未定义变量立即报错（防静默空值类 bug）。
Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'
$appExe   = 'D:\deepseek-harness\DeepSeek Harness\DeepSeek Harness.exe'
$logOut   = 'C:\Users\sephen\.dsh\tools\dsh-auto-restart.out'
$logFile  = 'C:\Users\sephen\.dsh\tools\dsh-auto-restart.log'
function Log([string]$m) { Add-Content -Path $logFile -Value ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -Encoding UTF8; Write-Output $m }
function Find-Web { return (Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'DeepSeek Harness.exe' -and $_.CommandLine -match '--expose-internals' -and $_.CommandLine -match 'bin\.js' -and $_.CommandLine -match 'web --host' } | Select-Object -First 1) }
function Test-Healthy([int]$pid) {
  try { Add-Type -AssemblyName System.Net.Http -ErrorAction Stop } catch { }
  $port = Get-NetTCPConnection -OwningProcess $pid -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalAddress -eq '127.0.0.1' } | Select-Object -First 1 -ExpandProperty LocalPort
  if (-not $port) { return $null }
  try { $c = New-Object System.Net.Http.HttpClient; $c.Timeout = [TimeSpan]::FromSeconds(6); $r = $c.GetAsync('http://127.0.0.1:' + $port + '/').Result; $r.Dispose(); $c.Dispose(); return $port } catch { if ($null -ne $c) { try { $c.Dispose() } catch { } }; return $null }
}

Log 'clean restart start'
taskkill /IM 'DeepSeek Harness.exe' /T /F 2>&1 | Out-Null
# ── 2026-08-23 补：taskkill /IM 只杀 exe 名，会漏掉：① 由 node 直跑的 DSH web
#   （--expose-internals <runtime>\lib\bin.js web --host，如测试 runtime 的孤儿进程）
#   ② MCP server 子进程（github-mcp-server.exe / desktop-touch server-windows.js）。
#   这些孤儿与正式实例共享 DSH_HOME/ports，是「首次启动 60s 超时」的加重元凶
#   （8-23 实测：一个 8-20 起的 tools-analyze/runtime-test web 孤儿拖死多次启动）。
#   按命令行特征清：只清"web --host"的 node 进程 + MCP server，不清其他 node。
$orphanWeb = Get-CimInstance Win32_Process | Where-Object {
  $_.Name -match '^node' -and $_.CommandLine -match 'bin\.js.*\bweb\b' -and $_.CommandLine -match '--host'
}
foreach ($o in $orphanWeb) { try { Stop-Process -Id $o.ProcessId -Force -ErrorAction SilentlyContinue } catch { } }
$orphanMcp = Get-CimInstance Win32_Process | Where-Object {
  ($_.Name -match 'github-mcp-server') -or ($_.CommandLine -match 'desktop-touch-mcp.*server-windows\.js')
}
foreach ($o in $orphanMcp) { try { Stop-Process -Id $o.ProcessId -Force -ErrorAction SilentlyContinue } catch { } }
Start-Sleep -Seconds 6
$deadline = (Get-Date).AddSeconds(30)
while ((Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 1 }
if (Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue) { Log 'WARN: some processes still alive' }
Log 'old processes cleared, launching app'
Start-Process -FilePath $appExe
$okPort = $null
$deadline = (Get-Date).AddSeconds(90)
while ((Get-Date) -lt $deadline) {
  $w = Find-Web
  if ($w) { $p = Test-Healthy $w.ProcessId; if ($p) { $okPort = $p; break } }
  Start-Sleep -Seconds 3
}
if ($okPort) {
  $url = 'http://127.0.0.1:' + $okPort
  Set-Content -Path $logOut -Value ("OK " + $url) -Encoding UTF8
  Log ('HEALTHY: ' + $url)
} else {
  Set-Content -Path $logOut -Value 'FAILED: no healthy web instance within 90s' -Encoding UTF8
  Log 'FAILED: no healthy web instance within 90s'
}
Log 'clean restart done'
