Import-Module (Join-Path $PSScriptRoot '..\tools\WindowsCopilotDeployment.psm1') -Force

Describe 'Locked Windows Copilot deployment' {
    BeforeAll {
        $script:repoRoot = Split-Path -Parent $PSScriptRoot
        $script:fixtureRoot = Join-Path $PSScriptRoot 'fixtures\windows-copilot'
        $script:lock = Read-WindowsCopilotLock -Path (Join-Path $repoRoot 'deployments\windows-copilot.lock.json')
        $script:catalog = Get-Content -LiteralPath (Join-Path $fixtureRoot 'model-catalog.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        function New-VersionedDesktopFixture {
            param(
                [Parameter(Mandatory)][string]$Path,
                [Parameter(Mandatory)][string]$Version
            )
            New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
            $typeName = 'DesktopFixture' + [guid]::NewGuid().ToString('N')
            $source = @"
using System.Reflection;
[assembly: AssemblyVersion("$Version.0")]
[assembly: AssemblyFileVersion("$Version.0")]
public static class $typeName { public static void Main() {} }
"@
            $sourcePath = "$Path.cs"
            Set-Content -LiteralPath $sourcePath -Value $source -Encoding UTF8
            $command = "Add-Type -Path '$($sourcePath.Replace("'", "''"))' -OutputAssembly '$($Path.Replace("'", "''"))' -OutputType ConsoleApplication"
            $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
            & powershell.exe -NoProfile -EncodedCommand $encoded
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
                throw 'Could not create the versioned Desktop fixture.'
            }
        }
        function Get-TestSha256Text {
            param([Parameter(Mandatory)][string]$Text)
            $sha = [Security.Cryptography.SHA256]::Create()
            try {
                $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
                return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
            } finally {
                $sha.Dispose()
            }
        }
        function New-ProviderReleaseFixture {
            param([Parameter(Mandatory)][string]$Root)
            $stageRoot = Join-Path $Root 'provider-release-stage'
            $packageRoot = Join-Path $stageRoot 'package'
            New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $script:fixtureRoot 'provider') `
                -Destination $packageRoot -Recurse
            $artifact = Join-Path $Root ([string]$script:lock.components.copilotIntegration.package.artifact.name)
            $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
            & $tar -czf $artifact -C $stageRoot package
            if ($LASTEXITCODE -ne 0) { throw 'Could not create provider Release fixture.' }
            $fixtureLock = $script:lock | ConvertTo-Json -Depth 30 | ConvertFrom-Json
            $fixtureLock.components.copilotIntegration.package.artifact.sha256 =
                (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
            $fixtureLock.components.copilotIntegration.package.artifact.size =
                (Get-Item -LiteralPath $artifact).Length
            [pscustomobject]@{ path = $artifact; lock = $fixtureLock }
        }
        function Get-TestDirectoryTreeState {
            param([Parameter(Mandatory)][string]$Path)
            $root = [IO.Path]::GetFullPath($Path).TrimEnd('\') + '\'
            $entries = @(Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object {
                [pscustomobject]@{
                    relativePath = $_.FullName.Substring($root.Length).Replace('\', '/')
                    sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                }
            } | Sort-Object relativePath)
            $text = ($entries | ForEach-Object {
                [string]$_.relativePath + "`t" + [string]$_.sha256
            }) -join "`n"
            [pscustomobject]@{
                fileCount = $entries.Count
                treeSha256 = Get-TestSha256Text -Text $text
            }
        }
        function New-DesktopInternalPluginFixture {
            param(
                [Parameter(Mandatory)][string]$ProfileRoot,
                [Parameter(Mandatory)][string]$DesktopExecutablePath,
                [string]$Version = [string]$script:lock.components.desktop.version
            )
            $desktopRoot = Split-Path -Parent $DesktopExecutablePath
            New-VersionedDesktopFixture -Path $DesktopExecutablePath -Version $Version
            $nodeModules = Join-Path $ProfileRoot 'node_modules'
            New-Item -ItemType Directory -Path $nodeModules -Force | Out-Null
            foreach ($plugin in @($script:lock.components.desktop.internalPlugins)) {
                $target = Join-Path $desktopRoot ([string]$plugin.relativePath)
                New-Item -ItemType Directory -Path $target -Force | Out-Null
                [ordered]@{
                    name = [string]$plugin.name
                    version = [string]$plugin.version
                } | ConvertTo-Json -Compress |
                    Set-Content -LiteralPath (Join-Path $target 'package.json') -Encoding UTF8
                New-Item -ItemType Junction -Path (Join-Path $nodeModules ([string]$plugin.name)) `
                    -Target $target | Out-Null
            }
            foreach ($dependency in @($script:lock.components.desktop.shippedDependencies)) {
                $target = Join-Path $desktopRoot ([string]$dependency.relativePath)
                New-Item -ItemType Directory -Path $target -Force | Out-Null
                [ordered]@{
                    name = [string]$dependency.name
                    version = [string]$dependency.version
                } | ConvertTo-Json -Compress |
                    Set-Content -LiteralPath (Join-Path $target 'package.json') -Encoding UTF8
            }
        }
        function New-ForkCoreFixture {
            param([Parameter(Mandatory)][string]$Prefix)
            $packageRoot = Join-Path $Prefix 'node_modules\@deepseek-ai\dsh'
            $binRoot = Join-Path $Prefix 'node_modules\.bin'
            $sandboxRoot = Join-Path $packageRoot 'node_modules\@deepseek-ai\dsh-sandbox\lib'
            $bashRoot = Join-Path $packageRoot 'node_modules\@deepseek-ai\dsh-tool-bash\lib'
            $pwshRoot = Join-Path $packageRoot 'node_modules\@deepseek-ai\dsh-tool-pwsh\lib'
            New-Item -ItemType Directory -Path $packageRoot, $binRoot, $sandboxRoot, $bashRoot, $pwshRoot -Force |
                Out-Null
            [ordered]@{
                name = '@deepseek-ai/dsh'
                version = [string]$script:lock.components.core.package.version
                type = 'module'
                bin = [ordered]@{ dsh = 'lib/bin.js' }
            } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $packageRoot 'package.json') -Encoding UTF8
            New-Item -ItemType Directory -Path (Join-Path $packageRoot 'lib') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $packageRoot 'lib\bin.js') -Value 'process.exit(0)' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $binRoot 'dsh.cmd') -Value '@echo off' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $Prefix 'dsh.cmd') `
                -Value "@echo off`r`n@call `"%~dp0node_modules\.bin\dsh.cmd`" %*" -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $sandboxRoot 'index.js') -Encoding UTF8 -Value @'
export async function approveEscalation(request, approval) {
  const rank = { 'read-only': 0, 'workspace-write': 1, 'danger-full-access': 2 }
  if (rank[request.requestedMode] <= rank[request.effectiveMode]) return request.effectiveMode
  await approval.approver.request()
  return request.requestedMode
}
'@
            foreach ($tool in @(
                [pscustomobject]@{ root = $bashRoot; name = 'bash' },
                [pscustomobject]@{ root = $pwshRoot; name = 'pwsh' }
            )) {
                Set-Content -LiteralPath (Join-Path $tool.root 'index.js') -Encoding UTF8 -Value @"
const approveEscalation = () => {}
approveEscalation()
export function apply(ctx) {
  ctx.tools.register({
    name: '$($tool.name)',
    parameters: {
      sandbox_permissions: { type: 'string' },
      justification: { type: 'string' },
    },
    async execute(args, exec) {
      return ctx.shell.run(ctx.shell.resolve({
        command: args.command,
        sandboxPolicy: { mode: 'danger-full-access' },
        signal: exec.signal,
      }))
    },
  })
}
"@
            }
            $packages = @([ordered]@{
                name = '@deepseek-ai/dsh'
                version = [string]$script:lock.components.core.package.version
                filename = 'deepseek-ai-dsh-fixture.tgz'
                sha256 = ('a' * 64)
                files = 10
            })
            $installedFiles = @(
                [ordered]@{
                    role = 'root-shim'
                    path = 'dsh.cmd'
                    sha256 = (Get-FileHash -LiteralPath (Join-Path $Prefix 'dsh.cmd') -Algorithm SHA256).Hash
                },
                [ordered]@{
                    role = 'npm-shim'
                    path = 'node_modules\.bin\dsh.cmd'
                    sha256 = (Get-FileHash -LiteralPath (Join-Path $binRoot 'dsh.cmd') -Algorithm SHA256).Hash
                },
                [ordered]@{
                    role = 'entrypoint'
                    path = 'node_modules\@deepseek-ai\dsh\lib\bin.js'
                    sha256 = (Get-FileHash -LiteralPath (Join-Path $packageRoot 'lib\bin.js') -Algorithm SHA256).Hash
                }
            )
            [ordered]@{
                schemaVersion = 1
                repositoryUrl = 'https://github.com/cloga/deepseek-harness.git'
                commitSha = [string]$script:lock.components.core.source.commit
                packageName = '@deepseek-ai/dsh'
                packageVersion = [string]$script:lock.components.core.package.version
                releaseManifestSha256 = Get-TestSha256Text `
                    -Text (ConvertTo-Json -InputObject $packages -Compress -Depth 4)
                cliPath = Join-Path $Prefix 'dsh.cmd'
                packages = $packages
                installedFiles = $installedFiles
            } | ConvertTo-Json -Depth 8 |
                Set-Content -LiteralPath (Join-Path $Prefix 'dsh-local-install.json') -Encoding UTF8
            return [pscustomobject]@{
                prefix = $Prefix
                cliPath = Join-Path $Prefix 'dsh.cmd'
                packageRoot = $packageRoot
            }
        }
        function Set-LegacyPhysicalPluginFixture {
            param(
                [Parameter(Mandatory)][string]$ProfileRoot,
                [Parameter(Mandatory)][string]$PackagePath
            )
            $profile = Get-Content -LiteralPath $PackagePath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($plugin in @($script:lock.profile.legacyPhysicalPlugins)) {
                $target = Join-Path $ProfileRoot (Join-Path 'node_modules' ([string]$plugin.name))
                if (Test-Path -LiteralPath $target) {
                    $item = Get-Item -LiteralPath $target -Force
                    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                        [IO.Directory]::Delete($target, $false)
                    } else {
                        Remove-Item -LiteralPath $target -Recurse -Force
                    }
                }
                New-Item -ItemType Directory -Path $target -Force | Out-Null
                [ordered]@{
                    name = [string]$plugin.name
                    version = [string]$plugin.version
                } | ConvertTo-Json -Compress |
                    Set-Content -LiteralPath (Join-Path $target 'package.json') -Encoding UTF8
                Set-Content -LiteralPath (Join-Path $target 'legacy-sentinel.txt') `
                    -Value ([string]$plugin.version) -Encoding UTF8
                $profile.dependencies | Add-Member -NotePropertyName ([string]$plugin.name) `
                    -NotePropertyValue ([string]$plugin.version) -Force
            }
            $profile | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $PackagePath -Encoding UTF8
        }

function Get-TestSha256 {
            param([Parameter(Mandatory)][string]$Path)
            return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
        }

function Get-TestTree {
            param([Parameter(Mandatory)][string]$Path)
            $root = [IO.Path]::GetFullPath($Path).TrimEnd('\') + '\'
            $entries = @(Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object {
                [pscustomobject]@{
                    relativePath = $_.FullName.Substring($root.Length).Replace('\', '/')
                    sha256 = Get-TestSha256 -Path $_.FullName
                    size = [int64]$_.Length
                }
            } | Sort-Object relativePath)
            $text = ($entries | ForEach-Object {
                [string]$_.relativePath + "`t" + [string]$_.sha256
            }) -join "`n"
            $sha = [Security.Cryptography.SHA256]::Create()
            try {
                $treeHash = ([BitConverter]::ToString(
                    $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))
                )).Replace('-', '').ToLowerInvariant()
            } finally {
                $sha.Dispose()
            }
            return [pscustomobject]@{
                fileCount = $entries.Count
                totalBytes = [int64](($entries | Measure-Object size -Sum).Sum)
                treeSha256 = $treeHash
            }
        }

function Get-OfficialLockFixture {
            $path = Join-Path $script:repoRoot 'deployments\windows-copilot.lock.json'
            return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        }

function New-OfficialRuntimeFixture {
            param(
                [Parameter(Mandatory)][string]$AppData,
                [Parameter(Mandatory)]$Lock
            )
            $root = Join-Path $AppData 'io.github.hairyf.deepseek-harness-desktop\dependencies\dsh'
            if (Test-Path -LiteralPath $root) {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
            $packageRoot = Join-Path $root 'node_modules\@deepseek-ai\dsh'
            New-Item -ItemType Directory -Path (Join-Path $packageRoot 'lib') -Force | Out-Null
            [ordered]@{
                name = 'deepseek-harness-pkg'
                version = '0.1.2-alpha.5'
            } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'package.json') -Encoding UTF8
            [ordered]@{
                name = '@deepseek-ai/dsh'
                version = '0.1.2-rc.1'
                bin = [ordered]@{ dsh = 'lib/bin.js' }
            } | ConvertTo-Json -Depth 4 |
                Set-Content -LiteralPath (Join-Path $packageRoot 'package.json') -Encoding UTF8
            $entrypoint = Join-Path $packageRoot 'lib\bin.js'
            [IO.File]::WriteAllText($entrypoint, 'process.exit(0)', [Text.UTF8Encoding]::new($false))
            foreach ($file in @($Lock.acceptance.runtimeSchema.requiredBuiltFiles)) {
                $symbolPath = Join-Path $root ([string]$file.path)
                New-Item -ItemType Directory -Path (Split-Path -Parent $symbolPath) -Force | Out-Null
                [IO.File]::WriteAllText(
                    $symbolPath,
                    'fixture',
                    [Text.UTF8Encoding]::new($false)
                )
            }
            $tree = Get-TestTree -Path $packageRoot
            $wrapperTree = Get-TestTree -Path $root
            $fixtureLock = $Lock | ConvertTo-Json -Depth 40 | ConvertFrom-Json
            $fixtureLock.components.desktop.runtimeSelectors[0].package.fileCount = $tree.fileCount
            $fixtureLock.components.desktop.runtimeSelectors[0].package.treeSha256 = $tree.treeSha256
            $fixtureLock.components.desktop.runtimeSelectors[0].package.entrypointSize =
                (Get-Item -LiteralPath $entrypoint).Length
            $fixtureLock.components.desktop.runtimeSelectors[0].package.entrypointSha256 =
                Get-TestSha256 -Path $entrypoint
            $fixtureLock.components.desktop.runtimeSelectors[0].rootPackage.manifestSha256 =
                Get-TestSha256 -Path (Join-Path $root 'package.json')
            $fixtureLock.components.desktop.runtimeSelectors[0].rootPackage.fileCount = $wrapperTree.fileCount
            $fixtureLock.components.desktop.runtimeSelectors[0].rootPackage.totalBytes = $wrapperTree.totalBytes
            $fixtureLock.components.desktop.runtimeSelectors[0].rootPackage.treeSha256 = $wrapperTree.treeSha256
            $fixtureLock.components.desktop.runtimeSelectors[0].rootPackage.reparseDirectoryCount = 0
            $fixtureLock.acceptance.runtimeSchema.package.entrypointSize =
                (Get-Item -LiteralPath $entrypoint).Length
            $fixtureLock.acceptance.runtimeSchema.package.entrypointSha256 =
                Get-TestSha256 -Path $entrypoint
            $fixtureLock.acceptance.runtimeSchema.wrapper.manifestSha256 =
                Get-TestSha256 -Path (Join-Path $root 'package.json')
            $fixtureLock.acceptance.runtimeSchema.wrapper.fileCount = $wrapperTree.fileCount
            $fixtureLock.acceptance.runtimeSchema.wrapper.totalBytes = $wrapperTree.totalBytes
            $fixtureLock.acceptance.runtimeSchema.wrapper.treeSha256 = $wrapperTree.treeSha256
            $fixtureLock.acceptance.runtimeSchema.wrapper.reparseDirectoryCount = 0
            foreach ($file in @($fixtureLock.acceptance.runtimeSchema.requiredBuiltFiles)) {
                $filePath = Join-Path $root ([string]$file.path)
                $file.size = (Get-Item -LiteralPath $filePath).Length
                $file.sha256 = Get-TestSha256 -Path $filePath
            }
            return [pscustomobject]@{
                lock = $fixtureLock
                root = $root
                packageRoot = $packageRoot
                entrypoint = $entrypoint
            }
        }

