Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DshDefaultStateRoot {
    if ($env:DSH_OPS_STATE_ROOT) {
        return [Environment]::ExpandEnvironmentVariables($env:DSH_OPS_STATE_ROOT)
    }
    return Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'dsh-windows-ops'
}

function Get-DshHomePath {
    param([Parameter(Mandatory)]$Config)
    if ($env:DSH_HOME) { return Expand-DshPath $env:DSH_HOME }
    if ($Config.dshHome) { return Expand-DshPath ([string]$Config.dshHome) }
    return Join-Path ([Environment]::GetFolderPath('UserProfile')) '.dsh'
}

function Expand-DshPath {
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    if ($expanded.StartsWith('~')) {
        $expanded = Join-Path ([Environment]::GetFolderPath('UserProfile')) $expanded.Substring(1).TrimStart('\', '/')
    }
    if (Test-Path -LiteralPath $expanded) {
        return (Resolve-Path -LiteralPath $expanded).ProviderPath
    }
    return [IO.Path]::GetFullPath($expanded)
}

function Read-DshJson {
    param([Parameter(Mandatory)][string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-DshPropertyValue {
    param(
        [Parameter(Mandatory)]$InputObject,
        [Parameter(Mandatory)][string]$Name
    )
    if ($InputObject -is [Collections.IDictionary]) { return $InputObject[$Name] }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-DshNestedProperty {
    param(
        [Parameter(Mandatory)]$InputObject,
        [Parameter(Mandatory)][string]$PropertyPath
    )
    $value = $InputObject
    foreach ($segment in $PropertyPath.Split('.')) {
        if ($null -eq $value) { return $null }
        $property = $value.PSObject.Properties[$segment]
        if ($null -eq $property) { return $null }
        $value = $property.Value
    }
    return $value
}

function Resolve-DshComponentRoot {
    param(
        [Parameter(Mandatory)]$Component,
        [AllowNull()][string]$DshHome
    )
    $candidates = [Collections.Generic.List[string]]::new()
    $rootEnv = Get-DshPropertyValue -InputObject $Component -Name 'rootEnv'
    if ($rootEnv) {
        $value = [Environment]::GetEnvironmentVariable([string]$rootEnv)
        if ($value) { $candidates.Add((Expand-DshPath $value)) }
    }
    foreach ($candidate in @(Get-DshPropertyValue -InputObject $Component -Name 'rootCandidates')) {
        if (-not $candidate) { continue }
        $expanded = [string]$candidate
        if ($DshHome) { $expanded = $expanded.Replace('${DSH_HOME}', $DshHome) }
        $candidates.Add((Expand-DshPath $expanded))
    }
    if ([string]$Component.name -eq 'dsh-desktop') {
        foreach ($registryPath in @(
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )) {
            foreach ($entry in @(Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue |
                Where-Object { (Get-DshPropertyValue -InputObject $_ -Name 'DisplayName') -match 'DeepSeek Harness' })) {
                $installLocation = Get-DshPropertyValue -InputObject $entry -Name 'InstallLocation'
                $displayIcon = Get-DshPropertyValue -InputObject $entry -Name 'DisplayIcon'
                if ($installLocation) {
                    try { $candidates.Add((Expand-DshPath ([string]$installLocation))) } catch { }
                } elseif ($displayIcon) {
                    $iconPath = ([string]$displayIcon).Split(',')[0].Trim('"')
                    try { $candidates.Add((Split-Path -Parent (Expand-DshPath $iconPath))) } catch { }
                }
            }
        }
    }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    return $null
}

function Get-DshPackageVersion {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)]$Component
    )
    foreach ($probe in @(Get-DshPropertyValue -InputObject $Component -Name 'versionProbes')) {
        if (-not $probe) { continue }
        $path = Join-Path $Root ([string]$probe.path)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        try {
            $json = Read-DshJson $path
            $value = Get-DshNestedProperty -InputObject $json -PropertyPath ([string]$probe.property)
            if ($value) { return [string]$value }
        } catch {
            return "unreadable: $($_.Exception.Message)"
        }
    }
    foreach ($probe in @(Get-DshPropertyValue -InputObject $Component -Name 'fileVersionProbes')) {
        if (-not $probe) { continue }
        $path = Join-Path $Root ([string]$probe.path)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $versionInfo = (Get-Item -LiteralPath $path).VersionInfo
        if ($versionInfo.ProductVersion) { return [string]$versionInfo.ProductVersion }
        if ($versionInfo.FileVersion) { return [string]$versionInfo.FileVersion }
    }
    return $null
}

function Get-DshComponentInventory {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config)

    $dshHome = Get-DshHomePath -Config $Config

    foreach ($component in @($Config.components)) {
        $root = Resolve-DshComponentRoot -Component $component -DshHome $dshHome
        [pscustomobject]@{
            name      = [string]$component.name
            installed = [bool]$root
            version   = if ($root) { Get-DshPackageVersion -Root $root -Component $component } else { $null }
            root      = $root
            source    = if ($root) { 'environment-or-configured-candidate' } else { 'not-found' }
        }
    }
}

function Test-DshPort {
    param([Parameter(Mandatory)][int]$Port)
    try {
        $client = [Net.Sockets.TcpClient]::new()
        $task = $client.ConnectAsync('127.0.0.1', $Port)
        if (-not $task.Wait(700)) { $client.Dispose(); return $false }
        $client.Dispose()
        return $true
    } catch {
        return $false
    }
}

function Get-DshServiceChecks {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config)

    foreach ($service in @($Config.services)) {
        $ports = @($service.ports | ForEach-Object { [int]$_ })
        $openPorts = @($ports | Where-Object { Test-DshPort $_ })
        $matches = @()
        try {
            $pattern = [string]$service.processPattern
            if ($pattern) {
                $matches = @(Get-CimInstance Win32_Process -ErrorAction Stop |
                    Where-Object { $_.Name -match $pattern -or $_.CommandLine -match $pattern } |
                    Select-Object -ExpandProperty ProcessId)
            }
        } catch {
            $matches = @()
        }
        [pscustomobject]@{
            name       = [string]$service.name
            processIds = $matches
            ports      = $ports
            openPorts  = $openPorts
            healthy    = [bool]($matches.Count -gt 0 -or $openPorts.Count -gt 0)
        }
    }
}

