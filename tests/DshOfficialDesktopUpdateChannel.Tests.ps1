Import-Module (Join-Path $PSScriptRoot '..\tools\DshOfficialDesktopBuild.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\tools\DshOfficialDesktopUpdateChannel.psm1') -Force

Describe 'Official Desktop local managed update channel' {
    BeforeEach {
        $script:policy=Get-DshOfficialDesktopBuildPolicy
        $script:buildRoot=Join-Path $TestDrive 'build'
        $script:sourceRoot=Join-Path $buildRoot 'source'
        $script:packageRoot=Join-Path $buildRoot 'package-source'
        $script:installer=Join-Path $packageRoot $policy.localPackage.installerName
        $script:receiptPath=Join-Path $packageRoot 'package.json'
        New-Item -ItemType Directory -Path $packageRoot -Force|Out-Null
        [IO.File]::WriteAllBytes($installer,[byte[]](1,2,3,4,5))
        $installerHash=(Get-FileHash $installer -Algorithm SHA256).Hash.ToLowerInvariant()
        $script:receipt=[pscustomobject][ordered]@{
            schemaVersion=1;action='packagelocal';status='complete';createdUtc='2026-09-14T00:00:00Z'
            source=[pscustomobject]@{repository=$policy.repository;tag=$policy.tag;commit=$policy.commit;tree=$policy.tree;clean=$true;lockfileSha256='a'*64}
            tools=[pscustomobject]@{};commands=@();artifacts=@();validation=[pscustomobject]@{}
            releaseBoundary=[pscustomobject]@{officialIdentityClaim=$false;officialSignature=$false;updateChannel=$false;packageCreated=$true;status='local-build-complete';reason='fixture'}
            registryRouting=[pscustomobject]@{}
            localPackage=[pscustomobject]@{
                installerPath=$installer;installerSignature='NotSigned';executablePath=(Join-Path $sourceRoot 'apps\desktop\.desktop-build\targets\win-x64\artifacts\win-unpacked\DeepSeek Harness.exe');executableSignature='NotSigned';appUpdatePresent=$false
                identity=[pscustomobject]@{appId=$policy.localPackage.appId;packageName=$policy.localPackage.packageName;productName=$policy.localPackage.productName}
                seed=[pscustomobject]@{version=$policy.version;hostProtocolVersion=3;nodeVersion='24.17.0';pnpmVersion='11.7.0'}
                hashes=[pscustomobject]@{installer=$installerHash;appAsar='b'*64;executable='c'*64;seed='d'*64;overlay='e'*64}
            }
            receiptSha256='f'*64
        }
        $receipt|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $receiptPath
        $script:ops=Get-DshOfficialDesktopUpdateChannelOperations
        $script:validatedSources=[Collections.Generic.List[string]]::new()
        $ops.InvokeBuild={param($root,$registry,$pnpm)[pscustomobject]@{action='packagelocal';status='complete';receiptPath=$script:receiptPath;sourceRoot=$script:sourceRoot}}
        $ops.ValidateBuildReceipt={param($path,$source,$pnpm,$recordedOnly)$script:validatedSources.Add([string]$source);$true}
        $ops.GetSignature={param($path)'NotSigned'}
    }

    It 'uses a strictly increasing local channel version without changing the upstream version' {
        Get-DshOfficialDesktopLocalChannelVersion 1|Should -Be '0.1.5-rc.2.local.1'
        Get-DshOfficialDesktopLocalChannelVersion 12|Should -Be '0.1.5-rc.2.local.12'
        {Get-DshOfficialDesktopLocalChannelVersion 0}|Should -Throw
    }

    It 'requires a credential-free HTTPS feed base URL' {
        foreach($url in @('http://example.test/feed/','relative','https://user@example.test/feed/','https://example.test/feed/?token=x')){
            {New-DshOfficialDesktopUpdateBundle -Sequence 1 -FeedBaseUrl $url -BuildRoot $buildRoot -Operations $ops}|Should -Throw '*feed-base-url*'
        }
    }

    It 'creates a deterministic generic-provider bundle without enabling the native updater' {
        $result=New-DshOfficialDesktopUpdateBundle -Sequence 7 -FeedBaseUrl 'https://github.com/cloga/dsh-windows-ops/releases/download/dsh-local-0.1.5-rc.2.local.7/' -BuildRoot $buildRoot -Operations $ops
        $result.status|Should -Be 'complete'
        $result.channelVersion|Should -Be '0.1.5-rc.2.local.7'
        $result.publicationPerformed|Should -BeFalse
        $result.nativeUpdaterEnabled|Should -BeFalse
        $verified=Test-DshOfficialDesktopUpdateBundle -BundleRoot $result.bundleRoot -Operations $ops
        $verified.valid|Should -BeTrue -Because $verified.reason
        $verified.manifest.security.applyMode|Should -Be 'manual'
        $verified.manifest.security.signatureRequiredForNativeUpdater|Should -BeTrue
        $verified.manifest.installer.signature|Should -Be 'NotSigned'
        Get-Content $verified.feedPath -Raw|Should -Match 'version: 0\.1\.5-rc\.2\.local\.7'
        Get-Content $verified.feedPath -Raw|Should -Match 'sha512: [A-Za-z0-9+/]+=='
        @(Get-ChildItem $result.bundleRoot -File|Select-Object -ExpandProperty Name|Sort-Object)|Should -Be @('build-receipt.json','dsh-local-build-0.1.5-rc.2.local.7-win-x64.exe','rc.yml','release.json')
    }

    It 'detects tampering and stages only an explicitly acknowledged manifest' {
        $result=New-DshOfficialDesktopUpdateBundle -Sequence 8 -FeedBaseUrl 'https://downloads.example.test/dsh/' -BuildRoot $buildRoot -Operations $ops
        $manifest=Get-Content $result.manifestPath -Raw|ConvertFrom-Json
        $dataRoot=Join-Path $TestDrive 'data'
        {Save-DshOfficialDesktopStagedUpdate -BundleRoot $result.bundleRoot -DataRoot $dataRoot -AcknowledgeManifestSha256 ('sha256:'+'0'*64) -Operations $ops}|Should -Throw '*acknowledgment*'
        $stage=Save-DshOfficialDesktopStagedUpdate -BundleRoot $result.bundleRoot -DataRoot $dataRoot -AcknowledgeManifestSha256 ('sha256:'+$manifest.manifestSha256) -Operations $ops
        $stage.status|Should -Be 'complete';$stage.completeAfterManualInstall|Should -BeTrue
        $again=Save-DshOfficialDesktopStagedUpdate -BundleRoot $result.bundleRoot -DataRoot $dataRoot -AcknowledgeManifestSha256 ('sha256:'+$manifest.manifestSha256) -Operations $ops
        $again.status|Should -Be 'verified';$again.idempotent|Should -BeTrue
        @($script:validatedSources|Where-Object{$_ -ceq $script:sourceRoot}).Count|Should -BeGreaterThan 1
        [IO.File]::AppendAllText($stage.installerPath,'tamper')
        (Test-DshOfficialDesktopUpdateBundle -BundleRoot $stage.stageRoot -Operations $ops).valid|Should -BeFalse
    }

    It 'compares the monotonic sequence read-only against schema-3 install metadata' {
        $result=New-DshOfficialDesktopUpdateBundle -Sequence 9 -FeedBaseUrl 'https://downloads.example.test/dsh/' -BuildRoot $buildRoot -Operations $ops
        $dataRoot=Join-Path $TestDrive 'data';New-Item -ItemType Directory $dataRoot -Force|Out-Null
        @{schemaVersion=3;updateChannel=@{owner='cloga/dsh-windows-ops';sequence=8}}|ConvertTo-Json|Set-Content (Join-Path $dataRoot 'official-desktop-local-install.json')
        $check=Get-DshOfficialDesktopUpdateChannelCheck -BundleRoot $result.bundleRoot -DataRoot $dataRoot -Operations $ops
        $check.status|Should -Be 'ready';$check.updateAvailable|Should -BeTrue;$check.mutated|Should -BeFalse
        @{schemaVersion=3;updateChannel=@{owner='cloga/dsh-windows-ops';sequence=9}}|ConvertTo-Json|Set-Content (Join-Path $dataRoot 'official-desktop-local-install.json')
        (Get-DshOfficialDesktopUpdateChannelCheck -BundleRoot $result.bundleRoot -DataRoot $dataRoot -Operations $ops).updateAvailable|Should -BeFalse
    }

    It 'checks a remote manifest without downloading the installer or mutating the data root' {
        $result=New-DshOfficialDesktopUpdateBundle -Sequence 20 -FeedBaseUrl 'https://downloads.example.test/dsh/' -BuildRoot $buildRoot -Operations $ops
        $dataRoot=Join-Path $TestDrive 'remote-check-data'
        $script:downloads=[Collections.Generic.List[string]]::new()
        $ops.DownloadFile={
            param($uri,$destination)
            $script:downloads.Add([string]$uri)
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force|Out-Null
            Copy-Item -LiteralPath $result.manifestPath -Destination $destination -Force
        }
        $check=Get-DshOfficialDesktopRemoteUpdateChannelCheck -ManifestUrl 'https://downloads.example.test/dsh/release.json' -DataRoot $dataRoot -Operations $ops
        $check.status|Should -Be 'ready'
        $check.updateAvailable|Should -BeTrue
        $check.downloadRequired|Should -BeTrue
        $check.mutated|Should -BeFalse
        $script:downloads|Should -Be @('https://downloads.example.test/dsh/release.json')
        Test-Path $dataRoot|Should -BeFalse
    }

    It 'downloads and revalidates every declared artifact before making the bundle visible' {
        $result=New-DshOfficialDesktopUpdateBundle -Sequence 21 -FeedBaseUrl 'https://downloads.example.test/dsh/' -BuildRoot $buildRoot -Operations $ops
        $sourceBundle=$result.bundleRoot
        $dataRoot=Join-Path $TestDrive 'download-data'
        $ops.DownloadFile={
            param($uri,$destination)
            $name=[Uri]::UnescapeDataString(([Uri]$uri).Segments[-1])
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force|Out-Null
            Copy-Item -LiteralPath (Join-Path $sourceBundle $name) -Destination $destination -Force
        }
        $download=Receive-DshOfficialDesktopUpdateBundle -ManifestUrl 'https://downloads.example.test/dsh/release.json' -DataRoot $dataRoot -Operations $ops
        $download.status|Should -Be 'complete'
        $verified=Test-DshOfficialDesktopUpdateBundle -BundleRoot $download.bundleRoot -Operations $ops
        $verified.valid|Should -BeTrue -Because $verified.reason
        $again=Receive-DshOfficialDesktopUpdateBundle -ManifestUrl 'https://downloads.example.test/dsh/release.json' -DataRoot $dataRoot -Operations $ops
        $again.status|Should -Be 'verified'
        $again.idempotent|Should -BeTrue
    }

    It 'uses one explicit interactive installer launch and then reuses strict completion' {
        $result=New-DshOfficialDesktopUpdateBundle -Sequence 22 -FeedBaseUrl 'https://downloads.example.test/dsh/' -BuildRoot $buildRoot -Operations $ops
        $dataRoot=Join-Path $TestDrive 'install-data'
        $installRoot=Join-Path $TestDrive 'Programs\DSH Local Build'
        $script:startedInstaller=$null
        $ops.StartInstaller={param($path)$script:startedInstaller=$path;[pscustomobject]@{ExitCode=0}}
        $installOps=InModuleScope DshOfficialDesktopUpdateChannel { Get-DshOfficialDesktopLocalOperations }
        Mock Get-DshOfficialDesktopLocalCheck {
            [pscustomobject]@{status='ready';reasons=@();processEnumerationUnavailable=$false;runningLocalProcesses=@()}
        } -ModuleName DshOfficialDesktopUpdateChannel
        Mock Complete-DshOfficialDesktopManualUpdate {
            [pscustomobject]@{action='complete';status='complete';installerRun=$false}
        } -ModuleName DshOfficialDesktopUpdateChannel
        $installed=Invoke-DshOfficialDesktopUpdateInstall -BundleRoot $result.bundleRoot -AcknowledgeManifestSha256 ('sha256:'+$result.manifestSha256) -BuildRoot $buildRoot -InstallRoot $installRoot -DataRoot $dataRoot -Operations $ops -InstallOperations $installOps
        $installed.status|Should -Be 'complete'
        $installed.installerRun|Should -BeTrue
        $installed.silentInstall|Should -BeFalse
        $installed.windowsInstallerConfirmationPreserved|Should -BeTrue
        $script:startedInstaller|Should -Be $installed.stage.installerPath
        Assert-MockCalled Complete-DshOfficialDesktopManualUpdate -ModuleName DshOfficialDesktopUpdateChannel -Times 1 -Exactly
    }

    It 'reports strict completion as pending after a successful installer exit' {
        $result=New-DshOfficialDesktopUpdateBundle -Sequence 23 -FeedBaseUrl 'https://downloads.example.test/dsh/' -BuildRoot $buildRoot -Operations $ops
        $dataRoot=Join-Path $TestDrive 'pending-data'
        $installRoot=Join-Path $TestDrive 'Programs\DSH Local Build'
        $ops.StartInstaller={param($path)[pscustomobject]@{ExitCode=0}}
        $installOps=InModuleScope DshOfficialDesktopUpdateChannel { Get-DshOfficialDesktopLocalOperations }
        Mock Get-DshOfficialDesktopLocalCheck {
            [pscustomobject]@{status='ready';reasons=@();processEnumerationUnavailable=$false;runningLocalProcesses=@()}
        } -ModuleName DshOfficialDesktopUpdateChannel
        Mock Complete-DshOfficialDesktopManualUpdate { throw 'installed-file-version-mismatch' } -ModuleName DshOfficialDesktopUpdateChannel
        $installed=Invoke-DshOfficialDesktopUpdateInstall -BundleRoot $result.bundleRoot -AcknowledgeManifestSha256 ('sha256:'+$result.manifestSha256) -BuildRoot $buildRoot -InstallRoot $installRoot -DataRoot $dataRoot -Operations $ops -InstallOperations $installOps
        $installed.status|Should -Be 'blocked'
        $installed.reason|Should -Be 'update-completion-required:installed-file-version-mismatch'
        $installed.installerRun|Should -BeTrue
        $installed.completeOnNextLaunch|Should -BeTrue
    }

    It 'reports an interactive installer cancellation without claiming completion' {
        $result=New-DshOfficialDesktopUpdateBundle -Sequence 24 -FeedBaseUrl 'https://downloads.example.test/dsh/' -BuildRoot $buildRoot -Operations $ops
        $dataRoot=Join-Path $TestDrive 'cancel-data'
        $installRoot=Join-Path $TestDrive 'Programs\DSH Local Build'
        $ops.StartInstaller={param($path)[pscustomobject]@{ExitCode=2}}
        $installOps=InModuleScope DshOfficialDesktopUpdateChannel { Get-DshOfficialDesktopLocalOperations }
        Mock Get-DshOfficialDesktopLocalCheck {
            [pscustomobject]@{status='ready';reasons=@();processEnumerationUnavailable=$false;runningLocalProcesses=@()}
        } -ModuleName DshOfficialDesktopUpdateChannel
        Mock Complete-DshOfficialDesktopManualUpdate {
            throw 'completion-must-not-run'
        } -ModuleName DshOfficialDesktopUpdateChannel
        $installed=Invoke-DshOfficialDesktopUpdateInstall -BundleRoot $result.bundleRoot -AcknowledgeManifestSha256 ('sha256:'+$result.manifestSha256) -BuildRoot $buildRoot -InstallRoot $installRoot -DataRoot $dataRoot -Operations $ops -InstallOperations $installOps
        $installed.status|Should -Be 'blocked'
        $installed.reason|Should -Be 'update-installer-exit-2'
        $installed.installerRun|Should -BeTrue
        Assert-MockCalled Complete-DshOfficialDesktopManualUpdate -ModuleName DshOfficialDesktopUpdateChannel -Times 0 -Exactly
    }

    It 'completes only after manual installation evidence and records schema-3 metadata without running an installer' {
        $result=New-DshOfficialDesktopUpdateBundle -Sequence 10 -FeedBaseUrl 'https://downloads.example.test/dsh/' -BuildRoot $buildRoot -Operations $ops
        $dataRoot=Join-Path $TestDrive 'complete-data'
        $stage=Save-DshOfficialDesktopStagedUpdate -BundleRoot $result.bundleRoot -DataRoot $dataRoot -AcknowledgeManifestSha256 ('sha256:'+$result.manifestSha256) -Operations $ops
        $installRoot=Join-Path $TestDrive 'Programs\DSH Local Build'
        $receiptPath=Join-Path $dataRoot 'official-desktop-local-install.json'
        New-Item -ItemType Directory -Path $dataRoot -Force|Out-Null
        [pscustomobject][ordered]@{
            schemaVersion=2;status='complete';createdUtc='2026-09-14T00:00:00Z'
            source=[pscustomobject]@{repository=$policy.repository;tag=$policy.tag;commit=$policy.commit;tree=$policy.tree;buildReceiptPath='old';buildReceiptSha256='a'*64;buildReceiptFileSha256='b'*64}
            installerPath='old';installerSha256='c'*64;installedExecutablePath=(Join-Path $installRoot 'DeepSeek Harness.exe');installedExecutableSha256='d'*64;installedSeedSha256='e'*64
            installRoot=$installRoot;dataRoot=$dataRoot;identity=[pscustomobject]@{productName='DeepSeek Harness';appId=$policy.localPackage.appId;packageName=$policy.localPackage.packageName;unsigned=$true;automaticUpdates=$false}
            launcher=[pscustomobject]@{};rollback=[pscustomobject]@{};home=[pscustomobject]@{mode='isolated';path=(Join-Path $dataRoot 'harness-home');electronUserData=(Join-Path $dataRoot 'electron-user-data');profileBackup=$null};receiptSha256='f'*64
        }|ConvertTo-Json -Depth 20|Set-Content $receiptPath
        $installOps=InModuleScope DshOfficialDesktopUpdateChannel { Get-DshOfficialDesktopLocalOperations }
        $installOps.GetSignature={param($path)'NotSigned'}
        $script:completedReceipt=$null
        Mock Get-DshOfficialDesktopLocalCheck {
            [pscustomobject]@{status='blocked';reasons=@('installed-executable-hash-mismatch');processEnumerationUnavailable=$false;runningLocalProcesses=@();installRoot=$installRoot;dataRoot=$dataRoot;buildRoot=$buildRoot;home=[pscustomobject]@{mode='isolated';path=(Join-Path $dataRoot 'harness-home');electronUserData=(Join-Path $dataRoot 'electron-user-data');profileBackup=$null}}
        } -ModuleName DshOfficialDesktopUpdateChannel
        Mock Assert-InstalledLocalDesktop {
            [pscustomobject]@{executablePath=(Join-Path $installRoot 'DeepSeek Harness.exe');executableHash='c'*64;uninstallString='uninstall';seed=[pscustomobject]@{}}
        } -ModuleName DshOfficialDesktopUpdateChannel
        Mock Test-TrustedLocalInstallReceipt { $true } -ModuleName DshOfficialDesktopUpdateChannel
        Mock Write-LocalLauncherAndShortcuts {
            [pscustomobject]@{launcherPath='launcher';launcherSha256='a'*64;shortcutPaths=@();description='manual managed update channel; native updater disabled'}
        } -ModuleName DshOfficialDesktopUpdateChannel
        Mock Write-LocalInstallReceipt {
            param($Receipt,$Path,$Operations)
            $script:completedReceipt=$Receipt
            return $Receipt
        } -ModuleName DshOfficialDesktopUpdateChannel
        $complete=Complete-DshOfficialDesktopManualUpdate -StageRoot $stage.stageRoot -AcknowledgeManifestSha256 ('sha256:'+$result.manifestSha256) -BuildRoot $buildRoot -InstallRoot $installRoot -DataRoot $dataRoot -Operations $ops -InstallOperations $installOps
        $complete.status|Should -Be 'complete';$complete.installerRun|Should -BeFalse
        $script:completedReceipt.schemaVersion|Should -Be 3
        $script:completedReceipt.updateChannel.sequence|Should -Be 10
        $script:completedReceipt.updateChannel.nativeUpdaterEnabled|Should -BeFalse
        $script:completedReceipt.identity.automaticUpdates|Should -BeFalse
        Assert-MockCalled Write-LocalLauncherAndShortcuts -ModuleName DshOfficialDesktopUpdateChannel -Times 1 -Exactly
    }
}
