Import-Module (Join-Path $PSScriptRoot '..\tools\DshOfficialDesktopPluginProvisioning.psm1') -Force

Describe 'Official Desktop plugin provisioning contract' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..\tools\DshOfficialDesktopPluginProvisioning.psm1') -Force
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
        $script:lockPath = Join-Path $repoRoot 'deployments\windows-copilot.lock.json'
    }

    It 'loads one complete immutable Release contract and keeps Windows Ops/native modes exclusive' {
        $contract = Get-DshOfficialDesktopPluginContract -LockPath $lockPath
        $contract.mode | Should -Be 'windowsOpsVerifiedRelease'
        $contract.registry | Should -Be 'https://packagefeedproxy.microsoft.io/npm/'
        $contract.package.version | Should -Be '0.4.0-alpha.18'
        $contract.artifact.releaseImmutable | Should -BeTrue
        $contract.artifact.releaseTag | Should -Be 'v0.4.0-alpha.18'
        $contract.artifact.releaseCommit | Should -Be '08bfccc3b5930b93ef2fe31d9cf9e509f34a8704'
        $contract.artifact.sha256 | Should -Be '2ca4f604e89eda3000cf2a51d79871cee3cb721fa6f4324fc9a1197926c359a8'
        $contract.artifact.sha512 | Should -Be '15975665b6ff2bc8e613ae06c1bf5953e5000c0a9a9007ea2d7aebbbfaa92c5492e2a0b82cc3b4b88714d4a6ecc350a0e79c5fd2af9949b9f4cb771dc83ccb5f'
        $contract.artifact.integrity | Should -Be 'sha512-FZdWZbb/K8jmE64Gwb9ZU+UADAqakAfqLXrru/qpLFSS4qC4LMO0uIcU1Kbsw1Cg55xf0q+ZSbn0y3cdyDzLXw=='

        $forged = Get-Content $lockPath -Raw | ConvertFrom-Json
        $forged.components.copilotIntegration.desktopProvisioning.nativeCapability.verified = $true
        $path = Join-Path $TestDrive 'both-active.json'
        $forged | ConvertTo-Json -Depth 60 | Set-Content $path
        { Get-DshOfficialDesktopPluginContract -LockPath $path } |
            Should -Throw '*native-capability-mode-mismatch*'

        $forged.components.copilotIntegration.desktopProvisioning.mode = 'desktopNativeVerifiedRelease'
        $forged.components.copilotIntegration.desktopProvisioning.nativeCapability.verified = $false
        $forged | ConvertTo-Json -Depth 60 | Set-Content $path
        { Get-DshOfficialDesktopPluginContract -LockPath $path } |
            Should -Throw '*native-provisioning-capability-unverified*'
    }

    It 'rejects incomplete version-only lock updates' {
        $forged = Get-Content $lockPath -Raw | ConvertFrom-Json
        $forged.components.copilotIntegration.package.version = '0.4.0-alpha.19'
        $path = Join-Path $TestDrive 'version-only.json'
        $forged | ConvertTo-Json -Depth 60 | Set-Content $path
        { Get-DshOfficialDesktopPluginContract -LockPath $path } |
            Should -Throw '*artifact-contract-invalid*'
    }

    It 'rejects checksum manifest and SRI drift in the authoritative contract' {
        $forged = Get-Content $lockPath -Raw | ConvertFrom-Json
        $path = Join-Path $TestDrive 'artifact-drift.json'
        $forged.components.copilotIntegration.package.artifact.checksumManifest.url = 'https://github.com/cloga/dsh-github-copilot/releases/download/v0.4.0-alpha.18/OTHER'
        $forged | ConvertTo-Json -Depth 60 | Set-Content $path
        { Get-DshOfficialDesktopPluginContract -LockPath $path } |
            Should -Throw '*checksum-manifest-contract-invalid*'

        $forged = Get-Content $lockPath -Raw | ConvertFrom-Json
        $forged.components.copilotIntegration.package.artifact.integrity = 'sha512-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=='
        $forged | ConvertTo-Json -Depth 60 | Set-Content $path
        { Get-DshOfficialDesktopPluginContract -LockPath $path } |
            Should -Throw '*sri-sha512-mismatch*'
    }
}

