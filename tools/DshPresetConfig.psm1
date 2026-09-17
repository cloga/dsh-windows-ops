Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'DshRuntimeSchema.psm1')

function New-PresetConfigFailure {
    param([string]$Code)
    [pscustomobject]@{
        valid = $false
        status = 'user-preset-config-blocked'
        diagnostics = @([pscustomobject]@{
            preset = ''; row = ''; plugin = ''; version = ''; key = ''
            code = $Code; action = 'Review the preset and exact target artifacts before retrying; do not overwrite user instructions.'
        })
    }
}

function Assert-PresetPhysicalPath {
    param([string]$Path)
    if ($Path -notmatch '^[A-Za-z]:[\\/]') { throw 'scope' }
    $cursor = [IO.Path]::GetFullPath($Path)
    if ($cursor.TrimEnd('\') -eq [IO.Path]::GetPathRoot($cursor).TrimEnd('\')) { throw 'scope' }
    while ($cursor) {
        try { $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop }
        catch [System.Management.Automation.ItemNotFoundException] { $item = $null }
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'scope' }
        $parent = [IO.Directory]::GetParent($cursor)
        if (-not $parent) { break }
        $cursor = $parent.FullName
    }
}

function Get-PresetTargetFiles {
    param([string]$Root)
    $pending = [Collections.Generic.Stack[string]]::new()
    $pending.Push($Root)
    $files = [Collections.Generic.List[object]]::new()
    $directories = 0
    $bytes = [int64]0
    while ($pending.Count) {
        $directory = $pending.Pop()
        if (++$directories -gt 40000) { throw 'limit' }
        foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force)) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'scope' }
            if ($item.PSIsContainer) {
                $pending.Push($item.FullName)
            } else {
                $bytes += $item.Length
                if ($files.Count -ge 30000 -or $bytes -gt 1GB) { throw 'limit' }
                $files.Add([pscustomobject]@{
                    path = $item.FullName.Substring($Root.Length + 1).Replace('\', '/')
                    sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                    size = $item.Length
                })
            }
        }
    }
    return @($files | Sort-Object path)
}

