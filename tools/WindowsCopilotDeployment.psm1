Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'DshCopilotBootstrap.psm1')
Import-Module (Join-Path $PSScriptRoot 'DshRuntimeSchema.psm1')

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

function Get-WindowsCopilotRuntimeSelector {
    param([Parameter(Mandatory)]$Lock)
    $selectors = @($Lock.components.desktop.runtimeSelectors)
    if ($selectors.Count -ne 1 -or
        [string]$Lock.components.desktop.defaultRuntimeSelector -cne 'desktop-official' -or
        [string]$selectors[0].id -cne 'desktop-official') {
        throw 'The deployment lock must define only the desktop-official runtime selector.'
    }
    return $selectors[0]
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
        $Value,
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
        'components.desktop.artifact.size',
        'components.desktop.installedExecutable.relativePath',
        'components.desktop.installedExecutable.sha256',
        'components.desktop.installedExecutable.size',
        'components.desktop.installedExecutable.productName',
        'components.desktop.installedExecutable.fileDescription',
        'components.desktop.installedExecutable.companyName',
        'components.desktop.installedExecutable.productVersion',
        'components.desktop.installedExecutable.authenticodeStatus',
        'components.desktop.installedResources.relativePath',
        'components.desktop.installedResources.fileCount',
        'components.desktop.installedResources.totalBytes',
        'components.desktop.installedResources.treeSha256',
        'components.desktop.installedResources.reparseDirectoryCount',
        'components.desktop.install.arguments',
        'components.desktop.install.acceptedExitCodes',
        'components.desktop.install.sideEffects.registryKeys',
        'components.desktop.install.sideEffects.shortcuts',
        'components.desktop.defaultRuntimeSelector',
        'components.desktop.runtimeSelectors',
        'components.copilotIntegration.source.repository',
        'components.copilotIntegration.source.pullRequest',
        'components.copilotIntegration.source.commit',
        'components.copilotIntegration.source.reviewedHead',
        'components.copilotIntegration.source.mergeCommit',
        'components.copilotIntegration.package.name',
        'components.copilotIntegration.package.version',
        'components.copilotIntegration.package.packageManager',
        'components.copilotIntegration.package.main',
        'components.copilotIntegration.package.types',
        'components.copilotIntegration.package.bundlePatch',
        'components.copilotIntegration.package.attestedFiles',
        'components.copilotIntegration.package.artifact.name',
        'components.copilotIntegration.package.artifact.url',
        'platform.runtimeConstraint.node',
        'platform.verifiedWith.node',
        'platform.verifiedWith.npm',
        'platform.verifiedWith.pnpm',
        'platform.observedCompatible.node',
        'components.desktop.shippedDependencies',
        'components.copilotIntegration.package.artifact.sha256',
        'components.copilotIntegration.package.artifact.releaseTag',
        'components.copilotIntegration.package.artifact.releaseCommit',
        'components.copilotIntegration.package.artifact.releaseImmutable',
        'components.copilotIntegration.package.artifact.size',
        'components.copilotIntegration.package.artifact.checksumManifest.name',
        'components.copilotIntegration.package.artifact.checksumManifest.url',
        'components.copilotIntegration.package.artifact.checksumManifest.sha256',
        'components.copilotIntegration.package.artifact.checksumManifest.size',
        'components.copilotIntegration.package.deploymentBaseline.id',
        'components.copilotIntegration.package.deploymentBaseline.kind',
        'components.copilotIntegration.package.deploymentBaseline.sourceCommitPolicy',
        'components.copilotIntegration.build.artifactPattern',
        'components.copilotIntegration.build.commands',
        'profile.lockManifest',
        'profile.legacyPhysicalPlugins',
        'profile.legacyCopilotIntegrations',
        'profile.requiredBundles',
        'profile.coherence.copilotProfiles',
        'profile.optionalOverlays',
        'companionSuite.id',
        'companionSuite.profile',
        'companionSuite.includeParameter',
        'companionSuite.members',
        'companionSuite.acceptance',
        'acceptance.credential.record',
        'acceptance.credential.kind',
        'acceptance.credential.missingStatus',
        'acceptance.providerRoute.settingsNamespace',
        'acceptance.providerRoute.provider',
        'acceptance.providerRoute.forbiddenKeys',
        'acceptance.providerRoute.legacyConnectionFieldsRemovedByDeployment',
        'acceptance.providerRoute.reconciliationOwnedPaths',
        'acceptance.providerRoute.repairTrigger',
        'acceptance.providerRoute.repairStates',
        'acceptance.providerRoute.requiredModelFields',
        'acceptance.providerRoute.requiredApis',
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
        'acceptance.runtimeSchema.scope',
        'acceptance.runtimeSchema.releaseStatus',
        'acceptance.runtimeSchema.source.repository',
        'acceptance.runtimeSchema.source.releaseTag',
        'acceptance.runtimeSchema.root',
        'acceptance.runtimeSchema.source.commit',
        'acceptance.runtimeSchema.wrapper.name',
        'acceptance.runtimeSchema.wrapper.version',
        'acceptance.runtimeSchema.wrapper.manifest',
        'acceptance.runtimeSchema.wrapper.manifestSha256',
        'acceptance.runtimeSchema.wrapper.fileCount',
        'acceptance.runtimeSchema.wrapper.totalBytes',
        'acceptance.runtimeSchema.wrapper.treeSha256',
        'acceptance.runtimeSchema.wrapper.reparseDirectoryCount',
        'acceptance.runtimeSchema.package.name',
        'acceptance.runtimeSchema.package.version',
        'acceptance.runtimeSchema.package.manifest',
        'acceptance.runtimeSchema.package.entrypoint',
        'acceptance.runtimeSchema.package.entrypointSize',
        'acceptance.runtimeSchema.package.entrypointSha256',
        'acceptance.runtimeSchema.requiredBuiltFiles',
        'acceptance.runtimeSchema.behavior.escalationProperties',
        'acceptance.runtimeSchema.behavior.escalationPropertiesRequired',
        'acceptance.runtimeSchema.behavior.providerCompatibilityOwner',
        'acceptance.copilotToolSchema.provider',
        'acceptance.copilotToolSchema.forbiddenProperties',
        'acceptance.copilotToolSchema.successMarkers',
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

    if ([string]$Lock.platform.runtimeConstraint.node -cne '^22.19.0 || >=24.0.0' -or
        [string]$Lock.platform.verifiedWith.pnpm -cne
            [string]$Lock.components.copilotIntegration.package.packageManager.Replace('pnpm@', '') -or
        [string]$Lock.platform.observedCompatible.pnpm -cne '11.7.0') {
        throw 'Platform contract must separate runtime compatibility from exact build-tool evidence.'
    }
    $desktopVersion = [string]$Lock.components.desktop.version
    $expectedDesktopArtifactName = "Deepseek.Harness.Desktop_${desktopVersion}_x64-setup.exe"
    $expectedDesktopArtifactUrl =
        "https://github.com/dsh-tauri-desk/deepseek-harness-desktop/releases/download/v${desktopVersion}/${expectedDesktopArtifactName}"
    if ($desktopVersion -cne '0.10.3' -or
        [string]$Lock.components.desktop.source.releaseTag -cne 'v0.10.3' -or
        [string]$Lock.components.desktop.artifact.name -cne $expectedDesktopArtifactName -or
        [string]$Lock.components.desktop.artifact.url -cne $expectedDesktopArtifactUrl) {
        throw 'Desktop identity must match the official 0.10.3 Release.'
    }
    $installedDesktop = $Lock.components.desktop.installedExecutable
    if ([string]$installedDesktop.relativePath -cne 'deepseek-harness-desktop.exe' -or
        [string]$installedDesktop.sha256 -cne
            'd191cb2729f53c4fa889fab62c48af38979812f5560d0bb8f8ad4cadeff8b5df' -or
        [int64]$installedDesktop.size -ne 23059456 -or
        [string]$installedDesktop.productName -cne 'Deepseek Harness Desktop' -or
        [string]$installedDesktop.fileDescription -cne 'Deepseek Harness Desktop' -or
        [string]$installedDesktop.companyName -cne 'github' -or
        [string]$installedDesktop.productVersion -cne '0.10.3' -or
        [string]$installedDesktop.authenticodeStatus -cne 'NotSigned') {
        throw 'Installed Desktop executable identity must match the reviewed official 0.10.3 bytes.'
    }
    $copilotSource = $Lock.components.copilotIntegration.source
    if ([string]$copilotSource.repository -cne 'https://github.com/cloga/dsh-github-copilot' -or
        [int]$copilotSource.pullRequest -ne 56 -or
        [string]$copilotSource.commit -cne '4e095196197570776515423929ddb72e8299c1db' -or
        [string]$copilotSource.reviewedHead -cne '4e095196197570776515423929ddb72e8299c1db' -or
        [string]$copilotSource.mergeCommit -cne '473b8aa174eb47a323b026c098b73bf7d716772c') {
        throw 'Copilot integration source must match reviewed PR #56 and its exact merge identity.'
    }

    foreach ($commit in @(
        [string]$Lock.components.desktop.source.commit,
        [string](Get-WindowsCopilotRuntimeSelector -Lock $Lock).package.commit,
        [string]$Lock.components.copilotIntegration.source.commit,
        [string]$Lock.components.copilotIntegration.source.reviewedHead,
        [string]$Lock.components.copilotIntegration.source.mergeCommit,
        [string]$Lock.components.copilotIntegration.package.artifact.releaseCommit,
        [string]$Lock.acceptance.runtimeSchema.source.commit
    )) {
        if ($commit -notmatch '^[0-9a-f]{40}$') { throw "Invalid locked commit: $commit" }
    }
    foreach ($overlay in @($Lock.profile.optionalOverlays)) {
        foreach ($commit in @([string]$overlay.sourceCommit, [string]$overlay.resolvedCommit)) {
            if ($commit -notmatch '^[0-9a-f]{40}$') {
                throw "Invalid optional-overlay commit for '$([string]$overlay.name)': $commit"
            }
        }
    }
    $runtimeSchema = $Lock.acceptance.runtimeSchema
    $runtimeFiles = @($runtimeSchema.requiredBuiltFiles)
    $runtimeSelector = Get-WindowsCopilotRuntimeSelector -Lock $Lock
    $expectedRuntimeFiles = @(
        [pscustomobject]@{
            path = 'node_modules\@deepseek-ai\dsh-tools\lib\index.js'
            size = 151923
            sha256 = '598d5a54cfed9fdc497b8504aefb464efe97ff6c6918e68888481bb6e3dfbda9'
        },
        [pscustomobject]@{
            path = 'node_modules\@deepseek-ai\dsh-tool-pwsh\lib\index.js'
            size = 20501
            sha256 = 'c1dd78a35722e47eaeef57b33d15d4170f4bb27db2bee15da76a6d4ea9557e63'
        },
        [pscustomobject]@{
            path = 'node_modules\@deepseek-ai\dsh-sandbox\lib\index.js'
            size = 10754
            sha256 = '8994b3e497b0673eddd3640392de4671621aa8972846f4a66d0b1219decf3c03'
        }
    )
    $runtimeEscalationProperties = @(
        $runtimeSchema.behavior.escalationProperties | ForEach-Object { [string]$_ }
    )
    if ([string]$runtimeSchema.scope -cne 'desktop-official' -or
        [string]$runtimeSchema.releaseStatus -cne 'official-desktop-managed' -or
        [string]$runtimeSchema.root -cne [string]$runtimeSelector.root -or
        [string]$runtimeSchema.source.repository -cne 'github.com/deepseek-ai/deepseek-harness' -or
        [string]$runtimeSchema.source.releaseTag -cne [string]$runtimeSelector.package.releaseTag -or
        [string]$runtimeSchema.source.commit -cne [string]$runtimeSelector.package.commit -or
        [string]$runtimeSchema.wrapper.name -cne [string]$runtimeSelector.rootPackage.name -or
        [string]$runtimeSchema.wrapper.version -cne [string]$runtimeSelector.rootPackage.version -or
        [string]$runtimeSchema.wrapper.manifest -cne [string]$runtimeSelector.rootPackage.manifest -or
        [string]$runtimeSchema.wrapper.manifestSha256 -cne
            'bcfbd3f14511fa9470ea748303a8f9c6307121d2741990823089c5677291e8ba' -or
        [int]$runtimeSchema.wrapper.fileCount -ne 10347 -or
        [int64]$runtimeSchema.wrapper.totalBytes -ne 134066533 -or
        [string]$runtimeSchema.wrapper.treeSha256 -cne
            'b0f32889536e1bce92a6bc032b11a6865e946015b44de5db4397f080e309c86d' -or
        [int]$runtimeSchema.wrapper.reparseDirectoryCount -ne 0 -or
        [string]$runtimeSchema.package.name -cne [string]$runtimeSelector.package.name -or
        [string]$runtimeSchema.package.version -cne [string]$runtimeSelector.package.version -or
        [string]$runtimeSchema.package.manifest -cne [string]$runtimeSelector.package.manifest -or
        [string]$runtimeSchema.package.entrypoint -cne [string]$runtimeSelector.package.entrypoint -or
        [int64]$runtimeSchema.package.entrypointSize -ne
            [int64]$runtimeSelector.package.entrypointSize -or
        [string]$runtimeSchema.package.entrypointSha256 -cne
            [string]$runtimeSelector.package.entrypointSha256 -or
        $runtimeFiles.Count -ne 3 -or
        @($expectedRuntimeFiles | Where-Object {
            $expected = $_
            @($runtimeFiles | Where-Object {
                [string]$_.path -ceq [string]$expected.path -and
                [int64]$_.size -eq [int64]$expected.size -and
                [string]$_.sha256 -ceq [string]$expected.sha256
            }).Count -ne 1
        }).Count -gt 0 -or
        $runtimeEscalationProperties.Count -ne 2 -or
        $runtimeEscalationProperties -cnotcontains 'sandbox_permissions' -or
        $runtimeEscalationProperties -cnotcontains 'justification' -or
        $runtimeSchema.behavior.escalationPropertiesRequired -ne $false -or
        [string]$runtimeSchema.behavior.providerCompatibilityOwner -cne 'dsh-github-copilot') {
        throw 'Runtime schema identity must match the official Desktop-managed runtime.'
    }
    $copilotToolSchema = $Lock.acceptance.copilotToolSchema
    $copilotForbiddenProperties = @($copilotToolSchema.forbiddenProperties | ForEach-Object { [string]$_ })
    $copilotSuccessMarkers = @($copilotToolSchema.successMarkers | ForEach-Object { [string]$_ })
    if ([string]$copilotToolSchema.provider -cne 'github-copilot' -or
        [string]$copilotToolSchema.package.name -cne 'dsh-github-copilot' -or
        [string]$copilotToolSchema.package.version -cne
            [string]$Lock.components.copilotIntegration.package.version -or
        [int]$copilotToolSchema.source.pullRequest -ne
            [int]$Lock.components.copilotIntegration.source.pullRequest -or
        [string]$copilotToolSchema.source.commit -cne
            [string]$Lock.components.copilotIntegration.source.commit -or
        [string]$copilotToolSchema.source.mergeCommit -cne
            [string]$Lock.components.copilotIntegration.source.mergeCommit -or
        $copilotForbiddenProperties.Count -ne 2 -or
        $copilotForbiddenProperties -cnotcontains 'sandbox_permissions' -or
        $copilotForbiddenProperties -cnotcontains 'justification' -or
        $copilotToolSchema.preserveForOtherProviders -ne $true -or
        $copilotToolSchema.requiresFreshSession -ne $true -or
        $copilotSuccessMarkers -cnotcontains 'PACKAGED_COPILOT_SCHEMA_FILTER_OK' -or
        $copilotSuccessMarkers -cnotcontains 'FRESH_SESSION_PACKAGED_FILTER_OK') {
        throw 'Copilot tool-schema acceptance must pin provider-only removal and fresh-Session proof.'
    }
    foreach ($sha in @(
        [string]$Lock.components.desktop.artifact.sha256,
        [string]$Lock.components.copilotIntegration.package.artifact.sha256,
        [string]$Lock.components.copilotIntegration.package.artifact.checksumManifest.sha256
    )) {
        if ($sha -notmatch '^[0-9a-f]{64}$') { throw "Invalid locked artifact SHA-256: $sha" }
    }
    if ($Lock.components.PSObject.Properties['core']) {
        throw 'The deployment lock must not define a separately managed Core.'
    }
    $officialSelector = Get-WindowsCopilotRuntimeSelector -Lock $Lock
    if ([string]$officialSelector.id -cne 'desktop-official' -or
        [string]$officialSelector.source -cne 'desktop-managed-download' -or
        [string]$officialSelector.desktopVersion -cne [string]$Lock.components.desktop.version -or
        [string]$officialSelector.package.name -cne '@deepseek-ai/dsh' -or
        [string]$officialSelector.package.version -cne
            [string]$Lock.components.copilotIntegration.package.deploymentBaseline.dshRelease -or
        [string]$officialSelector.package.releaseTag -cne 'dsh-v0.1.2-rc.1' -or
        [string]$officialSelector.package.commit -cne
            'a66e4702047846cdaa10c66c9d3df3951f5ea70d' -or
        [string]$officialSelector.root -cne
            '%APPDATA%\io.github.hairyf.deepseek-harness-desktop\dependencies\dsh' -or
        [string]$officialSelector.rootPackage.name -cne 'deepseek-harness-pkg' -or
        [string]$officialSelector.rootPackage.version -cne '0.1.2-alpha.5' -or
        [string]$officialSelector.rootPackage.manifest -cne 'package.json' -or
        [string]$officialSelector.rootPackage.manifestSha256 -cne
            'bcfbd3f14511fa9470ea748303a8f9c6307121d2741990823089c5677291e8ba' -or
        [int]$officialSelector.rootPackage.fileCount -ne 10347 -or
        [int64]$officialSelector.rootPackage.totalBytes -ne 134066533 -or
        [string]$officialSelector.rootPackage.treeSha256 -cne
            'b0f32889536e1bce92a6bc032b11a6865e946015b44de5db4397f080e309c86d' -or
        [int]$officialSelector.rootPackage.reparseDirectoryCount -ne 0 -or
        [string]$officialSelector.package.manifest -cne
            'node_modules\@deepseek-ai\dsh\package.json' -or
        [string]$officialSelector.package.entrypoint -cne
            'node_modules\@deepseek-ai\dsh\lib\bin.js' -or
        [int]$officialSelector.package.fileCount -le 0 -or
        [string]$officialSelector.package.treeSha256 -notmatch '^[0-9a-f]{64}$' -or
        [int]$officialSelector.package.entrypointSize -ne 8021 -or
        [string]$officialSelector.package.entrypointSha256 -cne
            'dc23f6c5dd7df8834e3e38bdb9609d77b459834681ae9b7133b417b0c35f3166') {
        throw 'The Desktop official runtime selector does not match the reviewed Desktop 0.10.3 dependency contract.'
    }
    $expectedProviderArtifactUrl = 'https://github.com/cloga/dsh-github-copilot/releases/download/v' +
        [string]$Lock.components.copilotIntegration.package.version + '/' +
        [string]$Lock.components.copilotIntegration.package.artifact.name
    $providerArtifact = $Lock.components.copilotIntegration.package.artifact
    $expectedProviderArtifactName = 'dsh-github-copilot-' +
        [string]$Lock.components.copilotIntegration.package.version + '.tgz'
    $expectedProviderReleaseTag = 'v' + [string]$Lock.components.copilotIntegration.package.version
    $expectedChecksumUrl = 'https://github.com/cloga/dsh-github-copilot/releases/download/' +
        $expectedProviderReleaseTag + '/SHA256SUMS'
    if ([string]$providerArtifact.name -cne $expectedProviderArtifactName -or
        [string]$providerArtifact.url -cne $expectedProviderArtifactUrl -or
        [string]$providerArtifact.releaseTag -cne $expectedProviderReleaseTag -or
        [string]$providerArtifact.releaseCommit -cne
            '473b8aa174eb47a323b026c098b73bf7d716772c' -or
        $providerArtifact.releaseImmutable -ne $true -or
        [int]$providerArtifact.size -le 0 -or
        [string]$providerArtifact.sha256 -notmatch '^[0-9a-f]{64}$' -or
        [string]$providerArtifact.checksumManifest.name -cne 'SHA256SUMS' -or
        [string]$providerArtifact.checksumManifest.url -cne $expectedChecksumUrl -or
        [int]$providerArtifact.checksumManifest.size -le 0 -or
        [string]$providerArtifact.checksumManifest.sha256 -notmatch '^[0-9a-f]{64}$') {
        throw 'Provider artifact must match the canonical immutable Release and SHA256SUMS contract.'
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
    $expectedProviderBuildCommands = @(
        'install --frozen-lockfile',
        'run verify',
        'pack --pack-destination .\dist'
    )
    $providerBuildCommands = @($Lock.components.copilotIntegration.build.commands | ForEach-Object {
        @($_ | ForEach-Object { [string]$_ }) -join ' '
    })
    if ($providerBuildCommands.Count -ne $expectedProviderBuildCommands.Count) {
        throw 'Provider build contract must preserve the verified clean-source command sequence.'
    }
    for ($index = 0; $index -lt $expectedProviderBuildCommands.Count; $index++) {
        if ($providerBuildCommands[$index] -cne $expectedProviderBuildCommands[$index]) {
            throw 'Provider build contract must run the complete plugin verification gate before packing.'
        }
    }
    if (@($Lock.components.desktop.install.arguments).Count -eq 0 -or
        @($Lock.components.desktop.install.acceptedExitCodes).Count -eq 0) {
        throw 'Desktop install arguments and accepted exit codes must be locked.'
    }
    if (@($Lock.components.desktop.install.sideEffects.registryKeys).Count -ne 1 -or
        [string]$Lock.components.desktop.install.sideEffects.registryKeys[0] -cne
            'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\Deepseek Harness Desktop' -or
        @($Lock.components.desktop.install.sideEffects.shortcuts).Count -ne 2 -or
        @($Lock.components.desktop.install.sideEffects.shortcuts.specialFolder) -cnotcontains
            'Desktop' -or
        @($Lock.components.desktop.install.sideEffects.shortcuts.specialFolder) -cnotcontains
            'Programs') {
        throw 'Desktop installer side effects must lock its uninstall key and shortcuts.'
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
        'dsh-tauri-panel-scheduler',
        'dsh-tauri-rightclick',
        'dsh-tauri-session',
        'dsh-tauri-ui',
        'dsh-tauri-worktree'
    )
    $internalPlugins = @($Lock.components.desktop.internalPlugins)
    if ($internalPlugins.Count -ne $internalPluginNames.Count) {
        throw 'Desktop must lock exactly eight official profile plugins.'
    }
    foreach ($name in $internalPluginNames) {
        $matches = @($internalPlugins | Where-Object {
            [string]$_.name -ceq $name -and [string]$_.version -ceq '0.6.7' -and
            [string]$_.relativePath -ceq "resources\node_modules\$name"
        })
        if ($matches.Count -ne 1) { throw "Desktop internal-plugin contract omits '$name@0.6.7'." }
    }
    $shippedDependencies = @($Lock.components.desktop.shippedDependencies)
    if ($shippedDependencies.Count -ne 1 -or
        [string]$shippedDependencies[0].name -cne 'dsh-tauri-panel-placeholder' -or
        [string]$shippedDependencies[0].version -cne '0.6.7' -or
        [string]$shippedDependencies[0].relativePath -cne
            'resources\node_modules\dsh-tauri-panel-placeholder' -or
        $shippedDependencies[0].profileBundle -ne $false) {
        throw 'Desktop shipped-dependency contract must attest the non-bundled panel placeholder.'
    }

    $copilotPackageName = [string]$Lock.components.copilotIntegration.package.name
    $requiredPlugins = @($internalPluginNames + $copilotPackageName)
    $plugins = @($Lock.profile.plugins)
    if ($plugins.Count -ne $requiredPlugins.Count) {
        throw 'Profile must define exactly eight official Desktop links and the Copilot plugin.'
    }
    foreach ($name in $internalPluginNames) {
        $matches = @($plugins | Where-Object {
            [string]$_.name -ceq $name -and [string]$_.version -ceq '0.6.7' -and
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
    $expectedLegacyIdentities = @(
        'dsh-web-search-provider@0.2.2',
        'dsh-web-search-provider@0.2.3-cloga.3'
    ) + @(1..13 | ForEach-Object { "dsh-github-copilot@0.3.0-cloga.$_" })
    $actualLegacyIdentities = @($legacyCopilotIntegrations | ForEach-Object {
        "$([string]$_.name)@$([string]$_.version)"
    })
    if ($actualLegacyIdentities.Count -ne $expectedLegacyIdentities.Count) {
        throw 'Profile migration must detect the reviewed legacy search providers and Copilot plugins.'
    }
    foreach ($identity in $expectedLegacyIdentities) {
        if (@($actualLegacyIdentities | Where-Object { $_ -ceq $identity }).Count -ne 1) {
            throw 'Profile migration must detect the reviewed legacy search providers and Copilot plugins.'
        }
    }
    $requiredBundles = @($Lock.profile.requiredBundles)
    $expectedRequiredBundles = @('@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app') + $requiredPlugins
    if ($requiredBundles.Count -ne $expectedRequiredBundles.Count) {
        throw 'Profile requiredBundles must contain exactly the official base, Web, Desktop, and Copilot bundles.'
    }
    foreach ($name in $expectedRequiredBundles) {
        if (@($requiredBundles | Where-Object { $_ -eq $name }).Count -ne 1) {
            throw "Profile requiredBundles must contain '$name' exactly once."
        }
    }
    $coherence = $Lock.profile.coherence
    if (@($coherence.copilotProfiles).Count -ne 2 -or
        @($coherence.copilotProfiles) -cnotcontains 'web' -or
        @($coherence.copilotProfiles) -cnotcontains 'headless' -or
        $coherence.requireManifestLockInstalledMatch -ne $true -or
        $coherence.checkModeMutates -ne $false) {
        throw 'Profile coherence must cover web and headless without mutating check mode.'
    }
    $optionalOverlays = @($Lock.profile.optionalOverlays)
    $expectedOptionalOverlays = [ordered]@{
        'dsh-playwright-host' = [ordered]@{
            version = '0.1.2'
            source = 'github:cloga/dsh-playwright-host#v0.1.2'
            sourceCommit = 'a7f63e2c3565008e1c614023afb1c3110fd62fff'
            resolvedCommit = '2cf6edfd52b5a70b3f6af7b1f502c58718a6f5ac'
            pullRequest = 6
        }
        'dsh-cron' = [ordered]@{
            version = '0.4.1'
            source = 'github:cloga/dsh-cron#v0.4.1'
            sourceCommit = 'e0ecca9e18a66fe0acecec6dfc6cc6faaa9520b2'
            resolvedCommit = '5f99313e110932195821d924259b2836947271f3'
            pullRequest = 12
        }
    }
    if ($optionalOverlays.Count -ne $expectedOptionalOverlays.Count) {
        throw 'Profile optional-overlay inventory must contain exactly the reviewed browser and scheduler additions.'
    }
    foreach ($name in $expectedOptionalOverlays.Keys) {
        $expectedOverlay = $expectedOptionalOverlays[$name]
        $matches = @($optionalOverlays | Where-Object {
            [string]$_.name -ceq $name -and
            [string]$_.version -ceq [string]$expectedOverlay.version -and
            [string]$_.source -ceq [string]$expectedOverlay.source -and
            [string]$_.sourceCommit -ceq [string]$expectedOverlay.sourceCommit -and
            [string]$_.resolvedCommit -ceq [string]$expectedOverlay.resolvedCommit -and
            [int]$_.pullRequest -eq [int]$expectedOverlay.pullRequest -and
            [string]$_.profile -ceq 'web' -and $_.required -eq $false
        })
        if ($matches.Count -ne 1) { throw "Optional overlay inventory omits '$name'." }
    }
    $playwrightOverlay = @($optionalOverlays | Where-Object { [string]$_.name -ceq 'dsh-playwright-host' })[0]
    $playwrightArtifact = $playwrightOverlay.artifact
    if ([string]$playwrightArtifact.name -cne 'dsh-playwright-host-0.1.2.tgz' -or
        [string]$playwrightArtifact.url -cne
            'https://github.com/cloga/dsh-playwright-host/releases/download/v0.1.2/dsh-playwright-host-0.1.2.tgz' -or
        [string]$playwrightArtifact.sha256 -cne
            '18e4e2d29429a94f495d9507188282e6157f11c2ef75fa076b54b30c03ac0cf2' -or
        [int]$playwrightArtifact.size -ne 3659 -or
        [string]$playwrightArtifact.releaseTag -cne 'v0.1.2' -or
        $playwrightArtifact.releaseImmutable -ne $true -or
        [string]$playwrightArtifact.checksumManifest.name -cne 'SHA256SUMS' -or
        [string]$playwrightArtifact.checksumManifest.url -cne
            'https://github.com/cloga/dsh-playwright-host/releases/download/v0.1.2/SHA256SUMS' -or
        [string]$playwrightArtifact.checksumManifest.sha256 -cne
            '06647ede584dad3055508733f17cd720f4ebf149c2cd73d680497e7117247e84' -or
        [int]$playwrightArtifact.checksumManifest.size -ne 96) {
        throw 'Optional dsh-playwright-host artifact must match the immutable v0.1.2 Release and SHA256SUMS.'
    }
    $cronOverlay = @($optionalOverlays | Where-Object { [string]$_.name -ceq 'dsh-cron' })[0]
    $cronArtifact = $cronOverlay.artifact
    if ([string]$cronArtifact.name -cne 'dsh-cron-0.4.1.tgz' -or
        [string]$cronArtifact.url -cne
            'https://github.com/cloga/dsh-cron/releases/download/v0.4.1/dsh-cron-0.4.1.tgz' -or
        [string]$cronArtifact.sha256 -cne
            '9be9e7c6ea1b4bf8a6f354dd1533e8a920f4d397c09fb20e14a2b5c91a50ce5f' -or
        [int]$cronArtifact.size -ne 34276 -or
        [string]$cronArtifact.releaseTag -cne 'v0.4.1' -or
        $cronArtifact.releaseImmutable -ne $true -or
        [string]$cronArtifact.checksumManifest.name -cne 'SHA256SUMS' -or
        [string]$cronArtifact.checksumManifest.url -cne
            'https://github.com/cloga/dsh-cron/releases/download/v0.4.1/SHA256SUMS' -or
        [string]$cronArtifact.checksumManifest.sha256 -cne
            'ad66a15d46072952f250001e875331b2dbc7bf2b5db615481d72a3e1e7925bbf' -or
        [int]$cronArtifact.checksumManifest.size -ne 85) {
        throw 'Optional dsh-cron artifact must match the immutable v0.4.1 Release and SHA256SUMS.'
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
    if ([string]$Lock.acceptance.composedConfig.execution -cne 'active-runtime-entry' -or
        [string]$Lock.acceptance.composedConfig.command[0] -cne '<active-runtime-entry>' -or
        @($Lock.acceptance.composedConfig.requiredMarkers) -notcontains 'dsh-github-copilot' -or
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
    $providerRoute = $Lock.acceptance.providerRoute
    if ($providerRoute.legacyConnectionFieldsRemovedByDeployment -ne $true -or
        @($providerRoute.reconciliationOwnedPaths).Count -ne 2 -or
        @($providerRoute.reconciliationOwnedPaths) -notcontains 'providers.github-copilot.models' -or
        @($providerRoute.reconciliationOwnedPaths) -notcontains 'providers.github-copilot.compat.supportsStrictMode' -or
        [string]$providerRoute.repairTrigger -cne 'existing-valid-grant' -or
        @($providerRoute.repairStates).Count -ne 5 -or
        @($providerRoute.repairStates) -notcontains 'route-missing' -or
        @($providerRoute.repairStates) -notcontains 'route-has-no-models' -or
        @($providerRoute.repairStates) -notcontains 'route-account-models-stale' -or
        @($providerRoute.repairStates) -notcontains 'route-model-api-missing' -or
        @($providerRoute.repairStates) -notcontains 'route-mixed-protocol-apis-missing' -or
        @($providerRoute.requiredModelFields).Count -ne 2 -or
        @($providerRoute.requiredModelFields) -notcontains 'id' -or
        @($providerRoute.requiredModelFields) -notcontains 'api' -or
        @($providerRoute.requiredApis).Count -ne 2 -or
        @($providerRoute.requiredApis) -notcontains 'openai-responses' -or
        @($providerRoute.requiredApis) -notcontains 'openai-completions') {
        throw 'Provider route contract must require existing-grant repair and complete mixed protocol model entries.'
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
    $baseline = $Lock.components.copilotIntegration.package.deploymentBaseline
    $expectedCapabilities = @(
        'client-module-loader-handoff',
        'strict-remote-result-codecs',
        'authorization-service-bootstrap',
        'models-provider-card-authorization',
        'path-level-account-model-reconciliation',
        'copilot-optional-tool-arguments',
        'per-model-api-route-materialization',
        'existing-grant-route-self-healing',
        'shared-copilot-credential-refresh',
        'strict-json-oauth-grant-normalization',
        'direct-provider-hosted-search',
        'traditional-search-bridge',
        'dsh-supported-baselines-fail-loud-guard',
        'dsh-rc2-models-settings-fallback'
    )
    $lockedCapabilities = @($baseline.requiredCapabilities)
    if ($lockedCapabilities.Count -ne $expectedCapabilities.Count) {
        throw 'Copilot integration baseline must lock exactly fourteen required capabilities.'
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
        [string]$baseline.dshRelease -ne '0.1.2-rc.1' -or
        [string]$baseline.dshDevelopmentRelease -ne '0.1.1-rc.2' -or
        [string]$baseline.dshPeerRange -ne '0.1.1-rc.2 || 0.1.2-rc.1' -or
        [string]$baseline.piAi -ne '^0.84.2' -or
        [string]$baseline.runtimeDependencies.'@deepseek-ai/dsh-authorization' -ne
            '0.1.1-rc.2 || 0.1.2-rc.1' -or
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
    $companionOverlays = @(Get-WindowsCopilotCompanionOverlays -Lock $Lock)
    if ($companionOverlays.Count -ne 2 -or
        @($companionOverlays.name) -notcontains 'dsh-cron' -or
        @($companionOverlays.name) -notcontains 'dsh-playwright-host' -or
        $Lock.companionSuite.acceptance.requiresHostRestart -ne $true -or
        @($Lock.companionSuite.acceptance.cron.requiredTools) -notcontains 'cron_list' -or
        @($Lock.companionSuite.acceptance.playwright.requiredTools) -notcontains
            'mcp__playwright__browser_snapshot' -or
        $Lock.companionSuite.acceptance.playwright.isolatedBrowser -ne $true) {
        throw 'The companion suite contract omits reviewed membership or acceptance.'
    }

    return [pscustomobject]@{
        valid = $true
        deploymentId = [string]$Lock.deploymentId
        requiredComponents = 2
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

function Assert-NoReparsePointAncestor {
    param([Parameter(Mandatory)][string]$Path)

    $cursor = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path))
    while ($cursor) {
        $item = Get-DeploymentPathItem -Path $cursor
        if ($item) {
            if ([bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw "Deployment path must not use reparse-point path '$cursor'."
            }
        }
        $parent = [IO.Directory]::GetParent($cursor)
        if ($null -eq $parent) { break }
        $cursor = $parent.FullName
    }
}

function Test-LockedArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Sha256,
        [string]$ExpectedName,
        [long]$ExpectedSize
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Locked artifact not found: $Path"
    }
    if ($ExpectedName -and (Split-Path -Leaf $Path) -ne $ExpectedName) {
        throw "Locked artifact name mismatch for '$Path'; expected '$ExpectedName'."
    }
    if ($ExpectedSize -gt 0 -and (Get-Item -LiteralPath $Path).Length -ne $ExpectedSize) {
        throw "Locked artifact size mismatch for '$Path'; expected $ExpectedSize bytes."
    }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Sha256.ToLowerInvariant()) {
        throw "SHA-256 mismatch for '$Path'."
    }

    return [pscustomobject]@{ path = (Resolve-DeploymentPath $Path); sha256 = $actual; valid = $true }
}

function Get-WindowsCopilotCompanionOverlays {
    param([Parameter(Mandatory)]$Lock)
    $members = @($Lock.companionSuite.members)
    $expected = [ordered]@{
        'dsh-github-copilot' = $true
        'dsh-cron' = $false
        'dsh-playwright-host' = $false
    }
    if ([string]$Lock.companionSuite.id -cne 'windows-companion-suite' -or
        [string]$Lock.companionSuite.profile -cne 'web' -or
        [string]$Lock.companionSuite.includeParameter -cne 'IncludeCompanionSuite' -or
        $members.Count -ne $expected.Count) {
        throw 'The companion suite contract must define the exact reviewed Windows suite.'
    }
    foreach ($name in $expected.Keys) {
        $matches = @($members | Where-Object {
            [string]$_.name -ceq $name -and
            [bool]$_.requiredByBaseDeployment -eq [bool]$expected[$name]
        })
        if ($matches.Count -ne 1) {
            throw "The companion suite contract has an invalid role for '$name'."
        }
    }
    return @($members | Where-Object { -not $_.requiredByBaseDeployment } | ForEach-Object {
        $member = $_
        $name = [string]$member.name
        $overlay = @($Lock.profile.optionalOverlays | Where-Object {
            [string]$_.name -ceq $name
        })
        if ($overlay.Count -ne 1 -or
            [string]$member.identitySource -cne 'profile.optionalOverlays') {
            throw "The companion suite identity source is invalid for '$name'."
        }
        $overlay[0]
    })
}

function Save-WindowsCopilotLockedArtifact {
    param(
        [Parameter(Mandatory)]$Artifact,
        [Parameter(Mandatory)][string]$Destination
    )
    $path = Resolve-DeploymentPath $Destination
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
        $temporary = $path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
        try {
            Invoke-WebRequest -Uri ([string]$Artifact.url) -OutFile $temporary -UseBasicParsing
            Test-LockedArtifact -Path $temporary -Sha256 ([string]$Artifact.sha256) `
                -ExpectedSize ([long]$Artifact.size) | Out-Null
            Move-Item -LiteralPath $temporary -Destination $path -Force
        } finally {
            if (Test-Path -LiteralPath $temporary) {
                Remove-Item -LiteralPath $temporary -Force
            }
        }
    }
    return Test-LockedArtifact -Path $path -Sha256 ([string]$Artifact.sha256) `
        -ExpectedName ([string]$Artifact.name) -ExpectedSize ([long]$Artifact.size)
}

function Test-WindowsCopilotInstalledArtifactClosure {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$ArtifactPath,
            [Parameter(Mandatory)][string]$InstalledRoot,
            [Parameter(Mandatory)][string]$Sha256,
            [string]$ExpectedName,
            [long]$ExpectedSize
        )
        Test-LockedArtifact -Path $ArtifactPath -Sha256 $Sha256 `
            -ExpectedName $ExpectedName -ExpectedSize $ExpectedSize | Out-Null
        if (-not (Test-Path -LiteralPath $InstalledRoot -PathType Container)) {
            return [pscustomobject]@{
                valid = $false
                status = 'installed-package-missing'
                installedRoot = $InstalledRoot
            }
        }
        $temporary = Join-Path ([IO.Path]::GetTempPath()) (
            'dsh-artifact-closure-' + [guid]::NewGuid().ToString('N')
        )
        New-Item -ItemType Directory -Path $temporary -Force | Out-Null
        try {
            $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
            & $tar -xzf $ArtifactPath -C $temporary
            if ($LASTEXITCODE -ne 0) {
                throw "Could not extract locked artifact '$ArtifactPath'."
            }
            $expectedRoot = Join-Path $temporary 'package'
            if (-not (Test-Path -LiteralPath $expectedRoot -PathType Container)) {
                throw 'Locked package artifact has no package root.'
            }
            $expected = Get-WindowsCopilotDirectoryTreeState -Path $expectedRoot
            $installed = Get-WindowsCopilotDirectoryTreeState -Path $InstalledRoot
            $valid = [bool](
                [int]$installed.fileCount -eq [int]$expected.fileCount -and
                [int64]$installed.totalBytes -eq [int64]$expected.totalBytes -and
                [string]$installed.treeSha256 -ceq [string]$expected.treeSha256
            )
            return [pscustomobject]@{
                valid = $valid
                status = if ($valid) { 'artifact-closure-verified' } else { 'installed-artifact-closure-mismatch' }
                installedRoot = [IO.Path]::GetFullPath($InstalledRoot)
                fileCount = [int]$installed.fileCount
                totalBytes = [int64]$installed.totalBytes
                treeSha256 = [string]$installed.treeSha256
                expectedFileCount = [int]$expected.fileCount
                expectedTotalBytes = [int64]$expected.totalBytes
                expectedTreeSha256 = [string]$expected.treeSha256
            }
        } finally {
            Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
        }
}

function Resolve-LockedCopilotPackageSpec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [string]$PackageSpec
    )
    $artifact = $Lock.components.copilotIntegration.package.artifact
    $lockedUrl = [string]$artifact.url
    if ([string]::IsNullOrWhiteSpace($PackageSpec)) { return $lockedUrl }

    $expanded = [Environment]::ExpandEnvironmentVariables($PackageSpec)
    if (Test-Path -LiteralPath $expanded -PathType Leaf) {
        return [string](Test-LockedArtifact -Path $expanded -Sha256 ([string]$artifact.sha256) `
            -ExpectedName ([string]$artifact.name)).path
    }
    if ($expanded -ceq $lockedUrl) { return $lockedUrl }
    throw "Copilot integration package must be the exact locked Release URL or a hash-verified local artifact named '$([string]$artifact.name)'."
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
    $resolvedArtifact = Resolve-DeploymentPath $ArtifactPath
    $artifactRoot = Split-Path -Parent $resolvedArtifact
    $artifactName = Split-Path -Leaf $resolvedArtifact
    Push-Location $artifactRoot
    try {
        $content = & tar -xOzf $artifactName ("package/" + $RelativePath) 2>$null | Out-String
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($content)) {
            throw "Cannot read '$RelativePath' from '$ArtifactPath'."
        }
        return $content | ConvertFrom-Json
    } finally {
        Pop-Location
    }
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
    $resolvedArtifact = [IO.Path]::GetFullPath($ArtifactPath)
    $artifactArgument = '"' + (Split-Path -Leaf $resolvedArtifact).Replace('"', '\"') + '"'
    $entryArgument = '"' + $EntryPath.Replace('"', '\"') + '"'
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = 'tar'
    $start.WorkingDirectory = Split-Path -Parent $resolvedArtifact
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
        [Alias('ProviderSourceRoot')][string]$CopilotIntegrationSourceRoot,
        [Alias('ProviderArtifactPath')][string]$CopilotIntegrationArtifactPath,
        [string]$DesktopArtifactPath,
        [string]$GatewayArtifactPath,
        [string]$BackupRoot,
        [switch]$IncludeCompanionSuite
    )
    Test-WindowsCopilotLock -Lock $Lock | Out-Null
    $profileRoot = Join-Path (Resolve-DeploymentPath $DshHome) ([string]$Lock.profile.relativePath)
    $globalSpecs = @($Lock.globalInstall.packages | ForEach-Object {
        "$($_.name)@$($_.version)"
    })
    $globalSpecs += '<locked-copilot-release-tarball>'

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
            inputs = @($CopilotIntegrationSourceRoot)
        },
        [pscustomobject]@{
            id = 'verify-release-artifacts'
            action = 'sha256-and-package-metadata'
            changesSystem = $false
            inputs = @($DesktopArtifactPath, $CopilotIntegrationArtifactPath)
        },
        [pscustomobject]@{
            id = 'verify-desktop-official-runtime'
            action = 'metadata-tree-entrypoint-and-sandbox'
            changesSystem = $false
            inputs = @([string](Get-WindowsCopilotRuntimeSelector -Lock $Lock).root)
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
            id = 'verify-installation'
            action = 'acceptance'
            checks = @('official-runtime-metadata', 'official-runtime-tree', 'official-runtime-entrypoint', 'official-desktop-plugin-links', 'plugin-bytes', 'profile-bundle', 'reference-free-provider-route', 'credential-record-metadata', 'allow-builds', 'loader-imports', 'loopback-3080', 'composed-config', 'search-contract', 'sandbox-same-narrower-zero-approval', 'desktop-backend-command-line')
            changesSystem = $false
            inputs = @($BackupRoot)
        }
    )
    if ($IncludeCompanionSuite) {
        $overlays = @(Get-WindowsCopilotCompanionOverlays -Lock $Lock)
        $steps = @($steps[0..4]) + @([pscustomobject]@{
            id = 'install-companion-suite'
            action = 'same-transaction-profile-artifacts'
            changesSystem = $true
            plugins = @([string]$Lock.components.copilotIntegration.package.name) +
                @($overlays | ForEach-Object { [string]$_.name })
            inputs = @($overlays | ForEach-Object { [string]$_.artifact.url })
        }) + @($steps[5..($steps.Count - 1)])
    }

    return [pscustomobject]@{
        mode = 'check'
        deploymentId = [string]$Lock.deploymentId
        dshHome = (Resolve-DeploymentPath $DshHome)
        profileRoot = $profileRoot
        includeCompanionSuite = [bool]$IncludeCompanionSuite
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

function Get-WindowsCopilotRegistryFingerprint {
    param([Parameter(Mandatory)][string]$Key)
    $providerPath = 'Registry::HKEY_CURRENT_USER\' +
        $Key.Substring('HKCU\'.Length)
    if (-not (Test-Path -LiteralPath $providerPath)) {
        return [pscustomobject]@{ kind = 'absent' }
    }
    $temporary = Join-Path ([IO.Path]::GetTempPath()) (
        'dsh-registry-' + [guid]::NewGuid().ToString('N') + '.reg'
    )
    try {
        & reg.exe export $Key $temporary /y | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Could not export registry key '$Key'." }
        return [pscustomobject]@{
            kind = 'registry'
            size = (Get-Item -LiteralPath $temporary).Length
            sha256 = (Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    } finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

function Backup-WindowsCopilotRegistryKey {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string]$OperationRoot
    )
    $fingerprint = Get-WindowsCopilotRegistryFingerprint -Key $Key
    $exists = [string]$fingerprint.kind -cne 'absent'
    if ($exists) {
        $destination = Join-Path $OperationRoot $RelativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force |
            Out-Null
        & reg.exe export $Key $destination /y | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Could not back up registry key '$Key'." }
    }
    return [pscustomobject]@{
        key = $Key
        relativePath = $RelativePath
        existed = $exists
        originalFingerprint = $fingerprint
    }
}

function Restore-WindowsCopilotRegistrySnapshots {
    param(
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$Snapshots,
        [Parameter(Mandatory)][string]$OperationRoot
    )
    foreach ($snapshot in $Snapshots) {
        if ($snapshot.existed) {
            $backup = Join-Path $OperationRoot ([string]$snapshot.relativePath)
            if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) {
                throw "Registry rollback backup is missing: '$backup'."
            }
            $backupFingerprint = [pscustomobject]@{
                kind = 'registry'
                size = (Get-Item -LiteralPath $backup).Length
                sha256 = (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash.ToLowerInvariant()
            }
            if (-not (Test-DeploymentFingerprintEqual -Left $backupFingerprint `
                -Right $snapshot.originalFingerprint)) {
                throw "Registry rollback backup fingerprint mismatch: '$backup'."
            }
        }
    }
    foreach ($snapshot in $Snapshots) {
        $providerPath = 'Registry::HKEY_CURRENT_USER\' +
            ([string]$snapshot.key).Substring('HKCU\'.Length)
        if (Test-Path -LiteralPath $providerPath) {
            Remove-Item -LiteralPath $providerPath -Recurse -Force
        }
        if ($snapshot.existed) {
            & reg.exe import (Join-Path $OperationRoot ([string]$snapshot.relativePath)) |
                Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Could not restore registry key '$([string]$snapshot.key)'."
            }
        }
    }
}

function Get-DeploymentPathFingerprint {
    param([Parameter(Mandatory)][string]$Path)
    $item = Get-DeploymentPathItem -Path $Path
    if (-not $item) { return [pscustomobject]@{ kind = 'absent' } }
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        return [pscustomobject]@{
            kind = 'reparse-point'
            target = @($item.Target | ForEach-Object { [string]$_ }) -join '|'
        }
    }
    if (-not $item.PSIsContainer) {
        return [pscustomobject]@{
            kind = 'file'
            size = [long]$item.Length
            sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    $tree = Get-WindowsCopilotDirectoryTreeState -Path $item.FullName
    return [pscustomobject]@{
        kind = 'directory'
        fileCount = [int]$tree.fileCount
        treeSha256 = [string]$tree.treeSha256
    }
}

function Test-DeploymentFingerprintEqual {
    param($Left, $Right)
    if ($null -eq $Left -or $null -eq $Right) { return $false }
    return (ConvertTo-Json $Left -Compress -Depth 4) -ceq
        (ConvertTo-Json $Right -Compress -Depth 4)
}

function Restore-DeploymentSnapshots {
    param(
        [Parameter(Mandatory)][object[]]$Snapshots,
        [Parameter(Mandatory)][string]$OperationRoot,
        [Parameter(Mandatory)][string]$NodeModulesRoot
    )
    foreach ($snapshot in $Snapshots) {
        if (-not [bool]$snapshot.existed) { continue }
        $source = Join-Path $OperationRoot ([string]$snapshot.relativePath)
        if (-not (Test-Path -LiteralPath $source)) {
            throw "Deployment rollback backup is missing: $source"
        }
        $backupFingerprint = Get-DeploymentPathFingerprint -Path $source
        if (-not (Test-DeploymentFingerprintEqual -Left $backupFingerprint `
            -Right $snapshot.originalFingerprint)) {
            throw "Deployment rollback backup fingerprint mismatch: $source"
        }
    }
    for ($index = $Snapshots.Count - 1; $index -ge 0; $index--) {
        $snapshot = $Snapshots[$index]
        $target = [string]$snapshot.path
        $currentFingerprint = Get-DeploymentPathFingerprint -Path $target
        if ([bool]$snapshot.existed -and
            (Test-DeploymentFingerprintEqual -Left $currentFingerprint `
                -Right $snapshot.originalFingerprint)) {
            continue
        }
        if (Get-DeploymentPathItem -Path $target) {
            if ([bool]$snapshot.pluginTarget) {
                Remove-ProfilePluginTarget -Target $target -NodeModulesRoot $NodeModulesRoot
            } else {
                Remove-Item -LiteralPath $target -Recurse -Force
            }
        }
        if ([bool]$snapshot.existed) {
            $source = Join-Path $OperationRoot ([string]$snapshot.relativePath)
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

function Test-WindowsCopilotDesiredArtifactDependency {
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Dependency,
        [Parameter(Mandatory)][string]$DshHome,
        [Parameter(Mandatory)][string]$ProfileRoot
    )
    if ([string]::IsNullOrWhiteSpace($Dependency)) { return $false }
    if ($Dependency -ceq [string]$Lock.components.copilotIntegration.package.artifact.url) {
        return $true
    }
    if (-not $Dependency.StartsWith('file:', [StringComparison]::Ordinal)) {
        return $false
    }

    $rawTarget = $Dependency.Substring('file:'.Length)
    if ([string]::IsNullOrWhiteSpace($rawTarget)) {
        return $false
    }
    try {
        $uri = $null
        $target = if ([Uri]::TryCreate($Dependency, [UriKind]::Absolute, [ref]$uri) -and $uri.IsFile) {
            $uri.LocalPath
        } elseif ([IO.Path]::IsPathRooted($rawTarget)) {
            $rawTarget
        } else {
            Join-Path $ProfileRoot $rawTarget
        }
        $resolvedTarget = Resolve-DeploymentPath $target
        $expectedTarget = Resolve-DeploymentPath (Join-Path $DshHome (
            Join-Path 'artifacts' (
                Join-Path ([string]$Lock.components.copilotIntegration.source.commit) `
                    ([string]$Lock.components.copilotIntegration.package.artifact.name)
            )
        ))
        return $resolvedTarget -ieq $expectedTarget
    } catch {
        return $false
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
            $dependencyIsOfficialLink = $false
            if ($dependencyProperty) {
                $dependency = [string]$dependencyProperty.Value
                if ($dependency.StartsWith('link:', [StringComparison]::Ordinal)) {
                    $rawTarget = $dependency.Substring('link:'.Length)
                    if (-not [string]::IsNullOrWhiteSpace($rawTarget)) {
                        $dependencyTarget = if ([IO.Path]::IsPathRooted($rawTarget)) {
                            Resolve-DeploymentPath $rawTarget
                        } else {
                            Resolve-DeploymentPath (Join-Path $profileRoot $rawTarget)
                        }
                        $dependencyIsOfficialLink = $dependencyTarget -ieq [string]$state.expectedTarget
                    }
                }
            }
            if ($dependencyProperty -and -not $dependencyIsLegacy -and -not $dependencyIsOfficialLink) {
                throw "Profile dependency '$($state.name)' is neither an exact official Desktop link nor a reviewed legacy dependency."
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
                (Test-WindowsCopilotDesiredArtifactDependency -Lock $Lock `
                    -Dependency ([string]$dependencyProperty.Value) -DshHome $home -ProfileRoot $profileRoot)) {
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
        [switch]$SkipPackageInstall,
        [switch]$IncludeCompanionSuite
    )
    Test-WindowsCopilotLock -Lock $Lock | Out-Null
    $CopilotIntegrationArtifactPath = Resolve-DeploymentPath $CopilotIntegrationArtifactPath
    Test-CopilotIntegrationDeploymentContract -Lock $Lock `
        -ArtifactPath $CopilotIntegrationArtifactPath | Out-Null
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
    $companionArtifacts = if ($IncludeCompanionSuite) {
        @(Get-WindowsCopilotCompanionOverlays -Lock $Lock | ForEach-Object {
            $overlay = $_
            $overlayArtifactRoot = Join-Path $home (
                'artifacts\' + [string]$overlay.sourceCommit
            )
            [pscustomobject]@{
                overlay = $overlay
                path = Join-Path $overlayArtifactRoot ([string]$overlay.artifact.name)
                dependency = 'file:../../artifacts/' + [string]$overlay.sourceCommit + '/' +
                    [string]$overlay.artifact.name
            }
        })
    } else {
        @()
    }
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
    foreach ($companion in $companionArtifacts) {
        $name = [string]$companion.overlay.name
        foreach ($snapshot in @(
            [pscustomobject]@{
                path = [string]$companion.path
                relativePath = Join-Path 'artifacts\companion-suite' ([string]$companion.overlay.artifact.name)
                pluginTarget = $false
            },
            [pscustomobject]@{
                path = Join-Path $nodeModules $name
                relativePath = Join-Path 'plugins\companion-suite' $name
                pluginTarget = $true
            }
        )) {
            $snapshot | Add-Member -NotePropertyName existed `
                -NotePropertyValue (Test-Path -LiteralPath $snapshot.path)
            $snapshots.Add($snapshot)
            Backup-DeploymentPath -Path $snapshot.path -RelativePath $snapshot.relativePath `
                -OperationRoot $OperationRoot
        }
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
    foreach ($snapshot in $snapshots) {
        $snapshot | Add-Member -NotePropertyName originalFingerprint `
            -NotePropertyValue (Get-DeploymentPathFingerprint -Path ([string]$snapshot.path)) -Force
    }

    try {
    New-Item -ItemType Directory -Path $profileRoot, $nodeModules -Force | Out-Null
    New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
    Copy-Item -LiteralPath $CopilotIntegrationArtifactPath -Destination $lockedArtifact -Force
    foreach ($companion in $companionArtifacts) {
        Save-WindowsCopilotLockedArtifact -Artifact $companion.overlay.artifact `
            -Destination ([string]$companion.path) | Out-Null
    }
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
    foreach ($companion in $companionArtifacts) {
        Set-ObjectProperty -Object $profile.dependencies -Name ([string]$companion.overlay.name) `
            -Value ([string]$companion.dependency)
    }
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
    foreach ($companion in $companionArtifacts) {
        $name = [string]$companion.overlay.name
        $bundles = @($bundles | Where-Object { $_ -ne $name })
        $bundles += $name
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
        $target = Join-Path $nodeModules ([string]$plugin.name)
        Remove-ProfilePluginTarget -Target $target -NodeModulesRoot $nodeModules
        $temporary = Join-Path ([IO.Path]::GetTempPath()) (
            'dsh-copilot-materialize-' + [guid]::NewGuid().ToString('N')
        )
        New-Item -ItemType Directory -Path $temporary -Force | Out-Null
        try {
            & (Join-Path $env:SystemRoot 'System32\tar.exe') -xzf `
                $CopilotIntegrationArtifactPath -C $temporary
            if ($LASTEXITCODE -ne 0) {
                throw 'Could not extract the locked Copilot artifact.'
            }
            Copy-Item -LiteralPath (Join-Path $temporary 'package') `
                -Destination $target -Recurse -Force
        } finally {
            Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
        }
        $closure = Test-WindowsCopilotInstalledArtifactClosure `
            -ArtifactPath $CopilotIntegrationArtifactPath -InstalledRoot $target `
            -Sha256 ([string]$Lock.components.copilotIntegration.package.artifact.sha256) `
            -ExpectedName ([string]$Lock.components.copilotIntegration.package.artifact.name) `
            -ExpectedSize ([long]$Lock.components.copilotIntegration.package.artifact.size)
        if (-not $closure.valid) {
            throw 'Materialized Copilot package does not match the locked artifact closure.'
        }
    }
    $companionStates = @($companionArtifacts | ForEach-Object {
        $companion = $_
        $name = [string]$companion.overlay.name
        $target = Join-Path $nodeModules $name
        Remove-ProfilePluginTarget -Target $target -NodeModulesRoot $nodeModules
        $temporary = Join-Path ([IO.Path]::GetTempPath()) (
            'dsh-companion-materialize-' + [guid]::NewGuid().ToString('N')
        )
        New-Item -ItemType Directory -Path $temporary -Force | Out-Null
        try {
            & (Join-Path $env:SystemRoot 'System32\tar.exe') -xzf `
                ([string]$companion.path) -C $temporary
            if ($LASTEXITCODE -ne 0) {
                throw "Could not extract the locked companion artifact for '$name'."
            }
            Copy-Item -LiteralPath (Join-Path $temporary 'package') `
                -Destination $target -Recurse -Force
        } finally {
            Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
        }
        $manifest = Join-Path $target 'package.json'
        if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
            throw "Companion suite package is missing after install: '$name'."
        }
        $metadata = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$metadata.version -cne [string]$companion.overlay.version) {
            throw "Companion suite package version mismatch for '$name'."
        }
        $closure = Test-WindowsCopilotInstalledArtifactClosure `
            -ArtifactPath ([string]$companion.path) -InstalledRoot $target `
            -Sha256 ([string]$companion.overlay.artifact.sha256) `
            -ExpectedName ([string]$companion.overlay.artifact.name) `
            -ExpectedSize ([long]$companion.overlay.artifact.size)
        if (-not $closure.valid) {
            throw "Companion suite package closure mismatch for '$name'."
        }
        [pscustomobject]@{
            name = $name
            version = [string]$metadata.version
            artifactPath = [string]$companion.path
            artifactSha256 = (Get-FileHash -LiteralPath ([string]$companion.path) -Algorithm SHA256).Hash.ToLowerInvariant()
            physical = $true
            closure = $closure
        }
    })
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

    foreach ($snapshot in $snapshots) {
        $snapshot | Add-Member -NotePropertyName appliedFingerprint `
            -NotePropertyValue (Get-DeploymentPathFingerprint -Path ([string]$snapshot.path)) -Force
    }
    $receipt = [pscustomobject]@{
        schemaVersion = 1
        deploymentId = [string]$Lock.deploymentId
        operationId = Split-Path -Leaf $OperationRoot
        status = 'active'
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
        nodeModulesRoot = $nodeModules
        snapshots = @($snapshots)
        includeCompanionSuite = [bool]$IncludeCompanionSuite
        companionSuite = @($companionStates)
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

function Restore-WindowsCopilotDeploymentLocked {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$BackupRoot,
        [string]$OperationId,
        [string[]]$AcknowledgeLiveSessionIds,
        [object[]]$DesktopProcesses
    )
    $root = Resolve-DeploymentPath $BackupRoot
    if (-not $OperationId) {
        $operation = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d{8}T\d{9}Z$' -and
                (Test-Path -LiteralPath (Join-Path $_.FullName 'receipt.json') -PathType Leaf) } |
            Sort-Object Name -Descending | Select-Object -First 1)
        if ($operation.Count -eq 0) {
            return [pscustomobject]@{ status = 'nothing-to-rollback'; changed = $false }
        }

        $OperationId = $operation[0].Name
    }
    if ($OperationId -notmatch '^\d{8}T\d{9}Z$') {
        throw "Invalid deployment operation id '$OperationId'."
    }
    $operationRoot = [IO.Path]::GetFullPath((Join-Path $root $OperationId))
    if (-not $operationRoot.StartsWith($root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Deployment rollback operation escapes the backup root.'
    }
    $receiptPath = Join-Path $operationRoot 'receipt.json'
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
        throw "Deployment rollback receipt not found: '$receiptPath'."
    }
    $receipt = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$receipt.schemaVersion -ne 1 -or
        [string]$receipt.deploymentId -cne [string]$Lock.deploymentId -or
        [string]$receipt.operationId -cne $OperationId) {
        throw 'Deployment rollback receipt does not match the locked deployment.'
    }
    if ([string]$receipt.status -ceq 'rolled-back') {
        return [pscustomobject]@{
            status = 'already-rolled-back'
            changed = $false
            operationId = $OperationId
        }
    }
    $snapshots = @($receipt.snapshots)
    if ($snapshots.Count -eq 0) { throw 'Deployment rollback receipt has no tracked snapshots.' }
    $registrySnapshots = if ($receipt.PSObject.Properties['registrySnapshots']) {
        @($receipt.registrySnapshots)
    } else { @() }
    foreach ($snapshot in $snapshots) {
        $current = Get-DeploymentPathFingerprint -Path ([string]$snapshot.path)
        if (-not (Test-DeploymentFingerprintEqual -Left $current -Right $snapshot.appliedFingerprint) -and
            -not (Test-DeploymentFingerprintEqual -Left $current -Right $snapshot.originalFingerprint)) {
            throw "Deployment path changed after Apply; refusing to overwrite '$([string]$snapshot.path)'."
        }
        foreach ($snapshot in $registrySnapshots) {
            $current = Get-WindowsCopilotRegistryFingerprint -Key ([string]$snapshot.key)
            if (-not (Test-DeploymentFingerprintEqual -Left $current `
                -Right $snapshot.appliedFingerprint) -and
                -not (Test-DeploymentFingerprintEqual -Left $current `
                    -Right $snapshot.originalFingerprint)) {
                throw "Registry key changed after Apply; refusing to overwrite '$([string]$snapshot.key)'."
            }
        }
    }
    $desktopSnapshots = @($snapshots | Where-Object {
        [string]$_.relativePath -ceq 'transaction\desktop'
    })
    if ($desktopSnapshots.Count -gt 1) {
        throw 'Deployment rollback receipt contains multiple Desktop snapshots.'
    }
    if ($desktopSnapshots.Count -eq 1) {
        $desktopSnapshot = $desktopSnapshots[0]
        $currentDesktop = Get-DeploymentPathFingerprint -Path ([string]$desktopSnapshot.path)
        if (-not (Test-DeploymentFingerprintEqual -Left $currentDesktop `
            -Right $desktopSnapshot.originalFingerprint)) {
            $desktopExecutable = Join-Path ([string]$desktopSnapshot.path) (
                [string]$Lock.components.desktop.installedExecutable.relativePath
            )
            if ($null -eq $DesktopProcesses) {
                $DesktopProcesses = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
                    Select-Object ProcessId, ParentProcessId, Name, ExecutablePath,
                        CommandLine, CreationDate)
            }
            $runningDesktop = @($DesktopProcesses | Where-Object {
                $_.ExecutablePath -and
                [IO.Path]::GetFullPath([string]$_.ExecutablePath) -ieq
                    [IO.Path]::GetFullPath($desktopExecutable)
            })
            if ($runningDesktop.Count -gt 0) {
                $live = @(Get-WindowsCopilotLiveSessions)
                $liveIds = @($live.sessionId | Sort-Object -Unique)
                $acknowledged = @($AcknowledgeLiveSessionIds | Sort-Object -Unique)
                if ($liveIds.Count -ne $acknowledged.Count -or
                    @($liveIds | Where-Object { $acknowledged -cnotcontains $_ }).Count -gt 0) {
                    throw 'Desktop rollback requires acknowledgement of the exact running Session IDs.'
                }
                $finalLiveIds = @(Get-WindowsCopilotLiveSessions |
                    ForEach-Object { [string]$_.sessionId } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    Sort-Object -Unique)
                if ($finalLiveIds.Count -ne $acknowledged.Count -or
                    @($finalLiveIds | Where-Object {
                        $acknowledged -cnotcontains $_
                    }).Count -gt 0) {
                    throw 'Desktop rollback blocked because the running Session set changed after acknowledgement.'
                }
                Stop-WindowsCopilotProcessTree -RootProcessIds @($runningDesktop.ProcessId) `
                    -Processes $DesktopProcesses | Out-Null
            }
        }
    }
    Restore-DeploymentSnapshots -Snapshots $snapshots -OperationRoot $operationRoot `
        -NodeModulesRoot ([string]$receipt.nodeModulesRoot)
    Restore-WindowsCopilotRegistrySnapshots -Snapshots $registrySnapshots `
        -OperationRoot $operationRoot
    if ($receipt.PSObject.Properties['legacyGatewayState']) {
        Restore-WindowsCopilotLegacyGateway -Lock $Lock -State $receipt.legacyGatewayState
    }
    $receipt.status = 'rolled-back'
    Set-WindowsCopilotJsonFile -Value $receipt -Path $receiptPath -Depth 12
    return [pscustomobject]@{
        status = 'rolled-back'
        changed = $true
        operationId = $OperationId
        restoredPaths = @($snapshots.path)
    }
}

function Restore-WindowsCopilotDeployment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$BackupRoot,
        [string]$OperationId,
        [string[]]$AcknowledgeLiveSessionIds,
        [object[]]$DesktopProcesses
    )
    $mutex = Enter-WindowsCopilotDeploymentLock -BackupRoot $BackupRoot
    try {
        return Restore-WindowsCopilotDeploymentLocked @PSBoundParameters
    } finally {
        Exit-WindowsCopilotDeploymentLock -Mutex $mutex
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
        [string]$Path
    )
    $expected = [string]$Lock.components.desktop.version
    $identity = $Lock.components.desktop.installedExecutable
    $resourcesIdentity = $Lock.components.desktop.installedResources
    $canonicalPath = if ($env:LOCALAPPDATA) {
        Join-Path $env:LOCALAPPDATA 'Deepseek Harness Desktop\deepseek-harness-desktop.exe'
    } else {
        $null
    }
    $discoveries = [Collections.Generic.List[object]]::new()
    foreach ($candidatePath in @($canonicalPath, $Path)) {
        if (-not $candidatePath -or -not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) { continue }
        $fullPath = [IO.Path]::GetFullPath($candidatePath)
        if (@($discoveries | Where-Object { $_.path -ieq $fullPath }).Count -gt 0) { continue }
        try {
            Assert-NoReparsePointAncestor -Path $fullPath
            $item = Get-Item -LiteralPath $fullPath -ErrorAction Stop
            $versionInfo = $item.VersionInfo
            $sha256 = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
            $signatureStatus = [string](Get-AuthenticodeSignature -FilePath $fullPath -ErrorAction Stop).Status
            $version = [string]$versionInfo.ProductVersion
            $bytesValid = [bool](
                [int64]$item.Length -eq [int64]$identity.size -and
                $sha256 -ceq [string]$identity.sha256
            )
            $metadataValid = [bool](
                [string]$versionInfo.ProductName -ceq [string]$identity.productName -and
                [string]$versionInfo.FileDescription -ceq [string]$identity.fileDescription -and
                [string]$versionInfo.CompanyName -ceq [string]$identity.companyName -and
                $version -ceq [string]$identity.productVersion
            )
            $authenticodeValid = $signatureStatus -ceq [string]$identity.authenticodeStatus
            $resourcesPath = Join-Path (Split-Path -Parent $fullPath) (
                [string]$resourcesIdentity.relativePath
            )
            $resourcesTree = Get-WindowsCopilotDirectoryTreeState -Path $resourcesPath
            $resourcesValid = [bool](
                [int]$resourcesTree.fileCount -eq [int]$resourcesIdentity.fileCount -and
                [int64]$resourcesTree.totalBytes -eq [int64]$resourcesIdentity.totalBytes -and
                [string]$resourcesTree.treeSha256 -ceq [string]$resourcesIdentity.treeSha256 -and
                [int]$resourcesTree.reparseDirectoryCount -eq
                    [int]$resourcesIdentity.reparseDirectoryCount
            )
            $discoveries.Add([pscustomobject]@{
                path = $fullPath
                source = if ($fullPath -ieq $canonicalPath) { 'canonical-official-path' } else { 'explicit-path' }
                version = $version
                size = [int64]$item.Length
                sha256 = $sha256
                authenticodeStatus = $signatureStatus
                bytesValid = $bytesValid
                metadataValid = $metadataValid
                authenticodeValid = $authenticodeValid
                resourcesPath = $resourcesPath
                resourcesFileCount = [int]$resourcesTree.fileCount
                resourcesTotalBytes = [int64]$resourcesTree.totalBytes
                resourcesTreeSha256 = [string]$resourcesTree.treeSha256
                resourcesValid = $resourcesValid
                identityValid = [bool](
                    $bytesValid -and $metadataValid -and $authenticodeValid -and
                    $resourcesValid
                )
            })
        } catch {
            $discoveries.Add([pscustomobject]@{
                path = $fullPath
                source = if ($fullPath -ieq $canonicalPath) { 'canonical-official-path' } else { 'explicit-path' }
                version = $null
                identityValid = $false
                error = $_.Exception.Message
            })
        }
    }
    $newer = @($discoveries | Where-Object {
        try { [version]$_.version -gt [version]$expected } catch { $false }
    })
    $selected = @($discoveries | Where-Object identityValid | Select-Object -First 1)
    if ($selected.Count -eq 0) {
        $selected = @($newer | Select-Object -First 1)
    }
    if ($selected.Count -eq 0) {
        $selected = @($discoveries | Select-Object -First 1)
    }
    $state = if ($selected.Count -gt 0) { $selected[0] } else { $null }
    $valid = [bool](
        $state -and $state.identityValid -and
        [string]$state.version -ceq $expected -and
        $newer.Count -eq 0
    )
    return [pscustomobject]@{
        path = if ($state) { $state.path } else { if ($Path) { $Path } else { $canonicalPath } }
        version = if ($state) { $state.version } else { $null }
        lockedVersion = $expected
        valid = $valid
        newerThanLock = $newer.Count -gt 0
        identityValid = [bool]($state -and $state.identityValid)
        status = if (-not $state -or -not $state.version) {
            'not-found-or-unreadable'
        } elseif ($newer.Count -gt 0) {
            'newer-than-lock'
        } elseif ($valid) {
            'locked'
        } elseif ($state.version -ceq $expected) {
            'identity-mismatch'
        } else {
            'version-mismatch'
        }
        discoveries = @($discoveries)
    }
}

function Get-WindowsCopilotDirectoryTreeState {
    param([Parameter(Mandatory)][string]$Path)
    Assert-NoReparsePointAncestor -Path $Path
    $root = [IO.Path]::GetFullPath($Path).TrimEnd('\') + '\'
    $items = @(Get-ChildItem -LiteralPath $root -Recurse -Force)
    if (@($items | Where-Object {
        [bool]($_.Attributes -band [IO.FileAttributes]::ReparsePoint)
    }).Count -gt 0) {
        throw "Official runtime tree contains a reparse point: '$Path'."
    }
    $entries = @($items | Where-Object { -not $_.PSIsContainer } | ForEach-Object {
        [pscustomobject]@{
            relativePath = $_.FullName.Substring($root.Length).Replace('\', '/')
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            size = [int64]$_.Length
        }
    } | Sort-Object relativePath)
    $text = ($entries | ForEach-Object {
        [string]$_.relativePath + "`t" + [string]$_.sha256
    }) -join "`n"
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $treeSha256 = ([BitConverter]::ToString(
            $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))
        )).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
    return [pscustomobject]@{
        fileCount = $entries.Count
        totalBytes = [int64](($entries | Measure-Object size -Sum).Sum)
        treeSha256 = $treeSha256
        reparseDirectoryCount = 0
    }
}

function Get-WindowsCopilotCommandScriptPath {
    param([Parameter(Mandatory)][string]$CommandLine)
    $tokens = @([regex]::Matches($CommandLine, '"([^"]*)"|''([^'']*)''|(\S+)') | ForEach-Object {
        if ($_.Groups[1].Success) {
            $_.Groups[1].Value
        } elseif ($_.Groups[2].Success) {
            $_.Groups[2].Value
        } else {
            $_.Groups[3].Value
        }
    })
    if ($tokens.Count -lt 2) { return $null }
    if ([IO.Path]::GetFileName([string]$tokens[0]) -notmatch '^node(?:\.exe)?$') { return $null }
    if ([string]$tokens[1] -match '^-') { return $null }
    try {
        return [IO.Path]::GetFullPath([string]$tokens[1])
    } catch {
        return $null
    }
}

function Get-WindowsCopilotOfficialRuntimeState {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Lock)

    $selector = Get-WindowsCopilotRuntimeSelector -Lock $Lock
    $root = [IO.Path]::GetFullPath(
        [Environment]::ExpandEnvironmentVariables([string]$selector.root)
    )
    $packageRoot = [IO.Path]::GetFullPath((Join-Path $root 'node_modules\@deepseek-ai\dsh'))
    $rootManifest = [IO.Path]::GetFullPath(
        (Join-Path $root ([string]$selector.rootPackage.manifest))
    )
    $packageManifest = [IO.Path]::GetFullPath(
        (Join-Path $root ([string]$selector.package.manifest))
    )
    $entrypoint = [IO.Path]::GetFullPath(
        (Join-Path $root ([string]$selector.package.entrypoint))
    )
    $state = [ordered]@{
        valid = $false
        status = 'package-not-found'
        selector = 'desktop-official'
        source = 'desktop-managed-download'
        version = [string]$selector.package.version
        root = $root
        packageRoot = $packageRoot
        entryPath = $entrypoint
        wrapperFileCount = $null
        wrapperTotalBytes = $null
        wrapperTreeSha256 = $null
        wrapperReparseDirectoryCount = $null
        fileCount = $null
        treeSha256 = $null
        entrypointSize = $null
        entrypointSha256 = $null
        reason = $null
    }
    try {
        foreach ($path in @($root, $packageRoot, $rootManifest, $packageManifest, $entrypoint)) {
            Assert-NoReparsePointAncestor -Path $path
        }
        if (-not (Test-Path -LiteralPath $root -PathType Container) -or
            -not (Test-Path -LiteralPath $packageRoot -PathType Container) -or
            -not (Test-Path -LiteralPath $rootManifest -PathType Leaf) -or
            -not (Test-Path -LiteralPath $packageManifest -PathType Leaf) -or
            -not (Test-Path -LiteralPath $entrypoint -PathType Leaf)) {
            return [pscustomobject]$state
        }
        $rootMetadata = Get-Content -LiteralPath $rootManifest -Raw -Encoding UTF8 | ConvertFrom-Json
        $metadata = Get-Content -LiteralPath $packageManifest -Raw -Encoding UTF8 | ConvertFrom-Json
        $wrapperTree = Get-WindowsCopilotDirectoryTreeState -Path $root
        $tree = Get-WindowsCopilotDirectoryTreeState -Path $packageRoot
        $entrypointItem = Get-Item -LiteralPath $entrypoint -Force
        $rootManifestSha256 = (Get-FileHash -LiteralPath $rootManifest -Algorithm SHA256).Hash.ToLowerInvariant()
        $entrypointSha256 = (Get-FileHash -LiteralPath $entrypoint -Algorithm SHA256).Hash.ToLowerInvariant()
        $state.wrapperFileCount = [int]$wrapperTree.fileCount
        $state.wrapperTotalBytes = [int64]$wrapperTree.totalBytes
        $state.wrapperTreeSha256 = [string]$wrapperTree.treeSha256
        $state.wrapperReparseDirectoryCount = [int]$wrapperTree.reparseDirectoryCount
        $state.fileCount = [int]$tree.fileCount
        $state.treeSha256 = [string]$tree.treeSha256
        $state.entrypointSize = [long]$entrypointItem.Length
        $state.entrypointSha256 = $entrypointSha256
        $state.valid = [bool](
            [string]$rootMetadata.name -ceq [string]$selector.rootPackage.name -and
            [string]$rootMetadata.version -ceq [string]$selector.rootPackage.version -and
            $rootManifestSha256 -ceq [string]$selector.rootPackage.manifestSha256 -and
            [int]$wrapperTree.fileCount -eq [int]$selector.rootPackage.fileCount -and
            [int64]$wrapperTree.totalBytes -eq [int64]$selector.rootPackage.totalBytes -and
            [string]$wrapperTree.treeSha256 -ceq [string]$selector.rootPackage.treeSha256 -and
            [int]$wrapperTree.reparseDirectoryCount -eq 0 -and
            [string]$metadata.name -ceq [string]$selector.package.name -and
            [string]$metadata.version -ceq [string]$selector.package.version -and
            [string]$metadata.bin.dsh -ceq 'lib/bin.js' -and
            [int]$tree.fileCount -eq [int]$selector.package.fileCount -and
            [string]$tree.treeSha256 -ceq [string]$selector.package.treeSha256 -and
            [long]$entrypointItem.Length -eq [long]$selector.package.entrypointSize -and
            $entrypointSha256 -ceq [string]$selector.package.entrypointSha256
        )
        $state.status = if ($state.valid) { 'package-verified' } else { 'package-identity-mismatch' }
    } catch {
        $state.status = if ($_.Exception.Message -like '*reparse*') {
            'reparse-point-path'
        } else {
            'package-metadata-invalid'
        }
        $state.reason = $_.Exception.Message
    }
    return [pscustomobject]$state
}

function Get-WindowsCopilotDesktopRuntimeState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$DesktopExecutablePath,
        [object[]]$Processes,
        [object[]]$ListenerStates
    )
    $desktopExecutable = Resolve-DeploymentPath $DesktopExecutablePath
    if ($null -eq $Processes) {
        $Processes = @(Get-CimInstance Win32_Process |
            Select-Object ProcessId, ParentProcessId, Name, ExecutablePath, CommandLine)
    }
    $desktopProcesses = @($Processes | Where-Object {
        [string]$_.Name -match '^(?:DeepSeek Harness|deepseek-harness-desktop)(?:\.exe)?$' -and
        $_.ExecutablePath -and
        [IO.Path]::GetFullPath([string]$_.ExecutablePath) -ieq $desktopExecutable
    })
    if ($desktopProcesses.Count -eq 0) {
        return [pscustomobject]@{
            valid = $false
            status = 'desktop-not-running'
            selector = $null
            source = $null
            version = $null
            packageRoot = $null
            entryPath = $null
            processIds = @()
            desktopProcessIds = @()
            listenerOwnerProcessIds = @()
            listenerBound = $false
        }
    }

    $descendants = [Collections.Generic.HashSet[int]]::new()
    foreach ($desktopProcess in $desktopProcesses) {
        [void]$descendants.Add([int]$desktopProcess.ProcessId)
    }
    do {
        $added = $false
        foreach ($process in $Processes) {
            if ($descendants.Contains([int]$process.ParentProcessId) -and
                $descendants.Add([int]$process.ProcessId)) {
                $added = $true
            }
        }
    } while ($added)
    $backendProcesses = @($Processes | Where-Object {
        $descendants.Contains([int]$_.ProcessId) -and
        [string]$_.Name -match '^node(?:\.exe)?$' -and
        $_.CommandLine
    })

    $official = Get-WindowsCopilotOfficialRuntimeState -Lock $Lock
    $officialEntry = [string]$official.entryPath
    $candidates = @([pscustomobject]@{
        id = 'desktop-official'
        source = 'desktop-managed-download'
        version = [string]$official.version
        packageRoot = [string]$official.packageRoot
        entryPath = $officialEntry
        metadataValid = [bool]$official.valid
        metadataStatus = [string]$official.status
    })

    foreach ($candidate in $candidates) {
        if (-not $candidate.metadataValid) { continue }
        $active = @($backendProcesses | Where-Object {
            $scriptPath = Get-WindowsCopilotCommandScriptPath -CommandLine ([string]$_.CommandLine)
            $scriptPath -and $scriptPath -ieq [string]$candidate.entryPath
        })
        if ($active.Count -gt 0) {
            if ($null -eq $ListenerStates) {
                $ListenerStates = @($Lock.acceptance.listeners | ForEach-Object {
                    Test-LoopbackListener -HostName ([string]$_.host) -Port ([int]$_.port)
                })
            }
            $desktopListener = @($ListenerStates | Where-Object {
                [string]$_.host -ceq '127.0.0.1' -and [int]$_.port -eq 3080
            })
            $listenerOwnerProcessIds = if ($desktopListener.Count -eq 1) {
                @($desktopListener[0].owningProcessIds)
            } else {
                @()
            }
            $listenerBound = [bool](
                $desktopListener.Count -eq 1 -and
                $desktopListener[0].bindingVerified -and
                $desktopListener[0].loopbackOnly -and
                @($listenerOwnerProcessIds).Count -eq 1 -and
                @($active.ProcessId | Where-Object {
                    [int]$_ -eq [int]$listenerOwnerProcessIds[0]
                }).Count -eq 1
            )
            return [pscustomobject]@{
                valid = $listenerBound
                status = [string]$candidate.id + $(if ($listenerBound) {
                    '-active-owns-3080'
                } else {
                    '-listener-owner-mismatch'
                })
                selector = [string]$candidate.id
                source = [string]$candidate.source
                version = [string]$candidate.version
                packageRoot = [string]$candidate.packageRoot
                entryPath = [string]$candidate.entryPath
                processIds = @($active.ProcessId)
                desktopProcessIds = @($desktopProcesses.ProcessId)
                listenerOwnerProcessIds = @($listenerOwnerProcessIds)
                listenerBound = $listenerBound
                metadataStatus = [string]$candidate.metadataStatus
            }
        }
    }

    $officialCommandActive = @($backendProcesses | Where-Object {
        $scriptPath = Get-WindowsCopilotCommandScriptPath -CommandLine ([string]$_.CommandLine)
        $scriptPath -and $scriptPath -ieq $officialEntry
    }).Count -gt 0
    return [pscustomobject]@{
        valid = $false
        status = if ($officialCommandActive -and -not $official.valid) {
            'desktop-official-runtime-invalid'
        } elseif ($backendProcesses.Count -eq 0) {
            'desktop-backend-not-running'
        } else {
            'unsupported-runtime-selector'
        }
        selector = $null
        source = $null
        version = $null
        packageRoot = $null
        entryPath = $null
        processIds = @()
        desktopProcessIds = @($desktopProcesses.ProcessId)
        listenerOwnerProcessIds = @()
        listenerBound = $false
        officialMetadataStatus = [string]$official.status
    }
}

function Test-WindowsCopilotOfficialRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [string]$DesktopExecutablePath,
        [object[]]$DesktopProcesses,
        [object[]]$ListenerStates,
        [switch]$SkipActiveCheck,
        [switch]$SkipRuntimeChecks
    )
    $package = Get-WindowsCopilotOfficialRuntimeState -Lock $Lock
    $active = if ($SkipRuntimeChecks -or $SkipActiveCheck) {
        [pscustomobject]@{ valid = $true; status = 'skipped'; packageRoot = $package.packageRoot }
    } elseif (-not $DesktopExecutablePath) {
        [pscustomobject]@{ valid = $false; status = 'locked-desktop-not-found'; packageRoot = $package.packageRoot }
    } else {
        Get-WindowsCopilotDesktopRuntimeState -Lock $Lock `
            -DesktopExecutablePath $DesktopExecutablePath -Processes $DesktopProcesses `
            -ListenerStates $ListenerStates
    }
    $schema = if (-not $package.valid) {
        [pscustomobject]@{ valid = $false; status = 'official-package-invalid'; packageRoot = $package.packageRoot }
    } elseif ($SkipRuntimeChecks) {
        [pscustomobject]@{ valid = $true; status = 'skipped'; packageRoot = $package.packageRoot }
    } else {
        $schemaParameters = @{
            Contract = $Lock.acceptance.runtimeSchema
            RequiredPackageRoot = [string]$package.packageRoot
        }
        if (-not $SkipActiveCheck -and $null -eq $DesktopProcesses -and
            @($active.processIds).Count -gt 0) {
            $schemaParameters.RequiredProcessIds = @($active.processIds)
        }
        Test-DshRuntimeSchemaState @schemaParameters
    }
    $sandbox = if (-not $package.valid) {
        [pscustomobject]@{ valid = $false; status = 'official-package-invalid'; packageRoot = $package.packageRoot }
    } elseif ($SkipRuntimeChecks) {
        [pscustomobject]@{ valid = $true; status = 'skipped'; packageRoot = $package.packageRoot }
    } else {
        try {
            $result = Test-DshSandboxRegression -PackageRoot ([string]$package.packageRoot) `
                -ProbeScript (Join-Path $PSScriptRoot 'dsh-sandbox-regression-probe.mjs') `
                -Mode ([string]$Lock.acceptance.sandbox.gate)
            $valid = [bool](
                [string]$result.capability -ceq [string]$Lock.acceptance.sandbox.capability -and
                [int]$result.sameAndNarrowerApprovalCalls -eq 0 -and
                [int]$result.widerApprovalCalls -eq [int]$Lock.acceptance.sandbox.widerApprovalCount
            )
            $result | Add-Member -MemberType NoteProperty -Name valid -Value $valid -Force
            $result | Add-Member -MemberType NoteProperty -Name packageRoot `
                -Value ([string]$package.packageRoot) -Force
            $result
        } catch {
            [pscustomobject]@{
                valid = $false
                status = 'failed'
                packageRoot = $package.packageRoot
                reason = $_.Exception.Message
            }
        }
    }
    return [pscustomobject]@{
        valid = [bool]($package.valid -and $schema.valid -and $sandbox.valid -and $active.valid)
        package = $package
        schema = $schema
        sandbox = $sandbox
        active = $active
    }
}

function Get-WindowsCopilotLegacyGatewayState {
    param(
        [Parameter(Mandatory)]$Lock,
        [string]$Path,
        [object[]]$ListenerStates,
        [object[]]$Processes,
        [object[]]$ScheduledTasks
    )
    $contract = $Lock.migration.legacyGateway
    $port = [int]$contract.listenerPorts[0]
    $allowedBinaryNames = @($contract.binaryNames | ForEach-Object { [string]$_ })
    $allowedProcessNames = @($contract.processNames | ForEach-Object { [string]$_ })
    if ($null -eq $ScheduledTasks) {
        $ScheduledTasks = if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
            @(Get-ScheduledTask -ErrorAction SilentlyContinue)
        } else {
            @()
        }
    }
    $taskCandidates = @($ScheduledTasks | ForEach-Object {
        $task = $_
        foreach ($action in @((Get-LockProperty -InputObject $task -Name 'Actions'))) {
            $execute = [string](Get-LockProperty -InputObject $action -Name 'Execute')
            if ([string]::IsNullOrWhiteSpace($execute)) { continue }
            try {
                $candidate = [IO.Path]::GetFullPath(
                    [Environment]::ExpandEnvironmentVariables($execute)
                )
                if ($allowedBinaryNames -icontains [IO.Path]::GetFileName($candidate)) {
                    $candidate
                }
            } catch { }
        }
    } | Select-Object -Unique)
    if ($null -eq $ListenerStates) {
        $ListenerStates = if (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue) {
            @(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue)
        } else {
            @()
        }
    }
    $portListeners = @($ListenerStates | Where-Object {
        $null -ne $_ -and [int](Get-LockProperty -InputObject $_ -Name 'LocalPort') -eq $port
    })
    $loopbackListeners = @($portListeners | Where-Object {
        [string](Get-LockProperty -InputObject $_ -Name 'LocalAddress') -ceq '127.0.0.1'
    })
    $invalidListeners = @($portListeners | Where-Object {
        [string](Get-LockProperty -InputObject $_ -Name 'LocalAddress') -cne '127.0.0.1'
    })
    if ($null -eq $Processes) {
        $Processes = if ($portListeners.Count -gt 0) {
            @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
                Select-Object ProcessId, Name, ExecutablePath, CommandLine)
        } else {
            @()
        }
    }
    $ownerIds = @($loopbackListeners | ForEach-Object {
        [int](Get-LockProperty -InputObject $_ -Name 'OwningProcess')
    } | Select-Object -Unique)
    $owners = @($Processes | Where-Object {
        $null -ne $_ -and
        $ownerIds -contains [int](Get-LockProperty -InputObject $_ -Name 'ProcessId')
    })
    $listenerStatus = if ($invalidListeners.Count -gt 0) {
        'non-ipv4-loopback-binding'
    } elseif ($loopbackListeners.Count -eq 0) {
        'not-found'
    } elseif ($ownerIds.Count -ne 1 -or $owners.Count -ne 1) {
        'ambiguous'
    } else {
        'loopback-process-resolved'
    }
    if (-not $Path -and $listenerStatus -ceq 'not-found' -and $taskCandidates.Count -gt 1) {
        $listenerStatus = 'task-ambiguous'
    }
    $resolvedPath = if ($Path) {
        [IO.Path]::GetFullPath($Path)
    } elseif ($listenerStatus -ceq 'loopback-process-resolved' -and
        (Get-LockProperty -InputObject $owners[0] -Name 'ExecutablePath')) {
        [IO.Path]::GetFullPath([string](Get-LockProperty -InputObject $owners[0] -Name 'ExecutablePath'))
    } elseif ($listenerStatus -ceq 'not-found' -and $taskCandidates.Count -eq 1) {
        [IO.Path]::GetFullPath([string]$taskCandidates[0])
    } else {
        $null
    }
    if ($Path -and $listenerStatus -ceq 'loopback-process-resolved' -and
        $resolvedPath -ine [IO.Path]::GetFullPath(
            [string](Get-LockProperty -InputObject $owners[0] -Name 'ExecutablePath')
        )) {
        $listenerStatus = 'executable-path-mismatch'
    }
    $nameValid = [bool]($resolvedPath -and
        $allowedBinaryNames -icontains [IO.Path]::GetFileName($resolvedPath))
    $processValid = [bool](
        $listenerStatus -eq 'not-found' -or
        ($listenerStatus -ceq 'loopback-process-resolved' -and
            $allowedProcessNames -icontains
                [string](Get-LockProperty -InputObject $owners[0] -Name 'Name') -and
            $resolvedPath -ieq [IO.Path]::GetFullPath(
                [string](Get-LockProperty -InputObject $owners[0] -Name 'ExecutablePath')
            ))
    )
    $actual = $null
    $pathPhysical = $false
    if ($resolvedPath -and (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        try {
            Assert-NoReparsePointAncestor -Path $resolvedPath
            $actual = (Get-FileHash -LiteralPath $resolvedPath -Algorithm SHA256).Hash.ToLowerInvariant()
            $pathPhysical = $true
        } catch { }
    }
    $expected = [string]$contract.artifact.sha256
    $detected = [bool]($Path -or $portListeners.Count -gt 0 -or $taskCandidates.Count -gt 0)
    $listenerVerified = $listenerStatus -ceq 'loopback-process-resolved'
    $referencingTasks = @()
    $reviewedTasks = @()
    if ($resolvedPath) {
        $referencingTasks = @($ScheduledTasks | Where-Object {
            $actions = @((Get-LockProperty -InputObject $_ -Name 'Actions'))
            @($actions | Where-Object {
                try {
                    [IO.Path]::GetFullPath(
                        [Environment]::ExpandEnvironmentVariables([string]$_.Execute)
                    ) -ieq $resolvedPath
                } catch {
                    $false
                }
            }).Count -gt 0
        })
        $reviewedTasks = @($referencingTasks | Where-Object {
            @((Get-LockProperty -InputObject $_ -Name 'Actions')).Count -eq 1
        } | ForEach-Object {
            [pscustomobject]@{
                taskName = [string]$_.TaskName
                taskPath = [string]$_.TaskPath
                state = [string]$_.State
                enabled = [bool]$_.Settings.Enabled
            }
        })
    }
    $taskVerified = [bool](
        $listenerStatus -ceq 'not-found' -and $taskCandidates.Count -eq 1 -and
        $reviewedTasks.Count -eq 1
    )
    $taskReferencesValid = $referencingTasks.Count -eq $reviewedTasks.Count
    $taskCandidatesMatchResolved = @($taskCandidates | Where-Object {
        [IO.Path]::GetFullPath([string]$_) -ine $resolvedPath
    }).Count -eq 0
    $matchesReviewedLegacy = [bool](
        $detected -and $pathPhysical -and $nameValid -and $processValid -and
        $actual -ceq $expected -and $taskReferencesValid -and
        $taskCandidatesMatchResolved -and
        ($Path -or $listenerVerified -or $taskVerified)
    )
    return [pscustomobject]@{
        path = $resolvedPath
        source = if ($Path) {
            'explicit'
        } elseif ($listenerVerified) {
            'active-loopback-listener'
        } elseif ($taskVerified) {
            'scheduled-task'
        } else {
            $null
        }
        listenerVerified = $listenerVerified
        listenerStatus = $listenerStatus
        sha256 = $actual
        lockedSha256 = $expected
        pathPhysical = $pathPhysical
        binaryNameValid = $nameValid
        processValid = $processValid
        processes = @($owners | ForEach-Object {
            [pscustomobject]@{
                processId = [int]$_.ProcessId
                name = [string](Get-LockProperty -InputObject $_ -Name 'Name')
                executablePath = [string](Get-LockProperty -InputObject $_ -Name 'ExecutablePath')
                commandLine = [string](Get-LockProperty -InputObject $_ -Name 'CommandLine')
            }
        })
        scheduledTasks = @($reviewedTasks)
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
        [object[]]$ListenerStates,
        [object[]]$Processes,
        [object[]]$ScheduledTasks
    )
    Get-WindowsCopilotLegacyGatewayState @PSBoundParameters
}

function Stop-WindowsCopilotLegacyGateway {
    param([Parameter(Mandatory)]$State)
    if (-not $State.matchesReviewedLegacy) {
        throw 'Refusing to stop an unreviewed legacy gateway.'
    }
    foreach ($task in @($State.scheduledTasks)) {
        Stop-ScheduledTask -TaskName ([string]$task.taskName) -TaskPath ([string]$task.taskPath) `
            -ErrorAction SilentlyContinue
        Disable-ScheduledTask -TaskName ([string]$task.taskName) -TaskPath ([string]$task.taskPath) `
            -ErrorAction Stop | Out-Null
    }
    foreach ($process in @($State.processes)) {
        Stop-Process -Id ([int]$process.processId) -Force -ErrorAction Stop
    }
}

function Restore-WindowsCopilotLegacyGateway {
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)]$State
    )
    if (-not $State.path -or -not (Test-Path -LiteralPath ([string]$State.path) -PathType Leaf)) {
        throw 'The reviewed legacy gateway binary was not restored.'
    }
    $current = Get-WindowsCopilotLegacyGatewayState -Lock $Lock -Path ([string]$State.path)
    if (-not $current.matchesReviewedLegacy) {
        throw 'The restored legacy gateway no longer matches the reviewed bytes.'
    }
    $currentTaskKeys = @($current.scheduledTasks | ForEach-Object {
        ([string]$_.taskPath + [string]$_.taskName).ToLowerInvariant()
    })
    foreach ($task in @($State.scheduledTasks)) {
        $key = ([string]$task.taskPath + [string]$task.taskName).ToLowerInvariant()
        if ($currentTaskKeys -notcontains $key) {
            throw "Scheduled task '$([string]$task.taskPath)$([string]$task.taskName)' no longer invokes the reviewed gateway."
        }
        if ([bool]$task.enabled) {
            Enable-ScheduledTask -TaskName ([string]$task.taskName) -TaskPath ([string]$task.taskPath) `
                -ErrorAction Stop | Out-Null
        }
        if ([string]$task.state -ceq 'Running') {
            Start-ScheduledTask -TaskName ([string]$task.taskName) -TaskPath ([string]$task.taskPath) `
                -ErrorAction Stop
        }
    }
    if (@($State.processes).Count -gt 0 -and
        @($State.scheduledTasks | Where-Object { [string]$_.state -ceq 'Running' }).Count -eq 0) {
        Start-Process -FilePath ([string]$State.path) -ErrorAction Stop | Out-Null
    }
}

function Get-WindowsCopilotRemediation {
    param(
        [Parameter(Mandatory)]$Desktop,
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
        requires = 'verified Desktop-managed official runtime; Desktop UI creates the built-in Copilot grant and account route'
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

function ConvertTo-WindowsCopilotSafeDiagnostic {
    param(
        [AllowNull()][object]$Value,
        [int]$Limit = 1000
    )
    if ($null -eq $Value) { return $null }
    $text = [string]$Value
    if ($env:USERPROFILE) {
        $text = [regex]::Replace($text, [regex]::Escape([string]$env:USERPROFILE), '%USERPROFILE%', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    $text = [regex]::Replace($text, '(?i)\b(authorization|token|api[_-]?key|secret)\s*[:=]\s*[^\s,;]+', '$1=<redacted>')
    $text = [regex]::Replace($text, '(?i)\b(bearer\s+|gh[pousr]_|github_pat_)[A-Za-z0-9._-]+', '<redacted>')
    if ($text.Length -gt $Limit) {
        $suffix = '…<truncated>'
        if ($Limit -le $suffix.Length) { return $suffix.Substring(0, $Limit) }
        return $text.Substring(0, $Limit - $suffix.Length) + $suffix
    }
    return $text
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
    $loaderPackageJson = ConvertTo-Json (Join-Path $loaderRoot 'package.json') -Compress
    $script = "import { createRequire } from 'node:module'; import { pathToFileURL } from 'node:url'; const require = createRequire(pathToFileURL($loaderPackageJson)); await Promise.all([$packageJson].map((id) => import(pathToFileURL(require.resolve(id)).href)))"
    $node = Get-Command node -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $node) {
        return [pscustomobject]@{
            valid = $false
            status = 'node-not-found'
            nodePath = $null
            nodeVersion = $null
            cwd = $loaderRoot
            packages = @($Lock.acceptance.loaderImports)
            failure = 'node executable is unavailable'
        }
    }
    $nodeVersion = (& $node.Source --version 2>$null | Select-Object -First 1)
    $probeRoot = Join-Path ([IO.Path]::GetTempPath()) ('dsh-loader-import-' + [guid]::NewGuid().ToString('N'))
    $probeScript = Join-Path $probeRoot 'probe.mjs'
    $stdoutPath = Join-Path $probeRoot 'stdout.log'
    $stderrPath = Join-Path $probeRoot 'stderr.log'
    New-Item -ItemType Directory -Path $probeRoot -Force | Out-Null
    try {
        [IO.File]::WriteAllText($probeScript, $script, [Text.UTF8Encoding]::new($false))
        $process = Start-Process -FilePath $node.Source -ArgumentList @($probeScript) `
            -WorkingDirectory $loaderRoot -Wait -PassThru -NoNewWindow `
            -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        $failure = if ($process.ExitCode -eq 0) {
            $null
        } else {
            (Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue).Trim()
        }
        return [pscustomobject]@{
            valid = [bool]($process.ExitCode -eq 0)
            status = if ($process.ExitCode -eq 0) { 'imported' } else { 'import-failed' }
            nodePath = [string]$node.Source
            nodeVersion = [string]$nodeVersion
            cwd = $loaderRoot
            packages = @($Lock.acceptance.loaderImports)
            failure = ConvertTo-WindowsCopilotSafeDiagnostic $failure
        }
    } catch {
        return [pscustomobject]@{
            valid = $false
            status = 'node-invocation-failed'
            nodePath = [string]$node.Source
            nodeVersion = [string]$nodeVersion
            cwd = $loaderRoot
            packages = @($Lock.acceptance.loaderImports)
            failure = ConvertTo-WindowsCopilotSafeDiagnostic $_.Exception.Message
        }
    } finally {
        Remove-Item -LiteralPath $probeRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Enter-WindowsCopilotDeploymentLock {
    param([Parameter(Mandatory)][string]$BackupRoot)
    [void](Resolve-DeploymentPath $BackupRoot)
    $name = 'Global\DshWindowsOpsDeployment'
    $mutex = [Threading.Mutex]::new($false, $name)
    $acquired = $false
    try {
        try {
            $acquired = $mutex.WaitOne(0)
        } catch [Threading.AbandonedMutexException] {
            $acquired = $true
        }
        if (-not $acquired) {
            throw 'Another Windows Copilot deployment operation is already running.'
        }
        return $mutex
    } catch {
        $mutex.Dispose()
        throw
    }
}

function Exit-WindowsCopilotDeploymentLock {
    param([Parameter(Mandatory)][Threading.Mutex]$Mutex)
    try {
        $Mutex.ReleaseMutex()
    } finally {
        $Mutex.Dispose()
    }
}

function Get-WindowsCopilotLiveSessions {
    [CmdletBinding()]
    param(
        [string]$HostName = '127.0.0.1',
        [int]$Port = 3080,
        [object[]]$Sessions,
        $Response
    )
    if ($PSBoundParameters.ContainsKey('Sessions')) {
        $items = @($Sessions)
    } else {
        if ($PSBoundParameters.ContainsKey('Response')) {
            $response = $Response
        } else {
            $request = @{
                type = 'client-request'
                rpcId = 'windows-ops-restart-preflight'
                method = 'session/list'
                payload = @{ args = @{ _request = @{} } }
            } | ConvertTo-Json -Depth 8
            try {
                $response = Invoke-RestMethod -Method Post -Uri "http://${HostName}:$Port/api/session/list" `
                    -ContentType 'application/json' -Body $request -TimeoutSec 10
            } catch {
                throw "Cannot verify live DSH Sessions before restart: $($_.Exception.Message)"
            }
        }
        $result = Get-LockProperty -InputObject $response -Name 'result'
        $value = Get-LockProperty -InputObject $result -Name 'value'
        $items = Get-LockProperty -InputObject $value -Name 'items'
        if ((Get-LockProperty -InputObject $response -Name 'type') -cne 'server-response' -or
            (Get-LockProperty -InputObject $result -Name 'ok') -ne $true -or
            $items -isnot [array]) {
            throw 'Cannot verify live DSH Sessions before restart: invalid session/list response.'
        }
    }
    $running = @($items | Where-Object { (Get-LockProperty -InputObject $_ -Name 'running') -eq $true })
    $runningIds = @($running | ForEach-Object {
        [string](Get-LockProperty -InputObject $_ -Name 'sessionId')
    })
    if (@($runningIds | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0 -or
        @($runningIds | Sort-Object -Unique).Count -ne $runningIds.Count) {
        throw 'Cannot verify live DSH Sessions before restart: running Sessions require unique non-empty IDs.'
    }
    return @($running | ForEach-Object {
        $projections = Get-LockProperty -InputObject $_ -Name 'projections'
        $values = if ($null -eq $projections) { $null } else {
            Get-LockProperty -InputObject $projections -Name 'values'
        }
        [pscustomobject]@{
            sessionId = [string](Get-LockProperty -InputObject $_ -Name 'sessionId')
            title = if ($null -eq $values) { '' } else {
                [string](Get-LockProperty -InputObject $values -Name 'title')
            }
            origin = [string](Get-LockProperty -InputObject $_ -Name 'origin')
            running = $true
        }
    })
}

