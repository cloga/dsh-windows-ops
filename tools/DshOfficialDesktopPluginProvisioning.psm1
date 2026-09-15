Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:DefaultLockPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'deployments\windows-copilot.lock.json'
$script:ReceiptName = 'official-desktop-plugin-provisioning.json'
$script:LifecycleHooks = @('preinstall', 'install', 'postinstall', 'prepare')
$script:BuiltInBundles = @('@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app')
$script:ConflictingBundles = @(
    '@deepseek-ai/dsh-acp-app',
    '@deepseek-ai/dsh-headless',
    '@deepseek-ai/dsh-sdk-app',
    '@deepseek-ai/dsh-sdk-minimal'
)

function ConvertTo-PluginCanonicalJson {
    param($Value)
    return ($Value | ConvertTo-Json -Depth 50 -Compress)
}

function Get-PluginNormalizedPath {
    param([Parameter(Mandatory)][string]$Path)
    return [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

function Test-PluginPathAtOrWithin {
    param([Parameter(Mandatory)][string]$Candidate, [Parameter(Mandatory)][string]$Parent)
    $child = Get-PluginNormalizedPath $Candidate
    $root = Get-PluginNormalizedPath $Parent
    return $child.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or
        ($child + '\').StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Get-PluginLeafValue {
    param($Object, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Object) { return $null }
    $property = @($Object.PSObject.Properties | Where-Object Name -CEQ $Name | Select-Object -First 1)
    if ($property.Count) { return $property[0].Value }
    return $null
}

function Test-PluginExactKeys {
    param($Object, [string[]]$Names)
    if ($null -eq $Object) { return $false }
    return (ConvertTo-PluginCanonicalJson @($Object.PSObject.Properties.Name | Sort-Object)) -ceq
        (ConvertTo-PluginCanonicalJson @($Names | Sort-Object))
}

function Assert-PluginOwnedPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][hashtable]$Operations
    )
    if ([string]::IsNullOrWhiteSpace($Path) -or -not [IO.Path]::IsPathRooted($Path) -or
        $Path.StartsWith('\\') -or $Path.StartsWith('//') -or $Path -match '[\r\n"&|<>^%!`]') {
        throw "$Name-invalid"
    }
    $resolved = Get-PluginNormalizedPath $Path
    foreach ($cloud in @($env:OneDrive, $env:OneDriveCommercial, $env:OneDriveConsumer, $env:Dropbox, $env:GoogleDrive)) {
        if ($cloud -and [IO.Path]::IsPathRooted($cloud) -and (Test-PluginPathAtOrWithin $resolved $cloud)) {
            throw "$Name-cloud-synchronized"
        }
    }
    if ($resolved -match '(?i)(^|[\\/])(OneDrive(?: - [^\\/]+)?|Dropbox|Google Drive|iCloudDrive)([\\/]|$)') {
        throw "$Name-cloud-synchronized"
    }
    $cursor = $resolved
    while ($cursor) {
        if (&$Operations.TestReparse $cursor) { throw "$Name-reparse-point" }
        $parent = Split-Path -Parent $cursor
        if (-not $parent -or $parent -ceq $cursor) { break }
        $cursor = $parent
    }
    return $resolved
}

