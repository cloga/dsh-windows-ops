Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RuntimeSchemaProperty {
    param(
        [Parameter(Mandatory)]$InputObject,
        [Parameter(Mandatory)][string]$Name
    )
    if ($InputObject -is [Collections.IDictionary]) { return $InputObject[$Name] }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Resolve-RuntimeSchemaFullPath {
    param([Parameter(Mandatory)][string]$Path)
    return [IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Get-DshRuntimeCommandDiscovery {
    $seen = @{}
    return @(Get-Command dsh -All -ErrorAction SilentlyContinue | ForEach-Object {
        $sourceProperty = $_.PSObject.Properties['Source']
        $pathProperty = $_.PSObject.Properties['Path']
        $source = if ($sourceProperty) { [string]$sourceProperty.Value } else { $null }
        $path = if ($source) {
            $source
        } elseif ($pathProperty) {
            [string]$pathProperty.Value
        } else {
            $null
        }
        $identity = if ($path) { $path } else { "$($_.CommandType):$($_.Name)" }
        if (-not $seen.ContainsKey($identity)) {
            $seen[$identity] = $true
            [pscustomobject]@{
                commandType = [string]$_.CommandType
                name = [string]$_.Name
                path = if ($path) { Resolve-RuntimeSchemaFullPath $path } else { $null }
                identity = $identity
            }
        }
    })
}

function Get-DshRuntimeCommandPaths {
    [CmdletBinding()]
    param()
    return @(Get-DshRuntimeCommandDiscovery | Where-Object path | ForEach-Object path)
}

function Resolve-DshRuntimePackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CommandPath
    )

    $command = Resolve-RuntimeSchemaFullPath $CommandPath
    $candidates = [Collections.Generic.List[string]]::new()
    $commandRoot = Split-Path -Parent $command
    $candidates.Add((Join-Path $commandRoot 'node_modules\@deepseek-ai\dsh'))
    if ((Split-Path -Leaf $commandRoot) -eq '.bin') {
        $candidates.Add((Join-Path (Split-Path -Parent $commandRoot) '@deepseek-ai\dsh'))
    }
    if (Test-Path -LiteralPath $command -PathType Leaf) {
        $content = Get-Content -LiteralPath $command -Raw -Encoding UTF8
        $matches = [regex]::Matches(
            $content,
            '(?i)(?<entry>[A-Z]:[^\r\n''"]*?node_modules[\\/]@deepseek-ai[\\/]dsh[\\/]lib[\\/]bin\.js)'
        )
        foreach ($match in $matches) {
            $entry = [string]$match.Groups['entry'].Value
            $candidates.Add((Split-Path -Parent (Split-Path -Parent $entry)))
        }
    }

    $resolvedRoot = $null
    foreach ($candidate in @($candidates)) {
        $manifest = Join-Path $candidate 'package.json'
        $entrypoint = Join-Path $candidate 'lib\bin.js'
        if ((Test-Path -LiteralPath $manifest -PathType Leaf) -and
            (Test-Path -LiteralPath $entrypoint -PathType Leaf)) {
            $resolvedRoot = Resolve-RuntimeSchemaFullPath $candidate
            break
        }
    }
    if (-not $resolvedRoot) {
        return [pscustomobject]@{
            valid = $false
            status = 'active-package-unresolved'
            commandPath = $command
        }
    }

    $item = Get-Item -LiteralPath $resolvedRoot -Force
    $target = $null
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        $targetValue = @($item.Target | Select-Object -First 1)
        if ($targetValue.Count -eq 1 -and $targetValue[0]) {
            $target = [string]$targetValue[0]
            if (-not [IO.Path]::IsPathRooted($target)) {
                $target = Join-Path (Split-Path -Parent $resolvedRoot) $target
            }
            $target = Resolve-RuntimeSchemaFullPath $target
        }
    }
    $manifestObject = Get-Content -LiteralPath (Join-Path $resolvedRoot 'package.json') -Raw -Encoding UTF8 |
        ConvertFrom-Json
    return [pscustomobject]@{
        valid = $true
        status = 'resolved'
        commandPath = $command
        packageRoot = $resolvedRoot
        packageTarget = $target
        linked = [bool]$target
        name = [string]$manifestObject.name
        version = [string]$manifestObject.version
        entrypoint = Join-Path $resolvedRoot 'lib\bin.js'
    }
}