function New-TestFingerprint {
            param([Parameter(Mandatory)][string]$Path)
            if (-not (Test-Path -LiteralPath $Path)) {
                return [ordered]@{ kind = 'absent' }
            }
            $item = Get-Item -LiteralPath $Path
            return [ordered]@{
                kind = 'file'
                size = [long]$item.Length
                sha256 = Get-TestSha256 -Path $Path
            }
        }
    }

    BeforeEach {
        $script:previousLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = Join-Path $TestDrive 'localappdata'
    }

    AfterEach {
        $env:LOCALAPPDATA = $script:previousLocalAppData
    }



    It 'requires Copilot manifest lock and installed bytes to agree in web and headless profiles' {
        $caseRoot = Join-Path $TestDrive 'profile-coherence'
        New-Item -ItemType Directory -Path $caseRoot -Force | Out-Null
        $dshHome = Join-Path $caseRoot '.dsh'
        $artifact = Join-Path $caseRoot 'dsh-github-copilot-0.3.0-cloga.15.tgz'
        $stage = Join-Path $caseRoot 'stage'
        $package = Join-Path $stage 'package'
        New-Item -ItemType Directory -Path $package -Force | Out-Null
        @{ name = 'dsh-github-copilot'; version = '0.3.0-cloga.15' } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $package 'package.json') `
                -Encoding UTF8
        @{ package = @{ name = 'dsh-github-copilot'; version = '0.3.0-cloga.15' } } |
            ConvertTo-Json -Depth 5 |
                Set-Content -LiteralPath (Join-Path $package 'deployment-baseline.json') `
                    -Encoding UTF8
        & (Join-Path $env:SystemRoot 'System32\tar.exe') -czf $artifact -C $stage package
        $coherenceLock = $lock | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        $coherenceLock.components.copilotIntegration.package.artifact.sha256 =
            (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
        $coherenceLock.components.copilotIntegration.package.artifact.size =
            (Get-Item -LiteralPath $artifact).Length
        $dependency = 'file:' + $artifact.Replace('\', '/')
        foreach ($profile in @('web', 'headless')) {
            $root = Join-Path $dshHome "profiles\$profile"
            $installed = Join-Path $root 'node_modules\dsh-github-copilot'
            New-Item -ItemType Directory -Path (Split-Path -Parent $installed) -Force |
                Out-Null
            Copy-Item -LiteralPath $package -Destination $installed -Recurse
            @{ dependencies = @{ 'dsh-github-copilot' = $dependency } } |
                ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $root 'package.json') -Encoding UTF8
            @"
lockfileVersion: '9.0'
importers:
  .:
    dependencies:
      dsh-github-copilot:
        specifier: $dependency
        version: file:../../artifacts/dsh-github-copilot-0.3.0-cloga.15.tgz
packages:
  dsh-github-copilot@file:../../artifacts/dsh-github-copilot-0.3.0-cloga.15.tgz:
    resolution: {tarball: file:../../artifacts/dsh-github-copilot-0.3.0-cloga.15.tgz}
    version: 0.3.0-cloga.15
"@ | Set-Content -LiteralPath (Join-Path $root 'pnpm-lock.yaml') -Encoding UTF8
        }

        $coherent = Test-WindowsCopilotProfileCoherence -Lock $coherenceLock -DshHome $dshHome
        $coherent.valid | Should -Be $true
        @($coherent.profiles).Count | Should -Be 2
        (Get-Content -LiteralPath (Join-Path $dshHome 'profiles\headless\pnpm-lock.yaml') -Raw).
            Replace(
                'version: file:../../artifacts/dsh-github-copilot-0.3.0-cloga.15.tgz',
                'version: file:../../artifacts/dsh-github-copilot-0.3.0-cloga.10.tgz'
            ) |
            Set-Content -LiteralPath (Join-Path $dshHome 'profiles\headless\pnpm-lock.yaml') -Encoding UTF8
        $drifted = Test-WindowsCopilotProfileCoherence -Lock $coherenceLock -DshHome $dshHome
        $drifted.valid | Should -Be $false
        @($drifted.profiles | Where-Object profile -eq 'headless')[0].reasons |
            Should -Contain 'lock-version-mismatch'
    }



    It 'bounds and redacts shareable loader diagnostics' {
        InModuleScope WindowsCopilotDeployment {
            $input = "$env:USERPROFILE\private token=super-secret-value " + ('x' * 200)
            $safe = ConvertTo-WindowsCopilotSafeDiagnostic -Value $input -Limit 80
            $safe | Should -Match '%USERPROFILE%'
            $safe | Should -Not -Match 'super-secret-value'
            $safe | Should -Match '<redacted>'
            $safe | Should -Match 'truncated>'
            $safe.Length | Should -BeLessOrEqual 80
        }
    }

    It 'runs the complete plugin verification gate before packing a clean source' {
        $sourceRoot = Join-Path $TestDrive 'clean-provider-source'
        New-Item -ItemType Directory -Path $sourceRoot -Force | Out-Null
        Test-Path -LiteralPath (Join-Path $sourceRoot 'lib') | Should -Be $false
        Test-Path -LiteralPath (Join-Path $sourceRoot 'dist') | Should -Be $false
        $commandLog = [Collections.Generic.List[string]]::new()

        InModuleScope WindowsCopilotDeployment -Parameters @{
            Commands = @($lock.components.copilotIntegration.build.commands)
            CommandLog = $commandLog
            SourceRoot = $sourceRoot
        } {
            param($Commands, $CommandLog, $SourceRoot)
            Mock Invoke-LockedCommand {
                param($FilePath, $Arguments, $WorkingDirectory)
                $command = @($Arguments | Select-Object -Skip 2)
                $CommandLog.Add(($command -join ' '))
                if ($command[0] -eq 'run' -and $command[1] -eq 'verify') {
                    $libRoot = Join-Path $WorkingDirectory 'lib'
                    New-Item -ItemType Directory -Path $libRoot -Force | Out-Null
                    Set-Content -LiteralPath (Join-Path $libRoot 'client.js') `
                        -Value 'export default {}' -Encoding UTF8
                } elseif ($command[0] -eq 'pack') {
                    if (-not (Test-Path -LiteralPath (Join-Path $WorkingDirectory 'lib\client.js') -PathType Leaf)) {
                        throw 'Client bundle is missing before pack.'
                    }
                    $distRoot = Join-Path $WorkingDirectory 'dist'
                    New-Item -ItemType Directory -Path $distRoot -Force | Out-Null
                    Set-Content -LiteralPath (Join-Path $distRoot 'provider.tgz') `
                        -Value 'packed' -Encoding UTF8
                }
            }

            Invoke-PinnedPnpmCommands -PackageManager 'pnpm@11.7.0' `
                -Commands $Commands -WorkingDirectory $SourceRoot
        }

        @($commandLog) | Should -Be @(
            'install --frozen-lockfile',
            'run verify',
            'pack --pack-destination .\dist'
        )
        Test-Path -LiteralPath (Join-Path $sourceRoot 'lib\client.js') | Should -Be $true
        Test-Path -LiteralPath (Join-Path $sourceRoot 'dist\provider.tgz') | Should -Be $true
    }



    It 'rejects incomplete or untrusted Copilot Release evidence in a deployment lock' {
        $mutableRelease = $lock | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        $mutableRelease.components.copilotIntegration.package.artifact.releaseImmutable = $false
        { Test-WindowsCopilotLock -Lock $mutableRelease } |
            Should -Throw '*canonical immutable Release*'

        $wrongTag = $lock | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        $wrongTag.components.copilotIntegration.package.artifact.releaseTag = 'v9.9.9'
        { Test-WindowsCopilotLock -Lock $wrongTag } |
            Should -Throw '*canonical immutable Release*'

        $badManifest = $lock | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        $badManifest.components.copilotIntegration.package.artifact.checksumManifest.sha256 = '0'
        { Test-WindowsCopilotLock -Lock $badManifest } |
            Should -Throw '*Invalid locked artifact SHA-256*'

        $missingManifest = $lock | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        $missingManifest.components.copilotIntegration.package.artifact.PSObject.Properties.Remove('checksumManifest')
        { Test-WindowsCopilotLock -Lock $missingManifest } |
            Should -Throw '*checksumManifest.name*'

        $wrongOverlayPr = $lock | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        (@($wrongOverlayPr.profile.optionalOverlays | Where-Object name -eq 'dsh-cron'))[0].pullRequest = 999
        { Test-WindowsCopilotLock -Lock $wrongOverlayPr } |
            Should -Throw '*Optional overlay inventory omits*'
    }













    It 'fails closed when session-list response omits an items array' {
        $malformed = [pscustomobject]@{
            type = 'server-response'
            result = [pscustomobject]@{ ok = $true; value = [pscustomobject]@{} }
        }
        { Get-WindowsCopilotLiveSessions -Response $malformed } |
            Should -Throw '*invalid session/list response*'
    }

    It 'fails closed when a running Session lacks a unique non-empty ID' {
        $missingId = [pscustomobject]@{ running = $true }
        $response = [pscustomobject]@{
            type = 'server-response'
            result = [pscustomobject]@{
                ok = $true
                value = [pscustomobject]@{ items = [object[]]@(
                    $missingId,
                    [pscustomobject]@{ sessionId = 'valid'; running = $true }
                ) }
            }
        }
        { Get-WindowsCopilotLiveSessions -Response $response } |
            Should -Throw '*unique non-empty IDs*'
        { Get-WindowsCopilotLiveSessions -Sessions @($missingId) } |
            Should -Throw '*unique non-empty IDs*'
        $duplicate = @(
            [pscustomobject]@{ sessionId = 'same'; running = $true },
            [pscustomobject]@{ sessionId = 'same'; running = $true }
        )
        { Get-WindowsCopilotLiveSessions -Sessions $duplicate } |
            Should -Throw '*unique non-empty IDs*'
    }

    It 'blocks Desktop restart while Sessions are live unless interruption is acknowledged' {
        $caseRoot = Join-Path $TestDrive 'restart-live-session-guard'
        $desktopPath = Join-Path $caseRoot 'desktop\deepseek-harness-desktop.exe'
        New-VersionedDesktopFixture -Path $desktopPath -Version '0.10.2'
        $processes = @([pscustomobject]@{
            ProcessId = 10
            ParentProcessId = 0
            Name = 'deepseek-harness-desktop.exe'
            ExecutablePath = $desktopPath
            CommandLine = "`"$desktopPath`""
        })
        $live = @([pscustomobject]@{
            sessionId = 'session-live'
            title = 'Protected work'
            origin = 'web'
            running = $true
        })

        {
            Restart-WindowsCopilotDesktop -DesktopExecutablePath $desktopPath `
                -Processes $processes -LiveSessions $live
        } | Should -Throw '*acknowledged Session IDs do not match*'
        $blocked = Restart-WindowsCopilotDesktop -DesktopExecutablePath $desktopPath `
            -Processes $processes -LiveSessions $live -DryRun
        $blocked.status | Should -Be 'would-block-live-sessions'
        @($blocked.liveSessions).Count | Should -Be 1
        $stale = Restart-WindowsCopilotDesktop -DesktopExecutablePath $desktopPath `
            -Processes $processes -LiveSessions $live -DryRun `
            -AcknowledgeLiveSessionIds @('session-old')
        $stale.status | Should -Be 'would-block-live-sessions'
        $approved = Restart-WindowsCopilotDesktop -DesktopExecutablePath $desktopPath `
            -Processes $processes -LiveSessions $live -DryRun `
            -AcknowledgeLiveSessionIds @('session-live')
        $approved.status | Should -Be 'would-restart'
        $preemptive = Restart-WindowsCopilotDesktop -DesktopExecutablePath $desktopPath `
            -Processes $processes -LiveSessions @() -DryRun `
            -AcknowledgeLiveSessionIds @('session-live')
        $preemptive.status | Should -Be 'would-block-stale-acknowledgement'
        $newLive = @($live) + [pscustomobject]@{
            sessionId = 'session-started-late'
            title = 'New protected work'
            origin = 'web'
            running = $true
        }
        {
            Restart-WindowsCopilotDesktop -DesktopExecutablePath $desktopPath `
                -Processes $processes -LiveSessions $live -FinalLiveSessions $newLive `
                -AcknowledgeLiveSessionIds @('session-live')
        } | Should -Throw '*running Session set changed after acknowledgement*'
    }

















    It 'accepts and preserves exact official Desktop link dependencies' {
        $caseRoot = Join-Path $TestDrive 'official-link-dependencies'
        $dshHome = Join-Path $caseRoot '.dsh'
        $profileRoot = Join-Path $dshHome 'profiles\web'
        $packagePath = Join-Path $profileRoot 'package.json'
        $desktopPath = Join-Path $caseRoot 'desktop\deepseek-harness-desktop.exe'
        New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'profile\package.json') -Destination $profileRoot
        New-DesktopInternalPluginFixture -ProfileRoot $profileRoot -DesktopExecutablePath $desktopPath
        $profile = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $expectedDependencies = @{}
        foreach ($plugin in @($lock.components.desktop.internalPlugins)) {
            $target = Join-Path (Split-Path -Parent $desktopPath) ([string]$plugin.relativePath)
            $dependency = 'link:' + ([IO.Path]::GetFullPath($target).Replace('\', '/'))
            $profile.dependencies | Add-Member -NotePropertyName ([string]$plugin.name) `
                -NotePropertyValue $dependency
            $expectedDependencies[[string]$plugin.name] = $dependency
        }
        $profile | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $packagePath -Encoding UTF8

        $module = Get-Module WindowsCopilotDeployment
        $plan = & $module {
            param($Lock, $DshHome, $DesktopExecutablePath)
            Get-WindowsCopilotProfileMigrationPlan -Lock $Lock -DshHome $DshHome `
                -DesktopExecutablePath $DesktopExecutablePath
        } $lock $dshHome $desktopPath

        @($plan.dependenciesToRemove).Count | Should -Be 0
        $preserved = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($plugin in @($lock.components.desktop.internalPlugins)) {
            $preserved.dependencies.([string]$plugin.name) |
                Should -Be $expectedDependencies[[string]$plugin.name]
        }
    }

    It 'accepts only exact locked provider artifact dependencies as desired state' {
        $caseRoot = Join-Path $TestDrive 'desired-provider-dependencies'
        $dshHome = Join-Path $caseRoot '.dsh'
        $profileRoot = Join-Path $dshHome 'profiles\web'
        $packagePath = Join-Path $profileRoot 'package.json'
        $desktopPath = Join-Path $caseRoot 'desktop\deepseek-harness-desktop.exe'
        New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'profile\package.json') -Destination $profileRoot
        New-DesktopInternalPluginFixture -ProfileRoot $profileRoot -DesktopExecutablePath $desktopPath
        $expectedArtifact = Join-Path $dshHome (
            Join-Path 'artifacts' (
                Join-Path ([string]$lock.components.copilotIntegration.source.commit) `
                    ([string]$lock.components.copilotIntegration.package.artifact.name)
            )
        )
        $module = Get-Module WindowsCopilotDeployment
        $emptyDependencyValid = & $module {
            param($Lock, $DshHome, $ProfileRoot)
            Test-WindowsCopilotDesiredArtifactDependency -Lock $Lock -Dependency '' `
                -DshHome $DshHome -ProfileRoot $ProfileRoot
        } $lock $dshHome $profileRoot
        $emptyDependencyValid | Should -Be $false
        $accepted = @(
            [string]$lock.components.copilotIntegration.package.artifact.url
            "file:../../artifacts/$($lock.components.copilotIntegration.source.commit)/$($lock.components.copilotIntegration.package.artifact.name)"
            ([Uri]::new([IO.Path]::GetFullPath($expectedArtifact))).AbsoluteUri
        )
        foreach ($dependency in $accepted) {
            $profile = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | ConvertFrom-Json
            $profile.dependencies | Add-Member -NotePropertyName 'dsh-github-copilot' `
                -NotePropertyValue $dependency -Force
            $profile | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $packagePath -Encoding UTF8
            {
                & $module {
                    param($Lock, $DshHome, $DesktopExecutablePath)
                    Get-WindowsCopilotProfileMigrationPlan -Lock $Lock -DshHome $DshHome `
                        -DesktopExecutablePath $DesktopExecutablePath
                } $lock $dshHome $desktopPath
            } | Should -Not -Throw
        }

        $rejected = @(
            'https://github.com/cloga/dsh-github-copilot/releases/download/v0.3.0-cloga.7/dsh-github-copilot-0.3.0-cloga.15.tgz'
            'https://github.com/cloga/dsh-github-copilot/releases/download/v0.3.0-cloga.15/not-dsh-github-copilot-0.3.0-cloga.15.tgz'
            "file:../../artifacts/wrong-commit/$($lock.components.copilotIntegration.package.artifact.name)"
            "file:../../arbitrary/$($lock.components.copilotIntegration.source.commit)/$($lock.components.copilotIntegration.package.artifact.name)"
            "https://example.test/$($lock.components.copilotIntegration.source.commit)/$($lock.components.copilotIntegration.package.artifact.name)"
        )
        foreach ($dependency in $rejected) {
            $profile = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | ConvertFrom-Json
            $profile.dependencies | Add-Member -NotePropertyName 'dsh-github-copilot' `
                -NotePropertyValue $dependency -Force
            $profile | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $packagePath -Encoding UTF8
            {
                & $module {
                    param($Lock, $DshHome, $DesktopExecutablePath)
                    Get-WindowsCopilotProfileMigrationPlan -Lock $Lock -DshHome $DshHome `
                        -DesktopExecutablePath $DesktopExecutablePath
                } $lock $dshHome $desktopPath
            } | Should -Throw "*Profile dependency 'dsh-github-copilot' is not a reviewed legacy Copilot integration.*"
        }
    }



    It 'resumes Apply after the provider dependency was updated before materialization' {
        $caseRoot = Join-Path $TestDrive 'provider-reentry'
        $dshHome = Join-Path $caseRoot '.dsh'
        $profileRoot = Join-Path $dshHome 'profiles\web'
        $packagePath = Join-Path $profileRoot 'package.json'
        $globalRoot = Join-Path $caseRoot 'global'
        $desktopPath = Join-Path $caseRoot 'desktop\deepseek-harness-desktop.exe'
        New-Item -ItemType Directory -Path $profileRoot, $globalRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'profile\package.json') -Destination $profileRoot
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'profile\pnpm-workspace.yaml') -Destination $profileRoot
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'settings.yaml') -Destination (Join-Path $dshHome 'settings.yaml')
        Copy-Item -Path (Join-Path $fixtureRoot 'global\*') -Destination $globalRoot -Recurse
        New-DesktopInternalPluginFixture -ProfileRoot $profileRoot -DesktopExecutablePath $desktopPath
        $profile = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $profile.dependencies | Add-Member -NotePropertyName 'dsh-github-copilot' `
            -NotePropertyValue ([string]$lock.components.copilotIntegration.package.artifact.url)
        $profile | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $packagePath -Encoding UTF8
        $providerRelease = New-ProviderReleaseFixture -Root $caseRoot
        $artifact = $providerRelease.path

        Set-WindowsCopilotProfile -Lock $providerRelease.lock -DshHome $dshHome -NpmGlobalRoot $globalRoot `
            -ProviderArtifactPath $artifact -Catalog $catalog -BackupRoot (Join-Path $caseRoot 'backups') `
            -DesktopExecutablePath $desktopPath -SkipPackageInstall | Out-Null

        $updated = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $updated.dependencies.'dsh-github-copilot' |
            Should -Be "file:../../artifacts/$($lock.components.copilotIntegration.source.commit)/$($lock.components.copilotIntegration.package.artifact.name)"
        $materialized = Join-Path $profileRoot 'node_modules\dsh-github-copilot'
        Test-Path -LiteralPath (Join-Path $materialized 'package.json') -PathType Leaf | Should -Be $true
        [bool]((Get-Item -LiteralPath $materialized).Attributes -band [IO.FileAttributes]::ReparsePoint) |
            Should -Be $false
    }

    It 'fails closed when the retired gateway catalog helper is called' {
        { Get-WindowsCopilotRouteModels -Lock $lock -Catalog $catalog } |
            Should -Throw '*direct baseline uses the account-available built-in pi-ai route*'
    }

    It 'updates the profile while preserving official links and provider bytes idempotently' {
        $dshHome = Join-Path $TestDrive 'profile-fixture\.dsh'
        $profileRoot = Join-Path $dshHome 'profiles\web'
        $globalRoot = Join-Path $TestDrive 'profile-fixture\global'
        $backupRoot = Join-Path $TestDrive 'profile-fixture\backups'
        New-Item -ItemType Directory -Path $profileRoot, $globalRoot -Force | Out-Null
        $desktopPath = Join-Path $TestDrive 'profile-fixture\desktop\deepseek-harness-desktop.exe'
        New-DesktopInternalPluginFixture -ProfileRoot $profileRoot -DesktopExecutablePath $desktopPath
        [IO.Directory]::Delete((Join-Path $profileRoot 'node_modules\dsh-tauri-panel-extension'), $false)
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'profile\package.json') -Destination $profileRoot
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'profile\pnpm-workspace.yaml') -Destination $profileRoot
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'settings.yaml') -Destination (Join-Path $dshHome 'settings.yaml')
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'credentials.yaml') -Destination (Join-Path $dshHome '.credentials.yaml')
        Copy-Item -Path (Join-Path $fixtureRoot 'global\*') -Destination $globalRoot -Recurse
        $legacyProfile = Get-Content -LiteralPath (Join-Path $profileRoot 'package.json') -Raw | ConvertFrom-Json
        $expectedOfficialDependencies = @{}
        foreach ($plugin in @($lock.components.desktop.internalPlugins)) {
            $target = Join-Path (Split-Path -Parent $desktopPath) ([string]$plugin.relativePath)
            $dependency = 'link:' + ([IO.Path]::GetFullPath($target).Replace('\', '/'))
            $legacyProfile.dependencies | Add-Member -NotePropertyName ([string]$plugin.name) `
                -NotePropertyValue $dependency
            $expectedOfficialDependencies[[string]$plugin.name] = $dependency
        }
        $legacyProfile.dependencies | Add-Member -NotePropertyName 'dsh-web-search-provider' `
            -NotePropertyValue '0.2.3-cloga.3'
        $legacyProfile.dependencies | Add-Member -NotePropertyName 'dsh-github-copilot' `
            -NotePropertyValue 'file:../../artifacts/8af7edb70c07e9da4b451e1ae07d73e99040340e/dsh-github-copilot-0.3.0-cloga.3.tgz'
        $legacyProfile.dsh.profile.bundles += 'dsh-web-search-provider'
        $legacyProfile.dsh.profile.bundles += 'dsh-github-copilot'
        $legacyProfile | ConvertTo-Json -Depth 12 |
            Set-Content -LiteralPath (Join-Path $profileRoot 'package.json') -Encoding UTF8
        Copy-Item -LiteralPath (Join-Path $globalRoot 'dsh-web-search-provider') `
            -Destination (Join-Path $profileRoot 'node_modules\dsh-web-search-provider') -Recurse
        Copy-Item -LiteralPath (Join-Path $globalRoot 'dsh-github-copilot') `
            -Destination (Join-Path $profileRoot 'node_modules\dsh-github-copilot') -Recurse
        $legacyCopilotManifestPath = Join-Path $profileRoot 'node_modules\dsh-github-copilot\package.json'
        $legacyCopilotManifest = Get-Content -LiteralPath $legacyCopilotManifestPath -Raw | ConvertFrom-Json
        $legacyCopilotManifest.version = '0.3.0-cloga.3'
        $legacyCopilotManifest | ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath $legacyCopilotManifestPath -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $profileRoot 'node_modules\dsh-github-copilot\legacy-sentinel.txt') `
            -Value 'pre-client-handoff-.3' -Encoding UTF8
        $providerRelease = New-ProviderReleaseFixture -Root (Join-Path $TestDrive 'idempotent-provider-release')
        $artifact = $providerRelease.path

        $first = Set-WindowsCopilotProfile -Lock $providerRelease.lock -DshHome $dshHome -NpmGlobalRoot $globalRoot `
            -ProviderArtifactPath $artifact -Catalog $catalog -BackupRoot $backupRoot `
            -DesktopExecutablePath $desktopPath -SkipPackageInstall
        $second = Set-WindowsCopilotProfile -Lock $providerRelease.lock -DshHome $dshHome -NpmGlobalRoot $globalRoot `
            -ProviderArtifactPath $artifact -Catalog $catalog -BackupRoot $backupRoot `
            -DesktopExecutablePath $desktopPath -SkipPackageInstall

        $profile = Get-Content -LiteralPath (Join-Path $profileRoot 'package.json') -Raw | ConvertFrom-Json
        $profile.dependencies.'fixture-dependency' | Should -Be '1.0.0'
        $profile.dependencies.'dsh-github-copilot' | Should -Match '^file:\.\./\.\./artifacts/'
        $profile.dependencies.PSObject.Properties.Name | Should -Not -Contain 'dsh-web-search-provider'
        foreach ($plugin in @($lock.components.desktop.internalPlugins)) {
            $profile.dependencies.([string]$plugin.name) |
                Should -Be $expectedOfficialDependencies[[string]$plugin.name]
        }
        @($profile.dsh.profile.bundles | Where-Object { $_ -eq 'dsh-github-copilot' }).Count | Should -Be 1
        @($profile.dsh.profile.bundles | Where-Object { $_ -eq 'dsh-web-search-provider' }).Count | Should -Be 0
        Test-Path -LiteralPath (Join-Path $profileRoot 'node_modules\dsh-web-search-provider') |
            Should -Be $false
        foreach ($bundle in @($lock.profile.requiredBundles)) {
            @($profile.dsh.profile.bundles | Where-Object { $_ -eq $bundle }).Count | Should -Be 1
        }

        $workspace = Get-Content -LiteralPath (Join-Path $profileRoot 'pnpm-workspace.yaml') -Raw
        $workspace | Should -Match "'@google/genai': true"
        $workspace | Should -Match "'protobufjs': true"
        @($workspace -split "`n" | Where-Object { $_ -match '@google/genai' }).Count | Should -Be 1

        $settings = Get-Content -LiteralPath (Join-Path $dshHome 'settings.yaml') -Raw
        $settings | Should -Match 'fixture-provider:'
        $settings | Should -Match 'github-copilot:'
        $settings | Should -Match 'fixture-responses-model'
        $settings | Should -Match 'fixture-completions-model'
        $settings | Should -Match 'api: openai-responses'
        $settings | Should -Match 'api: openai-completions'
        $settings | Should -Not -Match 'baseURL:\s*http://127\.0\.0\.1:7777|COPILOT_GITHUB_TOKEN|github-copilot-chat:'

        foreach ($name in @($lock.components.desktop.internalPlugins.name)) {
            $target = Join-Path $profileRoot (Join-Path 'node_modules' $name)
            (Test-Path -LiteralPath (Join-Path $target 'package.json')) | Should -Be $true
            [bool]((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint) | Should -Be $true
        }
        $providerTarget = Join-Path $profileRoot 'node_modules\dsh-github-copilot'
        [bool]((Get-Item -LiteralPath $providerTarget).Attributes -band [IO.FileAttributes]::ReparsePoint) |
            Should -Be $false
        (Test-Path -LiteralPath $first.backupRoot) | Should -Be $true
        (Test-Path -LiteralPath $second.backupRoot) | Should -Be $true
        Test-Path -LiteralPath (Join-Path $first.backupRoot 'plugins\dsh-github-copilot\legacy-sentinel.txt') |
            Should -Be $true
        $first.backupRoot | Should -Not -Match '\\sessions\\'

    }



    It 'atomically migrates the exact legacy physical Tauri profile state' {
        $caseRoot = Join-Path $TestDrive 'legacy-profile'
        $dshHome = Join-Path $caseRoot '.dsh'
        $profileRoot = Join-Path $dshHome 'profiles\web'
        $packagePath = Join-Path $profileRoot 'package.json'
        $globalRoot = Join-Path $caseRoot 'global'
        $desktopPath = Join-Path $caseRoot 'desktop\deepseek-harness-desktop.exe'
        New-Item -ItemType Directory -Path $profileRoot, $globalRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'profile\package.json') -Destination $profileRoot
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'profile\pnpm-workspace.yaml') -Destination $profileRoot
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'settings.yaml') -Destination (Join-Path $dshHome 'settings.yaml')
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'credentials.yaml') -Destination (Join-Path $dshHome '.credentials.yaml')
        Copy-Item -Path (Join-Path $fixtureRoot 'global\*') -Destination $globalRoot -Recurse
        New-DesktopInternalPluginFixture -ProfileRoot $profileRoot -DesktopExecutablePath $desktopPath
        Set-LegacyPhysicalPluginFixture -ProfileRoot $profileRoot -PackagePath $packagePath
        $providerRelease = New-ProviderReleaseFixture -Root $caseRoot
        $artifact = $providerRelease.path

        $module = Get-Module WindowsCopilotDeployment
        $migration = & $module {
            param($Lock, $DshHome, $DesktopExecutablePath)
            Get-WindowsCopilotProfileMigrationPlan -Lock $Lock -DshHome $DshHome `
                -DesktopExecutablePath $DesktopExecutablePath
        } $lock $dshHome $desktopPath
        @($migration.dependenciesToRemove | Sort-Object) |
            Should -Be @($lock.profile.legacyPhysicalPlugins.name | Sort-Object)

        $result = Set-WindowsCopilotProfile -Lock $providerRelease.lock -DshHome $dshHome -NpmGlobalRoot $globalRoot `
            -ProviderArtifactPath $artifact -Catalog $catalog -BackupRoot (Join-Path $caseRoot 'backups') `
            -DesktopExecutablePath $desktopPath -SkipPackageInstall

        $profile = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($legacy in @($lock.profile.legacyPhysicalPlugins)) {
            $profile.dependencies.PSObject.Properties.Name | Should -Not -Contain ([string]$legacy.name)
            $target = Join-Path $profileRoot (Join-Path 'node_modules' ([string]$legacy.name))
            [bool]((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint) |
                Should -Be $true
            (Get-Content -LiteralPath (Join-Path $target 'package.json') -Raw | ConvertFrom-Json).version |
                Should -Be '0.6.7'
            Test-Path -LiteralPath (Join-Path $result.backupRoot `
                (Join-Path 'plugins' (Join-Path ([string]$legacy.name) 'legacy-sentinel.txt'))) |
                Should -Be $true
        }
    }

    It 'rolls back the exact legacy profile when package installation fails' {
        $caseRoot = Join-Path $TestDrive 'legacy-rollback'
        $dshHome = Join-Path $caseRoot '.dsh'
        $profileRoot = Join-Path $dshHome 'profiles\web'
        $packagePath = Join-Path $profileRoot 'package.json'
        $globalRoot = Join-Path $caseRoot 'global'
        $desktopPath = Join-Path $caseRoot 'desktop\deepseek-harness-desktop.exe'
        New-Item -ItemType Directory -Path $profileRoot, $globalRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'profile\package.json') -Destination $profileRoot
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'profile\pnpm-workspace.yaml') -Destination $profileRoot
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'settings.yaml') -Destination (Join-Path $dshHome 'settings.yaml')
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'credentials.yaml') -Destination (Join-Path $dshHome '.credentials.yaml')
        Copy-Item -Path (Join-Path $fixtureRoot 'global\*') -Destination $globalRoot -Recurse
        New-DesktopInternalPluginFixture -ProfileRoot $profileRoot -DesktopExecutablePath $desktopPath
        Set-LegacyPhysicalPluginFixture -ProfileRoot $profileRoot -PackagePath $packagePath
        $packageBefore = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8
        $providerRelease = New-ProviderReleaseFixture -Root $caseRoot
        $artifact = $providerRelease.path
        Mock Invoke-PinnedPnpmCommands -ModuleName WindowsCopilotDeployment { throw 'fixture pnpm failure' }

        {
            Set-WindowsCopilotProfile -Lock $providerRelease.lock -DshHome $dshHome -NpmGlobalRoot $globalRoot `
                -ProviderArtifactPath $artifact -Catalog $catalog -BackupRoot (Join-Path $caseRoot 'backups') `
                -DesktopExecutablePath $desktopPath
        } | Should -Throw '*fixture pnpm failure*'

        Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | Should -Be $packageBefore
        foreach ($legacy in @($lock.profile.legacyPhysicalPlugins)) {
            $target = Join-Path $profileRoot (Join-Path 'node_modules' ([string]$legacy.name))
            [bool]((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint) |
                Should -Be $false
            Get-Content -LiteralPath (Join-Path $target 'legacy-sentinel.txt') -Raw |
                Should -Match ([regex]::Escape([string]$legacy.version))
        }
        $installedArtifact = Join-Path (Join-Path $dshHome 'artifacts') `
            (Join-Path ([string]$lock.components.copilotIntegration.source.commit) (Split-Path -Leaf $artifact))
        Test-Path -LiteralPath $installedArtifact |
            Should -Be $false
    }

    It 'rejects an unknown physical Tauri profile before Apply mutates the machine' {
        $caseRoot = Join-Path $TestDrive 'unknown-legacy'
        $dshHome = Join-Path $caseRoot '.dsh'
        $profileRoot = Join-Path $dshHome 'profiles\web'
        $packagePath = Join-Path $profileRoot 'package.json'
        $desktopPath = Join-Path $caseRoot 'desktop\deepseek-harness-desktop.exe'
        New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'profile\package.json') -Destination $profileRoot
        New-DesktopInternalPluginFixture -ProfileRoot $profileRoot -DesktopExecutablePath $desktopPath
        Set-LegacyPhysicalPluginFixture -ProfileRoot $profileRoot -PackagePath $packagePath
        $unknownPackage = Join-Path $profileRoot 'node_modules\dsh-tauri\package.json'
        $metadata = Get-Content -LiteralPath $unknownPackage -Raw | ConvertFrom-Json
        $metadata.version = '9.9.9'
        $metadata | ConvertTo-Json | Set-Content -LiteralPath $unknownPackage -Encoding UTF8

        $module = Get-Module WindowsCopilotDeployment
        {
            & $module {
                param($Lock, $DshHome, $DesktopExecutablePath)
                Get-WindowsCopilotProfileMigrationPlan -Lock $Lock -DshHome $DshHome `
                    -DesktopExecutablePath $DesktopExecutablePath
            } $lock $dshHome $desktopPath
        } | Should -Throw '*official Desktop internal-plugin link is missing or invalid*'
        Test-Path -LiteralPath (Join-Path $caseRoot 'backups') | Should -Be $false
    }

    It 'rejects a partial legacy Tauri triplet before profile mutation' {
        $caseRoot = Join-Path $TestDrive 'partial-legacy'
        $dshHome = Join-Path $caseRoot '.dsh'
        $profileRoot = Join-Path $dshHome 'profiles\web'
        $packagePath = Join-Path $profileRoot 'package.json'
        $desktopPath = Join-Path $caseRoot 'desktop\deepseek-harness-desktop.exe'
        New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'profile\package.json') -Destination $profileRoot
        New-DesktopInternalPluginFixture -ProfileRoot $profileRoot -DesktopExecutablePath $desktopPath
        Set-LegacyPhysicalPluginFixture -ProfileRoot $profileRoot -PackagePath $packagePath
        foreach ($name in @('dsh-tauri-ui', 'dsh-tauri-worktree')) {
            $target = Join-Path $profileRoot (Join-Path 'node_modules' $name)
            Remove-Item -LiteralPath $target -Recurse -Force
        }
        $profile = Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json
        $profile.dependencies.PSObject.Properties.Remove('dsh-tauri-ui')
        $profile.dependencies.PSObject.Properties.Remove('dsh-tauri-worktree')
        $profile | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $packagePath -Encoding UTF8
        $providerRelease = New-ProviderReleaseFixture -Root $caseRoot
        $artifact = $providerRelease.path

        {
            Set-WindowsCopilotProfile -Lock $providerRelease.lock -DshHome $dshHome `
                -NpmGlobalRoot (Join-Path $caseRoot 'global') -ProviderArtifactPath $artifact `
                -Catalog $catalog -BackupRoot (Join-Path $caseRoot 'backups') `
                -DesktopExecutablePath $desktopPath -SkipPackageInstall
        } | Should -Throw '*complete reviewed legacy physical-plugin state*'
        Test-Path -LiteralPath (Join-Path $caseRoot 'backups') | Should -Be $false
        Test-Path -LiteralPath (Join-Path $dshHome 'artifacts') | Should -Be $false
    }

    It 'rejects a dangling internal-plugin junction before Apply mutation' {
        $caseRoot = Join-Path $TestDrive 'dangling-internal'
        $dshHome = Join-Path $caseRoot '.dsh'
        $profileRoot = Join-Path $dshHome 'profiles\web'
        $desktopPath = Join-Path $caseRoot 'desktop\deepseek-harness-desktop.exe'
        New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'profile\package.json') -Destination $profileRoot
        New-DesktopInternalPluginFixture -ProfileRoot $profileRoot -DesktopExecutablePath $desktopPath
        $officialTarget = Join-Path (Split-Path -Parent $desktopPath) `
            'resources\node_modules\dsh-tauri'
        Remove-Item -LiteralPath $officialTarget -Recurse -Force

        $module = Get-Module WindowsCopilotDeployment
        {
            & $module {
                param($Lock, $DshHome, $DesktopExecutablePath)
                Get-WindowsCopilotProfileMigrationPlan -Lock $Lock -DshHome $DshHome `
                    -DesktopExecutablePath $DesktopExecutablePath
            } $lock $dshHome $desktopPath
        } | Should -Throw '*official Desktop internal-plugin link is missing or invalid*'
        Test-Path -LiteralPath (Join-Path $caseRoot 'backups') | Should -Be $false
    }

    It 'rejects an internal plugin link outside the official Desktop directory before mutation' {
        $caseRoot = Join-Path $TestDrive 'wrong-internal-link'
        $dshHome = Join-Path $caseRoot '.dsh'
        $profileRoot = Join-Path $dshHome 'profiles\web'
        $packagePath = Join-Path $profileRoot 'package.json'
        $desktopPath = Join-Path $caseRoot 'desktop\deepseek-harness-desktop.exe'
        New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'profile\package.json') -Destination $profileRoot
        New-DesktopInternalPluginFixture -ProfileRoot $profileRoot -DesktopExecutablePath $desktopPath
        $wrongTarget = Join-Path $caseRoot 'unofficial\dsh-tauri'
        New-Item -ItemType Directory -Path $wrongTarget -Force | Out-Null
        '{"name":"dsh-tauri","version":"0.6.7"}' |
            Set-Content -LiteralPath (Join-Path $wrongTarget 'package.json') -Encoding UTF8
        $profile = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $profile.dependencies | Add-Member -NotePropertyName 'dsh-tauri' `
            -NotePropertyValue ('link:' + ([IO.Path]::GetFullPath($wrongTarget).Replace('\', '/')))
        $profile | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $packagePath -Encoding UTF8
        $module = Get-Module WindowsCopilotDeployment

        {
            & $module {
                param($Lock, $DshHome, $DesktopExecutablePath)
                Get-WindowsCopilotProfileMigrationPlan -Lock $Lock -DshHome $DshHome `
                    -DesktopExecutablePath $DesktopExecutablePath
            } $lock $dshHome $desktopPath
        } | Should -Throw '*neither an exact official Desktop link nor a reviewed legacy dependency*'
        (Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | ConvertFrom-Json).
            dependencies.'dsh-tauri' | Should -Match '^link:'
    }

    It 'validates composed provider and hosted-search evidence fixtures' {
        $composed = Test-WindowsCopilotComposedConfig -Lock $lock `
            -Path (Join-Path $fixtureRoot 'composed-config.yml')
        $composedInMemory = Test-WindowsCopilotComposedConfig -Lock $lock `
            -Content (Get-Content -LiteralPath (Join-Path $fixtureRoot 'composed-config.yml') -Raw)
        $search = Test-WindowsCopilotSearchResponse -Lock $lock `
            -ResponsePath (Join-Path $fixtureRoot 'search-response.json')
        $composed.valid | Should -Be $true
        $composedInMemory.valid | Should -Be $true
        $composed.managedConfigValid | Should -Be $true
        $search.providerNativeEvidence | Should -Be $true
        $search.traditionalSearchEvidence | Should -Be $true
        $search.cordisSessionMounted | Should -Be $true
        $search.emptyReasoningSuppressed | Should -Be $true
        $search.nonemptyReasoningEmitted | Should -Be $true
        $search.deepSeekFallback | Should -Be $false
    }

    It 'rejects missing positive Responses or Anthropic reasoning evidence' {
        foreach ($property in @('emittedThinkCardsForNonempty', 'emittedThinkChunksForNonempty')) {
            $response = Get-Content -LiteralPath (Join-Path $fixtureRoot 'search-response.json') -Raw |
                ConvertFrom-Json
            if ($property -eq 'emittedThinkCardsForNonempty') {
                $response.reasoning.responses.$property = @()
            } else {
                $response.reasoning.anthropic.$property = @()
            }
            $path = Join-Path $TestDrive "$property.json"
            $response | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding UTF8
            {
                Test-WindowsCopilotSearchResponse -Lock $lock -ResponsePath $path
            } | Should -Throw '*did not produce*'
        }
    }

    It 'binds emitted Think output to exact nonempty reasoning input' {
        $response = Get-Content -LiteralPath (Join-Path $fixtureRoot 'search-response.json') -Raw |
            ConvertFrom-Json
        $response.reasoning.responses.emittedThinkCardsForNonempty = @('Different reasoning.')
        $path = Join-Path $TestDrive 'mismatched-reasoning.json'
        $response | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding UTF8
        {
            Test-WindowsCopilotSearchResponse -Lock $lock -ResponsePath $path
        } | Should -Throw '*did not produce*'
    }

    It 'rejects reordered or duplicate-substituted Think output' {
        $response = Get-Content -LiteralPath (Join-Path $fixtureRoot 'search-response.json') -Raw |
            ConvertFrom-Json
        $response.reasoning.responses.nonemptyItems = @(
            [pscustomobject]@{ type = 'reasoning'; content = @([pscustomobject]@{ type = 'reasoning_text'; text = 'a' }) },
            [pscustomobject]@{ type = 'reasoning'; content = @([pscustomobject]@{ type = 'reasoning_text'; text = 'a' }) },
            [pscustomobject]@{ type = 'reasoning'; content = @([pscustomobject]@{ type = 'reasoning_text'; text = 'b' }) }
        )
        $response.reasoning.responses.emittedThinkCardsForNonempty = @('a', 'b', 'b')
        $path = Join-Path $TestDrive 'duplicate-reasoning.json'
        $response | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding UTF8
        {
            Test-WindowsCopilotSearchResponse -Lock $lock -ResponsePath $path
        } | Should -Throw '*did not produce*'
    }

    It 'requires explicit empty and nonempty reasoning properties' {
        $response = Get-Content -LiteralPath (Join-Path $fixtureRoot 'search-response.json') -Raw |
            ConvertFrom-Json
        $response.reasoning.responses.emptyItems[0].PSObject.Properties.Remove('content')
        $response.reasoning.anthropic.emittedThinkChunksForNonempty = @(
            'Fixture Anthropic reasoning.',
            ''
        )
        $path = Join-Path $TestDrive 'missing-reasoning-properties.json'
        $response | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding UTF8
        {
            Test-WindowsCopilotSearchResponse -Lock $lock -ResponsePath $path
        } | Should -Throw
    }

    It 'rejects non-string emitted Think output without coercion' {
        foreach ($protocol in @('responses', 'anthropic')) {
            $response = Get-Content -LiteralPath (Join-Path $fixtureRoot 'search-response.json') -Raw |
                ConvertFrom-Json
            if ($protocol -eq 'responses') {
                $response.reasoning.responses.nonemptyItems[0].content[0].text = '1'
                $response.reasoning.responses.emittedThinkCardsForNonempty = @(1)
            } else {
                $response.reasoning.anthropic.nonemptyItems[0].thinking = '1'
                $response.reasoning.anthropic.emittedThinkChunksForNonempty = @(1)
            }
            $path = Join-Path $TestDrive "$protocol-numeric-reasoning.json"
            $response | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding UTF8
            {
                Test-WindowsCopilotSearchResponse -Lock $lock -ResponsePath $path
            } | Should -Throw '*did not produce*'
        }
    }

    It 'uses ordinal reasoning text comparison' {
        $response = Get-Content -LiteralPath (Join-Path $fixtureRoot 'search-response.json') -Raw |
            ConvertFrom-Json
        $response.reasoning.responses.nonemptyItems[0].content[0].text =
            "Fixture$([char]0) Responses reasoning."
        $response.reasoning.responses.emittedThinkCardsForNonempty = @('Fixture Responses reasoning.')
        $path = Join-Path $TestDrive 'ordinal-reasoning.json'
        $response | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding UTF8
        {
            Test-WindowsCopilotSearchResponse -Lock $lock -ResponsePath $path
        } | Should -Throw '*did not produce*'
    }

    It 'rejects scalar reasoning sequence containers' {
        foreach ($protocol in @('responses', 'anthropic')) {
            $response = Get-Content -LiteralPath (Join-Path $fixtureRoot 'search-response.json') -Raw |
                ConvertFrom-Json
            if ($protocol -eq 'responses') {
                $response.reasoning.responses.nonemptyItems =
                    $response.reasoning.responses.nonemptyItems[0]
                $response.reasoning.responses.emittedThinkCardsForNonempty =
                    'Fixture Responses reasoning.'
            } else {
                $response.reasoning.anthropic.nonemptyItems =
                    $response.reasoning.anthropic.nonemptyItems[0]
                $response.reasoning.anthropic.emittedThinkChunksForNonempty =
                    'Fixture Anthropic reasoning.'
            }
            $path = Join-Path $TestDrive "$protocol-scalar-reasoning.json"
            $response | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding UTF8
            {
                Test-WindowsCopilotSearchResponse -Lock $lock -ResponsePath $path
            } | Should -Throw '*properties are missing*'
        }
    }

    It 'rejects managed provider fields outside the config subtree' {
        $content = @'
- id: github-copilot
  name: dsh-github-copilot
  enabled: true
  providers: [github-copilot]
  config:
    probe: true
'@
        { Test-WindowsCopilotComposedConfig -Lock $lock -Content $content } |
            Should -Throw '*managed-copilot-search-config-missing*'
    }



    It 'validates the Copilot integration source against the exported deployment contract' {
        $result = Test-CopilotIntegrationDeploymentContract -Lock $lock -SourceRoot (Join-Path $fixtureRoot 'provider')
        $result.valid | Should -Be $true
        $result.sourceVerified | Should -Be $true
        $result.artifactVerified | Should -Be $false
        @($result.capabilities).Count | Should -Be 14
        @($result.capabilities) | Should -Contain 'client-module-loader-handoff'
        @($result.capabilities) | Should -Contain 'copilot-optional-tool-arguments'
        @($result.capabilities) | Should -Contain 'strict-remote-result-codecs'
        @($result.capabilities) | Should -Contain 'strict-json-oauth-grant-normalization'
        @($result.capabilities) | Should -Contain 'existing-grant-route-self-healing'
    }

    It 'accepts packed provider metadata after pnpm strips packageManager' {
        $providerRoot = Join-Path $TestDrive 'packed-provider-contract'
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'provider') -Destination $providerRoot -Recurse
        $packagePath = Join-Path $providerRoot 'package.json'
        $package = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $package.PSObject.Properties.Remove('packageManager')
        $package | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $packagePath -Encoding UTF8

        $result = Test-ProviderDeploymentContract -Lock $lock -SourceRoot $providerRoot
        $result.valid | Should -Be $true
    }

    It 'rejects a provider source missing a required capability' {
        $providerRoot = Join-Path $TestDrive 'provider-contract'
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'provider') -Destination $providerRoot -Recurse
        $baselinePath = Join-Path $providerRoot 'deployment-baseline.json'
        $baseline = Get-Content -LiteralPath $baselinePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $baseline.capabilities = @($baseline.capabilities | Where-Object {
            $_.id -ne 'shared-copilot-credential-refresh'
        })
        $baseline | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $baselinePath -Encoding UTF8

        $threw = $false
        try {
            Test-ProviderDeploymentContract -Lock $lock -SourceRoot $providerRoot | Out-Null
        } catch {
            $threw = $true
        }
        $threw | Should -Be $true
    }

    It 'rejects a provider source missing the authorization runtime dependency' {
        $providerRoot = Join-Path $TestDrive 'provider-runtime-contract'
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'provider') -Destination $providerRoot -Recurse
        $packagePath = Join-Path $providerRoot 'package.json'
        $package = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $package.dependencies.PSObject.Properties.Remove('@deepseek-ai/dsh-authorization')
        $package | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $packagePath -Encoding UTF8

        {
            Test-ProviderDeploymentContract -Lock $lock -SourceRoot $providerRoot | Out-Null
        } | Should -Throw '*deployment-baseline metadata does not match*'
    }

    It 'rejects a provider source missing the zod runtime dependency' {
        $providerRoot = Join-Path $TestDrive 'provider-zod-runtime-contract'
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'provider') -Destination $providerRoot -Recurse
        $packagePath = Join-Path $providerRoot 'package.json'
        $package = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $package.dependencies.PSObject.Properties.Remove('zod')
        $package | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $packagePath -Encoding UTF8

        {
            Test-ProviderDeploymentContract -Lock $lock -SourceRoot $providerRoot | Out-Null
        } | Should -Throw '*deployment-baseline metadata does not match*'
    }

    It 'resolves only the locked Copilot Release URL or a hash-matching local artifact' {
        $lockedUrl = [string]$lock.components.copilotIntegration.package.artifact.url
        (Resolve-LockedCopilotPackageSpec -Lock $lock) | Should -Be $lockedUrl
        (Resolve-LockedCopilotPackageSpec -Lock $lock -PackageSpec $lockedUrl) | Should -Be $lockedUrl

        $artifactRoot = Join-Path $TestDrive 'locked-provider-spec'
        New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
        $artifact = Join-Path $artifactRoot ([string]$lock.components.copilotIntegration.package.artifact.name)
        Set-Content -LiteralPath $artifact -Value 'locked provider fixture' -Encoding UTF8
        $fixtureLock = $lock | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        $fixtureLock.components.copilotIntegration.package.artifact.sha256 =
            (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
        (Resolve-LockedCopilotPackageSpec -Lock $fixtureLock -PackageSpec $artifact) |
            Should -Be ([IO.Path]::GetFullPath($artifact))

        { Resolve-LockedCopilotPackageSpec -Lock $lock -PackageSpec 'dsh-github-copilot' } |
            Should -Throw '*exact locked Release URL*'
        { Resolve-LockedCopilotPackageSpec -Lock $lock -PackageSpec 'https://example.test/provider.tgz' } |
            Should -Throw '*exact locked Release URL*'
        $wrongName = Join-Path $artifactRoot 'renamed.tgz'
        Copy-Item -LiteralPath $artifact -Destination $wrongName
        { Resolve-LockedCopilotPackageSpec -Lock $fixtureLock -PackageSpec $wrongName } |
            Should -Throw '*artifact name mismatch*'
        Set-Content -LiteralPath $artifact -Value 'tampered provider fixture' -Encoding UTF8
        { Resolve-LockedCopilotPackageSpec -Lock $fixtureLock -PackageSpec $artifact } |
            Should -Throw '*SHA-256 mismatch*'
    }

    It 'rejects an unverified provider artifact before the exported profile mutator creates backups' {
        $caseRoot = Join-Path $TestDrive 'profile-artifact-before-backup'
        $artifact = Join-Path $caseRoot ([string]$lock.components.copilotIntegration.package.artifact.name)
        New-Item -ItemType Directory -Path $caseRoot -Force | Out-Null
        Set-Content -LiteralPath $artifact -Value 'tampered provider artifact' -Encoding UTF8
        $backupRoot = Join-Path $caseRoot 'backups'
        {
            Set-WindowsCopilotProfile -Lock $lock -DshHome (Join-Path $caseRoot '.dsh') `
                -NpmGlobalRoot (Join-Path $caseRoot 'global') -ProviderArtifactPath $artifact `
                -BackupRoot $backupRoot -SkipPackageInstall
        } | Should -Throw '*SHA-256 mismatch*'
        Test-Path -LiteralPath $backupRoot | Should -Be $false
    }

    It 'rejects a tampered release artifact' {
        $artifact = Join-Path $TestDrive 'tampered.exe'
        Set-Content -LiteralPath $artifact -Value 'tampered' -Encoding UTF8
        $threw = $false
        try {
            Test-LockedArtifact -Path $artifact -Sha256 $lock.components.desktop.artifact.sha256 | Out-Null
        } catch {
            $threw = $true
        }
        $threw | Should -Be $true
    }

    It 'rejects a locked artifact with the wrong filename' {
        $artifact = Join-Path $TestDrive 'renamed.exe'
        Set-Content -LiteralPath $artifact -Value 'fixture' -Encoding UTF8
        $sha = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash
        $threw = $false
        try {
            Test-LockedArtifact -Path $artifact -Sha256 $sha -ExpectedName 'locked.exe' | Out-Null
        } catch {
            $threw = $true
        }
        $threw | Should -Be $true
    }













    It 'rejects an IPv6-only listener for the locked IPv4 address' {
        InModuleScope WindowsCopilotDeployment {
            Mock Get-NetTCPConnection {
                [pscustomobject]@{
                    LocalAddress = '::1'
                    LocalPort = 3080
                    OwningProcess = 101
                    State = 'Listen'
                }
            }
            $listener = Test-LoopbackListener -HostName '127.0.0.1' -Port 3080
            $listener.listening | Should -Be $false
            $listener.loopbackOnly | Should -Be $false
            @($listener.owningProcessIds).Count | Should -Be 0
        }
    }

    It 'keeps unsupported non-legacy YAML untouched instead of synthesizing routes' {
        foreach ($content in @(
            "'llm-pi-ai':`n  providers: {}`n",
            "llm-pi-ai:`n  'providers':`n    fixture: {}`n"
        )) {
            $settingsPath = Join-Path $TestDrive ("unsupported-" + [guid]::NewGuid() + '.yaml')
            Set-Content -LiteralPath $settingsPath -Value $content -Encoding UTF8 -NoNewline
            $before = Get-Content -LiteralPath $settingsPath -Raw
            (Set-WindowsCopilotRoutes -Lock $lock -SettingsPath $settingsPath -Catalog $catalog).changed |
                Should -Be $false
            Get-Content -LiteralPath $settingsPath -Raw | Should -Be $before
        }
    }

    It 'preserves official Desktop plugin junctions while materializing the provider' {
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { return }
        $dshHome = Join-Path $TestDrive 'junction-fixture\.dsh'
        $profileRoot = Join-Path $dshHome 'profiles\web'
        $globalRoot = Join-Path $TestDrive 'junction-fixture\global'
        $backupRoot = Join-Path $TestDrive 'junction-fixture\backups'
        New-Item -ItemType Directory -Path $profileRoot, $globalRoot -Force | Out-Null
        $desktopPath = Join-Path $TestDrive 'junction-fixture\desktop\deepseek-harness-desktop.exe'
        New-DesktopInternalPluginFixture -ProfileRoot $profileRoot -DesktopExecutablePath $desktopPath
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'profile\package.json') -Destination $profileRoot
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'profile\pnpm-workspace.yaml') -Destination $profileRoot
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'settings.yaml') -Destination (Join-Path $dshHome 'settings.yaml')
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'credentials.yaml') -Destination (Join-Path $dshHome '.credentials.yaml')
        Copy-Item -Path (Join-Path $fixtureRoot 'global\*') -Destination $globalRoot -Recurse
        $officialTauri = Join-Path (Split-Path -Parent $desktopPath) 'resources\node_modules\dsh-tauri'
        Set-Content -LiteralPath (Join-Path $officialTauri 'sentinel.txt') -Value 'keep' -Encoding UTF8
        $nodeModules = Join-Path $profileRoot 'node_modules'
        $providerRelease = New-ProviderReleaseFixture -Root (Join-Path $TestDrive 'junction-provider-release')
        $artifact = $providerRelease.path

        Set-WindowsCopilotProfile -Lock $providerRelease.lock -DshHome $dshHome -NpmGlobalRoot $globalRoot `
            -ProviderArtifactPath $artifact -Catalog $catalog -BackupRoot $backupRoot `
            -DesktopExecutablePath $desktopPath -SkipPackageInstall | Out-Null

        Test-Path -LiteralPath (Join-Path $officialTauri 'sentinel.txt') | Should -Be $true
        [bool]((Get-Item -LiteralPath (Join-Path $nodeModules 'dsh-tauri')).Attributes -band [IO.FileAttributes]::ReparsePoint) |
            Should -Be $true
    }

    It 'runs the entry script in non-mutating check mode with its default manifest' {
        $dshHome = Join-Path $TestDrive 'check-only\.dsh'
        $scriptPath = Join-Path $repoRoot 'tools\install-windows-copilot.ps1'
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath `
            -DshHome $dshHome `
            -NpmGlobalRoot (Join-Path $fixtureRoot 'global') `
            -ModelCatalogPath (Join-Path $fixtureRoot 'model-catalog.json') `
            -ComposedConfigPath (Join-Path $fixtureRoot 'composed-config.yml') `
            -SearchSmokeResponsePath (Join-Path $fixtureRoot 'search-response.json') `
            -SkipRuntimeChecks
        $LASTEXITCODE | Should -Be 0
        $result = ($output -join "`n") | ConvertFrom-Json
        $result.mode | Should -Be 'check'
        $result.checks.manifest.valid | Should -Be $true
        Test-Path -LiteralPath $dshHome | Should -Be $false
    }


    BeforeEach {
        $script:issuePreviousAppData = $env:APPDATA
        $script:issuePreviousDshCliPath = $env:DSH_CLI_PATH
        $env:APPDATA = Join-Path $TestDrive 'appdata'
    }

    AfterEach {
        $env:APPDATA = $script:issuePreviousAppData
        $env:DSH_CLI_PATH = $script:issuePreviousDshCliPath
    }
