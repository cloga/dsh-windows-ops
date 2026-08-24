# check-session-duplicates.ps1 - scan ~/.dsh/sessions for DUPLICATE session ids across project dirs.
# Why: DSH refuses to boot if the SAME session id exists under more than one project
#      directory ("duplicate JSONL session id ... appears in multiple project
#      directories") - 2026-08-24 incident: a stray 160-byte shell duplicated a real
#      628KB session and kept the app from starting. Run this BEFORE any session
#      move/delete operation, and before launching the app.
# Usage: powershell.exe -File check-session-duplicates.ps1 [-Home C:\Users\x\.dsh]
#        [-Quarantine <dir>]   # if set and duplicates found: move extras into it
# Exit: 0 = clean, 1 = duplicates found (and quarantined if -Quarantine given)
param(
  [string]$dshHome = '',
  [string]$Quarantine = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

if (-not $dshHome) { $dshHome = Join-Path $env:USERPROFILE '.dsh' }
$sessionsRoot = Join-Path $dshHome 'sessions'
if (-not (Test-Path $sessionsRoot)) { Write-Output ('sessions root missing: ' + $sessionsRoot); exit 0 }

# Map: sessionId -> @(projectDir names)
$byId = @{}
Get-ChildItem -Path $sessionsRoot -Recurse -Directory -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match '^session-' } |
  ForEach-Object {
    $id = $_.Name
    $proj = $_.Parent.Name
    if ($byId.ContainsKey($id)) {
      if ($byId[$id] -notcontains $proj) { $byId[$id] += $proj }
    } else {
      $byId[$id] = @($proj)
    }
  }

$dups = $byId.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 }
$total = ($byId.GetEnumerator() | Measure-Object).Count
Write-Output ("scanned " + $total + " session dirs at " + $sessionsRoot)

if (-not $dups) {
  Write-Output 'OK: no duplicate session ids.'
  exit 0
}

Write-Output ("DUPLICATES FOUND: " + $dups.Count)
foreach ($d in $dups) {
  Write-Output ('  ' + $d.Key + ' -> ' + ($d.Value -join ', '))
}

if ($Quarantine) {
  $qRoot = $Quarantine
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $moved = 0
  foreach ($d in $dups) {
    # keep the FIRST project dir's copy; move the rest
    $keep = $d.Value[0]
    for ($i = 1; $i -lt $d.Value.Count; $i++) {
      $proj = $d.Value[$i]
      $srcDir = Join-Path (Join-Path $sessionsRoot $proj) $d.Key
      if (Test-Path $srcDir) {
        $destDir = Join-Path $qRoot ("$stamp-" + $d.Key)
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        Copy-Item $srcDir -Destination $destDir -Recurse -Force
        Remove-Item $srcDir -Recurse -Force
        $moved++
        Write-Output ('  moved extra copy: ' + $proj + '\' + $d.Key + ' -> ' + $destDir)
      }
    }
  }
  Write-Output ('quarantined ' + $moved + ' extra copies to ' + $qRoot)
} else {
  Write-Output 'use -Quarantine <dir> to move extra copies safely (keep first dir).'
}
exit 1
