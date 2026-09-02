[CmdletBinding()]
param(
    [ValidateSet('Apply', 'Verify', 'Rollback')]
    [string]$Action = 'Apply',
    [string]$Model,
    [string]$CopilotIntegrationPackage = 'dsh-github-copilot',
    [Alias('ProviderPackage')]
    [string]$PluginPackage,
    [string]$DshHome = $(if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }),
    [string]$DshCliPath,
    [string]$DeploymentLockPath,
    [string]$DesktopExecutablePath = $(Join-Path $env:LOCALAPPDATA 'Deepseek Harness Desktop\deepseek-harness-desktop.exe'),
    [string]$StateRoot = $(if ($env:DSH_OPS_STATE_ROOT) { $env:DSH_OPS_STATE_ROOT } else { Join-Path $env:LOCALAPPDATA 'dsh-windows-ops' }),
    [string]$OperationId,
    [ValidateSet('Report', 'Require', 'Skip')]
    [string]$SandboxGate = 'Require',
    [string]$BaseUrl,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'DshCopilotBootstrap.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'WindowsCopilotDeployment.psm1') -Force
if (-not $DeploymentLockPath) {
    $DeploymentLockPath = Join-Path $PSScriptRoot '..\deployments\windows-copilot.lock.json'
}

if ($BaseUrl) {
    throw '-BaseUrl belongs to the retired copilot2api bootstrap and is not accepted by the direct plugin baseline.'
}
if ($PluginPackage) { $CopilotIntegrationPackage = $PluginPackage }
$DshHome = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($DshHome))
$StateRoot = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($StateRoot))
$CopilotIntegrationPackage = [Environment]::ExpandEnvironmentVariables($CopilotIntegrationPackage)
if (Test-Path -LiteralPath $CopilotIntegrationPackage -PathType Leaf) {
    $CopilotIntegrationPackage = [IO.Path]::GetFullPath($CopilotIntegrationPackage)
}

if ($Action -eq 'Rollback') {
    Restore-DshCopilotBackup -StateRoot $StateRoot -OperationId $OperationId -DryRun:$DryRun |
        ConvertTo-Json -Depth 8
    exit
}

$cli = Resolve-DshCliInfo -DshCliPath $DshCliPath
$lock = Read-WindowsCopilotLock -Path $DeploymentLockPath
$desktop = Get-WindowsCopilotDesktopState -Lock $lock -Path $DesktopExecutablePath
if (-not $desktop.valid) {
    throw "The exact locked Desktop is unavailable: '$($desktop.status)'."
}
$runtimeCli = [pscustomobject]@{
    valid = $true
    version = $cli.version
    packageRoot = $cli.packageRoot
    entryPath = $cli.entryPath
}
$runtime = Get-WindowsCopilotDesktopRuntimeState -Lock $lock -DesktopExecutablePath ([string]$desktop.path) `
    -ForkCliInfo $runtimeCli
$core = Test-DshActiveDesktopCore -CliInfo $cli -DeploymentLock $lock -DesktopRuntimeState $runtime
$renderer = Test-DshRendererCompatibility -PackageRoot $core.packageRoot -DshHome $DshHome `
    -RequireFlatFallback:($core.selector -ceq 'controlled-fork')
