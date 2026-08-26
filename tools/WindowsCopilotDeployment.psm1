Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-LockProperty {
    param(
        [Parameter(Mandatory)]$InputObject,
        [Parameter(Mandatory)][string]$Name
    )
    if ($InputObject -is [Collections.IDictionary]) { return $InputObject[$Name] }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Assert-LockValue {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$Path
    )
    if ($null -eq $Value -or ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value))) {
        throw "Deployment lock is missing '$Path'."
    }
}

function Read-WindowsCopilotLock {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Deployment lock not found: $Path"
    }
    $lock = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    Test-WindowsCopilotLock -Lock $lock | Out-Null
    return $lock
}

function Test-WindowsCopilotLock {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Lock)

    if ([int]$Lock.schemaVersion -ne 1) { throw 'Unsupported deployment lock schema.' }
    foreach ($path in @(
        'deploymentId',
        'components.desktop.version',
        'components.desktop.source.repository',
        'components.desktop.artifact.name',
        'components.desktop.artifact.sha256',
        'components.desktop.install.arguments',
        'components.desktop.install.acceptedExitCodes',
        'components.core.source.repository',
        'components.core.source.commit',
        'components.core.package.name',
        'components.core.package.version',
        'components.core.package.packageManager',
        'components.gateway.source.repository',
        'components.gateway.source.commit',
        'components.gateway.artifact.name',
        'components.gateway.artifact.sha256',
        'components.searchProvider.source.repository',
        'components.searchProvider.source.commit',
        'components.searchProvider.package.name',
        'components.searchProvider.package.version',
        'components.searchProvider.package.packageManager',
        'components.searchProvider.package.main',
        'components.searchProvider.package.types',
        'components.searchProvider.package.bundlePatch',
        'components.searchProvider.package.artifact.name',
        'components.searchProvider.package.artifact.sha256',
        'components.searchProvider.package.deploymentBaseline.id',
        'components.searchProvider.package.deploymentBaseline.kind',
        'components.searchProvider.package.deploymentBaseline.sourceCommitPolicy',
        'profile.lockManifest',
        'profile.requiredBundles'
    )) {
        $value = $Lock
        foreach ($segment in $path.Split('.')) {
            $value = Get-LockProperty -InputObject $value -Name $segment
            if ($null -eq $value) { break }
        }
        Assert-LockValue -Value $value -Path $path
    }

    foreach ($commit in @(
        [string]$Lock.components.core.source.commit,
        [string]$Lock.components.gateway.source.commit,
        [string]$Lock.components.searchProvider.source.commit
    )) {
        if ($commit -notmatch '^[0-9a-f]{40}$') { throw "Invalid locked commit: $commit" }
    }
    foreach ($sha in @(
        [string]$Lock.components.desktop.artifact.sha256,
        [string]$Lock.components.gateway.artifact.sha256,
        [string]$Lock.components.searchProvider.package.artifact.sha256
    )) {
        if ($sha -notmatch '^[0-9a-f]{64}$') { throw "Invalid locked artifact SHA-256: $sha" }
    }
    if (@($Lock.components.desktop.install.arguments).Count -eq 0 -or
        @($Lock.components.desktop.install.acceptedExitCodes).Count -eq 0) {
        throw 'Desktop install arguments and accepted exit codes must be locked.'
    }

    $requiredGlobal = @(
        '@deepseek-ai/cordis-plugin-hmr',
        '@deepseek-ai/cordis-plugin-timer',
        'node-addon-require-builtin',
        'dsh-tauri',
        'dsh-tauri-ui',
        'dsh-tauri-worktree'
    )
    $globalNames = @($Lock.globalInstall.packages | ForEach-Object { [string]$_.name })
    foreach ($name in $requiredGlobal) {
        if ($globalNames -notcontains $name) { throw "Global transaction omits '$name'." }
    }
    foreach ($package in @($Lock.globalInstall.packages)) {
        Assert-LockValue -Value $package.version -Path "globalInstall.packages.$($package.name).version"
    }

    $requiredPlugins = @(
        'dsh-tauri',
        'dsh-tauri-ui',
        'dsh-tauri-worktree',
        'dsh-web-search-provider'
    )
    $plugins = @($Lock.profile.plugins)
    foreach ($name in $requiredPlugins) {
        $matches = @($plugins | Where-Object { $_.name -eq $name -and $_.materialize -eq $true })
        if ($matches.Count -ne 1) { throw "Profile must materialize '$name' exactly once." }
    }
    $requiredBundles = @($Lock.profile.requiredBundles)
    foreach ($name in @('@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app') + $requiredPlugins) {
        if (@($requiredBundles | Where-Object { $_ -eq $name }).Count -ne 1) {
            throw "Profile requiredBundles must contain '$name' exactly once."
        }
    }

    $allowBuilds = @($Lock.profile.allowBuilds)
    if ($allowBuilds.Count -ne 2 -or
        $allowBuilds -notcontains '@google/genai' -or
        $allowBuilds -notcontains 'protobufjs') {
        throw 'Profile allowBuilds must contain only @google/genai and protobufjs.'
    }

    $routes = @($Lock.profile.routes)
    if ($routes.Count -ne 2) { throw 'Exactly two Copilot routes are required.' }
    $protocols = @($routes | ForEach-Object { [string]$_.protocol })
    foreach ($protocol in @('openai-responses', 'openai-completions')) {
        if ($protocols -notcontains $protocol) { throw "Missing '$protocol' route." }
    }
    foreach ($route in $routes) {
        if ([string]$route.id -eq 'github-copilot' -or
            @($Lock.profile.forbiddenRouteIds) -contains [string]$route.id) {
            throw "Forbidden route id '$($route.id)'."
        }
        Assert-LockValue -Value $route.endpointCapability -Path "profile.routes.$($route.id).endpointCapability"
    }

    $listenerPorts = @($Lock.acceptance.listeners | ForEach-Object { [int]$_.port })
    foreach ($port in @(3080, 7777)) {
        if ($listenerPorts -notcontains $port) { throw "Acceptance contract omits loopback port $port." }
    }
    foreach ($listener in @($Lock.acceptance.listeners)) {
        if ([string]$listener.host -ne '127.0.0.1') {
            throw "Listener '$($listener.name)' is not locked to IPv4 loopback."
        }
    }
    $imports = @($Lock.acceptance.loaderImports)
    foreach ($name in $requiredGlobal[0..2]) {
        if ($imports -notcontains $name) { throw "Loader import contract omits '$name'." }
    }
    if (@($Lock.acceptance.composedConfig.requiredMarkers) -notcontains 'dsh-web-search-provider') {
        throw 'Composed-config contract omits dsh-web-search-provider.'
    }
    $composedEntries = @($Lock.acceptance.composedConfig.requiredEntries)
    if (@($composedEntries | Where-Object {
        $_.id -eq 'web-search-provider' -and $_.name -eq 'dsh-web-search-provider'
    }).Count -ne 1) {
        throw 'Composed-config contract omits the active web-search-provider entry.'
    }
    if (@($Lock.acceptance.searchSmoke.forbiddenText) -notcontains 'DEEPSEEK_API_KEY') {
        throw 'Search smoke contract must reject DEEPSEEK_API_KEY fallback.'
    }

    $baseline = $Lock.components.searchProvider.package.deploymentBaseline
    $expectedCapabilities = @(
        'responses-replay-item-id-normalization',
        'grounded-sandbox-escalation',
        'image-attachment-bypass',
        'failure-safe-copilot-model-catalog',
        'orphaned-replay-item-filtering'
    )
    $lockedCapabilities = @($baseline.requiredCapabilities)
    if ($lockedCapabilities.Count -ne $expectedCapabilities.Count) {
        throw 'Provider deployment baseline must lock exactly five required capabilities.'
    }
    foreach ($capability in $expectedCapabilities) {
        if ($lockedCapabilities -notcontains $capability) {
            throw "Provider deployment baseline omits '$capability'."
        }
    }
    if ([int]$baseline.schemaVersion -ne 1 -or
        [string]$baseline.id -ne 'cloga.dsh-windows-copilot.web-search' -or
        [string]$baseline.kind -ne 'fork-deployment-baseline' -or
        [string]$baseline.sourceCommitPolicy -ne 'exact-external-pin' -or
        [string]$baseline.platform -ne 'windows' -or
        [string]$baseline.node -ne '>=22.0.0' -or
        [string]$baseline.dshRelease -ne '0.1.0-rc.6' -or
        [string]$baseline.copilotApi -ne 'openai-responses' -or
        [string]$baseline.modelCatalogEndpoint -ne '/v1/models' -or
        [string]$baseline.metadataProfile -ne 'optional-copilot-model-capabilities') {
        throw 'Provider deployment baseline metadata does not match the reviewed contract.'
    }

    return [pscustomobject]@{
        valid = $true
        deploymentId = [string]$Lock.deploymentId
        requiredComponents = 4
        requiredPhysicalPlugins = 4
    }
}

