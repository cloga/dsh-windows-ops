Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# This module intentionally owns only the optional, local migration stage.  It does
# not install packages, invoke Electron, call IPC, stop processes, or mutate the
# community DSH home.
$script:MigrationSchemaVersion = 1
$script:MigrationSchemaName = 'official-desktop-local-migration-v1'
$script:MigrationSettingsLimit = 1MB
$script:MigrationCredentialsLimit = 1MB
$script:MigrationManifestLimit = 1MB
$script:MigrationPresetLimit = 1MB
$script:MigrationPresetTotalLimit = 8MB
$script:MigrationMaxLines = 20000
$script:MigrationMaxLeaves = 4096
$script:MigrationMaxDepth = 32
$script:MigrationMaxScalar = 8192
$script:MigrationMaxActions = 4096
$script:MigrationReleaseVersion = '0.1.5-rc.2'
$script:MigrationSourceTag = 'dsh-v0.1.5-rc.2'
$script:MigrationSourceCommit = 'fb2c4b9e698e30edb738bca4cf0618587db7d203'
$script:MigrationHostProtocolVersion = 3
$script:MigrationAllowedProfiles = @('desktop', 'web', 'headless')
$script:MigrationSecretKeyPattern = '(?i)(^|[-_.])(api[-_]?key|token|secret|password|cookie|authorization|credential)([-_.]|$)'

function Get-MigrationProperty {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory)][string]$Name
    )
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }
    $property = @($Object.PSObject.Properties | Where-Object { $_.Name -ceq $Name } | Select-Object -First 1)
    if ($property.Count -eq 1) { return $property[0].Value }
    return $null
}

function Get-MigrationPath {
    param([Parameter(Mandatory)][string]$Path)
    return [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

function Test-MigrationPathWithin {
    param(
        [Parameter(Mandatory)][string]$Candidate,
        [Parameter(Mandatory)][string]$Parent
    )
    $candidatePath = Get-MigrationPath $Candidate
    $parentPath = Get-MigrationPath $Parent
    return $candidatePath.Equals($parentPath, [StringComparison]::OrdinalIgnoreCase) -or
        ($candidatePath + '\').StartsWith($parentPath + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Get-MigrationRelativePath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root
    )
    $fullPath = Get-MigrationPath $Path
    $fullRoot = Get-MigrationPath $Root
    if (-not (Test-MigrationPathWithin $fullPath $fullRoot)) { throw 'migration-relative-path-outside-root' }
    return $fullPath.Substring($fullRoot.Length).TrimStart('\', '/').Replace('\', '/')
}

function ConvertTo-MigrationCanonicalValue {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($key in @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object -CaseSensitive)) {
            $ordered[$key] = ConvertTo-MigrationCanonicalValue $Value[$key]
        }
        return $ordered
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $ordered = [ordered]@{}
        foreach ($property in @($Value.PSObject.Properties | Sort-Object Name)) {
            $ordered[$property.Name] = ConvertTo-MigrationCanonicalValue $property.Value
        }
        return $ordered
    }
    if ($Value -is [System.Array]) {
        return @($Value | ForEach-Object { ConvertTo-MigrationCanonicalValue $_ })
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        return @($Value | ForEach-Object { ConvertTo-MigrationCanonicalValue $_ })
    }
    return $Value
}

function ConvertTo-DshOfficialDesktopLocalMigrationCanonicalJson {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)
    $canonical = ConvertTo-MigrationCanonicalValue $Value
    return ($canonical | ConvertTo-Json -Depth 100 -Compress)
}

