Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'DshCopilotBootstrap.psm1')

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

function Set-WindowsCopilotJsonFile {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$Path,
        [int]$Depth = 8
    )
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $temporaryPath = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $Value | ConvertTo-Json -Depth $Depth |
            Set-Content -LiteralPath $temporaryPath -Encoding UTF8
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
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
        'components.desktop.source.commit',
        'components.desktop.artifact.name',
        'components.desktop.artifact.sha256',
        'components.desktop.install.arguments',
        'components.desktop.install.acceptedExitCodes',
        'components.core.source.repository',
        'components.core.source.commit',
        'components.core.package.name',
        'components.core.package.version',
        'components.core.package.packageManager',
        'components.core.capabilities',
        'components.core.build.artifactDirectories',
        'components.core.install.script',
        'components.core.install.attestedFiles',
        'components.core.activation.environmentVariable',
        'components.core.activation.currentReceipt',
        'components.core.activation.operationReceipt',
        'components.core.activation.conflictShims',
        'components.core.activation.conflictShimSha256',
        'components.copilotIntegration.source.repository',
        'components.copilotIntegration.source.commit',
        'components.copilotIntegration.source.mergeCommit',
        'components.copilotIntegration.package.name',
        'components.copilotIntegration.package.version',
        'components.copilotIntegration.package.packageManager',
        'components.copilotIntegration.package.main',
        'components.copilotIntegration.package.types',
        'components.copilotIntegration.package.bundlePatch',
        'components.copilotIntegration.package.attestedFiles',
        'components.copilotIntegration.package.artifact.name',
        'components.copilotIntegration.package.artifact.sha256',
        'components.copilotIntegration.package.deploymentBaseline.id',
        'components.copilotIntegration.package.deploymentBaseline.kind',
        'components.copilotIntegration.package.deploymentBaseline.sourceCommitPolicy',
        'profile.lockManifest',
        'profile.legacyPhysicalPlugins',
        'profile.legacyCopilotIntegrations',
        'profile.requiredBundles',
        'acceptance.credential.record',
        'acceptance.credential.kind',
        'acceptance.credential.missingStatus',
        'acceptance.providerRoute.settingsNamespace',
        'acceptance.providerRoute.provider',
        'acceptance.providerRoute.forbiddenKeys',
        'acceptance.composedConfig.forbiddenMarkers',
        'acceptance.composedConfig.forbiddenActiveEntries',
        'acceptance.composedConfig.managedEntry.id',
        'acceptance.composedConfig.managedEntry.provider',
        'acceptance.composedConfig.managedEntry.hostEntry',
        'acceptance.composedConfig.managedEntry.settingsNamespace',
        'acceptance.composedConfig.managedEntry.searchProvider',
        'acceptance.traditionalSearch.provider',
        'acceptance.reasoning.responses',
        'acceptance.reasoning.anthropic',
        'acceptance.sandbox.gate',
        'acceptance.sandbox.capability',
        'migration.legacyGateway.name',
        'migration.legacyGateway.listenerPorts',
        'migration.legacyGateway.routeIds',
        'migration.legacyGateway.credentialReferences'
    )) {
        $value = $Lock
        foreach ($segment in $path.Split('.')) {
            $value = Get-LockProperty -InputObject $value -Name $segment
            if ($null -eq $value) { break }
        }
        Assert-LockValue -Value $value -Path $path
    }

    foreach ($commit in @(
        [string]$Lock.components.desktop.source.commit,
        [string]$Lock.components.core.source.commit,
        [string]$Lock.components.copilotIntegration.source.commit,
        [string]$Lock.components.copilotIntegration.source.mergeCommit
    )) {
        if ($commit -notmatch '^[0-9a-f]{40}$') { throw "Invalid locked commit: $commit" }
    }
    $attestedFiles = @($Lock.components.core.install.attestedFiles)
    $expectedAttestedFiles = [ordered]@{
        'root-shim' = 'dsh.cmd'
        'npm-shim' = 'node_modules\.bin\dsh.cmd'
        'entrypoint' = 'node_modules\@deepseek-ai\dsh\lib\bin.js'
    }
    if ($attestedFiles.Count -ne $expectedAttestedFiles.Count) {
        throw 'Core install contract must attest exactly three executable files.'
    }
    foreach ($role in $expectedAttestedFiles.Keys) {
        $matches = @($attestedFiles | Where-Object {
            [string]$_.role -ceq $role -and [string]$_.path -ceq $expectedAttestedFiles[$role]
        })
        if ($matches.Count -ne 1) {
            throw "Core install contract omits exact '$role' attestation."
        }
    }
    foreach ($sha in @(
        [string]$Lock.components.desktop.artifact.sha256,
        [string]$Lock.components.copilotIntegration.package.artifact.sha256
    )) {
        if ($sha -notmatch '^[0-9a-f]{64}$') { throw "Invalid locked artifact SHA-256: $sha" }
    }
    $providerAttestedFiles = @($Lock.components.copilotIntegration.package.attestedFiles)
    $expectedProviderAttestedFiles = @(
        [string]$Lock.components.copilotIntegration.package.main,
        'lib/client.js',
        'lib/remote.js'
    )
    if ($providerAttestedFiles.Count -ne $expectedProviderAttestedFiles.Count -or
        @($expectedProviderAttestedFiles | Where-Object {
            $providerAttestedFiles -notcontains $_
        }).Count -gt 0) {
        throw 'Provider installed-file contract must attest the exact server, client, and remote entrypoints.'
    }
    if (@($Lock.components.desktop.install.arguments).Count -eq 0 -or
        @($Lock.components.desktop.install.acceptedExitCodes).Count -eq 0) {
        throw 'Desktop install arguments and accepted exit codes must be locked.'
    }

    $requiredGlobal = @(
        '@deepseek-ai/cordis-plugin-hmr',
        '@deepseek-ai/cordis-plugin-timer',
        'node-addon-require-builtin'
    )
    $globalNames = @($Lock.globalInstall.packages | ForEach-Object { [string]$_.name })
    if ($globalNames.Count -ne $requiredGlobal.Count) {
        throw 'Global transaction must contain exactly the three reviewed loader packages.'
    }
    foreach ($name in $requiredGlobal) {
        if ($globalNames -notcontains $name) { throw "Global transaction omits '$name'." }
    }
    foreach ($package in @($Lock.globalInstall.packages)) {
        Assert-LockValue -Value $package.version -Path "globalInstall.packages.$($package.name).version"
    }

    $internalPluginNames = @(
        'dsh-tauri',
        'dsh-tauri-panel',
        'dsh-tauri-panel-extension',
        'dsh-tauri-ui',
        'dsh-tauri-worktree'
    )
    $internalPlugins = @($Lock.components.desktop.internalPlugins)
    if ($internalPlugins.Count -ne $internalPluginNames.Count) {
        throw 'Desktop must lock exactly five official internal plugins.'
    }
    foreach ($name in $internalPluginNames) {
        $matches = @($internalPlugins | Where-Object {
            [string]$_.name -ceq $name -and [string]$_.version -ceq '0.4.9' -and
            [string]$_.relativePath -ceq "resources\internal-plugins\$name"
        })
        if ($matches.Count -ne 1) { throw "Desktop internal-plugin contract omits '$name@0.4.9'." }
    }

    $copilotPackageName = [string]$Lock.components.copilotIntegration.package.name
    $requiredPlugins = @($internalPluginNames + $copilotPackageName)
    $plugins = @($Lock.profile.plugins)
    foreach ($name in $internalPluginNames) {
        $matches = @($plugins | Where-Object {
            [string]$_.name -ceq $name -and [string]$_.version -ceq '0.4.9' -and
            [string]$_.source -ceq 'desktop-internal' -and $_.materialize -eq $false -and
            $_.preserve -eq $true
        })
        if ($matches.Count -ne 1) { throw "Profile must preserve official Desktop plugin '$name' exactly once." }
    }
    $expectedLegacyPlugins = [ordered]@{
        'dsh-tauri' = '0.2.0'
        'dsh-tauri-ui' = '0.1.0'
        'dsh-tauri-worktree' = '0.1.0'
    }
    $legacyPlugins = @($Lock.profile.legacyPhysicalPlugins)
    if ($legacyPlugins.Count -ne $expectedLegacyPlugins.Count) {
        throw 'Profile migration must lock exactly three legacy physical plugins.'
    }
    foreach ($name in $expectedLegacyPlugins.Keys) {
        if (@($legacyPlugins | Where-Object {
            [string]$_.name -ceq $name -and [string]$_.version -ceq $expectedLegacyPlugins[$name]
        }).Count -ne 1) {
            throw "Profile migration omits the reviewed legacy plugin '$name@$($expectedLegacyPlugins[$name])'."
        }
    }
    $providerPlugins = @($plugins | Where-Object {
        [string]$_.name -ceq $copilotPackageName -and
        [string]$_.source -ceq 'built-artifact' -and $_.materialize -eq $true
    })
    if ($providerPlugins.Count -ne 1) {
        throw "Profile must physically materialize $copilotPackageName exactly once."
    }
    $legacyCopilotIntegrations = @($Lock.profile.legacyCopilotIntegrations)
    if ($legacyCopilotIntegrations.Count -ne 7 -or
        @($legacyCopilotIntegrations | Where-Object {
            [string]$_.name -ceq 'dsh-web-search-provider' -and
            [string]$_.version -ceq '0.2.2'
        }).Count -ne 1 -or
        @($legacyCopilotIntegrations | Where-Object {
            [string]$_.name -ceq 'dsh-web-search-provider' -and
            [string]$_.version -ceq '0.2.3-cloga.3'
        }).Count -ne 1 -or
        @($legacyCopilotIntegrations | Where-Object {
            [string]$_.name -ceq 'dsh-github-copilot' -and
            [string]$_.version -ceq '0.3.0-cloga.1'
        }).Count -ne 1 -or
        @($legacyCopilotIntegrations | Where-Object {
            [string]$_.name -ceq 'dsh-github-copilot' -and
            [string]$_.version -ceq '0.3.0-cloga.2'
        }).Count -ne 1 -or
        @($legacyCopilotIntegrations | Where-Object {
            [string]$_.name -ceq 'dsh-github-copilot' -and
            [string]$_.version -ceq '0.3.0-cloga.3'
        }).Count -ne 1 -or
        @($legacyCopilotIntegrations | Where-Object {
            [string]$_.name -ceq 'dsh-github-copilot' -and
            [string]$_.version -ceq '0.3.0-cloga.4'
        }).Count -ne 1 -or
        @($legacyCopilotIntegrations | Where-Object {
            [string]$_.name -ceq 'dsh-github-copilot' -and
            [string]$_.version -ceq '0.3.0-cloga.5'
        }).Count -ne 1) {
        throw 'Profile migration must detect the reviewed legacy search providers and Copilot plugins.'
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

    $listenerPorts = @($Lock.acceptance.listeners | ForEach-Object { [int]$_.port })
    if ($listenerPorts.Count -ne 1 -or $listenerPorts[0] -ne 3080) {
        throw 'Acceptance contract must require only the Desktop loopback listener on port 3080.'
    }
    foreach ($listener in @($Lock.acceptance.listeners)) {
        if ([string]$listener.host -ne '127.0.0.1') {
            throw "Listener '$($listener.name)' is not locked to IPv4 loopback."
        }
    }
    $imports = @($Lock.acceptance.loaderImports)
    foreach ($name in $requiredGlobal) {
        if ($imports -notcontains $name) { throw "Loader import contract omits '$name'." }
    }
    if (@($Lock.acceptance.composedConfig.requiredMarkers) -notcontains 'dsh-github-copilot' -or
        @($Lock.acceptance.composedConfig.requiredMarkers) -notcontains 'searchProvider: github-copilot-hosted') {
        throw 'Composed-config contract omits dsh-github-copilot.'
    }
    $composedEntries = @($Lock.acceptance.composedConfig.requiredEntries)
    $requiredComposedEntries = [ordered]@{
        web = '@deepseek-ai/dsh-web'
        'tool-web' = '@deepseek-ai/dsh-tool-web'
        'github-copilot' = 'dsh-github-copilot'
    }
    foreach ($id in $requiredComposedEntries.Keys) {
        if (@($composedEntries | Where-Object {
            [string]$_.id -ceq $id -and [string]$_.name -ceq $requiredComposedEntries[$id]
        }).Count -ne 1) {
            throw "Composed-config contract omits active '$id'."
        }
    }
    $forbiddenEntries = @($Lock.acceptance.composedConfig.forbiddenActiveEntries)
    if ($forbiddenEntries.Count -ne 1 -or $forbiddenEntries[0] -cne 'web-search-provider') {
        throw 'Composed-config contract must reject only the legacy web-search-provider entry.'
    }
    if (@($Lock.acceptance.composedConfig.forbiddenMarkers) -notcontains 'searchProvider: copilot-hosted') {
        throw 'Composed-config contract must reject the legacy copilot-hosted search provider id.'
    }
    $managedEntry = $Lock.acceptance.composedConfig.managedEntry
    if ([string]$managedEntry.id -ne 'github-copilot' -or
        [string]$managedEntry.provider -ne 'github-copilot' -or
        [string]$managedEntry.hostEntry -ne 'web' -or
        [string]$managedEntry.settingsNamespace -ne 'github-copilot' -or
        [string]$managedEntry.searchProvider -ne 'github-copilot-hosted' -or
        $managedEntry.enabled -ne $true) {
        throw 'Composed-config contract does not require the managed Copilot search provider.'
    }
    foreach ($forbidden in @('DEEPSEEK_API_KEY', 'provider-not-registered')) {
        if (@($Lock.acceptance.searchSmoke.forbiddenText) -notcontains $forbidden -or
            @($Lock.acceptance.traditionalSearch.forbiddenText) -notcontains $forbidden) {
            throw "Search acceptance contract must reject '$forbidden'."
        }
    }
    if ([string]$Lock.acceptance.traditionalSearch.provider -ne 'github-copilot-hosted' -or
        [string]$Lock.acceptance.traditionalSearch.requiredEvidenceProperty -ne 'sources') {
        throw 'Traditional Search contract must require github-copilot-hosted sources.'
    }
    if ([string]$Lock.acceptance.reasoning.responses -ne 'nonempty-only' -or
        [string]$Lock.acceptance.reasoning.anthropic -ne 'nonempty-only') {
        throw 'Reasoning contract must suppress empty Responses and Anthropic reasoning.'
    }
    if ([string]$Lock.acceptance.sandbox.gate -ne 'Require' -or
        [string]$Lock.acceptance.sandbox.capability -ne 'sandbox-same-and-narrower-no-op' -or
        [string]$Lock.acceptance.sandbox.sameAndNarrower -ne 'no-op' -or
        [int]$Lock.acceptance.sandbox.widerApprovalCount -ne 1) {
        throw 'Sandbox acceptance contract must require no-op same/narrower and one wider approval.'
    }
    $coreCapabilities = @($Lock.components.core.capabilities)
    $expectedCoreCapabilities = @(
        [string]$Lock.acceptance.sandbox.capability,
        'pi-ai-oauth-json-record-normalization'
    )
    if ($coreCapabilities.Count -ne $expectedCoreCapabilities.Count) {
        throw 'Core capability evidence must lock exactly the sandbox and pi-ai OAuth JSON normalization fixes.'
    }
    for ($index = 0; $index -lt $expectedCoreCapabilities.Count; $index++) {
        if ([string]$coreCapabilities[$index] -cne [string]$expectedCoreCapabilities[$index]) {
            throw 'Core capability evidence must lock exactly the sandbox and pi-ai OAuth JSON normalization fixes.'
        }
    }
    $activation = $Lock.components.core.activation
    if ([string]$activation.environmentVariable -cne 'DSH_CLI_PATH' -or
        [string]$activation.currentReceipt -cne 'core-activation-current.json' -or
        [string]$activation.operationReceipt -cne 'core-activation.json') {
        throw 'Core activation contract does not use the reviewed DSH_CLI_PATH receipt names.'
    }
    $conflictShims = @($activation.conflictShims)
    if ($conflictShims.Count -ne 3 -or
        $conflictShims -notcontains 'dsh' -or
        $conflictShims -notcontains 'dsh.cmd' -or
        $conflictShims -notcontains 'dsh.ps1') {
        throw 'Core activation must cover the three npm global dsh shims.'
    }
    foreach ($shim in $conflictShims) {
        $sha256 = [string](Get-LockProperty -InputObject $activation.conflictShimSha256 -Name ([string]$shim))
        if ($sha256 -notmatch '^[0-9a-f]{64}$') {
            throw "Core activation has no canonical npm shim SHA-256 for '$shim'."
        }
    }

    $baseline = $Lock.components.copilotIntegration.package.deploymentBaseline
    $expectedCapabilities = @(
        'client-module-loader-handoff',
        'strict-remote-result-codecs',
        'authorization-service-bootstrap',
        'models-provider-card-authorization',
        'reference-free-route-mutation',
        'shared-copilot-credential-refresh',
        'strict-json-oauth-grant-normalization',
        'direct-provider-hosted-search',
        'traditional-search-bridge',
        'dsh-supported-baselines-fail-loud-guard',
        'dsh-rc2-models-settings-fallback'
    )
    $lockedCapabilities = @($baseline.requiredCapabilities)
    if ($lockedCapabilities.Count -ne $expectedCapabilities.Count) {
        throw 'Copilot integration baseline must lock exactly eleven required capabilities.'
    }
    foreach ($capability in $expectedCapabilities) {
        if ($lockedCapabilities -notcontains $capability) {
            throw "Provider deployment baseline omits '$capability'."
        }
    }
    if ([int]$baseline.schemaVersion -ne 1 -or
        [string]$baseline.id -ne 'cloga.dsh-github-copilot' -or
        [string]$baseline.kind -ne 'standalone-dsh-plugin' -or
        [string]$baseline.sourceCommitPolicy -ne 'exact-external-pin' -or
        @($baseline.platforms) -notcontains 'windows' -or
        @($baseline.platforms) -notcontains 'linux' -or
        [string]$baseline.node -ne '>=22.0.0' -or
        [string]$baseline.dshRelease -ne '0.1.2-alpha.4' -or
        [string]$baseline.dshDevelopmentRelease -ne '0.1.1-rc.2' -or
        [string]$baseline.dshPeerRange -ne '^0.1.1-rc.2 || ^0.1.2-alpha.4' -or
        [string]$baseline.piAi -ne '^0.84.2' -or
        [string]$baseline.runtimeDependencies.'@deepseek-ai/dsh-authorization' -ne
            '^0.1.1-rc.2 || ^0.1.2-alpha.4' -or
        [string]$baseline.runtimeDependencies.zod -ne '^4.4.3') {
        throw 'Provider deployment baseline metadata does not match the reviewed contract.'
    }
    $legacyGateway = $Lock.migration.legacyGateway
    if ($legacyGateway.active -ne $false -or $legacyGateway.successCriteria -ne $false -or
        $legacyGateway.backupRequired -ne $true -or
        @($legacyGateway.listenerPorts) -notcontains 7777 -or
        @($legacyGateway.routeIds) -notcontains 'github-copilot' -or
        @($legacyGateway.credentialReferences) -notcontains 'COPILOT_GITHUB_TOKEN') {
        throw 'Legacy gateway detection must remain migration-only and backup-gated.'
    }
    if ([string]$Lock.acceptance.credential.record -ne 'llm-pi-ai/github-copilot' -or
        [string]$Lock.acceptance.credential.kind -ne 'grant' -or
        [string]$Lock.acceptance.credential.missingStatus -ne 'sign-in-required' -or
        $Lock.acceptance.credential.payloadMustNotBeReported -ne $true) {
        throw 'Credential acceptance must use the built-in llm-pi-ai Copilot grant without payload reporting.'
    }
    if (@($Lock.acceptance.providerRoute.forbiddenKeys).Count -ne 2 -or
        @($Lock.acceptance.providerRoute.forbiddenKeys) -notcontains 'baseURL' -or
        @($Lock.acceptance.providerRoute.forbiddenKeys) -notcontains 'apiKeyEnv') {
        throw 'Direct provider route contract must reject endpoint and API-key references.'
    }

    return [pscustomobject]@{
        valid = $true
        deploymentId = [string]$Lock.deploymentId
        requiredComponents = 3
        requiredPhysicalPlugins = 1
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

function Get-DeploymentPathItem {
    param([Parameter(Mandatory)][string]$Path)
    $fullPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path))
    try {
        return Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
    } catch {
        $parent = Split-Path -Parent $fullPath
        $leaf = Split-Path -Leaf $fullPath
        if (-not $parent -or -not (Test-Path -LiteralPath $parent -PathType Container)) {
            return $null
        }
        return @(Get-ChildItem -LiteralPath $parent -Force -ErrorAction Stop | Where-Object {
            [string]$_.Name -ceq $leaf
        } | Select-Object -First 1)
    }
}

