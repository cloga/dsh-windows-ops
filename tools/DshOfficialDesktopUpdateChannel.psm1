Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'DshOfficialDesktopBuild.psm1')
Import-Module (Join-Path $PSScriptRoot 'Install-DshOfficialDesktopLocal.psm1')

$script:ChannelOwner = 'cloga/dsh-windows-ops'
$script:ChannelName = 'rc'
$script:ChannelMode = 'unsigned-manual'
$script:ManifestName = 'release.json'
$script:FeedName = 'rc.yml'

function ConvertTo-UpdateCanonicalJson {
    param($Value)
    return ($Value | ConvertTo-Json -Depth 40 -Compress)
}

function Get-UpdatePayloadHash {
    param($Value)
    $fields=@(
        [string]$Value.schemaVersion,[string]$Value.owner,[string]$Value.mode,[string]$Value.channel,
        [string]$Value.channelVersion,[string]$Value.upstreamVersion,[string]$Value.sequence,
        [string]$Value.createdUtc,[string]$Value.feedBaseUrl,[string]$Value.feedFile,
        [string]$Value.installer.file,[string]$Value.installer.size,[string]$Value.installer.sha256,
        [string]$Value.installer.sha512,[string]$Value.installer.signature,
        [string]$Value.buildReceipt.file,[string]$Value.buildReceipt.sha256,[string]$Value.buildReceipt.receiptSha256,
        [string]$Value.installedEvidence.executableSha256,[string]$Value.installedEvidence.seedSha256,
        ([string][bool]$Value.security.nativeUpdaterEnabled).ToLowerInvariant(),
        ([string][bool]$Value.security.appUpdateYmlPresent).ToLowerInvariant(),
        ([string][bool]$Value.security.signatureRequiredForNativeUpdater).ToLowerInvariant(),
        [string]$Value.security.applyMode,[string]$Value.security.publication
    )
    $payload=($fields|ForEach-Object{([Text.Encoding]::UTF8.GetByteCount($_)).ToString([Globalization.CultureInfo]::InvariantCulture)+':'+$_})-join"`n"
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($payload)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-FileSha512Base64 {
    param([Parameter(Mandatory)][string]$Path)
    $stream = [IO.File]::OpenRead($Path)
    $sha = [Security.Cryptography.SHA512]::Create()
    try { return [Convert]::ToBase64String($sha.ComputeHash($stream)) }
    finally { $sha.Dispose(); $stream.Dispose() }
}

function Assert-UpdateFeedBaseUrl {
    param([Parameter(Mandatory)][string]$FeedBaseUrl)
    try { $uri = [Uri]$FeedBaseUrl } catch { throw 'update-feed-base-url-invalid' }
    if (-not $uri.IsAbsoluteUri -or $uri.Scheme -cne 'https' -or -not [string]::IsNullOrEmpty($uri.UserInfo) -or
        -not [string]::IsNullOrEmpty($uri.Query) -or -not [string]::IsNullOrEmpty($uri.Fragment)) {
        throw 'update-feed-base-url-must-be-credential-free-https'
    }
    return $uri.AbsoluteUri.TrimEnd('/') + '/'
}

function Get-DshOfficialDesktopLocalChannelVersion {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateRange(1, 2147483647)][int]$Sequence)
    return "$(Get-DshOfficialDesktopBuildPolicy | Select-Object -ExpandProperty version).local.$Sequence"
}

function Test-ExactUpdateKeys {
    param($Object, [string[]]$Names)
    if ($null -eq $Object) { return $false }
    return (ConvertTo-UpdateCanonicalJson @($Object.PSObject.Properties.Name | Sort-Object)) -ceq
        (ConvertTo-UpdateCanonicalJson @($Names | Sort-Object))
}

