Import-Module (Join-Path $PSScriptRoot '..\tools\DshRuntimeSchema.psm1') -Force

Describe 'DSH official Desktop runtime schema' {
    BeforeAll {
        function Get-TestSha256 {
            param([Parameter(Mandatory)][string]$Path)
            (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
        }

        function Get-TestTreeState {
            param([Parameter(Mandatory)][string]$Root)
            $prefix = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
            $entries = @(Get-ChildItem -LiteralPath $prefix -Recurse -File -Force | ForEach-Object {
                [pscustomobject]@{
                    relativePath = $_.FullName.Substring($prefix.Length).Replace('\', '/')
                    sha256 = Get-TestSha256 -Path $_.FullName
                    size = [int64]$_.Length
                }
            } | Sort-Object relativePath)
            $text = ($entries | ForEach-Object {
                [string]$_.relativePath + "`t" + [string]$_.sha256
            }) -join "`n"
            $sha = [Security.Cryptography.SHA256]::Create()
            try {
                $treeSha256 = ([BitConverter]::ToString(
                    $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))
                )).Replace('-', '').ToLowerInvariant()
            } finally {
                $sha.Dispose()
            }
            [pscustomobject]@{
                fileCount = $entries.Count
                totalBytes = [int64](($entries | Measure-Object size -Sum).Sum)
                treeSha256 = $treeSha256
            }
        }

        function New-OfficialRuntimeFixture {
            param([Parameter(Mandatory)][string]$Root)
            $packageRoot = Join-Path $Root 'node_modules\@deepseek-ai\dsh'
            $toolsRoot = Join-Path $Root 'node_modules\@deepseek-ai\dsh-tools\lib'
            $pwshRoot = Join-Path $Root 'node_modules\@deepseek-ai\dsh-tool-pwsh\lib'
            $sandboxRoot = Join-Path $Root 'node_modules\@deepseek-ai\dsh-sandbox\lib'
            New-Item -ItemType Directory -Path (Join-Path $packageRoot 'lib'), $toolsRoot, $pwshRoot, $sandboxRoot -Force |
                Out-Null
            '{"name":"deepseek-harness-pkg","version":"0.1.2-alpha.5"}' |
                Set-Content -LiteralPath (Join-Path $Root 'package.json') -Encoding UTF8 -NoNewline
            '{"name":"@deepseek-ai/dsh","version":"0.1.2-rc.1","bin":{"dsh":"lib/bin.js"}}' |
                Set-Content -LiteralPath (Join-Path $packageRoot 'package.json') -Encoding UTF8 -NoNewline
            'entrypoint' | Set-Content -LiteralPath (Join-Path $packageRoot 'lib\bin.js') -Encoding UTF8 -NoNewline
            'tools-schema' | Set-Content -LiteralPath (Join-Path $toolsRoot 'index.js') -Encoding UTF8 -NoNewline
            'pwsh-schema' | Set-Content -LiteralPath (Join-Path $pwshRoot 'index.js') -Encoding UTF8 -NoNewline
            'sandbox' | Set-Content -LiteralPath (Join-Path $sandboxRoot 'index.js') -Encoding UTF8 -NoNewline

            $requiredFiles = @(
                'node_modules\@deepseek-ai\dsh-tools\lib\index.js',
                'node_modules\@deepseek-ai\dsh-tool-pwsh\lib\index.js',
                'node_modules\@deepseek-ai\dsh-sandbox\lib\index.js'
            ) | ForEach-Object {
                $path = Join-Path $Root $_
                [pscustomobject]@{
                    path = $_
                    size = (Get-Item -LiteralPath $path).Length
                    sha256 = Get-TestSha256 -Path $path
                }
            }
            $entrypoint = Join-Path $packageRoot 'lib\bin.js'
            $tree = Get-TestTreeState -Root $Root
            return [pscustomobject]@{
                packageRoot = $packageRoot
                contract = [pscustomobject]@{
                    root = $Root
                    wrapper = [pscustomobject]@{
                        name = 'deepseek-harness-pkg'
                        version = '0.1.2-alpha.5'
                        manifest = 'package.json'
                        manifestSha256 = Get-TestSha256 -Path (Join-Path $Root 'package.json')
                        fileCount = $tree.fileCount
                        totalBytes = $tree.totalBytes
                        treeSha256 = $tree.treeSha256
                        reparseDirectoryCount = 0
                    }
                    package = [pscustomobject]@{
                        name = '@deepseek-ai/dsh'
                        version = '0.1.2-rc.1'
                        manifest = 'node_modules\@deepseek-ai\dsh\package.json'
                        entrypoint = 'node_modules\@deepseek-ai\dsh\lib\bin.js'
                        entrypointSize = (Get-Item -LiteralPath $entrypoint).Length
                        entrypointSha256 = Get-TestSha256 -Path $entrypoint
                    }
                    requiredBuiltFiles = @($requiredFiles)
                }
            }
        }
    }

    It 'accepts the exact physical official runtime bytes' {
        $fixture = New-OfficialRuntimeFixture -Root (Join-Path $TestDrive 'official')
        $result = Test-DshRuntimeSchemaState -Contract $fixture.contract `
            -RequiredPackageRoot $fixture.packageRoot
        $result.valid | Should -Be $true
        $result.status | Should -Be 'desktop-official-runtime-schema-verified'
        $result.process.status | Should -Be 'not-requested'
    }

    It 'rejects wrapper, entrypoint, and schema byte drift' {
        foreach ($drift in @('wrapper', 'entrypoint', 'schema')) {
            $fixture = New-OfficialRuntimeFixture -Root (Join-Path $TestDrive $drift)
            if ($drift -eq 'wrapper') {
                '{"name":"deepseek-harness-pkg","version":"0.1.2-alpha.4"}' |
                    Set-Content -LiteralPath (Join-Path $fixture.contract.root 'package.json') -Encoding UTF8 -NoNewline
            } elseif ($drift -eq 'entrypoint') {
                Add-Content -LiteralPath (Join-Path $fixture.packageRoot 'lib\bin.js') -Value 'tamper'
            } else {
                Add-Content -LiteralPath (
                    Join-Path $fixture.contract.root 'node_modules\@deepseek-ai\dsh-tool-pwsh\lib\index.js'
                ) -Value 'tamper'
            }
            (Test-DshRuntimeSchemaState -Contract $fixture.contract `
                -RequiredPackageRoot $fixture.packageRoot).valid | Should -Be $false
        }
    }

    It 'rejects a package root outside the locked Desktop-managed runtime' {
        $fixture = New-OfficialRuntimeFixture -Root (Join-Path $TestDrive 'official-root')
        $other = New-OfficialRuntimeFixture -Root (Join-Path $TestDrive 'other-root')
        $result = Test-DshRuntimeSchemaState -Contract $fixture.contract `
            -RequiredPackageRoot $other.packageRoot
        $result.valid | Should -Be $false
        @($result.reasons) | Should -Contain 'runtime-package-root-mismatch'
    }

    It 'rejects any reparse directory inside the managed wrapper' {
        $fixture = New-OfficialRuntimeFixture -Root (Join-Path $TestDrive 'reparse-root')
        $target = Join-Path $TestDrive 'reparse-target'
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        New-Item -ItemType Junction -Path (
            Join-Path $fixture.contract.root 'node_modules\unexpected-link'
        ) -Target $target | Out-Null
        $result = Test-DshRuntimeSchemaState -Contract $fixture.contract `
            -RequiredPackageRoot $fixture.packageRoot
        $result.valid | Should -Be $false
        @($result.reasons) | Should -Contain 'runtime-wrapper-tree-mismatch'
    }
}