function Test-DeploymentPathOverlap {
    param(
        [Parameter(Mandatory)][string]$Left,
        [Parameter(Mandatory)][string]$Right
    )
    $leftPath = (Resolve-DeploymentPath $Left).TrimEnd('\')
    $rightPath = (Resolve-DeploymentPath $Right).TrimEnd('\')
    return [bool](
        $leftPath -ieq $rightPath -or
        $leftPath.StartsWith($rightPath + '\', [StringComparison]::OrdinalIgnoreCase) -or
        $rightPath.StartsWith($leftPath + '\', [StringComparison]::OrdinalIgnoreCase)
    )
}

function Assert-NoReparsePointAncestor {
    param([Parameter(Mandatory)][string]$Path)

    $cursor = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path)).TrimEnd('\')
    while ($cursor) {
        $item = Get-DeploymentPathItem -Path $cursor
        if ($item) {
            if ([bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw "CoreInstallPrefix must not use reparse-point path '$cursor'."
            }
        }
        $parent = [IO.Path]::GetDirectoryName($cursor)
        if (-not $parent -or $parent -eq $cursor) { break }
        $cursor = $parent.TrimEnd('\')
    }
}

function Assert-CoreInstallPrefixIsolation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$CoreInstallPrefix,
        [Parameter(Mandatory)][string]$DshHome,
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$HarnessSourceRoot,
        [Parameter(Mandatory)][Alias('ProviderSourceRoot')][string]$CopilotIntegrationSourceRoot,
        [Parameter(Mandatory)][string]$NpmGlobalRoot,
        [Parameter(Mandatory)][string]$DesktopArtifactPath,
        [string]$GatewayArtifactPath,
        [string]$GatewayInstallRoot,
        [string]$DesktopExecutablePath
    )
    Assert-NoReparsePointAncestor -Path $CoreInstallPrefix
    $globalRoot = Resolve-DeploymentPath $NpmGlobalRoot
    if ((Split-Path -Leaf $globalRoot) -ine 'node_modules') {
        throw "The global npm root must end in 'node_modules': '$globalRoot'."
    }
    $canonicalDesktopPath = if ($env:LOCALAPPDATA) {
        Join-Path $env:LOCALAPPDATA 'Deepseek Harness Desktop\deepseek-harness-desktop.exe'
    } else { $null }
    $desktopPaths = @($canonicalDesktopPath, $DesktopExecutablePath | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_)
    } | ForEach-Object {
        [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$_))
    } | Select-Object -Unique)
    $protected = [Collections.Generic.List[object]]::new()
    foreach ($item in @(
        [pscustomobject]@{ name = 'DshHome'; path = $DshHome },
        [pscustomobject]@{
            name = 'profile'
            path = Join-Path (Resolve-DeploymentPath $DshHome) ([string]$Lock.profile.relativePath)
        },
        [pscustomobject]@{ name = 'BackupRoot'; path = $BackupRoot },
        [pscustomobject]@{ name = 'HarnessSourceRoot'; path = $HarnessSourceRoot },
        [pscustomobject]@{ name = 'CopilotIntegrationSourceRoot'; path = $CopilotIntegrationSourceRoot },
        [pscustomobject]@{ name = 'NpmGlobalRoot'; path = $globalRoot },
        [pscustomobject]@{ name = 'npm global prefix'; path = Split-Path -Parent $globalRoot },
        [pscustomobject]@{ name = 'DesktopArtifactPath'; path = $DesktopArtifactPath }
    )) {
        $protected.Add($item)
    }
    foreach ($desktopPath in $desktopPaths) {
        $desktopRoot = Split-Path -Parent $desktopPath
        $label = if ($desktopPath -ieq $canonicalDesktopPath) { 'canonical Desktop' } else { 'explicit Desktop' }
        $protected.Add([pscustomobject]@{ name = "$label executable"; path = $desktopPath })
        $protected.Add([pscustomobject]@{ name = "$label root"; path = $desktopRoot })
        $protected.Add([pscustomobject]@{
            name = "$label internal plugins"
            path = Join-Path $desktopRoot 'resources\internal-plugins'
        })
        foreach ($plugin in @($Lock.components.desktop.internalPlugins)) {
            $protected.Add([pscustomobject]@{
                name = "$label internal plugin '$($plugin.name)'"
                path = Join-Path $desktopRoot ([string]$plugin.relativePath)
            })
        }
    }
    foreach ($item in $protected) {
        Assert-NoReparsePointAncestor -Path ([string]$item.path)
        if (Test-DeploymentPathOverlap -Left $CoreInstallPrefix -Right ([string]$item.path)) {
            throw "CoreInstallPrefix must not overlap $($item.name): '$($item.path)'."
        }
    }
    return [pscustomobject]@{
        valid = $true
        prefix = Resolve-DeploymentPath $CoreInstallPrefix
        protectedPathCount = $protected.Count
    }
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
    $expected = $Lock.components.copilotIntegration.package
    # pnpm strips its development-only packageManager field from packed package.json.
    # The lock still owns the build tool/version; runtime payload validation must
    # compare only metadata that survives the published artifact.
    if ([string]$Package.name -ne [string]$expected.name -or
        [string]$Package.version -ne [string]$expected.version -or
        [string]$Package.main -ne [string]$expected.main -or
        [string]$Package.types -ne [string]$expected.types -or
        [string]$Package.dsh.bundle.patch -ne [string]$expected.bundlePatch) {
        throw 'Provider package metadata does not match the deployment lock.'
    }
    $contract = $expected.deploymentBaseline
    $authorizationPackage = '@deepseek-ai/dsh-authorization'
    $zodPackage = 'zod'
    $expectedAuthorizationRange = [string](Get-LockProperty `
        -InputObject $contract.runtimeDependencies -Name $authorizationPackage)
    $baselineAuthorizationRange = [string](Get-LockProperty `
        -InputObject $Baseline.supportedBaselines.runtimeDependencies -Name $authorizationPackage)
    $packageAuthorizationRange = [string](Get-LockProperty `
        -InputObject $Package.dependencies -Name $authorizationPackage)
    $expectedZodRange = [string](Get-LockProperty -InputObject $contract.runtimeDependencies -Name $zodPackage)
    $baselineZodRange = [string](Get-LockProperty `
        -InputObject $Baseline.supportedBaselines.runtimeDependencies -Name $zodPackage)
    $packageZodRange = [string](Get-LockProperty -InputObject $Package.dependencies -Name $zodPackage)
    if ([int]$Baseline.schemaVersion -ne [int]$contract.schemaVersion -or
        [string]$Baseline.baseline.id -ne [string]$contract.id -or
        [string]$Baseline.baseline.kind -ne [string]$contract.kind -or
        [string]$Baseline.baseline.sourceCommitPolicy -ne [string]$contract.sourceCommitPolicy -or
        [string]$Baseline.package.name -ne [string]$expected.name -or
        [string]$Baseline.package.version -ne [string]$expected.version -or
        @($Baseline.supportedBaselines.platforms).Count -ne @($contract.platforms).Count -or
        @($contract.platforms | Where-Object {
            @($Baseline.supportedBaselines.platforms) -notcontains [string]$_
        }).Count -gt 0 -or
        [string]$Baseline.supportedBaselines.node -ne [string]$contract.node -or
        [string]$Baseline.supportedBaselines.dsh.release -ne [string]$contract.dshRelease -or
        [string]$Baseline.supportedBaselines.dsh.developmentRelease -ne [string]$contract.dshDevelopmentRelease -or
        [string]$Baseline.supportedBaselines.dsh.peerRange -ne [string]$contract.dshPeerRange -or
        [string]$Baseline.supportedBaselines.piAi -ne [string]$contract.piAi -or
        $baselineAuthorizationRange -ne $expectedAuthorizationRange -or
        $packageAuthorizationRange -ne $expectedAuthorizationRange -or
        $baselineZodRange -ne $expectedZodRange -or
        $packageZodRange -ne $expectedZodRange) {
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

function Get-TarEntrySha256 {
    param(
        [Parameter(Mandatory)][string]$ArtifactPath,
        [Parameter(Mandatory)][string]$EntryPath
    )
    if (-not (Test-Path -LiteralPath $ArtifactPath -PathType Leaf)) {
        throw "Tar artifact not found: '$ArtifactPath'."
    }
    if ([IO.Path]::IsPathRooted($EntryPath) -or $EntryPath -match '(^|/)\.\.(/|$)') {
        throw "Unsafe tar entry path: '$EntryPath'."
    }
    $artifactArgument = '"' + ([IO.Path]::GetFullPath($ArtifactPath)).Replace('"', '\"') + '"'
    $entryArgument = '"' + $EntryPath.Replace('"', '\"') + '"'
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = 'tar'
    $start.Arguments = "-xOzf $artifactArgument $entryArgument"
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.CreateNoWindow = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        if (-not $process.Start()) { throw 'Could not start tar for provider payload attestation.' }
        $hash = $sha.ComputeHash($process.StandardOutput.BaseStream)
        $errorText = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw "Could not read '$EntryPath' from provider artifact: $errorText"
        }
        return ([BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
        $process.Dispose()
    }
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
            -Sha256 ([string]$Lock.components.copilotIntegration.package.artifact.sha256) `
            -ExpectedName ([string]$Lock.components.copilotIntegration.package.artifact.name) | Out-Null
        if ((Split-Path -Leaf $ArtifactPath) -ne [string]$Lock.components.copilotIntegration.package.artifact.name) {
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
        capabilities = @($Lock.components.copilotIntegration.package.deploymentBaseline.requiredCapabilities)
    }
}

function Test-CopilotIntegrationDeploymentContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [string]$SourceRoot,
        [string]$ArtifactPath
    )
    Test-ProviderDeploymentContract -Lock $Lock -SourceRoot $SourceRoot -ArtifactPath $ArtifactPath
}

function Get-WindowsCopilotInstallPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$DshHome,
        [Parameter(Mandatory)][string]$NpmGlobalRoot,
        [string]$HarnessSourceRoot,
        [Alias('ProviderSourceRoot')][string]$CopilotIntegrationSourceRoot,
        [string]$DesktopArtifactPath,
        [string]$GatewayArtifactPath,
        [string]$CoreInstallPrefix,
        [string]$BackupRoot
    )
    Test-WindowsCopilotLock -Lock $Lock | Out-Null
    $profileRoot = Join-Path (Resolve-DeploymentPath $DshHome) ([string]$Lock.profile.relativePath)
    $globalSpecs = @($Lock.globalInstall.packages | ForEach-Object {
        "$($_.name)@$($_.version)"
    })
    $globalSpecs += '<built-copilot-integration-tarball>'

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
            inputs = @($HarnessSourceRoot, $CopilotIntegrationSourceRoot)
        },
        [pscustomobject]@{
            id = 'verify-release-artifacts'
            action = 'sha256'
            changesSystem = $false
            inputs = @($DesktopArtifactPath)
        },
        [pscustomobject]@{
            id = 'build-core'
            action = 'pnpm'
            packageManager = [string]$Lock.components.core.package.packageManager
            changesSystem = $false
            inputs = @($HarnessSourceRoot)
        },
        [pscustomobject]@{
            id = 'build-copilot-integration'
            action = 'pnpm-windows-safe'
            packageManager = [string]$Lock.components.copilotIntegration.package.packageManager
            commands = @($Lock.components.copilotIntegration.build.commands)
            changesSystem = $false
            inputs = @($CopilotIntegrationSourceRoot)
        },
        [pscustomobject]@{
            id = 'install-core-with-receipt'
            action = 'release-install-local'
            packageManager = [string]$Lock.components.core.package.packageManager
            changesSystem = $true
            inputs = @($CoreInstallPrefix)
        },
        [pscustomobject]@{
            id = 'verify-installed-core-capability'
            action = 'receipt-bytes-and-sandbox-probe'
            changesSystem = $false
            inputs = @($CoreInstallPrefix)
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
            id = 'preserve-desktop-internal-plugins'
            action = 'attest-official-links'
            plugins = @($Lock.profile.plugins | Where-Object {
                [string]$_.source -eq 'desktop-internal'
            } | ForEach-Object { [string]$_.name })
            changesSystem = $false
            inputs = @($profileRoot)
        },
        [pscustomobject]@{
            id = 'materialize-copilot-plugin'
            action = 'physical-copy'
            plugins = @($Lock.profile.plugins | Where-Object {
                $_.materialize -eq $true
            } | ForEach-Object { [string]$_.name })
            changesSystem = $true
            inputs = @($NpmGlobalRoot, $profileRoot)
        },
        [pscustomobject]@{
            id = 'activate-fork-core'
            action = 'persist-dsh-cli-path-and-quarantine-official-global-shims'
            changesSystem = $true
            inputs = @($CoreInstallPrefix, $BackupRoot)
        },
        [pscustomobject]@{
            id = 'verify-installation'
            action = 'acceptance'
            checks = @('official-desktop-plugin-links', 'plugin-bytes', 'profile-bundle', 'reference-free-provider-route', 'credential-record-metadata', 'allow-builds', 'loader-imports', 'loopback-3080', 'composed-config', 'search-contract', 'core-receipt-repository-commit-bytes', 'persisted-dsh-cli-path', 'global-dsh-conflict-free', 'sandbox-same-narrower-zero-approval', 'desktop-backend-command-line')
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
        $arguments = @('--yes', "pnpm@$version") + @($command | ForEach-Object {
            ([string]$_).Replace('{sourceRoot}', (Resolve-DeploymentPath $WorkingDirectory))
        })
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
    $relativeDirectories = @($Lock.components.core.build.artifactDirectories | ForEach-Object { [string]$_ })
    if ($relativeDirectories.Count -ne 3) {
        throw 'Core release must define DSH, vendor, and landlock artifact directories.'
    }
    $directories = @($relativeDirectories | ForEach-Object { Join-Path $Root $_ })
    $directory = $directories[0]
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
        $entries = @(& tar -tzf $path 2>$null | Where-Object { $_ -and -not $_.EndsWith('/') })
        if ($LASTEXITCODE -ne 0 -or $entries.Count -eq 0) {
            throw "Core release artifact has no verifiable file list: $path"
        }
        $packages.Add([pscustomobject]@{
            name = [string]$metadata.name
            version = [string]$metadata.version
            path = $path
            sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            files = $entries.Count
        })
    }
    foreach ($additionalDirectory in $directories[1..($directories.Count - 1)]) {
        $artifacts = @(Get-ChildItem -LiteralPath $additionalDirectory -Filter '*.tgz' -File)
        if ($artifacts.Count -eq 0) {
            throw "Core release artifact directory is empty: $additionalDirectory"
        }
        foreach ($artifact in $artifacts) {
            $metadata = Read-TarJson -ArtifactPath $artifact.FullName -RelativePath 'package.json'
            $entries = @(& tar -tzf $artifact.FullName 2>$null | Where-Object { $_ -and -not $_.EndsWith('/') })
            if ($LASTEXITCODE -ne 0 -or $entries.Count -eq 0) {
                throw "Core release artifact has no verifiable file list: $($artifact.FullName)"
            }
            $packages.Add([pscustomobject]@{
                name = [string]$metadata.name
                version = [string]$metadata.version
                path = $artifact.FullName
                sha256 = (Get-FileHash -LiteralPath $artifact.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                files = $entries.Count
            })
        }
    }
    $packageNames = @($packages | ForEach-Object { [string]$_.name })
    if (@($packageNames | Select-Object -Unique).Count -ne $packageNames.Count) {
        throw 'Core release artifact directories contain duplicate package names.'
    }
    $rootPackages = @($packages | Where-Object {
        $_.name -eq [string]$Lock.components.core.build.rootPackage -and
        $_.version -eq [string]$Lock.components.core.package.version
    })
    if ($rootPackages.Count -ne 1) {
        throw 'Core release family does not contain the locked @deepseek-ai/dsh package.'
    }
    return [pscustomobject]@{ directory = $directory; directories = @($directories); packages = @($packages) }
}

function Install-WindowsCopilotCoreRelease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$NpmGlobalRoot,
        [Parameter(Mandatory)][string]$CoreInstallPrefix,
        [Parameter(Mandatory)]$CoreRelease
    )
    $globalRoot = Resolve-DeploymentPath $NpmGlobalRoot
    if ((Split-Path -Leaf $globalRoot) -ine 'node_modules') {
        throw "The global npm root must end in 'node_modules' for receipt installation: '$globalRoot'."
    }
    $globalPrefix = Split-Path -Parent $globalRoot
    $prefix = Resolve-DeploymentPath $CoreInstallPrefix
    if ($prefix -ieq $globalPrefix) {
        throw 'CoreInstallPrefix must be a dedicated prefix, not the global npm prefix.'
    }
    $releaseDirectories = @($CoreRelease.directories)
    if ($releaseDirectories.Count -ne 3) {
        throw 'Core release installation requires DSH, vendor, and landlock artifact directories.'
    }
    $version = ([string]$Lock.components.core.package.packageManager).Split('@')[-1]
    $arguments = @(
        '--yes',
        "pnpm@$version",
        'run',
        [string]$Lock.components.core.install.script,
        '--',
        '--from', [string]$releaseDirectories[0],
        '--from', [string]$releaseDirectories[1],
        '--from', [string]$releaseDirectories[2],
        '--prefix', $prefix,
        '--expect-commit',
        [string]$Lock.components.core.source.commit,
        '--expect-version',
        [string]$Lock.components.core.package.version
    )
    Invoke-LockedCommand -FilePath 'npx' -Arguments $arguments -WorkingDirectory $SourceRoot

    $cliPath = Join-Path $prefix 'dsh.cmd'
    $receiptPath = Join-Path $prefix 'dsh-local-install.json'
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
        throw "The Core installer did not produce its receipt: '$receiptPath'."
    }
    $receipt = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $installedFiles = @($Lock.components.core.install.attestedFiles | ForEach-Object {
        $relativePath = [string]$_.path
        $fullPath = [IO.Path]::GetFullPath((Join-Path $prefix $relativePath))
        $prefixBoundary = $prefix.TrimEnd('\') + '\'
        if (-not $fullPath.StartsWith($prefixBoundary, [StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            throw "Core installed-file attestation target is missing or outside the prefix: '$relativePath'."
        }
        [ordered]@{
            role = [string]$_.role
            path = $relativePath
            sha256 = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    })
    $receipt | Add-Member -NotePropertyName installedFiles -NotePropertyValue $installedFiles -Force
    $temporaryReceipt = $receiptPath + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporaryReceipt -Encoding UTF8
        Move-Item -LiteralPath $temporaryReceipt -Destination $receiptPath -Force
    } finally {
        if (Test-Path -LiteralPath $temporaryReceipt) {
            Remove-Item -LiteralPath $temporaryReceipt -Force
        }
    }
    $info = Resolve-DshCliInfo -DshCliPath $cliPath -ExpectedRepository 'cloga/deepseek-harness'
    if ($info.commitSha -ine [string]$Lock.components.core.source.commit -or
        $info.version -ne [string]$Lock.components.core.package.version) {
        throw 'The Core installer receipt does not match the locked source commit and version.'
    }
    return $info
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
    if (-not (Get-DeploymentPathItem -Path $Path)) { return }
    $destination = Join-Path $OperationRoot $RelativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $Path -Destination $destination -Recurse -Force
}

function Restore-DeploymentSnapshots {
    param(
        [Parameter(Mandatory)][object[]]$Snapshots,
        [Parameter(Mandatory)][string]$OperationRoot,
        [Parameter(Mandatory)][string]$NodeModulesRoot
    )
    for ($index = $Snapshots.Count - 1; $index -ge 0; $index--) {
        $snapshot = $Snapshots[$index]
        $target = [string]$snapshot.path
        if (Get-DeploymentPathItem -Path $target) {
            if ([bool]$snapshot.pluginTarget) {
                Remove-ProfilePluginTarget -Target $target -NodeModulesRoot $NodeModulesRoot
            } else {
                Remove-Item -LiteralPath $target -Recurse -Force
            }
        }
        if ([bool]$snapshot.existed) {
            $source = Join-Path $OperationRoot ([string]$snapshot.relativePath)
            if (-not (Test-Path -LiteralPath $source)) {
                throw "Deployment rollback backup is missing: $source"
            }
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $target -Recurse -Force
        } elseif ([string](Get-LockProperty -InputObject $snapshot -Name 'linkTarget')) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            New-Item -ItemType Junction -Path $target `
                -Target ([string](Get-LockProperty -InputObject $snapshot -Name 'linkTarget')) `
                -ErrorAction Stop | Out-Null
        }
    }
}

function Remove-ProfilePluginTarget {
    param(
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$NodeModulesRoot
    )
    $item = Get-DeploymentPathItem -Path $Target
    if (-not $item) { return }
    $root = [IO.Path]::GetFullPath($NodeModulesRoot).TrimEnd('\') + '\'
    $resolvedTarget = [IO.Path]::GetFullPath($Target)
    if (-not $resolvedTarget.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Plugin target escapes profile node_modules: $Target"
    }
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
    throw 'Get-WindowsCopilotRouteModels is retired: the direct baseline uses the account-available built-in pi-ai route.'
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
        $Catalog
    )
    Test-WindowsCopilotLock -Lock $Lock | Out-Null
    return Remove-DshLegacyCopilotSettings -Path $SettingsPath
}

function Get-WindowsCopilotInternalPluginStates {
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$ProfileRoot,
        [Parameter(Mandatory)][string]$DesktopExecutablePath
    )
    $desktopRoot = Split-Path -Parent (Resolve-DeploymentPath $DesktopExecutablePath)
    foreach ($plugin in @($Lock.components.desktop.internalPlugins)) {
        $path = Join-Path $ProfileRoot (Join-Path 'node_modules' ([string]$plugin.name))
        $expectedTarget = Resolve-DeploymentPath (Join-Path $desktopRoot ([string]$plugin.relativePath))
        $pathItem = Get-DeploymentPathItem -Path $path
        $pathExists = $null -ne $pathItem
        $exists = Test-Path -LiteralPath (Join-Path $path 'package.json') -PathType Leaf
        $reparse = $false
        $target = $null
        $packageName = $null
        $version = $null
        if ($pathExists) {
            $item = $pathItem
            $reparse = [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
            if ($reparse) {
                $targetProperty = $item.PSObject.Properties['Target']
                $rawTarget = if ($targetProperty) { @($targetProperty.Value) | Select-Object -First 1 } else { $null }
                if ($rawTarget) {
                    $target = if ([IO.Path]::IsPathRooted([string]$rawTarget)) {
                        Resolve-DeploymentPath ([string]$rawTarget)
                    } else {
                        Resolve-DeploymentPath (Join-Path (Split-Path -Parent $path) ([string]$rawTarget))
                    }
                }
            }
            try {
                $metadata = Get-Content -LiteralPath (Join-Path $path 'package.json') -Raw -Encoding UTF8 | ConvertFrom-Json
                $packageName = [string]$metadata.name
                $version = [string]$metadata.version
            } catch { }
        }
        [pscustomobject]@{
            name = [string]$plugin.name
            path = $path
            pathExists = [bool]$pathExists
            exists = [bool]$exists
            reparse = $reparse
            target = $target
            expectedTarget = $expectedTarget
            targetValid = [bool]($target -and $target -ieq $expectedTarget)
            packageName = $packageName
            version = $version
            versionValid = [bool]($version -eq [string]$plugin.version)
            valid = [bool]($exists -and $reparse -and $target -and $target -ieq $expectedTarget -and
                $version -eq [string]$plugin.version)
        }
    }
}

function Get-WindowsCopilotProfileMigrationPlan {
        param(
            [Parameter(Mandatory)]$Lock,
            [Parameter(Mandatory)][string]$DshHome,
            [Parameter(Mandatory)][string]$DesktopExecutablePath
        )
        $home = Resolve-DeploymentPath $DshHome
        $profileRoot = Join-Path $home ([string]$Lock.profile.relativePath)
        $packagePath = Join-Path $profileRoot ([string]$Lock.profile.packageManifest)
        $profile = if (Test-Path -LiteralPath $packagePath -PathType Leaf) {
            Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | ConvertFrom-Json
        } else { $null }
        $dependencies = if ($profile) { Get-LockProperty -InputObject $profile -Name 'dependencies' } else { $null }
        $legacyByName = @{}
        foreach ($legacy in @($Lock.profile.legacyPhysicalPlugins)) {
            $legacyByName[[string]$legacy.name] = $legacy
        }
        $states = @(Get-WindowsCopilotInternalPluginStates -Lock $Lock -ProfileRoot $profileRoot `
            -DesktopExecutablePath $DesktopExecutablePath)
        $legacyTargets = [Collections.Generic.List[object]]::new()
        $dependenciesToRemove = [Collections.Generic.List[string]]::new()
        foreach ($state in $states) {
            $dependencyProperty = if ($dependencies) {
                $dependencies.PSObject.Properties[[string]$state.name]
            } else { $null }
            $legacy = $legacyByName[[string]$state.name]
            $dependencyIsLegacy = [bool](
                $legacy -and $dependencyProperty -and
                [string]$dependencyProperty.Value -ceq [string]$legacy.version
            )
            if ($dependencyProperty -and -not $dependencyIsLegacy) {
                throw "Profile dependency '$($state.name)' is not a reviewed legacy dependency."
            }
            if ($dependencyIsLegacy) {
                $dependenciesToRemove.Add([string]$state.name)
            }
            if ($state.valid -or -not $state.pathExists) { continue }
            $legacyPhysical = [bool](
                $legacy -and -not $state.reparse -and $state.exists -and
                [string]$state.packageName -ceq [string]$state.name -and
                [string]$state.version -ceq [string]$legacy.version -and
                $dependencyIsLegacy
            )
            if (-not $legacyPhysical) {
                throw "Official Desktop internal-plugin link is missing or invalid: $($state.name)."
            }
            $legacyTargets.Add([pscustomobject]@{
                name = [string]$state.name
                path = [string]$state.path
                version = [string]$state.version
            })
        }
        if (($legacyTargets.Count -gt 0 -or $dependenciesToRemove.Count -gt 0) -and
            ($legacyTargets.Count -ne $legacyByName.Count -or
            $dependenciesToRemove.Count -ne $legacyByName.Count)) {
            throw 'Profile does not match the complete reviewed legacy physical-plugin state.'
        }
        $legacyCopilotTargets = [Collections.Generic.List[object]]::new()
        foreach ($legacyIntegration in @($Lock.profile.legacyCopilotIntegrations)) {
            $name = [string]$legacyIntegration.name
            $dependencyProperty = if ($dependencies) { $dependencies.PSObject.Properties[$name] } else { $null }
            if (-not $dependencyProperty) { continue }
            $dependency = [string]$dependencyProperty.Value
            $artifactPattern = '^.*[/\\]' +
                [regex]::Escape([string]$legacyIntegration.artifactPattern).Replace('\*', '.*') + '$'
            $versionDependency = $dependency -ceq [string]$legacyIntegration.version
            $artifactDependency = $dependency -match $artifactPattern
            if (-not $versionDependency -and -not $artifactDependency) { continue }
            if ($dependenciesToRemove -notcontains $name) { $dependenciesToRemove.Add($name) }
            $target = Join-Path $profileRoot (Join-Path 'node_modules' $name)
            if (Test-Path -LiteralPath $target) {
                $metadataPath = Join-Path $target 'package.json'
                if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
                    throw "Legacy Copilot integration '$name' has no package metadata."
                }
                $metadata = Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ([string]$metadata.name -cne $name -or
                    [string]$metadata.version -cne [string]$legacyIntegration.version) {
                    throw "Legacy Copilot integration '$name' does not match the reviewed migration contract."
                }
                $legacyCopilotTargets.Add([pscustomobject]@{
                    name = $name
                    path = $target
                    version = [string]$metadata.version
                })
            }
        }
        foreach ($legacyName in @($Lock.profile.legacyCopilotIntegrations.name | Select-Object -Unique)) {
            $dependencyProperty = if ($dependencies) {
                $dependencies.PSObject.Properties[[string]$legacyName]
            } else { $null }
            $target = Join-Path $profileRoot (Join-Path 'node_modules' ([string]$legacyName))
            if ([string]$legacyName -ceq [string]$Lock.components.copilotIntegration.package.name -and
                $dependencyProperty -and
                [string]$dependencyProperty.Value -match (
                    [regex]::Escape([string]$Lock.components.copilotIntegration.source.commit) + '[/\\]' +
                    [regex]::Escape([string]$Lock.components.copilotIntegration.package.artifact.name) + '$'
                )) {
                continue
            }
            if ($dependencyProperty -and $dependenciesToRemove -notcontains [string]$legacyName) {
                throw "Profile dependency '$legacyName' is not a reviewed legacy Copilot integration."
            }
            if ((Test-Path -LiteralPath $target) -and
                @($legacyCopilotTargets | Where-Object { $_.name -ceq [string]$legacyName }).Count -eq 0) {
                throw "Physical legacy Copilot integration '$legacyName' is not covered by the migration contract."
            }
        }
        return [pscustomobject]@{
            profileRoot = $profileRoot
            packagePath = $packagePath
            internalStates = $states
            legacyTargets = @($legacyTargets)
            legacyCopilotTargets = @($legacyCopilotTargets)
            dependenciesToRemove = @($dependenciesToRemove)
        }
}

