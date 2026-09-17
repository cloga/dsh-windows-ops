BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\tools\DshCopilotManagedRoute.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '..\tools\WindowsCopilotDeployment.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '..\tools\DshWindowsOps.psm1') -Force
    function New-NativeRemoteFixture {
        @{
            migrationStatus = @{
                plugin = @{ name = 'dsh-github-copilot'; version = '0.4.0-alpha.24' }
                protocolVersion = 1
                historyScope = 'live-agents-only'
                observedAt = 1000
                capabilities = @{ agentsList = $true; sessionProjections = $true; settingsCas = $true; providerRegistry = $true; defaultSelection = $true }
                complete = @{ sessions = $true; defaultSelection = $true; routes = $true }
                defaultSelection = @{ provider = 'github-copilot-preview'; model = 'fixture-model' }
                sessions = @(@{
                    id = 'fixture-session'; status = 'running'
                    effectiveSelection = @{ provider = 'github-copilot-preview'; model = 'fixture-model' }
                    selectionSource = 'request-header'
                    activeRequestSelection = @{ provider = 'github-copilot-preview'; model = 'fixture-model' }
                })
                routes = @{ nativeConfigured = $false; nativeRegistered = $false; managedRegistered = $true }
            }
            authorizationStatus = @{
                configured = $true; phase = 'signed-in'; inFlight = $false; writable = $true; notices = @()
                accountModels = @{
                    state = 'ready'; models = @(@{ id = 'fixture-model'; name = 'Fixture Model'; api = 'openai-responses' })
                    rejected = @(); discoveredAt = 1000
                }
                route = @{ state = 'not-configured' }
            }
        }
    }
    function Test-NativeFixture {
        param($Fixture, [string]$Model = 'fixture-model', [string]$Session = 'fixture-session')
        Get-DshCopilotNativeRouteAssessment -PluginVersion '0.4.0-alpha.24' `
            -MigrationStatus $Fixture.migrationStatus -AuthorizationStatus $Fixture.authorizationStatus `
            -ExpectedModelId $Model -ExpectedSessionId $Session
    }
}

