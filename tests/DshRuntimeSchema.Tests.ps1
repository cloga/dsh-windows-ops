Import-Module (Join-Path $PSScriptRoot '..\tools\WindowsCopilotDeployment.psm1') -Force

Describe 'DSH active runtime schema diagnostics' {
    BeforeAll {
        $script:repoRoot = Split-Path -Parent $PSScriptRoot
        $script:fixtureRoot = Join-Path $PSScriptRoot 'fixtures\windows-copilot'
        $script:lock = Read-WindowsCopilotLock -Path (
            Join-Path $repoRoot 'deployments\windows-copilot.lock.json'
        )

        function New-RuntimeSchemaPackage {
            param(
                [Parameter(Mandatory)][string]$Path,
                [string]$Version = '0.1.2-alpha.1',
                [switch]$MissingCoreSymbol,
                [switch]$MissingPwshSymbol
            )
            New-Item -ItemType Directory -Path (Join-Path $Path 'lib') -Force | Out-Null
            New-Item -ItemType Directory -Path (
                Join-Path $Path 'node_modules\@deepseek-ai\dsh-tools\lib'
            ) -Force | Out-Null
            New-Item -ItemType Directory -Path (
                Join-Path $Path 'node_modules\@deepseek-ai\dsh-tool-pwsh\lib'
            ) -Force | Out-Null
            [ordered]@{ name = '@deepseek-ai/dsh'; version = $Version } |
                ConvertTo-Json -Compress |
                Set-Content -LiteralPath (Join-Path $Path 'package.json') -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $Path 'lib\bin.js') `
                -Value "console.log('$Version')" -Encoding UTF8
            Set-Content -LiteralPath (
                Join-Path $Path 'node_modules\@deepseek-ai\dsh-tools\lib\index.js'
            ) -Value $(if ($MissingCoreSymbol) { 'old schema' } else { 'projectModelSchema(agent)' }) `
                -Encoding UTF8
            Set-Content -LiteralPath (
                Join-Path $Path 'node_modules\@deepseek-ai\dsh-tool-pwsh\lib\index.js'
            ) -Value $(if ($MissingPwshSymbol) { 'old schema' } else { 'modelSchema: (agent)' }) `
                -Encoding UTF8
        }
        function Set-TestRuntimeCommands {
            param([Parameter(Mandatory)][string[]]$Path)
            $script:runtimeDiscovery = @($Path | ForEach-Object {
                $fullPath = [IO.Path]::GetFullPath($_)
                [pscustomobject]@{
                    commandType = 'ExternalScript'
                    name = Split-Path -Leaf $fullPath
                    path = $fullPath
                    identity = $fullPath
                }
            })
        }
    }

    BeforeEach {
        $script:runtimeDiscovery = @()
        $script:expectedActiveProcessIds = @()
        $script:expectedBoundPackageRoot = 'C:\fixture\node_modules\@deepseek-ai\dsh'
        Mock Get-DshRuntimeCommandDiscovery -ModuleName DshRuntimeSchema {
            @($script:runtimeDiscovery)
        }
        Mock Get-DshFreshProcessVersion -ModuleName DshRuntimeSchema {
            '0.1.2-alpha.1'
        }
        Mock Invoke-RuntimeSchemaGit -ModuleName DshRuntimeSchema {
            param($SourceRoot, $Arguments)
            if ($Arguments[0] -eq 'remote') {
                return 'https://github.com/cloga/deepseek-harness.git'
            }
            if ($Arguments[1] -eq 'HEAD') {
                return 'aa625de7be0e25b869b8a85d4a5301e84541c51c'
            }
            return 'aa625de7be0e25b869b8a85d4a5301e84541c51c'
        }
        Mock Get-DshRuntimeEvidenceBinding -ModuleName DshRuntimeSchema {
            [pscustomobject]@{
                effectiveCommand = 'C:\fixture\dsh.ps1'
                effectiveCommandSha256 = ('a' * 64)
                entrypointSha256 = ('b' * 64)
                packageVersion = '0.1.2-alpha.1'
                sourceCommit = 'aa625de7be0e25b869b8a85d4a5301e84541c51c'
                entrypoint = 'C:\fixture\node_modules\@deepseek-ai\dsh\lib\bin.js'
                packageRoot = $script:expectedBoundPackageRoot
                activeProcessIds = @($script:expectedActiveProcessIds)
                runtimeFiles = @(
                    [pscustomobject]@{ role = 'command'; path = 'C:\fixture\dsh.ps1'; sha256 = ('a' * 64); lastWriteTimeUtc = '2026-08-30T09:58:00.0000000Z' },
                    [pscustomobject]@{ role = 'entrypoint'; path = 'C:\fixture\bin.js'; sha256 = ('b' * 64); lastWriteTimeUtc = '2026-08-30T09:59:00.0000000Z' },
                    [pscustomobject]@{ role = 'schema-module'; path = 'C:\fixture\dsh-tools.js'; sha256 = ('c' * 64); lastWriteTimeUtc = '2026-08-30T10:00:00.0000000Z' },
                    [pscustomobject]@{ role = 'schema-module'; path = 'C:\fixture\dsh-tool-pwsh.js'; sha256 = ('d' * 64); lastWriteTimeUtc = '2026-08-30T10:00:00.0000000Z' }
                )
                runtimeReadyAtUtc = [datetime]::Parse(
                    '2026-08-30T10:00:00Z',
                    [Globalization.CultureInfo]::InvariantCulture,
                    [Globalization.DateTimeStyles]::RoundtripKind
                ).ToUniversalTime()
            }
        }
        Mock Test-DshRuntimeProcessEvidence -ModuleName DshRuntimeSchema { $true }
        Mock Read-DshRuntimeSchemaChallenge -ModuleName DshRuntimeSchema {
            [pscustomobject]@{
                schemaVersion = 1
                nonce = 'fixture-nonce'
                issuedAtUtc = '2026-08-30T10:00:30Z'
                expiresAtUtc = '2026-08-30T10:15:30Z'
                effectiveCommand = 'C:\fixture\dsh.ps1'
                effectiveCommandSha256 = ('a' * 64)
                entrypointSha256 = ('b' * 64)
                packageVersion = '0.1.2-alpha.1'
                sourceCommit = 'aa625de7be0e25b869b8a85d4a5301e84541c51c'
                packageRoot = $script:expectedBoundPackageRoot
                activeProcessIds = @($script:expectedActiveProcessIds)
                runtimeFiles = @(
                    [pscustomobject]@{ role = 'command'; path = 'C:\fixture\dsh.ps1'; sha256 = ('a' * 64); lastWriteTimeUtc = '2026-08-30T09:58:00.0000000Z' },
                    [pscustomobject]@{ role = 'entrypoint'; path = 'C:\fixture\bin.js'; sha256 = ('b' * 64); lastWriteTimeUtc = '2026-08-30T09:59:00.0000000Z' },
                    [pscustomobject]@{ role = 'schema-module'; path = 'C:\fixture\dsh-tools.js'; sha256 = ('c' * 64); lastWriteTimeUtc = '2026-08-30T10:00:00.0000000Z' },
                    [pscustomobject]@{ role = 'schema-module'; path = 'C:\fixture\dsh-tool-pwsh.js'; sha256 = ('d' * 64); lastWriteTimeUtc = '2026-08-30T10:00:00.0000000Z' }
                )
                runtimeReadyAtUtc = '2026-08-30T10:00:00.0000000Z'
            }
        }
        Mock Get-DshRuntimeUtcNow -ModuleName DshRuntimeSchema {
            [datetime]::Parse(
                '2026-08-30T10:05:00Z',
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::RoundtripKind
            ).ToUniversalTime()
        }
    }

    It 'fails on a stale global command before a healthy Desktop shim' {
        $globalRoot = Join-Path $TestDrive 'global'
        $desktopRoot = Join-Path $TestDrive 'desktop\bin'
        $globalCommand = Join-Path $globalRoot 'dsh.ps1'
        $desktopCommand = Join-Path $desktopRoot 'dsh.ps1'
        $globalPackage = Join-Path $globalRoot 'node_modules\@deepseek-ai\dsh'
        New-Item -ItemType Directory -Path $desktopRoot -Force | Out-Null
        New-RuntimeSchemaPackage -Path $globalPackage -Version '0.1.1-rc.2' `
            -MissingCoreSymbol -MissingPwshSymbol
        Set-Content -LiteralPath $globalCommand -Value '# global shim' -Encoding UTF8
        Set-Content -LiteralPath $desktopCommand -Value '# Desktop shim' -Encoding UTF8
        Set-TestRuntimeCommands -Path @($globalCommand, $desktopCommand)

        $result = Test-DshRuntimeSchemaState -Contract $lock.acceptance.runtimeSchema `
            -BehaviorEvidencePath (Join-Path $fixtureRoot 'runtime-schema-current.json') `
            -AttestedRepository 'https://github.com/cloga/deepseek-harness.git' `
            -AttestedSourceCommit 'aa625de7be0e25b869b8a85d4a5301e84541c51c'

        $result.valid | Should -Be $false
        $result.status | Should -Be 'stale-runtime-schema'
        $result.diagnosticCode | Should -Be 'STALE_RUNTIME_SCHEMA'
        $result.effectiveCommand | Should -Be ([IO.Path]::GetFullPath($globalCommand))
        $result.commands[1] | Should -Be ([IO.Path]::GetFullPath($desktopCommand))
        $result.remediation.automaticApplyAllowed | Should -Be $false
    }

    It 'verifies linked runtime content but keeps manual session evidence unattested' {
        $sourceRoot = Join-Path $TestDrive 'deepseek-harness'
        $target = Join-Path $sourceRoot 'apps\cli'
        $package = Join-Path $TestDrive 'prefix\node_modules\@deepseek-ai\dsh'
        $command = Join-Path $TestDrive 'prefix\dsh.ps1'
        New-Item -ItemType Directory -Path (Join-Path $sourceRoot '.git') -Force | Out-Null
        New-RuntimeSchemaPackage -Path $target
        New-Item -ItemType Directory -Path (Split-Path -Parent $package) -Force | Out-Null
        New-Item -ItemType Junction -Path $package -Target $target | Out-Null
        Set-Content -LiteralPath $command -Value '# linked shim' -Encoding UTF8
        Set-TestRuntimeCommands -Path @($command)

        $result = Test-DshRuntimeSchemaState -Contract $lock.acceptance.runtimeSchema `
            -BehaviorEvidencePath (Join-Path $fixtureRoot 'runtime-schema-current.json')

        $result.valid | Should -Be $false
        $result.status | Should -Be 'fresh-session-observed-unattested'
        $result.package.linked | Should -Be $true
        $result.package.packageTarget | Should -Be ([IO.Path]::GetFullPath($target))
        $result.source.commit | Should -Be $lock.acceptance.runtimeSchema.source.pullRequestHead
        $result.source.integrationSecondParent | Should -Be $lock.acceptance.runtimeSchema.source.pullRequestHead
        @($result.builtSymbols | Where-Object { -not $_.present }).Count | Should -Be 0
        $result.behavior.status | Should -Be 'fresh-session-observed-unattested'
        $result.behavior.observed | Should -Be $true
        $result.behavior.sessionAttested | Should -Be $false
    }

    It 'fails closed when either compiled schema symbol is absent' {
        foreach ($missing in @('core', 'pwsh')) {
            $prefix = Join-Path $TestDrive "$missing-prefix"
            $package = Join-Path $prefix 'node_modules\@deepseek-ai\dsh'
            $parameters = @{ Path = $package }
            if ($missing -eq 'core') { $parameters.MissingCoreSymbol = $true }
            else { $parameters.MissingPwshSymbol = $true }
            New-RuntimeSchemaPackage @parameters
            $command = Join-Path $prefix 'dsh.ps1'
            Set-Content -LiteralPath $command -Value '# shim' -Encoding UTF8
            Set-TestRuntimeCommands -Path @($command)
            $result = Test-DshRuntimeSchemaState -Contract $lock.acceptance.runtimeSchema `
                -BehaviorEvidencePath (Join-Path $fixtureRoot 'runtime-schema-current.json') `
                -AttestedRepository 'https://github.com/cloga/deepseek-harness.git' `
                -AttestedSourceCommit $lock.acceptance.runtimeSchema.source.integrationCommit
            $result.valid | Should -Be $false
            $result.status | Should -Be 'stale-runtime-schema'
        }
    }

    It 'rejects a fresh process whose version differs from package metadata' {
        $prefix = Join-Path $TestDrive 'fresh-version'
        $package = Join-Path $prefix 'node_modules\@deepseek-ai\dsh'
        $command = Join-Path $prefix 'dsh.ps1'
        New-RuntimeSchemaPackage -Path $package
        Set-Content -LiteralPath $command -Value '# shim' -Encoding UTF8
        Set-TestRuntimeCommands -Path @($command)
        Mock Get-DshFreshProcessVersion -ModuleName DshRuntimeSchema {
            '0.1.1-rc.2'
        }

        $result = Test-DshRuntimeSchemaState -Contract $lock.acceptance.runtimeSchema `
            -BehaviorEvidencePath (Join-Path $fixtureRoot 'runtime-schema-current.json') `
            -AttestedRepository 'https://github.com/cloga/deepseek-harness.git' `
            -AttestedSourceCommit $lock.acceptance.runtimeSchema.source.integrationCommit

        $result.valid | Should -Be $false
        $result.status | Should -Be 'stale-runtime-schema'
        $result.freshProcessVersionValid | Should -Be $false
    }

    It 'rejects stale cached-session behavior and stops mechanical retries' {
        $prefix = Join-Path $TestDrive 'stale-session'
        $package = Join-Path $prefix 'node_modules\@deepseek-ai\dsh'
        $command = Join-Path $prefix 'dsh.ps1'
        New-RuntimeSchemaPackage -Path $package
        Set-Content -LiteralPath $command -Value '# shim' -Encoding UTF8
        Set-TestRuntimeCommands -Path @($command)
        $result = Test-DshRuntimeSchemaState -Contract $lock.acceptance.runtimeSchema `
            -BehaviorEvidencePath (Join-Path $fixtureRoot 'runtime-schema-stale.json') `
            -AttestedRepository 'https://github.com/cloga/deepseek-harness.git' `
            -AttestedSourceCommit $lock.acceptance.runtimeSchema.source.integrationCommit

        $result.valid | Should -Be $false
        $result.status | Should -Be 'stale-runtime-schema'
        $result.diagnosticCode | Should -Be 'STALE_RUNTIME_SCHEMA'
        $result.restartRequired | Should -Be $true
        $result.behavior.staleErrors.Count | Should -Be 2
        $result.remediation.steps -join ' ' | Should -Match 'new session'
    }

    It 'rejects replayed evidence after its short validity window' {
        $prefix = Join-Path $TestDrive 'expired-evidence'
        $package = Join-Path $prefix 'node_modules\@deepseek-ai\dsh'
        $command = Join-Path $prefix 'dsh.ps1'
        $evidencePath = Join-Path $TestDrive 'expired-evidence.json'
        New-RuntimeSchemaPackage -Path $package
        Set-Content -LiteralPath $command -Value '# shim' -Encoding UTF8
        Set-TestRuntimeCommands -Path @($command)
        $evidence = Get-Content -LiteralPath (
            Join-Path $fixtureRoot 'runtime-schema-current.json'
        ) -Raw -Encoding UTF8 | ConvertFrom-Json
        $evidence.observedAtUtc = '2026-08-30T09:00:00Z'
        $evidence | ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath $evidencePath -Encoding UTF8

        $result = Test-DshRuntimeSchemaState -Contract $lock.acceptance.runtimeSchema `
            -BehaviorEvidencePath $evidencePath `
            -AttestedRepository 'https://github.com/cloga/deepseek-harness.git' `
            -AttestedSourceCommit $lock.acceptance.runtimeSchema.source.integrationCommit

        $result.valid | Should -Be $false
        $result.status | Should -Be 'stale-runtime-schema'
        $result.behavior.timeValid | Should -Be $false
    }

    It 'requires fresh-process behavior evidence and does not mutate the package' {
        $prefix = Join-Path $TestDrive 'evidence-required'
        $package = Join-Path $prefix 'node_modules\@deepseek-ai\dsh'
        $command = Join-Path $prefix 'dsh.ps1'
        New-RuntimeSchemaPackage -Path $package
        Set-Content -LiteralPath $command -Value '# shim' -Encoding UTF8
        Set-TestRuntimeCommands -Path @($command)
        $before = (Get-FileHash -LiteralPath (Join-Path $package 'package.json') -Algorithm SHA256).Hash

        $result = Test-DshRuntimeSchemaState -Contract $lock.acceptance.runtimeSchema `
            -AttestedRepository 'https://github.com/cloga/deepseek-harness.git' `
            -AttestedSourceCommit $lock.acceptance.runtimeSchema.source.integrationCommit

        $result.valid | Should -Be $false
        $result.status | Should -Be 'fresh-session-evidence-required'
        $result.behavior.diagnosticCode | Should -Be 'STALE_RUNTIME_SCHEMA'
        $result.behavior.challenge.token | Should -Not -BeNullOrEmpty
        $result.behavior.challenge.requiredOutputMarker | Should -Match '^PWSH_SCHEMA_OK:'
        (Get-FileHash -LiteralPath (Join-Path $package 'package.json') -Algorithm SHA256).Hash |
            Should -Be $before
    }

    It 'rejects a merge whose second parent is not the reviewed PR head' {
        $sourceRoot = Join-Path $TestDrive 'wrong-merge'
        $target = Join-Path $sourceRoot 'apps\cli'
        $package = Join-Path $TestDrive 'wrong-merge-prefix\node_modules\@deepseek-ai\dsh'
        $command = Join-Path $TestDrive 'wrong-merge-prefix\dsh.ps1'
        New-Item -ItemType Directory -Path (Join-Path $sourceRoot '.git') -Force | Out-Null
        New-RuntimeSchemaPackage -Path $target
        New-Item -ItemType Directory -Path (Split-Path -Parent $package) -Force | Out-Null
        New-Item -ItemType Junction -Path $package -Target $target | Out-Null
        Set-Content -LiteralPath $command -Value '# shim' -Encoding UTF8
        Set-TestRuntimeCommands -Path @($command)
        Mock Invoke-RuntimeSchemaGit -ModuleName DshRuntimeSchema {
            param($SourceRoot, $Arguments)
            if ($Arguments[0] -eq 'remote') {
                return 'https://github.com/cloga/deepseek-harness.git'
            }
            if ($Arguments[1] -eq 'HEAD') {
                return 'aa625de7be0e25b869b8a85d4a5301e84541c51c'
            }
            return ('f' * 40)
        }

        $result = Test-DshRuntimeSchemaState -Contract $lock.acceptance.runtimeSchema `
            -BehaviorEvidencePath (Join-Path $fixtureRoot 'runtime-schema-current.json')

        $result.valid | Should -Be $false
        $result.status | Should -Be 'runtime-provenance-unattested'
    }

    It 'rejects lookalike repository hosts' {
        $prefix = Join-Path $TestDrive 'lookalike-repository'
        $package = Join-Path $prefix 'node_modules\@deepseek-ai\dsh'
        $command = Join-Path $prefix 'dsh.ps1'
        New-RuntimeSchemaPackage -Path $package
        Set-Content -LiteralPath $command -Value '# shim' -Encoding UTF8
        Set-TestRuntimeCommands -Path @($command)

        $result = Test-DshRuntimeSchemaState -Contract $lock.acceptance.runtimeSchema `
            -BehaviorEvidencePath (Join-Path $fixtureRoot 'runtime-schema-current.json') `
            -AttestedRepository 'https://evilgithub.com/cloga/deepseek-harness.git' `
            -AttestedSourceCommit $lock.acceptance.runtimeSchema.source.integrationCommit

        $result.valid | Should -Be $false
        $result.status | Should -Be 'runtime-provenance-unattested'
    }

    It 'rejects a PATH runtime that is not the receipted Desktop package' {
        $prefix = Join-Path $TestDrive 'wrong-desktop-package'
        $package = Join-Path $prefix 'node_modules\@deepseek-ai\dsh'
        $command = Join-Path $prefix 'dsh.ps1'
        New-RuntimeSchemaPackage -Path $package
        Set-Content -LiteralPath $command -Value '# shim' -Encoding UTF8
        Set-TestRuntimeCommands -Path @($command)

        $result = Test-DshRuntimeSchemaState -Contract $lock.acceptance.runtimeSchema `
            -BehaviorEvidencePath (Join-Path $fixtureRoot 'runtime-schema-current.json') `
            -AttestedRepository 'https://github.com/cloga/deepseek-harness.git' `
            -AttestedSourceCommit $lock.acceptance.runtimeSchema.source.integrationCommit `
            -RequiredPackageRoot (Join-Path $TestDrive 'receipted\node_modules\@deepseek-ai\dsh')

        $result.valid | Should -Be $false
        $result.status | Should -Be 'runtime-not-active-desktop-core'
        $result.packageRootBindingValid | Should -Be $false
    }

    It 'requires evidence from the Desktop listener owner process' {
        $prefix = Join-Path $TestDrive 'wrong-desktop-process'
        $package = Join-Path $prefix 'node_modules\@deepseek-ai\dsh'
        $command = Join-Path $prefix 'dsh.ps1'
        New-RuntimeSchemaPackage -Path $package
        Set-Content -LiteralPath $command -Value '# shim' -Encoding UTF8
        Set-TestRuntimeCommands -Path @($command)
        $script:expectedActiveProcessIds = @(101)

        $result = Test-DshRuntimeSchemaState -Contract $lock.acceptance.runtimeSchema `
            -BehaviorEvidencePath (Join-Path $fixtureRoot 'runtime-schema-current.json') `
            -AttestedRepository 'https://github.com/cloga/deepseek-harness.git' `
            -AttestedSourceCommit $lock.acceptance.runtimeSchema.source.integrationCommit `
            -RequiredProcessIds @(101)

        $result.valid | Should -Be $false
        $result.status | Should -Be 'stale-runtime-schema'
        $result.behavior.activeProcessValid | Should -Be $false
    }

    It 'requires the expected entrypoint in the Node script position' {
        $wrong = InModuleScope DshRuntimeSchema {
            Test-DshNodeEntrypointArgument `
                -CommandLine '"C:\Program Files\nodejs\node.exe" "C:\runtime\old.js" C:\runtime\lib\bin.js' `
                -Entrypoint 'C:\runtime\lib\bin.js'
        }
        $right = InModuleScope DshRuntimeSchema {
            Test-DshNodeEntrypointArgument `
                -CommandLine '"C:\Program Files\nodejs\node.exe" "C:\runtime\lib\bin.js"' `
                -Entrypoint 'C:\runtime\lib\bin.js'
        }

        $wrong | Should -Be $false
        $right | Should -Be $true
    }

    It 'fails closed when a function shadows filesystem dsh commands' {
        $script:runtimeDiscovery = @(
            [pscustomobject]@{
                commandType = 'Function'
                name = 'dsh'
                path = $null
                identity = 'Function:dsh'
            },
            [pscustomobject]@{
                commandType = 'ExternalScript'
                name = 'dsh.ps1'
                path = 'C:\fixture\dsh.ps1'
                identity = 'C:\fixture\dsh.ps1'
            }
        )

        $result = Test-DshRuntimeSchemaState -Contract $lock.acceptance.runtimeSchema

        $result.valid | Should -Be $false
        $result.status | Should -Be 'runtime-command-shadowed'
        $result.diagnosticCode | Should -Be 'STALE_RUNTIME_SCHEMA'
        $result.effectiveCommand | Should -Be 'Function:dsh'
    }
}