function Find-DshModels {
    param(
        [Parameter(Mandatory)][AllowNull()]$Value,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[object]]$Models
    )
    if ($null -eq $Value) { return }
    if ($Value -is [Collections.IDictionary]) {
        $id = $Value['id']
        if (-not $id) { $id = $Value['name'] }
        $modalities = $Value['inputModalities']
        if (-not $modalities) { $modalities = $Value['modalities'] }
        $vision = $false
        $capabilities = $Value['capabilities']
        if ($capabilities) {
            $supports = Get-DshPropertyValue -InputObject $capabilities -Name 'supports'
            $limits = Get-DshPropertyValue -InputObject $capabilities -Name 'limits'
            if ($supports -and (Get-DshPropertyValue -InputObject $supports -Name 'vision') -eq $true) { $vision = $true }
            if ($limits -and (Get-DshPropertyValue -InputObject $limits -Name 'vision')) { $vision = $true }
        }
        if ($id) {
            $text = (($modalities | ForEach-Object { [string]$_ }) -join ',').ToLowerInvariant()
            $Models.Add([pscustomobject]@{
                id           = [string]$id
                imageCapable = [bool]($vision -or $text -match 'image|vision' -or [string]$id -match '(?i)vision|image|vlm|multimodal')
                modalities   = @($modalities)
            })
        }
        foreach ($child in $Value.Values) { Find-DshModels -Value $child -Models $Models }
        return
    }
    if ($Value -is [pscustomobject]) {
        $table = @{}
        foreach ($property in $Value.PSObject.Properties) { $table[$property.Name] = $property.Value }
        Find-DshModels -Value $table -Models $Models
        return
    }
    if ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
        foreach ($child in $Value) { Find-DshModels -Value $child -Models $Models }
    }
}