function Get-MigrationSha256Text {
    param([Parameter(Mandatory)][string]$Text)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-MigrationSha256File {
    param([Parameter(Mandatory)][string]$Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
        finally { $stream.Dispose() }
    } finally { $sha.Dispose() }
}

function Get-DshOfficialDesktopLocalMigrationOperations {
    [CmdletBinding()]
    param()
    return @{
        PathExists = { param($Path, $Type)
            if ($Type -eq 'Leaf') { return Test-Path -LiteralPath $Path -PathType Leaf }
            if ($Type -eq 'Container') { return Test-Path -LiteralPath $Path -PathType Container }
            return Test-Path -LiteralPath $Path
        }
        GetLength = { param($Path) ([IO.FileInfo](Get-Item -LiteralPath $Path -Force)).Length }
        ReadText = { param($Path) [IO.File]::ReadAllText($Path) }
        ReadJson = { param($Path) ([IO.File]::ReadAllText($Path) | ConvertFrom-Json) }
        GetHash = { param($Path) (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
        GetSignature = { param($Path) (Get-AuthenticodeSignature -LiteralPath $Path).Status.ToString() }
        GetVersionInfo = { param($Path) (Get-Item -LiteralPath $Path).VersionInfo }
        TestReparse = { param($Path)
            if (-not (Test-Path -LiteralPath $Path)) { return $false }
            return [bool]((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)
        }
        WriteAtomicText = { param($Path, $Text)
            $parent = Split-Path -Parent $Path
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            $temp = $Path + '.tmp-' + [guid]::NewGuid().ToString('N')
            [IO.File]::WriteAllText($temp, $Text, [Text.UTF8Encoding]::new($false))
            Move-Item -LiteralPath $temp -Destination $Path -Force
        }
        CopyFile = { param($Source, $Destination)
            $parent = Split-Path -Parent $Destination
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Copy-Item -LiteralPath $Source -Destination $Destination -Force
        }
        EnsureDirectory = { param($Path) if (-not (Test-Path -LiteralPath $Path -PathType Container)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null } }
        GetProcesses = {
            try {
                $rows = @(Get-CimInstance Win32_Process -ErrorAction Stop | ForEach-Object {
                    [pscustomobject]@{ Id = $_.ProcessId; Name = $_.Name; ExecutablePath = $_.ExecutablePath; CommandLine = $null }
                })
                return $rows
            } catch {
                try {
                    $rows = @(Get-Process -ErrorAction Stop | ForEach-Object {
                        $path = $null
                        try { $path = $_.Path } catch { $path = $null }
                        [pscustomobject]@{ Id = $_.Id; Name = $_.ProcessName; ExecutablePath = $path; CommandLine = $null }
                    })
                    return $rows
                } catch {
                    return [pscustomobject]@{ unavailable = $true }
                }
            }
        }
        # The Desktop session API is intentionally not called by this MVP.  A
        # caller that owns a live-session probe injects it; the default is
        # explicitly unavailable so Apply fails closed rather than treating an
        # unprobed machine as session-free.
        GetLiveSessions = { [pscustomobject]@{ unavailable = $true } }
        GetUtcNow = { [DateTime]::UtcNow }
        NewGuid = { [guid]::NewGuid() }
    }
}

function Merge-MigrationOperations {
    param([AllowNull()][hashtable]$Operations)
    $all = Get-DshOfficialDesktopLocalMigrationOperations
    if ($Operations) {
        foreach ($key in $Operations.Keys) { $all[$key] = $Operations[$key] }
    }
    return $all
}

function Test-MigrationCloudPath {
    param([Parameter(Mandatory)][string]$Path)
    $fullPath = Get-MigrationPath $Path
    foreach ($root in @($env:OneDrive, $env:OneDriveCommercial, $env:OneDriveConsumer, $env:Dropbox, $env:GoogleDrive)) {
        if ($root -and [IO.Path]::IsPathRooted($root) -and (Test-MigrationPathWithin $fullPath $root)) { return $true }
    }
    return [bool]($fullPath -match '(?i)(^|[\\/])(OneDrive(?: - [^\\/]+)?|Dropbox|Google Drive|iCloudDrive)([\\/]|$)')
}

function Test-MigrationReparseTree {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$Operations
    )
    $cursor = Get-MigrationPath $Path
    while ($cursor) {
        if (& $Operations.TestReparse $cursor) { return $true }
        $parent = Split-Path -Parent $cursor
        if (-not $parent -or $parent -ceq $cursor) { break }
        $cursor = $parent
    }
    return $false
}

function Assert-MigrationSafeRoot {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][hashtable]$Operations
    )
    if ([string]::IsNullOrWhiteSpace($Path) -or -not [IO.Path]::IsPathRooted($Path)) { throw "$Name-must-be-absolute" }
    if ($Path.StartsWith('\\') -or $Path.StartsWith('//')) { throw "$Name-must-be-local" }
    if (Test-MigrationCloudPath $Path) { throw "$Name-cloud-synchronized" }
    if (Test-MigrationReparseTree $Path $Operations) { throw "$Name-reparse-point" }
    return Get-MigrationPath $Path
}

function Assert-MigrationNoOverlap {
    param(
        [Parameter(Mandatory)][string]$CommunityRoot,
        [Parameter(Mandatory)][string]$DataRoot,
        [Parameter(Mandatory)][string]$InstallRoot
    )
    foreach ($pair in @(
        @($CommunityRoot, $DataRoot), @($CommunityRoot, $InstallRoot), @($DataRoot, $InstallRoot)
    )) {
        if ((Test-MigrationPathWithin $pair[0] $pair[1]) -or (Test-MigrationPathWithin $pair[1] $pair[0])) {
            throw 'migration-root-overlap'
        }
    }
}

function Get-MigrationFileRecord {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][int64]$Limit,
        [Parameter(Mandatory)][hashtable]$Operations
    )
    $present = [bool](& $Operations.PathExists $Path 'Leaf')
    if (-not $present) {
        return [pscustomobject][ordered]@{ path = $RelativePath.Replace('\', '/'); present = $false; size = 0; sha256 = $null }
    }
    if (Test-MigrationReparseTree $Path $Operations) { throw "migration-$Kind-reparse-point" }
    $length = [int64](& $Operations.GetLength $Path)
    if ($length -gt $Limit) { throw "migration-$Kind-too-large" }
    return [pscustomobject][ordered]@{ path = $RelativePath.Replace('\', '/'); present = $true; size = $length; sha256 = ('sha256:' + ([string](& $Operations.GetHash $Path)).ToLowerInvariant()) }
}

function Remove-MigrationInlineComment {
    param([Parameter(Mandatory)][string]$Text)
    $single = $false; $double = $false; $escaped = $false
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $char = $Text[$i]
        if ($double -and $escaped) { $escaped = $false; continue }
        if ($double -and $char -eq '\') { $escaped = $true; continue }
        if ($char -eq "'" -and -not $double) { $single = -not $single; continue }
        if ($char -eq '"' -and -not $single) { $double = -not $double; continue }
        if ($char -eq '#' -and -not $single -and -not $double -and ($i -eq 0 -or [char]::IsWhiteSpace($Text[$i - 1]))) {
            return $Text.Substring(0, $i).TrimEnd()
        }
    }
    return $Text.TrimEnd()
}

function Find-MigrationColon {
    param([Parameter(Mandatory)][string]$Text)
    $single = $false; $double = $false; $escaped = $false
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $char = $Text[$i]
        if ($double -and $escaped) { $escaped = $false; continue }
        if ($double -and $char -eq '\') { $escaped = $true; continue }
        if ($char -eq "'" -and -not $double) { $single = -not $single; continue }
        if ($char -eq '"' -and -not $single) { $double = -not $double; continue }
        if ($char -eq ':' -and -not $single -and -not $double) { return $i }
    }
    return -1
}

function ConvertFrom-MigrationYamlScalar {
    param([Parameter(Mandatory)][string]$Text)
    $value = (Remove-MigrationInlineComment $Text).Trim()
    if ($value.Length -eq 0 -or $value -eq '~' -or $value -eq 'null' -or $value -eq 'Null' -or $value -eq 'NULL') { return $null }
    if ($value.StartsWith('[') -or $value.StartsWith('{') -or $value -eq '|' -or $value -eq '>') { throw 'migration-yaml-complex-scalar' }
    if ($value.StartsWith('&') -or $value.StartsWith('*')) { throw 'migration-yaml-alias' }
    if ($value.Length -ge 2 -and $value[0] -eq "'" -and $value[$value.Length - 1] -eq "'") {
        return $value.Substring(1, $value.Length - 2).Replace("''", "'")
    }
    if ($value.Length -ge 2 -and $value[0] -eq '"' -and $value[$value.Length - 1] -eq '"') {
        try { return (('{' + '"v":' + $value + '}') | ConvertFrom-Json).v } catch { throw 'migration-yaml-invalid-quoted-scalar' }
    }
    if ($value -match '^(?i:true|false)$') { return [bool]::Parse($value) }
    if ($value -match '^-?\d+$') { try { return [int64]$value } catch { throw 'migration-yaml-invalid-number' } }
    if ($value -match '^-?\d+\.\d+$') { try { return [decimal]$value } catch { throw 'migration-yaml-invalid-number' } }
    if ($value -match '(^|\s)[&*][A-Za-z0-9_.-]+') { throw 'migration-yaml-alias' }
    return $value
}

function Get-MigrationPathKey {
    param([Parameter(Mandatory)][string[]]$Path)
    return ($Path -join '.')
}

function Get-MigrationYamlSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][int64]$Limit,
        [Parameter(Mandatory)][hashtable]$Operations
    )
    if (-not (& $Operations.PathExists $Path 'Leaf')) {
        return [pscustomobject][ordered]@{ exists = $false; text = ''; newline = "`n"; leaves = @(); modelEntries = @(); secretCount = 0; headerCount = 0 }
    }
    $record = Get-MigrationFileRecord $Path ([IO.Path]::GetFileName($Path)) $Kind $Limit $Operations
    $text = [string](& $Operations.ReadText $Path)
    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    if ($text.Length -gt $Limit) { throw "migration-$Kind-too-large-after-read" }
    $lines = $text -split "\r?\n"
    if ($lines.Count -gt $script:MigrationMaxLines) { throw "migration-$Kind-too-many-lines" }
    $leaves = [Collections.Generic.List[object]]::new()
    $modelEntries = [Collections.Generic.List[object]]::new()
    $stack = [Collections.Generic.List[object]]::new()
    $activeModel = $null
    $secretCount = 0
    $headerCount = 0
    $seen = @{}

    for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
        $line = [string]$lines[$lineIndex]
        if ($line -match "`t") { throw 'migration-yaml-tabs' }
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
        $indent = $line.Length - $line.TrimStart(' ').Length
        if ($indent -gt ($script:MigrationMaxDepth * 2)) { throw 'migration-yaml-depth-limit' }
        if ($line.Length -gt $script:MigrationMaxScalar) { throw 'migration-yaml-line-limit' }
        $content = $line.Substring($indent)
        if ($content -match '^(---|\.\.\.)\s*$') { throw 'migration-yaml-document-marker' }
        if ($content -match '(^|\s)[&*][A-Za-z0-9_.-]+') { throw 'migration-yaml-alias' }

        if ($content.StartsWith('-')) {
            if ($stack.Count -eq 0 -or [string]$stack[$stack.Count - 1].lastKey -cne 'models') { throw 'migration-yaml-array-unsupported' }
            $rest = $content.Substring(1).Trim()
            $colon = Find-MigrationColon $rest
            if ($colon -lt 0 -or $rest.Substring(0, $colon).Trim() -cne 'id') { throw 'migration-yaml-model-array-unsupported' }
            $id = ConvertFrom-MigrationYamlScalar $rest.Substring($colon + 1)
            if ($null -eq $id -or [string]::IsNullOrWhiteSpace([string]$id)) { throw 'migration-yaml-model-id-invalid' }
            $modelsPath = @($stack[$stack.Count - 1].path)
            $provider = if ($modelsPath.Count -ge 2) { [string]$modelsPath[$modelsPath.Count - 2] } else { '' }
            $activeModel = [ordered]@{ provider = $provider; id = [string]$id; api = $null; indent = $indent }
            $modelEntries.Add([pscustomobject]$activeModel)
            continue
        }

        while ($stack.Count -gt 0 -and $indent -le [int]$stack[$stack.Count - 1].indent) { $stack.RemoveAt($stack.Count - 1) }
        $colon = Find-MigrationColon $content
        if ($colon -le 0) { throw 'migration-yaml-mapping-unsupported' }
        $key = $content.Substring(0, $colon).Trim()
        if ($key.IndexOf("'") -ge 0 -or $key.IndexOf('"') -ge 0) { throw 'migration-yaml-quoted-key-unsupported' }
        if ($key -match '[\[\]{}]') { throw 'migration-yaml-key-unsupported' }
        $raw = $content.Substring($colon + 1).Trim()
        $parentPath = if ($stack.Count -gt 0) { @($stack[$stack.Count - 1].path) } else { @() }
        $pathBuilder = [Collections.Generic.List[string]]::new()
        foreach ($parentPart in @($parentPath)) { $pathBuilder.Add([string]$parentPart) }
        $pathBuilder.Add($key)
        $pathParts = @($pathBuilder)
        $pathKey = Get-MigrationPathKey $pathParts
        if ($raw.Length -eq 0) {
            $stack.Add([pscustomobject]@{ indent = $indent; path = $pathParts; lastKey = $key })
            continue
        }
        if ($raw.StartsWith('[') -or $raw.StartsWith('{') -or $raw -eq '|' -or $raw -eq '>') {
            throw 'migration-yaml-complex-value'
        }
        $value = ConvertFrom-MigrationYamlScalar $raw
        if ($seen.ContainsKey($pathKey)) { throw 'migration-yaml-duplicate-key' }
        $seen[$pathKey] = $true
        $isSecret = ($key -match $script:MigrationSecretKeyPattern) -or $key -ieq 'headers'
        if ($isSecret) { $secretCount++ }
        if ($key -ieq 'headers') { $headerCount++ }
        if ($leaves.Count -ge $script:MigrationMaxLeaves) { throw 'migration-yaml-leaf-limit' }
        if ([string]$raw.Length -gt $script:MigrationMaxScalar) { throw 'migration-yaml-scalar-limit' }
        $leaves.Add([pscustomobject][ordered]@{
                path = $pathParts; key = $key; pathKey = $pathKey; value = $value; raw = $raw; lineIndex = $lineIndex; indent = $indent; isSecret = $isSecret
            })
        if ($activeModel -and $indent -gt [int]$activeModel.indent -and $key -ceq 'api') {
            $activeModel.api = [string]$value
            $activeModel = [pscustomobject]$activeModel
            $modelEntries[$modelEntries.Count - 1] = $activeModel
        }
    }
    return [pscustomobject][ordered]@{
        exists = $true; text = $text; newline = $newline; lines = $lines; leaves = @($leaves); modelEntries = @($modelEntries)
        secretCount = $secretCount; headerCount = $headerCount; fileHash = ('sha256:' + ([string](& $Operations.GetHash $Path)).ToLowerInvariant()); size = [int64](& $Operations.GetLength $Path)
    }
}