function Resolve-DeploymentPath {
    param([Parameter(Mandatory)][string]$Path)
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    if (Test-Path -LiteralPath $expanded) {
        return (Resolve-Path -LiteralPath $expanded).ProviderPath
    }
    return [IO.Path]::GetFullPath($expanded)
}

function Test-LockedArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Sha256,
        [string]$ExpectedName
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Locked artifact not found: $Path"
    }
    if ($ExpectedName -and (Split-Path -Leaf $Path) -ne $ExpectedName) {
        throw "Locked artifact name mismatch for '$Path'; expected '$ExpectedName'."
    }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Sha256.ToLowerInvariant()) {
        throw "SHA-256 mismatch for '$Path'."
    }
    return [pscustomobject]@{ path = (Resolve-DeploymentPath $Path); sha256 = $actual; valid = $true }
}

function Assert-ProviderBaselineData {
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)]$Package,
        [Parameter(Mandatory)]$Baseline
    )
    $expected = $Lock.components.searchProvider.package
    if ([string]$Package.name -ne [string]$expected.name -or
        [string]$Package.version -ne [string]$expected.version -or
        [string]$Package.packageManager -ne [string]$expected.packageManager -or
        [string]$Package.main -ne [string]$expected.main -or
        [string]$Package.types -ne [string]$expected.types -or
        [string]$Package.dsh.bundle.patch -ne [string]$expected.bundlePatch) {
        throw 'Provider package metadata does not match the deployment lock.'
    }
    $contract = $expected.deploymentBaseline
    if ([int]$Baseline.schemaVersion -ne [int]$contract.schemaVersion -or
        [string]$Baseline.baseline.id -ne [string]$contract.id -or
        [string]$Baseline.baseline.kind -ne [string]$contract.kind -or
        [string]$Baseline.baseline.sourceCommitPolicy -ne [string]$contract.sourceCommitPolicy -or
        [string]$Baseline.package.name -ne [string]$expected.name -or
        [string]$Baseline.package.version -ne [string]$expected.version -or
        @($Baseline.supportedBaselines.platforms) -notcontains [string]$contract.platform -or
        [string]$Baseline.supportedBaselines.node -ne [string]$contract.node -or
        [string]$Baseline.supportedBaselines.dsh.release -ne [string]$contract.dshRelease -or
        [string]$Baseline.supportedBaselines.copilot.api -ne [string]$contract.copilotApi -or
        [string]$Baseline.supportedBaselines.copilot.modelCatalogEndpoint -ne [string]$contract.modelCatalogEndpoint -or
        [string]$Baseline.supportedBaselines.copilot.metadataProfile -ne [string]$contract.metadataProfile) {
        throw 'Provider deployment-baseline metadata does not match the deployment lock.'
    }
    $actualCapabilities = @($Baseline.capabilities | Where-Object { $_.required -eq $true } | ForEach-Object {
        [string]$_.id
    })
    $expectedCapabilities = @($contract.requiredCapabilities)
    if ($actualCapabilities.Count -ne $expectedCapabilities.Count) {
        throw 'Provider deployment-baseline capability count does not match the lock.'
    }
    foreach ($capability in $expectedCapabilities) {
        if ($actualCapabilities -notcontains $capability) {
            throw "Provider deployment-baseline omits '$capability'."
        }
    }
}

function Read-TarJson {
    param(
        [Parameter(Mandatory)][string]$ArtifactPath,
        [Parameter(Mandatory)][string]$RelativePath
    )
    $content = & tar -xOzf $ArtifactPath ("package/" + $RelativePath) 2>$null | Out-String
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($content)) {
        throw "Cannot read '$RelativePath' from '$ArtifactPath'."
    }
    return $content | ConvertFrom-Json
}

function Test-ProviderDeploymentContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [string]$SourceRoot,
        [string]$ArtifactPath
    )
    if (-not $SourceRoot -and -not $ArtifactPath) {
        throw 'SourceRoot or ArtifactPath is required.'
    }
    if ($SourceRoot) {
        $package = Get-Content -LiteralPath (Join-Path $SourceRoot 'package.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $baseline = Get-Content -LiteralPath (Join-Path $SourceRoot 'deployment-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-ProviderBaselineData -Lock $Lock -Package $package -Baseline $baseline
    }
    if ($ArtifactPath) {
        Test-LockedArtifact -Path $ArtifactPath `
            -Sha256 ([string]$Lock.components.searchProvider.package.artifact.sha256) `
            -ExpectedName ([string]$Lock.components.searchProvider.package.artifact.name) | Out-Null
        if ((Split-Path -Leaf $ArtifactPath) -ne [string]$Lock.components.searchProvider.package.artifact.name) {
            throw 'Provider tarball name does not match the deployment lock.'
        }
        $package = Read-TarJson -ArtifactPath $ArtifactPath -RelativePath 'package.json'
        $baseline = Read-TarJson -ArtifactPath $ArtifactPath -RelativePath 'deployment-baseline.json'
        Assert-ProviderBaselineData -Lock $Lock -Package $package -Baseline $baseline
    }
    return [pscustomobject]@{
        valid = $true
        sourceVerified = [bool]$SourceRoot
        artifactVerified = [bool]$ArtifactPath
        capabilities = @($Lock.components.searchProvider.package.deploymentBaseline.requiredCapabilities)
    }
}

