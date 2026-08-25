# dsh-restart-worker.ps1 - actual restart work, run detached (WMI).
# =============================================================================
# Kills the Tauri shell and any dsh web child (node bin.js), prunes orphan
# MCP servers (github-mcp-server / desktop-touch server-windows.js) that hold
# DSH_HOME/ports, relaunches the shell, waits for a healthy web instance.
# Log: tools/backups/dsh-restart-launch.log (callers tail this).
# =============================================================================
Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$shellExe = 'C:\Users\sephen\AppData\Local\Deepseek Harness Desktop\deepseek-harness-desktop.exe'
$log = 'C:\Users\sephen\.dsh\tools\backups\dsh-restart-launch.log'
New-Item -ItemType Directory -Path (Split-Path $log) -Force | Out-Null

function Log([string]$m) { Add-Content -Path $log -Value ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -Encoding UTF8 }

function Find-Web { return (Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'node.exe' -and $_.CommandLine -match 'dependencies..dsh' -and $_.CommandLine -match 'bin\.js' -and $_.CommandLine -match 'web --host' } | Select-Object -First 1) }
function Test-Healthy([int]$procId) {
  try { Add-Type -AssemblyName System.Net.Http -ErrorAction Stop } catch { }
  $port = Get-NetTCPConnection -OwningProcess $procId -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalAddress -eq '127.0.0.1' } | Select-Object -First 1 -ExpandProperty LocalPort
  if (-not $port) { return $null }
  try { $c = New-Object System.Net.Http.HttpClient; $c.Timeout = [TimeSpan]::FromSeconds(6); $r = $c.GetAsync('http://127.0.0.1:' + $port + '/').Result; $r.Dispose(); $c.Dispose(); return $port } catch { if ($null -ne $c) { try { $c.Dispose() } catch { } }; return $null }
}

Log 'restart start'
Get-Process -Name 'deepseek-harness-desktop' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
# orphan dsh web children (node bin.js web --host) and MCP servers
$orphanWeb = Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'node.exe' -and $_.CommandLine -match 'bin\.js.*\bweb\b' -and $_.CommandLine -match '--host' }
foreach ($o in $orphanWeb) { Log ('pruning orphan web pid ' + $o.ProcessId); try { Stop-Process -Id $o.ProcessId -Force -ErrorAction SilentlyContinue } catch { } }
$orphanMcp = Get-CimInstance Win32_Process | Where-Object { ($_.Name -match 'github-mcp-server') -or ($_.CommandLine -match 'desktop-touch-mcp.*server-windows\.js') }
foreach ($o in $orphanMcp) { Log ('pruning orphan mcp pid ' + $o.ProcessId); try { Stop-Process -Id $o.ProcessId -Force -ErrorAction SilentlyContinue } catch { } }
Start-Sleep -Seconds 6
Log 'old processes cleared, launching Tauri shell'
Start-Process -FilePath $shellExe
$okPort = $null
$deadline = (Get-Date).AddSeconds(120)
while ((Get-Date) -lt $deadline) {
  $w = Find-Web
  if ($w) { $p = Test-Healthy $w.ProcessId; if ($p) { $okPort = $p; break } }
  Start-Sleep -Seconds 4
}
if ($okPort) { Log ('HEALTHY: http://127.0.0.1:' + $okPort) } else { Log 'FAILED: no healthy web instance within 120s' }
Log 'restart done'
