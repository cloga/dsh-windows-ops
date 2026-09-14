# Dot-sourced by the installer so path and operation guards remain shared.
function Get-LocalHomeSelection {
    param([string]$SharedHome,[switch]$UseIsolatedHome,$Receipt,[string]$DataRoot)
    if($SharedHome -and $UseIsolatedHome){throw 'shared-home-conflicts-with-isolated-home'}
    $saved=Get-LocalLeafValue $Receipt 'home'
    if($SharedHome){$mode='shared';$path=Get-LocalNormalizedPath $SharedHome}
    elseif($UseIsolatedHome){$mode='isolated';$path=Join-Path $DataRoot 'harness-home'}
    elseif($saved){$mode=[string]$saved.mode;$path=[string]$saved.path}
    else{$mode='isolated';$path=Join-Path $DataRoot 'harness-home'}
    if($mode -notin @('shared','isolated')){throw 'saved-home-mode-invalid'}
    if($mode -eq 'isolated' -and $path -cne (Join-Path $DataRoot 'harness-home')){throw 'saved-isolated-home-invalid'}
    [pscustomobject]@{mode=$mode;path=$path;electronUserData=(Join-Path $DataRoot 'electron-user-data');profileBackup=(Get-LocalLeafValue $saved 'profileBackup')}
}

function Assert-LocalSharedHome {
    param($Selection,[string]$InstallRoot,[string]$DataRoot,[string]$BuildRoot,[hashtable]$Operations)
    $path=Assert-DshOfficialDesktopLocalPath $Selection.path 'shared-home' $Operations
    if($path.Substring(2) -match '[:*?]' -or $path -match '[\\/][^\\/]*[ .]([\\/]|$)' -or
        $path -match '(?i)[\\/](con|prn|aux|nul|com[1-9]|lpt[1-9])([.\\/]|$)'){throw 'shared-home-ambiguous-path'}
    if(-not (&$Operations.PathExists $path 'Container')){throw 'shared-home-must-exist'}
    foreach($other in @($InstallRoot,$DataRoot,$BuildRoot,(Split-Path $PSScriptRoot -Parent),(Join-Path $env:APPDATA 'io.github.hairyf.deepseek-harness-desktop'))){
        if((Test-LocalPathAtOrWithin $path $other)-or(Test-LocalPathAtOrWithin $other $path)){throw 'shared-home-path-overlap'}
    }
    if((Test-LocalPathAtOrWithin $HOME $path)-or $path -match '(?i)[\\/](profiles|sessions|workspaces|desktop|node_modules)$'){throw 'shared-home-not-a-home'}
    $defaultHome=Join-Path $HOME '.dsh'
    if($path -ine $defaultHome -and ((Test-LocalPathAtOrWithin $path $defaultHome)-or(Test-LocalPathAtOrWithin $defaultHome $path))){throw 'shared-home-nested-home'}
    if(-not (&$Operations.PathExists (Join-Path $path 'settings.yaml') 'Leaf') -or -not (&$Operations.PathExists (Join-Path $path 'sessions') 'Container')){throw 'shared-home-markers-missing'}
    foreach($marker in @('settings.yaml','sessions')){$null=Assert-DshOfficialDesktopLocalPath (Join-Path $path $marker) 'shared-home-marker' $Operations}
    foreach($owned in @($path,(Join-Path $path 'profiles'),(Join-Path $path 'profiles\desktop'),(Join-Path $path 'desktop'))){
        $null=Assert-DshOfficialDesktopLocalPath $owned 'shared-home-owned-path' $Operations
        if((&$Operations.PathExists $owned '') -and -not (&$Operations.IsCurrentUserOwner $owned)){throw 'shared-home-owner-mismatch'}
    }
    foreach($journal in @('desktop\pending.json','desktop\rollback\profile')){
        if(&$Operations.PathExists (Join-Path $path $journal) ''){throw 'shared-home-desktop-recovery-required'}
    }
    # Rename must stay on one volume; never turn backup into a recursive copy.
    if([IO.Path]::GetPathRoot($path) -cne [IO.Path]::GetPathRoot($DataRoot)){throw 'shared-home-backup-volume-mismatch'}
}