function Stop-WindowsCopilotProcessTree {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][int[]]$RootProcessIds,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Processes
    )
    if ($RootProcessIds.Count -eq 0) { return @() }
    $selected = [Collections.Generic.HashSet[int]]::new()
    foreach ($processId in $RootProcessIds) { [void]$selected.Add([int]$processId) }
    do {
        $added = $false
        foreach ($process in $Processes) {
            if ($selected.Contains([int]$process.ParentProcessId) -and
                $selected.Add([int]$process.ProcessId)) {
                $added = $true
            }
        }
    } while ($added)
    $remaining = [Collections.Generic.List[object]]::new()
    foreach ($process in $Processes) {
        if ($selected.Contains([int]$process.ProcessId)) { $remaining.Add($process) }
    }
    while ($remaining.Count -gt 0) {
        $currentProcesses = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Select-Object ProcessId, ParentProcessId, Name, ExecutablePath, CommandLine,
                CreationDate)
        do {
            $added = $false
            foreach ($process in $currentProcesses) {
                if ($selected.Contains([int]$process.ParentProcessId) -and
                    $selected.Add([int]$process.ProcessId)) {
                    $remaining.Add($process)
                    $added = $true
                }
            }
        } while ($added)
        $leaf = @($remaining | Where-Object {
            $candidate = $_
            @($remaining | Where-Object {
                [int]$_.ParentProcessId -eq [int]$candidate.ProcessId
            }).Count -eq 0
        } | Select-Object -First 1)
        if ($leaf.Count -eq 0) { throw 'Desktop process tree contains a cycle.' }
        $snapshot = $leaf[0]
        $current = Get-CimInstance Win32_Process -Filter (
            "ProcessId=$([int]$snapshot.ProcessId)"
        ) -ErrorAction SilentlyContinue
        if (-not $current) {
            [void]$remaining.Remove($snapshot)
            continue
        }
        foreach ($property in @('ParentProcessId', 'ExecutablePath', 'CreationDate')) {
            $expected = Get-LockProperty -InputObject $snapshot -Name $property
            $actual = Get-LockProperty -InputObject $current -Name $property
            if ($null -ne $expected -and [string]$expected -cne [string]$actual) {
                throw "Desktop process identity changed before termination: $([int]$snapshot.ProcessId)."
            }
        }
        try {
            Stop-Process -Id ([int]$snapshot.ProcessId) -Force -ErrorAction Stop
        } catch {
            if (Get-Process -Id ([int]$snapshot.ProcessId) -ErrorAction SilentlyContinue) {
                throw
            }
        }
        [void]$remaining.Remove($snapshot)
    }
    $deadline = (Get-Date).AddSeconds(10)
    do {
        $alive = @($selected | Where-Object {
            $null -ne (Get-Process -Id ([int]$_) -ErrorAction SilentlyContinue)
        })
        if ($alive.Count -eq 0) { break }
        Start-Sleep -Milliseconds 100
    } while ((Get-Date) -lt $deadline)
    if ($alive.Count -gt 0) {
        throw "Desktop process tree did not stop: $($alive -join ', ')."
    }
    return @($selected)
}

