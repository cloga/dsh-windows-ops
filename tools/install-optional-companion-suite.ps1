[CmdletBinding()]
param(
    [ValidateSet('Check', 'Apply', 'Remove')]
    [string]$Action = 'Check',
    [string]$Profile = 'web',
    [string]$ManifestPath = $(Join-Path $PSScriptRoot '..\deployments\windows-copilot.lock.json'),
    [string]$DshHome = $(if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME '.dsh' }),
    [string]$NpmGlobalRoot,
    [Alias('ProviderSourceRoot')]
    [string]$CopilotIntegrationSourceRoot,
    [Alias('ProviderArtifactPath')]
    [string]$CopilotIntegrationArtifactPath,
    [string]$DesktopArtifactPath,
    [string]$BackupRoot = $(Join-Path $env:LOCALAPPDATA 'dsh-windows-ops\deployment-backups'),
    [string]$DesktopExecutablePath,
    [string]$DshCliPath = 'dsh',
    [string[]]$AcknowledgeLiveSessionIds,
    [int]$TimeoutSeconds = 90,
    [switch]$SkipRuntimeChecks,
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Apply) {
    if ($Action -eq 'Remove') {
        throw '-Apply cannot be combined with -Action Remove.'
    }
    $Action = 'Apply'
}
if ($Profile -cne 'web') {
    throw "The reviewed Windows companion suite is locked to Profile 'web'."
}

$installer = Join-Path $PSScriptRoot 'install-windows-copilot.ps1'
$arguments = @{
    Action = if ($Action -eq 'Remove') { 'RemoveCompanionSuite' } else { $Action }
    ManifestPath = $ManifestPath
    DshHome = $DshHome
    BackupRoot = $BackupRoot
    IncludeCompanionSuite = $true
    TimeoutSeconds = $TimeoutSeconds
    SkipRuntimeChecks = [bool]$SkipRuntimeChecks
}
foreach ($entry in @{
    NpmGlobalRoot = $NpmGlobalRoot
    CopilotIntegrationSourceRoot = $CopilotIntegrationSourceRoot
    CopilotIntegrationArtifactPath = $CopilotIntegrationArtifactPath
    DesktopArtifactPath = $DesktopArtifactPath
    DesktopExecutablePath = $DesktopExecutablePath
}.GetEnumerator()) {
    if (-not [string]::IsNullOrWhiteSpace([string]$entry.Value)) {
        $arguments[$entry.Key] = $entry.Value
    }
}
if ($AcknowledgeLiveSessionIds) {
    $arguments.AcknowledgeLiveSessionIds = $AcknowledgeLiveSessionIds
}

& $installer @arguments
