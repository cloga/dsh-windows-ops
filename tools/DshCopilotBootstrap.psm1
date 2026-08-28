Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:SettingsBegin = '# dsh-windows-ops: copilot settings begin'
$script:SettingsEnd = '# dsh-windows-ops: copilot settings end'
$script:ProfileBegin = '# dsh-windows-ops: copilot profile begin'
$script:ProfileEnd = '# dsh-windows-ops: copilot profile end'

function ConvertTo-DshSingleQuotedYaml {
    param([Parameter(Mandatory)][string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Get-DshExplicitVisionCapability {
    param([Parameter(Mandatory)]$Model)

    $modalities = @()
    foreach ($name in @('input', 'inputModalities', 'modalities')) {
        $property = $Model.PSObject.Properties[$name]
        if ($property) { $modalities += @($property.Value) }
    }
    if (@($modalities | Where-Object { [string]$_ -match '^(?i:image|vision)$' }).Count -gt 0) {
        return [pscustomobject]@{ capable = $true; evidence = 'catalog-modalities' }
    }

    foreach ($containerName in @('capabilities', 'supports')) {
        $containerProperty = $Model.PSObject.Properties[$containerName]
        if (-not $containerProperty -or $null -eq $containerProperty.Value) { continue }
        $container = $containerProperty.Value
        foreach ($name in @('vision', 'image', 'images')) {
            $property = $container.PSObject.Properties[$name]
            if ($property -and $property.Value -eq $true) {
                return [pscustomobject]@{ capable = $true; evidence = "catalog-$containerName-$name" }
            }
        }
        $supportsProperty = $container.PSObject.Properties['supports']
        if ($supportsProperty -and $supportsProperty.Value) {
            foreach ($name in @('vision', 'image', 'images')) {
                $property = $supportsProperty.Value.PSObject.Properties[$name]
                if ($property -and $property.Value -eq $true) {
                    return [pscustomobject]@{ capable = $true; evidence = "catalog-$containerName-supports-$name" }
                }
            }
        }
    }
    return [pscustomobject]@{ capable = $false; evidence = 'no-explicit-catalog-evidence' }
}

function Get-DshCatalogModel {
    param(
        [Parameter(Mandatory)]$Catalog,
        [Parameter(Mandatory)][string]$Model
    )

    $items = @()
    if ($Catalog.PSObject.Properties['data']) { $items = @($Catalog.data) }
    elseif ($Catalog.PSObject.Properties['models']) { $items = @($Catalog.models) }
    elseif ($Catalog -is [Collections.IEnumerable] -and $Catalog -isnot [string]) { $items = @($Catalog) }

    $match = @($items | Where-Object {
        ($_.PSObject.Properties['id'] -and [string]$_.id -eq $Model) -or
        ($_.PSObject.Properties['name'] -and [string]$_.name -eq $Model)
    } | Select-Object -First 1)
    if ($match.Count -eq 0) { throw "Selected model '$Model' is absent from the copilot2api catalog." }
    $vision = Get-DshExplicitVisionCapability -Model $match[0]
    return [pscustomobject]@{
        id = $Model
        raw = $match[0]
        visionCapable = [bool]$vision.capable
        visionEvidence = [string]$vision.evidence
    }
}

function Get-DshCopilotCatalog {
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Model,
        [int]$TimeoutSeconds = 10
    )

    $uri = $BaseUrl.TrimEnd('/') + '/models'
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $uri -Method Get -TimeoutSec $TimeoutSeconds
        $catalog = $response.Content | ConvertFrom-Json
    } catch {
        throw "copilot2api model catalog is unreachable or invalid at '$uri'."
    }
    $selected = Get-DshCatalogModel -Catalog $catalog -Model $Model
    return [pscustomobject]@{
        uri = $uri
        statusCode = [int]$response.StatusCode
        selectedModel = $selected
    }
}

function Get-DshRequiredProperty {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Context
    )
    $property = $Object.PSObject.Properties[$Name]
    if (-not $property -or $null -eq $property.Value) {
        throw "$Context is missing required property '$Name'."
    }
    return $property.Value
}

