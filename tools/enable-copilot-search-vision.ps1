[CmdletBinding()]
param(
    [ValidateSet('Apply', 'Verify', 'Rollback')]
    [string]$Action = 'Apply',
    [string]$Model,
    [string]$CopilotIntegrationPackage,
    [Alias('ProviderPackage')]
    [string]$PluginPackage,
    [string]$DshHome = $(if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }),
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
Import-Module (Join-Path $PSScriptRoot 'DshRuntimeSchema.psm1') -Force
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

$deploymentMutex = if (-not $DryRun -and $Action -in @('Apply', 'Rollback')) {
    Enter-WindowsCopilotDeploymentLock -BackupRoot $StateRoot
} else {
    $null
}
try {
if ($Action -eq 'Rollback') {
    Restore-DshCopilotBackup -StateRoot $StateRoot -OperationId $OperationId -DryRun:$DryRun |
        ConvertTo-Json -Depth 8
    return
}

$lock = Read-WindowsCopilotLock -Path $DeploymentLockPath
$CopilotIntegrationPackage = Resolve-LockedCopilotPackageSpec -Lock $lock `
    -PackageSpec $CopilotIntegrationPackage
if ($Action -eq 'Apply' -and
    $CopilotIntegrationPackage -ceq
        [string]$lock.components.copilotIntegration.package.artifact.url) {
    $artifactPath = Join-Path $StateRoot (
        'artifacts\' + [string]$lock.components.copilotIntegration.package.artifact.name
    )
    $CopilotIntegrationPackage = [string](
        Save-WindowsCopilotLockedArtifact `
            -Artifact $lock.components.copilotIntegration.package.artifact `
            -Destination $artifactPath
    ).path
}
$desktop = Get-WindowsCopilotDesktopState -Lock $lock -Path $DesktopExecutablePath
if (-not $desktop.valid) {
    throw "The exact locked Desktop is unavailable: '$($desktop.status)'."
}
$runtime = Get-WindowsCopilotDesktopRuntimeState -Lock $lock -DesktopExecutablePath ([string]$desktop.path) `
    -ErrorAction Stop
$officialRuntime = Test-DshActiveDesktopCore -DeploymentLock $lock -DesktopRuntimeState $runtime
$schema = Test-DshRuntimeSchemaState -Contract $lock.acceptance.runtimeSchema `
    -RequiredPackageRoot $officialRuntime.packageRoot -RequiredProcessIds $officialRuntime.processIds
if (-not $schema.valid) {
    throw "The Desktop-managed official runtime schema is invalid: '$($schema.reasons -join ', ')'."
}
$renderer = Test-DshRendererCompatibility -PackageRoot $officialRuntime.packageRoot -DshHome $DshHome `
    -RequireFlatFallback:$false
$sandbox = Test-DshSandboxRegression -PackageRoot $officialRuntime.packageRoot `
    -ProbeScript (Join-Path $PSScriptRoot 'dsh-sandbox-regression-probe.mjs') -Mode $SandboxGate
$node = Get-Command node -ErrorAction Stop | Select-Object -First 1

$settingsPath = Join-Path $DshHome 'settings.yaml'
$credentialsPath = Join-Path $DshHome '.credentials.yaml'
$profilePaths = @('web', 'headless') | ForEach-Object {
    Join-Path $DshHome (Join-Path (Join-Path 'profiles' $_) 'cordis.patch.yml')
}
$trackedPaths = @($settingsPath, $credentialsPath)
$reviewedLegacyPackages = @{}
foreach ($profile in @('web', 'headless')) {
    $root = Join-Path $DshHome (Join-Path 'profiles' $profile)
    $manifestPath = Join-Path $root 'package.json'
    $legacy = Test-DshReviewedLegacySearchProvider -Lock $lock -ProfileRoot $root
    if ($legacy.present) {
        $reviewedLegacyPackages[$profile] = [string]$legacy.packageRoot
        $trackedPaths += [string]$legacy.packageRoot
    }
    $trackedPaths += @(
        $manifestPath,
        (Join-Path $root 'cordis.patch.yml'),
        (Join-Path $root 'pnpm-lock.yaml'),
        (Join-Path $root 'pnpm-workspace.yaml'),
        (Join-Path $root 'node_modules\dsh-github-copilot')
    )
}

$backup = $null
$changes = @()
$profiles = $null
$coherence = $null
$route = $null
if ($Action -eq 'Apply') {
    $backup = New-DshCopilotBackup -Paths $trackedPaths -StateRoot $StateRoot -DryRun:$DryRun
    try {
        if (-not $DryRun) {
            $previousDshHome = $env:DSH_HOME
            try {
                $env:DSH_HOME = $DshHome
                foreach ($profile in @('web', 'headless')) {
                    if ($reviewedLegacyPackages.ContainsKey($profile)) {
                        & $node.Source $officialRuntime.entryPath plugin --profile $profile remove dsh-web-search-provider |
                            Out-Null
                        if ($LASTEXITCODE -ne 0) {
                            throw "Legacy dsh-web-search-provider removal failed for profile '$profile'."
                        }
                    }
                    & $node.Source $officialRuntime.entryPath plugin --profile $profile add $CopilotIntegrationPackage |
                        Out-Null
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
        $profiles = @('web', 'headless') | ForEach-Object {
            Test-DshCopilotProfile -DshHome $DshHome -Profile $_ `
                -ExpectedPluginVersion ([string]$lock.components.copilotIntegration.package.version)
        }
        $coherence = Test-WindowsCopilotProfileCoherence -Lock $lock -DshHome $DshHome
        if (-not $DryRun -and -not $coherence.valid) {
            throw 'Copilot profile artifact source or installed closure is not verified.'
        }
        $route = if ($credential.configured) {
            Test-DshCopilotSettings -Path $settingsPath -Model $Model
        } else {
            Get-DshCopilotRouteState -SettingsPath $settingsPath
        }
        if (-not $DryRun) {
            $expectedStates = @($trackedPaths | Select-Object -Unique | ForEach-Object {
                $fingerprint = Get-DshCopilotPathFingerprint -Path $_
                $exists = [string]$fingerprint.kind -cne 'absent'
                [pscustomobject]@{
                    path = [IO.Path]::GetFullPath($_)
                    exists = $exists
                    fingerprint = $fingerprint
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
    $profiles = @('web', 'headless') | ForEach-Object {
        Test-DshCopilotProfile -DshHome $DshHome -Profile $_ `
            -ExpectedPluginVersion ([string]$lock.components.copilotIntegration.package.version)
    }
    $coherence = Test-WindowsCopilotProfileCoherence -Lock $lock -DshHome $DshHome
    if (-not $coherence.valid) {
        throw 'Copilot profile artifact source or installed closure is not verified.'
    }
    $route = if ($credential.configured) {
        Test-DshCopilotSettings -Path $settingsPath -Model $Model
    } else {
        Get-DshCopilotRouteState -SettingsPath $settingsPath
    }
}

[pscustomobject]@{
    status = if ($DryRun) { 'dry-run-ok' } elseif (-not $credential.configured) { 'sign-in-required' } else { 'verified' }
    action = $Action
    operationId = if ($backup) { $backup.operationId } else { $null }
    signIn = if ($credential.configured) {
        $null
    } else {
        'Open Models, select the GitHub Copilot provider card, and complete the device flow.'
    }
    runtime = @{
        packageRoot = $officialRuntime.packageRoot
        entryPath = $officialRuntime.entryPath
        version = $officialRuntime.version
        repository = $lock.acceptance.runtimeSchema.source.repository
        commitSha = $lock.acceptance.runtimeSchema.source.commit
        activeProcessIds = $officialRuntime.processIds
        desktopRuntimeSelector = $officialRuntime.selector
        desktopRuntimeSource = $officialRuntime.source
        desktopRuntimeVersion = $officialRuntime.version
        schemaStatus = $schema.status
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
    coherence = $coherence
    sandbox = $sandbox
    changes = @($changes)
} | ConvertTo-Json -Depth 10
} finally {
    if ($deploymentMutex) {
        Exit-WindowsCopilotDeploymentLock -Mutex $deploymentMutex
    }
}
