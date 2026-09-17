# Synthetic projection/command-line contracts only. No installed Desktop, Node,
# Electron, source CLI, registry discovery, network or live process control is used.
BeforeDiscovery {
    Import-Module (Join-Path $PSScriptRoot '..\tools\WindowsCopilotDeployment.psm1') -Force
}

Describe 'Desktop ASAR identity projects only full correlated native audit evidence' {
    InModuleScope WindowsCopilotDeployment {
        BeforeAll {
            function New-ProjectionLock([string] $Install) {
                @{
                    components = @{
                        desktop = @{
                            version = '0.1.6-alpha.1.cloga.1'
                            defaultRuntimeSelector = 'desktop-fork-managed'
                            runtimeSelectors = @(@{
                                id = 'desktop-fork-managed'; source = 'desktop-managed-release'
                                root = (Join-Path $Install 'resources\app.asar\dsh')
                                package = @{ name = '@deepseek-ai/dsh'; version = '0.1.6-alpha.1' }
                                descriptor = @{ manifest = 'desktop-runtime.json'; sha256 = ('a' * 64) }
                            })
                            installedExecutable = @{
                                relativePath = 'synthetic-desktop.exe'; size = 128; sha256 = ('b' * 64)
                                productVersion = '0.1.6.0'; productName = 'Synthetic Desktop'
                                fileDescription = 'Synthetic Desktop'; companyName = 'Synthetic publisher'
                                authenticodeStatus = 'NotSigned'
                            }
                            installedRuntimeDescriptor = @{
                                relativePath = 'resources\app.asar\dsh\desktop-runtime.json'; sha256 = ('a' * 64)
                            }
                            releaseChannel = @{
                                upstreamVersion = '0.1.6-alpha.1'
                                identity = @{ executableName = 'synthetic-desktop' }
                            }
                        }
                        copilotIntegration = @{ desktopProvisioning = @{ mode = 'desktopNativeVerifiedRelease' } }
                    }
                    acceptance = @{ runtimeSchema = @{ root = (Join-Path $Install 'resources\app.asar\dsh') } }
                }
            }
            function New-ProjectionAudit([string] $Install) {
                @{
                    valid = $true
                    runtime = @{
                        valid = $true; status = 'runtime-tree-verified'; mode = 'asar-runtime'
                        version = '0.1.6-alpha.1'; fileCount = 17
                        runtimeRoot = (Join-Path $Install 'resources\app.asar\dsh')
                        carrierExecutable = (Join-Path $Install 'synthetic-desktop.exe')
                        executableSha256 = ('b' * 64); descriptorSha256 = ('a' * 64)
                        metadataSnapshot = 'PRIVATE-METADATA-SENTINEL'
                    }
                    provisioning = @{ valid = $true; receipt = 'PRIVATE-RECEIPT-SENTINEL' }
                    stderr = 'PRIVATE-STDERR-SENTINEL'
                }
            }
        }

        BeforeEach {
            $script:install = 'C:\synthetic-desktop-projection\Desktop Spaces'
            $script:exePath = Join-Path $script:install 'synthetic-desktop.exe'
            $script:homePath = 'C:\synthetic-desktop-projection\explicit-home'
            $script:lock = New-ProjectionLock $script:install
            $script:audit = New-ProjectionAudit $script:install
            $script:exePresent = $true
            $script:exeHash = 'b' * 64
            $script:physicalDescriptor = $null
            $script:physicalDescriptorHash = 'a' * 64
            $script:signature = 'NotSigned'
            $script:fileItem = [pscustomobject]@{
                Length = 128
                VersionInfo = [pscustomobject]@{
                    ProductVersion = '0.1.6.0'; ProductName = 'Synthetic Desktop'
                    FileDescription = 'Synthetic Desktop'; CompanyName = 'Synthetic publisher'
                }
            }
            $script:savedDshHome = $env:DSH_HOME
            $script:savedProjectionHome = $env:DSH_TEST_PROJECTION_HOME
            Remove-Item Env:DSH_HOME, Env:DSH_TEST_PROJECTION_HOME -ErrorAction SilentlyContinue
            Mock Test-WindowsCopilotLock { $true }
            Mock Assert-NoReparsePointAncestor { }
            Mock Invoke-WindowsCopilotNativeFileAudit { $script:audit }
            Mock Test-Path {
                if ([string]$LiteralPath -match '(?i)\.asar([\\/]|$)') { throw 'VIRTUAL-TESTPATH-FORBIDDEN' }
                if ([string]$LiteralPath -eq $script:exePath) { return $script:exePresent }
                if ($script:physicalDescriptor -and [string]$LiteralPath -eq $script:physicalDescriptor) { return $true }
                return $false
            }
            Mock Get-Item {
                if ([string]$LiteralPath -ne $script:exePath) { throw 'UNEXPECTED-ITEM-PROBE' }
                $script:fileItem
            }
            Mock Get-FileHash {
                if ([string]$LiteralPath -match '(?i)\.asar([\\/]|$)') { throw 'VIRTUAL-HASH-FORBIDDEN' }
                if ([string]$LiteralPath -eq $script:exePath) { return [pscustomobject]@{ Hash = $script:exeHash } }
                if ($script:physicalDescriptor -and [string]$LiteralPath -eq $script:physicalDescriptor) {
                    return [pscustomobject]@{ Hash = $script:physicalDescriptorHash }
                }
                throw 'UNEXPECTED-HASH-PROBE'
            }
            Mock Get-AuthenticodeSignature { [pscustomobject]@{ Status = $script:signature } }
            Mock Get-Content { throw 'UNEXPECTED-CONTENT-READ' }
            Mock Get-ChildItem { throw 'UNEXPECTED-DIRECTORY-WALK' }
            Mock Get-ItemProperty { throw 'NO-LIVE-REGISTRY' }
            Mock Get-CimInstance { throw 'NO-LIVE-PROCESS-INVENTORY' }
            Mock Invoke-RestMethod { throw 'NO-NETWORK' }
            Mock Start-Process { throw 'NO-PROCESS-START' }
            Mock New-WindowsCopilotNativeAuditProcess { throw 'NO-AUDIT-PROCESS-START' }
            Mock Invoke-WindowsCopilotNativeAuditProcess { throw 'NO-REAL-AUDIT-NODE' }
            Mock Stop-WindowsCopilotNativeAuditProcess { throw 'NO-PROCESS-STOP' }
            Mock Get-WindowsCopilotDirectoryTreeState { throw 'NO-WRAPPER-TREE' }
            Mock Test-DshUserPresetConfig { [pscustomobject]@{ valid = $true; status = 'synthetic-no-presets' } }
        }
        AfterEach {
            $env:DSH_HOME = $script:savedDshHome
            $env:DSH_TEST_PROJECTION_HOME = $script:savedProjectionHome
            foreach ($command in @('Get-Content', 'Get-ChildItem', 'Get-ItemProperty', 'Get-CimInstance',
                'Invoke-RestMethod', 'Start-Process', 'New-WindowsCopilotNativeAuditProcess',
                'Invoke-WindowsCopilotNativeAuditProcess', 'Stop-WindowsCopilotNativeAuditProcess',
                'Get-WindowsCopilotDirectoryTreeState')) {
                Should -Invoke $command -Times 0 -Exactly
            }
            Should -Invoke Test-Path -Times 0 -Exactly -ParameterFilter { [string]$LiteralPath -match '(?i)\.asar([\\/]|$)' }
            Should -Invoke Get-FileHash -Times 0 -Exactly -ParameterFilter { [string]$LiteralPath -match '(?i)\.asar([\\/]|$)' }
        }

        It 'projects genuine-shaped correlated audit leaves without reading virtual descriptor bytes' {
            $result = Get-WindowsCopilotDesktopState -Lock $script:lock -Path $script:exePath -DshHome $script:homePath
            $result.valid | Should -BeTrue
            $result.identityValid | Should -BeTrue
            $result.status | Should -BeExactly 'locked'
            $result.path | Should -BeExactly $script:exePath
            $result.version | Should -BeExactly '0.1.6.0'
            $result.lockedVersion | Should -BeExactly '0.1.6-alpha.1.cloga.1'
            $result.discoveries.Count | Should -Be 1
            $d = $result.discoveries[0]
            $d.bytesValid | Should -BeTrue
            $d.metadataValid | Should -BeTrue
            $d.authenticodeValid | Should -BeTrue
            $d.lockedVersionValid | Should -BeTrue
            $d.runtimeDescriptorValid | Should -BeTrue
            $d.runtimeDescriptorPath | Should -BeExactly (Join-Path $script:install 'resources\app.asar\dsh\desktop-runtime.json')
            $d.runtimeDescriptorSha256 | Should -BeExactly ('a' * 64)
            $d.runtimeDescriptorStatus | Should -BeExactly 'runtime-asar-verified'
            $d.runtimeDescriptorReason | Should -BeNullOrEmpty
            ($result | ConvertTo-Json -Depth 20) | Should -Not -Match 'PRIVATE-|metadataSnapshot|receipt|stderr'
            Should -Invoke Invoke-WindowsCopilotNativeFileAudit -Times 1 -Exactly -ParameterFilter {
                $InstallRoot -eq $script:install -and $DshHome -eq $script:homePath -and $Lock -eq $script:lock
            }
        }
        It 'preserves numeric PE normalization when locked metadata carries a full release version' {
            $script:lock.components.desktop.installedExecutable.productVersion = '0.1.6-alpha.1.cloga.1'
            $result = Get-WindowsCopilotDesktopState -Lock $script:lock -Path $script:exePath -DshHome $script:homePath
            $result.valid | Should -BeTrue
            $result.version | Should -BeExactly '0.1.6.0'
            $result.lockedVersion | Should -BeExactly '0.1.6-alpha.1.cloga.1'
            $result.discoveries[0].lockedVersionValid | Should -BeTrue
        }
        It 'forwards <HomeMode> home as an explicit audit argument' -ForEach @(
            @{ HomeMode = 'explicit' }, @{ HomeMode = 'expanded-explicit' }, @{ HomeMode = 'environment' }, @{ HomeMode = 'default' }
        ) {
            $arguments = @{ Lock = $script:lock; Path = $script:exePath }
            switch ($HomeMode) {
                explicit { $arguments.DshHome = $script:homePath; $env:DSH_HOME = 'C:\synthetic-ignored-home'; $expected = $script:homePath }
                expanded-explicit { $env:DSH_TEST_PROJECTION_HOME = $script:homePath; $arguments.DshHome = '%DSH_TEST_PROJECTION_HOME%'; $expected = $script:homePath }
                environment { $env:DSH_HOME = $script:homePath; $expected = $script:homePath }
                default { $expected = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.dsh' }
            }
            (Get-WindowsCopilotDesktopState @arguments).valid | Should -BeTrue
            Should -Invoke Invoke-WindowsCopilotNativeFileAudit -Times 1 -Exactly -ParameterFilter { $DshHome -eq $expected }
        }
        It 'rejects correlated audit leaf <Field> = <Value>' -ForEach @(
            @{ Field = 'mode'; Value = 'physical-runtime' }, @{ Field = 'status'; Value = 'descriptor-only' },
            @{ Field = 'version'; Value = '0.1.6-other' }, @{ Field = 'carrierExecutable'; Value = 'C:\unrelated\synthetic-desktop.exe' },
            @{ Field = 'executableSha256'; Value = ('c' * 64) }, @{ Field = 'runtimeRoot'; Value = 'C:\wrong\resources\app.asar\dsh' },
            @{ Field = 'descriptorSha256'; Value = ('c' * 64) }, @{ Field = 'fileCount'; Value = 0 },
            @{ Field = 'fileCount'; Value = -1 }, @{ Field = 'fileCount'; Value = 200001 },
            @{ Field = 'fileCount'; Value = 1.5 }, @{ Field = 'fileCount'; Value = '17' },
            @{ Field = 'fileCount'; Value = $true }, @{ Field = 'fileCount'; Value = [double]::NaN },
            @{ Field = 'fileCount'; Value = [double]::PositiveInfinity }
        ) {
            $script:audit.runtime[$Field] = $Value
            $result = Get-WindowsCopilotDesktopState -Lock $script:lock -Path $script:exePath -DshHome $script:homePath
            $result.valid | Should -BeFalse
            $result.identityValid | Should -BeFalse
            $result.discoveries[0].runtimeDescriptorValid | Should -BeFalse
            $result.discoveries[0].runtimeDescriptorSha256 | Should -BeNullOrEmpty
            $result.discoveries[0].runtimeDescriptorReason | Should -Match '^native-'
        }
        It 'rejects missing audit runtime leaf <Field>' -ForEach @(
            @{ Field = 'mode' }, @{ Field = 'status' }, @{ Field = 'version' }, @{ Field = 'carrierExecutable' },
            @{ Field = 'executableSha256' }, @{ Field = 'runtimeRoot' }, @{ Field = 'descriptorSha256' }, @{ Field = 'fileCount' }
        ) {
            $script:audit.runtime.Remove($Field)
            $result = Get-WindowsCopilotDesktopState -Lock $script:lock -Path $script:exePath -DshHome $script:homePath
            $result.valid | Should -BeFalse
            $result.identityValid | Should -BeFalse
            $result.discoveries[0].runtimeDescriptorValid | Should -BeFalse
            $result.discoveries[0].runtimeDescriptorSha256 | Should -BeNullOrEmpty
        }
        It 'requires full typed audit sections: <BadAudit>' -ForEach @(
            @{ BadAudit = 'audit-false' }, @{ BadAudit = 'audit-string' }, @{ BadAudit = 'runtime-false' },
            @{ BadAudit = 'runtime-string' }, @{ BadAudit = 'provisioning-false' }, @{ BadAudit = 'provisioning-string' },
            @{ BadAudit = 'missing-runtime' }, @{ BadAudit = 'missing-provisioning' }, @{ BadAudit = 'null-audit' }, @{ BadAudit = 'throw' }
        ) {
            switch ($BadAudit) {
                audit-false { $script:audit.valid = $false }
                audit-string { $script:audit.valid = 'true' }
                runtime-false { $script:audit.runtime.valid = $false; $script:audit.runtime.reason = 'native-runtime-tree-mismatch' }
                runtime-string { $script:audit.runtime.valid = 'true' }
                provisioning-false { $script:audit.provisioning.valid = $false; $script:audit.provisioning.reason = 'native-receipt-invalid' }
                provisioning-string { $script:audit.provisioning.valid = 'true' }
                missing-runtime { $script:audit.Remove('runtime') }
                missing-provisioning { $script:audit.Remove('provisioning') }
                null-audit { $script:audit = $null }
                throw { Mock Invoke-WindowsCopilotNativeFileAudit { throw 'PRIVATE-UNTRUSTED-AUDIT-ERROR' } }
            }
            $result = Get-WindowsCopilotDesktopState -Lock $script:lock -Path $script:exePath -DshHome $script:homePath
            $result.valid | Should -BeFalse
            $result.identityValid | Should -BeFalse
            $result.discoveries[0].runtimeDescriptorValid | Should -BeFalse
            $result.discoveries[0].runtimeDescriptorSha256 | Should -BeNullOrEmpty
            ($result | ConvertTo-Json -Depth 20) | Should -Not -Match 'PRIVATE-'
        }
        It 'never audits when physical executable <Failure> is invalid' -ForEach @(
            @{ Failure = 'missing' }, @{ Failure = 'hash' }, @{ Failure = 'size' }, @{ Failure = 'product' },
            @{ Failure = 'description' }, @{ Failure = 'company' }, @{ Failure = 'PE-version' }, @{ Failure = 'signature' }
        ) {
            switch ($Failure) {
                missing { $script:exePresent = $false }
                hash { $script:exeHash = 'c' * 64 }
                size { $script:fileItem.Length = 129 }
                product { $script:fileItem.VersionInfo.ProductName = 'Wrong product' }
                description { $script:fileItem.VersionInfo.FileDescription = 'Wrong description' }
                company { $script:fileItem.VersionInfo.CompanyName = 'Wrong publisher' }
                PE-version { $script:fileItem.VersionInfo.ProductVersion = '0.1.7.0' }
                signature { $script:signature = 'HashMismatch' }
            }
            $result = Get-WindowsCopilotDesktopState -Lock $script:lock -Path $script:exePath -DshHome $script:homePath
            $result.valid | Should -BeFalse
            $result.identityValid | Should -BeFalse
            Should -Invoke Invoke-WindowsCopilotNativeFileAudit -Times 0 -Exactly
        }
        It 'keeps explicit literal .5 physical descriptor discovery unchanged: <DigestValid>' -ForEach @(
            @{ DigestValid = $true }, @{ DigestValid = $false }
        ) {
            $script:lock.components.desktop.version = '0.1.5-rc.3.cloga.7'
            $script:lock.components.desktop.installedExecutable.productVersion = '0.1.5.0'
            $script:fileItem.VersionInfo.ProductVersion = '0.1.5.0'
            $script:lock.components.desktop.releaseChannel.upstreamVersion = '0.1.5-rc.2'
            $script:lock.components.desktop.installedRuntimeDescriptor.relativePath = 'resources\dsh\desktop-runtime.json'
            $script:physicalDescriptor = Join-Path $script:install 'resources\dsh\desktop-runtime.json'
            if (-not $DigestValid) { $script:physicalDescriptorHash = 'c' * 64 }
            $result = Get-WindowsCopilotDesktopState -Lock $script:lock -Path $script:exePath
            $result.valid | Should -Be $DigestValid
            $result.discoveries[0].runtimeDescriptorValid | Should -Be $DigestValid
            $result.discoveries[0].runtimeDescriptorSha256 | Should -BeExactly $script:physicalDescriptorHash
            Should -Invoke Get-FileHash -Times 1 -Exactly -ParameterFilter { $LiteralPath -eq $script:physicalDescriptor }
            Should -Invoke Invoke-WindowsCopilotNativeFileAudit -Times 0 -Exactly
        }
        It 'binds exact same Desktop/Host rows only after valid Desktop audit projection: <Case>' -ForEach @(
            @{ Case = 'valid' }, @{ Case = 'audit-false' }, @{ Case = 'runtime-string' },
            @{ Case = 'wrong-root' }, @{ Case = 'bytes-invalid' }, @{ Case = 'runtime-files-invalid' }, @{ Case = 'extra-host-flag' }
        ) {
            $runtime = Join-Path $script:install 'resources\app.asar\dsh'
            $entry = Join-Path $runtime 'node_modules\@deepseek-ai\dsh-desktop-host\lib\index.js'
            $policy = 'file:///C:/synthetic-desktop-projection/Desktop%20Spaces/resources/app.asar/dsh/node_modules/@deepseek-ai/dsh-desktop-host/register-module-resolution-policy.mjs'
            $profile = Join-Path $script:homePath 'profiles\desktop'
            # Only process binding is under test. The separate payload/functional
            # projection is deliberately unqualified, as in the existing fixture.
            $script:fileEvidence = @{
                valid = $false
                runtime = @{ valid = $true; runtimeRoot = $runtime; hostEntry = $entry; moduleResolutionPolicyUrl = $policy }
                provisioning = @{ valid = $false }
                functional = @{ valid = $false; status = 'manual-verification-required'; modelResponseVerified = $false }
            }
            Mock node { $global:LASTEXITCODE = 0; $script:fileEvidence | ConvertTo-Json -Depth 12 -Compress }
            switch ($Case) {
                audit-false { $script:audit.valid = $false }
                runtime-string { $script:audit.runtime.valid = 'true' }
                wrong-root { $script:audit.runtime.runtimeRoot = 'C:\unrelated\resources\app.asar\dsh' }
                bytes-invalid { $script:exeHash = 'c' * 64 }
                runtime-files-invalid { $script:fileEvidence.runtime.valid = $false }
            }
            $args = @($script:exePath, '--import', $policy, $entry, $runtime, $profile)
            $hostCommand = '"' + ($args -join '" "') + '"'
            if ($Case -eq 'extra-host-flag') { $hostCommand += ' --unexpected-flag' }
            $processes = @(
                [pscustomobject]@{ ProcessId = 10; ParentProcessId = 1; Name = 'synthetic-desktop.exe'; ExecutablePath = $script:exePath; CommandLine = ('"' + $script:exePath + '"') },
                [pscustomobject]@{ ProcessId = 11; ParentProcessId = 10; Name = 'synthetic-desktop.exe'; ExecutablePath = $script:exePath; CommandLine = $hostCommand }
            )
            $result = Test-WindowsCopilotNativeInstallation -Lock $script:lock -DshHome $script:homePath -DesktopExecutablePath $script:exePath -DesktopProcesses $processes
            $result.desktop.valid | Should -Be ($Case -in @('valid', 'runtime-files-invalid', 'extra-host-flag'))
            $result.runtime.activeRuntime.valid | Should -Be ($Case -eq 'valid')
            if ($Case -eq 'valid') { $result.runtime.activeRuntime.status | Should -BeExactly 'native-host-process-bound' }
            $result.complete | Should -BeFalse
            $result.runtimeValid | Should -BeFalse
            $result.functional.valid | Should -BeFalse
            $result.runtime.listenerStatus | Should -BeExactly 'not-applicable-native-host'
            if ($Case -ne 'bytes-invalid') {
                Should -Invoke Invoke-WindowsCopilotNativeFileAudit -Times 1 -Exactly -ParameterFilter { $DshHome -eq $script:homePath }
            }
            Should -Invoke node -Times 1 -Exactly
        }
    }
}
