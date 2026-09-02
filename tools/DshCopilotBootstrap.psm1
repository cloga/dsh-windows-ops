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

function Get-DshYamlBlockRange {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory)][int]$Start,
        [Parameter(Mandatory)][int]$Indent
    )
    $end = $Lines.Count
    for ($i = $Start + 1; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\s*(?:#.*)?$') { continue }
        if ($Lines[$i] -notmatch '^(\s*)') { continue }
        if ($matches[1].Length -le $Indent) { $end = $i; break }
    }
    return [pscustomobject]@{ start = $Start; end = $end }
}

function Test-DshCopilotCredentialRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DshHome,
        [string]$RecordKey = 'llm-pi-ai/github-copilot'
    )
    $path = Join-Path $DshHome '.credentials.yaml'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject]@{
            record = $RecordKey
            configured = $false
            kind = $null
            status = 'sign-in-required'
            path = $path
        }
    }
    $lines = @(Get-Content -LiteralPath $path -Encoding UTF8)
    if (@($lines | Where-Object { $_ -match '^version\s*:\s*1\s*$' }).Count -ne 1) {
        throw 'The credential store is not a version 1 document.'
    }
    $recordsStart = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^records\s*:\s*$') { $recordsStart = $i; break }
    }
    if ($recordsStart -lt 0) {
        return [pscustomobject]@{
            record = $RecordKey
            configured = $false
            kind = $null
            status = 'sign-in-required'
            path = $path
        }
    }
    $recordsRange = Get-DshYamlBlockRange -Lines $lines -Start $recordsStart -Indent 0
    $recordStart = -1
    $escaped = [regex]::Escape($RecordKey)
    for ($i = $recordsStart + 1; $i -lt $recordsRange.end; $i++) {
        if ($lines[$i] -match ("^\s{2}['""]?" + $escaped + "['""]?\s*:\s*$")) {
            $recordStart = $i
            break
        }
    }
    if ($recordStart -lt 0) {
        return [pscustomobject]@{
            record = $RecordKey
            configured = $false
            kind = $null
            status = 'sign-in-required'
            path = $path
        }
    }
    $recordRange = Get-DshYamlBlockRange -Lines $lines -Start $recordStart -Indent 2
    $kind = $null
    for ($i = $recordStart + 1; $i -lt $recordRange.end; $i++) {
        if ($lines[$i] -match '^\s{4}kind\s*:\s*[''"]?([^''"#\s]+)[''"]?\s*$') {
            $kind = [string]$matches[1]
            break
        }
    }
    if ($kind -and $kind -ne 'grant') {
        throw "Credential record '$RecordKey' has unsupported kind '$kind'."
    }
    return [pscustomobject]@{
        record = $RecordKey
        configured = [bool]($kind -eq 'grant')
        kind = $kind
        status = if ($kind -eq 'grant') { 'signed-in' } else { 'sign-in-required' }
        path = $path
    }
}