function Get-WindowsCopilotInstallPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$DshHome,
        [Parameter(Mandatory)][string]$NpmGlobalRoot,
        [string]$HarnessSourceRoot,
        [string]$ProviderSourceRoot,
        [string]$DesktopArtifactPath,
        [string]$GatewayArtifactPath,
        [string]$BackupRoot
    )
    Test-WindowsCopilotLock -Lock $Lock | Out-Null
    $profileRoot = Join-Path (Resolve-DeploymentPath $DshHome) ([string]$Lock.profile.relativePath)
    $globalSpecs = @($Lock.globalInstall.packages | ForEach-Object {
        "$($_.name)@$($_.version)"
    })
    $globalSpecs += '<built-core-release-family-tarballs>'
    $globalSpecs += '<built-search-provider-tarball>'

    $steps = @(
        [pscustomobject]@{
            id = 'verify-lock'
            action = 'check'
            changesSystem = $false
            inputs = @([string]$Lock.deploymentId)
        },
        [pscustomobject]@{
            id = 'verify-source-checkouts'
            action = 'check'
            changesSystem = $false
            inputs = @($HarnessSourceRoot, $ProviderSourceRoot)
        },
        [pscustomobject]@{
            id = 'verify-release-artifacts'
            action = 'sha256'
            changesSystem = $false
            inputs = @($DesktopArtifactPath, $GatewayArtifactPath)
        },
        [pscustomobject]@{
            id = 'build-core'
            action = 'pnpm'
            packageManager = [string]$Lock.components.core.package.packageManager
            changesSystem = $false
            inputs = @($HarnessSourceRoot)
        },
        [pscustomobject]@{
            id = 'build-search-provider'
            action = 'pnpm-windows-safe'
            packageManager = [string]$Lock.components.searchProvider.package.packageManager
            commands = @($Lock.components.searchProvider.build.commands)
            changesSystem = $false
            inputs = @($ProviderSourceRoot)
        },
        [pscustomobject]@{
            id = 'install-global-transaction'
            action = 'npm-install-global'
            transactionId = [string]$Lock.globalInstall.transactionId
            packages = $globalSpecs
            changesSystem = $true
            inputs = @($NpmGlobalRoot)
        },
        [pscustomobject]@{
            id = 'install-profile'
            action = 'profile-package-and-settings'
            changesSystem = $true
            inputs = @($profileRoot)
        },
        [pscustomobject]@{
            id = 'materialize-profile-plugins'
            action = 'physical-copy'
            plugins = @($Lock.profile.plugins | ForEach-Object { [string]$_.name })
            changesSystem = $true
            inputs = @($NpmGlobalRoot, $profileRoot)
        },
        [pscustomobject]@{
            id = 'verify-installation'
            action = 'acceptance'
            checks = @('physical-plugins', 'profile-bundle', 'routes', 'allow-builds', 'loader-imports', 'loopback-3080', 'loopback-7777', 'model-catalog', 'composed-config', 'search-smoke')
            changesSystem = $false
            inputs = @($BackupRoot)
        }
    )

    return [pscustomobject]@{
        mode = 'check'
        deploymentId = [string]$Lock.deploymentId
        dshHome = (Resolve-DeploymentPath $DshHome)
        profileRoot = $profileRoot
        steps = $steps
    }
}

function Assert-SourceCheckout {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)]$Source
    )
    if (-not (Test-Path -LiteralPath (Join-Path $Root '.git'))) {
        throw "Source checkout is missing .git: $Root"
    }
    $head = (& git -C $Root rev-parse HEAD 2>$null).Trim()
    if ($LASTEXITCODE -ne 0 -or $head -ne [string]$Source.commit) {
        throw "Source checkout '$Root' is not at locked commit '$($Source.commit)'."
    }
    $remote = (& git -C $Root remote get-url origin 2>$null).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Cannot read source remote for '$Root'." }
    $expected = ([string]$Source.repository).TrimEnd('/').Replace('https://github.com/', '').Replace('.git', '')
    $normalized = $remote.Replace('\', '/').Replace(':', '/').Replace('.git', '')
    if (-not $normalized.EndsWith($expected, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Source checkout '$Root' does not match '$($Source.repository)'."
    }
    $status = @(& git -C $Root status --porcelain --untracked-files=all 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "Cannot inspect source worktree '$Root'." }
    if ($status.Count -gt 0) {
        throw "Source checkout '$Root' is not clean; refusing to build bytes outside the locked commit."
    }
}

function Invoke-LockedCommand {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$WorkingDirectory
    )
    Push-Location $WorkingDirectory
    try {
        & $FilePath @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed with exit code ${LASTEXITCODE}: $FilePath $($Arguments -join ' ')"
        }
    } finally {
        Pop-Location
    }
}

function Invoke-PinnedPnpmCommands {
    param(
        [Parameter(Mandatory)][string]$PackageManager,
        [Parameter(Mandatory)][object[]]$Commands,
        [Parameter(Mandatory)][string]$WorkingDirectory
    )
    $version = $PackageManager.Split('@')[-1]
    foreach ($command in $Commands) {
        $arguments = @('--yes', "pnpm@$version") + @($command | ForEach-Object { [string]$_ })
        Invoke-LockedCommand -FilePath 'npx' -Arguments $arguments -WorkingDirectory $WorkingDirectory
    }
}

function Get-OnlyBuiltArtifact {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Pattern
    )
    $path = Join-Path $Root $Pattern
    $artifacts = @(Get-ChildItem -Path $path -File)
    if ($artifacts.Count -ne 1) {
        throw "Expected one built artifact matching '$Pattern'; found $($artifacts.Count)."
    }
    return $artifacts[0].FullName
}

function Get-CoreReleaseArtifacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$Root
    )
    $directory = Join-Path $Root ([string]$Lock.components.core.build.artifactDirectory)
    $orderPath = Join-Path $directory ([string]$Lock.components.core.build.publishOrderFile)
    if (-not (Test-Path -LiteralPath $orderPath -PathType Leaf)) {
        throw "Core release publish order not found: $orderPath"
    }
    $filenames = @(Get-Content -LiteralPath $orderPath -Encoding UTF8 | Where-Object { $_ })
    if ($filenames.Count -lt 2 -or @($filenames | Select-Object -Unique).Count -ne $filenames.Count) {
        throw 'Core release publish order is empty, incomplete, or duplicated.'
    }
    $packages = [Collections.Generic.List[object]]::new()
    foreach ($filename in $filenames) {
        if ([IO.Path]::GetFileName([string]$filename) -ne [string]$filename -or
            [IO.Path]::GetExtension([string]$filename) -ne '.tgz') {
            throw "Invalid core release artifact name '$filename'."
        }
        $path = Join-Path $directory ([string]$filename)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Core release artifact is missing: $path"
        }
        $metadata = Read-TarJson -ArtifactPath $path -RelativePath 'package.json'
        $packages.Add([pscustomobject]@{
            name = [string]$metadata.name
            version = [string]$metadata.version
            path = $path
            sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        })
    }
    $rootPackages = @($packages | Where-Object {
        $_.name -eq [string]$Lock.components.core.build.rootPackage -and
        $_.version -eq [string]$Lock.components.core.package.version
    })
    if ($rootPackages.Count -ne 1) {
        throw 'Core release family does not contain the locked @deepseek-ai/dsh package.'
    }
    return [pscustomobject]@{ directory = $directory; packages = @($packages) }
}

function Assert-BackupRoot {
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$DshHome
    )
    $root = Resolve-DeploymentPath $BackupRoot
    $sessions = (Join-Path (Resolve-DeploymentPath $DshHome) 'sessions').TrimEnd('\') + '\'
    if (($root.TrimEnd('\') + '\').StartsWith($sessions, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Deployment backups cannot be stored under DSH sessions.'
    }
    return $root
}

function New-BackupOperation {
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$DshHome
    )
    $root = Assert-BackupRoot -BackupRoot $BackupRoot -DshHome $DshHome
    $operationId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')
    $operationRoot = Join-Path $root $operationId
    New-Item -ItemType Directory -Path $operationRoot -Force | Out-Null
    return $operationRoot
}

function Backup-DeploymentPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string]$OperationRoot
    )
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $destination = Join-Path $OperationRoot $RelativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $Path -Destination $destination -Recurse -Force
}

