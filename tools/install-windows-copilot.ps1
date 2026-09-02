[CmdletBinding()]
param(
    [string]$ManifestPath,
    [string]$DshHome = $(if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME '.dsh' }),
    [string]$NpmGlobalRoot,
    [string]$CoreInstallPrefix,
    [string]$HarnessSourceRoot,
    [Alias('ProviderSourceRoot')]
    [string]$CopilotIntegrationSourceRoot,
    [string]$DesktopArtifactPath,
    [string]$GatewayArtifactPath,
    [string]$GatewayInstallRoot = $(Join-Path $env:LOCALAPPDATA 'dsh-windows-ops\bin'),
    [string]$BackupRoot = $(Join-Path $env:LOCALAPPDATA 'dsh-windows-ops\deployment-backups'),
    [string]$ModelCatalogPath,
    [string]$SearchSmokeResponsePath,
    [string]$ComposedConfigPath,
    [string]$DshCliPath,
    [string]$DesktopExecutablePath,
    [string]$GatewayExecutablePath,
    [ValidateSet('Check', 'Apply', 'Verify', 'Rollback')]
    [string]$Action = 'Check',
    [string]$OperationId,
    [switch]$RestartDesktop,
    [int]$TimeoutSeconds = 90,
    [ValidateRange(1, 2147483)]
    [int]$CoreInstallTimeoutSeconds = 900,
    [switch]$SkipRuntimeChecks,
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'WindowsCopilotDeployment.psm1') -Force
if (-not $ManifestPath) {
    $ManifestPath = Join-Path $PSScriptRoot '..\deployments\windows-copilot.lock.json'
}
$lock = Read-WindowsCopilotLock -Path $ManifestPath
if ($Apply) {
    if ($Action -notin @('Check', 'Apply')) {
        throw '-Apply cannot be combined with -Action Verify or Rollback.'
    }
    $Action = 'Apply'
}

if (-not $NpmGlobalRoot) {
    $NpmGlobalRoot = (& npm root --global).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $NpmGlobalRoot) {
        throw 'Could not resolve the global npm package root.'
    }
}