function Set-WindowsCopilotProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$DshHome,
        [Parameter(Mandatory)][string]$NpmGlobalRoot,
        [Parameter(Mandatory)][Alias('ProviderArtifactPath')][string]$CopilotIntegrationArtifactPath,
        $Catalog,
        [Parameter(Mandatory)][string]$BackupRoot,
        [string]$DesktopExecutablePath,
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
    $credentialsPath = Join-Path $home '.credentials.yaml'
    $profilePatchPath = Join-Path $profileRoot 'cordis.patch.yml'
    $nodeModules = Join-Path $profileRoot 'node_modules'
    if (-not $DesktopExecutablePath) {
        $DesktopExecutablePath = Join-Path $env:LOCALAPPDATA 'Deepseek Harness Desktop\deepseek-harness-desktop.exe'
    }
    $migration = Get-WindowsCopilotProfileMigrationPlan -Lock $Lock -DshHome $home `
        -DesktopExecutablePath $DesktopExecutablePath
    $internalBefore = @($migration.internalStates)
    Assert-WindowsCopilotSettingsShape -Lock $Lock -SettingsPath $settingsPath
    if (-not $OperationRoot) {
        $OperationRoot = New-BackupOperation -BackupRoot $BackupRoot -DshHome $home
    }

    $artifactName = Split-Path -Leaf $CopilotIntegrationArtifactPath
    $artifactRoot = Join-Path $home (Join-Path 'artifacts' ([string]$Lock.components.copilotIntegration.source.commit))
    $lockedArtifact = Join-Path $artifactRoot $artifactName
    $snapshots = [Collections.Generic.List[object]]::new()
    foreach ($snapshot in @(
        [pscustomobject]@{ path = $packagePath; relativePath = 'profile\package.json'; pluginTarget = $false },
        [pscustomobject]@{ path = $workspacePath; relativePath = 'profile\pnpm-workspace.yaml'; pluginTarget = $false },
        [pscustomobject]@{ path = $lockPath; relativePath = 'profile\pnpm-lock.yaml'; pluginTarget = $false },
        [pscustomobject]@{ path = $settingsPath; relativePath = 'config\settings.yaml'; pluginTarget = $false },
        [pscustomobject]@{ path = $credentialsPath; relativePath = 'config\credentials.yaml'; pluginTarget = $false },
        [pscustomobject]@{ path = $profilePatchPath; relativePath = 'profile\cordis.patch.yml'; pluginTarget = $false },
        [pscustomobject]@{ path = $lockedArtifact; relativePath = 'artifacts\provider.tgz'; pluginTarget = $false }
    )) {
        $snapshot | Add-Member -NotePropertyName existed -NotePropertyValue (Test-Path -LiteralPath $snapshot.path)
        $snapshots.Add($snapshot)
        Backup-DeploymentPath -Path $snapshot.path -RelativePath $snapshot.relativePath -OperationRoot $OperationRoot
    }
    foreach ($plugin in @($Lock.profile.plugins | Where-Object { $_.materialize -eq $true })) {
        $target = Join-Path $nodeModules ([string]$plugin.name)
        $relativePath = Join-Path 'plugins' ([string]$plugin.name)
        $snapshots.Add([pscustomobject]@{
            path = $target
            relativePath = $relativePath
            pluginTarget = $true
            existed = (Test-Path -LiteralPath $target)
        })
        Backup-DeploymentPath -Path $target -RelativePath $relativePath -OperationRoot $OperationRoot
    }
    foreach ($legacyTarget in @($migration.legacyCopilotTargets)) {
        $snapshots.Add([pscustomobject]@{
            path = [string]$legacyTarget.path
            relativePath = Join-Path 'plugins' ([string]$legacyTarget.name)
            pluginTarget = $true
            existed = $true
        })
        Backup-DeploymentPath -Path ([string]$legacyTarget.path) `
            -RelativePath (Join-Path 'plugins' ([string]$legacyTarget.name)) -OperationRoot $OperationRoot
    }
    foreach ($state in $internalBefore) {
        $legacyTarget = @($migration.legacyTargets | Where-Object name -CEQ ([string]$state.name))
        $snapshots.Add([pscustomobject]@{
            path = [string]$state.path
            relativePath = Join-Path 'plugins' ([string]$state.name)
            pluginTarget = $true
            existed = [bool]($legacyTarget.Count -eq 1)
            linkTarget = if ($state.valid) { [string]$state.expectedTarget } else { $null }
        })
        if ($legacyTarget.Count -eq 1) {
            Backup-DeploymentPath -Path $state.path -RelativePath (Join-Path 'plugins' ([string]$state.name)) `
                -OperationRoot $OperationRoot
        }
    }

    try {
    New-Item -ItemType Directory -Path $profileRoot, $nodeModules -Force | Out-Null
    New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
    Copy-Item -LiteralPath $CopilotIntegrationArtifactPath -Destination $lockedArtifact -Force
    foreach ($legacyTarget in @($migration.legacyTargets)) {
        Remove-ProfilePluginTarget -Target ([string]$legacyTarget.path) -NodeModulesRoot $nodeModules
    }
    foreach ($legacyTarget in @($migration.legacyCopilotTargets)) {
        Remove-ProfilePluginTarget -Target ([string]$legacyTarget.path) -NodeModulesRoot $nodeModules
    }

    $profile = if (Test-Path -LiteralPath $packagePath -PathType Leaf) {
        Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | ConvertFrom-Json
    } else {
        [pscustomobject]@{ name = 'dsh-profile-web'; private = $true }
    }
    if (-not (Get-LockProperty -InputObject $profile -Name 'dependencies')) {
        Set-ObjectProperty -Object $profile -Name 'dependencies' -Value ([pscustomobject]@{})
    }
    foreach ($name in @($migration.dependenciesToRemove)) {
        $profile.dependencies.PSObject.Properties.Remove([string]$name)
    }
    $dependencyPath = "file:../../artifacts/$($Lock.components.copilotIntegration.source.commit)/$artifactName"
    Set-ObjectProperty -Object $profile.dependencies -Name ([string]$Lock.components.copilotIntegration.package.name) -Value $dependencyPath
    if (-not (Get-LockProperty -InputObject $profile -Name 'dsh')) {
        Set-ObjectProperty -Object $profile -Name 'dsh' -Value ([pscustomobject]@{})
    }
    if (-not (Get-LockProperty -InputObject $profile.dsh -Name 'profile')) {
        Set-ObjectProperty -Object $profile.dsh -Name 'profile' -Value ([pscustomobject]@{})
    }
    $bundles = @((Get-LockProperty -InputObject $profile.dsh.profile -Name 'bundles'))
    foreach ($legacyIntegration in @($Lock.profile.legacyCopilotIntegrations)) {
        $bundles = @($bundles | Where-Object { $_ -ne [string]$legacyIntegration.name })
    }
    foreach ($requiredBundle in @($Lock.profile.requiredBundles)) {
        $bundles = @($bundles | Where-Object { $_ -ne [string]$requiredBundle })
        $bundles += [string]$requiredBundle
    }
    Set-ObjectProperty -Object $profile.dsh.profile -Name 'bundles' -Value $bundles
    $profile | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $packagePath -Encoding UTF8

    Set-PnpmAllowBuilds -Path $workspacePath -Packages @($Lock.profile.allowBuilds)
    Remove-DshLegacyCopilotSettings -Path $settingsPath | Out-Null
    Remove-DshLegacyCopilotCredentialReference -Path $credentialsPath | Out-Null
    Set-DshCopilotProfilePatch -Path $profilePatchPath | Out-Null

    if (-not $SkipPackageInstall) {
        Invoke-PinnedPnpmCommands -PackageManager ([string]$Lock.components.copilotIntegration.package.packageManager) `
            -Commands @(, @('install', '--no-frozen-lockfile')) -WorkingDirectory $profileRoot
    }

    foreach ($plugin in @($Lock.profile.plugins | Where-Object { $_.materialize -eq $true })) {
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
    $internalCurrent = @(Get-WindowsCopilotInternalPluginStates -Lock $Lock -ProfileRoot $profileRoot `
        -DesktopExecutablePath $DesktopExecutablePath)
    foreach ($plugin in @($internalCurrent)) {
        if ($plugin.exists) {
            if (-not $plugin.valid) {
                throw "Profile package install changed an official Desktop internal-plugin link: $($plugin.name)."
            }
            continue
        }
        if (-not (Test-Path -LiteralPath (Join-Path $plugin.expectedTarget 'package.json') -PathType Leaf)) {
            throw "Official Desktop internal plugin is missing: $($plugin.expectedTarget)."
        }
        New-Item -ItemType Junction -Path $plugin.path -Target $plugin.expectedTarget -ErrorAction Stop | Out-Null
    }
    $internalAfter = @(Get-WindowsCopilotInternalPluginStates -Lock $Lock -ProfileRoot $profileRoot `
        -DesktopExecutablePath $DesktopExecutablePath)
    $invalidInternalAfter = @($internalAfter | Where-Object { -not $_.valid })
    if ($invalidInternalAfter.Count -gt 0) {
        throw "Profile package install changed an official Desktop internal-plugin link: $($invalidInternalAfter.name -join ', ')."
    }

    $receipt = [pscustomobject]@{
        deploymentId = [string]$Lock.deploymentId
        createdUtc = (Get-Date).ToUniversalTime().ToString('o')
        copilotIntegrationArtifact = [pscustomobject]@{
            path = $lockedArtifact
            sha256 = (Get-FileHash -LiteralPath $lockedArtifact -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        providerArtifact = [pscustomobject]@{
            path = $lockedArtifact
            sha256 = (Get-FileHash -LiteralPath $lockedArtifact -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        internalPlugins = @($internalAfter)
        backupRoot = $OperationRoot
    }
    $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OperationRoot 'receipt.json') -Encoding UTF8
    return $receipt
    } catch {
        $failure = $_
        try {
            Restore-DeploymentSnapshots -Snapshots @($snapshots) -OperationRoot $OperationRoot `
                -NodeModulesRoot $nodeModules
        } catch {
            throw "Profile migration failed and rollback was incomplete: $($failure.Exception.Message) Rollback error: $($_.Exception.Message)"
        }
        throw $failure
    }
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
    $sourceEvidence = $false
    $citationEvidence = $false
    foreach ($item in @($response.output)) {
        $action = Get-LockProperty -InputObject $item -Name 'action'
        [object[]]$sources = if ($action) { @(Get-LockProperty -InputObject $action -Name 'sources') } else { @() }
        if ([string]$item.type -eq 'web_search_call' -and $sources.Count -gt 0) {
            $sourceEvidence = $true
        }
        $contentItems = Get-LockProperty -InputObject $item -Name 'content'
        foreach ($content in @($contentItems | Where-Object { $null -ne $_ })) {
            $annotations = Get-LockProperty -InputObject $content -Name 'annotations'
            foreach ($annotation in @($annotations | Where-Object { $null -ne $_ })) {
                if ([string]$annotation.type -eq 'url_citation' -and $annotation.url) {
                    $citationEvidence = $true
                }
            }
        }
    }
    if (-not $sourceEvidence -or -not $citationEvidence) {
        throw 'Search smoke response must contain native web_search_call sources and a URL citation.'
    }
    $traditional = Get-LockProperty -InputObject $response -Name 'traditionalSearch'
    if (-not $traditional -or
        [string]$traditional.provider -ne [string]$Lock.acceptance.traditionalSearch.provider -or
        @($traditional.sources).Count -eq 0) {
        throw 'Traditional Search evidence is missing github-copilot-hosted sources.'
    }
    $session = Get-LockProperty -InputObject $response -Name 'cordisSession'
    $mounted = if ($session) { @($session.mounted) } else { @() }
    foreach ($id in @($Lock.acceptance.composedConfig.requiredEntries.id)) {
        if ($mounted -notcontains $id) { throw "Cordis session did not mount '$id'." }
    }
    $reasoning = Get-LockProperty -InputObject $response -Name 'reasoning'
    $responsesReasoning = if ($reasoning) { Get-LockProperty -InputObject $reasoning -Name 'responses' } else { $null }
    $anthropicReasoning = if ($reasoning) { Get-LockProperty -InputObject $reasoning -Name 'anthropic' } else { $null }
    if (-not $responsesReasoning -or -not $anthropicReasoning) {
        throw 'Responses or Anthropic reasoning regression evidence is missing.'
    }
    $responsesEmptyProperty = $responsesReasoning.PSObject.Properties['emptyItems']
    $responsesEmptyOutputProperty = $responsesReasoning.PSObject.Properties['emittedThinkCards']
    if (-not $responsesEmptyProperty -or -not $responsesEmptyOutputProperty -or
        $responsesEmptyProperty.Value -isnot [Array] -or
        $responsesEmptyOutputProperty.Value -isnot [Array]) {
        throw 'Empty Responses reasoning regression properties are missing.'
    }
    $responsesEmptyItems = @($responsesEmptyProperty.Value)
    $responsesInvalidEmptyItems = @($responsesEmptyItems | Where-Object {
        $contentProperty = $_.PSObject.Properties['content']
        [string](Get-LockProperty -InputObject $_ -Name 'type') -cne 'reasoning' -or
        -not $contentProperty -or @($contentProperty.Value).Count -ne 0
    })
    if ($responsesEmptyItems.Count -eq 0 -or
        $responsesInvalidEmptyItems.Count -gt 0 -or
        @($responsesEmptyOutputProperty.Value).Count -ne 0) {
        throw 'Empty Responses reasoning produced a Think card or lacks regression evidence.'
    }
    $responsesNonemptyProperty = $responsesReasoning.PSObject.Properties['nonemptyItems']
    $responsesOutputProperty = $responsesReasoning.PSObject.Properties['emittedThinkCardsForNonempty']
    if (-not $responsesNonemptyProperty -or -not $responsesOutputProperty -or
        $responsesNonemptyProperty.Value -isnot [Array] -or
        $responsesOutputProperty.Value -isnot [Array]) {
        throw 'Nonempty Responses reasoning regression properties are missing.'
    }
    $responsesNonemptyItems = @($responsesNonemptyProperty.Value)
    $responsesInvalidNonemptyItems = @($responsesNonemptyItems | Where-Object {
        $item = $_
        $contentProperty = $item.PSObject.Properties['content']
        $content = if ($contentProperty) { @($contentProperty.Value) } else { @() }
        $validContent = @($content | Where-Object {
            $textProperty = $_.PSObject.Properties['text']
            [string](Get-LockProperty -InputObject $_ -Name 'type') -ceq 'reasoning_text' -and
            $textProperty -and $textProperty.Value -is [string] -and
            -not [string]::IsNullOrWhiteSpace([string]$textProperty.Value)
        })
        [string](Get-LockProperty -InputObject $item -Name 'type') -cne 'reasoning' -or
        -not $contentProperty -or $contentProperty.Value -isnot [Array] -or
        @($content).Count -eq 0 -or
        @($validContent).Count -ne @($content).Count
    })
    $responsesInputText = @($responsesNonemptyItems | ForEach-Object {
        @($_.PSObject.Properties['content'].Value) | ForEach-Object {
            [string]$_.PSObject.Properties['text'].Value
        }
    })
    $responsesRawOutput = @($responsesOutputProperty.Value)
    $responsesInvalidOutput = @($responsesRawOutput | Where-Object {
        $_ -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$_)
    })
    $responsesOutputText = @($responsesRawOutput | ForEach-Object { [string]$_ })
    $responsesSequenceMismatch = $responsesInputText.Count -ne $responsesOutputText.Count
    if (-not $responsesSequenceMismatch) {
        for ($index = 0; $index -lt $responsesInputText.Count; $index++) {
            if (-not [string]::Equals(
                [string]$responsesInputText[$index],
                [string]$responsesOutputText[$index],
                [StringComparison]::Ordinal
            )) {
                $responsesSequenceMismatch = $true
                break
            }
        }
    }
    if ($responsesInvalidNonemptyItems.Count -gt 0 -or $responsesInvalidOutput.Count -gt 0 -or
        $responsesInputText.Count -eq 0 -or
        $responsesSequenceMismatch) {
        throw 'Nonempty Responses reasoning did not produce a Think card.'
    }
    $anthropicEmptyProperty = $anthropicReasoning.PSObject.Properties['emptyItems']
    $anthropicEmptyOutputProperty = $anthropicReasoning.PSObject.Properties['emittedThinkChunks']
    if (-not $anthropicEmptyProperty -or -not $anthropicEmptyOutputProperty -or
        $anthropicEmptyProperty.Value -isnot [Array] -or
        $anthropicEmptyOutputProperty.Value -isnot [Array]) {
        throw 'Empty Anthropic reasoning regression properties are missing.'
    }
    $anthropicEmptyItems = @($anthropicEmptyProperty.Value)
    $anthropicInvalidEmptyItems = @($anthropicEmptyItems | Where-Object {
        $thinkingProperty = $_.PSObject.Properties['thinking']
        [string](Get-LockProperty -InputObject $_ -Name 'type') -cne 'thinking' -or
        -not $thinkingProperty -or $thinkingProperty.Value -isnot [string] -or
        -not [string]::IsNullOrWhiteSpace([string]$thinkingProperty.Value)
    })
    if ($anthropicEmptyItems.Count -eq 0 -or
        $anthropicInvalidEmptyItems.Count -gt 0 -or
        @($anthropicEmptyOutputProperty.Value).Count -ne 0) {
        throw 'Empty Anthropic reasoning produced a Think chunk or lacks regression evidence.'
    }
    $anthropicNonemptyProperty = $anthropicReasoning.PSObject.Properties['nonemptyItems']
    $anthropicOutputProperty = $anthropicReasoning.PSObject.Properties['emittedThinkChunksForNonempty']
    if (-not $anthropicNonemptyProperty -or -not $anthropicOutputProperty -or
        $anthropicNonemptyProperty.Value -isnot [Array] -or
        $anthropicOutputProperty.Value -isnot [Array]) {
        throw 'Nonempty Anthropic reasoning regression properties are missing.'
    }
    $anthropicNonemptyItems = @($anthropicNonemptyProperty.Value)
    $anthropicInvalidNonemptyItems = @($anthropicNonemptyItems | Where-Object {
        $thinkingProperty = $_.PSObject.Properties['thinking']
        [string](Get-LockProperty -InputObject $_ -Name 'type') -cne 'thinking' -or
        -not $thinkingProperty -or $thinkingProperty.Value -isnot [string] -or
        [string]::IsNullOrWhiteSpace([string]$thinkingProperty.Value)
    })
    $anthropicInputText = @($anthropicNonemptyItems | ForEach-Object {
        [string]$_.PSObject.Properties['thinking'].Value
    })
    $anthropicRawOutput = @($anthropicOutputProperty.Value)
    $anthropicInvalidOutput = @($anthropicRawOutput | Where-Object {
        $_ -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$_)
    })
    $anthropicOutputText = @($anthropicRawOutput | ForEach-Object { [string]$_ })
    $anthropicSequenceMismatch = $anthropicInputText.Count -ne $anthropicOutputText.Count
    if (-not $anthropicSequenceMismatch) {
        for ($index = 0; $index -lt $anthropicInputText.Count; $index++) {
            if (-not [string]::Equals(
                [string]$anthropicInputText[$index],
                [string]$anthropicOutputText[$index],
                [StringComparison]::Ordinal
            )) {
                $anthropicSequenceMismatch = $true
                break
            }
        }
    }
    if ($anthropicInvalidNonemptyItems.Count -gt 0 -or $anthropicInvalidOutput.Count -gt 0 -or
        $anthropicInputText.Count -eq 0 -or
        $anthropicSequenceMismatch) {
        throw 'Nonempty Anthropic reasoning did not produce a Think chunk.'
    }
    return [pscustomobject]@{
        valid = $true
        providerNativeEvidence = $true
        traditionalSearchEvidence = $true
        cordisSessionMounted = $true
        emptyReasoningSuppressed = $true
        nonemptyReasoningEmitted = $true
        deepSeekFallback = $false
    }
}

function Get-ComposedConfigEntryBlock {
    param(
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$Id
    )
    $lines = @($Content -split "`r?`n")
    $escaped = [regex]::Escape($Id)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch ("^(?<indent>\s*)-\s+id\s*:\s*['""]?" + $escaped + "['""]?\s*$")) {
            continue
        }
        $indent = $matches['indent'].Length
        $end = $lines.Count
        for ($j = $i + 1; $j -lt $lines.Count; $j++) {
            if ($lines[$j] -match '^\s*$') { continue }
            if ($lines[$j] -match '^(?<indent>\s*)\S' -and $matches['indent'].Length -le $indent) {
                $end = $j
                break
            }
        }
        return ($lines[$i..($end - 1)] -join "`n")
    }
    return $null
}

function Get-ComposedConfigChildBlock {
    param(
        [Parameter(Mandatory)][string]$EntryBlock,
        [Parameter(Mandatory)][string]$Name
    )
    $lines = @($EntryBlock -split "`r?`n")
    $escaped = [regex]::Escape($Name)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch ("^(?<indent>\s*)" + $escaped + '\s*:\s*$')) {
            continue
        }
        $indent = $matches['indent'].Length
        $end = $lines.Count
        for ($j = $i + 1; $j -lt $lines.Count; $j++) {
            if ($lines[$j] -match '^\s*$') { continue }
            if ($lines[$j] -match '^(?<indent>\s*)\S' -and $matches['indent'].Length -le $indent) {
                $end = $j
                break
            }
        }
        if ($end -le $i + 1) { return '' }
        return ($lines[($i + 1)..($end - 1)] -join "`n")
    }
    return $null
}

function Get-WindowsCopilotComposedConfigState {
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )
    $reasons = [Collections.Generic.List[string]]::new()
    $missingMarkers = @($Lock.acceptance.composedConfig.requiredMarkers | Where-Object {
        $Content.IndexOf([string]$_, [StringComparison]::Ordinal) -lt 0
    })
    if ($missingMarkers.Count -gt 0) {
        $reasons.Add('required-marker-missing')
    }
    $forbiddenMarkers = @($Lock.acceptance.composedConfig.forbiddenMarkers | Where-Object {
        $Content.IndexOf([string]$_, [StringComparison]::Ordinal) -ge 0
    })
    if ($forbiddenMarkers.Count -gt 0) {
        $reasons.Add('legacy-search-provider-active')
    }
    $missingEntries = [Collections.Generic.List[string]]::new()
    foreach ($entry in @($Lock.acceptance.composedConfig.requiredEntries)) {
        $block = Get-ComposedConfigEntryBlock -Content $Content -Id ([string]$entry.id)
        $namePattern = '(?m)^\s+name\s*:\s*[''"]?' + [regex]::Escape([string]$entry.name) + '[''"]?\s*$'
        if (-not $block -or $block -notmatch $namePattern) {
            $missingEntries.Add([string]$entry.id)
        }
    }
    if ($missingEntries.Count -gt 0) {
        $reasons.Add('required-entry-missing')
    }
    $forbiddenEntries = @($Lock.acceptance.composedConfig.forbiddenActiveEntries | Where-Object {
        $null -ne (Get-ComposedConfigEntryBlock -Content $Content -Id ([string]$_))
    })
    if ($forbiddenEntries.Count -gt 0) {
        $reasons.Add('legacy-search-entry-active')
    }
    $managed = $Lock.acceptance.composedConfig.managedEntry
    $managedBlock = Get-ComposedConfigEntryBlock -Content $Content -Id ([string]$managed.id)
    $managedConfigBlock = if ($managedBlock) {
        Get-ComposedConfigChildBlock -EntryBlock $managedBlock -Name 'config'
    } else {
        $null
    }
    $providerPattern = '(?m)^\s+providers\s*:\s*\[[^\]]*\b' +
        [regex]::Escape([string]$managed.provider) + '\b[^\]]*\]\s*$'
    $providerListPattern = '(?ms)^\s+providers\s*:\s*$.*?^\s+-\s+[''"]?' +
        [regex]::Escape([string]$managed.provider) + '[''"]?\s*$'
    $enabledPattern = '(?m)^\s+enabled\s*:\s*true\s*$'
    $hostBlock = Get-ComposedConfigEntryBlock -Content $Content -Id ([string]$managed.hostEntry)
    $hostConfigBlock = if ($hostBlock) {
        Get-ComposedConfigChildBlock -EntryBlock $hostBlock -Name 'config'
    } else {
        $null
    }
    $searchProviderPattern = '(?m)^\s+searchProvider\s*:\s*[''"]?' +
        [regex]::Escape([string]$managed.searchProvider) + '[''"]?\s*$'
    $managedConfigValid = [bool](
        $managedConfigBlock -and
        ($managedConfigBlock -match $providerPattern -or $managedConfigBlock -match $providerListPattern) -and
        $managedConfigBlock -match $enabledPattern -and
        $hostConfigBlock -and
        $hostConfigBlock -match $searchProviderPattern
    )
    if (-not $managedConfigValid) {
        $reasons.Add('managed-copilot-search-config-missing')
    }
    return [pscustomobject]@{
        valid = [bool]($reasons.Count -eq 0)
        status = if ($reasons.Count -eq 0) { 'valid' } else { 'drifted' }
        reasons = @($reasons)
        missingMarkers = @($missingMarkers)
        missingEntries = @($missingEntries)
        forbiddenMarkers = @($forbiddenMarkers)
        forbiddenActiveEntries = @($forbiddenEntries)
        managedConfigValid = $managedConfigValid
        requiredMarkers = @($Lock.acceptance.composedConfig.requiredMarkers)
        requiredEntries = @($Lock.acceptance.composedConfig.requiredEntries)
    }
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
    $state = Get-WindowsCopilotComposedConfigState -Lock $Lock -Content $content
    if (-not $state.valid) {
        throw "Composed config drift: $($state.reasons -join ', ')."
    }
    return $state
}

function Get-WindowsCopilotDesktopState {
    param(
        [Parameter(Mandatory)]$Lock,
        [string]$Path,
        [string]$Version
    )
    $expected = [string]$Lock.components.desktop.version
    $canonicalPath = if ($env:LOCALAPPDATA) {
        Join-Path $env:LOCALAPPDATA 'Deepseek Harness Desktop\deepseek-harness-desktop.exe'
    } else {
        $null
    }
    $candidates = [Collections.Generic.List[object]]::new()
    if ($Version) {
        $candidates.Add([pscustomobject]@{
            path = if ($Path) { [IO.Path]::GetFullPath($Path) } else { $canonicalPath }
            rawVersion = $Version
            source = 'injected'
        })
    }
    foreach ($candidatePath in @($canonicalPath, $Path)) {
        if (-not $candidatePath -or -not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) { continue }
        $fullPath = [IO.Path]::GetFullPath($candidatePath)
        if (@($candidates | Where-Object { $_.path -ieq $fullPath }).Count -gt 0) { continue }
        $versionInfo = (Get-Item -LiteralPath $fullPath).VersionInfo
        $actual = if ($versionInfo.ProductVersion) { $versionInfo.ProductVersion } else { $versionInfo.FileVersion }
        $candidates.Add([pscustomobject]@{
            path = $fullPath
            rawVersion = $actual
            source = if ($fullPath -ieq $canonicalPath) { 'canonical-official-path' } else { 'explicit-path' }
        })
    }
    $discoveries = @($candidates | ForEach-Object {
        $match = if ($_.rawVersion) { [regex]::Match([string]$_.rawVersion, '\d+\.\d+\.\d+') } else { $null }
        $normalized = if ($match -and $match.Success) { $match.Value } else { $null }
        [pscustomobject]@{
            path = $_.path
            source = $_.source
            version = $normalized
            valid = [bool]($normalized -and ([version]$normalized -eq [version]$expected))
            newerThanLock = [bool]($normalized -and ([version]$normalized -gt [version]$expected))
        }
    })
    $selected = @($discoveries | Where-Object newerThanLock | Sort-Object { [version]$_.version } -Descending | Select-Object -First 1)
    if ($selected.Count -eq 0) {
        $selected = @($discoveries | Where-Object valid | Select-Object -First 1)
    }
    if ($selected.Count -eq 0) {
        $selected = @($discoveries | Select-Object -First 1)
    }
    $state = if ($selected.Count -gt 0) { $selected[0] } else { $null }
    $valid = [bool]($state -and $state.valid -and @($discoveries | Where-Object newerThanLock).Count -eq 0)
    $newer = [bool](@($discoveries | Where-Object newerThanLock).Count -gt 0)
    return [pscustomobject]@{
        path = if ($state) { $state.path } else { if ($Path) { $Path } else { $canonicalPath } }
        version = if ($state) { $state.version } else { $null }
        lockedVersion = $expected
        valid = $valid
        newerThanLock = $newer
        status = if (-not $state -or -not $state.version) { 'not-found-or-unreadable' } elseif ($newer) { 'newer-than-lock' } elseif ($valid) { 'locked' } else { 'version-mismatch' }
        discoveries = @($discoveries)
    }
}

function Get-WindowsCopilotLegacyGatewayState {
    param(
        [Parameter(Mandatory)]$Lock,
        [string]$Path,
        [string]$Sha256
    )
    $source = if ($Path) { 'explicit' } elseif ($Sha256) { 'injected-hash' } else { $null }
    $listenerVerified = [bool]$Sha256
    $listenerStatus = if ($Sha256) { 'injected' } else { 'not-checked' }
    if (-not $Sha256 -and (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue)) {
        $port = [int]$Lock.migration.legacyGateway.listenerPorts[0]
        $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue)
        $publicListeners = @($listeners | Where-Object { $_.LocalAddress -notin @('127.0.0.1', '::1') })
        $processPaths = @()
        if ($listeners.Count -gt 0 -and $publicListeners.Count -eq 0) {
            foreach ($processId in @($listeners.OwningProcess | Select-Object -Unique)) {
                $process = Get-CimInstance Win32_Process -Filter "ProcessId = $processId" -ErrorAction SilentlyContinue
                if ($process -and $process.ExecutablePath) {
                    $processPaths += [IO.Path]::GetFullPath([string]$process.ExecutablePath)
                }
            }
        }
        $processPaths = @($processPaths | Select-Object -Unique)
        if ($publicListeners.Count -gt 0) {
            $listenerStatus = 'public-binding'
        } elseif ($processPaths.Count -eq 0) {
            $listenerStatus = 'not-found'
        } elseif ($processPaths.Count -gt 1) {
            $listenerStatus = 'ambiguous'
        } elseif (-not (Test-Path -LiteralPath $processPaths[0] -PathType Leaf)) {
            $listenerStatus = 'process-image-not-found'
        } else {
            $activePath = $processPaths[0]
            $listenerStatus = 'loopback-process-resolved'
            if (-not $Path) {
                $Path = $activePath
                $listenerVerified = $true
            } elseif ([IO.Path]::GetFullPath($Path) -ieq $activePath) {
                $listenerVerified = $true
            } else {
                $listenerStatus = 'executable-path-mismatch'
            }
            $source = 'active-loopback-listener'
        }
    }
    $actual = $Sha256
    if (-not $actual -and $Path -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    }
    $expected = [string]$Lock.migration.legacyGateway.artifact.sha256
    $detected = [bool]($listenerVerified -or $actual)
    $matchesReviewedLegacy = [bool]($detected -and $actual -and $actual -ieq $expected)
    return [pscustomobject]@{
        path = $Path
        source = $source
        listenerVerified = $listenerVerified
        listenerStatus = $listenerStatus
        sha256 = if ($actual) { $actual.ToLowerInvariant() } else { $null }
        lockedSha256 = $expected
        detected = $detected
        matchesReviewedLegacy = $matchesReviewedLegacy
        migrationOnly = $true
        status = if (-not $detected) { 'not-detected' } elseif ($matchesReviewedLegacy) { 'reviewed-legacy-detected' } else { 'unreviewed-legacy-detected' }
    }
}