function Get-DshConfigChecks {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config)

    $dshHome = Get-DshHomePath -Config $Config
    $models = [Collections.Generic.List[object]]::new()
    $files = foreach ($candidate in @($Config.configFiles)) {
        $configuredPath = ([string]$candidate).Replace('${DSH_HOME}', $dshHome)
        $path = Expand-DshPath $configuredPath
        $exists = Test-Path -LiteralPath $path -PathType Leaf
        $hash = $null
        $parse = 'not-applicable'
        if ($exists) {
            $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            if ([IO.Path]::GetExtension($path) -eq '.json') {
                try {
                    $json = Read-DshJson $path
                    Find-DshModels -Value $json -Models $models
                    $parse = 'valid-json'
                } catch {
                    $parse = 'invalid-json'
                }
            }
        }
        [pscustomobject]@{ path = $path; exists = $exists; sha256 = $hash; parse = $parse }
    }
    [pscustomobject]@{
        files              = @($files)
        models             = @($models | Sort-Object id -Unique)
        imageCapableModels = @($models | Where-Object imageCapable | Select-Object -ExpandProperty id -Unique)
    }
}

function Get-DshEndpointChecks {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config)

    foreach ($endpoint in @($Config.modelEndpoints)) {
        $baseUrl = [string]$endpoint.baseUrl
        $baseUrlEnv = Get-DshPropertyValue -InputObject $endpoint -Name 'baseUrlEnv'
        if ($baseUrlEnv) {
            $fromEnv = [Environment]::GetEnvironmentVariable([string]$baseUrlEnv)
            if ($fromEnv) { $baseUrl = $fromEnv }
        }
        $uri = $baseUrl.TrimEnd('/') + '/' + ([string]$endpoint.path).TrimStart('/')
        $uriBuilder = [UriBuilder]$uri
        $uriBuilder.Query = ''
        $uriBuilder.UserName = ''
        $uriBuilder.Password = ''
        $displayUri = $uriBuilder.Uri.AbsoluteUri.TrimEnd('/')
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri $uri -Method Get -TimeoutSec 5
            $body = $response.Content | ConvertFrom-Json
            $models = [Collections.Generic.List[object]]::new()
            Find-DshModels -Value $body -Models $models
            [pscustomobject]@{
                name               = [string]$endpoint.name
                uri                = $displayUri
                statusCode         = [int]$response.StatusCode
                reachable          = $true
                modelCount         = @($models | Select-Object -ExpandProperty id -Unique).Count
                imageCapableModels = @($models | Where-Object imageCapable | Select-Object -ExpandProperty id -Unique)
                error              = $null
            }
        } catch {
            $statusCode = $null
            $responseProperty = $_.Exception.PSObject.Properties['Response']
            if ($responseProperty -and $responseProperty.Value -and $responseProperty.Value.StatusCode) {
                $statusCode = [int]$responseProperty.Value.StatusCode
            }
            [pscustomobject]@{
                name               = [string]$endpoint.name
                uri                = $displayUri
                statusCode         = $statusCode
                reachable          = [bool]($statusCode -eq 401 -or $statusCode -eq 403)
                modelCount         = 0
                imageCapableModels = @()
                error              = if ($statusCode -eq 401 -or $statusCode -eq 403) { 'authentication-required' } else { 'connection-or-response-failed' }
            }
        }
    }
}

function Resolve-DshPatchTarget {
    param(
        [Parameter(Mandatory)]$Patch,
        [Parameter(Mandatory)]$Config
    )
    $component = @($Config.components | Where-Object { $_.name -eq $Patch.component } | Select-Object -First 1)
    if ($component.Count -eq 0) { return $null }
    $dshHome = Get-DshHomePath -Config $Config
    $root = Resolve-DshComponentRoot -Component $component[0] -DshHome $dshHome
    if (-not $root) { return $null }
    foreach ($relative in @($Patch.files)) {
        $candidate = [IO.Path]::GetFullPath((Join-Path $root ([string]$relative)))
        $prefix = $root.TrimEnd('\') + '\'
        if (-not $candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Patch '$($Patch.id)' escapes component root."
        }
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return [pscustomobject]@{ root = $root; path = $candidate; relative = [string]$relative }
        }
    }
    return [pscustomobject]@{ root = $root; path = $null; relative = $null }
}