function ConvertTo-DshRepositorySlug {
    param([Parameter(Mandatory)][string]$RepositoryUrl)

    $value = $RepositoryUrl.Trim() -replace '^git\+', ''
    $match = [regex]::Match(
        $value,
        '^(?:(?:https?|ssh)://(?:git@)?|git@)?github\.com[/:](?<owner>[^/:\s]+)/(?<repo>[^/:\s]+?)(?:\.git)?/?$',
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    if (-not $match.Success) { throw "Receipt repositoryUrl is not a normalized GitHub repository URL." }
    return ($match.Groups['owner'].Value + '/' + $match.Groups['repo'].Value).ToLowerInvariant()
}

function Get-DshPrefixFromCliPath {
    param([Parameter(Mandatory)][string]$CliPath)

    $normalized = $CliPath.Replace('/', '\')
    $canonicalSuffix = '\node_modules\.bin\dsh.cmd'
    if ($normalized.EndsWith($canonicalSuffix, [StringComparison]::OrdinalIgnoreCase)) {
        return $normalized.Substring(0, $normalized.Length - $canonicalSuffix.Length)
    }
    if ([IO.Path]::GetFileName($normalized) -ieq 'dsh.cmd') {
        return [IO.Path]::GetDirectoryName($normalized)
    }
    throw "DSH_CLI_PATH must name the prefix-root dsh.cmd or the receipt canonical CLI."
}

function Get-DshSha256Text {
    param([Parameter(Mandatory)][string]$Text)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Resolve-DshCliInfo {
    param(
        [string]$DshCliPath,
        [string]$ExpectedRepository = 'cloga/deepseek-harness',
        [string[]]$GlobalRoots
    )

    $candidate = $DshCliPath
    if (-not $candidate) { $candidate = $env:DSH_CLI_PATH }
    if (-not $candidate) {
        $command = Get-Command dsh -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) {
            $candidate = $command.Source
            if ([IO.Path]::GetExtension($candidate) -ieq '.ps1') {
                $cmdShim = [IO.Path]::ChangeExtension($candidate, '.cmd')
                if (Test-Path -LiteralPath $cmdShim -PathType Leaf) { $candidate = $cmdShim }
            }
        }
    }
    if (-not $candidate) { throw 'Local dsh CLI was not found. Set DSH_CLI_PATH.' }
    $cliPath = [IO.Path]::GetFullPath($candidate)
    if (-not (Test-Path -LiteralPath $cliPath -PathType Leaf)) {
        throw "DSH_CLI_PATH does not name a file: '$cliPath'."
    }

    $prefix = [IO.Path]::GetFullPath((Get-DshPrefixFromCliPath -CliPath $cliPath))
    $canonicalCli = [IO.Path]::GetFullPath((Join-Path $prefix 'node_modules\.bin\dsh.cmd'))
    $desktopCli = [IO.Path]::GetFullPath((Join-Path $prefix 'dsh.cmd'))
    if ($cliPath -ine $canonicalCli -and $cliPath -ine $desktopCli) {
        throw "DSH_CLI_PATH is not consistent with the installed prefix '$prefix'."
    }
    if (-not (Test-Path -LiteralPath $canonicalCli -PathType Leaf)) {
        throw "The receipt canonical CLI is missing: '$canonicalCli'."
    }
    if (-not (Test-Path -LiteralPath $desktopCli -PathType Leaf)) {
        throw "The receipt prefix-root CLI is missing: '$desktopCli'."
    }
    $shimLines = @(Get-Content -LiteralPath $desktopCli -Encoding UTF8)
    if (
        $shimLines.Count -ne 2 -or
        $shimLines[0] -notmatch '(?i)^@?echo off$' -or
        $shimLines[1] -notmatch '(?i)^@?call "%~dp0node_modules\\\.bin\\dsh\.cmd" %\*$'
    ) {
        throw "The prefix-root dsh.cmd does not forward to the receipt canonical CLI."
    }

    $receiptPath = Join-Path $prefix 'dsh-local-install.json'
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
        throw "The local Core install receipt is missing: '$receiptPath'."
    }
    try {
        $receipt = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        throw "The local Core install receipt is not valid JSON: '$receiptPath'."
    }
    $schemaVersion = Get-DshRequiredProperty -Object $receipt -Name 'schemaVersion' -Context 'Receipt'
    if (
        ($schemaVersion -isnot [int] -and $schemaVersion -isnot [long]) -or
        [int64]$schemaVersion -ne 1
    ) {
        throw 'The local Core install receipt schemaVersion must be 1.'
    }
    $repositoryUrl = [string](Get-DshRequiredProperty -Object $receipt -Name 'repositoryUrl' -Context 'Receipt')
    $repository = ConvertTo-DshRepositorySlug -RepositoryUrl $repositoryUrl
    if ($repository -ine $ExpectedRepository) {
        throw "The local Core receipt repository is '$repository', expected '$ExpectedRepository'."
    }
    $commitSha = [string](Get-DshRequiredProperty -Object $receipt -Name 'commitSha' -Context 'Receipt')
    if ($commitSha -notmatch '^[0-9a-fA-F]{40}$') { throw 'Receipt commitSha must be a full 40-character SHA.' }
    $releaseManifestSha256 = [string](Get-DshRequiredProperty -Object $receipt -Name 'releaseManifestSha256' -Context 'Receipt')
    if ($releaseManifestSha256 -notmatch '^[0-9a-fA-F]{64}$') {
        throw 'Receipt releaseManifestSha256 must be a 64-character SHA-256.'
    }
    $receiptCli = [IO.Path]::GetFullPath(
        [string](Get-DshRequiredProperty -Object $receipt -Name 'cliPath' -Context 'Receipt')
    )
    if ($receiptCli -ine $desktopCli) {
        throw "Receipt cliPath '$receiptCli' does not match prefix-root CLI '$desktopCli'."
    }

    $packageRoot = [IO.Path]::GetFullPath((Join-Path $prefix 'node_modules\@deepseek-ai\dsh'))
    $manifestPath = Join-Path $packageRoot 'package.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "The installed @deepseek-ai/dsh manifest is missing: '$manifestPath'."
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $packageName = [string](Get-DshRequiredProperty -Object $receipt -Name 'packageName' -Context 'Receipt')
    $packageVersion = [string](Get-DshRequiredProperty -Object $receipt -Name 'packageVersion' -Context 'Receipt')
    if ($packageName -cne '@deepseek-ai/dsh' -or [string]$manifest.name -cne $packageName) {
        throw 'Receipt packageName does not match the installed @deepseek-ai/dsh package.'
    }
    if (-not $packageVersion -or [string]$manifest.version -cne $packageVersion) {
        throw 'Receipt packageVersion does not match the installed @deepseek-ai/dsh package.'
    }

    $receiptPackages = @((Get-DshRequiredProperty -Object $receipt -Name 'packages' -Context 'Receipt'))
    if ($receiptPackages.Count -eq 0) { throw 'Receipt packages must contain the installed runtime closure.' }
    $seen = @{}
    $normalizedPackages = @()
    foreach ($item in $receiptPackages) {
        $name = [string](Get-DshRequiredProperty -Object $item -Name 'name' -Context 'Receipt package')
        $version = [string](Get-DshRequiredProperty -Object $item -Name 'version' -Context "Receipt package '$name'")
        $filename = [string](Get-DshRequiredProperty -Object $item -Name 'filename' -Context "Receipt package '$name'")
        $sha256 = [string](Get-DshRequiredProperty -Object $item -Name 'sha256' -Context "Receipt package '$name'")
        $files = Get-DshRequiredProperty -Object $item -Name 'files' -Context "Receipt package '$name'"
        if (-not $name -or $seen.ContainsKey($name)) { throw "Receipt package name is empty or duplicated: '$name'." }
        if ($name -notmatch '^(?:@[a-z0-9][a-z0-9._-]*/)?[a-z0-9][a-z0-9._-]*$') {
            throw "Receipt package name is invalid: '$name'."
        }
        if (-not $version) { throw "Receipt package '$name' has no version." }
        if ([IO.Path]::GetFileName($filename) -cne $filename -or $filename -notmatch '\.tgz$') {
            throw "Receipt package '$name' has an invalid tarball filename."
        }
        if ($sha256 -notmatch '^[0-9a-fA-F]{64}$') { throw "Receipt package '$name' has an invalid SHA-256." }
        if ($files -isnot [ValueType] -or [int64]$files -le 0 -or [double]$files -ne [int64]$files) {
            throw "Receipt package '$name' has an invalid file count."
        }
        $seen[$name] = $true

        $installedManifestPath = Join-Path $prefix (
            'node_modules\' + $name.Replace('/', '\') + '\package.json'
        )
        if (-not (Test-Path -LiteralPath $installedManifestPath -PathType Leaf)) {
            throw "Receipt package '$name' is not installed under the receipt prefix."
        }
        $installedManifest = Get-Content -LiteralPath $installedManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$installedManifest.name -cne $name -or [string]$installedManifest.version -cne $version) {
            throw "Receipt package '$name@$version' does not match its installed manifest."
        }
        $normalizedPackages += [ordered]@{
            name = $name
            version = $version
            filename = $filename
            sha256 = $sha256.ToLowerInvariant()
            files = [int64]$files
        }
    }
    if (-not $seen.ContainsKey($packageName)) {
        throw "Receipt packages do not include '$packageName'."
    }
    $manifestJson = ConvertTo-Json -InputObject @($normalizedPackages) -Compress -Depth 4
    if ((Get-DshSha256Text -Text $manifestJson) -ine $releaseManifestSha256) {
        throw 'Receipt releaseManifestSha256 does not match the listed installed packages.'
    }

    return [pscustomobject]@{
        cliPath = $cliPath
        canonicalCliPath = $canonicalCli
        prefix = $prefix
        packageRoot = $packageRoot
        version = $packageVersion
        repository = $ExpectedRepository
        commitSha = $commitSha.ToLowerInvariant()
        receiptPath = [IO.Path]::GetFullPath($receiptPath)
        releaseManifestSha256 = $releaseManifestSha256.ToLowerInvariant()
        packageCount = $receiptPackages.Count
    }
}