function Get-WindowsCopilotGatewayState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [string]$Path,
        [string]$Sha256
    )
    Get-WindowsCopilotLegacyGatewayState -Lock $Lock -Path $Path -Sha256 $Sha256
}

function Get-WindowsCopilotCoreReceiptState {
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$NpmGlobalRoot,
        [string]$CoreInstallPrefix,
        [string]$DshCliPath
    )
    $candidate = $DshCliPath
    if (-not $candidate -and $CoreInstallPrefix) {
        $candidate = Join-Path (Resolve-DeploymentPath $CoreInstallPrefix) 'dsh.cmd'
    }
    if (-not $candidate) { $candidate = $env:DSH_CLI_PATH }
    if (-not $candidate) {
        $candidate = Join-Path (Split-Path -Parent (Resolve-DeploymentPath $NpmGlobalRoot)) 'dsh.cmd'
    }
    $fullCandidate = [IO.Path]::GetFullPath($candidate)
    $parent = Split-Path -Parent $fullCandidate
    $prefix = if ((Split-Path -Leaf $parent) -ieq '.bin' -and
        (Split-Path -Leaf (Split-Path -Parent $parent)) -ieq 'node_modules') {
        Split-Path -Parent (Split-Path -Parent $parent)
    } else {
        $parent
    }
    $receiptPath = Join-Path $prefix 'dsh-local-install.json'
    if (-not (Test-Path -LiteralPath $fullCandidate -PathType Leaf)) {
        return [pscustomobject]@{
            valid = $false
            status = 'cli-not-found'
            cliPath = $fullCandidate
            receiptPath = $receiptPath
            expectedCommit = [string]$Lock.components.core.source.commit
        }
    }
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
        return [pscustomobject]@{
            valid = $false
            status = 'receipt-missing'
            cliPath = $fullCandidate
            receiptPath = $receiptPath
            expectedCommit = [string]$Lock.components.core.source.commit
        }
    }
    try {
        $info = Resolve-DshCliInfo -DshCliPath $fullCandidate -ExpectedRepository 'cloga/deepseek-harness'
        $commitValid = [bool]($info.commitSha -ieq [string]$Lock.components.core.source.commit)
        $versionValid = [bool]($info.version -eq [string]$Lock.components.core.package.version)
        return [pscustomobject]@{
            valid = [bool]($commitValid -and $versionValid)
            status = if (-not $commitValid) { 'source-commit-mismatch' } elseif (-not $versionValid) { 'version-mismatch' } else { 'verified' }
            repository = $info.repository
            repositoryUrl = $info.repositoryUrl
            cliPath = $info.cliPath
            canonicalCliPath = $info.canonicalCliPath
            packageRoot = $info.packageRoot
            entryPath = $info.entryPath
            receiptPath = $info.receiptPath
            commitSha = $info.commitSha
            expectedCommit = [string]$Lock.components.core.source.commit
            version = $info.version
            expectedVersion = [string]$Lock.components.core.package.version
            releaseManifestSha256 = $info.releaseManifestSha256
            packageCount = $info.packageCount
            installedFileCount = $info.installedFileCount
        }
    } catch {
        $status = if ($_.Exception.Message -like '*installed-bytes-unattested*') {
            'installed-bytes-unattested'
        } elseif ($_.Exception.Message -like '*installed-bytes-mismatch*') {
            'installed-bytes-mismatch'
        } else {
            'receipt-invalid'
        }
        return [pscustomobject]@{
            valid = $false
            status = $status
            cliPath = $fullCandidate
            receiptPath = $receiptPath
            expectedCommit = [string]$Lock.components.core.source.commit
        }
    }
}