function Remove-ProfilePluginTarget {
    param(
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$NodeModulesRoot
    )
    if (-not (Test-Path -LiteralPath $Target)) { return }
    $root = [IO.Path]::GetFullPath($NodeModulesRoot).TrimEnd('\') + '\'
    $resolvedTarget = [IO.Path]::GetFullPath($Target)
    if (-not $resolvedTarget.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Plugin target escapes profile node_modules: $Target"
    }
    $item = Get-Item -LiteralPath $Target -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        # Unlink the junction itself. Never recurse through a pnpm/Desktop link.
        [IO.Directory]::Delete($resolvedTarget, $false)
        return
    }
    if (-not $item.PSIsContainer) {
        throw "Plugin target is not a directory: $Target"
    }
    Remove-Item -LiteralPath $Target -Recurse -Force
}

function Set-ObjectProperty {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value
    )
    $property = $Object.PSObject.Properties[$Name]
    if ($property) {
        $property.Value = $Value
    } else {
        $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    }
}

function Set-PnpmAllowBuilds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$Packages
    )
    $lines = if (Test-Path -LiteralPath $Path) {
        @(Get-Content -LiteralPath $Path -Encoding UTF8)
    } else {
        @("packages:", "  - '.'")
    }
    if (@($lines | Where-Object { $_ -match '^\s*allowBuilds\s*:' }).Count -gt 1) {
        throw "Multiple allowBuilds mappings are not supported in '$Path'."
    }
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^allowBuilds\s*:\s*$') { $start = $i; break }
    }
    if ($start -lt 0) {
        if ($lines.Count -gt 0 -and $lines[-1] -ne '') { $lines += '' }
        $lines += 'allowBuilds:'
        foreach ($name in $Packages) { $lines += "  '$name': true" }
    } else {
        $end = $lines.Count
        for ($i = $start + 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\S') { $end = $i; break }
        }
        $before = if ($start -gt 0) { @($lines[0..$start]) } else { @($lines[0]) }
        $after = if ($end -lt $lines.Count) { @($lines[$end..($lines.Count - 1)]) } else { @() }
        $block = @($Packages | ForEach-Object { "  '$_': true" })
        $lines = $before + $block + $after
    }
    Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
}

function Get-YamlIndent {
    param([Parameter(Mandatory)][string]$Line)
    if ($Line -match '^(\s*)') { return $matches[1].Length }
    return 0
}

function Get-YamlBlockEnd {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory)][int]$Start,
        [Parameter(Mandatory)][int]$Indent
    )
    for ($i = $Start + 1; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\s*(#.*)?$') { continue }
        if ((Get-YamlIndent $Lines[$i]) -le $Indent) { return $i }
    }
    return $Lines.Count
}

function Quote-YamlScalar {
    param([Parameter(Mandatory)][string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Get-WindowsCopilotRouteModels {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)]$Catalog
    )
    $data = @($Catalog.data)
    if ($data.Count -lt [int]$Lock.acceptance.modelCatalog.minimumModels) {
        throw 'Gateway model catalog is empty.'
    }
    $result = @{}
    foreach ($route in @($Lock.profile.routes)) {
        $capability = ([string]$route.endpointCapability).Trim().ToLowerInvariant()
        $models = @($data | Where-Object {
            $endpoints = @($_.supported_endpoints | ForEach-Object {
                $endpoint = ([string]$_).Trim().ToLowerInvariant()
                if (-not $endpoint.StartsWith('/')) { $endpoint = '/' + $endpoint }
                if (-not $endpoint.StartsWith('/v1/')) { $endpoint = '/v1' + $endpoint }
                $endpoint
            })
            $endpoints -contains $capability
        } | ForEach-Object { [string]$_.id } | Where-Object { $_ } | Sort-Object -Unique)
        if ($models.Count -eq 0) {
            throw "Catalog has no models for '$($route.endpointCapability)'."
        }
        $result[[string]$route.id] = $models
    }
    return $result
}

function Assert-WindowsCopilotSettingsShape {
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$SettingsPath
    )
    if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) { return }
    $lines = @(Get-Content -LiteralPath $SettingsPath -Encoding UTF8)
    if (@($lines | Where-Object { $_ -match '^\s*\t' }).Count -gt 0) {
        throw "Tabs are not supported in '$SettingsPath'."
    }
    foreach ($forbidden in @($Lock.profile.forbiddenRouteIds)) {
        if (@($lines | Where-Object {
            $_ -match ("^\s{4}['""]?" + [regex]::Escape([string]$forbidden) + "['""]?\s*:")
        }).Count -gt 0) {
            throw "Forbidden existing route id '$forbidden' in '$SettingsPath'."
        }
    }
    $llmKeyLines = @($lines | Where-Object { $_ -match '^[''"]?llm-pi-ai[''"]?\s*:' })
    if ($llmKeyLines.Count -gt 1) {
        throw "Multiple llm-pi-ai mappings are not supported in '$SettingsPath'."
    }
    if ($llmKeyLines.Count -eq 1 -and $llmKeyLines[0] -notmatch '^llm-pi-ai\s*:\s*$') {
        throw "Quoted, commented, or flow-style llm-pi-ai mappings are not supported in '$SettingsPath'."
    }
    if ($llmKeyLines.Count -eq 0) { return }
    $llmStart = [array]::IndexOf($lines, $llmKeyLines[0])
    $llmEnd = Get-YamlBlockEnd -Lines $lines -Start $llmStart -Indent 0
    $providerKeyLines = @()
    for ($i = $llmStart + 1; $i -lt $llmEnd; $i++) {
        if ($lines[$i] -match '^\s{2}[''"]?providers[''"]?\s*:') {
            $providerKeyLines += $lines[$i]
        }
    }
    if ($providerKeyLines.Count -gt 1) {
        throw "Multiple llm-pi-ai.providers mappings are not supported in '$SettingsPath'."
    }
    if ($providerKeyLines.Count -eq 1 -and $providerKeyLines[0] -notmatch '^\s{2}providers\s*:\s*$') {
        throw "Quoted, commented, or flow-style providers mappings are not supported in '$SettingsPath'."
    }
}

