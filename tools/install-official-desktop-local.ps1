[CmdletBinding()]
param(
    [ValidateSet('Check','Apply')][string]$Action = 'Check',
    [switch]$Apply,
    [string]$BuildRoot = 'C:\tmp\dsh-official-desktop-build\work',
    [string]$Registry = 'https://registry.npmjs.org/',
    [string]$PnpmPath,
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'Programs\DSH Local Build'),
    [string]$DataRoot = (Join-Path $env:LOCALAPPDATA 'DSH Local Build'),
    [string]$CommunityRoot = (Join-Path $HOME '.dsh'),
    [switch]$AcknowledgeUnsignedLocalBuild,
    [switch]$Migrate,
    [switch]$WriteMigrationPlan,
    [string]$AcknowledgeMigrationPlan
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Install-DshOfficialDesktopLocal.psm1') -Force
if ($Migrate) { Import-Module (Join-Path $PSScriptRoot 'DshOfficialDesktopLocalMigration.psm1') -Force }
if ($Apply) {
    if ($PSBoundParameters.ContainsKey('Action') -and $Action -ne 'Apply') { throw 'apply-switch-conflicts-with-action' }
    $Action = 'Apply'
}
try {
    if ($Migrate -and $Action -eq 'Check') {
        $installCheck = Invoke-DshOfficialDesktopLocalInstall -Action Check -BuildRoot $BuildRoot -Registry $Registry -PnpmPath $PnpmPath -InstallRoot $InstallRoot -DataRoot $DataRoot
        $migrationPlan = Get-DshOfficialDesktopLocalMigrationPlan -CommunityRoot $CommunityRoot -InstallRoot $InstallRoot -DataRoot $DataRoot -WritePlan:$WriteMigrationPlan
        [pscustomobject]@{ schemaVersion = 1; action = 'migration-plan'; status = $migrationPlan.status; install = $installCheck; migration = $migrationPlan } | ConvertTo-Json -Depth 40
        if ($installCheck.status -eq 'blocked' -or $migrationPlan.status -eq 'blocked') { exit 2 }
        exit 0
    }
    $migrationPreflight = $null
    if ($Migrate) {
        if ($Action -ne 'Apply') { throw 'migration-requires-apply-or-check' }
        if ([string]::IsNullOrWhiteSpace($AcknowledgeMigrationPlan) -or $AcknowledgeMigrationPlan -notmatch '^sha256:[0-9a-fA-F]{64}$') { throw 'migration-plan-acknowledgment-required-before-install' }
        $migrationPreflight = Get-DshOfficialDesktopLocalMigrationPlan -CommunityRoot $CommunityRoot -InstallRoot $InstallRoot -DataRoot $DataRoot
        if ($migrationPreflight.status -ne 'ready') { throw ('migration-target-not-ready-before-install:' + (($migrationPreflight.reasons -join ',') -replace '[\r\n]', '')) }
        if ([string]$migrationPreflight.planHash -cne $AcknowledgeMigrationPlan.ToLowerInvariant()) { throw 'migration-plan-stale-before-install' }
    }
    $result = Invoke-DshOfficialDesktopLocalInstall -Action $Action -BuildRoot $BuildRoot -Registry $Registry -PnpmPath $PnpmPath -InstallRoot $InstallRoot -DataRoot $DataRoot -AcknowledgeUnsignedLocalBuild:$AcknowledgeUnsignedLocalBuild
    if ($Migrate) {
        if ($Action -ne 'Apply') { throw 'migration-requires-apply-or-check' }
        $migration = Invoke-DshOfficialDesktopLocalMigration -Action Apply -CommunityRoot $CommunityRoot -InstallRoot $InstallRoot -DataRoot $DataRoot -AcknowledgeMigrationPlan $AcknowledgeMigrationPlan
        [pscustomobject]@{ schemaVersion = 1; action = 'apply-migrate'; status = $migration.status; install = $result; migration = $migration } | ConvertTo-Json -Depth 40
        if ($result.status -eq 'blocked' -or $migration.status -notin @('complete','noop')) { exit 2 }
        exit 0
    }
    $result | ConvertTo-Json -Depth 30
    if ($result.status -eq 'blocked') { exit 2 }
    exit 0
} catch {
    [pscustomobject]@{
        schemaVersion = 1
        action = $Action.ToLowerInvariant()
        status = $(if ($_.Exception.Message -like 'partial-install-manual-review-required:*') { 'partial-manual-review' } else { 'failed' })
        reason = $_.Exception.Message
        launchedGui = $false
        stoppedProcesses = $false
        automaticRollback = $false
    } | ConvertTo-Json -Depth 8
    exit 2
}