function Test-DshPatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Patch,
        [Parameter(Mandatory)]$Config
    )
    $target = Resolve-DshPatchTarget -Patch $Patch -Config $Config
    if (-not $target) {
        return [pscustomobject]@{ id = $Patch.id; component = $Patch.component; status = 'component-not-found'; upstream = $Patch.upstreamStatus }
    }
    if (-not $target.path) {
        return [pscustomobject]@{ id = $Patch.id; component = $Patch.component; status = 'target-not-found'; upstream = $Patch.upstreamStatus }
    }
    $content = Get-Content -LiteralPath $target.path -Raw -Encoding UTF8
    $verifyMarkers = Get-DshPropertyValue -InputObject $Patch -Name 'verifyMarkers'
    if ($verifyMarkers) {
        $missing = @($verifyMarkers | Where-Object { -not $content.Contains([string]$_) })
        $status = if ($missing.Count -eq 0) { 'verified-upstream' } else { 'incompatible' }
    } elseif ($Patch.patchedFind -and $content.Contains([string]$Patch.patchedFind)) {
        $status = 'already-applied'
    } elseif ($Patch.find -and $content.Contains([string]$Patch.find)) {
        $status = 'applicable'
    } else {
        $status = 'incompatible'
    }
    return [pscustomobject]@{
        id          = [string]$Patch.id
        component   = [string]$Patch.component
        status      = $status
        target      = $target.path
        upstream    = [string]$Patch.upstreamStatus
        upstreamUrl = [string]$Patch.upstreamUrl
    }
}

function Write-DshOperationMetadata {
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)]$Metadata
    )
    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    $path = Join-Path $BackupRoot 'metadata.json'
    $temp = "$path.tmp"
    $Metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temp -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $path -Force
}