It 'requires the Desktop 0.10.3 official-only runtime contract' {
        (Test-WindowsCopilotLock -Lock $lock).valid | Should -Be $true
        $lock.components.desktop.version | Should -Be '0.10.3'
        $lock.components.PSObject.Properties.Name | Should -Not -Contain 'core'
        $lock.components.desktop.defaultRuntimeSelector | Should -Be 'desktop-official'
        @($lock.components.desktop.runtimeSelectors).Count | Should -Be 1
        $lock.components.desktop.runtimeSelectors[0].id | Should -Be 'desktop-official'
        $lock.components.desktop.runtimeSelectors[0].rootPackage.version | Should -Be '0.1.2-alpha.5'
        $lock.components.desktop.runtimeSelectors[0].package.version | Should -Be '0.1.2-rc.1'
        $lock.components.desktop.runtimeSelectors[0].package.entrypointSize | Should -Be 8021
        $lock.components.desktop.runtimeSelectors[0].package.entrypointSha256 |
            Should -Be 'dc23f6c5dd7df8834e3e38bdb9609d77b459834681ae9b7133b417b0c35f3166'
        @($lock.components.desktop.install.sideEffects.registryKeys).Count | Should -Be 1
        @($lock.components.desktop.install.sideEffects.shortcuts.specialFolder) |
            Should -Be @('Desktop', 'Programs')
        $runtimeSchema = $lock.acceptance.runtimeSchema
        $runtimeSchema.scope | Should -Be 'desktop-official'
        $runtimeSchema.root | Should -Be $lock.components.desktop.runtimeSelectors[0].root
        $runtimeSchema.source.repository | Should -Be 'github.com/deepseek-ai/deepseek-harness'
        $runtimeSchema.source.releaseTag | Should -Be 'dsh-v0.1.2-rc.1'
        $runtimeSchema.source.commit | Should -Be 'a66e4702047846cdaa10c66c9d3df3951f5ea70d'
        $runtimeSchema.wrapper.manifest | Should -Be 'package.json'
        $runtimeSchema.wrapper.manifestSha256 |
            Should -Be 'bcfbd3f14511fa9470ea748303a8f9c6307121d2741990823089c5677291e8ba'
        $runtimeSchema.wrapper.fileCount | Should -Be 10347
        $runtimeSchema.wrapper.totalBytes | Should -Be 134066533
        $runtimeSchema.wrapper.treeSha256 |
            Should -Be 'b0f32889536e1bce92a6bc032b11a6865e946015b44de5db4397f080e309c86d'
        $runtimeSchema.wrapper.reparseDirectoryCount | Should -Be 0
        $runtimeSchema.package.manifest |
            Should -Be 'node_modules\@deepseek-ai\dsh\package.json'
        $runtimeSchema.package.entrypoint |
            Should -Be 'node_modules\@deepseek-ai\dsh\lib\bin.js'
        @($runtimeSchema.requiredBuiltFiles).Count | Should -Be 3
        @($runtimeSchema.behavior.escalationProperties | Sort-Object) |
            Should -Be @('justification', 'sandbox_permissions')
        $runtimeSchema.behavior.escalationPropertiesRequired | Should -Be $false
        $runtimeSchema.behavior.providerCompatibilityOwner | Should -Be 'dsh-github-copilot'
        $runtimeSchema.releaseStatus | Should -Be 'official-desktop-managed'
        $copilot = $lock.components.copilotIntegration
        $copilot.source.pullRequest | Should -Be 56
        $copilot.source.commit | Should -Be '4e095196197570776515423929ddb72e8299c1db'
        $copilot.source.mergeCommit | Should -Be '473b8aa174eb47a323b026c098b73bf7d716772c'
        $copilot.source.reviewedHead | Should -Be '4e095196197570776515423929ddb72e8299c1db'
        $copilot.package.artifact.releaseCommit |
            Should -Be '473b8aa174eb47a323b026c098b73bf7d716772c'
        $officialProfileLinks = @(
            'dsh-tauri',
            'dsh-tauri-panel',
            'dsh-tauri-panel-extension',
            'dsh-tauri-panel-scheduler',
            'dsh-tauri-rightclick',
            'dsh-tauri-session',
            'dsh-tauri-ui',
            'dsh-tauri-worktree'
        )
        @($lock.components.desktop.internalPlugins.name | Sort-Object) |
            Should -Be @($officialProfileLinks | Sort-Object)
        @($lock.profile.plugins | Where-Object { $_.source -eq 'desktop-internal' }).Count |
            Should -Be 8
        @($lock.profile.plugins.name | Sort-Object) |
            Should -Be @(($officialProfileLinks + 'dsh-github-copilot') | Sort-Object)
        @($lock.profile.requiredBundles | Sort-Object) |
            Should -Be @(
                (@('@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app') +
                    $officialProfileLinks + 'dsh-github-copilot') | Sort-Object
            )
        $lock.components.desktop.shippedDependencies[0].name |
            Should -Be 'dsh-tauri-panel-placeholder'
        $lock.components.desktop.shippedDependencies[0].profileBundle | Should -Be $false
        @($lock.profile.optionalOverlays.name | Sort-Object) |
            Should -Be @('dsh-cron', 'dsh-playwright-host')
        @($lock.profile.optionalOverlays | Where-Object { $_.required }).Count | Should -Be 0
        $lock.migration.legacyGateway.active | Should -Be $false
    }