function Get-DshOfficialDesktopPluginContract {
    [CmdletBinding()]
    param([string]$LockPath = $script:DefaultLockPath)

    if (-not (Test-Path -LiteralPath $LockPath -PathType Leaf)) { throw 'desktop-plugin-lock-missing' }
    $lock = Get-Content -LiteralPath $LockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $component = $lock.components.copilotIntegration
    $contract = $component.desktopProvisioning
    $package = $component.package
    $artifact = $package.artifact
    if (-not (Test-PluginExactKeys $contract @(
        'schemaVersion', 'mode', 'adapter', 'registry', 'allowedRedirectHosts',
        'nativeCapability', 'removal'
    ))) { throw 'desktop-plugin-contract-shape-invalid' }
    if ([int]$contract.schemaVersion -ne 1 -or
        [string]$contract.mode -notin @('windowsOpsVerifiedRelease', 'desktopNativeVerifiedRelease') -or
        [string]$contract.adapter -cne 'DshOfficialDesktopPluginProvisioning.psm1') {
        throw 'desktop-plugin-contract-invalid'
    }
    if ([string]$contract.mode -ceq 'desktopNativeVerifiedRelease') {
        if ($null -ne $contract.registry) { throw 'desktop-plugin-registry-invalid' }
    } elseif ([string]$contract.registry -cne 'https://packagefeedproxy.microsoft.io/npm/') {
        throw 'desktop-plugin-registry-invalid'
    }
    $hosts = @($contract.allowedRedirectHosts)
    $requiredHosts = if ([string]$contract.mode -ceq 'desktopNativeVerifiedRelease') {
        @('github.com', 'objects.githubusercontent.com', 'release-assets.githubusercontent.com')
    } else {
        @('github.com', 'release-assets.githubusercontent.com')
    }
    if ($hosts.Count -ne $requiredHosts.Count -or
        @($requiredHosts | Where-Object { $hosts -notcontains $_ }).Count -gt 0) {
        throw 'desktop-plugin-redirect-hosts-invalid'
    }
    if ([string]$package.name -cne 'dsh-github-copilot' -or
        [string]$package.version -cnotmatch '^[0-9]+\.[0-9]+\.[0-9]+-[0-9A-Za-z.-]+$' -or
        [string]$artifact.name -cne "$($package.name)-$($package.version).tgz" -or
        [string]$artifact.releaseTag -cne "v$($package.version)" -or
        [string]$artifact.url -cne
            "https://github.com/cloga/dsh-github-copilot/releases/download/v$($package.version)/$($artifact.name)" -or
        [string]$artifact.releaseCommit -cnotmatch '^[0-9a-f]{40}$' -or
        $artifact.releaseImmutable -ne $true -or
        [long]$artifact.size -lt 1 -or
        [string]$artifact.sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$artifact.sha512 -cnotmatch '^[0-9a-f]{128}$' -or
        [string]$artifact.integrity -cnotmatch '^sha512-[A-Za-z0-9+/]+={0,2}$') {
        throw 'desktop-plugin-artifact-contract-invalid'
    }
    $checksum = $artifact.checksumManifest
    if ([string]$checksum.name -cne 'SHA256SUMS' -or
        [string]$checksum.url -cne
            "https://github.com/cloga/dsh-github-copilot/releases/download/v$($package.version)/SHA256SUMS" -or
        [string]$checksum.sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        [long]$checksum.size -lt 1) {
        throw 'desktop-plugin-checksum-manifest-contract-invalid'
    }
    $sriBytes = [Convert]::FromBase64String(([string]$artifact.integrity).Substring(7))
    $sriHex = ([BitConverter]::ToString($sriBytes)).Replace('-', '').ToLowerInvariant()
    if ($sriHex -cne [string]$artifact.sha512) { throw 'desktop-plugin-sri-sha512-mismatch' }
    if ([string]$component.source.repository -cne 'https://github.com/cloga/dsh-github-copilot' -or
        [string]$component.source.commit -cne [string]$artifact.releaseCommit) {
        throw 'desktop-plugin-source-release-mismatch'
    }
    if ($contract.mode -ceq 'desktopNativeVerifiedRelease') {
        $native = $contract.nativeCapability
        if ($native.verified -ne $true -or
            [string]$native.coreCommit -cnotmatch '^[0-9a-f]{40}$' -or
            [string]$native.desktopCommit -cnotmatch '^[0-9a-f]{40}$' -or
            [string]$native.fixture -cnotmatch '\.json$' -or
            -not (Test-Path -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) ([string]$native.fixture)) -PathType Leaf)) {
            throw 'desktop-native-provisioning-capability-unverified'
        }
    } elseif ($contract.nativeCapability.verified -eq $true) {
        throw 'desktop-plugin-native-capability-mode-mismatch'
    }
    return [pscustomobject]@{
        schemaVersion = [int]$contract.schemaVersion
        mode = [string]$contract.mode
        adapter = [string]$contract.adapter
        registry = if ($null -eq $contract.registry) { $null } else { [string]$contract.registry }
        allowedRedirectHosts = @($hosts)
        nativeCapability = $contract.nativeCapability
        removal = $contract.removal
        source = $component.source
        package = $package
        artifact = $artifact
        lockPath = Get-PluginNormalizedPath $LockPath
    }
}

function Get-DshOfficialDesktopPluginRecipe {
    [CmdletBinding()]
    param([string]$LockPath = $script:DefaultLockPath)
    $contract = Get-DshOfficialDesktopPluginContract -LockPath $LockPath
    return [pscustomobject][ordered]@{
        schemaVersion = $contract.schemaVersion
        mode = $contract.mode
        adapter = $contract.adapter
        registry = $contract.registry
        allowedRedirectHosts = @($contract.allowedRedirectHosts)
        source = $contract.source
        package = $contract.package
        nativeCapability = $contract.nativeCapability
    }
}

