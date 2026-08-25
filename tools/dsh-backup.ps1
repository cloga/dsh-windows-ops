# =============================================================================
# dsh-backup.ps1 - A/B rotation for DeepSeek Harness
#
# A (active) = current live home : C:\Users\sephen\.dsh
# B (backup) = last known-good   : C:\Users\sephen\.dsh-backup
#
# B holds a SNAPSHOT of A's config+plugins layer (robocopy /MIR of profiles/
# plus the root config files) and JUNCTIONS to A's live data dirs
# (sessions/memories/storages), so a rescue instance started from B home sees
# every session and all memory - no context re-introduction needed.
#
# Promotion rule: A is only snapshotted while it is healthy right now, so a
# broken state is never promoted into B. Each promote REPLACES the old B.
#
# Modes:
#   dsh-backup.ps1 -init      create B home skeleton + data junctions (once)
#   dsh-backup.ps1 -promote   snapshot current healthy A state into B
#   dsh-backup.ps1 -status    report A/B health and last promote time
#
# Automatic promotion: scheduled task "DSH Backup Promote" runs daily.
# =============================================================================
param([switch]$init, [switch]$promote, [switch]$status)

# 2026-08-24 加固：未定义变量立即报错（防静默空值类 bug，param 之后注入）。
Set-StrictMode -Version Latest

$src = 'C:\Users\sephen\.dsh'
$dst = 'C:\Users\sephen\.dsh-backup'
$logPath = Join-Path $src 'tools\dsh-backup.log'
$marker = Join-Path $dst 'PROMOTED.txt'
$dataDirs = @('sessions', 'memories', 'storages')
$rootFiles = @('cordis.patch.yml', 'settings.yaml', 'AGENTS.md', '.env', '.credentials.yaml', '.anonymous-user-id')
# profiles/node_modules is a boot-managed SYMLINK FARM pointing into the shared
# runtime; it must not be materialized by robocopy (boot refuses real dirs).
$farmSrc = Join-Path $src 'profiles\node_modules'
$farmDst = Join-Path $dst 'profiles\node_modules'
# Plugin layers (web/headless node_modules) are JUNCTIONS to the live home too:
# after a cross-runtime upgrade the plugin code must match the CURRENT runtime
# (an old snapshot layout crashed B boot - 2026-08-22). Config stays a snapshot;
# only plugin code is shared live.
$pluginLayers = @('web', 'headless')

function Log([string]$msg) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Add-Content -Path $logPath -Value $line -Encoding UTF8
}

function Find-WebInstance {
    # Tauri-shell web process: node.exe running the vendored dsh bin.js
    return (Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq 'node.exe' -and
        $_.CommandLine -match 'dependencies..dsh' -and
        $_.CommandLine -match 'bin\.js' -and
        $_.CommandLine -match 'web --host'
    } | Select-Object -First 1)
}