function Get-WindowsCopilotRemediation {
    param(
        [Parameter(Mandatory)]$Desktop,
        [Parameter(Mandatory)]$CoreReceipt,
        [Parameter(Mandatory)][bool]$DriftDetected
    )
    if (-not $DriftDetected) {
        return [pscustomobject]@{ status = 'not-required'; automaticApplyAllowed = $false; steps = @() }
    }
    $blockedByNewerDesktop = [bool]$Desktop.newerThanLock
    $steps = [Collections.Generic.List[object]]::new()
    $steps.Add([pscustomobject]@{
        order = 1
        action = 'check-locked-deployment'
        path = 'tools\install-windows-copilot.ps1'
        mode = 'check'
    })
    if ($blockedByNewerDesktop) {
        $steps.Add([pscustomobject]@{
            order = 2
            action = 'update-lock-or-review-compatible-migration'
            path = 'deployments\windows-copilot.lock.json'
            requirement = 'Preserve the installed newer Desktop shell; do not apply the older Desktop lock.'
        })
    }
    if (-not $CoreReceipt.valid) {
        $steps.Add([pscustomobject]@{
            order = $steps.Count + 1
            action = 'reinstall-local-core-with-receipt'
            path = 'cloga/deepseek-harness:scripts/release/install-local'
            requirement = 'Produce and validate dsh-local-install.json before bootstrap.'
        })
    }
    $steps.Add([pscustomobject]@{
        order = $steps.Count + 1
        action = 'apply-compatible-locked-deployment'
        path = 'tools\install-windows-copilot.ps1'
        mode = 'apply'
        requires = if ($blockedByNewerDesktop) { 'reviewed lock update or compatible migration' } else { 'exact locked sources and artifacts' }
    })
    $steps.Add([pscustomobject]@{
        order = $steps.Count + 1
        action = 'bootstrap-direct-copilot'
        path = 'tools\enable-copilot-search-vision.ps1'
        mode = 'apply'
        requires = 'valid local Core receipt; Desktop UI creates the built-in Copilot grant and account route'
    })
    return [pscustomobject]@{
        status = if ($blockedByNewerDesktop) { 'blocked-lock-update-required' } else { 'locked-repair-required' }
        automaticApplyAllowed = [bool]($Desktop.valid -and -not $blockedByNewerDesktop)
        steps = @($steps)
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
        $loopback = @($listeners | Where-Object { $_.LocalAddress -eq $HostName })
        $public = @($listeners | Where-Object {
            $_.LocalAddress -ne $HostName
        })
        return [pscustomobject]@{
            host = $HostName
            port = $Port
            listening = [bool]($loopback.Count -gt 0)
            loopbackOnly = [bool]($loopback.Count -gt 0 -and $public.Count -eq 0)
            bindingVerified = $true
            owningProcessIds = @($loopback | ForEach-Object { $_.OwningProcess } | Select-Object -Unique)
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
            owningProcessIds = @()
        }
    } catch {
        return [pscustomobject]@{
            host = $HostName
            port = $Port
            listening = $false
            loopbackOnly = $false
            bindingVerified = $false
            owningProcessIds = @()
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

function Get-WindowsCopilotUserEnvironment {
    param([Parameter(Mandatory)][string]$Name)
    return [Environment]::GetEnvironmentVariable($Name, 'User')
}

function Set-WindowsCopilotUserEnvironment {
    param(
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][string]$Value
    )
    [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
}

function Get-WindowsCopilotCoreConflictState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$NpmGlobalRoot,
        [Parameter(Mandatory)][string]$SelectedCliPath
    )
    $globalRoot = Resolve-DeploymentPath $NpmGlobalRoot
    if ((Split-Path -Leaf $globalRoot) -ine 'node_modules') {
        throw "The global npm root must end in 'node_modules': '$globalRoot'."
    }
    $globalPrefix = Split-Path -Parent $globalRoot
    $selectedPrefix = Split-Path -Parent (Resolve-DeploymentPath $SelectedCliPath)
    if ($globalPrefix -ieq $selectedPrefix) {
        throw 'The selected fork Core must use a dedicated prefix outside the npm global prefix.'
    }
    $packagePath = Join-Path $globalRoot '@deepseek-ai\dsh\package.json'
    $packageName = $null
    $packageVersion = $null
    $packageEntrypoint = $null
    $packageEntrypointSha256 = $null
    if (Test-Path -LiteralPath $packagePath -PathType Leaf) {
        try {
            $package = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | ConvertFrom-Json
            $packageName = [string]$package.name
            $packageVersion = [string]$package.version
            $packageEntrypoint = if ($package.bin -is [string]) {
                [string]$package.bin
            } else {
                [string]$package.bin.dsh
            }
        } catch {
            $packageName = 'unreadable'
        }
    }
    $globalReceipt = Join-Path $globalPrefix 'dsh-local-install.json'
    $hasManagedReceipt = Test-Path -LiteralPath $globalReceipt -PathType Leaf
    $normalizedPackageEntrypoint = if ($packageEntrypoint) {
        $packageEntrypoint.Replace('\', '/')
    } else {
        ''
    }
    if ($normalizedPackageEntrypoint -eq 'lib/bin.js') {
        $entrypointPath = Join-Path (Split-Path -Parent $packagePath) $packageEntrypoint
        if (Test-Path -LiteralPath $entrypointPath -PathType Leaf) {
            $packageEntrypointSha256 = (
                Get-FileHash -LiteralPath $entrypointPath -Algorithm SHA256
            ).Hash.ToLowerInvariant()
        }
    }
    $shims = @($Lock.components.core.activation.conflictShims | ForEach-Object {
        $name = [string]$_
        $path = Join-Path $globalPrefix $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
        $sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        $expectedSha256 = [string](Get-LockProperty `
            -InputObject $Lock.components.core.activation.conflictShimSha256 -Name $name)
        $canonicalShim = [bool]($sha256 -ceq $expectedSha256)
        $officialGlobal = [bool](
            $packageName -ceq '@deepseek-ai/dsh' -and
            $packageVersion -and
            $normalizedPackageEntrypoint -ceq 'lib/bin.js' -and
            $packageEntrypointSha256 -and
            -not $hasManagedReceipt -and
            $canonicalShim
        )
        [pscustomobject]@{
            name = $name
            path = [IO.Path]::GetFullPath($path)
            sha256 = $sha256
            expectedSha256 = $expectedSha256
            kind = if ($officialGlobal) { 'official-unreceipted-global' } else { 'unmanaged-global' }
            canonicalShim = $canonicalShim
            quarantinable = $officialGlobal
        }
    })
    $unmanaged = @($shims | Where-Object { -not $_.quarantinable })
    return [pscustomobject]@{
        valid = [bool]($shims.Count -eq 0)
        status = if ($shims.Count -eq 0) {
            'none'
        } elseif ($unmanaged.Count -gt 0) {
            'unmanaged-global-dsh-conflict'
        } else {
            'official-global-dsh-conflict'
        }
        globalPrefix = $globalPrefix
        packageName = $packageName
        packageVersion = $packageVersion
        packageEntrypoint = $packageEntrypoint
        packageEntrypointSha256 = $packageEntrypointSha256
        managedReceipt = $hasManagedReceipt
        shims = @($shims)
    }
}

function Assert-WindowsCopilotCoreConflictSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$NpmGlobalRoot,
        [Parameter(Mandatory)][string]$SelectedCliPath
    )
    $conflicts = Get-WindowsCopilotCoreConflictState -Lock $Lock -NpmGlobalRoot $NpmGlobalRoot `
        -SelectedCliPath $SelectedCliPath
    $unmanaged = @($conflicts.shims | Where-Object { -not $_.quarantinable })
    if ($unmanaged.Count -gt 0) {
        throw "Refusing to remove unmanaged global dsh shims: $($unmanaged.path -join ', ')."
    }
    return $conflicts
}

function Get-WindowsCopilotCoreActivationState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$NpmGlobalRoot,
        [string]$CoreInstallPrefix,
        [string]$DshCliPath
    )
    $core = Get-WindowsCopilotCoreReceiptState -Lock $Lock -NpmGlobalRoot $NpmGlobalRoot `
        -CoreInstallPrefix $CoreInstallPrefix -DshCliPath $DshCliPath
    $environmentName = [string]$Lock.components.core.activation.environmentVariable
    $persisted = Get-WindowsCopilotUserEnvironment -Name $environmentName
    $selected = [string]$core.cliPath
    $environmentValid = [bool](
        $core.valid -and $persisted -and
        [IO.Path]::GetFullPath($persisted) -ieq [IO.Path]::GetFullPath($selected)
    )
    $conflicts = if ($core.valid -and $selected) {
        Get-WindowsCopilotCoreConflictState -Lock $Lock -NpmGlobalRoot $NpmGlobalRoot `
            -SelectedCliPath $selected
    } else {
        [pscustomobject]@{
            valid = $false
            status = 'selected-cli-unavailable'
            globalPrefix = Split-Path -Parent (Resolve-DeploymentPath $NpmGlobalRoot)
            shims = @()
        }
    }
    return [pscustomobject]@{
        valid = [bool]($core.valid -and $environmentValid -and $conflicts.valid)
        status = if (-not $core.valid) {
            'core-receipt-invalid'
        } elseif (-not $environmentValid) {
            'user-dsh-cli-path-mismatch'
        } elseif (-not $conflicts.valid) {
            $conflicts.status
        } else {
            'enabled'
        }
        environmentVariable = $environmentName
        selectedCliPath = $selected
        persistedUserValue = $persisted
        processValue = $env:DSH_CLI_PATH
        environmentValid = $environmentValid
        conflicts = $conflicts
        core = $core
    }
}

function Enter-WindowsCopilotActivationLock {
    param([Parameter(Mandatory)][string]$BackupRoot)
    $normalized = (Resolve-DeploymentPath $BackupRoot).ToLowerInvariant()
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($normalized))
    } finally {
        $sha256.Dispose()
    }
    $hashText = ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
    $name = 'Local\DshWindowsOpsCoreActivation-' + $hashText.Substring(0, 32)
    $mutex = [Threading.Mutex]::new($false, $name)
    $acquired = $false
    try {
        try {
            $acquired = $mutex.WaitOne(0)
        } catch [Threading.AbandonedMutexException] {
            $acquired = $true
        }
        if (-not $acquired) {
            throw "Another Windows Copilot activation operation is using '$normalized'."
        }
        return $mutex
    } catch {
        $mutex.Dispose()
        throw
    }
}

