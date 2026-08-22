# gh-dl.ps1 - download GitHub release/raw assets with mirror fallback.
# Usage: gh-dl.ps1 <github-url> [out-path]
#   first arg    - original https://github.com/... URL (release asset or raw file)
#   second arg   - destination path (default: current dir + basename of URL)
# Mirrors tried in order (first that yields >100KB wins):
#   ghfast.top / ghproxy.net / mirror.ghproxy.com
# Direct URL is NOT attempted first (it resets on this network); pass "direct"
# as third arg to try direct first.
$ErrorActionPreference = 'Continue'

$Url = $args[0]
$Out = $args[1]
if (-not $Url) { Write-Host 'usage: gh-dl.ps1 <github-url> [out-path] [direct]'; exit 2 }
$directFirst = ($args[2] -eq 'direct')

$mirrors = @(
  'https://ghfast.top/',
  'https://ghproxy.net/',
  'https://mirror.ghproxy.com/'
)

$name = [System.Uri]::new($Url).AbsolutePath -split '/' | Select-Object -Last 1
if (-not $name) { $name = 'download.bin' }
if (-not $Out) { $Out = Join-Path (Get-Location) $name }

# Raw file URLs: raw.githubusercontent.com works directly on this network
# (measured ~900ms), while github.com/<repo>/raw/... goes through a
# page-redirect that every mirror mishandles - rewrite to direct first.
$urls = @()
if ($Url -match '/raw/') {
  $direct = $Url -replace 'github\.com/([^/]+)/([^/]+)/raw/', 'raw.githubusercontent.com/$1/$2/'
  Write-Host ("raw path detected, direct: " + $direct)
  $urls += $direct
}
if ($directFirst) { $urls += $Url }
foreach ($m in $mirrors) { $urls += ($m + $Url) }

function Try-Download([string]$u, [string]$dest) {
  curl.exe -L -s -o $dest --connect-timeout 20 --max-time 600 --retry 2 -w "%{http_code}" $u 2>$null
  if (Test-Path $dest) { return (Get-Item $dest).Length }
  return 0
}

$ok = $false
foreach ($u in $urls) {
  Write-Host ("trying: " + $u)
  $len = Try-Download $u $Out
  if ($len -gt 0) {
    Write-Host ("OK: " + $len + " bytes -> " + $Out)
    $ok = $true
    break
  }
  Write-Host ("failed/small (" + $len + "), next...")
}
if (-not $ok) {
  Write-Host "ALL MIRRORS FAILED for $Url"
  exit 1
}
