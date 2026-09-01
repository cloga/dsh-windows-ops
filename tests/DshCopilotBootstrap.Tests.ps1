Import-Module (Join-Path $PSScriptRoot '..\tools\DshCopilotBootstrap.psm1') -Force

Describe 'DSH Copilot bootstrap' {
    BeforeEach {
        $script:root = Join-Path $TestDrive 'dsh'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
    }

    BeforeAll {
    function Get-FixtureSha256 {
        param([Parameter(Mandatory)][string]$Text)
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
            return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
        } finally {
            $sha.Dispose()
        }
    }

    function New-DshReceiptFixture {
        param(
            $SchemaVersion = 1,
            [string]$RepositoryUrl = 'https://github.com/cloga/deepseek-harness.git',
            [string]$PackageVersion = '1.2.3',
            [string]$InstalledVersion = '1.2.3',
            [string]$CommitSha = '0123456789abcdef0123456789abcdef01234567',
            [string]$PackageSha256 = ('a' * 64),
            [string]$ReceiptCliPath,
            [string]$ReleaseManifestSha256,
            [string]$DesktopShim = "@ECHO off`r`n@CALL `"%~dp0node_modules\.bin\dsh.cmd`" %*"
        )
        $prefix = Join-Path $root ([guid]::NewGuid().ToString('N'))
        $package = Join-Path $prefix 'node_modules\@deepseek-ai\dsh'
        $canonicalCli = Join-Path $prefix 'node_modules\.bin\dsh.cmd'
        $desktopCli = Join-Path $prefix 'dsh.cmd'
        New-Item -ItemType Directory -Path $package, (Split-Path $canonicalCli -Parent) -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $package 'package.json') -Encoding UTF8 -Value (
            [ordered]@{
                name = '@deepseek-ai/dsh'
                version = $InstalledVersion
                bin = [ordered]@{ dsh = 'lib/bin.js' }
                repository = [ordered]@{ url = 'git+https://github.com/deepseek-ai/deepseek-harness.git' }
            } | ConvertTo-Json -Compress
        )
        Set-Content -LiteralPath $canonicalCli -Value '@echo off' -Encoding ASCII
        Set-Content -LiteralPath $desktopCli -Value $DesktopShim -Encoding ASCII
        New-Item -ItemType Directory -Path (Join-Path $package 'lib') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $package 'lib\bin.js') -Value 'process.exit(0)' -Encoding UTF8
        $packages = @([ordered]@{
            name = '@deepseek-ai/dsh'
            version = $PackageVersion
            filename = "deepseek-ai-dsh-$PackageVersion.tgz"
            sha256 = $PackageSha256
            files = 10
        })
        $manifestJson = ConvertTo-Json -InputObject $packages -Compress -Depth 4
        if (-not $ReleaseManifestSha256) { $ReleaseManifestSha256 = Get-FixtureSha256 -Text $manifestJson }
        $installedFiles = @(
            [ordered]@{
                role = 'root-shim'
                path = 'dsh.cmd'
                sha256 = (Get-FileHash -LiteralPath $desktopCli -Algorithm SHA256).Hash.ToLowerInvariant()
            },
            [ordered]@{
                role = 'npm-shim'
                path = 'node_modules\.bin\dsh.cmd'
                sha256 = (Get-FileHash -LiteralPath $canonicalCli -Algorithm SHA256).Hash.ToLowerInvariant()
            },
            [ordered]@{
                role = 'entrypoint'
                path = 'node_modules\@deepseek-ai\dsh\lib\bin.js'
                sha256 = (Get-FileHash -LiteralPath (Join-Path $package 'lib\bin.js') -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        )
        $receipt = [ordered]@{
            schemaVersion = $SchemaVersion
            repositoryUrl = $RepositoryUrl
            commitSha = $CommitSha
            packageName = '@deepseek-ai/dsh'
            packageVersion = $PackageVersion
            releaseManifestSha256 = $ReleaseManifestSha256
            cliPath = $(if ($ReceiptCliPath) { $ReceiptCliPath } else { $desktopCli })
            packages = $packages
            installedFiles = $installedFiles
        }
        Set-Content -LiteralPath (Join-Path $prefix 'dsh-local-install.json') -Encoding UTF8 -Value (
            $receipt | ConvertTo-Json -Depth 5
        )
        return [pscustomobject]@{
            prefix = $prefix
            packageRoot = $package
            canonicalCli = $canonicalCli
            desktopCli = $desktopCli
            receiptPath = Join-Path $prefix 'dsh-local-install.json'
        }
    }

    function Test-DshCliResolutionThrows {
        param(
            [Parameter(Mandatory)][string]$CliPath,
            [string[]]$GlobalRoots
        )
        try {
            Resolve-DshCliInfo -DshCliPath $CliPath -GlobalRoots $GlobalRoots | Out-Null
            return $false
        } catch {
            return $true
        }
    }
    }

    It 'does not write managed settings during dry-run' {
        $path = Join-Path $root 'settings.yaml'
        Set-Content -LiteralPath $path -Value "# existing`n" -Encoding UTF8
        $before = Get-Content -LiteralPath $path -Raw
        $result = Set-DshCopilotSettings -Path $path -BaseUrl 'http://127.0.0.1:7777/v1' `
            -Model 'fixture-model' -VisionCapable $true -DryRun
        $result.status | Should -Be 'would-change'
        Get-Content -LiteralPath $path -Raw | Should -Be $before
    }

    It 'is idempotent for settings and profile patches' {
        $settings = Join-Path $root 'settings.yaml'
        $patch = Join-Path $root 'cordis.patch.yml'
        Set-Content -LiteralPath $patch -Value "[]`n" -Encoding UTF8
        (Set-DshCopilotSettings -Path $settings -BaseUrl 'http://127.0.0.1:7777/v1' `
            -Model 'fixture-model' -VisionCapable $true).status | Should -Be 'changed'
        (Set-DshCopilotSettings -Path $settings -BaseUrl 'http://127.0.0.1:7777/v1' `
            -Model 'fixture-model' -VisionCapable $true).status | Should -Be 'unchanged'
        (Set-DshCopilotProfilePatch -Path $patch).status | Should -Be 'changed'
        (Set-DshCopilotProfilePatch -Path $patch).status | Should -Be 'unchanged'
    }

    It 'refuses duplicate managed blocks' {
        $path = Join-Path $root 'settings.yaml'
        $block = @'
# dsh-windows-ops: copilot settings begin
# dsh-windows-ops: copilot settings end
# dsh-windows-ops: copilot settings begin
# dsh-windows-ops: copilot settings end
'@
        Set-Content -LiteralPath $path -Value $block -Encoding UTF8
        $threw = $false
        try {
            Set-DshCopilotSettings -Path $path -BaseUrl 'http://127.0.0.1:7777/v1' `
                -Model 'fixture-model' -VisionCapable $true | Out-Null
        } catch {
            $threw = $true
        }
        $threw | Should -Be $true
    }

    It 'refuses unmanaged conflicts outside an existing managed block' {
        $path = Join-Path $root 'cordis.patch.yml'
        Set-Content -LiteralPath $path -Value "[]`n" -Encoding UTF8
        Set-DshCopilotProfilePatch -Path $path | Out-Null
        Add-Content -LiteralPath $path -Value "`n- id: web`n  config:`n    searchProvider: other"
        $threw = $false
        try {
            Set-DshCopilotProfilePatch -Path $path | Out-Null
        } catch {
            $threw = $true
        }
        $threw | Should -Be $true
    }

    It 'selects hosted Search without disabling the web host or tool' {
        $path = Join-Path $root 'cordis.patch.yml'
        Set-Content -LiteralPath $path -Value "[]`n" -Encoding UTF8
        Set-DshCopilotProfilePatch -Path $path | Out-Null
        $text = Get-Content -LiteralPath $path -Raw
        $text | Should -Match '(?s)- id: web\s+config:\s+searchProvider: github-copilot-hosted'
        $text | Should -Not -Match '(?m)^\s*-\s+id:\s+web-search-deepseek\s*$'
        $text | Should -Not -Match '(?m)^\s*-\s+id:\s+tool-web\s*$'
        $text | Should -Match 'providers: \[github-copilot\]'
    }

    It 'accepts the deployed @ECHO and @CALL Desktop shim with a root receipt' {
        $fixture = New-DshReceiptFixture
        $info = Resolve-DshCliInfo -DshCliPath $fixture.desktopCli
        $info.cliPath | Should -Be ([IO.Path]::GetFullPath($fixture.desktopCli))
        $info.canonicalCliPath | Should -Be ([IO.Path]::GetFullPath($fixture.canonicalCli))
        $info.packageRoot | Should -Be ([IO.Path]::GetFullPath($fixture.packageRoot))
        $info.repository | Should -Be 'cloga/deepseek-harness'
        $info.version | Should -Be '1.2.3'
        $info.packageCount | Should -Be 1
        $info.installedFileCount | Should -Be 3
    }

    It 'accepts the canonical user input alias with a root receipt' {
        $fixture = New-DshReceiptFixture
        (Resolve-DshCliInfo -DshCliPath $fixture.canonicalCli).canonicalCliPath |
            Should -Be ([IO.Path]::GetFullPath($fixture.canonicalCli))
    }

    It 'rejects malformed Desktop shim forwarding' {
        $fixture = New-DshReceiptFixture -DesktopShim "@echo off`r`n@call `"%~dp0other\dsh.cmd`" %*"
        Test-DshCliResolutionThrows -CliPath $fixture.desktopCli | Should -Be $true

        $fixture = New-DshReceiptFixture -DesktopShim "@echo off`r`n@call `"%~dp0node_modules\.bin\dsh.cmd`" --unsafe %*"
        Test-DshCliResolutionThrows -CliPath $fixture.canonicalCli | Should -Be $true

        $fixture = New-DshReceiptFixture -DesktopShim " @echo off`r`n@call `"%~dp0node_modules\.bin\dsh.cmd`" %*"
        Test-DshCliResolutionThrows -CliPath $fixture.desktopCli | Should -Be $true
    }

    It 'rejects a receipt that records the canonical alias' {
        $fixture = New-DshReceiptFixture
        $receipt = Get-Content -LiteralPath $fixture.receiptPath -Raw | ConvertFrom-Json
        $receipt.cliPath = $fixture.canonicalCli
        Set-Content -LiteralPath $fixture.receiptPath -Encoding UTF8 -Value (
            $receipt | ConvertTo-Json -Depth 5
        )
        Test-DshCliResolutionThrows -CliPath $fixture.canonicalCli | Should -Be $true
    }

    It 'rejects an unrelated dsh path' {
        $fixture = New-DshReceiptFixture
        $unrelatedCli = Join-Path $fixture.prefix 'other\dsh.cmd'
        New-Item -ItemType Directory -Path (Split-Path $unrelatedCli -Parent) -Force | Out-Null
        Set-Content -LiteralPath $unrelatedCli -Value '@echo off' -Encoding ASCII
        Test-DshCliResolutionThrows -CliPath $unrelatedCli | Should -Be $true
    }

    It 'maps an implicitly discovered npm PowerShell shim to dsh.cmd' {
        $fixture = New-DshReceiptFixture
        Set-Content -LiteralPath (Join-Path $fixture.prefix 'dsh.ps1') -Value 'exit 1' -Encoding ASCII
        $previousPath = $env:PATH
        $previousCli = $env:DSH_CLI_PATH
        try {
            $env:PATH = $fixture.prefix + [IO.Path]::PathSeparator + $previousPath
            $env:DSH_CLI_PATH = $null
            (Resolve-DshCliInfo).cliPath | Should -Be ([IO.Path]::GetFullPath($fixture.desktopCli))
        } finally {
            $env:PATH = $previousPath
            $env:DSH_CLI_PATH = $previousCli
        }
    }

    It 'rejects a receipt for the wrong repository' {
        $fixture = New-DshReceiptFixture -RepositoryUrl 'https://github.com/deepseek-ai/deepseek-harness.git'
        Test-DshCliResolutionThrows -CliPath $fixture.canonicalCli | Should -Be $true
    }

    It 'rejects an unsupported receipt schema' {
        $fixture = New-DshReceiptFixture -SchemaVersion 2
        Test-DshCliResolutionThrows -CliPath $fixture.canonicalCli | Should -Be $true
        $fixture = New-DshReceiptFixture -SchemaVersion '1'
        Test-DshCliResolutionThrows -CliPath $fixture.canonicalCli | Should -Be $true
        $fixture = New-DshReceiptFixture -SchemaVersion $true
        Test-DshCliResolutionThrows -CliPath $fixture.canonicalCli | Should -Be $true
    }

    It 'rejects a receipt version that differs from the installed package' {
        $fixture = New-DshReceiptFixture -PackageVersion '1.2.4'
        Test-DshCliResolutionThrows -CliPath $fixture.canonicalCli | Should -Be $true
    }

    It 'rejects a receipt CLI outside the installed prefix' {
        $fixture = New-DshReceiptFixture -ReceiptCliPath (Join-Path $root 'other\dsh.cmd')
        Test-DshCliResolutionThrows -CliPath $fixture.canonicalCli | Should -Be $true
    }

    It 'rejects malformed commit and release manifest SHAs' {
        $fixture = New-DshReceiptFixture -CommitSha 'short'
        Test-DshCliResolutionThrows -CliPath $fixture.canonicalCli | Should -Be $true
        $fixture = New-DshReceiptFixture -ReleaseManifestSha256 'not-a-sha'
        Test-DshCliResolutionThrows -CliPath $fixture.canonicalCli | Should -Be $true
        $fixture = New-DshReceiptFixture -PackageSha256 'not-a-sha'
        Test-DshCliResolutionThrows -CliPath $fixture.canonicalCli | Should -Be $true
    }

    It 'rejects a release manifest hash that is not linked to its package list' {
        $fixture = New-DshReceiptFixture -ReleaseManifestSha256 ('b' * 64)
        Test-DshCliResolutionThrows -CliPath $fixture.canonicalCli | Should -Be $true
    }

    It 'rejects a missing receipt' {
        $fixture = New-DshReceiptFixture
        Remove-Item -LiteralPath $fixture.receiptPath
        Test-DshCliResolutionThrows -CliPath $fixture.canonicalCli | Should -Be $true
    }

    It 'rejects a receipt without installed executable hashes' {
        $fixture = New-DshReceiptFixture
        $receipt = Get-Content -LiteralPath $fixture.receiptPath -Raw | ConvertFrom-Json
        $receipt.PSObject.Properties.Remove('installedFiles')
        $receipt | ConvertTo-Json -Depth 6 |
            Set-Content -LiteralPath $fixture.receiptPath -Encoding UTF8
        {
            Resolve-DshCliInfo -DshCliPath $fixture.desktopCli
        } | Should -Throw '*installed-bytes-unattested*'
    }

    It 'rejects tampered installed entrypoint and npm shim hashes' {
        foreach ($relativePath in @(
            'lib\bin.js',
            '..\..\.bin\dsh.cmd'
        )) {
            $fixture = New-DshReceiptFixture
            $target = Join-Path $fixture.packageRoot $relativePath
            Add-Content -LiteralPath $target -Value 'tampered' -Encoding ASCII
            {
                Resolve-DshCliInfo -DshCliPath $fixture.desktopCli
            } | Should -Throw '*installed-bytes-mismatch*'
        }
    }

    It 'rejects a byte-changed root shim that still has the valid forwarding shape' {
        $fixture = New-DshReceiptFixture
        Set-Content -LiteralPath $fixture.desktopCli -Encoding ASCII -NoNewline `
            -Value "@echo off`r`n@CALL `"%~dp0node_modules\.bin\dsh.cmd`" %*"
        {
            Resolve-DshCliInfo -DshCliPath $fixture.desktopCli
        } | Should -Throw '*installed-bytes-mismatch*'
    }

    It 'does not fall back to trusted-looking package metadata' {
        $fixture = New-DshReceiptFixture
        Remove-Item -LiteralPath $fixture.receiptPath
        Test-DshCliResolutionThrows -CliPath $fixture.canonicalCli -GlobalRoots @($fixture.packageRoot) |
            Should -Be $true
    }

    It 'validates the current local Core receipt when installed' {
        $desktopCli = 'C:\.tools\dsh-cloga\dsh.cmd'
        if (Test-Path -LiteralPath $desktopCli -PathType Leaf) {
            $receiptPath = Join-Path (Split-Path -Parent $desktopCli) 'dsh-local-install.json'
            $receipt = if (Test-Path -LiteralPath $receiptPath -PathType Leaf) {
                Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
            } else { $null }
            if (-not $receipt -or -not $receipt.PSObject.Properties['installedFiles']) {
                Set-ItResult -Skipped -Because 'The local Core receipt predates installed-file attestation.'
                return
            }
            $info = Resolve-DshCliInfo -DshCliPath $desktopCli
            $info.repository | Should -Be 'cloga/deepseek-harness'
            $info.packageCount | Should -BeGreaterThan 1
        }
    }

    It 'requires explicit catalog metadata for vision' {
        $catalog = [pscustomobject]@{ data = @(
            [pscustomobject]@{ id = 'vision-by-name-only' },
            [pscustomobject]@{ id = 'actual-image'; input = @('text', 'image') }
        ) }
        (Get-DshCatalogModel -Catalog $catalog -Model 'vision-by-name-only').visionCapable | Should -Be $false
        (Get-DshCatalogModel -Catalog $catalog -Model 'actual-image').visionCapable | Should -Be $true
    }

    It 'accepts only an active Desktop descendant using the local package' {
        $cli = [pscustomobject]@{
            cliPath = 'C:\npm\dsh.cmd'
            packageRoot = 'C:\npm\node_modules\@deepseek-ai\dsh'
            entryPath = 'C:\npm\node_modules\@deepseek-ai\dsh\lib\bin.js'
        }
        $processes = @(
            [pscustomobject]@{ ProcessId = 10; ParentProcessId = 1; Name = 'deepseek-harness-desktop.exe'; CommandLine = 'desktop' },
            [pscustomobject]@{ ProcessId = 11; ParentProcessId = 10; Name = 'node.exe'; CommandLine = 'node C:\npm\node_modules\@deepseek-ai\dsh\lib\bin.js web' }
        )
        (Test-DshActiveDesktopCore -CliInfo $cli -Processes $processes).healthy | Should -Be $true
        $processes[1].Name = 'cmd.exe'
        $processes[1].CommandLine = 'cmd.exe /c echo C:\npm\node_modules\@deepseek-ai\dsh\lib\bin.js'
        { Test-DshActiveDesktopCore -CliInfo $cli -Processes $processes } |
            Should -Throw '*not running the selected local dsh package*'
    }

    It 'refuses a renderer without the exact SlotOutlet marker' {
        $package = Join-Path $root 'package'
        $renderer = Join-Path $package 'node_modules\@deepseek-ai\dsh-client-ui-renderer\lib'
        $flat = Join-Path $root 'home\profiles\node_modules\@deepseek-ai\dsh-client-ui-renderer\lib'
        New-Item -ItemType Directory -Path $renderer -Force | Out-Null
        New-Item -ItemType Directory -Path $flat -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $renderer 'client.js') -Value 'exports.inject = inject;' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $flat 'client.js') -Value 'exports.inject = inject;' -Encoding UTF8
        $threw = $false
        try {
            Test-DshRendererCompatibility -PackageRoot $package -DshHome (Join-Path $root 'home') | Out-Null
        } catch {
            $threw = $true
        }
        $threw | Should -Be $true
    }

    It 'backs up and restores every tracked profile file' {
        $file = Join-Path $root 'settings.yaml'
        $state = Join-Path $root 'state'
        Set-Content -LiteralPath $file -Value 'before' -Encoding UTF8
        $backup = New-DshCopilotBackup -Paths @($file) -StateRoot $state
        Set-Content -LiteralPath $file -Value 'after' -Encoding UTF8
        $expected = @([pscustomobject]@{
            path = [IO.Path]::GetFullPath($file)
            exists = $true
            sha256 = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
        })
        Complete-DshCopilotBackup -StateRoot $state -OperationId $backup.operationId -ExpectedStates $expected | Out-Null
        Restore-DshCopilotBackup -StateRoot $state -OperationId $backup.operationId | Out-Null
        (Get-Content -LiteralPath $file -Raw).Trim() | Should -Be 'before'
    }

    It 'refuses rollback after a tracked file changes again' {
        $file = Join-Path $root 'settings.yaml'
        $state = Join-Path $root 'state'
        Set-Content -LiteralPath $file -Value 'before' -Encoding UTF8
        $backup = New-DshCopilotBackup -Paths @($file) -StateRoot $state
        Set-Content -LiteralPath $file -Value 'bootstrap' -Encoding UTF8
        $expected = @([pscustomobject]@{
            path = [IO.Path]::GetFullPath($file)
            exists = $true
            sha256 = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
        })
        Complete-DshCopilotBackup -StateRoot $state -OperationId $backup.operationId -ExpectedStates $expected | Out-Null
        Set-Content -LiteralPath $file -Value 'later-user-change' -Encoding UTF8
        $threw = $false
        try {
            Restore-DshCopilotBackup -StateRoot $state -OperationId $backup.operationId | Out-Null
        } catch {
            $threw = $true
        }
        $threw | Should -Be $true
        (Get-Content -LiteralPath $file -Raw).Trim() | Should -Be 'later-user-change'
    }

    It 'rejects the pre-fix sandbox contract under the required gate' {
        $package = Join-Path $root 'package'
        $sandbox = Join-Path $package 'node_modules\@deepseek-ai\dsh-sandbox\lib'
        $bash = Join-Path $package 'node_modules\@deepseek-ai\dsh-tool-bash\lib'
        $pwsh = Join-Path $package 'node_modules\@deepseek-ai\dsh-tool-pwsh\lib'
        New-Item -ItemType Directory -Path $sandbox, $bash, $pwsh -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $sandbox 'index.js') -Encoding UTF8 -Value @'
export async function approveEscalation(request, approval) {
  if (request.requestedMode === request.effectiveMode) throw new Error('not strictly wider')
  await approval.approver.request()
  return request.requestedMode
}
'@
        foreach ($tool in @(
            [pscustomobject]@{ root = $bash; name = 'bash' },
            [pscustomobject]@{ root = $pwsh; name = 'pwsh' }
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
        {
            Test-DshSandboxRegression -PackageRoot $package `
                -ProbeScript (Join-Path $PSScriptRoot '..\tools\dsh-sandbox-regression-probe.mjs') -Mode Require
        } | Should -Throw '*sandbox non-widening regression gate*'
    }

    It 'passes same narrower and wider sandbox behavior without lowering policy' {
        $package = Join-Path $root 'package'
        $sandbox = Join-Path $package 'node_modules\@deepseek-ai\dsh-sandbox\lib'
        $bash = Join-Path $package 'node_modules\@deepseek-ai\dsh-tool-bash\lib'
        $pwsh = Join-Path $package 'node_modules\@deepseek-ai\dsh-tool-pwsh\lib'
        New-Item -ItemType Directory -Path $sandbox, $bash, $pwsh -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $sandbox 'index.js') -Encoding UTF8 -Value @'
export async function approveEscalation(request, approval) {
  const rank = { 'read-only': 0, 'workspace-write': 1, 'danger-full-access': 2 }
  if (rank[request.requestedMode] <= rank[request.effectiveMode]) return request.effectiveMode
  await approval.approver.request()
  return request.requestedMode
}
'@
        foreach ($tool in @(
            [pscustomobject]@{ root = $bash; name = 'bash' },
            [pscustomobject]@{ root = $pwsh; name = 'pwsh' }
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
        $result = Test-DshSandboxRegression -PackageRoot $package `
            -ProbeScript (Join-Path $PSScriptRoot '..\tools\dsh-sandbox-regression-probe.mjs') -Mode Require
        $result.status | Should -Be 'passed'
        $result.effectiveMode | Should -Be 'danger-full-access'
        $result.sameAndNarrowerApprovalCalls | Should -Be 0
        $result.widerApprovalCalls | Should -Be 1
        @($result.tools).Count | Should -Be 2
        @($result.tools | Where-Object { $_.approvalCalls -ne 0 }).Count | Should -Be 0

        Set-Content -LiteralPath (Join-Path $pwsh 'index.js') -Encoding UTF8 -Value @'
const approveEscalation = () => {}
approveEscalation()
export const applyMissing = true
'@
        {
            Test-DshSandboxRegression -PackageRoot $package `
                -ProbeScript (Join-Path $PSScriptRoot '..\tools\dsh-sandbox-regression-probe.mjs') -Mode Require
        } | Should -Throw '*sandbox non-widening regression gate*'
    }
}
