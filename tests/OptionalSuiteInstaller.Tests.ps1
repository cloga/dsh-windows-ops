Describe 'Optional companion suite compatibility wrapper' {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $wrapperPath = Join-Path $repoRoot 'tools\install-optional-companion-suite.ps1'
        $modulePath = Join-Path $repoRoot 'tools\WindowsCopilotDeployment.psm1'
        $lockPath = Join-Path $repoRoot 'deployments\windows-copilot.lock.json'
        $wrapper = Get-Content -LiteralPath $wrapperPath -Raw
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

    It 'routes Check Apply and Verify through authoritative plugin-only module functions' {
        $wrapper | Should -Match "Get-WindowsCopilotCompanionSuitePlan"
        $wrapper | Should -Match "Test-WindowsCopilotCompanionSuite"
        $wrapper | Should -Match "Invoke-WindowsCopilotCompanionSuiteApply"
        $wrapper | Should -Match "CopilotIntegrationArtifactPath"
        $wrapper | Should -Match "ArtifactDirectory"
        $wrapper | Should -Not -Match "DesktopArtifactPath|NpmGlobalRoot|RestartDesktop"
    }

    It 'routes removal directly to the module-owned plugin-only action' {
        $wrapper | Should -Match "Remove-WindowsCopilotCompanionSuite"
        $module | Should -Match "function Remove-WindowsCopilotCompanionSuite"
    }

    It 'checks Core Cordis and required plugin APIs without checking Desktop version' {
        $runtimeRoot = Join-Path $TestDrive 'compatible-runtime'
        $compatibility = $lock.companionSuite.compatibility
        foreach ($component in @($compatibility.core, $compatibility.cordis)) {
            $path = Join-Path $runtimeRoot ([string]$component.manifest)
            New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force |
                Out-Null
            [ordered]@{
                name = [string]$component.name
                version = if ([string]$component.name -eq '@deepseek-ai/dsh') {
                    [string]$component.versions[0]
                } else {
                    '4.0.2'
                }
            } | ConvertTo-Json | Set-Content -LiteralPath $path -Encoding UTF8
        }
        foreach ($api in @($compatibility.requiredPluginApis)) {
            $path = Join-Path $runtimeRoot ([string]$api.manifest)
            New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force |
                Out-Null
            '{"name":"fixture-api","version":"1.0.0"}' |
                Set-Content -LiteralPath $path -Encoding UTF8
        }

        $result = Test-WindowsCopilotCompanionCompatibility -Lock $lock `
            -RuntimeRoot $runtimeRoot

        $result.valid | Should -BeTrue
        $result.core.version | Should -Be '0.1.2-rc.1'
        $result.cordis.version | Should -Be '4.0.2'
        $result.desktopVersionChecked | Should -BeFalse
    }

    It 'fails closed for unsupported Core and missing plugin APIs' {
        $runtimeRoot = Join-Path $TestDrive 'unsupported-runtime'
        $compatibility = $lock.companionSuite.compatibility
        foreach ($component in @($compatibility.core, $compatibility.cordis)) {
            $path = Join-Path $runtimeRoot ([string]$component.manifest)
            New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force |
                Out-Null
            [ordered]@{
                name = [string]$component.name
                version = if ([string]$component.name -eq '@deepseek-ai/dsh') {
                    '9.9.9'
                } else {
                    '4.0.2'
                }
            } | ConvertTo-Json | Set-Content -LiteralPath $path -Encoding UTF8
        }

        $result = Test-WindowsCopilotCompanionCompatibility -Lock $lock `
            -RuntimeRoot $runtimeRoot

        $result.valid | Should -BeFalse
        $result.status | Should -Be 'unsupported-core-or-plugin-api'
        @($result.reasons) | Should -Contain 'core-version-unsupported'
        @($result.reasons | Where-Object { $_ -like 'plugin-api-*-missing' }).Count |
            Should -Be 4
    }

    It 'evaluates plugin peer ranges with SemVer prerelease rules and fails unknown syntax' {
        InModuleScope WindowsCopilotDeployment {
            Test-WindowsCopilotSemVerRange -Version '0.1.2-rc.1' `
                -Range '0.1.1-rc.2 || 0.1.2-rc.1' | Should -BeTrue
            Test-WindowsCopilotSemVerRange -Version '0.1.2-rc.1' `
                -Range '>=0.1.1-rc.2 <0.1.2-0 || >=0.1.2-alpha.4 <0.1.2' |
                Should -BeTrue
            Test-WindowsCopilotSemVerRange -Version '0.1.2-beta.1' `
                -Range '>=0.1.1 <0.2.0' | Should -BeFalse
            Test-WindowsCopilotSemVerRange -Version '4.0.2' -Range '^4.0.1' |
                Should -BeTrue
            Test-WindowsCopilotSemVerRange -Version '5.0.0' -Range '^4.0.1' |
                Should -BeFalse
            {
                Test-WindowsCopilotSemVerRange -Version '0.1.2-rc.1' `
                    -Range 'workspace:*'
            } | Should -Throw '*Unsupported SemVer range syntax*'
        }
    }

    It 'loads companion entrypoints through the preserved Profile and runtime resolution' {
        $profileRoot = Join-Path $TestDrive 'import-home\profiles\web'
        $runtimeRoot = Join-Path $TestDrive 'import-runtime'
        New-Item -ItemType Directory -Path $profileRoot, $runtimeRoot `
            -Force | Out-Null
        '{}' | Set-Content -LiteralPath (Join-Path $profileRoot 'package.json') `
            -Encoding UTF8
        '{}' | Set-Content -LiteralPath (Join-Path $runtimeRoot 'package.json') `
            -Encoding UTF8
        foreach ($package in @(
            @{
                Root = $profileRoot
                Name = 'dsh-github-copilot'
            },
            @{
                Root = $profileRoot
                Name = 'dsh-cron'
            },
            @{
                Root = $runtimeRoot
                Name = '@deepseek-ai\dsh-mcp-client'
            }
        )) {
            $target = Join-Path $package.Root "node_modules\$($package.Name)"
            New-Item -ItemType Directory -Path $target -Force | Out-Null
            '{"type":"module","main":"index.js"}' | Set-Content -LiteralPath (
                Join-Path $target 'package.json'
            ) -Encoding UTF8
            'export default true;' | Set-Content -LiteralPath (
                Join-Path $target 'index.js'
            ) -Encoding UTF8
        }
        $loaderRoot = Join-Path $runtimeRoot (
            'node_modules\@deepseek-ai\dsh'
        )
        New-Item -ItemType Directory -Path (Join-Path $loaderRoot 'lib') `
            -Force | Out-Null
        '{"type":"module"}' | Set-Content -LiteralPath (
            Join-Path $loaderRoot 'package.json'
        ) -Encoding UTF8
        @'
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import path from 'node:path';
const manifest = path.join(
  process.env.DSH_HOME, 'profiles', 'web', 'package.json'
);
const profile = createRequire(pathToFileURL(manifest));
for (const id of ['dsh-github-copilot', 'dsh-cron']) {
  await import(pathToFileURL(profile.resolve(id)).href);
}
'@ | Set-Content -LiteralPath (Join-Path $loaderRoot 'lib\bin.js') `
            -Encoding UTF8

        InModuleScope WindowsCopilotDeployment -Parameters @{
            FixtureProfile = $profileRoot
            FixtureRuntime = $runtimeRoot
        } {
            $result = Test-WindowsCopilotCompanionImports `
                -ProfileRoot $FixtureProfile -RuntimeRoot $FixtureRuntime
            $result.valid | Should -BeTrue
            $result.status | Should -BeExactly 'managed-loader-verified'
        }
    }

    It 'keeps the plugin transaction free of Desktop Core global and restart mutations' {
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseInput(
            $module,
            [ref]$tokens,
            [ref]$errors
        )
        $errors.Count | Should -Be 0
        $apply = @($ast.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Invoke-WindowsCopilotCompanionSuiteApplyLocked'
        }, $true))[0].Extent.Text
        $apply | Should -Not -Match 'Start-Process|Stop-WindowsCopilot|npm.+--global|legacyGateway'
        $apply | Should -Match 'Test-WindowsCopilotCompanionCompatibility'
        $apply | Should -Match 'Test-WindowsCopilotCompanionArtifactCompatibility'
        $apply | Should -Match 'Restore-DeploymentSnapshots'
        $apply | Should -Match 'officialSnapshots'
        $apply | Should -Match 'Install-WindowsCopilotLockedPackage'
        $apply | Should -Match 'Save-WindowsCopilotReleaseArtifact'
        $materializer = @($ast.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Install-WindowsCopilotLockedPackage'
        }, $true))[0].Extent.Text
        $materializer | Should -Match 'Test-WindowsCopilotInstalledArtifactClosure'
    }

    It 'restores the complete Profile when plugin-only package installation fails' {
        $dshHome = Join-Path $TestDrive 'apply-rollback'
        $profileRoot = Join-Path $dshHome ([string]$lock.profile.relativePath)
        $nodeModules = Join-Path $profileRoot 'node_modules'
        New-Item -ItemType Directory -Path $nodeModules -Force | Out-Null
        $profilePath = Join-Path $profileRoot 'package.json'
        $workspacePath = Join-Path $profileRoot 'pnpm-workspace.yaml'
        $lockfilePath = Join-Path $profileRoot 'pnpm-lock.yaml'
        $settingsPath = Join-Path $dshHome 'settings.yaml'
        '{"name":"fixture","dependencies":{"unrelated":"1.0.0"},"dsh":{"profile":{"bundles":["unrelated"]}}}' |
            Set-Content -LiteralPath $profilePath -Encoding UTF8
        "packages:`n  - ." | Set-Content -LiteralPath $workspacePath -Encoding UTF8
        "lockfileVersion: '9.0'" | Set-Content -LiteralPath $lockfilePath -Encoding UTF8
        'preserve: true' | Set-Content -LiteralPath $settingsPath -Encoding UTF8
        New-Item -ItemType Directory -Path (
            Join-Path $nodeModules 'unrelated'
        ) -Force | Out-Null
        'original unrelated bytes' | Set-Content -LiteralPath (
            Join-Path $nodeModules 'unrelated\payload.txt'
        )
        $beforeProfile = Get-Content -LiteralPath $profilePath -Raw
        $beforeWorkspace = Get-Content -LiteralPath $workspacePath -Raw
        $officialTargets = @{}
        foreach ($name in @($lock.components.desktop.internalPlugins.name)) {
            $source = Join-Path $dshHome "desktop-resources\$name"
            $target = Join-Path $nodeModules $name
            New-Item -ItemType Directory -Path $source -Force | Out-Null
            New-Item -ItemType Junction -Path $target -Target $source | Out-Null
            $officialTargets[$name] = [IO.Path]::GetFullPath($source)
        }

        InModuleScope WindowsCopilotDeployment -Parameters @{
            FixtureLock = $lock
            FixtureHome = $dshHome
            FixtureBackup = (Join-Path $TestDrive 'apply-backups')
        } {
            Mock Test-WindowsCopilotLock {}
            Mock Test-WindowsCopilotCompanionCompatibility {
                [pscustomobject]@{
                    valid = $true
                    runtimeRoot = (Join-Path $FixtureHome 'runtime')
                    reasons = @()
                }
            }
            Mock Save-WindowsCopilotReleaseArtifact {
                New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) `
                    -Force | Out-Null
                'fixture artifact' | Set-Content -LiteralPath $Destination
                'fixture checksum' | Set-Content -LiteralPath (
                    Join-Path (Split-Path -Parent $Destination) 'SHA256SUMS'
                )
                [pscustomobject]@{ path = $Destination; valid = $true }
            }
            Mock Test-CopilotIntegrationDeploymentContract {
                [pscustomobject]@{ valid = $true }
            }
            Mock Test-WindowsCopilotCompanionArtifactCompatibility {
                [pscustomobject]@{ valid = $true; plugins = @() }
            }
            Mock Get-WindowsCopilotLiveSessions { @() }
            Mock Invoke-PinnedPnpmCommands {
                $changed = Join-Path $FixtureHome (
                    'profiles\web\node_modules\unrelated\payload.txt'
                )
                New-Item -ItemType Directory -Path (Split-Path -Parent $changed) `
                    -Force | Out-Null
                'changed by pnpm' | Set-Content -LiteralPath $changed
                throw 'fixture package-manager failure'
            }

            {
                Invoke-WindowsCopilotCompanionSuiteApplyLocked -Lock $FixtureLock `
                    -DshHome $FixtureHome -BackupRoot $FixtureBackup
            } | Should -Throw '*fixture package-manager failure*'
        }

        (Get-Content -LiteralPath $profilePath -Raw) | Should -BeExactly $beforeProfile
        (Get-Content -LiteralPath $workspacePath -Raw) | Should -BeExactly $beforeWorkspace
        (Get-Content -LiteralPath $settingsPath -Raw).Trim() |
            Should -BeExactly 'preserve: true'
        foreach ($name in $officialTargets.Keys) {
            $item = Get-Item -LiteralPath (Join-Path $nodeModules $name) -Force
            [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint) |
                Should -BeTrue
            [IO.Path]::GetFullPath([string]@($item.Target)[0]) |
                Should -BeExactly $officialTargets[$name]
        }
        Test-Path -LiteralPath (Join-Path $nodeModules 'unrelated') |
            Should -BeTrue
        (Get-Content -LiteralPath (
            Join-Path $nodeModules 'unrelated\payload.txt'
        ) -Raw).Trim() | Should -BeExactly 'original unrelated bytes'
    }

    It 'does not overwrite an external Profile edit when artifact staging fails' {
        $dshHome = Join-Path $TestDrive 'download-failure'
        $profileRoot = Join-Path $dshHome ([string]$lock.profile.relativePath)
        New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null
        $profilePath = Join-Path $profileRoot 'package.json'
        '{"name":"before-download"}' |
            Set-Content -LiteralPath $profilePath -Encoding UTF8
        $backupRoot = Join-Path $TestDrive 'download-failure-backups'

        InModuleScope WindowsCopilotDeployment -Parameters @{
            FixtureLock = $lock
            FixtureHome = $dshHome
            FixtureProfile = $profilePath
            FixtureBackup = $backupRoot
        } {
            Mock Test-WindowsCopilotLock {}
            Mock Test-WindowsCopilotCompanionCompatibility {
                [pscustomobject]@{
                    valid = $true
                    runtimeRoot = (Join-Path $FixtureHome 'runtime')
                    reasons = @()
                }
            }
            Mock Save-WindowsCopilotReleaseArtifact {
                '{"name":"external-edit"}' |
                    Set-Content -LiteralPath $FixtureProfile -Encoding UTF8
                throw 'fixture download failure'
            }

            {
                Invoke-WindowsCopilotCompanionSuiteApplyLocked -Lock $FixtureLock `
                    -DshHome $FixtureHome -BackupRoot $FixtureBackup
            } | Should -Throw '*fixture download failure*'
        }

        (Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json).name |
            Should -BeExactly 'external-edit'
        Test-Path -LiteralPath $backupRoot | Should -BeFalse
    }

    It 'places and activates all three reviewed companions without replacing unrelated packages' {
        $dshHome = Join-Path $TestDrive 'apply-success'
        $profileRoot = Join-Path $dshHome ([string]$lock.profile.relativePath)
        $nodeModules = Join-Path $profileRoot 'node_modules'
        New-Item -ItemType Directory -Path $nodeModules -Force | Out-Null
        $profilePath = Join-Path $profileRoot 'package.json'
        '{"name":"fixture","dependencies":{"unrelated":"1.0.0"},"dsh":{"profile":{"bundles":["unrelated"]}}}' |
            Set-Content -LiteralPath $profilePath -Encoding UTF8
        "packages:`n  - ." | Set-Content -LiteralPath (
            Join-Path $profileRoot 'pnpm-workspace.yaml'
        ) -Encoding UTF8
        "lockfileVersion: '9.0'" | Set-Content -LiteralPath (
            Join-Path $profileRoot 'pnpm-lock.yaml'
        ) -Encoding UTF8
        New-Item -ItemType Directory -Path (
            Join-Path $nodeModules 'unrelated'
        ) -Force | Out-Null
        'preserved' | Set-Content -LiteralPath (
            Join-Path $nodeModules 'unrelated\payload.txt'
        )
        foreach ($name in @($lock.components.desktop.internalPlugins.name)) {
            $source = Join-Path $dshHome "desktop-resources\$name"
            New-Item -ItemType Directory -Path $source -Force | Out-Null
            New-Item -ItemType Junction -Path (Join-Path $nodeModules $name) `
                -Target $source | Out-Null
        }

        InModuleScope WindowsCopilotDeployment -Parameters @{
            FixtureLock = $lock
            FixtureHome = $dshHome
            FixtureBackup = (Join-Path $TestDrive 'apply-success-backups')
        } {
            Mock Test-WindowsCopilotLock {}
            Mock Test-WindowsCopilotCompanionCompatibility {
                [pscustomobject]@{
                    valid = $true
                    runtimeRoot = (Join-Path $FixtureHome 'runtime')
                    reasons = @()
                }
            }
            Mock Save-WindowsCopilotReleaseArtifact {
                New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) `
                    -Force | Out-Null
                'fixture artifact' | Set-Content -LiteralPath $Destination
                'fixture checksum' | Set-Content -LiteralPath (
                    Join-Path (Split-Path -Parent $Destination) 'SHA256SUMS'
                )
                [pscustomobject]@{ path = $Destination; valid = $true }
            }
            Mock Test-CopilotIntegrationDeploymentContract {
                [pscustomobject]@{ valid = $true }
            }
            Mock Test-WindowsCopilotCompanionArtifactCompatibility {
                [pscustomobject]@{ valid = $true; plugins = @() }
            }
            Mock Get-WindowsCopilotLiveSessions {
                @([pscustomobject]@{
                    sessionId = 'session-approved'
                    title = 'fixture session'
                })
            }
            Mock Invoke-PinnedPnpmCommands {}
            Mock Install-WindowsCopilotLockedPackage {
                New-Item -ItemType Directory -Path $Target -Force | Out-Null
                [ordered]@{ name = $Name; version = $Version } |
                    ConvertTo-Json | Set-Content -LiteralPath (
                        Join-Path $Target 'package.json'
                    ) -Encoding UTF8
                [pscustomobject]@{
                    name = $Name
                    version = $Version
                    artifactPath = $ArtifactPath
                    artifactSha256 = 'fixture'
                    physical = $true
                    closure = [pscustomobject]@{ valid = $true }
                }
            }
            Mock Test-WindowsCopilotInstalledArtifactClosure {
                [pscustomobject]@{ valid = $true }
            }
            Mock Test-WindowsCopilotCompanionImports {
                [pscustomobject]@{
                    valid = $true
                    status = 'imported'
                    failure = $null
                }
            }

            Invoke-WindowsCopilotCompanionSuiteApplyLocked -Lock $FixtureLock `
                -DshHome $FixtureHome -BackupRoot $FixtureBackup `
                -AcknowledgeLiveSessionIds 'session-approved' | Out-Null
            Should -Invoke Test-WindowsCopilotCompanionImports -Times 1
        }

        $profile = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
        foreach ($name in @(
            'dsh-github-copilot',
            'dsh-cron',
            'dsh-playwright-host'
        )) {
            [string]$profile.dependencies.$name | Should -Not -BeNullOrEmpty
            @($profile.dsh.profile.bundles) | Should -Contain $name
            Test-Path -LiteralPath (Join-Path $nodeModules "$name\package.json") |
                Should -BeTrue
        }
        (Get-Content -LiteralPath (
            Join-Path $nodeModules 'unrelated\payload.txt'
        ) -Raw).Trim() | Should -BeExactly 'preserved'
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
