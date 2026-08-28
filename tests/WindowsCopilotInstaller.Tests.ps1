Import-Module (Join-Path $PSScriptRoot '..\tools\WindowsCopilotDeployment.psm1') -Force

Describe 'Locked Windows Copilot deployment' {
    BeforeAll {
        $script:repoRoot = Split-Path -Parent $PSScriptRoot
        $script:fixtureRoot = Join-Path $PSScriptRoot 'fixtures\windows-copilot'
        $script:lock = Read-WindowsCopilotLock -Path (Join-Path $repoRoot 'deployments\windows-copilot.lock.json')
        $script:catalog = Get-Content -LiteralPath (Join-Path $fixtureRoot 'model-catalog.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    It 'pins every verified source and artifact identity' {
        $lock.components.desktop.version | Should -Be '0.8.2'
        $lock.components.desktop.artifact.sha256 | Should -Be 'a87b7a5d25bd2d4942315a462407326bfb16197178ed0abb0718ab203b5c404b'
        $lock.components.core.source.commit | Should -Be '3c8be05b4218fc08da679179b50f75bf8f780cdb'
        $lock.components.core.package.version | Should -Be '0.1.1-rc.2'
        $lock.components.gateway.source.commit | Should -Be 'a4aac95d4a8f430f02121f79ea36aeaaa06daea1'
        $lock.components.gateway.version | Should -Be '0.6.1'
        $lock.components.searchProvider.source.commit | Should -Be 'f7fc5adfebaf87a3f2d56cfdf5e60601961edcb0'
        $lock.components.searchProvider.package.version | Should -Be '0.2.3-cloga.1'
        $lock.components.searchProvider.package.packageManager | Should -Be 'pnpm@11.7.0'
        $lock.components.searchProvider.package.artifact.sha256 | Should -Be 'd1ded34f5a2b8b1a1e82aa9d6477c0f660d0cd307f14589c26e52c2fb7c18e8f'
        $lock.components.searchProvider.package.bundlePatch | Should -Be './cordis.patch.yml'
        @($lock.components.searchProvider.package.deploymentBaseline.requiredCapabilities).Count | Should -Be 5
        @($lock.acceptance.composedConfig.forbiddenActiveEntries) | Should -Be @(
            'web', 'web-search-deepseek', 'tool-web'
        )
        $lock.acceptance.composedConfig.managedEntry.provider | Should -Be 'copilot-responses'
        $lock.acceptance.composedConfig.managedEntry.apiKeyEnv | Should -Be 'COPILOT_API_KEY'
    }

    It 'keeps all global packages and built artifacts in one npm transaction' {
        $plan = Get-WindowsCopilotInstallPlan -Lock $lock -DshHome (Join-Path $TestDrive '.dsh') `
            -NpmGlobalRoot (Join-Path $TestDrive 'global')
        $step = @($plan.steps | Where-Object id -eq 'install-global-transaction')[0]
        $step.packages.Count | Should -Be 8
        ($step.packages -contains '@deepseek-ai/cordis-plugin-hmr@1.0.16') | Should -Be $true
        ($step.packages -contains '@deepseek-ai/cordis-plugin-timer@1.1.3') | Should -Be $true
        ($step.packages -contains 'node-addon-require-builtin@0.1.4') | Should -Be $true
        ($step.packages -contains '<built-core-release-family-tarballs>') | Should -Be $true
        ($step.packages -contains '<built-search-provider-tarball>') | Should -Be $true
    }

    It 'requires all four plugins to be physical after every profile install' {
        $plan = Get-WindowsCopilotInstallPlan -Lock $lock -DshHome (Join-Path $TestDrive '.dsh') `
            -NpmGlobalRoot (Join-Path $TestDrive 'global')
        $step = @($plan.steps | Where-Object id -eq 'materialize-profile-plugins')[0]
        $step.plugins.Count | Should -Be 4
        ($step.plugins -contains 'dsh-tauri') | Should -Be $true
        ($step.plugins -contains 'dsh-tauri-ui') | Should -Be $true
        ($step.plugins -contains 'dsh-tauri-worktree') | Should -Be $true
        ($step.plugins -contains 'dsh-web-search-provider') | Should -Be $true
    }

    It 'derives separate Responses and Completions model catalogs' {
        $routes = Get-WindowsCopilotRouteModels -Lock $lock -Catalog $catalog
        @($routes['github-copilot-gateway']).Count | Should -Be 2
        @($routes['github-copilot-chat']).Count | Should -Be 2
        ($routes['github-copilot-gateway'] -contains 'responses-only') | Should -Be $true
        ($routes['github-copilot-chat'] -contains 'completions-only') | Should -Be $true
    }

    It 'updates profile manifests, settings, allowBuilds, and physical plugins idempotently' {
        $dshHome = Join-Path $TestDrive 'profile-fixture\.dsh'
        $profileRoot = Join-Path $dshHome 'profiles\web'
        $globalRoot = Join-Path $TestDrive 'profile-fixture\global'
        $backupRoot = Join-Path $TestDrive 'profile-fixture\backups'
        New-Item -ItemType Directory -Path $profileRoot, $globalRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'profile\package.json') -Destination $profileRoot
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'profile\pnpm-workspace.yaml') -Destination $profileRoot
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'settings.yaml') -Destination (Join-Path $dshHome 'settings.yaml')
        Copy-Item -Path (Join-Path $fixtureRoot 'global\*') -Destination $globalRoot -Recurse
        $artifact = Join-Path $TestDrive 'dsh-web-search-provider-0.2.3-cloga.1.tgz'
        Set-Content -LiteralPath $artifact -Value 'fixture artifact' -Encoding UTF8

        $first = Set-WindowsCopilotProfile -Lock $lock -DshHome $dshHome -NpmGlobalRoot $globalRoot `
            -ProviderArtifactPath $artifact -Catalog $catalog -BackupRoot $backupRoot -SkipPackageInstall
        $second = Set-WindowsCopilotProfile -Lock $lock -DshHome $dshHome -NpmGlobalRoot $globalRoot `
            -ProviderArtifactPath $artifact -Catalog $catalog -BackupRoot $backupRoot -SkipPackageInstall

        $profile = Get-Content -LiteralPath (Join-Path $profileRoot 'package.json') -Raw | ConvertFrom-Json
        $profile.dependencies.'fixture-dependency' | Should -Be '1.0.0'
        $profile.dependencies.'dsh-web-search-provider' | Should -Match '^file:\.\./\.\./artifacts/'
        $profile.dependencies.'dsh-tauri' | Should -Be '0.2.0'
        $profile.dependencies.'dsh-tauri-ui' | Should -Be '0.1.0'
        $profile.dependencies.'dsh-tauri-worktree' | Should -Be '0.1.0'
        @($profile.dsh.profile.bundles | Where-Object { $_ -eq 'dsh-web-search-provider' }).Count | Should -Be 1
        foreach ($bundle in @($lock.profile.requiredBundles)) {
            @($profile.dsh.profile.bundles | Where-Object { $_ -eq $bundle }).Count | Should -Be 1
        }

        $workspace = Get-Content -LiteralPath (Join-Path $profileRoot 'pnpm-workspace.yaml') -Raw
        $workspace | Should -Match "'@google/genai': true"
        $workspace | Should -Match "'protobufjs': true"
        @($workspace -split "`n" | Where-Object { $_ -match '@google/genai' }).Count | Should -Be 1

        $settings = Get-Content -LiteralPath (Join-Path $dshHome 'settings.yaml') -Raw
        $settings | Should -Match 'fixture-provider:'
        $settings | Should -Match 'github-copilot-gateway:'
        $settings | Should -Match "api: 'openai-responses'"
        $settings | Should -Match 'github-copilot-chat:'
        $settings | Should -Match "api: 'openai-completions'"
        $settings | Should -Not -Match '^\s{4}github-copilot:'

        foreach ($name in @('dsh-tauri', 'dsh-tauri-ui', 'dsh-tauri-worktree', 'dsh-web-search-provider')) {
            $target = Join-Path $profileRoot (Join-Path 'node_modules' $name)
            (Test-Path -LiteralPath (Join-Path $target 'package.json')) | Should -Be $true
            [bool]((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint) | Should -Be $false
        }
        (Test-Path -LiteralPath $first.backupRoot) | Should -Be $true
        (Test-Path -LiteralPath $second.backupRoot) | Should -Be $true
        $first.backupRoot | Should -Not -Match '\\sessions\\'

        $state = Test-WindowsCopilotInstallation -Lock $lock -DshHome $dshHome `
            -NpmGlobalRoot $globalRoot -ModelCatalogPath (Join-Path $fixtureRoot 'model-catalog.json') `
            -ComposedConfigPath (Join-Path $fixtureRoot 'composed-config.yml') `
            -SearchSmokeResponsePath (Join-Path $fixtureRoot 'search-response.json') `
            -DshCliPath (Join-Path $TestDrive 'missing-dsh.cmd') -DesktopVersion '0.8.2' `
            -GatewaySha256 $lock.components.gateway.artifact.sha256 -SkipRuntimeChecks
        $state.profile.dependencyValid | Should -Be $true
        $state.profile.bundleValid | Should -Be $true
        $state.profile.allowBuildsValid | Should -Be $true
        $state.profile.routesValid | Should -Be $true
        @($state.profile.plugins | Where-Object { -not $_.physical }).Count | Should -Be 0

        $profile.dsh.profile.bundles = @($profile.dsh.profile.bundles | Where-Object { $_ -ne 'dsh-tauri' })
        $profile | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $profileRoot 'package.json') -Encoding UTF8
        $missingBundle = Test-WindowsCopilotInstallation -Lock $lock -DshHome $dshHome `
            -NpmGlobalRoot $globalRoot -ModelCatalogPath (Join-Path $fixtureRoot 'model-catalog.json') `
            -ComposedConfigPath (Join-Path $fixtureRoot 'composed-config.yml') `
            -SearchSmokeResponsePath (Join-Path $fixtureRoot 'search-response.json') `
            -DshCliPath (Join-Path $TestDrive 'missing-dsh.cmd') -DesktopVersion '0.8.2' `
            -GatewaySha256 $lock.components.gateway.artifact.sha256 -SkipRuntimeChecks
        $missingBundle.profile.bundleValid | Should -Be $false
        @($missingBundle.drift.reasons) | Should -Contain 'profile-bundle-drift'
        $missingBundle.drift.remediation.status | Should -Not -Be 'not-required'
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
        $search.deepSeekFallback | Should -Be $false
    }

    It 'rejects managed provider fields outside the config subtree' {
        $content = @'
- id: web-search-provider
  name: dsh-web-search-provider
  enabled: true
  providers: [copilot-responses]
  apiKeyEnv: COPILOT_API_KEY
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
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'profile\package.json') -Destination $profileRoot
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'profile\pnpm-workspace.yaml') -Destination $profileRoot
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'settings.yaml') -Destination (Join-Path $dshHome 'settings.yaml')
        Copy-Item -Path (Join-Path $fixtureRoot 'global\*') -Destination $globalRoot -Recurse
        $artifact = Join-Path $caseRoot 'dsh-web-search-provider-0.2.3-cloga.1.tgz'
        Set-Content -LiteralPath $artifact -Value 'fixture artifact' -Encoding UTF8
        Set-WindowsCopilotProfile -Lock $lock -DshHome $dshHome -NpmGlobalRoot $globalRoot `
            -ProviderArtifactPath $artifact -Catalog $catalog -BackupRoot (Join-Path $caseRoot 'backups') `
            -SkipPackageInstall | Out-Null

        $profilePath = Join-Path $profileRoot 'package.json'
        $profile = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $profile.dependencies.'dsh-web-search-provider' =
            'file:C:/Users/incident/dsh-web-search-provider/dist-all-fixes/dsh-web-search-provider-0.2.2-all-fixes-bd40ffb.tgz'
        $profile | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $profilePath -Encoding UTF8
        $providerRoot = Join-Path $profileRoot 'node_modules\dsh-web-search-provider'
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'provider-0.2.2\package.json') `
            -Destination (Join-Path $providerRoot 'package.json') -Force
        Remove-Item -LiteralPath (Join-Path $providerRoot 'deployment-baseline.json') -Force
        Set-Content -LiteralPath $canonicalCli -Value '@echo off' -Encoding ASCII
        Set-Content -LiteralPath $desktopCli -Value "@echo off`r`n@call `"%~dp0node_modules\.bin\dsh.cmd`" %*" -Encoding ASCII

        $profileBefore = (Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash
        $state = Test-WindowsCopilotInstallation -Lock $lock -DshHome $dshHome `
            -NpmGlobalRoot (Join-Path $corePrefix 'node_modules') `
            -ModelCatalogPath (Join-Path $fixtureRoot 'model-catalog.json') `
            -ComposedConfigPath (Join-Path $fixtureRoot 'composed-config-incident-2026-08-28.yml') `
            -SearchSmokeResponsePath (Join-Path $fixtureRoot 'search-response.json') `
            -DshCliPath $desktopCli -DesktopVersion '0.9.2' `
            -GatewaySha256 $lock.components.gateway.artifact.sha256 -SkipRuntimeChecks

        $state.complete | Should -Be $false
        $state.readyForManualSearchSmoke | Should -Be $false
        $state.health | Should -Be 'drifted'
        $state.drift.incidentId | Should -Be 'windows-copilot-drift-2026-08-28'
        $state.drift.mixedState | Should -Be $true
        $state.deployment.desktop.status | Should -Be 'newer-than-lock'
        $state.deployment.gateway.status | Should -Be 'locked'
        $state.deployment.core.status | Should -Be 'receipt-missing'
        $state.profile.providerDependency | Should -Match 'dsh-web-search-provider-0\.2\.2-all-fixes-bd40ffb\.tgz$'
        (@($state.profile.plugins | Where-Object name -eq 'dsh-web-search-provider'))[0].baselineStatus |
            Should -Be 'missing'
        (@($state.profile.plugins | Where-Object name -eq 'dsh-web-search-provider'))[0].payloadStatus |
            Should -Be 'verified'
        $state.runtime.composedConfig.managedConfigValid | Should -Be $false
        @($state.runtime.composedConfig.forbiddenActiveEntries) | Should -Contain 'web-search-deepseek'
        $state.drift.remediation.status | Should -Be 'blocked-lock-update-required'
        $state.drift.remediation.automaticApplyAllowed | Should -Be $false
        @($state.drift.remediation.steps.action) | Should -Contain 'update-lock-or-review-compatible-migration'
        @($state.drift.remediation.steps.action) | Should -Contain 'bootstrap-copilot-search'
        (Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash | Should -Be $profileBefore
        Test-Path -LiteralPath (Join-Path $corePrefix 'dsh-local-install.json') | Should -Be $false
    }

    It 'validates the provider source against the exported deployment contract' {
        $result = Test-ProviderDeploymentContract -Lock $lock -SourceRoot (Join-Path $fixtureRoot 'provider')
        $result.valid | Should -Be $true
        $result.sourceVerified | Should -Be $true
        $result.artifactVerified | Should -Be $false
        @($result.capabilities).Count | Should -Be 5
    }

    It 'rejects a provider source missing a required capability' {
        $providerRoot = Join-Path $TestDrive 'provider-contract'
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'provider') -Destination $providerRoot -Recurse
        $baselinePath = Join-Path $providerRoot 'deployment-baseline.json'
        $baseline = Get-Content -LiteralPath $baselinePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $baseline.capabilities = @($baseline.capabilities | Where-Object {
            $_.id -ne 'orphaned-replay-item-filtering'
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
        {
            Invoke-WindowsCopilotApply -Lock $lock -DshHome (Join-Path $TestDrive '.dsh') `
                -NpmGlobalRoot (Join-Path $TestDrive 'global') `
                -HarnessSourceRoot (Join-Path $TestDrive 'missing-core-source') `
                -ProviderSourceRoot (Join-Path $TestDrive 'missing-provider-source') `
                -DesktopArtifactPath (Join-Path $TestDrive 'missing-desktop.exe') `
                -GatewayArtifactPath (Join-Path $TestDrive 'missing-gateway.exe') `
                -GatewayInstallRoot (Join-Path $TestDrive 'gateway') `
                -BackupRoot (Join-Path $TestDrive 'backups') -Catalog $catalog -DesktopVersion '0.9.2'
        } | Should -Throw '*Refusing a downgrade*'
        Test-Path -LiteralPath (Join-Path $TestDrive '.dsh') | Should -Be $false
        Test-Path -LiteralPath (Join-Path $TestDrive 'backups') | Should -Be $false
    }

    It 'rejects unsupported YAML key shapes without changing the file' {
        foreach ($content in @(
            "'llm-pi-ai':`n  providers: {}`n",
            "llm-pi-ai:`n  'providers':`n    fixture: {}`n"
        )) {
            $settingsPath = Join-Path $TestDrive ("unsupported-" + [guid]::NewGuid() + '.yaml')
            Set-Content -LiteralPath $settingsPath -Value $content -Encoding UTF8 -NoNewline
            $before = Get-Content -LiteralPath $settingsPath -Raw
            $threw = $false
            try {
                Set-WindowsCopilotRoutes -Lock $lock -SettingsPath $settingsPath -Catalog $catalog
            } catch {
                $threw = $true
            }
            $threw | Should -Be $true
            Get-Content -LiteralPath $settingsPath -Raw | Should -Be $before
        }
    }

    It 'unlinks a plugin junction without deleting its target' {
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { return }
        $dshHome = Join-Path $TestDrive 'junction-fixture\.dsh'
        $profileRoot = Join-Path $dshHome 'profiles\web'
        $globalRoot = Join-Path $TestDrive 'junction-fixture\global'
        $backupRoot = Join-Path $TestDrive 'junction-fixture\backups'
        $outside = Join-Path $TestDrive 'junction-fixture\outside'
        New-Item -ItemType Directory -Path $profileRoot, $globalRoot, $outside -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'profile\package.json') -Destination $profileRoot
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'profile\pnpm-workspace.yaml') -Destination $profileRoot
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'settings.yaml') -Destination (Join-Path $dshHome 'settings.yaml')
        Copy-Item -Path (Join-Path $fixtureRoot 'global\*') -Destination $globalRoot -Recurse
        Set-Content -LiteralPath (Join-Path $outside 'sentinel.txt') -Value 'keep' -Encoding UTF8
        $nodeModules = Join-Path $profileRoot 'node_modules'
        New-Item -ItemType Directory -Path $nodeModules -Force | Out-Null
        New-Item -ItemType Junction -Path (Join-Path $nodeModules 'dsh-tauri') -Target $outside | Out-Null
        $artifact = Join-Path $TestDrive 'dsh-web-search-provider-0.2.3-cloga.1.tgz'
        Set-Content -LiteralPath $artifact -Value 'fixture artifact' -Encoding UTF8

        Set-WindowsCopilotProfile -Lock $lock -DshHome $dshHome -NpmGlobalRoot $globalRoot `
            -ProviderArtifactPath $artifact -Catalog $catalog -BackupRoot $backupRoot -SkipPackageInstall | Out-Null

        Test-Path -LiteralPath (Join-Path $outside 'sentinel.txt') | Should -Be $true
        [bool]((Get-Item -LiteralPath (Join-Path $nodeModules 'dsh-tauri')).Attributes -band [IO.FileAttributes]::ReparsePoint) |
            Should -Be $false
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
