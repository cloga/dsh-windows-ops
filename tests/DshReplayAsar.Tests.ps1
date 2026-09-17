Import-Module (Join-Path $PSScriptRoot '..\tools\DshWindowsOps.psm1') -Force

Describe 'Synthetic native ASAR replay evidence and immutable targets' {
    BeforeEach {
        $script:savedHome = $env:DSH_HOME
        $script:savedAsarRoot = $env:DSH_TEST_ASAR_ROOT
        Remove-Item Env:DSH_HOME, Env:DSH_TEST_ASAR_ROOT -ErrorAction SilentlyContinue
        $script:replayLock = Get-Content (Join-Path $PSScriptRoot '..\deployments\windows-copilot.lock.json') -Raw | ConvertFrom-Json
        $script:replayLock.components.copilotIntegration.desktopProvisioning.mode = 'desktopNativeVerifiedRelease'
        $script:archive = Join-Path $TestDrive 'package\resources\app.asar'
        New-Item -ItemType Directory -Path (Split-Path -Parent $archive) -Force | Out-Null
        Set-Content -LiteralPath $archive -Value 'synthetic archive, never opened as a runtime' -Encoding UTF8
        $script:runtimeRoot = $archive + '\dsh'
        $script:desktopPath = Join-Path $TestDrive 'package\cloga-deepseek-harness.exe'
        $script:runtimeEvidence = [pscustomobject]@{
            valid = $true
            status = 'native-asar-audit-verified'
            selector = 'desktop-fork-managed'
            source = 'desktop-managed-release'
            mode = 'asar-runtime'
            root = $runtimeRoot
            version = '0.1.6'
            fileCount = 321
            reason = $null
            immutable = $true
            entryPath = $null
            descriptorPath = $runtimeRoot + '\desktop-runtime.json'
        }
        $script:replayConfig = [pscustomobject]@{
            dshHome = (Join-Path $TestDrive 'explicit-home')
            components = @(
                [pscustomobject]@{ name = 'dsh-desktop'; rootCandidates = @(); executables = @() },
                [pscustomobject]@{
                    name = 'dsh-desktop-runtime'; rootCandidates = @()
                    versionProbes = @([pscustomobject]@{ path = 'node_modules\@deepseek-ai\dsh\package.json'; property = 'version' })
                }
            )
            services = @()
            configFiles = @()
            modelEndpoints = @()
        }
        $script:patch = [pscustomobject]@{
            id = 'synthetic-asar-marker'
            component = 'dsh-desktop-runtime'
            files = @('node_modules\@deepseek-ai\dsh\lib\bin.js')
            verifyMarkers = @('synthetic-marker')
            upstreamStatus = 'synthetic'
            upstreamUrl = ''
        }
        $script:manifest = [pscustomobject]@{ patches = @($patch) }
        Mock Get-WindowsCopilotDesktopState -ModuleName DshWindowsOps {
            [pscustomobject]@{ path = $desktopPath; valid = $true; status = 'locked' }
        }
        Mock Get-WindowsCopilotOfficialRuntimeState -ModuleName DshWindowsOps { $runtimeEvidence }
        Mock Resolve-DshComponentRoot -ModuleName DshWindowsOps { throw 'virtual-root-probe-forbidden' } `
            -ParameterFilter { $Component.name -eq 'dsh-desktop-runtime' }
        Mock Get-DshPackageVersion -ModuleName DshWindowsOps { throw 'virtual-version-probe-forbidden' } `
            -ParameterFilter { $Component.name -eq 'dsh-desktop-runtime' }
        Mock Test-Path -ModuleName DshWindowsOps { throw 'virtual-TestPath-forbidden' } `
            -ParameterFilter { [string]$LiteralPath -match '\.asar([\\/]|$)' }
        Mock Get-Content -ModuleName DshWindowsOps { throw 'virtual-read-forbidden' } `
            -ParameterFilter { [string]$LiteralPath -match '\.asar([\\/]|$)' }
        Mock Start-Process -ModuleName DshWindowsOps { throw 'process-launch-forbidden' }
        Mock Write-DshOperationMetadata -ModuleName DshWindowsOps { throw 'backup-write-forbidden' }
    }

    AfterEach {
        $env:DSH_HOME = $savedHome
        $env:DSH_TEST_ASAR_ROOT = $savedAsarRoot
        Should -Invoke Get-DshPackageVersion -ModuleName DshWindowsOps -Times 0 -Exactly `
            -ParameterFilter { $Component.name -eq 'dsh-desktop-runtime' }
        Should -Invoke Resolve-DshComponentRoot -ModuleName DshWindowsOps -Times 0 -Exactly `
            -ParameterFilter { $Component.name -eq 'dsh-desktop-runtime' }
        Should -Invoke Test-Path -ModuleName DshWindowsOps -Times 0 -Exactly `
            -ParameterFilter { [string]$LiteralPath -match '\.asar([\\/]|$)' }
        Should -Invoke Get-Content -ModuleName DshWindowsOps -Times 0 -Exactly `
            -ParameterFilter { [string]$LiteralPath -match '\.asar([\\/]|$)' }
        Should -Invoke Start-Process -ModuleName DshWindowsOps -Times 0 -Exactly
        Should -Invoke Write-DshOperationMetadata -ModuleName DshWindowsOps -Times 0 -Exactly
    }

    It 'passes the replay-config home explicitly to the native audit' {
        $resolved = Resolve-DshLockedReplayConfig -Config $replayConfig -Lock $replayLock
        $resolved.deployment.valid | Should -BeTrue
        Should -Invoke Get-WindowsCopilotOfficialRuntimeState -ModuleName DshWindowsOps -Times 1 -Exactly `
            -ParameterFilter { $DshHome -eq $replayConfig.dshHome -and $DesktopExecutablePath -eq $desktopPath }
        $resolved.deployment.runtime.entryPath | Should -BeNullOrEmpty
        $resolved.components[1].rootCandidates | Should -Be @($runtimeRoot)
    }

    It 'preserves DSH_HOME precedence when supplying the audit home' {
        $env:DSH_HOME = Join-Path $TestDrive 'environment-home'
        $null = Resolve-DshLockedReplayConfig -Config $replayConfig -Lock $replayLock
        Should -Invoke Get-WindowsCopilotOfficialRuntimeState -ModuleName DshWindowsOps -Times 1 -Exactly `
            -ParameterFilter { $DshHome -eq $env:DSH_HOME }
    }

    It 'uses valid audited version root and count without a physical package or fake CLI' {
        $resolved = Resolve-DshLockedReplayConfig -Config $replayConfig -Lock $replayLock
        $inventory = @(Get-DshComponentInventory -Config $resolved | Where-Object name -eq 'dsh-desktop-runtime')
        $inventory.Count | Should -Be 1
        $inventory[0].installed | Should -BeTrue
        $inventory[0].version | Should -Be '0.1.6'
        $inventory[0].root | Should -Be $runtimeRoot
        $inventory[0].fileCount | Should -Be 321
        $inventory[0].source | Should -Be 'native-asar-audit'
        $inventory[0].immutable | Should -BeTrue
        $inventory[0].status | Should -Be $runtimeEvidence.status
    }

    It 'carries invalid audit evidence without promoting partial version/count: <AuditStatus>' -TestCases @(
        @{ AuditStatus = 'native-asar-audit-prerequisite-not-ready' },
        @{ AuditStatus = 'native-asar-audit-not-ready' },
        @{ AuditStatus = 'native-runtime-layout-unsupported' }
    ) {
        param($AuditStatus)
        $runtimeEvidence.valid = $false
        $runtimeEvidence.status = $AuditStatus
        $runtimeEvidence.reason = 'synthetic full audit did not pass'
        # Even accidentally retained partial fields cannot become installed evidence.
        $resolved = Resolve-DshLockedReplayConfig -Config $replayConfig -Lock $replayLock
        $resolved.deployment.valid | Should -BeFalse
        $inventory = @(Get-DshComponentInventory -Config $resolved | Where-Object name -eq 'dsh-desktop-runtime')
        $inventory[0].installed | Should -BeFalse
        $inventory[0].version | Should -BeNullOrEmpty
        $inventory[0].fileCount | Should -BeNullOrEmpty
        $inventory[0].root | Should -Be $runtimeRoot
        $inventory[0].status | Should -Be $AuditStatus
        $inventory[0].reason | Should -Be $runtimeEvidence.reason
        $inventory[0].source | Should -Be 'native-asar-audit'
        $check = Test-DshPatch -Patch $patch -Config $resolved
        $check.status | Should -Be 'unsupported-immutable-asar-target'
        $check.supported | Should -BeFalse
        $check.applicable | Should -BeFalse
        $check.target | Should -BeNullOrEmpty
    }

    It 'classifies the ASAR mode before selector filters or any target discovery' {
        $resolved = Resolve-DshLockedReplayConfig -Config $replayConfig -Lock $replayLock
        $resolved.components[1].rootCandidates = @()
        $patch | Add-Member runtimeSelectors @('desktop-official')
        Mock Resolve-DshPatchTarget -ModuleName DshWindowsOps { throw 'target-resolution-forbidden' }
        (Test-DshPatch -Patch $patch -Config $resolved).status | Should -Be 'unsupported-immutable-asar-target'
        Should -Invoke Resolve-DshPatchTarget -ModuleName DshWindowsOps -Times 0 -Exactly
    }

    It 'classifies configured ASAR paths without deployment evidence: <Carrier>' -TestCases @(
        @{ Carrier = 'component-root' },
        @{ Carrier = 'environment-root' },
        @{ Carrier = 'home-placeholder' },
        @{ Carrier = 'patch-file' }
    ) {
        param($Carrier)
        # A custom component cannot bypass the archive boundary by changing its name.
        $patch.component = 'custom-component'
        $replayConfig.components[1].name = 'custom-component'
        switch ($Carrier) {
            'component-root' { $replayConfig.components[1].rootCandidates = @($runtimeRoot) }
            'environment-root' {
                $env:DSH_TEST_ASAR_ROOT = $runtimeRoot
                $replayConfig.components[1] | Add-Member rootEnv 'DSH_TEST_ASAR_ROOT'
            }
            'home-placeholder' {
                $replayConfig.dshHome = $runtimeRoot
                $replayConfig.components[1].rootCandidates = @('${DSH_HOME}\nested')
            }
            'patch-file' {
                $replayConfig.components[1].rootCandidates = @((Split-Path -Parent $archive))
                $patch.files = @('APP.ASAR/dsh/node_modules/example/lib/index.js')
            }
        }
        Mock Resolve-DshPatchTarget -ModuleName DshWindowsOps { throw 'target-resolution-forbidden' }
        Mock Resolve-DshComponentRoot -ModuleName DshWindowsOps { throw 'root-resolution-forbidden' }
        Mock Test-Path -ModuleName DshWindowsOps { throw 'filesystem-probe-forbidden' }
        Mock Get-Content -ModuleName DshWindowsOps { throw 'filesystem-read-forbidden' }
        $check = Test-DshPatch -Patch $patch -Config $replayConfig
        $check.status | Should -Be 'unsupported-immutable-asar-target'
        $check.id | Should -Be $patch.id
        $check.component | Should -Be $patch.component
        $check.supported | Should -BeFalse
        $check.applicable | Should -BeFalse
        Should -Invoke Resolve-DshPatchTarget -ModuleName DshWindowsOps -Times 0 -Exactly
        Should -Invoke Resolve-DshComponentRoot -ModuleName DshWindowsOps -Times 0 -Exactly
        Should -Invoke Test-Path -ModuleName DshWindowsOps -Times 0 -Exactly
        Should -Invoke Get-Content -ModuleName DshWindowsOps -Times 0 -Exactly
    }

    It 'refuses native unpacked backing targets before Verify or DryRun reads: <Carrier>' -TestCases @(
        @{ Carrier = 'desktop-patch-file' },
        @{ Carrier = 'custom-root' },
        @{ Carrier = 'sidecar-parent-root' },
        @{ Carrier = 'environment-root' }
    ) {
        param($Carrier)
        $patch.component = 'dsh-desktop'
        $sidecar = Join-Path (Split-Path -Parent $archive) 'app.asar.unpacked\dsh'
        switch ($Carrier) {
            'desktop-patch-file' {
                $replayConfig.components[0].rootCandidates = @((Split-Path -Parent (Split-Path -Parent $archive)))
                $patch.files = @('resources/APP.ASAR.UNPACKED/dsh/node_modules/fixture/native.node')
            }
            'custom-root' {
                $patch.component = 'custom-component'
                $replayConfig.components[0].name = 'custom-component'
                $replayConfig.components[0].rootCandidates = @($sidecar)
                $patch.files = @('node_modules/fixture/native.node')
            }
            'sidecar-parent-root' {
                $replayConfig.components[0].rootCandidates = @((Split-Path -Parent $sidecar))
                $patch.files = @('dsh/node_modules/fixture/native.node')
            }
            'environment-root' {
                $env:DSH_TEST_ASAR_ROOT = $sidecar
                $replayConfig.components[0] | Add-Member rootEnv 'DSH_TEST_ASAR_ROOT'
                $patch.files = @('node_modules/fixture/native.node')
            }
        }
        Mock Resolve-DshPatchTarget -ModuleName DshWindowsOps { throw 'immutable-backing-discovery-forbidden' }
        Mock Resolve-DshComponentRoot -ModuleName DshWindowsOps { throw 'immutable-backing-root-forbidden' }
        Mock Test-Path -ModuleName DshWindowsOps { throw 'immutable-backing-probe-forbidden' }
        Mock Get-Content -ModuleName DshWindowsOps { throw 'immutable-backing-read-forbidden' }
        Mock Expand-DshPath -ModuleName DshWindowsOps { throw 'state-root-expansion-forbidden' }
        (Test-DshPatch -Patch $patch -Config $replayConfig).status | Should -Be 'unsupported-immutable-asar-target'
        $apply = Invoke-DshPatchSet -Config $replayConfig -Manifest $manifest -DryRun -StateRoot 'synthetic-unused-state'
        $apply.results[0].status | Should -Be 'unsupported-immutable-asar-target'
        (Restore-DshPatchSet -Config $replayConfig -Manifest $manifest -DryRun -StateRoot 'synthetic-unused-state').status |
            Should -Be 'unsupported-immutable-asar-target'
        Should -Invoke Resolve-DshPatchTarget -ModuleName DshWindowsOps -Times 0 -Exactly
        Should -Invoke Resolve-DshComponentRoot -ModuleName DshWindowsOps -Times 0 -Exactly
        Should -Invoke Test-Path -ModuleName DshWindowsOps -Times 0 -Exactly
        Should -Invoke Get-Content -ModuleName DshWindowsOps -Times 0 -Exactly
        Should -Invoke Expand-DshPath -ModuleName DshWindowsOps -Times 0 -Exactly
    }

    It 'does not mistake an ordinary asar.unpacked directory for an archive target' {
        $physicalRoot = Join-Path $TestDrive 'ordinary.asar.unpacked'
        New-Item -ItemType Directory -Path $physicalRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $physicalRoot 'index.js') -Value 'synthetic-marker' -Encoding UTF8
        $patch.component = 'physical-fixture'
        $patch.files = @('index.js')
        $replayConfig.components[1].name = 'physical-fixture'
        $replayConfig.components[1].rootCandidates = @($physicalRoot)
        (Test-DshPatch -Patch $patch -Config $replayConfig).status | Should -Be 'verified-upstream'
    }

    It 'leaves archive and StateRoot unchanged for Apply and Rollback DryRun' {
        $runtimeEvidence.valid = $false
        $runtimeEvidence.status = 'native-asar-audit-not-ready'
        $resolved = Resolve-DshLockedReplayConfig -Config $replayConfig -Lock $replayLock
        $stateRoot = Join-Path $TestDrive 'never-create-state'
        $before = (Get-FileHash -LiteralPath $archive).Hash
        $apply = Invoke-DshPatchSet -Config $resolved -Manifest $manifest -DryRun -StateRoot $stateRoot
        $apply.results[0].status | Should -Be 'unsupported-immutable-asar-target'
        # Rollback must not even check backups or expand StateRoot for immutable targets.
        Mock Expand-DshPath -ModuleName DshWindowsOps { throw 'state-root-probe-forbidden' }
        $rollback = Restore-DshPatchSet -Config $resolved -Manifest $manifest -DryRun -StateRoot $stateRoot
        $rollback.status | Should -Be 'unsupported-immutable-asar-target'
        $rollback.results[0].applicable | Should -BeFalse
        Should -Invoke Expand-DshPath -ModuleName DshWindowsOps -Times 0 -Exactly
        Test-Path -LiteralPath $stateRoot | Should -BeFalse
        (Get-FileHash -LiteralPath $archive).Hash | Should -Be $before
    }

    It 'refuses native mutations before marker or backup reads even when the audit is invalid' {
        $runtimeEvidence.valid = $false
        $resolved = Resolve-DshLockedReplayConfig -Config $replayConfig -Lock $replayLock
        Mock Test-DshPatch -ModuleName DshWindowsOps { throw 'marker-probe-forbidden' }
        Mock Expand-DshPath -ModuleName DshWindowsOps { throw 'state-root-probe-forbidden' }
        { Invoke-DshPatchSet -Config $resolved -Manifest $manifest -StateRoot 'C:\synthetic-never-create' } |
            Should -Throw '*native-replay-mutation-delegated*'
        { Restore-DshPatchSet -Config $resolved -Manifest $manifest -StateRoot 'C:\synthetic-never-create' } |
            Should -Throw '*native-replay-mutation-delegated*'
        Should -Invoke Test-DshPatch -ModuleName DshWindowsOps -Times 0 -Exactly
        Should -Invoke Expand-DshPath -ModuleName DshWindowsOps -Times 0 -Exactly
    }

    It 'exposes audited identity and explicit unsupported targets through all read-only actions: valid=<AuditValid>' -TestCases @(
        @{ AuditValid = $true },
        @{ AuditValid = $false }
    ) {
        param($AuditValid)
        $runtimeEvidence.valid = $AuditValid
        if (-not $AuditValid) { $runtimeEvidence.status = 'native-asar-audit-not-ready' }
        $configPath = Join-Path $TestDrive 'replay.json'
        $manifestPath = Join-Path $TestDrive 'patches.json'
        $lockPath = Join-Path $TestDrive 'lock.json'
        $stateRoot = Join-Path $TestDrive 'entrypoint-no-state'
        $replayConfig | ConvertTo-Json -Depth 20 | Set-Content $configPath -Encoding UTF8
        $manifest | ConvertTo-Json -Depth 20 | Set-Content $manifestPath -Encoding UTF8
        $replayLock | ConvertTo-Json -Depth 100 | Set-Content $lockPath -Encoding UTF8
        $entrypoint = Join-Path $PSScriptRoot '..\tools\dsh-replay.ps1'
        $args = @{ Config = $configPath; PatchManifest = $manifestPath; LockPath = $lockPath; StateRoot = $stateRoot }
        foreach ($action in @('Preflight', 'Inventory', 'SelfCheck')) {
            $result = & $entrypoint -Action $action @args | ConvertFrom-Json
            $result.deployment.runtime.root | Should -Be $runtimeRoot
            $result.deployment.runtime.entryPath | Should -BeNullOrEmpty
            $runtime = @($result.components | Where-Object name -eq 'dsh-desktop-runtime')[0]
            $runtime.installed | Should -Be $AuditValid
            $runtime.source | Should -Be 'native-asar-audit'
            $runtime.status | Should -Be $runtimeEvidence.status
            if ($action -eq 'SelfCheck') {
                $result.diagnosticScope | Should -Be 'service-config-endpoint-checks-are-web-headless-not-native-host'
            }
            if ($action -ne 'Inventory') { $result.patches[0].status | Should -Be 'unsupported-immutable-asar-target' }
        }
        $verify = & $entrypoint -Action Verify @args | ConvertFrom-Json
        @($verify)[0].status | Should -Be 'unsupported-immutable-asar-target'
        foreach ($action in @('Apply', 'Rollback')) {
            $result = & $entrypoint -Action $action -DryRun @args | ConvertFrom-Json
            $result.results[0].status | Should -Be 'unsupported-immutable-asar-target'
            { & $entrypoint -Action $action @args } | Should -Throw '*native-replay-mutation-delegated*'
        }
        Test-Path -LiteralPath $stateRoot | Should -BeFalse
    }
}