function Set-WindowsCopilotRoutes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$SettingsPath,
        [Parameter(Mandatory)]$Catalog
    )
    Assert-WindowsCopilotSettingsShape -Lock $Lock -SettingsPath $SettingsPath
    $routeModels = Get-WindowsCopilotRouteModels -Lock $Lock -Catalog $Catalog
    $lines = if (Test-Path -LiteralPath $SettingsPath) {
        @(Get-Content -LiteralPath $SettingsPath -Encoding UTF8)
    } else {
        @()
    }
    if (@($lines | Where-Object { $_ -match '^\s*\t' }).Count -gt 0) {
        throw "Tabs are not supported in '$SettingsPath'."
    }
    foreach ($forbidden in @($Lock.profile.forbiddenRouteIds)) {
        if (@($lines | Where-Object {
            $_ -match ("^\s{4}['""]?" + [regex]::Escape([string]$forbidden) + "['""]?\s*:")
        }).Count -gt 0) {
            throw "Forbidden existing route id '$forbidden' in '$SettingsPath'."
        }
    }

    $routeLines = [Collections.Generic.List[string]]::new()
    foreach ($route in @($Lock.profile.routes)) {
        $routeLines.Add("    $($route.id):")
        $routeLines.Add("      apiKeyEnv: $(Quote-YamlScalar ([string]$route.apiKeyEnv))")
        $routeLines.Add("      api: $(Quote-YamlScalar ([string]$route.protocol))")
        $routeLines.Add("      baseURL: $(Quote-YamlScalar ([string]$route.baseURL))")
        $routeLines.Add('      models:')
        foreach ($model in @($routeModels[[string]$route.id])) {
            $routeLines.Add("        - id: $(Quote-YamlScalar $model)")
        }
    }

    $llmStart = -1
    $llmKeyLines = @($lines | Where-Object { $_ -match '^[''"]?llm-pi-ai[''"]?\s*:' })
    if ($llmKeyLines.Count -gt 1) {
        throw "Multiple llm-pi-ai mappings are not supported in '$SettingsPath'."
    }
    if ($llmKeyLines.Count -eq 1 -and $llmKeyLines[0] -notmatch '^llm-pi-ai\s*:\s*$') {
        throw "Quoted, commented, or flow-style llm-pi-ai mappings are not supported in '$SettingsPath'."
    }
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^llm-pi-ai\s*:\s*$') { $llmStart = $i; break }
    }
    if ($llmStart -lt 0) {
        if ($lines.Count -gt 0 -and $lines[-1] -ne '') { $lines += '' }
        $lines += 'llm-pi-ai:'
        $lines += '  providers:'
        $lines += @($routeLines)
    } else {
        $llmEnd = Get-YamlBlockEnd -Lines $lines -Start $llmStart -Indent 0
        $providersStart = -1
        $providerKeyLines = @()
        for ($i = $llmStart + 1; $i -lt $llmEnd; $i++) {
            if ($lines[$i] -match '^\s{2}[''"]?providers[''"]?\s*:') {
                $providerKeyLines += $lines[$i]
            }
        }
        if ($providerKeyLines.Count -gt 1) {
            throw "Multiple llm-pi-ai.providers mappings are not supported in '$SettingsPath'."
        }
        if ($providerKeyLines.Count -eq 1 -and $providerKeyLines[0] -notmatch '^\s{2}providers\s*:\s*$') {
            throw "Quoted, commented, or flow-style providers mappings are not supported in '$SettingsPath'."
        }
        for ($i = $llmStart + 1; $i -lt $llmEnd; $i++) {
            if ($lines[$i] -match '^\s{2}providers\s*:\s*$') { $providersStart = $i; break }
        }
        if ($providersStart -lt 0) {
            $before = @($lines[0..$llmStart])
            $after = if ($llmStart + 1 -lt $lines.Count) {
                @($lines[($llmStart + 1)..($lines.Count - 1)])
            } else { @() }
            $lines = $before + @('  providers:') + @($routeLines) + $after
        } else {
            foreach ($route in @($Lock.profile.routes)) {
                $routeStart = -1
                $providersEnd = Get-YamlBlockEnd -Lines $lines -Start $providersStart -Indent 2
                for ($i = $providersStart + 1; $i -lt $providersEnd; $i++) {
                    if ($lines[$i] -match ("^\s{4}['""]?" + [regex]::Escape([string]$route.id) + "['""]?\s*:\s*$")) {
                        $routeStart = $i
                        break
                    }
                }
                if ($routeStart -ge 0) {
                    $routeEnd = Get-YamlBlockEnd -Lines $lines -Start $routeStart -Indent 4
                    $before = if ($routeStart -gt 0) { @($lines[0..($routeStart - 1)]) } else { @() }
                    $after = if ($routeEnd -lt $lines.Count) {
                        @($lines[$routeEnd..($lines.Count - 1)])
                    } else { @() }
                    $lines = $before + $after
                }
            }
            $providersEnd = Get-YamlBlockEnd -Lines $lines -Start $providersStart -Indent 2
            $before = @($lines[0..($providersEnd - 1)])
            $after = if ($providersEnd -lt $lines.Count) {
                @($lines[$providersEnd..($lines.Count - 1)])
            } else { @() }
            $lines = $before + @($routeLines) + $after
        }
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $SettingsPath) -Force | Out-Null
    Set-Content -LiteralPath $SettingsPath -Value $lines -Encoding UTF8
}