It 'rejects tampered runtime and Copilot plugin identity metadata' {
        $tampered = $lock | ConvertTo-Json -Depth 40 | ConvertFrom-Json
        $tampered.components.desktop.runtimeSelectors[0].id = 'controlled-fork'
        { Test-WindowsCopilotLock -Lock $tampered } | Should -Throw '*official runtime selector*'

        $tampered = $lock | ConvertTo-Json -Depth 40 | ConvertFrom-Json
        $tampered.components.desktop.runtimeSelectors[0].package.entrypointSize = 8020
        { Test-WindowsCopilotLock -Lock $tampered } |
            Should -Throw '*official Desktop-managed runtime*'

        $tampered = $lock | ConvertTo-Json -Depth 40 | ConvertFrom-Json
        $tampered.acceptance.runtimeSchema.source.releaseTag = 'dsh-v0.1.2'
        { Test-WindowsCopilotLock -Lock $tampered } |
            Should -Throw '*official Desktop-managed runtime*'

        $tampered = $lock | ConvertTo-Json -Depth 40 | ConvertFrom-Json
        $tampered.acceptance.runtimeSchema.requiredBuiltFiles[1].sha256 = ('0' * 64) -join ''
        { Test-WindowsCopilotLock -Lock $tampered } |
            Should -Throw '*official Desktop-managed runtime*'

        $tampered = $lock | ConvertTo-Json -Depth 40 | ConvertFrom-Json
        $tampered.acceptance.runtimeSchema.behavior.escalationPropertiesRequired = $true
        { Test-WindowsCopilotLock -Lock $tampered } |
            Should -Throw '*official Desktop-managed runtime*'

        $tampered = $lock | ConvertTo-Json -Depth 40 | ConvertFrom-Json
        $tampered.components.copilotIntegration.source.reviewedHead = ('0' * 40) -join ''
        { Test-WindowsCopilotLock -Lock $tampered } |
            Should -Throw '*reviewed PR #56*'

        $tampered = $lock | ConvertTo-Json -Depth 40 | ConvertFrom-Json
        $tampered.components.copilotIntegration.package.artifact.releaseCommit = ('0' * 40) -join ''
        { Test-WindowsCopilotLock -Lock $tampered } |
            Should -Throw '*canonical immutable Release*'

        $tampered = $lock | ConvertTo-Json -Depth 40 | ConvertFrom-Json
        $tampered.profile.plugins = @($tampered.profile.plugins | Where-Object {
            $_.name -ne 'dsh-tauri-panel-scheduler'
        })
        { Test-WindowsCopilotLock -Lock $tampered } |
            Should -Throw '*exactly eight official Desktop links*'

        $tampered = $lock | ConvertTo-Json -Depth 40 | ConvertFrom-Json
        $tampered.profile.requiredBundles = @($tampered.profile.requiredBundles | Where-Object {
            $_ -ne 'dsh-tauri-panel-scheduler'
        })
        { Test-WindowsCopilotLock -Lock $tampered } |
            Should -Throw '*requiredBundles must contain exactly*'
    }