function Test-DshActiveDesktopCore {
    param(
        [Parameter(Mandatory)]$CliInfo,
        [string]$DesktopRoot,
        [object[]]$Processes
    )

    if ($null -eq $Processes) {
        $Processes = @(Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId, Name, ExecutablePath, CommandLine)
    }
    $desktop = @($Processes | Where-Object { [string]$_.Name -match '^DeepSeek Harness(\.exe)?$' })
    if ($desktop.Count -eq 0) { throw 'No active DSH Desktop process was found.' }

    $descendants = [Collections.Generic.HashSet[int]]::new()
    foreach ($item in $desktop) { [void]$descendants.Add([int]$item.ProcessId) }
    do {
        $added = $false
        foreach ($item in $Processes) {
            if ($descendants.Contains([int]$item.ParentProcessId) -and $descendants.Add([int]$item.ProcessId)) {
                $added = $true
            }
        }
    } while ($added)

    $packageRoot = ([string]$CliInfo.packageRoot).Replace('/', '\')
    $cliPath = ([string]$CliInfo.cliPath).Replace('/', '\')
    $active = @($Processes | Where-Object {
        $descendants.Contains([int]$_.ProcessId) -and $_.CommandLine -and (
            ([string]$_.CommandLine).Replace('/', '\').IndexOf($packageRoot, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            ([string]$_.CommandLine).Replace('/', '\').IndexOf($cliPath, [StringComparison]::OrdinalIgnoreCase) -ge 0
        )
    })
    if ($active.Count -eq 0) { throw 'Desktop is not running the selected local dsh package.' }
    if ($DesktopRoot) {
        $desktopPrefix = [IO.Path]::GetFullPath($DesktopRoot).TrimEnd('\') + '\'
        if ($CliInfo.packageRoot.StartsWith($desktopPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'The selected dsh package is inside the Desktop packaged-core directory.'
        }
    }
    return [pscustomobject]@{ healthy = $true; processIds = @($active | Select-Object -ExpandProperty ProcessId) }
}

function Test-DshRendererCompatibility {
    param(
        [Parameter(Mandatory)][string]$PackageRoot,
        [Parameter(Mandatory)][string]$DshHome
    )

    $renderer = Join-Path $PackageRoot 'node_modules\@deepseek-ai\dsh-client-ui-renderer\lib\client.js'
    if (-not (Test-Path -LiteralPath $renderer -PathType Leaf)) {
        throw "Active-core renderer was not found at '$renderer'."
    }
    $source = Get-Content -LiteralPath $renderer -Raw -Encoding UTF8
    if (-not $source.Contains('exports.SlotOutlet = SlotOutlet;')) {
        if (-not $source.Contains('return module.exports;')) {
            throw 'Renderer SlotOutlet export is absent and the exact patch anchor is incompatible.'
        }
        throw 'Renderer SlotOutlet export is absent. Apply the Desktop exact-marker patch before bootstrap.'
    }
    $flatRenderer = Join-Path $DshHome 'profiles\node_modules\@deepseek-ai\dsh-client-ui-renderer\lib\client.js'
    if (-not (Test-Path -LiteralPath $flatRenderer -PathType Leaf)) {
        throw 'The DSH profiles flat module fallback does not expose the active renderer.'
    }
    $flatSource = Get-Content -LiteralPath $flatRenderer -Raw -Encoding UTF8
    if (-not $flatSource.Contains('exports.SlotOutlet = SlotOutlet;')) {
        throw 'The DSH profiles flat module fallback exposes a renderer without SlotOutlet.'
    }
    return [pscustomobject]@{ healthy = $true; renderer = $renderer; flatRenderer = $flatRenderer }
}

function Test-DshCredentialReference {
    param(
        [Parameter(Mandatory)][string]$DshHome,
        [string]$Reference = 'COPILOT_API_KEY'
    )
    if ([Environment]::GetEnvironmentVariable($Reference)) { return 'environment' }
    $path = Join-Path $DshHome '.credentials.yaml'
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $lines = @(Get-Content -LiteralPath $path -Encoding UTF8)
        if (@($lines | Where-Object { $_ -match '^\s*version\s*:\s*1\s*$' }).Count -ne 1) {
            throw 'The credential store is not a version 1 document.'
        }
        $inRefs = $false
        foreach ($line in $lines) {
            if ($line -match '^refs\s*:\s*$') { $inRefs = $true; continue }
            if ($line -match '^\S') { $inRefs = $false }
            if ($inRefs -and $line -match ("^\s{2}$([regex]::Escape($Reference))\s*:\s*(.+?)\s*$")) {
                $value = $matches[1].Trim()
                if ($value -and $value -notmatch '^#' -and $value -notin @("''", '""')) {
                    return 'credential-store'
                }
            }
        }
    }
    throw "Credential reference '$Reference' is unresolved."
}

function Set-DshManagedTextBlock {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Begin,
        [Parameter(Mandatory)][string]$End,
        [Parameter(Mandatory)][string]$Block,
        [string[]]$ConflictPatterns = @(),
        [switch]$DryRun
    )

    $exists = Test-Path -LiteralPath $Path -PathType Leaf
    $current = if ($exists) { Get-Content -LiteralPath $Path -Raw -Encoding UTF8 } else { '' }
    $beginIndex = $current.IndexOf($Begin, [StringComparison]::Ordinal)
    $endIndex = $current.IndexOf($End, [StringComparison]::Ordinal)
    $beginCount = [regex]::Matches($current, [regex]::Escape($Begin)).Count
    $endCount = [regex]::Matches($current, [regex]::Escape($End)).Count
    if ($beginCount -gt 1 -or $endCount -gt 1) { throw "Duplicate managed markers exist in '$Path'." }
    if (($beginIndex -ge 0) -xor ($endIndex -ge 0)) { throw "Managed markers are incomplete in '$Path'." }
    if ($beginIndex -ge 0 -and $endIndex -lt $beginIndex) { throw "Managed markers are reversed in '$Path'." }

    $outside = $current
    if ($beginIndex -ge 0) {
        $endExclusive = $endIndex + $End.Length
        while ($endExclusive -lt $current.Length -and $current[$endExclusive] -in "`r", "`n") { $endExclusive++ }
        $outside = $current.Substring(0, $beginIndex) + $current.Substring($endExclusive)
    }
    foreach ($pattern in $ConflictPatterns) {
        if ($outside -match $pattern) { throw "Unmanaged conflicting configuration exists in '$Path'." }
    }

    if ($beginIndex -ge 0) {
        $next = $current.Substring(0, $beginIndex) + $Block.TrimEnd() + [Environment]::NewLine + $current.Substring($endExclusive)
    } else {
        $trimmed = $current.TrimEnd()
        if ($trimmed -match '(?m)^\[\]\s*$') {
            $trimmed = [regex]::Replace($trimmed, '(?m)^\[\]\s*$', '').TrimEnd()
        }
        $prefix = if ($trimmed) { $trimmed + [Environment]::NewLine } else { '' }
        $next = $prefix + $Block.TrimEnd() + [Environment]::NewLine
    }
    $changed = $next -ne $current
    if ($changed -and -not $DryRun) {
        $parent = Split-Path -Parent $Path
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        $temp = "$Path.dsh-ops-tmp"
        try {
            Set-Content -LiteralPath $temp -Value $next -Encoding UTF8 -NoNewline
            Move-Item -LiteralPath $temp -Destination $Path -Force
        } finally {
            if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
        }
    }
    return [pscustomobject]@{ path = $Path; changed = $changed; status = if (-not $changed) { 'unchanged' } elseif ($DryRun) { 'would-change' } else { 'changed' } }
}

function Set-DshCopilotSettings {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][bool]$VisionCapable,
        [switch]$DryRun
    )
    $input = if ($VisionCapable) { '          input: [text, image]' } else { '          input: [text]' }
    $block = @"
$script:SettingsBegin
llm-pi-ai:
  providers:
    copilot-responses:
      displayName: GitHub Copilot via copilot2api
      apiKeyEnv: COPILOT_API_KEY
      api: openai-responses
      baseURL: $(ConvertTo-DshSingleQuotedYaml $BaseUrl)
      models:
        - id: $(ConvertTo-DshSingleQuotedYaml $Model)
$input
agent-default-model:
  provider: copilot-responses
  model: $(ConvertTo-DshSingleQuotedYaml $Model)
$script:SettingsEnd
"@
    return Set-DshManagedTextBlock -Path $Path -Begin $script:SettingsBegin -End $script:SettingsEnd `
        -Block $block -ConflictPatterns @('(?m)^llm-pi-ai\s*:', '(?m)^agent-default-model\s*:') -DryRun:$DryRun
}

function Set-DshCopilotProfilePatch {
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$DryRun
    )
    $block = @"
$script:ProfileBegin
- id: web
  disabled: true
- id: web-search-deepseek
  disabled: true
- id: tool-web
  disabled: true
- id: web-search-provider
  config:
    enabled: true
    providers: [copilot-responses]
    apiKeyEnv: COPILOT_API_KEY
    probe: true
$script:ProfileEnd
"@
    return Set-DshManagedTextBlock -Path $Path -Begin $script:ProfileBegin -End $script:ProfileEnd `
        -Block $block -ConflictPatterns @(
            '(?m)^\s*-\s+id:\s+web\s*$',
            '(?m)^\s*-\s+id:\s+web-search-deepseek\s*$',
            '(?m)^\s*-\s+id:\s+tool-web\s*$',
            '(?m)^\s*-\s+id:\s+web-search-provider\s*$'
        ) -DryRun:$DryRun
}

function Test-DshCopilotSettings {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Model
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'DSH settings.yaml was not found.' }
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([regex]::Matches($text, [regex]::Escape($script:SettingsBegin)).Count -ne 1 -or
        [regex]::Matches($text, [regex]::Escape($script:SettingsEnd)).Count -ne 1) {
        throw 'DSH settings contain missing or duplicate managed markers.'
    }
    $start = $text.IndexOf($script:SettingsBegin, [StringComparison]::Ordinal)
    $finish = $text.IndexOf($script:SettingsEnd, [StringComparison]::Ordinal)
    if ($finish -lt $start) { throw 'DSH settings managed markers are reversed.' }
    $managed = $text.Substring($start, $finish + $script:SettingsEnd.Length - $start)
    $outside = $text.Substring(0, $start) + $text.Substring($finish + $script:SettingsEnd.Length)
    if ($outside -match '(?m)^llm-pi-ai\s*:' -or $outside -match '(?m)^agent-default-model\s*:') {
        throw 'DSH settings contain unmanaged conflicting provider configuration.'
    }
    foreach ($marker in @(
        $script:SettingsBegin,
        'copilot-responses:',
        'apiKeyEnv: COPILOT_API_KEY',
        'api: openai-responses',
        "baseURL: $(ConvertTo-DshSingleQuotedYaml $BaseUrl)",
        "id: $(ConvertTo-DshSingleQuotedYaml $Model)",
        'input: [text, image]',
        'provider: copilot-responses',
        "model: $(ConvertTo-DshSingleQuotedYaml $Model)",
        $script:SettingsEnd
    )) {
        if (-not $managed.Contains($marker)) { throw 'DSH settings do not match the managed Copilot route.' }
    }
    return [pscustomobject]@{ healthy = $true; path = $Path; provider = 'copilot-responses'; model = $Model }
}

