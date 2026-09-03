Describe 'Optional DSH companion suite installer' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '..\tools\install-optional-companion-suite.ps1'
    }

    It 'is check-only by default and reports all independent components' {
        $dshHome = Join-Path $TestDrive 'empty-dsh-home'
        $result = & $scriptPath -DshHome $dshHome | ConvertFrom-Json

        $result.action | Should -Be 'check'
        $result.profile | Should -Be 'web'
        $result.profileExists | Should -Be $false
        $result.complete | Should -Be $false
        @($result.components.name) | Should -Be @(
            'dsh-github-copilot',
            'dsh-cron',
            'dsh-playwright-host'
        )
        $result.activation | Should -Match 'never restarts'
    }

    It 'refuses apply when the target Profile has not been initialized' {
        $dshHome = Join-Path $TestDrive 'missing-profile'

        { & $scriptPath -Action Apply -DshHome $dshHome } |
            Should -Throw '*Profile does not exist*'
    }

    It 'recognizes an already composed three-bundle profile without mutation' {
        $dshHome = Join-Path $TestDrive 'complete-dsh-home'
        $profile = Join-Path $dshHome 'profiles\web'
        New-Item -ItemType Directory -Path $profile -Force | Out-Null
        @{
            dependencies = @{
                'dsh-github-copilot' = 'https://github.com/cloga/dsh-github-copilot/releases/download/v0.3.0-cloga.14/dsh-github-copilot-0.3.0-cloga.14.tgz'
                'dsh-cron' = 'github:cloga/dsh-cron#f5e8df45496523c98874e6f484b886941683f7d6'
                'dsh-playwright-host' = 'github:cloga/dsh-playwright-host#86ca74d4fdf89d6aa6036f273eb8acab4adae34f'
            }
            dsh = @{
                profile = @{
                    bundles = @(
                        '@deepseek-ai/dsh-base',
                        '@deepseek-ai/dsh-web-app',
                        'dsh-github-copilot',
                        'dsh-cron',
                        'dsh-playwright-host'
                    )
                }
            }
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $profile 'package.json') -Encoding UTF8
        @"
lockfileVersion: '9.0'
importers:
  .:
    dependencies:
      dsh-github-copilot:
        specifier: https://github.com/cloga/dsh-github-copilot/releases/download/v0.3.0-cloga.14/dsh-github-copilot-0.3.0-cloga.14.tgz
      dsh-cron:
        specifier: github:cloga/dsh-cron#f5e8df45496523c98874e6f484b886941683f7d6
      dsh-playwright-host:
        specifier: github:cloga/dsh-playwright-host#86ca74d4fdf89d6aa6036f273eb8acab4adae34f
"@ | Set-Content -LiteralPath (Join-Path $profile 'pnpm-lock.yaml') -Encoding UTF8
        foreach ($package in @(
            @{ name = 'dsh-github-copilot'; version = '0.3.0-cloga.14' },
            @{ name = 'dsh-cron'; version = '0.3.3' },
            @{ name = 'dsh-playwright-host'; version = '0.1.1' }
        )) {
            $packageRoot = Join-Path (Join-Path $profile 'node_modules') $package.name
            New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
            $package | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $packageRoot 'package.json') -Encoding UTF8
        }

        $result = & $scriptPath -DshHome $dshHome | ConvertFrom-Json

        $result.complete | Should -Be $true
        @($result.components | Where-Object { -not $_.dependencyPresent }).Count | Should -Be 0
        @($result.components | Where-Object { -not $_.bundlePresent }).Count | Should -Be 0
        @($result.components | Where-Object { -not $_.sourceValid }).Count | Should -Be 0
        @($result.components | Where-Object { -not $_.installedValid }).Count | Should -Be 0
        @($result.components | Where-Object { -not $_.lockEvidence }).Count | Should -Be 0

        @"
lockfileVersion: '9.0'
importers:
  .:
    dependencies:
      dsh-github-copilot:
        specifier: github:cloga/dsh-cron#f5e8df45496523c98874e6f484b886941683f7d6
      dsh-cron:
        specifier: github:cloga/dsh-playwright-host#86ca74d4fdf89d6aa6036f273eb8acab4adae34f
      dsh-playwright-host:
        specifier: https://github.com/cloga/dsh-github-copilot/releases/download/v0.3.0-cloga.14/dsh-github-copilot-0.3.0-cloga.14.tgz
