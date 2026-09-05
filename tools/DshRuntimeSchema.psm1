Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RuntimeSchemaPath {
    param([Parameter(Mandatory)][string]$Path)
    return [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path)).TrimEnd('\')
}

function Get-RuntimeSchemaSha256 {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-RuntimeSchemaTreeState {
    param([Parameter(Mandatory)][string]$Path)
    $root = (Resolve-RuntimeSchemaPath $Path).TrimEnd('\') + '\'
    $reparseEntries = @(Get-ChildItem -LiteralPath $root -Recurse -Force |
        Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
    $entries = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force | ForEach-Object {
        [pscustomobject]@{
            relativePath = $_.FullName.Substring($root.Length).Replace('\', '/')
            sha256 = Get-RuntimeSchemaSha256 -Path $_.FullName
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
        reparseDirectoryCount = $reparseEntries.Count
    }
}

function Test-RuntimeSchemaPhysicalPath {
    param([Parameter(Mandatory)][string]$Path)
    $current = Get-Item -LiteralPath $Path -Force
    while ($current) {
        if ($current.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
        if (-not $current.Parent) { break }
        $current = $current.Parent
    }
    return $true
}

function Split-DshRuntimeCommandLine {
    param([string]$CommandLine)
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return @() }
    return @([regex]::Matches($CommandLine, '"(?<quoted>[^"]*)"|(?<bare>[^\s"]+)') |
        ForEach-Object {
            if ($_.Groups['quoted'].Success) { $_.Groups['quoted'].Value }
            else { $_.Groups['bare'].Value }
        })
}

function Test-DshRuntimeProcessBinding {
    param(
        [Parameter(Mandatory)][string]$Entrypoint,
        [int[]]$ProcessIds
    )
    $ids = @($ProcessIds | Where-Object { $null -ne $_ })
    if ($ids.Count -eq 0) {
        return [pscustomobject]@{ valid = $true; status = 'not-requested'; processIds = @() }
    }
    $expected = Resolve-RuntimeSchemaPath $Entrypoint
    $states = @($ids | ForEach-Object {
        $processId = [int]$_
        try {
            $process = Get-CimInstance Win32_Process -Filter "ProcessId=$processId" -ErrorAction Stop
            $arguments = @(Split-DshRuntimeCommandLine -CommandLine ([string]$process.CommandLine))
            $entry = if ($arguments.Count -ge 2 -and [IO.Path]::IsPathRooted($arguments[1])) {
                Resolve-RuntimeSchemaPath ([string]$arguments[1])
            } else {
                $null
            }
            [pscustomobject]@{
                processId = $processId
                valid = [bool](
                    [string]$process.Name -match '^node(?:\.exe)?$' -and
                    $entry -and $entry -ieq $expected
                )
            }
        } catch {
            [pscustomobject]@{ processId = $processId; valid = $false }
        }
    })
    return [pscustomobject]@{
        valid = @($states | Where-Object { -not $_.valid }).Count -eq 0
        status = if (@($states | Where-Object { -not $_.valid }).Count -eq 0) {
            'bound'
        } else {
            'process-entrypoint-mismatch'
        }
        processIds = @($ids)
    }
}

function Test-DshRuntimeSchemaState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Contract,
        [string]$RequiredPackageRoot,
        [int[]]$RequiredProcessIds
    )

    $reasons = [Collections.Generic.List[string]]::new()
    $root = Resolve-RuntimeSchemaPath ([string]$Contract.root)
    $packageRoot = Join-Path $root 'node_modules\@deepseek-ai\dsh'
    if ($RequiredPackageRoot -and
        (Resolve-RuntimeSchemaPath $RequiredPackageRoot) -ine (Resolve-RuntimeSchemaPath $packageRoot)) {
        [void]$reasons.Add('runtime-package-root-mismatch')
    }

    $wrapperManifestPath = Join-Path $root ([string]$Contract.wrapper.manifest)
    $packageManifestPath = Join-Path $root ([string]$Contract.package.manifest)
    $entrypoint = Join-Path $root ([string]$Contract.package.entrypoint)
    foreach ($requiredPath in @($root, $packageRoot, $wrapperManifestPath, $packageManifestPath, $entrypoint)) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            [void]$reasons.Add('runtime-path-missing')
        }
    }

    $physical = $false
    $wrapper = $null
    $package = $null
    $wrapperTree = $null
    if ($reasons.Count -eq 0) {
        try {
            $physical = (Test-RuntimeSchemaPhysicalPath -Path $root) -and
                (Test-RuntimeSchemaPhysicalPath -Path $packageRoot)
            if (-not $physical) { [void]$reasons.Add('runtime-reparse-point') }
            $wrapperTree = Get-RuntimeSchemaTreeState -Path $root
            if ([int]$wrapperTree.reparseDirectoryCount -ne [int]$Contract.wrapper.reparseDirectoryCount -or
                [int]$wrapperTree.fileCount -ne [int]$Contract.wrapper.fileCount -or
                [int64]$wrapperTree.totalBytes -ne [int64]$Contract.wrapper.totalBytes -or
                [string]$wrapperTree.treeSha256 -cne [string]$Contract.wrapper.treeSha256) {
                [void]$reasons.Add('runtime-wrapper-tree-mismatch')
            }
            $wrapper = Get-Content -LiteralPath $wrapperManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $package = Get-Content -LiteralPath $packageManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ([string]$wrapper.name -cne [string]$Contract.wrapper.name -or
                [string]$wrapper.version -cne [string]$Contract.wrapper.version -or
                (Get-RuntimeSchemaSha256 -Path $wrapperManifestPath) -cne
                    [string]$Contract.wrapper.manifestSha256) {
                [void]$reasons.Add('runtime-wrapper-identity-mismatch')
            }
            if ([string]$package.name -cne [string]$Contract.package.name -or
                [string]$package.version -cne [string]$Contract.package.version -or
                [string]$package.bin.dsh -cne 'lib/bin.js') {
                [void]$reasons.Add('runtime-package-identity-mismatch')
            }
        } catch {
            [void]$reasons.Add('runtime-manifest-invalid')
        }
    }

    $fileStates = @($Contract.requiredBuiltFiles | ForEach-Object {
        $relativePath = [string]$_.path
        $path = Join-Path $root $relativePath
        $exists = Test-Path -LiteralPath $path -PathType Leaf
        $size = if ($exists) { (Get-Item -LiteralPath $path).Length } else { $null }
        $sha256 = if ($exists) { Get-RuntimeSchemaSha256 -Path $path } else { $null }
        [pscustomobject]@{
            path = $relativePath
            exists = $exists
            size = $size
            sha256 = $sha256
            valid = [bool](
                $exists -and [int64]$size -eq [int64]$_.size -and
                [string]$sha256 -ceq [string]$_.sha256
            )
        }
    })
    if (@($fileStates | Where-Object { -not $_.valid }).Count -gt 0) {
        [void]$reasons.Add('runtime-schema-bytes-mismatch')
    }

    $entrypointState = [pscustomobject]@{
        path = $entrypoint
        size = if (Test-Path -LiteralPath $entrypoint -PathType Leaf) {
            (Get-Item -LiteralPath $entrypoint).Length
        } else { $null }
        sha256 = if (Test-Path -LiteralPath $entrypoint -PathType Leaf) {
            Get-RuntimeSchemaSha256 -Path $entrypoint
        } else { $null }
    }
    $entrypointState | Add-Member -NotePropertyName valid -NotePropertyValue ([bool](
        [int64]$entrypointState.size -eq [int64]$Contract.package.entrypointSize -and
        [string]$entrypointState.sha256 -ceq [string]$Contract.package.entrypointSha256
    ))
    if (-not $entrypointState.valid) { [void]$reasons.Add('runtime-entrypoint-bytes-mismatch') }

    $process = Test-DshRuntimeProcessBinding -Entrypoint $entrypoint -ProcessIds $RequiredProcessIds
    if (-not $process.valid) { [void]$reasons.Add([string]$process.status) }

    $valid = $reasons.Count -eq 0
    return [pscustomobject]@{
        valid = $valid
        status = if ($valid) { 'desktop-official-runtime-schema-verified' } else { 'desktop-official-runtime-schema-invalid' }
        root = $root
        packageRoot = $packageRoot
        entrypoint = $entrypointState
        wrapperTree = $wrapperTree
        files = @($fileStates)
        process = $process
        reasons = @($reasons)
    }
}

Export-ModuleMember -Function @(
    'Test-DshRuntimeSchemaState'
)