function New-DshCopilotBackup {
    param(
        [Parameter(Mandatory)][string[]]$Paths,
        [Parameter(Mandatory)][string]$StateRoot,
        [switch]$DryRun
    )
    $operationId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')
    if ($DryRun) { return [pscustomobject]@{ operationId = $operationId; dryRun = $true; files = @() } }
    $root = Join-Path ([IO.Path]::GetFullPath($StateRoot)) (Join-Path 'copilot-backups' $operationId)
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $files = [Collections.Generic.List[object]]::new()
    $index = 0
    foreach ($path in $Paths | Select-Object -Unique) {
        $full = [IO.Path]::GetFullPath($path)
        $exists = Test-Path -LiteralPath $full -PathType Leaf
        $backup = Join-Path $root ("{0:D3}.bak" -f $index)
        if ($exists) { Copy-Item -LiteralPath $full -Destination $backup -Force }
        $files.Add([pscustomobject]@{
            path = $full
            existed = $exists
            backup = if ($exists) { $backup } else { $null }
            originalSha256 = if ($exists) { (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash } else { $null }
            committedExists = $null
            committedSha256 = $null
        })
        $index++
    }
    $metadata = [pscustomobject]@{
        operationId = $operationId
        createdUtc = (Get-Date).ToUniversalTime().ToString('o')
        state = 'in-progress'
        files = @($files)
    }
    $metadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $root 'metadata.json') -Encoding UTF8
    return $metadata
}

