# Synthetic contract tests only: no installed Desktop, Node, source CLI or taskkill is executed.
BeforeDiscovery {
    Import-Module (Join-Path $PSScriptRoot '..\tools\WindowsCopilotDeployment.psm1') -Force
}

Describe 'Native ASAR runtime state uses correlated audit leaves, not virtual files' {
    InModuleScope WindowsCopilotDeployment {
        BeforeAll {
            function New-SyntheticAsarLock($Install) {
                @{
                    components = @{
                        copilotIntegration = @{ desktopProvisioning = @{ mode = 'desktopNativeVerifiedRelease' } }
                        desktop = @{
                            defaultRuntimeSelector = 'desktop-fork-managed'
                            runtimeSelectors = @(@{
                                id = 'desktop-fork-managed'; root = (Join-Path $Install 'resources\app.asar\dsh')
                                descriptor = @{ manifest = 'desktop-runtime.json'; sha256 = ('a' * 64) }
                                package = @{ version = '0.1.6-synthetic' }
                            })
                            installedRuntimeDescriptor = @{ relativePath = 'resources/app.asar/dsh/desktop-runtime.json'; sha256 = ('a' * 64) }
                            installedExecutable = @{ relativePath = 'synthetic-desktop.exe'; sha256 = ('b' * 64) }
                            releaseChannel = @{ upstreamVersion = '0.1.6-synthetic' }
                        }
                    }
                }
            }
            function New-SyntheticAudit($Install) {
                @{
                    valid = $true; reason = $null
                    runtime = @{
                        valid = $true; status = 'runtime-tree-verified'; reason = $null; mode = 'asar-runtime'
                        version = '0.1.6-synthetic'; fileCount = 17; descriptorSha256 = ('a' * 64)
                        runtimeRoot = (Join-Path $Install 'resources\app.asar\dsh')
                        carrierExecutable = (Join-Path $Install 'synthetic-desktop.exe'); executableSha256 = ('b' * 64)
                        metadataSnapshot = @{ private = 'PRIVATE-METADATA-SENTINEL' }
                    }
                    provisioning = @{ valid = $true; reason = $null; receipt = 'PRIVATE-RECEIPT-SENTINEL' }
                    stderr = 'PRIVATE-STDERR-SENTINEL'
                }
            }
        }
        BeforeEach {
            $script:install = Join-Path $TestDrive 'inert-desktop'
            $script:homePath = Join-Path $TestDrive 'inert-home'
            $script:lock = New-SyntheticAsarLock $script:install
            $script:audit = New-SyntheticAudit $script:install
            Mock Invoke-WindowsCopilotNativeFileAudit { $script:audit }
            Mock Test-WindowsCopilotLock { $true }
            Mock Test-Path { throw 'NO VIRTUAL TEST PATH' }
            Mock Get-Content { throw 'NO VIRTUAL CONTENT' }
            Mock Get-Item { throw 'NO VIRTUAL ITEM' }
            Mock Get-ChildItem { throw 'NO VIRTUAL WALK' }
            Mock Get-FileHash { throw 'NO VIRTUAL HASH' }
            Mock Get-WindowsCopilotDirectoryTreeState { throw 'NO WRAPPER WALK' }
            Mock Test-WindowsCopilotNativeInstallation { throw 'NO RECURSION' }
            Mock Test-DshUserPresetConfig { throw 'NO PRESET RECURSION' }
            Mock New-WindowsCopilotNativeAuditProcess { throw 'NO PROCESS' }
            Mock Stop-WindowsCopilotNativeAuditProcess { throw 'NO STOP' }
        }
        AfterEach {
            foreach ($command in @('Test-Path', 'Get-Content', 'Get-Item', 'Get-ChildItem', 'Get-FileHash',
                'Get-WindowsCopilotDirectoryTreeState', 'Test-WindowsCopilotNativeInstallation', 'Test-DshUserPresetConfig',
                'New-WindowsCopilotNativeAuditProcess', 'Stop-WindowsCopilotNativeAuditProcess')) {
                Should -Invoke $command -Times 0 -Exactly
            }
        }
        It 'accepts full JS-valid correlated evidence and keeps descriptor identity separate from CLI/tree identity' {
            $result = Get-WindowsCopilotOfficialRuntimeState -Lock $script:lock -DshHome $script:homePath
            $result.valid | Should -BeTrue
            $result.status | Should -BeExactly 'runtime-asar-verified'
            $result.mode | Should -BeExactly 'asar-runtime'
            $result.immutable | Should -BeTrue
            $result.version | Should -BeExactly '0.1.6-synthetic'
            $result.fileCount | Should -Be 17
            $result.root | Should -BeExactly $script:audit.runtime.runtimeRoot
            $result.packageRoot | Should -BeExactly $result.root
            $result.descriptorPath | Should -BeExactly (Join-Path $result.root 'desktop-runtime.json')
            $result.descriptorSha256 | Should -BeExactly ('a' * 64)
            foreach ($name in @('entryPath', 'entrypointSha256', 'entrypointSize', 'treeSha256', 'wrapperFileCount',
                'wrapperTotalBytes', 'wrapperTreeSha256', 'wrapperReparseDirectoryCount')) {
                $result.$name | Should -BeNullOrEmpty
            }
            $result.modelResponseVerified | Should -BeFalse
            ($result | ConvertTo-Json -Depth 20) | Should -Not -Match 'PRIVATE-|metadataSnapshot|receipt|stderr'
            Should -Invoke Invoke-WindowsCopilotNativeFileAudit -Times 1 -Exactly -ParameterFilter {
                $InstallRoot -eq $script:install -and $DshHome -eq $script:homePath -and $Lock -eq $script:lock
            }
        }
        It 'uses default home only as a lexical mock argument, never accessing it' {
            Get-WindowsCopilotOfficialRuntimeState -Lock $script:lock | Out-Null
            Should -Invoke Invoke-WindowsCopilotNativeFileAudit -Times 1 -Exactly -ParameterFilter {
                $DshHome -eq (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.dsh')
            }
        }
        It 'expands the explicitly supplied synthetic home before forwarding' {
            $previous = $env:DSH_SYNTHETIC_AUDIT_HOME
            try {
                $env:DSH_SYNTHETIC_AUDIT_HOME = $script:homePath
                Get-WindowsCopilotOfficialRuntimeState -Lock $script:lock -DshHome '%DSH_SYNTHETIC_AUDIT_HOME%' | Out-Null
                Should -Invoke Invoke-WindowsCopilotNativeFileAudit -Times 1 -Exactly -ParameterFilter { $DshHome -eq $script:homePath }
            } finally { $env:DSH_SYNTHETIC_AUDIT_HOME = $previous }
        }
        It 'rejects correlated runtime leaf <Field> = <Value>' -ForEach @(
            @{ Field = 'mode'; Value = 'physical-runtime' }
            @{ Field = 'status'; Value = 'runtime-descriptor-verified' }
            @{ Field = 'version'; Value = '0.1.6-other' }
            @{ Field = 'descriptorSha256'; Value = ('c' * 64) }
            @{ Field = 'runtimeRoot'; Value = 'unrelated-root' }
            @{ Field = 'carrierExecutable'; Value = 'unrelated.exe' }
            @{ Field = 'executableSha256'; Value = ('c' * 64) }
            @{ Field = 'fileCount'; Value = '17' }
            @{ Field = 'fileCount'; Value = $true }
            @{ Field = 'fileCount'; Value = 0 }
            @{ Field = 'fileCount'; Value = -1 }
            @{ Field = 'fileCount'; Value = 200001 }
            @{ Field = 'fileCount'; Value = 1.5 }
            @{ Field = 'fileCount'; Value = [double]::NaN }
            @{ Field = 'fileCount'; Value = [double]::PositiveInfinity }
            @{ Field = 'fileCount'; Value = $null }
        ) {
            $script:audit.runtime[$Field] = $Value
            $result = Get-WindowsCopilotOfficialRuntimeState -Lock $script:lock -DshHome $script:homePath
            $result.valid | Should -BeFalse
            $result.status | Should -BeExactly 'native-asar-audit-not-ready'
            $result.reason | Should -BeExactly 'native-audit-correlation-mismatch'
            $result.version | Should -BeNullOrEmpty
            $result.fileCount | Should -BeNullOrEmpty
            $result.descriptorSha256 | Should -BeNullOrEmpty
        }
        It 'requires a string for mandatory success leaf <Field>' -ForEach @(
            @{ Field = 'mode' }, @{ Field = 'status' }, @{ Field = 'version' }, @{ Field = 'descriptorSha256' },
            @{ Field = 'runtimeRoot' }, @{ Field = 'carrierExecutable' }, @{ Field = 'executableSha256' }
        ) {
            $script:audit.runtime[$Field] = $null
            $result = Get-WindowsCopilotOfficialRuntimeState -Lock $script:lock -DshHome $script:homePath
            $result.valid | Should -BeFalse
            $result.reason | Should -BeExactly 'native-audit-input-or-protocol-invalid'
            $result.version | Should -BeNullOrEmpty
            $result.fileCount | Should -BeNullOrEmpty
        }
        It 'requires real booleans in <Section> evidence' -ForEach @(
            @{ Section = 'audit' }, @{ Section = 'runtime' }, @{ Section = 'provisioning' }
        ) {
            if ($Section -eq 'audit') { $script:audit.valid = 'true' } else { $script:audit[$Section].valid = 'true' }
            $result = Get-WindowsCopilotOfficialRuntimeState -Lock $script:lock -DshHome $script:homePath
            $result.valid | Should -BeFalse
            $result.reason | Should -BeExactly 'native-audit-input-or-protocol-invalid'
            $result.version | Should -BeNullOrEmpty
            $result.fileCount | Should -BeNullOrEmpty
        }
        It 'fails closed for <Failure> with precise sanitized not-ready state' -ForEach @(
            @{ Failure = 'runtime'; Status = 'native-asar-audit-not-ready'; Reason = 'native-runtime-hash-mismatch' }
            @{ Failure = 'metadata'; Status = 'native-asar-audit-prerequisite-not-ready'; Reason = 'native-provisioning-metadata-invalid' }
            @{ Failure = 'missing-home'; Status = 'native-asar-audit-prerequisite-not-ready'; Reason = 'native-audit-profile-prerequisite-missing' }
            @{ Failure = 'stderr'; Status = 'native-asar-audit-not-ready'; Reason = 'native-audit-not-ready' }
            @{ Failure = 'throw'; Status = 'native-asar-audit-not-ready'; Reason = 'native-audit-input-or-protocol-invalid' }
        ) {
            switch ($Failure) {
                runtime { $script:audit.valid = $false; $script:audit.runtime.valid = $false; $script:audit.runtime.reason = $Reason; $script:audit.provisioning.valid = $false; $script:audit.provisioning.reason = 'native-runtime-prerequisite-failed' }
                metadata { $script:audit.valid = $false; $script:audit.provisioning.valid = $false; $script:audit.provisioning.reason = $Reason }
                missing-home { $script:audit = @{ valid = $false; reason = $Reason } }
                stderr { $script:audit = @{ valid = $false; reason = 'PRIVATE-STDERR-SENTINEL' } }
                throw { Mock Invoke-WindowsCopilotNativeFileAudit { throw 'PRIVATE-METADATA-SENTINEL' } }
            }
            $result = Get-WindowsCopilotOfficialRuntimeState -Lock $script:lock -DshHome $script:homePath
            $result.valid | Should -BeFalse
            $result.status | Should -BeExactly $Status
            $result.reason | Should -BeExactly $Reason
            $result.version | Should -BeNullOrEmpty
            $result.fileCount | Should -BeNullOrEmpty
            ($result | ConvertTo-Json -Depth 20) | Should -Not -Match 'PRIVATE-|metadataSnapshot|receipt|stderr'
        }
        It 'rejects inconsistent lock <Mismatch> before the audit' -ForEach @(
            @{ Mismatch = 'descriptor-path' }, @{ Mismatch = 'manifest' }, @{ Mismatch = 'descriptor-pin' },
            @{ Mismatch = 'version-pin' }, @{ Mismatch = 'hash-format' }, @{ Mismatch = 'root-layout' }
        ) {
            $selector = $script:lock.components.desktop.runtimeSelectors[0]
            switch ($Mismatch) {
                descriptor-path { $script:lock.components.desktop.installedRuntimeDescriptor.relativePath = 'resources/app.asar/dsh/other.json' }
                manifest { $selector.descriptor.manifest = 'other.json' }
                descriptor-pin { $selector.descriptor.sha256 = ('c' * 64) }
                version-pin { $selector.package.version = '0.1.6-other' }
                hash-format { $selector.descriptor.sha256 = 'invalid'; $script:lock.components.desktop.installedRuntimeDescriptor.sha256 = 'invalid' }
                root-layout { $selector.root = Join-Path $script:install 'resources\other.asar\dsh' }
            }
            $result = Get-WindowsCopilotOfficialRuntimeState -Lock $script:lock -DshHome $script:homePath
            $result.valid | Should -BeFalse
            $result.status | Should -BeExactly 'native-asar-layout-unsupported'
            $result.reason | Should -BeExactly 'native-runtime-layout-unsupported'
            $result.version | Should -BeNullOrEmpty
            $result.fileCount | Should -BeNullOrEmpty
            Should -Invoke Invoke-WindowsCopilotNativeFileAudit -Times 0 -Exactly
        }
        It 'rejects an explicitly supplied executable with the wrong filename before audit' {
            $result = Get-WindowsCopilotOfficialRuntimeState -Lock $script:lock -DshHome $script:homePath -DesktopExecutablePath (Join-Path $script:install 'other.exe')
            $result.valid | Should -BeFalse
            $result.reason | Should -BeExactly 'native-audit-executable-mismatch'
            Should -Invoke Invoke-WindowsCopilotNativeFileAudit -Times 0 -Exactly
        }
    }
}

Describe 'Native file audit physical prerequisites and minimal JSON projection' {
    InModuleScope WindowsCopilotDeployment {
        BeforeEach {
            $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $script:install = Join-Path $caseRoot 'physical-desktop'
            $script:homePath = Join-Path $caseRoot 'physical-home'
            $script:nodePath = Join-Path $caseRoot 'audit-tool\node.exe'
            $script:diagnostic = Join-Path $caseRoot 'diagnostic'
            foreach ($directory in @((Join-Path $script:install 'resources'), $script:homePath, (Split-Path $script:nodePath), $script:diagnostic)) {
                New-Item -ItemType Directory -Path $directory -Force | Out-Null
            }
            $script:exe = Join-Path $script:install 'synthetic-desktop.exe'
            $script:archive = Join-Path $script:install 'resources\app.asar'
            foreach ($path in @($script:exe, $script:archive, $script:nodePath)) { 'inert-not-executable' | Set-Content -LiteralPath $path }
            $script:lock = @{
                components = @{
                    copilotIntegration = @{ desktopProvisioning = @{ mode = 'desktopNativeVerifiedRelease' } }
                    desktop = @{
                        installedRuntimeDescriptor = @{ relativePath = 'resources/app.asar/dsh/desktop-runtime.json'; sha256 = ('a' * 64) }
                        installedExecutable = @{ relativePath = 'synthetic-desktop.exe'; sha256 = (Get-FileHash $script:exe).Hash.ToLowerInvariant() }
                    }
                }
            }
            $script:parsed = @{
                valid = $true; mutated = $false; functional = @{ modelResponseVerified = $false; private = 'PRIVATE-FUNCTIONAL-SENTINEL' }
                runtime = @{
                    valid = $true; status = 'runtime-tree-verified'; mode = 'asar-runtime'; reason = $null; fileCount = 17
                    version = '0.1.6-synthetic'; runtimeRoot = (Join-Path $script:install 'resources\app.asar\dsh')
                    carrierExecutable = $script:exe; executableSha256 = $script:lock.components.desktop.installedExecutable.sha256
                    descriptorSha256 = ('a' * 64); metadataSnapshot = @{ private = 'PRIVATE-METADATA-SENTINEL' }
                }
                provisioning = @{ valid = $true; reason = $null; receipt = 'PRIVATE-RECEIPT-SENTINEL' }
                metadataSnapshot = 'PRIVATE-TOPLEVEL-SENTINEL'; receipt = 'PRIVATE-TOPLEVEL-RECEIPT'
            }
            $script:oldTemp = $env:TEMP; $script:oldTmp = $env:TMP
            $env:TEMP = $script:diagnostic; $env:TMP = $script:diagnostic
            Mock Get-Command { [pscustomobject]@{ Source = $script:nodePath } } -ParameterFilter { $Name -eq 'node.exe' }
            Mock Invoke-WindowsCopilotNativeAuditProcess { @{ valid = $true; output = ($script:parsed | ConvertTo-Json -Depth 20 -Compress) } }
            Mock New-WindowsCopilotNativeAuditProcess { throw 'NO REAL PROCESS FACTORY' }
            Mock Stop-WindowsCopilotNativeAuditProcess { throw 'NO REAL STOP' }
            Mock Test-WindowsCopilotNativeInstallation { throw 'NO RECURSION' }
            Mock Test-DshUserPresetConfig { throw 'NO PRESETS' }
            Mock Get-Content { throw 'NO VIRTUAL CONTENT' }
            Mock Test-Path { throw 'NO VIRTUAL PATH' } -ParameterFilter { $LiteralPath -match '(?i)\.asar[\\/]' }
            Mock Get-FileHash { throw 'NO VIRTUAL HASH' } -ParameterFilter { $LiteralPath -match '(?i)\.asar[\\/]' }
        }
        AfterEach {
            $env:TEMP = $script:oldTemp; $env:TMP = $script:oldTmp
            Should -Invoke New-WindowsCopilotNativeAuditProcess -Times 0 -Exactly
            Should -Invoke Stop-WindowsCopilotNativeAuditProcess -Times 0 -Exactly
            Should -Invoke Test-WindowsCopilotNativeInstallation -Times 0 -Exactly
            Should -Invoke Test-DshUserPresetConfig -Times 0 -Exactly
            Should -Invoke Get-Content -Times 0 -Exactly
            Should -Invoke Test-Path -Times 0 -Exactly -ParameterFilter { $LiteralPath -match '(?i)\.asar[\\/]' }
            Should -Invoke Get-FileHash -Times 0 -Exactly -ParameterFilter { $LiteralPath -match '(?i)\.asar[\\/]' }
        }
        It 'hashes the physical EXE and sends only canonical physical roots to the mocked backend' {
            $result = Invoke-WindowsCopilotNativeFileAudit -Lock $script:lock -InstallRoot $script:install -DshHome $script:homePath
            $result.valid | Should -BeTrue
            $result.runtime.fileCount | Should -Be 17
            $result.runtime.descriptorSha256 | Should -BeExactly ('a' * 64)
            ($result | ConvertTo-Json -Depth 20) | Should -Not -Match 'PRIVATE-|metadataSnapshot|receipt|functional'
            @($result.PSObject.Properties.Name | Sort-Object) -join ',' | Should -Be 'modelResponseVerified,provisioning,runtime,valid'
            @($result.runtime.PSObject.Properties.Name | Sort-Object) -join ',' | Should -Be 'carrierExecutable,descriptorSha256,executableSha256,fileCount,mode,reason,runtimeRoot,status,valid,version'
            Should -Invoke Invoke-WindowsCopilotNativeAuditProcess -Times 1 -Exactly -ParameterFilter {
                $request = $InputJson | ConvertFrom-Json
                $NodePath -eq $script:nodePath -and $DiagnosticRoot -eq $script:diagnostic -and
                $request.installRoot -eq $script:install -and $request.dshHome -eq $script:homePath -and
                $request.lock.components.desktop.installedExecutable.sha256 -eq $script:lock.components.desktop.installedExecutable.sha256
            }
        }
        It 'rejects physical prerequisite <Failure> before any backend call' -ForEach @(
            @{ Failure = 'exe-hash'; Reason = 'native-audit-executable-mismatch' }
            @{ Failure = 'missing-exe'; Reason = 'native-audit-installed-evidence-missing' }
            @{ Failure = 'missing-archive'; Reason = 'native-audit-installed-evidence-missing' }
            @{ Failure = 'missing-home'; Reason = 'native-audit-profile-prerequisite-missing' }
            @{ Failure = 'wrong-layout'; Reason = 'native-audit-input-tool-or-protocol-invalid' }
            @{ Failure = 'exe-traversal'; Reason = 'native-audit-input-tool-or-protocol-invalid' }
            @{ Failure = 'virtual-home'; Reason = 'native-audit-input-tool-or-protocol-invalid' }
            @{ Failure = 'reparse'; Reason = 'native-audit-input-tool-or-protocol-invalid' }
            @{ Failure = 'missing-node'; Reason = 'native-audit-input-tool-or-protocol-invalid' }
            @{ Failure = 'relative-node'; Reason = 'native-audit-input-tool-or-protocol-invalid' }
            @{ Failure = 'node-inside-install'; Reason = 'native-audit-input-tool-or-protocol-invalid' }
            @{ Failure = 'node-inside-home'; Reason = 'native-audit-input-tool-or-protocol-invalid' }
            @{ Failure = 'node-virtual'; Reason = 'native-audit-input-tool-or-protocol-invalid' }
            @{ Failure = 'node-not-file'; Reason = 'native-audit-input-tool-or-protocol-invalid' }
            @{ Failure = 'archive-directory'; Reason = 'native-audit-installed-evidence-missing' }
            @{ Failure = 'relative-install'; Reason = 'native-audit-input-tool-or-protocol-invalid' }
            @{ Failure = 'home-reparse'; Reason = 'native-audit-input-tool-or-protocol-invalid' }
            @{ Failure = 'node-reparse'; Reason = 'native-audit-input-tool-or-protocol-invalid' }
        ) {
            switch ($Failure) {
                exe-hash { $script:lock.components.desktop.installedExecutable.sha256 = ('c' * 64) }
                missing-exe { Remove-Item -LiteralPath $script:exe }
                missing-archive { Remove-Item -LiteralPath $script:archive }
                missing-home { Remove-Item -LiteralPath $script:homePath }
                wrong-layout { $script:lock.components.desktop.installedRuntimeDescriptor.relativePath = 'resources/dsh/desktop-runtime.json' }
                exe-traversal { $script:lock.components.desktop.installedExecutable.relativePath = '..\escape.exe' }
                virtual-home { $script:homePath = Join-Path $TestDrive 'private.asar\home' }
                reparse { Mock Assert-NoReparsePointAncestor { throw 'synthetic reparse' } -ParameterFilter { $Path -eq $script:archive } }
                missing-node { Mock Get-Command { throw 'synthetic missing node' } -ParameterFilter { $Name -eq 'node.exe' } }
                relative-node { $script:nodePath = 'node.exe' }
                node-inside-install { $script:nodePath = $script:exe }
                node-inside-home { $script:nodePath = Join-Path $script:homePath 'node.exe'; 'inert' | Set-Content $script:nodePath }
                node-virtual { $script:nodePath = Join-Path $script:install 'resources\app.asar\node.exe' }
                node-not-file { Remove-Item -LiteralPath $script:nodePath }
                archive-directory { Remove-Item -LiteralPath $script:archive; New-Item -ItemType Directory $script:archive | Out-Null }
                relative-install { $script:install = 'relative-install' }
                home-reparse { Mock Assert-NoReparsePointAncestor { throw 'synthetic reparse' } -ParameterFilter { $Path -eq $script:homePath } }
                node-reparse { Mock Assert-NoReparsePointAncestor { throw 'synthetic reparse' } -ParameterFilter { $Path -eq $script:nodePath } }
            }
            $result = Invoke-WindowsCopilotNativeFileAudit -Lock $script:lock -InstallRoot $script:install -DshHome $script:homePath
            $result.valid | Should -BeFalse
            $result.reason | Should -BeExactly $Reason
            Should -Invoke Invoke-WindowsCopilotNativeAuditProcess -Times 0 -Exactly
        }
        It 'preserves a fixed cleanup failure from the backend <Delivery>' -ForEach @(
            @{ Delivery = 'throw' }, @{ Delivery = 'return' }
        ) {
            if ($Delivery -eq 'throw') {
                Mock Invoke-WindowsCopilotNativeAuditProcess { throw 'native-audit-termination-failed' }
            } else {
                Mock Invoke-WindowsCopilotNativeAuditProcess { @{ valid = $false; reason = 'native-audit-termination-failed'; stderr = 'PRIVATE-SENTINEL' } }
            }
            $result = Invoke-WindowsCopilotNativeFileAudit -Lock $script:lock -InstallRoot $script:install -DshHome $script:homePath
            $result.valid | Should -BeFalse
            $result.reason | Should -BeExactly 'native-audit-termination-failed'
            ($result | ConvertTo-Json -Depth 20) | Should -Not -Match 'PRIVATE-|stderr'
            Should -Invoke Invoke-WindowsCopilotNativeAuditProcess -Times 1 -Exactly
        }
        It 'rejects malformed or string-boolean backend protocol <Failure>' -ForEach @(
            @{ Failure = 'malformed-json' }, @{ Failure = 'process-string-bool' }, @{ Failure = 'valid-string-bool' },
            @{ Failure = 'runtime-string-bool' }, @{ Failure = 'provisioning-string-bool' }, @{ Failure = 'mutated-string-bool' },
            @{ Failure = 'functional-string-bool' }, @{ Failure = 'mutated-true' }, @{ Failure = 'functional-true' },
            @{ Failure = 'runtime-object' }, @{ Failure = 'output-limit' }, @{ Failure = 'output-object' },
            @{ Failure = 'provisioning-reason-object' }, @{ Failure = 'provisioning-reason-private' },
            @{ Failure = 'runtime-reason-private' }, @{ Failure = 'runtime-reason-long' },
            @{ Failure = 'count-object' }, @{ Failure = 'count-string' }, @{ Failure = 'count-bool' },
            @{ Failure = 'count-fraction' }, @{ Failure = 'count-negative' }, @{ Failure = 'count-too-large' },
            @{ Failure = 'backend-private-reason' }, @{ Failure = 'backend-object-reason' }
        ) {
            switch ($Failure) {
                malformed-json { Mock Invoke-WindowsCopilotNativeAuditProcess { @{ valid = $true; output = '{PRIVATE-MALFORMED' } } }
                process-string-bool { Mock Invoke-WindowsCopilotNativeAuditProcess { @{ valid = 'true'; output = '{}' } } }
                valid-string-bool { $script:parsed.valid = 'true' }
                runtime-string-bool { $script:parsed.runtime.valid = 'true' }
                provisioning-string-bool { $script:parsed.provisioning.valid = 'true' }
                mutated-string-bool { $script:parsed.mutated = 'false' }
                functional-string-bool { $script:parsed.functional.modelResponseVerified = 'false' }
                mutated-true { $script:parsed.mutated = $true }
                functional-true { $script:parsed.functional.modelResponseVerified = $true }
                runtime-object { $script:parsed.runtime.version = @{ private = 'PRIVATE-SENTINEL' } }
                provisioning-reason-object { $script:parsed.provisioning.reason = @{ private = 'PRIVATE-SENTINEL' } }
                provisioning-reason-private { $script:parsed.provisioning.reason = 'PRIVATE-SENTINEL' }
                runtime-reason-private { $script:parsed.runtime.reason = 'PRIVATE-SENTINEL' }
                runtime-reason-long { $script:parsed.runtime.reason = 'native-' + ('x' * 121) }
                count-object { $script:parsed.runtime.fileCount = @{ private = 'PRIVATE-SENTINEL' } }
                count-string { $script:parsed.runtime.fileCount = '17' }
                count-bool { $script:parsed.runtime.fileCount = $true }
                count-fraction { $script:parsed.runtime.fileCount = 1.5 }
                count-negative { $script:parsed.runtime.fileCount = -1 }
                count-too-large { $script:parsed.runtime.fileCount = 200001 }
                backend-private-reason { Mock Invoke-WindowsCopilotNativeAuditProcess { @{ valid = $false; reason = 'PRIVATE-SENTINEL' } } }
                backend-object-reason { Mock Invoke-WindowsCopilotNativeAuditProcess { @{ valid = $false; reason = @{ private = 'PRIVATE-SENTINEL' } } } }
                output-object { Mock Invoke-WindowsCopilotNativeAuditProcess { @{ valid = $true; output = @{ private = 'PRIVATE-SENTINEL' } } } }
                output-limit { Mock Invoke-WindowsCopilotNativeAuditProcess { @{ valid = $true; output = ('x' * (1MB + 1)) } } }
            }
            $result = Invoke-WindowsCopilotNativeFileAudit -Lock $script:lock -InstallRoot $script:install -DshHome $script:homePath
            $result.valid | Should -BeFalse
            $result.reason | Should -BeExactly 'native-audit-input-tool-or-protocol-invalid'
            ($result | ConvertTo-Json -Depth 20) | Should -Not -Match 'PRIVATE-'
            Should -Invoke Invoke-WindowsCopilotNativeAuditProcess -Times 1 -Exactly
        }
    }
}

Describe 'Native diagnostic termination requires confirmed cleanup of only its supplied fake PID' {
    InModuleScope WindowsCopilotDeployment {
        BeforeEach {
            $script:killExit = 0
            $script:terminationFake = [pscustomobject]@{
                Id = 987654321; HasExited = $false; ExitAfterWait = $true; WaitResult = $true
                WaitCount = 0; WaitMilliseconds = 0
            }
            $script:terminationFake | Add-Member ScriptMethod WaitForExit {
                param($Milliseconds)
                $this.WaitCount++; $this.WaitMilliseconds = $Milliseconds
                $this.HasExited = $this.ExitAfterWait
                return $this.WaitResult
            }
            # Never invoke the OS taskkill wrapper; exercise only the stop policy.
            Mock Invoke-WindowsCopilotNativeAuditTaskKill { $script:killExit }
        }
        AfterEach {
            Should -Invoke Invoke-WindowsCopilotNativeAuditTaskKill -Times 0 -Exactly -ParameterFilter { $ProcessId -ne 987654321 }
        }
        It 'requires zero exit, true wait and confirmed exit for the supplied fake PID' {
            { Stop-WindowsCopilotNativeAuditProcess -Process $script:terminationFake } | Should -Not -Throw
            Should -Invoke Invoke-WindowsCopilotNativeAuditTaskKill -Times 1 -Exactly -ParameterFilter { $ProcessId -eq 987654321 }
            $script:terminationFake.WaitCount | Should -Be 1
            $script:terminationFake.WaitMilliseconds | Should -Be 5000
            $script:terminationFake.HasExited | Should -BeTrue
        }
        It 'does not invoke taskkill or wait for an already-exited fake' {
            $script:terminationFake.HasExited = $true
            { Stop-WindowsCopilotNativeAuditProcess -Process $script:terminationFake } | Should -Not -Throw
            Should -Invoke Invoke-WindowsCopilotNativeAuditTaskKill -Times 0 -Exactly
            $script:terminationFake.WaitCount | Should -Be 0
        }
        It 'throws the fixed termination failure for <Failure>' -ForEach @(
            @{ Failure = 'nonzero-exit' }, @{ Failure = 'string-exit' }, @{ Failure = 'wait-false' },
            @{ Failure = 'wait-string' }, @{ Failure = 'still-alive' }, @{ Failure = 'taskkill-throws' }, @{ Failure = 'wait-throws' }
        ) {
            switch ($Failure) {
                nonzero-exit { $script:killExit = 5 }
                string-exit { $script:killExit = '0' }
                wait-false { $script:terminationFake.WaitResult = $false }
                wait-string { $script:terminationFake.WaitResult = 'true' }
                still-alive { $script:terminationFake.ExitAfterWait = $false }
                taskkill-throws { Mock Invoke-WindowsCopilotNativeAuditTaskKill { throw 'PRIVATE-TASKKILL-SENTINEL' } }
                wait-throws { $script:terminationFake | Add-Member ScriptMethod WaitForExit { throw 'PRIVATE-WAIT-SENTINEL' } -Force }
            }
            { Stop-WindowsCopilotNativeAuditProcess -Process $script:terminationFake } |
                Should -Throw -ExpectedMessage 'native-audit-termination-failed'
            Should -Invoke Invoke-WindowsCopilotNativeAuditTaskKill -Times 1 -Exactly -ParameterFilter { $ProcessId -eq 987654321 }
        }
    }
}

Describe 'Native diagnostic process runner with inert managed stream process doubles' {
    InModuleScope WindowsCopilotDeployment {
        BeforeAll {
            function New-InertAuditProcess([string]$Stdout, [string]$Stderr, [bool]$Exited = $true, [int]$ExitCode = 0) {
                $inputStream = [IO.MemoryStream]::new()
                $outputStream = [IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($Stdout))
                $errorStream = [IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($Stderr))
                $fake = [pscustomobject]@{
                    Id = 987654321; HasExited = $Exited; ExitCode = $ExitCode; StartInfo = $null
                    StartCount = 0; DisposeCount = 0; WaitCount = 0; InputBytes = $null
                    InputMemory = $inputStream
                    # Deliberately BOM-capable: closing the writer after raw BaseStream writes would append EFBBBF.
                    StandardInput = [IO.StreamWriter]::new($inputStream, [Text.Encoding]::UTF8)
                    StandardOutput = [IO.StreamReader]::new($outputStream, [Text.Encoding]::UTF8)
                    StandardError = [IO.StreamReader]::new($errorStream, [Text.Encoding]::UTF8)
                }
                $fake | Add-Member ScriptMethod Start { $this.StartCount++; return $true }
                $fake | Add-Member ScriptMethod WaitForExit { param($Milliseconds); $this.WaitCount++; return $this.HasExited }
                $fake | Add-Member ScriptMethod Dispose {
                    $this.InputBytes = $this.InputMemory.ToArray()
                    $this.DisposeCount++
                    # Do not flush the writer from this process double's cleanup; the runner owns raw pipe closure.
                    $this.StandardOutput.Dispose(); $this.StandardError.Dispose(); $this.InputMemory.Dispose()
                }
                return $fake
            }
        }
        BeforeEach {
            $script:diagnostic = Join-Path $TestDrive 'diagnostic'
            $script:nodePath = Join-Path $TestDrive 'inert-tool\node.exe'
            $script:fake = New-InertAuditProcess '{"valid":true}' ''
            Mock New-WindowsCopilotNativeAuditProcess { $script:fake }
            # Never invoke real taskkill, Process.Start, or a pre-existing PID.
            Mock Stop-WindowsCopilotNativeAuditProcess {
                param($Process)
                if ($Process -ne $script:fake -or $Process.Id -ne 987654321) { throw 'not the owned fake process' }
                $Process.HasExited = $true
            }
        }
        AfterEach {
            $script:fake.StartCount | Should -BeLessOrEqual 1
            Should -Invoke Stop-WindowsCopilotNativeAuditProcess -Times 0 -Exactly -ParameterFilter { $Process -ne $script:fake }
        }
        It 'writes exact BOM-free UTF8 stdin and uses a shell-free allowlisted environment' {
            $names = @('GH_TOKEN', 'GITHUB_TOKEN', 'NODE_OPTIONS', 'NODE_PATH', 'DSH_HOME', 'DSH_CLI_PATH', 'ELECTRON_RUN_AS_NODE')
            $previous = @{}
            try {
                foreach ($name in $names) { $previous[$name] = [Environment]::GetEnvironmentVariable($name); [Environment]::SetEnvironmentVariable($name, 'PRIVATE-ENV-SENTINEL') }
                $json = '{"path":"' + [char]0x6d4b + [char]0x8bd5 + '"}'
                $result = Invoke-WindowsCopilotNativeAuditProcess -NodePath $script:nodePath -InputJson $json -DiagnosticRoot $script:diagnostic
                $result.valid | Should -BeTrue
                $result.output | Should -BeExactly '{"valid":true}'
                [Convert]::ToBase64String($script:fake.InputBytes) | Should -BeExactly ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json)))
                $start = $script:fake.StartInfo
                $start.FileName | Should -BeExactly $script:nodePath
                $start.UseShellExecute | Should -BeFalse
                $start.CreateNoWindow | Should -BeTrue
                $start.RedirectStandardInput | Should -BeTrue
                $start.RedirectStandardOutput | Should -BeTrue
                $start.RedirectStandardError | Should -BeTrue
                $start.WorkingDirectory | Should -BeExactly $script:diagnostic
                $start.Arguments | Should -Match '^--max-old-space-size=512 ".*verify-native-desktop\.mjs"$'
                foreach ($name in $names) { $start.EnvironmentVariables.ContainsKey($name) | Should -BeFalse }
                foreach ($name in @('TEMP', 'TMP', 'HOME', 'USERPROFILE')) { $start.EnvironmentVariables[$name] | Should -BeExactly $script:diagnostic }
                foreach ($name in $start.EnvironmentVariables.Keys) { $name | Should -BeIn @('SystemRoot', 'WINDIR', 'TEMP', 'TMP', 'HOME', 'USERPROFILE') }
                $script:fake.StartCount | Should -Be 1
                $script:fake.DisposeCount | Should -Be 1
                Should -Invoke Stop-WindowsCopilotNativeAuditProcess -Times 0 -Exactly
            } finally { foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $previous[$name]) } }
        }
        It 'rejects oversized UTF8 input before requesting even a fake process' {
            # Fewer than 1MB characters, but more than 1MB encoded bytes.
            $result = Invoke-WindowsCopilotNativeAuditProcess -NodePath $script:nodePath -InputJson (([string][char]0x6d4b) * 350000) -DiagnosticRoot $script:diagnostic
            $result.valid | Should -BeFalse
            $result.reason | Should -BeExactly 'native-audit-input-limit'
            Should -Invoke New-WindowsCopilotNativeAuditProcess -Times 0 -Exactly
            $script:fake.Dispose()
        }
        It 'bounds <Channel> and only stops the owned fake process' -ForEach @(
            @{ Channel = 'stdout' }, @{ Channel = 'stderr' }
        ) {
            $script:fake.Dispose()
            $script:fake = if ($Channel -eq 'stdout') { New-InertAuditProcess (([string][char]0x6d4b) * 350000) '' $false }
                else { New-InertAuditProcess '' (([string][char]0x6d4b) * 5500) $false }
            $result = Invoke-WindowsCopilotNativeAuditProcess -NodePath $script:nodePath -InputJson '{}' -DiagnosticRoot $script:diagnostic
            $result.valid | Should -BeFalse
            $result.reason | Should -BeExactly 'native-audit-output-limit'
            Should -Invoke Stop-WindowsCopilotNativeAuditProcess -Times 1 -Exactly -ParameterFilter { $Process -eq $script:fake -and $Process.Id -eq 987654321 }
            $script:fake.DisposeCount | Should -Be 1
        }
        It 'times out a nonexiting fake and never stops a real process' {
            $script:fake.HasExited = $false
            $result = Invoke-WindowsCopilotNativeAuditProcess -NodePath $script:nodePath -InputJson '{}' -DiagnosticRoot $script:diagnostic -TimeoutSeconds 1
            $result.valid | Should -BeFalse
            $result.reason | Should -BeExactly 'native-audit-timeout'
            Should -Invoke Stop-WindowsCopilotNativeAuditProcess -Times 1 -Exactly -ParameterFilter { $Process -eq $script:fake -and $Process.Id -eq 987654321 }
            $script:fake.DisposeCount | Should -Be 1
        }
        It 'sanitizes a HasExited getter failure after start without disposing an unconfirmed fake handle' {
            Mock Invoke-WindowsCopilotNativeAuditTaskKill { throw 'NO REAL TASKKILL' }
            # PS5.1 can suppress a ScriptProperty getter exception to null. Bound the
            # timeout; any resulting stop/retry is still only the inherited fake mock.
            $script:fake | Add-Member ScriptProperty HasExited {
                if ($this.StartCount -gt 0) { throw 'PRIVATE-HASEXITED-SENTINEL' }
                return $false
            } -Force
            try {
                { Invoke-WindowsCopilotNativeAuditProcess -NodePath $script:nodePath -InputJson '{}' -DiagnosticRoot $script:diagnostic -TimeoutSeconds 1 } |
                    Should -Throw -ExpectedMessage 'native-audit-termination-failed'
                $script:fake.StartCount | Should -Be 1
                $script:fake.DisposeCount | Should -Be 0
                Should -Invoke Invoke-WindowsCopilotNativeAuditTaskKill -Times 0 -Exactly
            } finally {
                # Dispose only the test's managed memory, never an OS process.
                $script:fake.Dispose()
            }
        }
        It 'propagates final cleanup failure and retains the still-running fake handle' {
            $script:fake.Dispose()
            $script:fake = New-InertAuditProcess '' ('x' * 16385) $false
            Mock Stop-WindowsCopilotNativeAuditProcess { throw 'native-audit-termination-failed' }
            try {
                { Invoke-WindowsCopilotNativeAuditProcess -NodePath $script:nodePath -InputJson '{}' -DiagnosticRoot $script:diagnostic } |
                    Should -Throw -ExpectedMessage 'native-audit-termination-failed'
                Should -Invoke Stop-WindowsCopilotNativeAuditProcess -Times 2 -Exactly -ParameterFilter { $Process -eq $script:fake }
                $script:fake.HasExited | Should -BeFalse
                $script:fake.DisposeCount | Should -Be 0
            } finally {
                # This is only an in-memory fake, not an OS process or real handle.
                $script:fake.Dispose()
            }
        }
        It 'keeps the first cleanup failure not-ready even when the final retry succeeds' {
            $script:fake.Dispose()
            $script:fake = New-InertAuditProcess '' ('x' * 16385) $false
            $script:stopAttempt = 0
            Mock Stop-WindowsCopilotNativeAuditProcess {
                param($Process)
                $script:stopAttempt++
                if ($script:stopAttempt -eq 1) { throw 'native-audit-termination-failed' }
                $Process.HasExited = $true
            }
            $result = Invoke-WindowsCopilotNativeAuditProcess -NodePath $script:nodePath -InputJson '{}' -DiagnosticRoot $script:diagnostic
            $result.valid | Should -BeFalse
            $result.reason | Should -BeExactly 'native-audit-termination-failed'
            Should -Invoke Stop-WindowsCopilotNativeAuditProcess -Times 2 -Exactly -ParameterFilter { $Process -eq $script:fake }
            $script:fake.HasExited | Should -BeTrue
            $script:fake.DisposeCount | Should -Be 1
        }
        It 'does not return raw output on <Failure>' -ForEach @(
            @{ Failure = 'stderr' }, @{ Failure = 'exit-code' }, @{ Failure = 'start-exception' }
        ) {
            switch ($Failure) {
                stderr { $script:fake.Dispose(); $script:fake = New-InertAuditProcess 'PRIVATE-STDOUT-SENTINEL' 'PRIVATE-STDERR-SENTINEL' }
                exit-code { $script:fake.ExitCode = 7 }
                start-exception { $script:fake | Add-Member ScriptMethod Start { throw 'PRIVATE-START-SENTINEL' } -Force }
            }
            $result = Invoke-WindowsCopilotNativeAuditProcess -NodePath $script:nodePath -InputJson '{}' -DiagnosticRoot $script:diagnostic
            $result.valid | Should -BeFalse
            $result.reason | Should -BeExactly 'native-audit-process-failed'
            ($result | ConvertTo-Json) | Should -Not -Match 'PRIVATE-|output|stderr'
            $script:fake.DisposeCount | Should -Be 1
        }
    }
}