function Get-DshOfficialDesktopPluginOperations {
    [CmdletBinding()]
    param()
    return @{
        PathExists = {
            param($path, $type)
            if ($type -ceq 'Leaf') { Test-Path -LiteralPath $path -PathType Leaf }
            elseif ($type -ceq 'Container') { Test-Path -LiteralPath $path -PathType Container }
            else { Test-Path -LiteralPath $path }
        }
        TestReparse = {
            param($path)
            if (-not (Test-Path -LiteralPath $path)) { return $false }
            return [bool]((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)
        }
        IsCurrentUserOwner = {
            param($path)
            (Get-Acl -LiteralPath $path).GetOwner([Security.Principal.SecurityIdentifier]).Value -ceq
                [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        }
        ReadJson = { param($path) Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json }
        WriteJsonAtomic = {
            param($path, $value)
            $parent = Split-Path -Parent $path
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            $temp = $path + '.tmp-' + [guid]::NewGuid().ToString('N')
            [IO.File]::WriteAllText($temp, (($value | ConvertTo-Json -Depth 50) + "`n"), [Text.UTF8Encoding]::new($false))
            Move-Item -LiteralPath $temp -Destination $path -Force
        }
        GetHash = { param($path, $algorithm) (Get-FileHash -LiteralPath $path -Algorithm $algorithm).Hash.ToLowerInvariant() }
        GetLength = { param($path) (Get-Item -LiteralPath $path).Length }
        CreateDirectory = { param($path) New-Item -ItemType Directory -Path $path -Force | Out-Null }
        CopyFile = {
            param($source, $destination)
            $parent = Split-Path -Parent $destination
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }
        CopyDirectory = {
            param($source, $destination)
            Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force
        }
        MoveDirectory = { param($source, $destination) [IO.Directory]::Move($source, $destination) }
        MoveFile = { param($source, $destination) [IO.File]::Move($source, $destination) }
        RemoveDirectory = { param($path) if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force } }
        RemoveFile = { param($path) if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force } }
        GetChildren = { param($path) @(Get-ChildItem -LiteralPath $path -Force) }
        GetProcesses = {
            try {
                [pscustomobject]@{
                    unavailable = $false
                    items = @(Get-CimInstance Win32_Process -ErrorAction Stop | ForEach-Object {
                        [pscustomobject]@{
                            Id = $_.ProcessId
                            Name = $_.Name
                            ExecutablePath = $_.ExecutablePath
                            CommandLine = $_.CommandLine
                        }
                    })
                }
            } catch {
                [pscustomobject]@{ unavailable = $true; items = @() }
            }
        }
        Download = {
            param($url, $destination, $allowedHosts)
            if (-not ('System.Net.Http.HttpClientHandler' -as [type])) {
                Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
            }
            $handler = [Net.Http.HttpClientHandler]::new()
            $handler.AllowAutoRedirect = $false
            $client = [Net.Http.HttpClient]::new($handler)
            try {
                $current = [Uri]$url
                for ($redirects = 0; $redirects -le 5; $redirects++) {
                    if ($current.Scheme -cne 'https' -or $allowedHosts -notcontains $current.Host.ToLowerInvariant()) {
                        throw 'desktop-plugin-download-host-not-allowed'
                    }
                    $response = $client.GetAsync($current, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
                    if ([int]$response.StatusCode -in @(301, 302, 303, 307, 308)) {
                        if ($null -eq $response.Headers.Location) { throw 'desktop-plugin-download-redirect-missing-location' }
                        $current = [Uri]::new($current, $response.Headers.Location)
                        continue
                    }
                    if (-not $response.IsSuccessStatusCode) { throw "desktop-plugin-download-http-$([int]$response.StatusCode)" }
                    $parent = Split-Path -Parent $destination
                    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
                    $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
                    $file = [IO.File]::Open($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                    try { $stream.CopyTo($file) } finally { $file.Dispose(); $stream.Dispose() }
                    return
                }
                throw 'desktop-plugin-download-too-many-redirects'
            } finally {
                $client.Dispose()
                $handler.Dispose()
            }
        }
        Run = {
            param($file, $arguments, $workingDirectory, $environment)
            $saved = @{}
            try {
                foreach ($name in $environment.Keys) {
                    $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
                    $value = $environment[$name]
                    if ($null -eq $value) { Remove-Item -LiteralPath ("Env:" + $name) -ErrorAction SilentlyContinue }
                    else { Set-Item -LiteralPath ("Env:" + $name) -Value ([string]$value) }
                }
                Push-Location $workingDirectory
                try { & $file @arguments; $code = $LASTEXITCODE } finally { Pop-Location }
                return [pscustomobject]@{ ExitCode = $code }
            } finally {
                foreach ($name in $saved.Keys) {
                    if ($null -eq $saved[$name]) { Remove-Item -LiteralPath ("Env:" + $name) -ErrorAction SilentlyContinue }
                    else { Set-Item -LiteralPath ("Env:" + $name) -Value $saved[$name] }
                }
            }
        }
        UtcNow = { [DateTime]::UtcNow }
    }
}

function Merge-PluginOperations {
    param([hashtable]$Operations)
    $merged = Get-DshOfficialDesktopPluginOperations
    if ($Operations) { foreach ($key in $Operations.Keys) { $merged[$key] = $Operations[$key] } }
    return $merged
}

function Test-DshOfficialDesktopPluginArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        $Contract = (Get-DshOfficialDesktopPluginContract),
        [hashtable]$Operations
    )
    $ops = Merge-PluginOperations $Operations
    try {
        if (-not (&$ops.PathExists $Path 'Leaf')) { throw 'desktop-plugin-artifact-missing' }
        if ((Split-Path -Leaf $Path) -cne [string]$Contract.artifact.name) { throw 'desktop-plugin-artifact-name-mismatch' }
        if ([long](&$ops.GetLength $Path) -ne [long]$Contract.artifact.size) { throw 'desktop-plugin-artifact-size-mismatch' }
        if ((&$ops.GetHash $Path 'SHA256') -cne [string]$Contract.artifact.sha256) { throw 'desktop-plugin-artifact-sha256-mismatch' }
        if ((&$ops.GetHash $Path 'SHA512') -cne [string]$Contract.artifact.sha512) { throw 'desktop-plugin-artifact-sha512-mismatch' }
        $entries = @(& tar -tzf $Path 2>$null)
        if ($LASTEXITCODE -ne 0 -or -not $entries.Count) { throw 'desktop-plugin-artifact-list-failed' }
        foreach ($entry in $entries) {
            if ([string]::IsNullOrWhiteSpace($entry) -or $entry.StartsWith('/') -or
                $entry.Contains('\') -or $entry -match '^[A-Za-z]:' -or
                $entry -match '(^|/)\.\.(/|$)' -or
                -not $entry.StartsWith('package/')) {
                throw 'desktop-plugin-artifact-path-traversal'
            }
        }
        if (@($entries | Where-Object { $_ -ceq 'package/package.json' }).Count -ne 1) {
            throw 'desktop-plugin-artifact-manifest-count-invalid'
        }
        $verboseEntries = @(& tar -tvzf $Path 2>$null)
        if ($LASTEXITCODE -ne 0 -or -not $verboseEntries.Count -or
            @($verboseEntries | Where-Object {
                $line = ([string]$_).TrimStart()
                $line.Length -eq 0 -or $line[0] -notin @('-', 'd')
            }).Count) {
            throw 'desktop-plugin-artifact-entry-type-invalid'
        }
        $manifestText = & tar -xOzf $Path package/package.json 2>$null | Out-String
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($manifestText)) {
            throw 'desktop-plugin-artifact-manifest-missing'
        }
        $manifest = $manifestText | ConvertFrom-Json
        if ([string]$manifest.name -cne [string]$Contract.package.name -or
            [string]$manifest.version -cne [string]$Contract.package.version -or
            [string]$manifest.main -cne [string]$Contract.package.main -or
            [string]$manifest.types -cne [string]$Contract.package.types -or
            [string]$manifest.dsh.bundle.patch -cne [string]$Contract.package.bundlePatch) {
            throw 'desktop-plugin-artifact-manifest-drift'
        }
        foreach ($hook in $script:LifecycleHooks) {
            if ($null -ne (Get-PluginLeafValue $manifest.scripts $hook)) {
                throw "desktop-plugin-lifecycle-hook-forbidden:$hook"
            }
        }
        return [pscustomobject]@{
            valid = $true
            reason = $null
            path = Get-PluginNormalizedPath $Path
            manifest = $manifest
            entryCount = $entries.Count
        }
    } catch {
        return [pscustomobject]@{ valid = $false; reason = $_.Exception.Message; path = $Path }
    }
}

