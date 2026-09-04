[CmdletBinding()]
param(
    [ValidateSet('Check', 'Apply', 'Remove')]
    [string]$Action = 'Check',
    [string]$Profile = 'web',
    [string]$DshHome = $(if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME '.dsh' }),
    [string]$DshCliPath = 'dsh',
    [string]$PnpmCliPath = 'pnpm',
    [string]$DownloadRoot = $(Join-Path $DshHome 'downloads'),
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Apply) {
    if ($Action -notin @('Check', 'Apply')) {
        throw '-Apply cannot be combined with -Action Remove.'
    }
    $Action = 'Apply'
}

$components = @(
    [pscustomobject]@{
        name = 'dsh-github-copilot'
        version = '0.3.0-cloga.15'
        spec = 'https://github.com/cloga/dsh-github-copilot/releases/download/v0.3.0-cloga.15/dsh-github-copilot-0.3.0-cloga.15.tgz'
        sha256 = '7486d2c062c7fcdd5ee36505ff9320eaec634497c1ea2481b335ea67e85a25b1'
    },
    [pscustomobject]@{
        name = 'dsh-cron'
        version = '0.3.3'
        spec = 'github:cloga/dsh-cron#f5e8df45496523c98874e6f484b886941683f7d6'
        sha256 = $null
    },
    [pscustomobject]@{
        name = 'dsh-playwright-host'
        version = '0.1.1'
        spec = 'github:cloga/dsh-playwright-host#86ca74d4fdf89d6aa6036f273eb8acab4adae34f'
        sha256 = $null
    }
)

function Read-ProfileState {
    $profileDir = Join-Path (Join-Path $DshHome 'profiles') $Profile
    $manifestPath = Join-Path $profileDir 'package.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return [pscustomobject]@{
            profileDir = $profileDir
            manifestPath = $manifestPath
            exists = $false
            dependencySpecs = @{}
            bundles = @()
        }
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $dependencySpecs = @{}
    if ($null -ne $manifest.dependencies) {
        foreach ($property in $manifest.dependencies.psobject.Properties) {
            $dependencySpecs[$property.Name] = [string]$property.Value
        }
    }
    $bundles = if ($null -eq $manifest.dsh -or $null -eq $manifest.dsh.profile) { @() } else { @($manifest.dsh.profile.bundles) }
    return [pscustomobject]@{
        profileDir = $profileDir
        manifestPath = $manifestPath
        exists = $true
        dependencySpecs = $dependencySpecs
        bundles = $bundles
    }
}

