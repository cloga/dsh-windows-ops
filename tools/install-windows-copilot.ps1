[CmdletBinding()]
param(
    [string]$ManifestPath,
    [string]$DshHome = $(if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME '.dsh' }),
    [string]$NpmGlobalRoot,
    [Alias('ProviderSourceRoot')]
    [string]$CopilotIntegrationSourceRoot,
    [Alias('ProviderArtifactPath')]
    [string]$CopilotIntegrationArtifactPath,
    [string]$DesktopArtifactPath,
    [string]$GatewayArtifactPath,
    [string]$GatewayInstallRoot = $(Join-Path $env:LOCALAPPDATA 'dsh-windows-ops\bin'),
    [string]$BackupRoot = $(Join-Path $env:LOCALAPPDATA 'dsh-windows-ops\deployment-backups'),
    [string]$ModelCatalogPath,
    [string]$SearchSmokeResponsePath,
    [string]$ComposedConfigPath,
    [string]$DesktopExecutablePath,
    [string]$GatewayExecutablePath,
    [ValidateSet('Check', 'Apply', 'Verify', 'Rollback', 'RemoveCompanionSuite')]
    [string]$Action = 'Check',
    [string]$OperationId,
    [switch]$RestartDesktop,
    [switch]$IncludeCompanionSuite,
    [string[]]$AcknowledgeLiveSessionIds,
    [int]$TimeoutSeconds = 90,
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
        throw '-Apply cannot be combined with -Action Verify, Rollback, or RemoveCompanionSuite.'
    }
    $Action = 'Apply'
}
if ($Action -eq 'RemoveCompanionSuite') {
    Remove-WindowsCopilotCompanionSuite -Lock $lock -DshHome $DshHome `
        -BackupRoot $BackupRoot -DesktopExecutablePath $DesktopExecutablePath |
        ConvertTo-Json -Depth 20
    exit 0
}
if (-not $NpmGlobalRoot) {
    $NpmGlobalRoot = (& npm root --global).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $NpmGlobalRoot) {
        throw 'Could not resolve the global npm package root.'
    }
}

$plan = Get-WindowsCopilotInstallPlan -Lock $lock -DshHome $DshHome `
    -NpmGlobalRoot $NpmGlobalRoot -CopilotIntegrationSourceRoot $CopilotIntegrationSourceRoot `
    -CopilotIntegrationArtifactPath $CopilotIntegrationArtifactPath `
    -DesktopArtifactPath $DesktopArtifactPath -GatewayArtifactPath $GatewayArtifactPath `
    -BackupRoot $BackupRoot -IncludeCompanionSuite:$IncludeCompanionSuite

if ($Action -eq 'Rollback') {
    $rollback = Restore-WindowsCopilotDeployment -Lock $lock -BackupRoot $BackupRoot `
        -OperationId $OperationId -AcknowledgeLiveSessionIds $AcknowledgeLiveSessionIds
    $restart = if ($RestartDesktop) {
        $desktop = Get-WindowsCopilotDesktopState -Lock $lock -Path $DesktopExecutablePath
        if (-not $desktop.valid) {
            throw 'Rollback completed, but the exact locked Desktop executable is unavailable for restart.'
        }

        Restart-WindowsCopilotDesktop -DesktopExecutablePath ([string]$desktop.path) `
            -Lock $lock -TimeoutSeconds $TimeoutSeconds `
            -AcknowledgeLiveSessionIds $AcknowledgeLiveSessionIds
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
    $desktop = Get-WindowsCopilotDesktopState -Lock $lock -Path $DesktopExecutablePath
    $verification = Test-WindowsCopilotOfficialRuntime -Lock $lock `
        -DesktopExecutablePath ([string]$desktop.path) -SkipRuntimeChecks:$SkipRuntimeChecks
    $installation = Test-WindowsCopilotInstallation -Lock $lock -DshHome $DshHome `
        -NpmGlobalRoot $NpmGlobalRoot -DesktopExecutablePath $DesktopExecutablePath `
        -GatewayExecutablePath $GatewayExecutablePath -SkipRuntimeChecks:$SkipRuntimeChecks `
        -IncludeCompanionSuite:$IncludeCompanionSuite
    $acceptance = Test-WindowsCopilotVerificationAcceptance -Installation $installation `
        -IncludeCompanionSuite:$IncludeCompanionSuite
    [pscustomobject]@{
        mode = 'verify'
        valid = [bool]($desktop.valid -and $verification.valid -and $acceptance.valid)
        desktop = $desktop
        officialRuntime = $verification
        companionSuite = $installation.profile.companionSuite
        acceptance = $acceptance
    } | ConvertTo-Json -Depth 20
    if (-not ($desktop.valid -and $verification.valid -and $acceptance.valid)) { exit 2 }
    exit 0
}

if ($Action -eq 'Check') {
    $installation = Test-WindowsCopilotInstallation -Lock $lock -DshHome $DshHome `
        -NpmGlobalRoot $NpmGlobalRoot -ModelCatalogPath $ModelCatalogPath `
        -ComposedConfigPath $ComposedConfigPath -SearchSmokeResponsePath $SearchSmokeResponsePath `
        -DesktopExecutablePath $DesktopExecutablePath -GatewayExecutablePath $GatewayExecutablePath `
        -SkipRuntimeChecks:$SkipRuntimeChecks -IncludeCompanionSuite:$IncludeCompanionSuite
    $checks = [ordered]@{
        manifest = Test-WindowsCopilotLock -Lock $lock
        desktopArtifact = if ($DesktopArtifactPath) {
            Test-LockedArtifact -Path $DesktopArtifactPath `
                -Sha256 ([string]$lock.components.desktop.artifact.sha256) `
                -ExpectedName ([string]$lock.components.desktop.artifact.name)
        } else { [pscustomobject]@{ status = 'not-supplied'; requiredForApply = $true } }
        copilotSource = if ($CopilotIntegrationSourceRoot) {
            Test-CopilotIntegrationDeploymentContract -Lock $lock `
                -SourceRoot $CopilotIntegrationSourceRoot
        } else { [pscustomobject]@{ status = 'not-supplied'; requiredForApply = $true } }
        copilotArtifact = if ($CopilotIntegrationArtifactPath) {
            Test-CopilotIntegrationDeploymentContract -Lock $lock `
                -ArtifactPath $CopilotIntegrationArtifactPath
        } else { [pscustomobject]@{ status = 'not-supplied'; requiredForApply = $true } }
        officialRuntime = $installation.runtime.officialRuntime
        legacyGateway = $installation.migration.legacyGateway
        credential = $installation.profile.credential
        providerRoute = $installation.profile.providerRoute
        composedConfig = if ($ComposedConfigPath) {
            $installation.runtime.composedConfig
        } else {
            [pscustomobject]@{
                status = 'not-supplied'
                command = @($lock.acceptance.composedConfig.command)
            }
        }
        searchSmoke = if ($SearchSmokeResponsePath) {
            Test-WindowsCopilotSearchResponse -Lock $lock -ResponsePath $SearchSmokeResponsePath
        } else {
            [pscustomobject]@{
                status = 'manual-or-injectable'
                contract = $lock.acceptance.searchSmoke
            }
        }
        installation = $installation
        companionSuite = $installation.profile.companionSuite
    }
    [pscustomobject]@{ mode = 'check'; plan = $plan; checks = $checks } |
        ConvertTo-Json -Depth 20
    exit 0
}

foreach ($required in @{
    CopilotIntegrationSourceRoot = $CopilotIntegrationSourceRoot
    CopilotIntegrationArtifactPath = $CopilotIntegrationArtifactPath
    DesktopArtifactPath = $DesktopArtifactPath
}.GetEnumerator()) {
    if ([string]::IsNullOrWhiteSpace([string]$required.Value)) {
        throw "-$($required.Key) is required with -Apply."
    }
}

Invoke-WindowsCopilotApply -Lock $lock -DshHome $DshHome -NpmGlobalRoot $NpmGlobalRoot `
    -CopilotIntegrationSourceRoot $CopilotIntegrationSourceRoot `
    -CopilotIntegrationArtifactPath $CopilotIntegrationArtifactPath `
    -DesktopArtifactPath $DesktopArtifactPath -GatewayArtifactPath $GatewayArtifactPath `
    -GatewayInstallRoot $GatewayInstallRoot -GatewayExecutablePath $GatewayExecutablePath `
    -BackupRoot $BackupRoot -DesktopExecutablePath $DesktopExecutablePath `
    -RestartDesktop:$RestartDesktop -IncludeCompanionSuite:$IncludeCompanionSuite `
    -AcknowledgeLiveSessionIds $AcknowledgeLiveSessionIds `
    -TimeoutSeconds $TimeoutSeconds | ConvertTo-Json -Depth 20