function Find-DshRuntimeSourceRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StartPath)

    $current = Resolve-RuntimeSchemaFullPath $StartPath
    while ($current) {
        if (Test-Path -LiteralPath (Join-Path $current '.git')) { return $current }
        $parent = Split-Path -Parent $current
        if (-not $parent -or $parent -eq $current) { break }
        $current = $parent
    }
    return $null
}

function Invoke-RuntimeSchemaGit {
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string[]]$Arguments
    )
    $output = @(& git -C $SourceRoot @Arguments 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed." }
    return ($output -join "`n").Trim()
}

function Get-DshFreshProcessVersion {
    param([Parameter(Mandatory)][string]$Entrypoint)
    $output = @(& node $Entrypoint --version 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'The active DSH entrypoint failed in a fresh Node process.' }
    return ($output -join "`n").Trim()
}

function Get-DshRuntimeEvidenceBinding {
    param(
        [Parameter(Mandatory)][string]$CommandPath,
        [Parameter(Mandatory)][string]$Entrypoint,
        [Parameter(Mandatory)][string]$PackageVersion,
        [Parameter(Mandatory)][string]$SourceCommit,
        [Parameter(Mandatory)][string[]]$SchemaFiles,
        [string]$PackageRoot,
        [int[]]$ActiveProcessIds
    )
    $commandItem = Get-Item -LiteralPath $CommandPath -Force
    $entrypointItem = Get-Item -LiteralPath $Entrypoint -Force
    $schemaFileState = @($SchemaFiles | ForEach-Object {
        $item = Get-Item -LiteralPath $_ -Force
        [pscustomobject]@{
            path = Resolve-RuntimeSchemaFullPath $_
            sha256 = (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()
            lastWriteTimeUtc = $item.LastWriteTimeUtc
        }
    })
    $runtimeFiles = @(
        [pscustomobject]@{
            role = 'command'
            path = Resolve-RuntimeSchemaFullPath $CommandPath
            sha256 = (Get-FileHash -LiteralPath $CommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
            lastWriteTimeUtc = $commandItem.LastWriteTimeUtc.ToString('o')
        },
        [pscustomobject]@{
            role = 'entrypoint'
            path = Resolve-RuntimeSchemaFullPath $Entrypoint
            sha256 = (Get-FileHash -LiteralPath $Entrypoint -Algorithm SHA256).Hash.ToLowerInvariant()
            lastWriteTimeUtc = $entrypointItem.LastWriteTimeUtc.ToString('o')
        }
    )
    $runtimeFiles += @($schemaFileState | ForEach-Object {
        [pscustomobject]@{
            role = 'schema-module'
            path = $_.path
            sha256 = $_.sha256
            lastWriteTimeUtc = $_.lastWriteTimeUtc.ToString('o')
        }
    })
    $runtimeReadyCandidates = @(
        $commandItem.LastWriteTimeUtc,
        $entrypointItem.LastWriteTimeUtc
    )
    $runtimeReadyCandidates += @($schemaFileState | ForEach-Object lastWriteTimeUtc)
    $runtimeReadyAt = $runtimeReadyCandidates | Sort-Object -Descending | Select-Object -First 1
    return [pscustomobject]@{
        effectiveCommand = Resolve-RuntimeSchemaFullPath $CommandPath
        effectiveCommandSha256 = $runtimeFiles[0].sha256
        entrypointSha256 = $runtimeFiles[1].sha256
        packageVersion = $PackageVersion
        sourceCommit = $SourceCommit
        entrypoint = Resolve-RuntimeSchemaFullPath $Entrypoint
        packageRoot = if ($PackageRoot) { Resolve-RuntimeSchemaFullPath $PackageRoot } else { $null }
        activeProcessIds = @($ActiveProcessIds | Sort-Object -Unique)
        runtimeFiles = @($runtimeFiles)
        runtimeReadyAtUtc = ([datetime]$runtimeReadyAt).ToUniversalTime()
    }
}

function Split-DshRuntimeCommandLine {
    param([string]$CommandLine)
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return @() }
    return @([regex]::Matches($CommandLine, '"(?<quoted>[^"]*)"|(?<bare>[^\s"]+)') |
        ForEach-Object {
            if ($_.Groups['quoted'].Success) {
                $_.Groups['quoted'].Value
            } else {
                $_.Groups['bare'].Value
            }
        })
}

function Test-DshNodeEntrypointArgument {
    param(
        [string]$CommandLine,
        [Parameter(Mandatory)][string]$Entrypoint
    )
    $arguments = @(Split-DshRuntimeCommandLine -CommandLine $CommandLine)
    if ($arguments.Count -lt 2 -or -not [IO.Path]::IsPathRooted($arguments[1])) {
        return $false
    }
    try {
        return (Resolve-RuntimeSchemaFullPath $arguments[1]) -ieq (
            Resolve-RuntimeSchemaFullPath $Entrypoint
        )
    } catch {
        return $false
    }
}

function Test-DshRuntimeProcessEvidence {
    param(
        [Parameter(Mandatory)][int]$ProcessId,
        [Parameter(Mandatory)][datetime]$ExpectedStartTimeUtc,
        [Parameter(Mandatory)][datetime]$RuntimeReadyAtUtc,
        [Parameter(Mandatory)][string]$Entrypoint
    )
    try {
        $process = Get-Process -Id $ProcessId -ErrorAction Stop
        $actualStart = $process.StartTime.ToUniversalTime()
        $processRecord = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction Stop
        return [bool](
            $process.ProcessName -ieq 'node' -and
            [Math]::Abs(($actualStart - $ExpectedStartTimeUtc).TotalSeconds) -le 2 -and
            $actualStart -ge $RuntimeReadyAtUtc -and
            (Test-DshNodeEntrypointArgument -CommandLine ([string]$processRecord.CommandLine) `
                -Entrypoint $Entrypoint)
        )
    } catch {
        return $false
    }
}

function Get-DshRuntimeUtcNow {
    return [datetime]::UtcNow
}

function Initialize-DshRuntimeDataProtection {
    if (-not ('System.Security.Cryptography.ProtectedData' -as [type])) {
        Add-Type -AssemblyName System.Security
    }
}

function New-DshRuntimeSchemaChallenge {
    param(
        [Parameter(Mandatory)]$RuntimeBinding,
        [Parameter(Mandatory)][int]$MaximumAgeMinutes
    )
    Initialize-DshRuntimeDataProtection
    $issuedAt = Get-DshRuntimeUtcNow
    $nonceBytes = New-Object byte[] 24
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($nonceBytes)
    $payload = [ordered]@{
        schemaVersion = 1
        nonce = [Convert]::ToBase64String($nonceBytes)
        issuedAtUtc = $issuedAt.ToString('o')
        expiresAtUtc = $issuedAt.AddMinutes($MaximumAgeMinutes).ToString('o')
        effectiveCommand = [string]$RuntimeBinding.effectiveCommand
        effectiveCommandSha256 = [string]$RuntimeBinding.effectiveCommandSha256
        entrypointSha256 = [string]$RuntimeBinding.entrypointSha256
        packageVersion = [string]$RuntimeBinding.packageVersion
        sourceCommit = [string]$RuntimeBinding.sourceCommit
        packageRoot = [string]$RuntimeBinding.packageRoot
        activeProcessIds = @($RuntimeBinding.activeProcessIds)
        runtimeFiles = @($RuntimeBinding.runtimeFiles)
        runtimeReadyAtUtc = $RuntimeBinding.runtimeReadyAtUtc.ToString('o')
    }
    $plainBytes = [Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Compress -Depth 6))
    $entropy = [Text.Encoding]::UTF8.GetBytes('dsh-windows-ops/runtime-schema/v1')
    $protectedBytes = [Security.Cryptography.ProtectedData]::Protect(
        $plainBytes,
        $entropy,
        [Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    return [pscustomobject]@{
        token = [Convert]::ToBase64String($protectedBytes)
        nonce = $payload.nonce
        issuedAtUtc = $payload.issuedAtUtc
        expiresAtUtc = $payload.expiresAtUtc
        requiredOutputMarker = 'PWSH_SCHEMA_OK:' + $payload.nonce
    }
}

function Read-DshRuntimeSchemaChallenge {
    param([Parameter(Mandatory)][string]$Token)
    Initialize-DshRuntimeDataProtection
    $protectedBytes = [Convert]::FromBase64String($Token)
    $entropy = [Text.Encoding]::UTF8.GetBytes('dsh-windows-ops/runtime-schema/v1')
    $plainBytes = [Security.Cryptography.ProtectedData]::Unprotect(
        $protectedBytes,
        $entropy,
        [Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    return [Text.Encoding]::UTF8.GetString($plainBytes) | ConvertFrom-Json
}

function ConvertTo-DshRepositoryIdentity {
    param([string]$Repository)
    if ([string]::IsNullOrWhiteSpace($Repository)) { return $null }
    $match = [regex]::Match(
        $Repository.Trim(),
        '^(?:(?:https|ssh)://(?:git@)?|git@)?(?<host>github\.com)[:/](?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?/?$',
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    if (-not $match.Success) { return $null }
    return (
        $match.Groups['host'].Value.ToLowerInvariant() + '/' +
        $match.Groups['owner'].Value.ToLowerInvariant() + '/' +
        $match.Groups['repo'].Value.ToLowerInvariant()
    )
}

function Test-DshRuntimeBehaviorEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Contract,
        [Parameter(Mandatory)]$RuntimeBinding,
        [string]$Path
    )

    if (-not $Path) {
        return [pscustomobject]@{
            valid = $false
            status = 'fresh-session-evidence-required'
            diagnosticCode = 'STALE_RUNTIME_SCHEMA'
            challenge = New-DshRuntimeSchemaChallenge -RuntimeBinding $RuntimeBinding `
                -MaximumAgeMinutes ([int]$Contract.maximumEvidenceAgeMinutes)
        }
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{
            valid = $false
            status = 'behavior-evidence-missing'
            diagnosticCode = 'STALE_RUNTIME_SCHEMA'
        }
    }
    try {
        $evidence = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        $visible = @(Get-RuntimeSchemaProperty $evidence 'visibleRequiredFields' | ForEach-Object { [string]$_ })
        $omitted = @(Get-RuntimeSchemaProperty $evidence 'invocationOmittedFields' | ForEach-Object { [string]$_ })
        $output = @((Get-RuntimeSchemaProperty $evidence 'outputMarkers') | ForEach-Object { [string]$_ })
        $errors = @((Get-RuntimeSchemaProperty $evidence 'errors') | ForEach-Object { [string]$_ })
        $forbidden = @($Contract.forbiddenRequiredFields | ForEach-Object { [string]$_ })
        $stalePatterns = @($Contract.staleErrorPatterns | ForEach-Object { [string]$_ })
        $freshProcess = (Get-RuntimeSchemaProperty $evidence 'freshProcess') -eq $true
        $freshSession = (Get-RuntimeSchemaProperty $evidence 'freshSession') -eq $true
        $challenge = Read-DshRuntimeSchemaChallenge -Token (
            [string](Get-RuntimeSchemaProperty $evidence 'challengeToken')
        )
        $challengeIssuedAt = [datetime]::Parse(
            [string]$challenge.issuedAtUtc,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal
        ).ToUniversalTime()
        $challengeExpiresAt = [datetime]::Parse(
            [string]$challenge.expiresAtUtc,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal
        ).ToUniversalTime()
        $observedAt = [datetime]::Parse(
            [string](Get-RuntimeSchemaProperty $evidence 'observedAtUtc'),
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal
        ).ToUniversalTime()
        $processStartedAt = [datetime]::Parse(
            [string](Get-RuntimeSchemaProperty $evidence 'processStartedAtUtc'),
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal
        ).ToUniversalTime()
        $sessionStartedAt = [datetime]::Parse(
            [string](Get-RuntimeSchemaProperty $evidence 'sessionStartedAtUtc'),
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal
        ).ToUniversalTime()
        $now = Get-DshRuntimeUtcNow
        $ageMinutes = ($now - $observedAt).TotalMinutes
        $timeValid = [bool](
            $ageMinutes -ge 0 -and
            $ageMinutes -le [int]$Contract.maximumEvidenceAgeMinutes -and
            $challengeIssuedAt -le $sessionStartedAt -and
            $challengeExpiresAt -ge $observedAt -and
            $processStartedAt -ge $RuntimeBinding.runtimeReadyAtUtc -and
            $sessionStartedAt -ge $processStartedAt -and
            $sessionStartedAt -le $observedAt
        )
        $bindingValid = [bool](
            [int]$challenge.schemaVersion -eq 1 -and
            [string]$challenge.effectiveCommand -ceq [string]$RuntimeBinding.effectiveCommand -and
            [string]$challenge.effectiveCommandSha256 -ceq
                [string]$RuntimeBinding.effectiveCommandSha256 -and
            [string]$challenge.entrypointSha256 -ceq [string]$RuntimeBinding.entrypointSha256 -and
            [string]$challenge.packageVersion -ceq [string]$RuntimeBinding.packageVersion -and
            [string]$challenge.sourceCommit -ceq [string]$RuntimeBinding.sourceCommit -and
            [string]$challenge.packageRoot -ceq [string]$RuntimeBinding.packageRoot -and
            (ConvertTo-Json -InputObject @($challenge.activeProcessIds) -Compress) -ceq
                (ConvertTo-Json -InputObject @($RuntimeBinding.activeProcessIds) -Compress) -and
            (ConvertTo-Json -InputObject @($challenge.runtimeFiles) -Compress -Depth 6) -ceq
                (ConvertTo-Json -InputObject @($RuntimeBinding.runtimeFiles) -Compress -Depth 6) -and
            [string]$challenge.runtimeReadyAtUtc -ceq
                $RuntimeBinding.runtimeReadyAtUtc.ToString('o') -and
            [string](Get-RuntimeSchemaProperty $evidence 'effectiveCommand') -ceq
                [string]$RuntimeBinding.effectiveCommand -and
            [string](Get-RuntimeSchemaProperty $evidence 'effectiveCommandSha256') -ceq
                [string]$RuntimeBinding.effectiveCommandSha256 -and
            [string](Get-RuntimeSchemaProperty $evidence 'entrypointSha256') -ceq
                [string]$RuntimeBinding.entrypointSha256 -and
            [string](Get-RuntimeSchemaProperty $evidence 'packageVersion') -ceq
                [string]$RuntimeBinding.packageVersion -and
            [string](Get-RuntimeSchemaProperty $evidence 'sourceCommit') -ceq
                [string]$RuntimeBinding.sourceCommit
        )
        $processValid = Test-DshRuntimeProcessEvidence `
            -ProcessId ([int](Get-RuntimeSchemaProperty $evidence 'processId')) `
            -ExpectedStartTimeUtc $processStartedAt `
            -RuntimeReadyAtUtc $RuntimeBinding.runtimeReadyAtUtc `
            -Entrypoint $RuntimeBinding.entrypoint
        $activeProcessValid = [bool](
            @($RuntimeBinding.activeProcessIds).Count -eq 0 -or
            @($RuntimeBinding.activeProcessIds | Where-Object {
                [int]$_ -eq [int](Get-RuntimeSchemaProperty $evidence 'processId')
            }).Count -eq 1
        )
        $sessionId = [string](Get-RuntimeSchemaProperty $evidence 'sessionId')
        $environmentValid = (
            [string](Get-RuntimeSchemaProperty $evidence 'sandboxMode') -ceq [string]$Contract.sandboxMode -and
            [string](Get-RuntimeSchemaProperty $evidence 'approval') -ceq [string]$Contract.approval
        )
        $forbiddenVisible = @($visible | Where-Object { $forbidden -ccontains $_ })
        $missingOmissions = @($forbidden | Where-Object { $omitted -cnotcontains $_ })
        $staleErrors = @($errors | Where-Object {
            $errorText = $_
            @($stalePatterns | Where-Object { $errorText -match $_ }).Count -gt 0
        })
        $observed = [bool](
            $freshProcess -and $freshSession -and $environmentValid -and
            $timeValid -and $bindingValid -and $processValid -and $activeProcessValid -and
            -not [string]::IsNullOrWhiteSpace($sessionId) -and
            $forbiddenVisible.Count -eq 0 -and $missingOmissions.Count -eq 0 -and
            $output -ccontains ([string]$Contract.successMarker + ':' + [string]$challenge.nonce) -and
            $staleErrors.Count -eq 0
        )
        return [pscustomobject]@{
            valid = $false
            observed = $observed
            sessionAttested = $false
            status = if ($observed) {
                'fresh-session-observed-unattested'
            } else {
                'stale-runtime-schema'
            }
            diagnosticCode = if ($observed) {
                'RUNTIME_SCHEMA_SESSION_UNATTESTED'
            } else {
                'STALE_RUNTIME_SCHEMA'
            }
            freshProcess = $freshProcess
            freshSession = $freshSession
            evidenceAgeMinutes = $ageMinutes
            timeValid = $timeValid
            bindingValid = $bindingValid
            processValid = $processValid
            activeProcessValid = $activeProcessValid
            environmentValid = $environmentValid
            forbiddenVisibleFields = @($forbiddenVisible)
            missingOmittedFields = @($missingOmissions)
            staleErrors = @($staleErrors)
        }
    } catch {
        return [pscustomobject]@{
            valid = $false
            status = 'behavior-evidence-invalid'
            diagnosticCode = 'STALE_RUNTIME_SCHEMA'
            reason = $_.Exception.Message
        }
    }
}

function Test-DshRuntimeSchemaState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Contract,
        [string]$BehaviorEvidencePath,
        [string]$AttestedRepository,
        [string]$AttestedSourceCommit,
        [string]$RequiredPackageRoot,
        [int[]]$RequiredProcessIds
    )

    $discovery = @(Get-DshRuntimeCommandDiscovery)
    $commands = @($discovery | ForEach-Object identity)
    $remediation = [pscustomobject]@{
        automaticApplyAllowed = $false
        reason = 'PR #10 is not yet available through the receipt-producing locked release installer.'
        steps = @(
            'Use an exact checkout of the reviewed PR head or merge commit.',
            'Build the workspace and temporarily link apps\cli with npm link --ignore-scripts --no-audit --no-fund.',
            'Rerun this diagnostic, restart the DSH process, and create a new session.',
            'Replace the development link with a reviewed receipt-producing release when one is available.'
            'Add a trusted Core session-attestation channel before treating behavior evidence as deployment health.'
        )
    }
    if ($commands.Count -eq 0) {
        return [pscustomobject]@{
            valid = $false
            status = 'runtime-command-missing'
            diagnosticCode = 'STALE_RUNTIME_SCHEMA'
            commands = @()
            remediation = $remediation
        }
    }
    if (-not $discovery[0].path) {
        return [pscustomobject]@{
            valid = $false
            status = 'runtime-command-shadowed'
            diagnosticCode = 'STALE_RUNTIME_SCHEMA'
            commands = @($commands)
            effectiveCommand = $discovery[0].identity
            remediation = $remediation
        }
    }

    $runtime = Resolve-DshRuntimePackage -CommandPath $discovery[0].path
    if (-not $runtime.valid) {
        return [pscustomobject]@{
            valid = $false
            status = [string]$runtime.status
            diagnosticCode = 'STALE_RUNTIME_SCHEMA'
            commands = @($commands)
            effectiveCommand = $discovery[0].path
            package = $runtime
            remediation = $remediation
        }
    }
    $packageRootBindingValid = [bool](
        -not $RequiredPackageRoot -or
        (Resolve-RuntimeSchemaFullPath $runtime.packageRoot) -ieq
            (Resolve-RuntimeSchemaFullPath $RequiredPackageRoot)
    )

    $expectedName = [string]$Contract.package.name
    $expectedVersion = [string]$Contract.package.version
    $packageValid = $runtime.name -ceq $expectedName -and $runtime.version -ceq $expectedVersion
    $symbolChecks = @($Contract.requiredBuiltSymbols | ForEach-Object {
        $path = Join-Path $runtime.packageRoot ([string]$_.path)
        $present = $false
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $present = [bool](Select-String -LiteralPath $path -SimpleMatch ([string]$_.symbol) -Quiet)
        }
        [pscustomobject]@{ path = [string]$_.path; symbol = [string]$_.symbol; present = $present }
    })
    $symbolsValid = @($symbolChecks | Where-Object { -not $_.present }).Count -eq 0

    $sourceRoot = if ($runtime.packageTarget) {
        Find-DshRuntimeSourceRoot -StartPath $runtime.packageTarget
    } else { $null }
    $repository = $AttestedRepository
    $sourceCommit = $AttestedSourceCommit
    $mergeSecondParent = $null
    if ($sourceRoot) {
        try {
            $repository = Invoke-RuntimeSchemaGit -SourceRoot $sourceRoot -Arguments @('remote', 'get-url', 'origin')
            $sourceCommit = Invoke-RuntimeSchemaGit -SourceRoot $sourceRoot -Arguments @('rev-parse', 'HEAD')
            $mergeSecondParent = Invoke-RuntimeSchemaGit -SourceRoot $sourceRoot `
                -Arguments @('rev-parse', ([string]$Contract.source.integrationCommit + '^2'))
        } catch {
            $repository = $null
            $sourceCommit = $null
            $mergeSecondParent = $null
        }
    }
    $normalizedRepository = ConvertTo-DshRepositoryIdentity -Repository $repository
    $expectedRepository = ConvertTo-DshRepositoryIdentity -Repository (
        [string]$Contract.source.repository
    )
    $acceptedCommits = @(
        [string]$Contract.source.integrationCommit,
        [string]$Contract.source.pullRequestHead
    )
    $provenanceValid = [bool](
        $normalizedRepository -and
        $normalizedRepository -ceq $expectedRepository -and
        $acceptedCommits -ccontains [string]$sourceCommit -and
        (
            -not $sourceRoot -or
            [string]$mergeSecondParent -ceq [string]$Contract.source.pullRequestHead
        )
    )
    try {
        $freshVersion = Get-DshFreshProcessVersion -Entrypoint $runtime.entrypoint
    } catch {
        $freshVersion = $null
    }
    $freshVersionValid = [string]$freshVersion -ceq $expectedVersion
    try {
        $runtimeBinding = Get-DshRuntimeEvidenceBinding `
            -CommandPath $discovery[0].path `
            -Entrypoint $runtime.entrypoint `
            -PackageVersion $runtime.version `
            -SourceCommit ([string]$sourceCommit) `
            -SchemaFiles @($symbolChecks | ForEach-Object {
                Join-Path $runtime.packageRoot ([string]$_.path)
            }) `
            -PackageRoot $runtime.packageRoot `
            -ActiveProcessIds @($RequiredProcessIds)
        $behavior = Test-DshRuntimeBehaviorEvidence -Contract $Contract.behavior `
            -RuntimeBinding $runtimeBinding -Path $BehaviorEvidencePath
    } catch {
        $runtimeBinding = $null
        $behavior = [pscustomobject]@{
            valid = $false
            status = 'behavior-evidence-invalid'
            diagnosticCode = 'STALE_RUNTIME_SCHEMA'
            reason = $_.Exception.Message
        }
    }

    $valid = [bool](
        $packageValid -and $packageRootBindingValid -and $symbolsValid -and
        $provenanceValid -and $freshVersionValid -and $behavior.valid
    )
    $status = if ($valid) {
        'runtime-schema-current'
    } elseif (-not $packageValid -or -not $symbolsValid -or -not $freshVersionValid) {
        'stale-runtime-schema'
    } elseif (-not $packageRootBindingValid) {
        'runtime-not-active-desktop-core'
    } elseif (-not $provenanceValid) {
        'runtime-provenance-unattested'
    } else {
        [string]$behavior.status
    }
    return [pscustomobject]@{
        valid = $valid
        status = $status
        diagnosticCode = if ($valid) { $null } else { 'STALE_RUNTIME_SCHEMA' }
        commands = @($commands)
        effectiveCommand = $discovery[0].path
        package = $runtime
        packageValid = $packageValid
        packageRootBindingValid = $packageRootBindingValid
        freshProcessVersion = $freshVersion
        freshProcessVersionValid = $freshVersionValid
        source = [pscustomobject]@{
            root = $sourceRoot
            repository = $repository
            commit = $sourceCommit
            integrationSecondParent = $mergeSecondParent
            valid = $provenanceValid
        }
        builtSymbols = @($symbolChecks)
        behavior = $behavior
        evidenceBinding = $runtimeBinding
        restartRequired = -not $behavior.valid
        remediation = $remediation
    }
}

Export-ModuleMember -Function @(
    'Get-DshRuntimeCommandPaths',
    'Resolve-DshRuntimePackage',
    'Test-DshRuntimeBehaviorEvidence',
    'Test-DshRuntimeSchemaState'
)