function Restart-WindowsCopilotDesktop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DesktopExecutablePath,
        $Lock,
        [int]$TimeoutSeconds = 90,
        [switch]$DryRun,
        [string[]]$AcknowledgeLiveSessionIds,
        [object[]]$Processes,
        [object[]]$LiveSessions,
        [object[]]$FinalLiveSessions
    )
    $executable = Resolve-DeploymentPath $DesktopExecutablePath
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        throw "Desktop executable not found: '$executable'."
    }
    if ($null -eq $Processes) {
        $Processes = @(Get-CimInstance Win32_Process |
            Select-Object ProcessId, ParentProcessId, Name, ExecutablePath, CommandLine,
                CreationDate)
    }
    $desktopProcesses = @($Processes | Where-Object {
        $_.ExecutablePath -and
        [IO.Path]::GetFullPath([string]$_.ExecutablePath) -ieq $executable
    })
    $runningSessions = @(if ($PSBoundParameters.ContainsKey('LiveSessions')) {
        Get-WindowsCopilotLiveSessions -Sessions $LiveSessions
    } elseif ($desktopProcesses.Count -gt 0) {
        Get-WindowsCopilotLiveSessions
    })
    $runningSessionIds = @($runningSessions | ForEach-Object { [string]$_.sessionId } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    $acknowledgedIds = @($AcknowledgeLiveSessionIds | ForEach-Object { [string]$_ } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    $acknowledgementMatches = [bool](
        $runningSessionIds.Count -eq $acknowledgedIds.Count -and
        @($runningSessionIds | Where-Object { $acknowledgedIds -cnotcontains $_ }).Count -eq 0
    )
    if ($DryRun) {
        return [pscustomobject]@{
            status = if ($acknowledgementMatches) {
                'would-restart'
            } elseif ($runningSessionIds.Count -gt 0) {
                'would-block-live-sessions'
            } else {
                'would-block-stale-acknowledgement'
            }
            executable = $executable
            processIds = @($desktopProcesses.ProcessId)
            liveSessions = @($runningSessions)
            acknowledgedSessionIds = @($acknowledgedIds)
        }
    }
    if (-not $acknowledgementMatches) {
        $labels = @($runningSessions | ForEach-Object {
            $title = if ([string]::IsNullOrWhiteSpace([string]$_.title)) { '<untitled>' } else { [string]$_.title }
            "${title} [$([string]$_.sessionId)]"
        }) -join '; '
        throw "Desktop restart blocked because the acknowledged Session IDs do not match the current running set: $labels. Re-run only after direct user approval with -AcknowledgeLiveSessionIds <exact ids>."
    }
    if ($desktopProcesses.Count -gt 0) {
        $finalSessions = @(if ($PSBoundParameters.ContainsKey('FinalLiveSessions')) {
            Get-WindowsCopilotLiveSessions -Sessions $FinalLiveSessions
        } else {
            Get-WindowsCopilotLiveSessions
        })
        $finalSessionIds = @($finalSessions | ForEach-Object { [string]$_.sessionId } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
        if ($finalSessionIds.Count -ne $acknowledgedIds.Count -or
            @($finalSessionIds | Where-Object {
                $acknowledgedIds -cnotcontains $_
            }).Count -gt 0) {
            throw 'Desktop restart blocked because the running Session set changed after acknowledgement.'
        }
    }
    Stop-WindowsCopilotProcessTree -RootProcessIds @($desktopProcesses.ProcessId) `
        -Processes $Processes | Out-Null
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
        try {
            if (-not $Lock) { throw 'The Desktop runtime lock is required for restart acceptance.' }
            $active = Get-WindowsCopilotDesktopRuntimeState -Lock $Lock `
                -Processes $current -DesktopExecutablePath $executable
            if (-not $active.valid) {
                throw "Desktop runtime selector is not accepted: '$($active.status)'."
            }
            return [pscustomobject]@{
                status = 'restarted'
                executable = $executable
                stoppedProcessIds = @($desktopProcesses.ProcessId)
                backendProcessIds = @($active.processIds)
                runtimeSelector = $active.selector
                runtimeVersion = $active.version
            }
        } catch {
            $lastError = $_.Exception.Message
        }
    } while ((Get-Date) -lt $deadline)
    Stop-WindowsCopilotProcessTree -RootProcessIds @($currentDesktop.ProcessId) `
        -Processes $current | Out-Null
    throw "Desktop restarted, but its backend did not select an exact supported runtime within $TimeoutSeconds seconds. Last check: $lastError"
}

function Get-PnpmImporterDependencyBlock {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string]$Name
    )
    $lines = @($Text -split "`r?`n")
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $match = [regex]::Match($lines[$index], '^([ ]*)' + [regex]::Escape($Name) + ':\s*$')
        if (-not $match.Success) { continue }
        $indent = $match.Groups[1].Value.Length
        $block = [Collections.Generic.List[string]]::new()
        for ($cursor = $index + 1; $cursor -lt $lines.Count; $cursor++) {
            $line = [string]$lines[$cursor]
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                $leading = $line.Length - $line.TrimStart(' ').Length
                if ($leading -le $indent) { break }
            }
            $block.Add($line)
        }
        return ($block -join "`n")
    }
    return $null
}