function Get-LocalSharedRuntimeBlockers {
    param($Probe,[string]$HarnessHome,[string]$InstallRoot)
    if([bool](Get-LocalLeafValue $Probe 'unavailable')){throw 'shared-home-process-enumeration-unavailable'}
    if(-not $Probe -or $Probe.PSObject.Properties.Name -notcontains 'items' -or $null -eq $Probe.items){throw 'shared-home-process-enumeration-invalid'}
    foreach($process in @($Probe.items)){
        $exe=[string](Get-LocalLeafValue $process 'ExecutablePath')
        $command=[string](Get-LocalLeafValue $process 'CommandLine')
        $name=[string](Get-LocalLeafValue $process 'Name')
        if(-not $process -or (-not $exe -and -not $name)){throw 'shared-home-process-enumeration-invalid'}
        $runtime=$name -match '(?i)^(node|pnpm|dsh|deepseek.*)\.exe$' -or $exe -match '(?i)[\\/](node|pnpm|dsh|deepseek[^\\/]*)\.exe$'
        $matched=($exe -and ((Test-LocalPathAtOrWithin $exe $InstallRoot)-or(Test-LocalPathAtOrWithin $exe $HarnessHome))) -or
            $name -match '(?i)^(dsh|deepseek.*)\.exe$' -or $exe -match '(?i)[\\/](dsh|deepseek[^\\/]*)\.exe$' -or
            ($runtime -and (-not $command -or $command -match '(?i)(deepseek|dsh|desktop-host)' -or $command.IndexOf($HarnessHome,[StringComparison]::OrdinalIgnoreCase) -ge 0))
        if($matched){[pscustomobject]@{id=(Get-LocalLeafValue $process 'Id');reason='possible-shared-home-consumer'}}
    }
}

