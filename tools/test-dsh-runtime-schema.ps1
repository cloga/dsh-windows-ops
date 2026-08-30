[CmdletBinding()]
param(
    [string]$ManifestPath,
    [string]$BehaviorEvidencePath,
    [string]$AttestedRepository,
    [string]$AttestedSourceCommit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'WindowsCopilotDeployment.psm1') -Force
if (-not $ManifestPath) {
    $ManifestPath = Join-Path $PSScriptRoot '..\deployments\windows-copilot.lock.json'
}
$lock = Read-WindowsCopilotLock -Path $ManifestPath
$arguments = @{
    Contract = $lock.acceptance.runtimeSchema
    BehaviorEvidencePath = $BehaviorEvidencePath
    AttestedRepository = $AttestedRepository
    AttestedSourceCommit = $AttestedSourceCommit
}
Test-DshRuntimeSchemaState @arguments | ConvertTo-Json -Depth 12
