Import-Module (Join-Path $PSScriptRoot '..\tools\DshOfficialDesktopLocalMigration.psm1') -Force

Describe 'Official Desktop local migration plan and guarded apply' {
    BeforeEach {
        $script:community = Join-Path $TestDrive 'community'
        $script:data = Join-Path $TestDrive 'data'
        $script:install = Join-Path $TestDrive 'install'
        New-Item -ItemType Directory -Path (Join-Path $community 'profiles\web'),(Join-Path $data 'harness-home\profiles\desktop'),(Join-Path $install 'resources\seed') -Force | Out-Null
        @'
ui-theme:
  preference: light
llm-pi-ai:
  providers:
    demo:
      api: openai
      apiKeyEnv: DEMO_API_KEY
      baseURL: https://example.invalid
      headers: "Authorization: super-secret-value"
'@ | Set-Content -LiteralPath (Join-Path $community 'settings.yaml') -Encoding utf8
        @'
ui-theme:
  preference: dark
llm-pi-ai:
  providers:
    demo:
      api: openai
      apiKeyEnv: DEMO_API_KEY
      baseURL: https://example.invalid
      headers: "Authorization: target-value"
'@ | Set-Content -LiteralPath (Join-Path $data 'harness-home\settings.yaml') -Encoding utf8
        '{"schemaVersion":1,"version":"0.1.5-rc.2","hostProtocolVersion":3,"nodeVersion":"24.17.0","pnpmVersion":"11.7.0"}' | Set-Content -LiteralPath (Join-Path $install 'resources\seed\desktop-release.json') -Encoding utf8
        $script:ops = Get-DshOfficialDesktopLocalMigrationOperations
    }

    It 'canonicalizes equivalent object key orders identically' {
        $a = [pscustomobject][ordered]@{ z = 1; a = [pscustomobject][ordered]@{ y = 2; b = 3 } }
        $b = [pscustomobject][ordered]@{ a = [pscustomobject][ordered]@{ b = 3; y = 2 }; z = 1 }
        (ConvertTo-DshOfficialDesktopLocalMigrationCanonicalJson $a) | Should -Be (ConvertTo-DshOfficialDesktopLocalMigrationCanonicalJson $b)
    }

    It 'creates a read-only plan without exposing secret values' {
        $before = Get-ChildItem -LiteralPath $data -Force -Recurse | Select-Object FullName,Length,LastWriteTimeUtc | ConvertTo-Json
        $plan = Get-DshOfficialDesktopLocalMigrationPlan -CommunityRoot $community -InstallRoot $install -DataRoot $data -Operations $ops
        $after = Get-ChildItem -LiteralPath $data -Force -Recurse | Select-Object FullName,Length,LastWriteTimeUtc | ConvertTo-Json
        $plan.status | Should -Be 'ready'
        ($plan | ConvertTo-Json -Depth 40) | Should -Not -Match 'super-secret-value|target-value'
        $plan.planHash | Should -Match '^sha256:[0-9a-f]{64}$'
        $after | Should -Be $before
        (Get-ChildItem -LiteralPath $data -Force -Recurse | Where-Object Name -eq 'migration-plans').Count | Should -Be 0
    }

    It 'changes the plan hash and refuses a stale acknowledgement when source changes' {
        $plan = Get-DshOfficialDesktopLocalMigrationPlan -CommunityRoot $community -InstallRoot $install -DataRoot $data -Operations $ops
        Add-Content -LiteralPath (Join-Path $community 'settings.yaml') -Value "# changed"
        { Invoke-DshOfficialDesktopLocalMigration -Action Apply -CommunityRoot $community -InstallRoot $install -DataRoot $data -AcknowledgeMigrationPlan $plan.planHash -Operations $ops } | Should -Throw '*migration-plan-stale*'
    }

    It 'rejects control characters before generating a YAML scalar' {
        InModuleScope DshOfficialDesktopLocalMigration {
            { Get-MigrationSafeScalarText "bad`nvalue" } | Should -Throw '*scalar-control*'
            { Get-MigrationSafeScalarText ('x' * 9000) } | Should -Throw '*scalar-control*'
        }
    }

    It 'fails closed when process or live-session probes are unavailable' {
        InModuleScope DshOfficialDesktopLocalMigration {
            $localOps = Get-DshOfficialDesktopLocalMigrationOperations
            $localOps.GetProcesses = { [pscustomobject]@{ unavailable = $true } }
            $localOps.GetLiveSessions = { [pscustomobject]@{ unavailable = $true } }
            $state = Get-MigrationProcessState 'C:\community' 'C:\data' 'C:\install' $localOps
            $state.processState | Should -Be 'unavailable'
            $state.sessionState | Should -Be 'unavailable'
        }
    }

    It 'classifies credentials and unsupported data without copying them' {
        $plan = Get-DshOfficialDesktopLocalMigrationPlan -CommunityRoot $community -InstallRoot $install -DataRoot $data -Operations $ops
        ($plan | ConvertTo-Json -Depth 40) | Should -Match 'skip-secret|requires-reauthorization|skip-unsupported'
        ($plan | ConvertTo-Json -Depth 40) | Should -Not -Match 'super-secret-value|target-value'
    }

    It 'requires an acknowledgement hash for Apply' {
        { Invoke-DshOfficialDesktopLocalMigration -Action Apply -CommunityRoot $community -InstallRoot $install -DataRoot $data -Operations $ops } | Should -Throw '*acknowledgment-required*'
    }
}