function Complete-DshCopilotBackup {
    param(
        [Parameter(Mandatory)][string]$StateRoot,
        [Parameter(Mandatory)][string]$OperationId,
        [Parameter(Mandatory)][object[]]$ExpectedStates
    )
    if ($OperationId -notmatch '^\d{8}T\d{9}Z$') { throw 'Invalid backup operation id.' }
    $root = Join-Path ([IO.Path]::GetFullPath($StateRoot)) (Join-Path 'copilot-backups' $OperationId)
    $metadataPath = Join-Path $root 'metadata.json'
    $metadata = Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($file in @($metadata.files)) {
        $expected = @($ExpectedStates | Where-Object {
            ([string]$_.path).Equals([string]$file.path, [StringComparison]::OrdinalIgnoreCase)
        } | Select-Object -First 1)
        if ($expected.Count -eq 0) { throw "Missing expected committed state for '$($file.path)'." }
        $exists = Test-Path -LiteralPath ([string]$file.path) -PathType Leaf
        if ($exists -ne [bool]$expected[0].exists) { throw "Tracked file state changed during verification for '$($file.path)'." }
        $hash = if ($exists) { (Get-FileHash -LiteralPath ([string]$file.path) -Algorithm SHA256).Hash } else { $null }
        if ($exists -and $hash -ne [string]$expected[0].sha256) {
            throw "Tracked file changed during verification for '$($file.path)'."
        }
        $file.committedExists = $exists
        $file.committedSha256 = $hash
    }
    $metadata.state = 'completed'
    $metadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $metadataPath -Encoding UTF8
    return $metadata
}