Describe 'Official Desktop plugin artifact and transaction' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..\tools\DshOfficialDesktopPluginProvisioning.psm1') -Force
    }

    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:homeRoot = Join-Path $root 'home'
        $script:install = Join-Path $root 'install'
        $script:data = Join-Path $root 'data'
        $script:seed = Join-Path $install 'resources\seed'
        $script:artifactRoot = Join-Path $root 'artifact-source'
        $script:artifact = Join-Path $root 'dsh-github-copilot-0.4.0-alpha.18.tgz'
        New-Item -ItemType Directory -Path $seed,(Join-Path $seed 'desktop-packages'),(Join-Path $artifactRoot 'package'),(Join-Path $install 'resources\runtime\node'),(Join-Path $install 'resources\runtime\pnpm\bin') -Force | Out-Null
        foreach ($file in @('desktop-release.json','desktop-packages.json','integrity.json')) {
            '{}' | Set-Content (Join-Path $seed $file)
        }
        @'
{
  "name": "@deepseek-ai/dsh-desktop-runtime",
  "private": true,
  "version": "0.1.5-rc.2",
  "dependencies": {},
  "dsh": { "profile": { "bundles": ["@deepseek-ai/dsh-base", "@deepseek-ai/dsh-web-app"] } }
}
'@ | Set-Content (Join-Path $seed 'package.json')
        "lockfileVersion: '9.0'" | Set-Content (Join-Path $seed 'pnpm-lock.yaml')
        "packages:`n  - ." | Set-Content (Join-Path $seed 'pnpm-workspace.yaml')
        'core' | Set-Content (Join-Path $seed 'desktop-packages\core.tgz')
        @'
{
  "name": "dsh-github-copilot",
  "version": "0.4.0-alpha.18",
  "main": "lib/index.js",
  "types": "lib/types/index.d.ts",
  "dsh": { "bundle": { "patch": "./cordis.patch.yml" } },
  "scripts": { "test": "vitest run" }
}
'@ | Set-Content (Join-Path $artifactRoot 'package\package.json')
        '[]' | Set-Content (Join-Path $artifactRoot 'package\cordis.patch.yml')
        Push-Location $artifactRoot
        try { & tar -czf $artifact package; if ($LASTEXITCODE -ne 0) { throw 'fixture-tar-failed' } }
        finally { Pop-Location }
        '' | Set-Content (Join-Path $install 'resources\runtime\node\node.exe')
        '' | Set-Content (Join-Path $install 'resources\runtime\pnpm\bin\pnpm.mjs')
        $script:ops = Get-DshOfficialDesktopPluginOperations
        $ops.GetProcesses = { [pscustomobject]@{ unavailable = $false; items = @() } }
        $ops.IsCurrentUserOwner = { param($path) $true }
        $ops.TestReparse = { param($path) $false }
        $ops.GetLength = { param($path) 538911 }
        $ops.GetHash = {
            param($path,$algorithm)
            if ($algorithm -ceq 'SHA512') {
                '15975665b6ff2bc8e613ae06c1bf5953e5000c0a9a9007ea2d7aebbbfaa92c5492e2a0b82cc3b4b88714d4a6ecc350a0e79c5fd2af9949b9f4cb771dc83ccb5f'
            } else {
                '2ca4f604e89eda3000cf2a51d79871cee3cb721fa6f4324fc9a1197926c359a8'
            }
        }
        $runLog = [Collections.Generic.List[object]]::new()
        $script:runs = $runLog
        $ops.Run = {
            param($file,$arguments,$workingDirectory,$environment)
            $runLog.Add([pscustomobject]@{
                file=$file
                arguments=@($arguments)
                workingDirectory=$workingDirectory
                environment=@{}+$environment
            })
            if ($arguments[0] -like '*pnpm.mjs') {
                foreach ($package in @(
                    @('@deepseek-ai\dsh','@deepseek-ai/dsh','0.1.5-rc.2'),
                    @('@deepseek-ai\dsh-desktop-host','@deepseek-ai/dsh-desktop-host','0.1.5-rc.2')
                )) {
                    $target=Join-Path $workingDirectory ('node_modules\'+$package[0])
                    New-Item -ItemType Directory -Path $target -Force|Out-Null
                    @{name=$package[1];version=$package[2]}|ConvertTo-Json|Set-Content (Join-Path $target 'package.json')
                }
                if (@($arguments | Where-Object { $_ -like '*dsh-github-copilot-0.4.0-alpha.18.tgz' }).Count -eq 1) {
                    $target=Join-Path $workingDirectory 'node_modules\dsh-github-copilot'
                    New-Item -ItemType Directory -Path $target -Force|Out-Null
                    @{
                        name='dsh-github-copilot';version='0.4.0-alpha.18'
                        dsh=@{bundle=@{patch='./cordis.patch.yml'}}
                    }|ConvertTo-Json -Depth 5|Set-Content (Join-Path $target 'package.json')
                    '[]'|Set-Content (Join-Path $target 'cordis.patch.yml')
                }
            }
            [pscustomobject]@{ExitCode=0}
        }.GetNewClosure()
    }

    It 'keeps Check read-only and reports the verified locked local artifact' {
        $before = @(Get-ChildItem $root -Recurse -Force).Count
        $check = Get-DshOfficialDesktopPluginProvisioningCheck -DshHome $homeRoot -InstallRoot $install `
            -DataRoot $data -ArtifactPath $artifact -Operations $ops
        $check.status | Should -Be 'ready'
        $check.artifact.valid | Should -BeTrue
        $check.mutated | Should -BeFalse
        @(Get-ChildItem $root -Recurse -Force).Count | Should -Be $before
        Test-Path (Join-Path $homeRoot 'profiles\desktop') | Should -BeFalse
    }

    It 'rejects artifact name, hash, lifecycle, traversal, and redirect-host drift' {
        $wrongName = Join-Path $root 'wrong.tgz'
        Copy-Item -LiteralPath $artifact -Destination $wrongName
        (Test-DshOfficialDesktopPluginArtifact -Path $wrongName -Operations $ops).reason |
            Should -Be 'desktop-plugin-artifact-name-mismatch'

        $badHashOps = $ops.Clone()
        $badHashOps.GetHash = { param($path,$algorithm) '0' * $(if ($algorithm -ceq 'SHA512') { 128 } else { 64 }) }
        (Test-DshOfficialDesktopPluginArtifact -Path $artifact -Operations $badHashOps).reason |
            Should -Be 'desktop-plugin-artifact-sha256-mismatch'

        $manifest = Get-Content (Join-Path $artifactRoot 'package\package.json') -Raw | ConvertFrom-Json
        $manifest.scripts | Add-Member -NotePropertyName install -NotePropertyValue 'node install.js'
        $manifest | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $artifactRoot 'package\package.json')
        Remove-Item -LiteralPath $artifact
        Push-Location $artifactRoot
        try { & tar -czf $artifact package }
        finally { Pop-Location }
        (Test-DshOfficialDesktopPluginArtifact -Path $artifact -Operations $ops).reason |
            Should -Be 'desktop-plugin-lifecycle-hook-forbidden:install'

        [IO.File]::WriteAllBytes($artifact, [Convert]::FromBase64String(
            'H4sIAAAAAAAC/+3TQW7DIBAFUI5isa7H2HGiKrfBgGJa2yCDq0SR715MW1XKppsmUtX/NgPzkWbDeKle5clU/qPSS3AT+2UiObRtrsltFc3++5z7dX1odqwQ7AGWEOWcxrP/6conORp+LLgOfXmysV+6UjlvBxf5U8HfzBysm7YHgloSpRx8L6l+3sJR2pwMtqvspM05fZ+tHy/ehK8gXz5jTTE/SLNSfOXdMunB5KOXUW1NTpVys7aBcocu48DXdWVwF0SVCUp6Q/Ec7zTjp/0XYnez/6LeN9j/R+ikxhIAAAAAAAAAAAAAAAAAAAAA/GHvkTYzTgAoAAA='))
        (Test-DshOfficialDesktopPluginArtifact -Path $artifact -Operations $ops).reason |
            Should -Be 'desktop-plugin-artifact-path-traversal'

        { &$ops.Download 'https://example.invalid/plugin.tgz' (Join-Path $root 'download.tgz') @('github.com') } |
            Should -Throw '*download-host-not-allowed*'
    }

    It 'builds staging through pnpm, health checks, atomically activates, and writes a receipt' {
        $sharedHome = Join-Path $root 'shared-default-home'
        New-Item -ItemType Directory -Path $sharedHome -Force | Out-Null
        'preserve' | Set-Content (Join-Path $sharedHome 'sentinel.txt')
        $oldDshHome,$oldHome,$oldUserProfile,$oldAppData,$oldLocalAppData =
            $env:DSH_HOME,$env:HOME,$env:USERPROFILE,$env:APPDATA,$env:LOCALAPPDATA
        $env:DSH_HOME=$sharedHome;$env:HOME=$sharedHome;$env:USERPROFILE=$sharedHome
        $env:APPDATA=Join-Path $sharedHome 'Roaming';$env:LOCALAPPDATA=Join-Path $sharedHome 'Local'
        try {
        $result = Invoke-DshOfficialDesktopPluginProvisioning -Action Apply -DshHome $homeRoot `
            -InstallRoot $install -DataRoot $data -ArtifactPath $artifact -Operations $ops
        } finally {
            $env:DSH_HOME=$oldDshHome;$env:HOME=$oldHome;$env:USERPROFILE=$oldUserProfile
            $env:APPDATA=$oldAppData;$env:LOCALAPPDATA=$oldLocalAppData
        }
        $result.status | Should -Be 'complete'
        $result.receipt.registry | Should -Be 'https://packagefeedproxy.microsoft.io/npm/'
        $result.receipt.sharedHomeContentRead | Should -BeFalse
        $pnpmRuns = @($runs | Where-Object { $_.arguments[0] -like '*pnpm.mjs' })
        $pnpmRuns.Count | Should -BeGreaterOrEqual 2
        @($pnpmRuns | Where-Object { $_.arguments -contains '--offline' }).Count | Should -Be 0
        @($pnpmRuns | Where-Object {
            $_.environment.NPM_CONFIG_REGISTRY -cne 'https://packagefeedproxy.microsoft.io/npm/' -or
            $_.arguments -notcontains '--config.registry=https://packagefeedproxy.microsoft.io/npm/'
        }).Count | Should -Be 0
        $profile = Join-Path $homeRoot 'profiles\desktop'
        (Get-Content (Join-Path $profile 'package.json') -Raw | ConvertFrom-Json).dsh.profile.bundles |
            Should -Be @('@deepseek-ai/dsh-base','@deepseek-ai/dsh-web-app','dsh-github-copilot')
        Test-Path (Join-Path $profile 'node_modules\dsh-github-copilot\package.json') | Should -BeTrue
        Test-Path (Join-Path $homeRoot 'desktop\pending.json') | Should -BeFalse
        Test-Path (Join-Path $homeRoot 'desktop\rollback\profile') | Should -BeFalse
        Get-Content (Join-Path $sharedHome 'sentinel.txt') | Should -Be 'preserve'
        @(Get-ChildItem $sharedHome -Force).Count | Should -Be 1
        $healthRuns = @($runs | Where-Object { $_.arguments[0] -like '*dsh-official-desktop-plugin-health.mjs' })
        $healthRuns.Count | Should -Be 2
        foreach ($run in $healthRuns) {
            $run.environment.DSH_HOME | Should -Not -Be $sharedHome
            $run.environment.HOME | Should -Be $run.environment.DSH_HOME
            $run.environment.USERPROFILE | Should -Be $run.environment.DSH_HOME
            $healthRoot = Split-Path $run.environment.DSH_HOME -Parent
            $run.environment.APPDATA | Should -Be (Join-Path $healthRoot 'appdata\Roaming')
            $run.environment.LOCALAPPDATA | Should -Be (Join-Path $healthRoot 'appdata\Local')
            Test-Path (Split-Path $run.environment.DSH_HOME -Parent) | Should -BeFalse
        }
    }

    It 'leaves the active profile unchanged when staging dependency installation fails' {
        $profile = Join-Path $homeRoot 'profiles\desktop'
        New-Item -ItemType Directory -Path (Join-Path $profile 'desktop-packages') -Force | Out-Null
        Copy-Item (Join-Path $seed '*') $profile -Recurse -Force
        'original' | Set-Content (Join-Path $profile 'original.txt')
        $baseRun = $ops.Run
        $ops.Run = {
            param($file,$arguments,$workingDirectory,$environment)
            if ($arguments[0] -like '*pnpm.mjs' -and
                @($arguments | Where-Object { $_ -like '*dsh-github-copilot-0.4.0-alpha.18.tgz' }).Count -eq 1) {
                return [pscustomobject]@{ExitCode=1}
            }
            &$baseRun $file $arguments $workingDirectory $environment
        }.GetNewClosure()
        { Invoke-DshOfficialDesktopPluginProvisioning -Action Apply -DshHome $homeRoot `
            -InstallRoot $install -DataRoot $data -ArtifactPath $artifact -Operations $ops } |
            Should -Throw '*desktop-plugin-pnpm-failed:1*'
        Get-Content (Join-Path $profile 'original.txt') | Should -Be 'original'
        Test-Path (Join-Path $homeRoot 'desktop\pending.json') | Should -BeFalse
    }

    It 'restores the previous profile when active health fails' {
        $profile = Join-Path $homeRoot 'profiles\desktop'
        New-Item -ItemType Directory -Path (Join-Path $profile 'desktop-packages'),(Join-Path $profile 'node_modules\old-plugin') -Force|Out-Null
        Copy-Item (Join-Path $seed '*') $profile -Recurse -Force
        $manifest=Get-Content (Join-Path $profile 'package.json') -Raw|ConvertFrom-Json
        $manifest.dsh.profile.bundles+= 'old-plugin'
        $manifest|ConvertTo-Json -Depth 10|Set-Content (Join-Path $profile 'package.json')
        '{"name":"old-plugin","version":"1.0.0","dsh":{"bundle":{"patch":"./cordis.patch.yml"}}}'|Set-Content (Join-Path $profile 'node_modules\old-plugin\package.json')
        '[]'|Set-Content (Join-Path $profile 'node_modules\old-plugin\cordis.patch.yml')
        'original'|Set-Content (Join-Path $profile 'original.txt')
        $script:healthRuns=0
        $baseRun=$ops.Run
        $ops.Run={
            param($file,$arguments,$workingDirectory,$environment)
            if($arguments[0] -like '*dsh-official-desktop-plugin-health.mjs'){
                $script:healthRuns++
                return [pscustomobject]@{ExitCode=$(if($script:healthRuns-eq2){1}else{0})}
            }
            if($arguments[0] -like '*pnpm.mjs' -and ($arguments -contains 'old-plugin@1.0.0')){
                $target=Join-Path $workingDirectory 'node_modules\old-plugin'
                New-Item -ItemType Directory -Path $target -Force|Out-Null
                '{"name":"old-plugin","version":"1.0.0","dsh":{"bundle":{"patch":"./cordis.patch.yml"}}}'|Set-Content (Join-Path $target 'package.json')
                '[]'|Set-Content (Join-Path $target 'cordis.patch.yml')
            }
            &$baseRun $file $arguments $workingDirectory $environment
        }.GetNewClosure()
        {Invoke-DshOfficialDesktopPluginProvisioning -Action Apply -DshHome $homeRoot `
            -InstallRoot $install -DataRoot $data -ArtifactPath $artifact -Operations $ops} |
            Should -Throw '*active-health-failed*'
        Get-Content (Join-Path $profile 'original.txt') | Should -Be 'original'
        Test-Path (Join-Path $homeRoot 'desktop\pending.json') | Should -BeFalse
        Test-Path (Join-Path $homeRoot 'desktop\rollback\profile') | Should -BeFalse
    }

    It 'restores the previous profile and receipt when receipt commit fails' {
        $profile = Join-Path $homeRoot 'profiles\desktop'
        New-Item -ItemType Directory -Path (Join-Path $profile 'desktop-packages') -Force | Out-Null
        Copy-Item (Join-Path $seed '*') $profile -Recurse -Force
        'original' | Set-Content (Join-Path $profile 'original.txt')
        New-Item -ItemType Directory -Path $data -Force | Out-Null
        $receiptPath = Join-Path $data 'official-desktop-plugin-provisioning.json'
        '{"status":"previous"}' | Set-Content $receiptPath
        $baseWrite = $ops.WriteJsonAtomic
        $ops.WriteJsonAtomic = {
            param($path,$value)
            if ($path -ceq $receiptPath) { throw 'simulated-receipt-write-failure' }
            &$baseWrite $path $value
        }.GetNewClosure()

        { Invoke-DshOfficialDesktopPluginProvisioning -Action Apply -DshHome $homeRoot `
            -InstallRoot $install -DataRoot $data -ArtifactPath $artifact -Operations $ops } |
            Should -Throw '*simulated-receipt-write-failure*'
        Get-Content (Join-Path $profile 'original.txt') | Should -Be 'original'
        (Get-Content $receiptPath -Raw | ConvertFrom-Json).status | Should -Be 'previous'
        Test-Path (Join-Path $homeRoot 'desktop\pending.json') | Should -BeFalse
        Test-Path (Join-Path $homeRoot 'desktop\rollback\profile') | Should -BeFalse
    }

    It 'retains a receipt-committed journal when finalization cannot remove it' {
        $profile = Join-Path $homeRoot 'profiles\desktop'
        New-Item -ItemType Directory -Path (Join-Path $profile 'desktop-packages') -Force | Out-Null
        Copy-Item (Join-Path $seed '*') $profile -Recurse -Force
        'original' | Set-Content (Join-Path $profile 'original.txt')
        $pendingPath = Join-Path $homeRoot 'desktop\pending.json'
        $baseRemoveFile = $ops.RemoveFile
        $ops.RemoveFile = {
            param($path)
            if ($path -ceq $pendingPath) { throw 'simulated-pending-remove-failure' }
            &$baseRemoveFile $path
        }.GetNewClosure()

        { Invoke-DshOfficialDesktopPluginProvisioning -Action Apply -DshHome $homeRoot `
            -InstallRoot $install -DataRoot $data -ArtifactPath $artifact -Operations $ops } |
            Should -Throw '*finalization-recovery-required*'
        Test-Path $pendingPath | Should -BeTrue
        (Get-Content $pendingPath -Raw | ConvertFrom-Json).step | Should -Be 'receipt-committed'
        Test-Path (Join-Path $profile 'original.txt') | Should -BeFalse
        Test-Path (Join-Path $homeRoot 'desktop\rollback\profile') | Should -BeFalse
        (Get-Content (Join-Path $data 'official-desktop-plugin-provisioning.json') -Raw | ConvertFrom-Json).status |
            Should -Be 'complete'
    }
}