$plan = Get-WindowsCopilotInstallPlan -Lock $lock -DshHome $DshHome `
    -NpmGlobalRoot $NpmGlobalRoot -HarnessSourceRoot $HarnessSourceRoot `
    -CopilotIntegrationSourceRoot $CopilotIntegrationSourceRoot -DesktopArtifactPath $DesktopArtifactPath `
    -GatewayArtifactPath $GatewayArtifactPath -CoreInstallPrefix $CoreInstallPrefix -BackupRoot $BackupRoot

if ($Action -eq 'Rollback') {
    $rollback = Restore-WindowsCopilotForkCore -Lock $lock -BackupRoot $BackupRoot `
        -NpmGlobalRoot $NpmGlobalRoot -OperationId $OperationId
    $restart = if ($RestartDesktop) {
        $desktop = Get-WindowsCopilotDesktopState -Lock $lock -Path $DesktopExecutablePath
        if (-not $desktop.valid) {
            throw 'Rollback completed, but the exact locked Desktop executable is unavailable for restart.'
        }
        Restart-WindowsCopilotDesktop -DesktopExecutablePath ([string]$desktop.path) `
            -TimeoutSeconds $TimeoutSeconds
    } else {
        [pscustomobject]@{ status = 'not-requested' }
    }
    [pscustomobject]@{
        mode = 'rollback'
        rollback = $rollback
        desktopRestart = $restart
    } | ConvertTo-Json -Depth 20
    exit 0
}

if ($Action -eq 'Verify') {
    $verification = Test-WindowsCopilotForkCore -Lock $lock -NpmGlobalRoot $NpmGlobalRoot `
        -CoreInstallPrefix $CoreInstallPrefix -DshCliPath $DshCliPath `
        -DesktopRoot $(if ($DesktopExecutablePath) { Split-Path -Parent $DesktopExecutablePath } else { $null }) `
        -DesktopExecutablePath $DesktopExecutablePath `
        -SkipRuntimeChecks:$SkipRuntimeChecks
    [pscustomobject]@{
        mode = 'verify'
        valid = [bool]$verification.valid
        forkCore = $verification
    } | ConvertTo-Json -Depth 20
    if (-not $verification.valid) { exit 2 }
    exit 0
}

if ($Action -eq 'Check') {
    $installation = Test-WindowsCopilotInstallation -Lock $lock -DshHome $DshHome `
        -NpmGlobalRoot $NpmGlobalRoot -ModelCatalogPath $ModelCatalogPath `
        -ComposedConfigPath $ComposedConfigPath -SearchSmokeResponsePath $SearchSmokeResponsePath `
        -CoreInstallPrefix $CoreInstallPrefix -DshCliPath $DshCliPath `
        -DesktopExecutablePath $DesktopExecutablePath `
        -GatewayExecutablePath $GatewayExecutablePath `
        -SkipRuntimeChecks:$SkipRuntimeChecks
    $forkCore = Test-WindowsCopilotForkCore -Lock $lock -NpmGlobalRoot $NpmGlobalRoot `
        -CoreInstallPrefix $CoreInstallPrefix -DshCliPath $DshCliPath `
        -DesktopRoot $(if ($DesktopExecutablePath) { Split-Path -Parent $DesktopExecutablePath } else { $null }) `
        -DesktopExecutablePath $DesktopExecutablePath `
        -SkipRuntimeChecks:$SkipRuntimeChecks
    $checks = [ordered]@{
        manifest = Test-WindowsCopilotLock -Lock $lock
        desktopArtifact = if ($DesktopArtifactPath) {
            Test-LockedArtifact -Path $DesktopArtifactPath `
                -Sha256 ([string]$lock.components.desktop.artifact.sha256) `
                -ExpectedName ([string]$lock.components.desktop.artifact.name)
        } else { [pscustomobject]@{ status = 'not-supplied'; requiredForApply = $true } }
        legacyGateway = $installation.migration.legacyGateway
        credential = $installation.profile.credential
        providerRoute = $installation.profile.providerRoute
        composedConfig = if ($ComposedConfigPath) {
            $installation.runtime.composedConfig
        } else { [pscustomobject]@{ status = 'not-supplied'; command = @($lock.acceptance.composedConfig.command) } }
        searchSmoke = if ($SearchSmokeResponsePath) {
            Test-WindowsCopilotSearchResponse -Lock $lock -ResponsePath $SearchSmokeResponsePath
        } else { [pscustomobject]@{ status = 'manual-or-injectable'; contract = $lock.acceptance.searchSmoke } }
        forkCore = $forkCore
        installation = $installation
    }
    [pscustomobject]@{ mode = 'check'; plan = $plan; checks = $checks } | ConvertTo-Json -Depth 20
    exit 0
}

foreach ($required in @{
    HarnessSourceRoot = $HarnessSourceRoot
    CopilotIntegrationSourceRoot = $CopilotIntegrationSourceRoot
    DesktopArtifactPath = $DesktopArtifactPath
    CoreInstallPrefix = $CoreInstallPrefix
}.GetEnumerator()) {
    if ([string]::IsNullOrWhiteSpace([string]$required.Value)) {
        throw "-$($required.Key) is required with -Apply."
    }
}

Invoke-WindowsCopilotApply -Lock $lock -DshHome $DshHome -NpmGlobalRoot $NpmGlobalRoot `
    -HarnessSourceRoot $HarnessSourceRoot -CopilotIntegrationSourceRoot $CopilotIntegrationSourceRoot `
    -DesktopArtifactPath $DesktopArtifactPath -GatewayArtifactPath $GatewayArtifactPath `
    -GatewayInstallRoot $GatewayInstallRoot -GatewayExecutablePath $GatewayExecutablePath `
    -CoreInstallPrefix $CoreInstallPrefix `
    -BackupRoot $BackupRoot `
    -DesktopExecutablePath $DesktopExecutablePath -RestartDesktop:$RestartDesktop `
    -TimeoutSeconds $TimeoutSeconds -CoreInstallTimeoutSeconds $CoreInstallTimeoutSeconds |
    ConvertTo-Json -Depth 20
