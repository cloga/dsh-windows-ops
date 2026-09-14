Import-Module (Join-Path $PSScriptRoot '..\tools\DshOfficialDesktopBuild.psm1') -Force

Describe 'Official deepseek-harness Electron Desktop local build' {
    BeforeEach {
        $script:policy = Get-DshOfficialDesktopBuildPolicy
        $script:fixturePolicy = Get-Content (Join-Path $PSScriptRoot 'fixtures\official-desktop-build\policy.json') -Raw | ConvertFrom-Json
        $script:root = Join-Path $TestDrive 'local-build'
        if (Test-Path $root) { Remove-Item $root -Recurse -Force }
        $script:source = Join-Path $root 'source'
        New-Item -ItemType Directory -Path (Join-Path $source 'apps\desktop') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $source 'apps\desktop-host') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $source '.git\hooks') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $source 'apps\desktop\scripts') -Force | Out-Null
        Copy-Item (Join-Path $PSScriptRoot 'fixtures\official-desktop-build\prepare-seed.ts') (Join-Path $source ($policy.prepareSeedRelativePath.Replace('/','\')))
        @{version=$policy.version;packageManager=$policy.packageManager;engines=@{node=$policy.nodeEngine}}|ConvertTo-Json|Set-Content (Join-Path $source 'package.json')
        @{version=$policy.version;name='@deepseek-ai/dsh-desktop'}|ConvertTo-Json|Set-Content (Join-Path $source 'apps\desktop\package.json')
        @{version=$policy.version;name='@deepseek-ai/dsh-desktop-host'}|ConvertTo-Json|Set-Content (Join-Path $source 'apps\desktop-host\package.json')
        'lockfileVersion: ''9.0'''|Set-Content (Join-Path $source 'pnpm-lock.yaml')
        $script:calls=[Collections.Generic.List[object]]::new();$script:dirty=$false;$script:wrongLock=$false
        $script:runner={
            param($file,$arguments,$cwd,$environment)
            $script:calls.Add([pscustomobject]@{file=$file;arguments=@($arguments);cwd=$cwd;environment=$environment})
            $a=@($arguments);if($a.Count-ge2-and$a[0]-eq'-c'-and$a[1]-eq'core.hooksPath=NUL'){$a=$a[2..($a.Count-1)]};$joined=$a-join' '
            $exit=0;$output=switch -Regex($joined){
                '^--version$'{@('v24.17.0');break}
                '^pnpm@11\.7\.0 --version$'{@('11.7.0');break}
                '^ls-remote '{@($script:policy.commit+"`trefs/tags/"+$script:policy.tag);break}
                '^rev-parse --show-toplevel$'{@($script:source);break}
                '^rev-parse --absolute-git-dir$'{@((Join-Path $script:source '.git'));break}
                '^remote get-url origin$'{@($script:policy.repository);break}
                '^config --local --get core\.hooksPath$'{$exit=1;@();break}
                '^rev-parse HEAD\^\{tree\}$'{@($script:policy.tree);break}
                '^rev-parse HEAD$'{@($script:policy.commit);break}
                '^status '{@($(if($script:dirty){' M package.json'}));break}
                default{@()}
            }
            [pscustomobject]@{exitCode=$exit;output=$output}
        }
    }

    It 'requires the complete immutable policy including exact hashes paths commands and boundary text' {
        ($fixturePolicy|ConvertTo-Json -Depth 20)|Should -Be($policy|ConvertTo-Json -Depth 20)
        foreach($change in @(
            {param($p)$p.commit='0'*40},{param($p)$p.tree='0'*40},{param($p)$p.defaultRegistry='https://example.invalid/'},
            {param($p)$p.sourceDirectory='..\source'},{param($p)$p.toolStateDirectory='..\tools'},
            {param($p)$p.receiptDirectory='..\receipts'},{param($p)$p.officialCommands.install=@('install')},
            {param($p)$p.releaseBoundary.reason='alternate'})) {
            $copy=$fixturePolicy|ConvertTo-Json -Depth 20|ConvertFrom-Json;&$change $copy
            {Test-DshOfficialDesktopBuildPolicy $copy}|Should -Throw '*policy-invalid*'
        }
    }

    It 'rejects relative UNC repository-equal containing and cloud roots' {
        $repo=Split-Path $PSScriptRoot -Parent
        {Assert-DshOfficialDesktopBuildRoot 'relative\work' -RepositoryRoot $repo}|Should -Throw '*absolute*'
        {Assert-DshOfficialDesktopBuildRoot '\\server\share\work' -RepositoryRoot $repo}|Should -Throw '*fixed-local-drive*'
        {Assert-DshOfficialDesktopBuildRoot $repo -RepositoryRoot $repo}|Should -Throw '*operations-repository*'
        {Assert-DshOfficialDesktopBuildRoot (Split-Path $repo -Parent) -RepositoryRoot $repo}|Should -Throw '*operations-repository*'
        {Assert-DshOfficialDesktopBuildRoot 'C:\Users\fixture\OneDrive - Company\work' -RepositoryRoot $repo}|Should -Throw '*cloud-synchronized*'
    }

    It 'rejects reparse points in existing build ancestors' -Skip:($env:OS -ne 'Windows_NT') {
        $target=Join-Path $TestDrive 'real';$link=Join-Path $TestDrive 'linked';New-Item -ItemType Directory $target|Out-Null
        New-Item -ItemType Junction -Path $link -Target $target|Out-Null
        {Assert-DshOfficialDesktopBuildRoot (Join-Path $link 'work')}|Should -Throw '*reparse-point*'
    }

    It 'performs Check without writes installs process control or source operations' {
        $checkRoot=Join-Path $TestDrive 'check-only';$result=Get-DshOfficialDesktopBuildCheck $checkRoot $runner $policy
        $result.status|Should -Be 'ready';Test-Path $checkRoot|Should -BeFalse
        ($calls|ConvertTo-Json -Depth 8)|Should -Not -Match '(?i)clone|install|checkout|start-process|stop-process|taskkill|msiexec'
    }

    It 'refuses Prepare reuse and Verify rejects wrong origin hooks bare or external git dirs' {
        {Invoke-DshOfficialDesktopBuild Prepare $root $runner $policy}|Should -Throw '*refuses-existing-source*'
        foreach($case in @('origin','hooks','bare')) {
            $script:currentCase=$case
            $bad={param($file,$arguments,$cwd,$environment);$a=@($arguments);if($a.Count-ge2-and$a[0]-eq'-c'){$a=$a[2..($a.Count-1)]};$j=$a-join' ';$exit=0;$out=switch -Regex($j){'^--version$'{@('v24.17.0');break}'^ls-remote '{@($script:policy.commit+"`trefs/tags/"+$script:policy.tag);break}'^rev-parse --show-toplevel$'{if($script:currentCase-eq'bare'){@(Join-Path $script:source 'nested')}else{@($script:source)};break}'^rev-parse --absolute-git-dir$'{@((Join-Path $script:source '.git'));break}'^remote get-url origin$'{if($script:currentCase-eq'origin'){@('https://example.invalid/fork.git')}else{@($script:policy.repository)};break}'^config --get core\.hooksPath$'{if($script:currentCase-eq'hooks'){@('hooks')}else{$exit=1;@()};break}default{@()}};[pscustomobject]@{exitCode=$exit;output=$out}}
            {Invoke-DshOfficialDesktopBuild Verify $root $bad $policy}|Should -Throw
        }
        'custom'|Set-Content (Join-Path $source '.git\hooks\pre-commit')
        {Invoke-DshOfficialDesktopBuild Verify $root $runner $policy}|Should -Throw '*custom-hook*'
    }

    It 'uses real local Git config inspection without the hooksPath command override' {
        $git=(Get-Command git).Source;$repo=Join-Path $TestDrive 'real-git';New-Item -ItemType Directory $repo|Out-Null
        & $git -c init.defaultBranch=main -C $repo init | Out-Null;& $git -C $repo remote add origin $policy.repository
        InModuleScope DshOfficialDesktopBuild -Parameters @{repo=$repo;git=$git;policy=$policy} {
            param($repo,$git,$policy)
            $gitEnvironment=@{GIT_CONFIG_NOSYSTEM='1';GIT_CONFIG_GLOBAL='NUL'}
            {Assert-OfficialSourceRepository $repo $git $policy $gitEnvironment $null}|Should -Not -Throw
            & $git -C $repo config --local core.hooksPath hooks
            {Assert-OfficialSourceRepository $repo $git $policy $gitEnvironment $null}|Should -Throw '*hooks-path-configured*'
        }
    }

    It 'rejects nested reparse points in managed tool state before build commands' -Skip:($env:OS -ne 'Windows_NT') {
        $outside=Join-Path $TestDrive 'outside-store';New-Item -ItemType Directory $outside|Out-Null
        $store=Join-Path $root 'tool-state\pnpm-store';New-Item -ItemType Directory $store -Force|Out-Null
        New-Item -ItemType Junction -Path (Join-Path $store 'v3') -Target $outside|Out-Null
        {Invoke-DshOfficialDesktopBuild Build $root $runner $policy}|Should -Throw '*reparse-point*'
        @($calls|Where-Object{($_.arguments-join' ')-match'pnpm@11\.7\.0'}).Count|Should -Be 0
    }

    It 'rejects manifest and pinned pnpm version mismatches' {
        $manifest=Get-Content (Join-Path $source 'package.json') -Raw|ConvertFrom-Json;$manifest.packageManager='pnpm@10.0.0';$manifest|ConvertTo-Json|Set-Content (Join-Path $source 'package.json')
        {Invoke-DshOfficialDesktopBuild Build $root $runner $policy}|Should -Throw '*package-manager-mismatch*'
        $manifest.packageManager=$policy.packageManager;$manifest|ConvertTo-Json|Set-Content (Join-Path $source 'package.json')
        $badPnpm={param($file,$arguments,$cwd,$environment);$a=@($arguments);if(($a-join' ')-eq'pnpm@11.7.0 --version'){return [pscustomobject]@{exitCode=0;output=@('11.6.0')}};&$script:runner $file $arguments $cwd $environment}
        {Invoke-DshOfficialDesktopBuild Build $root $badPnpm $policy}|Should -Throw '*pnpm-version-mismatch*'
    }

    It 'isolates writable config state while preserving the caller proxy and TLS environment' {
        $result=Invoke-DshOfficialDesktopBuild Build $root $runner $policy;$install=@($calls|Where-Object{($_.arguments-join' ')-match'install --frozen-lockfile'})[0]
        foreach($name in @('DSH_HOME','HOME','USERPROFILE','APPDATA','LOCALAPPDATA','COREPACK_HOME','PNPM_HOME','npm_config_cache','npm_config_store_dir','npm_config_userconfig','npm_config_globalconfig','XDG_CONFIG_HOME','XDG_STATE_HOME','XDG_CACHE_HOME','TEMP','TMP')){$install.environment[$name]|Should -Match([regex]::Escape($root))}
        $install.environment.GIT_CONFIG_NOSYSTEM|Should -Be '1';$install.environment.GIT_CONFIG_GLOBAL|Should -Be 'NUL';$install.environment.CI|Should -Be 'true'
        foreach($name in @('NODE_OPTIONS','NODE_PATH','npm_config_script_shell','GIT_DIR','GIT_WORK_TREE','GIT_CONFIG_COUNT','GIT_SSH_COMMAND','GIT_ASKPASS','COREPACK_INTEGRITY_KEYS')){$install.environment[$name]|Should -BeNullOrEmpty}
        @($calls|Where-Object{$_.file-like'*git*'}|ForEach-Object{$_.arguments[0..1]-join' '})|Should -Not -Contain ''
    }

    It 'accepts only absolute credential-free HTTPS registry URLs' {
        Assert-DshRegistry 'https://registry.npmjs.org/' | Should -Be 'https://registry.npmjs.org/'
        Assert-DshRegistry 'https://packages.example.test/npm/' | Should -Be 'https://packages.example.test/npm/'
        foreach($bad in @('http://registry.npmjs.org/','registry.npmjs.org','https://user@registry.example/','https://registry.example/?x=1','https://registry.example/#x')) {
            { Assert-DshRegistry $bad } | Should -Throw '*registry-must*'
        }
    }

    It 'patches exactly two official registry routing literals and restores original bytes after success' {
        $seed=Join-Path $source ($policy.prepareSeedRelativePath.Replace('/','\'))
        (Get-FileHash $seed -Algorithm SHA256).Hash.ToLowerInvariant() | Should -Be $policy.prepareSeedSha256
        $sawPatched=$false
        $proxyRunner={param($file,$arguments,$cwd,$environment);if(($arguments-join' ')-match'run prepare:desktop'){$body=[IO.File]::ReadAllText($seed);$script:sawPatched=(([regex]::Matches($body,[regex]::Escape('https://packages.example.test/npm/'))).Count-eq2)};&$script:runner $file $arguments $cwd $environment}
        $build=Invoke-DshOfficialDesktopBuild Build $root $proxyRunner $policy 'https://packages.example.test/npm/'
        $script:sawPatched | Should -BeTrue
        (Get-FileHash $seed -Algorithm SHA256).Hash.ToLowerInvariant() | Should -Be $policy.prepareSeedSha256
        $build.receipt.registryRouting.deviation | Should -BeTrue
        $build.receipt.registryRouting.patchedSha256 | Should -Not -Be $policy.prepareSeedSha256
        $build.receipt.registryRouting.restored | Should -BeTrue
    }

    It 'generates a syntax-valid canonical file URI for special-character source paths' {
        $specialRoot=Join-Path $TestDrive "quote' # percent% Unicode-测试"
        $specialSource=Join-Path $specialRoot 'source'
        New-Item -ItemType Directory (Join-Path $specialSource 'apps\desktop') -Force|Out-Null
        ''|Set-Content (Join-Path $specialSource 'apps\desktop\electron-builder.config.mjs')
        InModuleScope DshOfficialDesktopBuild -Parameters @{specialRoot=$specialRoot;specialSource=$specialSource;policy=$policy} {
            param($specialRoot,$specialSource,$policy)
            New-Item -ItemType Directory (Join-Path $specialRoot 'tool-state') -Force|Out-Null
            $overlay=New-LocalOverlay $specialRoot $specialSource $policy
            $text=Get-Content $overlay.path -Raw
            $text|Should -Match 'file:///'
            $text|Should -Match '%23|%25|%27'
            & (Get-Command node).Source --check $overlay.path
            $LASTEXITCODE|Should -Be 0
        }
    }

    It 'fails closed when a hash-pinned candidate has one or three registry literals' {
        $candidate=Join-Path $TestDrive 'seed-candidate.ts'
        foreach($count in @(1,3)){
            $body=((1..$count|ForEach-Object{"const r$_ = 'https://registry.npmjs.org/'"})-join"`n")
            [IO.File]::WriteAllText($candidate,$body,[Text.UTF8Encoding]::new($false));$hash=(Get-FileHash $candidate -Algorithm SHA256).Hash.ToLowerInvariant()
            {Assert-PrepareSeedRegistrySource $candidate $hash 2}|Should -Throw '*literal-count-mismatch*'
        }
    }

    It 'restores original prepare-seed bytes even when official prepare fails' {
        $seed=Join-Path $source ($policy.prepareSeedRelativePath.Replace('/','\'))
        $failed={param($file,$arguments,$cwd,$environment);if(($arguments-join' ')-match'run prepare:desktop'){return [pscustomobject]@{exitCode=9;output=@('failed')}};&$script:runner $file $arguments $cwd $environment}
        {Invoke-DshOfficialDesktopBuild Build $root $failed $policy 'https://packages.example.test/npm/'} | Should -Throw '*official-desktop-prepare:9*'
        (Get-FileHash $seed -Algorithm SHA256).Hash.ToLowerInvariant() | Should -Be $policy.prepareSeedSha256
    }

    It 'fails after a command when tracked source or lockfile drifts' {
        $count=0;$postDirty={param($file,$arguments,$cwd,$environment);$r=&$script:runner $file $arguments $cwd $environment;if(($arguments-join' ')-match'install --frozen-lockfile'){$script:dirty=$true};return $r}
        {Invoke-DshOfficialDesktopBuild Build $root $postDirty $policy}|Should -Throw '*source-dirty*'
        $script:dirty=$false;$changedLock={param($file,$arguments,$cwd,$environment);$r=&$script:runner $file $arguments $cwd $environment;if(($arguments-join' ')-match'install --frozen-lockfile'){'changed'|Set-Content (Join-Path $script:source 'pnpm-lock.yaml')};return $r}
        {Invoke-DshOfficialDesktopBuild Build $root $changedLock $policy}|Should -Throw '*lockfile-drift*'
    }

    It 'fails closed on a non-frozen command failure' {
        $failed={param($file,$arguments,$cwd,$environment);if(($arguments-join' ')-match'vitest run'){return [pscustomobject]@{exitCode=7;output=@()}};&$script:runner $file $arguments $cwd $environment}
        {Invoke-DshOfficialDesktopBuild Build $root $failed $policy}|Should -Throw '*official-desktop-test:7*'
    }

    It 'creates a strict unsigned PackageLocal receipt with external local identity overlay and scrubbed signing environment' {
        Mock Get-AuthenticodeSignature { [pscustomobject]@{Status='NotSigned'} } -ModuleName DshOfficialDesktopBuild
        Mock Get-LocalExecutableVersionInfo { [pscustomobject]@{ProductName='DSH Local Build';FileDescription='DSH Local Build';InternalName='DSH Local Build'} } -ModuleName DshOfficialDesktopBuild
        $target=Join-Path $source 'apps\desktop\.desktop-build\targets\win-x64'
        $packageRunner={
            param($file,$arguments,$cwd,$environment)
            $joined=$arguments-join' '
            if($joined-match'run prepare:desktop'){
                New-Item -ItemType Directory (Join-Path $target 'seed') -Force|Out-Null
                New-Item -ItemType Directory (Join-Path $target 'runtime') -Force|Out-Null
                @{schemaVersion=1;version='0.1.5-rc.2';hostProtocolVersion=3;nodeVersion='24.17.0';pnpmVersion='11.7.0'}|ConvertTo-Json|Set-Content (Join-Path $target 'seed\desktop-release.json')
                @{schemaVersion=1;node='24.17.0';pnpm='11.7.0'}|ConvertTo-Json|Set-Content (Join-Path $target 'runtime\versions.json')
            }
            if($joined-match'exec electron-builder'){
                $out=Join-Path $target 'artifacts';$unpacked=Join-Path $out 'win-unpacked';New-Item -ItemType Directory (Join-Path $unpacked 'resources') -Force|Out-Null
                [IO.File]::WriteAllBytes((Join-Path $out 'dsh-local-build-0.1.5-rc.2-win-x64.exe'),[byte[]](1,2,3))
                [IO.File]::WriteAllBytes((Join-Path $unpacked 'DSH Local Build.exe'),[byte[]](4,5,6))
                [IO.File]::WriteAllBytes((Join-Path $unpacked 'resources\app.asar'),[byte[]](7,8,9))
            }
            &$script:runner $file $arguments $cwd $environment
        }
        $old=@{};foreach($name in @('DSH_DESKTOP_TARGET','DSH_DESKTOP_WINDOWS_TOKEN_PIN','CSC_LINK','NODE_OPTIONS','GIT_DIR','GIT_CONFIG_COUNT','GIT_CONFIG_KEY_0','GIT_CONFIG_VALUE_0')){$old[$name]=[Environment]::GetEnvironmentVariable($name,'Process');Set-Item -LiteralPath ("Env:"+$name) -Value 'secret'}
        try{$package=Invoke-DshOfficialDesktopBuild PackageLocal $root $packageRunner $policy}catch{throw}finally{foreach($name in $old.Keys){if($null-eq$old[$name]){Remove-Item -LiteralPath ("Env:"+$name) -ErrorAction SilentlyContinue}else{Set-Item -LiteralPath ("Env:"+$name) -Value $old[$name]}}}
        foreach($name in $old.Keys){[Environment]::GetEnvironmentVariable($name,'Process')|Should -Be $old[$name]}
        [IO.Path]::GetFullPath(((& git rev-parse --show-toplevel).Trim()))|Should -Be (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $call=@($calls|Where-Object{($_.arguments-join' ')-match'exec electron-builder'})[0]
        $record=@($package.receipt.commands|Where-Object name -eq 'local-electron-builder')[0]
        $record.arguments.Count | Should -Be 9
        $record.arguments[5] | Should -Be '--win'
        $record.arguments[6] | Should -Be '--x64'
        $record.arguments[7] | Should -Be '--publish'
        $record.arguments[8] | Should -Be 'never'
        $record.arguments | Should -Contain '--config'
        $call.cwd | Should -Be (Join-Path $source 'apps\desktop')
        $call.environment.DSH_DESKTOP_APP_ID | Should -Be 'local.cloga.dsh-official-source-build'
        $call.environment.DSH_DESKTOP_AUTO_UPDATE_ENV | Should -Be 'test'
        $call.environment.DOWNLOAD_TEST_ORIGIN | Should -Be 'https://invalid.invalid'
        $call.environment.DSH_DESKTOP_TARGET | Should -BeNullOrEmpty
        $call.environment.DSH_DESKTOP_WINDOWS_TOKEN_PIN | Should -BeNullOrEmpty
        $call.environment.CSC_LINK | Should -BeNullOrEmpty
        $call.environment.NODE_OPTIONS | Should -BeNullOrEmpty
        $call.environment.GIT_DIR | Should -BeNullOrEmpty
        $call.environment.GIT_CONFIG_COUNT | Should -BeNullOrEmpty
        $call.environment.GIT_CONFIG_KEY_0 | Should -BeNullOrEmpty
        $call.environment.GIT_CONFIG_VALUE_0 | Should -BeNullOrEmpty
        $overlay=Get-Content $package.receipt.localPackage.overlayPath -Raw
        $overlay | Should -Match "appId: 'local\.cloga\.dsh-official-source-build'"
        $overlay | Should -Match "productName: 'DSH Local Build'"
        $overlay | Should -Match "name: 'dsh-local-build'"
        $overlay | Should -Match 'publish: null'
        $overlay | Should -Match 'forceCodeSigning: false'
        $overlay | Should -Match 'signtoolOptions: undefined'
        $overlay | Should -Not -Match 'DeepSeek Harness|download\.deepseek\.com'
        $package.receipt.releaseBoundary.status | Should -Be 'local-build-complete'
        $package.receipt.releaseBoundary.officialIdentityClaim | Should -BeFalse
        $package.receipt.releaseBoundary.officialSignature | Should -BeFalse
        $package.receipt.releaseBoundary.updateChannel | Should -BeFalse
        Test-DshOfficialDesktopBuildReceipt $package.receiptPath $source $policy (Get-Command git).Source 'v24.17.0' '11.7.0' $runner | Should -BeTrue
        $forged=Get-Content $package.receiptPath -Raw|ConvertFrom-Json;$forged.localPackage.overlayPath=Join-Path $root 'elsewhere.mjs';$forged.PSObject.Properties.Remove('receiptSha256');$forgedPath=Join-Path $TestDrive 'forged-local.json';Write-DshOfficialDesktopBuildReceipt $forged $forgedPath|Out-Null
        Test-DshOfficialDesktopBuildReceipt $forgedPath $source $policy (Get-Command git).Source 'v24.17.0' '11.7.0' $runner | Should -BeFalse
        $forged=Get-Content $package.receiptPath -Raw|ConvertFrom-Json;$forged.commands[-1].workingDirectory=$source;$forged.PSObject.Properties.Remove('receiptSha256');$forgedPath=Join-Path $TestDrive 'forged-cwd.json';Write-DshOfficialDesktopBuildReceipt $forged $forgedPath|Out-Null
        Test-DshOfficialDesktopBuildReceipt $forgedPath $source $policy (Get-Command git).Source 'v24.17.0' '11.7.0' $runner | Should -BeFalse
    }

    It 'refuses stale artifact cleanup through a reparse point' -Skip:($env:OS -ne 'Windows_NT') {
        $target=Join-Path $source 'apps\desktop\.desktop-build\targets\win-x64';New-Item -ItemType Directory $target -Force|Out-Null
        $outside=Join-Path $TestDrive 'outside-artifacts';New-Item -ItemType Directory $outside|Out-Null;'keep'|Set-Content (Join-Path $outside 'keep.txt')
        New-Item -ItemType Junction -Path (Join-Path $target 'artifacts') -Target $outside|Out-Null
        {Invoke-DshOfficialDesktopBuild PackageLocal $root $runner $policy}|Should -Throw '*reparse-point*'
        Test-Path (Join-Path $outside 'keep.txt')|Should -BeTrue
    }

    It 'creates a strict receipt and Verify validates it without overwrite' {
        $artifact=Join-Path $source 'apps\desktop\.desktop-build\targets\win-x64\artifacts\sample.bin';New-Item -ItemType Directory (Split-Path $artifact) -Force|Out-Null;'original'|Set-Content $artifact
        $build=Invoke-DshOfficialDesktopBuild Build $root $runner $policy
        $before=(Get-FileHash -LiteralPath $build.receiptPath).Hash
        $receiptDirectory=Split-Path -Parent $build.receiptPath
        $count=@(Get-ChildItem -LiteralPath $receiptDirectory).Count
        $verify=Invoke-DshOfficialDesktopBuild Verify $root $runner $policy
        $verify.status|Should -Be 'verified'
        (Get-FileHash -LiteralPath $build.receiptPath).Hash|Should -Be $before
        @(Get-ChildItem -LiteralPath $receiptDirectory).Count|Should -Be $count
        {Write-DshOfficialDesktopBuildReceipt $build.receipt $build.receiptPath}|Should -Throw '*already-exists*'
    }

    It 'rejects recomputed forged receipt omitted or extra artifacts and traversal paths' {
        $artifact=Join-Path $source 'apps\desktop\.desktop-build\targets\win-x64\artifacts\sample.bin';New-Item -ItemType Directory (Split-Path $artifact) -Force|Out-Null;'original'|Set-Content $artifact
        $build=Invoke-DshOfficialDesktopBuild Build $root $runner $policy
        function Save-Forged($receipt){$receipt.PSObject.Properties.Remove('receiptSha256');$tmp=Join-Path $TestDrive ([guid]::NewGuid().ToString()+'.json');Write-DshOfficialDesktopBuildReceipt $receipt $tmp|Out-Null;return $tmp}
        $r=Get-Content $build.receiptPath -Raw|ConvertFrom-Json;$r.source.commit='0'*40;$p=Save-Forged $r;Test-DshOfficialDesktopBuildReceipt $p $source $policy (Get-Command git).Source 'v24.17.0' '11.7.0' $runner|Should -BeFalse
        $r=Get-Content $build.receiptPath -Raw|ConvertFrom-Json;$r.artifacts=@();$p=Save-Forged $r;Test-DshOfficialDesktopBuildReceipt $p $source $policy (Get-Command git).Source 'v24.17.0' '11.7.0' $runner|Should -BeFalse
        $r=Get-Content $build.receiptPath -Raw|ConvertFrom-Json;$r.artifacts[0].path='../escape';$p=Save-Forged $r;Test-DshOfficialDesktopBuildReceipt $p $source $policy (Get-Command git).Source 'v24.17.0' '11.7.0' $runner|Should -BeFalse
        'extra'|Set-Content (Join-Path (Split-Path $artifact) 'extra.bin');Test-DshOfficialDesktopBuildReceipt $build.receiptPath $source $policy (Get-Command git).Source 'v24.17.0' '11.7.0' $runner|Should -BeFalse
    }

    It 'requires a prior receipt for Verify and never claims package identity or update channel' {
        {Invoke-DshOfficialDesktopBuild Verify $root $runner $policy}|Should -Throw '*receipt-not-found*'
        $policy.releaseBoundary.status|Should -Be 'signed-release-unavailable';$policy.releaseBoundary.officialIdentityClaim|Should -BeFalse;$policy.releaseBoundary.updateChannelConfigured|Should -BeFalse;$policy.releaseBoundary.packageCreated|Should -BeFalse
        $text=(Get-Content (Join-Path $PSScriptRoot '..\tools\DshOfficialDesktopBuild.psm1') -Raw)+(Get-Content (Join-Path $PSScriptRoot '..\tools\build-official-desktop.ps1') -Raw)
        $text|Should -Not -Match 'package:desktop:win:x64';$text|Should -Match 'PackageLocal';$text|Should -Match 'local\.cloga\.dsh-official-source-build';$text|Should -Not -Match '(?i)Stop-Process|Start-Process|taskkill|msiexec|uninstall'
    }
}
