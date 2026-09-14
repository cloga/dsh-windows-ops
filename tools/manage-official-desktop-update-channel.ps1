[CmdletBinding()]
param(
    [ValidateSet('Check','Package','Stage','Install','Complete')][string]$Action='Check',
    [ValidateRange(1,2147483647)][int]$Sequence=1,
    [string]$FeedBaseUrl,
    [string]$BundleRoot,
    [string]$ManifestUrl,
    [string]$StageRoot,
    [string]$AcknowledgeManifestSha256,
    [string]$BuildRoot='C:\tmp\dsh-official-desktop-build\work',
    [string]$Registry='https://registry.npmjs.org/',
    [string]$PnpmPath,
    [string]$InstallRoot=(Join-Path $env:LOCALAPPDATA 'Programs\DSH Local Build'),
    [string]$DataRoot=(Join-Path $env:LOCALAPPDATA 'DSH Local Build'),
    [string]$SharedHome,
    [switch]$UseIsolatedHome
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DshOfficialDesktopUpdateChannel.psm1') -Force

try {
    $result = switch ($Action) {
        'Package' {
            if ([string]::IsNullOrWhiteSpace($FeedBaseUrl)) { throw 'feed-base-url-required' }
            New-DshOfficialDesktopUpdateBundle -Sequence $Sequence -FeedBaseUrl $FeedBaseUrl -BuildRoot $BuildRoot -Registry $Registry -PnpmPath $PnpmPath
        }
        'Check' {
            if ([string]::IsNullOrWhiteSpace($BundleRoot) -eq [string]::IsNullOrWhiteSpace($ManifestUrl)) { throw 'exactly-one-update-source-required' }
            if ($ManifestUrl) {
                Get-DshOfficialDesktopRemoteUpdateChannelCheck -ManifestUrl $ManifestUrl -DataRoot $DataRoot
            } else {
                Get-DshOfficialDesktopUpdateChannelCheck -BundleRoot $BundleRoot -DataRoot $DataRoot
            }
        }
        'Stage' {
            if ([string]::IsNullOrWhiteSpace($BundleRoot)) { throw 'bundle-root-required' }
            if ([string]::IsNullOrWhiteSpace($AcknowledgeManifestSha256)) { throw 'manifest-acknowledgment-required' }
            Save-DshOfficialDesktopStagedUpdate -BundleRoot $BundleRoot -DataRoot $DataRoot -AcknowledgeManifestSha256 $AcknowledgeManifestSha256
        }
        'Install' {
            if ([string]::IsNullOrWhiteSpace($AcknowledgeManifestSha256)) { throw 'manifest-acknowledgment-required' }
            Invoke-DshOfficialDesktopUpdateInstall -BundleRoot $BundleRoot -ManifestUrl $ManifestUrl -DataRoot $DataRoot -AcknowledgeManifestSha256 $AcknowledgeManifestSha256 -BuildRoot $BuildRoot -InstallRoot $InstallRoot -SharedHome $SharedHome -UseIsolatedHome:$UseIsolatedHome -PnpmPath $PnpmPath
        }
        'Complete' {
            if ([string]::IsNullOrWhiteSpace($StageRoot)) { throw 'stage-root-required' }
            if ([string]::IsNullOrWhiteSpace($AcknowledgeManifestSha256)) { throw 'manifest-acknowledgment-required' }
            Complete-DshOfficialDesktopManualUpdate -StageRoot $StageRoot -AcknowledgeManifestSha256 $AcknowledgeManifestSha256 -BuildRoot $BuildRoot -InstallRoot $InstallRoot -DataRoot $DataRoot -SharedHome $SharedHome -UseIsolatedHome:$UseIsolatedHome -PnpmPath $PnpmPath
        }
    }
    $result | ConvertTo-Json -Depth 40
    if ($result.status -eq 'blocked') { exit 2 }
} catch {
    [pscustomobject]@{schemaVersion=1;action=$Action.ToLowerInvariant();status='failed';reason=$_.Exception.Message;installerRun=$false;nativeUpdaterEnabled=$false} | ConvertTo-Json -Depth 8
    exit 2
}