"@ | Set-Content -LiteralPath (Join-Path $profile 'pnpm-lock.yaml') -Encoding UTF8
        $rotated = & $scriptPath -DshHome $dshHome | ConvertFrom-Json
        $rotated.complete | Should -Be $false
        @($rotated.components | Where-Object lockEvidence).Count | Should -Be 0
    }

    It 'does not report completion for name-matching packages from wrong sources' {
        $dshHome = Join-Path $TestDrive 'wrong-source-home'
        $profile = Join-Path $dshHome 'profiles\web'
        New-Item -ItemType Directory -Path $profile -Force | Out-Null
        @{
            dependencies = @{
                'dsh-github-copilot' = 'fixture'
                'dsh-cron' = 'fixture'
                'dsh-playwright-host' = 'fixture'
            }
            dsh = @{ profile = @{ bundles = @('dsh-github-copilot', 'dsh-cron', 'dsh-playwright-host') } }
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $profile 'package.json') -Encoding UTF8

        $result = & $scriptPath -DshHome $dshHome | ConvertFrom-Json

        $result.complete | Should -Be $false
        @($result.components | Where-Object sourceValid).Count | Should -Be 0
    }

    It 'removes a partial suite idempotently and restores the caller DSH_HOME' {
        $dshHome = Join-Path $TestDrive 'partial-suite-home'
        $profile = Join-Path $dshHome 'profiles\web'
        New-Item -ItemType Directory -Path $profile -Force | Out-Null
        @{
            dependencies = @{ 'dsh-cron' = 'github:cloga/dsh-cron#f5e8df45496523c98874e6f484b886941683f7d6' }
            dsh = @{ profile = @{ bundles = @('dsh-github-copilot', 'dsh-cron', 'dsh-playwright-host') } }
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $profile 'package.json') -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $profile 'pnpm-lock.yaml') -Value "lockfileVersion: '9.0'" -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $profile 'pnpm-workspace.yaml') -Value "packages:`n  - ." -Encoding UTF8
        $fakeDsh = Join-Path $TestDrive 'fake-dsh.ps1'
        @'
$manifestPath = Join-Path $env:DSH_HOME 'profiles\web\package.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$manifest.dependencies.psobject.Properties.Remove('dsh-cron')
$manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
$global:LASTEXITCODE = 0
'@ | Set-Content -LiteralPath $fakeDsh -Encoding UTF8
        $previous = $env:DSH_HOME
        try {
            $env:DSH_HOME = 'caller-sentinel'
            $result = & $scriptPath -Action Remove -DshHome $dshHome -DshCliPath $fakeDsh | ConvertFrom-Json
            $env:DSH_HOME | Should -Be 'caller-sentinel'
        } finally {
            $env:DSH_HOME = $previous
        }

        @($result.components | Where-Object { $_.dependencyPresent -or $_.bundlePresent }).Count | Should -Be 0
        $result.backupPath | Should -Not -BeNullOrEmpty
    }

    It 'restores a valid backup when a failed plugin command corrupts package.json' {
        $dshHome = Join-Path $TestDrive 'corrupt-restore-home'
        $profile = Join-Path $dshHome 'profiles\web'
        New-Item -ItemType Directory -Path $profile -Force | Out-Null
        @{
            dependencies = @{ 'dsh-cron' = 'github:cloga/dsh-cron#f5e8df45496523c98874e6f484b886941683f7d6' }
            dsh = @{ profile = @{ bundles = @('dsh-cron') } }
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $profile 'package.json') -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $profile 'pnpm-lock.yaml') -Value "lockfileVersion: '9.0'" -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $profile 'pnpm-workspace.yaml') -Value "packages:`n  - ." -Encoding UTF8
        $before = Get-Content -LiteralPath (Join-Path $profile 'package.json') -Raw
        $fakeDsh = Join-Path $TestDrive 'corrupting-dsh.ps1'
        @'
Set-Content -LiteralPath (Join-Path $env:DSH_HOME 'profiles\web\package.json') -Value '{broken' -Encoding UTF8
$global:LASTEXITCODE = 1
'@ | Set-Content -LiteralPath $fakeDsh -Encoding UTF8
        $fakePnpm = Join-Path $TestDrive 'successful-pnpm.ps1'
        '$global:LASTEXITCODE = 0' | Set-Content -LiteralPath $fakePnpm -Encoding UTF8

        { & $scriptPath -Action Remove -DshHome $dshHome -DshCliPath $fakeDsh -PnpmCliPath $fakePnpm } |
            Should -Throw '*were restored*'

        (Get-Content -LiteralPath (Join-Path $profile 'package.json') -Raw) | Should -BeExactly $before
    }

    It 'pins reviewed immutable component versions and never performs a restart' {
        $source = Get-Content -LiteralPath $scriptPath -Raw

        $source | Should -Match 'dsh-github-copilot-0\.3\.0-cloga\.14\.tgz'
        $source | Should -Match 'c7e05eeefc0edf28324d01ee55e85bb4297d8c26ce982d51009a7019ac49aa96'
        $source | Should -Match 'github:cloga/dsh-cron#f5e8df45496523c98874e6f484b886941683f7d6'
        $source | Should -Match 'github:cloga/dsh-playwright-host#86ca74d4fdf89d6aa6036f273eb8acab4adae34f'
        $source | Should -Not -Match 'Restart-Process|Stop-Process|taskkill'
    }
}
