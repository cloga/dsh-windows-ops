# dsh-restart-detached.ps1 - clean app restart, run OUTSIDE the app process
# tree (scheduled task) so killing the app cannot kill this script.
# Steps: kill all DeepSeek Harness -> wait -> start desktop shell -> wait for
# the web instance to come up healthy. Result written to dsh-auto-restart.out
# and logged to dsh-auto-restart.log.
# Env:
#   DSH_APP_EXE   - absolute path to DeepSeek Harness.exe (REQUIRED)
#   DSH_TOOLS_DIR - result/log dir (default: %TEMP%)
$ErrorActionPreference = 'SilentlyContinue'
if (-not $env:DSH_APP_EXE) { Write-Output 'ERR: DSH_APP_EXE not set'; exit 2 }
$appExe   = $env:DSH_APP_EXE
$toolsDir = if ($env:DSH_TOOLS_DIR) { $env:DSH_TOOLS_DIR } else { $env:TEMP }
$logOut   = Join-Path $toolsDir 'dsh-auto-restart.out'
$logFile  = Join-Path $toolsDir 'dsh-auto-restart.log'
function Log([string]$m) { Add-Content -Path $logFile -Value ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -Encoding UTF8; Write-Output $m }
function Find-Web { return (Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'DeepSeek Harness.exe' -and $_.CommandLine -match 'web --host' } | Select-Object -First 1) }
function Test-Healthy([int]$pid) {
  try { Add-Type -AssemblyName System.Net.Http -ErrorAction Stop } catch { }
  $port = Get-NetTCPConnection -OwningProcess $pid -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalAddress -eq '127.0.0.1' } | Select-Object -First 1 -ExpandProperty LocalPort
  if (-not $port) { return $null }
  try { $c = New-Object System.Net.Http.HttpClient; $c.Timeout = [TimeSpan]::FromSeconds(6); $r = $c.GetAsync('http://127.0.0.1:' + $port + '/').Result; $r.Dispose(); $c.Dispose(); return $port } catch { try { $c.Dispose() } catch { }; return $null }
}

Log 'clean restart start'
taskkill /IM 'DeepSeek Harness.exe' /T /F 2>&1 | Out-Null
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