It 'plans no Core build install receipt or activation work' {
        $plan = Get-WindowsCopilotInstallPlan -Lock $lock -DshHome (Join-Path $TestDrive '.dsh') `
            -NpmGlobalRoot (Join-Path $TestDrive 'global\node_modules')
        $text = $plan | ConvertTo-Json -Depth 10
        $text | Should -Not -Match '(?i)build-core|install-core|receipt|DSH_CLI_PATH|controlled-fork'
        @($plan.steps.id) | Should -Contain 'verify-desktop-official-runtime'
        @($plan.steps.id) | Should -Contain 'install-global-transaction'
    }

It 'plans the reviewed companion suite in the same deployment transaction' {
        $plan = Get-WindowsCopilotInstallPlan -Lock $lock -DshHome (Join-Path $TestDrive '.dsh') `
            -NpmGlobalRoot (Join-Path $TestDrive 'global\node_modules') -IncludeCompanionSuite
        $plan.includeCompanionSuite | Should -Be $true
        @($plan.steps.id | Where-Object { $_ -eq 'install-companion-suite' }).Count |
            Should -Be 1
        $suite = @($plan.steps | Where-Object id -eq 'install-companion-suite')[0]
        @($suite.plugins) | Should -Be @(
            'dsh-github-copilot',
            'dsh-cron',
            'dsh-playwright-host'
        )
        $suite.action | Should -Be 'same-transaction-profile-artifacts'
        ($plan | ConvertTo-Json -Depth 10) | Should -Not -Match 'install-optional-companion-suite'
    }

