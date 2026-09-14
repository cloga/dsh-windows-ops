BeforeAll {
    $repo = Split-Path $PSScriptRoot
    Import-Module (Join-Path $repo 'tools\WindowsCopilotDeployment.psm1') -Force

    function New-PresetTarget {
        param([string]$Root, [string]$Plugin = @'
export const Config = { dict: { prefix: {} }, '~standard': { version: 1, validate(value) {
  return typeof value?.prefix === 'string' ? { value } :
    { issues: [{ path: ['prefix'], message: 'SECRET prompt credential value' }] };
} } };
export function apply() { throw new Error('MUST NOT APPLY'); }
'@, [switch]$WithoutPersona)
        $modules = @{
            '@deepseek-ai/dsh' = 'export default {};'
            '@deepseek-ai/cordis-plugin-include' = 'export const entryListSchema = {};'
            'js-yaml' = @'
export function load(text, options) {
  if (!options.schema) throw Error('schema required');
  try { return JSON.parse(text); } catch {
    throw Object.assign(Error(text), { mark: { buffer: text } });
  }
}
'@
            'fixture-persona' = $Plugin
        }
        if ($WithoutPersona) { $modules.Remove('fixture-persona') }
        New-Item -ItemType Directory -Path $Root -Force | Out-Null
        '{"name":"deepseek-harness-pkg","version":"1.0.0"}' |
            Set-Content (Join-Path $Root 'package.json') -NoNewline
        foreach ($name in $modules.Keys) {
            $dir = Join-Path $Root ('node_modules\' + $name.Replace('/', '\'))
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            @{ name = $name; version = '1.0.0'; type = 'module'; main = 'index.js'; bin = @{ dsh = 'lib/bin.js' } } |
                ConvertTo-Json -Compress | Set-Content (Join-Path $dir 'package.json') -NoNewline
            $modules[$name] | Set-Content (Join-Path $dir 'index.js') -NoNewline
        }
        $entry = 'node_modules\@deepseek-ai\dsh\lib\bin.js'
        New-Item -ItemType Directory (Join-Path $Root 'node_modules\@deepseek-ai\dsh\lib') | Out-Null
        'throw Error("MUST NOT BOOT")' | Set-Content (Join-Path $Root $entry) -NoNewline
        $files = @(Get-ChildItem $Root -File -Recurse | ForEach-Object {
            [pscustomobject]@{
                path = $_.FullName.Substring($Root.Length + 1).Replace('\', '/')
                sha256 = (Get-FileHash $_.FullName).Hash.ToLowerInvariant()
                size = $_.Length
            }
        } | Sort-Object path)
        $text = ($files | ForEach-Object { $_.path + "`t" + $_.sha256 }) -join "`n"
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $tree = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))).Replace('-', '').ToLowerInvariant() }
        finally { $sha.Dispose() }
        $entryFile = $files | Where-Object path -eq $entry.Replace('\', '/')
        [pscustomobject]@{
            root = $Root
            wrapper = [pscustomobject]@{
                name = 'deepseek-harness-pkg'; version = '1.0.0'; manifest = 'package.json'
                manifestSha256 = (Get-FileHash (Join-Path $Root 'package.json')).Hash.ToLowerInvariant()
                fileCount = $files.Count; totalBytes = ($files | Measure-Object size -Sum).Sum
                treeSha256 = $tree; reparseDirectoryCount = 0
            }
            package = [pscustomobject]@{
                name = '@deepseek-ai/dsh'; version = '1.0.0'
                manifest = 'node_modules\@deepseek-ai\dsh\package.json'
                entrypoint = $entry; entrypointSize = $entryFile.size; entrypointSha256 = $entryFile.sha256
            }
            requiredBuiltFiles = @([pscustomobject]@{
                path = 'node_modules\@deepseek-ai\dsh\index.js'
                size = (Get-Item (Join-Path $Root 'node_modules\@deepseek-ai\dsh\index.js')).Length
                sha256 = (Get-FileHash (Join-Path $Root 'node_modules\@deepseek-ai\dsh\index.js')).Hash.ToLowerInvariant()
            })
        }
    }

    function Set-PresetRows {
        param([string]$HomePath, $Rows)
        $dir = Join-Path $HomePath '.agent-presets\sample'
        New-Item -ItemType Directory $dir -Force | Out-Null
        ConvertTo-Json -InputObject @($Rows) -Depth 30 |
            Set-Content (Join-Path $dir 'agent.cordis.yml') -NoNewline
    }
}