function Find-MigrationLeaf {
    param(
        [Parameter(Mandatory)][object]$Snapshot,
        [Parameter(Mandatory)][string[]]$Path
    )
    $key = Get-MigrationPathKey $Path
    $matches = @($Snapshot.leaves | Where-Object { $_.pathKey -ceq $key } | Select-Object -First 1)
    if ($matches.Count -gt 0) { return $matches[0] }
    return $null
}

function Get-MigrationSourceFilePath {
    param([Parameter(Mandatory)][string]$CommunityRoot)
    return Join-Path $CommunityRoot 'settings.yaml'
}

function Get-MigrationTargetHome {
    param([Parameter(Mandatory)][string]$DataRoot)
    return Join-Path $DataRoot 'harness-home'
}

function Get-MigrationTargetSettingsPath {
    param([Parameter(Mandatory)][string]$DataRoot)
    return Join-Path (Get-MigrationTargetHome $DataRoot) 'settings.yaml'
}

function Get-MigrationTargetReceiptPath {
    param([Parameter(Mandatory)][string]$DataRoot)
    return Join-Path $DataRoot 'official-desktop-local-install.json'
}

function Get-MigrationTargetSeedPath {
    param([Parameter(Mandatory)][string]$InstallRoot)
    return Join-Path $InstallRoot 'resources\seed\desktop-release.json'
}