function Test-Healthy([int]$procId) {
    # Windows PowerShell 5.1 does not auto-load System.Net.Http (HttpClient via
    # New-Object fails with "Cannot find type") - load it explicitly; no-op on
    # PowerShell 7 where the assembly is already available.
    try { Add-Type -AssemblyName System.Net.Http -ErrorAction Stop } catch {
        Log ('WARN: System.Net.Http not loadable: ' + $_.Exception.Message)
    }
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

function Ensure-FarmJunction {
    # B's module fallback layer = junction to A's symlink farm (same runtime).
    if (Test-Path $farmSrc) {
        $f = Get-Item $farmDst -Force -ErrorAction SilentlyContinue
        if (-not $f) {
            New-Item -ItemType Junction -Path $farmDst -Target $farmSrc | Out-Null
            Log ("farm junction created: " + $farmDst + " -> " + $farmSrc)
        } elseif ($f.LinkType -ne 'Junction') {
            # materialized copy from an older promote - replace with junction
            Remove-Item $farmDst -Recurse -Force
            New-Item -ItemType Junction -Path $farmDst -Target $farmSrc | Out-Null
            Log ("farm junction recreated (was a real dir): " + $farmDst)
        }
    } else {
        Log ("WARN: farm source missing: " + $farmSrc)
    }
}

function Ensure-PluginLayers {
    # Plugin code layer must be the CURRENT runtime's code (junction to A live);
    # a copied snapshot of an older runtime's node_modules crashes B boot.
    foreach ($layer in $pluginLayers) {
        $dstL = Join-Path $dst ("profiles\" + $layer + "\node_modules")
        $srcL = Join-Path $src ("profiles\" + $layer + "\node_modules")
        if (-not (Test-Path $srcL)) { continue }
        $f = Get-Item $dstL -Force -ErrorAction SilentlyContinue
        if (-not $f) {
            New-Item -ItemType Junction -Path $dstL -Target $srcL | Out-Null
            Log ("plugin layer junction created: " + $dstL + " -> " + $srcL)
        } elseif ($f.LinkType -ne 'Junction') {
            Remove-Item $dstL -Recurse -Force
            New-Item -ItemType Junction -Path $dstL -Target $srcL | Out-Null
            Log ("plugin layer junction recreated (was a real dir): " + $dstL)
        }
    }
}

function Invoke-Init {
    if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }
    foreach ($d in $dataDirs) {
        $link = Join-Path $dst $d
        $target = Join-Path $src $d
        if (-not (Test-Path $link)) {
            if (Test-Path $target) {
                New-Item -ItemType Junction -Path $link -Target $target | Out-Null
                Log ("junction created: " + $link + " -> " + $target)
            } else {
                Log ("WARN: data target missing, skipped: " + $target)
            }
        }
    }
    foreach ($f in $rootFiles) {
        $sf = Join-Path $src $f
        if (Test-Path $sf) { Copy-Item $sf (Join-Path $dst $f) -Force }
    }
    New-Item -ItemType Directory -Path (Join-Path $dst 'profiles') -Force | Out-Null
    Ensure-FarmJunction
    Ensure-PluginLayers
    Log 'init done'
}

function Invoke-Promote {
    $web = Find-WebInstance
    if (-not $web) {
        Write-Output 'ABORT: A is not running - a broken/absent state must not become B'
        Log 'promote aborted: A not running'
        return
    }
    if (-not (Test-Healthy $web.ProcessId)) {
        Write-Output 'ABORT: A is running but unhealthy (HTTP check failed)'
        Log 'promote aborted: A unhealthy'
        return
    }
    Invoke-Init
    Write-Output 'A is healthy - snapshotting config into B (robocopy /MIR, plugin layers shared)...'
    Log 'promote: A healthy, snapshotting profiles (config only)'
    # /SL keeps symlinks as links; /XD excludes the boot-managed module farm AND
    # the shared plugin layers (web/headless node_modules are junctions to A)
    $xIncludes = @($farmSrc) + @($pluginLayers | ForEach-Object { Join-Path $src ("profiles\" + $_ + "\node_modules") })
    & robocopy (Join-Path $src 'profiles') (Join-Path $dst 'profiles') /MIR /SL /XD $xIncludes /NFL /NDL /NJH /NJS /NP | Out-Null
    $rc = $LASTEXITCODE
    if ($rc -ge 8) {
        Write-Output ("ABORT: robocopy failed (code " + $rc + ")")
        Log ("promote aborted: robocopy code " + $rc)
        return
    }
    Ensure-FarmJunction
    Ensure-PluginLayers
    foreach ($f in $rootFiles) {
        $sf = Join-Path $src $f
        if (Test-Path $sf) { Copy-Item $sf (Join-Path $dst $f) -Force }
    }
    # static plugin manifest into B (name/version/source) - the "reconstruct"
    # ammunition for plugin-layer incidents that live junctions cannot cover
    $node22 = 'C:\Users\sephen\.workbuddy\binaries\node\versions\22.22.2\node.exe'
    $manifest = & $node22 (Join-Path $src 'tools\dsh-doctor.mjs') --list-plugins --json 2>$null
    if ($LASTEXITCODE -eq 0 -and $manifest) {
        $manifestPath = Join-Path $dst 'plugins-manifest.json'
        $manifest | Out-File -FilePath $manifestPath -Encoding UTF8
        Log ("plugin manifest saved: " + $manifestPath)
    } else {
        Log 'WARN: plugin manifest generation failed (doctor not runnable?)'
    }
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Set-Content -Path $marker -Value ("last promote: " + $stamp) -Encoding UTF8
    Write-Output ("PROMOTED at " + $stamp + " (robocopy code " + $rc + ")")
    Log ("promote done: " + $stamp)
}

function Invoke-Status {
    Write-Output '=== A (active home) ==='
    $web = Find-WebInstance
    if ($web) {
        $port = Get-NetTCPConnection -OwningProcess $web.ProcessId -State Listen -ErrorAction SilentlyContinue |
                Where-Object { $_.LocalAddress -eq '127.0.0.1' } |
                Select-Object -First 1 -ExpandProperty LocalPort
        $ok = Test-Healthy $web.ProcessId
        Write-Output ("web pid=" + $web.ProcessId + " port=" + $port + " http=" + $ok)
    } else {
        Write-Output 'not running'
    }
    Write-Output '=== B (backup home) ==='
    if (-not (Test-Path $dst)) { Write-Output 'B home not created yet - run dsh-backup.ps1 -promote'; return }
    if (Test-Path $marker) { Write-Output ((Get-Content $marker -Raw).Trim()) }
    else { Write-Output 'never promoted' }
    $nmdir = Join-Path $dst 'profiles\web\node_modules'
    if (Test-Path $nmdir) {
        $n = (Get-ChildItem $nmdir -Directory -ErrorAction SilentlyContinue | Measure-Object).Count
        Write-Output ("profiles present (plugin dirs: " + $n + ")")
    } else { Write-Output 'profiles MISSING' }
    foreach ($d in $dataDirs) {
        $link = Join-Path $dst $d
        if (Test-Path $link) {
            $item = Get-Item $link
            if ($item.LinkType -eq 'Junction') { Write-Output ("data " + $d + " : junction") }
            else { Write-Output ("data " + $d + " : dir") }
        } else { Write-Output ("data " + $d + " : MISSING") }
    }
}

if ($init) { Invoke-Init; Write-Output 'init done' }
elseif ($promote) { Invoke-Promote }
elseif ($status) { Invoke-Status }
else { Write-Output 'usage: dsh-backup.ps1 -init | -promote | -status' }