Describe 'Read-only target preset Config gate' {
    BeforeEach {
        $homePath = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $contract = New-PresetTarget (Join-Path $TestDrive ([guid]::NewGuid().ToString()))
    }

    It 'rejects legacy text against the target prefix schema and preserves all input bytes' {
        Set-PresetRows $homePath @(@{ name = 'fixture-persona'; config = @{ text = 'SECRET prompt credential value' } })
        $file = Join-Path $homePath '.agent-presets\sample\agent.cordis.yml'
        $before = (Get-FileHash $file).Hash
        $result = Test-DshUserPresetConfig -DshHome $homePath -Contract $contract
        $result.valid | Should -BeFalse
        $result.diagnostics.code | Should -Contain 'config-invalid'
        $result.diagnostics.key | Should -Contain '$.prefix'
        ($result | ConvertTo-Json -Depth 20) | Should -Not -Match 'SECRET|credential|mark|buffer'
        (Get-FileHash $file).Hash | Should -Be $before
    }

    It 'accepts equivalent prefix without applying plugins or booting Core' {
        Set-PresetRows $homePath @(@{ name = 'fixture-persona'; config = @{ prefix = 'SECRET' } })
        (Test-DshUserPresetConfig -DshHome $homePath -Contract $contract).valid | Should -BeTrue
    }

    It 'accepts UTF-8 console stdin preambles without changing Unicode request paths' {
        $encoding = [Console]::InputEncoding
        try {
            [Console]::InputEncoding = [Text.Encoding]::UTF8
            $unicodeHome = Join-Path $homePath ([string][char]0x6D4B + [char]0x8BD5)
            Set-PresetRows $unicodeHome @(@{ name = 'fixture-persona'; config = @{ prefix = 'valid' } })
            (Test-DshUserPresetConfig -DshHome $unicodeHome -Contract $contract).valid | Should -BeTrue
        } finally { [Console]::InputEncoding = $encoding }
    }

    It 'does not resolve a current or parent runtime in place of the target' {
        Set-PresetRows $homePath @(@{ name = 'fixture-persona'; config = @{ prefix = 'x' } })
        '{"name":"@deepseek-ai/dsh","version":"9.9.9"}' |
            Set-Content (Join-Path $contract.root 'node_modules\@deepseek-ai\dsh\package.json')
        $result = Test-DshUserPresetConfig -DshHome $homePath -Contract $contract
        $result.valid | Should -BeFalse
        $result.diagnostics.code | Should -Contain 'target-artifacts-unverified'
    }

    It 'requires exact target artifacts for an existing preset even on a fresh install' {
        Set-PresetRows $homePath @(@{ name = 'fixture-persona' })
        $contract.root = Join-Path $TestDrive 'absent-target'
        (Test-DshUserPresetConfig -DshHome $homePath -Contract $contract).diagnostics.code |
            Should -Contain 'target-artifacts-unavailable'
    }

    It 'reports no user presets without requiring a runtime or creating a home' {
        $contract.root = Join-Path $TestDrive 'absent-target'
        $result = Test-DshUserPresetConfig -DshHome $homePath -Contract $contract
        $result.valid | Should -BeTrue
        $result.status | Should -Be 'no-user-presets'
        Test-Path $homePath | Should -BeFalse
    }

    It 'fails on unresolved packages and rejects non-package specifiers' {
        foreach ($name in @('not-installed', '../escape.js', 'node:fs')) {
            Set-PresetRows $homePath @(@{ name = $name })
            (Test-DshUserPresetConfig -DshHome $homePath -Contract $contract).valid | Should -BeFalse
        }
    }

    It 'conservatively validates disabled predicates without evaluating them' {
        Set-PresetRows $homePath @(@{
            name = 'fixture-persona'; disabled = @{ __jsExpr = 'throw Error("SECRET")' }
            config = @{ text = 'legacy' }
        })
        (Test-DshUserPresetConfig -DshHome $homePath -Contract $contract).diagnostics.code |
            Should -Contain 'config-invalid'
    }

    It 'explicitly blocks dynamic config instead of evaluating it' {
        Set-PresetRows $homePath @(@{
            name = 'fixture-persona'; config = @{ prefix = @{ __jsExpr = 'process.env.SECRET' } }
        })
        (Test-DshUserPresetConfig -DshHome $homePath -Contract $contract).diagnostics.code |
            Should -Contain 'dynamic-config-unsupported'
    }

    It 'distinguishes absent schemas from malformed schemas using the published passthrough contract' {
        foreach ($variant in @(
            @{ code = 'export function apply() {}'; valid = $true },
            @{ code = 'export const Config = {}; export function apply() {}'; valid = $false },
            @{ code = 'export default function apply() {}; export const Config = {};'; valid = $false }
        )) {
            $target = New-PresetTarget (Join-Path $TestDrive ([guid]::NewGuid().ToString())) $variant.code
            Set-PresetRows $homePath @(@{ name = 'fixture-persona'; config = @{ arbitrary = 'SECRET' } })
            $result = Test-DshUserPresetConfig -DshHome $homePath -Contract $target
            $result.valid | Should -Be $variant.valid
        }
    }

    It 'redacts YAML parser exception buffers and import stdout and stderr' {
        Set-PresetRows $homePath @(@{ name = 'fixture-persona' })
        'SECRET: [malformed yaml' | Set-Content (Join-Path $homePath '.agent-presets\sample\agent.cordis.yml')
        $result = Test-DshUserPresetConfig -DshHome $homePath -Contract $contract
        $result.diagnostics.code | Should -Contain 'manifest-invalid'
        ($result | ConvertTo-Json -Depth 20) | Should -Not -Match 'SECRET|malformed|buffer'
        $target = New-PresetTarget (Join-Path $TestDrive 'noisy') @'
console.log('SECRET'); console.error('SECRET'); throw Error('SECRET');
'@
        Set-PresetRows $homePath @(@{ name = 'fixture-persona' })
        $result = Test-DshUserPresetConfig -DshHome $homePath -Contract $target
        $result.valid | Should -BeFalse
        ($result | ConvertTo-Json -Depth 20) | Should -Not -Match 'SECRET'
    }

    It 'bounds hanging schema imports and reports a stable timeout' {
        $target = New-PresetTarget (Join-Path $TestDrive 'hanging') 'while (true) {}'
        Set-PresetRows $homePath @(@{ name = 'fixture-persona' })
        $result = Test-DshUserPresetConfig -DshHome $homePath -Contract $target -TimeoutSeconds 2
        $result.valid | Should -BeFalse
        $result.diagnostics.code | Should -Contain 'validator-timeout'
    }

    It 'rejects schema exceptions, asynchronous and malformed validation results without exposing values' {
        foreach ($body in @(
            'throw Error(JSON.stringify(value))',
            'return Promise.resolve({ value })',
            'return {}',
            'return { issues: [] }'
        )) {
            $target = New-PresetTarget (Join-Path $TestDrive ([guid]::NewGuid().ToString())) @"
export function apply() {}
export const Config = { '~standard': { version: 1, validate(value) { $body } } };
"@
            Set-PresetRows $homePath @(@{ name = 'fixture-persona'; config = @{ prefix = 'SECRET' } })
            $result = Test-DshUserPresetConfig -DshHome $homePath -Contract $target
            $result.valid | Should -BeFalse
            ($result | ConvertTo-Json -Depth 20) | Should -Not -Match 'SECRET'
        }
    }

    It 'redacts arbitrary dictionary paths even when they look like identifiers' {
        $target = New-PresetTarget (Join-Path $TestDrive 'dictionary') @'
export function apply() {}
export const Config = { '~standard': { version: 1, validate() {
  return { issues: [{ path: ['SECRET'], message: 'SECRET' }] };
} } };
'@
        Set-PresetRows $homePath @(@{ name = 'fixture-persona'; config = @{ SECRET = 'SECRET' } })
        $result = Test-DshUserPresetConfig -DshHome $homePath -Contract $target
        $result.diagnostics.key | Should -Contain '$.*'
        ($result | ConvertTo-Json -Depth 20) | Should -Not -Match 'SECRET'
    }

    It 'uses the target export rather than a schema with the same package name in NODE_PATH' {
        $old = $env:NODE_PATH
        try {
            $current = New-PresetTarget (Join-Path $TestDrive 'current') @'
export function apply() {}
export const Config = { '~standard': { version: 1, validate(value) { return { value }; } } };
'@
            $env:NODE_PATH = Join-Path $current.root 'node_modules'
            Set-PresetRows $homePath @(@{ name = 'fixture-persona'; config = @{ text = 'legacy' } })
            (Test-DshUserPresetConfig -DshHome $homePath -Contract $contract).valid | Should -BeFalse
        } finally { $env:NODE_PATH = $old }
    }

    It 'does not expose parent credentials or Node preloads to schema imports' {
        $old = $env:PRESET_TEST_SECRET
        $options = $env:NODE_OPTIONS
        try {
            $env:PRESET_TEST_SECRET = 'SECRET'
            $env:NODE_OPTIONS = '--require=nonexistent-SECRET-preload'
            $target = New-PresetTarget (Join-Path $TestDrive 'environment') @'
if (process.env.PRESET_TEST_SECRET || process.env.NODE_OPTIONS) throw Error('SECRET');
export function apply() {}
'@
            Set-PresetRows $homePath @(@{ name = 'fixture-persona' })
            (Test-DshUserPresetConfig -DshHome $homePath -Contract $target).valid | Should -BeTrue
        } finally {
            $env:PRESET_TEST_SECRET = $old
            $env:NODE_OPTIONS = $options
        }
    }

    It 'rejects upward Node resolution to a package outside the target closure' {
        $parent = New-PresetTarget (Join-Path $TestDrive 'parent-runtime')
        $target = New-PresetTarget (Join-Path $parent.root 'target') -WithoutPersona
        Set-PresetRows $homePath @(@{ name = 'fixture-persona'; config = @{ prefix = 'valid' } })
        $result = Test-DshUserPresetConfig -DshHome $homePath -Contract $target
        $result.valid | Should -BeFalse
        $result.diagnostics.code | Should -Contain 'plugin-unresolvable-or-import-unsupported'
    }

    It 'rejects relative or drive-relative scope and oversized input before imports' {
        foreach ($path in @('.dsh', 'C:relative', 'C:\')) {
            (Test-DshUserPresetConfig -DshHome $path -Contract $contract).diagnostics.code |
                Should -Contain 'preset-scope-invalid'
        }
        Set-PresetRows $homePath @(@{ name = 'fixture-persona'; config = @{ prefix = ('x' * 1MB) } })
        (Test-DshUserPresetConfig -DshHome $homePath -Contract $contract).diagnostics.code |
            Should -Contain 'preset-scope-limit'
    }

    It 'denies plugin import writes and process or network activation' {
        foreach ($code in @(
            'import { writeFileSync } from "node:fs"; writeFileSync(new URL("./MUTATED", import.meta.url), "bad");',
            'import { spawnSync } from "node:child_process"; spawnSync(process.execPath, ["--version"]);',
            'await fetch("http://127.0.0.1:1");',
            'import { connect } from "node:net"; connect(1, "127.0.0.1");'
        )) {
            $target = New-PresetTarget (Join-Path $TestDrive ([guid]::NewGuid().ToString())) $code
            Set-PresetRows $homePath @(@{ name = 'fixture-persona' })
            (Test-DshUserPresetConfig -DshHome $homePath -Contract $target).valid | Should -BeFalse
            Test-Path (Join-Path $target.root 'node_modules\fixture-persona\MUTATED') | Should -BeFalse
        }
    }

    It 'fails on worker premature exit and oversized raw output without forwarding it' {
        foreach ($code in @(
            'process.exit(0);',
            'import { writeSync } from "node:fs"; writeSync(1, "SECRET".repeat(100000)); export function apply() {}'
        )) {
            $target = New-PresetTarget (Join-Path $TestDrive ([guid]::NewGuid().ToString())) $code
            Set-PresetRows $homePath @(@{ name = 'fixture-persona' })
            $result = Test-DshUserPresetConfig -DshHome $homePath -Contract $target
            $result.valid | Should -BeFalse
            ($result | ConvertTo-Json -Depth 20) | Should -Not -Match 'SECRET'
        }
    }

    It 'checks nested groups and rejects conflicting row ids' {
        Set-PresetRows $homePath @(@{ name = 'group'; group = $true; config = @(
            @{ name = 'fixture-persona'; id = 'same'; config = @{ text = 'legacy' } },
            @{ name = 'fixture-persona'; id = 'same'; config = @{ prefix = 'valid' } }
        ) })
        $result = Test-DshUserPresetConfig -DshHome $homePath -Contract $contract
        $result.diagnostics.code | Should -Contain 'config-invalid'
        $result.diagnostics.code | Should -Contain 'entry-id-conflict'
        $result.diagnostics.row | Should -Contain '1.1'
    }

    It 'rejects an entrypoint escape or a target with a reparse dependency' {
        Set-PresetRows $homePath @(@{ name = 'fixture-persona'; config = @{ prefix = 'valid' } })
        $entry = $contract.package.entrypoint
        $contract.package.entrypoint = '..\elsewhere.js'
        (Test-DshUserPresetConfig -DshHome $homePath -Contract $contract).valid | Should -BeFalse
        $contract.package.entrypoint = $entry
        New-Item -ItemType Junction (Join-Path $contract.root 'node_modules\outside') -Target $homePath | Out-Null
        (Test-DshUserPresetConfig -DshHome $homePath -Contract $contract).valid | Should -BeFalse
    }

    It 'blocks reparse points and missing composition manifests' {
        New-Item -ItemType Directory (Join-Path $homePath '.agent-presets\broken') -Force | Out-Null
        (Test-DshUserPresetConfig -DshHome $homePath -Contract $contract).valid | Should -BeFalse
        $linked = Join-Path $TestDrive 'linked-home'
        New-Item -ItemType Junction $linked -Target $homePath | Out-Null
        (Test-DshUserPresetConfig -DshHome $linked -Contract $contract).diagnostics.code |
            Should -Contain 'preset-scope-invalid'
    }
}

Describe 'Managed entrypoint ordering' {
    It 'blocks locked Apply before backup, artifact extraction, profile inspection or Desktop operations' {
        InModuleScope WindowsCopilotDeployment {
            Mock Test-WindowsCopilotLock {}
            Mock Test-DshUserPresetConfig { [pscustomobject]@{
                valid = $false; diagnostics = @(@{ code = 'config-invalid' })
            } }
            Mock New-BackupOperation { throw 'MUTATION' }
            Mock Get-WindowsCopilotDesktopState { throw 'DESKTOP' }
            Mock Test-CopilotIntegrationDeploymentContract { throw 'ARTIFACT' }
            { Invoke-WindowsCopilotApplyLocked -Lock @{ acceptance = @{ runtimeSchema = @{} } } `
                -DshHome 'unused' -NpmGlobalRoot 'unused' -CopilotIntegrationSourceRoot 'unused' `
                -CopilotIntegrationArtifactPath 'unused' -DesktopArtifactPath 'unused' -BackupRoot 'unused' } |
                Should -Throw '*user-preset-config*'
            Should -Invoke New-BackupOperation -Times 0 -Exactly
            Should -Invoke Get-WindowsCopilotDesktopState -Times 0 -Exactly
            Should -Invoke Test-CopilotIntegrationDeploymentContract -Times 0 -Exactly
        }
    }

    It 'runs Check with an incompatible preset before other runtime checks even when SkipRuntimeChecks is set' {
        $homePath = Join-Path $TestDrive 'check-home'
        Set-PresetRows $homePath @(@{ name = 'fixture-persona'; config = @{ text = 'SECRET' } })
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'tools\install-windows-copilot.ps1') `
            -DshHome $homePath -NpmGlobalRoot (Join-Path $TestDrive 'absent-npm') -SkipRuntimeChecks
        $LASTEXITCODE | Should -Be 2
        $result = ($output -join "`n") | ConvertFrom-Json
        $result.checks.userPresetConfig.valid | Should -BeFalse
        ($output -join "`n") | Should -Not -Match 'SECRET'
        Test-Path (Join-Path $TestDrive 'absent-npm') | Should -BeFalse
    }
}