function Test-WindowsCopilotProfileCoherence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$DshHome
    )
    $home = Resolve-DeploymentPath $DshHome
    $packageName = [string]$Lock.components.copilotIntegration.package.name
    $expectedVersion = [string]$Lock.components.copilotIntegration.package.version
    $expectedSha256 = [string]$Lock.components.copilotIntegration.package.artifact.sha256
    $states = @($Lock.profile.coherence.copilotProfiles | ForEach-Object {
        $profile = [string]$_
        $root = Join-Path $home ("profiles\$profile")
        $manifestPath = Join-Path $root 'package.json'
        $lockPath = Join-Path $root 'pnpm-lock.yaml'
        $installedManifestPath = Join-Path $root "node_modules\$packageName\package.json"
        $installedBaselinePath = Join-Path $root "node_modules\$packageName\deployment-baseline.json"
        $reasons = [Collections.Generic.List[string]]::new()
        $dependency = $null
        $installedVersion = $null
        $baselineVersion = $null
        $artifactPath = $null
        $artifactSha256 = $null
        $closure = $null
        try {
            if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
                [void]$reasons.Add('manifest-missing')
            } else {
                $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $dependency = [string](Get-LockProperty -InputObject $manifest.dependencies -Name $packageName)
                if ([string]::IsNullOrWhiteSpace($dependency)) { [void]$reasons.Add('dependency-missing') }
            }
            if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
                [void]$reasons.Add('lock-missing')
            } elseif ($dependency) {
                $lockText = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8
                $artifactName = "$packageName-$expectedVersion.tgz"
                $importerBlock = Get-PnpmImporterDependencyBlock -Text $lockText -Name $packageName
                if ($null -eq $importerBlock -or
                    -not [regex]::IsMatch($importerBlock,
                        '(?m)^\s*specifier:\s*' + [regex]::Escape($dependency) + '\s*$')) {
                    [void]$reasons.Add('lock-specifier-mismatch')
                }
                if ($null -eq $importerBlock -or
                    -not [regex]::IsMatch($importerBlock,
                        '(?m)^\s*version:\s*[^\r\n]*' + [regex]::Escape($artifactName) + '[^\r\n]*$') -or
                    -not [regex]::IsMatch($lockText,
                        '(?m)^\s{2}' + [regex]::Escape($packageName) + '@[^\r\n]*' +
                        [regex]::Escape($artifactName) + ':\s*$') -or
                    -not [regex]::IsMatch($lockText,
                        '(?m)^\s*resolution:\s*\{[^\r\n]*tarball:\s*[^\r\n]*' +
                        [regex]::Escape($artifactName))) {
                    [void]$reasons.Add('lock-version-mismatch')
                }
            }
            if (-not (Test-Path -LiteralPath $installedManifestPath -PathType Leaf)) {
                [void]$reasons.Add('installed-package-missing')
            } else {
                $installedVersion = [string](Get-Content -LiteralPath $installedManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json).version
                if ($installedVersion -cne $expectedVersion) { [void]$reasons.Add('installed-version-mismatch') }
            }
            if (-not (Test-Path -LiteralPath $installedBaselinePath -PathType Leaf)) {
                [void]$reasons.Add('installed-baseline-missing')
            } else {
                $baselineVersion = [string](Get-Content -LiteralPath $installedBaselinePath -Raw -Encoding UTF8 | ConvertFrom-Json).package.version
                if ($baselineVersion -cne $expectedVersion) { [void]$reasons.Add('baseline-version-mismatch') }
            }
            if ($dependency -and $dependency.StartsWith('file:', [StringComparison]::Ordinal)) {
                $artifactPath = $dependency.Substring(5).Replace('/', '\')
                if (-not [IO.Path]::IsPathRooted($artifactPath)) { $artifactPath = Join-Path $root $artifactPath }
                $artifactPath = [IO.Path]::GetFullPath($artifactPath)
                if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
                    [void]$reasons.Add('artifact-missing')
                } else {
                    $artifactSha256 = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
                    if ($artifactSha256 -cne $expectedSha256) { [void]$reasons.Add('artifact-hash-mismatch') }
                    $closure = Test-WindowsCopilotInstalledArtifactClosure `
                        -ArtifactPath $artifactPath `
                        -InstalledRoot (Split-Path -Parent $installedManifestPath) `
                        -Sha256 $expectedSha256 `
                        -ExpectedName ([string]$Lock.components.copilotIntegration.package.artifact.name) `
                        -ExpectedSize ([long]$Lock.components.copilotIntegration.package.artifact.size)
                    if (-not $closure.valid) {
                        [void]$reasons.Add('installed-artifact-closure-mismatch')
                    }
                }
            } elseif ($dependency) {
                [void]$reasons.Add('artifact-local-copy-required')
            }
        } catch {
            [void]$reasons.Add('profile-coherence-read-failed')
        }
        [pscustomobject]@{
            profile = $profile
            valid = $reasons.Count -eq 0
            dependency = $dependency
            installedVersion = $installedVersion
            baselineVersion = $baselineVersion
            artifactPath = $artifactPath
            artifactSha256 = $artifactSha256
            closure = $closure
            reasons = @($reasons)
        }
    })
    return [pscustomobject]@{
        valid = @($states | Where-Object { -not $_.valid }).Count -eq 0
        profiles = $states
    }
}

function Get-WindowsCopilotOptionalOverlayStates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$ProfileRoot,
        $Profile
    )
    $profileDependencyNames = if ($Profile -and $Profile.dependencies) {
        @($Profile.dependencies.PSObject.Properties.Name | ForEach-Object { [string]$_ })
    } else { @() }
    $profileLockPath = Join-Path $ProfileRoot ([string]$Lock.profile.lockManifest)
    $profileLockText = if (Test-Path -LiteralPath $profileLockPath -PathType Leaf) {
        Get-Content -LiteralPath $profileLockPath -Raw -Encoding UTF8
    } else { '' }
    return @($Lock.profile.optionalOverlays | ForEach-Object {
        $overlay = $_
        $name = [string]$overlay.name
        $configured = $profileDependencyNames -contains $name
        $configuredSource = if ($configured) {
            [string](Get-LockProperty -InputObject $Profile.dependencies -Name $name)
        } else { $null }
        $artifactPath = $null
        $artifactSha256 = $null
        $artifactValid = $false
        $closure = $null
        $manifestPath = Join-Path $ProfileRoot "node_modules\$name\package.json"
        if ($configuredSource -and
            $configuredSource.StartsWith('file:', [StringComparison]::OrdinalIgnoreCase)) {
            $artifactPath = $configuredSource.Substring(5).Replace('/', '\')
            if (-not [IO.Path]::IsPathRooted($artifactPath)) {
                $artifactPath = Join-Path $ProfileRoot $artifactPath
            }

            $artifactPath = [IO.Path]::GetFullPath($artifactPath)
            if (Test-Path -LiteralPath $artifactPath -PathType Leaf) {
                $artifactSha256 = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
                $artifactValid = [bool](
                    [IO.Path]::GetFileName($artifactPath) -ceq [string]$overlay.artifact.name -and
                    $artifactSha256 -ceq [string]$overlay.artifact.sha256 -and
                    (Get-Item -LiteralPath $artifactPath).Length -eq [long]$overlay.artifact.size
                )
                if ($artifactValid -and (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
                    $closure = Test-WindowsCopilotInstalledArtifactClosure `
                        -ArtifactPath $artifactPath `
                        -InstalledRoot (Split-Path -Parent $manifestPath) `
                        -Sha256 ([string]$overlay.artifact.sha256) `
                        -ExpectedName ([string]$overlay.artifact.name) `
                        -ExpectedSize ([long]$overlay.artifact.size)
                    $artifactValid = [bool]$closure.valid
                }
            }
        }
        $sourceValid = [bool](
            -not $configured -or
            $configuredSource -ceq [string]$overlay.source -or
            $artifactValid
        )
        $resolvedCommit = [string](Get-LockProperty -InputObject $overlay -Name 'resolvedCommit')
        $importerBlock = Get-PnpmImporterDependencyBlock -Text $profileLockText -Name $name
        $resolvedCommitValid = [bool](-not $configured -or $artifactValid -or
            (-not [string]::IsNullOrWhiteSpace($resolvedCommit) -and
                $null -ne $importerBlock -and [regex]::IsMatch(
                    $importerBlock,
                    '(?m)^\s*version:\s*[^\r\n]*' + [regex]::Escape($resolvedCommit) + '[^\r\n]*$'
                )))
        $installedVersion = $null
        if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
            try { $installedVersion = [string](Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json).version } catch { }
        }
        $versionValid = [bool]($null -eq $installedVersion -or $installedVersion -ceq [string]$overlay.version)
        $installedPhysical = [bool](
            $null -ne $installedVersion -and
            -not ((Get-Item -LiteralPath (Split-Path -Parent $manifestPath)).Attributes -band
                [IO.FileAttributes]::ReparsePoint)
        )
        $bundles = if ($Profile -and $Profile.dsh -and $Profile.dsh.profile) {
            @($Profile.dsh.profile.bundles)
        } else { @() }
        $bundlePresent = $bundles -contains $name
        [pscustomobject]@{
            name = $name
            classification = if ($sourceValid -and $resolvedCommitValid -and $versionValid) {
                'optional-known'
            } else {
                'optional-unknown'
            }
            configured = $configured
            configuredSource = $configuredSource
            sourceValid = $sourceValid
            resolvedCommitValid = $resolvedCommitValid
            installed = $null -ne $installedVersion
            physical = $installedPhysical
            version = $installedVersion
            versionValid = $versionValid
            bundlePresent = $bundlePresent
            artifactPath = $artifactPath
            artifactSha256 = $artifactSha256
            artifactValid = $artifactValid
            closure = $closure
            required = $false
        }
    })
}

