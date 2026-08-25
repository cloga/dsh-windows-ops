# dsh-restart-patched.ps1 - restart with doctor --fix first, then restart shell.
# =============================================================================
# Tauri world: no asar patch anymore. "Patched" now means: run dsh-doctor.mjs
# --fix (reapply worker/adapter patches, rebuild broken links, disable dup
# inserts, quarantine banned plugins) directly before the detached restart.
#
# Usage: powershell -File dsh-restart-patched.ps1 [-wait]
# Env: DSH_NODE_BIN (node>=22), DSH_TOOLS_DIR (default: ~/.dsh/tools)
# =============================================================================
param([switch]$wait)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$toolsDir = if ($env:DSH_TOOLS_DIR) { $env:DSH_TOOLS_DIR } else { 'C:\Users\sephen\.dsh\tools' }
$nodeExe  = if ($env:DSH_NODE_BIN) { $env:DSH_NODE_BIN } else { 'C:\Users\sephen\.workbuddy\binaries\node\versions\22.22.2\node.exe' }
$doctor   = Join-Path $toolsDir 'dsh-doctor.mjs'
$logFile  = Join-Path $toolsDir 'dsh-restart-patched.log'
function Log([string]$m) { Add-Content -Path $logFile -Value ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -Encoding UTF8 }

if (-not (Test-Path $doctor)) { Log 'ERROR: dsh-doctor.mjs missing'; Write-Output 'ERROR: dsh-doctor.mjs missing'; exit 1 }
Log ('doctor --fix...')
$d = & $nodeExe $doctor --fix
Log ("doctor exit=" + $LASTEXITCODE)
$tail = @($d | Select-Object -Last 8)
foreach ($t in $tail) { Log ('  ' + $t) }

Log 'calling detached restart...'
$detached = Join-Path $toolsDir 'dsh-restart-detached.ps1'
if (Test-Path $detached) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $detached
    Write-Output 'restart requested (worker running detached).'
    if ($wait) { Start-Sleep -Seconds 200; $wl = Join-Path $toolsDir 'backups\dsh-restart-launch.log'; if (Test-Path $wl) { Get-Content $wl -Tail 15 } }
} else {
    Log 'ERROR: dsh-restart-detached.ps1 missing'
    Write-Output 'ERROR: dsh-restart-detached.ps1 missing'
}
