[CmdletBinding()]
param(
    [ValidateSet('Check', 'Apply', 'Verify', 'Remove')]
    [string]$Action = 'Check',
    [string]$Profile = 'web',
    [string]$ManifestPath = $(Join-Path $PSScriptRoot '..\deployments\windows-copilot.lock.json'),
    [string]$DshHome = $(if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME '.dsh' }),
    [Alias('ProviderArtifactPath')]
    [string]$CopilotIntegrationArtifactPath,
    [string]$BackupRoot = $(Join-Path $env:LOCALAPPDATA 'dsh-windows-ops\deployment-backups'),
    [string]$RuntimeRoot,
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

Import-Module (Join-Path $PSScriptRoot 'WindowsCopilotDeployment.psm1') -Force
$lock = Read-WindowsCopilotLock -Path $ManifestPath

if ($Action -eq 'Remove') {
    Remove-WindowsCopilotCompanionSuite -Lock $lock -DshHome $DshHome `
        -BackupRoot $BackupRoot | ConvertTo-Json -Depth 20
    exit 0
}
if ($Action -eq 'Check') {
    [pscustomobject]@{
        plan = Get-WindowsCopilotCompanionSuitePlan -Lock $lock -DshHome $DshHome `
            -RuntimeRoot $RuntimeRoot
        installation = Test-WindowsCopilotCompanionSuite -Lock $lock -DshHome $DshHome `
            -RuntimeRoot $RuntimeRoot
    } | ConvertTo-Json -Depth 20
    exit 0
}
if ($Action -eq 'Verify') {
    $verification = Test-WindowsCopilotCompanionSuite -Lock $lock -DshHome $DshHome `
        -RuntimeRoot $RuntimeRoot
    $verification | ConvertTo-Json -Depth 20
    if (-not $verification.valid) { exit 2 }
    exit 0
}

Invoke-WindowsCopilotCompanionSuiteApply -Lock $lock -DshHome $DshHome `
    -BackupRoot $BackupRoot `
    -CopilotIntegrationArtifactPath $CopilotIntegrationArtifactPath `
    -RuntimeRoot $RuntimeRoot | ConvertTo-Json -Depth 20