function Get-DshOfficialDesktopUpdateChannelOperations {
    [CmdletBinding()]
    param()
    return @{
        InvokeBuild = {
            param($root, $registry, $pnpmPath)
            Invoke-DshOfficialDesktopBuild -Action PackageLocal -BuildRoot $root -Registry $registry -PnpmPath $pnpmPath
        }
        ValidateBuildReceipt = {
            param($path, $sourceRoot, $pnpmPath, $recordedOnly)
            Test-DshOfficialDesktopBuildReceipt -Path $path -SourceRoot $sourceRoot -PnpmPath $pnpmPath -RecordedEvidenceOnly:$recordedOnly
        }
        GetHash = { param($path) (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
        GetSignature = { param($path) (Get-AuthenticodeSignature -LiteralPath $path).Status.ToString() }
        GetLength = { param($path) (Get-Item -LiteralPath $path).Length }
        ReadJson = { param($path) Get-Content -LiteralPath $path -Raw | ConvertFrom-Json }
        WriteText = {
            param($path, $text)
            $parent = Split-Path -Parent $path
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
        }
        CopyFile = {
            param($source, $destination)
            $parent = Split-Path -Parent $destination
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }
        PathExists = { param($path, $type) if ($type -eq 'Leaf') { Test-Path -LiteralPath $path -PathType Leaf } elseif ($type -eq 'Container') { Test-Path -LiteralPath $path -PathType Container } else { Test-Path -LiteralPath $path } }
        MoveDirectory = { param($source, $destination) [IO.Directory]::Move($source, $destination) }
        RemoveDirectory = { param($path) Remove-Item -LiteralPath $path -Recurse -Force }
        UtcNow = { [DateTime]::UtcNow }
    }
}

function Merge-UpdateOperations {
    param([hashtable]$Operations)
    $all = Get-DshOfficialDesktopUpdateChannelOperations
    if ($Operations) { foreach ($key in $Operations.Keys) { $all[$key] = $Operations[$key] } }
    return $all
}

function New-DshOfficialDesktopUpdateBundle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateRange(1, 2147483647)][int]$Sequence,
        [Parameter(Mandatory)][string]$FeedBaseUrl,
        [string]$BuildRoot = 'C:\tmp\dsh-official-desktop-build\work',
        [string]$Registry = 'https://registry.npmjs.org/',
        [string]$PnpmPath,
        [hashtable]$Operations
    )
    $ops = Merge-UpdateOperations $Operations
    $feed = Assert-UpdateFeedBaseUrl $FeedBaseUrl
    $package = &$ops.InvokeBuild $BuildRoot $Registry $PnpmPath
    if (-not $package -or $package.status -cne 'complete' -or $package.action -cne 'packagelocal') { throw 'update-package-result-invalid' }
    if (-not (&$ops.ValidateBuildReceipt $package.receiptPath $package.sourceRoot $PnpmPath $false)) { throw 'update-build-receipt-invalid' }
    $receipt = &$ops.ReadJson $package.receiptPath
    if ($receipt.releaseBoundary.officialSignature -ne $false -or $receipt.releaseBoundary.updateChannel -ne $false -or
        $receipt.localPackage.appUpdatePresent -ne $false) { throw 'update-package-security-boundary-invalid' }
    $sourceInstaller = [IO.Path]::GetFullPath([string]$receipt.localPackage.installerPath)
    if (-not (&$ops.PathExists $sourceInstaller 'Leaf')) { throw 'update-installer-missing' }
    if ((&$ops.GetHash $sourceInstaller) -cne [string]$receipt.localPackage.hashes.installer) { throw 'update-installer-hash-mismatch' }
    if ((&$ops.GetSignature $sourceInstaller) -cne 'NotSigned') { throw 'update-installer-must-be-unsigned' }

    $channelVersion = Get-DshOfficialDesktopLocalChannelVersion $Sequence
    $bundleRoot = Join-Path $BuildRoot "update-channel\$channelVersion"
    if (&$ops.PathExists $bundleRoot 'Container') { throw 'update-bundle-already-exists' }
    $tempRoot = $bundleRoot + '.tmp-' + [guid]::NewGuid().ToString('N')
    $installerName = "dsh-local-build-$channelVersion-win-x64.exe"
    $installerPath = Join-Path $tempRoot $installerName
    $buildReceiptPath = Join-Path $tempRoot 'build-receipt.json'
    try {
        &$ops.CopyFile $sourceInstaller $installerPath
        &$ops.CopyFile $package.receiptPath $buildReceiptPath
        $installerSha256 = &$ops.GetHash $installerPath
        $installerSha512 = Get-FileSha512Base64 $installerPath
        $installerSize = [long](&$ops.GetLength $installerPath)
        if ($installerSha256 -cne [string]$receipt.localPackage.hashes.installer) { throw 'update-bundle-copy-hash-mismatch' }
        $releaseDate = (&$ops.UtcNow).ToString('o')
        $feedText = @(
            "version: $channelVersion"
            'files:'
            "  - url: $installerName"
            "    sha512: $installerSha512"
            "    size: $installerSize"
            "path: $installerName"
            "sha512: $installerSha512"
            "releaseDate: '$releaseDate'"
            ''
        ) -join "`n"
        &$ops.WriteText (Join-Path $tempRoot $script:FeedName) $feedText
        $manifest = [pscustomobject][ordered]@{
            schemaVersion = 1
            owner = $script:ChannelOwner
            mode = $script:ChannelMode
            channel = $script:ChannelName
            channelVersion = $channelVersion
            upstreamVersion = [string](Get-DshOfficialDesktopBuildPolicy).version
            sequence = $Sequence
            createdUtc = $releaseDate
            feedBaseUrl = $feed
            feedFile = $script:FeedName
            installer = [pscustomobject][ordered]@{
                file = $installerName
                size = $installerSize
                sha256 = $installerSha256
                sha512 = $installerSha512
                signature = 'NotSigned'
            }
            buildReceipt = [pscustomobject][ordered]@{
                file = 'build-receipt.json'
                sha256 = &$ops.GetHash $buildReceiptPath
                receiptSha256 = [string]$receipt.receiptSha256
            }
            installedEvidence = [pscustomobject][ordered]@{
                executableSha256 = [string]$receipt.localPackage.hashes.executable
                seedSha256 = [string]$receipt.localPackage.hashes.seed
            }
            security = [pscustomobject][ordered]@{
                nativeUpdaterEnabled = $false
                appUpdateYmlPresent = $false
                signatureRequiredForNativeUpdater = $true
                applyMode = 'manual'
                publication = 'immutable-github-release-or-approved-static-feed'
            }
        }
        $manifest=$manifest|ConvertTo-Json -Depth 20|ConvertFrom-Json
        $manifest | Add-Member manifestSha256 (Get-UpdatePayloadHash $manifest)
        &$ops.WriteText (Join-Path $tempRoot $script:ManifestName) ($manifest | ConvertTo-Json -Depth 20)
        &$ops.MoveDirectory $tempRoot $bundleRoot
    } catch {
        if (&$ops.PathExists $tempRoot 'Container') { &$ops.RemoveDirectory $tempRoot }
        throw
    }
    $verified = Test-DshOfficialDesktopUpdateBundle -BundleRoot $bundleRoot -Operations $ops
    if (-not $verified.valid) { throw "update-bundle-self-verification-failed:$($verified.reason)" }
    return [pscustomobject]@{
        schemaVersion = 1
        action = 'package'
        status = 'complete'
        bundleRoot = $bundleRoot
        manifestPath = Join-Path $bundleRoot $script:ManifestName
        manifestSha256 = $verified.manifest.manifestSha256
        channelVersion = $channelVersion
        publicationPerformed = $false
        nativeUpdaterEnabled = $false
    }
}