function Get-DshCopilotRouteState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SettingsPath)
    $missingRoute = {
        param([string]$Status = 'route-missing')
        [pscustomobject]@{
            exists = $false
            referenceFree = $false
            modelsComplete = $false
            mixedProtocolApis = $false
            availableModels = @()
            modelRoutes = @()
            apis = @()
            status = $Status
            path = $SettingsPath
        }
    }
    if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) {
        return & $missingRoute
    }
    $lines = @(Get-Content -LiteralPath $SettingsPath -Encoding UTF8)
    $llmStart = [array]::IndexOf($lines, 'llm-pi-ai:')
    if ($llmStart -lt 0) {
        return & $missingRoute
    }
    $llmRange = Get-DshYamlBlockRange -Lines $lines -Start $llmStart -Indent 0
    $providersStart = -1
    for ($i = $llmStart + 1; $i -lt $llmRange.end; $i++) {
        if ($lines[$i] -match '^\s{2}providers\s*:\s*$') { $providersStart = $i; break }
    }
    if ($providersStart -lt 0) {
        return & $missingRoute
    }
    $providersRange = Get-DshYamlBlockRange -Lines $lines -Start $providersStart -Indent 2
    $routeStart = -1
    for ($i = $providersStart + 1; $i -lt $providersRange.end; $i++) {
        if ($lines[$i] -match '^\s{4}[''"]?github-copilot[''"]?\s*:\s*(?:\{\s*\})?\s*$') {
            $routeStart = $i
            break
        }
    }
    if ($routeStart -lt 0) {
        return & $missingRoute
    }
    $routeRange = Get-DshYamlBlockRange -Lines $lines -Start $routeStart -Indent 4
    $routeLines = @($lines[$routeStart..($routeRange.end - 1)])
    $forbiddenKeys = @('baseURL', 'apiKeyEnv')
    $foundForbidden = @($forbiddenKeys | Where-Object {
        $key = [regex]::Escape($_)
        @($routeLines | Where-Object { $_ -match ("^\s{6}" + $key + '\s*:') }).Count -gt 0
    })
    $modelRoutes = [Collections.Generic.List[object]]::new()
    $modelsStart = -1
    for ($i = $routeStart + 1; $i -lt $routeRange.end; $i++) {
        if ($lines[$i] -match '^\s{6}models\s*:\s*$') { $modelsStart = $i; break }
    }
    if ($modelsStart -ge 0) {
        $modelsRange = Get-DshYamlBlockRange -Lines $lines -Start $modelsStart -Indent 6
        $current = $null
        for ($i = $modelsStart + 1; $i -lt $modelsRange.end; $i++) {
            if ($lines[$i] -match '^\s{8}-\s+(id|api)\s*:\s*[''"]?([^''"#]+?)[''"]?\s*$') {
                if ($current) { $modelRoutes.Add([pscustomobject]$current) }
                $current = [ordered]@{ id = $null; api = $null }
                $current[$matches[1]] = $matches[2].Trim()
            } elseif ($current -and $lines[$i] -match '^\s{10}(id|api)\s*:\s*[''"]?([^''"#]+?)[''"]?\s*$') {
                $current[$matches[1]] = $matches[2].Trim()
            }
        }
        if ($current) { $modelRoutes.Add([pscustomobject]$current) }
    }
    $models = @($modelRoutes | ForEach-Object { $_.id } | Select-Object -Unique)
    $apis = @($modelRoutes | ForEach-Object { $_.api } | Where-Object { $_ } | Select-Object -Unique)
    $modelsComplete = [bool]($modelRoutes.Count -gt 0 -and
        @($modelRoutes | Where-Object { -not $_.id -or -not $_.api }).Count -eq 0)
    $mixedProtocolApis = [bool](
        $apis -contains 'openai-responses' -and
        $apis -contains 'openai-completions'
    )
    $status = if ($foundForbidden.Count -gt 0) {
        'legacy-reference-route'
    } elseif ($modelRoutes.Count -eq 0) {
        'route-has-no-models'
    } elseif (-not $modelsComplete) {
        'route-model-api-missing'
    } elseif (-not $mixedProtocolApis) {
        'route-mixed-protocol-apis-missing'
    } else {
        'available'
    }
    return [pscustomobject]@{
        exists = $true
        referenceFree = [bool]($foundForbidden.Count -eq 0)
        modelsComplete = $modelsComplete
        mixedProtocolApis = $mixedProtocolApis
        forbiddenKeys = @($foundForbidden)
        availableModels = $models
        modelRoutes = @($modelRoutes)
        apis = $apis
        status = $status
        path = $SettingsPath
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
    $bin = Get-DshRequiredProperty -Object $manifest -Name 'bin' -Context 'Installed @deepseek-ai/dsh manifest'
    $entryRelative = if ($bin -is [string]) {
        [string]$bin
    } else {
        [string](Get-DshRequiredProperty -Object $bin -Name 'dsh' -Context 'Installed @deepseek-ai/dsh bin')
    }
    $entryPath = [IO.Path]::GetFullPath((Join-Path $packageRoot $entryRelative))
    $packagePrefix = $packageRoot.TrimEnd('\') + '\'
    if (-not $entryPath.StartsWith($packagePrefix, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $entryPath -PathType Leaf)) {
        throw 'The installed @deepseek-ai/dsh entry point is missing or outside the package root.'
    }

    $installedFilesProperty = $receipt.PSObject.Properties['installedFiles']
    if (-not $installedFilesProperty -or $null -eq $installedFilesProperty.Value) {
        throw 'Core receipt installed-bytes-unattested: installedFiles is missing.'
    }
    $expectedInstalledFiles = @(
        [pscustomobject]@{ role = 'root-shim'; path = 'dsh.cmd'; fullPath = $desktopCli },
        [pscustomobject]@{
            role = 'npm-shim'
            path = 'node_modules\.bin\dsh.cmd'
            fullPath = $canonicalCli
        },
        [pscustomobject]@{
            role = 'entrypoint'
            path = 'node_modules\@deepseek-ai\dsh\lib\bin.js'
            fullPath = $entryPath
        }
    )
    $installedFiles = @($installedFilesProperty.Value)
    if ($installedFiles.Count -ne $expectedInstalledFiles.Count) {
        throw 'Core receipt installed-bytes-unattested: installedFiles must contain exactly three entries.'
    }
    $seenInstalledRoles = @{}
    foreach ($item in $installedFiles) {
        $roleProperty = $item.PSObject.Properties['role']
        $pathProperty = $item.PSObject.Properties['path']
        $shaProperty = $item.PSObject.Properties['sha256']
        if (-not $roleProperty -or -not $pathProperty -or -not $shaProperty) {
            throw 'Core receipt installed-bytes-unattested: an installedFiles entry is incomplete.'
        }
        $role = [string]$roleProperty.Value
        $relativePath = ([string]$pathProperty.Value).Replace('/', '\')
        $sha256 = [string]$shaProperty.Value
        $expectedFile = @($expectedInstalledFiles | Where-Object { $_.role -ceq $role })
        if ($seenInstalledRoles.ContainsKey($role) -or $expectedFile.Count -ne 1 -or
            [IO.Path]::IsPathRooted($relativePath) -or $relativePath -ne [string]$expectedFile[0].path -or
            $sha256 -notmatch '^[0-9a-fA-F]{64}$') {
            throw "Core receipt installed-bytes-unattested: invalid installedFiles entry '$role'."
        }
        $seenInstalledRoles[$role] = $true
        $fullPath = [IO.Path]::GetFullPath((Join-Path $prefix $relativePath))
        if ($fullPath -ine [string]$expectedFile[0].fullPath -or
            -not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            throw "Core receipt installed-bytes-unattested: '$role' does not resolve to the required file."
        }
        $actualSha256 = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash
        if ($actualSha256 -ine $sha256) {
            throw "Core receipt installed-bytes-mismatch: '$role' SHA-256 does not match."
        }
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
        entryPath = $entryPath
        version = $packageVersion
        repository = $ExpectedRepository
        repositoryUrl = $repositoryUrl
        commitSha = $commitSha.ToLowerInvariant()
        receiptPath = [IO.Path]::GetFullPath($receiptPath)
        releaseManifestSha256 = $releaseManifestSha256.ToLowerInvariant()
        packageCount = $receiptPackages.Count
        installedFileCount = $installedFiles.Count
    }
}

function Test-DshActiveDesktopCore {
    param(
        [Parameter(Mandatory)]$CliInfo,
        [string]$DesktopRoot,
        [string]$DesktopExecutablePath,
        [object[]]$Processes
    )

    if ($null -eq $Processes) {
        $Processes = @(Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId, Name, ExecutablePath, CommandLine)
    }
    $desktop = @($Processes | Where-Object {
        [string]$_.Name -match '^(?:DeepSeek Harness|deepseek-harness-desktop)(?:\.exe)?$' -and
        (-not $DesktopExecutablePath -or (
            $_.ExecutablePath -and
            [IO.Path]::GetFullPath([string]$_.ExecutablePath) -ieq
                [IO.Path]::GetFullPath($DesktopExecutablePath)
        ))
    })
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

    $entryPath = ([string]$CliInfo.entryPath).Replace('/', '\')
    if (-not $entryPath) { throw 'The receipted dsh entry point is missing.' }
    $entryPattern = '(?i)(?:^|[\s"''])' + [regex]::Escape($entryPath) + '(?:$|[\s"''])'
    $active = @($Processes | Where-Object {
        $descendants.Contains([int]$_.ProcessId) -and
        [string]$_.Name -match '^node(?:\.exe)?$' -and
        $_.CommandLine -and
        ([string]$_.CommandLine).Replace('/', '\') -match $entryPattern
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

    $packageNodeModules = Split-Path -Parent (Split-Path -Parent $PackageRoot)
    $rendererCandidates = @(
        (Join-Path $PackageRoot 'node_modules\@deepseek-ai\dsh-client-ui-renderer\lib\client.js'),
        (Join-Path $packageNodeModules '@deepseek-ai\dsh-client-ui-renderer\lib\client.js')
    )
    $renderer = @($rendererCandidates | Where-Object {
        Test-Path -LiteralPath $_ -PathType Leaf
    } | Select-Object -First 1)
    if ($renderer.Count -eq 0) {
        throw "Active-core renderer was not found through nested or hoisted Node resolution."
    }
    $renderer = [string]$renderer[0]
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

function Remove-DshLegacyCopilotSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$DryRun
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ path = $Path; changed = $false; status = 'unchanged'; removedRoutes = @() }
    }
    $current = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $next = $current
    $managedBegin = $next.IndexOf($script:SettingsBegin, [StringComparison]::Ordinal)
    $managedEnd = $next.IndexOf($script:SettingsEnd, [StringComparison]::Ordinal)
    if (($managedBegin -ge 0) -xor ($managedEnd -ge 0)) {
        throw "Legacy managed settings markers are incomplete in '$Path'."
    }
    if ($managedBegin -ge 0) {
        if ([regex]::Matches($next, [regex]::Escape($script:SettingsBegin)).Count -ne 1 -or
            [regex]::Matches($next, [regex]::Escape($script:SettingsEnd)).Count -ne 1 -or
            $managedEnd -lt $managedBegin) {
            throw "Legacy managed settings markers are ambiguous in '$Path'."
        }
        $end = $managedEnd + $script:SettingsEnd.Length
        while ($end -lt $next.Length -and $next[$end] -in "`r", "`n") { $end++ }
        $next = $next.Remove($managedBegin, $end - $managedBegin)
    }

    $removedRoutes = [Collections.Generic.List[string]]::new()
    $lines = @($next -split "`r?`n")
    $llmStart = [array]::IndexOf($lines, 'llm-pi-ai:')
    if ($llmStart -ge 0) {
        $llmRange = Get-DshYamlBlockRange -Lines $lines -Start $llmStart -Indent 0
        $providersStart = -1
        for ($i = $llmStart + 1; $i -lt $llmRange.end; $i++) {
            if ($lines[$i] -match '^\s{2}providers\s*:\s*$') { $providersStart = $i; break }
        }
        if ($providersStart -ge 0) {
            foreach ($routeId in @('github-copilot-gateway', 'github-copilot-chat', 'github-copilot')) {
                $providersRange = Get-DshYamlBlockRange -Lines $lines -Start $providersStart -Indent 2
                $routeStart = -1
                for ($i = $providersStart + 1; $i -lt $providersRange.end; $i++) {
                    if ($lines[$i] -match ("^\s{4}['""]?" + [regex]::Escape($routeId) + "['""]?\s*:\s*$")) {
                        $routeStart = $i
                        break
                    }
                }
                if ($routeStart -lt 0) { continue }
                $routeRange = Get-DshYamlBlockRange -Lines $lines -Start $routeStart -Indent 4
                $routeText = $lines[$routeStart..($routeRange.end - 1)] -join "`n"
                $isLegacy = $routeId -eq 'github-copilot-gateway' -or
                    $routeText -match '(?m)^\s{6}apiKeyEnv\s*:\s*[''"]?COPILOT_GITHUB_TOKEN[''"]?\s*$' -or
                    $routeText -match 'http://127\.0\.0\.1:7777'
                if (-not $isLegacy) { continue }
                $before = if ($routeStart -gt 0) { @($lines[0..($routeStart - 1)]) } else { @() }
                $after = if ($routeRange.end -lt $lines.Count) {
                    @($lines[$routeRange.end..($lines.Count - 1)])
                } else { @() }
                $lines = @($before + $after)
                $removedRoutes.Add($routeId)
            }
            $next = ($lines -join [Environment]::NewLine).TrimEnd() + [Environment]::NewLine
        }
    }
    $changed = $next -ne $current
    if ($changed -and -not $DryRun) {
        $temporary = "$Path.dsh-ops-tmp"
        try {
            Set-Content -LiteralPath $temporary -Value $next -Encoding UTF8 -NoNewline
            Move-Item -LiteralPath $temporary -Destination $Path -Force
        } finally {
            if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
        }
    }
    return [pscustomobject]@{
        path = $Path
        changed = $changed
        status = if (-not $changed) { 'unchanged' } elseif ($DryRun) { 'would-change' } else { 'changed' }
        removedRoutes = @($removedRoutes)
    }
}

function Remove-DshLegacyCopilotCredentialReference {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Reference = 'COPILOT_GITHUB_TOKEN',
        [switch]$DryRun
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ path = $Path; changed = $false; status = 'unchanged' }
    }
    $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8)
    $matchIndexes = @()
    $inRefs = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^refs\s*:\s*$') { $inRefs = $true; continue }
        if ($inRefs -and $lines[$i] -match '^\S') { $inRefs = $false }
        if ($inRefs -and $lines[$i] -match ("^\s{2}['""]?" + [regex]::Escape($Reference) + "['""]?\s*:")) {
            $matchIndexes += $i
        }
    }
    if ($matchIndexes.Count -gt 1) { throw "Credential reference '$Reference' is duplicated." }
    if ($matchIndexes.Count -eq 0) {
        return [pscustomobject]@{ path = $Path; changed = $false; status = 'unchanged' }
    }
    $next = for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($i -ne $matchIndexes[0]) { $lines[$i] }
    }
    if (-not $DryRun) {
        Set-Content -LiteralPath $Path -Value $next -Encoding UTF8
    }
    return [pscustomobject]@{
        path = $Path
        changed = $true
        status = if ($DryRun) { 'would-change' } else { 'changed' }
    }
}