function Get-DesktopPluginProfileState {
    param([string]$ProfileRoot, $Contract, [hashtable]$Operations)
    if (-not (&$Operations.PathExists $ProfileRoot '')) {
        return [pscustomobject]@{ kind = 'absent'; plugins = @(); targetInstalled = $false }
    }
    if (-not (&$Operations.PathExists $ProfileRoot 'Container') -or
        -not (&$Operations.IsCurrentUserOwner $ProfileRoot)) {
        throw 'desktop-plugin-profile-owner-or-type-invalid'
    }
    $manifestPath = Join-Path $ProfileRoot 'package.json'
    $releasePath = Join-Path $ProfileRoot 'desktop-release.json'
    if (-not (&$Operations.PathExists $manifestPath 'Leaf') -or
        -not (&$Operations.PathExists $releasePath 'Leaf')) {
        throw 'desktop-plugin-profile-not-official'
    }
    $manifest = &$Operations.ReadJson $manifestPath
    if ([string]$manifest.name -cne '@deepseek-ai/dsh-desktop-runtime' -or $manifest.private -ne $true) {
        throw 'desktop-plugin-profile-manifest-invalid'
    }
    $bundles = @($manifest.dsh.profile.bundles)
    if ($bundles.Count -lt 2 -or $bundles[0] -cne $script:BuiltInBundles[0] -or
        $bundles[1] -cne $script:BuiltInBundles[1] -or
        @($bundles | Select-Object -Unique).Count -ne $bundles.Count -or
        @($bundles | Where-Object { $script:ConflictingBundles -contains [string]$_ }).Count) {
        throw 'desktop-plugin-profile-bundle-composition-invalid'
    }
    $plugins = @()
    foreach ($name in @($bundles | Select-Object -Skip 2)) {
        if ([string]$name -cnotmatch '^(?:@[a-z0-9][a-z0-9._~-]*/)?[a-z0-9][a-z0-9._~-]*$') {
            throw 'desktop-plugin-profile-package-name-invalid'
        }
        $pluginManifest = Join-Path $ProfileRoot ('node_modules\' + ([string]$name).Replace('/', '\') + '\package.json')
        if (-not (&$Operations.PathExists $pluginManifest 'Leaf')) { throw "desktop-plugin-profile-package-missing:$name" }
        $metadata = &$Operations.ReadJson $pluginManifest
        if ([string]$metadata.name -cne [string]$name -or [string]$metadata.version -notmatch '^[0-9A-Za-z][0-9A-Za-z.+_-]*$') {
            throw "desktop-plugin-profile-package-invalid:$name"
        }
        $plugins += [pscustomobject]@{ name = [string]$name; version = [string]$metadata.version }
    }
    $target = @($plugins | Where-Object name -CEQ ([string]$Contract.package.name))
    return [pscustomobject]@{
        kind = 'official'
        manifest = $manifest
        plugins = $plugins
        targetInstalled = [bool]($target.Count -eq 1 -and $target[0].version -ceq [string]$Contract.package.version)
    }
}

function Get-DshOfficialDesktopPluginProvisioningCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DshHome,
        [Parameter(Mandatory)][string]$InstallRoot,
        [Parameter(Mandatory)][string]$DataRoot,
        [string]$LockPath = $script:DefaultLockPath,
        [string]$ArtifactPath,
        [hashtable]$Operations
    )
    $ops = Merge-PluginOperations $Operations
    $contract = Get-DshOfficialDesktopPluginContract -LockPath $LockPath
    $homeRoot = Assert-PluginOwnedPath $DshHome 'desktop-plugin-home' $ops
    $install = Assert-PluginOwnedPath $InstallRoot 'desktop-plugin-install-root' $ops
    $data = Assert-PluginOwnedPath $DataRoot 'desktop-plugin-data-root' $ops
    foreach ($pair in @(@($homeRoot, $install), @($homeRoot, $data), @($install, $data))) {
        if ((Test-PluginPathAtOrWithin $pair[0] $pair[1]) -or (Test-PluginPathAtOrWithin $pair[1] $pair[0])) {
            throw 'desktop-plugin-owned-path-overlap'
        }
    }
    foreach ($owned in @($homeRoot, (Join-Path $homeRoot 'desktop'), (Join-Path $homeRoot 'profiles'), (Join-Path $homeRoot 'profiles\desktop'))) {
        if ((&$ops.PathExists $owned '') -and -not (&$ops.IsCurrentUserOwner $owned)) {
            throw 'desktop-plugin-owned-path-owner-mismatch'
        }
    }
    $processProbe = &$ops.GetProcesses
    $reasons = [Collections.Generic.List[string]]::new()
    if ($processProbe.unavailable) { $reasons.Add('desktop-plugin-process-enumeration-unavailable') }
    $running = @()
    foreach ($process in @($processProbe.items)) {
        $exe = [string](Get-PluginLeafValue $process 'ExecutablePath')
        $command = [string](Get-PluginLeafValue $process 'CommandLine')
        $name = [string](Get-PluginLeafValue $process 'Name')
        if (($exe -and ((Test-PluginPathAtOrWithin $exe $install) -or (Test-PluginPathAtOrWithin $exe $homeRoot))) -or
            ($name -match '(?i)^(dsh|deepseek.*|node|pnpm)\.exe$' -and $command -and
                ($command.IndexOf($homeRoot, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                    $command.IndexOf($install, [StringComparison]::OrdinalIgnoreCase) -ge 0))) {
            $running += $process
        }
    }
    if ($running.Count) { $reasons.Add('desktop-plugin-runtime-running') }
    $pending = Join-Path $homeRoot 'desktop\pending.json'
    $rollback = Join-Path $homeRoot 'desktop\rollback\profile'
    if (&$ops.PathExists $pending 'Leaf') { $reasons.Add('desktop-plugin-recovery-required') }
    if (&$ops.PathExists $rollback '') { $reasons.Add('desktop-plugin-rollback-state-present') }
    $seed = Join-Path $install 'resources\seed'
    foreach ($required in @('package.json', 'desktop-release.json', 'desktop-packages.json', 'pnpm-workspace.yaml', 'pnpm-lock.yaml', 'integrity.json')) {
        if (-not (&$ops.PathExists (Join-Path $seed $required) 'Leaf')) { $reasons.Add("desktop-plugin-seed-missing:$required") }
    }
    $profileRoot = Join-Path $homeRoot 'profiles\desktop'
    $profile = $null
    try { $profile = Get-DesktopPluginProfileState $profileRoot $contract $ops } catch { $reasons.Add($_.Exception.Message) }
    $resolvedArtifact = if ($ArtifactPath) { Get-PluginNormalizedPath $ArtifactPath } else {
        Join-Path $data ('artifacts\desktop-plugins\' + [string]$contract.artifact.sha256 + '\' + [string]$contract.artifact.name)
    }
    $artifact = if (&$ops.PathExists $resolvedArtifact 'Leaf') {
        Test-DshOfficialDesktopPluginArtifact -Path $resolvedArtifact -Contract $contract -Operations $ops
    } else { [pscustomobject]@{ valid = $false; reason = 'desktop-plugin-artifact-not-downloaded'; path = $resolvedArtifact } }
    if ((&$ops.PathExists $resolvedArtifact 'Leaf') -and -not $artifact.valid) { $reasons.Add([string]$artifact.reason) }
    $receiptPath = Join-Path $data $script:ReceiptName
    $receipt = if (&$ops.PathExists $receiptPath 'Leaf') {
        try { &$ops.ReadJson $receiptPath } catch { $reasons.Add('desktop-plugin-receipt-unreadable'); $null }
    } else { $null }
    $verified = $profile -and $profile.targetInstalled -and $receipt -and
        [string]$receipt.mode -ceq [string]$contract.mode -and
        [string]$receipt.version -ceq [string]$contract.package.version -and
        [string]$receipt.artifactSha256 -ceq [string]$contract.artifact.sha256 -and
        [string]$receipt.profileRoot -ceq $profileRoot
    return [pscustomobject]@{
        schemaVersion = 1
        action = 'check'
        status = if ($reasons.Count) { 'blocked' } elseif ($verified) { 'verified' } else { 'ready' }
        reasons = @($reasons)
        mode = $contract.mode
        delegatedToDesktop = [bool]($contract.mode -ceq 'desktopNativeVerifiedRelease')
        contract = $contract
        home = $homeRoot
        installRoot = $install
        dataRoot = $data
        seedRoot = $seed
        profileRoot = $profileRoot
        profile = $profile
        artifact = $artifact
        artifactPath = $resolvedArtifact
        receiptPath = $receiptPath
        runningProcesses = $running
        mutated = $false
    }
}

function Invoke-DesktopPluginPnpm {
    param(
        [string]$ProjectRoot,
        [string[]]$Arguments,
        [string]$InstallRoot,
        [string]$DshHome,
        [string]$Registry,
        [hashtable]$Operations
    )
    $node = Join-Path $InstallRoot 'resources\runtime\node\node.exe'
    $pnpm = Join-Path $InstallRoot 'resources\runtime\pnpm\bin\pnpm.mjs'
    if (-not (&$Operations.PathExists $node 'Leaf') -or -not (&$Operations.PathExists $pnpm 'Leaf')) {
        throw 'desktop-plugin-bundled-runtime-missing'
    }
    $store = Join-Path $DshHome 'desktop\pnpm\store'
    $config = Join-Path $DshHome 'desktop\pnpm\config'
    &$Operations.CreateDirectory $store
    &$Operations.CreateDirectory $config
    $environment = @{
        NODE_OPTIONS = $null
        NODE_PATH = $null
        NPM_CONFIG_REGISTRY = $Registry
        NPM_CONFIG_STORE_DIR = $store
        NPM_CONFIG_USERCONFIG = (Join-Path $config 'npmrc')
        COREPACK_HOME = $null
        PNPM_HOME = (Join-Path $DshHome 'desktop\pnpm\home')
    }
    $full = @($pnpm) + @($Arguments) + @(
        "--config.store-dir=$store",
        '--config.enable-global-virtual-store=false',
        "--config.registry=$Registry",
        '--config.ignore-scripts=true'
    )
    $run = &$Operations.Run $node $full $ProjectRoot $environment
    if ($null -eq $run -or [int]$run.ExitCode -ne 0) {
        throw "desktop-plugin-pnpm-failed:$([int]$run.ExitCode)"
    }
}

function Copy-DesktopPluginProjectMetadata {
    param([string]$Source, [string]$Target, [hashtable]$Operations)
    &$Operations.CreateDirectory $Target
    foreach ($file in @('package.json', 'pnpm-lock.yaml', 'pnpm-workspace.yaml', 'desktop-release.json', 'desktop-packages.json')) {
        $path = Join-Path $Source $file
        if (&$Operations.PathExists $path 'Leaf') { &$Operations.CopyFile $path (Join-Path $Target $file) }
    }
    $packages = Join-Path $Source 'desktop-packages'
    if (-not (&$Operations.PathExists $packages 'Container')) { throw 'desktop-plugin-core-packages-missing' }
    &$Operations.CopyDirectory $packages (Join-Path $Target 'desktop-packages')
}

function Set-DesktopPluginBundleManifest {
    param([string]$ProfileRoot, $Plugins, [hashtable]$Operations)
    $path = Join-Path $ProfileRoot 'package.json'
    $manifest = &$Operations.ReadJson $path
    $bundles = @($script:BuiltInBundles) + @($Plugins | Sort-Object name | ForEach-Object { [string]$_.name })
    if (@($bundles | Select-Object -Unique).Count -ne $bundles.Count -or
        @($bundles | Where-Object { $script:ConflictingBundles -contains [string]$_ }).Count) {
        throw 'desktop-plugin-profile-bundle-composition-invalid'
    }
    $manifest.dsh.profile.bundles = $bundles
    &$Operations.WriteJsonAtomic $path $manifest
}

function Invoke-DesktopPluginHealthCheck {
    param(
        [string]$ProfileRoot,
        [string]$HealthRoot,
        [string]$InstallRoot,
        [string]$HealthScript,
        [hashtable]$Operations
    )
    $home = Join-Path $HealthRoot 'home'
    $roaming = Join-Path $HealthRoot 'appdata\Roaming'
    $local = Join-Path $HealthRoot 'appdata\Local'
    try {
        foreach ($path in @($home, $roaming, $local)) {
            &$Operations.CreateDirectory $path
        }
        return &$Operations.Run (Join-Path $InstallRoot 'resources\runtime\node\node.exe') `
            @($HealthScript, $ProfileRoot) $ProfileRoot @{
                NODE_OPTIONS = $null
                NODE_PATH = $null
                DSH_HOME = $home
                HOME = $home
                USERPROFILE = $home
                APPDATA = $roaming
                LOCALAPPDATA = $local
            }
    } finally {
        &$Operations.RemoveDirectory $HealthRoot
    }
}

function Test-DesktopPluginProvisioningReceipt {
    param($Expected, $Actual)
    if ($null -eq $Actual -or -not (Test-PluginExactKeys $Actual @(
        'schemaVersion', 'status', 'mode', 'createdUtc', 'package', 'version',
        'artifactPath', 'artifactSha256', 'artifactSha512', 'registry', 'homeMode',
        'profileRoot', 'preservedPlugins', 'sharedHomeContentRead', 'nativeUpdaterEnabled'
    ))) { return $false }
    return (ConvertTo-PluginCanonicalJson $Actual) -ceq (ConvertTo-PluginCanonicalJson $Expected)
}

function Invoke-DshOfficialDesktopPluginProvisioning {
    [CmdletBinding()]
    param(
        [ValidateSet('Check', 'Apply')][string]$Action = 'Check',
        [Parameter(Mandatory)][string]$DshHome,
        [Parameter(Mandatory)][string]$InstallRoot,
        [Parameter(Mandatory)][string]$DataRoot,
        [string]$LockPath = $script:DefaultLockPath,
        [string]$ArtifactPath,
        [hashtable]$Operations
    )
    $ops = Merge-PluginOperations $Operations
    $check = Get-DshOfficialDesktopPluginProvisioningCheck -DshHome $DshHome -InstallRoot $InstallRoot `
        -DataRoot $DataRoot -LockPath $LockPath -ArtifactPath $ArtifactPath -Operations $ops
    if ($Action -ceq 'Check' -or $check.status -in @('blocked', 'verified')) { return $check }
    if ($check.mode -ceq 'desktopNativeVerifiedRelease') {
        return [pscustomobject]@{
            schemaVersion = 1
            action = 'apply'
            status = 'delegated'
            mode = $check.mode
            changed = $false
            delegatedToDesktop = $true
        }
    }
    if ($check.runningProcesses.Count) { throw 'desktop-plugin-runtime-running' }
    $artifact = $check.artifactPath
    if (-not (&$ops.PathExists $artifact 'Leaf')) {
        $parent = Split-Path -Parent $artifact
        &$ops.CreateDirectory $parent
        $temp = Join-Path $parent (([string]$check.contract.artifact.name) + '.partial-' + [guid]::NewGuid().ToString('N'))
        try {
            &$ops.Download ([string]$check.contract.artifact.url) $temp @($check.contract.allowedRedirectHosts)
            $named = Join-Path $parent ([string]$check.contract.artifact.name)
            &$ops.MoveFile $temp $named
            $artifact = $named
        } catch {
            &$ops.RemoveFile $temp
            throw
        }
    }
    $artifactState = Test-DshOfficialDesktopPluginArtifact -Path $artifact -Contract $check.contract -Operations $ops
    if (-not $artifactState.valid) { throw $artifactState.reason }
    $desktopRoot = Join-Path $check.home 'desktop'
    $staging = Join-Path $desktopRoot ('staging\' + [guid]::NewGuid().ToString('N') + '\profile')
    $transactionRoot = Split-Path $staging -Parent
    $rollback = Join-Path $desktopRoot 'rollback\profile'
    $pending = Join-Path $desktopRoot 'pending.json'
    $receiptBackup = Join-Path $transactionRoot 'recovery\previous-receipt.json'
    $previousReceiptPresent = &$ops.PathExists $check.receiptPath 'Leaf'
    $receiptCommitted = $false
    if ((&$ops.PathExists $pending '') -or (&$ops.PathExists $rollback '')) { throw 'desktop-plugin-recovery-required' }
    $source = if ($check.profile.kind -ceq 'official') { $check.profileRoot } else { $check.seedRoot }
    $plugins = @($check.profile.plugins |
        Where-Object name -CNE ([string]$check.contract.package.name) |
        ForEach-Object { [pscustomobject]@{ name = [string]$_.name; version = [string]$_.version } })
    $plugins += [pscustomobject]@{ name = [string]$check.contract.package.name; version = [string]$check.contract.package.version }
    try {
        Copy-DesktopPluginProjectMetadata $source $staging $ops
        Invoke-DesktopPluginPnpm $staging @('install', '--frozen-lockfile', '--trust-lockfile') `
            $check.installRoot $check.home $check.contract.registry $ops
        foreach ($plugin in @($plugins | Where-Object name -CNE ([string]$check.contract.package.name))) {
            Invoke-DesktopPluginPnpm $staging @('add', "$($plugin.name)@$($plugin.version)", '--save-exact') `
                $check.installRoot $check.home $check.contract.registry $ops
        }
        Invoke-DesktopPluginPnpm $staging @('add', $artifact, '--save-exact') `
            $check.installRoot $check.home $check.contract.registry $ops
        Set-DesktopPluginBundleManifest $staging $plugins $ops
        $stagedState = Get-DesktopPluginProfileState $staging $check.contract $ops
        if (-not $stagedState.targetInstalled) { throw 'desktop-plugin-staging-validation-failed' }
        $healthScript = Join-Path $PSScriptRoot 'dsh-official-desktop-plugin-health.mjs'
        $health = Invoke-DesktopPluginHealthCheck $staging (Join-Path $transactionRoot 'health\staged') `
            $check.installRoot $healthScript $ops
        if ($null -eq $health -or [int]$health.ExitCode -ne 0) { throw 'desktop-plugin-staging-health-failed' }
        if ($previousReceiptPresent) {
            &$ops.CopyFile $check.receiptPath $receiptBackup
        }
        $journal = [pscustomobject]@{
            schemaVersion = 1
            id = Split-Path (Split-Path $staging -Parent) -Leaf
            stagingProfile = $staging
            activeProfile = $check.profileRoot
            rollbackProfile = $rollback
            previousProfilePresent = [bool](&$ops.PathExists $check.profileRoot 'Container')
            previousReceiptPresent = [bool]$previousReceiptPresent
            previousReceiptBackup = if ($previousReceiptPresent) { $receiptBackup } else { $null }
            step = 'prepared'
        }
        &$ops.WriteJsonAtomic $pending $journal
        if (&$ops.PathExists $check.profileRoot 'Container') {
            &$ops.CreateDirectory (Split-Path -Parent $rollback)
            &$ops.MoveDirectory $check.profileRoot $rollback
            $journal.step = 'active-moved'
            &$ops.WriteJsonAtomic $pending $journal
        }
        &$ops.CreateDirectory (Split-Path -Parent $check.profileRoot)
        &$ops.MoveDirectory $staging $check.profileRoot
        $journal.step = 'staging-activated'
        &$ops.WriteJsonAtomic $pending $journal
        $activeHealth = Invoke-DesktopPluginHealthCheck $check.profileRoot (Join-Path $transactionRoot 'health\active') `
            $check.installRoot $healthScript $ops
        if ($null -eq $activeHealth -or [int]$activeHealth.ExitCode -ne 0) { throw 'desktop-plugin-active-health-failed' }
        $receipt = [pscustomobject][ordered]@{
            schemaVersion = 1
            status = 'complete'
            mode = $check.mode
            createdUtc = (&$ops.UtcNow).ToString('o')
            package = [string]$check.contract.package.name
            version = [string]$check.contract.package.version
            artifactPath = $artifact
            artifactSha256 = [string]$check.contract.artifact.sha256
            artifactSha512 = [string]$check.contract.artifact.sha512
            registry = [string]$check.contract.registry
            homeMode = if ($check.home -ceq (Join-Path $check.dataRoot 'harness-home')) { 'isolated' } else { 'shared' }
            profileRoot = $check.profileRoot
            preservedPlugins = @($plugins | Where-Object name -CNE ([string]$check.contract.package.name))
            sharedHomeContentRead = $false
            nativeUpdaterEnabled = $false
        }
        &$ops.WriteJsonAtomic $check.receiptPath $receipt
        $committedReceipt = &$ops.ReadJson $check.receiptPath
        if (-not (Test-DesktopPluginProvisioningReceipt $receipt $committedReceipt)) {
            throw 'desktop-plugin-receipt-commit-verification-failed'
        }
        $receiptCommitted = $true
        $journal.step = 'receipt-committed'
        &$ops.WriteJsonAtomic $pending $journal
        &$ops.RemoveDirectory $rollback
        &$ops.RemoveDirectory $transactionRoot
        &$ops.RemoveFile $pending
        return [pscustomobject]@{
            schemaVersion = 1
            action = 'apply'
            status = 'complete'
            changed = $true
            mode = $check.mode
            receipt = $receipt
            receiptPath = $check.receiptPath
            profileRoot = $check.profileRoot
            rollbackCompleted = $false
        }
    } catch {
        $failure = $_
        try {
            if (&$ops.PathExists $pending 'Leaf') {
                if ($receiptCommitted -and -not (&$ops.PathExists $rollback 'Container')) {
                    throw "desktop-plugin-finalization-recovery-required:$($failure.Exception.Message)"
                }
                if ((&$ops.PathExists $check.profileRoot 'Container') -and (&$ops.PathExists $rollback 'Container')) {
                    $failed = Join-Path $desktopRoot ('failed\' + [guid]::NewGuid().ToString('N'))
                    &$ops.CreateDirectory (Split-Path -Parent $failed)
                    &$ops.MoveDirectory $check.profileRoot $failed
                    &$ops.MoveDirectory $rollback $check.profileRoot
                    &$ops.RemoveDirectory $failed
                } elseif (-not (&$ops.PathExists $check.profileRoot '') -and (&$ops.PathExists $rollback 'Container')) {
                    &$ops.MoveDirectory $rollback $check.profileRoot
                } elseif (-not $journal.previousProfilePresent -and (&$ops.PathExists $check.profileRoot 'Container')) {
                    &$ops.RemoveDirectory $check.profileRoot
                }
                if ($previousReceiptPresent) {
                    &$ops.CopyFile $receiptBackup $check.receiptPath
                } else {
                    &$ops.RemoveFile $check.receiptPath
                }
                &$ops.RemoveFile $pending
            }
            &$ops.RemoveDirectory $transactionRoot
        } catch {
            throw "desktop-plugin-provisioning-failed-and-rollback-incomplete:$($failure.Exception.Message);$($_.Exception.Message)"
        }
        throw $failure
    }
}

Export-ModuleMember -Function @(
    'Get-DshOfficialDesktopPluginContract',
    'Get-DshOfficialDesktopPluginRecipe',
    'Get-DshOfficialDesktopPluginOperations',
    'Test-DshOfficialDesktopPluginArtifact',
    'Get-DshOfficialDesktopPluginProvisioningCheck',
    'Invoke-DshOfficialDesktopPluginProvisioning'
)