$sandbox = Test-DshSandboxRegression -PackageRoot $cli.packageRoot `
    -ProbeScript (Join-Path $PSScriptRoot 'dsh-sandbox-regression-probe.mjs') -Mode $SandboxGate

$settingsPath = Join-Path $DshHome 'settings.yaml'
$credentialsPath = Join-Path $DshHome '.credentials.yaml'
$profilePaths = @('web', 'headless') | ForEach-Object {
    Join-Path $DshHome (Join-Path (Join-Path 'profiles' $_) 'cordis.patch.yml')
}
$trackedPaths = @($settingsPath, $credentialsPath)
foreach ($profile in @('web', 'headless')) {
    $root = Join-Path $DshHome (Join-Path 'profiles' $profile)
    $trackedPaths += @(
        (Join-Path $root 'package.json'),
        (Join-Path $root 'cordis.patch.yml'),
        (Join-Path $root 'pnpm-lock.yaml'),
        (Join-Path $root 'pnpm-workspace.yaml')
    )
}

$backup = $null
$changes = @()
if ($Action -eq 'Apply') {
    $backup = New-DshCopilotBackup -Paths $trackedPaths -StateRoot $StateRoot -DryRun:$DryRun
    try {
        if (-not $DryRun) {
            $previousDshHome = $env:DSH_HOME
            try {
                $env:DSH_HOME = $DshHome
                foreach ($profile in @('web', 'headless')) {
                    $manifestPath = Join-Path $DshHome (Join-Path "profiles\$profile" 'package.json')
                    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
                        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
                        if ($manifest.PSObject.Properties['dependencies'] -and
                            $manifest.dependencies.PSObject.Properties['dsh-web-search-provider']) {
                            & $cli.cliPath plugin --profile $profile remove dsh-web-search-provider | Out-Null
                            if ($LASTEXITCODE -ne 0) {
                                throw "Legacy dsh-web-search-provider removal failed for profile '$profile'."
                            }
                        }
                    }
                    & $cli.cliPath plugin --profile $profile add $CopilotIntegrationPackage | Out-Null
                    if ($LASTEXITCODE -ne 0) {
                        throw "dsh-github-copilot installation failed for profile '$profile'."
                    }
                }
            } finally {
                $env:DSH_HOME = $previousDshHome
            }
        }
        $changes += Remove-DshLegacyCopilotSettings -Path $settingsPath -DryRun:$DryRun
        $changes += Remove-DshLegacyCopilotCredentialReference -Path $credentialsPath -DryRun:$DryRun
        foreach ($path in $profilePaths) {
            $changes += Set-DshCopilotProfilePatch -Path $path -DryRun:$DryRun
        }
        $credential = Test-DshCopilotCredentialRecord -DshHome $DshHome
        if ($credential.configured -and $Model) {
            $changes += Set-DshCopilotModelSelection -Path $settingsPath -Model $Model -DryRun:$DryRun
        }
        if (-not $DryRun) {
            $expectedStates = @($trackedPaths | Select-Object -Unique | ForEach-Object {
                $exists = Test-Path -LiteralPath $_ -PathType Leaf
                [pscustomobject]@{
                    path = [IO.Path]::GetFullPath($_)
                    exists = $exists
                    sha256 = if ($exists) { (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash } else { $null }
                }
            })
            Complete-DshCopilotBackup -StateRoot $StateRoot -OperationId $backup.operationId `
                -ExpectedStates $expectedStates | Out-Null
        }
    } catch {
        if (-not $DryRun -and $backup) {
            Restore-DshCopilotBackup -StateRoot $StateRoot -OperationId $backup.operationId -ForceIncomplete |
                Out-Null
        }
        throw
    }
} else {
    $credential = Test-DshCopilotCredentialRecord -DshHome $DshHome
}

$profiles = @('web', 'headless') | ForEach-Object {
    Test-DshCopilotProfile -DshHome $DshHome -Profile $_ `
        -ExpectedPluginVersion ([string]$lock.components.copilotIntegration.package.version)
}
$route = if ($credential.configured) {
    Test-DshCopilotSettings -Path $settingsPath -Model $Model
} else {
    Get-DshCopilotRouteState -SettingsPath $settingsPath
}

[pscustomobject]@{
    status = if ($DryRun) { 'dry-run-ok' } elseif (-not $credential.configured) { 'sign-in-required' } else { 'verified' }
    action = $Action
    operationId = if ($backup) { $backup.operationId } else { $null }
    signIn = if ($credential.configured) {
        $null
    } elseif ($core.version -eq '0.1.1-rc.2') {
        'Open Settings -> GitHub Copilot and complete the device flow.'
    } else {
        'Open Models, select the GitHub Copilot provider card, and complete the device flow.'
    }
    core = @{
        cliPath = $cli.cliPath
        packageRoot = $cli.packageRoot
        version = $cli.version
        repository = $cli.repository
        commitSha = $cli.commitSha
        receiptPath = $cli.receiptPath
        releaseManifestSha256 = $cli.releaseManifestSha256
        packageCount = $cli.packageCount
        activeProcessIds = $core.processIds
        desktopRuntimeSelector = $core.selector
        desktopRuntimeSource = $core.source
        desktopRuntimeVersion = $core.version
    }
    renderer = @{ healthy = $renderer.healthy }
    credential = @{
        record = $credential.record
        kind = $credential.kind
        configured = $credential.configured
        status = $credential.status
    }
    provider = @{
        route = 'github-copilot'
        referenceFree = [bool]$route.referenceFree
        availableModels = @($route.availableModels)
        selectedModel = $Model
    }
    profiles = @($profiles)
    sandbox = $sandbox
    changes = @($changes)
} | ConvertTo-Json -Depth 10