function Exit-WindowsCopilotActivationLock {
    param([Parameter(Mandatory)][Threading.Mutex]$Mutex)
    try {
        $Mutex.ReleaseMutex()
    } finally {
        $Mutex.Dispose()
    }
}

function Get-WindowsCopilotCurrentActivation {
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$BackupRoot
    )
    $path = Join-Path (Resolve-DeploymentPath $BackupRoot) `
        ([string]$Lock.components.core.activation.currentReceipt)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $receipt = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $operationId = [string]$receipt.operationId
    $status = [string](Get-LockProperty -InputObject $receipt -Name 'status')
    if (-not $status) { $status = 'active' }
    if ([int]$receipt.schemaVersion -ne 1 -or
        [string]$receipt.deploymentId -cne [string]$Lock.deploymentId -or
        $operationId -notmatch '^\d{8}T\d{9}Z$' -or
        $status -notin @('pending', 'active', 'rolled-back')) {
        throw 'Current activation receipt is invalid or does not match the locked deployment.'
    }
    return [pscustomobject]@{
        path = $path
        operationId = $operationId
        status = $status
        receipt = $receipt
    }
}

function Get-WindowsCopilotActivationReceipt {
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$OperationId
    )
    if ($OperationId -notmatch '^\d{8}T\d{9}Z$') {
        throw "Invalid activation operation id '$OperationId'."
    }
    $root = Resolve-DeploymentPath $BackupRoot
    $operationRoot = [IO.Path]::GetFullPath((Join-Path $root $OperationId))
    if (-not $operationRoot.StartsWith($root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Activation rollback operation escapes the backup root.'
    }
    $path = Join-Path $operationRoot ([string]$Lock.components.core.activation.operationReceipt)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Activation rollback receipt not found: '$path'."
    }
    $receipt = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$receipt.schemaVersion -ne 1 -or
        [string]$receipt.deploymentId -cne [string]$Lock.deploymentId -or
        [string]$receipt.operationId -cne $OperationId -or
        [string]$receipt.environmentVariable -cne [string]$Lock.components.core.activation.environmentVariable -or
        [string]$receipt.commitSha -cne [string]$Lock.components.core.source.commit -or
        [string]$receipt.packageVersion -cne [string]$Lock.components.core.package.version -or
        [string]$receipt.capability -cne [string]$Lock.acceptance.sandbox.capability) {
        throw 'Activation rollback receipt does not match the locked Core identity.'
    }
    try {
        $receiptRepository = ConvertTo-DshRepositorySlug -RepositoryUrl ([string]$receipt.repositoryUrl)
        $lockedRepository = ConvertTo-DshRepositorySlug `
            -RepositoryUrl ([string]$Lock.components.core.source.repository)
    } catch {
        throw 'Activation rollback receipt repository does not match the locked fork.'
    }
    if ($receiptRepository -ine $lockedRepository) {
        throw 'Activation rollback receipt repository does not match the locked fork.'
    }
    $selectedCliPath = [IO.Path]::GetFullPath([string]$receipt.selectedCliPath)
    if ((Split-Path -Leaf $selectedCliPath) -ine 'dsh.cmd') {
        throw 'Activation rollback receipt selected CLI is not a prefix-root dsh.cmd.'
    }
    return [pscustomobject]@{
        operationRoot = $operationRoot
        path = $path
        receipt = $receipt
        selectedCliPath = $selectedCliPath
    }
}

function Assert-WindowsCopilotNoPendingActivation {
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$BackupRoot
    )
    $current = Get-WindowsCopilotCurrentActivation -Lock $Lock -BackupRoot $BackupRoot
    if ($current -and $current.status -eq 'pending') {
        throw "Pending activation operation '$($current.operationId)' must be rolled back before Apply can continue."
    }
}

function Invoke-WindowsCopilotForkCoreActivation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$NpmGlobalRoot,
        [Parameter(Mandatory)][string]$CoreInstallPrefix,
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$OperationRoot
    )
    $core = Get-WindowsCopilotCoreReceiptState -Lock $Lock -NpmGlobalRoot $NpmGlobalRoot `
        -CoreInstallPrefix $CoreInstallPrefix
    if (-not $core.valid) {
        throw "Cannot activate the fork Core because its receipt is '$($core.status)'."
    }
    $sandbox = Assert-WindowsCopilotCoreCapability -Lock $Lock -Core $core
    $conflicts = Assert-WindowsCopilotCoreConflictSafe -Lock $Lock -NpmGlobalRoot $NpmGlobalRoot `
        -SelectedCliPath ([string]$core.cliPath)
    $environmentName = [string]$Lock.components.core.activation.environmentVariable
    $previousUserValue = Get-WindowsCopilotUserEnvironment -Name $environmentName
    $selectedCliPath = [IO.Path]::GetFullPath([string]$core.cliPath)
    $currentState = Get-WindowsCopilotCurrentActivation -Lock $Lock -BackupRoot $BackupRoot
    $currentOperationId = if ($currentState) { [string]$currentState.operationId } else { $null }
    $currentStatus = if ($currentState) { [string]$currentState.status } else { $null }
    $selectedAlready = [bool](
        $conflicts.valid -and
        $previousUserValue -and
        [IO.Path]::GetFullPath($previousUserValue) -ieq $selectedCliPath
    )
    if ($currentStatus -eq 'pending') {
        $pending = Get-WindowsCopilotActivationReceipt -Lock $Lock -BackupRoot $BackupRoot `
            -OperationId $currentOperationId
        if ([string]$pending.selectedCliPath -ine $selectedCliPath) {
            throw "Pending activation operation '$currentOperationId' selects a different Core; run Rollback."
        }
        if (-not $selectedAlready) {
            throw "Pending activation operation '$currentOperationId' must be rolled back before Apply can continue."
        }
        $currentState.receipt.status = 'active'
        Set-WindowsCopilotJsonFile -Value $currentState.receipt -Path $currentState.path -Depth 4
        $currentStatus = 'active'
    }
    if ($currentStatus -eq 'active') {
        if (-not $selectedAlready) {
            throw "Active activation operation '$currentOperationId' is drifted; run Verify or Rollback before Apply."
        }
        $env:DSH_CLI_PATH = $selectedCliPath
        return [pscustomobject]@{
            status = 'already-enabled'
            changed = $false
            operationId = $currentOperationId
            selectedCliPath = $selectedCliPath
            core = $core
            sandbox = $sandbox
        }
    }

    New-Item -ItemType Directory -Path $OperationRoot -Force | Out-Null
    $shimBackups = @($conflicts.shims | ForEach-Object {
        $relativePath = Join-Path 'core-activation\global-shims' ([string]$_.name)
        Backup-DeploymentPath -Path ([string]$_.path) -RelativePath $relativePath `
            -OperationRoot $OperationRoot
        [pscustomobject]@{
            path = [string]$_.path
            relativePath = $relativePath
            sha256 = [string]$_.sha256
        }
    })
    $receipt = [ordered]@{
        schemaVersion = 1
        deploymentId = [string]$Lock.deploymentId
        operationId = Split-Path -Leaf (Resolve-DeploymentPath $OperationRoot)
        environmentVariable = $environmentName
        selectedCliPath = $selectedCliPath
        previousUserValue = $previousUserValue
        repositoryUrl = [string]$core.repositoryUrl
        commitSha = [string]$core.commitSha
        packageVersion = [string]$core.version
        capability = [string]$sandbox.capability
        globalPackage = [ordered]@{
            name = [string]$conflicts.packageName
            version = [string]$conflicts.packageVersion
            entrypoint = [string]$conflicts.packageEntrypoint
            entrypointSha256 = [string]$conflicts.packageEntrypointSha256
        }
        shims = @($shimBackups)
    }
    $receiptPath = Join-Path $OperationRoot ([string]$Lock.components.core.activation.operationReceipt)
    $currentPath = Join-Path (Resolve-DeploymentPath $BackupRoot) `
        ([string]$Lock.components.core.activation.currentReceipt)
    $currentReceipt = [ordered]@{
        schemaVersion = 1
        deploymentId = [string]$Lock.deploymentId
        operationId = [string]$receipt.operationId
        status = 'pending'
    }
    Set-WindowsCopilotJsonFile -Value $receipt -Path $receiptPath
    Set-WindowsCopilotJsonFile -Value $currentReceipt -Path $currentPath -Depth 4
    try {
        foreach ($shim in @($conflicts.shims)) {
            Remove-Item -LiteralPath ([string]$shim.path) -Force
        }
        Set-WindowsCopilotUserEnvironment -Name $environmentName -Value $selectedCliPath
        $env:DSH_CLI_PATH = $selectedCliPath
        $currentReceipt.status = 'active'
        Set-WindowsCopilotJsonFile -Value $currentReceipt -Path $currentPath -Depth 4
    } catch {
        Set-WindowsCopilotUserEnvironment -Name $environmentName -Value $previousUserValue
        $env:DSH_CLI_PATH = $previousUserValue
        foreach ($shim in $shimBackups) {
            $backup = Join-Path $OperationRoot ([string]$shim.relativePath)
            if (-not (Test-Path -LiteralPath ([string]$shim.path) -PathType Leaf) -and
                (Test-Path -LiteralPath $backup -PathType Leaf)) {
                Copy-Item -LiteralPath $backup -Destination ([string]$shim.path) -Force
            }
        }
        $currentReceipt.status = 'rolled-back'
        Set-WindowsCopilotJsonFile -Value $currentReceipt -Path $currentPath -Depth 4
        throw
    }
    return [pscustomobject]@{
        status = 'enabled'
        changed = $true
        operationId = [string]$receipt.operationId
        receiptPath = $receiptPath
        selectedCliPath = $selectedCliPath
        quarantinedShims = @($shimBackups.path)
        core = $core
        sandbox = $sandbox
    }
}

function Enable-WindowsCopilotForkCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$NpmGlobalRoot,
        [Parameter(Mandatory)][string]$CoreInstallPrefix,
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$OperationRoot
    )
    $mutex = Enter-WindowsCopilotActivationLock -BackupRoot $BackupRoot
    try {
        return Invoke-WindowsCopilotForkCoreActivation @PSBoundParameters
    } finally {
        Exit-WindowsCopilotActivationLock -Mutex $mutex
    }
}

function Assert-WindowsCopilotCoreCapability {
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)]$Core
    )
    $sandbox = Test-DshSandboxRegression -PackageRoot ([string]$Core.packageRoot) `
        -ProbeScript (Join-Path $PSScriptRoot 'dsh-sandbox-regression-probe.mjs') `
        -Mode ([string]$Lock.acceptance.sandbox.gate)
    if ([string]$sandbox.capability -cne [string]$Lock.acceptance.sandbox.capability -or
        [int]$sandbox.sameAndNarrowerApprovalCalls -ne 0 -or
        [int]$sandbox.widerApprovalCalls -ne [int]$Lock.acceptance.sandbox.widerApprovalCount) {
        throw 'Installed Core did not produce the locked sandbox capability evidence.'
    }
    return $sandbox
}

function Invoke-WindowsCopilotForkCoreRollback {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$NpmGlobalRoot,
        [string]$OperationId
    )
    $currentState = Get-WindowsCopilotCurrentActivation -Lock $Lock -BackupRoot $BackupRoot
    $currentOperationId = if ($currentState) { [string]$currentState.operationId } else { $null }
    $currentStatus = if ($currentState) { [string]$currentState.status } else { $null }
    if (-not $OperationId) {
        if (-not $currentOperationId) {
            return [pscustomobject]@{ status = 'nothing-to-rollback'; changed = $false }
        }
        $OperationId = $currentOperationId
    } elseif (-not $currentOperationId) {
        throw "Activation operation '$OperationId' is not current; no active operation receipt exists."
    } elseif ($currentOperationId -cne $OperationId) {
        throw "Activation operation '$OperationId' is not current; active operation is '$currentOperationId'."
    }
    $activationReceipt = Get-WindowsCopilotActivationReceipt -Lock $Lock -BackupRoot $BackupRoot `
        -OperationId $OperationId
    $operationRoot = [string]$activationReceipt.operationRoot
    $receipt = $activationReceipt.receipt
    $environmentName = [string]$receipt.environmentVariable
    $selectedCliPath = [string]$activationReceipt.selectedCliPath
    if ($currentStatus -eq 'rolled-back') {
        return [pscustomobject]@{
            status = 'already-rolled-back'
            changed = $false
            operationId = $OperationId
            restoredUserValue = Get-LockProperty -InputObject $receipt -Name 'previousUserValue'
            restoredShims = @()
        }
    }
    $globalRoot = Resolve-DeploymentPath $NpmGlobalRoot
    if ((Split-Path -Leaf $globalRoot) -ine 'node_modules') {
        throw "The global npm root must end in 'node_modules': '$globalRoot'."
    }
    $expectedGlobalPrefix = Split-Path -Parent $globalRoot
    $globalPackagePath = Join-Path $globalRoot '@deepseek-ai\dsh\package.json'
    if (@($receipt.shims).Count -gt 0) {
        if (-not (Test-Path -LiteralPath $globalPackagePath -PathType Leaf)) {
            throw 'The npm-global @deepseek-ai/dsh package is missing; refusing to restore dangling shims.'
        }
        $globalPackage = Get-Content -LiteralPath $globalPackagePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $globalEntrypoint = if ($globalPackage.bin -is [string]) {
            [string]$globalPackage.bin
        } else {
            [string]$globalPackage.bin.dsh
        }
        $normalizedGlobalEntrypoint = if ($globalEntrypoint) {
            $globalEntrypoint.Replace('\', '/')
        } else {
            ''
        }
        if ([string]$globalPackage.name -cne [string]$receipt.globalPackage.name -or
            [string]$globalPackage.version -cne [string]$receipt.globalPackage.version -or
            $normalizedGlobalEntrypoint -cne [string]$receipt.globalPackage.entrypoint) {
            throw 'The npm-global @deepseek-ai/dsh package changed after activation; refusing to restore its shims.'
        }
        $globalEntrypointPath = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $globalPackagePath) $globalEntrypoint))
        $packageBoundary = [IO.Path]::GetFullPath((Split-Path -Parent $globalPackagePath)).TrimEnd('\') + '\'
        if (-not $globalEntrypointPath.StartsWith($packageBoundary, [StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $globalEntrypointPath -PathType Leaf) -or
            (Get-FileHash -LiteralPath $globalEntrypointPath -Algorithm SHA256).Hash -ine
                [string]$receipt.globalPackage.entrypointSha256) {
            throw 'The npm-global @deepseek-ai/dsh entrypoint bytes changed after activation; refusing to restore its shims.'
        }
    }
    $currentUserValue = Get-WindowsCopilotUserEnvironment -Name $environmentName
    $previousUserValue = Get-LockProperty -InputObject $receipt -Name 'previousUserValue'
    $environmentAlreadyRestored = [string]::Equals(
        [string]$currentUserValue,
        [string]$previousUserValue,
        [StringComparison]::OrdinalIgnoreCase
    )
    if (-not $environmentAlreadyRestored -and
        -not [string]::Equals(
            [string]$currentUserValue,
            $selectedCliPath,
            [StringComparison]::OrdinalIgnoreCase
        )) {
        throw "User $environmentName changed after activation; refusing to overwrite it."
    }
    foreach ($shim in @($receipt.shims)) {
        $target = [IO.Path]::GetFullPath([string]$shim.path)
        $globalPrefix = Split-Path -Parent $target
        if ($globalPrefix -ine $expectedGlobalPrefix) {
            throw "Activation rollback shim is outside the selected npm global prefix: '$target'."
        }
        if (@($Lock.components.core.activation.conflictShims) -notcontains (Split-Path -Leaf $target)) {
            throw "Activation rollback receipt contains an unsupported shim '$target'."
        }
        $backup = [IO.Path]::GetFullPath((Join-Path $operationRoot ([string]$shim.relativePath)))
        if (-not $backup.StartsWith($operationRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $backup -PathType Leaf) -or
            (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -ine [string]$shim.sha256) {
            throw "Activation rollback backup is missing or invalid for '$target'."
        }
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ine [string]$shim.sha256) {
                throw "Global dsh shim changed after activation; refusing to overwrite '$target'."
            }
        } elseif (-not (Test-Path -LiteralPath $globalPrefix -PathType Container)) {
            throw "Global npm prefix no longer exists: '$globalPrefix'."
        }
    }
    if (-not $environmentAlreadyRestored) {
        Set-WindowsCopilotUserEnvironment -Name $environmentName -Value $previousUserValue
    }
    $env:DSH_CLI_PATH = $previousUserValue
    $restored = [Collections.Generic.List[string]]::new()
    foreach ($shim in @($receipt.shims)) {
        $target = [IO.Path]::GetFullPath([string]$shim.path)
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            Copy-Item -LiteralPath (Join-Path $operationRoot ([string]$shim.relativePath)) `
                -Destination $target -Force
            $restored.Add($target)
        }
    }
    $currentState.receipt.status = 'rolled-back'
    Set-WindowsCopilotJsonFile -Value $currentState.receipt -Path $currentState.path -Depth 4
    return [pscustomobject]@{
        status = if ($environmentAlreadyRestored -and $restored.Count -eq 0) {
            'already-rolled-back'
        } else {
            'rolled-back'
        }
        changed = [bool](-not $environmentAlreadyRestored -or $restored.Count -gt 0)
        operationId = $OperationId
        restoredUserValue = $previousUserValue
        restoredShims = @($restored)
    }
}

function Restore-WindowsCopilotForkCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$NpmGlobalRoot,
        [string]$OperationId
    )
    $mutex = Enter-WindowsCopilotActivationLock -BackupRoot $BackupRoot
    try {
        return Invoke-WindowsCopilotForkCoreRollback @PSBoundParameters
    } finally {
        Exit-WindowsCopilotActivationLock -Mutex $mutex
    }
}

function Restart-WindowsCopilotDesktop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DesktopExecutablePath,
        $CliInfo,
        [int]$TimeoutSeconds = 90,
        [switch]$DryRun,
        [object[]]$Processes
    )
    $executable = Resolve-DeploymentPath $DesktopExecutablePath
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        throw "Desktop executable not found: '$executable'."
    }
    if ($null -eq $Processes) {
        $Processes = @(Get-CimInstance Win32_Process |
            Select-Object ProcessId, ParentProcessId, Name, ExecutablePath, CommandLine)
    }
    $desktopProcesses = @($Processes | Where-Object {
        $_.ExecutablePath -and
        [IO.Path]::GetFullPath([string]$_.ExecutablePath) -ieq $executable
    })
    if ($DryRun) {
        return [pscustomobject]@{
            status = 'would-restart'
            executable = $executable
            processIds = @($desktopProcesses.ProcessId)
        }
    }
    foreach ($process in $desktopProcesses) {
        Stop-Process -Id ([int]$process.ProcessId) -Force
    }
    Start-Process -FilePath $executable | Out-Null
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastError = $null
    do {
        Start-Sleep -Milliseconds 500
        $current = @(Get-CimInstance Win32_Process |
            Select-Object ProcessId, ParentProcessId, Name, ExecutablePath, CommandLine)
        $currentDesktop = @($current | Where-Object {
            $_.ExecutablePath -and
            [IO.Path]::GetFullPath([string]$_.ExecutablePath) -ieq $executable
        })
        if (-not $CliInfo -and $currentDesktop.Count -gt 0) {
            return [pscustomobject]@{
                status = 'restarted'
                executable = $executable
                stoppedProcessIds = @($desktopProcesses.ProcessId)
                backendProcessIds = @()
                backendVerification = 'not-applicable-after-rollback'
            }
        }
        try {
            $active = Test-DshActiveDesktopCore -CliInfo $CliInfo -Processes $current `
                -DesktopExecutablePath $executable
            return [pscustomobject]@{
                status = 'restarted'
                executable = $executable
                stoppedProcessIds = @($desktopProcesses.ProcessId)
                backendProcessIds = @($active.processIds)
            }
        } catch {
            $lastError = $_.Exception.Message
        }
    } while ((Get-Date) -lt $deadline)
    throw "Desktop restarted, but its backend command line did not select the fork Core within $TimeoutSeconds seconds. Last check: $lastError"
}

