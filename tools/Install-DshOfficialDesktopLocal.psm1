Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'DshOfficialDesktopBuild.psm1')
. (Join-Path $PSScriptRoot 'DshOfficialDesktopSharedHome.ps1')

$script:InstallReceiptName = 'official-desktop-local-install.json'
$script:LauncherName = 'DeepSeek Harness Local Build.cmd'
$script:ExpectedDisplayName = 'DeepSeek Harness 0.1.5-rc.2'

function ConvertTo-LocalCanonicalJson { param($Value) return ($Value | ConvertTo-Json -Depth 40 -Compress) }
function Get-LocalNormalizedPath { param([Parameter(Mandatory)][string]$Path) return [IO.Path]::GetFullPath($Path).TrimEnd('\','/') }
function Test-LocalPathAtOrWithin { param([string]$Candidate,[string]$Parent);$c=Get-LocalNormalizedPath $Candidate;$p=Get-LocalNormalizedPath $Parent;return $c.Equals($p,[StringComparison]::OrdinalIgnoreCase)-or($c+'\').StartsWith($p+'\',[StringComparison]::OrdinalIgnoreCase) }
function Get-LocalReceiptPayloadHash { param($Receipt);$copy=[ordered]@{};foreach($p in $Receipt.PSObject.Properties){if($p.Name-cne'receiptSha256'){$copy[$p.Name]=$p.Value}};$bytes=[Text.Encoding]::UTF8.GetBytes((ConvertTo-LocalCanonicalJson $copy));$sha=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()} }
function Test-LocalReceiptHash { param($Receipt);return $Receipt.receiptSha256-and((Get-LocalReceiptPayloadHash $Receipt)-ceq[string]$Receipt.receiptSha256) }
function Get-LocalLeafValue { param($Object,[string]$Name);if($null-eq$Object){return $null};$property=@($Object.PSObject.Properties|Where-Object{$_.Name-ceq$Name}|Select-Object -First 1);if($property.Count){return $property[0].Value};return $null }
function ConvertFrom-QuotedLocalPath { param($Value);if($null-eq$Value){return $null};$text=([string]$Value).Trim();if($text-match'^(?<quoted>"[^"]+"|''[^'']+'')\s*(?:,\s*-?\d+)?$'){$text=$Matches.quoted};if($text.Length-ge2-and(($text[0]-eq'"'-and$text[$text.Length-1]-eq'"')-or($text[0]-eq"'"-and$text[$text.Length-1]-eq"'"))){$text=$text.Substring(1,$text.Length-2).Trim()}elseif($text-match'^(?<path>.+?),\s*-?\d+$'){$text=$Matches.path.Trim()};if([string]::IsNullOrWhiteSpace($text)){return $null};return $text }

function Get-DshOfficialDesktopLocalOperations {
    [CmdletBinding()]param()
    return @{
        InvokeBuild = { param($action,$buildRoot,$registry,$pnpmPath) Invoke-DshOfficialDesktopBuild -Action $action -BuildRoot $buildRoot -Registry $registry -PnpmPath $pnpmPath }
        ValidateBuildReceipt = { param($path,$sourceRoot,$pnpmPath,$recordedOnly) Test-DshOfficialDesktopBuildReceipt -Path $path -SourceRoot $sourceRoot -PnpmPath $pnpmPath -RecordedEvidenceOnly:$recordedOnly }
        GetSignature = { param($path) (Get-AuthenticodeSignature -LiteralPath $path).Status.ToString() }
        GetVersionInfo = { param($path) (Get-Item -LiteralPath $path).VersionInfo }
        GetHash = { param($path) (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
        GetTreeHash = { param($path) $root=Get-LocalNormalizedPath $path;$rows=@(Get-ChildItem -LiteralPath $root -File -Recurse|Sort-Object FullName|ForEach-Object{[pscustomobject]@{path=(Get-LocalNormalizedPath $_.FullName).Substring($root.Length).TrimStart('\').Replace('\','/');size=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}});$bytes=[Text.Encoding]::UTF8.GetBytes((ConvertTo-LocalCanonicalJson $rows));$sha=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()} }
        GetProcesses = { try{[pscustomobject]@{unavailable=$false;items=@(Get-CimInstance Win32_Process -ErrorAction Stop | ForEach-Object { [pscustomobject]@{ Id=$_.ProcessId; Name=$_.Name; ExecutablePath=$_.ExecutablePath; CommandLine=$_.CommandLine } })}}catch{[pscustomobject]@{unavailable=$true;items=@()}} }
        IsCurrentUserOwner = { param($path) (Get-Acl -LiteralPath $path).GetOwner([Security.Principal.SecurityIdentifier]).Value -ceq [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }
        GetDirectChildren = { param($path) @(Get-ChildItem -LiteralPath $path -Force) }
        MoveDirectory = { param($source,$destination) [IO.Directory]::Move($source,$destination) }
        RemoveFile = { param($path) Remove-Item -LiteralPath $path -ErrorAction Stop }
        GetOpaqueTreeHash = {
            param($path)
            $root=Get-LocalNormalizedPath $path
            $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($root)
            $rows=[Collections.Generic.List[object]]::new()
            while($pending.Count){
                foreach($item in Get-ChildItem -LiteralPath $pending.Pop() -Force){
                    $relative=$item.FullName.Substring($root.Length).TrimStart('\')
                    if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){
                        throw 'shared-profile-unexpected-reparse'
                    }elseif($item.PSIsContainer){
                        $rows.Add([pscustomobject]@{path=$relative;kind='directory'});$pending.Push($item.FullName)
                    }else{
                        $rows.Add([pscustomobject]@{path=$relative;kind='file';size=$item.Length;sha256=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()})
                    }
                }
            }
            $sha=[Security.Cryptography.SHA256]::Create()
            try{([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes((ConvertTo-LocalCanonicalJson @($rows|Sort-Object path)))))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
        }
        GetUninstallEntries = {
            $paths=@('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')
            @($paths|ForEach-Object{Get-ItemProperty $_ -ErrorAction SilentlyContinue}|ForEach-Object{
                [pscustomobject]@{
                    DisplayName=Get-LocalLeafValue $_ 'DisplayName'
                    UninstallString=Get-LocalLeafValue $_ 'UninstallString'
                    InstallLocation=ConvertFrom-QuotedLocalPath (Get-LocalLeafValue $_ 'InstallLocation')
                    DisplayIcon=Get-LocalLeafValue $_ 'DisplayIcon'
                }
            })
        }
        StartInstaller = { param($path,$arguments) $p=Start-Process -FilePath $path -ArgumentList ([string[]]$arguments) -Wait -PassThru;[pscustomobject]@{ExitCode=$p.ExitCode} }
        ReadShortcut = { param($path) if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return $null};$shell=New-Object -ComObject WScript.Shell;$s=$shell.CreateShortcut($path);[pscustomobject]@{TargetPath=$s.TargetPath;Arguments=$s.Arguments;Description=$s.Description} }
        WriteShortcut = { param($path,$target,$arguments,$description,$icon) $parent=Split-Path -Parent $path;if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null};$shell=New-Object -ComObject WScript.Shell;$s=$shell.CreateShortcut($path);$s.TargetPath=$target;$s.Arguments=$arguments;$s.Description=$description;$s.IconLocation=$icon;$s.Save() }
        WriteText = { param($path,$text) $parent=Split-Path -Parent $path;if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null};[IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false)) }
        WriteAtomicText = { param($path,$text) $parent=Split-Path -Parent $path;if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null};$temp=$path+'.tmp-'+[guid]::NewGuid().ToString('N');[IO.File]::WriteAllText($temp,$text,[Text.UTF8Encoding]::new($false));Move-Item -LiteralPath $temp -Destination $path -Force }
        CopyFile = { param($source,$destination) $parent=Split-Path -Parent $destination;if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null};Copy-Item -LiteralPath $source -Destination $destination -Force }
        TestReparse = { param($path) if(-not(Test-Path -LiteralPath $path)){return $false};return [bool]((Get-Item -LiteralPath $path -Force).Attributes-band[IO.FileAttributes]::ReparsePoint) }
        GetChildren = { param($path) if(Test-Path -LiteralPath $path -PathType Container){@(Get-ChildItem -LiteralPath $path -Force -Recurse)}else{@()} }
        GetSpecialFolder = { param($name) [Environment]::GetFolderPath($name) }
        PathExists = { param($path,$type) if($type-eq'Leaf'){Test-Path -LiteralPath $path -PathType Leaf}elseif($type-eq'Container'){Test-Path -LiteralPath $path -PathType Container}else{Test-Path -LiteralPath $path} }
        ReadJson = { param($path) Get-Content -LiteralPath $path -Raw|ConvertFrom-Json }
        ReadText = { param($path) [IO.File]::ReadAllText($path) }
    }
}

function Merge-LocalOperations { param([hashtable]$Operations);$all=Get-DshOfficialDesktopLocalOperations;if($Operations){foreach($key in $Operations.Keys){$all[$key]=$Operations[$key]}};return $all }
function Assert-NoLocalReparseTree { param([string]$Path,[hashtable]$Operations);$cursor=Get-LocalNormalizedPath $Path;while($cursor){if(&$Operations.TestReparse $cursor){throw 'local-owned-path-reparse-point'};$parent=Split-Path -Parent $cursor;if(-not$parent-or$parent-ceq$cursor){break};$cursor=$parent};foreach($item in @(&$Operations.GetChildren $Path)){if(&$Operations.TestReparse ([string](Get-LocalLeafValue $item 'FullName'))){throw 'local-owned-path-reparse-point'}} }

function Assert-DshOfficialDesktopLocalPath {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][hashtable]$Operations)
    if([string]::IsNullOrWhiteSpace($Path)){throw "$Name-must-be-absolute"}
    if($Path-match'[\r\n"&|<>^%!`]'){throw "$Name-contains-command-metacharacter"}
    try { if(-not[IO.Path]::IsPathRooted($Path)){throw "$Name-must-be-absolute"} } catch { if($_.Exception.Message -like "*$Name-must-be-absolute*" -or $_.Exception.Message -like "*$Name-contains-command-metacharacter*"){throw};throw "$Name-invalid-path" }
    if($Path.StartsWith('\\')-or$Path.StartsWith('//')){throw "$Name-must-be-fixed-local-drive"}
    $root=Get-LocalNormalizedPath $Path
    $driveName=[IO.Path]::GetPathRoot($root).TrimEnd('\').TrimEnd(':');$drive=Get-PSDrive -Name $driveName -PSProvider FileSystem -ErrorAction SilentlyContinue
    if(-not$drive-or$drive.DisplayRoot-or($drive.Root-and$drive.Root.StartsWith('\\'))){throw "$Name-must-be-fixed-local-drive"}
    try{if([IO.DriveInfo]::new([IO.Path]::GetPathRoot($root)).DriveType-ne[IO.DriveType]::Fixed){throw "$Name-must-be-fixed-local-drive"}}catch{if($_.Exception.Message-eq"$Name-must-be-fixed-local-drive"){throw};throw "$Name-must-be-fixed-local-drive"}
    foreach($cloud in @($env:OneDrive,$env:OneDriveCommercial,$env:OneDriveConsumer,$env:Dropbox,$env:GoogleDrive)){if($cloud-and[IO.Path]::IsPathRooted($cloud)-and(Test-LocalPathAtOrWithin $root $cloud)){throw "$Name-cloud-synchronized"}}
    if($root-match'(?i)(^|[\\/])(OneDrive(?: - [^\\/]+)?|Dropbox|Google Drive|iCloudDrive)([\\/]|$)'){throw "$Name-cloud-synchronized"}
    $cursor=$root;while($cursor){if(&$Operations.TestReparse $cursor){throw "$Name-reparse-point"};$parent=Split-Path -Parent $cursor;if(-not$parent-or$parent-ceq$cursor){break};$cursor=$parent}
    return $root
}

function Get-LocalShortcutPaths { param([hashtable]$Operations);$desktop=&$Operations.GetSpecialFolder 'Desktop';$programs=&$Operations.GetSpecialFolder 'Programs';return @((Join-Path $desktop 'DeepSeek Harness.lnk'),(Join-Path $programs 'DeepSeek Harness.lnk')) }
function Get-CommunityState {
    param([object[]]$Entries,[string]$InstallRoot,[hashtable]$Operations)
    $matches=@($Entries|Where-Object{
        $displayName=[string](Get-LocalLeafValue $_ 'DisplayName')
        $location=ConvertFrom-QuotedLocalPath (Get-LocalLeafValue $_ 'InstallLocation')
        $displayName -and $displayName -match '(?i)^Deep\s*Seek Harness(?: Desktop)?(?:\s|$)' -and
        $displayName -cne $script:ExpectedDisplayName -and
        (-not $location -or -not (Test-LocalPathAtOrWithin $location $InstallRoot))
    })
    $exeMatches=@($matches|Where-Object{
        $location=ConvertFrom-QuotedLocalPath (Get-LocalLeafValue $_ 'InstallLocation')
        $displayIcon=ConvertFrom-QuotedLocalPath (Get-LocalLeafValue $_ 'DisplayIcon')
        $candidates=[Collections.Generic.List[string]]::new()
        if($location){$candidates.Add((Join-Path $location 'DeepSeek Harness.exe'));$candidates.Add((Join-Path $location 'deepseek-harness-desktop.exe'))}
        if($displayIcon-and[IO.Path]::IsPathRooted($displayIcon)-and(-not$location-or(Test-LocalPathAtOrWithin $displayIcon $location))){$candidates.Add($displayIcon)}
        [bool]@($candidates|Where-Object{&$Operations.PathExists $_ 'Leaf'}).Count
    })
    return [pscustomobject]@{entries=$matches;present=[bool]$matches.Count;executablePresent=[bool]$exeMatches.Count}
}

function Get-DshOfficialDesktopLocalCheck {
    [CmdletBinding()]param([string]$BuildRoot='C:\tmp\dsh-official-desktop-build\work',[string]$Registry='https://registry.npmjs.org/',[string]$PnpmPath,[string]$InstallRoot=(Join-Path $env:LOCALAPPDATA 'Programs\DSH Local Build'),[string]$DataRoot=(Join-Path $env:LOCALAPPDATA 'DSH Local Build'),[hashtable]$Operations,[string]$SharedHome,[switch]$UseIsolatedHome)
    $ops=Merge-LocalOperations $Operations;$repo=Split-Path $PSScriptRoot -Parent;$install=Assert-DshOfficialDesktopLocalPath $InstallRoot install-root $ops;$data=Assert-DshOfficialDesktopLocalPath $DataRoot data-root $ops;$build=Assert-DshOfficialDesktopBuildRoot $BuildRoot -RepositoryRoot $repo;$registryValue=Assert-DshRegistry $Registry
    foreach($pair in @(@($install,$data),@($install,$build),@($data,$build),@($install,$repo),@($data,$repo))){if((Test-LocalPathAtOrWithin $pair[0] $pair[1])-or(Test-LocalPathAtOrWithin $pair[1] $pair[0])){throw 'local-path-overlap'}}
    foreach($protected in @((Join-Path $env:APPDATA 'io.github.hairyf.deepseek-harness-desktop'),(Join-Path $HOME '.dsh'))){if($protected-and((Test-LocalPathAtOrWithin $install $protected)-or(Test-LocalPathAtOrWithin $protected $install)-or(Test-LocalPathAtOrWithin $data $protected)-or(Test-LocalPathAtOrWithin $protected $data))){throw 'local-path-overlaps-community-data'}}
    $entries=@(&$ops.GetUninstallEntries);$processProbe=&$ops.GetProcesses;$processUnavailable=[bool](Get-LocalLeafValue $processProbe 'unavailable');$processItems=if($null-ne(Get-LocalLeafValue $processProbe 'items')){@(Get-LocalLeafValue $processProbe 'items')}else{@($processProbe)};$processes=@($processItems|Where-Object{$executable=[string](Get-LocalLeafValue $_ 'ExecutablePath');$executable-and(Test-LocalPathAtOrWithin $executable $install)});$shortcuts=@(Get-LocalShortcutPaths $ops|ForEach-Object{[pscustomobject]@{path=$_;value=(&$ops.ReadShortcut $_)}});$receiptPath=Join-Path $data $script:InstallReceiptName;$receipt=$null;if(&$ops.PathExists $receiptPath 'Leaf'){try{$receipt=&$ops.ReadJson $receiptPath}catch{$receipt=[pscustomobject]@{invalid=$true}}}
    $trusted=$receipt -and (Test-TrustedLocalInstallReceipt $receipt $build $install $data $ops $PnpmPath)
    $buildCheck=if($trusted){[pscustomobject]@{status='ready';action='installed-evidence';sourceRevalidated=$false}}else{&$ops.InvokeBuild 'Check' $build $registryValue $PnpmPath}
    $selection=Get-LocalHomeSelection $SharedHome -UseIsolatedHome:$UseIsolatedHome -Receipt $receipt -DataRoot $data
    $reasons=[Collections.Generic.List[string]]::new();$profile=$null;$sharedProcesses=@()
    if($trusted){
        try{$null=Assert-InstalledLocalDesktop $install ([pscustomobject]@{executableHash=$receipt.installedExecutableSha256;seedHash=$receipt.installedSeedSha256}) $ops}
        catch{$reasons.Add($_.Exception.Message)}
    }
    if(&$ops.PathExists (Join-Path $data 'home-change.pending.json') ''){$reasons.Add('home-change-recovery-required')}
    if($receipt -and (Get-LocalLeafValue $receipt 'invalid')){$reasons.Add('install-receipt-unreadable')}
    if((Get-LocalLeafValue $receipt 'home') -and -not$trusted){$reasons.Add('saved-home-receipt-untrusted')}
    if($selection.mode -eq 'shared'){
        try{
            Assert-LocalSharedHome $selection $install $data $build $ops
            $profile=Get-LocalSharedProfile $selection.path $install $ops
            if($profile.kind -eq 'official' -and -not $trusted){$reasons.Add('shared-official-seed-attestation-required')}
            $sharedProcesses=@(Get-LocalSharedRuntimeBlockers $processProbe $selection.path $install)
            if($sharedProcesses.Count){$reasons.Add('shared-home-runtime-running')}
            if($profile.kind -eq 'legacy-blank' -and -not $SharedHome){$reasons.Add('shared-home-legacy-backup-explicit-opt-in-required')}
        }catch{$reasons.Add($_.Exception.Message)}
    }
    elseif((Get-LocalLeafValue (Get-LocalLeafValue $receipt 'home') 'mode') -eq 'shared'){
        try{
            if(@(Get-LocalSharedRuntimeBlockers $processProbe $receipt.home.path $install).Count){$reasons.Add('shared-home-runtime-running')}
        }catch{$reasons.Add($_.Exception.Message)}
    }
    [pscustomobject]@{schemaVersion=2;action='check';status=$(if($buildCheck.status-eq'ready'-and-not$reasons.Count){'ready'}else{'blocked'});reasons=@($reasons);home=$selection;sharedProfile=$profile;sharedHomeExplicit=[bool]$SharedHome;isolatedHomeExplicit=[bool]$UseIsolatedHome;runningSharedProcesses=$sharedProcesses;copilotDesktopInstall='unsupported-release-tarball-spec';build=$buildCheck;buildRoot=$build;registry=$registryValue;installRoot=$install;dataRoot=$data;sourcePresent=[bool](&$ops.PathExists (Join-Path $build 'source') 'Container');installedExecutable=(Join-Path $install 'DeepSeek Harness.exe');installPresent=[bool](&$ops.PathExists (Join-Path $install 'DeepSeek Harness.exe') 'Leaf');installReceipt=$receipt;uninstallEntries=@($entries|Where-Object{[string](Get-LocalLeafValue $_ 'DisplayName')-ceq$script:ExpectedDisplayName});community=(Get-CommunityState $entries $install $ops);shortcuts=$shortcuts;runningLocalProcesses=$processes;processEnumerationUnavailable=$processUnavailable;mutated=$false;launchedGui=$false;stoppedProcesses=$false}
}

function Assert-LocalPackageReceipt {
    param($Package,[string]$BuildRoot,[string]$DataRoot,[string]$Registry,[hashtable]$Operations,[string]$PnpmPath)
    if(-not$Package-or$Package.status-cne'complete'-or$Package.action-cne'packagelocal'){throw 'packagelocal-result-invalid'}
    $sourceReceipt=Get-LocalNormalizedPath $Package.receiptPath;if(-not(Test-LocalPathAtOrWithin $sourceReceipt (Join-Path $BuildRoot 'receipts'))){throw 'packagelocal-receipt-outside-build-root'}
    $snapshotRoot=Join-Path $DataRoot 'artifacts\build-receipts';Assert-NoLocalReparseTree (Join-Path $DataRoot 'artifacts') $Operations;Assert-NoLocalReparseTree $snapshotRoot $Operations
    $sourceHashBefore=&$Operations.GetHash $sourceReceipt;$snapshot=Join-Path $snapshotRoot ($sourceHashBefore+'.json');Assert-NoLocalReparseTree $snapshot $Operations
    if(&$Operations.PathExists $snapshot 'Leaf'){if((&$Operations.GetHash $snapshot)-cne$sourceHashBefore){throw 'packagelocal-receipt-snapshot-conflict'}}else{&$Operations.CopyFile $sourceReceipt $snapshot}
    $sourceHashAfter=&$Operations.GetHash $sourceReceipt;$snapshotHashBefore=&$Operations.GetHash $snapshot
    if($sourceHashBefore-cne$sourceHashAfter-or$sourceHashBefore-cne$snapshotHashBefore){throw 'packagelocal-receipt-changed-during-copy'}
    if(-not(&$Operations.ValidateBuildReceipt $snapshot $Package.sourceRoot $PnpmPath)){throw 'packagelocal-receipt-invalid'}
    if((&$Operations.GetHash $snapshot)-cne$snapshotHashBefore){throw 'packagelocal-receipt-snapshot-changed'}
    $r=&$Operations.ReadJson $snapshot
    if((&$Operations.GetHash $snapshot)-cne$snapshotHashBefore){throw 'packagelocal-receipt-snapshot-changed'}
    $policy=Get-DshOfficialDesktopBuildPolicy
    if($r.action-cne'packagelocal'-or$r.status-cne'complete'-or$r.source.commit-cne$policy.commit-or$r.source.tree-cne$policy.tree-or$r.registryRouting.registry-cne$Registry){throw 'packagelocal-receipt-policy-mismatch'}
    if($r.releaseBoundary.officialSignature-ne$false-or$r.releaseBoundary.updateChannel-ne$false-or$r.localPackage.identity.appId-cne$policy.localPackage.appId-or$r.localPackage.identity.packageName-cne$policy.localPackage.packageName-or$r.localPackage.identity.productName-cne$policy.localPackage.productName){throw 'packagelocal-local-identity-mismatch'}
    $installer=Get-LocalNormalizedPath $r.localPackage.installerPath;$unpacked=Get-LocalNormalizedPath $r.localPackage.executablePath;if(-not(Test-LocalPathAtOrWithin $installer $BuildRoot)-or-not(Test-LocalPathAtOrWithin $unpacked $BuildRoot)){throw 'packagelocal-artifact-outside-build-root'}
    if((-not(&$Operations.PathExists $installer 'Leaf'))-or(-not(&$Operations.PathExists $unpacked 'Leaf'))){throw 'packagelocal-artifact-missing'}
    if((&$Operations.GetHash $installer)-cne$r.localPackage.hashes.installer-or(&$Operations.GetHash $unpacked)-cne$r.localPackage.hashes.executable){throw 'packagelocal-artifact-hash-mismatch'}
    if((&$Operations.GetSignature $installer)-cne'NotSigned'-or(&$Operations.GetSignature $unpacked)-cne'NotSigned'){throw 'packagelocal-artifact-must-be-unsigned'}
    if($r.localPackage.appUpdatePresent-ne$false-or$r.localPackage.seed.version-cne'0.1.5-rc.2'-or$r.localPackage.seed.hostProtocolVersion-ne3-or$r.localPackage.seed.nodeVersion-cne'24.17.0'-or$r.localPackage.seed.pnpmVersion-cne'11.7.0'){throw 'packagelocal-seed-mismatch'}
    return [pscustomobject]@{receipt=$r;receiptPath=(Get-LocalNormalizedPath $snapshot);receiptFileHash=$snapshotHashBefore;installerPath=$installer;unpackedExecutable=$unpacked;installerHash=$r.localPackage.hashes.installer;executableHash=$r.localPackage.hashes.executable;seedHash=$r.localPackage.hashes.seed}
}

function Assert-InstalledLocalDesktop {
    param([string]$InstallRoot,$PackageEvidence,[hashtable]$Operations)
    $exe=Join-Path $InstallRoot 'DeepSeek Harness.exe';if(-not(&$Operations.PathExists $exe 'Leaf')){throw 'installed-executable-missing'}
    if((&$Operations.GetHash $exe)-cne$PackageEvidence.executableHash){throw 'installed-executable-hash-mismatch'}
    if((&$Operations.GetSignature $exe)-cne'NotSigned'){throw 'installed-executable-must-be-unsigned'}
    $v=&$Operations.GetVersionInfo $exe;foreach($name in @('ProductName','FileDescription','InternalName')){if([string]$v.$name-cne'DeepSeek Harness'){throw "installed-version-info-mismatch:$name"}};if([string]$v.FileVersion-cne'0.1.5-rc.2'){throw 'installed-file-version-mismatch'}
    $seedRoot=Join-Path $InstallRoot 'resources\seed';Assert-NoLocalReparseTree $seedRoot $Operations;$seedPath=Join-Path $seedRoot 'desktop-release.json';if(-not(&$Operations.PathExists $seedPath 'Leaf')){throw 'installed-seed-missing'};$seed=&$Operations.ReadJson $seedPath;if($seed.version-cne'0.1.5-rc.2'-or$seed.hostProtocolVersion-ne3-or$seed.nodeVersion-cne'24.17.0'-or$seed.pnpmVersion-cne'11.7.0'){throw 'installed-seed-mismatch'}
    $manifestPath=Join-Path $seedRoot 'package.json';$packageSetPath=Join-Path $seedRoot 'desktop-packages.json';if((-not(&$Operations.PathExists $manifestPath 'Leaf'))-or(-not(&$Operations.PathExists $packageSetPath 'Leaf'))){throw 'installed-core-package-evidence-missing'}
    $manifest=&$Operations.ReadJson $manifestPath;$packageSet=&$Operations.ReadJson $packageSetPath
    if([string](Get-LocalLeafValue $manifest 'name')-cne'@deepseek-ai/dsh-desktop-runtime'-or(Get-LocalLeafValue $packageSet 'schemaVersion')-ne1){throw 'installed-core-package-evidence-invalid'}
    foreach($name in @('@deepseek-ai/dsh','@deepseek-ai/dsh-desktop-host')){
        $spec=[string](Get-LocalLeafValue (Get-LocalLeafValue $manifest 'dependencies') $name);if($spec-cnotmatch'^file:\./desktop-packages/.+-0\.1\.5-rc\.2\.tgz$'){throw "installed-core-manifest-mismatch:$name"}
        $records=@(Get-LocalLeafValue $packageSet 'packages'|Where-Object{[string](Get-LocalLeafValue $_ 'name')-ceq$name});if($records.Count-ne1-or[string](Get-LocalLeafValue $records[0] 'version')-cne'0.1.5-rc.2'){throw "installed-core-package-set-mismatch:$name"}
    }
    if((&$Operations.GetTreeHash $seedRoot)-cne$PackageEvidence.seedHash){throw 'installed-seed-tree-hash-mismatch'}
    if(&$Operations.PathExists (Join-Path $InstallRoot 'resources\app-update.yml') 'Leaf'){throw 'installed-update-config-present'}
    $entry=@(&$Operations.GetUninstallEntries|Where-Object{[string](Get-LocalLeafValue $_ 'DisplayName')-ceq$script:ExpectedDisplayName});if($entry.Count-lt1){throw 'installed-uninstall-entry-mismatch'};$uninstalls=@($entry|ForEach-Object{[string](Get-LocalLeafValue $_ 'UninstallString')}|Where-Object{$_}|Select-Object -Unique);if($uninstalls.Count-ne1){throw 'installed-uninstall-entry-conflict'};$uninstall=$uninstalls[0];if($uninstall.IndexOf($InstallRoot,[StringComparison]::OrdinalIgnoreCase)-lt0){throw 'installed-uninstall-string-outside-install-root'}
    return [pscustomobject]@{executablePath=$exe;executableHash=$PackageEvidence.executableHash;uninstallString=$uninstall;seed=$seed}
}

function Write-LocalLauncherAndShortcuts {
    param([string]$InstallRoot,[string]$DataRoot,[hashtable]$Operations,$Selection)
    Assert-NoLocalReparseTree $InstallRoot $Operations
    if(-not $Selection){$Selection=Get-LocalHomeSelection -DataRoot $DataRoot}
    $launcher=Join-Path $InstallRoot $script:LauncherName;$exe=Join-Path $InstallRoot 'DeepSeek Harness.exe'
    $body=Get-LocalLauncherContent $InstallRoot $DataRoot $Selection.path
    $shortcutPaths=@(Get-LocalShortcutPaths $Operations)
    foreach($path in $shortcutPaths){$old=&$Operations.ReadShortcut $path;if($old-and$old.TargetPath-and-not(Test-LocalPathAtOrWithin $old.TargetPath $InstallRoot)){throw 'shortcut-target-outside-local-install'}}
    &$Operations.WriteText $launcher $body
    $description='DeepSeek Harness local source build (unsigned; '+$(if($Selection.mode-eq'shared'){'shared DSH home'}else{'isolated DSH home'})+'; update channel not configured)'
    foreach($path in $shortcutPaths){&$Operations.WriteShortcut $path $launcher '' $description $exe}
    if((&$Operations.ReadText $launcher) -cne $body){throw 'launcher-write-verification-failed'}
    foreach($path in $shortcutPaths){$actual=&$Operations.ReadShortcut $path;if(-not $actual -or $actual.TargetPath -cne $launcher -or $actual.Arguments -cne '' -or $actual.Description -cne $description){throw 'shortcut-write-verification-failed'}}
    return [pscustomobject]@{launcherPath=$launcher;launcherSha256=(&$Operations.GetHash $launcher);shortcutPaths=@(Get-LocalShortcutPaths $Operations);description=$description}
}

function Write-LocalInstallReceipt {
    param($Receipt,[string]$Path,[hashtable]$Operations)
    $copy=$Receipt|ConvertTo-Json -Depth 40|ConvertFrom-Json;$copy|Add-Member receiptSha256 (Get-LocalReceiptPayloadHash $copy) -Force;&$Operations.WriteAtomicText $Path ($copy|ConvertTo-Json -Depth 40)
    $written=&$Operations.ReadJson $Path
    if(-not(Test-LocalReceiptHash $written) -or (ConvertTo-LocalCanonicalJson $written) -cne (ConvertTo-LocalCanonicalJson $copy)){throw 'install-receipt-write-verification-failed'}
    return $copy
}
function Test-ExactLocalKeys { param($Object,[string[]]$Names);if($null-eq$Object){return $false};return (ConvertTo-LocalCanonicalJson @($Object.PSObject.Properties.Name|Sort-Object))-ceq(ConvertTo-LocalCanonicalJson @($Names|Sort-Object)) }
function Test-TrustedLocalInstallReceipt {
    param($Receipt,[string]$BuildRoot,[string]$InstallRoot,[string]$DataRoot,[hashtable]$Operations,[string]$PnpmPath)
    try {
        $keys=@('schemaVersion','status','createdUtc','source','installerPath','installerSha256','installedExecutablePath','installedExecutableSha256','installedSeedSha256','installRoot','dataRoot','identity','launcher','rollback','receiptSha256')
        if($Receipt.schemaVersion -eq 2){$keys+= 'home';if(-not(Test-ExactLocalKeys $Receipt.home @('mode','path','electronUserData','profileBackup'))){return $false};if($Receipt.home.mode -notin @('shared','isolated') -or $Receipt.home.electronUserData -cne (Join-Path $DataRoot 'electron-user-data')){return $false}}
        if(-not(Test-ExactLocalKeys $Receipt $keys)){return $false}
        if(-not(Test-ExactLocalKeys $Receipt.source @('repository','tag','commit','tree','buildReceiptPath','buildReceiptSha256','buildReceiptFileSha256'))-or-not(Test-ExactLocalKeys $Receipt.identity @('productName','appId','packageName','unsigned','automaticUpdates'))){return $false}
        $policy=Get-DshOfficialDesktopBuildPolicy
        if($Receipt.schemaVersion-notin@(1,2)-or$Receipt.status-cne'complete'-or-not(Test-LocalReceiptHash $Receipt)-or$Receipt.installRoot-cne$InstallRoot-or$Receipt.dataRoot-cne$DataRoot){return $false}
        if($Receipt.source.repository-cne$policy.repository-or$Receipt.source.tag-cne$policy.tag-or$Receipt.source.commit-cne$policy.commit-or$Receipt.source.tree-cne$policy.tree){return $false}
        if($Receipt.identity.productName-cne$policy.localPackage.productName-or$Receipt.identity.appId-cne$policy.localPackage.appId-or$Receipt.identity.packageName-cne$policy.localPackage.packageName-or$Receipt.identity.unsigned-ne$true-or$Receipt.identity.automaticUpdates-ne$false){return $false}
        $sourceRoot=Join-Path $BuildRoot $policy.sourceDirectory;$buildReceipt=Get-LocalNormalizedPath $Receipt.source.buildReceiptPath;$archive=Get-LocalNormalizedPath $Receipt.installerPath
        if(-not(Test-LocalPathAtOrWithin $buildReceipt (Join-Path $DataRoot 'artifacts\build-receipts'))-or-not(Test-LocalPathAtOrWithin $archive (Join-Path $DataRoot 'artifacts'))){return $false}
        if((-not(&$Operations.PathExists $buildReceipt 'Leaf'))-or(-not(&$Operations.PathExists $archive 'Leaf'))){return $false}
        Assert-NoLocalReparseTree (Join-Path $DataRoot 'artifacts') $Operations
        $buildHashBefore=&$Operations.GetHash $buildReceipt;if($buildHashBefore-cne$Receipt.source.buildReceiptFileSha256-or-not(&$Operations.ValidateBuildReceipt $buildReceipt $sourceRoot $PnpmPath $true)){return $false};$buildEvidence=&$Operations.ReadJson $buildReceipt
        if((&$Operations.GetHash $buildReceipt)-cne$buildHashBefore-or$buildEvidence.receiptSha256-cne$Receipt.source.buildReceiptSha256){return $false}
        if(-not(Test-LocalPathAtOrWithin (Get-LocalNormalizedPath $buildEvidence.localPackage.installerPath) $BuildRoot)-or$buildEvidence.localPackage.hashes.installer-cne$Receipt.installerSha256-or$buildEvidence.localPackage.hashes.executable-cne$Receipt.installedExecutableSha256){return $false}
        if((&$Operations.GetHash $archive)-cne$buildEvidence.localPackage.hashes.installer-or(&$Operations.GetSignature $archive)-cne'NotSigned'){return $false}
        if((Get-LocalNormalizedPath $Receipt.installedExecutablePath)-cne(Get-LocalNormalizedPath (Join-Path $InstallRoot 'DeepSeek Harness.exe'))-or(&$Operations.GetHash $Receipt.installedExecutablePath)-cne$buildEvidence.localPackage.hashes.executable-or$Receipt.installedSeedSha256-cne$buildEvidence.localPackage.hashes.seed){return $false}
        return $true
    } catch { return $false }
}

function Invoke-DshOfficialDesktopLocalInstall {
    [CmdletBinding()]param([ValidateSet('Check','Apply')][string]$Action='Check',[string]$BuildRoot='C:\tmp\dsh-official-desktop-build\work',[string]$Registry='https://registry.npmjs.org/',[string]$PnpmPath,[string]$InstallRoot=(Join-Path $env:LOCALAPPDATA 'Programs\DSH Local Build'),[string]$DataRoot=(Join-Path $env:LOCALAPPDATA 'DSH Local Build'),[switch]$AcknowledgeUnsignedLocalBuild,[hashtable]$Operations,[string]$SharedHome,[switch]$UseIsolatedHome)
    $ops=Merge-LocalOperations $Operations;$check=Get-DshOfficialDesktopLocalCheck $BuildRoot $Registry $PnpmPath $InstallRoot $DataRoot $ops -SharedHome $SharedHome -UseIsolatedHome:$UseIsolatedHome;if($Action-eq'Check'-or$check.status-ne'ready'){return $check};if(-not$AcknowledgeUnsignedLocalBuild){throw 'acknowledge-unsigned-local-build-required'};if($check.processEnumerationUnavailable){throw 'local-process-enumeration-unavailable'};if(@($check.runningLocalProcesses).Count){throw 'local-build-process-running'};Assert-NoLocalReparseTree $check.installRoot $ops
    $receiptPath=Join-Path $check.dataRoot $script:InstallReceiptName;$artifactDir=Join-Path $check.dataRoot 'artifacts';$snapshotRoot=Join-Path $artifactDir 'build-receipts';$backupDir=Join-Path $check.dataRoot 'install-backups';Assert-NoLocalReparseTree $artifactDir $ops;Assert-NoLocalReparseTree $snapshotRoot $ops;Assert-NoLocalReparseTree $backupDir $ops;Assert-NoLocalReparseTree $receiptPath $ops;$old=$check.installReceipt
    $oldInvalid=$old-and($old.PSObject.Properties.Name-ccontains'invalid')-and[bool]$old.invalid
    if($old-and-not$oldInvalid-and(Test-TrustedLocalInstallReceipt $old $check.buildRoot $check.installRoot $check.dataRoot $ops $PnpmPath)){
        $evidence=[pscustomobject]@{executableHash=$old.installedExecutableSha256;seedHash=$old.installedSeedSha256};$post=Assert-InstalledLocalDesktop $check.installRoot $evidence $ops
        Assert-LocalLauncherOwnership $check $ops
        try{
            $pending=Start-LocalHomeTransaction $check $ops
            $check.home.profileBackup=Move-LocalSharedLegacyProfile $check $ops
            $shell=Write-LocalLauncherAndShortcuts $check.installRoot $check.dataRoot $ops $check.home
            $old.schemaVersion=2;$old.launcher=$shell;$old|Add-Member home $check.home -Force
            $written=Write-LocalInstallReceipt $old $receiptPath $ops
            &$ops.RemoveFile $pending
        }catch{throw ('partial-install-manual-review-required: '+$_.Exception.Message)}
        return [pscustomobject]@{schemaVersion=2;action='apply';status='verified';idempotent=$true;installerRun=$false;installRoot=$check.installRoot;dataRoot=$check.dataRoot;home=$check.home;receipt=$written;postcheck=$post;launcher=$shell;communityRetained=$check.community.present;launchedGui=$false;stoppedProcesses=$false;rollback='Uninstall only the local binaries. Home data rollback is manual; never merge or overwrite profiles.'}
    }
    foreach($shortcut in $check.shortcuts){if($shortcut.value-and$shortcut.value.TargetPath-and-not(Test-LocalPathAtOrWithin $shortcut.value.TargetPath $check.installRoot)){throw 'shortcut-target-outside-local-install'}}
    if($check.sourcePresent){
        $verified=&$ops.InvokeBuild 'Verify' $check.buildRoot $check.registry $PnpmPath
        if(-not$verified-or$verified.status-cne'verified'-or$verified.action-cne'verify'){throw 'existing-build-root-verification-failed'}
    }else{
        $prepared=&$ops.InvokeBuild 'Prepare' $check.buildRoot $check.registry $PnpmPath
        if(-not$prepared-or$prepared.status-cne'complete'-or$prepared.action-cne'prepare'){throw 'fresh-build-root-prepare-failed'}
    }
    $package=&$ops.InvokeBuild 'PackageLocal' $check.buildRoot $check.registry $PnpmPath;$evidence=Assert-LocalPackageReceipt $package $check.buildRoot $check.dataRoot $check.registry $ops $PnpmPath
    Assert-NoLocalReparseTree $artifactDir $ops;Assert-NoLocalReparseTree $snapshotRoot $ops;Assert-NoLocalReparseTree $backupDir $ops;Assert-NoLocalReparseTree $receiptPath $ops;$preservedInstaller=Join-Path $artifactDir ($evidence.installerHash+'-'+(Get-DshOfficialDesktopBuildPolicy).localPackage.installerName);Assert-NoLocalReparseTree $preservedInstaller $ops
    if($old-and(Test-LocalReceiptHash $old)){
        $oldInstaller=ConvertFrom-QuotedLocalPath (Get-LocalLeafValue $old 'installerPath');$oldHash=[string](Get-LocalLeafValue $old 'installerSha256')
        if($oldInstaller-and$oldHash-and(&$ops.PathExists $oldInstaller 'Leaf')-and(&$ops.GetHash $oldInstaller)-ceq$oldHash){$oldArchive=Join-Path (Join-Path $check.dataRoot 'install-backups') ('installer-'+$oldHash+'.exe');&$ops.CopyFile $oldInstaller $oldArchive}
    }
    &$ops.CopyFile $evidence.installerPath $preservedInstaller
    if((&$ops.GetHash $preservedInstaller)-cne$evidence.installerHash-or(&$ops.GetSignature $preservedInstaller)-cne'NotSigned'){throw 'archived-installer-verification-failed'}
    if(&$ops.PathExists $receiptPath 'Leaf'){$backup=Join-Path (Join-Path $check.dataRoot 'install-backups') ('receipt-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ')+'.json');&$ops.CopyFile $receiptPath $backup}
    $beforeCommunity=$check.community
    $installerStarted=$false
    try{
        if((&$ops.GetHash $preservedInstaller)-cne$evidence.installerHash-or(&$ops.GetSignature $preservedInstaller)-cne'NotSigned'){throw 'archived-installer-changed-before-launch'}
        Assert-NoLocalReparseTree $check.installRoot $ops
        if($check.home.mode -eq 'shared' -and @(Get-LocalSharedRuntimeBlockers (&$ops.GetProcesses) $check.home.path $check.installRoot).Count){throw 'shared-home-runtime-running'}
        $installerStarted=$true;$run=&$ops.StartInstaller $preservedInstaller @('/S',('/D='+$check.installRoot));if($null-eq$run-or[int]$run.ExitCode-ne0){throw ('installer-exit-'+$(if($null-eq$run){'missing'}else{$run.ExitCode}))};$post=Assert-InstalledLocalDesktop $check.installRoot $evidence $ops;$afterCommunity=Get-CommunityState @(&$ops.GetUninstallEntries) $check.installRoot $ops;if($beforeCommunity.present-and-not$afterCommunity.present){throw 'community-install-not-retained'};$shell=$null
        $installReceipt=[pscustomobject][ordered]@{schemaVersion=1;status='complete';createdUtc=[DateTime]::UtcNow.ToString('o');source=[pscustomobject]@{repository=$evidence.receipt.source.repository;tag=$evidence.receipt.source.tag;commit=$evidence.receipt.source.commit;tree=$evidence.receipt.source.tree;buildReceiptPath=$evidence.receiptPath;buildReceiptSha256=$evidence.receipt.receiptSha256;buildReceiptFileSha256=$evidence.receiptFileHash};installerPath=$preservedInstaller;installerSha256=$evidence.installerHash;installedExecutablePath=$post.executablePath;installedExecutableSha256=$post.executableHash;installedSeedSha256=$evidence.seedHash;installRoot=$check.installRoot;dataRoot=$check.dataRoot;identity=[pscustomobject]@{productName='DeepSeek Harness';appId='local.cloga.dsh-official-source-build';packageName='dsh-local-build';unsigned=$true;automaticUpdates=$false};launcher=$shell;rollback=[pscustomobject]@{uninstallString=$post.uninstallString;communityRetained=$afterCommunity.present;automaticCoreRollback=$false;note='Community Desktop is the primary rollback path. Data may be forward-migrated; Core/data rollback is manual.'}}
        $pending=Start-LocalHomeTransaction $check $ops
        $check.home.profileBackup=Move-LocalSharedLegacyProfile $check $ops
        $shell=Write-LocalLauncherAndShortcuts $check.installRoot $check.dataRoot $ops $check.home
        $installReceipt.schemaVersion=2;$installReceipt.launcher=$shell;$installReceipt|Add-Member home $check.home
        $written=Write-LocalInstallReceipt $installReceipt $receiptPath $ops;&$ops.RemoveFile $pending;return [pscustomobject]@{schemaVersion=2;action='apply';status='complete';idempotent=$false;installerRun=$true;installRoot=$check.installRoot;dataRoot=$check.dataRoot;home=$check.home;receiptPath=$receiptPath;receipt=$written;postcheck=$post;communityRetained=$afterCommunity.present;launchedGui=$false;stoppedProcesses=$false}
    }catch{if($installerStarted){$ex=[InvalidOperationException]::new(('partial-install-manual-review-required: '+$_.Exception.Message),$_.Exception);throw $ex};throw}
}

Export-ModuleMember -Function Get-DshOfficialDesktopLocalOperations,Assert-DshOfficialDesktopLocalPath,Get-DshOfficialDesktopLocalCheck,Assert-LocalPackageReceipt,Assert-InstalledLocalDesktop,Write-LocalLauncherAndShortcuts,Invoke-DshOfficialDesktopLocalInstall
