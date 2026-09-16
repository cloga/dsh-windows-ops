Import-Module (Join-Path $PSScriptRoot '..\tools\DshWindowsOps.psm1') -Force

Describe 'Lock-selected replay discovery' {
    BeforeEach {
        $script:replayConfig = Get-Content (Join-Path $PSScriptRoot '..\tools\dsh-replay.config.example.json') -Raw |
            ConvertFrom-Json
        $script:replayLock = Get-Content (Join-Path $PSScriptRoot '..\deployments\windows-copilot.lock.json') -Raw |
            ConvertFrom-Json
        $script:savedDesktopRoot = $env:DSH_DESKTOP_ROOT
        $script:savedRuntimeRoot = $env:DSH_DESKTOP_RUNTIME_ROOT
        Remove-Item Env:DSH_DESKTOP_ROOT, Env:DSH_DESKTOP_RUNTIME_ROOT -ErrorAction SilentlyContinue
        Mock Get-WindowsCopilotDesktopState -ModuleName DshWindowsOps {
            [pscustomobject]@{
                path = 'C:\fixture\package-install\cloga-deepseek-harness.exe'
                valid = $true
                status = 'locked'
            }
        }
        Mock Get-WindowsCopilotOfficialRuntimeState -ModuleName DshWindowsOps {
            [pscustomobject]@{
                root = 'C:\fixture\package-install\resources\dsh'
                selector = 'desktop-fork-managed'
                valid = $true
                status = 'runtime-descriptor-verified'
            }
        }
    }

    AfterEach {
        $env:DSH_DESKTOP_ROOT = $savedDesktopRoot
        $env:DSH_DESKTOP_RUNTIME_ROOT = $savedRuntimeRoot
    }

    It 'follows the installer-selected actual path and attests its bundled runtime' {
        $result = Resolve-DshLockedReplayConfig -Config $replayConfig -Lock $replayLock
        $result.deployment.valid | Should -BeTrue
        $result.components[0].rootCandidates | Should -Be @('C:\fixture\package-install')
        $result.components[0].registryDiscovery | Should -BeFalse
        $result.components[1].rootCandidates | Should -Be @('C:\fixture\package-install\resources\dsh')
        Should -Invoke Get-WindowsCopilotOfficialRuntimeState -ModuleName DshWindowsOps -Times 1 -Exactly `
            -ParameterFilter { $DesktopExecutablePath -eq 'C:\fixture\package-install\cloga-deepseek-harness.exe' }
        $replayConfig.components[0].rootCandidates.Count | Should -Be 0
    }

    It 'rejects an old explicit Desktop environment or config rather than changing shells' {
        Mock Get-WindowsCopilotDesktopState -ModuleName DshWindowsOps {
            [pscustomobject]@{ path = $Path; valid = $false; status = 'not-found-or-unreadable' }
        }
        $env:DSH_DESKTOP_ROOT = 'C:\fixture\old-tauri'
        { Resolve-DshLockedReplayConfig -Config $replayConfig -Lock $replayLock } |
            Should -Throw '*replay-explicit-desktop-conflicts-with-lock*'
        Remove-Item Env:DSH_DESKTOP_ROOT
        $replayConfig.components[0].rootCandidates = @('C:\fixture\old-tauri')
        { Resolve-DshLockedReplayConfig -Config $replayConfig -Lock $replayLock } |
            Should -Throw '*replay-explicit-desktop-conflicts-with-lock*'
    }

    It 'rejects a separate legacy runtime override' {
        $env:DSH_DESKTOP_RUNTIME_ROOT = 'C:\fixture\legacy-runtime'
        { Resolve-DshLockedReplayConfig -Config $replayConfig -Lock $replayLock } |
            Should -Throw '*replay-explicit-runtime-conflicts-with-lock*'
    }

    It 'rejects stale configured roots even when an environment override selects the new shell' {
        $env:DSH_DESKTOP_ROOT = 'C:\fixture\package-install'
        $replayConfig.components[0].rootCandidates = @('C:\fixture\old-tauri')
        { Resolve-DshLockedReplayConfig -Config $replayConfig -Lock $replayLock } |
            Should -Throw '*replay-configured-desktop-conflicts-with-lock*'
    }

    It 'rejects a legacy executable in a custom config' {
        $replayConfig.components[0].executables = @('deepseek-harness-desktop.exe')
        { Resolve-DshLockedReplayConfig -Config $replayConfig -Lock $replayLock } |
            Should -Throw '*replay-configured-executable-conflicts-with-lock*'
    }

    It 'reports a missing locked target without querying the legacy registry' {
        Mock Get-WindowsCopilotDesktopState -ModuleName DshWindowsOps {
            [pscustomobject]@{ path = 'C:\missing-locked-fixture\cloga-deepseek-harness.exe'; valid = $false; status = 'not-found-or-unreadable' }
        }
        Mock Get-WindowsCopilotOfficialRuntimeState -ModuleName DshWindowsOps {
            [pscustomobject]@{ root = 'C:\missing-locked-fixture\resources\dsh'; valid = $false; status = 'runtime-descriptor-not-found' }
        }
        Mock Get-ItemProperty -ModuleName DshWindowsOps { throw 'legacy-registry-must-not-be-read' }
        $result = Resolve-DshLockedReplayConfig -Config $replayConfig -Lock $replayLock
        $result.deployment.valid | Should -BeFalse
        $inventory = @(Get-DshComponentInventory -Config $result)
        $inventory[0].installed | Should -BeFalse
        $inventory[1].installed | Should -BeFalse
        Should -Invoke Get-ItemProperty -ModuleName DshWindowsOps -Times 0 -Exactly
    }

    It 'keeps Desktop plugin evidence separate from optional Web and headless profiles' {
        $replayConfig.components[2].rootCandidates |
            Should -Be @('${DSH_HOME}\profiles\desktop\node_modules\dsh-github-copilot')
        $replayConfig.configFiles | Should -Contain '${DSH_HOME}\profiles\web\cordis.patch.yml'
        $replayConfig.configFiles | Should -Contain '${DSH_HOME}\profiles\headless\cordis.patch.yml'
    }

    It 'does not apply legacy shell patches to the locked fork or an unknown runtime' {
        $manifest = Get-Content (Join-Path $PSScriptRoot '..\tools\dsh-replay.patches.json') -Raw | ConvertFrom-Json
        $config = Resolve-DshLockedReplayConfig -Config $replayConfig -Lock $replayLock
        foreach ($id in @('desktop-official-renderer-slot-outlet', 'desktop-no-open-recovery')) {
            $patch = $manifest.patches | Where-Object id -eq $id
            (Test-DshPatch -Patch $patch -Config $config).status | Should -Be 'not-applicable'
            (Test-DshPatch -Patch $patch -Config $replayConfig).status | Should -Be 'unsupported'
        }
    }

    It 'keeps SelfCheck and exact-marker DryRun read-only and exposes deployment evidence' {
        $replayConfig.configFiles = @()
        $replayConfig.services = @()
        $configPath = Join-Path $TestDrive 'replay.json'
        $stateRoot = Join-Path $TestDrive 'no-writes'
        $replayConfig | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
        $before = (Get-FileHash $configPath).Hash
        $entrypoint = Join-Path $PSScriptRoot '..\tools\dsh-replay.ps1'
        $selfCheck = & $entrypoint -Action SelfCheck -Config $configPath -StateRoot $stateRoot |
            ConvertFrom-Json
        $dryRun = & $entrypoint -Action Apply -DryRun -Config $configPath -StateRoot $stateRoot |
            ConvertFrom-Json
        $selfCheck.deployment.runtime.status | Should -Be 'runtime-descriptor-verified'
        $dryRun.deployment.desktop.status | Should -Be 'locked'
        $dryRun.dryRun | Should -BeTrue
        (Get-FileHash $configPath).Hash | Should -Be $before
        Test-Path $stateRoot | Should -BeFalse
    }
}

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
        $inventory[0].installed | Should -Be $true
        $inventory[0].version | Should -Be '1.2.3'
    }

    It 'locks exact Copilot client ModuleLoader handoff replay markers' {
        $manifestPath = Join-Path $PSScriptRoot '..\tools\dsh-replay.patches.json'
        $repositoryManifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $patch = @($repositoryManifest.patches | Where-Object id -eq 'github-copilot-client-module-loader-handoff')

        $patch.Count | Should -Be 1
        @($patch[0].verifyMarkers) | Should -Be @(
            'window.__ModuleLoader__.load({',
            'id: "dsh-github-copilot"',
            'factory: (require) => {',
            'return module.exports;'
        )
        $patch[0].upstreamUrl | Should -Be 'https://github.com/cloga/dsh-github-copilot/pull/23'
    }

    It 'locks strict remote result codec replay markers' {
        $manifestPath = Join-Path $PSScriptRoot '..\tools\dsh-replay.patches.json'
        $repositoryManifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $patch = @($repositoryManifest.patches | Where-Object id -eq 'github-copilot-strict-remote-result-codecs')

        $patch.Count | Should -Be 1
        $patch[0].files | Should -Be @('lib\remote.js')
        @($patch[0].verifyMarkers) | Should -Be @(
            'import { z } from "zod";',
            'dsh-github-copilot#GitHubCopilotAuthorizationView',
            'const GitHubCopilotAuthorizationViewSchema = z.object({',
            'mode: "strict"',
            'schema: GitHubCopilotAuthorizationViewSchema'
        )
        $patch[0].upstreamUrl | Should -Be 'https://github.com/cloga/dsh-github-copilot/pull/26'
    }

    It 'locks exact rc.2 authorization bootstrap replay markers' {
        $manifestPath = Join-Path $PSScriptRoot '..\tools\dsh-replay.patches.json'
        $repositoryManifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $patch = @($repositoryManifest.patches | Where-Object id -eq 'github-copilot-authorization-bootstrap')

        $patch.Count | Should -Be 1
        @($patch[0].verifyMarkers) | Should -Be @(
            'ctx.get("authorization", false)',
            'ctx.plugin(AuthorizationService)',
            'ctx.inject(integrationInject'
        )
        $patch[0].upstreamUrl | Should -Be 'https://github.com/cloga/dsh-github-copilot/pull/21'
    }

    It 'locks strict JSON OAuth grant normalization replay markers' {
        $manifestPath = Join-Path $PSScriptRoot '..\tools\dsh-replay.patches.json'
        $repositoryManifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $patch = @($repositoryManifest.patches |
            Where-Object id -eq 'github-copilot-strict-json-oauth-grant-normalization')

        $patch.Count | Should -Be 1
        $patch[0].files | Should -Be @('lib\index.js')
        @($patch[0].verifyMarkers) | Should -Be @(
            'normalizeGitHubCopilotOAuthCredential',
            'Number.isFinite(expires)'
        )
        $patch[0].upstreamUrl | Should -Be 'https://github.com/cloga/dsh-github-copilot/pull/33'
    }

    It 'locks account-snapshot protocol facts replay markers' {
        $manifestPath = Join-Path $PSScriptRoot '..\tools\dsh-replay.patches.json'
        $repositoryManifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $patch = @($repositoryManifest.patches |
            Where-Object id -eq 'github-copilot-per-model-api-route-materialization')

        $patch.Count | Should -Be 1
        $patch[0].files | Should -Be @('lib\index.js')
        @($patch[0].verifyMarkers) | Should -Be @(
            'routeFacts(modelId)',
            'const snapshot = source.readSnapshot();',
            'api: descriptor.api',
            'baseURL: proof.baseURL'
        )
        $patch[0].upstreamUrl | Should -Be 'https://github.com/cloga/dsh-github-copilot/blob/479340f965c5be7b4408e4f1e6c9dda6c421d37b/src/preview-route.ts'
    }

    It 'locks canonical route precedence and hostname-scoped metadata in the packed shared chunk' {
        $repositoryManifest = Get-Content (Join-Path $PSScriptRoot '..\tools\dsh-replay.patches.json') -Raw |
            ConvertFrom-Json
        $patch = $repositoryManifest.patches | Where-Object id -eq 'github-copilot-shared-routing-chunk'
        $patch.files | Should -Be @('lib\search-routing-pFLux0W7.js')
        $patch.verifyMarkers | Should -Be @(
            'const effectiveApi = provider === "github-copilot" ? routeApi : selectedApi ?? routeApi;',
            'hostname.endsWith(".githubcopilot.com") || hostname.startsWith("copilot-api.")',
            'headers["X-Initiator"] = initiator;',
            'headers["Openai-Intent"] = "conversation-edits";'
        )
    }

    It 'verifies all current plugin marker sets against the synthetic release fixture' {
        $repositoryManifest = Get-Content (Join-Path $PSScriptRoot '..\tools\dsh-replay.patches.json') -Raw |
            ConvertFrom-Json
        $fixtureConfig = [pscustomobject]@{
            dshHome = $TestDrive
            components = @([pscustomobject]@{
                name = 'dsh-github-copilot'
                rootCandidates = @((Join-Path $PSScriptRoot 'fixtures\windows-copilot\global\dsh-github-copilot'))
            })
        }
        foreach ($patch in @($repositoryManifest.patches | Where-Object component -eq 'dsh-github-copilot')) {
            (Test-DshPatch -Patch $patch -Config $fixtureConfig).status |
                Should -Be 'verified-upstream' -Because $patch.id
        }
    }

    It 'locks existing-grant route self-healing replay markers' {
        $manifestPath = Join-Path $PSScriptRoot '..\tools\dsh-replay.patches.json'
        $repositoryManifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $patch = @($repositoryManifest.patches |
            Where-Object id -eq 'github-copilot-existing-grant-route-self-healing')

        $patch.Count | Should -Be 1
        $patch[0].files | Should -Be @('lib\index.js')
        @($patch[0].verifyMarkers) | Should -Be @(
            'ensureGitHubCopilotProviderProfile(ctx)',
            'validateGrant(record)',
            'current !== void 0 && providerSupportsStrictMode(current) !== false',
            'async function repairGitHubCopilotProviderProfile(ctx)',
            'normalizeGitHubCopilotOAuthCredential(record.payload)'
        )
        $patch[0].upstreamUrl | Should -Be 'https://github.com/cloga/dsh-github-copilot/blob/479340f965c5be7b4408e4f1e6c9dda6c421d37b/src/authorization-controller.ts'
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
        $inventory[0].installed | Should -Be $true
        $inventory[0].version | Should -BeNullOrEmpty
        $inventory[0].root | Should -Be $root
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
        $checks[0].name | Should -Be 'unreachable-fixture'
        $checks[0].reachable | Should -Be $false
    }

    It 'uses explicit input metadata rather than model names for vision' {
        $config.configFiles = @((Join-Path $TestDrive 'models.json'))
        Set-Content -LiteralPath $config.configFiles[0] -Encoding UTF8 -Value @'
{"data":[{"id":"vision-by-name-only"},{"id":"actual-image","input":["text","image"]}]}
'@
        $check = Get-DshConfigChecks -Config $config
        @($check.imageCapableModels) | Should -Be @('actual-image')
    }

    It 'does not change files in dry-run mode' {
        $result = Invoke-DshPatchSet -Config $config -Manifest $manifest -DryRun -StateRoot $state
        $result.results[0].status | Should -Be 'would-apply'
        Get-Content -LiteralPath (Join-Path $root 'dist\index.js') -Raw | Should -Be 'before TARGET after'
        Test-Path -LiteralPath $state | Should -Be $false
    }

    It 'is idempotent and creates a rollback backup' {
        $first = Invoke-DshPatchSet -Config $config -Manifest $manifest -StateRoot $state
        $second = Invoke-DshPatchSet -Config $config -Manifest $manifest -StateRoot $state
        $first.results[0].status | Should -Be 'applied'
        $second.results[0].status | Should -Be 'already-applied'
        Get-Content -LiteralPath (Join-Path $root 'dist\index.js') -Raw | Should -Be 'before PATCHED after'

        $rollback = Restore-DshPatchSet -Config $config -Manifest $manifest -OperationId $first.operationId -StateRoot $state
        $rollback.results[0].status | Should -Be 'restored'
        Get-Content -LiteralPath (Join-Path $root 'dist\index.js') -Raw | Should -Be 'before TARGET after'
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
        $threw | Should -Be $true
    }

    It 'rejects rollback operation traversal' {
        New-Item -ItemType Directory -Path (Join-Path $state 'backups') -Force | Out-Null
        $threw = $false
        try {
            Restore-DshPatchSet -Config $config -Manifest $manifest -OperationId '..\outside' -StateRoot $state | Out-Null
        } catch {
            $threw = $true
        }
        $threw | Should -Be $true
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
        $threw | Should -Be $true
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
        $threw | Should -Be $true
        Get-Content -LiteralPath (Join-Path $root 'dist\index.js') -Raw | Should -Match 'new vendor build'
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
        $threw | Should -Be $true
        Get-Content -LiteralPath (Join-Path $root 'dist\index.js') -Raw | Should -Be 'before PATCHED after'
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
        $rollback.results[0].status | Should -Be 'not-applied'
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
        $threw | Should -Be $true
        Get-Content -LiteralPath (Join-Path $root 'dist\index.js') -Raw | Should -Be 'before TARGET after'
        Test-Path -LiteralPath $state | Should -Be $false
    }
}