function Get-MigrationTargetReleaseEvidence {
    param(
        [Parameter(Mandatory)][string]$DataRoot,
        [Parameter(Mandatory)][string]$InstallRoot,
        [Parameter(Mandatory)][hashtable]$Operations
    )
    $seedPath = Get-MigrationTargetSeedPath $InstallRoot
    $seed = $null
    $seedRecord = [pscustomobject][ordered]@{ present = $false; size = 0; sha256 = $null }
    $reasons = [Collections.Generic.List[string]]::new()
    if (-not (& $Operations.PathExists $seedPath 'Leaf')) {
        $reasons.Add('target-release-metadata-missing')
    } elseif (Test-MigrationReparseTree $seedPath $Operations) {
        $reasons.Add('target-release-metadata-reparse-point')
    } elseif ([int64](& $Operations.GetLength $seedPath) -gt $script:MigrationManifestLimit) {
        $reasons.Add('target-release-metadata-too-large')
    } else {
        $seedRecord = Get-MigrationFileRecord $seedPath 'resources/seed/desktop-release.json' 'release' $script:MigrationManifestLimit $Operations
        try { $seed = & $Operations.ReadJson $seedPath } catch { $reasons.Add('target-release-metadata-invalid') }
        if ($seed) {
            if ([string](Get-MigrationProperty $seed 'version') -cne $script:MigrationReleaseVersion) { $reasons.Add('target-release-version-mismatch') }
            if ([int](Get-MigrationProperty $seed 'hostProtocolVersion') -ne $script:MigrationHostProtocolVersion) { $reasons.Add('target-host-protocol-mismatch') }
        }
    }
    $profileMetadata = [Collections.Generic.List[object]]::new()
    $targetHome = Get-MigrationTargetHome $DataRoot
    foreach ($profile in $script:MigrationAllowedProfiles) {
        $metadataPath = Join-Path (Join-Path $targetHome ('profiles\' + $profile)) 'desktop-release.json'
        if (& $Operations.PathExists $metadataPath 'Leaf') {
            if (Test-MigrationReparseTree $metadataPath $Operations) {
                $reasons.Add("target-profile-release-reparse-point:$profile")
                $profileMetadata.Add([pscustomobject][ordered]@{ profile = $profile; present = $true; valid = $false })
                continue
            }
            if ([int64](& $Operations.GetLength $metadataPath) -gt $script:MigrationManifestLimit) {
                $reasons.Add("target-profile-release-too-large:$profile")
                $profileMetadata.Add([pscustomobject][ordered]@{ profile = $profile; present = $true; valid = $false })
                continue
            }
            try {
                $metadata = & $Operations.ReadJson $metadataPath
                $metadataVersion = [string](Get-MigrationProperty $metadata 'version')
                $metadataProtocol = [int](Get-MigrationProperty $metadata 'hostProtocolVersion')
                $ok = $metadataVersion -ceq $script:MigrationReleaseVersion -and $metadataProtocol -eq $script:MigrationHostProtocolVersion
                if (-not $ok) { $reasons.Add("target-profile-release-mismatch:$profile") }
                $profileMetadata.Add([pscustomobject][ordered]@{ profile = $profile; present = $true; valid = $ok })
            } catch {
                $reasons.Add("target-profile-release-invalid:$profile")
                $profileMetadata.Add([pscustomobject][ordered]@{ profile = $profile; present = $true; valid = $false })
            }
        } else {
            $profileMetadata.Add([pscustomobject][ordered]@{ profile = $profile; present = $false; valid = $true })
        }
    }
    return [pscustomobject][ordered]@{
        valid = ($reasons.Count -eq 0)
        version = $script:MigrationReleaseVersion
        hostProtocolVersion = $script:MigrationHostProtocolVersion
        seed = [pscustomobject][ordered]@{ path = 'resources/seed/desktop-release.json'; present = [bool]$seedRecord.present; size = $seedRecord.size; sha256 = $seedRecord.sha256 }
        profiles = @($profileMetadata)
        reasons = @($reasons | Sort-Object -Unique)
    }
}

function Test-MigrationReceiptHash {
    param([Parameter(Mandatory)][object]$Receipt)
    $hash = [string](Get-MigrationProperty $Receipt 'receiptSha256')
    if ([string]::IsNullOrWhiteSpace($hash)) { return $false }
    $copy = [ordered]@{}
    foreach ($property in @($Receipt.PSObject.Properties)) {
        if ($property.Name -cne 'receiptSha256') { $copy[$property.Name] = $property.Value }
    }
    # The install module's receipt hash is intentionally insertion-order JSON;
    # preserve that compatibility here. Plan hashes use the recursive canonical
    # serializer above, but an install receipt is an existing contract.
    $payload = $copy | ConvertTo-Json -Depth 40 -Compress
    return (Get-MigrationSha256Text $payload) -ceq $hash.ToLowerInvariant()
}

function Test-MigrationTrustedInstallReceipt {
    param(
        [AllowNull()][object]$Receipt,
        [Parameter(Mandatory)][string]$DataRoot,
        [Parameter(Mandatory)][string]$InstallRoot,
        [Parameter(Mandatory)][hashtable]$Operations
    )
    try {
        if ($null -eq $Receipt) { return $false }
        if ([int](Get-MigrationProperty $Receipt 'schemaVersion') -ne 1 -or [string](Get-MigrationProperty $Receipt 'status') -cne 'complete') { return $false }
        if ((Get-MigrationPath ([string](Get-MigrationProperty $Receipt 'installRoot'))) -cne (Get-MigrationPath $InstallRoot)) { return $false }
        if ((Get-MigrationPath ([string](Get-MigrationProperty $Receipt 'dataRoot'))) -cne (Get-MigrationPath $DataRoot)) { return $false }
        $identity = Get-MigrationProperty $Receipt 'identity'
        if ([string](Get-MigrationProperty $identity 'productName') -cne 'DeepSeek Harness') { return $false }
        if ([string](Get-MigrationProperty $identity 'appId') -cne 'local.cloga.dsh-official-source-build') { return $false }
        if ([string](Get-MigrationProperty $identity 'packageName') -cne 'dsh-local-build') { return $false }
        if ((Get-MigrationProperty $identity 'unsigned') -ne $true -or (Get-MigrationProperty $identity 'automaticUpdates') -ne $false) { return $false }
        $source = Get-MigrationProperty $Receipt 'source'
        if ([string](Get-MigrationProperty $source 'tag') -cne $script:MigrationSourceTag -or [string](Get-MigrationProperty $source 'commit') -cne $script:MigrationSourceCommit) { return $false }
        if (-not (Test-MigrationReceiptHash $Receipt)) { return $false }
        $executablePath = [string](Get-MigrationProperty $Receipt 'installedExecutablePath')
        if (-not $executablePath -or -not (Test-MigrationPathWithin $executablePath $InstallRoot)) { return $false }
        if (-not (& $Operations.PathExists $executablePath 'Leaf')) { return $false }
        $expectedExecutableHash = [string](Get-MigrationProperty $Receipt 'installedExecutableSha256')
        if ($expectedExecutableHash -notmatch '^[0-9a-fA-F]{64}$' -or ([string](& $Operations.GetHash $executablePath)).ToLowerInvariant() -cne $expectedExecutableHash.ToLowerInvariant()) { return $false }
        if ($Operations.ContainsKey('GetSignature') -and (& $Operations.GetSignature $executablePath) -cne 'NotSigned') { return $false }
        if ($Operations.ContainsKey('GetVersionInfo')) {
            $version = & $Operations.GetVersionInfo $executablePath
            foreach ($field in @('ProductName', 'FileDescription', 'InternalName')) { if ([string](Get-MigrationProperty $version $field) -cne 'DeepSeek Harness') { return $false } }
            if ([string](Get-MigrationProperty $version 'FileVersion') -cne $script:MigrationReleaseVersion) { return $false }
        }
        return $true
    } catch { return $false }
}

function Get-MigrationReceiptEvidence {
    param(
        [Parameter(Mandatory)][string]$DataRoot,
        [Parameter(Mandatory)][string]$InstallRoot,
        [Parameter(Mandatory)][hashtable]$Operations
    )
    $path = Get-MigrationTargetReceiptPath $DataRoot
    if (-not (& $Operations.PathExists $path 'Leaf')) {
        return [pscustomobject][ordered]@{ present = $false; valid = $false; path = 'official-desktop-local-install.json' }
    }
    if ((Test-MigrationReparseTree $path $Operations) -or ([int64](& $Operations.GetLength $path) -gt $script:MigrationManifestLimit)) {
        return [pscustomobject][ordered]@{ present = $true; valid = $false; path = 'official-desktop-local-install.json' }
    }
    $record = Get-MigrationFileRecord $path 'official-desktop-local-install.json' 'receipt' $script:MigrationManifestLimit $Operations
    $receipt = $null
    try { $receipt = & $Operations.ReadJson $path } catch { return [pscustomobject][ordered]@{ present = $true; valid = $false; path = 'official-desktop-local-install.json'; size = $record.size; sha256 = $record.sha256; executableSha256 = $null } }
    return [pscustomobject][ordered]@{
        present = $true
        valid = (Test-MigrationTrustedInstallReceipt $receipt $DataRoot $InstallRoot $Operations)
        path = 'official-desktop-local-install.json'
        size = $record.size
        sha256 = $record.sha256
        executableSha256 = [string](Get-MigrationProperty $receipt 'installedExecutableSha256')
    }
}

function Get-MigrationSafeScalarText {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [int] -or $Value -is [int64] -or $Value -is [decimal] -or $Value -is [double]) { return ([string]$Value) }
    $text = [string]$Value
    if ($text -match '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F\r\n]' -or $text.Length -gt $script:MigrationMaxScalar) { throw 'migration-scalar-control-or-size-limit' }
    if ($text -match '^[A-Za-z0-9_./@+:-]+$' -and $text -notmatch '^(?i:true|false|null|~)$') { return $text }
    return "'" + $text.Replace("'", "''") + "'"
}

function Get-MigrationAction {
    param(
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$TargetPath,
        [AllowNull()][string]$SettingPath,
        [AllowNull()][string]$Reason,
        [AllowNull()][int]$Count,
        [AllowNull()][object]$Metadata
    )
    $row = [ordered]@{ category = $Category; action = $Action; status = $Status; sourcePath = $SourcePath.Replace('\', '/'); targetPath = $TargetPath.Replace('\', '/') }
    if ($SettingPath) { $row.settingPath = $SettingPath }
    if ($Reason) { $row.reason = $Reason }
    if ($null -ne $Count) { $row.count = $Count }
    if ($null -ne $Metadata) { $row.metadata = $Metadata }
    return [pscustomobject]$row
}

function Get-MigrationTargetPresetExists {
    param(
        [Parameter(Mandatory)][string]$Preset,
        [Parameter(Mandatory)][string]$DataRoot,
        [Parameter(Mandatory)][hashtable]$Operations
    )
    if ([string]::IsNullOrWhiteSpace($Preset) -or $Preset -match '[\\/]|\.\.') { return $false }
    $targetHome = Get-MigrationTargetHome $DataRoot
    $candidates = @(
        (Join-Path (Join-Path $targetHome 'presets') $Preset),
        (Join-Path (Join-Path $targetHome 'agents') (Join-Path $Preset 'agent.cordis.yml')),
        (Join-Path (Join-Path $targetHome 'profiles\desktop\presets') $Preset),
        (Join-Path (Join-Path $targetHome 'profiles\desktop\agents') (Join-Path $Preset 'agent.cordis.yml'))
    )
    foreach ($candidate in $candidates) {
        if ((& $Operations.PathExists $candidate 'Container') -or (& $Operations.PathExists $candidate 'Leaf')) { return $true }
    }
    return $false
}

function Test-MigrationTargetModel {
    param(
        [Parameter(Mandatory)][object]$TargetSnapshot,
        [Parameter(Mandatory)][string]$Provider,
        [Parameter(Mandatory)][string]$Model
    )
    foreach ($entry in @($TargetSnapshot.modelEntries)) {
        if ([string]$entry.provider -ceq $Provider -and [string]$entry.id -ceq $Model) { return $true }
    }
    return $false
}

function Get-MigrationSettingsActions {
    param(
        [Parameter(Mandatory)][object]$SourceSnapshot,
        [Parameter(Mandatory)][object]$TargetSnapshot,
        [Parameter(Mandatory)][string]$SourceRelativePath,
        [Parameter(Mandatory)][string]$TargetRelativePath,
        [Parameter(Mandatory)][string]$DataRoot,
        [Parameter(Mandatory)][hashtable]$Operations
    )
    $actions = [Collections.Generic.List[object]]::new()
    $safeLeaves = @(
        @('ui-theme', 'preference'), @('ui-theme', 'fontSize'), @('permission', 'defaultPreset')
    )
    foreach ($path in $safeLeaves) {
        $sourceLeaf = Find-MigrationLeaf $SourceSnapshot $path
        if ($null -eq $sourceLeaf) { continue }
        $settingPath = Get-MigrationPathKey $path
        if ($sourceLeaf.isSecret) {
            $actions.Add((Get-MigrationAction 'settings' 'skip-secret' 'not-migrated' $SourceRelativePath $TargetRelativePath $settingPath 'secret-leaf' 1 $null)); continue
        }
        if ($settingPath -ceq 'ui-theme.preference') {
            if ([string]$sourceLeaf.value -notin @('light', 'dark', 'system', 'auto')) {
                $actions.Add((Get-MigrationAction 'settings' 'copy-safe-leaf' 'skipped-invalid' $SourceRelativePath $TargetRelativePath $settingPath 'unsupported-theme-preference' 1 $null)); continue
            }
        }
        if ($settingPath -ceq 'ui-theme.fontSize') {
            $font = 0
            try { $font = [int]$sourceLeaf.value } catch { $font = 0 }
            if ($font -lt 8 -or $font -gt 72) {
                $actions.Add((Get-MigrationAction 'settings' 'copy-safe-leaf' 'skipped-invalid' $SourceRelativePath $TargetRelativePath $settingPath 'invalid-font-size' 1 $null)); continue
            }
        }
        if ($settingPath -ceq 'permission.defaultPreset' -and -not (Get-MigrationTargetPresetExists ([string]$sourceLeaf.value) $DataRoot $Operations)) {
            $actions.Add((Get-MigrationAction 'settings' 'copy-safe-leaf' 'skipped-target-missing' $SourceRelativePath $TargetRelativePath $settingPath 'target-preset-not-found' 1 $null)); continue
        }
        $targetLeaf = Find-MigrationLeaf $TargetSnapshot $path
        if ($null -eq $targetLeaf -or $targetLeaf.isSecret) {
            $actions.Add((Get-MigrationAction 'settings' 'copy-safe-leaf' 'skipped-target-missing' $SourceRelativePath $TargetRelativePath $settingPath 'target-leaf-not-found' 1 $null)); continue
        }
        $status = if ([string]$targetLeaf.value -ceq [string]$sourceLeaf.value) { 'already-matching' } else { 'eligible' }
        $actions.Add((Get-MigrationAction 'settings' 'copy-safe-leaf' $status $SourceRelativePath $TargetRelativePath $settingPath $null 1 $null))
    }

    # Default model is represented by two scalar leaves.  It is only eligible
    # when the exact provider/model already exists in the target model inventory.
    $modelCandidates = @(
        [pscustomobject]@{ ProviderPath = @('agent-default-model', 'provider'); ModelPath = @('agent-default-model', 'model') },
        [pscustomobject]@{ ProviderPath = @('agent', 'defaultModel', 'provider'); ModelPath = @('agent', 'defaultModel', 'model') }
    )
    foreach ($candidate in $modelCandidates) {
        $providerLeaf = Find-MigrationLeaf $SourceSnapshot ([string[]]$candidate.ProviderPath)
        $modelLeaf = Find-MigrationLeaf $SourceSnapshot ([string[]]$candidate.ModelPath)
        if ($null -eq $providerLeaf -or $null -eq $modelLeaf) { continue }
        $provider = [string]$providerLeaf.value; $model = [string]$modelLeaf.value
        $settingPath = Get-MigrationPathKey @($providerLeaf.path)
        if ($providerLeaf.isSecret -or $modelLeaf.isSecret) {
            $actions.Add((Get-MigrationAction 'settings' 'copy-safe-leaf' 'skipped-secret' $SourceRelativePath $TargetRelativePath $settingPath 'secret-default-model-leaf' 1 $null)); continue
        }
        if (-not (Test-MigrationTargetModel $TargetSnapshot $provider $model)) {
            $actions.Add((Get-MigrationAction 'settings' 'copy-safe-leaf' 'skipped-target-missing' $SourceRelativePath $TargetRelativePath $settingPath 'target-provider-model-not-found' 1 $null)); continue
        }
        foreach ($leaf in @($providerLeaf, $modelLeaf)) {
            $targetLeaf = Find-MigrationLeaf $TargetSnapshot @($leaf.path)
            $leafPath = Get-MigrationPathKey @($leaf.path)
            if ($null -eq $targetLeaf) {
                $actions.Add((Get-MigrationAction 'settings' 'copy-safe-leaf' 'skipped-target-missing' $SourceRelativePath $TargetRelativePath $leafPath 'target-leaf-not-found' 1 $null))
            } else {
                $status = if ([string]$targetLeaf.value -ceq [string]$leaf.value) { 'already-matching' } else { 'eligible' }
                $actions.Add((Get-MigrationAction 'settings' 'copy-safe-leaf' $status $SourceRelativePath $TargetRelativePath $leafPath $null 1 $null))
            }
        }
        break
    }

    # Provider route metadata is copied only as existing scalar leaves.  Model
    # arrays are inventory/manual follow-up; headers and secret-looking leaves
    # never become actions containing their values.
    $providerLeaves = @($SourceSnapshot.leaves | Where-Object {
        $_.path.Count -ge 4 -and $_.path[0] -ceq 'llm-pi-ai' -and $_.path[1] -ceq 'providers'
    })
    $providers = @($providerLeaves | ForEach-Object { [string]$_.path[2] } | Sort-Object -Unique)
    foreach ($provider in $providers) {
        $routeLeaves = @($providerLeaves | Where-Object { [string]$_.path[2] -ceq $provider })
        $targetProviderLeaves = @($TargetSnapshot.leaves | Where-Object {
            $_.path.Count -ge 4 -and $_.path[0] -ceq 'llm-pi-ai' -and $_.path[1] -ceq 'providers' -and [string]$_.path[2] -ceq $provider
        })
        $targetProviderExists = $targetProviderLeaves.Count -gt 0 -or @($TargetSnapshot.modelEntries | Where-Object { [string]$_.provider -ceq $provider }).Count -gt 0
        foreach ($leaf in $routeLeaves) {
            $key = [string]$leaf.key
            $settingPath = Get-MigrationPathKey @($leaf.path)
            if ($key -ieq 'headers' -or $leaf.isSecret) {
                $actions.Add((Get-MigrationAction 'settings' 'skip-secret' 'not-migrated' $SourceRelativePath $TargetRelativePath $settingPath 'secret-or-header' 1 $null)); continue
            }
            if ($key -ieq 'models') { continue }
            if ($key -ieq 'baseURL') {
                $actions.Add((Get-MigrationAction 'settings' 'copy-route-metadata' 'requires-explicit-approval' $SourceRelativePath $TargetRelativePath $settingPath 'custom-base-url' 1 $null)); continue
            }
            if ($key -notin @('api', 'apiKeyEnv', 'displayName', 'name', 'type')) { continue }
            if ($key -ieq 'apiKeyEnv' -and [string]$leaf.value -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
                $actions.Add((Get-MigrationAction 'settings' 'copy-route-metadata' 'skipped-invalid' $SourceRelativePath $TargetRelativePath $settingPath 'invalid-api-key-env-reference' 1 $null)); continue
            }
            if (-not $targetProviderExists) {
                $actions.Add((Get-MigrationAction 'settings' 'copy-route-metadata' 'skipped-target-missing' $SourceRelativePath $TargetRelativePath $settingPath 'target-provider-not-found' 1 $null)); continue
            }
            $targetLeaf = Find-MigrationLeaf $TargetSnapshot $leaf.path
            if ($null -eq $targetLeaf) {
                $actions.Add((Get-MigrationAction 'settings' 'copy-route-metadata' 'skipped-target-missing' $SourceRelativePath $TargetRelativePath $settingPath 'target-route-leaf-not-found' 1 $null)); continue
            }
            $status = if ([string]$targetLeaf.value -ceq [string]$leaf.value) { 'already-matching' } else { 'eligible' }
            $actions.Add((Get-MigrationAction 'settings' 'copy-route-metadata' $status $SourceRelativePath $TargetRelativePath $settingPath $null 1 $null))
        }
        $models = @($SourceSnapshot.modelEntries | Where-Object { [string]$_.provider -ceq $provider })
        if ($models.Count -gt 0) {
            $targetModels = @($TargetSnapshot.modelEntries | Where-Object { [string]$_.provider -ceq $provider })
            $actions.Add((Get-MigrationAction 'settings' 'inventory-route-models' 'manual-follow-up' $SourceRelativePath $TargetRelativePath ('llm-pi-ai.providers.' + $provider + '.models') 'model-metadata-not-written' $models.Count ([pscustomobject][ordered]@{ targetCount = $targetModels.Count })))
        }
    }

    # Namespace and Copilot authorization are intentionally never copied.
    $pluginLeaves = @($SourceSnapshot.leaves | Where-Object { $_.path.Count -gt 0 -and $_.path[0] -ieq 'plugins' })
    if ($pluginLeaves.Count -gt 0) {
        $actions.Add((Get-MigrationAction 'plugins' 'reauthorize' 'manual-follow-up' $SourceRelativePath $TargetRelativePath 'plugins' 'plugin-namespace-not-copied' $pluginLeaves.Count $null))
    }
    $copilotPresent = @($SourceSnapshot.leaves | Where-Object {
        ($_.path -join '.') -match '(?i)(github-copilot|copilot)'
    }).Count -gt 0
    if ($copilotPresent) {
        $actions.Add((Get-MigrationAction 'credentials' 'reauthorize' 'requires-reauthorization' $SourceRelativePath $TargetRelativePath 'github-copilot' 'interactive-reauthorization-required' 1 $null))
    }
    return @($actions)
}

function Get-MigrationPluginActions {
    param(
        [Parameter(Mandatory)][string]$CommunityRoot,
        [Parameter(Mandatory)][string]$TargetHome,
        [Parameter(Mandatory)][hashtable]$Operations
    )
    $actions = [Collections.Generic.List[object]]::new()
    $profiles = [Collections.Generic.List[object]]::new()
    foreach ($profile in $script:MigrationAllowedProfiles) {
        $manifestPath = Join-Path (Join-Path $CommunityRoot ('profiles\' + $profile)) 'package.json'
        $manifestRelative = 'profiles/' + $profile + '/package.json'
        if (-not (& $Operations.PathExists $manifestPath 'Leaf')) { continue }
        if (Test-MigrationReparseTree $manifestPath $Operations) { throw 'migration-manifest-reparse-point' }
        if ([int64](& $Operations.GetLength $manifestPath) -gt $script:MigrationManifestLimit) { throw 'migration-manifest-too-large' }
        $manifest = $null
        try { $manifest = & $Operations.ReadJson $manifestPath } catch { throw 'migration-manifest-invalid-json' }
        $profiles.Add([pscustomobject][ordered]@{ profile = $profile; present = $true })
        foreach ($section in @('dependencies', 'devDependencies')) {
            $dependencyObject = Get-MigrationProperty $manifest $section
            if ($null -eq $dependencyObject) { continue }
            foreach ($property in @($dependencyObject.PSObject.Properties | Sort-Object Name)) {
                $name = [string]$property.Name
                if (-not $name.StartsWith('@deepseek-ai/', [StringComparison]::Ordinal)) { continue }
                $spec = [string]$property.Value
                $exactSemver = $spec -match '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$'
                $status = 'eligible-manual'
                $action = 'plugin-install-intent'
                $reason = 'registry-exact-version-manual-follow-up'
                if ($name -match '(?i)copilot') {
                    $status = 'requires-reauthorization'; $action = 'reauthorize'; $reason = 'interactive-copilot-authorization-required'
                } elseif (-not $exactSemver) {
                    $status = 'unsupported-registry-source'; $reason = 'registry-exact-semver-required'
                }
                $actions.Add((Get-MigrationAction 'plugins' $action $status $manifestRelative ('profiles/' + $profile + '/package.json') ('dependency.' + $name) $reason 1 ([pscustomobject][ordered]@{ profile = $profile; package = $name; exactVersion = $exactSemver })))
            }
        }
    }
    return [pscustomobject][ordered]@{ actions = @($actions); profiles = @($profiles) }
}

function Get-MigrationUnsupportedActions {
    param(
        [Parameter(Mandatory)][string]$CommunityRoot,
        [Parameter(Mandatory)][string]$DataRoot,
        [Parameter(Mandatory)][hashtable]$Operations
    )
    $rows = [Collections.Generic.List[object]]::new()
    $sourceKnown = @{
        sessions = 'sessions'; workspaces = 'workspaces'; attachments = 'attachments'; cron = 'cron'; feedback = 'feedback'; projection = 'projection'; anonymous = 'anonymous'; node_modules = 'node_modules'; '.store.dat' = '.store.dat'
    }
    $targetHome = Get-MigrationTargetHome $DataRoot
    $targetKnown = @{
        'package-stores' = 'pnpm-store'; caches = 'cache'; node_modules = 'node_modules'; '.store.dat' = '.store.dat'; 'desktop-staging' = 'desktop-staging'; 'desktop-rollback' = 'desktop-rollback'; 'profile-files' = 'profiles'
    }
    foreach ($category in @($sourceKnown.Keys | Sort-Object)) {
        $relative = [string]$sourceKnown[$category]
        $present = [bool](& $Operations.PathExists (Join-Path $CommunityRoot $relative))
        $rows.Add([pscustomobject][ordered]@{ category = $category; action = 'skip-unsupported'; status = 'not-migrated'; sourcePresent = $present; targetPresent = $false; count = [int]$present })
    }
    foreach ($category in @($targetKnown.Keys | Sort-Object)) {
        $relative = [string]$targetKnown[$category]
        $present = [bool](& $Operations.PathExists (Join-Path $targetHome $relative))
        $rows.Add([pscustomobject][ordered]@{ category = $category; action = 'skip-unsupported'; status = 'not-migrated'; sourcePresent = $false; targetPresent = $present; count = [int]$present })
    }
    return @($rows | Sort-Object category, action)
}

function Get-MigrationSchemaFingerprint {
    $shape = [ordered]@{
        schema = $script:MigrationSchemaName
        version = $script:MigrationSchemaVersion
        release = $script:MigrationReleaseVersion
        hostProtocol = $script:MigrationHostProtocolVersion
        safeLeaves = @('ui-theme.preference', 'ui-theme.fontSize', 'permission.defaultPreset', 'agent-default-model', 'llm-pi-ai.providers.route-metadata')
        unsupported = @('sessions', 'workspaces', 'attachments', 'cron', 'feedback', 'projection', 'anonymous', 'node_modules', '.store.dat', 'desktop-staging', 'desktop-rollback', 'profile-files')
    }
    return 'sha256:' + (Get-MigrationSha256Text (ConvertTo-DshOfficialDesktopLocalMigrationCanonicalJson $shape))
}

function Get-MigrationPlanHashInput {
    param([Parameter(Mandatory)][object]$Plan)
    $copy = [ordered]@{}
    foreach ($property in @($Plan.PSObject.Properties)) {
        if ($property.Name -in @('planHash', 'planPath', 'generatedUtc', 'display')) { continue }
        $copy[$property.Name] = $property.Value
    }
    return $copy
}

function Get-MigrationPlanHash {
    param([Parameter(Mandatory)][object]$Plan)
    return 'sha256:' + (Get-MigrationSha256Text (ConvertTo-DshOfficialDesktopLocalMigrationCanonicalJson (Get-MigrationPlanHashInput $Plan)))
}

function Write-DshOfficialDesktopLocalMigrationPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Plan,
        [Parameter(Mandatory)][string]$DataRoot,
        [Parameter(Mandatory)][hashtable]$Operations
    )
    $plansRoot = Join-Path $DataRoot 'migration-plans'
    if (Test-MigrationReparseTree $plansRoot $Operations) { throw 'migration-plan-directory-reparse-point' }
    & $Operations.EnsureDirectory $plansRoot
    $path = Join-Path $plansRoot ('plan-' + ([string]$Plan.planHash).Substring(7) + '.json')
    if (Test-MigrationReparseTree $path $Operations) { throw 'migration-plan-path-reparse-point' }
    $copy = $Plan | ConvertTo-Json -Depth 100
    & $Operations.WriteAtomicText $path $copy
    return $path
}

function New-MigrationOpaqueSnapshot {
    param([Parameter(Mandatory)][object]$Record)
    return [pscustomobject][ordered]@{ exists = [bool]$Record.present; text = ''; newline = "`n"; lines = @(); leaves = @(); modelEntries = @(); secretCount = 0; headerCount = 0; fileHash = $Record.sha256; size = $Record.size }
}

function Get-DshOfficialDesktopLocalMigrationPlan {
    [CmdletBinding()]
    param(
        [Alias('CommunityDshHome')][string]$CommunityRoot = (Join-Path $HOME '.dsh'),
        [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'Programs\DSH Local Build'),
        [string]$DataRoot = (Join-Path $env:LOCALAPPDATA 'DSH Local Build'),
        [Alias('Plan')][switch]$WritePlan,
        [hashtable]$Operations
    )
    $ops = Merge-MigrationOperations $Operations
    $community = Assert-MigrationSafeRoot $CommunityRoot 'community-root' $ops
    $data = Assert-MigrationSafeRoot $DataRoot 'data-root' $ops
    $install = Assert-MigrationSafeRoot $InstallRoot 'install-root' $ops
    Assert-MigrationNoOverlap $community $data $install
    $sourceSettingsPath = Get-MigrationSourceFilePath $community
    $targetSettingsPath = Get-MigrationTargetSettingsPath $data
    $sourceSettingsRecord = Get-MigrationFileRecord $sourceSettingsPath 'settings.yaml' 'settings' $script:MigrationSettingsLimit $ops
    $sourceCredentialPath = Join-Path $community '.credentials.yaml'
    $sourceCredentialRecord = Get-MigrationFileRecord $sourceCredentialPath '.credentials.yaml' 'credentials' $script:MigrationCredentialsLimit $ops
    $targetSettingsRecord = Get-MigrationFileRecord $targetSettingsPath 'harness-home/settings.yaml' 'target-settings' $script:MigrationSettingsLimit $ops
    $parseReasons = [Collections.Generic.List[string]]::new()
    try { $sourceSettings = Get-MigrationYamlSnapshot $sourceSettingsPath 'settings' $script:MigrationSettingsLimit $ops }
    catch { $sourceSettings = New-MigrationOpaqueSnapshot $sourceSettingsRecord; $parseReasons.Add('community-settings-schema-unsupported') }
    try { $targetSettings = Get-MigrationYamlSnapshot $targetSettingsPath 'target-settings' $script:MigrationSettingsLimit $ops }
    catch { $targetSettings = New-MigrationOpaqueSnapshot ([pscustomobject]@{ present = $targetSettingsRecord.present; sha256 = $targetSettingsRecord.sha256; size = $targetSettingsRecord.size }); $parseReasons.Add('target-settings-schema-unsupported') }
    $targetHome = Get-MigrationTargetHome $data
    $release = Get-MigrationTargetReleaseEvidence $data $install $ops
    $receipt = Get-MigrationReceiptEvidence $data $install $ops
    $pluginEvidence = Get-MigrationPluginActions $community $targetHome $ops
    $settingsActions = if ($sourceSettings.exists -and $targetSettings.exists) {
        Get-MigrationSettingsActions $sourceSettings $targetSettings 'settings.yaml' 'harness-home/settings.yaml' $data $ops
    } else { @() }
    $unsupported = Get-MigrationUnsupportedActions $community $data $ops
    $actions = @($settingsActions) + @($pluginEvidence.actions)
    $actions = @($actions | Sort-Object category, sourcePath, targetPath, action, settingPath, status)
    if ($actions.Count -gt $script:MigrationMaxActions -or @($unsupported).Count -gt $script:MigrationMaxActions) { throw 'migration-action-limit' }
    $reasons = [Collections.Generic.List[string]]::new()
    foreach ($parseReason in @($parseReasons)) { $reasons.Add([string]$parseReason) }
    if (-not $sourceSettings.exists) { $reasons.Add('community-settings-missing') }
    if (-not $targetSettings.exists) { $reasons.Add('target-settings-missing') }
    foreach ($reason in @($release.reasons)) { $reasons.Add([string]$reason) }
    $sourceRootLabel = 'community-dsh-home'
    $targetRootLabel = 'target-data-root'
    $summary = [ordered]@{
        eligible = @($actions | Where-Object { $_.status -eq 'eligible' }).Count
        alreadyMatching = @($actions | Where-Object { $_.status -eq 'already-matching' }).Count
        manualFollowUp = @($actions | Where-Object { $_.status -in @('manual-follow-up', 'eligible-manual', 'requires-reauthorization') }).Count
        skipped = @($actions | Where-Object { $_.status -notin @('eligible', 'already-matching') }).Count
        unsupportedCategories = @($unsupported | Where-Object { $_.count -gt 0 }).Count
    }
    $plan = [pscustomobject][ordered]@{
        schemaVersion = $script:MigrationSchemaVersion
        schemaFingerprint = Get-MigrationSchemaFingerprint
        kind = 'official-desktop-local-migration'
        status = $(if ($reasons.Count -eq 0) { 'ready' } else { 'blocked' })
        reasons = @($reasons | Sort-Object -Unique)
        source = [pscustomobject][ordered]@{
            rootLabel = $sourceRootLabel
            settings = $sourceSettingsRecord
            credentials = $sourceCredentialRecord
            profileManifests = @($pluginEvidence.profiles | Sort-Object profile)
        }
        target = [pscustomobject][ordered]@{
            rootLabel = $targetRootLabel
            settings = [pscustomobject][ordered]@{ path = 'harness-home/settings.yaml'; present = $targetSettings.exists; size = $(if ($targetSettings.exists) { $targetSettings.size } else { 0 }); sha256 = $(if ($targetSettings.exists) { $targetSettings.fileHash } else { $null }) }
            release = $release
            installReceipt = $receipt
        }
        actions = $actions
        unsupported = $unsupported
        summary = [pscustomobject]$summary
        planHash = $null
        planPath = $null
    }
    $plan.planHash = Get-MigrationPlanHash $plan
    if ($WritePlan) { $plan.planPath = Write-DshOfficialDesktopLocalMigrationPlan $plan $data $ops }
    return $plan
}

function Get-MigrationProcessState {
    param(
        [Parameter(Mandatory)][string]$CommunityRoot,
        [Parameter(Mandatory)][string]$DataRoot,
        [Parameter(Mandatory)][string]$InstallRoot,
        [Parameter(Mandatory)][hashtable]$Operations
    )
    $local = [Collections.Generic.List[object]]::new()
    $community = [Collections.Generic.List[object]]::new()
    $processState = 'clear'
    try {
        $processes = @(& $Operations.GetProcesses)
        if ($processes.Count -eq 1 -and (Get-MigrationProperty $processes[0] 'unavailable') -eq $true) { $processState = 'unavailable'; $processes = @() }
    } catch { $processState = 'unavailable'; $processes = @() }
    foreach ($process in $processes) {
        $path = [string](Get-MigrationProperty $process 'ExecutablePath')
        $name = [string](Get-MigrationProperty $process 'Name')
        $commandLine = [string](Get-MigrationProperty $process 'CommandLine')
        $isLocal = ($path -and (Test-MigrationPathWithin $path $InstallRoot)) -or ($commandLine -and $commandLine.IndexOf((Get-MigrationPath $DataRoot), [StringComparison]::OrdinalIgnoreCase) -ge 0)
        $isCommunity = ($path -and ((Test-MigrationPathWithin $path $CommunityRoot) -or $path -match '(?i)deepseek-harness|dsh')) -or ($name -match '(?i)deepseek|dsh-host|dsh-desktop')
        if ($isLocal) { $local.Add([pscustomobject]@{ present = $true }) }
        elseif ($isCommunity) { $community.Add([pscustomobject]@{ present = $true }) }
    }
    $sessions = @()
    $sessionState = 'clear'
    try {
        $liveResult = @(& $Operations.GetLiveSessions)
        if ($liveResult.Count -eq 1 -and (Get-MigrationProperty $liveResult[0] 'unavailable') -eq $true) {
            $sessionState = 'unavailable'
        } elseif ($null -eq $liveResult) {
            $sessionState = 'unavailable'
        } else {
            $sessions = @($liveResult)
            if ($sessions.Count -gt 0) { $sessionState = 'present' }
        }
    } catch { $sessionState = 'unavailable' }
    return [pscustomobject][ordered]@{ processState = $processState; localCount = $local.Count; communityCount = $community.Count; sessionState = $sessionState; sessionCount = $sessions.Count }
}

function Get-MigrationReceiptHash {
    param([Parameter(Mandatory)][object]$Receipt)
    $copy = [ordered]@{}
    foreach ($property in @($Receipt.PSObject.Properties)) {
        if ($property.Name -cne 'receiptSha256') { $copy[$property.Name] = $property.Value }
    }
    return Get-MigrationSha256Text (ConvertTo-DshOfficialDesktopLocalMigrationCanonicalJson $copy)
}

function Invoke-DshOfficialDesktopLocalMigration {
    [CmdletBinding()]
    param(
        [ValidateSet('Check', 'Apply')][string]$Action = 'Check',
        [switch]$Apply,
        [switch]$ApplyMigration,
        [string]$AcknowledgeMigrationPlan,
        [Alias('Plan')][switch]$WritePlan,
        [Alias('CommunityDshHome')][string]$CommunityRoot = (Join-Path $HOME '.dsh'),
        [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'Programs\DSH Local Build'),
        [string]$DataRoot = (Join-Path $env:LOCALAPPDATA 'DSH Local Build'),
        [hashtable]$Operations
    )
    if ($Apply -or $ApplyMigration) { $Action = 'Apply' }
    $ops = Merge-MigrationOperations $Operations
    if ($Action -eq 'Check') {
        return Get-DshOfficialDesktopLocalMigrationPlan -CommunityRoot $CommunityRoot -InstallRoot $InstallRoot -DataRoot $DataRoot -WritePlan:$WritePlan -Operations $ops
    }
    if ([string]::IsNullOrWhiteSpace($AcknowledgeMigrationPlan) -or $AcknowledgeMigrationPlan -notmatch '^sha256:[0-9a-fA-F]{64}$') {
        throw 'migration-plan-acknowledgment-required'
    }
    $plan = Get-DshOfficialDesktopLocalMigrationPlan -CommunityRoot $CommunityRoot -InstallRoot $InstallRoot -DataRoot $DataRoot -Operations $ops
    if ([string]$plan.planHash -cne $AcknowledgeMigrationPlan.ToLowerInvariant()) { throw 'migration-plan-stale' }
    if ($plan.status -ne 'ready') { throw ('migration-target-not-ready:' + (($plan.reasons -join ',') -replace '[\r\n]', '')) }
    if (-not $plan.target.installReceipt.valid) { throw 'migration-installed-receipt-required' }
    $processState = Get-MigrationProcessState (Get-MigrationPath $CommunityRoot) (Get-MigrationPath $DataRoot) (Get-MigrationPath $InstallRoot) $ops
    if ($processState.processState -eq 'unavailable') { throw 'migration-process-state-unavailable' }
    if ($processState.localCount -gt 0 -or $processState.communityCount -gt 0) { throw 'migration-process-running' }
    if ($processState.sessionState -eq 'unavailable') { throw 'migration-live-session-state-unavailable' }
    if ($processState.sessionCount -gt 0) { throw 'migration-live-sessions-present' }
    $eligible = @($plan.actions | Where-Object { $_.status -eq 'eligible' -and $_.action -in @('copy-safe-leaf', 'copy-route-metadata') })
    if ($eligible.Count -eq 0) {
        return [pscustomobject][ordered]@{ schemaVersion = $script:MigrationSchemaVersion; action = 'apply'; status = 'noop'; mutated = $false; planHash = $plan.planHash; eligibleActions = 0; backup = $null; receiptPath = $null; stoppedProcesses = $false }
    }

    $sourceSettingsPath = Get-MigrationSourceFilePath (Get-MigrationPath $CommunityRoot)
    $targetSettingsPath = Get-MigrationTargetSettingsPath (Get-MigrationPath $DataRoot)
    $beforeSourceHash = [string]$plan.source.settings.sha256
    $beforeCredentialHash = [string]$plan.source.credentials.sha256
    $beforeSourceHashNow = if (& $ops.PathExists $sourceSettingsPath 'Leaf') { 'sha256:' + ([string](& $ops.GetHash $sourceSettingsPath)).ToLowerInvariant() } else { $null }
    if ($beforeSourceHash -ne $beforeSourceHashNow) { throw 'migration-source-changed-before-write' }
    if ($beforeCredentialHash) {
        $nowCredentialHash = if (& $ops.PathExists (Join-Path (Get-MigrationPath $CommunityRoot) '.credentials.yaml') 'Leaf') { 'sha256:' + ([string](& $ops.GetHash (Join-Path (Get-MigrationPath $CommunityRoot) '.credentials.yaml'))).ToLowerInvariant() } else { $null }
        if ($beforeCredentialHash -ne $nowCredentialHash) { throw 'migration-source-changed-before-write' }
    } elseif (& $ops.PathExists (Join-Path (Get-MigrationPath $CommunityRoot) '.credentials.yaml') 'Leaf') {
        throw 'migration-source-changed-before-write'
    }
    $targetHashBeforeBackup = if (& $ops.PathExists $targetSettingsPath 'Leaf') { 'sha256:' + ([string](& $ops.GetHash $targetSettingsPath)).ToLowerInvariant() } else { $null }
    if ([string]$plan.target.settings.sha256 -cne $targetHashBeforeBackup) { throw 'migration-target-changed-before-write' }

    $operationId = ([string](& $ops.GetUtcNow).ToString('yyyyMMddTHHmmssfffffffZ')) + '-' + ([string](& $ops.NewGuid).ToString('N'))
    $backupRoot = Join-Path (Join-Path (Get-MigrationPath $DataRoot) 'migration-backups') $operationId
    if (Test-MigrationReparseTree $backupRoot $ops) { throw 'migration-backup-reparse-point' }
    & $ops.EnsureDirectory $backupRoot
    $backupRows = [Collections.Generic.List[object]]::new()
    if (-not (& $ops.PathExists $targetSettingsPath 'Leaf')) { throw 'migration-target-settings-missing-before-backup' }
    if (Test-MigrationReparseTree $targetSettingsPath $ops) { throw 'migration-target-settings-reparse-point' }
    $backupSettingsPath = Join-Path $backupRoot 'harness-home-settings.yaml'
    & $ops.CopyFile $targetSettingsPath $backupSettingsPath
    $backupRows.Add([pscustomobject][ordered]@{ source = 'harness-home/settings.yaml'; backup = 'harness-home-settings.yaml'; sha256 = ('sha256:' + ([string](& $ops.GetHash $backupSettingsPath)).ToLowerInvariant()); size = [int64](& $ops.GetLength $backupSettingsPath) })
    $migrationReceiptPath = Join-Path (Get-MigrationPath $DataRoot) 'migration-receipt.json'
    $existingMigrationReceiptHash = $null
    if (& $ops.PathExists $migrationReceiptPath 'Leaf') {
        if (Test-MigrationReparseTree $migrationReceiptPath $ops -or [int64](& $ops.GetLength $migrationReceiptPath) -gt $script:MigrationManifestLimit) { throw 'migration-receipt-unsafe' }
        $existingMigrationReceiptHash = 'sha256:' + ([string](& $ops.GetHash $migrationReceiptPath)).ToLowerInvariant()
        $backupReceiptPath = Join-Path $backupRoot 'migration-receipt.json'
        & $ops.CopyFile $migrationReceiptPath $backupReceiptPath
        $backupRows.Add([pscustomobject][ordered]@{ source = 'migration-receipt.json'; backup = 'migration-receipt.json'; sha256 = ('sha256:' + ([string](& $ops.GetHash $backupReceiptPath)).ToLowerInvariant()); size = [int64](& $ops.GetLength $backupReceiptPath) })
    }
    $backupManifest = [pscustomobject][ordered]@{ schemaVersion = 1; operationId = $operationId; files = @($backupRows) }
    $backupManifestPath = Join-Path $backupRoot 'manifest.json'
    & $ops.WriteAtomicText $backupManifestPath ($backupManifest | ConvertTo-Json -Depth 20)

    $sourceSnapshot = Get-MigrationYamlSnapshot $sourceSettingsPath 'settings' $script:MigrationSettingsLimit $ops
    $targetSnapshot = Get-MigrationYamlSnapshot $targetSettingsPath 'target-settings' $script:MigrationSettingsLimit $ops
    $lines = @($targetSnapshot.lines)
    $updated = $false
    $resultActions = [Collections.Generic.List[object]]::new()
    foreach ($action in $eligible) {
        $pathParts = ([string]$action.settingPath).Split('.')
        $sourceLeaf = Find-MigrationLeaf $sourceSnapshot $pathParts
        $targetLeaf = Find-MigrationLeaf $targetSnapshot $pathParts
        if ($null -eq $sourceLeaf -or $null -eq $targetLeaf -or $sourceLeaf.isSecret -or $targetLeaf.isSecret) { throw 'migration-safe-leaf-disappeared' }
        $lineIndex = [int]$targetLeaf.lineIndex
        $targetLine = [string]$lines[$lineIndex]
        $colon = Find-MigrationColon ($targetLine.TrimStart(' '))
        if ($colon -lt 0) { throw 'migration-target-leaf-line-invalid' }
        $leading = $targetLine.Substring(0, $targetLine.Length - $targetLine.TrimStart(' ').Length)
        $keyText = $targetLine.TrimStart(' ').Substring(0, $colon + 1)
        # Do not copy inline comments: a `#` inside a quoted scalar is data, and
        # re-emitting it without a full YAML lexer could change the document.
        $comment = ''
        $newLine = $leading + $keyText + ' ' + (Get-MigrationSafeScalarText $sourceLeaf.value)
        if ($newLine -cne $targetLine) { $lines[$lineIndex] = $newLine; $updated = $true }
        $resultActions.Add([pscustomobject][ordered]@{ category = [string]$action.category; action = [string]$action.action; status = 'applied'; settingPath = [string]$action.settingPath })
    }
    if (-not $updated) {
        return [pscustomobject][ordered]@{ schemaVersion = $script:MigrationSchemaVersion; action = 'apply'; status = 'noop'; mutated = $false; planHash = $plan.planHash; eligibleActions = $eligible.Count; backup = $backupRoot; receiptPath = $null; stoppedProcesses = $false }
    }
    $targetHashBeforeWrite = if (& $ops.PathExists $targetSettingsPath 'Leaf') { 'sha256:' + ([string](& $ops.GetHash $targetSettingsPath)).ToLowerInvariant() } else { $null }
    if ([string]$plan.target.settings.sha256 -cne $targetHashBeforeWrite) { throw 'migration-target-changed-before-write' }
    $lateProcessState = Get-MigrationProcessState (Get-MigrationPath $CommunityRoot) (Get-MigrationPath $DataRoot) (Get-MigrationPath $InstallRoot) $ops
    if ($lateProcessState.processState -eq 'unavailable') { throw 'migration-process-state-unavailable' }
    if ($lateProcessState.localCount -gt 0 -or $lateProcessState.communityCount -gt 0) { throw 'migration-process-running' }
    if ($lateProcessState.sessionState -eq 'unavailable') { throw 'migration-live-session-state-unavailable' }
    if ($lateProcessState.sessionCount -gt 0) { throw 'migration-live-sessions-present' }
    $newText = $lines -join $targetSnapshot.newline
    $targetWriteStarted = $false
    $producedTargetHash = $null
    try {
        $targetWriteStarted = $true
        & $ops.WriteAtomicText $targetSettingsPath $newText
        $producedTargetHash = if (& $ops.PathExists $targetSettingsPath 'Leaf') { 'sha256:' + ([string](& $ops.GetHash $targetSettingsPath)).ToLowerInvariant() } else { $null }
        $verifiedTarget = Get-MigrationYamlSnapshot $targetSettingsPath 'target-settings' $script:MigrationSettingsLimit $ops
        foreach ($action in $eligible) {
            $pathParts = ([string]$action.settingPath).Split('.')
            $sourceLeaf = Find-MigrationLeaf $sourceSnapshot $pathParts
            $targetLeaf = Find-MigrationLeaf $verifiedTarget $pathParts
            if ($null -eq $targetLeaf -or [string]$targetLeaf.value -cne [string]$sourceLeaf.value) { throw 'migration-post-write-verification-failed' }
        }
        $afterSourceHash = if (& $ops.PathExists $sourceSettingsPath 'Leaf') { 'sha256:' + ([string](& $ops.GetHash $sourceSettingsPath)).ToLowerInvariant() } else { $null }
        if ($beforeSourceHash -ne $afterSourceHash) { throw 'migration-source-changed-after-write' }
        $receipt = [pscustomobject][ordered]@{
            schemaVersion = $script:MigrationSchemaVersion
            status = 'complete'
            operationId = $operationId
            planHash = $plan.planHash
            actionStatuses = @($resultActions | Sort-Object category, action, settingPath)
            backup = [pscustomobject][ordered]@{ relativePath = 'migration-backups/' + $operationId; manifest = 'manifest.json'; files = @($backupRows) }
            target = [pscustomobject][ordered]@{ settingsPath = 'harness-home/settings.yaml'; settingsSha256 = $producedTargetHash }
            receiptSha256 = $null
        }
        $receipt.receiptSha256 = Get-MigrationReceiptHash $receipt
        $receiptPath = $migrationReceiptPath
        if ($existingMigrationReceiptHash) {
            $currentMigrationReceiptHash = if (& $ops.PathExists $receiptPath 'Leaf') { 'sha256:' + ([string](& $ops.GetHash $receiptPath)).ToLowerInvariant() } else { $null }
            if ($currentMigrationReceiptHash -cne $existingMigrationReceiptHash) { throw 'migration-receipt-changed-before-write' }
        }
        & $ops.WriteAtomicText $receiptPath ($receipt | ConvertTo-Json -Depth 40)
        return [pscustomobject][ordered]@{ schemaVersion = $script:MigrationSchemaVersion; action = 'apply'; status = 'complete'; mutated = $true; planHash = $plan.planHash; eligibleActions = $eligible.Count; backup = $backupRoot; receiptPath = $receiptPath; receipt = $receipt; stoppedProcesses = $false }
    } catch {
        $failure = $_.Exception.Message
        if (-not $targetWriteStarted) { throw }
        $restored = $false
        try {
            $currentHash = if (& $ops.PathExists $targetSettingsPath 'Leaf') { 'sha256:' + ([string](& $ops.GetHash $targetSettingsPath)).ToLowerInvariant() } else { $null }
            if ($currentHash -eq $producedTargetHash -or $currentHash -eq $targetHashBeforeWrite) {
                if ($currentHash -ne $targetHashBeforeWrite) {
                    $backupText = & $ops.ReadText $backupSettingsPath
                    & $ops.WriteAtomicText $targetSettingsPath $backupText
                }
                $restored = $true
            }
        } catch { $restored = $false }
        if ($restored) { throw ("migration-write-rolled-back: $failure; backup=$backupRoot") }
        throw ("migration-partial-manual-review-required: $failure; backup=$backupRoot")
    }
}

Export-ModuleMember -Function Get-DshOfficialDesktopLocalMigrationOperations, ConvertTo-DshOfficialDesktopLocalMigrationCanonicalJson, Get-DshOfficialDesktopLocalMigrationPlan, Write-DshOfficialDesktopLocalMigrationPlan, Invoke-DshOfficialDesktopLocalMigration
