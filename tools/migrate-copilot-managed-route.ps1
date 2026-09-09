[CmdletBinding()]
param(
    [ValidateSet('Check', 'Apply', 'Verify')][string]$Action = 'Check',
    [string]$PolicyPath = (Join-Path $PSScriptRoot '..\deployments\copilot-managed-route.policy.json'),
    [string]$SnapshotPath,
    [string]$BaseUri = 'http://127.0.0.1:3080',
    [switch]$Live,
    [switch]$AllowAccountDiscovery,
    [switch]$ApproveNativeRemoval,
    [switch]$ApproveSearchAllowlist,
    [switch]$AcknowledgeColdHistoryLimitation
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'DshCopilotManagedRoute.psm1') -Force
try {
    $policy = Get-Content -LiteralPath $PolicyPath -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    throw 'Cannot read managed-route policy JSON; input contents withheld.'
}
Test-DshCopilotManagedRoutePolicy $policy | Out-Null
if ($SnapshotPath -and ($Live -or $Action -eq 'Apply' -or $AllowAccountDiscovery)) {
    throw 'Offline snapshots are only for Check/Verify and cannot authorize live Apply or discovery.'
}
if ($Action -eq 'Apply' -and (-not $Live -or -not $AllowAccountDiscovery)) {
    throw 'Apply requires -Live and explicit -AllowAccountDiscovery for fresh catalog readback.'
}
if (-not $Live -and -not $SnapshotPath) {
    [pscustomobject]@{
        mode = $Action.ToLowerInvariant(); status = 'evidence-required'; fullBaseline = 'not-verified'
        reasons = @('provide-offline-snapshot-or-explicit-live-check')
        liveActions = @(); directCredentialWrites = $false
    } | ConvertTo-Json -Depth 12
    exit 2
}
if ($AllowAccountDiscovery -and -not $Live) { throw '-AllowAccountDiscovery requires -Live.' }
if ($Action -eq 'Apply') {
    $readLive = {
        Get-DshCopilotManagedRouteSnapshot -BaseUri $BaseUri -AllowAccountDiscovery
    }.GetNewClosure()
    $mutate = {
        param($ns, $ops, $revision)
        Invoke-DshCopilotManagedRouteRpc -BaseUri $BaseUri -Method 'settings/mutate' `
            -Arguments @{ ns = $ns; ops = $ops; expectedRevision = $revision }
    }.GetNewClosure()
    # The versioned plugin Remote reports live selections and capabilities.
    # No supplied JSON, partial Session-list cache or guessed Core version can
    # substitute for its fresh result. This is not a full Desktop attestation.
    $result = Invoke-DshCopilotManagedRouteMigration -Policy $policy -ReadLiveSnapshot $readLive -Mutate $mutate `
        -ApproveNativeRemoval:$ApproveNativeRemoval -ApproveSearchAllowlist:$ApproveSearchAllowlist `
        -AcknowledgeColdHistoryLimitation:$AcknowledgeColdHistoryLimitation
} else {
    $snapshot = if ($SnapshotPath) {
        try {
            $value = Get-Content -LiteralPath $SnapshotPath -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            throw 'Cannot read managed-route snapshot JSON; input contents withheld.'
        }
        $value | Add-Member -NotePropertyName source -NotePropertyValue 'offline-snapshot' -Force
        $value
    } else {
        Get-DshCopilotManagedRouteSnapshot -BaseUri $BaseUri -AllowAccountDiscovery:$AllowAccountDiscovery
    }
    $result = Get-DshCopilotManagedRoutePlan -Policy $policy -Snapshot $snapshot `
        -ApproveNativeRemoval:$ApproveNativeRemoval -ApproveSearchAllowlist:$ApproveSearchAllowlist `
        -AcknowledgeColdHistoryLimitation:$AcknowledgeColdHistoryLimitation
    if ($Action -eq 'Verify' -and $result.status -eq 'ready') {
        $result.status = 'migration-required'
    }
}
[pscustomobject]@{ mode = $Action.ToLowerInvariant(); result = $result } | ConvertTo-Json -Depth 16
if ($result.status -cin @('already-managed', 'applied', 'ready')) { exit 0 }
exit 2
