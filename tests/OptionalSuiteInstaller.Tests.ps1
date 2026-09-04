Describe 'Optional companion suite compatibility wrapper' {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $wrapperPath = Join-Path $repoRoot 'tools\install-optional-companion-suite.ps1'
        $mainPath = Join-Path $repoRoot 'tools\install-windows-copilot.ps1'
        $modulePath = Join-Path $repoRoot 'tools\WindowsCopilotDeployment.psm1'
        $lockPath = Join-Path $repoRoot 'deployments\windows-copilot.lock.json'
        $wrapper = Get-Content -LiteralPath $wrapperPath -Raw
        $main = Get-Content -LiteralPath $mainPath -Raw
        $module = Get-Content -LiteralPath $modulePath -Raw
        $lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
        Import-Module $modulePath -Force

        function Initialize-RemovalFixture {
            param([Parameter(Mandatory)][string]$DshHome)
            $profileRoot = Join-Path $DshHome ([string]$lock.profile.relativePath)
            $nodeModules = Join-Path $profileRoot 'node_modules'
            New-Item -ItemType Directory -Path $nodeModules -Force | Out-Null
            $required = [string]$lock.components.copilotIntegration.package.name
            $optional = @($lock.companionSuite.members | Where-Object {
                -not $_.requiredByBaseDeployment
            } | ForEach-Object { [string]$_.name })
            $dependencies = [ordered]@{}
            foreach ($name in @($required) + $optional) {
                $dependencies[$name] = "file:fixture/$name.tgz"
                $target = Join-Path $nodeModules $name
                New-Item -ItemType Directory -Path $target -Force | Out-Null
                $name | Set-Content -LiteralPath (Join-Path $target 'payload.txt') -Encoding UTF8
            }
            $officialLinks = [ordered]@{}
            foreach ($name in @($lock.components.desktop.internalPlugins.name)) {
                $source = Join-Path $DshHome (Join-Path 'desktop-resources' $name)
                $target = Join-Path $nodeModules $name
                New-Item -ItemType Directory -Path $source -Force | Out-Null
                $name | Set-Content -LiteralPath (Join-Path $source 'payload.txt') -Encoding UTF8
                New-Item -ItemType Junction -Path $target -Target $source | Out-Null
                $officialLinks[$name] = [IO.Path]::GetFullPath($source)
            }
            [ordered]@{
                dependencies = $dependencies
                dsh = @{ profile = @{ bundles = @($required) + $optional } }
            } | ConvertTo-Json -Depth 8 |
                Set-Content -LiteralPath (Join-Path $profileRoot 'package.json') -Encoding UTF8
            "packages:`n  - ." |
                Set-Content -LiteralPath (Join-Path $profileRoot 'pnpm-workspace.yaml') -Encoding UTF8
            "lockfileVersion: '9.0'" |
                Set-Content -LiteralPath (Join-Path $profileRoot 'pnpm-lock.yaml') -Encoding UTF8
            return [pscustomobject]@{
                profileRoot = $profileRoot
                nodeModules = $nodeModules
                required = $required
                optional = $optional
                officialLinks = $officialLinks
            }
        }
    }

    It 'contains no independent companion identity pins' {
        foreach ($value in @(
            [string]$lock.components.copilotIntegration.package.version,
            [string]$lock.components.copilotIntegration.package.artifact.sha256
        ) + @($lock.profile.optionalOverlays | ForEach-Object {
            @([string]$_.version, [string]$_.artifact.sha256)
        })) {
            $wrapper | Should -Not -Match ([regex]::Escape($value))
        }
    }

    It 'routes Check and Apply through the authoritative main installer suite switch' {
        $wrapper | Should -Match "install-windows-copilot\.ps1"
        $wrapper | Should -Match "IncludeCompanionSuite"
        $wrapper | Should -Match "CopilotIntegrationSourceRoot"
        $wrapper | Should -Match "CopilotIntegrationArtifactPath"
        $wrapper | Should -Match "DesktopArtifactPath"
    }

    It 'routes removal to the module-owned main installer action' {
        $wrapper | Should -Match "RemoveCompanionSuite"
        $main | Should -Match "Remove-WindowsCopilotCompanionSuite"
        $module | Should -Match "function Remove-WindowsCopilotCompanionSuite"
        $main.IndexOf("if (`$Action -eq 'RemoveCompanionSuite')") |
            Should -BeLessThan $main.IndexOf("if (`$Action -eq 'Rollback')")
        $main.IndexOf("if (`$Action -eq 'RemoveCompanionSuite')") |
            Should -BeLessThan $main.IndexOf("if (-not `$NpmGlobalRoot)")
    }

    It 'keeps exactly one required Copilot member and two optional overlays' {
        @($lock.companionSuite.members).Count | Should -Be 3
        $required = @($lock.companionSuite.members | Where-Object requiredByBaseDeployment)
        $optional = @($lock.companionSuite.members | Where-Object {
            -not $_.requiredByBaseDeployment
        })
        @($required.name) | Should -Be @('dsh-github-copilot')
        @($optional.name | Sort-Object) | Should -Be @(
            'dsh-cron',
            'dsh-playwright-host'
        )
    }

    It 'removes only optional member names and snapshots required Copilot state' {
        $module | Should -Match "Get-WindowsCopilotCompanionOverlays"
        $module | Should -Match "requiredTarget"
        $module | Should -Match "beforeCoherence"
        $module | Should -Match "afterCoherence"
        $module | Should -Match "Restore-DeploymentSnapshots"
    }

    It 'uses the same global deployment mutex for wrapper mutations' {
        $module | Should -Match "Global\\DshWindowsOpsDeployment"
        $module | Should -Match "Enter-WindowsCopilotDeploymentLock"
        $module | Should -Match "Exit-WindowsCopilotDeploymentLock"
    }

    It 'removes only optional overlays and preserves required Copilot bytes' {
        $dshHome = Join-Path $TestDrive 'remove-success'
        $fixture = Initialize-RemovalFixture -DshHome $dshHome
        $officialTarget = Join-Path $TestDrive 'official-target'
        $wrongTarget = Join-Path $TestDrive 'wrong-target'
        $officialLink = Join-Path $fixture.nodeModules '@deepseek-ai\official-fixture'
        New-Item -ItemType Directory -Path $officialTarget, $wrongTarget,
            (Split-Path -Parent $officialLink) -Force | Out-Null
        New-Item -ItemType Junction -Path $officialLink -Target $officialTarget |
            Out-Null
        Mock Test-WindowsCopilotProfileCoherence {
            [pscustomobject]@{ valid = $true }
        } -ModuleName WindowsCopilotDeployment
        Mock Invoke-PinnedPnpmCommands {
            [IO.Directory]::Delete($officialLink, $false)
            New-Item -ItemType Junction -Path $officialLink -Target $wrongTarget |
                Out-Null
        } -ModuleName WindowsCopilotDeployment
        Mock Get-WindowsCopilotInternalPluginStates {
            @([pscustomobject]@{
                name = '@deepseek-ai/official-fixture'
                path = $officialLink
                expectedTarget = $officialTarget
                valid = $true
            })
        } -ModuleName WindowsCopilotDeployment

        $result = Remove-WindowsCopilotCompanionSuite -Lock $lock -DshHome $dshHome `
            -BackupRoot (Join-Path $TestDrive 'backups')
        $profile = Get-Content -LiteralPath (
            Join-Path $fixture.profileRoot 'package.json'
        ) -Raw | ConvertFrom-Json

        $result.mode | Should -Be 'remove-companion-suite'
        $profile.dependencies.PSObject.Properties.Name | Should -Contain $fixture.required
        @($profile.dsh.profile.bundles) | Should -Contain $fixture.required
        (Get-Content -LiteralPath (
            Join-Path $fixture.nodeModules "$($fixture.required)\payload.txt"
        ) -Raw).Trim() | Should -BeExactly $fixture.required
        [IO.Path]::GetFullPath([string]@(
            (Get-Item -LiteralPath $officialLink -Force).Target
        )[0]) | Should -Be ([IO.Path]::GetFullPath($officialTarget))
        foreach ($name in $fixture.optional) {
            $profile.dependencies.PSObject.Properties.Name | Should -Not -Contain $name
            @($profile.dsh.profile.bundles) | Should -Not -Contain $name
            Test-Path -LiteralPath (Join-Path $fixture.nodeModules $name) |
                Should -BeFalse
        }
        foreach ($name in $fixture.officialLinks.Keys) {
            $item = Get-Item -LiteralPath (Join-Path $fixture.nodeModules $name)
            [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint) |
                Should -BeTrue
            [IO.Path]::GetFullPath([string]@($item.Target)[0]) |
                Should -BeExactly $fixture.officialLinks[$name]
        }
    }

    It 'restores the complete profile when optional removal fails' {
        $dshHome = Join-Path $TestDrive 'remove-rollback'
        $fixture = Initialize-RemovalFixture -DshHome $dshHome
        $packagePath = Join-Path $fixture.profileRoot 'package.json'
        $before = Get-Content -LiteralPath $packagePath -Raw
        Mock Test-WindowsCopilotProfileCoherence {
            [pscustomobject]@{ valid = $true }
        } -ModuleName WindowsCopilotDeployment
        Mock Invoke-PinnedPnpmCommands {
            throw 'fixture package-manager failure'
        } -ModuleName WindowsCopilotDeployment
        Mock Get-WindowsCopilotInternalPluginStates {
            @()
        } -ModuleName WindowsCopilotDeployment

        {
            Remove-WindowsCopilotCompanionSuite -Lock $lock -DshHome $dshHome `
                -BackupRoot (Join-Path $TestDrive 'rollback-backups')
        } | Should -Throw '*fixture package-manager failure*'

        (Get-Content -LiteralPath $packagePath -Raw) | Should -BeExactly $before
        foreach ($name in @($fixture.required) + $fixture.optional) {
            (Get-Content -LiteralPath (
                Join-Path $fixture.nodeModules "$name\payload.txt"
            ) -Raw).Trim() | Should -BeExactly $name
        }
    }
}