function Set-DshCopilotModelSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Model,
        [switch]$DryRun
    )
    $route = Get-DshCopilotRouteState -SettingsPath $Path
    if ($route.status -ne 'available') {
        throw "A complete reference-free mixed-protocol llm-pi-ai.providers.github-copilot route is required before selecting a model."
    }
    if (@($route.availableModels) -notcontains $Model) {
        throw "Model '$Model' is not in the signed-in account's available GitHub Copilot route."
    }
    $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8)
    $starts = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^agent-default-model\s*:\s*$') { $starts += $i }
    }
    if ($starts.Count -gt 1) { throw "Multiple agent-default-model mappings are not supported in '$Path'." }
    $selection = @(
        'agent-default-model:',
        '  provider: github-copilot',
        "  model: $(ConvertTo-DshSingleQuotedYaml $Model)"
    )
    if ($starts.Count -eq 1) {
        $range = Get-DshYamlBlockRange -Lines $lines -Start $starts[0] -Indent 0
        $before = if ($starts[0] -gt 0) { @($lines[0..($starts[0] - 1)]) } else { @() }
        $after = if ($range.end -lt $lines.Count) { @($lines[$range.end..($lines.Count - 1)]) } else { @() }
        $nextLines = @($before + $selection + $after)
    } else {
        $nextLines = @($lines)
        if ($nextLines.Count -gt 0 -and $nextLines[-1] -ne '') { $nextLines += '' }
        $nextLines += $selection
    }
    $current = (Get-Content -LiteralPath $Path -Raw -Encoding UTF8).TrimEnd()
    $next = ($nextLines -join [Environment]::NewLine).TrimEnd()
    $changed = $current -ne $next
    if ($changed -and -not $DryRun) {
        Set-Content -LiteralPath $Path -Value ($next + [Environment]::NewLine) -Encoding UTF8 -NoNewline
    }
    return [pscustomobject]@{
        path = $Path
        model = $Model
        changed = $changed
        status = if (-not $changed) { 'unchanged' } elseif ($DryRun) { 'would-change' } else { 'changed' }
    }
}

