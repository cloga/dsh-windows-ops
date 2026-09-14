[CmdletBinding()]
param(
    [ValidateSet('Check', 'Prepare', 'Verify', 'Build', 'PackageLocal')][string]$Action = 'Check',
    [string]$BuildRoot = 'C:\tmp\dsh-official-desktop-build\work',
    [string]$Registry = 'https://packagefeedproxy.microsoft.io/npm/',
    [string]$PnpmPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'DshOfficialDesktopBuild.psm1') -Force

try {
    $result = Invoke-DshOfficialDesktopBuild -Action $Action -BuildRoot $BuildRoot -Registry $Registry -PnpmPath $PnpmPath
    $result | ConvertTo-Json -Depth 20
    if ($result.status -eq 'blocked') { exit 2 }
    exit 0
} catch {
    [pscustomobject]@{
        action = $Action.ToLowerInvariant()
        status = 'failed'
        reason = $_.Exception.Message
        installedDesktop = $false
        launchedGui = $false
        modifiedLiveData = $false
    } | ConvertTo-Json -Depth 8
    exit 2
}
