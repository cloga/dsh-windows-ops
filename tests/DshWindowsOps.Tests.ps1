Import-Module (Join-Path $PSScriptRoot '..\tools\DshWindowsOps.psm1') -Force

Describe 'DSH replay patching' {
    BeforeEach {
        $script:root = Join-Path $TestDrive 'component'
        $script:state = Join-Path $TestDrive 'state'
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        if (Test-Path -LiteralPath $state) { Remove-Item -LiteralPath $state -Recurse -Force }
        New-Item -ItemType Directory -Path (Join-Path $root 'dist') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'package.json') -Value '{"version":"1.2.3"}' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $root 'dist\index.js') -Value 'before TARGET after' -Encoding UTF8 -NoNewline
        $env:DSH_TEST_COMPONENT_ROOT = $root
        $script:config = [pscustomobject]@{
            dshHome = (Join-Path $TestDrive '.dsh')
            components = @(
                [pscustomobject]@{
                    name = 'fixture'
                    rootEnv = 'DSH_TEST_COMPONENT_ROOT'
                    rootCandidates = @()
                    versionProbes = @([pscustomobject]@{ path = 'package.json'; property = 'version' })
                }
            )
            services = @()
            configFiles = @()
        }
        $script:manifest = [pscustomobject]@{
            patches = @(
                [pscustomobject]@{
                    id = 'fixture-patch'
                    component = 'fixture'
                    files = @('dist\index.js')
                    find = 'TARGET'
                    replace = 'PATCHED'
                    patchedFind = 'PATCHED'
                    upstreamStatus = 'temporary'
                    upstreamUrl = ''
                }
            )
        }
    }

    AfterEach {
        Remove-Item Env:DSH_TEST_COMPONENT_ROOT -ErrorAction SilentlyContinue
    }

    It 'detects component versions without exposing file contents' {
        $inventory = @(Get-DshComponentInventory -Config $config)
        $inventory[0].installed | Should Be $true
        $inventory[0].version | Should Be '1.2.3'
    }

    It 'accepts components without optional root and version properties under StrictMode' {
        $minimalConfig = [pscustomobject]@{
            dshHome = (Join-Path $TestDrive '.dsh')
            components = @(
                [pscustomobject]@{
                    name = 'minimal'
                    rootCandidates = @($root)
                }
            )
        }

        $inventory = @(Get-DshComponentInventory -Config $minimalConfig)
        $inventory[0].installed | Should Be $true
        $inventory[0].version | Should BeNullOrEmpty
        $inventory[0].root | Should Be $root
    }

    It 'accepts model endpoints without an optional baseUrlEnv under StrictMode' {
        $minimalConfig = [pscustomobject]@{
            modelEndpoints = @(
                [pscustomobject]@{
                    name = 'unreachable-fixture'
                    baseUrl = 'http://127.0.0.1:1'
                    path = '/v1/models'
                }
            )
        }

        $checks = @(Get-DshEndpointChecks -Config $minimalConfig)
        $checks[0].name | Should Be 'unreachable-fixture'
        $checks[0].reachable | Should Be $false
    }

    It 'uses explicit input metadata rather than model names for vision' {
        $config.configFiles = @((Join-Path $TestDrive 'models.json'))
        Set-Content -LiteralPath $config.configFiles[0] -Encoding UTF8 -Value @'
{"data":[{"id":"vision-by-name-only"},{"id":"actual-image","input":["text","image"]}]}
'@
        $check = Get-DshConfigChecks -Config $config
        @($check.imageCapableModels) | Should Be @('actual-image')
    }

    It 'does not change files in dry-run mode' {
        $result = Invoke-DshPatchSet -Config $config -Manifest $manifest -DryRun -StateRoot $state
        $result.results[0].status | Should Be 'would-apply'
        Get-Content -LiteralPath (Join-Path $root 'dist\index.js') -Raw | Should Be 'before TARGET after'
        Test-Path -LiteralPath $state | Should Be $false
    }

    It 'is idempotent and creates a rollback backup' {
        $first = Invoke-DshPatchSet -Config $config -Manifest $manifest -StateRoot $state
        $second = Invoke-DshPatchSet -Config $config -Manifest $manifest -StateRoot $state
        $first.results[0].status | Should Be 'applied'
        $second.results[0].status | Should Be 'already-applied'
        Get-Content -LiteralPath (Join-Path $root 'dist\index.js') -Raw | Should Be 'before PATCHED after'

        $rollback = Restore-DshPatchSet -Config $config -Manifest $manifest -OperationId $first.operationId -StateRoot $state
        $rollback.results[0].status | Should Be 'restored'
        Get-Content -LiteralPath (Join-Path $root 'dist\index.js') -Raw | Should Be 'before TARGET after'
    }

    It 'rejects patch targets that escape the component root' {
        $badPatch = [pscustomobject]@{
            id = 'outside'
            component = 'fixture'
            files = @('..\outside.js')
            verifyMarkers = @('anything')
            upstreamStatus = 'temporary'
            upstreamUrl = ''
        }
        $threw = $false
        try {
            Test-DshPatch -Patch $badPatch -Config $config | Out-Null
        } catch {
            $threw = $true
        }
        $threw | Should Be $true
    }

    It 'rejects rollback operation traversal' {
        New-Item -ItemType Directory -Path (Join-Path $state 'backups') -Force | Out-Null
        $threw = $false
        try {
            Restore-DshPatchSet -Config $config -Manifest $manifest -OperationId '..\outside' -StateRoot $state | Out-Null
        } catch {
            $threw = $true
        }
        $threw | Should Be $true
    }

    It 'rejects tampered rollback targets' {
        $applied = Invoke-DshPatchSet -Config $config -Manifest $manifest -StateRoot $state
        $metadataPath = Join-Path $state (Join-Path 'backups' (Join-Path $applied.operationId 'metadata.json'))
        $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
        $metadata.files[0].relative = '..\outside.js'
        $metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $metadataPath -Encoding UTF8

        $threw = $false
        try {
            Restore-DshPatchSet -Config $config -Manifest $manifest -OperationId $applied.operationId -StateRoot $state | Out-Null
        } catch {
            $threw = $true
        }
        $threw | Should Be $true
    }

    It 'refuses to overwrite a file changed after patching' {
        $applied = Invoke-DshPatchSet -Config $config -Manifest $manifest -StateRoot $state
        Set-Content -LiteralPath (Join-Path $root 'dist\index.js') -Value 'new vendor build' -Encoding UTF8
        $threw = $false
        try {
            Restore-DshPatchSet -Config $config -Manifest $manifest -OperationId $applied.operationId -StateRoot $state | Out-Null
        } catch {
            $threw = $true
        }
        $threw | Should Be $true
        Get-Content -LiteralPath (Join-Path $root 'dist\index.js') -Raw | Should Match 'new vendor build'
    }

    It 'does not partially restore when a later file fails validation' {
        Set-Content -LiteralPath (Join-Path $root 'dist\second.js') -Value 'second TARGET' -Encoding UTF8 -NoNewline
        $manifest.patches += [pscustomobject]@{
            id = 'second-patch'
            component = 'fixture'
            files = @('dist\second.js')
            find = 'TARGET'
            replace = 'PATCHED'
            patchedFind = 'PATCHED'
            upstreamStatus = 'temporary'
            upstreamUrl = ''
        }
        $applied = Invoke-DshPatchSet -Config $config -Manifest $manifest -StateRoot $state
        Set-Content -LiteralPath (Join-Path $root 'dist\second.js') -Value 'new vendor build' -Encoding UTF8

        $threw = $false
        try {
            Restore-DshPatchSet -Config $config -Manifest $manifest -OperationId $applied.operationId -StateRoot $state | Out-Null
        } catch {
            $threw = $true
        }
        $threw | Should Be $true
        Get-Content -LiteralPath (Join-Path $root 'dist\index.js') -Raw | Should Be 'before PATCHED after'
    }

    It 'ignores a staged entry whose target was never committed' {
        $applied = Invoke-DshPatchSet -Config $config -Manifest $manifest -StateRoot $state
        $operationRoot = Join-Path $state (Join-Path 'backups' $applied.operationId)
        $metadataPath = Join-Path $operationRoot 'metadata.json'
        $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
        $metadata.files[0].state = 'staged'
        $metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $metadataPath -Encoding UTF8
        Copy-Item -LiteralPath (Join-Path $operationRoot 'fixture\dist\index.js') -Destination (Join-Path $root 'dist\index.js') -Force

        $rollback = Restore-DshPatchSet -Config $config -Manifest $manifest -OperationId $applied.operationId -StateRoot $state
        $rollback.results[0].status | Should Be 'not-applied'
    }

    It 'rejects multiple applicable patches for the same file' {
        $manifest.patches += [pscustomobject]@{
            id = 'duplicate-target'
            component = 'fixture'
            files = @('dist\index.js')
            find = 'before'
            replace = 'changed'
            patchedFind = 'changed'
            upstreamStatus = 'temporary'
            upstreamUrl = ''
        }
        $threw = $false
        try {
            Invoke-DshPatchSet -Config $config -Manifest $manifest -StateRoot $state | Out-Null
        } catch {
            $threw = $true
        }
        $threw | Should Be $true
        Get-Content -LiteralPath (Join-Path $root 'dist\index.js') -Raw | Should Be 'before TARGET after'
        Test-Path -LiteralPath $state | Should Be $false
    }
}
