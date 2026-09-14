[CmdletBinding()]
param(
    [ValidateSet('Check', 'Generate')][string]$Action = 'Check',
    [string]$LockPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'DshOfficialDesktopPluginProvisioning.psm1') -Force
if ([string]::IsNullOrWhiteSpace($LockPath)) {
    $LockPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'deployments\windows-copilot.lock.json'
}

try {
    $contract = Get-DshOfficialDesktopPluginContract -LockPath $LockPath
    $repository = ([string]$contract.source.repository).Replace('https://github.com/', '').TrimEnd('/')
    $tag = [string]$contract.artifact.releaseTag
    $headers = @{ Accept = 'application/vnd.github+json'; 'User-Agent' = 'dsh-windows-ops-release-verifier' }
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repository/releases/tags/$tag" -Headers $headers
    $asset = @($release.assets | Where-Object name -CEQ ([string]$contract.artifact.name))
    $checksum = @($release.assets | Where-Object name -CEQ ([string]$contract.artifact.checksumManifest.name))
    $ref = Invoke-RestMethod -Uri "https://api.github.com/repos/$repository/git/ref/tags/$tag" -Headers $headers
    $releaseCommit = [string]$ref.object.sha
    if ([string]$ref.object.type -ceq 'tag') {
        $tagObject = Invoke-RestMethod -Uri ([string]$ref.object.url) -Headers $headers
        if ([string]$tagObject.object.type -cne 'commit') { throw 'release-tag-does-not-resolve-to-commit' }
        $releaseCommit = [string]$tagObject.object.sha
    }
    $drift = [Collections.Generic.List[string]]::new()
    if ($release.immutable -ne $true) { $drift.Add('release-not-immutable') }
    if ([string]$release.tag_name -cne $tag) { $drift.Add('release-tag-mismatch') }
    if ($releaseCommit -cne [string]$contract.artifact.releaseCommit) { $drift.Add('release-commit-mismatch') }
    if ($asset.Count -ne 1) { $drift.Add('release-asset-count') }
    else {
        if ([long]$asset[0].size -ne [long]$contract.artifact.size) { $drift.Add('release-asset-size-mismatch') }
        if ([string]$asset[0].digest -cne ('sha256:' + [string]$contract.artifact.sha256)) {
            $drift.Add('release-asset-sha256-mismatch')
        }
        if ([string]$asset[0].browser_download_url -cne [string]$contract.artifact.url) {
            $drift.Add('release-asset-url-mismatch')
        }
    }
    if ($checksum.Count -ne 1) { $drift.Add('checksum-asset-count') }
    else {
        if ([long]$checksum[0].size -ne [long]$contract.artifact.checksumManifest.size) {
            $drift.Add('checksum-asset-size-mismatch')
        }
        if ([string]$checksum[0].digest -cne ('sha256:' + [string]$contract.artifact.checksumManifest.sha256)) {
            $drift.Add('checksum-asset-sha256-mismatch')
        }
    }
    $result = [pscustomobject][ordered]@{
        schemaVersion = 1
        action = $Action.ToLowerInvariant()
        status = if ($drift.Count) { 'drifted' } else { 'verified' }
        mode = $contract.mode
        repository = $repository
        tag = $tag
        releaseCommit = $releaseCommit
        immutable = [bool]$release.immutable
        asset = if ($asset.Count -eq 1) {
            [pscustomobject]@{
                name = [string]$asset[0].name
                size = [long]$asset[0].size
                digest = [string]$asset[0].digest
                url = [string]$asset[0].browser_download_url
            }
        } else { $null }
        drift = @($drift)
        updateCommand = if ($Action -ceq 'Generate') {
            "pwsh -NoProfile -File tools\sync-official-desktop-plugin-release.ps1 -Action Check"
        } else { $null }
        lockModified = $false
        credentialsPersisted = $false
    }
    $result | ConvertTo-Json -Depth 12
    if ($drift.Count) { exit 2 }
    exit 0
} catch {
    [pscustomobject]@{
        schemaVersion = 1
        action = $Action.ToLowerInvariant()
        status = 'failed'
        reason = $_.Exception.Message
        lockModified = $false
        credentialsPersisted = $false
    } | ConvertTo-Json -Depth 6
    exit 2
}