It 'fails Verify acceptance until the required base and smoke are complete' {
        $failed = [pscustomobject]@{
            complete = $false
            readyForManualSearchSmoke = $false
            profile = [pscustomobject]@{
                companionSuite = [pscustomobject]@{ selected = $false; valid = $false }
            }
        }
        (Test-WindowsCopilotVerificationAcceptance -Installation $failed).valid |
            Should -Be $false

        $manual = $failed | ConvertTo-Json -Depth 5 | ConvertFrom-Json
        $manual.readyForManualSearchSmoke = $true
        $manualResult = Test-WindowsCopilotVerificationAcceptance -Installation $manual
        $manualResult.valid | Should -Be $false
        $manualResult.baseValid | Should -Be $false
        $manualResult.status | Should -Be 'manual-search-smoke-pending'

        $manual.profile.companionSuite.selected = $true
        (Test-WindowsCopilotVerificationAcceptance -Installation $manual `
            -IncludeCompanionSuite).valid | Should -Be $false
        $manual.profile.companionSuite.valid = $true
        (Test-WindowsCopilotVerificationAcceptance -Installation $manual `
            -IncludeCompanionSuite).valid | Should -Be $false
    }

It 'requires a local Copilot artifact closure for profile coherence' {
        $moduleText = Get-Content -LiteralPath (
            Join-Path $repoRoot 'tools\WindowsCopilotDeployment.psm1'
        ) -Raw
        $moduleText | Should -Match "artifact-local-copy-required"
        $moduleText | Should -Match "Test-WindowsCopilotInstalledArtifactClosure"
    }

It 'rejects companion suite role drift' {
        $tampered = $lock | ConvertTo-Json -Depth 40 | ConvertFrom-Json
        (@($tampered.companionSuite.members | Where-Object name -eq 'dsh-cron'))[0].
            requiredByBaseDeployment = $true
        { Test-WindowsCopilotLock -Lock $tampered } |
            Should -Throw '*companion suite contract*'
    }

It 'removes fork-only inputs and mutations from the installer and Apply implementation' {
        $scriptText = Get-Content -LiteralPath (
            Join-Path $repoRoot 'tools\install-windows-copilot.ps1'
        ) -Raw
        foreach ($name in @('HarnessSourceRoot', 'CoreInstallPrefix', 'CoreInstallTimeoutSeconds', 'DshCliPath')) {
            $scriptText | Should -Not -Match ([regex]::Escape($name))
        }
        $scriptText | Should -Not -Match 'DSH_CLI_PATH'

        $moduleText = Get-Content -LiteralPath (
            Join-Path $repoRoot 'tools\WindowsCopilotDeployment.psm1'
        ) -Raw
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseInput(
            $moduleText,
            [ref]$tokens,
            [ref]$errors
        )
        $errors.Count | Should -Be 0
        $apply = @($ast.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Invoke-WindowsCopilotApplyLocked'
        }, $true))[0].Extent.Text
        $apply | Should -Not -Match 'components\.core|DSH_CLI_PATH|CoreInstall|ForkCore|HarnessSourceRoot'
        $apply | Should -Match 'transactionSnapshots'
        $apply | Should -Match 'transaction\\global-packages'
        $apply | Should -Match 'transaction\\desktop'
        $apply | Should -Match 'transaction\\shortcuts'
        $apply | Should -Match 'registrySnapshots'
        $apply | Should -Match 'outerSnapshotsMerged'
        $apply.IndexOf('$gatewayStopped = $true') |
            Should -BeLessThan $apply.IndexOf('Stop-WindowsCopilotLegacyGateway')
        ([regex]::Matches($apply, 'Get-WindowsCopilotLiveSessions')).Count |
            Should -BeGreaterOrEqual 2
        $apply | Should -Match 'AcknowledgeLiveSessionIds'
        $apply.IndexOf('Stop-WindowsCopilotProcessTree') |
            Should -BeLessThan $apply.IndexOf('Start-Process -FilePath $DesktopArtifactPath')
        $moduleText |
            Should -Not -Match 'components\.core|DSH_CLI_PATH|CoreInstall|ForkCore|HarnessSourceRoot'
        $moduleText | Should -Match 'profile-unknown-dependency'
        $moduleText | Should -Match '\$unknownOverlayNames\.Count -eq 0'
        Get-Command -Module WindowsCopilotDeployment |
            Select-Object -ExpandProperty Name |
            Should -Not -Contain 'Enable-WindowsCopilotForkCore'
    }

