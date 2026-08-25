[CmdletBinding()]
param(
    [ValidateSet('Preflight', 'SelfCheck', 'Verify', 'Apply', 'Rollback', 'RecoverDesktop')]
    [string]$Action = 'Preflight',
    [string]$Config,
    [string]$PatchManifest,
    [string]$OperationId,
    [string]$StateRoot,
    [switch]$DryRun,
    [int]$TimeoutSeconds = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $Config) { $Config = Join-Path $PSScriptRoot 'dsh-replay.config.example.json' }
if (-not $PatchManifest) { $PatchManifest = Join-Path $PSScriptRoot 'dsh-replay.patches.json' }

Import-Module (Join-Path $PSScriptRoot 'DshWindowsOps.psm1') -Force

$resolvedConfig = Get-Content -LiteralPath $Config -Raw -Encoding UTF8 | ConvertFrom-Json
$resolvedManifest = Get-Content -LiteralPath $PatchManifest -Raw -Encoding UTF8 | ConvertFrom-Json
$stateArgs = @{}
if ($StateRoot) { $stateArgs.StateRoot = $StateRoot }

switch ($Action) {
    'Preflight' {
        [pscustomobject]@{
            components = @(Get-DshComponentInventory -Config $resolvedConfig)
            patches = @($resolvedManifest.patches | ForEach-Object { Test-DshPatch -Patch $_ -Config $resolvedConfig })
        } | ConvertTo-Json -Depth 10
    }
    'SelfCheck' {
        [pscustomobject]@{
            components = @(Get-DshComponentInventory -Config $resolvedConfig)
            services = @(Get-DshServiceChecks -Config $resolvedConfig)
            configuration = Get-DshConfigChecks -Config $resolvedConfig
            modelEndpoints = @(Get-DshEndpointChecks -Config $resolvedConfig)
            patches = @($resolvedManifest.patches | ForEach-Object { Test-DshPatch -Patch $_ -Config $resolvedConfig })
        } | ConvertTo-Json -Depth 12
    }
    'Verify' {
        @($resolvedManifest.patches | ForEach-Object { Test-DshPatch -Patch $_ -Config $resolvedConfig }) |
            ConvertTo-Json -Depth 8
    }
    'Apply' {
        Invoke-DshPatchSet -Config $resolvedConfig -Manifest $resolvedManifest -DryRun:$DryRun @stateArgs |
            ConvertTo-Json -Depth 10
    }
    'Rollback' {
        Restore-DshPatchSet -Config $resolvedConfig -Manifest $resolvedManifest -OperationId $OperationId -DryRun:$DryRun @stateArgs |
            ConvertTo-Json -Depth 10
    }
    'RecoverDesktop' {
        Invoke-DshDesktopRecovery -Config $resolvedConfig -DryRun:$DryRun -TimeoutSeconds $TimeoutSeconds |
            ConvertTo-Json -Depth 10
    }
}