function Invoke-DshPatchSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)]$Manifest,
        [switch]$DryRun,
        [string]$StateRoot = (Get-DshDefaultStateRoot)
    )
    $operationId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')
    $backupRoot = Join-Path (Expand-DshPath $StateRoot) (Join-Path 'backups' $operationId)
    $results = [Collections.Generic.List[object]]::new()
    $inventory = [Collections.Generic.List[object]]::new()
    $plans = [Collections.Generic.List[object]]::new()
    $plannedTargets = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    foreach ($patch in @($Manifest.patches)) {
        $check = Test-DshPatch -Patch $patch -Config $Config
        if ($check.status -ne 'applicable') {
            $results.Add($check)
            continue
        }
        if ($DryRun) {
            $check.status = 'would-apply'
            $results.Add($check)
            continue
        }
        $target = Resolve-DshPatchTarget -Patch $patch -Config $Config
        if (-not $plannedTargets.Add([string]$target.path)) {
            throw "Multiple applicable patches target '$($target.path)'; combine them into one manifest entry."
        }
        $content = Get-Content -LiteralPath $target.path -Raw -Encoding UTF8
        $next = $content.Replace([string]$patch.find, [string]$patch.replace)
        if ($next -eq $content) {
            throw "Patch '$($patch.id)' produced no change."
        }
        $plans.Add([pscustomobject]@{ patch = $patch; check = $check; target = $target; next = $next })
    }

    if (-not $DryRun -and $plans.Count -gt 0) {
        $metadata = [pscustomobject]@{
            operationId = $operationId
            createdUtc = (Get-Date).ToUniversalTime().ToString('o')
            state = 'in-progress'
            files = @()
        }
        Write-DshOperationMetadata -BackupRoot $backupRoot -Metadata $metadata
    }

    foreach ($plan in $plans) {
        $patch = $plan.patch
        $target = $plan.target
        $backup = Join-Path $backupRoot (Join-Path ([string]$patch.component) ([string]$target.relative))
        $backupParent = Split-Path -Parent $backup
        New-Item -ItemType Directory -Path $backupParent -Force | Out-Null
        Copy-Item -LiteralPath $target.path -Destination $backup -Force
        $temp = "$($target.path).dsh-ops-tmp"
        try {
            Set-Content -LiteralPath $temp -Value $plan.next -Encoding UTF8 -NoNewline
            $entry = [pscustomobject]@{
                id = [string]$patch.id; component = [string]$patch.component
                relative = [string]$target.relative
                originalSha256 = (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash
                patchedSha256 = (Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash
                state = 'staged'
            }
            $inventory.Add($entry)
            $metadata.files = @($inventory)
            Write-DshOperationMetadata -BackupRoot $backupRoot -Metadata $metadata
            Move-Item -LiteralPath $temp -Destination $target.path -Force
            $entry.state = 'committed'
            Write-DshOperationMetadata -BackupRoot $backupRoot -Metadata $metadata
        } finally {
            if (Test-Path -LiteralPath $temp -PathType Leaf) {
                Remove-Item -LiteralPath $temp -Force
            }
        }
        $plan.check.status = 'applied'
        $results.Add($plan.check)
    }

    if (-not $DryRun -and $plans.Count -gt 0) {
        $metadata.state = 'completed'
        Write-DshOperationMetadata -BackupRoot $backupRoot -Metadata $metadata
    }
    return [pscustomobject]@{ operationId = $operationId; dryRun = [bool]$DryRun; results = @($results) }
}

function Restore-DshPatchSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)]$Manifest,
        [string]$OperationId,
        [string]$StateRoot = (Get-DshDefaultStateRoot),
        [switch]$DryRun
    )
    $backups = Join-Path (Expand-DshPath $StateRoot) 'backups'
    if (-not (Test-Path -LiteralPath $backups -PathType Container)) { throw 'No backups are available.' }
    if (-not $OperationId) {
        $OperationId = Get-ChildItem -LiteralPath $backups -Directory |
            Where-Object { $_.Name -match '^\d{8}T\d{9}Z$' } |
            Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty Name
    }
    if (-not $OperationId) { throw 'No backup operation was found.' }
    if ($OperationId -notmatch '^\d{8}T\d{9}Z$') { throw 'Invalid backup operation id.' }
    $operationRoot = [IO.Path]::GetFullPath((Join-Path $backups $OperationId))
    $backupsPrefix = [IO.Path]::GetFullPath($backups).TrimEnd('\') + '\'
    if (-not $operationRoot.StartsWith($backupsPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Backup operation escapes the state root.'
    }
    $metadataPath = Join-Path $operationRoot 'metadata.json'
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) { throw "Backup metadata not found for '$OperationId'." }
    $metadata = Read-DshJson $metadataPath
    $restorePlans = [Collections.Generic.List[object]]::new()
    foreach ($file in @($metadata.files)) {
        $patch = @($Manifest.patches | Where-Object { $_.id -eq $file.id } | Select-Object -First 1)
        if ($patch.Count -eq 0) { throw "Backup references unknown patch '$($file.id)'." }
        if ([string]$patch[0].component -ne [string]$file.component) {
            throw "Backup component does not match patch '$($file.id)'."
        }
        if (@($patch[0].files) -notcontains [string]$file.relative) {
            throw "Backup target is not allowed by patch '$($file.id)'."
        }
        $component = @($Config.components | Where-Object { $_.name -eq $patch[0].component } | Select-Object -First 1)
        if ($component.Count -eq 0) { throw "Component '$($patch[0].component)' is not configured." }
        $root = Resolve-DshComponentRoot -Component $component[0] -DshHome (Get-DshHomePath -Config $Config)
        if (-not $root) { throw "Component '$($patch[0].component)' is not installed." }
        $target = [IO.Path]::GetFullPath((Join-Path $root ([string]$file.relative)))
        $rootPrefix = $root.TrimEnd('\') + '\'
        if (-not $target.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Restore target escapes component '$($patch[0].component)'."
        }
        $backup = [IO.Path]::GetFullPath((Join-Path $operationRoot (Join-Path ([string]$file.component) ([string]$file.relative))))
        $operationPrefix = $operationRoot.TrimEnd('\') + '\'
        if (-not $backup.StartsWith($operationPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Backup path escapes operation '$OperationId'."
        }
        if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) {
            throw "Backup file is missing for patch '$($file.id)'."
        }
        $backupHash = (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash
        if ($backupHash -ne [string]$file.originalSha256) {
            throw "Backup hash mismatch for patch '$($file.id)'."
        }
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            throw "Current target is missing for patch '$($file.id)'."
        }
        $currentHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
        $fileState = Get-DshPropertyValue -InputObject $file -Name 'state'
        if (-not $fileState) { $fileState = 'committed' }
        if ($fileState -eq 'staged' -and $currentHash -eq [string]$file.originalSha256) {
            $action = 'skip-uncommitted'
        } elseif ($currentHash -eq [string]$file.patchedSha256) {
            $action = 'restore'
        } else {
            throw "Current target changed after patch '$($file.id)'; refusing stale rollback."
        }
        $restorePlans.Add([pscustomobject]@{
            id = [string]$file.id
            target = $target
            backup = $backup
            originalSha256 = [string]$file.originalSha256
            action = $action
        })
    }

    $results = foreach ($plan in $restorePlans) {
        if ($plan.action -eq 'skip-uncommitted') {
            [pscustomobject]@{ id = $plan.id; status = 'not-applied'; target = $plan.target }
            continue
        }
        if (-not $DryRun) {
            $restoreTemp = "$($plan.target).dsh-ops-restore-tmp"
            try {
                Copy-Item -LiteralPath $plan.backup -Destination $restoreTemp -Force
                if ((Get-FileHash -LiteralPath $restoreTemp -Algorithm SHA256).Hash -ne $plan.originalSha256) {
                    throw "Restore staging hash mismatch for patch '$($plan.id)'."
                }
                Move-Item -LiteralPath $restoreTemp -Destination $plan.target -Force
            } finally {
                if (Test-Path -LiteralPath $restoreTemp -PathType Leaf) {
                    Remove-Item -LiteralPath $restoreTemp -Force
                }
            }
        }
        [pscustomobject]@{ id = $plan.id; status = if ($DryRun) { 'would-restore' } else { 'restored' }; target = $plan.target }
    }
    return [pscustomobject]@{ operationId = $OperationId; dryRun = [bool]$DryRun; results = @($results) }
}

function Invoke-DshDesktopRecovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [switch]$DryRun,
        [int]$TimeoutSeconds = 90
    )
    $desktop = @($Config.components | Where-Object name -eq 'dsh-desktop' | Select-Object -First 1)
    if ($desktop.Count -eq 0) { throw 'The configuration has no dsh-desktop component.' }
    $root = Resolve-DshComponentRoot -Component $desktop[0] -DshHome (Expand-DshPath $env:DSH_HOME)
    if (-not $root) { throw 'DSH Desktop was not found. Set DSH_DESKTOP_ROOT.' }
    $app = $null
    foreach ($relative in @($desktop[0].executables)) {
        $candidate = Join-Path $root ([string]$relative)
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $app = $candidate; break }
    }
    if (-not $app) { throw 'DSH Desktop executable was not found under DSH_DESKTOP_ROOT.' }
    if ($DryRun) {
        return [pscustomobject]@{ status = 'would-restart'; executable = $app; timeoutSeconds = $TimeoutSeconds }
    }
    $resolvedApp = [IO.Path]::GetFullPath($app)
    $processes = @(Get-CimInstance Win32_Process | Where-Object {
        $_.ExecutablePath -and [IO.Path]::GetFullPath($_.ExecutablePath).Equals($resolvedApp, [StringComparison]::OrdinalIgnoreCase)
    })
    foreach ($process in $processes) { Stop-Process -Id $process.ProcessId -Force }
    Start-Process -FilePath $resolvedApp | Out-Null
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Milliseconds 500
        $checks = @(Get-DshServiceChecks -Config $Config | Where-Object name -eq 'dsh-desktop')
        if ($checks.Count -gt 0 -and $checks[0].healthy) {
            return [pscustomobject]@{ status = 'healthy'; executable = $resolvedApp; service = $checks[0] }
        }
    } while ((Get-Date) -lt $deadline)
    throw "DSH Desktop did not become healthy within $TimeoutSeconds seconds."
}

Export-ModuleMember -Function @(
    'Get-DshComponentInventory',
    'Get-DshServiceChecks',
    'Get-DshConfigChecks',
    'Get-DshEndpointChecks',
    'Test-DshPatch',
    'Invoke-DshPatchSet',
    'Restore-DshPatchSet',
    'Invoke-DshDesktopRecovery'
)