It 'attests exact official metadata tree and entrypoint bytes and rejects tampering' {
        $fixture = New-OfficialRuntimeFixture -AppData $env:APPDATA -Lock $lock
        $state = Get-WindowsCopilotOfficialRuntimeState -Lock $fixture.lock
        $state.valid | Should -Be $true
        $state.packageRoot | Should -Be $fixture.packageRoot
        $state.wrapperFileCount | Should -Be $fixture.lock.components.desktop.runtimeSelectors[0].rootPackage.fileCount
        $state.wrapperTotalBytes | Should -Be $fixture.lock.components.desktop.runtimeSelectors[0].rootPackage.totalBytes

        $extraFile = Join-Path $fixture.root 'unexpected-wrapper-file.txt'
        Set-Content -LiteralPath $extraFile -Value 'tampered'
        (Get-WindowsCopilotOfficialRuntimeState -Lock $fixture.lock).valid | Should -Be $false
        Remove-Item -LiteralPath $extraFile
        (Get-WindowsCopilotOfficialRuntimeState -Lock $fixture.lock).valid | Should -Be $true

        Add-Content -LiteralPath $fixture.entrypoint -Value 'tampered'
        $tampered = Get-WindowsCopilotOfficialRuntimeState -Lock $fixture.lock
        $tampered.valid | Should -Be $false
        $tampered.status | Should -Be 'package-identity-mismatch'
    }

It 'compares the complete installed companion closure to locked tar bytes' {
        $stage = Join-Path $TestDrive 'closure-stage'
        $package = Join-Path $stage 'package'
        $installed = Join-Path $TestDrive 'closure-installed'
        New-Item -ItemType Directory -Path (Join-Path $package 'lib'), (Join-Path $installed 'lib') `
            -Force | Out-Null
        '{"name":"fixture","version":"1.0.0"}' |
            Set-Content -LiteralPath (Join-Path $package 'package.json') -Encoding UTF8
        'payload' | Set-Content -LiteralPath (Join-Path $package 'lib\index.js') -Encoding UTF8
        Copy-Item -Path (Join-Path $package '*') -Destination $installed -Recurse -Force
        $artifact = Join-Path $TestDrive 'fixture-1.0.0.tgz'
        & (Join-Path $env:SystemRoot 'System32\tar.exe') -czf $artifact -C $stage package
        $sha = Get-TestSha256 -Path $artifact

        (Test-WindowsCopilotInstalledArtifactClosure -ArtifactPath $artifact `
            -InstalledRoot $installed -Sha256 $sha `
            -ExpectedName 'fixture-1.0.0.tgz' -ExpectedSize (Get-Item $artifact).Length).
            valid | Should -Be $true

        Add-Content -LiteralPath (Join-Path $installed 'lib\index.js') -Value 'tamper'
        (Test-WindowsCopilotInstalledArtifactClosure -ArtifactPath $artifact `
            -InstalledRoot $installed -Sha256 $sha).valid | Should -Be $false
    }

It 'rejects reparse directories anywhere in the official wrapper tree' {
        $fixture = New-OfficialRuntimeFixture -AppData $env:APPDATA -Lock $lock
        $target = Join-Path $TestDrive 'outside-wrapper'
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $target 'payload.txt') -Value 'outside'
        $junction = Join-Path $fixture.root 'unexpected-junction'
        New-Item -ItemType Junction -Path $junction -Target $target | Out-Null

        $state = Get-WindowsCopilotOfficialRuntimeState -Lock $fixture.lock
        $state.valid | Should -Be $false
        $state.status | Should -Be 'reparse-point-path'
    }

It 'rejects modified same-version Desktop executables by exact bytes metadata and signature' {
        $desktopPath = Join-Path $TestDrive 'desktop-attestation\deepseek-harness-desktop.exe'
        New-Item -ItemType Directory -Path (Split-Path -Parent $desktopPath) -Force | Out-Null
        Set-Content -LiteralPath $desktopPath -Value 'fixture'
        InModuleScope WindowsCopilotDeployment -Parameters @{
            FixtureLock = $lock
            Executable = $desktopPath
        } {
            Mock Get-Item {
                [pscustomobject]@{
                    FullName = $Executable
                    Length = [int64]$FixtureLock.components.desktop.installedExecutable.size
                    Attributes = [IO.FileAttributes]::Normal
                    VersionInfo = [pscustomobject]@{
                        ProductName = 'Deepseek Harness Desktop'
                        FileDescription = 'Deepseek Harness Desktop'
                        CompanyName = 'github'
                        ProductVersion = '0.10.3'
                    }
                }
            } -ParameterFilter { $LiteralPath -eq $Executable }
            Mock Get-FileHash {
                [pscustomobject]@{ Hash = [string]$FixtureLock.components.desktop.installedExecutable.sha256 }
            } -ParameterFilter { $LiteralPath -eq $Executable }
            Mock Get-AuthenticodeSignature {
                [pscustomobject]@{ Status = 'NotSigned' }
            } -ParameterFilter { $FilePath -eq $Executable }
            Mock Get-WindowsCopilotDirectoryTreeState {
                [pscustomobject]@{
                    fileCount = [int]$FixtureLock.components.desktop.installedResources.fileCount
                    totalBytes = [int64]$FixtureLock.components.desktop.installedResources.totalBytes
                    treeSha256 = [string]$FixtureLock.components.desktop.installedResources.treeSha256
                    reparseDirectoryCount = 0
                }
            }

            (Get-WindowsCopilotDesktopState -Lock $FixtureLock -Path $Executable).valid |
                Should -Be $true

            $tamperedLock = $FixtureLock | ConvertTo-Json -Depth 40 | ConvertFrom-Json
            $tamperedLock.components.desktop.installedExecutable.sha256 = ('0' * 64)
            $modified = Get-WindowsCopilotDesktopState -Lock $tamperedLock -Path $Executable
            $modified.valid | Should -Be $false
            $modified.status | Should -Be 'identity-mismatch'

            Mock Get-WindowsCopilotDirectoryTreeState {
                [pscustomobject]@{
                    fileCount = [int]$FixtureLock.components.desktop.installedResources.fileCount
                    totalBytes = [int64]$FixtureLock.components.desktop.installedResources.totalBytes
                    treeSha256 = ('f' * 64)
                    reparseDirectoryCount = 0
                }
            }
            $resourceDrift = Get-WindowsCopilotDesktopState -Lock $FixtureLock -Path $Executable
            $resourceDrift.valid | Should -Be $false
            $resourceDrift.status | Should -Be 'identity-mismatch'
        }
    }

It 'accepts only an official Desktop descendant owning exact IPv4 127.0.0.1:3080' {
        $fixture = New-OfficialRuntimeFixture -AppData $env:APPDATA -Lock $lock
        $desktopPath = Join-Path $TestDrive 'desktop\deepseek-harness-desktop.exe'
        New-Item -ItemType Directory -Path (Split-Path -Parent $desktopPath) -Force | Out-Null
        Set-Content -LiteralPath $desktopPath -Value 'fixture'
        $processes = @(
            [pscustomobject]@{
                ProcessId = 10; ParentProcessId = 0; Name = 'deepseek-harness-desktop.exe'
                ExecutablePath = $desktopPath; CommandLine = "`"$desktopPath`""
            },
            [pscustomobject]@{
                ProcessId = 11; ParentProcessId = 10; Name = 'node.exe'
                ExecutablePath = 'C:\Program Files\nodejs\node.exe'
                CommandLine = "node `"$($fixture.entrypoint)`" --profile web"
            }
        )
        $accepted = Get-WindowsCopilotDesktopRuntimeState -Lock $fixture.lock `
            -DesktopExecutablePath $desktopPath -Processes $processes `
            -ListenerStates @([pscustomobject]@{
                host = '127.0.0.1'; port = 3080; bindingVerified = $true
                loopbackOnly = $true; owningProcessIds = @(11)
            })
        $accepted.valid | Should -Be $true
        $accepted.selector | Should -Be 'desktop-official'
        $accepted.status | Should -Be 'desktop-official-active-owns-3080'

        $wrongAddress = Get-WindowsCopilotDesktopRuntimeState -Lock $fixture.lock `
            -DesktopExecutablePath $desktopPath -Processes $processes `
            -ListenerStates @([pscustomobject]@{
                host = '::1'; port = 3080; bindingVerified = $true
                loopbackOnly = $true; owningProcessIds = @(11)
            })
        $wrongAddress.valid | Should -Be $false
        $wrongAddress.status | Should -Be 'desktop-official-listener-owner-mismatch'

        $wrongOwner = Get-WindowsCopilotDesktopRuntimeState -Lock $fixture.lock `
            -DesktopExecutablePath $desktopPath -Processes $processes `
            -ListenerStates @([pscustomobject]@{
                host = '127.0.0.1'; port = 3080; bindingVerified = $true
                loopbackOnly = $true; owningProcessIds = @(99)
            })
        $wrongOwner.valid | Should -Be $false
    }

It 'runs runtime schema and sandbox validation against the official package root' {
        $fixture = New-OfficialRuntimeFixture -AppData $env:APPDATA -Lock $lock
        InModuleScope WindowsCopilotDeployment -Parameters @{
            FixtureLock = $fixture.lock
            PackageRoot = $fixture.packageRoot
        } {
            $ExpectedPackageRoot = $PackageRoot
            Mock Test-DshSandboxRegression {
                [pscustomobject]@{
                    status = 'passed'
                    capability = 'sandbox-same-and-narrower-no-op'
                    sameAndNarrowerApprovalCalls = 0
                    widerApprovalCalls = 1
                }
            }

            $result = Test-WindowsCopilotOfficialRuntime -Lock $FixtureLock -SkipActiveCheck
            @($result.schema.reasons) | Should -BeNullOrEmpty
            $result.valid | Should -Be $true
            $result.schema.packageRoot | Should -Be $PackageRoot
            $result.sandbox.packageRoot | Should -Be $PackageRoot
            Should -Invoke Test-DshSandboxRegression -Times 1 -Exactly -ParameterFilter {
                $PackageRoot -eq $ExpectedPackageRoot
            }
        }
    }