function Test-WindowsCopilotVerificationAcceptance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Installation,
        [switch]$IncludeCompanionSuite
    )
    $manualSmokePending = [bool](
        -not $Installation.complete -and $Installation.readyForManualSearchSmoke
    )
    $baseValid = [bool]$Installation.complete
    $companionValid = [bool](
        -not $IncludeCompanionSuite -or
        (
            $Installation.profile.companionSuite.selected -and
            $Installation.profile.companionSuite.valid
        )
    )
    return [pscustomobject]@{
        valid = [bool]($baseValid -and $companionValid)
        baseValid = $baseValid
        companionValid = $companionValid
        manualSmokePending = $manualSmokePending
        status = if ($manualSmokePending) {
            'manual-search-smoke-pending'
        } elseif (-not $baseValid) {
            'base-acceptance-failed'
        } elseif (-not $companionValid) {
            'companion-suite-acceptance-failed'
        } else {
            'complete'
        }
    }
}

function Remove-WindowsCopilotCompanionSuiteLocked {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]$Lock,
                [Parameter(Mandatory)][string]$DshHome,
                [Parameter(Mandatory)][string]$BackupRoot,
                [string]$DesktopExecutablePath
            )
            Test-WindowsCopilotLock -Lock $Lock | Out-Null
            $home = Resolve-DeploymentPath $DshHome
            $profileRoot = Join-Path $home ([string]$Lock.profile.relativePath)
            $packagePath = Join-Path $profileRoot ([string]$Lock.profile.packageManifest)
            $lockPath = Join-Path $profileRoot ([string]$Lock.profile.lockManifest)
            $workspacePath = Join-Path $profileRoot ([string]$Lock.profile.workspaceManifest)
            $nodeModules = Join-Path $profileRoot 'node_modules'
            if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
                throw "The '$([string]$Lock.profile.name)' Profile is not initialized."
            }
            $beforeCoherence = Test-WindowsCopilotProfileCoherence -Lock $Lock -DshHome $home
            if (-not $beforeCoherence.valid) {
                throw 'Required Copilot profile coherence must be valid before removing optional overlays.'
            }
            $optionalNames = @(Get-WindowsCopilotCompanionOverlays -Lock $Lock |
                ForEach-Object { [string]$_.name })
            $requiredName = [string]$Lock.components.copilotIntegration.package.name
            $requiredTarget = Join-Path $nodeModules $requiredName
            $operationRoot = New-BackupOperation -BackupRoot $BackupRoot -DshHome $home
            $snapshots = [Collections.Generic.List[object]]::new()
            foreach ($item in (@(
                [pscustomobject]@{ path = $packagePath; relativePath = 'profile\package.json'; pluginTarget = $false },
                [pscustomobject]@{ path = $lockPath; relativePath = 'profile\pnpm-lock.yaml'; pluginTarget = $false },
                [pscustomobject]@{ path = $workspacePath; relativePath = 'profile\pnpm-workspace.yaml'; pluginTarget = $false },
                [pscustomobject]@{ path = $requiredTarget; relativePath = "plugins\$requiredName"; pluginTarget = $true }
            ) + @($optionalNames | ForEach-Object {
                [pscustomobject]@{
                    path = Join-Path $nodeModules $_
                    relativePath = "plugins\$_"
                    pluginTarget = $true
                }
            }))) {
                $snapshot = [pscustomobject]@{
                    path = [IO.Path]::GetFullPath([string]$item.path)
                    relativePath = [string]$item.relativePath
                    pluginTarget = [bool]$item.pluginTarget
                    existed = Test-Path -LiteralPath ([string]$item.path)
                    originalFingerprint = Get-DeploymentPathFingerprint -Path ([string]$item.path)
                }
                $snapshots.Add($snapshot)
                Backup-DeploymentPath -Path ([string]$item.path) `
                    -RelativePath ([string]$item.relativePath) -OperationRoot $operationRoot
            }
            if (-not $DesktopExecutablePath) {
                $DesktopExecutablePath = Join-Path $env:LOCALAPPDATA (
                    'Deepseek Harness Desktop\deepseek-harness-desktop.exe'
                )
            }
            $internalStates = @(Get-WindowsCopilotInternalPluginStates -Lock $Lock `
                -ProfileRoot $profileRoot -DesktopExecutablePath $DesktopExecutablePath)
            $invalidInternal = @($internalStates | Where-Object { -not $_.valid })
            if ($invalidInternal.Count -gt 0) {
                throw "Official Desktop profile link is invalid before optional removal: '$($invalidInternal.name -join ', ')'."
            }
            foreach ($state in $internalStates) {
                $target = [string]$state.path
                $snapshots.Add([pscustomobject]@{
                    path = [IO.Path]::GetFullPath($target)
                    relativePath = "plugins\official\$([string]$state.name)"
                    pluginTarget = $true
                    existed = $false
                    linkTarget = [IO.Path]::GetFullPath([string]$state.expectedTarget)
                    originalFingerprint = Get-DeploymentPathFingerprint -Path $target
                })
            }
            try {
                $profile = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 |
                    ConvertFrom-Json
                foreach ($name in $optionalNames) {
                    if ($profile.dependencies) {
                        $profile.dependencies.PSObject.Properties.Remove($name)
                    }
                }
                if ($profile.dsh -and $profile.dsh.profile) {
                    $profile.dsh.profile.bundles = @($profile.dsh.profile.bundles |
                        Where-Object { $optionalNames -notcontains [string]$_ })
                }
                $profile | ConvertTo-Json -Depth 12 |
                    Set-Content -LiteralPath $packagePath -Encoding UTF8
                Invoke-PinnedPnpmCommands `
                    -PackageManager ([string]$Lock.components.copilotIntegration.package.packageManager) `
                    -Commands @(, @('install', '--no-frozen-lockfile')) `
                    -WorkingDirectory $profileRoot
                foreach ($snapshot in @($snapshots | Where-Object {
                    $_.PSObject.Properties['linkTarget']
                })) {
                    $current = Get-DeploymentPathFingerprint -Path ([string]$snapshot.path)
                    if (-not (Test-DeploymentFingerprintEqual -Left $current `
                        -Right $snapshot.originalFingerprint)) {
                        Restore-DeploymentSnapshots -Snapshots @($snapshot) `
                            -OperationRoot $operationRoot -NodeModulesRoot $nodeModules
                    }
                    $verified = Get-DeploymentPathFingerprint -Path ([string]$snapshot.path)
                    if (-not (Test-DeploymentFingerprintEqual -Left $verified `
                        -Right $snapshot.originalFingerprint)) {
                        throw "Official Desktop profile link changed during optional removal: '$([string]$snapshot.path)'."
                    }
                }
                foreach ($name in $optionalNames) {
                    $target = Join-Path $nodeModules $name
                    if (Get-DeploymentPathItem -Path $target) {
                        Remove-ProfilePluginTarget -Target $target -NodeModulesRoot $nodeModules
                    }
                }
                $requiredSnapshot = @($snapshots | Where-Object {
                    [string]$_.path -ieq [IO.Path]::GetFullPath($requiredTarget)
                })[0]
                $requiredCurrent = Get-DeploymentPathFingerprint -Path $requiredTarget
                if (-not (Test-DeploymentFingerprintEqual -Left $requiredCurrent `
                    -Right $requiredSnapshot.originalFingerprint)) {
                    Restore-DeploymentSnapshots -Snapshots @($requiredSnapshot) `
                        -OperationRoot $operationRoot -NodeModulesRoot $nodeModules
                }
                $afterCoherence = Test-WindowsCopilotProfileCoherence -Lock $Lock -DshHome $home
                if (-not $afterCoherence.valid) {
                    throw 'Required Copilot profile coherence changed during optional removal.'
                }
                foreach ($snapshot in $snapshots) {
                    $snapshot | Add-Member -NotePropertyName appliedFingerprint `
                        -NotePropertyValue (Get-DeploymentPathFingerprint -Path ([string]$snapshot.path))
                }
                $receipt = [pscustomobject]@{
                    schemaVersion = 1
                    deploymentId = [string]$Lock.deploymentId
                    operationId = Split-Path -Leaf $operationRoot
                    status = 'active'
                    nodeModulesRoot = $nodeModules
                    snapshots = @($snapshots)
                    removedCompanions = @($optionalNames)
                }
                Set-WindowsCopilotJsonFile -Value $receipt `
                    -Path (Join-Path $operationRoot 'receipt.json') -Depth 12
                return [pscustomobject]@{
                    mode = 'remove-companion-suite'
                    operationId = [string]$receipt.operationId
                    removed = @($optionalNames)
                    required = $requiredName
                }
            } catch {
                $failure = $_
                try {
                    Restore-DeploymentSnapshots -Snapshots @($snapshots) `
                        -OperationRoot $operationRoot -NodeModulesRoot $nodeModules
                } catch {
                    throw "Optional removal failed and rollback was incomplete: $($failure.Exception.Message) Rollback error: $($_.Exception.Message)"
                }
                throw $failure
            }
        }

function Remove-WindowsCopilotCompanionSuite {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]$Lock,
                [Parameter(Mandatory)][string]$DshHome,
                [Parameter(Mandatory)][string]$BackupRoot,
                [string]$DesktopExecutablePath
            )
            $mutex = Enter-WindowsCopilotDeploymentLock -BackupRoot $BackupRoot
            try {
                return Remove-WindowsCopilotCompanionSuiteLocked @PSBoundParameters
            } finally {
                Exit-WindowsCopilotDeploymentLock -Mutex $mutex
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
        [string]$DesktopExecutablePath,
        [string]$GatewayExecutablePath,
        [object[]]$DesktopProcesses,
        [switch]$SkipRuntimeChecks,
        [switch]$IncludeCompanionSuite
    )
    Test-WindowsCopilotLock -Lock $Lock | Out-Null
    $home = Resolve-DeploymentPath $DshHome
    $profileRoot = Join-Path $home ([string]$Lock.profile.relativePath)
    $packagePath = Join-Path $profileRoot ([string]$Lock.profile.packageManifest)
    $workspacePath = Join-Path $profileRoot ([string]$Lock.profile.workspaceManifest)
    $settingsPath = Join-Path $home ([string]$Lock.profile.settingsManifest)
    $desktop = Get-WindowsCopilotDesktopState -Lock $Lock -Path $DesktopExecutablePath
    $legacyGateway = Get-WindowsCopilotLegacyGatewayState -Lock $Lock `
        -Path $GatewayExecutablePath
    $officialRuntime = Get-WindowsCopilotOfficialRuntimeState -Lock $Lock
    $credential = Test-DshCopilotCredentialRecord -DshHome $home
    $providerRoute = Get-DshCopilotRouteState -SettingsPath $settingsPath
    $profileCoherence = Test-WindowsCopilotProfileCoherence -Lock $Lock -DshHome $home

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
                if ($name -eq [string]$Lock.components.copilotIntegration.package.name) {
                    if (-not (Test-WindowsCopilotDesiredArtifactDependency -Lock $Lock `
                        -Dependency $dependency -DshHome $home -ProfileRoot $profileRoot)) {
                        $dependencyValid = $false
                    }
                } elseif ($dependency.Replace('\', '/') -ne [string]$plugin.version) {
                    $dependencyValid = $false
                }
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
    $desktopRootPath = if ($desktop.path) { Split-Path -Parent ([string]$desktop.path) } else { $null }
    $shippedDependencyStates = @($Lock.components.desktop.shippedDependencies | ForEach-Object {
        $target = if ($desktopRootPath) { Join-Path $desktopRootPath ([string]$_.relativePath) } else { $null }
        $manifest = if ($target) { Join-Path $target 'package.json' } else { $null }
        $version = $null
        if ($manifest -and (Test-Path -LiteralPath $manifest -PathType Leaf)) {
            try { $version = [string](Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json).version } catch { }
        }
        [pscustomobject]@{
            name = [string]$_.name
            target = $target
            exists = [bool]($target -and (Test-Path -LiteralPath $target -PathType Container))
            version = $version
            valid = [bool]($version -ceq [string]$_.version -and $_.profileBundle -eq $false)
            profileBundle = [bool]$_.profileBundle
        }
    })
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

    $profileDependencyNames = if ($profile -and $profile.dependencies) {
        @($profile.dependencies.PSObject.Properties.Name | ForEach-Object { [string]$_ })
    } else { @() }
    $optionalOverlayStates = @(Get-WindowsCopilotOptionalOverlayStates `
        -Lock $Lock -ProfileRoot $profileRoot -Profile $profile)
    $selectedCompanionNames = if ($IncludeCompanionSuite) {
        @(Get-WindowsCopilotCompanionOverlays -Lock $Lock | ForEach-Object { [string]$_.name })
    } else { @() }
    $selectedCompanionStates = @($optionalOverlayStates | Where-Object {
        $selectedCompanionNames -contains [string]$_.name
    })
    $companionSuiteValid = [bool](
        -not $IncludeCompanionSuite -or
        (
            $selectedCompanionStates.Count -eq $selectedCompanionNames.Count -and
            @($selectedCompanionStates | Where-Object {
                -not $_.configured -or -not $_.installed -or -not $_.physical -or
                -not $_.versionValid -or -not $_.sourceValid -or
                -not $_.resolvedCommitValid -or -not $_.bundlePresent -or
                -not $_.artifactValid
            }).Count -eq 0
        )
    )
    $knownDependencyNames = @($Lock.profile.plugins.name) + @($Lock.profile.optionalOverlays.name)
    $unknownOverlayNames = @($profileDependencyNames | Where-Object { $knownDependencyNames -notcontains $_ })

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

    $routesValid = [bool](
        $providerRoute.exists -and
        $providerRoute.referenceFree -and
        $providerRoute.modelsComplete -and
        $providerRoute.mixedProtocolApis
    )

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
    $runtimeValidation = Test-WindowsCopilotOfficialRuntime -Lock $Lock `
        -DesktopExecutablePath ([string]$desktop.path) -DesktopProcesses $DesktopProcesses `
        -ListenerStates $listeners -SkipRuntimeChecks:$SkipRuntimeChecks
    $officialRuntime = $runtimeValidation.package
    $activeRuntime = $runtimeValidation.active
    $runtimeSchema = $runtimeValidation.schema
    $sandbox = $runtimeValidation.sandbox

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
            if (-not $activeRuntime.valid) {
                throw 'The active Desktop runtime is not valid; refusing an ambiguous dump-config.'
            }
            $entryPath = [string]$activeRuntime.entryPath
            if (-not $entryPath -or -not (Test-Path -LiteralPath $entryPath -PathType Leaf)) {
                throw 'The active Desktop runtime entrypoint is unavailable for composed-config validation.'
            }
            $arguments = @($command[1..($command.Count - 1)] | ForEach-Object { [string]$_ })
            if ([IO.Path]::GetExtension($entryPath) -ieq '.js') {
                $node = Get-Command node -ErrorAction Stop | Select-Object -First 1
                $output = & $node.Source $entryPath @arguments 2>&1 | Out-String
            } else {
                $output = & $entryPath @arguments 2>&1 | Out-String
            }
            if ($LASTEXITCODE -ne 0) { throw 'active runtime dump-config failed.' }
            $composedCheck = Get-WindowsCopilotComposedConfigState -Lock $Lock -Content $output
            $composedCheck | Add-Member -NotePropertyName execution -NotePropertyValue ([pscustomobject]@{
                selector = $activeRuntime.selector
                version = $activeRuntime.version
                entryPath = $entryPath
            }) -Force
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
        $officialRuntime.valid -and
        $profileCoherence.valid -and
        $dependencyValid -and
        $bundleValid -and
        $allowBuildsValid -and
        $routesValid -and
        $credential.configured -and
        $companionSuiteValid -and
        $unknownOverlayNames.Count -eq 0 -and
        @($plugins | Where-Object {
            -not $_.exists -or -not $_.versionValid -or
            ($_.materialize -and -not $_.physical) -or
            ($_.source -eq 'desktop-internal' -and -not $_.officialDesktopLink) -or
            -not $_.baselineValid -or -not $_.payloadValid
        }).Count -eq 0 -and
        @($shippedDependencyStates | Where-Object { -not $_.valid }).Count -eq 0
    )
    $runtimeValid = [bool](
        -not $SkipRuntimeChecks -and
        @($listeners | Where-Object { -not $_.loopbackOnly }).Count -eq 0 -and
        $loaderImports.valid -and
        $activeRuntime.valid -and
        $runtimeSchema.valid -and
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
    if (-not $officialRuntime.valid) {
        $driftReasons.Add('desktop-official-runtime-' + [string]$officialRuntime.status)
    } elseif (-not $activeRuntime.valid) {
        if ([string]$activeRuntime.status -like '*-listener-owner-mismatch') {
            $driftReasons.Add('desktop-runtime-process-does-not-own-3080')
        } else {
            $driftReasons.Add('desktop-runtime-unsupported-or-inactive')
        }
    }
    if (-not $SkipRuntimeChecks -and -not $sandbox.valid) {
        $driftReasons.Add('official-runtime-sandbox-regression-gate-failed')
    }
    if (-not $SkipRuntimeChecks -and -not $runtimeSchema.valid) {
        $driftReasons.Add('official-runtime-schema-invalid')
    }
    if (-not $profileCoherence.valid) { $driftReasons.Add('profile-manifest-lock-installed-drift') }
    if (@($optionalOverlayStates | Where-Object classification -eq 'optional-unknown').Count -gt 0) {
        $driftReasons.Add('profile-optional-overlay-source-drift')
    }
    if ($unknownOverlayNames.Count -gt 0) {
        $driftReasons.Add('profile-unknown-dependency')
    }
    if ($IncludeCompanionSuite -and -not $companionSuiteValid) {
        $driftReasons.Add('companion-suite-drift')
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
    if (@($shippedDependencyStates | Where-Object { -not $_.valid }).Count -gt 0) {
        $driftReasons.Add('desktop-shipped-dependency-drift')
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
        $legacy022.Count -eq 1 -and
        [string]$legacy022[0].installedVersion -eq '0.2.2' -and
        -not $officialRuntime.valid -and
        @($composedCheck.forbiddenActiveEntries) -contains 'web-search-provider' -and
        @($composedCheck.forbiddenMarkers) -contains 'searchProvider: deepseek-official' -and
        -not $composedCheck.managedConfigValid
    )
    $driftDetected = [bool]($driftReasons.Count -gt 0)
    $remediation = Get-WindowsCopilotRemediation -Desktop $desktop -DriftDetected $driftDetected
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
            runtime = $officialRuntime
            copilotIntegration = $provider
        }
        drift = [pscustomobject]@{
            detected = $driftDetected
            incidentId = if ($incidentDetected) { 'windows-copilot-drift-2026-08-28' } else { $null }
            mixedState = [bool](($desktop.valid -or $incidentDetected) -and
                (-not $provider.versionValid -or -not $officialRuntime.valid))
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
            coherence = $profileCoherence
            optionalOverlays = @($optionalOverlayStates)
            companionSuite = [pscustomobject]@{
                selected = [bool]$IncludeCompanionSuite
                valid = $companionSuiteValid
                members = @($selectedCompanionStates)
                acceptance = $Lock.companionSuite.acceptance
            }
            unknownOverlays = @($unknownOverlayNames | ForEach-Object {
                [pscustomobject]@{ name = [string]$_; classification = 'optional-unknown' }
            })
            credential = $credential
            plugins = @($plugins)
            shippedDependencies = @($shippedDependencyStates)
        }
        runtime = [pscustomobject]@{
            listeners = @($listeners)
            loaderImports = $loaderImports
            officialRuntime = $officialRuntime
            activeRuntime = $activeRuntime
            runtimeSchema = $runtimeSchema
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
        [Parameter(Mandatory)][Alias('ProviderSourceRoot')][string]$CopilotIntegrationSourceRoot,
        [Parameter(Mandatory)][Alias('ProviderArtifactPath')][string]$CopilotIntegrationArtifactPath,
        [Parameter(Mandatory)][string]$DesktopArtifactPath,
        [string]$GatewayArtifactPath,
        [string]$GatewayInstallRoot,
        [string]$GatewayExecutablePath,
        [Parameter(Mandatory)][string]$BackupRoot,
        $Catalog,
        [string]$DesktopExecutablePath,
        [switch]$RestartDesktop,
        [switch]$IncludeCompanionSuite,
        [string[]]$AcknowledgeLiveSessionIds,
        [int]$TimeoutSeconds = 90
    )
    Test-WindowsCopilotLock -Lock $Lock | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($GatewayArtifactPath)) {
        throw '-GatewayArtifactPath is retired and is not accepted by Apply.'
    }
    $desktopState = Get-WindowsCopilotDesktopState -Lock $Lock -Path $DesktopExecutablePath
    if ($desktopState.newerThanLock) {
        throw "Installed Desktop $($desktopState.version) is newer than locked Desktop $($desktopState.lockedVersion). Refusing a downgrade; update the lock or use a reviewed compatible migration."
    }
    Get-WindowsCopilotProfileMigrationPlan -Lock $Lock -DshHome $DshHome `
        -DesktopExecutablePath ([string]$desktopState.path) | Out-Null
    $settingsPath = Join-Path (Resolve-DeploymentPath $DshHome) ([string]$Lock.profile.settingsManifest)
    Assert-WindowsCopilotSettingsShape -Lock $Lock -SettingsPath $settingsPath
    Assert-SourceCheckout -Root $CopilotIntegrationSourceRoot -Source $Lock.components.copilotIntegration.source
    Test-CopilotIntegrationDeploymentContract -Lock $Lock -SourceRoot $CopilotIntegrationSourceRoot | Out-Null
    Test-LockedArtifact -Path $DesktopArtifactPath `
        -Sha256 ([string]$Lock.components.desktop.artifact.sha256) `
        -ExpectedName ([string]$Lock.components.desktop.artifact.name) | Out-Null
    $copilotIntegrationArtifact = Resolve-DeploymentPath $CopilotIntegrationArtifactPath
    Test-CopilotIntegrationDeploymentContract -Lock $Lock `
        -ArtifactPath $copilotIntegrationArtifact | Out-Null
    $operationRoot = New-BackupOperation -BackupRoot $BackupRoot -DshHome $DshHome
    $gatewayState = $null
    $gatewayStopped = $false
    $gatewaySnapshots = [Collections.Generic.List[object]]::new()
    $transactionSnapshots = [Collections.Generic.List[object]]::new()
    $registrySnapshots = [Collections.Generic.List[object]]::new()
    $profileReceipt = $null
    $outerSnapshotsMerged = $false
    $globalPackageNames = @($Lock.globalInstall.packages | ForEach-Object {
        [string]$_.name
    })
    foreach ($name in @($globalPackageNames | Select-Object -Unique)) {
        $target = Join-Path $NpmGlobalRoot $name.Replace('/', '\')
        $relative = Join-Path 'transaction\global-packages' (
            $name.Replace('@', '').Replace('/', '__')
        )
        $snapshot = [pscustomobject]@{
            path = [IO.Path]::GetFullPath($target)
            relativePath = $relative
            pluginTarget = $false
            existed = Test-Path -LiteralPath $target
            originalFingerprint = Get-DeploymentPathFingerprint -Path $target
        }
        $transactionSnapshots.Add($snapshot)
        Backup-DeploymentPath -Path $target -RelativePath $relative `
            -OperationRoot $operationRoot
    }
    if (-not $desktopState.valid) {
        $desktopRoot = Split-Path -Parent ([string]$desktopState.path)
        $desktopSnapshot = [pscustomobject]@{
            path = [IO.Path]::GetFullPath($desktopRoot)
            relativePath = 'transaction\desktop'
            pluginTarget = $false
            existed = Test-Path -LiteralPath $desktopRoot
            originalFingerprint = Get-DeploymentPathFingerprint -Path $desktopRoot
        }
        $transactionSnapshots.Add($desktopSnapshot)
        Backup-DeploymentPath -Path $desktopRoot -RelativePath $desktopSnapshot.relativePath `
            -OperationRoot $operationRoot
        foreach ($shortcut in @($Lock.components.desktop.install.sideEffects.shortcuts)) {
            $folder = [Environment]::GetFolderPath(
                [Environment+SpecialFolder]([string]$shortcut.specialFolder)
            )
            $shortcutPath = Join-Path $folder ([string]$shortcut.name)
            $shortcutSnapshot = [pscustomobject]@{
                path = [IO.Path]::GetFullPath($shortcutPath)
                relativePath = Join-Path 'transaction\shortcuts' (
                    [string]$shortcut.specialFolder + '.lnk'
                )
                pluginTarget = $false
                existed = Test-Path -LiteralPath $shortcutPath
                originalFingerprint = Get-DeploymentPathFingerprint -Path $shortcutPath
            }
            $transactionSnapshots.Add($shortcutSnapshot)
            Backup-DeploymentPath -Path $shortcutPath `
                -RelativePath $shortcutSnapshot.relativePath -OperationRoot $operationRoot
        }
        foreach ($registryKey in @($Lock.components.desktop.install.sideEffects.registryKeys)) {
            $registrySnapshots.Add((
                Backup-WindowsCopilotRegistryKey -Key ([string]$registryKey) `
                    -RelativePath 'transaction\registry\desktop-uninstall.reg' `
                    -OperationRoot $operationRoot
            ))
        }
    }
    try {
    $legacyGatewayTarget = if ($GatewayExecutablePath) {
        [IO.Path]::GetFullPath($GatewayExecutablePath)
    } elseif ($GatewayInstallRoot) {
        $gatewayCandidates = @($Lock.migration.legacyGateway.binaryNames | ForEach-Object {
            Join-Path $GatewayInstallRoot ([string]$_)
        } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
        if ($gatewayCandidates.Count -gt 1) {
            throw 'Multiple reviewed-name legacy gateway binaries were found; provide -GatewayExecutablePath.'
        }
        if ($gatewayCandidates.Count -eq 1) { [IO.Path]::GetFullPath($gatewayCandidates[0]) } else { $null }
    } else {
        $null
    }
    $gatewayState = if ($legacyGatewayTarget) {
        Get-WindowsCopilotLegacyGatewayState -Lock $Lock -Path $legacyGatewayTarget
    } else {
        Get-WindowsCopilotLegacyGatewayState -Lock $Lock
    }
    if ($gatewayState.detected -and -not $gatewayState.matchesReviewedLegacy) {
        throw "A legacy gateway was found but is not the unique reviewed IPv4 loopback deployment ($($gatewayState.listenerStatus))."
    }
    if ($gatewayState.matchesReviewedLegacy) {
        $legacyGatewayTarget = [string]$gatewayState.path
        $backupName = [IO.Path]::GetFileName($legacyGatewayTarget)
        Backup-DeploymentPath -Path $legacyGatewayTarget -RelativePath 'migration\copilot2api.exe' `
            -OperationRoot $operationRoot
        $gatewaySnapshots.Add([pscustomobject]@{
            path = [IO.Path]::GetFullPath($legacyGatewayTarget)
            relativePath = 'migration\copilot2api.exe'
            originalName = $backupName
            pluginTarget = $false
            existed = $true
            originalFingerprint = Get-DeploymentPathFingerprint -Path $legacyGatewayTarget
        })
        $gatewayStopped = $true
        Stop-WindowsCopilotLegacyGateway -State $gatewayState
        Remove-Item -LiteralPath $legacyGatewayTarget -Force
    }

        $globalSpecs = @($Lock.globalInstall.packages | ForEach-Object { "$($_.name)@$($_.version)" })
        Invoke-LockedCommand -FilePath 'npm' -Arguments (@('install', '--global') + $globalSpecs) `
            -WorkingDirectory $CopilotIntegrationSourceRoot

        if (-not $desktopState.valid) {
            $desktopProcesses = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
                Select-Object ProcessId, ParentProcessId, Name, ExecutablePath,
                    CommandLine, CreationDate)
            $runningDesktop = @($desktopProcesses | Where-Object {
                $_.ExecutablePath -and $desktopState.path -and
                [IO.Path]::GetFullPath([string]$_.ExecutablePath) -ieq
                    [IO.Path]::GetFullPath([string]$desktopState.path)
            })
            if ($runningDesktop.Count -gt 0) {
                $acknowledged = @($AcknowledgeLiveSessionIds |
                    ForEach-Object { [string]$_ } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    Sort-Object -Unique)
                $liveIds = @(Get-WindowsCopilotLiveSessions |
                    ForEach-Object { [string]$_.sessionId } | Sort-Object -Unique)
                if ($liveIds.Count -ne $acknowledged.Count -or
                    @($liveIds | Where-Object {
                        $acknowledged -cnotcontains $_
                    }).Count -gt 0) {
                    throw 'Desktop upgrade requires acknowledgement of the exact running Session IDs.'
                }
                $finalLiveIds = @(Get-WindowsCopilotLiveSessions |
                    ForEach-Object { [string]$_.sessionId } | Sort-Object -Unique)
                if ($finalLiveIds.Count -ne $acknowledged.Count -or
                    @($finalLiveIds | Where-Object {
                        $acknowledged -cnotcontains $_
                    }).Count -gt 0) {
                    throw 'Desktop upgrade blocked because the running Session set changed after acknowledgement.'
                }
                Stop-WindowsCopilotProcessTree `
                    -RootProcessIds @($runningDesktop.ProcessId) `
                    -Processes $desktopProcesses | Out-Null
            }
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

        $runtime = Test-WindowsCopilotOfficialRuntime -Lock $Lock `
            -DesktopExecutablePath ([string]$desktopState.path) -SkipActiveCheck
        if (-not $runtime.valid) {
            throw "Desktop-managed official runtime attestation failed: '$([string]$runtime.package.status)'."
        }
        $profileReceipt = Set-WindowsCopilotProfile -Lock $Lock -DshHome $DshHome `
            -NpmGlobalRoot $NpmGlobalRoot -CopilotIntegrationArtifactPath $copilotIntegrationArtifact `
            -Catalog $Catalog -BackupRoot $BackupRoot -OperationRoot $operationRoot `
            -DesktopExecutablePath ([string]$desktopState.path) `
            -IncludeCompanionSuite:$IncludeCompanionSuite
        foreach ($snapshot in @($transactionSnapshots) + @($gatewaySnapshots)) {
            $snapshot | Add-Member -NotePropertyName appliedFingerprint `
                -NotePropertyValue (Get-DeploymentPathFingerprint -Path ([string]$snapshot.path)) -Force
        }
        foreach ($snapshot in $registrySnapshots) {
            $snapshot | Add-Member -NotePropertyName appliedFingerprint `
                -NotePropertyValue (
                    Get-WindowsCopilotRegistryFingerprint -Key ([string]$snapshot.key)
                ) -Force
        }
        $allSnapshots = @($profileReceipt.snapshots) + @($transactionSnapshots) +
            @($gatewaySnapshots)
        $profileReceipt.snapshots = $allSnapshots
        $outerSnapshotsMerged = $true
        if ($gatewayState -and $gatewayState.matchesReviewedLegacy) {
            $profileReceipt | Add-Member -NotePropertyName legacyGatewayState `
                -NotePropertyValue $gatewayState -Force
        }
        $profileReceipt | Add-Member -NotePropertyName registrySnapshots `
            -NotePropertyValue @($registrySnapshots) -Force
        Set-WindowsCopilotJsonFile -Value $profileReceipt `
            -Path (Join-Path $operationRoot 'receipt.json') -Depth 12

        $restart = if ($RestartDesktop) {
            Restart-WindowsCopilotDesktop -DesktopExecutablePath ([string]$desktopState.path) `
                -Lock $Lock -TimeoutSeconds $TimeoutSeconds `
                -AcknowledgeLiveSessionIds $AcknowledgeLiveSessionIds
        } else {
            [pscustomobject]@{
                status = 'not-requested'
                executable = [string]$desktopState.path
            }
        }
    } catch {
        $failure = $_
        $snapshots = if ($profileReceipt) {
            if ($outerSnapshotsMerged) {
                @($profileReceipt.snapshots)
            } else {
                @($profileReceipt.snapshots) + @($transactionSnapshots) +
                    @($gatewaySnapshots)
            }
        } else {
            @($transactionSnapshots) + @($gatewaySnapshots)
        }
        if ($snapshots.Count -gt 0) {
            try {
                $profileRoot = Join-Path (Resolve-DeploymentPath $DshHome) ([string]$Lock.profile.relativePath)
                Restore-DeploymentSnapshots -Snapshots $snapshots -OperationRoot $operationRoot `
                    -NodeModulesRoot (Join-Path $profileRoot 'node_modules')
                Restore-WindowsCopilotRegistrySnapshots -Snapshots @($registrySnapshots) `
                    -OperationRoot $operationRoot
                if ($gatewayStopped -and $gatewayState) {
                    Restore-WindowsCopilotLegacyGateway -Lock $Lock -State $gatewayState
                }
            } catch {
                throw "Apply failed and rollback was incomplete: $($failure.Exception.Message) Rollback error: $($_.Exception.Message)"
            }
        }
        throw $failure
    }

    return [pscustomobject]@{
        mode = 'apply'
        deploymentId = [string]$Lock.deploymentId
        deploymentOperationId = Split-Path -Leaf $operationRoot
        globalTransaction = [string]$Lock.globalInstall.transactionId
        copilotIntegrationArtifactSha256 = (
            Get-FileHash -LiteralPath $copilotIntegrationArtifact -Algorithm SHA256
        ).Hash.ToLowerInvariant()
        providerArtifactSha256 = (
            Get-FileHash -LiteralPath $copilotIntegrationArtifact -Algorithm SHA256
        ).Hash.ToLowerInvariant()
        profile = $profileReceipt
        companionSuite = [pscustomobject]@{
            selected = [bool]$IncludeCompanionSuite
            members = if ($IncludeCompanionSuite) {
                @([string]$Lock.components.copilotIntegration.package.name) +
                    @(Get-WindowsCopilotCompanionOverlays -Lock $Lock |
                        ForEach-Object { [string]$_.name })
            } else {
                @([string]$Lock.components.copilotIntegration.package.name)
            }
            acceptance = $Lock.companionSuite.acceptance
        }
        officialRuntime = $runtime
        desktopRestart = $restart
        nextCheck = 'Run tools\install-windows-copilot.ps1 -Action Verify.'
    }
}

function Invoke-WindowsCopilotApply {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$DshHome,
        [Parameter(Mandatory)][string]$NpmGlobalRoot,
        [Parameter(Mandatory)][Alias('ProviderSourceRoot')][string]$CopilotIntegrationSourceRoot,
        [Parameter(Mandatory)][Alias('ProviderArtifactPath')][string]$CopilotIntegrationArtifactPath,
        [Parameter(Mandatory)][string]$DesktopArtifactPath,
        [string]$GatewayArtifactPath,
        [string]$GatewayInstallRoot,
        [string]$GatewayExecutablePath,
        [Parameter(Mandatory)][string]$BackupRoot,
        $Catalog,
        [string]$DesktopExecutablePath,
        [switch]$RestartDesktop,
        [switch]$IncludeCompanionSuite,
        [string[]]$AcknowledgeLiveSessionIds,
        [int]$TimeoutSeconds = 90
    )
    $mutex = Enter-WindowsCopilotDeploymentLock -BackupRoot $BackupRoot
    try {
        return Invoke-WindowsCopilotApplyLocked @PSBoundParameters
    } finally {
        Exit-WindowsCopilotDeploymentLock -Mutex $mutex
    }
}

Export-ModuleMember -Function @(
    'Read-WindowsCopilotLock',
    'Test-WindowsCopilotLock',
    'Test-LockedArtifact',
    'Test-WindowsCopilotInstalledArtifactClosure',
    'Get-WindowsCopilotDirectoryTreeState',
    'Save-WindowsCopilotLockedArtifact',
    'Resolve-LockedCopilotPackageSpec',
    'Test-CopilotIntegrationDeploymentContract',
    'Test-ProviderDeploymentContract',
    'Get-WindowsCopilotInstallPlan',
    'Get-WindowsCopilotRouteModels',
    'Set-PnpmAllowBuilds',
    'Set-WindowsCopilotRoutes',
    'Set-WindowsCopilotProfile',
    'Test-WindowsCopilotSearchResponse',
    'Test-WindowsCopilotComposedConfig',
    'Test-DshRuntimeSchemaState',
    'Test-WindowsCopilotProfileCoherence',
    'Get-WindowsCopilotOptionalOverlayStates',
    'Get-WindowsCopilotDesktopState',
    'Get-WindowsCopilotOfficialRuntimeState',
    'Get-WindowsCopilotDesktopRuntimeState',
    'Test-WindowsCopilotOfficialRuntime',
    'Restore-WindowsCopilotDeployment',
    'Get-WindowsCopilotLiveSessions',
    'Restart-WindowsCopilotDesktop',
    'Test-WindowsCopilotInstallation',
    'Test-WindowsCopilotVerificationAcceptance',
    'Remove-WindowsCopilotCompanionSuite',
    'Enter-WindowsCopilotDeploymentLock',
    'Exit-WindowsCopilotDeploymentLock',
    'Invoke-WindowsCopilotApply'
)
