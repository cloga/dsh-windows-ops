# Synthetic metadata/process mocks only; no installed runtime or CLI is executed.
Describe 'Optional Web physical-runtime boundary for ASAR Desktop' {
    BeforeAll {
        $repo = Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $repo 'tools\WindowsCopilotDeployment.psm1') -Force
        $baseline = Get-Content (Join-Path $repo 'deployments\windows-copilot.lock.json') -Raw | ConvertFrom-Json
        function New-OptionalAsarLock {
            param([string]$Root)
            $copy = $baseline | ConvertTo-Json -Depth 100 | ConvertFrom-Json
            $copy.components.desktop.runtimeSelectors[0].root = Join-Path $Root 'resources\app.asar\dsh'
            $copy.components.desktop.installedRuntimeDescriptor.relativePath = 'resources\app.asar\dsh\desktop-runtime.json'
            return $copy
        }
        function New-PhysicalOptionalFixture {
            param($Lock, [string]$Root, [string]$Version)
            foreach ($component in @($Lock.companionSuite.compatibility.core, $Lock.companionSuite.compatibility.cordis)) {
                $path = Join-Path $Root $component.manifest
                New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
                @{ name = $component.name; version = $(if ($component.name -eq '@deepseek-ai/dsh') { $Version } else { '4.0.2' }) } |
                    ConvertTo-Json | Set-Content -LiteralPath $path -Encoding UTF8
            }
            foreach ($api in $Lock.companionSuite.compatibility.requiredPluginApis) {
                $path = Join-Path $Root $api.manifest
                New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
                @{ name = 'synthetic-api'; version = $Version } | ConvertTo-Json | Set-Content -LiteralPath $path -Encoding UTF8
            }
        }
    }

    It 'rejects omitted or explicit archive roots before artifacts imports mutex or mutations' -TestCases @(
        @{ Root = $null }, @{ Root = 'C:\synthetic\resources\app.asar\dsh' },
        @{ Root = 'C:/synthetic/resources/APP.ASAR/dsh' }, @{ Root = 'C:\synthetic\custom.asar' }
    ) {
        param($Root)
        $lock = New-OptionalAsarLock (Join-Path $TestDrive 'desktop')
        InModuleScope WindowsCopilotDeployment -Parameters @{ L = $lock; R = $Root; H = (Join-Path $TestDrive 'absent-home'); B = (Join-Path $TestDrive 'absent-backup') } {
            Mock Test-WindowsCopilotLock {}
            Mock Test-Path { throw 'virtual fs forbidden' } -ParameterFilter { $LiteralPath -match '\.asar([\\/]|$)' }
            Mock Get-Content { throw 'content forbidden' }
            Mock Read-TarJson { throw 'artifact parser forbidden' }
            Mock Test-LockedArtifact { throw 'artifact check forbidden' }
            Mock Save-WindowsCopilotReleaseArtifact { throw 'download forbidden' }
            Mock Test-WindowsCopilotCompanionImports { throw 'import forbidden' }
            Mock Enter-WindowsCopilotDeploymentLock { throw 'mutex forbidden' }
            Mock Invoke-WindowsCopilotCompanionSuiteApplyLocked { throw 'mutation forbidden' }
            $compat = Test-WindowsCopilotCompanionCompatibility -Lock $L -RuntimeRoot $R
            $compat.valid | Should -BeFalse
            $compat.status | Should -BeExactly 'physical-web-runtime-required'
            $compat.scope | Should -BeExactly 'optional-web-only'
            $plan = Get-WindowsCopilotCompanionSuitePlan -Lock $L -DshHome $H -RuntimeRoot $R
            $plan.compatible | Should -BeFalse
            $plan.changesSystem | Should -BeFalse
            $state = Test-WindowsCopilotCompanionSuite -Lock $L -DshHome $H -RuntimeRoot $R -ArtifactDirectory 'C:\inert-artifacts'
            $state.valid | Should -BeFalse
            $state.status | Should -BeExactly 'physical-web-runtime-required'
            $state.imports.status | Should -BeExactly 'not-run'
            { Invoke-WindowsCopilotCompanionSuiteApply -Lock $L -DshHome $H -BackupRoot $B -RuntimeRoot $R } |
                Should -Throw '*physical-web-runtime-required*'
            Should -Invoke Test-Path -Times 0 -Exactly -ParameterFilter { $LiteralPath -match '\.asar([\\/]|$)' }
            foreach ($name in @('Get-Content', 'Read-TarJson', 'Test-LockedArtifact', 'Save-WindowsCopilotReleaseArtifact',
                'Test-WindowsCopilotCompanionImports', 'Enter-WindowsCopilotDeploymentLock', 'Invoke-WindowsCopilotCompanionSuiteApplyLocked')) {
                Should -Invoke $name -Times 0 -Exactly
            }
            Test-Path -LiteralPath $B | Should -BeFalse
        }
    }

    It 'rejects a mixed selector fallback when the locked descriptor already selects ASAR' {
        $lock = New-OptionalAsarLock (Join-Path $TestDrive 'desktop')
        $lock.components.desktop.runtimeSelectors[0].root = Join-Path $TestDrive 'old-physical-default'
        InModuleScope WindowsCopilotDeployment -Parameters @{ L = $lock } {
            Mock Test-WindowsCopilotLock {}
            Mock Get-Content { throw 'no physical fallback' }
            (Test-WindowsCopilotCompanionCompatibility -Lock $L).status | Should -BeExactly 'physical-web-runtime-required'
            Should -Invoke Get-Content -Times 0 -Exactly
        }
    }

    It 'expands an explicit archive environment path before any filesystem or Node lookup' {
        $previous = $env:DSH_SYNTHETIC_OPTIONAL_ROOT
        $env:DSH_SYNTHETIC_OPTIONAL_ROOT = 'C:\synthetic\app.asar\dsh'
        try {
            InModuleScope WindowsCopilotDeployment -Parameters @{ L = $baseline } {
                Mock Test-WindowsCopilotLock {}
                Mock Get-Command { throw 'node lookup forbidden' }
                Mock Resolve-DeploymentPath { throw 'physical probe forbidden' }
                (Test-WindowsCopilotCompanionCompatibility -Lock $L -RuntimeRoot '%DSH_SYNTHETIC_OPTIONAL_ROOT%').status |
                    Should -BeExactly 'physical-web-runtime-required'
                (Test-WindowsCopilotCompanionImports -ProfileRoot 'C:\inert-profile' -RuntimeRoot '%DSH_SYNTHETIC_OPTIONAL_ROOT%').status |
                    Should -BeExactly 'physical-web-runtime-required'
                Should -Invoke Get-Command -Times 0 -Exactly
                Should -Invoke Resolve-DeploymentPath -Times 0 -Exactly
            }
        } finally {
            if ($null -eq $previous) { Remove-Item Env:DSH_SYNTHETIC_OPTIONAL_ROOT -ErrorAction SilentlyContinue }
            else { $env:DSH_SYNTHETIC_OPTIONAL_ROOT = $previous }
        }
    }

    It 'rejects direct artifact and import helpers for ASAR without parsing or spawning' {
        InModuleScope WindowsCopilotDeployment -Parameters @{ L = $baseline } {
            Mock Read-TarJson { throw 'parser forbidden' }
            Mock Get-Command { throw 'node lookup forbidden' }
            Mock Start-Process { throw 'spawn forbidden' }
            Mock Resolve-DeploymentPath { throw 'virtual physical resolution forbidden' }
            $member = [pscustomobject]@{ name = 'inert'; version = '1.0.0'; artifactPath = 'C:\inert.tgz' }
            (Test-WindowsCopilotCompanionArtifactCompatibility -Lock $L -Members @($member) -RuntimeRoot 'C:\inert\app.asar\dsh').status |
                Should -BeExactly 'physical-web-runtime-required'
            (Test-WindowsCopilotCompanionImports -ProfileRoot 'C:\inert-profile' -RuntimeRoot 'C:\inert\app.asar\dsh').status |
                Should -BeExactly 'physical-web-runtime-required'
            foreach ($name in @('Read-TarJson', 'Get-Command', 'Start-Process', 'Resolve-DeploymentPath')) { Should -Invoke $name -Times 0 -Exactly }
        }
    }

    It 'requires an existing ordinary physical override for an ASAR default' {
        $lock = New-OptionalAsarLock (Join-Path $TestDrive 'desktop')
        InModuleScope WindowsCopilotDeployment -Parameters @{ L = $lock; R = (Join-Path $TestDrive 'absent-web') } {
            Mock Test-WindowsCopilotLock {}
            Mock Get-Content { throw 'not an existing runtime' }
            $state = Test-WindowsCopilotCompanionCompatibility -Lock $L -RuntimeRoot $R
            $state.status | Should -BeExactly 'physical-web-runtime-required'
            $state.reasons | Should -Contain 'explicit-physical-web-runtime-unavailable-or-reparse'
            Should -Invoke Get-Content -Times 0 -Exactly
        }
    }

    It 'retains supported version and all API checks for explicit physical Web fixtures' {
        foreach ($version in @($baseline.companionSuite.compatibility.core.versions)) {
            $lock = New-OptionalAsarLock (Join-Path $TestDrive 'desktop')
            $root = Join-Path $TestDrive ('physical-' + $version)
            New-PhysicalOptionalFixture $lock $root $version
            InModuleScope WindowsCopilotDeployment -Parameters @{ L = $lock; R = $root; V = $version } {
                Mock Test-WindowsCopilotLock {}
                $state = Test-WindowsCopilotCompanionCompatibility -Lock $L -RuntimeRoot $R
                $state.valid | Should -BeTrue
                $state.scope | Should -BeExactly 'explicit-physical-web-runtime'
                $state.core.version | Should -BeExactly $V
                $state.pluginApis.Count | Should -Be $L.companionSuite.compatibility.requiredPluginApis.Count
                $state.desktopVersionChecked | Should -BeFalse
            }
        }
    }

    It 'still rejects unsupported physical versions before the public Apply mutex' {
        $lock = New-OptionalAsarLock (Join-Path $TestDrive 'desktop')
        $root = Join-Path $TestDrive 'wrong-version'
        New-PhysicalOptionalFixture $lock $root '9.9.9'
        InModuleScope WindowsCopilotDeployment -Parameters @{ L = $lock; R = $root; H = $TestDrive } {
            Mock Test-WindowsCopilotLock {}
            Mock Enter-WindowsCopilotDeploymentLock { throw 'mutex forbidden' }
            $state = Test-WindowsCopilotCompanionCompatibility -Lock $L -RuntimeRoot $R
            $state.valid | Should -BeFalse
            $state.reasons | Should -Contain 'core-version-unsupported'
            { Invoke-WindowsCopilotCompanionSuiteApply -Lock $L -DshHome $H -RuntimeRoot $R -BackupRoot (Join-Path $H 'unused') } | Should -Throw '*supported Core*'
            Should -Invoke Enter-WindowsCopilotDeploymentLock -Times 0 -Exactly
        }
    }

    It 'retains required API and artifact peer rejection for physical roots' {
        $lock = New-OptionalAsarLock (Join-Path $TestDrive 'desktop')
        $root = Join-Path $TestDrive 'physical-peer-check'
        New-PhysicalOptionalFixture $lock $root ([string]$lock.companionSuite.compatibility.core.versions[0])
        Remove-Item -LiteralPath (Join-Path $root $lock.companionSuite.compatibility.requiredPluginApis[0].manifest)
        InModuleScope WindowsCopilotDeployment -Parameters @{ L = $lock; R = $root } {
            Mock Test-WindowsCopilotLock {}
            (Test-WindowsCopilotCompanionCompatibility -Lock $L -RuntimeRoot $R).valid | Should -BeFalse
            Mock Read-TarJson { [pscustomobject]@{ name = 'inert-plugin'; version = '1.0.0'; peerDependencies = [pscustomobject]@{ '@deepseek-ai/cordis' = '^9.0.0' } } }
            $member = [pscustomobject]@{ name = 'inert-plugin'; version = '1.0.0'; artifactPath = 'C:\inert.tgz' }
            $state = Test-WindowsCopilotCompanionArtifactCompatibility -Lock $L -Members @($member) -RuntimeRoot $R
            $state.valid | Should -BeFalse
            $state.plugins[0].peerDependencies[0].status | Should -BeExactly 'range-mismatch'
        }
    }

    It 'keeps the physical import protocol with a mocked process, not an ASAR CLI substitute' {
        $root = Join-Path $TestDrive 'physical-import'
        $anchor = Join-Path $root 'node_modules\@deepseek-ai\dsh-app-boot\package.json'
        New-Item -ItemType Directory -Path (Split-Path -Parent $anchor) -Force | Out-Null
        '{}' | Set-Content -LiteralPath $anchor
        InModuleScope WindowsCopilotDeployment -Parameters @{ R = $root; H = $TestDrive } {
            Mock Get-Command { [pscustomobject]@{ Source = 'C:\inert-tools\node.exe' } } -ParameterFilter { $Name -eq 'node' }
            Mock Start-Process {
                $text = Get-Content -LiteralPath $ArgumentList[0] -Raw
                $text | Should -Match 'createRequire'
                $text | Should -Match 'resolved outside expected package root'
                $text | Should -Not -Match 'resolution-mode|ELECTRON_RUN_AS_NODE'
                return [pscustomobject]@{ ExitCode = 0 }
            }
            $state = Test-WindowsCopilotCompanionImports -ProfileRoot (Join-Path $H 'inert-profile') -RuntimeRoot $R
            $state.status | Should -BeExactly 'entrypoints-imported'
            Should -Invoke Start-Process -Times 1 -Exactly
        }
    }

    It 'historical bootstrap rejects a native ASAR selector before target inspection' {
        $lock = New-OptionalAsarLock (Join-Path $TestDrive 'desktop')
        InModuleScope DshCopilotBootstrap -Parameters @{ L = $lock } {
            Mock Get-Content { throw 'target inspection forbidden' }
            Mock Test-DshRendererCompatibility { throw 'renderer probe forbidden' }
            $runtime = [pscustomobject]@{ valid = $true; selector = 'desktop-fork-managed'; mode = 'asar-runtime' }
            { Test-DshActiveDesktopCore -DeploymentLock $L -DesktopRuntimeState $runtime } | Should -Throw '*official Desktop-managed runtime*'
            Should -Invoke Get-Content -Times 0 -Exactly
            Should -Invoke Test-DshRendererCompatibility -Times 0 -Exactly
        }
    }

    It 'does not weaken the historical official-only bootstrap selector guard' {
        $source = Get-Content (Join-Path $repo 'tools\DshCopilotBootstrap.psm1') -Raw
        $source | Should -Match 'desktop-official'
        $source | Should -Match 'desktop-managed-download'
        $optional = Get-Content (Join-Path $repo 'tools\install-optional-companion-suite.ps1') -Raw
        $optional | Should -Match "Profile -cne 'web'"
        $optional | Should -Not -Match 'ELECTRON_RUN_AS_NODE|resolution-mode|dump-config'
        InModuleScope WindowsCopilotDeployment {
            Test-WindowsCopilotAsarPath 'C:\ordinary\app.asar.unpacked\dsh' | Should -BeFalse
            Test-WindowsCopilotAsarPath 'C:\ordinary\app.asar\dsh' | Should -BeTrue
        }
    }
}
