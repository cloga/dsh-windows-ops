Import-Module (Join-Path $PSScriptRoot '..\tools\DshOfficialDesktopPluginProvisioning.psm1') -Force

Describe 'Official Desktop plugin provisioning contract' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..\tools\DshOfficialDesktopPluginProvisioning.psm1') -Force
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
        $script:lockPath = Join-Path $repoRoot 'deployments\windows-copilot.lock.json'
    }

    It 'loads one complete immutable Release contract and keeps Windows Ops/native modes exclusive' {
        $contract = Get-DshOfficialDesktopPluginContract -LockPath $lockPath
        $contract.mode | Should -Be 'desktopNativeVerifiedRelease'
        $contract.registry | Should -BeNullOrEmpty
        $contract.nativeCapability.verified | Should -BeTrue
        $contract.nativeCapability.capability.id | Should -Be 'desktopNativeVerifiedRelease'
        $contract.nativeCapability.capability.automaticProvisioning | Should -BeFalse
        $contract.package.version | Should -Be '0.4.0-alpha.30'
        $contract.artifact.releaseImmutable | Should -BeTrue
        $contract.artifact.releaseTag | Should -Be 'v0.4.0-alpha.30'
        $contract.artifact.releaseCommit | Should -Be 'b75eac570cd418497c52e80a3ce47958cdcc6b26'
        $contract.artifact.sha256 | Should -Be '12af04aa61caef9a8c8e92526d6e3d9ec94b1d624097138540bcd5fd7cc29207'
        $contract.artifact.sha512 | Should -Be '32e90b9a84122146ece16955545db830953de1bfc7a317a612416dacfeb0922585a11c22898a8a0ea2c19de956e311889556719ffcae227b757bf3c62d3be67b'
        $contract.artifact.integrity | Should -Be 'sha512-MukLmoQSIUbs4WlVVF24MJU94b/HoxemEkFtrP6wkiWFoRwiiYqKDqLBnelW4xGIlVZxn/yuInt1e/PGLTvmew=='

        $forged = Get-Content $lockPath -Raw | ConvertFrom-Json
        $forged.components.copilotIntegration.desktopProvisioning.mode = 'windowsOpsVerifiedRelease'
        $forged.components.copilotIntegration.desktopProvisioning.registry = 'https://packagefeedproxy.microsoft.io/npm/'
        $forged.components.copilotIntegration.desktopProvisioning.allowedRedirectHosts =
            @('github.com','release-assets.githubusercontent.com')
        $forged.components.copilotIntegration.desktopProvisioning.nativeCapability.verified = $true
        $path = Join-Path $TestDrive 'both-active.json'
        $forged | ConvertTo-Json -Depth 60 | Set-Content $path
        { Get-DshOfficialDesktopPluginContract -LockPath $path } |
            Should -Throw '*native-capability-mode-mismatch*'

        $forged.components.copilotIntegration.desktopProvisioning.mode = 'desktopNativeVerifiedRelease'
        $forged.components.copilotIntegration.desktopProvisioning.registry = $null
        $forged.components.copilotIntegration.desktopProvisioning.allowedRedirectHosts =
            @('github.com','objects.githubusercontent.com','release-assets.githubusercontent.com')
        $forged.components.copilotIntegration.desktopProvisioning.nativeCapability.verified = $false
        $forged | ConvertTo-Json -Depth 60 | Set-Content $path
        { Get-DshOfficialDesktopPluginContract -LockPath $path } |
            Should -Throw '*native-provisioning-capability-unverified*'
    }

    It 'rejects a stale alpha24 version-only lock regression' {
        $forged = Get-Content $lockPath -Raw | ConvertFrom-Json
        $forged.components.copilotIntegration.package.version = '0.4.0-alpha.24'
        $path = Join-Path $TestDrive 'version-only.json'
        $forged | ConvertTo-Json -Depth 60 | Set-Content $path
        { Get-DshOfficialDesktopPluginContract -LockPath $path } |
            Should -Throw '*artifact-contract-invalid*'
    }

    It 'rejects checksum manifest and SRI drift in the authoritative contract' {
        $forged = Get-Content $lockPath -Raw | ConvertFrom-Json
        $path = Join-Path $TestDrive 'artifact-drift.json'
        $forged.components.copilotIntegration.package.artifact.checksumManifest.url = 'https://github.com/cloga/dsh-github-copilot/releases/download/v0.4.0-alpha.30/OTHER'
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
        $script:artifact = Join-Path $root 'dsh-github-copilot-0.4.0-alpha.30.tgz'
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
  "version": "0.4.0-alpha.30",
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
        $ops.GetLength = { param($path) 694316 }
        $ops.GetHash = {
            param($path,$algorithm)
            if ($algorithm -ceq 'SHA512') {
                '32e90b9a84122146ece16955545db830953de1bfc7a317a612416dacfeb0922585a11c22898a8a0ea2c19de956e311889556719ffcae227b757bf3c62d3be67b'
            } else {
                '12af04aa61caef9a8c8e92526d6e3d9ec94b1d624097138540bcd5fd7cc29207'
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
                if (@($arguments | Where-Object { $_ -like '*dsh-github-copilot-0.4.0-alpha.30.tgz' }).Count -eq 1) {
                    $target=Join-Path $workingDirectory 'node_modules\dsh-github-copilot'
                    New-Item -ItemType Directory -Path $target -Force|Out-Null
                    @{
                        name='dsh-github-copilot';version='0.4.0-alpha.30'
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

    It 'delegates Apply to the native Desktop capability without mutating the profile' {
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
        $result.status | Should -Be 'delegated'
        $result.delegatedToDesktop | Should -BeTrue
        $result.mutated | Should -BeFalse
        $pnpmRuns = @($runs | Where-Object { $_.arguments[0] -like '*pnpm.mjs' })
        $pnpmRuns.Count | Should -Be 0
        $profile = Join-Path $homeRoot 'profiles\desktop'
        Test-Path (Join-Path $profile 'package.json') | Should -BeFalse
        Test-Path (Join-Path $profile 'node_modules\dsh-github-copilot\package.json') | Should -BeFalse
        Test-Path (Join-Path $homeRoot 'desktop\pending.json') | Should -BeFalse
        Test-Path (Join-Path $homeRoot 'desktop\rollback\profile') | Should -BeFalse
        Get-Content (Join-Path $sharedHome 'sentinel.txt') | Should -Be 'preserve'
        @(Get-ChildItem $sharedHome -Force).Count | Should -Be 1
        $healthRuns = @($runs | Where-Object { $_.arguments[0] -like '*dsh-official-desktop-plugin-health.mjs' })
        $healthRuns.Count | Should -Be 0
    }

    It 'does not enter the legacy pnpm failure path in native delegated mode' {
        $profile = Join-Path $homeRoot 'profiles\desktop'
        New-Item -ItemType Directory -Path (Join-Path $profile 'desktop-packages') -Force | Out-Null
        Copy-Item (Join-Path $seed '*') $profile -Recurse -Force
        'original' | Set-Content (Join-Path $profile 'original.txt')
        $baseRun = $ops.Run
        $ops.Run = {
            param($file,$arguments,$workingDirectory,$environment)
            if ($arguments[0] -like '*pnpm.mjs' -and
                @($arguments | Where-Object { $_ -like '*dsh-github-copilot-0.4.0-alpha.30.tgz' }).Count -eq 1) {
                return [pscustomobject]@{ExitCode=1}
            }
            &$baseRun $file $arguments $workingDirectory $environment
        }.GetNewClosure()
        $result = Invoke-DshOfficialDesktopPluginProvisioning -Action Apply -DshHome $homeRoot `
            -InstallRoot $install -DataRoot $data -ArtifactPath $artifact -Operations $ops
        $result.status | Should -Be 'delegated'
        $result.mutated | Should -BeFalse
        Get-Content (Join-Path $profile 'original.txt') | Should -Be 'original'
        Test-Path (Join-Path $homeRoot 'desktop\pending.json') | Should -BeFalse
    }

    It 'does not enter the legacy active-health rollback path in native delegated mode' {
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
        $result = Invoke-DshOfficialDesktopPluginProvisioning -Action Apply -DshHome $homeRoot `
            -InstallRoot $install -DataRoot $data -ArtifactPath $artifact -Operations $ops
        $result.status | Should -Be 'delegated'
        $result.mutated | Should -BeFalse
        Get-Content (Join-Path $profile 'original.txt') | Should -Be 'original'
        Test-Path (Join-Path $homeRoot 'desktop\pending.json') | Should -BeFalse
        Test-Path (Join-Path $homeRoot 'desktop\rollback\profile') | Should -BeFalse
    }

    It 'does not write legacy receipts in native delegated mode' {
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

        $result = Invoke-DshOfficialDesktopPluginProvisioning -Action Apply -DshHome $homeRoot `
            -InstallRoot $install -DataRoot $data -ArtifactPath $artifact -Operations $ops
        $result.status | Should -Be 'delegated'
        $result.mutated | Should -BeFalse
        Get-Content (Join-Path $profile 'original.txt') | Should -Be 'original'
        (Get-Content $receiptPath -Raw | ConvertFrom-Json).status | Should -Be 'previous'
        Test-Path (Join-Path $homeRoot 'desktop\pending.json') | Should -BeFalse
        Test-Path (Join-Path $homeRoot 'desktop\rollback\profile') | Should -BeFalse
    }

    It 'does not create a legacy provisioning journal in native delegated mode' {
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

        $result = Invoke-DshOfficialDesktopPluginProvisioning -Action Apply -DshHome $homeRoot `
            -InstallRoot $install -DataRoot $data -ArtifactPath $artifact -Operations $ops
        $result.status | Should -Be 'delegated'
        $result.mutated | Should -BeFalse
        Test-Path $pendingPath | Should -BeFalse
        Test-Path (Join-Path $profile 'original.txt') | Should -BeTrue
        Test-Path (Join-Path $homeRoot 'desktop\rollback\profile') | Should -BeFalse
        Test-Path (Join-Path $data 'official-desktop-plugin-provisioning.json') | Should -BeFalse
    }
}
