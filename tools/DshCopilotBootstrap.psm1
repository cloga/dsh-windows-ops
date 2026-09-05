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
        if ($lines[$i] -match '^\s{4}[''"]?github-copilot[''"]?\s*:\s*(?:\{\s*\}|\{\s*)?$') {
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
    $routeText = $routeLines -join "`n"
    $foundForbidden = @($forbiddenKeys | Where-Object {
        $key = [regex]::Escape($_)
        $routeText -match ('(?m)(?:^\s*|[{,]\s*)[''"]?' + $key + '[''"]?\s*:')
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
    $flowModels = [regex]::Match(
        $routeText,
        '(?s)(?:^|[\s,{])[''"]?models[''"]?\s*:\s*\[(?<models>.*?)\]'
    )
    if ($flowModels.Success) {
        foreach ($modelMatch in [regex]::Matches($flowModels.Groups['models'].Value, '\{(?<model>[^{}]*)\}')) {
            $model = [ordered]@{ id = $null; api = $null }
            $fieldCounts = @{ id = 0; api = 0 }
            foreach ($fieldMatch in [regex]::Matches(
                $modelMatch.Groups['model'].Value,
                '(?:^|,)\s*[''"]?(?<key>id|api)[''"]?\s*:\s*(?<value>[^,}]+)'
            )) {
                $key = [string]$fieldMatch.Groups['key'].Value
                $value = [string]$fieldMatch.Groups['value'].Value.Trim()
                if (($value.StartsWith("'") -and $value.EndsWith("'")) -or
                    ($value.StartsWith('"') -and $value.EndsWith('"'))) {
                    $value = $value.Substring(1, $value.Length - 2)
                }
                $fieldCounts[$key]++
                $model[$key] = $value.Trim()
            }
            if ($fieldCounts.id -ne 1 -or $fieldCounts.api -ne 1) {
                $model.id = $null
                $model.api = $null
            }
            $modelRoutes.Add([pscustomobject]$model)
        }
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

function Test-DshActiveDesktopCore {
    param(
        [Parameter(Mandatory)]$DeploymentLock,
        [Parameter(Mandatory)]$DesktopRuntimeState
    )
    $selectors = @($DeploymentLock.components.desktop.runtimeSelectors)
    if ($selectors.Count -ne 1 -or
        [string]$DeploymentLock.components.desktop.defaultRuntimeSelector -cne 'desktop-official') {
        throw 'The deployment lock does not define only the official Desktop-managed runtime.'
    }
    $official = $selectors[0]
    if ([string]$official.id -cne 'desktop-official' -or
        [string]$official.source -cne 'desktop-managed-download') {
        throw 'The deployment lock does not define the official Desktop-managed runtime.'
    }
    if (-not [bool]$DesktopRuntimeState.valid) {
        throw "Desktop runtime selector is not accepted: '$($DesktopRuntimeState.status)'."
    }

    $selector = [string]$DesktopRuntimeState.selector
    if ($selector -cne 'desktop-official') {
        throw "Unsupported Desktop runtime selector '$selector'."
    }
    $officialRoot = [IO.Path]::GetFullPath(
        [Environment]::ExpandEnvironmentVariables([string]$official.root)
    )
    $expectedPackageRoot = [IO.Path]::GetFullPath(
        (Join-Path $officialRoot 'node_modules\@deepseek-ai\dsh')
    )
    $expectedEntry = [IO.Path]::GetFullPath(
        (Join-Path $officialRoot ([string]$official.package.entrypoint))
    )
    if ([string]$DesktopRuntimeState.source -cne [string]$official.source -or
        [string]$DesktopRuntimeState.version -cne [string]$official.package.version -or
        [IO.Path]::GetFullPath([string]$DesktopRuntimeState.packageRoot) -ine $expectedPackageRoot -or
        [IO.Path]::GetFullPath([string]$DesktopRuntimeState.entryPath) -ine $expectedEntry) {
        throw 'Desktop official runtime does not match the exact managed path and locked version.'
    }

    return [pscustomobject]@{
        healthy = $true
        selector = $selector
        source = [string]$DesktopRuntimeState.source
        version = [string]$DesktopRuntimeState.version
        packageRoot = [string]$DesktopRuntimeState.packageRoot
        entryPath = [string]$DesktopRuntimeState.entryPath
        processIds = @($DesktopRuntimeState.processIds)
    }
}

function Test-DshRendererCompatibility {
    param(
        [Parameter(Mandatory)][string]$PackageRoot,
        [Parameter(Mandatory)][string]$DshHome,
        [bool]$RequireFlatFallback = $true
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
    if (-not $RequireFlatFallback) {
        return [pscustomobject]@{ healthy = $true; renderer = $renderer; flatRenderer = $null }
    }
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

function Get-DshCopilotPathFingerprint {
    param([Parameter(Mandatory)][string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) { return [pscustomobject]@{ kind = 'absent' } }
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Tracked bootstrap path contains a reparse point: '$Path'."
    }
    if (-not $item.PSIsContainer) {
        return [pscustomobject]@{
            kind = 'file'
            size = [int64]$item.Length
            sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
        }
    }
    $root = $item.FullName.TrimEnd('\') + '\'
    $items = @(Get-ChildItem -LiteralPath $item.FullName -Recurse -Force)
    if (@($items | Where-Object {
        $_.Attributes -band [IO.FileAttributes]::ReparsePoint
    }).Count -gt 0) {
        throw "Tracked bootstrap directory contains a reparse point: '$Path'."
    }
    $entries = @($items | Where-Object { -not $_.PSIsContainer } | ForEach-Object {
        [pscustomobject]@{
            relativePath = $_.FullName.Substring($root.Length).Replace('\', '/')
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
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
        )).Replace('-', '')
    } finally {
        $sha.Dispose()
    }
    return [pscustomobject]@{
        kind = 'directory'
        fileCount = $entries.Count
        totalBytes = [int64](($entries | Measure-Object size -Sum).Sum)
        treeSha256 = $treeSha256
    }
}

function Test-DshCopilotFingerprintEqual {
    param($Left, $Right)
    return (ConvertTo-Json $Left -Compress -Depth 5) -ceq
        (ConvertTo-Json $Right -Compress -Depth 5)
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
        $item = Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
        $exists = $null -ne $item
        $kind = if (-not $exists) {
            'absent'
        } elseif ($item.PSIsContainer) {
            'directory'
        } else {
            'file'
        }
        $backup = Join-Path $root ("{0:D3}.bak" -f $index)
        if ($exists) { Copy-Item -LiteralPath $full -Destination $backup -Recurse -Force }
        $original = Get-DshCopilotPathFingerprint -Path $full
        $files.Add([pscustomobject]@{
            path = $full
            existed = $exists
            kind = $kind
            backup = if ($exists) { $backup } else { $null }
            originalFingerprint = $original
            committedExists = $null
            committedFingerprint = $null
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
        $fingerprint = Get-DshCopilotPathFingerprint -Path ([string]$file.path)
        $exists = [string]$fingerprint.kind -cne 'absent'
        if ($exists -ne [bool]$expected[0].exists) { throw "Tracked file state changed during verification for '$($file.path)'." }
        if (-not (Test-DshCopilotFingerprintEqual -Left $fingerprint -Right $expected[0].fingerprint)) {
            throw "Tracked file changed during verification for '$($file.path)'."
        }
        $file.committedExists = $exists
        $file.committedFingerprint = $fingerprint
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
            if (-not (Test-Path -LiteralPath ([string]$file.backup))) {
                throw "Backup file is missing for '$($file.path)'."
            }
            $backupFingerprint = Get-DshCopilotPathFingerprint -Path ([string]$file.backup)
            if (-not (Test-DshCopilotFingerprintEqual -Left $backupFingerprint `
                -Right $file.originalFingerprint)) {
                throw "Backup hash mismatch for '$($file.path)'."
            }
        }
        if (-not $ForceIncomplete) {
            $currentFingerprint = Get-DshCopilotPathFingerprint -Path ([string]$file.path)
            $currentExists = [string]$currentFingerprint.kind -cne 'absent'
            if ([bool]$file.committedExists -ne $currentExists) {
                throw "Current file state changed after bootstrap for '$($file.path)'."
            }
            if (-not (Test-DshCopilotFingerprintEqual -Left $currentFingerprint `
                -Right $file.committedFingerprint)) {
                throw "Current file changed after bootstrap for '$($file.path)'."
            }
        }
    }
    $results = foreach ($file in @($metadata.files)) {
        if (-not $DryRun) {
            if ($file.existed) {
                if (Test-Path -LiteralPath ([string]$file.path)) {
                    Remove-Item -LiteralPath ([string]$file.path) -Recurse -Force
                }
                Copy-Item -LiteralPath ([string]$file.backup) -Destination ([string]$file.path) `
                    -Recurse -Force
            } elseif (Test-Path -LiteralPath ([string]$file.path)) {
                Remove-Item -LiteralPath ([string]$file.path) -Recurse -Force
            }
        }
        [pscustomobject]@{ path = [string]$file.path; status = if ($DryRun) { 'would-restore' } else { 'restored' } }
    }
    return [pscustomobject]@{ operationId = $OperationId; dryRun = [bool]$DryRun; results = @($results) }
}

function Test-DshReviewedLegacySearchProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$ProfileRoot
    )
    $manifestPath = Join-Path $ProfileRoot 'package.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return [pscustomobject]@{ present = $false; valid = $true; packageRoot = $null }
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
    $dependency = if ($manifest.PSObject.Properties['dependencies']) {
        $manifest.dependencies.PSObject.Properties['dsh-web-search-provider']
    } else { $null }
    if (-not $dependency) {
        return [pscustomobject]@{ present = $false; valid = $true; packageRoot = $null }
    }
    $packageRoot = Join-Path $ProfileRoot 'node_modules\dsh-web-search-provider'
    $packageManifest = Join-Path $packageRoot 'package.json'
    if (-not (Test-Path -LiteralPath $packageManifest -PathType Leaf)) {
        throw 'Legacy dsh-web-search-provider payload is missing.'
    }
    $metadata = Get-Content -LiteralPath $packageManifest -Raw -Encoding UTF8 |
        ConvertFrom-Json
    $matches = @($Lock.profile.legacyCopilotIntegrations | Where-Object {
        [string]$_.name -ceq 'dsh-web-search-provider' -and
        [string]$_.version -ceq [string]$metadata.version -and
        (
            [string]$dependency.Value -ceq [string]$_.version -or
            [IO.Path]::GetFileName(([string]$dependency.Value).Replace('\', '/')) -like
                [string]$_.artifactPattern
        )
    })
    if ($matches.Count -ne 1) {
        throw 'Legacy dsh-web-search-provider is not in the reviewed migration inventory.'
    }
    $fingerprint = Get-DshCopilotPathFingerprint -Path $packageRoot
    return [pscustomobject]@{
        present = $true
        valid = $true
        version = [string]$metadata.version
        dependency = [string]$dependency.Value
        packageRoot = $packageRoot
        fingerprint = $fingerprint
    }
}

function Test-DshCopilotProfile {
    param(
        [Parameter(Mandatory)][string]$DshHome,
        [Parameter(Mandatory)][string]$Profile,
        [Parameter(Mandatory)][string]$ExpectedPluginVersion
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
    $pluginVersion = [string](Get-Content $pluginManifest -Raw | ConvertFrom-Json).version
    if ($pluginVersion -cne $ExpectedPluginVersion) {
        throw "Profile '$Profile' resolves dsh-github-copilot@$pluginVersion instead of locked $ExpectedPluginVersion."
    }
    return [pscustomobject]@{ profile = $Profile; healthy = $true; pluginVersion = $pluginVersion }
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
        owner = 'official-desktop-managed-runtime'
    }
}

Export-ModuleMember -Function @(
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
    'Get-DshCopilotPathFingerprint',
    'Restore-DshCopilotBackup',
    'Test-DshCopilotProfile',
    'Test-DshReviewedLegacySearchProvider',
    'Invoke-DshVisionProbe',
    'Test-DshSandboxRegression'
)
