[CmdletBinding()]
param(
    [ValidateSet('Apply', 'Verify', 'Rollback')]
    [string]$Action = 'Apply',
    [string]$Model,
    [string]$BaseUrl = 'http://127.0.0.1:7777/v1',
    [string]$DshHome = $(if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }),
    [string]$DshCliPath,
    [string]$DesktopRoot = $env:DSH_DESKTOP_ROOT,
    [string]$StateRoot = $(if ($env:DSH_OPS_STATE_ROOT) { $env:DSH_OPS_STATE_ROOT } else { Join-Path $env:LOCALAPPDATA 'dsh-windows-ops' }),
    [string]$OperationId,
    [ValidateSet('Contract', 'Live')]
    [string]$VisionProbe = 'Contract',
    [ValidateSet('Report', 'Require', 'Skip')]
    [string]$SandboxGate = 'Report',
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'DshCopilotBootstrap.psm1') -Force

$DshHome = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($DshHome))
$StateRoot = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($StateRoot))

if ($Action -eq 'Rollback') {
    Restore-DshCopilotBackup -StateRoot $StateRoot -OperationId $OperationId -DryRun:$DryRun |
        ConvertTo-Json -Depth 8
    exit
}
if (-not $Model) { throw '-Model is required for Apply and Verify.' }

$cli = Resolve-DshCliInfo -DshCliPath $DshCliPath
$core = Test-DshActiveDesktopCore -CliInfo $cli -DesktopRoot $DesktopRoot
$renderer = Test-DshRendererCompatibility -PackageRoot $cli.packageRoot -DshHome $DshHome
$credentialSource = Test-DshCredentialReference -DshHome $DshHome
$catalog = Get-DshCopilotCatalog -BaseUrl $BaseUrl -Model $Model
if (-not $catalog.selectedModel.visionCapable) {
    throw "Selected model '$Model' has no explicit image-capability metadata; its name is not evidence."
}
$sandbox = Test-DshSandboxRegression -PackageRoot $cli.packageRoot `
    -ProbeScript (Join-Path $PSScriptRoot 'dsh-sandbox-regression-probe.mjs') -Mode $SandboxGate

$settingsPath = Join-Path $DshHome 'settings.yaml'
$profilePaths = @('web', 'headless') | ForEach-Object {
    Join-Path $DshHome (Join-Path (Join-Path 'profiles' $_) 'cordis.patch.yml')
}
$trackedPaths = @($settingsPath)
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
$profiles = @()
$settings = $null
$vision = $null
if ($Action -eq 'Apply') {
    Set-DshCopilotSettings -Path $settingsPath -BaseUrl $BaseUrl -Model $Model `
        -VisionCapable $true -DryRun | Out-Null
    foreach ($path in $profilePaths) {
        Set-DshCopilotProfilePatch -Path $path -DryRun | Out-Null
    }
    $backup = New-DshCopilotBackup -Paths $trackedPaths -StateRoot $StateRoot -DryRun:$DryRun
    try {
        if (-not $DryRun) {
            $previousDshHome = $env:DSH_HOME
            try {
                $env:DSH_HOME = $DshHome
                foreach ($profile in @('web', 'headless')) {
                    & $cli.cliPath plugin --profile $profile add dsh-web-search-provider | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw "dsh plugin installation failed for profile '$profile'." }
                }
            } finally {
                $env:DSH_HOME = $previousDshHome
            }
        }
        $changes += Set-DshCopilotSettings -Path $settingsPath -BaseUrl $BaseUrl -Model $Model `
            -VisionCapable $true -DryRun:$DryRun
        foreach ($path in $profilePaths) {
            $changes += Set-DshCopilotProfilePatch -Path $path -DryRun:$DryRun
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
            $profiles = @('web', 'headless') | ForEach-Object {
                Test-DshCopilotProfile -DshHome $DshHome -Profile $_
            }
            $settings = Test-DshCopilotSettings -Path $settingsPath -BaseUrl $BaseUrl -Model $Model
            $vision = Invoke-DshVisionProbe -BaseUrl $BaseUrl -Model $Model -Mode $VisionProbe
            Complete-DshCopilotBackup -StateRoot $StateRoot -OperationId $backup.operationId `
                -ExpectedStates $expectedStates | Out-Null
        } else {
            $vision = Invoke-DshVisionProbe -BaseUrl $BaseUrl -Model $Model -Mode 'Contract'
        }
    } catch {
        if (-not $DryRun -and $backup) {
            Restore-DshCopilotBackup -StateRoot $StateRoot -OperationId $backup.operationId -ForceIncomplete | Out-Null
        }
        throw
    }
} else {
    $profiles = @('web', 'headless') | ForEach-Object {
        Test-DshCopilotProfile -DshHome $DshHome -Profile $_
    }
    $settings = Test-DshCopilotSettings -Path $settingsPath -BaseUrl $BaseUrl -Model $Model
    $vision = Invoke-DshVisionProbe -BaseUrl $BaseUrl -Model $Model -Mode $VisionProbe
}

[pscustomobject]@{
    status = if ($DryRun) { 'dry-run-ok' } else { 'verified' }
    action = $Action
    operationId = if ($backup) { $backup.operationId } else { $null }
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
    }
    renderer = @{ healthy = $renderer.healthy }
    credential = @{ reference = 'COPILOT_API_KEY'; source = $credentialSource }
    gateway = @{
        modelsUri = $catalog.uri
        selectedModel = $catalog.selectedModel.id
        visionEvidence = $catalog.selectedModel.visionEvidence
    }
    profiles = @($profiles)
    settings = $settings
    vision = $vision
    sandbox = $sandbox
    changes = @($changes)
} | ConvertTo-Json -Depth 10
