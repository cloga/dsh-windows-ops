Import-Module (Join-Path $PSScriptRoot '..\tools\WindowsCopilotDeployment.psm1') -Force

Describe 'Windows Copilot profile plugin policy' {
    BeforeAll {
        $script:repoRoot = Split-Path -Parent $PSScriptRoot
        $script:lock = Read-WindowsCopilotLock -Path (Join-Path $repoRoot 'deployments\windows-copilot.lock.json')
        $script:alphaVersion = '0.1.3-alpha.1'
        $script:alphaCommit = 'd347e703908d0406b7a7ef80e3a0e594d86b2215'
    }

    BeforeEach {
        $script:profileRoot = Join-Path $TestDrive 'profile'
        New-Item -ItemType Directory -Path (Join-Path $profileRoot 'node_modules') -Force | Out-Null
    }

    function script:New-PolicyProfile {
        param(
            [Parameter(Mandatory)][hashtable]$Dependencies,
            [string[]]$Bundles = @()
        )
        $dependencyObject = [pscustomobject]$Dependencies
        [pscustomobject]@{
            dependencies = $dependencyObject
            dsh = [pscustomobject]@{
                profile = [pscustomobject]@{ bundles = @($Bundles) }
            }
        }
    }

    function script:Add-InstalledPlugin {
        param(
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][string]$Version
        )
        $root = Join-Path $profileRoot "node_modules\$Name"
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        [ordered]@{ name = $Name; version = $Version } | ConvertTo-Json -Compress |
            Set-Content -LiteralPath (Join-Path $root 'package.json') -Encoding UTF8
    }

    It 'rejects missing or malformed plugin policy data in the deployment lock' {
        $missing = $lock | ConvertTo-Json -Depth 40 | ConvertFrom-Json
        $missing.profile.PSObject.Properties.Remove('pluginPolicy')
        { Test-WindowsCopilotLock -Lock $missing } | Should -Throw "*profile.pluginPolicy*"

        $badDisposition = $lock | ConvertTo-Json -Depth 40 | ConvertFrom-Json
        $badDisposition.profile.pluginPolicy.unmanagedDisposition = 'allow'
        { Test-WindowsCopilotLock -Lock $badDisposition } | Should -Throw '*unmanaged plugins as warnings*'

        $badTarget = $lock | ConvertTo-Json -Depth 40 | ConvertFrom-Json
        $badTarget.profile.pluginPolicy.targets[0].core.commit = '0' * 40
        { Test-WindowsCopilotLock -Lock $badTarget } | Should -Throw '*exact reviewed Core*'

        $missingRule = $lock | ConvertTo-Json -Depth 40 | ConvertFrom-Json
        $missingRule.profile.pluginPolicy.targets[0].rules = @($missingRule.profile.pluginPolicy.targets[0].rules | Select-Object -Skip 1)
        { Test-WindowsCopilotLock -Lock $missingRule } | Should -Throw '*exactly the reviewed compatibility rules*'
    }

    It 'inventories an unmanaged dependency as a warning without blocking managed health' {
        Add-InstalledPlugin -Name 'user-plugin' -Version '1.2.3'
        $profile = New-PolicyProfile -Dependencies @{ 'user-plugin' = '1.2.3' }
        $state = Get-WindowsCopilotProfilePluginPolicyState -Lock $lock -ProfileRoot $profileRoot `
            -Profile $profile -TargetCoreVersion $alphaVersion -TargetCoreCommit $alphaCommit `
            -ComposedConfigContent ''

        $state.status | Should -Be 'allowed'
        @($state.blocking).Count | Should -Be 0
        @($state.warnings).Count | Should -Be 1
        $state.inventory[0].ownership | Should -Be 'unmanaged'
        $state.inventory[0].activation | Should -Be 'installed-only'
    }

    It 'classifies required base bundles as managed rather than unmanaged warnings' {
        $profile = New-PolicyProfile -Dependencies @{} -Bundles @('@deepseek-ai/dsh-base')
        $state = Get-WindowsCopilotProfilePluginPolicyState -Lock $lock -ProfileRoot $profileRoot `
            -Profile $profile -TargetCoreVersion $alphaVersion -TargetCoreCommit $alphaCommit

        ($state.inventory | Where-Object name -eq '@deepseek-ai/dsh-base').ownership |
            Should -Be 'managed-baseline'
        @($state.warnings | Where-Object name -eq '@deepseek-ai/dsh-base').Count | Should -Be 0
    }

    It 'does not block an installed denylisted plugin when its bundle is inactive' {
        Add-InstalledPlugin -Name 'dsh-better-sidebar' -Version '0.18.0'
        $profile = New-PolicyProfile -Dependencies @{ 'dsh-better-sidebar' = 'file:sidebar.tgz' }
        $state = Get-WindowsCopilotProfilePluginPolicyState -Lock $lock -ProfileRoot $profileRoot `
            -Profile $profile -TargetCoreVersion $alphaVersion -TargetCoreCommit $alphaCommit

        $state.status | Should -Be 'allowed'
        @($state.blocking).Count | Should -Be 0
        $state.inventory[0].activation | Should -Be 'inactive'
    }

    It 'blocks the exact denylisted plugin version when its composed entry is active' {
        Add-InstalledPlugin -Name 'dsh-better-sidebar' -Version '0.18.0'
        $profile = New-PolicyProfile -Dependencies @{ 'dsh-better-sidebar' = 'file:sidebar.tgz' } `
            -Bundles @('dsh-better-sidebar')
        $state = Get-WindowsCopilotProfilePluginPolicyState -Lock $lock -ProfileRoot $profileRoot `
            -Profile $profile -TargetCoreVersion $alphaVersion -TargetCoreCommit $alphaCommit `
            -ComposedConfigContent "- id: better-sidebar`n  name: dsh-better-sidebar`n"

        $state.status | Should -Be 'blocked-denylist'
        @($state.blocking).Count | Should -Be 1
        $state.blocking[0].activation | Should -Be 'active'
    }

    It 'allows the required-disabled Pet only when every reviewed entry is explicitly disabled' {
        Add-InstalledPlugin -Name 'dsh-tauri-pet' -Version '0.1.0'
        $profile = New-PolicyProfile -Dependencies @{ 'dsh-tauri-pet' = 'link:pet' } `
            -Bundles @('dsh-tauri-pet')
        $composed = @'
- id: dsh-tauri-pet-skills
  name: pet-skills
  disabled: true
- id: dsh-tauri-pet
  name: dsh-tauri-pet
  disabled: true
'@
        $state = Get-WindowsCopilotProfilePluginPolicyState -Lock $lock -ProfileRoot $profileRoot `
            -Profile $profile -TargetCoreVersion $alphaVersion -TargetCoreCommit $alphaCommit `
            -ComposedConfigContent $composed

        $state.status | Should -Be 'allowed'
        @($state.blocking).Count | Should -Be 0
        ($state.inventory | Where-Object name -eq 'dsh-tauri-pet').activation | Should -Be 'disabled'
    }

    It 'fails closed when a required-disabled entry is active or cannot be observed' {
        Add-InstalledPlugin -Name 'dsh-tauri-pet' -Version '0.1.0'
        $profile = New-PolicyProfile -Dependencies @{ 'dsh-tauri-pet' = 'link:pet' } `
            -Bundles @('dsh-tauri-pet')
        foreach ($composed in @(
            "- id: dsh-tauri-pet`n  name: dsh-tauri-pet`n",
            $null
        )) {
            $state = Get-WindowsCopilotProfilePluginPolicyState -Lock $lock -ProfileRoot $profileRoot `
                -Profile $profile -TargetCoreVersion $alphaVersion -TargetCoreCommit $alphaCommit `
                -ComposedConfigContent $composed
            $state.status | Should -Be 'blocked-denylist'
            @($state.blocking).Count | Should -Be 1
        }
    }

    It 'blocks a patch-injected active entry even when the package bundle is absent' {
        Add-InstalledPlugin -Name 'dsh-better-sidebar' -Version '0.18.0'
        $profile = New-PolicyProfile -Dependencies @{ 'dsh-better-sidebar' = 'file:sidebar.tgz' }
        $state = Get-WindowsCopilotProfilePluginPolicyState -Lock $lock -ProfileRoot $profileRoot `
            -Profile $profile -TargetCoreVersion $alphaVersion -TargetCoreCommit $alphaCommit `
            -ComposedConfigContent "- id: better-sidebar`n  name: dsh-better-sidebar`n"

        $state.status | Should -Be 'blocked-denylist'
        $state.blocking[0].activation | Should -Be 'active'
    }

    It 'does not mistake nested disabled data for a disabled plugin row' {
        Add-InstalledPlugin -Name 'dsh-better-sidebar' -Version '0.18.0'
        $profile = New-PolicyProfile -Dependencies @{ 'dsh-better-sidebar' = 'file:sidebar.tgz' } `
            -Bundles @('dsh-better-sidebar')
        $composed = "- id: better-sidebar`n  name: dsh-better-sidebar`n  config:`n    child:`n      disabled: true`n"
        $state = Get-WindowsCopilotProfilePluginPolicyState -Lock $lock -ProfileRoot $profileRoot `
            -Profile $profile -TargetCoreVersion $alphaVersion -TargetCoreCommit $alphaCommit `
            -ComposedConfigContent $composed

        $state.status | Should -Be 'blocked-denylist'
        $state.blocking[0].activation | Should -Be 'active'
    }

    It 'treats duplicate disabled entry ids as ambiguous and blocks cutover' {
        Add-InstalledPlugin -Name 'dsh-better-sidebar' -Version '0.18.0'
        $profile = New-PolicyProfile -Dependencies @{ 'dsh-better-sidebar' = 'file:sidebar.tgz' } `
            -Bundles @('dsh-better-sidebar')
        $composed = "- id: better-sidebar`n  disabled: true`n- id: better-sidebar`n  disabled: true`n"
        $state = Get-WindowsCopilotProfilePluginPolicyState -Lock $lock -ProfileRoot $profileRoot `
            -Profile $profile -TargetCoreVersion $alphaVersion -TargetCoreCommit $alphaCommit `
            -ComposedConfigContent $composed

        $state.status | Should -Be 'blocked-denylist'
        $state.blocking[0].activation | Should -Be 'ambiguous'
    }

    It 'never reads outside node_modules for an invalid unmanaged package name' {
        $outside = Join-Path $TestDrive 'outside'
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        '{"name":"outside","version":"9.9.9"}' | Set-Content (Join-Path $outside 'package.json')
        $profile = New-PolicyProfile -Dependencies @{ '..\..\outside' = 'file:outside' }
        $state = Get-WindowsCopilotProfilePluginPolicyState -Lock $lock -ProfileRoot $profileRoot `
            -Profile $profile -TargetCoreVersion $alphaVersion -TargetCoreCommit $alphaCommit

        $state.inventory[0].validPackageName | Should -Be $false
        $state.inventory[0].version | Should -BeNullOrEmpty
        $state.warnings[0].code | Should -Be 'unmanaged-plugin-invalid-name'
    }

    It 'does not apply the alpha denylist to a different Core identity' {
        Add-InstalledPlugin -Name 'dsh-better-sidebar' -Version '0.18.0'
        $profile = New-PolicyProfile -Dependencies @{ 'dsh-better-sidebar' = 'file:sidebar.tgz' } `
            -Bundles @('dsh-better-sidebar')
        $state = Get-WindowsCopilotProfilePluginPolicyState -Lock $lock -ProfileRoot $profileRoot `
            -Profile $profile -TargetCoreVersion '0.1.2-rc.1' `
            -TargetCoreCommit 'a66e4702047846cdaa10c66c9d3df3951f5ea70d' `
            -ComposedConfigContent "- id: better-sidebar`n  name: dsh-better-sidebar`n"

        $state.status | Should -Be 'not-evaluated'
        @($state.blocking).Count | Should -Be 0
    }
}
