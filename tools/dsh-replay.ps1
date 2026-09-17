[CmdletBinding()]
param(
    [ValidateSet('Preflight', 'Inventory', 'SelfCheck', 'Verify', 'Apply', 'Rollback', 'RecoverDesktop')]
    [string]$Action = 'Preflight',
    [string]$Config,
    [string]$LockPath,
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

Import-Module (Join-Path $PSScriptRoot 'DshWindowsOps.psm1')

$resolvedConfig = Get-Content -LiteralPath $Config -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $LockPath) { $LockPath = Join-Path $PSScriptRoot '..\deployments\windows-copilot.lock.json' }
Import-Module (Join-Path $PSScriptRoot 'WindowsCopilotDeployment.psm1')
$lock = Read-WindowsCopilotLock -Path $LockPath
$resolvedConfig = Resolve-DshLockedReplayConfig -Config $resolvedConfig -Lock $lock
if (($Action -eq 'Apply' -and -not $DryRun) -or $Action -in @('Rollback', 'RecoverDesktop')) {
    # Native actions must reach the module's delegation refusal even when its audit
    # is not ready; DryRun reports immutable targets without reading backup state.
    if ($resolvedConfig.deployment.provisioningMode -cne 'desktopNativeVerifiedRelease' -and
        -not $resolvedConfig.deployment.valid) { throw 'replay-deployment-does-not-match-lock' }
}
$resolvedManifest = Get-Content -LiteralPath $PatchManifest -Raw -Encoding UTF8 | ConvertFrom-Json
$stateArgs = @{}
if ($StateRoot) { $stateArgs.StateRoot = $StateRoot }

switch ($Action) {
    'Preflight' {
        [pscustomobject]@{
            deployment = $resolvedConfig.deployment
            components = @(Get-DshComponentInventory -Config $resolvedConfig)
            patches = @($resolvedManifest.patches | ForEach-Object { Test-DshPatch -Patch $_ -Config $resolvedConfig })
        } | ConvertTo-Json -Depth 10
    }
    'Inventory' {
        [pscustomobject]@{
            deployment = $resolvedConfig.deployment
            components = @(Get-DshComponentInventory -Config $resolvedConfig)
        } | ConvertTo-Json -Depth 8
    }
    'SelfCheck' {
        [pscustomobject]@{
            deployment = $resolvedConfig.deployment
            diagnosticScope = 'service-config-endpoint-checks-are-web-headless-not-native-host'
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
        $result = Invoke-DshPatchSet -Config $resolvedConfig -Manifest $resolvedManifest -DryRun:$DryRun @stateArgs
        $result | Add-Member -NotePropertyName deployment -NotePropertyValue $resolvedConfig.deployment
        $result | ConvertTo-Json -Depth 10
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