function Get-ComponentSourceStatus {
    param(
        [Parameter(Mandatory)]$Component,
        [string]$InstalledSpec
    )
    if ([string]::IsNullOrWhiteSpace($InstalledSpec)) {
        return [pscustomobject]@{ valid = $false; hashVerified = $false }
    }
    if ($Component.name -ne 'dsh-github-copilot') {
        return [pscustomobject]@{
            valid = $InstalledSpec -ceq $Component.spec
            hashVerified = $false
        }
    }
    if ($InstalledSpec -ceq $Component.spec) {
        return [pscustomobject]@{ valid = $true; hashVerified = $false }
    }
    if (-not $InstalledSpec.StartsWith('file:', [StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{ valid = $false; hashVerified = $false }
    }
    $artifactPath = $InstalledSpec.Substring(5)
    if (-not [IO.Path]::IsPathRooted($artifactPath)) {
        $artifactPath = Join-Path (Join-Path (Join-Path $DshHome 'profiles') $Profile) $artifactPath
    }
    if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
        return [pscustomobject]@{ valid = $false; hashVerified = $false }
    }
    $matches = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $Component.sha256
    return [pscustomobject]@{ valid = $matches; hashVerified = $matches }
}

function Test-LockImporterDependency {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$LockText,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Specifier
    )
    $inImporters = $false
    $inRootImporter = $false
    $inDependencies = $false
    $inTarget = $false
    foreach ($line in ($LockText -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $trimmed = $line.Trim()
        $indent = $line.Length - $line.TrimStart().Length
        if ($indent -eq 0) {
            $inImporters = $trimmed -ceq 'importers:'
            $inRootImporter = $false
            $inDependencies = $false
            $inTarget = $false
            continue
        }
        if (-not $inImporters) { continue }
        if ($indent -eq 2) {
            $inRootImporter = $trimmed -ceq '.:'
            $inDependencies = $false
            $inTarget = $false
            continue
        }
        if (-not $inRootImporter) { continue }
        if ($indent -eq 4) {
            $inDependencies = $trimmed -ceq 'dependencies:'
            $inTarget = $false
            continue
        }
        if (-not $inDependencies) { continue }
        if ($indent -eq 6) {
            $inTarget = $trimmed -ceq "${Name}:"
            continue
        }
        if ($inTarget -and $indent -eq 8 -and $trimmed.StartsWith('specifier:', [StringComparison]::Ordinal)) {
            $value = $trimmed.Substring('specifier:'.Length).Trim()
            if (($value.StartsWith("'") -and $value.EndsWith("'")) -or ($value.StartsWith('"') -and $value.EndsWith('"'))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            return $value -ceq $Specifier
        }
    }
    return $false
}

function Get-SuiteStatus {
    $state = Read-ProfileState
    $lockPath = Join-Path $state.profileDir 'pnpm-lock.yaml'
    $lockText = if (Test-Path -LiteralPath $lockPath -PathType Leaf) {
        Get-Content -LiteralPath $lockPath -Raw
    } else { '' }
    $items = @($components | ForEach-Object {
        $dependencyPresent = $state.dependencySpecs.ContainsKey($_.name)
        $installedSpec = if ($dependencyPresent) { [string]$state.dependencySpecs[$_.name] } else { $null }
        $source = Get-ComponentSourceStatus -Component $_ -InstalledSpec $installedSpec
        $installedManifestPath = Join-Path (Join-Path (Join-Path $state.profileDir 'node_modules') $_.name) 'package.json'
        $installedVersion = $null
        if (Test-Path -LiteralPath $installedManifestPath -PathType Leaf) {
            $installedManifest = Get-Content -LiteralPath $installedManifestPath -Raw | ConvertFrom-Json
            if ([string]$installedManifest.name -ceq $_.name) {
                $installedVersion = [string]$installedManifest.version
            }
        }
        $lockEvidence = -not [string]::IsNullOrWhiteSpace($installedSpec) `
            -and (Test-LockImporterDependency -LockText $lockText -Name $_.name -Specifier $installedSpec)
        [pscustomobject]@{
            name = $_.name
            version = $_.version
            desiredSpec = $_.spec
            installedSpec = $installedSpec
            installedVersion = $installedVersion
            dependencyPresent = $dependencyPresent
            bundlePresent = $state.bundles -contains $_.name
            lockEvidence = $lockEvidence
            installedValid = $installedVersion -ceq $_.version
            sourceValid = $source.valid
            hashVerified = $source.hashVerified
        }
    })
    return [pscustomobject]@{
        action = $Action.ToLowerInvariant()
        profile = $Profile
        profileExists = $state.exists
        profileManifest = $state.manifestPath
        lockPresent = -not [string]::IsNullOrEmpty($lockText)
        complete = @($items | Where-Object {
            -not ($_.dependencyPresent -and $_.bundlePresent -and $_.lockEvidence -and $_.installedValid -and $_.sourceValid)
        }).Count -eq 0
        components = $items
        activation = 'A Host restart is required; this installer never restarts Desktop or DSH.'
    }
}

function Invoke-DshPlugin {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $previousDshHome = $env:DSH_HOME
    try {
        $env:DSH_HOME = $DshHome
        & $DshCliPath plugin --profile $Profile @Arguments
        $exitCode = $LASTEXITCODE
    } finally {
        if ($null -eq $previousDshHome) {
            Remove-Item Env:DSH_HOME -ErrorAction SilentlyContinue
        } else {
            $env:DSH_HOME = $previousDshHome
        }
    }
    if ($exitCode -ne 0) {
        throw "dsh plugin failed with exit code $exitCode."
    }
}

function Remove-StaleSuiteBundleEntries {
    $state = Read-ProfileState
    $manifest = Get-Content -LiteralPath $state.manifestPath -Raw | ConvertFrom-Json
    if ($null -eq $manifest.dsh -or $null -eq $manifest.dsh.profile) { return }
    $suiteNames = @($components.name)
    $before = @($manifest.dsh.profile.bundles)
    $after = @($before | Where-Object { $suiteNames -notcontains $_ })
    if ($after.Count -eq $before.Count) { return }
    $manifest.dsh.profile.bundles = $after
    $manifest | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $state.manifestPath -Encoding UTF8
}

function New-ProfileBackup {
    $state = Read-ProfileState
    $backupRoot = Join-Path $DshHome 'suite-backups'
    $backupPath = Join-Path $backupRoot ((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ') + '-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
    foreach ($name in @('package.json', 'pnpm-lock.yaml', 'pnpm-workspace.yaml')) {
        $source = Join-Path $state.profileDir $name
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            Copy-Item -LiteralPath $source -Destination (Join-Path $backupPath $name)
        }
    }
    return $backupPath
}

function Restore-ProfileBackup {
    param([Parameter(Mandatory)][string]$BackupPath)
    $profileDir = Join-Path (Join-Path $DshHome 'profiles') $Profile
    foreach ($name in @('package.json', 'pnpm-lock.yaml', 'pnpm-workspace.yaml')) {
        $backupFile = Join-Path $BackupPath $name
        $target = Join-Path $profileDir $name
        if (Test-Path -LiteralPath $backupFile -PathType Leaf) {
            Copy-Item -LiteralPath $backupFile -Destination $target -Force
        } else {
            Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
        }
    }
    Push-Location $profileDir
    try {
        & $PnpmCliPath install --offline --frozen-lockfile
        if ($LASTEXITCODE -ne 0) {
            throw "pnpm offline restore failed with exit code $LASTEXITCODE."
        }
    } finally {
        Pop-Location
    }
}

function Complete-Mutation {
    param(
        [Parameter(Mandatory)][string]$BackupPath,
        [Parameter(Mandatory)][ValidateSet('Present', 'Absent')][string]$ExpectedState
    )
    $result = Get-SuiteStatus
    $valid = if ($ExpectedState -eq 'Present') {
        $result.complete
    } else {
        @($result.components | Where-Object { $_.dependencyPresent -or $_.bundlePresent }).Count -eq 0
    }
    if (-not $valid) {
        throw 'DSH completed the package command but post-operation source and bundle verification failed.'
    }
    $result | Add-Member -NotePropertyName backupPath -NotePropertyValue $BackupPath
    return $result
}

if ($Action -eq 'Check') {
    Get-SuiteStatus | ConvertTo-Json -Depth 8
    exit 0
}

$initialState = Read-ProfileState
if (-not $initialState.exists) {
    throw "The '$Profile' Profile does not exist under DSH_HOME. Initialize and verify the Profile before applying optional bundles."
}
$backupPath = New-ProfileBackup

try {
    if ($Action -eq 'Remove') {
        $installedNames = @($components | Where-Object { $initialState.dependencySpecs.ContainsKey($_.name) } | ForEach-Object name)
        if ($installedNames.Count -gt 0) {
            Invoke-DshPlugin -Arguments (@('remove') + $installedNames)
        }
        Remove-StaleSuiteBundleEntries
        Complete-Mutation -BackupPath $backupPath -ExpectedState Absent | ConvertTo-Json -Depth 8
        exit 0
    }

    New-Item -ItemType Directory -Path $DownloadRoot -Force | Out-Null
    $copilot = $components[0]
    $copilotArtifact = Join-Path $DownloadRoot "dsh-github-copilot-$($copilot.version).tgz"
    Invoke-WebRequest -UseBasicParsing -Uri $copilot.spec -OutFile $copilotArtifact
    $actualSha256 = (Get-FileHash -LiteralPath $copilotArtifact -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualSha256 -cne $copilot.sha256) {
        Remove-Item -LiteralPath $copilotArtifact -Force -ErrorAction SilentlyContinue
        throw 'The downloaded dsh-github-copilot artifact failed SHA-256 verification.'
    }

    Invoke-DshPlugin -Arguments @(
        'add',
        $copilotArtifact,
        $components[1].spec,
        $components[2].spec
    )
    Complete-Mutation -BackupPath $backupPath -ExpectedState Present | ConvertTo-Json -Depth 8
} catch {
    $failure = $_.Exception.Message
    try {
        Restore-ProfileBackup -BackupPath $backupPath
    } catch {
        throw "$failure Automatic restore also failed; preserve and inspect backup $backupPath. Restore failure: $($_.Exception.Message)"
    }
    throw "$failure The previous Profile manifests and lockfile were restored from $backupPath."
}
