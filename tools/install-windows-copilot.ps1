[CmdletBinding()]
param(
    [string]$ManifestPath,
    [string]$DshHome = $(if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME '.dsh' }),
    [string]$NpmGlobalRoot,
    [string]$HarnessSourceRoot,
    [string]$ProviderSourceRoot,
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

if (-not $NpmGlobalRoot) {
    $NpmGlobalRoot = (& npm root --global).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $NpmGlobalRoot) {
        throw 'Could not resolve the global npm package root.'
    }
}

$plan = Get-WindowsCopilotInstallPlan -Lock $lock -DshHome $DshHome `
    -NpmGlobalRoot $NpmGlobalRoot -HarnessSourceRoot $HarnessSourceRoot `
    -ProviderSourceRoot $ProviderSourceRoot -DesktopArtifactPath $DesktopArtifactPath `
    -GatewayArtifactPath $GatewayArtifactPath -BackupRoot $BackupRoot

if (-not $Apply) {
    $installation = Test-WindowsCopilotInstallation -Lock $lock -DshHome $DshHome `
        -NpmGlobalRoot $NpmGlobalRoot -ModelCatalogPath $ModelCatalogPath `
        -ComposedConfigPath $ComposedConfigPath -SearchSmokeResponsePath $SearchSmokeResponsePath `
        -DshCliPath $DshCliPath -DesktopExecutablePath $DesktopExecutablePath `
        -GatewayExecutablePath $GatewayExecutablePath `
        -SkipRuntimeChecks:$SkipRuntimeChecks
    $checks = [ordered]@{
        manifest = Test-WindowsCopilotLock -Lock $lock
        desktopArtifact = if ($DesktopArtifactPath) {
            Test-LockedArtifact -Path $DesktopArtifactPath `
                -Sha256 ([string]$lock.components.desktop.artifact.sha256) `
                -ExpectedName ([string]$lock.components.desktop.artifact.name)
        } else { [pscustomobject]@{ status = 'not-supplied'; requiredForApply = $true } }
        gatewayArtifact = if ($GatewayArtifactPath) {
            Test-LockedArtifact -Path $GatewayArtifactPath `
                -Sha256 ([string]$lock.components.gateway.artifact.sha256) `
                -ExpectedName ([string]$lock.components.gateway.artifact.name)
        } else { [pscustomobject]@{ status = 'not-supplied'; requiredForApply = $true } }
        modelCatalog = if ($ModelCatalogPath) {
            $catalog = Get-Content -LiteralPath $ModelCatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $routes = Get-WindowsCopilotRouteModels -Lock $lock -Catalog $catalog
            [pscustomobject]@{
                status = 'valid'
                responses = @($routes[[string]$lock.profile.routes[0].id]).Count
                completions = @($routes[[string]$lock.profile.routes[1].id]).Count
            }
        } else { [pscustomobject]@{ status = 'not-supplied'; liveUrl = [string]$lock.acceptance.modelCatalog.url } }
        composedConfig = if ($ComposedConfigPath) {
            Test-WindowsCopilotComposedConfig -Lock $lock -Path $ComposedConfigPath
        } else { [pscustomobject]@{ status = 'not-supplied'; command = @($lock.acceptance.composedConfig.command) } }
        searchSmoke = if ($SearchSmokeResponsePath) {
            Test-WindowsCopilotSearchResponse -Lock $lock -ResponsePath $SearchSmokeResponsePath
        } else { [pscustomobject]@{ status = 'manual-or-injectable'; contract = $lock.acceptance.searchSmoke } }
        installation = $installation
    }
    [pscustomobject]@{ mode = 'check'; plan = $plan; checks = $checks } | ConvertTo-Json -Depth 20
    exit 0
}

foreach ($required in @{
    HarnessSourceRoot = $HarnessSourceRoot
    ProviderSourceRoot = $ProviderSourceRoot
    DesktopArtifactPath = $DesktopArtifactPath
    GatewayArtifactPath = $GatewayArtifactPath
    ModelCatalogPath = $ModelCatalogPath
}.GetEnumerator()) {
    if ([string]::IsNullOrWhiteSpace([string]$required.Value)) {
        throw "-$($required.Key) is required with -Apply."
    }
}

$catalog = Get-Content -LiteralPath $ModelCatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
Invoke-WindowsCopilotApply -Lock $lock -DshHome $DshHome -NpmGlobalRoot $NpmGlobalRoot `
    -HarnessSourceRoot $HarnessSourceRoot -ProviderSourceRoot $ProviderSourceRoot `
    -DesktopArtifactPath $DesktopArtifactPath -GatewayArtifactPath $GatewayArtifactPath `
    -GatewayInstallRoot $GatewayInstallRoot -BackupRoot $BackupRoot -Catalog $catalog `
    -DesktopExecutablePath $DesktopExecutablePath |
    ConvertTo-Json -Depth 20