function Get-LocalSharedProfile {
    param([string]$HarnessHome,[string]$InstallRoot,[hashtable]$Operations)
    $profile=Join-Path $HarnessHome 'profiles\desktop'
    if(-not (&$Operations.PathExists $profile '')){return [pscustomobject]@{kind='absent';path=$profile;fingerprint=$null}}
    if(-not (&$Operations.PathExists $profile 'Container')){throw 'shared-desktop-profile-not-directory'}
    $null=Assert-DshOfficialDesktopLocalPath $profile 'shared-desktop-profile' $Operations
    $release=Join-Path $profile 'desktop-release.json'
    if(&$Operations.PathExists $release 'Leaf'){
        # Only the unchanged official seed profile is supported here. Plugin/custom
        # transactions remain exclusively owned by DesktopProjectManager.
        $seed=Join-Path $InstallRoot 'resources\seed'
        $manifestPath=Join-Path $profile 'package.json'
        $null=Assert-DshOfficialDesktopLocalPath $manifestPath 'shared-profile-metadata' $Operations
        $manifest=&$Operations.ReadJson $manifestPath
        $bundles=@(Get-LocalLeafValue (Get-LocalLeafValue (Get-LocalLeafValue $manifest 'dsh') 'profile') 'bundles')
        foreach($bundle in @('@deepseek-ai/dsh-acp-app','@deepseek-ai/dsh-headless','@deepseek-ai/dsh-sdk-app','@deepseek-ai/dsh-sdk-minimal')){
            if($bundles -contains $bundle){throw 'shared-official-profile-conflicting-app-bundles'}
        }
        foreach($item in @(&$Operations.GetDirectChildren $profile)){
            if($item.Name -notin @('package.json','desktop-release.json','desktop-packages.json','pnpm-workspace.yaml','pnpm-lock.yaml','desktop-packages','node_modules','cordis.patch.yml')){throw 'shared-official-profile-customized-or-corrupt'}
            if($item.Name -eq 'cordis.patch.yml'){
                $patch=Join-Path $profile $item.Name
                $null=Assert-DshOfficialDesktopLocalPath $patch 'shared-profile-patch' $Operations
                if((&$Operations.GetHash $patch) -notin @('ef189a8c27db6d63930aa3046a3040482e952eafcb7487c644d508e8d461f027','37517e5f3dc66819f61f5a7bb8ace1921282415f10551d2defa5c3eb0985b570')){throw 'shared-official-profile-customized-or-corrupt'}
            }
        }
        foreach($file in @('package.json','desktop-release.json','desktop-packages.json','pnpm-workspace.yaml','pnpm-lock.yaml')){
            $actual=Join-Path $profile $file;$expected=Join-Path $seed $file
            $null=Assert-DshOfficialDesktopLocalPath $actual 'shared-profile-metadata' $Operations
            if(-not (&$Operations.PathExists $actual 'Leaf') -or -not (&$Operations.PathExists $expected 'Leaf') -or
                (&$Operations.GetHash $actual) -cne (&$Operations.GetHash $expected)){throw 'shared-official-profile-customized-or-corrupt'}
        }
        $version=&$Operations.ReadJson $release
        if($manifest.name -cne '@deepseek-ai/dsh-desktop-runtime' -or $manifest.private -ne $true -or
            $version.version -cne '0.1.5-rc.2' -or $version.hostProtocolVersion -ne 3 -or
            $version.nodeVersion -cne '24.17.0' -or $version.pnpmVersion -cne '11.7.0'){throw 'shared-official-profile-identity-invalid'}
        foreach($name in @('@deepseek-ai/dsh','@deepseek-ai/dsh-desktop-host')){
            $packagePath=Join-Path $profile ('node_modules\'+$name.Replace('/','\')+'\package.json')
            $null=Assert-DshOfficialDesktopLocalPath $packagePath 'shared-profile-package' $Operations
            $package=&$Operations.ReadJson $packagePath
            if($package.name -cne $name -or $package.version -cne '0.1.5-rc.2'){throw 'shared-official-profile-runtime-invalid'}
        }
        $packages=Join-Path $profile 'desktop-packages'
        Assert-NoLocalReparseTree $packages $Operations
        if((&$Operations.GetTreeHash $packages) -cne (&$Operations.GetTreeHash (Join-Path $seed 'desktop-packages'))){throw 'shared-official-profile-packages-invalid'}
        return [pscustomobject]@{kind='official';path=$profile;fingerprint=(&$Operations.GetHash $release)}
    }
    $expected=[ordered]@{
        'package.json'='bb3969723f1c7590c78a59cd7aaf8b98ad8eefae0ec590cfe6e7f4ef21d77f53'
        'cordis.yml'='37517e5f3dc66819f61f5a7bb8ace1921282415f10551d2defa5c3eb0985b570'
        'cordis.patch.yml'='ef189a8c27db6d63930aa3046a3040482e952eafcb7487c644d508e8d461f027'
        'pnpm-workspace.yaml'='ae7c5b68e2f157528e62885804e69e88583897b775e03c86fcbe52feaf498aba'
    }
    $top=@(&$Operations.GetDirectChildren $profile)
    $names=@($top|ForEach-Object{$_.Name}|Sort-Object)
    $allowed=@(@($expected.Keys)+@('node_modules','.dsh-module-fallback')|Sort-Object)
    if((ConvertTo-LocalCanonicalJson $names) -cne (ConvertTo-LocalCanonicalJson $allowed)){throw 'shared-desktop-profile-unknown'}
    foreach($file in $expected.Keys){
        $path=Join-Path $profile $file
        $null=Assert-DshOfficialDesktopLocalPath $path 'shared-legacy-metadata' $Operations
        if(-not (&$Operations.PathExists $path 'Leaf') -or (&$Operations.GetHash $path) -cne $expected[$file]){throw 'shared-desktop-profile-unknown'}
    }
    foreach($dir in @('node_modules','.dsh-module-fallback')){
        $path=Join-Path $profile $dir
        $null=Assert-DshOfficialDesktopLocalPath $path 'shared-legacy-directory' $Operations
        if(-not (&$Operations.PathExists $path 'Container')){throw 'shared-desktop-profile-unknown'}
    }
    $fallback=Join-Path $profile '.dsh-module-fallback'
    $fallbackChildren=@(&$Operations.GetDirectChildren $fallback)
    if($fallbackChildren.Count -ne 1 -or $fallbackChildren[0].Name -cne 'node_modules' -or
        -not (&$Operations.PathExists (Join-Path $fallback 'node_modules') 'Container') -or
        @(&$Operations.GetDirectChildren (Join-Path $fallback 'node_modules')).Count -ne 0 -or
        @(&$Operations.GetDirectChildren (Join-Path $profile 'node_modules')).Count -ne 0){throw 'shared-desktop-profile-nonempty-dependencies'}
    Assert-NoLocalReparseTree $profile $Operations
    [pscustomobject]@{kind='legacy-blank';path=$profile;fingerprint=(&$Operations.GetOpaqueTreeHash $profile)}
}

function Move-LocalSharedLegacyProfile {
    param($Check,[hashtable]$Operations)
    if($Check.home.mode -ne 'shared'){return $Check.home.profileBackup}
    Assert-LocalSharedHome $Check.home $Check.installRoot $Check.dataRoot $Check.buildRoot $Operations
    $blockers=@(Get-LocalSharedRuntimeBlockers (&$Operations.GetProcesses) $Check.home.path $Check.installRoot)
    if($blockers.Count){throw 'shared-home-runtime-running'}
    $current=Get-LocalSharedProfile $Check.home.path $Check.installRoot $Operations
    if($current.kind -cne $Check.sharedProfile.kind -or $current.fingerprint -cne $Check.sharedProfile.fingerprint){throw 'shared-home-profile-changed'}
    if($current.kind -ne 'legacy-blank'){return $Check.home.profileBackup}
    if(-not $Check.sharedHomeExplicit){throw 'shared-home-legacy-backup-explicit-opt-in-required'}
    $root=Join-Path $Check.dataRoot ('install-backups\shared-profile-'+[guid]::NewGuid().ToString('N'))
    Assert-NoLocalReparseTree $root $Operations
    $destination=Join-Path $root 'desktop'
    if(&$Operations.PathExists $root ''){throw 'shared-home-backup-already-exists'}
    $record=[pscustomobject]@{schemaVersion=1;status='prepared';source=$current.path;destination=$destination;fingerprint=$current.fingerprint;automaticRollback=$false}
    $journal=Join-Path $root 'backup.json'
    &$Operations.WriteAtomicText $journal ($record|ConvertTo-Json -Depth 8)
    try{
        # Recheck after the journal write, immediately before the only home mutation.
        if(@(Get-LocalSharedRuntimeBlockers (&$Operations.GetProcesses) $Check.home.path $Check.installRoot).Count){throw 'shared-home-runtime-running'}
        Assert-LocalSharedHome $Check.home $Check.installRoot $Check.dataRoot $Check.buildRoot $Operations
        if((&$Operations.GetOpaqueTreeHash $current.path) -cne $current.fingerprint){throw 'shared-home-profile-changed'}
        &$Operations.MoveDirectory $current.path $destination
        if((&$Operations.PathExists $current.path '') -or -not (&$Operations.PathExists $destination 'Container') -or
            (&$Operations.GetOpaqueTreeHash $destination) -cne $current.fingerprint){throw 'shared-home-backup-verification-failed'}
        $record.status='moved'
        &$Operations.WriteAtomicText $journal ($record|ConvertTo-Json -Depth 8)
        return $record
    }catch{throw ('partial-install-manual-review-required: shared profile backup journal '+$journal+'; '+$_.Exception.Message)}
}

function Start-LocalHomeTransaction {
    param($Check,[hashtable]$Operations)
    $previous=Get-LocalLeafValue $Check.installReceipt 'home'
    foreach($selection in @($previous,$Check.home)){
        if($selection -and $selection.mode -eq 'shared' -and
            @(Get-LocalSharedRuntimeBlockers (&$Operations.GetProcesses) $selection.path $Check.installRoot).Count){throw 'shared-home-runtime-running'}
    }
    $pending=Join-Path $Check.dataRoot 'home-change.pending.json'
    Assert-NoLocalReparseTree $pending $Operations
    if(&$Operations.PathExists $pending ''){throw 'home-change-recovery-required'}
    $backup=Join-Path $Check.dataRoot ('install-backups\home-change-'+[guid]::NewGuid().ToString('N'))
    Assert-NoLocalReparseTree $backup $Operations
    $rows=@()
    foreach($source in @((Join-Path $Check.installRoot $script:LauncherName),(Join-Path $Check.dataRoot $script:InstallReceiptName))){
        if(&$Operations.PathExists $source 'Leaf'){
            $destination=Join-Path $backup (Split-Path -Leaf $source)
            $hash=&$Operations.GetHash $source
            &$Operations.CopyFile $source $destination
            if((&$Operations.GetHash $source) -cne $hash -or (&$Operations.GetHash $destination) -cne $hash){throw 'home-change-backup-verification-failed'}
            $rows+= [pscustomobject]@{source=$source;backup=$destination;sha256=$hash}
        }

    }
    &$Operations.WriteAtomicText $pending ([pscustomobject]@{schemaVersion=1;home=$Check.home;files=$rows;automaticRollback=$false}|ConvertTo-Json -Depth 12)
    return $pending
}

function Assert-LocalLauncherOwnership {
    param($Check,[hashtable]$Operations)
    $launcher=Join-Path $Check.installRoot $script:LauncherName
    if(-not (&$Operations.PathExists $launcher 'Leaf')){return}
    $savedLauncher=Get-LocalLeafValue $Check.installReceipt 'launcher'
    $savedHash=Get-LocalLeafValue $savedLauncher 'launcherSha256'
    if($savedHash -and (&$Operations.GetHash $launcher) -ceq $savedHash){return}
    $expected=Get-LocalLauncherContent $Check.installRoot $Check.dataRoot $Check.home.path
    if(($Check.sharedHomeExplicit -or $Check.isolatedHomeExplicit) -and (&$Operations.ReadText $launcher) -ceq $expected){return}
    throw 'launcher-modified-review-required'
}

function Get-LocalLauncherContent {
    param([string]$InstallRoot,[string]$DataRoot,[string]$HarnessHome)
    $exe=Join-Path $InstallRoot 'DeepSeek Harness.exe'
    $userData=Join-Path $DataRoot 'electron-user-data'
    return "@echo off`r`nsetlocal`r`nset `"DSH_HOME=$HarnessHome`"`r`nstart `"`" `"$exe`" `"--user-data-dir=$userData`" %*`r`n"
}