function Test-DshOfficialDesktopUpdateBundle {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$BundleRoot, [hashtable]$Operations)
    $ops = Merge-UpdateOperations $Operations
    try {
        $root = [IO.Path]::GetFullPath($BundleRoot)
        $manifestPath = Join-Path $root $script:ManifestName
        if (-not (&$ops.PathExists $manifestPath 'Leaf')) { throw 'manifest-missing' }
        $manifest = &$ops.ReadJson $manifestPath
        if (-not (Test-ExactUpdateKeys $manifest @('schemaVersion','owner','mode','channel','channelVersion','upstreamVersion','sequence','createdUtc','feedBaseUrl','feedFile','installer','buildReceipt','installedEvidence','security','manifestSha256'))) { throw 'manifest-schema' }
        if ((Get-UpdatePayloadHash $manifest) -cne [string]$manifest.manifestSha256) { throw 'manifest-self-hash' }
        if ($manifest.schemaVersion -ne 1 -or $manifest.owner -cne $script:ChannelOwner -or $manifest.mode -cne $script:ChannelMode -or
            $manifest.channel -cne $script:ChannelName -or [int]$manifest.sequence -lt 1 -or
            $manifest.channelVersion -cne (Get-DshOfficialDesktopLocalChannelVersion ([int]$manifest.sequence)) -or
            $manifest.upstreamVersion -cne [string](Get-DshOfficialDesktopBuildPolicy).version) { throw 'manifest-identity' }
        $null = Assert-UpdateFeedBaseUrl ([string]$manifest.feedBaseUrl)
        if ($manifest.feedFile -cne $script:FeedName -or $manifest.security.nativeUpdaterEnabled -ne $false -or
            $manifest.security.appUpdateYmlPresent -ne $false -or $manifest.security.signatureRequiredForNativeUpdater -ne $true -or
            $manifest.security.applyMode -cne 'manual') { throw 'manifest-security' }
        foreach ($hash in @($manifest.installer.sha256,$manifest.buildReceipt.sha256,$manifest.buildReceipt.receiptSha256,$manifest.installedEvidence.executableSha256,$manifest.installedEvidence.seedSha256)) {
            if ([string]$hash -cnotmatch '^[0-9a-f]{64}$') { throw 'manifest-hash-shape' }
        }
        if ([string]$manifest.installer.sha512 -cnotmatch '^[A-Za-z0-9+/]{86}==$') { throw 'manifest-sha512-shape' }
        $installerPath = Join-Path $root ([string]$manifest.installer.file)
        $buildReceiptPath = Join-Path $root ([string]$manifest.buildReceipt.file)
        $feedPath = Join-Path $root ([string]$manifest.feedFile)
        foreach ($path in @($installerPath,$buildReceiptPath,$feedPath)) {
            if (-not (&$ops.PathExists $path 'Leaf')) { throw 'bundle-file-missing' }
            if (-not ([IO.Path]::GetFullPath($path).StartsWith($root + '\',[StringComparison]::OrdinalIgnoreCase))) { throw 'bundle-file-outside-root' }
        }
        if ((&$ops.GetHash $installerPath) -cne [string]$manifest.installer.sha256 -or
            (Get-FileSha512Base64 $installerPath) -cne [string]$manifest.installer.sha512 -or
            [long](&$ops.GetLength $installerPath) -ne [long]$manifest.installer.size -or
            (&$ops.GetSignature $installerPath) -cne 'NotSigned') { throw 'installer-evidence' }
        if ((&$ops.GetHash $buildReceiptPath) -cne [string]$manifest.buildReceipt.sha256) { throw 'build-receipt-file-hash' }
        $buildReceipt = &$ops.ReadJson $buildReceiptPath
        $recordedExecutable=[IO.Path]::GetFullPath([string]$buildReceipt.localPackage.executablePath)
        $recordedSuffix='\apps\desktop\.desktop-build\targets\win-x64\artifacts\win-unpacked\DeepSeek Harness.exe'
        if(-not$recordedExecutable.EndsWith($recordedSuffix,[StringComparison]::OrdinalIgnoreCase)){throw 'build-receipt-recorded-source-path'}
        $recordedSourceRoot=$recordedExecutable.Substring(0,$recordedExecutable.Length-$recordedSuffix.Length)
        if ([string]$buildReceipt.receiptSha256 -cne [string]$manifest.buildReceipt.receiptSha256 -or
            -not (&$ops.ValidateBuildReceipt $buildReceiptPath $recordedSourceRoot $null $true)) { throw 'build-receipt-invalid' }
        if ($buildReceipt.localPackage.hashes.installer -cne $manifest.installer.sha256 -or
            $buildReceipt.localPackage.hashes.executable -cne $manifest.installedEvidence.executableSha256 -or
            $buildReceipt.localPackage.hashes.seed -cne $manifest.installedEvidence.seedSha256 -or
            $buildReceipt.localPackage.appUpdatePresent -ne $false) { throw 'build-receipt-evidence-mismatch' }
        return [pscustomobject]@{valid=$true;reason=$null;manifest=$manifest;manifestPath=$manifestPath;installerPath=$installerPath;buildReceiptPath=$buildReceiptPath;feedPath=$feedPath}
    } catch {
        return [pscustomobject]@{valid=$false;reason=$_.Exception.Message;manifest=$null}
    }
}

function Get-DshOfficialDesktopUpdateChannelCheck {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$BundleRoot, [string]$DataRoot=(Join-Path $env:LOCALAPPDATA 'DSH Local Build'), [hashtable]$Operations)
    $ops = Merge-UpdateOperations $Operations
    $DataRoot=Assert-DshOfficialDesktopLocalPath $DataRoot 'data-root' (Get-DshOfficialDesktopLocalOperations)
    $bundle = Test-DshOfficialDesktopUpdateBundle -BundleRoot $BundleRoot -Operations $ops
    if (-not $bundle.valid) { return [pscustomobject]@{schemaVersion=1;action='check';status='blocked';reasons=@($bundle.reason);updateAvailable=$false;mutated=$false} }
    $receiptPath = Join-Path $DataRoot 'official-desktop-local-install.json'
    $installedSequence = 0
    if (&$ops.PathExists $receiptPath 'Leaf') {
        try {
            $receipt = &$ops.ReadJson $receiptPath
            if ($receipt.schemaVersion -eq 3 -and $receipt.updateChannel.owner -ceq $script:ChannelOwner) { $installedSequence = [int]$receipt.updateChannel.sequence }
        } catch { return [pscustomobject]@{schemaVersion=1;action='check';status='blocked';reasons=@('install-receipt-unreadable');updateAvailable=$false;mutated=$false} }
    }
    return [pscustomobject]@{
        schemaVersion=1;action='check';status='ready';reasons=@()
        updateAvailable=([int]$bundle.manifest.sequence -gt $installedSequence)
        installedSequence=$installedSequence;availableSequence=[int]$bundle.manifest.sequence
        channelVersion=$bundle.manifest.channelVersion;manifestSha256=$bundle.manifest.manifestSha256
        nativeUpdaterEnabled=$false;applyMode='manual';mutated=$false
    }
}

function Save-DshOfficialDesktopStagedUpdate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BundleRoot,
        [Parameter(Mandatory)][string]$AcknowledgeManifestSha256,
        [string]$DataRoot=(Join-Path $env:LOCALAPPDATA 'DSH Local Build'),
        [hashtable]$Operations
    )
    $ops = Merge-UpdateOperations $Operations
    $DataRoot=Assert-DshOfficialDesktopLocalPath $DataRoot 'data-root' (Get-DshOfficialDesktopLocalOperations)
    $bundle = Test-DshOfficialDesktopUpdateBundle -BundleRoot $BundleRoot -Operations $ops
    if (-not $bundle.valid) { throw "update-bundle-invalid:$($bundle.reason)" }
    $expected = 'sha256:' + [string]$bundle.manifest.manifestSha256
    if ($AcknowledgeManifestSha256.ToLowerInvariant() -cne $expected) { throw 'update-manifest-acknowledgment-required' }
    $stageRoot = Join-Path $DataRoot ('updates\staged\' + [string]$bundle.manifest.channelVersion)
    if (&$ops.PathExists $stageRoot 'Container') {
        $existing = Test-DshOfficialDesktopUpdateBundle -BundleRoot $stageRoot -Operations $ops
        if ($existing.valid -and $existing.manifest.manifestSha256 -ceq $bundle.manifest.manifestSha256) {
            return [pscustomobject]@{schemaVersion=1;action='stage';status='verified';idempotent=$true;stageRoot=$stageRoot;installerPath=$existing.installerPath;completeAfterManualInstall=$true}
        }
        throw 'update-stage-conflict'
    }
    $temp = $stageRoot + '.tmp-' + [guid]::NewGuid().ToString('N')
    try {
        foreach ($name in @($script:ManifestName,$script:FeedName,[string]$bundle.manifest.installer.file,[string]$bundle.manifest.buildReceipt.file)) {
            &$ops.CopyFile (Join-Path $BundleRoot $name) (Join-Path $temp $name)
        }
        $staged = Test-DshOfficialDesktopUpdateBundle -BundleRoot $temp -Operations $ops
        if (-not $staged.valid -or $staged.manifest.manifestSha256 -cne $bundle.manifest.manifestSha256) { throw 'update-stage-verification-failed' }
        &$ops.MoveDirectory $temp $stageRoot
    } catch {
        if (&$ops.PathExists $temp 'Container') { &$ops.RemoveDirectory $temp }
        throw
    }
    $result = Test-DshOfficialDesktopUpdateBundle -BundleRoot $stageRoot -Operations $ops
    return [pscustomobject]@{schemaVersion=1;action='stage';status='complete';idempotent=$false;stageRoot=$stageRoot;installerPath=$result.installerPath;manifestSha256=$result.manifest.manifestSha256;completeAfterManualInstall=$true;nativeUpdaterEnabled=$false}
}