function Set-WindowsCopilotProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$DshHome,
        [Parameter(Mandatory)][string]$NpmGlobalRoot,
        [Parameter(Mandatory)][string]$ProviderArtifactPath,
        [Parameter(Mandatory)]$Catalog,
        [Parameter(Mandatory)][string]$BackupRoot,
        [string]$OperationRoot,
        [switch]$SkipPackageInstall
    )
    Test-WindowsCopilotLock -Lock $Lock | Out-Null
    $home = Resolve-DeploymentPath $DshHome
    $profileRoot = Join-Path $home ([string]$Lock.profile.relativePath)
    $packagePath = Join-Path $profileRoot ([string]$Lock.profile.packageManifest)
    $workspacePath = Join-Path $profileRoot ([string]$Lock.profile.workspaceManifest)
    $lockPath = Join-Path $profileRoot ([string]$Lock.profile.lockManifest)
    $settingsPath = Join-Path $home ([string]$Lock.profile.settingsManifest)
    $nodeModules = Join-Path $profileRoot 'node_modules'
    Assert-WindowsCopilotSettingsShape -Lock $Lock -SettingsPath $settingsPath
    if (-not $OperationRoot) {
        $OperationRoot = New-BackupOperation -BackupRoot $BackupRoot -DshHome $home
    }

    Backup-DeploymentPath -Path $packagePath -RelativePath 'profile\package.json' -OperationRoot $OperationRoot
    Backup-DeploymentPath -Path $workspacePath -RelativePath 'profile\pnpm-workspace.yaml' -OperationRoot $OperationRoot
    Backup-DeploymentPath -Path $lockPath -RelativePath 'profile\pnpm-lock.yaml' -OperationRoot $OperationRoot
    Backup-DeploymentPath -Path $settingsPath -RelativePath 'config\settings.yaml' -OperationRoot $OperationRoot
    foreach ($plugin in @($Lock.profile.plugins)) {
        $target = Join-Path $nodeModules ([string]$plugin.name)
        Backup-DeploymentPath -Path $target -RelativePath (Join-Path 'plugins' ([string]$plugin.name)) -OperationRoot $OperationRoot
    }

    New-Item -ItemType Directory -Path $profileRoot, $nodeModules -Force | Out-Null
    $artifactName = Split-Path -Leaf $ProviderArtifactPath
    $artifactRoot = Join-Path $home (Join-Path 'artifacts' ([string]$Lock.components.searchProvider.source.commit))
    New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
    $lockedArtifact = Join-Path $artifactRoot $artifactName
    Copy-Item -LiteralPath $ProviderArtifactPath -Destination $lockedArtifact -Force

    $profile = if (Test-Path -LiteralPath $packagePath -PathType Leaf) {
        Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | ConvertFrom-Json
    } else {
        [pscustomobject]@{ name = 'dsh-profile-web'; private = $true }
    }
    if (-not (Get-LockProperty -InputObject $profile -Name 'dependencies')) {
        Set-ObjectProperty -Object $profile -Name 'dependencies' -Value ([pscustomobject]@{})
    }
    $dependencyPath = "file:../../artifacts/$($Lock.components.searchProvider.source.commit)/$artifactName"
    Set-ObjectProperty -Object $profile.dependencies -Name ([string]$Lock.components.searchProvider.package.name) -Value $dependencyPath
    if (-not (Get-LockProperty -InputObject $profile -Name 'dsh')) {
        Set-ObjectProperty -Object $profile -Name 'dsh' -Value ([pscustomobject]@{})
    }
    if (-not (Get-LockProperty -InputObject $profile.dsh -Name 'profile')) {
        Set-ObjectProperty -Object $profile.dsh -Name 'profile' -Value ([pscustomobject]@{})
    }
    foreach ($plugin in @($Lock.profile.plugins)) {
        $name = [string]$plugin.name
        $dependency = if ($name -eq [string]$Lock.components.searchProvider.package.name) {
            $dependencyPath
        } else {
            [string]$plugin.version
        }
        Set-ObjectProperty -Object $profile.dependencies -Name $name -Value $dependency
    }
    $bundles = @((Get-LockProperty -InputObject $profile.dsh.profile -Name 'bundles'))
    foreach ($requiredBundle in @($Lock.profile.requiredBundles)) {
        $bundles = @($bundles | Where-Object { $_ -ne [string]$requiredBundle })
        $bundles += [string]$requiredBundle
    }
    Set-ObjectProperty -Object $profile.dsh.profile -Name 'bundles' -Value $bundles
    $profile | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $packagePath -Encoding UTF8

    Set-PnpmAllowBuilds -Path $workspacePath -Packages @($Lock.profile.allowBuilds)
    Set-WindowsCopilotRoutes -Lock $Lock -SettingsPath $settingsPath -Catalog $Catalog

    if (-not $SkipPackageInstall) {
        Invoke-PinnedPnpmCommands -PackageManager ([string]$Lock.components.searchProvider.package.packageManager) `
            -Commands @(, @('install', '--no-frozen-lockfile')) -WorkingDirectory $profileRoot
    }

    foreach ($plugin in @($Lock.profile.plugins)) {
        $source = Join-Path $NpmGlobalRoot ([string]$plugin.name)
        $sourcePackage = Join-Path $source 'package.json'
        if (-not (Test-Path -LiteralPath $sourcePackage -PathType Leaf)) {
            throw "Global materialization source is missing: $sourcePackage"
        }
        $sourceMetadata = Get-Content -LiteralPath $sourcePackage -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$sourceMetadata.version -ne [string]$plugin.version) {
            throw "Global '$($plugin.name)' version '$($sourceMetadata.version)' does not match '$($plugin.version)'."
        }
        $target = Join-Path $nodeModules ([string]$plugin.name)
        Remove-ProfilePluginTarget -Target $target -NodeModulesRoot $nodeModules
        Copy-Item -LiteralPath $source -Destination $target -Recurse
        if ((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Materialized plugin remains a reparse point: $target"
        }
    }

    $receipt = [pscustomobject]@{
        deploymentId = [string]$Lock.deploymentId
        createdUtc = (Get-Date).ToUniversalTime().ToString('o')
        providerArtifact = [pscustomobject]@{
            path = $lockedArtifact
            sha256 = (Get-FileHash -LiteralPath $lockedArtifact -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        backupRoot = $OperationRoot
    }
    $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OperationRoot 'receipt.json') -Encoding UTF8
    return $receipt
}

function Test-WindowsCopilotSearchResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$ResponsePath
    )
    $raw = Get-Content -LiteralPath $ResponsePath -Raw -Encoding UTF8
    foreach ($text in @($Lock.acceptance.searchSmoke.forbiddenText)) {
        if ($raw.IndexOf([string]$text, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            throw "Search smoke response contains forbidden fallback text '$text'."
        }
    }
    $response = $raw | ConvertFrom-Json
    $evidence = $false
    foreach ($item in @($response.output)) {
        $action = Get-LockProperty -InputObject $item -Name 'action'
        [object[]]$sources = if ($action) { @(Get-LockProperty -InputObject $action -Name 'sources') } else { @() }
        if ([string]$item.type -eq 'web_search_call' -and $sources.Count -gt 0) {
            $evidence = $true
        }
        $contentItems = Get-LockProperty -InputObject $item -Name 'content'
        foreach ($content in @($contentItems | Where-Object { $null -ne $_ })) {
            $annotations = Get-LockProperty -InputObject $content -Name 'annotations'
            foreach ($annotation in @($annotations | Where-Object { $null -ne $_ })) {
                if ([string]$annotation.type -eq 'url_citation' -and $annotation.url) {
                    $evidence = $true
                }
            }
        }
    }
    if (-not $evidence) { throw 'Search smoke response contains no provider-native search evidence.' }
    return [pscustomobject]@{ valid = $true; providerNativeEvidence = $true; deepSeekFallback = $false }
}

function Test-WindowsCopilotComposedConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [string]$Path,
        [AllowEmptyString()][string]$Content
    )
    if ([bool]$Path -eq [bool]$Content) {
        throw 'Provide exactly one of Path or Content for composed-config validation.'
    }
    $content = if ($Path) {
        Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    } else {
        $Content
    }
    $missing = @($Lock.acceptance.composedConfig.requiredMarkers | Where-Object {
        $content.IndexOf([string]$_, [StringComparison]::Ordinal) -lt 0
    })
    if ($missing.Count -gt 0) {
        throw "Composed config is missing: $($missing -join ', ')"
    }
    foreach ($entry in @($Lock.acceptance.composedConfig.requiredEntries)) {
        $pattern = '(?ms)^\s*-\s+id\s*:\s*[''"]?' + [regex]::Escape([string]$entry.id) +
            '[''"]?\s*$.*?^\s+name\s*:\s*[''"]?' + [regex]::Escape([string]$entry.name) + '[''"]?\s*$'
        if ($content -notmatch $pattern) {
            throw "Composed config has no active '$($entry.id)' / '$($entry.name)' entry."
        }
    }
    return [pscustomobject]@{
        valid = $true
        requiredMarkers = @($Lock.acceptance.composedConfig.requiredMarkers)
        requiredEntries = @($Lock.acceptance.composedConfig.requiredEntries)
    }
}

function Test-LoopbackListener {
    param(
        [Parameter(Mandatory)][string]$HostName,
        [Parameter(Mandatory)][int]$Port
    )
    $command = Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue
    if ($command) {
        $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
        $loopback = @($listeners | Where-Object {
            $_.LocalAddress -eq $HostName -or $_.LocalAddress -eq '::1'
        })
        $public = @($listeners | Where-Object {
            $_.LocalAddress -ne $HostName -and $_.LocalAddress -ne '::1'
        })
        return [pscustomobject]@{
            host = $HostName
            port = $Port
            listening = [bool]($loopback.Count -gt 0)
            loopbackOnly = [bool]($loopback.Count -gt 0 -and $public.Count -eq 0)
            bindingVerified = $true
        }
    }
    try {
        $client = [Net.Sockets.TcpClient]::new()
        $task = $client.ConnectAsync($HostName, $Port)
        $connected = $task.Wait(700) -and $client.Connected
        $client.Dispose()
        return [pscustomobject]@{
            host = $HostName
            port = $Port
            listening = [bool]$connected
            loopbackOnly = $false
            bindingVerified = $false
        }
    } catch {
        return [pscustomobject]@{
            host = $HostName
            port = $Port
            listening = $false
            loopbackOnly = $false
            bindingVerified = $false
        }
    }
}

function Test-LoaderPackageImports {
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$NpmGlobalRoot
    )
    $loaderRoot = Join-Path $NpmGlobalRoot '@deepseek-ai\dsh-app-boot\node_modules\@deepseek-ai\cordis-plugin-loader'
    if (-not (Test-Path -LiteralPath $loaderRoot -PathType Container)) {
        $loaderRoot = Join-Path $NpmGlobalRoot '@deepseek-ai\cordis-plugin-loader'
    }
    if (-not (Test-Path -LiteralPath $loaderRoot -PathType Container)) {
        return [pscustomobject]@{ valid = $false; status = 'loader-root-not-found' }
    }
    $packageJson = @($Lock.acceptance.loaderImports | ForEach-Object {
        ConvertTo-Json ([string]$_) -Compress
    }) -join ','
    $script = "await Promise.all([$packageJson].map((id) => import(id)))"
    Push-Location $loaderRoot
    try {
        & node --input-type=module -e $script 2>$null
        return [pscustomobject]@{
            valid = [bool]($LASTEXITCODE -eq 0)
            status = if ($LASTEXITCODE -eq 0) { 'imported' } else { 'import-failed' }
        }
    } catch {
        return [pscustomobject]@{ valid = $false; status = 'node-invocation-failed' }
    } finally {
        Pop-Location
    }
}

function Test-WindowsCopilotInstallation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$DshHome,
        [Parameter(Mandatory)][string]$NpmGlobalRoot,
        [string]$ModelCatalogPath,
        [string]$ComposedConfigPath,
        [string]$SearchSmokeResponsePath,
        [switch]$SkipRuntimeChecks
    )
    Test-WindowsCopilotLock -Lock $Lock | Out-Null
    $home = Resolve-DeploymentPath $DshHome
    $profileRoot = Join-Path $home ([string]$Lock.profile.relativePath)
    $packagePath = Join-Path $profileRoot ([string]$Lock.profile.packageManifest)
    $workspacePath = Join-Path $profileRoot ([string]$Lock.profile.workspaceManifest)
    $settingsPath = Join-Path $home ([string]$Lock.profile.settingsManifest)

    $profile = $null
    if (Test-Path -LiteralPath $packagePath -PathType Leaf) {
        try { $profile = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    }
    $dependencyValid = $false
    $bundleValid = $false
    if ($profile) {
        $dependencies = Get-LockProperty -InputObject $profile -Name 'dependencies'
        if ($dependencies) {
            $dependencyValid = $true
            foreach ($plugin in @($Lock.profile.plugins)) {
                $name = [string]$plugin.name
                $dependency = [string](Get-LockProperty -InputObject $dependencies -Name $name)
                $expected = if ($name -eq [string]$Lock.components.searchProvider.package.name) {
                    'file:../../artifacts/' + [string]$Lock.components.searchProvider.source.commit + '/' +
                        [string]$Lock.components.searchProvider.package.artifact.name
                } else {
                    [string]$plugin.version
                }
                if ($dependency.Replace('\', '/') -ne $expected) { $dependencyValid = $false }
            }
        }
        $dsh = Get-LockProperty -InputObject $profile -Name 'dsh'
        $profileManifest = if ($dsh) { Get-LockProperty -InputObject $dsh -Name 'profile' } else { $null }
        $bundles = if ($profileManifest) { @(Get-LockProperty -InputObject $profileManifest -Name 'bundles') } else { @() }
        $bundleValid = $true
        foreach ($requiredBundle in @($Lock.profile.requiredBundles)) {
            if (@($bundles | Where-Object { $_ -eq [string]$requiredBundle }).Count -ne 1) {
                $bundleValid = $false
            }
        }
    }

    $plugins = foreach ($plugin in @($Lock.profile.plugins)) {
        $path = Join-Path $profileRoot (Join-Path 'node_modules' ([string]$plugin.name))
        $exists = Test-Path -LiteralPath (Join-Path $path 'package.json') -PathType Leaf
        $physical = $false
        $version = $null
        if ($exists) {
            $physical = -not [bool]((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint)
            try {
                $metadata = Get-Content -LiteralPath (Join-Path $path 'package.json') -Raw -Encoding UTF8 | ConvertFrom-Json
                $version = [string]$metadata.version
            } catch { }
        }
        [pscustomobject]@{
            name = [string]$plugin.name
            exists = [bool]$exists
            physical = [bool]$physical
            version = $version
            versionValid = [bool]($version -eq [string]$plugin.version)
        }
    }

    $workspace = if (Test-Path -LiteralPath $workspacePath -PathType Leaf) {
        Get-Content -LiteralPath $workspacePath -Raw -Encoding UTF8
    } else { '' }
    $allowBuildKeys = @()
    $workspaceLines = @($workspace -split "`r?`n")
    $allowStart = -1
    for ($i = 0; $i -lt $workspaceLines.Count; $i++) {
        if ($workspaceLines[$i] -match '^allowBuilds\s*:\s*$') { $allowStart = $i; break }
    }
    if ($allowStart -ge 0) {
        $allowEnd = Get-YamlBlockEnd -Lines $workspaceLines -Start $allowStart -Indent 0
        for ($i = $allowStart + 1; $i -lt $allowEnd; $i++) {
            if ($workspaceLines[$i] -match "^\s+['""]?([^'"":]+)['""]?\s*:\s*true\s*$") {
                $allowBuildKeys += [string]$matches[1]
            }
        }
    }
    $expectedAllowBuilds = @($Lock.profile.allowBuilds)
    $allowBuildsValid = [bool](
        $allowBuildKeys.Count -eq $expectedAllowBuilds.Count -and
        @($allowBuildKeys | Select-Object -Unique).Count -eq $allowBuildKeys.Count
    )
    foreach ($name in $expectedAllowBuilds) {
        if ($allowBuildKeys -notcontains [string]$name) { $allowBuildsValid = $false }
    }

    $settings = if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
        Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8
    } else { '' }
    $routesValid = $true
    foreach ($route in @($Lock.profile.routes)) {
        $routePattern = '(?ms)^\s{4}[''"]?' + [regex]::Escape([string]$route.id) +
            '[''"]?\s*:\s*$.*?^\s{6}api\s*:\s*[''"]?' + [regex]::Escape([string]$route.protocol) + '[''"]?\s*$'
        if ($settings -notmatch $routePattern) { $routesValid = $false }
    }
    foreach ($forbidden in @($Lock.profile.forbiddenRouteIds)) {
        if ($settings -match ("(?m)^\s{4}['""]?" + [regex]::Escape([string]$forbidden) + "['""]?\s*:")) {
            $routesValid = $false
        }
    }

    $listeners = if ($SkipRuntimeChecks) {
        @($Lock.acceptance.listeners | ForEach-Object {
            [pscustomobject]@{ host = $_.host; port = $_.port; status = 'skipped'; loopbackOnly = $false }
        })
    } else {
        @($Lock.acceptance.listeners | ForEach-Object {
            Test-LoopbackListener -HostName ([string]$_.host) -Port ([int]$_.port)
        })
    }
    $loaderImports = if ($SkipRuntimeChecks) {
        [pscustomobject]@{ valid = $false; status = 'skipped' }
    } else {
        Test-LoaderPackageImports -Lock $Lock -NpmGlobalRoot $NpmGlobalRoot
    }

    try {
        $catalog = if ($ModelCatalogPath) {
            Get-Content -LiteralPath $ModelCatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
        } else {
            Invoke-RestMethod -UseBasicParsing -Uri ([string]$Lock.acceptance.modelCatalog.url) -Method Get -TimeoutSec 5
        }
        $routeModels = Get-WindowsCopilotRouteModels -Lock $Lock -Catalog $catalog
        $catalogCheck = [pscustomobject]@{
            valid = $true
            modelCount = @($catalog.data).Count
            responses = @($routeModels[[string]$Lock.profile.routes[0].id]).Count
            completions = @($routeModels[[string]$Lock.profile.routes[1].id]).Count
        }
    } catch {
        $catalogCheck = [pscustomobject]@{ valid = $false; status = 'unavailable-or-invalid' }
    }

    try {
        if ($ComposedConfigPath) {
            $composedCheck = Test-WindowsCopilotComposedConfig -Lock $Lock -Path $ComposedConfigPath
        } elseif ($SkipRuntimeChecks) {
            $composedCheck = [pscustomobject]@{ valid = $false; status = 'skipped' }
        } else {
            $command = @($Lock.acceptance.composedConfig.command)
            $executable = [string]$command[0]
            $arguments = @($command[1..($command.Count - 1)] | ForEach-Object { [string]$_ })
            $output = & $executable @arguments 2>$null | Out-String
            if ($LASTEXITCODE -ne 0) { throw 'dsh dump-config failed.' }
            $composedCheck = Test-WindowsCopilotComposedConfig -Lock $Lock -Content $output
        }
    } catch {
        $composedCheck = [pscustomobject]@{ valid = $false; status = 'unavailable-or-invalid' }
    }

    try {
        $searchCheck = if ($SearchSmokeResponsePath) {
            Test-WindowsCopilotSearchResponse -Lock $Lock -ResponsePath $SearchSmokeResponsePath
        } else {
            [pscustomobject]@{ valid = $false; status = 'manual-or-injectable' }
        }
    } catch {
        $searchCheck = [pscustomobject]@{ valid = $false; status = 'invalid' }
    }

    $staticValid = [bool](
        $dependencyValid -and
        $bundleValid -and
        $allowBuildsValid -and
        $routesValid -and
        @($plugins | Where-Object { -not $_.exists -or -not $_.physical -or -not $_.versionValid }).Count -eq 0
    )
    $runtimeValid = [bool](
        -not $SkipRuntimeChecks -and
        @($listeners | Where-Object { -not $_.loopbackOnly }).Count -eq 0 -and
        $loaderImports.valid -and
        $catalogCheck.valid -and
        $composedCheck.valid
    )
    return [pscustomobject]@{
        complete = [bool]($staticValid -and $runtimeValid -and $searchCheck.valid)
        readyForManualSearchSmoke = [bool]($staticValid -and $runtimeValid -and -not $searchCheck.valid)
        profile = [pscustomobject]@{
            dependencyValid = $dependencyValid
            bundleValid = $bundleValid
            allowBuildsValid = $allowBuildsValid
            routesValid = $routesValid
            plugins = @($plugins)
        }
        runtime = [pscustomobject]@{
            listeners = @($listeners)
            loaderImports = $loaderImports
            modelCatalog = $catalogCheck
            composedConfig = $composedCheck
            searchSmoke = $searchCheck
        }
    }
}

function Invoke-WindowsCopilotApply {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$DshHome,
        [Parameter(Mandatory)][string]$NpmGlobalRoot,
        [Parameter(Mandatory)][string]$HarnessSourceRoot,
        [Parameter(Mandatory)][string]$ProviderSourceRoot,
        [Parameter(Mandatory)][string]$DesktopArtifactPath,
        [Parameter(Mandatory)][string]$GatewayArtifactPath,
        [Parameter(Mandatory)][string]$GatewayInstallRoot,
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)]$Catalog
    )
    Test-WindowsCopilotLock -Lock $Lock | Out-Null
    Get-WindowsCopilotRouteModels -Lock $Lock -Catalog $Catalog | Out-Null
    $settingsPath = Join-Path (Resolve-DeploymentPath $DshHome) ([string]$Lock.profile.settingsManifest)
    Assert-WindowsCopilotSettingsShape -Lock $Lock -SettingsPath $settingsPath
    Assert-SourceCheckout -Root $HarnessSourceRoot -Source $Lock.components.core.source
    Assert-SourceCheckout -Root $ProviderSourceRoot -Source $Lock.components.searchProvider.source
    Test-ProviderDeploymentContract -Lock $Lock -SourceRoot $ProviderSourceRoot | Out-Null
    Test-LockedArtifact -Path $DesktopArtifactPath `
        -Sha256 ([string]$Lock.components.desktop.artifact.sha256) `
        -ExpectedName ([string]$Lock.components.desktop.artifact.name) | Out-Null
    Test-LockedArtifact -Path $GatewayArtifactPath `
        -Sha256 ([string]$Lock.components.gateway.artifact.sha256) `
        -ExpectedName ([string]$Lock.components.gateway.artifact.name) | Out-Null

    Invoke-PinnedPnpmCommands -PackageManager ([string]$Lock.components.core.package.packageManager) `
        -Commands @($Lock.components.core.build.commands) -WorkingDirectory $HarnessSourceRoot
    $coreRelease = Get-CoreReleaseArtifacts -Lock $Lock -Root $HarnessSourceRoot

    $providerLib = Join-Path $ProviderSourceRoot 'lib'
    if (Test-Path -LiteralPath $providerLib) { Remove-Item -LiteralPath $providerLib -Recurse -Force }
    Invoke-PinnedPnpmCommands -PackageManager ([string]$Lock.components.searchProvider.package.packageManager) `
        -Commands @($Lock.components.searchProvider.build.commands) -WorkingDirectory $ProviderSourceRoot
    $providerArtifact = Get-OnlyBuiltArtifact -Root $ProviderSourceRoot -Pattern ([string]$Lock.components.searchProvider.build.artifactPattern)
    Test-ProviderDeploymentContract -Lock $Lock -ArtifactPath $providerArtifact | Out-Null

    $operationRoot = New-BackupOperation -BackupRoot $BackupRoot -DshHome $DshHome
    $gatewayTarget = Join-Path $GatewayInstallRoot 'copilot2api.exe'
    Backup-DeploymentPath -Path $gatewayTarget -RelativePath 'gateway\copilot2api.exe' -OperationRoot $operationRoot

    $globalSpecs = @($Lock.globalInstall.packages | ForEach-Object { "$($_.name)@$($_.version)" })
    $globalSpecs += @($coreRelease.packages | ForEach-Object { [string]$_.path })
    $globalSpecs += $providerArtifact
    Invoke-LockedCommand -FilePath 'npm' -Arguments (@('install', '--global') + $globalSpecs) -WorkingDirectory $HarnessSourceRoot

    New-Item -ItemType Directory -Path $GatewayInstallRoot -Force | Out-Null
    Copy-Item -LiteralPath $GatewayArtifactPath -Destination $gatewayTarget -Force
    $desktopProcess = Start-Process -FilePath $DesktopArtifactPath `
        -ArgumentList @($Lock.components.desktop.install.arguments) -Wait -PassThru
    if (@($Lock.components.desktop.install.acceptedExitCodes) -notcontains [int]$desktopProcess.ExitCode) {
        throw "Desktop installer exited with code $($desktopProcess.ExitCode)."
    }

    $profileReceipt = Set-WindowsCopilotProfile -Lock $Lock -DshHome $DshHome `
        -NpmGlobalRoot $NpmGlobalRoot -ProviderArtifactPath $providerArtifact `
        -Catalog $Catalog -BackupRoot $BackupRoot -OperationRoot $operationRoot

    return [pscustomobject]@{
        mode = 'apply'
        deploymentId = [string]$Lock.deploymentId
        globalTransaction = [string]$Lock.globalInstall.transactionId
        coreArtifacts = @($coreRelease.packages)
        providerArtifactSha256 = (Get-FileHash -LiteralPath $providerArtifact -Algorithm SHA256).Hash.ToLowerInvariant()
        profile = $profileReceipt
        nextCheck = 'Re-run tools\install-windows-copilot.ps1 without -Apply after Desktop and copilot2api are running.'
    }
}

Export-ModuleMember -Function @(
    'Read-WindowsCopilotLock',
    'Test-WindowsCopilotLock',
    'Test-LockedArtifact',
    'Test-ProviderDeploymentContract',
    'Get-WindowsCopilotInstallPlan',
    'Get-WindowsCopilotRouteModels',
    'Set-PnpmAllowBuilds',
    'Set-WindowsCopilotRoutes',
    'Set-WindowsCopilotProfile',
    'Test-WindowsCopilotSearchResponse',
    'Test-WindowsCopilotComposedConfig',
    'Test-WindowsCopilotInstallation',
    'Invoke-WindowsCopilotApply'
)
