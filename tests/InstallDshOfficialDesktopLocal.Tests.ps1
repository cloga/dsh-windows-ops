Import-Module (Join-Path $PSScriptRoot '..\tools\DshOfficialDesktopBuild.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\tools\Install-DshOfficialDesktopLocal.psm1') -Force

Describe 'Official Desktop local side-by-side installer' {
    BeforeEach {
        $script:policy=Get-Content (Join-Path $PSScriptRoot 'fixtures\official-desktop-build\policy.json') -Raw|ConvertFrom-Json
        $script:buildRoot=Join-Path $TestDrive 'build'
        $script:installRoot=Join-Path $TestDrive 'Programs\DSH Local Build'
        $script:dataRoot=Join-Path $TestDrive 'DSH Local Build'
        $script:sourceRoot=Join-Path $buildRoot 'source'
        $script:installer=Join-Path $buildRoot $policy.localPackage.installerName
        $script:unpacked=Join-Path $buildRoot 'win-unpacked\DeepSeek Harness.exe'
        $script:buildReceiptPath=Join-Path $buildRoot 'receipts\package.json'
        $script:installed=Join-Path $installRoot 'DeepSeek Harness.exe'
        $script:seed=Join-Path $installRoot 'resources\seed\desktop-release.json'
        $script:seedManifest=Join-Path $installRoot 'resources\seed\package.json'
        $script:packageSet=Join-Path $installRoot 'resources\seed\desktop-packages.json'
        $script:launcher=Join-Path $installRoot 'DeepSeek Harness Local Build.cmd'
        $script:exists=@{};$exists[$installer]=$true;$exists[$unpacked]=$true;$exists[$buildReceiptPath]=$true
        $script:hashes=@{};$hashes[$installer]='a'*64;$hashes[$unpacked]='b'*64;$hashes[$buildReceiptPath]='c'*64
        $script:files=@{};$script:shortcuts=@{};$script:calls=[Collections.Generic.List[object]]::new()
        $script:entries=@([pscustomobject]@{DisplayName='DeepSeek Harness 0.10.3';UninstallString='C:\Community\Uninstall.exe';InstallLocation='C:\Community'})
        $script:processes=@();$script:installerExit=0;$script:postMismatch=$false
        $script:buildReceipt=[pscustomobject]@{
            action='packagelocal';status='complete';receiptSha256='c'*64
            source=[pscustomobject]@{repository=$policy.repository;tag=$policy.tag;commit=$policy.commit;tree=$policy.tree}
            registryRouting=[pscustomobject]@{registry=$policy.defaultRegistry}
            releaseBoundary=[pscustomobject]@{officialSignature=$false;updateChannel=$false}
            localPackage=[pscustomobject]@{
                installerPath=$installer;executablePath=$unpacked;installerSignature='NotSigned';executableSignature='NotSigned';appUpdatePresent=$false
                identity=[pscustomobject]@{appId=$policy.localPackage.appId;packageName=$policy.localPackage.packageName;productName=$policy.localPackage.productName}
                seed=[pscustomobject]@{version=$policy.version;hostProtocolVersion=3;nodeVersion='24.17.0';pnpmVersion='11.7.0'}
                hashes=[pscustomobject]@{installer='a'*64;executable='b'*64;seed='s'*64}
            }
        }
        $script:ops=@{
            InvokeBuild={param($action,$root,$registry)$script:calls.Add("build:$action");switch($action){'Check'{[pscustomobject]@{status='ready';action='check'}}'Prepare'{$script:exists[(Join-Path $root 'source')]=$true;[pscustomobject]@{status='complete';action='prepare'}}'Verify'{[pscustomobject]@{status='verified';action='verify'}}default{[pscustomobject]@{status='complete';action='packagelocal';receiptPath=$script:buildReceiptPath;sourceRoot=$script:sourceRoot}}}}
            ValidateBuildReceipt={param($path,$source,$pnpmPath)$script:calls.Add("validate-pnpm:$pnpmPath");$true}
            GetSignature={param($path)'NotSigned'}
            GetVersionInfo={param($path)[pscustomobject]@{ProductName='DeepSeek Harness';FileDescription='DeepSeek Harness';InternalName='DeepSeek Harness';FileVersion=$(if($script:postMismatch){'9.9.9'}else{'0.1.5-rc.2'})}}
            GetHash={param($path)if($script:hashes.ContainsKey($path)){$script:hashes[$path]}elseif($path-eq$script:launcher){'d'*64}else{'e'*64}}
            GetTreeHash={param($path)'s'*64}
            GetProcesses={[pscustomobject]@{unavailable=$false;items=@($script:processes)}}
            GetUninstallEntries={@($script:entries)}
            StartInstaller={param($path,$arguments)$script:calls.Add([pscustomobject]@{kind='installer';path=$path;arguments=@($arguments)});if($script:installerExit-eq0){$script:exists[$script:installed]=$true;$script:exists[$script:seed]=$true;$script:exists[$script:seedManifest]=$true;$script:exists[$script:packageSet]=$true;$script:hashes[$script:installed]='b'*64;$script:files[$script:seed]=[pscustomobject]@{version='0.1.5-rc.2';hostProtocolVersion=3;nodeVersion='24.17.0';pnpmVersion='11.7.0'};$script:files[$script:seedManifest]=[pscustomobject]@{name='@deepseek-ai/dsh-desktop-runtime';dependencies=[pscustomobject]@{'@deepseek-ai/dsh'='file:./desktop-packages/deepseek-ai-dsh-0.1.5-rc.2.tgz';'@deepseek-ai/dsh-desktop-host'='file:./desktop-packages/deepseek-ai-dsh-desktop-host-0.1.5-rc.2.tgz'}};$script:files[$script:packageSet]=[pscustomobject]@{schemaVersion=1;packages=@([pscustomobject]@{name='@deepseek-ai/dsh';version='0.1.5-rc.2'},[pscustomobject]@{name='@deepseek-ai/dsh-desktop-host';version='0.1.5-rc.2'})};$script:entries+=,[pscustomobject]@{DisplayName='DeepSeek Harness 0.1.5-rc.2';UninstallString=('"'+(Join-Path $script:installRoot 'Uninstall DeepSeek Harness.exe')+'" /currentuser');InstallLocation=$script:installRoot}};[pscustomobject]@{ExitCode=$script:installerExit}}
            ReadShortcut={param($path)if($script:shortcuts.ContainsKey($path)){$script:shortcuts[$path]}else{$null}}
            WriteShortcut={param($path,$target,$arguments,$description,$icon)$script:calls.Add("shortcut:$path");$script:shortcuts[$path]=[pscustomobject]@{TargetPath=$target;Arguments=$arguments;Description=$description}}
            WriteText={param($path,$text)$script:calls.Add("write:$path");$script:files[$path]=$text;$script:exists[$path]=$true}
            WriteAtomicText={param($path,$text)$script:calls.Add("atomic:$path");$script:files[$path]=$text;$script:exists[$path]=$true}
            CopyFile={param($source,$destination)$script:calls.Add("copy:$destination");$script:exists[$destination]=$true;$script:hashes[$destination]=if($script:hashes.ContainsKey($source)){$script:hashes[$source]}elseif($source-eq$script:launcher){'d'*64}else{'e'*64};if($source-eq$script:buildReceiptPath){$script:files[$destination]=$script:buildReceipt}elseif($script:files.ContainsKey($source)){$script:files[$destination]=$script:files[$source]}}
            TestReparse={param($path)$false}
            GetChildren={param($path)@()}
            GetSpecialFolder={param($name)if($name-eq'Desktop'){Join-Path $TestDrive 'Desktop'}else{Join-Path $TestDrive 'ProgramsMenu'}}
            PathExists={param($path,$type)[bool]$script:exists[$path]}
            ReadJson={param($path)if($path-eq$script:buildReceiptPath){$script:buildReceipt}elseif($script:files.ContainsKey($path)){$v=$script:files[$path];if($v-is[string]){$v|ConvertFrom-Json}else{$v}}else{throw 'missing-json'}}
            ReadText={param($path)[string]$script:files[$path]}
            RemoveFile={param($path)$script:exists.Remove($path);$script:files.Remove($path)}
            IsCurrentUserOwner={param($path)$true}
            GetDirectChildren={param($path)if($script:directChildren.ContainsKey($path)){@($script:directChildren[$path])}else{@()}}
            GetOpaqueTreeHash={param($path)'1'*64}
            MoveDirectory={
                param($source,$destination)
                $script:calls.Add("move:$source")
                foreach($path in @($script:exists.Keys|Where-Object{$_ -eq $source -or $_.StartsWith($source+'\')})){
                    $script:exists[$destination+$path.Substring($source.Length)]=$script:exists[$path]
                    $script:exists.Remove($path)
                }
            }
        }
        $script:directChildren=@{}
        $script:sharedRoot=Join-Path $TestDrive 'shared-home'
        $script:sharedProfile=Join-Path $sharedRoot 'profiles\desktop'
        foreach($path in @($sharedRoot,(Join-Path $sharedRoot 'settings.yaml'),(Join-Path $sharedRoot 'sessions'),(Join-Path $sharedRoot 'profiles'))){$script:exists[$path]=$true}
        function New-LegacyProfileFixture {
            $script:exists[$script:sharedProfile]=$true
            $hashes=@{
                'package.json'='bb3969723f1c7590c78a59cd7aaf8b98ad8eefae0ec590cfe6e7f4ef21d77f53'
                'cordis.yml'='37517e5f3dc66819f61f5a7bb8ace1921282415f10551d2defa5c3eb0985b570'
                'cordis.patch.yml'='ef189a8c27db6d63930aa3046a3040482e952eafcb7487c644d508e8d461f027'
                'pnpm-workspace.yaml'='ae7c5b68e2f157528e62885804e69e88583897b775e03c86fcbe52feaf498aba'
            }
            $names=@($hashes.Keys)+@('node_modules','.dsh-module-fallback')
            $script:directChildren[$script:sharedProfile]=@($names|ForEach-Object{[pscustomobject]@{Name=$_}})
            foreach($name in $names){$path=Join-Path $script:sharedProfile $name;$script:exists[$path]=$true;if($hashes.ContainsKey($name)){$script:hashes[$path]=$hashes[$name]}}
            $script:exists[(Join-Path $script:sharedProfile '.dsh-module-fallback\node_modules')]=$true
            $script:directChildren[(Join-Path $script:sharedProfile '.dsh-module-fallback')]=@([pscustomobject]@{Name='node_modules'})
        }
        function Invoke-FixtureInstall {
            param([string]$SharedHome,[switch]$UseIsolatedHome,[string]$Action='Apply')
            Invoke-DshOfficialDesktopLocalInstall -Action $Action -AcknowledgeUnsignedLocalBuild -BuildRoot $script:buildRoot -InstallRoot $script:installRoot -DataRoot $script:dataRoot -SharedHome $SharedHome -UseIsolatedHome:$UseIsolatedHome -Operations $script:ops
        }
    }

    It 'defaults to a read-only Check and never creates the build root or installs' {
        $result=Invoke-DshOfficialDesktopLocalInstall -BuildRoot $buildRoot -InstallRoot $installRoot -DataRoot $dataRoot -Operations $ops
        $result.status|Should -Be 'ready';$result.mutated|Should -BeFalse
        @($calls)|Should -Contain 'build:Check'
        ($calls|ConvertTo-Json -Depth 5)|Should -Not -Match 'installer|write:|atomic:|copy:|shortcut:'
    }

    It 'selects shared existing data without copying settings sessions or credentials' {
        $check=Invoke-FixtureInstall -Action Check -SharedHome $sharedRoot
        $check.status|Should -Be 'ready' -Because ($check.reasons -join ',');$check.sharedProfile.kind|Should -Be 'absent'
        ($calls|ConvertTo-Json)|Should -Not -Match 'write:|atomic:|copy:|move:'
        $result=Invoke-FixtureInstall -SharedHome $sharedRoot
        $result.home.mode|Should -Be 'shared'
        $result.receipt.home.path|Should -Be $sharedRoot
        $files[$launcher]|Should -Match ([regex]::Escape('DSH_HOME='+$sharedRoot))
        $files[$launcher]|Should -Match ([regex]::Escape('--user-data-dir='+$dataRoot+'\electron-user-data'))
        $result.receipt.launcher.description|Should -Be 'DeepSeek Harness local source build (unsigned; shared DSH home; update channel not configured)'
        ($calls|ConvertTo-Json)|Should -Not -Match 'copy:.*(settings|credentials|sessions)|move:'
    }

    It 'records schema-3 manual channel metadata without advertising native automatic updates' {
        $result=Invoke-FixtureInstall
        $receipt=$result.receipt
        $files[$receipt.source.buildReceiptPath].localPackage.executablePath=Join-Path $sourceRoot 'apps\desktop\.desktop-build\targets\win-x64\artifacts\win-unpacked\DeepSeek Harness.exe'
        $receipt.schemaVersion=3
        $receipt|Add-Member updateChannel ([pscustomobject][ordered]@{
            mode='unsigned-manual';owner='cloga/dsh-windows-ops';channel='rc'
            channelVersion='0.1.5-rc.2.local.4';sequence=4
            manifestPath=(Join-Path $dataRoot 'updates\manifests\manifest.json');manifestSha256='f'*64
            feedBaseUrl='https://downloads.example.test/dsh/';nativeUpdaterEnabled=$false
            signatureRequiredForNativeUpdater=$true;completedUtc='2026-09-14T00:00:00Z'
        }) -Force
        $script:exists[$receipt.updateChannel.manifestPath]=$true
        $script:files[$receipt.updateChannel.manifestPath]=[pscustomobject]@{manifestSha256='f'*64;owner='cloga/dsh-windows-ops';sequence=4;channelVersion='0.1.5-rc.2.local.4'}
        $receipt.PSObject.Properties.Remove('receiptSha256')
        InModuleScope Install-DshOfficialDesktopLocal -Parameters @{receipt=$receipt} {param($receipt)$receipt|Add-Member receiptSha256 (Get-LocalReceiptPayloadHash $receipt)}
        Test-TrustedLocalInstallReceipt $receipt $buildRoot $installRoot $dataRoot $ops | Should -BeTrue
        $shell=Write-LocalLauncherAndShortcuts $installRoot $dataRoot $ops $result.home $receipt.updateChannel
        $shell.description|Should -Match 'manual managed update channel'
        $shell.description|Should -Match 'native updater disabled'
        $receipt.identity.automaticUpdates|Should -BeFalse
    }

    It 'upgrades schema1 to shared and retains the mode when arguments are omitted' {
        $first=Invoke-FixtureInstall
        $receipt=$first.receipt
        $receipt.schemaVersion=1;$receipt.PSObject.Properties.Remove('home')
        InModuleScope Install-DshOfficialDesktopLocal -Parameters @{receipt=$receipt} {param($receipt)$receipt.receiptSha256=Get-LocalReceiptPayloadHash $receipt}
        $script:files[(Join-Path $dataRoot 'official-desktop-local-install.json')]=$receipt
        $script:calls.Clear()
        $shared=Invoke-FixtureInstall -SharedHome $sharedRoot
        $shared.installerRun|Should -BeFalse
        $shared.receipt.schemaVersion|Should -Be 2
        (Invoke-FixtureInstall -Action Check).home.path|Should -Be $sharedRoot
        $again=Invoke-FixtureInstall
        $again.home.mode|Should -Be 'shared';$again.installerRun|Should -BeFalse
        @($calls)|Should -Not -Contain 'build:PackageLocal'
        InModuleScope Install-DshOfficialDesktopLocal -Parameters @{receipt=$again.receipt} {param($receipt)(Test-LocalReceiptHash $receipt)|Should -BeTrue}
        $isolated=Invoke-FixtureInstall -UseIsolatedHome
        $isolated.home.mode|Should -Be 'isolated'
        $isolated.home.path|Should -Be (Join-Path $dataRoot 'harness-home')
        $isolated.receipt.launcher.description|Should -Match 'isolated DSH home'
        $script:exists[$sharedRoot]|Should -BeTrue
    }

    It 'detects the exact blank legacy collision read-only and moves it intact once on Apply' {
        New-LegacyProfileFixture
        $check=Invoke-FixtureInstall -Action Check -SharedHome $sharedRoot
        $check.status|Should -Be 'ready' -Because ($check.reasons -join ',');$check.sharedProfile.kind|Should -Be 'legacy-blank'
        ($calls|ConvertTo-Json)|Should -Not -Match 'move:|copy:|atomic:'
        $result=Invoke-FixtureInstall -SharedHome $sharedRoot
        $result.home.profileBackup.status|Should -Be 'moved'
        $result.home.profileBackup.destination|Should -BeLike ($dataRoot+'\install-backups\*\desktop')
        $script:exists.ContainsKey($sharedProfile)|Should -BeFalse
        $script:exists[$result.home.profileBackup.destination]|Should -BeTrue
        $again=Invoke-FixtureInstall
        $again.home.profileBackup.destination|Should -Be $result.home.profileBackup.destination
        @($calls|Where-Object{$_ -like 'move:*'}).Count|Should -Be 1
    }

    It 'fails closed on customized blank profiles without installer or writes' {
        New-LegacyProfileFixture
        $script:hashes[(Join-Path $sharedProfile 'cordis.patch.yml')]='custom'
        $result=Invoke-FixtureInstall -SharedHome $sharedRoot
        $result.status|Should -Be 'blocked'
        $result.reasons|Should -Contain 'shared-desktop-profile-unknown'
        @($calls)|Should -Not -Contain 'build:PackageLocal'
        ($calls|ConvertTo-Json)|Should -Not -Match 'move:|write:|copy:'
    }

    It 'blocks unsafe shared boundaries owner mismatches and metadata reparse paths' {
        foreach($path in @($dataRoot,$installRoot,$buildRoot,(Join-Path $sharedRoot 'profiles'))){
            $script:exists[$path]=$true
            (Invoke-FixtureInstall -Action Check -SharedHome $path).status|Should -Be 'blocked'
        }
        $ops.IsCurrentUserOwner={param($path)$false}
        (Invoke-FixtureInstall -SharedHome $sharedRoot).reasons|Should -Contain 'shared-home-owner-mismatch'
        $ops.IsCurrentUserOwner={param($path)$true}
        $ops.TestReparse={param($path)$path -eq (Join-Path $script:sharedRoot 'profiles')}
        (Invoke-FixtureInstall -SharedHome $sharedRoot).status|Should -Be 'blocked'
        ($calls|ConvertTo-Json)|Should -Not -Match 'move:|write:|copy:'
    }

    It 'blocks community runtimes and unknown node commands even on the idempotent mode switch path' {
        $null=Invoke-FixtureInstall -SharedHome $sharedRoot
        foreach($process in @(
            [pscustomobject]@{Id=9;Name='DeepSeek Harness.exe';ExecutablePath='C:\Community\DeepSeek Harness.exe';CommandLine='community'},
            [pscustomobject]@{Id=10;Name='node.exe';ExecutablePath='C:\Runtime\node.exe';CommandLine='node C:\dsh\host.js'},
            [pscustomobject]@{Id=11;Name='node.exe';ExecutablePath='C:\Runtime\node.exe';CommandLine=$null}
        )){
            $script:processes=@($process)
            (Invoke-FixtureInstall).reasons|Should -Contain 'shared-home-runtime-running'
            (Invoke-FixtureInstall -UseIsolatedHome).reasons|Should -Contain 'shared-home-runtime-running'
        }
    }

    It 'preserves backups and reports partial failure rather than rollback success' {
        New-LegacyProfileFixture
        $ops.MoveDirectory={param($source,$destination)throw 'simulated-move-failure'}
        {Invoke-FixtureInstall -SharedHome $sharedRoot}|Should -Throw '*partial-install-manual-review-required*simulated-move-failure*'
        $script:exists[$sharedProfile]|Should -BeTrue
        (Invoke-FixtureInstall -Action Check -SharedHome $sharedRoot).reasons|Should -Contain 'home-change-recovery-required'
        @($files.Keys|Where-Object{$_ -like '*shared-profile-*\backup.json'}).Count|Should -Be 1
    }

    It 'does not reset shared mode after an unreadable or altered receipt' {
        $first=Invoke-FixtureInstall -SharedHome $sharedRoot
        $path=Join-Path $dataRoot 'official-desktop-local-install.json'
        $first.receipt.home.path='C:\tampered'
        $script:files[$path]=$first.receipt
        (Invoke-FixtureInstall).reasons|Should -Contain 'saved-home-receipt-untrusted'
        $script:files[$path]='broken-json'
        (Invoke-FixtureInstall).reasons|Should -Contain 'install-receipt-unreadable'
    }

    It 'reuses archived install evidence when source and build tools are gone' {
        $null=Invoke-FixtureInstall
        $script:exists.Remove($sourceRoot)
        $ops.InvokeBuild={throw 'build must not be invoked for attested install'}
        $ops.ValidateBuildReceipt={param($path,$source,$pnpm,$recordedOnly)if(-not $recordedOnly){throw 'recorded mode required'};$true}
        $result=Invoke-FixtureInstall -SharedHome $sharedRoot
        $result.installerRun|Should -BeFalse
        (Invoke-FixtureInstall -Action Check).build.action|Should -Be 'installed-evidence'
    }

    It 'refuses conflicting options and malformed process enumeration' {
        {Invoke-FixtureInstall -SharedHome $sharedRoot -UseIsolatedHome}|Should -Throw '*conflicts*'
        foreach($probe in @(
            [pscustomobject]@{unavailable=$true;items=@()},
            [pscustomobject]@{unavailable=$false;items=@([pscustomobject]@{Id=7})}
        )){
            $script:probe=$probe;$ops.GetProcesses={$script:probe}
            (Invoke-FixtureInstall -SharedHome $sharedRoot).status|Should -Be 'blocked'
        }
    }

    It 'catches a runtime starting after Check and never moves the legacy profile' {
        New-LegacyProfileFixture
        $null=Invoke-FixtureInstall -UseIsolatedHome
        $script:probeCount=0
        $ops.GetProcesses={
            $script:probeCount++
            [pscustomobject]@{unavailable=$false;items=@(if($script:probeCount -gt 1){[pscustomobject]@{Id=14;Name='dsh.exe';ExecutablePath='C:\runtime\dsh.exe'}})}
        }
        {Invoke-FixtureInstall -SharedHome $sharedRoot}|Should -Throw '*shared-home-runtime-running*'
        @($calls|Where-Object{$_ -like 'move:*'}).Count|Should -Be 0
        $script:exists[$sharedProfile]|Should -BeTrue
    }

    It 'does not silently overwrite a modified launcher but can adopt the explicit canonical selection' {
        $null=Invoke-FixtureInstall
        $script:hashes[$launcher]='f'*64;$script:files[$launcher]='custom command'
        {Invoke-FixtureInstall}|Should -Throw '*launcher-modified-review-required*'
        $script:files[$launcher]="@echo off`r`nsetlocal`r`nset `"DSH_HOME=$sharedRoot`"`r`nstart `"`" `"$installed`" `"--user-data-dir=$dataRoot\electron-user-data`" %*`r`n"
        (Invoke-FixtureInstall -SharedHome $sharedRoot).home.mode|Should -Be 'shared'
    }

    It 'retains the pending journal when a shortcut write silently fails' {
        $null=Invoke-FixtureInstall
        $ops.WriteShortcut={param($path,$target,$arguments,$description,$icon)}
        {Invoke-FixtureInstall -SharedHome $sharedRoot}|Should -Throw '*partial-install-manual-review-required*shortcut-write-verification-failed*'
        (Invoke-FixtureInstall -Action Check).reasons|Should -Contain 'home-change-recovery-required'
        @($files.Keys|Where-Object{$_ -like '*home-change-*\DeepSeek Harness Local Build.cmd'}).Count|Should -BeGreaterThan 0
    }

    It 'requires explicit acknowledgement before PackageLocal' {
        {Invoke-DshOfficialDesktopLocalInstall -Action Apply -BuildRoot $buildRoot -InstallRoot $installRoot -DataRoot $dataRoot -Operations $ops}|Should -Throw '*acknowledge*'
        @($calls)|Should -Not -Contain 'build:PackageLocal'
    }

    It 'blocks Apply when process enumeration is unavailable' {
        $ops.GetProcesses={[pscustomobject]@{unavailable=$true;items=@()}}
        $check=Invoke-DshOfficialDesktopLocalInstall -BuildRoot $buildRoot -InstallRoot $installRoot -DataRoot $dataRoot -Operations $ops
        $check.status|Should -Be 'ready';$check.processEnumerationUnavailable|Should -BeTrue
        {Invoke-DshOfficialDesktopLocalInstall -Action Apply -AcknowledgeUnsignedLocalBuild -BuildRoot $buildRoot -InstallRoot $installRoot -DataRoot $dataRoot -Operations $ops}|Should -Throw '*process-enumeration-unavailable*'
        @($calls)|Should -Not -Contain 'build:PackageLocal'
    }

    It 'refuses a running executable below InstallRoot without stopping it' {
        $script:processes=@([pscustomobject]@{Id=42;ExecutablePath=(Join-Path $installRoot 'DeepSeek Harness.exe')})
        {Invoke-DshOfficialDesktopLocalInstall -Action Apply -AcknowledgeUnsignedLocalBuild -BuildRoot $buildRoot -InstallRoot $installRoot -DataRoot $dataRoot -Operations $ops}|Should -Throw '*process-running*'
        ($calls|ConvertTo-Json)|Should -Not -Match 'Stop-Process|taskkill|build:PackageLocal'
    }

    It 'rejects unsafe paths, overlap, command metacharacters, and reparse points' {
        {Invoke-DshOfficialDesktopLocalInstall -BuildRoot $buildRoot -InstallRoot 'relative' -DataRoot $dataRoot -Operations $ops}|Should -Throw '*absolute*'
        {Invoke-DshOfficialDesktopLocalInstall -BuildRoot $buildRoot -InstallRoot ($installRoot+' & bad') -DataRoot $dataRoot -Operations $ops}|Should -Throw '*metacharacter*'
        {Invoke-DshOfficialDesktopLocalInstall -BuildRoot $buildRoot -InstallRoot ($installRoot+'"bad') -DataRoot $dataRoot -Operations $ops}|Should -Throw '*metacharacter*'
        {Invoke-DshOfficialDesktopLocalInstall -BuildRoot $buildRoot -InstallRoot $installRoot -DataRoot (Join-Path $installRoot 'data') -Operations $ops}|Should -Throw '*overlap*'
        $ops.TestReparse={param($path)$path-eq$script:installRoot}
        {Invoke-DshOfficialDesktopLocalInstall -BuildRoot $buildRoot -InstallRoot $installRoot -DataRoot $dataRoot -Operations $ops}|Should -Throw '*reparse*'
    }

    It 'passes an explicit pnpm path into strict package receipt validation' {
        $custom=Join-Path $TestDrive 'custom-pnpm.cmd'
        $null=Invoke-DshOfficialDesktopLocalInstall -Action Apply -AcknowledgeUnsignedLocalBuild -BuildRoot $buildRoot -PnpmPath $custom -InstallRoot $installRoot -DataRoot $dataRoot -Operations $ops
        @($calls)|Should -Contain ("validate-pnpm:$custom")
    }

    It 'rejects reparse descendants in owned artifact backup receipt and installed seed trees' {
        foreach($blocked in @(
            (Join-Path $dataRoot 'artifacts\linked'),
            (Join-Path $dataRoot 'artifacts\build-receipts\linked'),
            (Join-Path $dataRoot 'install-backups\linked')
        )){
            $script:blocked=$blocked
            $ops.GetChildren={param($path)if($script:blocked.StartsWith($path,[StringComparison]::OrdinalIgnoreCase)){@([pscustomobject]@{FullName=$script:blocked})}else{@()}}
            $ops.TestReparse={param($path)$path-ceq$script:blocked}
            {Invoke-DshOfficialDesktopLocalInstall -Action Apply -AcknowledgeUnsignedLocalBuild -BuildRoot $buildRoot -InstallRoot $installRoot -DataRoot $dataRoot -Operations $ops}|Should -Throw '*local-owned-path-reparse-point*'
        }
        $script:exists[$installed]=$true;$script:hashes[$installed]='b'*64
        $ops.GetChildren={param($path)if($path-eq(Join-Path $script:installRoot 'resources\seed')){@([pscustomobject]@{FullName=(Join-Path $path 'linked')})}else{@()}};$ops.TestReparse={param($path)$path-like'*resources\seed\linked'}
        {Assert-InstalledLocalDesktop $installRoot ([pscustomobject]@{executableHash='b'*64;seedHash='s'*64}) $ops}|Should -Throw '*local-owned-path-reparse-point*'
    }

    It 'rejects any existing InstallRoot reparse descendant before installer launch' {
        $blocked=Join-Path $installRoot 'old\linked';$ops.GetChildren={param($path)if($path-eq$script:installRoot){@([pscustomobject]@{FullName=$blocked})}else{@()}};$ops.TestReparse={param($path)$path-ceq$blocked}
        {Invoke-DshOfficialDesktopLocalInstall -Action Apply -AcknowledgeUnsignedLocalBuild -BuildRoot $buildRoot -InstallRoot $installRoot -DataRoot $dataRoot -Operations $ops}|Should -Throw '*local-owned-path-reparse-point*'
        ($calls|ConvertTo-Json -Depth 5)|Should -Not -Match '"kind":"installer"|write:|shortcut:'
    }

    It 'accepts real uninstall shapes with missing optional fields and quoted community paths' {
        $communityRoot=Join-Path $TestDrive 'Community Desktop';$communityExe=Join-Path $communityRoot 'deepseek-harness-desktop.exe';$script:exists[$communityExe]=$true
        $script:entries=@(
            [pscustomobject]@{DisplayName='Deepseek Harness Desktop';InstallLocation=('"'+$communityRoot+'"');DisplayIcon=('"'+$communityExe+'",0')},
            [pscustomobject]@{DisplayName='DeepSeek Harness 0.1.5-rc.2';UninstallString=('"'+(Join-Path $installRoot 'Uninstall DeepSeek Harness.exe')+'"')},
            [pscustomobject]@{DisplayName='Unrelated application'}
        )
        $result=Invoke-DshOfficialDesktopLocalInstall -BuildRoot $buildRoot -InstallRoot $installRoot -DataRoot $dataRoot -Operations $ops
        $result.status|Should -Be 'ready';$result.community.present|Should -BeTrue;$result.community.executablePresent|Should -BeTrue
        @($result.uninstallEntries).Count|Should -Be 1
    }

    It 'prepares an empty build root before PackageLocal in exact order' {
        $null=Invoke-DshOfficialDesktopLocalInstall -Action Apply -AcknowledgeUnsignedLocalBuild -BuildRoot $buildRoot -InstallRoot $installRoot -DataRoot $dataRoot -Operations $ops
        @($calls|Where-Object{$_-is[string]-and$_-like'build:*'})|Should -Be @('build:Check','build:Prepare','build:PackageLocal')
    }

    It 'verifies an existing prepared root before PackageLocal without Prepare reuse' {
        $script:exists[(Join-Path $buildRoot 'source')]=$true
        $null=Invoke-DshOfficialDesktopLocalInstall -Action Apply -AcknowledgeUnsignedLocalBuild -BuildRoot $buildRoot -InstallRoot $installRoot -DataRoot $dataRoot -Operations $ops
        @($calls|Where-Object{$_-is[string]-and$_-like'build:*'})|Should -Be @('build:Check','build:Verify','build:PackageLocal')
        @($calls)|Should -Not -Contain 'build:Prepare'
    }

    It 'rejects an existing prepared root when strict Verify fails' {
        $script:exists[(Join-Path $buildRoot 'source')]=$true
        $ops.InvokeBuild={param($action,$root,$registry)$script:calls.Add("build:$action");if($action-eq'Check'){[pscustomobject]@{status='ready';action='check'}}elseif($action-eq'Verify'){[pscustomobject]@{status='failed';action='verify'}}else{throw 'unexpected-build-call'}}
        {Invoke-DshOfficialDesktopLocalInstall -Action Apply -AcknowledgeUnsignedLocalBuild -BuildRoot $buildRoot -InstallRoot $installRoot -DataRoot $dataRoot -Operations $ops}|Should -Throw '*existing-build-root-verification-failed*'
        @($calls)|Should -Not -Contain 'build:PackageLocal'
    }

    It 'rejects a changed PackageLocal receipt and unsigned constraint mismatch' {
        $ops.ValidateBuildReceipt={param($p,$s)$false}
        {Invoke-DshOfficialDesktopLocalInstall -Action Apply -AcknowledgeUnsignedLocalBuild -BuildRoot $buildRoot -InstallRoot $installRoot -DataRoot $dataRoot -Operations $ops}|Should -Throw '*receipt-invalid*'
        $ops.ValidateBuildReceipt={param($p,$s)$true};$ops.GetSignature={param($p)'Valid'}
        {Invoke-DshOfficialDesktopLocalInstall -Action Apply -AcknowledgeUnsignedLocalBuild -BuildRoot $buildRoot -InstallRoot $installRoot -DataRoot $dataRoot -Operations $ops}|Should -Throw '*must-be-unsigned*'
    }

    It 'runs the installer silently with destination last and performs no launch or restart' {
        $result=Invoke-DshOfficialDesktopLocalInstall -Action Apply -AcknowledgeUnsignedLocalBuild -BuildRoot $buildRoot -InstallRoot $installRoot -DataRoot $dataRoot -Operations $ops
        $result.status|Should -Be 'complete';$result.launchedGui|Should -BeFalse;$result.stoppedProcesses|Should -BeFalse
        $call=@($calls|Where-Object{$_.kind-eq'installer'})[0];$call.path|Should -Be (Join-Path (Join-Path $dataRoot 'artifacts') (('a'*64)+'-'+$policy.localPackage.installerName));$call.arguments|Should -Be @('/S',('/D='+$installRoot));$call.arguments[-1]|Should -Be('/D='+$installRoot)
        [string]$files[$launcher]|Should -Match ([regex]::Escape('set "DSH_HOME='+$dataRoot+'\harness-home"'))
        [string]$files[$launcher]|Should -Match ([regex]::Escape('"--user-data-dir='+$dataRoot+'\electron-user-data"'))
        ($calls|ConvertTo-Json -Depth 5)|Should -Not -Match '(?i)Stop-Process|Restart|Uninstall|session|default.profile'
    }

    It 'reports every nonzero installer outcome as partial manual review without rollback' {
        $script:installerExit=9
        {Invoke-DshOfficialDesktopLocalInstall -Action Apply -AcknowledgeUnsignedLocalBuild -BuildRoot $buildRoot -InstallRoot $installRoot -DataRoot $dataRoot -Operations $ops}|Should -Throw '*partial-install-manual-review-required*installer-exit-9*'
        ($calls|ConvertTo-Json -Depth 5)|Should -Not -Match 'atomic:|shortcut:|uninstall|rollback'
    }

    It 'marks post-installer mismatch as partial manual review and retains community install' {
        $script:postMismatch=$true
        {Invoke-DshOfficialDesktopLocalInstall -Action Apply -AcknowledgeUnsignedLocalBuild -BuildRoot $buildRoot -InstallRoot $installRoot -DataRoot $dataRoot -Operations $ops}|Should -Throw '*partial-install-manual-review-required*file-version*'
        @($entries|Where-Object {$_.DisplayName -eq 'DeepSeek Harness 0.10.3'}).Count|Should -Be 1
        ($calls|ConvertTo-Json -Depth 5)|Should -Not -Match 'uninstall|Stop-Process|taskkill'
    }

    It 'refuses to replace a shortcut not already owned by InstallRoot' {
        $desktop=&$ops.GetSpecialFolder 'Desktop';$script:shortcuts[(Join-Path $desktop 'DeepSeek Harness.lnk')]=[pscustomobject]@{TargetPath='C:\Community\DeepSeek Harness.exe'}
        {Invoke-DshOfficialDesktopLocalInstall -Action Apply -AcknowledgeUnsignedLocalBuild -BuildRoot $buildRoot -InstallRoot $installRoot -DataRoot $dataRoot -Operations $ops}|Should -Throw '*shortcut-target-outside*'
        @($calls)|Should -Not -Contain 'build:PackageLocal'
    }

    It 'rejects receipt swaps during validation before consuming artifact paths' {
        $count=0;$ops.GetHash={param($path)if($path-eq$script:buildReceiptPath){$script:count++;if($script:count-eq1){'c'*64}else{'f'*64}}elseif($script:hashes.ContainsKey($path)){$script:hashes[$path]}else{'e'*64}}
        {Invoke-DshOfficialDesktopLocalInstall -Action Apply -AcknowledgeUnsignedLocalBuild -BuildRoot $buildRoot -InstallRoot $installRoot -DataRoot $dataRoot -Operations $ops}|Should -Throw '*receipt-changed-during-copy*'
        ($calls|ConvertTo-Json -Depth 5)|Should -Not -Match 'installer'
    }

    It 'rejects archived installer byte changes before launch' {
        $archivedReads=0;$ops.GetHash={param($path)if($path-like('*artifacts*'+$script:policy.localPackage.installerName)){$script:archivedReads++;if($script:archivedReads-eq1){'a'*64}else{'f'*64}}elseif($script:hashes.ContainsKey($path)){$script:hashes[$path]}else{'e'*64}}
        {Invoke-DshOfficialDesktopLocalInstall -Action Apply -AcknowledgeUnsignedLocalBuild -BuildRoot $buildRoot -InstallRoot $installRoot -DataRoot $dataRoot -Operations $ops}|Should -Throw '*archived-installer-changed-before-launch*'
        ($calls|ConvertTo-Json -Depth 5)|Should -Not -Match '"kind":"installer"'
    }

    It 'rejects a mismatched installed Core or Desktop Host package identity' {
        $script:postMismatch=$false
        $original=$ops.StartInstaller;$ops.StartInstaller={param($path,$arguments)$result=&$original $path $arguments;$script:files[$script:packageSet].packages[1].version='9.9.9';$result}
        {Invoke-DshOfficialDesktopLocalInstall -Action Apply -AcknowledgeUnsignedLocalBuild -BuildRoot $buildRoot -InstallRoot $installRoot -DataRoot $dataRoot -Operations $ops}|Should -Throw '*partial-install-manual-review-required*installed-core-package-set-mismatch*'
    }

    It 'rejects an installed seed tree whose hash differs from the packaged seed' {
        $ops.GetTreeHash={param($path)'tampered'}
        {Invoke-DshOfficialDesktopLocalInstall -Action Apply -AcknowledgeUnsignedLocalBuild -BuildRoot $buildRoot -InstallRoot $installRoot -DataRoot $dataRoot -Operations $ops}|Should -Throw '*partial-install-manual-review-required*installed-seed-tree-hash-mismatch*'
    }

    It 'does not trust a self-hashed install receipt when its strict build receipt is missing' {
        $script:exists[$installed]=$true;$script:hashes[$installed]='b'*64
        $archived=Join-Path (Join-Path $dataRoot 'artifacts') (('a'*64)+'-'+$policy.localPackage.installerName);$script:exists[$archived]=$true;$script:hashes[$archived]='a'*64
        $snapshot=Join-Path $dataRoot ('artifacts\build-receipts\'+('c'*64)+'.json')
        $receipt=[pscustomobject][ordered]@{schemaVersion=1;status='complete';createdUtc='2026-09-14T00:00:00Z';source=[pscustomobject]@{repository=$policy.repository;tag=$policy.tag;commit=$policy.commit;tree=$policy.tree;buildReceiptPath=$snapshot;buildReceiptSha256='c'*64;buildReceiptFileSha256='c'*64};installerPath=$archived;installerSha256='a'*64;installedExecutablePath=$installed;installedExecutableSha256='b'*64;installedSeedSha256='s'*64;installRoot=$installRoot;dataRoot=$dataRoot;identity=[pscustomobject]@{productName='DeepSeek Harness';appId=$policy.localPackage.appId;packageName=$policy.localPackage.packageName;unsigned=$true;automaticUpdates=$false};launcher=[pscustomobject]@{};rollback=[pscustomobject]@{}}
        InModuleScope Install-DshOfficialDesktopLocal -Parameters @{receipt=$receipt} {param($receipt)$receipt|Add-Member receiptSha256 (Get-LocalReceiptPayloadHash $receipt)}
        $receiptPath=Join-Path $dataRoot 'official-desktop-local-install.json';$script:exists[$receiptPath]=$true;$script:files[$receiptPath]=$receipt;$script:exists[$buildReceiptPath]=$false
        $result=Invoke-DshOfficialDesktopLocalInstall -Action Apply -AcknowledgeUnsignedLocalBuild -BuildRoot $buildRoot -InstallRoot $installRoot -DataRoot $dataRoot -Operations $ops
        $result.idempotent|Should -BeFalse
        @($calls)|Should -Contain 'build:PackageLocal'
    }

    It 'rejects a DataRoot reparse descendant before the idempotent trust path' {
        $blocked=Join-Path $dataRoot 'artifacts\linked';$ops.GetChildren={param($path)if($path-eq(Join-Path $script:dataRoot 'artifacts')){@([pscustomobject]@{FullName=$blocked})}else{@()}};$ops.TestReparse={param($path)$path-ceq$blocked}
        {Invoke-DshOfficialDesktopLocalInstall -Action Apply -AcknowledgeUnsignedLocalBuild -BuildRoot $buildRoot -InstallRoot $installRoot -DataRoot $dataRoot -Operations $ops}|Should -Throw '*local-owned-path-reparse-point*'
        @($calls)|Should -Not -Contain 'build:PackageLocal';($calls|ConvertTo-Json -Depth 5)|Should -Not -Match 'installer|write:|shortcut:'
    }

    It 'idempotently verifies an exact receipt and repairs only launcher and shortcuts' {
        $script:exists[$installed]=$true;$script:hashes[$installed]='b'*64;$script:exists[$seed]=$true;$script:exists[$seedManifest]=$true;$script:exists[$packageSet]=$true;$script:files[$seed]=[pscustomobject]@{version='0.1.5-rc.2';hostProtocolVersion=3;nodeVersion='24.17.0';pnpmVersion='11.7.0'};$script:files[$seedManifest]=[pscustomobject]@{name='@deepseek-ai/dsh-desktop-runtime';dependencies=[pscustomobject]@{'@deepseek-ai/dsh'='file:./desktop-packages/deepseek-ai-dsh-0.1.5-rc.2.tgz';'@deepseek-ai/dsh-desktop-host'='file:./desktop-packages/deepseek-ai-dsh-desktop-host-0.1.5-rc.2.tgz'}};$script:files[$packageSet]=[pscustomobject]@{schemaVersion=1;packages=@([pscustomobject]@{name='@deepseek-ai/dsh';version='0.1.5-rc.2'},[pscustomobject]@{name='@deepseek-ai/dsh-desktop-host';version='0.1.5-rc.2'})}
        $script:entries+=,[pscustomobject]@{DisplayName='DeepSeek Harness 0.1.5-rc.2';UninstallString=('"'+(Join-Path $installRoot 'Uninstall DeepSeek Harness.exe')+'"');InstallLocation=$installRoot}
        $archived=Join-Path (Join-Path $dataRoot 'artifacts') (('a'*64)+'-'+$policy.localPackage.installerName);$script:exists[$archived]=$true;$script:hashes[$archived]='a'*64
        $snapshot=Join-Path $dataRoot ('artifacts\build-receipts\'+('c'*64)+'.json')
        $receipt=[pscustomobject][ordered]@{schemaVersion=1;status='complete';createdUtc='2026-09-14T00:00:00Z';source=[pscustomobject]@{repository=$policy.repository;tag=$policy.tag;commit=$policy.commit;tree=$policy.tree;buildReceiptPath=$snapshot;buildReceiptSha256='c'*64;buildReceiptFileSha256='c'*64};installerPath=$archived;installerSha256='a'*64;installedExecutablePath=$installed;installedExecutableSha256='b'*64;installedSeedSha256='s'*64;installRoot=$installRoot;dataRoot=$dataRoot;identity=[pscustomobject]@{productName='DeepSeek Harness';appId=$policy.localPackage.appId;packageName=$policy.localPackage.packageName;unsigned=$true;automaticUpdates=$false};launcher=[pscustomobject]@{};rollback=[pscustomobject]@{}}
        InModuleScope Install-DshOfficialDesktopLocal -Parameters @{receipt=$receipt} {param($receipt)$receipt|Add-Member receiptSha256 (Get-LocalReceiptPayloadHash $receipt)}
        $receiptPath=Join-Path $dataRoot 'official-desktop-local-install.json';$script:exists[$receiptPath]=$true;$script:files[$receiptPath]=$receipt;$script:exists[$snapshot]=$true;$script:hashes[$snapshot]='c'*64;$script:files[$snapshot]=$buildReceipt
        $result=Invoke-DshOfficialDesktopLocalInstall -Action Apply -AcknowledgeUnsignedLocalBuild -BuildRoot $buildRoot -InstallRoot $installRoot -DataRoot $dataRoot -Operations $ops
        $result.idempotent|Should -BeTrue;$result.installerRun|Should -BeFalse
        @($calls)|Should -Not -Contain 'build:PackageLocal';($calls|ConvertTo-Json -Depth 5)|Should -Not -Match 'installer'
    }
}