function Test-WindowsCopilotForkCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$NpmGlobalRoot,
        [string]$CoreInstallPrefix,
        [string]$DshCliPath,
        [string]$DesktopRoot,
        [string]$DesktopExecutablePath,
        [object[]]$DesktopProcesses,
        [switch]$SkipRuntimeChecks
    )
    $activation = Get-WindowsCopilotCoreActivationState -Lock $Lock -NpmGlobalRoot $NpmGlobalRoot `
        -CoreInstallPrefix $CoreInstallPrefix -DshCliPath $DshCliPath
    $sandbox = if (-not $activation.core.valid) {
        [pscustomobject]@{ valid = $false; status = 'receipt-invalid' }
    } else {
        try {
            $result = Test-DshSandboxRegression -PackageRoot ([string]$activation.core.packageRoot) `
                -ProbeScript (Join-Path $PSScriptRoot 'dsh-sandbox-regression-probe.mjs') `
                -Mode ([string]$Lock.acceptance.sandbox.gate)
            $valid = [bool](
                [string]$result.capability -ceq [string]$Lock.acceptance.sandbox.capability -and
                [int]$result.sameAndNarrowerApprovalCalls -eq 0 -and
                [int]$result.widerApprovalCalls -eq [int]$Lock.acceptance.sandbox.widerApprovalCount
            )
            $result | Add-Member -MemberType NoteProperty -Name valid -Value $valid -Force
            $result
        } catch {
            [pscustomobject]@{ valid = $false; status = 'failed'; reason = $_.Exception.Message }
        }
    }
    $activeCore = if ($SkipRuntimeChecks) {
        [pscustomobject]@{ valid = $true; status = 'skipped' }
    } elseif (-not $activation.core.valid) {
        [pscustomobject]@{ valid = $false; status = 'receipt-invalid' }
    } else {
        $desktop = Get-WindowsCopilotDesktopState -Lock $Lock -Path $DesktopExecutablePath
        if (-not $desktop.valid) {
            [pscustomobject]@{
                valid = $false
                status = 'locked-desktop-not-found'
                path = $desktop.path
            }
        } else {
            try {
                $active = Test-DshActiveDesktopCore -CliInfo $activation.core -DesktopRoot $DesktopRoot `
                    -DesktopExecutablePath ([string]$desktop.path) -Processes $DesktopProcesses
                [pscustomobject]@{
                    valid = [bool]$active.healthy
                    status = 'fork-core-command-line-active'
                    processIds = @($active.processIds)
                }
            } catch {
                [pscustomobject]@{
                    valid = $false
                    status = 'fork-core-command-line-inactive'
                    reason = $_.Exception.Message
                }
            }
        }
    }
    return [pscustomobject]@{
        valid = [bool]($activation.valid -and $sandbox.valid -and $activeCore.valid)
        expectedRepository = [string]$Lock.components.core.source.repository
        expectedCommit = [string]$Lock.components.core.source.commit
        expectedVersion = [string]$Lock.components.core.package.version
        expectedCapability = [string]$Lock.acceptance.sandbox.capability
        activation = $activation
        sandbox = $sandbox
        activeCore = $activeCore
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
        [string]$CoreInstallPrefix,
        [string]$DshCliPath,
        [string]$DesktopExecutablePath,
        [string]$DesktopVersion,
        [string]$GatewayExecutablePath,
        [string]$GatewaySha256,
        [string]$DesktopRoot,
        [object[]]$DesktopProcesses,
        [switch]$SkipRuntimeChecks
    )
    Test-WindowsCopilotLock -Lock $Lock | Out-Null
    $home = Resolve-DeploymentPath $DshHome
    $profileRoot = Join-Path $home ([string]$Lock.profile.relativePath)
    $packagePath = Join-Path $profileRoot ([string]$Lock.profile.packageManifest)
    $workspacePath = Join-Path $profileRoot ([string]$Lock.profile.workspaceManifest)
    $settingsPath = Join-Path $home ([string]$Lock.profile.settingsManifest)
    $desktop = Get-WindowsCopilotDesktopState -Lock $Lock -Path $DesktopExecutablePath -Version $DesktopVersion
    $legacyGateway = Get-WindowsCopilotLegacyGatewayState -Lock $Lock `
        -Path $GatewayExecutablePath -Sha256 $GatewaySha256
    $coreReceipt = Get-WindowsCopilotCoreReceiptState -Lock $Lock -NpmGlobalRoot $NpmGlobalRoot `
        -CoreInstallPrefix $CoreInstallPrefix -DshCliPath $DshCliPath
    $credential = Test-DshCopilotCredentialRecord -DshHome $home
    $providerRoute = Get-DshCopilotRouteState -SettingsPath $settingsPath

    $profile = $null
    if (Test-Path -LiteralPath $packagePath -PathType Leaf) {
        try { $profile = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    }
    $dependencyValid = $false
    $bundleValid = $false
    $providerDependency = $null
    $legacyCopilotStates = [Collections.Generic.List[object]]::new()
    if ($profile) {
        $dependencies = Get-LockProperty -InputObject $profile -Name 'dependencies'
        if ($dependencies) {
            $dependencyValid = $true
            foreach ($plugin in @($Lock.profile.plugins | Where-Object { $_.materialize -eq $true })) {
                $name = [string]$plugin.name
                $dependency = [string](Get-LockProperty -InputObject $dependencies -Name $name)
                if ($name -eq [string]$Lock.components.copilotIntegration.package.name) {
                    $providerDependency = $dependency
                }
                $expected = if ($name -eq [string]$Lock.components.copilotIntegration.package.name) {
                    'file:../../artifacts/' + [string]$Lock.components.copilotIntegration.source.commit + '/' +
                        [string]$Lock.components.copilotIntegration.package.artifact.name
                } else {
                    [string]$plugin.version
                }
                if ($dependency.Replace('\', '/') -ne $expected) { $dependencyValid = $false }
            }
        }
        $dsh = Get-LockProperty -InputObject $profile -Name 'dsh'
        $profileManifest = if ($dsh) { Get-LockProperty -InputObject $dsh -Name 'profile' } else { $null }
        $bundles = if ($profileManifest) { @(Get-LockProperty -InputObject $profileManifest -Name 'bundles') } else { @() }
        foreach ($legacyIntegration in @($Lock.profile.legacyCopilotIntegrations)) {
            $legacyName = [string]$legacyIntegration.name
            $legacyDependency = if ($dependencies) {
                [string](Get-LockProperty -InputObject $dependencies -Name $legacyName)
            } else { '' }
            if (-not $legacyDependency) { continue }
            $legacyArtifactPattern = '^.*[/\\]' +
                [regex]::Escape([string]$legacyIntegration.artifactPattern).Replace('\*', '.*') + '$'
            if ($legacyDependency -cne [string]$legacyIntegration.version -and
                $legacyDependency -notmatch $legacyArtifactPattern) {
                continue
            }
            $legacyRoot = Join-Path $profileRoot (Join-Path 'node_modules' $legacyName)
            $installedVersion = $null
            try {
                $legacyMetadata = Get-Content -LiteralPath (Join-Path $legacyRoot 'package.json') `
                    -Raw -Encoding UTF8 | ConvertFrom-Json
                $installedVersion = [string]$legacyMetadata.version
            } catch { }
            $legacyCopilotStates.Add([pscustomobject]@{
                name = $legacyName
                lockedLegacyVersion = [string]$legacyIntegration.version
                dependency = $legacyDependency
                installedVersion = $installedVersion
                bundleActive = [bool]($bundles -contains $legacyName)
            })
        }
        if ($legacyCopilotStates.Count -gt 0) { $dependencyValid = $false }
        $bundleValid = $true
        foreach ($requiredBundle in @($Lock.profile.requiredBundles)) {
            if (@($bundles | Where-Object { $_ -eq [string]$requiredBundle }).Count -ne 1) {
                $bundleValid = $false
            }
            if (@($Lock.profile.legacyCopilotIntegrations.name | Select-Object -Unique | Where-Object {
                [string]$_ -cne [string]$Lock.components.copilotIntegration.package.name -and
                $bundles -contains [string]$_
            }).Count -gt 0) {
                $bundleValid = $false
            }
        }
    }

    $internalPluginStates = @(Get-WindowsCopilotInternalPluginStates -Lock $Lock -ProfileRoot $profileRoot `
        -DesktopExecutablePath ([string]$desktop.path))
    $plugins = foreach ($plugin in @($Lock.profile.plugins)) {
        if ([string]$plugin.source -eq 'desktop-internal') {
            $internal = @($internalPluginStates | Where-Object { $_.name -eq [string]$plugin.name })[0]
            [pscustomobject]@{
                name = [string]$plugin.name
                source = [string]$plugin.source
                materialize = $false
                exists = [bool]$internal.exists
                physical = $false
                officialDesktopLink = [bool]$internal.valid
                target = $internal.target
                expectedTarget = $internal.expectedTarget
                version = $internal.version
                versionValid = [bool]$internal.versionValid
                baselineValid = $true
                baselineStatus = 'not-applicable'
                payloadValid = $true
                payloadStatus = 'official-desktop-internal'
                payloadReason = $null
            }
            continue
        }
        $path = Join-Path $profileRoot (Join-Path 'node_modules' ([string]$plugin.name))
        $exists = Test-Path -LiteralPath (Join-Path $path 'package.json') -PathType Leaf
        $physical = $false
        $version = $null
        $baselineValid = $true
        $baselineStatus = 'not-applicable'
        $payloadValid = $true
        $payloadStatus = 'not-applicable'
        $payloadReason = $null
        if ($exists) {
            $physical = -not [bool]((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint)
            try {
                $metadata = Get-Content -LiteralPath (Join-Path $path 'package.json') -Raw -Encoding UTF8 | ConvertFrom-Json
                $version = [string]$metadata.version
            } catch { }
            if ([string]$plugin.name -eq [string]$Lock.components.copilotIntegration.package.name) {
                $payloadStatus = 'verified'
                $providerRoot = [IO.Path]::GetFullPath($path).TrimEnd('\') + '\'
                foreach ($relativePath in @(
                    [string]$metadata.main,
                    [string]$metadata.types,
                    [string]$metadata.dsh.bundle.patch
                )) {
                    $payloadPath = [IO.Path]::GetFullPath((Join-Path $path $relativePath))
                    if (-not $payloadPath.StartsWith($providerRoot, [StringComparison]::OrdinalIgnoreCase) -or
                        -not (Test-Path -LiteralPath $payloadPath -PathType Leaf)) {
                        $payloadValid = $false
                        $payloadStatus = 'entrypoint-missing-or-invalid'
                    }
                }
                if ($payloadValid) {
                    $lockedProviderArtifact = Join-Path $home (
                        'artifacts\' + [string]$Lock.components.copilotIntegration.source.commit + '\' +
                        [string]$Lock.components.copilotIntegration.package.artifact.name
                    )
                    try {
                        Test-LockedArtifact -Path $lockedProviderArtifact `
                            -Sha256 ([string]$Lock.components.copilotIntegration.package.artifact.sha256) `
                            -ExpectedName ([string]$Lock.components.copilotIntegration.package.artifact.name) | Out-Null
                        foreach ($relativePath in @($Lock.components.copilotIntegration.package.attestedFiles)) {
                            $normalizedRelativePath = ([string]$relativePath).Replace('/', '\')
                            $installedPath = [IO.Path]::GetFullPath((Join-Path $path $normalizedRelativePath))
                            if (-not $installedPath.StartsWith($providerRoot, [StringComparison]::OrdinalIgnoreCase)) {
                                throw "Provider attestation path escapes the package: '$relativePath'."
                            }
                            $artifactSha = Get-TarEntrySha256 -ArtifactPath $lockedProviderArtifact `
                                -EntryPath ('package/' + ([string]$relativePath).Replace('\', '/'))
                            $installedSha = (Get-FileHash -LiteralPath $installedPath -Algorithm SHA256).Hash
                            if ($installedSha -ine $artifactSha) {
                                throw "Installed provider file differs from the locked artifact: '$relativePath'."
                            }
                        }
                    } catch {
                        $payloadValid = $false
                        $payloadReason = $_.Exception.Message
                        $payloadStatus = if ($_.Exception.Message -like '*Installed provider file differs*') {
                            'installed-file-mismatch'
                        } else {
                            'locked-artifact-missing-or-invalid'
                        }
                    }
                }
                $baselinePath = Join-Path $path 'deployment-baseline.json'
                if (-not (Test-Path -LiteralPath $baselinePath -PathType Leaf)) {
                    $baselineValid = $false
                    $baselineStatus = 'missing'
                } else {
                    try {
                        $baseline = Get-Content -LiteralPath $baselinePath -Raw -Encoding UTF8 | ConvertFrom-Json
                        Assert-ProviderBaselineData -Lock $Lock -Package $metadata -Baseline $baseline
                        $baselineStatus = 'verified'
                    } catch {
                        $baselineValid = $false
                        $baselineStatus = 'invalid'
                    }
                }
            }
        } elseif ([string]$plugin.name -eq [string]$Lock.components.copilotIntegration.package.name) {
            $baselineValid = $false
            $baselineStatus = 'provider-missing'
            $payloadValid = $false
            $payloadStatus = 'provider-missing'
        }
        [pscustomobject]@{
            name = [string]$plugin.name
            source = [string]$plugin.source
            materialize = [bool]$plugin.materialize
            exists = [bool]$exists
            physical = [bool]$physical
            officialDesktopLink = $false
            version = $version
            versionValid = [bool]($version -eq [string]$plugin.version)
            baselineValid = [bool]$baselineValid
            baselineStatus = $baselineStatus
            payloadValid = [bool]$payloadValid
            payloadStatus = $payloadStatus
            payloadReason = $payloadReason
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

    $routesValid = [bool]($providerRoute.exists -and $providerRoute.referenceFree)

    $listeners = if ($SkipRuntimeChecks) {
        @($Lock.acceptance.listeners | ForEach-Object {
            [pscustomobject]@{
                host = $_.host
                port = $_.port
                status = 'skipped'
                loopbackOnly = $false
                bindingVerified = $false
                owningProcessIds = @()
            }
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
    $activeCore = if ($SkipRuntimeChecks) {
        [pscustomobject]@{ valid = $false; status = 'skipped' }
    } elseif (-not $coreReceipt.valid) {
        [pscustomobject]@{ valid = $false; status = 'receipt-invalid' }
    } else {
        try {
            if (-not $DesktopRoot) { $DesktopRoot = $env:DSH_DESKTOP_ROOT }
            $active = Test-DshActiveDesktopCore -CliInfo $coreReceipt -DesktopRoot $DesktopRoot `
                -DesktopExecutablePath ([string]$desktop.path) -Processes $DesktopProcesses
            $desktopListener = @($listeners | Where-Object { [int]$_.port -eq 3080 })
            $ownerProcessIds = @()
            if ($desktopListener.Count -eq 1) {
                $ownerProcessIds = @($desktopListener[0].owningProcessIds)
            }
            $listenerBound = [bool](
                $desktopListener.Count -eq 1 -and
                $desktopListener[0].bindingVerified -and
                $desktopListener[0].loopbackOnly -and
                $ownerProcessIds.Count -eq 1 -and
                @($active.processIds | Where-Object { [int]$_ -eq [int]$ownerProcessIds[0] }).Count -eq 1
            )
            [pscustomobject]@{
                valid = [bool]($active.healthy -and $listenerBound)
                status = if ($listenerBound) {
                    'receipted-core-owns-3080'
                } else {
                    'receipted-core-listener-owner-mismatch'
                }
                processIds = @($active.processIds)
                listenerOwnerProcessIds = @($ownerProcessIds)
                listenerBound = $listenerBound
                reason = $null
            }
        } catch {
            [pscustomobject]@{
                valid = $false
                status = 'receipted-core-not-active'
                reason = $_.Exception.Message
            }
        }
    }
    $sandbox = if ($SkipRuntimeChecks) {
        [pscustomobject]@{ valid = $false; status = 'skipped' }
    } elseif (-not $coreReceipt.valid) {
        [pscustomobject]@{ valid = $false; status = 'receipt-invalid' }
    } else {
        try {
            $sandboxResult = Test-DshSandboxRegression -PackageRoot ([string]$coreReceipt.packageRoot) `
                -ProbeScript (Join-Path $PSScriptRoot 'dsh-sandbox-regression-probe.mjs') `
                -Mode ([string]$Lock.acceptance.sandbox.gate)
            $sandboxResult | Add-Member -MemberType NoteProperty -Name valid `
                -Value ([bool]($sandboxResult.status -eq 'passed')) -Force
            $sandboxResult
        } catch {
            [pscustomobject]@{
                valid = $false
                status = 'failed'
                reason = $_.Exception.Message
            }
        }
    }

    $catalogCheck = [pscustomobject]@{
        valid = [bool]($credential.configured -and $providerRoute.exists -and $providerRoute.referenceFree)
        status = if (-not $credential.configured) { 'sign-in-required' } else { [string]$providerRoute.status }
        source = 'built-in-pi-ai-account-route'
        modelCount = @($providerRoute.availableModels).Count
    }

    try {
        if ($ComposedConfigPath) {
            $composedContent = Get-Content -LiteralPath $ComposedConfigPath -Raw -Encoding UTF8
            $composedCheck = Get-WindowsCopilotComposedConfigState -Lock $Lock -Content $composedContent
        } elseif ($SkipRuntimeChecks) {
            $composedCheck = [pscustomobject]@{
                valid = $false
                status = 'skipped'
                reasons = @('composed-config-skipped')
                forbiddenMarkers = @()
                forbiddenActiveEntries = @()
                managedConfigValid = $false
            }
        } else {
            $command = @($Lock.acceptance.composedConfig.command)
            if (-not $coreReceipt.valid) {
                throw 'The local Core receipt is not valid; refusing to execute an unattested CLI.'
            }
            $executable = [string]$coreReceipt.cliPath
            if (-not $executable -or -not (Test-Path -LiteralPath $executable -PathType Leaf)) {
                throw 'The attested Core CLI candidate is unavailable for composed-config validation.'
            }
            $arguments = @($command[1..($command.Count - 1)] | ForEach-Object { [string]$_ })
            $output = & $executable @arguments 2>$null | Out-String
            if ($LASTEXITCODE -ne 0) { throw 'dsh dump-config failed.' }
            $composedCheck = Get-WindowsCopilotComposedConfigState -Lock $Lock -Content $output
        }
    } catch {
        $composedCheck = [pscustomobject]@{
            valid = $false
            status = 'unavailable-or-invalid'
            reasons = @('composed-config-unavailable-or-invalid')
            forbiddenMarkers = @()
            forbiddenActiveEntries = @()
            managedConfigValid = $false
        }
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
        $desktop.valid -and
        $coreReceipt.valid -and
        $dependencyValid -and
        $bundleValid -and
        $allowBuildsValid -and
        $routesValid -and
        $credential.configured -and
        @($plugins | Where-Object {
            -not $_.exists -or -not $_.versionValid -or
            ($_.materialize -and -not $_.physical) -or
            ($_.source -eq 'desktop-internal' -and -not $_.officialDesktopLink) -or
            -not $_.baselineValid -or -not $_.payloadValid
        }).Count -eq 0
    )
    $runtimeValid = [bool](
        -not $SkipRuntimeChecks -and
        @($listeners | Where-Object { -not $_.loopbackOnly }).Count -eq 0 -and
        $loaderImports.valid -and
        $activeCore.valid -and
        $sandbox.valid -and
        $catalogCheck.valid -and
        $composedCheck.valid
    )
    $provider = @($plugins | Where-Object {
        $_.name -eq [string]$Lock.components.copilotIntegration.package.name
    })[0]
    $driftReasons = [Collections.Generic.List[string]]::new()
    if ($desktop.newerThanLock) { $driftReasons.Add('desktop-newer-than-lock') }
    elseif (-not $desktop.valid) { $driftReasons.Add('desktop-version-mismatch') }
    if ($legacyGateway.detected) { $driftReasons.Add('legacy-copilot2api-detected') }
    if (-not $coreReceipt.valid) { $driftReasons.Add('core-' + [string]$coreReceipt.status) }
    elseif (-not $activeCore.valid) {
        if ($activeCore.status -eq 'receipted-core-listener-owner-mismatch') {
            $driftReasons.Add('core-receipted-process-does-not-own-3080')
        } else {
            $driftReasons.Add('core-receipted-package-not-active-under-desktop')
        }
    }
    if (-not $SkipRuntimeChecks -and -not $sandbox.valid) {
        $driftReasons.Add('core-sandbox-regression-gate-failed')
    }
    if (-not $dependencyValid) { $driftReasons.Add('provider-dependency-unlocked') }
    if (-not $bundleValid) { $driftReasons.Add('profile-bundle-drift') }
    if (-not $allowBuildsValid) { $driftReasons.Add('profile-allow-builds-drift') }
    if (-not $credential.configured) { $driftReasons.Add('copilot-sign-in-required') }
    if (-not $routesValid) {
        $driftReasons.Add($(if ($providerRoute.status -eq 'legacy-reference-route') {
            'legacy-copilot-route-active'
        } else {
            'profile-route-drift'
        }))
    }
    if (-not $provider.exists) { $driftReasons.Add('provider-missing') }
    elseif (-not $provider.physical) { $driftReasons.Add('provider-not-physical') }
    if (-not $provider.versionValid) { $driftReasons.Add('provider-version-mismatch') }
    if (-not $provider.baselineValid) { $driftReasons.Add('provider-baseline-' + [string]$provider.baselineStatus) }
    if (-not $provider.payloadValid) { $driftReasons.Add('provider-payload-' + [string]$provider.payloadStatus) }
    if (@($plugins | Where-Object {
        $_.source -eq 'desktop-internal' -and
        (-not $_.officialDesktopLink -or -not $_.versionValid)
    }).Count -gt 0) {
        $driftReasons.Add('desktop-internal-plugin-link-drift')
    }
    foreach ($reason in @($composedCheck.reasons)) {
        if ($driftReasons -notcontains [string]$reason) { $driftReasons.Add([string]$reason) }
    }
    foreach ($legacyState in @($legacyCopilotStates)) {
        $legacyVersion = ([string]$legacyState.lockedLegacyVersion).Replace('.', '-')
        $driftReasons.Add("legacy-dsh-web-search-provider-$legacyVersion-active")
    }
    $legacy022 = @($legacyCopilotStates | Where-Object {
        [string]$_.lockedLegacyVersion -eq '0.2.2'
    } | Select-Object -First 1)
    $incidentDetected = [bool](
        $desktop.version -eq '0.9.2' -and
        $desktop.valid -and
        $legacy022.Count -eq 1 -and
        [string]$legacy022[0].installedVersion -eq '0.2.2' -and
        $coreReceipt.status -eq 'receipt-missing' -and
        @($composedCheck.forbiddenActiveEntries) -contains 'web-search-provider' -and
        @($composedCheck.forbiddenMarkers) -contains 'searchProvider: deepseek-official' -and
        -not $composedCheck.managedConfigValid
    )
    $driftDetected = [bool]($driftReasons.Count -gt 0)
    $remediation = Get-WindowsCopilotRemediation -Desktop $desktop -CoreReceipt $coreReceipt -DriftDetected $driftDetected
    $installationComplete = [bool]($staticValid -and $runtimeValid -and $searchCheck.valid)
    $readyForManualSearchSmoke = [bool]($staticValid -and $runtimeValid -and -not $searchCheck.valid)
    return [pscustomobject]@{
        complete = $installationComplete
        readyForManualSearchSmoke = $readyForManualSearchSmoke
        health = if ($installationComplete) {
            'healthy'
        } elseif (-not $credential.configured -and
            @($driftReasons | Where-Object { $_ -notin @('copilot-sign-in-required', 'profile-route-drift') }).Count -eq 0) {
            'sign-in-required'
        } elseif ($driftDetected) {
            'drifted'
        } elseif ($readyForManualSearchSmoke) {
            'search-smoke-required'
        } else {
            'unhealthy'
        }
        deployment = [pscustomobject]@{
            desktop = $desktop
            core = $coreReceipt
            copilotIntegration = $provider
        }
        drift = [pscustomobject]@{
            detected = $driftDetected
            incidentId = if ($incidentDetected) { 'windows-copilot-drift-2026-08-28' } else { $null }
            mixedState = [bool]($desktop.valid -and (-not $provider.versionValid -or -not $coreReceipt.valid))
            reasons = @($driftReasons)
            remediation = $remediation
        }
        migration = [pscustomobject]@{
            legacyGateway = $legacyGateway
            backupRequired = [bool]$Lock.migration.legacyGateway.backupRequired
        }
        profile = [pscustomobject]@{
            dependencyValid = $dependencyValid
            copilotIntegrationDependency = $providerDependency
            providerDependency = $providerDependency
            legacyCopilotIntegrations = @($legacyCopilotStates)
            bundleValid = $bundleValid
            allowBuildsValid = $allowBuildsValid
            routesValid = $routesValid
            providerRoute = $providerRoute
            credential = $credential
            plugins = @($plugins)
        }
        runtime = [pscustomobject]@{
            listeners = @($listeners)
            loaderImports = $loaderImports
            activeCore = $activeCore
            sandbox = $sandbox
            directProvider = $catalogCheck
            composedConfig = $composedCheck
            searchSmoke = $searchCheck
        }
    }
}

function Invoke-WindowsCopilotApplyLocked {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$DshHome,
        [Parameter(Mandatory)][string]$NpmGlobalRoot,
        [Parameter(Mandatory)][string]$HarnessSourceRoot,
        [Parameter(Mandatory)][Alias('ProviderSourceRoot')][string]$CopilotIntegrationSourceRoot,
        [Parameter(Mandatory)][string]$DesktopArtifactPath,
        [string]$GatewayArtifactPath,
        [string]$GatewayInstallRoot,
        [string]$GatewayExecutablePath,
        [Parameter(Mandatory)][string]$CoreInstallPrefix,
        [Parameter(Mandatory)][string]$BackupRoot,
        $Catalog,
        [string]$DesktopExecutablePath,
        [switch]$RestartDesktop,
        [int]$TimeoutSeconds = 90
    )
    Test-WindowsCopilotLock -Lock $Lock | Out-Null
    Assert-WindowsCopilotNoPendingActivation -Lock $Lock -BackupRoot $BackupRoot
    $desktopState = Get-WindowsCopilotDesktopState -Lock $Lock -Path $DesktopExecutablePath
    if ($desktopState.newerThanLock) {
        throw "Installed Desktop $($desktopState.version) is newer than locked Desktop $($desktopState.lockedVersion). Refusing a downgrade; update the lock or use a reviewed compatible migration."
    }
    Assert-CoreInstallPrefixIsolation -Lock $Lock -CoreInstallPrefix $CoreInstallPrefix `
        -DshHome $DshHome -BackupRoot $BackupRoot -HarnessSourceRoot $HarnessSourceRoot `
        -CopilotIntegrationSourceRoot $CopilotIntegrationSourceRoot -NpmGlobalRoot $NpmGlobalRoot `
        -DesktopArtifactPath $DesktopArtifactPath -DesktopExecutablePath $DesktopExecutablePath | Out-Null
    Get-WindowsCopilotProfileMigrationPlan -Lock $Lock -DshHome $DshHome `
        -DesktopExecutablePath ([string]$desktopState.path) | Out-Null
    $settingsPath = Join-Path (Resolve-DeploymentPath $DshHome) ([string]$Lock.profile.settingsManifest)
    Assert-WindowsCopilotSettingsShape -Lock $Lock -SettingsPath $settingsPath
    Assert-SourceCheckout -Root $HarnessSourceRoot -Source $Lock.components.core.source
    Assert-SourceCheckout -Root $CopilotIntegrationSourceRoot -Source $Lock.components.copilotIntegration.source
    Test-CopilotIntegrationDeploymentContract -Lock $Lock -SourceRoot $CopilotIntegrationSourceRoot | Out-Null
    Test-LockedArtifact -Path $DesktopArtifactPath `
        -Sha256 ([string]$Lock.components.desktop.artifact.sha256) `
        -ExpectedName ([string]$Lock.components.desktop.artifact.name) | Out-Null
    Assert-WindowsCopilotCoreConflictSafe -Lock $Lock -NpmGlobalRoot $NpmGlobalRoot `
        -SelectedCliPath (Join-Path (Resolve-DeploymentPath $CoreInstallPrefix) 'dsh.cmd') | Out-Null

    Invoke-PinnedPnpmCommands -PackageManager ([string]$Lock.components.core.package.packageManager) `
        -Commands @($Lock.components.core.build.commands) -WorkingDirectory $HarnessSourceRoot
    $coreRelease = Get-CoreReleaseArtifacts -Lock $Lock -Root $HarnessSourceRoot
    $coreInstall = Install-WindowsCopilotCoreRelease -Lock $Lock -SourceRoot $HarnessSourceRoot `
        -NpmGlobalRoot $NpmGlobalRoot -CoreInstallPrefix $CoreInstallPrefix -CoreRelease $coreRelease
    $installedCore = Get-WindowsCopilotCoreReceiptState -Lock $Lock -NpmGlobalRoot $NpmGlobalRoot `
        -CoreInstallPrefix $CoreInstallPrefix
    if (-not $installedCore.valid) {
        throw "Installed fork Core receipt validation failed before deployment mutation: '$($installedCore.status)'."
    }
    Assert-WindowsCopilotCoreCapability -Lock $Lock -Core $installedCore | Out-Null

    $providerLib = Join-Path $CopilotIntegrationSourceRoot 'lib'
    if (Test-Path -LiteralPath $providerLib) { Remove-Item -LiteralPath $providerLib -Recurse -Force }
    Invoke-PinnedPnpmCommands -PackageManager ([string]$Lock.components.copilotIntegration.package.packageManager) `
        -Commands @($Lock.components.copilotIntegration.build.commands) -WorkingDirectory $CopilotIntegrationSourceRoot
    $copilotIntegrationArtifact = Get-OnlyBuiltArtifact -Root $CopilotIntegrationSourceRoot `
        -Pattern ([string]$Lock.components.copilotIntegration.build.artifactPattern)
    Test-CopilotIntegrationDeploymentContract -Lock $Lock -ArtifactPath $copilotIntegrationArtifact | Out-Null

    $operationRoot = New-BackupOperation -BackupRoot $BackupRoot -DshHome $DshHome
    $legacyGatewayTarget = if ($GatewayExecutablePath) {
        $GatewayExecutablePath
    } elseif ($GatewayInstallRoot) {
        Join-Path $GatewayInstallRoot 'copilot2api.exe'
    } else {
        $null
    }
    if ($legacyGatewayTarget -and (Test-Path -LiteralPath $legacyGatewayTarget -PathType Leaf)) {
        $legacyGateway = Get-WindowsCopilotLegacyGatewayState -Lock $Lock -Path $legacyGatewayTarget
        if (-not $legacyGateway.matchesReviewedLegacy) {
            throw 'A legacy gateway binary was found but does not match the reviewed migration contract.'
        }
        Backup-DeploymentPath -Path $legacyGatewayTarget -RelativePath 'migration\copilot2api.exe' `
            -OperationRoot $operationRoot
        Remove-Item -LiteralPath $legacyGatewayTarget -Force
    }

    $globalSpecs = @($Lock.globalInstall.packages | ForEach-Object { "$($_.name)@$($_.version)" })
    $globalSpecs += $copilotIntegrationArtifact
    Invoke-LockedCommand -FilePath 'npm' -Arguments (@('install', '--global') + $globalSpecs) -WorkingDirectory $HarnessSourceRoot

    if (-not $desktopState.valid) {
        $desktopProcess = Start-Process -FilePath $DesktopArtifactPath `
            -ArgumentList @($Lock.components.desktop.install.arguments) -Wait -PassThru
        if (@($Lock.components.desktop.install.acceptedExitCodes) -notcontains [int]$desktopProcess.ExitCode) {
            throw "Desktop installer exited with code $($desktopProcess.ExitCode)."
        }
        $desktopState = Get-WindowsCopilotDesktopState -Lock $Lock -Path $DesktopExecutablePath
        if (-not $desktopState.valid) {
            throw 'Desktop installer completed but the exact locked official Desktop is not installed.'
        }
    }

    $profileReceipt = Set-WindowsCopilotProfile -Lock $Lock -DshHome $DshHome `
        -NpmGlobalRoot $NpmGlobalRoot -CopilotIntegrationArtifactPath $copilotIntegrationArtifact `
        -Catalog $Catalog -BackupRoot $BackupRoot -OperationRoot $operationRoot `
        -DesktopExecutablePath ([string]$desktopState.path)
    $activation = Enable-WindowsCopilotForkCore -Lock $Lock -NpmGlobalRoot $NpmGlobalRoot `
        -CoreInstallPrefix $CoreInstallPrefix -BackupRoot $BackupRoot -OperationRoot $operationRoot
    $restart = if ($RestartDesktop) {
        Restart-WindowsCopilotDesktop -DesktopExecutablePath ([string]$desktopState.path) `
            -CliInfo $activation.core -TimeoutSeconds $TimeoutSeconds
    } else {
        [pscustomobject]@{
            status = 'not-requested'
            executable = [string]$desktopState.path
        }
    }

    return [pscustomobject]@{
        mode = 'apply'
        deploymentId = [string]$Lock.deploymentId
        deploymentOperationId = Split-Path -Leaf $operationRoot
        activationOperationId = $activation.operationId
        globalTransaction = [string]$Lock.globalInstall.transactionId
        coreArtifacts = @($coreRelease.packages)
        coreReceipt = $coreInstall
        copilotIntegrationArtifactSha256 = (
            Get-FileHash -LiteralPath $copilotIntegrationArtifact -Algorithm SHA256
        ).Hash.ToLowerInvariant()
        providerArtifactSha256 = (
            Get-FileHash -LiteralPath $copilotIntegrationArtifact -Algorithm SHA256
        ).Hash.ToLowerInvariant()
        profile = $profileReceipt
        activation = $activation
        desktopRestart = $restart
        nextCheck = 'Run tools\install-windows-copilot.ps1 -Action Verify with the same CoreInstallPrefix.'
    }
}

function Invoke-WindowsCopilotApply {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$DshHome,
        [Parameter(Mandatory)][string]$NpmGlobalRoot,
        [Parameter(Mandatory)][string]$HarnessSourceRoot,
        [Parameter(Mandatory)][Alias('ProviderSourceRoot')][string]$CopilotIntegrationSourceRoot,
        [Parameter(Mandatory)][string]$DesktopArtifactPath,
        [string]$GatewayArtifactPath,
        [string]$GatewayInstallRoot,
        [string]$GatewayExecutablePath,
        [Parameter(Mandatory)][string]$CoreInstallPrefix,
        [Parameter(Mandatory)][string]$BackupRoot,
        $Catalog,
        [string]$DesktopExecutablePath,
        [switch]$RestartDesktop,
        [int]$TimeoutSeconds = 90
    )
    $mutex = Enter-WindowsCopilotActivationLock -BackupRoot $BackupRoot
    try {
        return Invoke-WindowsCopilotApplyLocked @PSBoundParameters
    } finally {
        Exit-WindowsCopilotActivationLock -Mutex $mutex
    }
}

Export-ModuleMember -Function @(
    'Read-WindowsCopilotLock',
    'Test-WindowsCopilotLock',
    'Test-LockedArtifact',
    'Test-CopilotIntegrationDeploymentContract',
    'Test-ProviderDeploymentContract',
    'Assert-CoreInstallPrefixIsolation',
    'Install-WindowsCopilotCoreRelease',
    'Get-WindowsCopilotInstallPlan',
    'Get-WindowsCopilotRouteModels',
    'Set-PnpmAllowBuilds',
    'Set-WindowsCopilotRoutes',
    'Set-WindowsCopilotProfile',
    'Test-WindowsCopilotSearchResponse',
    'Test-WindowsCopilotComposedConfig',
    'Get-WindowsCopilotDesktopState',
    'Get-WindowsCopilotCoreConflictState',
    'Assert-WindowsCopilotCoreConflictSafe',
    'Get-WindowsCopilotCoreActivationState',
    'Enable-WindowsCopilotForkCore',
    'Restore-WindowsCopilotForkCore',
    'Restart-WindowsCopilotDesktop',
    'Test-WindowsCopilotForkCore',
    'Test-WindowsCopilotInstallation',
    'Invoke-WindowsCopilotApply'
)