function Complete-DshOfficialDesktopManualUpdate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StageRoot,
        [Parameter(Mandatory)][string]$AcknowledgeManifestSha256,
        [string]$BuildRoot='C:\tmp\dsh-official-desktop-build\work',
        [string]$InstallRoot=(Join-Path $env:LOCALAPPDATA 'Programs\DSH Local Build'),
        [string]$DataRoot=(Join-Path $env:LOCALAPPDATA 'DSH Local Build'),
        [string]$SharedHome,
        [switch]$UseIsolatedHome,
        [string]$PnpmPath,
        [hashtable]$Operations,
        [hashtable]$InstallOperations
    )
    $ops = Merge-UpdateOperations $Operations
    $bundle = Test-DshOfficialDesktopUpdateBundle -BundleRoot $StageRoot -Operations $ops
    if (-not $bundle.valid) { throw "update-stage-invalid:$($bundle.reason)" }
    if ($AcknowledgeManifestSha256.ToLowerInvariant() -cne ('sha256:' + [string]$bundle.manifest.manifestSha256)) { throw 'update-manifest-acknowledgment-required' }
    $installOps = if ($InstallOperations) { $InstallOperations } else { Get-DshOfficialDesktopLocalOperations }
    $check = Get-DshOfficialDesktopLocalCheck -BuildRoot $BuildRoot -InstallRoot $InstallRoot -DataRoot $DataRoot -PnpmPath $PnpmPath -Operations $installOps -SharedHome $SharedHome -UseIsolatedHome:$UseIsolatedHome
    $allowedPostInstallReasons=@('installed-executable-hash-mismatch')
    $unexpectedReasons=@($check.reasons|Where-Object{$_ -notin $allowedPostInstallReasons})
    if ($check.status -ne 'ready' -and $unexpectedReasons.Count) { throw ('update-install-check-blocked:' + ($check.reasons -join ',')) }
    if ($check.processEnumerationUnavailable -or @($check.runningLocalProcesses).Count) { throw 'update-local-process-running-or-unavailable' }
    $evidence = [pscustomobject]@{executableHash=[string]$bundle.manifest.installedEvidence.executableSha256;seedHash=[string]$bundle.manifest.installedEvidence.seedSha256}
    $post = Assert-InstalledLocalDesktop $check.installRoot $evidence $installOps
    $receiptPath = Join-Path $check.dataRoot 'official-desktop-local-install.json'
    if (-not (&$installOps.PathExists $receiptPath 'Leaf')) { throw 'update-install-receipt-missing' }
    $old = &$installOps.ReadJson $receiptPath
    if (-not (Test-TrustedLocalInstallReceipt $old $check.buildRoot $check.installRoot $check.dataRoot $installOps $PnpmPath -AllowInstalledExecutableMismatch)) { throw 'update-existing-install-receipt-untrusted' }
    $artifactRoot = Join-Path $check.dataRoot 'artifacts'
    $archivedInstaller = Join-Path $artifactRoot (([string]$bundle.manifest.installer.sha256) + '-' + [string]$bundle.manifest.installer.file)
    $archivedBuildReceipt = Join-Path (Join-Path $artifactRoot 'build-receipts') (([string]$bundle.manifest.buildReceipt.sha256) + '.json')
    &$installOps.CopyFile $bundle.installerPath $archivedInstaller
    &$installOps.CopyFile $bundle.buildReceiptPath $archivedBuildReceipt
    if ((&$installOps.GetHash $archivedInstaller) -cne [string]$bundle.manifest.installer.sha256 -or
        (&$installOps.GetSignature $archivedInstaller) -cne 'NotSigned' -or
        (&$installOps.GetHash $archivedBuildReceipt) -cne [string]$bundle.manifest.buildReceipt.sha256) { throw 'update-archive-verification-failed' }
    $manifestArchive = Join-Path (Join-Path $check.dataRoot 'updates\manifests') (([string]$bundle.manifest.manifestSha256) + '.json')
    &$installOps.CopyFile $bundle.manifestPath $manifestArchive
    if ((&$installOps.GetHash $manifestArchive) -cne (&$installOps.GetHash $bundle.manifestPath)) { throw 'update-manifest-archive-verification-failed' }
    $shell = Write-LocalLauncherAndShortcuts $check.installRoot $check.dataRoot $installOps $check.home $bundle.manifest
    $old.schemaVersion = 3
    $old.createdUtc = (&$ops.UtcNow).ToString('o')
    $old.source.buildReceiptPath = $archivedBuildReceipt
    $old.source.buildReceiptSha256 = [string]$bundle.manifest.buildReceipt.receiptSha256
    $old.source.buildReceiptFileSha256 = [string]$bundle.manifest.buildReceipt.sha256
    $old.installerPath = $archivedInstaller
    $old.installerSha256 = [string]$bundle.manifest.installer.sha256
    $old.installedExecutableSha256 = [string]$bundle.manifest.installedEvidence.executableSha256
    $old.installedSeedSha256 = [string]$bundle.manifest.installedEvidence.seedSha256
    $old.launcher = $shell
    $old | Add-Member updateChannel ([pscustomobject][ordered]@{
        mode=$script:ChannelMode;owner=$script:ChannelOwner;channel=$script:ChannelName
        channelVersion=[string]$bundle.manifest.channelVersion;sequence=[int]$bundle.manifest.sequence
        manifestPath=$manifestArchive;manifestSha256=[string]$bundle.manifest.manifestSha256
        feedBaseUrl=[string]$bundle.manifest.feedBaseUrl;nativeUpdaterEnabled=$false
        signatureRequiredForNativeUpdater=$true;completedUtc=(&$ops.UtcNow).ToString('o')
    }) -Force
    $old.PSObject.Properties.Remove('receiptSha256')
    $written = Write-LocalInstallReceipt $old $receiptPath $installOps
    if (-not (Test-TrustedLocalInstallReceipt $written $check.buildRoot $check.installRoot $check.dataRoot $installOps $PnpmPath)) { throw 'update-completed-receipt-invalid' }
    return [pscustomobject]@{schemaVersion=1;action='complete';status='complete';channelVersion=$bundle.manifest.channelVersion;sequence=$bundle.manifest.sequence;receipt=$written;postcheck=$post;nativeUpdaterEnabled=$false;installerRun=$false}
}

Export-ModuleMember -Function Get-DshOfficialDesktopLocalChannelVersion,Get-DshOfficialDesktopUpdateChannelOperations,New-DshOfficialDesktopUpdateBundle,Test-DshOfficialDesktopUpdateBundle,Get-DshOfficialDesktopUpdateChannelCheck,Save-DshOfficialDesktopStagedUpdate,Complete-DshOfficialDesktopManualUpdate