It 'discovers only the reviewed legacy gateway on exact IPv4 loopback' {
            $gatewayPath = Join-Path $TestDrive 'gateway\copilot2api-windows-amd64.exe'
            New-Item -ItemType Directory -Path (Split-Path -Parent $gatewayPath) -Force | Out-Null
            Set-Content -LiteralPath $gatewayPath -Value 'reviewed-gateway'
            $fixtureLock = $lock | ConvertTo-Json -Depth 40 | ConvertFrom-Json
            $fixtureLock.migration.legacyGateway.artifact.sha256 = Get-TestSha256 -Path $gatewayPath
            $listeners = @([pscustomobject]@{
                LocalAddress = '127.0.0.1'; LocalPort = 7777; OwningProcess = 41
            })
            $processes = @([pscustomobject]@{
                ProcessId = 41; Name = 'copilot2api-windows-amd64.exe'
                ExecutablePath = $gatewayPath; CommandLine = "`"$gatewayPath`""
            })
            $state = InModuleScope WindowsCopilotDeployment -Parameters @{
                FixtureLock = $fixtureLock; Listeners = $listeners; Processes = $processes
            } {
                Get-WindowsCopilotLegacyGatewayState -Lock $FixtureLock `
                    -ListenerStates $Listeners -Processes $Processes -ScheduledTasks @()
            }
            $state.matchesReviewedLegacy | Should -Be $true
            $state.path | Should -Be $gatewayPath
            $state.source | Should -Be 'active-loopback-listener'

            Set-Content -LiteralPath $gatewayPath -Value 'unknown-bytes'
            $unknown = InModuleScope WindowsCopilotDeployment -Parameters @{
                FixtureLock = $fixtureLock; Listeners = $listeners; Processes = $processes
            } {
                Get-WindowsCopilotLegacyGatewayState -Lock $FixtureLock `
                    -ListenerStates $Listeners -Processes $Processes -ScheduledTasks @()
            }
            $unknown.detected | Should -Be $true
            $unknown.matchesReviewedLegacy | Should -Be $false

            $secondPath = Join-Path $TestDrive 'gateway2\copilot2api.exe'
            New-Item -ItemType Directory -Path (Split-Path -Parent $secondPath) -Force | Out-Null
            Copy-Item -LiteralPath $gatewayPath -Destination $secondPath
            $ambiguous = InModuleScope WindowsCopilotDeployment -Parameters @{
                FixtureLock = $fixtureLock
                Listeners = @(
                    [pscustomobject]@{ LocalAddress = '127.0.0.1'; LocalPort = 7777; OwningProcess = 41 },
                    [pscustomobject]@{ LocalAddress = '127.0.0.1'; LocalPort = 7777; OwningProcess = 42 }
                )
                Processes = @(
                    [pscustomobject]@{ ProcessId = 41; Name = 'copilot2api-windows-amd64.exe'; ExecutablePath = $gatewayPath },
                    [pscustomobject]@{ ProcessId = 42; Name = 'copilot2api.exe'; ExecutablePath = $secondPath }
                )
            } {
                Get-WindowsCopilotLegacyGatewayState -Lock $FixtureLock `
                    -ListenerStates $Listeners -Processes $Processes -ScheduledTasks @()
            }
            $ambiguous.listenerStatus | Should -Be 'ambiguous'
            $ambiguous.matchesReviewedLegacy | Should -Be $false
        }

It 'restores reviewed legacy gateway task state without starting an extra process' {
            $gatewayPath = Join-Path $TestDrive 'gateway-rollback\copilot2api.exe'
            New-Item -ItemType Directory -Path (Split-Path -Parent $gatewayPath) -Force | Out-Null
            Set-Content -LiteralPath $gatewayPath -Value 'reviewed-gateway'
            $fixtureLock = $lock | ConvertTo-Json -Depth 40 | ConvertFrom-Json
            $fixtureLock.migration.legacyGateway.artifact.sha256 = Get-TestSha256 -Path $gatewayPath
            $state = [pscustomobject]@{
                path = $gatewayPath
                processes = @([pscustomobject]@{ processId = 41 })
                scheduledTasks = @([pscustomobject]@{
                    taskName = 'Reviewed gateway'; taskPath = '\'
                    state = 'Running'; enabled = $true
                })
            }

            InModuleScope WindowsCopilotDeployment -Parameters @{
                FixtureLock = $fixtureLock; GatewayPath = $gatewayPath; GatewayState = $state
            } {
                Mock Get-ScheduledTask {
                    [pscustomobject]@{
                        TaskName = 'Reviewed gateway'; TaskPath = '\'; State = 'Disabled'
                        Settings = [pscustomobject]@{ Enabled = $false }
                        Actions = @([pscustomobject]@{ Execute = $GatewayPath })
                    }
                }
                Mock Enable-ScheduledTask {}
                Mock Start-ScheduledTask {}
                Mock Start-Process {}

                Restore-WindowsCopilotLegacyGateway -Lock $FixtureLock -State $GatewayState

                Should -Invoke Enable-ScheduledTask -Times 1 -Exactly
                Should -Invoke Start-ScheduledTask -Times 1 -Exactly
                Should -Invoke Start-Process -Times 0 -Exactly
            }
        }

It 'discovers and validates a reviewed task-only gateway outside the default path' {
        $gatewayPath = Join-Path $TestDrive 'task-only\copilot2api-windows-amd64.exe'
        New-Item -ItemType Directory -Path (Split-Path -Parent $gatewayPath) -Force |
            Out-Null
        Set-Content -LiteralPath $gatewayPath -Value 'reviewed-task-gateway'
        $fixtureLock = $lock | ConvertTo-Json -Depth 40 | ConvertFrom-Json
        $fixtureLock.migration.legacyGateway.artifact.sha256 =
            Get-TestSha256 -Path $gatewayPath
        $task = [pscustomobject]@{
            TaskName = 'Reviewed task-only gateway'
            TaskPath = '\'
            State = 'Ready'
            Settings = [pscustomobject]@{ Enabled = $true }
            Actions = @([pscustomobject]@{ Execute = $gatewayPath })
        }
        $state = InModuleScope WindowsCopilotDeployment -Parameters @{
            FixtureLock = $fixtureLock
            ScheduledTask = $task
        } {
            Get-WindowsCopilotLegacyGatewayState -Lock $FixtureLock `
                -ListenerStates @() -Processes @() -ScheduledTasks @($ScheduledTask)
        }
        $state.matchesReviewedLegacy | Should -Be $true
        $state.source | Should -Be 'scheduled-task'
        $state.path | Should -Be $gatewayPath
        @($state.scheduledTasks).Count | Should -Be 1

        $multiActionTask = $task.PSObject.Copy()
        $multiActionTask.Actions = @(
            [pscustomobject]@{ Execute = $gatewayPath },
            [pscustomobject]@{ Execute = "$env:SystemRoot\System32\notepad.exe" }
        )
        $multiAction = InModuleScope WindowsCopilotDeployment -Parameters @{
            FixtureLock = $fixtureLock
            ScheduledTask = $multiActionTask
        } {
            Get-WindowsCopilotLegacyGatewayState -Lock $FixtureLock `
                -ListenerStates @() -Processes @() -ScheduledTasks @($ScheduledTask)
        }
        $multiAction.matchesReviewedLegacy | Should -Be $false
        @($multiAction.scheduledTasks).Count | Should -Be 0

        $otherGatewayPath = Join-Path $TestDrive (
            'other-task\copilot2api-windows-amd64.exe'
        )
        New-Item -ItemType Directory -Path (Split-Path -Parent $otherGatewayPath) `
            -Force | Out-Null
        Copy-Item -LiteralPath $gatewayPath -Destination $otherGatewayPath
        $otherTask = [pscustomobject]@{
            TaskName = 'Other reviewed-name gateway'
            TaskPath = '\'
            State = 'Ready'
            Settings = [pscustomobject]@{ Enabled = $true }
            Actions = @([pscustomobject]@{ Execute = $otherGatewayPath })
        }
        $ambiguousTasks = InModuleScope WindowsCopilotDeployment -Parameters @{
            FixtureLock = $fixtureLock
            GatewayPath = $gatewayPath
            Tasks = @($task, $otherTask)
        } {
            Get-WindowsCopilotLegacyGatewayState -Lock $FixtureLock `
                -Path $GatewayPath -ListenerStates @() -Processes @() `
                -ScheduledTasks $Tasks
        }
        $ambiguousTasks.matchesReviewedLegacy | Should -Be $false

        Set-Content -LiteralPath $gatewayPath -Value 'unknown'
        $unknown = InModuleScope WindowsCopilotDeployment -Parameters @{
            FixtureLock = $fixtureLock
            ScheduledTask = $task
        } {
            Get-WindowsCopilotLegacyGatewayState -Lock $FixtureLock `
                -ListenerStates @() -Processes @() -ScheduledTasks @($ScheduledTask)
        }
        $unknown.matchesReviewedLegacy | Should -Be $false
    }

It 'restores reviewed profile plugin and gateway snapshots and refuses later drift' {
        $backupRoot = Join-Path $TestDrive 'backups'
        $operationId = '20260904T120000000Z'
        $operationRoot = Join-Path $backupRoot $operationId
        $profilePath = Join-Path $TestDrive 'profile\package.json'
        $gatewayPath = Join-Path $TestDrive 'bin\copilot2api.exe'
        New-Item -ItemType Directory -Path (Split-Path -Parent $profilePath),
            (Split-Path -Parent $gatewayPath), (Join-Path $operationRoot 'profile'),
            (Join-Path $operationRoot 'migration') -Force | Out-Null
        Set-Content -LiteralPath $profilePath -Value 'original-profile'
        Set-Content -LiteralPath $gatewayPath -Value 'original-gateway'
        Copy-Item $profilePath (Join-Path $operationRoot 'profile\package.json')
        Copy-Item $gatewayPath (Join-Path $operationRoot 'migration\copilot2api.exe')
        $profileOriginal = New-TestFingerprint -Path $profilePath
        $gatewayOriginal = New-TestFingerprint -Path $gatewayPath
        Set-Content -LiteralPath $profilePath -Value 'applied-profile'
        Remove-Item -LiteralPath $gatewayPath
        $snapshots = @(
            [ordered]@{
                path = $profilePath; relativePath = 'profile\package.json'
                pluginTarget = $false; existed = $true
                originalFingerprint = $profileOriginal
                appliedFingerprint = New-TestFingerprint -Path $profilePath
            },
            [ordered]@{
                path = $gatewayPath; relativePath = 'migration\copilot2api.exe'
                pluginTarget = $false; existed = $true
                originalFingerprint = $gatewayOriginal
                appliedFingerprint = New-TestFingerprint -Path $gatewayPath
            }
        )
        [ordered]@{
            schemaVersion = 1
            deploymentId = [string]$lock.deploymentId
            operationId = $operationId
            status = 'active'
            nodeModulesRoot = Join-Path $TestDrive 'profile\node_modules'
            snapshots = $snapshots
        } | ConvertTo-Json -Depth 12 |
            Set-Content -LiteralPath (Join-Path $operationRoot 'receipt.json') -Encoding UTF8

        $result = Restore-WindowsCopilotDeployment -Lock $lock -BackupRoot $backupRoot `
            -OperationId $operationId
        $result.status | Should -Be 'rolled-back'
        (Get-Content -LiteralPath $profilePath -Raw).Trim() | Should -Be 'original-profile'
        (Get-Content -LiteralPath $gatewayPath -Raw).Trim() | Should -Be 'original-gateway'

        $operationId2 = '20260904T120000001Z'
        $operationRoot2 = Join-Path $backupRoot $operationId2
        New-Item -ItemType Directory -Path (Join-Path $operationRoot2 'profile') -Force | Out-Null
        Copy-Item $profilePath (Join-Path $operationRoot2 'profile\package.json')
        $original = New-TestFingerprint -Path $profilePath
        Set-Content -LiteralPath $profilePath -Value 'applied'
        $applied = New-TestFingerprint -Path $profilePath
        [ordered]@{
            schemaVersion = 1
            deploymentId = [string]$lock.deploymentId
            operationId = $operationId2
            status = 'active'
            nodeModulesRoot = Join-Path $TestDrive 'profile\node_modules'
            snapshots = @([ordered]@{
                path = $profilePath; relativePath = 'profile\package.json'
                pluginTarget = $false; existed = $true
                originalFingerprint = $original; appliedFingerprint = $applied
            })
        } | ConvertTo-Json -Depth 12 |
            Set-Content -LiteralPath (Join-Path $operationRoot2 'receipt.json') -Encoding UTF8
        Set-Content -LiteralPath $profilePath -Value 'later-user-change'
        {
            Restore-WindowsCopilotDeployment -Lock $lock -BackupRoot $backupRoot `
                -OperationId $operationId2
        } | Should -Throw '*changed after Apply*'
    }

It 'rejects a modified rollback backup before changing any target' {
        $backupRoot = Join-Path $TestDrive 'tampered-backup'
        $operationId = '20260904T120000002Z'
        $operationRoot = Join-Path $backupRoot $operationId
        $target = Join-Path $TestDrive 'rollback-target\package.json'
        $backup = Join-Path $operationRoot 'profile\package.json'
        New-Item -ItemType Directory -Path (Split-Path -Parent $target),
            (Split-Path -Parent $backup) -Force | Out-Null
        Set-Content -LiteralPath $target -Value 'original'
        Copy-Item -LiteralPath $target -Destination $backup
        $original = New-TestFingerprint -Path $target
        Set-Content -LiteralPath $target -Value 'applied'
        $applied = New-TestFingerprint -Path $target
        [ordered]@{
            schemaVersion = 1
            deploymentId = [string]$lock.deploymentId
            operationId = $operationId
            status = 'active'
            nodeModulesRoot = Join-Path $TestDrive 'profile\node_modules'
            snapshots = @([ordered]@{
                path = $target
                relativePath = 'profile\package.json'
                pluginTarget = $false
                existed = $true
                originalFingerprint = $original
                appliedFingerprint = $applied
            })
        } | ConvertTo-Json -Depth 12 |
            Set-Content -LiteralPath (Join-Path $operationRoot 'receipt.json') -Encoding UTF8
        Set-Content -LiteralPath $backup -Value 'corrupted-backup'

        {
            Restore-WindowsCopilotDeployment -Lock $lock -BackupRoot $backupRoot `
                -OperationId $operationId
        } | Should -Throw '*backup fingerprint mismatch*'
        (Get-Content -LiteralPath $target -Raw).Trim() | Should -Be 'applied'
    }

It 'guards public rollback with the same deployment mutex as Apply' {
        $moduleText = Get-Content -LiteralPath (
            Join-Path $repoRoot 'tools\WindowsCopilotDeployment.psm1'
        ) -Raw
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseInput(
            $moduleText, [ref]$tokens, [ref]$errors
        )
        $rollback = @($ast.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Restore-WindowsCopilotDeployment'
        }, $true))[0].Extent.Text
        $rollback | Should -Match 'Enter-WindowsCopilotDeploymentLock'
        $rollback | Should -Match 'Exit-WindowsCopilotDeploymentLock'
        $rollback | Should -Match 'Restore-WindowsCopilotDeploymentLocked'
        $moduleText | Should -Match "Global\\DshWindowsOpsDeployment"
        $moduleText | Should -Not -Match "Local\\DshWindowsOpsDeployment"
        $lockedRollback = @($ast.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Restore-WindowsCopilotDeploymentLocked'
        }, $true))[0].Extent.Text
        $lockedRollback | Should -Match 'transaction\\desktop'
        $lockedRollback | Should -Match 'Get-WindowsCopilotLiveSessions'
        $lockedRollback | Should -Match 'AcknowledgeLiveSessionIds'
        $lockedRollback | Should -Match 'Restore-WindowsCopilotRegistrySnapshots'
        $restart = @($ast.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Restart-WindowsCopilotDesktop'
        }, $true))[0].Extent.Text
        $restart.LastIndexOf('Stop-WindowsCopilotProcessTree') |
            Should -BeGreaterThan $restart.LastIndexOf('while ((Get-Date) -lt $deadline)')
    }

It 'stops verified Desktop descendants leaf-first' {
        InModuleScope WindowsCopilotDeployment {
            $script:stopped = [Collections.Generic.List[int]]::new()
            Mock Stop-Process {
                foreach ($processId in @($Id)) {
                    $script:stopped.Add([int]$processId)
                }
            }
            Mock Get-Process { $null }
            $processes = @(
                [pscustomobject]@{ ProcessId = 10; ParentProcessId = 0 },
                [pscustomobject]@{ ProcessId = 11; ParentProcessId = 10 },
                [pscustomobject]@{ ProcessId = 12; ParentProcessId = 11 },
                [pscustomobject]@{ ProcessId = 99; ParentProcessId = 0 }
            )
            Mock Get-CimInstance {
                $match = [regex]::Match([string]$Filter, 'ProcessId=(\d+)')
                if ($match.Success) {
                    $processId = [int]$match.Groups[1].Value
                    return @($processes | Where-Object ProcessId -eq $processId)[0]
                }
                return $processes
            }
            Stop-WindowsCopilotProcessTree -RootProcessIds @(10) -Processes $processes |
                Out-Null
            @($script:stopped) | Should -Be @(12, 11, 10)
            @($script:stopped) | Should -Not -Contain 99
            @(Stop-WindowsCopilotProcessTree -RootProcessIds @() -Processes @()).
                Count | Should -Be 0
        }
    }

It 'keeps default Check non-mutating and free of fork inputs' {
        $dshHome = Join-Path $TestDrive 'check-only\.dsh'
        $manifest = Join-Path $TestDrive 'official-lock.json'
        $lock | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $manifest -Encoding UTF8
        $scriptPath = Join-Path $repoRoot 'tools\install-windows-copilot.ps1'
        $output = & pwsh -NoProfile -File $scriptPath -ManifestPath $manifest `
            -DshHome $dshHome -NpmGlobalRoot (Join-Path $TestDrive 'global\node_modules') `
            -SkipRuntimeChecks
        $LASTEXITCODE | Should -Be 0
        $result = ($output -join "`n") | ConvertFrom-Json
        $result.mode | Should -Be 'check'
        $result.checks.manifest.valid | Should -Be $true
        Test-Path -LiteralPath $dshHome | Should -Be $false
        $env:DSH_CLI_PATH | Should -Be $script:previousDshCliPath
    }
}