function Set-DshCopilotProfilePatch {
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$DryRun
    )
    $block = @"
$script:ProfileBegin
- id: web
  config:
    searchProvider: github-copilot-hosted
- id: github-copilot
  config:
    enabled: true
    providers: [github-copilot]
    probe: true
$script:ProfileEnd
"@
    return Set-DshManagedTextBlock -Path $Path -Begin $script:ProfileBegin -End $script:ProfileEnd `
        -Block $block -ConflictPatterns @(
            '(?m)^\s*-\s+id:\s+web\s*$',
            '(?m)^\s*-\s+id:\s+github-copilot\s*$',
            '(?m)^\s*-\s+id:\s+web-search-provider\s*$'
        ) -DryRun:$DryRun
}

function Test-DshCopilotSettings {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Model
    )
    $route = Get-DshCopilotRouteState -SettingsPath $Path
    if (-not $route.exists) { throw 'DSH GitHub Copilot route is absent; sign in through the Desktop UI.' }
    if (-not $route.referenceFree) { throw 'DSH GitHub Copilot route contains a legacy endpoint or credential reference.' }
    if (-not $route.modelsComplete) { throw 'DSH GitHub Copilot route has no complete per-model {id, api} entries.' }
    if (-not $route.mixedProtocolApis) { throw 'DSH GitHub Copilot route does not retain the required mixed protocol APIs.' }
    if ($Model -and @($route.availableModels) -notcontains $Model) {
        throw "Selected model '$Model' is not account-available."
    }
    return [pscustomobject]@{
        healthy = $true
        path = $Path
        provider = 'github-copilot'
        model = $Model
        availableModels = @($route.availableModels)
        referenceFree = $true
    }
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
    $dependency = $manifest.dependencies.PSObject.Properties['dsh-github-copilot']
    if (-not $dependency) { throw "Profile '$Profile' does not install dsh-github-copilot." }
    if (@($manifest.dsh.profile.bundles) -notcontains 'dsh-github-copilot') {
        throw "Profile '$Profile' does not activate the dsh-github-copilot bundle."
    }
    $pluginManifest = Join-Path $profileRoot 'node_modules\dsh-github-copilot\package.json'
    if (-not (Test-Path -LiteralPath $pluginManifest -PathType Leaf)) {
        throw "Profile '$Profile' cannot resolve dsh-github-copilot."
    }
    $pluginPatchPath = Join-Path $profileRoot 'node_modules\dsh-github-copilot\cordis.patch.yml'
    if (-not (Test-Path -LiteralPath $pluginPatchPath -PathType Leaf)) {
        throw "Profile '$Profile' plugin bundle patch is missing."
    }
    $pluginPatch = Get-Content -LiteralPath $pluginPatchPath -Raw -Encoding UTF8
    if (-not $pluginPatch.Contains('id: github-copilot') -or
        -not $pluginPatch.Contains('name: dsh-github-copilot')) {
        throw "Profile '$Profile' plugin bundle does not insert github-copilot."
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
        '(?m)^\s*-\s+id:\s+github-copilot\s*$',
        '(?m)^\s*-\s+id:\s+web-search-provider\s*$'
    )) {
        if ($outside -match $pattern) { throw "Profile '$Profile' contains unmanaged conflicting search configuration." }
    }
    foreach ($marker in @(
        $script:ProfileBegin,
        '- id: web',
        'searchProvider: github-copilot-hosted',
        '- id: github-copilot',
        'enabled: true',
        'providers: [github-copilot]',
        $script:ProfileEnd
    )) {
        if (-not $managed.Contains($marker)) { throw "Profile '$Profile' is missing managed search configuration." }
    }
    return [pscustomobject]@{ profile = $Profile; healthy = $true; pluginVersion = [string](Get-Content $pluginManifest -Raw | ConvertFrom-Json).version }
}

function Invoke-DshVisionProbe {
    param(
        [Parameter(Mandatory)][string]$SettingsPath,
        [Parameter(Mandatory)][string]$Model
    )
    $route = Test-DshCopilotSettings -Path $SettingsPath -Model $Model
    return [pscustomobject]@{
        mode = 'account-route-contract'
        healthy = [bool]$route.healthy
        evidence = 'model is present in the account-available built-in pi-ai route'
    }
}

function Test-DshSandboxRegression {
    param(
        [Parameter(Mandatory)][string]$PackageRoot,
        [Parameter(Mandatory)][string]$ProbeScript,
        [ValidateSet('Report', 'Require', 'Skip')][string]$Mode = 'Require'
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
            capability = [string]$result.capability
            sameMode = [string]$result.sameMode
            narrowerMode = [string]$result.narrowerMode
            widerMode = [string]$result.widerMode
            effectiveMode = [string]$result.effectiveMode
            sameAndNarrowerApprovalCalls = [int]$result.sameAndNarrowerApprovalCalls
            widerApprovalCalls = [int]$result.widerApprovalCalls
            tools = @($result.tools)
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
    'ConvertTo-DshRepositorySlug',
    'Resolve-DshCliInfo',
    'Test-DshActiveDesktopCore',
    'Test-DshRendererCompatibility',
    'Test-DshCopilotCredentialRecord',
    'Get-DshCopilotRouteState',
    'Set-DshManagedTextBlock',
    'Remove-DshLegacyCopilotSettings',
    'Remove-DshLegacyCopilotCredentialReference',
    'Set-DshCopilotModelSelection',
    'Set-DshCopilotProfilePatch',
    'Test-DshCopilotSettings',
    'New-DshCopilotBackup',
    'Complete-DshCopilotBackup',
    'Restore-DshCopilotBackup',
    'Test-DshCopilotProfile',
    'Invoke-DshVisionProbe',
    'Test-DshSandboxRegression'
)