Describe 'Native installer mode and interruption boundaries' {
    BeforeEach {
        $script:nativeLock = Get-Content (Join-Path $PSScriptRoot '..\deployments\windows-copilot.lock.json') -Raw | ConvertFrom-Json
        Mock Enter-WindowsCopilotDeploymentLock -ModuleName WindowsCopilotDeployment { throw 'must not mutate' }
        Mock Get-WindowsCopilotLiveSessions -ModuleName WindowsCopilotDeployment { throw 'Web evidence must not authorize native work' }
        Mock Stop-WindowsCopilotProcessTree -ModuleName WindowsCopilotDeployment { throw 'must not stop' }
        Mock Start-Process -ModuleName WindowsCopilotDeployment { throw 'must not start' }
        Mock Invoke-RestMethod -ModuleName WindowsCopilotDeployment { throw 'native has no HTTP attachment' }
    }

    It 'blocks native <Action> before mutex, Web Session reads or process control' -ForEach @(
        @{ Action = 'Apply' }, @{ Action = 'Rollback' }, @{ Action = 'Restart' }, @{ Action = 'DryRun' }
    ) {
        {
            switch ($Action) {
                Apply {
                    Invoke-WindowsCopilotApply -Lock $script:nativeLock -DshHome $TestDrive -NpmGlobalRoot $TestDrive `
                        -CopilotIntegrationSourceRoot $TestDrive -CopilotIntegrationArtifactPath 'unused.tgz' `
                        -DesktopArtifactPath 'unused.exe' -BackupRoot (Join-Path $TestDrive 'backups')
                }

                Rollback { Restore-WindowsCopilotDeployment -Lock $script:nativeLock -BackupRoot (Join-Path $TestDrive 'backups') }
                Restart {
                    Restart-WindowsCopilotDesktop -Lock $script:nativeLock -DesktopExecutablePath 'unused.exe' `
                        -LiveSessions @() -FinalLiveSessions @()
                }
                DryRun { Restart-WindowsCopilotDesktop -Lock $script:nativeLock -DesktopExecutablePath 'unused.exe' -DryRun }
            }
        } | Should -Throw '*native-desktop-mutation-delegated*'
        Should -Invoke Enter-WindowsCopilotDeploymentLock -ModuleName WindowsCopilotDeployment -Times 0
        Should -Invoke Get-WindowsCopilotLiveSessions -ModuleName WindowsCopilotDeployment -Times 0
        Should -Invoke Stop-WindowsCopilotProcessTree -ModuleName WindowsCopilotDeployment -Times 0
        Should -Invoke Start-Process -ModuleName WindowsCopilotDeployment -Times 0
    }

    It 'also blocks native replay mutations while keeping exact-marker DryRun read-only' {
        $config = [pscustomobject]@{
            deployment = [pscustomobject]@{ provisioningMode = 'desktopNativeVerifiedRelease' }
            components = @()
        }
        $manifest = [pscustomobject]@{ patches = @() }
        $stateRoot = Join-Path $TestDrive 'untouched-state'
        { Invoke-DshPatchSet -Config $config -Manifest $manifest -StateRoot $stateRoot } |
            Should -Throw '*native-replay-mutation-delegated*'
        { Restore-DshPatchSet -Config $config -Manifest $manifest -StateRoot $stateRoot } |
            Should -Throw '*native-replay-mutation-delegated*'
        { Invoke-DshDesktopRecovery -Config $config } | Should -Throw '*native-replay-mutation-delegated*'
        Invoke-DshPatchSet -Config $config -Manifest $manifest -StateRoot $stateRoot -DryRun | Out-Null
        (Invoke-DshDesktopRecovery -Config $config -DryRun).status |
            Should -Be 'would-block-native-session-evidence-unavailable'
        Test-Path -LiteralPath $stateRoot | Should -BeFalse
    }

    It 'preserves Unicode installation paths through the legacy physical Node stdin fixture without changing caller encoding' {
        # This is deliberately an inert .5 transport regression, not .6 ASAR evidence.
        $script:nativeLock.components.desktop.installedRuntimeDescriptor.relativePath = 'resources\dsh\desktop-runtime.json'
        $script:nativeLock.components.desktop.releaseChannel.upstreamVersion = '0.1.5-rc.2'
        $oldEncoding = $OutputEncoding
        $install = Join-Path $TestDrive ('native-' + [char]0x6d4b + [char]0x8bd5)
        $runtime = Join-Path $install 'resources\dsh'
        New-Item -ItemType Directory -Path $runtime -Force | Out-Null
        $body = 'fixture'
        [IO.File]::WriteAllText((Join-Path $runtime 'fixture.js'), $body, [Text.UTF8Encoding]::new($false))
        $descriptor = @{
            schemaVersion = 1; platform = 'win32'; arch = 'x64'; sharedPackages = @()
            files = @(@{ path = 'fixture.js'; bytes = 7; sha256 = (Get-FileHash (Join-Path $runtime 'fixture.js')).Hash.ToLowerInvariant(); executable = $false })
        } | ConvertTo-Json -Depth 8 -Compress
        $descriptorPath = Join-Path $runtime 'desktop-runtime.json'
        [IO.File]::WriteAllText($descriptorPath, $descriptor, [Text.UTF8Encoding]::new($false))
        $script:nativeLock.components.desktop.installedRuntimeDescriptor.sha256 = (Get-FileHash $descriptorPath).Hash.ToLowerInvariant()
        $script:nativeExe = Join-Path $install 'cloga-deepseek-harness.exe'
        Mock Test-WindowsCopilotLock -ModuleName WindowsCopilotDeployment { $true }
        Mock Get-WindowsCopilotDesktopState -ModuleName WindowsCopilotDeployment {
            [pscustomobject]@{ valid = $true; path = $script:nativeExe }
        }
        $result = Test-WindowsCopilotNativeInstallation -Lock $script:nativeLock -DshHome $TestDrive -SkipRuntimeChecks
        $result.runtime.officialRuntime.valid | Should -BeTrue
        $result.runtime.officialRuntime.fileCount | Should -Be 1
        $OutputEncoding | Should -Be $oldEncoding
    }

    It 'binds only the locked <Layout> parent, executable and exact Host argv: <Mismatch> (preload <Preload>)' -ForEach @(
        foreach ($layout in @('legacy', 'asar')) {
            foreach ($mismatch in @('', 'parent', 'parent-executable', 'node', 'profile', 'script', 'runtime',
                'policy', 'policy-case', 'import-case', 'missing-import', 'extra-import', 'flag', 'unknown-flag',
                'runtime-attestation', 'desktop-attestation', 'none', 'duplicate', 'argv-executable',
                'malformed-quotes', 'joined-quotes', 'unknown-layout', 'layout-case', 'layout-traversal', 'opposite-layout')) {
                @{ Layout = $layout; Mismatch = $mismatch; Preload = $true }
            }
        }
        foreach ($mismatch in @('', 'parent', 'node', 'profile', 'script', 'flag', 'none', 'unattested-import')) {
            @{ Layout = 'legacy'; Mismatch = $mismatch; Preload = $false }
        }
        foreach ($mismatch in @('missing-policy-evidence', 'missing-host-evidence', 'runtime-root-evidence',
            'parent-host', 'parent-renderer', 'parent-helper', 'parent-missing-argv', 'parent-argv-executable')) {
            @{ Layout = 'asar'; Mismatch = $mismatch; Preload = $true }
        }
    ) {
        $install = Join-Path $TestDrive ('Desktop Spaces % # ' + [char]0x6d4b + [char]0x8bd5)
        $script:nativeExe = Join-Path $install 'cloga-deepseek-harness.exe'
        $script:desktopValid = $Mismatch -ne 'desktop-attestation'
        Mock Test-WindowsCopilotLock -ModuleName WindowsCopilotDeployment { $true }
        Mock Get-WindowsCopilotDesktopState -ModuleName WindowsCopilotDeployment {
            [pscustomobject]@{ valid = $script:desktopValid; path = $script:nativeExe }
        }
        Mock Get-CimInstance -ModuleName WindowsCopilotDeployment { throw 'must use synthetic process inventory' }
        Mock node -ModuleName WindowsCopilotDeployment {
            $global:LASTEXITCODE = 0
            $script:nativeFileEvidence | ConvertTo-Json -Depth 8 -Compress
        }
        $nodePath = if ($Layout -eq 'asar') { $script:nativeExe } else { Join-Path $install 'resources\runtime\node\node.exe' }
        $runtimeRelative = if ($Layout -eq 'asar') { 'resources\app.asar\dsh' } else { 'resources\dsh' }
        $script:nativeLock.components.desktop.installedRuntimeDescriptor.relativePath = "$runtimeRelative\desktop-runtime.json"
        $script:nativeLock.components.desktop.releaseChannel.upstreamVersion = if ($Layout -eq 'asar') { '0.1.6-alpha.1' } else { '0.1.5-rc.2' }
        $runtime = Join-Path $install $runtimeRelative
        $hostScript = Join-Path $runtime 'node_modules\@deepseek-ai\dsh-desktop-host\lib\index.js'
        $profile = Join-Path $TestDrive 'profiles\desktop'
        $policyPath = Join-Path $runtime 'node_modules\@deepseek-ai\dsh-desktop-host\register-module-resolution-policy.mjs'
        $policyUri = & (Get-Command node -CommandType Application).Source -e "console.log(require('node:url').pathToFileURL(process.argv[1]).href)" $policyPath
        $LASTEXITCODE | Should -Be 0
        $script:nativeFileEvidence = @{
            valid = $false
            runtime = @{
                valid = $Mismatch -ne 'runtime-attestation'; runtimeRoot = $runtime; hostEntry = $hostScript
                moduleResolutionPolicyUrl = if ($Preload) { $policyUri } else { $null }
            }
            provisioning = @{ valid = $false }
            functional = @{ valid = $false; status = 'manual-verification-required' }
        }
        $parentId = 10
        $parentExecutable = $script:nativeExe
        switch ($Mismatch) {
            parent { $parentId = 99 }
            parent-executable { $parentExecutable = Join-Path $TestDrive 'cloga-deepseek-harness.exe' }
            node { $nodePath = Join-Path $TestDrive ([IO.Path]::GetFileName($nodePath)) }
            profile { $profile = Join-Path $TestDrive 'profiles\web' }
            script { $hostScript = Join-Path $runtime 'desktop-runtime.json' }
            runtime { $runtime = Join-Path $TestDrive 'wrong-runtime' }
            policy { $policyUri = 'file:///C:/unowned/register-module-resolution-policy.mjs' }
            policy-case { $policyUri = $policyUri.Replace('register-module', 'Register-module') }
            unknown-layout { $script:nativeLock.components.desktop.installedRuntimeDescriptor.relativePath = 'resources/other/desktop-runtime.json' }
            layout-case { $script:nativeLock.components.desktop.installedRuntimeDescriptor.relativePath = "$runtimeRelative\Desktop-runtime.json" }
            layout-traversal { $script:nativeLock.components.desktop.installedRuntimeDescriptor.relativePath = "$runtimeRelative\..\dsh\desktop-runtime.json" }
            opposite-layout {
                $script:nativeLock.components.desktop.installedRuntimeDescriptor.relativePath = if ($Layout -eq 'asar') {
                    'resources/dsh/desktop-runtime.json'
                } else { 'resources/app.asar/dsh/desktop-runtime.json' }
            }
            missing-policy-evidence { $script:nativeFileEvidence.runtime.moduleResolutionPolicyUrl = $null }
            missing-host-evidence { $script:nativeFileEvidence.runtime.hostEntry = $null }
            runtime-root-evidence { $script:nativeFileEvidence.runtime.runtimeRoot = Join-Path $install 'resources\dsh' }
        }
        $arguments = @($nodePath)
        if (($Preload -and $Mismatch -ne 'missing-import') -or $Mismatch -eq 'unattested-import') {
            $arguments += @('--import', $policyUri)
        }
        if ($Mismatch -eq 'extra-import') { $arguments += @('--import', $policyUri) }
        $arguments += @($hostScript, $runtime, $profile)
        if ($Mismatch -eq 'argv-executable') { $arguments[0] = Join-Path $TestDrive 'other.exe' }
        if ($Mismatch -eq 'import-case') { $arguments[1] = '--IMPORT' }
        $command = '"' + ($arguments -join '" "') + '"'
        if ($Mismatch -eq 'flag') { $command += ' --allow-linked-profile' }
        if ($Mismatch -eq 'unknown-flag') { $command += ' --unknown' }
        if ($Mismatch -eq 'malformed-quotes') { $command += '"' }
        if ($Mismatch -eq 'joined-quotes') { $command = $command.Replace('" "', '""') }
        $processes = @(
            [pscustomobject]@{ ProcessId = 10; ParentProcessId = 1; Name = 'cloga-deepseek-harness.exe'; ExecutablePath = $parentExecutable; CommandLine = '"' + $parentExecutable + '"' },
            [pscustomobject]@{ ProcessId = 11; ParentProcessId = $parentId; Name = [IO.Path]::GetFileName($nodePath); ExecutablePath = $nodePath; CommandLine = $command }
        )
        switch ($Mismatch) {
            parent-host { $processes[0].CommandLine = $command }
            parent-renderer { $processes[0].CommandLine += ' --type=renderer' }
            parent-helper { $processes[0].CommandLine += ' --type=utility' }
            parent-missing-argv { $processes[0].CommandLine = '' }
            parent-argv-executable { $processes[0].CommandLine = '"' + (Join-Path $TestDrive 'other.exe') + '"' }
            duplicate {
                $processes += [pscustomobject]@{ ProcessId = 12; ParentProcessId = $parentId; Name = [IO.Path]::GetFileName($nodePath); ExecutablePath = $nodePath; CommandLine = $command }
            }
            none { $processes = @() }
        }
        $result = Test-WindowsCopilotNativeInstallation -Lock $script:nativeLock -DshHome $TestDrive -DesktopProcesses $processes
        $result.runtime.activeRuntime.valid | Should -Be ($Mismatch -eq '')
        $result.runtime.listenerStatus | Should -Be 'not-applicable-native-host'
        $result.complete | Should -BeFalse
        $result.functional.valid | Should -BeFalse
        Should -Invoke Invoke-RestMethod -ModuleName WindowsCopilotDeployment -Times 0
    }
}

Describe 'Read-only native managed Copilot projections' {
    It 'accepts managed-only composition without recreating the canonical profile or proving an LLM response' {
        $fixture = New-NativeRemoteFixture
        $before = $fixture | ConvertTo-Json -Depth 16 -Compress
        $result = Test-NativeFixture $fixture
        $result.valid | Should -BeTrue
        $result.status | Should -Be 'ready-projection'
        $result.legacyRouteStatus | Should -Be 'not-configured'
        $result.modelResponseVerified | Should -BeFalse
        $result.fullBaselineVerified | Should -BeFalse
        ($fixture | ConvertTo-Json -Depth 16 -Compress) | Should -BeExactly $before
    }

    It 'does not accept incomplete routes, absent registration or a different loaded plugin' -ForEach @(
        @{ Field = 'version' }, @{ Field = 'protocol' }, @{ Field = 'registry' },
        @{ Field = 'complete' }, @{ Field = 'registered' }, @{ Field = 'boolean-string' }
    ) {
        $fixture = New-NativeRemoteFixture
        switch ($Field) {
            version { $fixture.migrationStatus.plugin.version = '0.4.0-alpha.18' }
            protocol { $fixture.migrationStatus.protocolVersion = '1' }
            registry { $fixture.migrationStatus.capabilities.providerRegistry = $false }
            complete { $fixture.migrationStatus.complete.routes = $false }
            registered { $fixture.migrationStatus.routes.managedRegistered = $null }
            boolean-string { $fixture.migrationStatus.routes.managedRegistered = 'true' }
        }
        (Test-NativeFixture $fixture).valid | Should -BeFalse
    }

    It 'rejects account state <State> without refreshing discovery or OAuth' -ForEach @(
        @{ State = 'idle' }, @{ State = 'loading' }, @{ State = 'stale' }, @{ State = 'error' },
        @{ State = 'disposed' }, @{ State = 'unconfigured' }, @{ State = 'unavailable' }
    ) {
        $fixture = New-NativeRemoteFixture
        $fixture.authorizationStatus.accountModels.state = $State
        (Test-NativeFixture $fixture).reasons | Should -Contain 'managed-account-models-not-ready'
    }

    It 'fails closed for missing, private, or malformed authorization evidence' -ForEach @(
        @{ Field = 'missing' }, @{ Field = 'models-empty' }, @{ Field = 'error' }, @{ Field = 'in-flight' },
        @{ Field = 'signed-out' }, @{ Field = 'private-root' }, @{ Field = 'private-model' },
        @{ Field = 'private-notice' }, @{ Field = 'null-models' }, @{ Field = 'null-account' }
    ) {
        $fixture = New-NativeRemoteFixture
        switch ($Field) {
            missing { $fixture.authorizationStatus = $null }
            models-empty { $fixture.authorizationStatus.accountModels.models = @() }
            error { $fixture.authorizationStatus.error = '' }
            in-flight { $fixture.authorizationStatus.inFlight = $true }
            signed-out { $fixture.authorizationStatus.phase = 'signed-out' }
            private-root { $fixture.authorizationStatus.accessToken = 'fixture-not-a-token' }
            private-model { $fixture.authorizationStatus.accountModels.models[0].headers = @{} }
            private-notice { $fixture.authorizationStatus.notices = @(@{ message = 'fixture'; privateKey = 'fixture' }) }
            null-models { $fixture.authorizationStatus.accountModels.models = $null }
            null-account { $fixture.authorizationStatus.accountModels = $null }
        }
        $result = Test-NativeFixture $fixture
        $result.valid | Should -BeFalse
        ($result | ConvertTo-Json -Depth 5) | Should -Not -Match 'fixture-not-a-token|privateKey|accessToken|headers'
    }

    It 'requires the exact model and checks live Session evidence only when explicitly requested' {
        $fixture = New-NativeRemoteFixture
        (Test-NativeFixture $fixture -Model '').valid | Should -BeFalse
        (Test-NativeFixture $fixture -Model 'different').valid | Should -BeFalse
        (Test-NativeFixture $fixture -Session 'missing').valid | Should -BeFalse
        $fixture.migrationStatus.sessions = @()
        $result = Test-NativeFixture $fixture -Session ''
        $result.valid | Should -BeTrue
        $result.sessionBinding | Should -Be 'not-requested'
    }

    It 'rejects incomplete, unknown, wrong-provider or wrong-running-request Session projections' -ForEach @(
        @{ Field = 'incomplete' }, @{ Field = 'source' }, @{ Field = 'provider' },
        @{ Field = 'model' }, @{ Field = 'request' }, @{ Field = 'private' }
    ) {
        $fixture = New-NativeRemoteFixture
        switch ($Field) {
            incomplete { $fixture.migrationStatus.complete.sessions = $false }
            source { $fixture.migrationStatus.sessions[0].selectionSource = 'unknown' }
            provider { $fixture.migrationStatus.sessions[0].effectiveSelection.provider = 'github-copilot' }
            model { $fixture.migrationStatus.sessions[0].effectiveSelection.model = 'different' }
            request { $fixture.migrationStatus.sessions[0].activeRequestSelection = $null }
            private { $fixture.migrationStatus.sessions[0].accountKey = 'fixture' }
        }
        (Test-NativeFixture $fixture).valid | Should -BeFalse
    }

}