function Restore-DshCopilotBackup {
    param(
        [Parameter(Mandatory)][string]$StateRoot,
        [string]$OperationId,
        [switch]$DryRun,
        [switch]$ForceIncomplete
    )
    $backups = Join-Path ([IO.Path]::GetFullPath($StateRoot)) 'copilot-backups'
    if (-not $OperationId) {
        $OperationId = Get-ChildItem -LiteralPath $backups -Directory -ErrorAction Stop |
            Where-Object Name -match '^\d{8}T\d{9}Z$' |
            Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty Name
    }
    if ($OperationId -notmatch '^\d{8}T\d{9}Z$') { throw 'Invalid backup operation id.' }
    $root = [IO.Path]::GetFullPath((Join-Path $backups $OperationId))
    $prefix = [IO.Path]::GetFullPath($backups).TrimEnd('\') + '\'
    if (-not $root.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Backup operation escapes the state root.' }
    $metadata = Get-Content -LiteralPath (Join-Path $root 'metadata.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$metadata.state -ne 'completed' -and -not $ForceIncomplete) {
        throw 'Backup operation is incomplete; refusing public rollback.'
    }
    foreach ($file in @($metadata.files)) {
        if ($file.existed) {
            if (-not (Test-Path -LiteralPath ([string]$file.backup) -PathType Leaf)) {
                throw "Backup file is missing for '$($file.path)'."
            }
            if ((Get-FileHash -LiteralPath ([string]$file.backup) -Algorithm SHA256).Hash -ne [string]$file.originalSha256) {
                throw "Backup hash mismatch for '$($file.path)'."
            }
        }
        if (-not $ForceIncomplete) {
            $currentExists = Test-Path -LiteralPath ([string]$file.path) -PathType Leaf
            if ([bool]$file.committedExists -ne $currentExists) {
                throw "Current file state changed after bootstrap for '$($file.path)'."
            }
            if ($currentExists -and
                (Get-FileHash -LiteralPath ([string]$file.path) -Algorithm SHA256).Hash -ne [string]$file.committedSha256) {
                throw "Current file changed after bootstrap for '$($file.path)'."
            }
        }
    }
    $results = foreach ($file in @($metadata.files)) {
        if (-not $DryRun) {
            if ($file.existed) {
                Copy-Item -LiteralPath ([string]$file.backup) -Destination ([string]$file.path) -Force
            } elseif (Test-Path -LiteralPath ([string]$file.path) -PathType Leaf) {
                Remove-Item -LiteralPath ([string]$file.path) -Force
            }
        }
        [pscustomobject]@{ path = [string]$file.path; status = if ($DryRun) { 'would-restore' } else { 'restored' } }
    }
    return [pscustomobject]@{ operationId = $OperationId; dryRun = [bool]$DryRun; results = @($results) }
}

function Test-DshCopilotProfile {
    param(
        [Parameter(Mandatory)][string]$DshHome,
        [Parameter(Mandatory)][string]$Profile
    )
    $profileRoot = Join-Path $DshHome (Join-Path 'profiles' $Profile)
    $manifestPath = Join-Path $profileRoot 'package.json'
    $patchPath = Join-Path $profileRoot 'cordis.patch.yml'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Profile '$Profile' is not initialized." }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $dependency = $manifest.dependencies.PSObject.Properties['dsh-web-search-provider']
    if (-not $dependency) { throw "Profile '$Profile' does not install dsh-web-search-provider." }
    if (@($manifest.dsh.profile.bundles) -notcontains 'dsh-web-search-provider') {
        throw "Profile '$Profile' does not activate the dsh-web-search-provider bundle."
    }
    $pluginManifest = Join-Path $profileRoot 'node_modules\dsh-web-search-provider\package.json'
    if (-not (Test-Path -LiteralPath $pluginManifest -PathType Leaf)) {
        throw "Profile '$Profile' cannot resolve dsh-web-search-provider."
    }
    $pluginPatchPath = Join-Path $profileRoot 'node_modules\dsh-web-search-provider\cordis.patch.yml'
    if (-not (Test-Path -LiteralPath $pluginPatchPath -PathType Leaf)) {
        throw "Profile '$Profile' plugin bundle patch is missing."
    }
    $pluginPatch = Get-Content -LiteralPath $pluginPatchPath -Raw -Encoding UTF8
    if (-not $pluginPatch.Contains('id: web-search-provider') -or
        -not $pluginPatch.Contains('name: dsh-web-search-provider')) {
        throw "Profile '$Profile' plugin bundle does not insert web-search-provider."
    }
    $patch = Get-Content -LiteralPath $patchPath -Raw -Encoding UTF8
    if ([regex]::Matches($patch, [regex]::Escape($script:ProfileBegin)).Count -ne 1 -or
        [regex]::Matches($patch, [regex]::Escape($script:ProfileEnd)).Count -ne 1) {
        throw "Profile '$Profile' contains missing or duplicate managed markers."
    }
    $start = $patch.IndexOf($script:ProfileBegin, [StringComparison]::Ordinal)
    $finish = $patch.IndexOf($script:ProfileEnd, [StringComparison]::Ordinal)
    if ($finish -lt $start) { throw "Profile '$Profile' managed markers are reversed." }
    $managed = $patch.Substring($start, $finish + $script:ProfileEnd.Length - $start)
    $outside = $patch.Substring(0, $start) + $patch.Substring($finish + $script:ProfileEnd.Length)
    foreach ($pattern in @(
        '(?m)^\s*-\s+id:\s+web\s*$',
        '(?m)^\s*-\s+id:\s+web-search-deepseek\s*$',
        '(?m)^\s*-\s+id:\s+tool-web\s*$',
        '(?m)^\s*-\s+id:\s+web-search-provider\s*$'
    )) {
        if ($outside -match $pattern) { throw "Profile '$Profile' contains unmanaged conflicting search configuration." }
    }
    foreach ($marker in @(
        $script:ProfileBegin,
        '- id: web',
        '- id: web-search-deepseek',
        '- id: tool-web',
        'disabled: true',
        '- id: web-search-provider',
        'enabled: true',
        'providers: [copilot-responses]',
        'apiKeyEnv: COPILOT_API_KEY',
        $script:ProfileEnd
    )) {
        if (-not $managed.Contains($marker)) { throw "Profile '$Profile' is missing managed search configuration." }
    }
    return [pscustomobject]@{ profile = $Profile; healthy = $true; pluginVersion = [string](Get-Content $pluginManifest -Raw | ConvertFrom-Json).version }
}

function Invoke-DshVisionProbe {
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Model,
        [ValidateSet('Contract', 'Live')][string]$Mode = 'Contract',
        [int]$TimeoutSeconds = 30
    )
    if ($Mode -eq 'Contract') {
        return [pscustomobject]@{ mode = 'contract'; healthy = $true; evidence = 'explicit catalog metadata plus openai-responses input contract' }
    }

    $key = [Environment]::GetEnvironmentVariable('COPILOT_API_KEY')
    if (-not $key) { throw 'Live vision probe requires COPILOT_API_KEY in the process environment.' }
    $png = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2n0kAAAAASUVORK5CYII='
    $body = @{
        model = $Model
        input = @(@{ role = 'user'; content = @(
            @{ type = 'input_text'; text = 'Reply with the single word pixel.' },
            @{ type = 'input_image'; image_url = $png }
        ) })
        max_output_tokens = 8
    } | ConvertTo-Json -Depth 8 -Compress
    $headers = @{ Authorization = "Bearer $key" }
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri ($BaseUrl.TrimEnd('/') + '/responses') `
            -Method Post -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec $TimeoutSeconds
    } catch {
        throw 'The deterministic image-capable request failed.'
    }
    if ([int]$response.StatusCode -lt 200 -or [int]$response.StatusCode -ge 300) {
        throw 'The deterministic image-capable request returned a non-success status.'
    }
    return [pscustomobject]@{ mode = 'live'; healthy = $true; statusCode = [int]$response.StatusCode }
}

function Test-DshSandboxRegression {
    param(
        [Parameter(Mandatory)][string]$PackageRoot,
        [Parameter(Mandatory)][string]$ProbeScript,
        [ValidateSet('Report', 'Require', 'Skip')][string]$Mode = 'Report'
    )
    if ($Mode -eq 'Skip') {
        return [pscustomobject]@{ status = 'skipped'; required = $false }
    }
    $node = Get-Command node -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $node) { throw 'Node.js is required for the sandbox regression probe.' }
    $output = @(& $node.Source $ProbeScript $PackageRoot 2>$null)
    $exitCode = $LASTEXITCODE
    $last = $output | Select-Object -Last 1
    try {
        $result = $last | ConvertFrom-Json
    } catch {
        throw 'Sandbox regression probe returned invalid output.'
    }
    if ($exitCode -eq 0 -and [string]$result.status -eq 'passed') {
        return [pscustomobject]@{
            status = 'passed'
            required = [bool]($Mode -eq 'Require')
            sameMode = [string]$result.sameMode
            narrowerMode = [string]$result.narrowerMode
            widerMode = [string]$result.widerMode
            effectiveMode = [string]$result.effectiveMode
        }
    }
    if ($Mode -eq 'Require') {
        throw "Installed Core fails the sandbox non-widening regression gate: $([string]$result.reason)"
    }
    return [pscustomobject]@{
        status = 'expected-fail'
        required = $false
        reason = [string]$result.reason
        owner = 'cloga/deepseek-harness'
    }
}

Export-ModuleMember -Function @(
    'Get-DshExplicitVisionCapability',
    'Get-DshCatalogModel',
    'Get-DshCopilotCatalog',
    'Resolve-DshCliInfo',
    'Test-DshActiveDesktopCore',
    'Test-DshRendererCompatibility',
    'Test-DshCredentialReference',
    'Set-DshManagedTextBlock',
    'Set-DshCopilotSettings',
    'Set-DshCopilotProfilePatch',
    'Test-DshCopilotSettings',
    'New-DshCopilotBackup',
    'Complete-DshCopilotBackup',
    'Restore-DshCopilotBackup',
    'Test-DshCopilotProfile',
    'Invoke-DshVisionProbe',
    'Test-DshSandboxRegression'
)
