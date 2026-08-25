# dsh-restart-detached.ps1 - restart the Tauri DSH shell outside this process tree.
# =============================================================================
# Kills the Tauri shell (+ its dsh web children) and relaunches it, observing
# health for up to 3 minutes in a detached worker (spawned via WMI), so killing
# the shell cannot kill the script. Log: tools/backups/dsh-restart-launch.log.
#
# Usage: powershell -File dsh-restart-detached.ps1 [-wait]
#   -wait   block this window and print the worker log tail (default: fire-and-forget)
# =============================================================================
param([switch]$wait)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$worker = Join-Path $scriptDir 'dsh-restart-worker.ps1'

if (-not (Test-Path $worker)) { Write-Output 'ERROR: dsh-restart-worker.ps1 missing'; exit 1 }

$cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $worker + '"'
$sh = New-Object -ComObject WScript.Shell
$r = $sh.Run($cmd, 0, $false)
Write-Output ("restart worker spawned (code " + $r + "). Shell restarts and health-checks in the background.")
if ($wait) {
    $log = Join-Path $scriptDir 'backups\dsh-restart-launch.log'
    Start-Sleep -Seconds 200
    if (Test-Path $log) { Get-Content $log -Tail 15 } else { Write-Output 'no worker log yet' }
}
