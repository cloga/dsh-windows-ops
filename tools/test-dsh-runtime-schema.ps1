[CmdletBinding()]
param(
    [string]$ManifestPath,
    [string]$RuntimeRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'WindowsCopilotDeployment.psm1') -Force
if (-not $ManifestPath) {
    $ManifestPath = Join-Path $PSScriptRoot '..\deployments\windows-copilot.lock.json'
}
$lock = Read-WindowsCopilotLock -Path $ManifestPath
$arguments = @{ Contract = $lock.acceptance.runtimeSchema }
if ($RuntimeRoot) {
    $arguments.RequiredPackageRoot = Join-Path $RuntimeRoot 'node_modules\@deepseek-ai\dsh'
}
Test-DshRuntimeSchemaState @arguments | ConvertTo-Json -Depth 12
