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
            CopyFile={param($source,$destination)$script:calls.Add("copy:$destination");$script:exists[$destination]=$true;$script:hashes[$destination]=$script:hashes[$source];if($source-eq$script:buildReceiptPath){$script:files[$destination]=$script:buildReceipt}elseif($script:files.ContainsKey($source)){$script:files[$destination]=$script:files[$source]}}
            TestReparse={param($path)$false}
            GetChildren={param($path)@()}
            GetSpecialFolder={param($name)if($name-eq'Desktop'){Join-Path $TestDrive 'Desktop'}else{Join-Path $TestDrive 'ProgramsMenu'}}
            PathExists={param($path,$type)[bool]$script:exists[$path]}
            ReadJson={param($path)if($path-eq$script:buildReceiptPath){$script:buildReceipt}elseif($script:files.ContainsKey($path)){$v=$script:files[$path];if($v-is[string]){$v|ConvertFrom-Json}else{$v}}else{throw 'missing-json'}}
            ReadText={param($path)[string]$script:files[$path]}
        }
    }

    It 'defaults to a read-only Check and never creates the build root or installs' {
        $result=Invoke-DshOfficialDesktopLocalInstall -BuildRoot $buildRoot -InstallRoot $installRoot -DataRoot $dataRoot -Operations $ops
        $result.status|Should -Be 'ready';$result.mutated|Should -BeFalse
        @($calls)|Should -Contain 'build:Check'
        ($calls|ConvertTo-Json -Depth 5)|Should -Not -Match 'installer|write:|atomic:|copy:|shortcut:'
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