function Test-DshUserPresetConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DshHome,
        [Parameter(Mandatory)]$Contract,
        [ValidateRange(1, 60)][int]$TimeoutSeconds = 20
    )
    try {
        $homePath = [Environment]::ExpandEnvironmentVariables($DshHome)
        Assert-PresetPhysicalPath $homePath
        $homePath = [IO.Path]::GetFullPath($homePath).TrimEnd('\')
        if ((Test-Path -LiteralPath $homePath) -and
            -not (Test-Path -LiteralPath $homePath -PathType Container)) { throw 'scope' }
        $presetRoot = Join-Path $homePath '.agent-presets'
        Assert-PresetPhysicalPath $presetRoot
        $manifests = [Collections.Generic.List[object]]::new()
        $totalBytes = 0
        if (Test-Path -LiteralPath $presetRoot) {
            if (-not (Test-Path -LiteralPath $presetRoot -PathType Container)) { throw 'scope' }
            foreach ($directory in @(Get-ChildItem -LiteralPath $presetRoot -Force)) {
                if ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'scope' }
                if (-not $directory.PSIsContainer) { continue }
                # The published user roster discovers direct child directories only.
                $path = Join-Path $directory.FullName 'agent.cordis.yml'
                Assert-PresetPhysicalPath $path
                if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                    return New-PresetConfigFailure 'preset-manifest-missing'
                }
                $size = (Get-Item -LiteralPath $path).Length
                $totalBytes += $size
                if ($size -gt 1MB -or $totalBytes -gt 8MB -or $manifests.Count -ge 128) {
                    return New-PresetConfigFailure 'preset-scope-limit'
                }
                $manifests.Add([pscustomobject]@{
                    path = $path
                    relative = '.agent-presets/' + $directory.Name + '/agent.cordis.yml'
                    sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
                })
            }
        }
    } catch {
        return New-PresetConfigFailure 'preset-scope-invalid'
    }
    if (-not $manifests.Count) {
        return [pscustomobject]@{ valid = $true; status = 'no-user-presets'; diagnostics = @(); rows = @() }
    }

    try {
        $root = [Environment]::ExpandEnvironmentVariables([string]$Contract.root)
        $canonicalRoot = [IO.Path]::GetFullPath($root).TrimEnd('\')
        # ASAR virtual paths are not physical wrappers; do not walk or import the target.
        if ($canonicalRoot -match '(^|[\\/])[^\\/]*\.asar([\\/]|$)') {
            return New-PresetConfigFailure 'unsupported-asar-target-validation'
        }
        Assert-PresetPhysicalPath $root
        $root = $canonicalRoot
        if (-not (Test-Path -LiteralPath $root -PathType Container)) {
            return New-PresetConfigFailure 'target-artifacts-unavailable'
        }
        foreach ($relative in @(
            $Contract.wrapper.manifest, $Contract.package.manifest, $Contract.package.entrypoint
        ) + @($Contract.requiredBuiltFiles | ForEach-Object { $_.path })) {
            if ([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)') {
                throw 'target'
            }
        }
        # Inspect without following links before using the existing whole-wrapper attestation.
        $files = @(Get-PresetTargetFiles $root)
        $state = Test-DshRuntimeSchemaState -Contract $Contract
        if (-not $state.valid) { return New-PresetConfigFailure 'target-artifacts-unverified' }
        $text = ($files | ForEach-Object { $_.path + "`t" + $_.sha256 }) -join "`n"
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            $fingerprint = [BitConverter]::ToString(
                $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))
            ).Replace('-', '').ToLowerInvariant()
        } finally { $sha.Dispose() }
        if ($fingerprint -cne [string]$Contract.wrapper.treeSha256) {
            return New-PresetConfigFailure 'target-artifacts-unverified'
        }
        $request = @{
            root = $root
            entrypoint = [string]$Contract.package.entrypoint
            files = $files
            manifests = @($manifests)
            timeoutMs = $TimeoutSeconds * 1000
        } | ConvertTo-Json -Depth 12 -Compress
    } catch {
        return New-PresetConfigFailure 'target-artifacts-unverified'
    }

    $process = $null
    try {
        $node = (Get-Command node.exe -CommandType Application -ErrorAction Stop).Source
        $start = [Diagnostics.ProcessStartInfo]::new()
        $start.FileName = $node
        $start.Arguments = '--max-old-space-size=192 "' + (Join-Path $PSScriptRoot 'dsh-preset-config.mjs') + '"'
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardInput = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $start.StandardOutputEncoding = [Text.Encoding]::UTF8
        $start.StandardErrorEncoding = [Text.Encoding]::UTF8
        $start.EnvironmentVariables.Clear()
        foreach ($name in @('SystemRoot', 'WINDIR')) {
            if ([Environment]::GetEnvironmentVariable($name)) {
                $start.EnvironmentVariables[$name] = [Environment]::GetEnvironmentVariable($name)
            }
        }
        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $start
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $inputBytes = [Text.Encoding]::UTF8.GetBytes($request)
        $process.StandardInput.BaseStream.Write($inputBytes, 0, $inputBytes.Length)
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(($TimeoutSeconds + 15) * 1000)) {
            # Only this invocation's validator process tree; never Desktop or a Host.
            & taskkill.exe /PID $process.Id /T /F 2>&1 | Out-Null
            return New-PresetConfigFailure 'validator-timeout'
        }
        $output = $stdout.GetAwaiter().GetResult()
        [void]$stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0 -or $output.Length -gt 262144) {
            return New-PresetConfigFailure 'validator-process-failed'
        }
        $result = $output | ConvertFrom-Json
        if ($result.valid -isnot [bool] -or
            $result.status -notin @('user-preset-config-verified', 'user-preset-config-blocked')) {
            return New-PresetConfigFailure 'validator-protocol-invalid'
        }
        return $result
    } catch {
        return New-PresetConfigFailure 'validator-process-failed'
    } finally {
        if ($process) { $process.Dispose() }
    }
}

Export-ModuleMember -Function 'Test-DshUserPresetConfig'
