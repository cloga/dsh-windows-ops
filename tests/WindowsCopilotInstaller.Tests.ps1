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
    }

    BeforeEach {
        $script:previousLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = Join-Path $TestDrive 'localappdata'
    }

    AfterEach {
        $env:LOCALAPPDATA = $script:previousLocalAppData
    }

    It 'pins every verified source and artifact identity' {
        $lock.deploymentId | Should -Be 'windows-copilot-2026-09-02'
        $lock.verifiedDate | Should -Be '2026-09-02'
        $lock.components.desktop.version | Should -Be '0.10.2'
        $lock.components.desktop.source.commit | Should -Be '2bb8f6b8e75c7e6e61b9bf5da7abbe53f9e93c63'
        $lock.components.desktop.artifact.name | Should -Be 'Deepseek.Harness.Desktop_0.10.2_x64-setup.exe'
        $lock.components.desktop.artifact.url |
            Should -Be 'https://github.com/dsh-tauri-desk/deepseek-harness-desktop/releases/download/v0.10.2/Deepseek.Harness.Desktop_0.10.2_x64-setup.exe'
        $lock.components.desktop.artifact.sha256 | Should -Be '54d4c4a5718e5b1bb1276c256dbea8dccac6c36835f195f98b711b850e6488fa'
        @($lock.components.desktop.internalPlugins).Count | Should -Be 5
        @($lock.components.desktop.internalPlugins | Where-Object version -ne '0.6.7').Count | Should -Be 0
        @($lock.components.desktop.internalPlugins | Where-Object {
            $_.relativePath -cne "resources\node_modules\$($_.name)"
        }).Count | Should -Be 0
        @($lock.profile.legacyPhysicalPlugins).Count | Should -Be 3
        (@($lock.profile.legacyPhysicalPlugins | Where-Object name -eq 'dsh-tauri'))[0].version |
            Should -Be '0.2.0'
        $lock.components.core.source.commit | Should -Be 'a772dbbde82780bff2b9394427e9f0a24cafa1d5'
        $lock.components.core.source.maintenanceBranch | Should -Be 'cloga-pi-ai-model-api'
        $lock.components.core.package.version | Should -Be '0.1.1-rc.2'
        @($lock.components.core.capabilities) | Should -Be @(
            'sandbox-same-and-narrower-no-op',
            'pi-ai-oauth-json-record-normalization',
            'pi-ai-per-model-api-routes'
        )
        $lock.components.core.install.script | Should -Be 'release:install-local'
        @($lock.components.core.install.attestedFiles).Count | Should -Be 3
        $lock.components.core.activation.environmentVariable | Should -Be 'DSH_CLI_PATH'
        @($lock.components.core.activation.conflictShims).Count | Should -Be 3
        foreach ($shim in @($lock.components.core.activation.conflictShims)) {
            $lock.components.core.activation.conflictShimSha256.$shim | Should -Match '^[0-9a-f]{64}$'
        }
        $lock.components.PSObject.Properties.Name | Should -Not -Contain 'gateway'
        $lock.migration.legacyGateway.active | Should -Be $false
        $lock.migration.legacyGateway.successCriteria | Should -Be $false
        $lock.components.copilotIntegration.source.pullRequest | Should -Be 33
        $lock.components.copilotIntegration.source.commit | Should -Be '94d921dc7bad4d5035c27ed9543d638694cb7391'
        $lock.components.copilotIntegration.source.mergeCommit | Should -Be 'eae8b56715e197d5e206a7852bfaa418bbc70dc5'
        $lock.components.copilotIntegration.package.version | Should -Be '0.3.0-cloga.8'
        $lock.components.copilotIntegration.package.packageManager | Should -Be 'pnpm@11.7.0'
        $lock.components.copilotIntegration.package.artifact.url |
            Should -Be 'https://github.com/cloga/dsh-github-copilot/releases/download/v0.3.0-cloga.8/dsh-github-copilot-0.3.0-cloga.8.tgz'
        $lock.components.copilotIntegration.package.artifact.sha256 |
            Should -Be 'b37e7621628e10d2a33f4cb7e4692c4fcd1348c7d7e8eb92467f250bbaa4ae32'
        $lock.components.copilotIntegration.package.bundlePatch | Should -Be './cordis.patch.yml'
        @($lock.components.copilotIntegration.package.attestedFiles) |
            Should -Be @('lib/index.js', 'lib/client.js', 'lib/remote.js')
        $lock.components.copilotIntegration.package.deploymentBaseline.kind | Should -Be 'standalone-dsh-plugin'
        @($lock.components.copilotIntegration.package.deploymentBaseline.requiredCapabilities).Count | Should -Be 13
        @($lock.components.copilotIntegration.package.deploymentBaseline.requiredCapabilities) |
            Should -Contain 'client-module-loader-handoff'
        @($lock.components.copilotIntegration.package.deploymentBaseline.requiredCapabilities) |
            Should -Contain 'strict-remote-result-codecs'
        @($lock.components.copilotIntegration.package.deploymentBaseline.requiredCapabilities) |
            Should -Contain 'strict-json-oauth-grant-normalization'
        @($lock.components.copilotIntegration.package.deploymentBaseline.requiredCapabilities) |
            Should -Contain 'per-model-api-route-materialization'
        @($lock.components.copilotIntegration.package.deploymentBaseline.requiredCapabilities) |
            Should -Contain 'existing-grant-route-self-healing'
        $lock.components.copilotIntegration.package.deploymentBaseline.runtimeDependencies.'@deepseek-ai/dsh-authorization' |
            Should -Be '^0.1.1-rc.2 || ^0.1.2-alpha.4'
        $lock.components.copilotIntegration.package.deploymentBaseline.runtimeDependencies.zod |
            Should -Be '^4.4.3'
        @($lock.profile.legacyCopilotIntegrations.version) | Should -Contain '0.2.2'
        @($lock.profile.legacyCopilotIntegrations.version) | Should -Contain '0.2.3-cloga.3'
        @($lock.profile.legacyCopilotIntegrations.version) | Should -Contain '0.3.0-cloga.1'
        @($lock.profile.legacyCopilotIntegrations.version) | Should -Contain '0.3.0-cloga.2'
        @($lock.profile.legacyCopilotIntegrations.version) | Should -Contain '0.3.0-cloga.3'
        @($lock.profile.legacyCopilotIntegrations.version) | Should -Contain '0.3.0-cloga.4'
        @($lock.profile.legacyCopilotIntegrations.version) | Should -Contain '0.3.0-cloga.5'
        @($lock.profile.legacyCopilotIntegrations.version) | Should -Contain '0.3.0-cloga.6'
        @($lock.profile.legacyCopilotIntegrations.version) | Should -Contain '0.3.0-cloga.7'
        @($lock.acceptance.composedConfig.forbiddenActiveEntries) | Should -Be @('web-search-provider')
        $lock.acceptance.composedConfig.managedEntry.provider | Should -Be 'github-copilot'
        $lock.acceptance.composedConfig.managedEntry.searchProvider | Should -Be 'github-copilot-hosted'
        @($lock.acceptance.listeners.port) | Should -Be @(3080)
        $lock.acceptance.credential.record | Should -Be 'llm-pi-ai/github-copilot'
        $lock.acceptance.providerRoute.repairTrigger | Should -Be 'existing-valid-grant'
        @($lock.acceptance.providerRoute.repairStates) | Should -Be @(
            'route-missing',
            'route-has-no-models',
            'route-model-api-missing',
            'route-mixed-protocol-apis-missing'
        )
        @($lock.acceptance.providerRoute.requiredModelFields) | Should -Be @('id', 'api')
        @($lock.acceptance.providerRoute.requiredApis) | Should -Be @(
            'openai-responses',
            'openai-completions'
        )
        $lock.acceptance.sandbox.gate | Should -Be 'Require'
        $lock.acceptance.sandbox.capability | Should -Be 'sandbox-same-and-narrower-no-op'
    }

    It 'rejects incomplete or extended Core capability evidence' {
        $missingCapability = $lock | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $missingCapability.components.core.capabilities = @('sandbox-same-and-narrower-no-op')
        { Test-WindowsCopilotLock -Lock $missingCapability } |
            Should -Throw '*per-model API route fixes*'

        $unexpectedCapability = $lock | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $unexpectedCapability.components.core.capabilities += 'unreviewed-core-capability'
        { Test-WindowsCopilotLock -Lock $unexpectedCapability } |
            Should -Throw '*per-model API route fixes*'
    }

    It 'checks applies verifies and rolls back fork Core activation with official global conflict backup' {
        $caseRoot = Join-Path $TestDrive 'fork-core-activation'
        $core = New-ForkCoreFixture -Prefix (Join-Path $caseRoot 'fork-prefix')
        $globalRoot = Join-Path $caseRoot 'global\node_modules'
        $globalPrefix = Split-Path -Parent $globalRoot
        $globalPackage = Join-Path $globalRoot '@deepseek-ai\dsh'
        New-Item -ItemType Directory -Path $globalPackage -Force | Out-Null
        [ordered]@{
            name = '@deepseek-ai/dsh'
            version = '0.1.1-rc.2'
            bin = [ordered]@{ dsh = 'lib/bin.js' }
        } | ConvertTo-Json -Compress |
            Set-Content -LiteralPath (Join-Path $globalPackage 'package.json') -Encoding UTF8
        New-Item -ItemType Directory -Path (Join-Path $globalPackage 'lib') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $globalPackage 'lib\bin.js') `
            -Value 'official global entrypoint' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $globalPrefix 'dsh.cmd') -Encoding UTF8 -Value @'
@ECHO off
GOTO start
:find_dp0
SET dp0=%~dp0
EXIT /b
:start
"%dp0%\node_modules\@deepseek-ai\dsh\lib\bin.js" %*
'@
        Set-Content -LiteralPath (Join-Path $globalPrefix 'dsh.ps1') -Encoding UTF8 -Value @'
$basedir=Split-Path $MyInvocation.MyCommand.Definition -Parent
& "$basedir/node_modules/@deepseek-ai/dsh/lib/bin.js" $args
exit $ret
'@
        Set-Content -LiteralPath (Join-Path $globalPrefix 'dsh') -Encoding UTF8 -Value @'
#!/bin/sh
basedir=$(dirname "$0")
"$basedir/node_modules/@deepseek-ai/dsh/lib/bin.js" "$@"
'@
        $activationLock = $lock | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        foreach ($shim in @($activationLock.components.core.activation.conflictShims)) {
            $activationLock.components.core.activation.conflictShimSha256.$shim =
                (Get-FileHash -LiteralPath (Join-Path $globalPrefix ([string]$shim)) -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        $backupRoot = Join-Path $caseRoot 'backups'
        $operationId = '20260901T120000000Z'
        $operationRoot = Join-Path $backupRoot $operationId
        $script:userDshCliPath = 'C:\previous\dsh.cmd'
        Mock Get-WindowsCopilotUserEnvironment -ModuleName WindowsCopilotDeployment {
            $script:userDshCliPath
        }
        Mock Set-WindowsCopilotUserEnvironment -ModuleName WindowsCopilotDeployment {
            param($Name, $Value)
            $script:userDshCliPath = $Value
        }

        $before = Get-WindowsCopilotCoreActivationState -Lock $activationLock -NpmGlobalRoot $globalRoot `
            -CoreInstallPrefix $core.prefix
        $before.valid | Should -Be $false
        $before.status | Should -Be 'user-dsh-cli-path-mismatch'
        $before.conflicts.status | Should -Be 'official-global-dsh-conflict'

        $apply = Enable-WindowsCopilotForkCore -Lock $activationLock -NpmGlobalRoot $globalRoot `
            -CoreInstallPrefix $core.prefix -BackupRoot $backupRoot -OperationRoot $operationRoot
        $apply.status | Should -Be 'enabled'
        $apply.sandbox.capability | Should -Be 'sandbox-same-and-narrower-no-op'
        $apply.sandbox.sameAndNarrowerApprovalCalls | Should -Be 0
        $script:userDshCliPath | Should -Be $core.cliPath
        foreach ($shim in @($lock.components.core.activation.conflictShims)) {
            Test-Path -LiteralPath (Join-Path $globalPrefix ([string]$shim)) | Should -Be $false
        }

        $verify = Test-WindowsCopilotForkCore -Lock $activationLock -NpmGlobalRoot $globalRoot `
            -CoreInstallPrefix $core.prefix -SkipRuntimeChecks
        $verify.valid | Should -Be $true
        $verify.activation.core.commitSha | Should -Be $lock.components.core.source.commit
        $verify.activation.core.repositoryUrl | Should -Be 'https://github.com/cloga/deepseek-harness.git'
        $verify.activation.core.installedFileCount | Should -Be 3
        $verify.sandbox.sameAndNarrowerApprovalCalls | Should -Be 0
        $desktopPath = Join-Path $env:LOCALAPPDATA 'Deepseek Harness Desktop\deepseek-harness-desktop.exe'
        New-VersionedDesktopFixture -Path $desktopPath -Version '0.10.2'
        $runtimeVerify = Test-WindowsCopilotForkCore -Lock $activationLock -NpmGlobalRoot $globalRoot `
            -CoreInstallPrefix $core.prefix -DesktopProcesses @(
                [pscustomobject]@{
                    ProcessId = 20
                    ParentProcessId = 0
                    Name = 'deepseek-harness-desktop.exe'
                    ExecutablePath = $desktopPath
                    CommandLine = "`"$desktopPath`""
                },
                [pscustomobject]@{
                    ProcessId = 21
                    ParentProcessId = 20
                    Name = 'node.exe'
                    ExecutablePath = 'C:\Program Files\nodejs\node.exe'
                    CommandLine = "node `"$($verify.activation.core.entryPath)`""
                }
            )
        $runtimeVerify.valid | Should -Be $true
        $runtimeVerify.activeCore.status | Should -Be 'fork-core-command-line-active'

        $secondOperation = Join-Path $backupRoot '20260901T120001000Z'
        $currentReceiptPath = Join-Path $backupRoot 'core-activation-current.json'
        $currentReceipt = Get-Content -LiteralPath $currentReceiptPath -Raw | ConvertFrom-Json
        $currentReceipt.status = 'pending'
        $currentReceipt | ConvertTo-Json -Depth 4 |
            Set-Content -LiteralPath $currentReceiptPath -Encoding UTF8
        $pendingReceipt = Get-Content -LiteralPath (Join-Path $operationRoot 'core-activation.json') -Raw |
            ConvertFrom-Json
        $pendingShim = @($pendingReceipt.shims)[0]
        Copy-Item -LiteralPath (Join-Path $operationRoot ([string]$pendingShim.relativePath)) `
            -Destination ([string]$pendingShim.path) -Force
        {
            Enable-WindowsCopilotForkCore -Lock $activationLock -NpmGlobalRoot $globalRoot `
                -CoreInstallPrefix $core.prefix -BackupRoot $backupRoot -OperationRoot $secondOperation
        } | Should -Throw '*must be rolled back before Apply*'
        (Get-Content -LiteralPath $currentReceiptPath -Raw | ConvertFrom-Json).operationId |
            Should -Be $operationId
        Remove-Item -LiteralPath ([string]$pendingShim.path) -Force
        $second = Enable-WindowsCopilotForkCore -Lock $activationLock -NpmGlobalRoot $globalRoot `
            -CoreInstallPrefix $core.prefix -BackupRoot $backupRoot -OperationRoot $secondOperation
        $second.status | Should -Be 'already-enabled'
        $second.operationId | Should -Be $operationId
        Test-Path -LiteralPath $secondOperation | Should -Be $false

        $currentReceipt = Get-Content -LiteralPath $currentReceiptPath -Raw | ConvertFrom-Json
        $currentReceipt.operationId = '20260901T120001000Z'
        $currentReceipt | ConvertTo-Json -Depth 4 |
            Set-Content -LiteralPath $currentReceiptPath -Encoding UTF8
        {
            Restore-WindowsCopilotForkCore -Lock $activationLock -BackupRoot $backupRoot `
                -NpmGlobalRoot $globalRoot -OperationId $operationId
        } | Should -Throw '*is not current*'
        $script:userDshCliPath | Should -Be $core.cliPath
        $currentReceipt.operationId = $operationId
        $currentReceipt | ConvertTo-Json -Depth 4 |
            Set-Content -LiteralPath $currentReceiptPath -Encoding UTF8

        $activationReceiptPath = Join-Path $operationRoot 'core-activation.json'
        $activationReceipt = Get-Content -LiteralPath $activationReceiptPath -Raw | ConvertFrom-Json
        $activationReceipt.environmentVariable = 'PATH'
        $activationReceipt | ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath $activationReceiptPath -Encoding UTF8
        {
            Restore-WindowsCopilotForkCore -Lock $activationLock -BackupRoot $backupRoot `
                -NpmGlobalRoot $globalRoot -OperationId $operationId
        } | Should -Throw '*locked Core identity*'
        $activationReceipt.environmentVariable = 'DSH_CLI_PATH'
        $activationReceipt | ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath $activationReceiptPath -Encoding UTF8
        $globalPackageMetadata = Get-Content -LiteralPath (Join-Path $globalPackage 'package.json') -Raw |
            ConvertFrom-Json
        $globalPackageMetadata.version = '9.9.9'
        $globalPackageMetadata | ConvertTo-Json -Depth 4 |
            Set-Content -LiteralPath (Join-Path $globalPackage 'package.json') -Encoding UTF8
        {
            Restore-WindowsCopilotForkCore -Lock $activationLock -BackupRoot $backupRoot `
                -NpmGlobalRoot $globalRoot -OperationId $operationId
        } | Should -Throw '*package changed after activation*'
        $globalPackageMetadata.version = '0.1.1-rc.2'
        $globalPackageMetadata | ConvertTo-Json -Depth 4 |
            Set-Content -LiteralPath (Join-Path $globalPackage 'package.json') -Encoding UTF8
        Add-Content -LiteralPath (Join-Path $globalPackage 'lib\bin.js') -Value 'changed' -Encoding UTF8
        {
            Restore-WindowsCopilotForkCore -Lock $activationLock -BackupRoot $backupRoot `
                -NpmGlobalRoot $globalRoot -OperationId $operationId
        } | Should -Throw '*entrypoint bytes changed after activation*'
        Set-Content -LiteralPath (Join-Path $globalPackage 'lib\bin.js') `
            -Value 'official global entrypoint' -Encoding UTF8
        $activationReceipt.repositoryUrl = 'git@github.com:cloga/deepseek-harness.git'
        $activationReceipt | ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath $activationReceiptPath -Encoding UTF8
        $currentReceipt = Get-Content -LiteralPath $currentReceiptPath -Raw | ConvertFrom-Json
        $currentReceipt.status = 'pending'
        $currentReceipt | ConvertTo-Json -Depth 4 |
            Set-Content -LiteralPath $currentReceiptPath -Encoding UTF8

        $rollback = Restore-WindowsCopilotForkCore -Lock $activationLock -BackupRoot $backupRoot -NpmGlobalRoot $globalRoot `
            -OperationId $operationId
        $rollback.status | Should -Be 'rolled-back'
        $script:userDshCliPath | Should -Be 'C:\previous\dsh.cmd'
        (Get-Content -LiteralPath $currentReceiptPath -Raw | ConvertFrom-Json).status |
            Should -Be 'rolled-back'
        foreach ($shim in @($lock.components.core.activation.conflictShims)) {
            Test-Path -LiteralPath (Join-Path $globalPrefix ([string]$shim)) | Should -Be $true
        }
        (Restore-WindowsCopilotForkCore -Lock $activationLock -BackupRoot $backupRoot -NpmGlobalRoot $globalRoot `
            -OperationId $operationId).status | Should -Be 'already-rolled-back'
        Remove-Item -LiteralPath $currentReceiptPath -Force
        {
            Restore-WindowsCopilotForkCore -Lock $activationLock -BackupRoot $backupRoot `
                -NpmGlobalRoot $globalRoot -OperationId $operationId
        } | Should -Throw '*no active operation receipt exists*'
    }

    It 'refuses to remove an unmanaged npm-global dsh conflict' {
        $caseRoot = Join-Path $TestDrive 'unmanaged-global-conflict'
        $core = New-ForkCoreFixture -Prefix (Join-Path $caseRoot 'fork-prefix')
        $globalRoot = Join-Path $caseRoot 'global\node_modules'
        $globalPrefix = Split-Path -Parent $globalRoot
        New-Item -ItemType Directory -Path $globalRoot -Force | Out-Null
        $shimPath = Join-Path $globalPrefix 'dsh.cmd'
        Set-Content -LiteralPath $shimPath -Value 'unmanaged' -Encoding UTF8
        $script:userDshCliPath = $null
        Mock Get-WindowsCopilotUserEnvironment -ModuleName WindowsCopilotDeployment {
            $script:userDshCliPath
        }
        Mock Set-WindowsCopilotUserEnvironment -ModuleName WindowsCopilotDeployment {
            throw 'must not mutate user environment'
        }

        {
            Enable-WindowsCopilotForkCore -Lock $lock -NpmGlobalRoot $globalRoot `
                -CoreInstallPrefix $core.prefix -BackupRoot (Join-Path $caseRoot 'backups') `
                -OperationRoot (Join-Path $caseRoot 'backups\20260901T130000000Z')
        } | Should -Throw '*unmanaged global dsh shims*'
        Test-Path -LiteralPath $shimPath | Should -Be $true
    }

    It 'targets only the exact Desktop executable during a restart dry run' {
        $caseRoot = Join-Path $TestDrive 'desktop-restart'
        $desktopPath = Join-Path $caseRoot 'desktop\deepseek-harness-desktop.exe'
        New-VersionedDesktopFixture -Path $desktopPath -Version '0.10.2'
        $processes = @(
            [pscustomobject]@{
                ProcessId = 10
                ParentProcessId = 0
                Name = 'deepseek-harness-desktop.exe'
                ExecutablePath = $desktopPath
                CommandLine = "`"$desktopPath`""
            },
            [pscustomobject]@{
                ProcessId = 11
                ParentProcessId = 0
                Name = 'deepseek-harness-desktop.exe'
                ExecutablePath = Join-Path $caseRoot 'other\deepseek-harness-desktop.exe'
                CommandLine = 'other'
            }
        )
        $result = Restart-WindowsCopilotDesktop -DesktopExecutablePath $desktopPath `
            -CliInfo ([pscustomobject]@{}) -Processes $processes -DryRun
        $result.processIds | Should -Be @(10)
    }

    It 'installs Core through the receipt producer before the remaining global transaction' {
        $plan = Get-WindowsCopilotInstallPlan -Lock $lock -DshHome (Join-Path $TestDrive '.dsh') `
            -NpmGlobalRoot (Join-Path $TestDrive 'global')
        $coreStep = @($plan.steps | Where-Object id -eq 'install-core-with-receipt')[0]
        $probeStep = @($plan.steps | Where-Object id -eq 'verify-installed-core-capability')[0]
        $step = @($plan.steps | Where-Object id -eq 'install-global-transaction')[0]
        $stepIds = @($plan.steps | ForEach-Object { [string]$_.id })
        $coreStep.action | Should -Be 'release-install-local'
        $probeStep.action | Should -Be 'receipt-bytes-and-sandbox-probe'
        [array]::IndexOf($stepIds, 'verify-installed-core-capability') |
            Should -BeLessThan ([array]::IndexOf($stepIds, 'install-global-transaction'))
        $step.packages.Count | Should -Be 4
        ($step.packages -contains '@deepseek-ai/cordis-plugin-hmr@1.0.16') | Should -Be $true
        ($step.packages -contains '@deepseek-ai/cordis-plugin-timer@1.1.3') | Should -Be $true
        ($step.packages -contains 'node-addon-require-builtin@0.1.4') | Should -Be $true
        ($step.packages -contains '<built-core-release-family-tarballs>') | Should -Be $false
        ($step.packages -contains '<built-copilot-integration-tarball>') | Should -Be $true
    }

    It 'forwards Core installer options through pinned pnpm without a positional separator' {
        $caseRoot = Join-Path $TestDrive 'pnpm-script-arguments'
        $capturePath = Join-Path $caseRoot 'arguments.json'
        New-Item -ItemType Directory -Path $caseRoot -Force | Out-Null
        [ordered]@{
            private = $true
            scripts = [ordered]@{
                'capture-install-args' = 'node capture-install-args.cjs'
            }
        } | ConvertTo-Json -Depth 4 |
            Set-Content -LiteralPath (Join-Path $caseRoot 'package.json') -Encoding UTF8
        @'
const fs = require('node:fs')
fs.writeFileSync(process.env.ARG_CAPTURE_PATH, JSON.stringify(process.argv.slice(2)))
'@ | Set-Content -LiteralPath (Join-Path $caseRoot 'capture-install-args.cjs') -Encoding UTF8
        $previousCapturePath = $env:ARG_CAPTURE_PATH
        try {
            $env:ARG_CAPTURE_PATH = $capturePath
            $module = Get-Module WindowsCopilotDeployment
            & $module {
                param($WorkingDirectory)
                Invoke-LockedCommand -FilePath 'npx' -Arguments @(
                    '--yes',
                    'pnpm@11.7.0',
                    'run',
                    'capture-install-args',
                    '--from', 'release-one',
                    '--from', 'release-two',
                    '--from', 'release-three',
                    '--prefix', 'install-prefix',
                    '--expect-commit', 'a772dbbde82780bff2b9394427e9f0a24cafa1d5',
                    '--expect-version', '0.1.1-rc.2'
                ) -WorkingDirectory $WorkingDirectory
            } $caseRoot
        } finally {
            $env:ARG_CAPTURE_PATH = $previousCapturePath
        }
        Get-Content -LiteralPath $capturePath -Raw -Encoding UTF8 |
            Should -Be (
                '["--from","release-one","--from","release-two","--from","release-three",' +
                '"--prefix","install-prefix","--expect-commit",' +
                '"a772dbbde82780bff2b9394427e9f0a24cafa1d5","--expect-version","0.1.1-rc.2"]'
            )
    }

    It 'blocks a new Apply before mutation when an activation is pending' {
        $caseRoot = Join-Path $TestDrive 'pending-apply'
        $backupRoot = Join-Path $caseRoot 'backups'
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
        [ordered]@{
            schemaVersion = 1
            deploymentId = [string]$lock.deploymentId
            operationId = '20260901T125959000Z'
            status = 'pending'
        } | ConvertTo-Json | Set-Content `
            -LiteralPath (Join-Path $backupRoot 'core-activation-current.json') -Encoding UTF8
        $catalog = Get-Content -LiteralPath (Join-Path $fixtureRoot 'model-catalog.json') -Raw |
            ConvertFrom-Json

        {
            Invoke-WindowsCopilotApply -Lock $lock -DshHome (Join-Path $caseRoot '.dsh') `
                -NpmGlobalRoot (Join-Path $caseRoot 'global\node_modules') `
                -HarnessSourceRoot (Join-Path $caseRoot 'missing-core') `
                -CopilotIntegrationSourceRoot (Join-Path $caseRoot 'missing-provider') `
                -DesktopArtifactPath (Join-Path $caseRoot 'missing-desktop.exe') `
                -GatewayArtifactPath (Join-Path $caseRoot 'missing-gateway.exe') `
                -GatewayInstallRoot (Join-Path $caseRoot 'gateway') `
                -CoreInstallPrefix (Join-Path $caseRoot 'core') `
                -BackupRoot $backupRoot -Catalog $catalog
        } | Should -Throw '*must be rolled back before Apply*'
        Test-Path -LiteralPath (Join-Path $caseRoot 'core') | Should -Be $false
        Test-Path -LiteralPath (Join-Path $caseRoot 'gateway') | Should -Be $false
    }

    It 'produces a validated Core receipt and accepts the exact healthy baseline' {
        $caseRoot = Join-Path $TestDrive 'healthy-baseline'
        $script:receiptPrefix = Join-Path $caseRoot 'prefix'
        $globalRoot = Join-Path $caseRoot 'global\node_modules'
        $sourceRoot = Join-Path $caseRoot 'source'
        $releaseRoot = Join-Path $sourceRoot 'dist\npm'
        $vendorReleaseRoot = Join-Path $sourceRoot 'dist\npm-vendor'
        $landlockReleaseRoot = Join-Path $sourceRoot 'dist\npm-landlock'
        New-Item -ItemType Directory -Path $globalRoot, $releaseRoot, $vendorReleaseRoot, $landlockReleaseRoot -Force | Out-Null
        $script:receiptPackage = [ordered]@{
            name = '@deepseek-ai/dsh'
            version = [string]$lock.components.core.package.version
            filename = 'deepseek-ai-dsh-fixture.tgz'
            sha256 = ('a' * 64)
            files = 10
        }
        $coreRelease = [pscustomobject]@{
            directory = $releaseRoot
            directories = @($releaseRoot, $vendorReleaseRoot, $landlockReleaseRoot)
            packages = @([pscustomobject]@{
                name = $receiptPackage.name
                version = $receiptPackage.version
                path = Join-Path $releaseRoot $receiptPackage.filename
                sha256 = $receiptPackage.sha256
                files = $receiptPackage.files
            })
        }
        $script:coreInstallCommand = $null
        Mock Invoke-LockedCommand -ModuleName WindowsCopilotDeployment {
            param($FilePath, $Arguments, $WorkingDirectory)
            $script:coreInstallCommand = [pscustomobject]@{
                filePath = $FilePath
                arguments = @($Arguments)
                workingDirectory = $WorkingDirectory
            }
            $packageRoot = Join-Path $script:receiptPrefix 'node_modules\@deepseek-ai\dsh'
            $binRoot = Join-Path $script:receiptPrefix 'node_modules\.bin'
            New-Item -ItemType Directory -Path $packageRoot, $binRoot -Force | Out-Null
            [ordered]@{
                name = '@deepseek-ai/dsh'
                version = $script:receiptPackage.version
                bin = [ordered]@{ dsh = 'lib/bin.js' }
            } | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $packageRoot 'package.json') -Encoding UTF8
            New-Item -ItemType Directory -Path (Join-Path $packageRoot 'lib') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $packageRoot 'lib\bin.js') -Value 'process.exit(0)' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $binRoot 'dsh.cmd') -Value '@echo off' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $script:receiptPrefix 'dsh.cmd') `
                -Value "@echo off`r`n@call `"%~dp0node_modules\.bin\dsh.cmd`" %*" -Encoding ASCII
            $packages = @($script:receiptPackage)
            $manifestJson = ConvertTo-Json -InputObject $packages -Compress -Depth 4
            [ordered]@{
                schemaVersion = 1
                repositoryUrl = 'https://github.com/cloga/deepseek-harness.git'
                commitSha = [string]$script:lock.components.core.source.commit
                packageName = '@deepseek-ai/dsh'
                packageVersion = $script:receiptPackage.version
                releaseManifestSha256 = Get-TestSha256Text -Text $manifestJson
                cliPath = Join-Path $script:receiptPrefix 'dsh.cmd'
                packages = $packages
            } | ConvertTo-Json -Depth 6 | Set-Content `
                -LiteralPath (Join-Path $script:receiptPrefix 'dsh-local-install.json') -Encoding UTF8
        }
        $core = Install-WindowsCopilotCoreRelease -Lock $lock -SourceRoot $sourceRoot `
            -NpmGlobalRoot $globalRoot -CoreInstallPrefix $receiptPrefix -CoreRelease $coreRelease
        $script:coreInstallCommand.filePath | Should -Be 'npx'
        $script:coreInstallCommand.workingDirectory | Should -Be ([IO.Path]::GetFullPath($sourceRoot))
        $script:coreInstallCommand.arguments | Should -Be @(
            '--yes',
            'pnpm@11.7.0',
            'run',
            'release:install-local',
            '--from', [IO.Path]::GetFullPath($releaseRoot),
            '--from', [IO.Path]::GetFullPath($vendorReleaseRoot),
            '--from', [IO.Path]::GetFullPath($landlockReleaseRoot),
            '--prefix', [IO.Path]::GetFullPath($receiptPrefix),
            '--expect-commit', [string]$lock.components.core.source.commit,
            '--expect-version', [string]$lock.components.core.package.version
        )
        @($script:coreInstallCommand.arguments | Where-Object { $_ -ceq '--' }).Count | Should -Be 0
        Should -Invoke Invoke-LockedCommand -ModuleName WindowsCopilotDeployment -Times 1 -Exactly
        $core.commitSha | Should -Be $lock.components.core.source.commit
        Test-Path -LiteralPath $core.receiptPath | Should -Be $true
        $core.installedFileCount | Should -Be 3

        Copy-Item -Path (Join-Path $fixtureRoot 'global\*') -Destination $globalRoot -Recurse
        $dshHome = Join-Path $caseRoot '.dsh'
        $profileRoot = Join-Path $dshHome 'profiles\web'
        New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null
        $desktopPath = Join-Path $caseRoot 'Deepseek Harness Desktop\deepseek-harness-desktop.exe'
        New-DesktopInternalPluginFixture -ProfileRoot $profileRoot -DesktopExecutablePath $desktopPath
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'profile\package.json') -Destination $profileRoot
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'profile\pnpm-workspace.yaml') -Destination $profileRoot
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'settings.yaml') -Destination (Join-Path $dshHome 'settings.yaml')
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'credentials.yaml') -Destination (Join-Path $dshHome '.credentials.yaml')
        $providerArtifact = Join-Path $caseRoot 'dsh-github-copilot-0.3.0-cloga.8.tgz'
        $providerStage = Join-Path $caseRoot 'provider-stage'
        New-Item -ItemType Directory -Path $providerStage -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $globalRoot 'dsh-github-copilot') `
            -Destination (Join-Path $providerStage 'package') -Recurse
        & tar -czf $providerArtifact -C $providerStage package
        if ($LASTEXITCODE -ne 0) { throw 'Could not create provider test artifact.' }
        $healthyLock = $lock | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $healthyLock.components.copilotIntegration.package.artifact.sha256 =
            (Get-FileHash -LiteralPath $providerArtifact -Algorithm SHA256).Hash.ToLowerInvariant()
        Set-WindowsCopilotProfile -Lock $healthyLock -DshHome $dshHome -NpmGlobalRoot $globalRoot `
            -ProviderArtifactPath $providerArtifact -Catalog $catalog -BackupRoot (Join-Path $caseRoot 'backups') `
            -DesktopExecutablePath $desktopPath -SkipPackageInstall | Out-Null
        Mock Test-LoopbackListener -ModuleName WindowsCopilotDeployment {
            param($HostName, $Port)
            [pscustomobject]@{
                host = '127.0.0.1'
                port = $Port
                listening = $true
                loopbackOnly = $true
                bindingVerified = $true
                owningProcessIds = @($(if ($Port -eq 3080) { 101 } else { 201 }))
            }
        }
        Mock Test-LoaderPackageImports -ModuleName WindowsCopilotDeployment {
            [pscustomobject]@{ valid = $true; status = 'imported' }
        }
        Mock Test-DshSandboxRegression -ModuleName WindowsCopilotDeployment {
            [pscustomobject]@{
                status = 'passed'
                required = $true
                sameMode = 'workspace-write'
                narrowerMode = 'workspace-write'
                widerMode = 'danger-full-access'
                effectiveMode = 'danger-full-access'
            }
        }
        Mock Get-WindowsCopilotLegacyGatewayState -ModuleName WindowsCopilotDeployment {
            [pscustomobject]@{
                detected = $false
                matchesReviewedLegacy = $false
                migrationOnly = $true
                status = 'not-detected'
            }
        }
        $activeProcesses = @(
            [pscustomobject]@{
                ProcessId = 100
                ParentProcessId = 0
                Name = 'deepseek-harness-desktop.exe'
                ExecutablePath = $desktopPath
                CommandLine = "`"$desktopPath`""
            },
            [pscustomobject]@{
                ProcessId = 101
                ParentProcessId = 100
                Name = 'node.exe'
                ExecutablePath = 'C:\Program Files\nodejs\node.exe'
                CommandLine = 'node "' + $core.packageRoot + '\lib\bin.js"'
            }
        )
        $previousCliPath = $env:DSH_CLI_PATH
        try {
            $env:DSH_CLI_PATH = Join-Path $caseRoot 'wrong-global\dsh.cmd'
            $state = Test-WindowsCopilotInstallation -Lock $healthyLock -DshHome $dshHome `
                -NpmGlobalRoot $globalRoot -CoreInstallPrefix $receiptPrefix -DesktopVersion '0.10.2' `
                -DesktopExecutablePath $desktopPath `
                -ModelCatalogPath (Join-Path $fixtureRoot 'model-catalog.json') `
                -ComposedConfigPath (Join-Path $fixtureRoot 'composed-config.yml') `
                -SearchSmokeResponsePath (Join-Path $fixtureRoot 'search-response.json') `
                -DesktopProcesses $activeProcesses
        } finally {
            $env:DSH_CLI_PATH = $previousCliPath
        }
        $state.deployment.core.status | Should -Be 'verified'
        $state.runtime.activeCore.reason | Should -BeNullOrEmpty
        $state.runtime.activeCore.status | Should -Be 'receipted-core-owns-3080'
        $state.runtime.activeCore.listenerOwnerProcessIds | Should -Be @(101)
        $healthyProvider = @($state.profile.plugins | Where-Object name -eq 'dsh-github-copilot')[0]
        $healthyProvider.payloadReason | Should -BeNullOrEmpty
        $healthyProvider.payloadStatus | Should -Be 'verified'
        $state.complete | Should -Be $true -Because ($state | ConvertTo-Json -Depth 12 -Compress)
        $state.health | Should -Be 'healthy'

        $unrelatedProcesses = @(
            $activeProcesses[0],
            [pscustomobject]@{
                ProcessId = 102
                ParentProcessId = 100
                Name = 'node.exe'
                ExecutablePath = 'C:\Program Files\nodejs\node.exe'
                CommandLine = 'node "C:\Program Files\DeepSeek Harness\packaged-core\lib\bin.js"'
            }
        )
        $falseActive = Test-WindowsCopilotInstallation -Lock $healthyLock -DshHome $dshHome `
            -NpmGlobalRoot $globalRoot -DshCliPath $core.cliPath -DesktopVersion '0.10.2' `
            -DesktopExecutablePath $desktopPath `
            -ModelCatalogPath (Join-Path $fixtureRoot 'model-catalog.json') `
            -ComposedConfigPath (Join-Path $fixtureRoot 'composed-config.yml') `
            -SearchSmokeResponsePath (Join-Path $fixtureRoot 'search-response.json') `
            -DesktopProcesses $unrelatedProcesses
        $falseActive.complete | Should -Be $false
        $falseActive.runtime.activeCore.status | Should -Be 'receipted-core-not-active'
        @($falseActive.drift.reasons) | Should -Contain 'core-receipted-package-not-active-under-desktop'

        Mock Test-LoopbackListener -ModuleName WindowsCopilotDeployment {
            param($HostName, $Port)
            [pscustomobject]@{
                host = '127.0.0.1'
                port = $Port
                listening = $true
                loopbackOnly = $true
                bindingVerified = $true
                owningProcessIds = @($(if ($Port -eq 3080) { 999 } else { 201 }))
            }
        }
        $wrongOwner = Test-WindowsCopilotInstallation -Lock $healthyLock -DshHome $dshHome `
            -NpmGlobalRoot $globalRoot -CoreInstallPrefix $receiptPrefix -DesktopVersion '0.10.2' `
            -DesktopExecutablePath $desktopPath `
            -ModelCatalogPath (Join-Path $fixtureRoot 'model-catalog.json') `
            -ComposedConfigPath (Join-Path $fixtureRoot 'composed-config.yml') `
            -SearchSmokeResponsePath (Join-Path $fixtureRoot 'search-response.json') `
            -DesktopProcesses $activeProcesses
        $wrongOwner.complete | Should -Be $false
        $wrongOwner.runtime.activeCore.status | Should -Be 'receipted-core-listener-owner-mismatch'
        @($wrongOwner.drift.reasons) | Should -Contain 'core-receipted-process-does-not-own-3080'

        Add-Content -LiteralPath (Join-Path $profileRoot 'node_modules\dsh-github-copilot\lib\index.js') `
            -Value 'tampered' -Encoding ASCII
        $providerTamper = Test-WindowsCopilotInstallation -Lock $healthyLock -DshHome $dshHome `
            -NpmGlobalRoot $globalRoot -CoreInstallPrefix $receiptPrefix -DesktopVersion '0.10.2' `
            -DesktopExecutablePath $desktopPath `
            -ModelCatalogPath (Join-Path $fixtureRoot 'model-catalog.json') `
            -ComposedConfigPath (Join-Path $fixtureRoot 'composed-config.yml') `
            -SearchSmokeResponsePath (Join-Path $fixtureRoot 'search-response.json') `
            -SkipRuntimeChecks
        $provider = @($providerTamper.profile.plugins | Where-Object name -eq 'dsh-github-copilot')[0]
        $provider.payloadStatus | Should -Be 'installed-file-mismatch'
        @($providerTamper.drift.reasons) | Should -Contain 'provider-payload-installed-file-mismatch'

        $receipt = Get-Content -LiteralPath $core.receiptPath -Raw | ConvertFrom-Json
        $receipt.PSObject.Properties.Remove('installedFiles')
        $receipt | ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath $core.receiptPath -Encoding UTF8
        $unattested = Test-WindowsCopilotInstallation -Lock $healthyLock -DshHome $dshHome `
            -NpmGlobalRoot $globalRoot -CoreInstallPrefix $receiptPrefix -DesktopVersion '0.10.2' `
            -DesktopExecutablePath $desktopPath `
            -ModelCatalogPath (Join-Path $fixtureRoot 'model-catalog.json') `
            -ComposedConfigPath (Join-Path $fixtureRoot 'composed-config.yml') `
            -SearchSmokeResponsePath (Join-Path $fixtureRoot 'search-response.json') `
            -DesktopProcesses $activeProcesses
        $unattested.complete | Should -Be $false
        $unattested.deployment.core.status | Should -Be 'installed-bytes-unattested'
        @($unattested.drift.reasons) | Should -Contain 'core-installed-bytes-unattested'
    }

    It 'loads the real receipt installer from an exact locked Core checkout' -Skip:(-not $env:DSH_LOCKED_CORE_CHECKOUT) {
        $checkout = [IO.Path]::GetFullPath($env:DSH_LOCKED_CORE_CHECKOUT)
        Test-Path -LiteralPath (Join-Path $checkout '.git') | Should -Be $true
        (& git -C $checkout rev-parse HEAD).Trim() | Should -Be $lock.components.core.source.commit
        $remote = (& git -C $checkout remote get-url origin).Trim()
        $remote.Replace('\', '/').Replace(':', '/').Replace('.git', '') |
            Should -Match 'github\.com/cloga/deepseek-harness$'
        $rootPackage = Get-Content -LiteralPath (Join-Path $checkout 'package.json') -Raw | ConvertFrom-Json
        $cliPackage = Get-Content -LiteralPath (Join-Path $checkout 'apps\cli\package.json') -Raw | ConvertFrom-Json
        $scriptName = [string]$lock.components.core.install.script
        $rootPackage.scripts.$scriptName | Should -Be 'tsx scripts/release/install-local.ts'
        $cliPackage.version | Should -Be $lock.components.core.package.version
        Test-Path -LiteralPath (Join-Path $checkout 'scripts\release\install-local.ts') | Should -Be $true
        & git -C $checkout merge-base --is-ancestor d931e5482181f41de0b96a9453de5f2112a4fe47 HEAD
        $LASTEXITCODE | Should -Be 0

        Push-Location $checkout
        try {
            $output = & npx --yes tsx@4.22.4 scripts/release/install-local.ts 2>&1 | Out-String
            $LASTEXITCODE | Should -Be 1
            $output | Should -Match 'usage: install-local\.ts --from <packed directory>'
            & pnpm -C $checkout exec vitest run packages/sandbox/sandbox/tests/escalation.spec.ts
            $LASTEXITCODE | Should -Be 0
        } finally {
            Pop-Location
        }
    }

    It 'preserves five official Desktop links and materializes only the provider' {
        $plan = Get-WindowsCopilotInstallPlan -Lock $lock -DshHome (Join-Path $TestDrive '.dsh') `
            -NpmGlobalRoot (Join-Path $TestDrive 'global')
        $preserve = @($plan.steps | Where-Object id -eq 'preserve-desktop-internal-plugins')[0]
        $materialize = @($plan.steps | Where-Object id -eq 'materialize-copilot-plugin')[0]
        $preserve.plugins.Count | Should -Be 5
        ($preserve.plugins -contains 'dsh-tauri-panel-extension') | Should -Be $true
        $materialize.plugins | Should -Be @('dsh-github-copilot')
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
            'https://github.com/cloga/dsh-github-copilot/releases/download/v0.3.0-cloga.7/dsh-github-copilot-0.3.0-cloga.8.tgz'
            'https://github.com/cloga/dsh-github-copilot/releases/download/v0.3.0-cloga.8/dsh-github-copilot-0.3.0-cloga.9.tgz'
            'https://github.com/cloga/dsh-github-copilot/releases/download/v0.3.0-cloga.8/not-dsh-github-copilot-0.3.0-cloga.8.tgz'
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
        $artifact = Join-Path $caseRoot ([string]$lock.components.copilotIntegration.package.artifact.name)
        Set-Content -LiteralPath $artifact -Value 'fixture artifact' -Encoding UTF8

        Set-WindowsCopilotProfile -Lock $lock -DshHome $dshHome -NpmGlobalRoot $globalRoot `
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
        $artifact = Join-Path $TestDrive 'dsh-github-copilot-0.3.0-cloga.8.tgz'
        Set-Content -LiteralPath $artifact -Value 'fixture artifact' -Encoding UTF8

        $first = Set-WindowsCopilotProfile -Lock $lock -DshHome $dshHome -NpmGlobalRoot $globalRoot `
            -ProviderArtifactPath $artifact -Catalog $catalog -BackupRoot $backupRoot `
            -DesktopExecutablePath $desktopPath -SkipPackageInstall
        $second = Set-WindowsCopilotProfile -Lock $lock -DshHome $dshHome -NpmGlobalRoot $globalRoot `
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

        $state = Test-WindowsCopilotInstallation -Lock $lock -DshHome $dshHome `
            -NpmGlobalRoot $globalRoot -ModelCatalogPath (Join-Path $fixtureRoot 'model-catalog.json') `
            -ComposedConfigPath (Join-Path $fixtureRoot 'composed-config.yml') `
            -SearchSmokeResponsePath (Join-Path $fixtureRoot 'search-response.json') `
            -DshCliPath (Join-Path $TestDrive 'missing-dsh.cmd') -DesktopVersion '0.10.2' `
            -DesktopExecutablePath $desktopPath `
            -SkipRuntimeChecks
        $state.profile.dependencyValid | Should -Be $true
        $state.profile.bundleValid | Should -Be $true
        $state.profile.allowBuildsValid | Should -Be $true
        $state.profile.routesValid | Should -Be $true
        $state.profile.providerRoute.modelsComplete | Should -Be $true
        $state.profile.providerRoute.mixedProtocolApis | Should -Be $true
        @($state.profile.providerRoute.apis) | Should -Be @('openai-responses', 'openai-completions')
        @($state.profile.plugins | Where-Object {
            $_.source -eq 'desktop-internal' -and -not $_.officialDesktopLink
        }).Count | Should -Be 0
        (@($state.profile.plugins | Where-Object name -eq 'dsh-github-copilot'))[0].physical |
            Should -Be $true

        $profile.dsh.profile.bundles = @($profile.dsh.profile.bundles | Where-Object { $_ -ne 'dsh-tauri' })
        $profile | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $profileRoot 'package.json') -Encoding UTF8
        $missingBundle = Test-WindowsCopilotInstallation -Lock $lock -DshHome $dshHome `
            -NpmGlobalRoot $globalRoot -ModelCatalogPath (Join-Path $fixtureRoot 'model-catalog.json') `
            -ComposedConfigPath (Join-Path $fixtureRoot 'composed-config.yml') `
            -SearchSmokeResponsePath (Join-Path $fixtureRoot 'search-response.json') `
            -DshCliPath (Join-Path $TestDrive 'missing-dsh.cmd') -DesktopVersion '0.10.2' `
            -DesktopExecutablePath $desktopPath `
            -SkipRuntimeChecks
        $missingBundle.profile.bundleValid | Should -Be $false
        @($missingBundle.drift.reasons) | Should -Contain 'profile-bundle-drift'
        $missingBundle.drift.remediation.status | Should -Not -Be 'not-required'
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
        $artifact = Join-Path $caseRoot 'dsh-github-copilot-0.3.0-cloga.8.tgz'
        Set-Content -LiteralPath $artifact -Value 'fixture artifact' -Encoding UTF8

        $module = Get-Module WindowsCopilotDeployment
        $migration = & $module {
            param($Lock, $DshHome, $DesktopExecutablePath)
            Get-WindowsCopilotProfileMigrationPlan -Lock $Lock -DshHome $DshHome `
                -DesktopExecutablePath $DesktopExecutablePath
        } $lock $dshHome $desktopPath
        @($migration.dependenciesToRemove | Sort-Object) |
            Should -Be @($lock.profile.legacyPhysicalPlugins.name | Sort-Object)

        $result = Set-WindowsCopilotProfile -Lock $lock -DshHome $dshHome -NpmGlobalRoot $globalRoot `
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
        $artifact = Join-Path $caseRoot 'dsh-github-copilot-0.3.0-cloga.8.tgz'
        Set-Content -LiteralPath $artifact -Value 'fixture artifact' -Encoding UTF8
        Mock Invoke-PinnedPnpmCommands -ModuleName WindowsCopilotDeployment { throw 'fixture pnpm failure' }

        {
            Set-WindowsCopilotProfile -Lock $lock -DshHome $dshHome -NpmGlobalRoot $globalRoot `
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

        {
            Invoke-WindowsCopilotApply -Lock $lock -DshHome $dshHome `
                -NpmGlobalRoot (Join-Path $caseRoot 'global\node_modules') `
                -HarnessSourceRoot (Join-Path $caseRoot 'missing-core') `
                -ProviderSourceRoot (Join-Path $caseRoot 'missing-provider') `
                -DesktopArtifactPath (Join-Path $caseRoot 'missing-desktop.exe') `
                -GatewayArtifactPath (Join-Path $caseRoot 'missing-gateway.exe') `
                -GatewayInstallRoot (Join-Path $caseRoot 'gateway') `
                -CoreInstallPrefix (Join-Path $caseRoot 'core') `
                -BackupRoot (Join-Path $caseRoot 'backups') -Catalog $catalog `
                -DesktopExecutablePath $desktopPath
        } | Should -Throw '*official Desktop internal-plugin link is missing or invalid*'
        Test-Path -LiteralPath (Join-Path $caseRoot 'core') | Should -Be $false
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
        $artifact = Join-Path $caseRoot 'dsh-github-copilot-0.3.0-cloga.8.tgz'
        Set-Content -LiteralPath $artifact -Value 'fixture artifact' -Encoding UTF8

        {
            Set-WindowsCopilotProfile -Lock $lock -DshHome $dshHome `
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

        {
            Invoke-WindowsCopilotApply -Lock $lock -DshHome $dshHome `
                -NpmGlobalRoot (Join-Path $caseRoot 'global\node_modules') `
                -HarnessSourceRoot (Join-Path $caseRoot 'missing-core') `
                -ProviderSourceRoot (Join-Path $caseRoot 'missing-provider') `
                -DesktopArtifactPath (Join-Path $caseRoot 'missing-desktop.exe') `
                -GatewayArtifactPath (Join-Path $caseRoot 'missing-gateway.exe') `
                -GatewayInstallRoot (Join-Path $caseRoot 'gateway') `
                -CoreInstallPrefix (Join-Path $caseRoot 'core') `
                -BackupRoot (Join-Path $caseRoot 'backups') -Catalog $catalog `
                -DesktopExecutablePath $desktopPath
        } | Should -Throw '*official Desktop internal-plugin link is missing or invalid*'
        Test-Path -LiteralPath (Join-Path $caseRoot 'core') | Should -Be $false
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

    It 'fails closed on the exact 2026-08-28 mixed deployment signature' {
        $caseRoot = Join-Path $TestDrive 'incident-2026-08-28'
        $dshHome = Join-Path $caseRoot '.dsh'
        $profileRoot = Join-Path $dshHome 'profiles\web'
        $globalRoot = Join-Path $caseRoot 'global'
        $corePrefix = Join-Path $caseRoot 'core-prefix'
        $canonicalCli = Join-Path $corePrefix 'node_modules\.bin\dsh.cmd'
        $desktopCli = Join-Path $corePrefix 'dsh.cmd'
        New-Item -ItemType Directory -Path $profileRoot, $globalRoot, (Split-Path $canonicalCli -Parent) -Force | Out-Null
        $canonicalDesktop = Join-Path $env:LOCALAPPDATA 'Deepseek Harness Desktop\deepseek-harness-desktop.exe'
        New-DesktopInternalPluginFixture -ProfileRoot $profileRoot -DesktopExecutablePath $canonicalDesktop `
            -Version '0.9.2'
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'profile\package.json') -Destination $profileRoot
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'profile\pnpm-workspace.yaml') -Destination $profileRoot
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'settings.yaml') -Destination (Join-Path $dshHome 'settings.yaml')
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'credentials.yaml') -Destination (Join-Path $dshHome '.credentials.yaml')
        Copy-Item -Path (Join-Path $fixtureRoot 'global\*') -Destination $globalRoot -Recurse
        $artifact = Join-Path $caseRoot 'dsh-github-copilot-0.3.0-cloga.8.tgz'
        Set-Content -LiteralPath $artifact -Value 'fixture artifact' -Encoding UTF8
        Set-WindowsCopilotProfile -Lock $lock -DshHome $dshHome -NpmGlobalRoot $globalRoot `
            -ProviderArtifactPath $artifact -Catalog $catalog -BackupRoot (Join-Path $caseRoot 'backups') `
            -DesktopExecutablePath $canonicalDesktop -SkipPackageInstall | Out-Null

        $profilePath = Join-Path $profileRoot 'package.json'
        $profile = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $profile.dependencies | Add-Member -NotePropertyName 'dsh-web-search-provider' -NotePropertyValue `
            'file:C:/Users/incident/dsh-web-search-provider/dist-all-fixes/dsh-web-search-provider-0.2.2-all-fixes-bd40ffb.tgz'
        $profile | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $profilePath -Encoding UTF8
        $providerRoot = Join-Path $profileRoot 'node_modules\dsh-web-search-provider'
        New-Item -ItemType Directory -Path $providerRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'provider-0.2.2\package.json') `
            -Destination (Join-Path $providerRoot 'package.json') -Force
        Set-Content -LiteralPath $canonicalCli -Value '@echo off' -Encoding ASCII
        Set-Content -LiteralPath $desktopCli -Value "@echo off`r`n@call `"%~dp0node_modules\.bin\dsh.cmd`" %*" -Encoding ASCII

        $profileBefore = (Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash
        $state = Test-WindowsCopilotInstallation -Lock $lock -DshHome $dshHome `
            -NpmGlobalRoot (Join-Path $corePrefix 'node_modules') `
            -ModelCatalogPath (Join-Path $fixtureRoot 'model-catalog.json') `
            -ComposedConfigPath (Join-Path $fixtureRoot 'composed-config-incident-2026-08-28.yml') `
            -SearchSmokeResponsePath (Join-Path $fixtureRoot 'search-response.json') `
            -DshCliPath $desktopCli -DesktopVersion '0.9.2' -DesktopExecutablePath $canonicalDesktop `
            -SkipRuntimeChecks

        $state.complete | Should -Be $false
        $state.readyForManualSearchSmoke | Should -Be $false
        $state.health | Should -Be 'drifted'
        $state.drift.incidentId | Should -Be 'windows-copilot-drift-2026-08-28'
        $state.drift.mixedState | Should -Be $true
        $state.deployment.desktop.status | Should -Be 'version-mismatch'
        $state.deployment.PSObject.Properties.Name | Should -Not -Contain 'gateway'
        $state.deployment.core.status | Should -Be 'receipt-missing'
        $legacy = @($state.profile.legacyCopilotIntegrations | Where-Object {
            $_.lockedLegacyVersion -eq '0.2.2'
        })[0]
        $legacy.dependency | Should -Match 'dsh-web-search-provider-0\.2\.2-all-fixes-bd40ffb\.tgz$'
        $legacy.installedVersion | Should -Be '0.2.2'
        @($state.drift.reasons) | Should -Contain 'legacy-dsh-web-search-provider-0-2-2-active'
        $state.runtime.composedConfig.managedConfigValid | Should -Be $false
        @($state.runtime.composedConfig.forbiddenActiveEntries) | Should -Contain 'web-search-provider'
        $state.drift.remediation.status | Should -Be 'locked-repair-required'
        $state.drift.remediation.automaticApplyAllowed | Should -Be $false
        @($state.drift.remediation.steps.action) | Should -Contain 'bootstrap-direct-copilot'
        (Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash | Should -Be $profileBefore
        Test-Path -LiteralPath (Join-Path $corePrefix 'dsh-local-install.json') | Should -Be $false

        $scriptPath = Join-Path $repoRoot 'tools\install-windows-copilot.ps1'
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath `
            -DshHome $dshHome -NpmGlobalRoot (Join-Path $corePrefix 'node_modules') `
            -ModelCatalogPath (Join-Path $fixtureRoot 'model-catalog.json') `
            -ComposedConfigPath (Join-Path $fixtureRoot 'composed-config-incident-2026-08-28.yml') `
            -SearchSmokeResponsePath (Join-Path $fixtureRoot 'search-response.json') `
            -DshCliPath $desktopCli -DesktopExecutablePath (Join-Path $caseRoot 'wrong-desktop.exe') `
            -SkipRuntimeChecks
        $LASTEXITCODE | Should -Be 0
        $entryResult = ($output -join "`n") | ConvertFrom-Json
        $entryResult.checks.installation.drift.incidentId | Should -Be 'windows-copilot-drift-2026-08-28'
        $entryResult.checks.composedConfig.status | Should -Be 'drifted'
        $entryResult.checks.installation.drift.remediation.status | Should -Be 'locked-repair-required'
    }

    It 'validates the Copilot integration source against the exported deployment contract' {
        $result = Test-CopilotIntegrationDeploymentContract -Lock $lock -SourceRoot (Join-Path $fixtureRoot 'provider')
        $result.valid | Should -Be $true
        $result.sourceVerified | Should -Be $true
        $result.artifactVerified | Should -Be $false
        @($result.capabilities).Count | Should -Be 13
        @($result.capabilities) | Should -Contain 'client-module-loader-handoff'
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

    It 'refuses apply before mutation when the installed Desktop is newer than the lock' {
        $catalog = Get-Content -LiteralPath (Join-Path $fixtureRoot 'model-catalog.json') -Raw | ConvertFrom-Json
        $canonicalDesktop = Join-Path $env:LOCALAPPDATA 'Deepseek Harness Desktop\deepseek-harness-desktop.exe'
        New-VersionedDesktopFixture -Path $canonicalDesktop -Version '0.10.3'
        {
            Invoke-WindowsCopilotApply -Lock $lock -DshHome (Join-Path $TestDrive '.dsh') `
                -NpmGlobalRoot (Join-Path $TestDrive 'global\node_modules') `
                -HarnessSourceRoot (Join-Path $TestDrive 'missing-core-source') `
                -ProviderSourceRoot (Join-Path $TestDrive 'missing-provider-source') `
                -DesktopArtifactPath (Join-Path $TestDrive 'missing-desktop.exe') `
                -GatewayArtifactPath (Join-Path $TestDrive 'missing-gateway.exe') `
                -GatewayInstallRoot (Join-Path $TestDrive 'gateway') `
                -CoreInstallPrefix (Join-Path $TestDrive 'core-prefix') `
                -BackupRoot (Join-Path $TestDrive 'backups') -Catalog $catalog `
                -DesktopExecutablePath (Join-Path $TestDrive 'override\missing-desktop.exe')
        } | Should -Throw '*Refusing a downgrade*'
        Test-Path -LiteralPath (Join-Path $TestDrive '.dsh') | Should -Be $false
        Test-Path -LiteralPath (Join-Path $TestDrive 'backups') | Should -Be $false
    }

    It 'rejects every Core prefix overlap before mutation' {
        $base = Join-Path $TestDrive 'prefix-isolation'
        $arguments = @{
            Lock = $lock
            DshHome = Join-Path $base 'dsh-home'
            BackupRoot = Join-Path $base 'backups'
            HarnessSourceRoot = Join-Path $base 'source-core'
            ProviderSourceRoot = Join-Path $base 'source-provider'
            NpmGlobalRoot = Join-Path $base 'global\node_modules'
            DesktopArtifactPath = Join-Path $base 'artifacts\desktop.exe'
            GatewayArtifactPath = Join-Path $base 'artifacts\gateway.exe'
            GatewayInstallRoot = Join-Path $base 'gateway-install'
            DesktopExecutablePath = Join-Path $base 'desktop\deepseek-harness-desktop.exe'
        }
        (Assert-CoreInstallPrefixIsolation @arguments -CoreInstallPrefix (Join-Path $base 'core-prefix')).valid |
            Should -Be $true

        $overlaps = @(
            $arguments.DshHome,
            (Split-Path -Parent $arguments.DshHome),
            (Join-Path $arguments.DshHome 'nested'),
            $arguments.BackupRoot,
            $arguments.HarnessSourceRoot,
            $arguments.ProviderSourceRoot,
            $arguments.NpmGlobalRoot,
            (Split-Path -Parent $arguments.NpmGlobalRoot),
            $arguments.DesktopArtifactPath,
            $arguments.DesktopExecutablePath,
            (Split-Path -Parent $arguments.DesktopExecutablePath),
            (Join-Path (Split-Path -Parent $arguments.DesktopExecutablePath) 'resources\node_modules'),
            (Join-Path $env:LOCALAPPDATA 'Deepseek Harness Desktop'),
            (Join-Path $env:LOCALAPPDATA 'Deepseek Harness Desktop\resources\node_modules')
        )
        foreach ($candidate in $overlaps) {
            {
                Assert-CoreInstallPrefixIsolation @arguments -CoreInstallPrefix $candidate
            } | Should -Throw '*CoreInstallPrefix must not overlap*'
        }
        Test-Path -LiteralPath $base | Should -Be $false
    }

    It 'rejects a Core prefix beneath a junction alias to a protected root' {
        $base = Join-Path $TestDrive 'prefix-junction'
        $protected = Join-Path $base 'protected'
        $aliasParent = Join-Path $base 'aliases'
        $alias = Join-Path $aliasParent 'protected-alias'
        New-Item -ItemType Directory -Path $protected, $aliasParent -Force | Out-Null
        try {
            New-Item -ItemType Junction -Path $alias -Target $protected -ErrorAction Stop | Out-Null
        } catch {
            Set-ItResult -Skipped -Because "Junction creation is unavailable: $($_.Exception.Message)"
            return
        }
        $arguments = @{
            Lock = $lock
            CoreInstallPrefix = Join-Path $alias 'core'
            DshHome = $protected
            BackupRoot = Join-Path $base 'backups'
            HarnessSourceRoot = Join-Path $base 'source-core'
            ProviderSourceRoot = Join-Path $base 'source-provider'
            NpmGlobalRoot = Join-Path $base 'global\node_modules'
            DesktopArtifactPath = Join-Path $base 'desktop.exe'
            GatewayArtifactPath = Join-Path $base 'gateway.exe'
            GatewayInstallRoot = Join-Path $base 'gateway-install'
        }
        {
            Assert-CoreInstallPrefixIsolation @arguments
        } | Should -Throw '*must not use reparse-point path*'
    }

    It 'rejects a protected DSH home beneath a junction alias' {
        $base = Join-Path $TestDrive 'protected-junction'
        $target = Join-Path $base 'target'
        $aliasParent = Join-Path $base 'aliases'
        $alias = Join-Path $aliasParent 'dsh-home'
        New-Item -ItemType Directory -Path $target, $aliasParent -Force | Out-Null
        try {
            New-Item -ItemType Junction -Path $alias -Target $target -ErrorAction Stop | Out-Null
        } catch {
            Set-ItResult -Skipped -Because "Junction creation is unavailable: $($_.Exception.Message)"
            return
        }
        $arguments = @{
            Lock = $lock
            CoreInstallPrefix = Join-Path $base 'core'
            DshHome = $alias
            BackupRoot = Join-Path $base 'backups'
            HarnessSourceRoot = Join-Path $base 'source-core'
            ProviderSourceRoot = Join-Path $base 'source-provider'
            NpmGlobalRoot = Join-Path $base 'global\node_modules'
            DesktopArtifactPath = Join-Path $base 'desktop.exe'
            GatewayArtifactPath = Join-Path $base 'gateway.exe'
            GatewayInstallRoot = Join-Path $base 'gateway-install'
        }
        {
            Assert-CoreInstallPrefixIsolation @arguments
        } | Should -Throw '*must not use reparse-point path*'
    }

    It 'rejects an explicit Desktop root beneath a junction alias' {
        $base = Join-Path $TestDrive 'desktop-junction'
        $target = Join-Path $base 'installed-desktop'
        $aliasParent = Join-Path $base 'aliases'
        $alias = Join-Path $aliasParent 'desktop'
        New-Item -ItemType Directory -Path $target, $aliasParent -Force | Out-Null
        try {
            New-Item -ItemType Junction -Path $alias -Target $target -ErrorAction Stop | Out-Null
        } catch {
            Set-ItResult -Skipped -Because "Junction creation is unavailable: $($_.Exception.Message)"
            return
        }
        $arguments = @{
            Lock = $lock
            CoreInstallPrefix = Join-Path $base 'core'
            DshHome = Join-Path $base 'dsh-home'
            BackupRoot = Join-Path $base 'backups'
            HarnessSourceRoot = Join-Path $base 'source-core'
            ProviderSourceRoot = Join-Path $base 'source-provider'
            NpmGlobalRoot = Join-Path $base 'global\node_modules'
            DesktopArtifactPath = Join-Path $base 'desktop.exe'
            GatewayArtifactPath = Join-Path $base 'gateway.exe'
            GatewayInstallRoot = Join-Path $base 'gateway-install'
            DesktopExecutablePath = Join-Path $alias 'deepseek-harness-desktop.exe'
        }
        {
            Assert-CoreInstallPrefixIsolation @arguments
        } | Should -Throw '*must not use reparse-point path*'
    }

    It 'rejects a Desktop internal plugin junction targeting the Core prefix' {
        $base = Join-Path $TestDrive 'desktop-plugin-alias'
        $corePrefix = Join-Path $base 'core'
        $desktopRoot = Join-Path $base 'desktop'
        $pluginRoot = Join-Path $desktopRoot 'resources\node_modules'
        New-Item -ItemType Directory -Path $corePrefix, $pluginRoot -Force | Out-Null
        New-Item -ItemType Junction -Path (Join-Path $pluginRoot 'dsh-tauri') `
            -Target $corePrefix -ErrorAction Stop | Out-Null
        $arguments = @{
            Lock = $lock
            CoreInstallPrefix = $corePrefix
            DshHome = Join-Path $base 'dsh-home'
            BackupRoot = Join-Path $base 'backups'
            HarnessSourceRoot = Join-Path $base 'source-core'
            ProviderSourceRoot = Join-Path $base 'source-provider'
            NpmGlobalRoot = Join-Path $base 'global\node_modules'
            DesktopArtifactPath = Join-Path $base 'desktop.exe'
            GatewayArtifactPath = Join-Path $base 'gateway.exe'
            GatewayInstallRoot = Join-Path $base 'gateway-install'
            DesktopExecutablePath = Join-Path $desktopRoot 'deepseek-harness-desktop.exe'
        }
        {
            Assert-CoreInstallPrefixIsolation @arguments
        } | Should -Throw '*must not use reparse-point path*'
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
        $artifact = Join-Path $TestDrive 'dsh-github-copilot-0.3.0-cloga.8.tgz'
        Set-Content -LiteralPath $artifact -Value 'fixture artifact' -Encoding UTF8

        Set-WindowsCopilotProfile -Lock $lock -DshHome $dshHome -NpmGlobalRoot $globalRoot `
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
}
