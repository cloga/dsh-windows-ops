BeforeAll {
    Import-Module (Join-Path (Split-Path $PSScriptRoot) 'tools\DshPresetConfig.psm1') -Force
}

Describe 'ASAR preset target validation fails closed before target access' {
    BeforeEach {
        $homePath = Join-Path $TestDrive ('home-' + [guid]::NewGuid())
        $targetBase = Join-Path $TestDrive ('target-' + [guid]::NewGuid())
        $presetDirectory = Join-Path $homePath '.agent-presets\sample'
        New-Item -ItemType Directory $presetDirectory -Force | Out-Null
        $manifest = Join-Path $presetDirectory 'agent.cordis.yml'
        # Inert bytes: the ASAR guard must not parse even an invalid manifest.
        'SECRET: [not parsed' | Set-Content -LiteralPath $manifest -NoNewline
        $beforeHash = (Get-FileHash -LiteralPath $manifest).Hash
        $contract = [pscustomobject]@{ root = (Join-Path $targetBase 'resources\app.asar\dsh') }

        Mock Get-PresetTargetFiles -ModuleName DshPresetConfig { throw 'TARGET WALK' }
        Mock Test-DshRuntimeSchemaState -ModuleName DshPresetConfig { throw 'RUNTIME SCHEMA' }
        # Node lookup is the mandatory precursor to Process.Start in this module.
        Mock Get-Command -ModuleName DshPresetConfig { throw 'NODE PROCESS' } -ParameterFilter { $Name -eq 'node.exe' }
        Mock Import-Module -ModuleName DshPresetConfig { throw 'TARGET IMPORT' }
        Mock Assert-PresetPhysicalPath -ModuleName DshPresetConfig { throw 'TARGET PHYSICAL WALK' } -ParameterFilter {
            $Path -like "$targetBase*"
        }
        Mock Test-Path -ModuleName DshPresetConfig { throw 'TARGET TEST PATH' } -ParameterFilter {
            $LiteralPath -like "$targetBase*"
        }
        Mock Get-Item -ModuleName DshPresetConfig { throw 'TARGET GET ITEM' } -ParameterFilter {
            $LiteralPath -like "$targetBase*"
        }
        Mock Get-ChildItem -ModuleName DshPresetConfig { throw 'TARGET ENUMERATION' } -ParameterFilter {
            $LiteralPath -like "$targetBase*"
        }
        Mock Get-Content -ModuleName DshPresetConfig { throw 'TARGET CONTENT' }
        Mock Get-FileHash -ModuleName DshPresetConfig { throw 'TARGET HASH' } -ParameterFilter {
            $LiteralPath -like "$targetBase*"
        }
    }

    AfterEach {
        Should -Invoke Get-PresetTargetFiles -ModuleName DshPresetConfig -Times 0 -Exactly
        Should -Invoke Test-DshRuntimeSchemaState -ModuleName DshPresetConfig -Times 0 -Exactly
        Should -Invoke Get-Command -ModuleName DshPresetConfig -Times 0 -Exactly -ParameterFilter { $Name -eq 'node.exe' }
        Should -Invoke Import-Module -ModuleName DshPresetConfig -Times 0 -Exactly
        Should -Invoke Assert-PresetPhysicalPath -ModuleName DshPresetConfig -Times 0 -Exactly -ParameterFilter {
            $Path -like "$targetBase*"
        }
        Should -Invoke Test-Path -ModuleName DshPresetConfig -Times 0 -Exactly -ParameterFilter {
            $LiteralPath -like "$targetBase*"
        }
        Should -Invoke Get-Item -ModuleName DshPresetConfig -Times 0 -Exactly -ParameterFilter {
            $LiteralPath -like "$targetBase*"
        }
        Should -Invoke Get-ChildItem -ModuleName DshPresetConfig -Times 0 -Exactly -ParameterFilter {
            $LiteralPath -like "$targetBase*"
        }
        Should -Invoke Get-Content -ModuleName DshPresetConfig -Times 0 -Exactly
        Should -Invoke Get-FileHash -ModuleName DshPresetConfig -Times 0 -Exactly -ParameterFilter {
            $LiteralPath -like "$targetBase*"
        }
        (Get-FileHash -LiteralPath $manifest).Hash | Should -Be $beforeHash
    }

    It 'blocks canonical archive component <Suffix> without inspecting target artifacts' -TestCases @(
        @{ Suffix = 'resources\app.asar' }
        @{ Suffix = 'resources\app.asar\dsh' }
        @{ Suffix = 'resources\APP.AsAr\dsh\' }
        @{ Suffix = 'resources/app.asar/dsh' }
        @{ Suffix = 'resources\custom.bundle.ASAR\dsh' }
        @{ Suffix = 'resources\.asar\dsh' }
        @{ Suffix = 'resources\not-an-archive\..\app.asar\dsh' }
    ) {
        param($Suffix)
        $contract.root = Join-Path $targetBase $Suffix
        $result = Test-DshUserPresetConfig -DshHome $homePath -Contract $contract
        $result.valid | Should -BeFalse
        $result.status | Should -Be 'user-preset-config-blocked'
        @($result.diagnostics).Count | Should -Be 1
        $result.diagnostics[0].code | Should -Be 'unsupported-asar-target-validation'
        ($result | ConvertTo-Json -Depth 10) | Should -Not -Match 'SECRET|not parsed'
    }

    It 'recognizes an environment-expanded archive root before physical target access' {
        $previous = $env:DSH_PRESET_TEST_ASAR_ROOT
        try {
            $env:DSH_PRESET_TEST_ASAR_ROOT = $contract.root
            $contract.root = '%DSH_PRESET_TEST_ASAR_ROOT%'
            (Test-DshUserPresetConfig -DshHome $homePath -Contract $contract).diagnostics.code |
                Should -Contain 'unsupported-asar-target-validation'
        } finally { $env:DSH_PRESET_TEST_ASAR_ROOT = $previous }
    }

    It 'keeps the no-user-presets success before the ASAR guard for <Layout>' -TestCases @(
        @{ Layout = 'absent-home' }
        @{ Layout = 'empty-roster' }
        @{ Layout = 'roster-files-only' }
    ) {
        param($Layout)
        $emptyHome = Join-Path $homePath $Layout
        $emptyRoster = Join-Path $emptyHome '.agent-presets'
        if ($Layout -ne 'absent-home') {
            New-Item -ItemType Directory $emptyRoster -Force | Out-Null
        }
        if ($Layout -eq 'roster-files-only') {
            'ignored roster file' | Set-Content (Join-Path $emptyRoster 'ignored.txt')
        }
        $result = Test-DshUserPresetConfig -DshHome $emptyHome -Contract $contract
        $result.valid | Should -BeTrue
        $result.status | Should -Be 'no-user-presets'
        @($result.diagnostics).Count | Should -Be 0
        @($result.rows).Count | Should -Be 0
        if ($Layout -eq 'absent-home') { Test-Path $emptyHome | Should -BeFalse }
    }

    It 'preserves missing-manifest rejection ahead of the ASAR target guard' {
        New-Item -ItemType Directory (Join-Path $homePath '.agent-presets\broken') | Out-Null
        (Test-DshUserPresetConfig -DshHome $homePath -Contract $contract).diagnostics.code |
            Should -Contain 'preset-manifest-missing'
    }

    It 'preserves oversized-input rejection ahead of the ASAR target guard' {
        $largeDirectory = Join-Path $homePath '.agent-presets\oversized'
        New-Item -ItemType Directory $largeDirectory | Out-Null
        ('x' * (1MB + 1)) | Set-Content (Join-Path $largeDirectory 'agent.cordis.yml') -NoNewline
        (Test-DshUserPresetConfig -DshHome $homePath -Contract $contract).diagnostics.code |
            Should -Contain 'preset-scope-limit'
    }

    It 'preserves input hashing before the ASAR target guard' {
        Mock Get-FileHash -ModuleName DshPresetConfig { throw 'INPUT HASH FAILURE' } -ParameterFilter {
            $LiteralPath -eq $manifest
        }
        (Test-DshUserPresetConfig -DshHome $homePath -Contract $contract).diagnostics.code |
            Should -Contain 'preset-scope-invalid'
        Should -Invoke Get-FileHash -ModuleName DshPresetConfig -Times 1 -Exactly -ParameterFilter {
            $LiteralPath -eq $manifest
        }
    }

    It 'preserves reparse input rejection ahead of the ASAR target guard' {
        $linkedHome = Join-Path $homePath 'linked'
        $physicalHome = Join-Path $TestDrive ('physical-' + [guid]::NewGuid())
        New-Item -ItemType Directory $physicalHome | Out-Null
        New-Item -ItemType Junction $linkedHome -Target $physicalHome | Out-Null
        (Test-DshUserPresetConfig -DshHome $linkedHome -Contract $contract).diagnostics.code |
            Should -Contain 'preset-scope-invalid'
    }
}

Describe 'Physical preset target boundaries remain enforced' {
    BeforeEach {
        $homePath = Join-Path $TestDrive ('home-' + [guid]::NewGuid())
        $presetDirectory = Join-Path $homePath '.agent-presets\sample'
        New-Item -ItemType Directory $presetDirectory -Force | Out-Null
        '[]' | Set-Content (Join-Path $presetDirectory 'agent.cordis.yml') -NoNewline
        Mock Get-PresetTargetFiles -ModuleName DshPresetConfig { throw 'TARGET WALK' }
        Mock Test-DshRuntimeSchemaState -ModuleName DshPresetConfig { throw 'RUNTIME SCHEMA' }
        Mock Get-Command -ModuleName DshPresetConfig { throw 'NODE PROCESS' } -ParameterFilter { $Name -eq 'node.exe' }
    }

    AfterEach {
        Should -Invoke Get-PresetTargetFiles -ModuleName DshPresetConfig -Times 0 -Exactly
        Should -Invoke Test-DshRuntimeSchemaState -ModuleName DshPresetConfig -Times 0 -Exactly
        Should -Invoke Get-Command -ModuleName DshPresetConfig -Times 0 -Exactly -ParameterFilter { $Name -eq 'node.exe' }
    }

    It 'does not mistake <Suffix> for a canonical ASAR path component' -TestCases @(
        @{ Suffix = 'app.asar.unpacked\dsh' }
        @{ Suffix = 'app.asar-backup\dsh' }
        @{ Suffix = 'app.asarfoo\dsh' }
        @{ Suffix = 'asar\dsh' }
        @{ Suffix = 'app.asar\..\physical\dsh' }
    ) {
        param($Suffix)
        $contract = [pscustomobject]@{ root = (Join-Path $TestDrive ('absent\' + $Suffix)) }
        (Test-DshUserPresetConfig -DshHome $homePath -Contract $contract).diagnostics.code |
            Should -Contain 'target-artifacts-unavailable'
    }

    It 'still rejects nonabsolute physical target <Root>' -TestCases @(
        @{ Root = 'relative-target' }
        @{ Root = 'C:relative-target' }
        @{ Root = 'C:\' }
    ) {
        param($Root)
        $contract = [pscustomobject]@{ root = $Root }
        (Test-DshUserPresetConfig -DshHome $homePath -Contract $contract).diagnostics.code |
            Should -Contain 'target-artifacts-unverified'
    }
}
