# dsh-rescue.ps1 - start B (last known-good snapshot) with the Tauri shell
# =============================================================================
# Use when A (the live DSH) is dead or unbootable:
#   1. close/kill the main DSH completely (task manager: deepseek-harness-desktop)
#   2. run this script (or: powershell -File dsh-rescue.ps1)
#   3. the Tauri shell opens with DSH_HOME=B - same sessions/memory/credentials
#      (data dirs are junctions to the live home), last known-good config
#      snapshot. Fix A from inside B, then close B and reopen the main app.
#
# Rule: B must never run at the same time as A (shared data dirs + im-gateway
# instance lock).
# =============================================================================
param([switch]$force)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$src = 'C:\Users\sephen\.dsh'
$dst = 'C:\Users\sephen\.dsh-backup'
$shellExe = 'C:\Users\sephen\AppData\Local\Deepseek Harness Desktop\deepseek-harness-desktop.exe'
$toolsDir = Join-Path $src 'tools'
$logPath = Join-Path $toolsDir 'dsh-rescue.log'
$urlFile = Join-Path $dst 'RESCUE-URL.txt'

function Log([string]$msg) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Add-Content -Path $logPath -Value $line -Encoding UTF8
}

# Tauri-shell web process: node.exe running the vendored dsh bin.js
function Find-WebInstance {
    return (Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq 'node.exe' -and
        $_.CommandLine -match 'dependencies..dsh' -and
        $_.CommandLine -match 'bin\.js' -and
        $_.CommandLine -match 'web --host'
    } | Select-Object -First 1)
}

function Test-Healthy([int]$procId) {
    try { Add-Type -AssemblyName System.Net.Http -ErrorAction Stop } catch { }
    $port = Get-NetTCPConnection -OwningProcess $procId -State Listen -ErrorAction SilentlyContinue |
            Where-Object { $_.LocalAddress -eq '127.0.0.1' } |
            Select-Object -First 1 -ExpandProperty LocalPort
    if (-not $port) { return $false }
    try {
        $client = New-Object System.Net.Http.HttpClient
        $client.Timeout = [TimeSpan]::FromSeconds(6)
        $resp = $client.GetAsync('http://127.0.0.1:' + $port + '/').Result
        $resp.Dispose()
        $client.Dispose()
        return $true
    } catch {
        if ($null -ne $client) { try { $client.Dispose() } catch { } }
        return $false
    }
}

if (-not (Test-Path (Join-Path $dst 'profiles'))) {
    Write-Output ('ERROR: B home not ready at ' + $dst)
    Write-Output 'Run dsh-backup.ps1 -promote first (while A is healthy).'
    exit 1
}
if (-not (Test-Path $shellExe)) {
    Write-Output 'ERROR: Tauri shell not found at ' + $shellExe
    exit 1
}

$before = @(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -eq 'node.exe' -and $_.CommandLine -match 'bin\.js' -and $_.CommandLine -match 'web --host'
} | Select-Object -ExpandProperty ProcessId)

if ($before.Count -gt 0 -and -not $force) {
    Write-Output 'A (the main DSH) is still running - rescue cannot start while it is open.'
    Write-Output 'Close the main DSH app completely (taskbar tray + task manager), then run this again.'
    exit 1
}
if ($before.Count -gt 0 -and $force) {
    Write-Output 'WARNING: A is running; forcing launch (im-gateway instance lock may block it).'
}

$env:DSH_HOME = $dst   # inherited by the Tauri shell and its dsh child processes
$p = Start-Process -FilePath $shellExe -PassThru
Log ("rescue launch shell pid=" + $p.Id + " home=" + $dst)
Write-Output ('launched shell pid ' + $p.Id + ' - waiting for a healthy web instance (B home)...')

$deadline = (Get-Date).AddSeconds(90)
$ok = $false
while ((Get-Date) -lt $deadline) {
    $w = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq 'node.exe' -and
        $_.CommandLine -match 'dependencies..dsh' -and
        $_.CommandLine -match 'bin\.js' -and
        $_.CommandLine -match 'web --host' -and
        $_.ProcessId -notin $before
    } | Select-Object -First 1
    if ($w -and (Test-Healthy $w.ProcessId)) {
        $port = Get-NetTCPConnection -OwningProcess $w.ProcessId -State Listen -ErrorAction SilentlyContinue |
                Where-Object { $_.LocalAddress -eq '127.0.0.1' } |
                Select-Object -First 1 -ExpandProperty LocalPort
        $url = 'http://127.0.0.1:' + $port
        Set-Content -Path $urlFile -Value $url -Encoding UTF8
        Log ("rescue instance up: " + $url)
        Write-Output ('RESCUE INSTANCE IS UP: ' + $url)
        Start-Process $url
        $ok = $true
        break
    }
    Start-Sleep -Seconds 3
}
if (-not $ok) {
    Write-Output 'FAILED: no healthy web instance appeared within 90s.'
    Write-Output 'Possible causes: single-instance lock (A still running), B config broken, core not installed for the shell.'
    Log 'rescue failed: no healthy instance (see shell log: AppData/Roaming/io.github.hairyf.deepseek-harness-desktop/logs)'
    exit 1
}
