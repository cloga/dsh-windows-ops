Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Config-only maintenance. This module never installs packages, opens credential
# records, edits live files, controls processes, or changes Session selections.
function Get-ManagedRouteField {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [Collections.IDictionary]) { return ,$Object[$Name] }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return ,$property.Value }
    return $null
}

function Test-ManagedRouteObject {
    param($Value)
    return $null -ne $Value -and ($Value -is [Collections.IDictionary] -or $Value -is [System.Management.Automation.PSCustomObject])
}

function Test-ManagedRouteTrue {
    param($Value)
    # Do not type this parameter as bool: binding would coerce the wire value.
    return $Value -is [bool] -and $Value -eq $true
}

function Get-ManagedRouteKeys {
    param($Value)
    if ($Value -is [Collections.IDictionary]) { return @($Value.Keys) }
    if ($Value -is [System.Management.Automation.PSCustomObject]) { return @($Value.PSObject.Properties | ForEach-Object { $_.Name }) }
    return @()
}

function Test-ManagedRouteEqual {
    param($Left, $Right)
    # Inputs are decoded, redacted RPC JSON, not Cordis runtime objects.
    if ($null -eq $Left -or $null -eq $Right) { return $null -eq $Left -and $null -eq $Right }
    if ((Test-ManagedRouteObject $Left) -or (Test-ManagedRouteObject $Right)) {
        if (-not (Test-ManagedRouteObject $Left) -or -not (Test-ManagedRouteObject $Right)) { return $false }
        $keys = @(Get-ManagedRouteKeys $Left)
        if ($keys.Count -ne @(Get-ManagedRouteKeys $Right).Count) { return $false }
        foreach ($key in $keys) {
            if (@(Get-ManagedRouteKeys $Right) -cnotcontains $key -or
                -not (Test-ManagedRouteEqual (Get-ManagedRouteField $Left $key) (Get-ManagedRouteField $Right $key))) { return $false }
        }
        return $true
    }
    if ($Left -is [array] -or $Right -is [array]) {
        if ($Left -isnot [array] -or $Right -isnot [array] -or $Left.Count -ne $Right.Count) { return $false }
        for ($i = 0; $i -lt $Left.Count; $i++) {
            if (-not (Test-ManagedRouteEqual $Left[$i] $Right[$i])) { return $false }
        }
        return $true
    }
    return $Left.GetType() -eq $Right.GetType() -and $Left -ceq $Right
}

function Test-ManagedRouteUnownedFieldsEqual {
    param($Before, $After, [string]$OwnedKey)
    $keys = @(@(Get-ManagedRouteKeys $Before) + @(Get-ManagedRouteKeys $After) | Sort-Object -Unique)
    foreach ($key in $keys) {
        if ($key -ceq $OwnedKey) { continue }
        if (@(Get-ManagedRouteKeys $Before) -cnotcontains $key -or @(Get-ManagedRouteKeys $After) -cnotcontains $key -or
            -not (Test-ManagedRouteEqual (Get-ManagedRouteField $Before $key) (Get-ManagedRouteField $After $key))) { return $false }
    }
    return $true
}

function Test-DshCopilotManagedRoutePolicy {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Policy)
    $plugin = Get-ManagedRouteField $Policy 'plugin'
    $search = Get-ManagedRouteField $Policy 'search'
    if ((Get-ManagedRouteField $Policy 'schemaVersion') -ne 1 -or
        (Get-ManagedRouteField $Policy 'purpose') -cne 'config-only-managed-route-maintenance' -or
        (Get-ManagedRouteField $Policy 'nativeProvider') -cne 'github-copilot' -or
        (Get-ManagedRouteField $Policy 'managedProvider') -cne 'github-copilot-preview' -or
        (Get-ManagedRouteField $plugin 'name') -cne 'dsh-github-copilot' -or
        (Get-ManagedRouteField $plugin 'version') -cnotmatch '^0\.4\.0-alpha\.[1-9][0-9]*$' -or
        (Get-ManagedRouteField $Policy 'supportedCoreVersions') -isnot [array] -or
        (Get-ManagedRouteField $Policy 'supportedCoreVersions').Count -eq 0 -or
        (Get-ManagedRouteField $Policy 'migrationStatusProtocol') -ne 1 -or
        -not (Test-ManagedRouteEqual (Get-ManagedRouteField $Policy 'requiredCapabilities') @('agentsList', 'sessionProjections', 'settingsCas', 'providerRegistry', 'defaultSelection')) -or
        (Get-ManagedRouteField $search 'namespace') -cne 'github-copilot' -or
        -not (Test-ManagedRouteEqual (Get-ManagedRouteField $search 'path') @('providers')) -or
        -not (Test-ManagedRouteEqual (Get-ManagedRouteField $search 'from') @('github-copilot')) -or
        -not (Test-ManagedRouteEqual (Get-ManagedRouteField $search 'to') @('github-copilot-preview'))) {
        throw 'Invalid config-only managed-route policy.'
    }
    return $true
}

function Test-ManagedRouteArtifactPin {
    param($Policy)
    $plugin = Get-ManagedRouteField $Policy 'plugin'
    $version = Get-ManagedRouteField $plugin 'version'
    $artifact = Get-ManagedRouteField $plugin 'artifact'
    $checksum = Get-ManagedRouteField $artifact 'checksumManifest'
    $prefix = 'https://github.com/cloga/dsh-github-copilot/releases/download/v' + $version + '/'
    $name = 'dsh-github-copilot-' + $version + '.tgz'
    if ((Get-ManagedRouteField $artifact 'name') -cne $name -or
        (Get-ManagedRouteField $artifact 'url') -cne ($prefix + $name) -or
        (Get-ManagedRouteField $artifact 'releaseTag') -cne ('v' + $version) -or
        (Get-ManagedRouteField $artifact 'releaseCommit') -cnotmatch '^[0-9a-f]{40}$' -or
        (Get-ManagedRouteField $artifact 'releaseImmutable') -isnot [bool] -or
        (Get-ManagedRouteField $artifact 'releaseImmutable') -ne $true -or
        (Get-ManagedRouteField $checksum 'name') -cne 'SHA256SUMS' -or
        (Get-ManagedRouteField $checksum 'url') -cne ($prefix + 'SHA256SUMS')) { return $false }
    foreach ($item in @($artifact, $checksum)) {
        $size = Get-ManagedRouteField $item 'size'
        if ((Get-ManagedRouteField $item 'sha256') -cnotmatch '^[0-9a-f]{64}$' -or
            -not ($size -is [int] -or $size -is [long]) -or $size -le 0) { return $false }
    }
    return $true
}

function Get-ManagedRouteDescriptor {
    param($Settings, [string]$Namespace)
    $matches = @((Get-ManagedRouteField $Settings 'namespaces') | Where-Object {
        (Get-ManagedRouteField $_ 'ns') -ceq $Namespace
    })
    if ($matches.Count -ne 1) { return $null }
    $revision = Get-ManagedRouteField $matches[0] 'revision'
    if (-not ($revision -is [int] -or $revision -is [long] -or $revision -is [double] -or $revision -is [decimal]) -or
        $revision -lt 0 -or $revision -gt 9007199254740991 -or $revision % 1 -ne 0) { return $null }
    return $matches[0]
}

function Get-ManagedRouteNativeProfile {
    param($Section)
    return Get-ManagedRouteField (Get-ManagedRouteField $Section 'providers') 'github-copilot'
}

function Test-ManagedRouteReviewedProfile {
    param($Profile)
    if (-not (Test-ManagedRouteObject $Profile)) { return $false }
    foreach ($key in @(Get-ManagedRouteKeys $Profile)) {
        if ($key -cnotin @('displayName', 'api', 'models', 'compat')) { return $false }
    }
    $name = Get-ManagedRouteField $Profile 'displayName'
    if ($null -ne $name -and $name -isnot [string]) { return $false }
    $api = Get-ManagedRouteField $Profile 'api'
    if ($null -ne $api -and $api -cnotin @('openai-responses', 'openai-completions', 'anthropic-messages')) { return $false }
    $compat = Get-ManagedRouteField $Profile 'compat'
    if ($null -ne $compat -and (-not (Test-ManagedRouteObject $compat) -or
        @(Get-ManagedRouteKeys $compat).Count -ne 1 -or
        (Get-ManagedRouteField $compat 'supportsStrictMode') -isnot [bool] -or
        (Get-ManagedRouteField $compat 'supportsStrictMode') -ne $false)) { return $false }
    $models = Get-ManagedRouteField $Profile 'models'
    if ($null -ne $models) {
        if ($models -isnot [array] -or $models.Count -gt 512) { return $false }
        $ids = @()
        foreach ($model in $models) {
            if (-not (Test-ManagedRouteObject $model)) { return $false }
            foreach ($key in @(Get-ManagedRouteKeys $model)) { if ($key -cnotin @('id', 'api')) { return $false } }
            $id = Get-ManagedRouteField $model 'id'
            $modelApi = Get-ManagedRouteField $model 'api'
            if ($id -isnot [string] -or $id -cnotmatch '^[a-zA-Z0-9._:/-]{1,200}$' -or $ids -ccontains $id -or
                ($null -ne $modelApi -and $modelApi -cnotin @('openai-responses', 'openai-completions', 'anthropic-messages'))) { return $false }
            $ids += $id
        }
    }
    return $true
}

function Test-ManagedRouteSelection {
    param($Selection)
    if (-not (Test-ManagedRouteObject $Selection)) { return $false }
    foreach ($key in @(Get-ManagedRouteKeys $Selection)) { if ($key -cnotin @('provider', 'model', 'reasoningEffort')) { return $false } }
    foreach ($key in @('provider', 'model')) {
        $value = Get-ManagedRouteField $Selection $key
        if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value) -or $value.Length -gt 512) { return $false }
    }
    if (@(Get-ManagedRouteKeys $Selection) -ccontains 'reasoningEffort') {
        $value = Get-ManagedRouteField $Selection 'reasoningEffort'
        if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value) -or $value.Length -gt 512) { return $false }
    }
    return $true
}

function Test-ManagedRouteReceipt {
    param($Receipt, $Policy)
    if (-not (Test-ManagedRouteObject $Receipt)) { return $false }
    if (-not (Test-ManagedRouteEqual (@(Get-ManagedRouteKeys $Receipt) | Sort-Object) (@('plugin', 'protocolVersion', 'historyScope', 'observedAt', 'capabilities', 'complete', 'defaultSelection', 'sessions', 'routes') | Sort-Object))) { return $false }
    $plugin = Get-ManagedRouteField $Receipt 'plugin'
    $time = Get-ManagedRouteField $Receipt 'observedAt'
    if ((Get-ManagedRouteField $Receipt 'protocolVersion') -ne (Get-ManagedRouteField $Policy 'migrationStatusProtocol') -or
        (Get-ManagedRouteField $Receipt 'historyScope') -cne 'live-agents-only' -or
        (Get-ManagedRouteField $plugin 'name') -cne 'dsh-github-copilot' -or
        (Get-ManagedRouteField $plugin 'version') -cne (Get-ManagedRouteField (Get-ManagedRouteField $Policy 'plugin') 'version') -or
        -not (Test-ManagedRouteEqual (@(Get-ManagedRouteKeys $plugin) | Sort-Object) @('name', 'version')) -or
        -not ($time -is [int] -or $time -is [long] -or $time -is [double]) -or $time -lt 0 -or $time -gt 9007199254740991 -or $time % 1 -ne 0) { return $false }
    foreach ($section in @('capabilities', 'complete', 'routes')) {
        $value = Get-ManagedRouteField $Receipt $section
        $keys = switch ($section) {
            'capabilities' { @('agentsList', 'sessionProjections', 'settingsCas', 'providerRegistry', 'defaultSelection') }
            'complete' { @('sessions', 'defaultSelection', 'routes') }
            'routes' { @('nativeConfigured', 'nativeRegistered', 'managedRegistered') }
        }
        if (-not (Test-ManagedRouteEqual (@(Get-ManagedRouteKeys $value) | Sort-Object) (@($keys) | Sort-Object))) { return $false }
        foreach ($key in $keys) {
            $flag = Get-ManagedRouteField $value $key
            if ($flag -isnot [bool] -and -not ($section -ceq 'routes' -and $null -eq $flag)) { return $false }
        }
    }
    $default = Get-ManagedRouteField $Receipt 'defaultSelection'
    if ($null -ne $default -and -not (Test-ManagedRouteSelection $default)) { return $false }
    $sessions = Get-ManagedRouteField $Receipt 'sessions'
    if ($sessions -isnot [array] -or $sessions.Count -gt 1024) { return $false }
    $ids = @()
    foreach ($session in $sessions) {
        if (-not (Test-ManagedRouteEqual (@(Get-ManagedRouteKeys $session) | Sort-Object) (@('id', 'status', 'effectiveSelection', 'selectionSource', 'activeRequestSelection') | Sort-Object))) { return $false }
        $id = Get-ManagedRouteField $session 'id'
        if ($id -isnot [string] -or [string]::IsNullOrWhiteSpace($id) -or $id.Length -gt 512 -or $ids -ccontains $id -or
            (Get-ManagedRouteField $session 'status') -cnotin @('idle', 'running') -or
            (Get-ManagedRouteField $session 'selectionSource') -cnotin @('pending', 'request-header', 'default', 'unknown')) { return $false }
        $ids += $id
        foreach ($key in @('effectiveSelection', 'activeRequestSelection')) {
            $selection = Get-ManagedRouteField $session $key
            if ($null -ne $selection -and -not (Test-ManagedRouteSelection $selection)) { return $false }
        }
    }
    return $true
}

function Get-DshCopilotManagedRoutePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Policy,
        [Parameter(Mandatory)]$Snapshot,
        [switch]$ApproveNativeRemoval,
        [switch]$ApproveSearchAllowlist,
        [switch]$AcknowledgeColdHistoryLimitation
    )
    Test-DshCopilotManagedRoutePolicy $Policy | Out-Null
    $reasons = [Collections.Generic.List[string]]::new()
    $operations = [Collections.Generic.List[object]]::new()
    $dependencies = [Collections.Generic.List[object]]::new()
    $settings = Get-ManagedRouteField $Snapshot 'settings'
    if (-not (Test-ManagedRouteObject $settings) -or -not (Test-ManagedRouteTrue (Get-ManagedRouteField $settings 'writable'))) { $reasons.Add('settings-not-writable') }
    $native = Get-ManagedRouteDescriptor $settings 'llm-pi-ai'
    $search = Get-ManagedRouteDescriptor $settings 'github-copilot'
    $default = Get-ManagedRouteDescriptor $settings 'agent-default-model'
    if ($null -eq $native -or $null -eq $search -or $null -eq $default) { $reasons.Add('settings-descriptor-missing-duplicate-or-invalid') }
    $raw = Get-ManagedRouteNativeProfile (Get-ManagedRouteField $native 'user')
    $base = Get-ManagedRouteNativeProfile (Get-ManagedRouteField $native 'base')
    $effective = Get-ManagedRouteNativeProfile (Get-ManagedRouteField $native 'value')
    if ($null -ne $base) { $reasons.Add('inherited-native-profile') }
    foreach ($layer in @('base', 'user', 'value')) {
        if ($null -ne (Get-ManagedRouteField (Get-ManagedRouteField $search $layer) 'temporaryRouteBackup')) {
            $reasons.Add('route-ownership-journal-present'); break
        }
    }
    $secrets = Get-ManagedRouteField $native 'secrets'
    if ($secrets -isnot [array]) { $reasons.Add('secret-status-unverified') }
    foreach ($secret in $secrets) {
        $path = Get-ManagedRouteField $secret 'path'
        $set = Get-ManagedRouteField $secret 'set'
        if (-not (Test-ManagedRouteObject $secret) -or $set -isnot [bool] -or $path -isnot [array]) {
            $reasons.Add('secret-status-unverified'); continue
        }
        if ($set -and $path.Count -ge 2 -and
            $path[0] -ceq 'providers' -and $path[1] -ceq 'github-copilot') { $reasons.Add('native-profile-has-secrets'); break }
    }
    if ($null -ne $raw -and -not (Test-ManagedRouteReviewedProfile $raw)) { $reasons.Add('native-user-profile-not-reviewed') }
    if ($null -eq $raw -and $null -ne $effective -and $null -eq $base) { $reasons.Add('native-effective-profile-unattributed') }

    $allowlist = Get-ManagedRouteField (Get-ManagedRouteField $search 'value') 'providers'
    $searchChange = -not (Test-ManagedRouteEqual $allowlist @('github-copilot-preview'))
    if ($searchChange) {
        if (-not (Test-ManagedRouteEqual $allowlist @('github-copilot'))) { $reasons.Add('search-allowlist-not-reviewed') }
        if (-not $ApproveSearchAllowlist) { $reasons.Add('search-allowlist-approval-required') }
        $operations.Add([pscustomobject]@{
            ns = 'github-copilot'; expectedRevision = Get-ManagedRouteField $search 'revision'
            ops = @(@{ op = 'set'; path = @('providers'); value = @('github-copilot-preview') })
        })
    }
    if ($null -ne $raw) {
        if (-not $ApproveNativeRemoval) { $reasons.Add('native-removal-approval-required') }
        $operations.Add([pscustomobject]@{
            ns = 'llm-pi-ai'; expectedRevision = Get-ManagedRouteField $native 'revision'
            ops = @(@{ op = 'unset'; path = @('providers', 'github-copilot') })
        })
    }

    $catalog = Get-ManagedRouteField $Snapshot 'catalog'
    $groups = Get-ManagedRouteField $catalog 'groups'
    $routable = Get-ManagedRouteField $catalog 'routableProviders'
    $failures = Get-ManagedRouteField $catalog 'failures'
    if ($groups -isnot [array] -or $routable -isnot [array] -or $failures -isnot [array]) { $reasons.Add('catalog-unverified') }
    $managedGroups = @($groups | Where-Object { (Get-ManagedRouteField $_ 'id') -ceq 'github-copilot-preview' })
    $modelIds = @()
    if ($managedGroups.Count -ne 1 -or @($routable | Where-Object { $_ -ceq 'github-copilot-preview' }).Count -ne 1) {
        $reasons.Add('managed-route-unavailable-or-duplicate')
    } else {
        $models = Get-ManagedRouteField $managedGroups[0] 'models'
        if ($models -isnot [array] -or $models.Count -eq 0 -or $models.Count -gt 512) { $reasons.Add('managed-model-catalog-empty-or-invalid') }
        foreach ($model in @($models)) {
            $id = Get-ManagedRouteField $model 'id'
            if ($id -isnot [string] -or [string]::IsNullOrWhiteSpace($id) -or $modelIds -ccontains $id) { $reasons.Add('managed-model-catalog-invalid') }
            $modelIds += $id
        }
    }
    if (@($failures | Where-Object { (Get-ManagedRouteField $_ 'id') -ceq 'github-copilot-preview' }).Count -gt 0) { $reasons.Add('managed-catalog-failed') }
    $nativeRegistered = @($routable | Where-Object { $_ -ceq 'github-copilot' }).Count -gt 0 -or
        @($groups | Where-Object { (Get-ManagedRouteField $_ 'id') -ceq 'github-copilot' }).Count -gt 0 -or
        @($failures | Where-Object { (Get-ManagedRouteField $_ 'id') -ceq 'github-copilot' }).Count -gt 0
    if ($null -eq $raw -and $nativeRegistered) { $reasons.Add('native-registry-route-remains') }
    $futureDefault = Get-ManagedRouteField $catalog 'default'
    $storedDefault = Get-ManagedRouteField $default 'value'
    if (-not (Test-ManagedRouteEqual $futureDefault $storedDefault)) { $reasons.Add('default-evidence-disagrees') }
    $defaultProvider = Get-ManagedRouteField $futureDefault 'provider'
    $defaultModel = Get-ManagedRouteField $futureDefault 'model'
    if ($defaultProvider -ceq 'github-copilot') { $reasons.Add('native-future-default-dependency') }
    elseif ($defaultProvider -isnot [string] -or [string]::IsNullOrWhiteSpace($defaultProvider) -or
        $defaultModel -isnot [string] -or [string]::IsNullOrWhiteSpace($defaultModel) -or $routable -cnotcontains $defaultProvider) { $reasons.Add('future-default-unverified') }
    $defaultGroups = @($groups | Where-Object { (Get-ManagedRouteField $_ 'id') -ceq $defaultProvider })
    if ($defaultGroups.Count -ne 1 -or @((Get-ManagedRouteField $defaultGroups[0] 'models') | Where-Object {
        (Get-ManagedRouteField $_ 'id') -ceq $defaultModel
    }).Count -ne 1) { $reasons.Add('future-default-model-unavailable') }

    $receipt = Get-ManagedRouteField $Snapshot 'migrationStatus'
    if (-not (Test-ManagedRouteReceipt $receipt $Policy)) {
        $reasons.Add('migration-status-invalid-or-version-mismatch')
    } else {
        foreach ($key in (Get-ManagedRouteField $Policy 'requiredCapabilities')) {
            if ((Get-ManagedRouteField (Get-ManagedRouteField $receipt 'capabilities') $key) -ne $true) { $reasons.Add('required-public-capability-unavailable') }
        }
        foreach ($key in @('sessions', 'defaultSelection', 'routes')) {
            if ((Get-ManagedRouteField (Get-ManagedRouteField $receipt 'complete') $key) -ne $true) { $reasons.Add('migration-status-incomplete') }
        }
        if (-not (Test-ManagedRouteEqual (Get-ManagedRouteField $receipt 'defaultSelection') $futureDefault)) { $reasons.Add('default-evidence-disagrees') }
        $routeFacts = Get-ManagedRouteField $receipt 'routes'
        if ((Get-ManagedRouteField $routeFacts 'managedRegistered') -ne $true -or
            (Get-ManagedRouteField $routeFacts 'nativeRegistered') -cne [bool]$nativeRegistered -or
            (Get-ManagedRouteField $routeFacts 'nativeConfigured') -cne [bool]($null -ne $effective)) { $reasons.Add('runtime-route-evidence-disagrees') }
        foreach ($session in (Get-ManagedRouteField $receipt 'sessions')) {
            $id = Get-ManagedRouteField $session 'id'
            $selection = Get-ManagedRouteField $session 'effectiveSelection'
            $selectionSource = Get-ManagedRouteField $session 'selectionSource'
            if ($null -eq $selection -or $selectionSource -ceq 'unknown') {
                $reasons.Add('session-selection-unknown'); $dependencies.Add(@{ sessionId = $id; reason = 'unknown-effective-selection' })
            } elseif ((Get-ManagedRouteField $selection 'provider') -ceq 'github-copilot') {
                $reasons.Add('native-session-dependency'); $dependencies.Add(@{ sessionId = $id; reason = 'native-effective-selection' })
            }
            if ((Get-ManagedRouteField $selection 'provider') -ceq 'github-copilot-preview' -and
                $modelIds -cnotcontains (Get-ManagedRouteField $selection 'model')) { $reasons.Add('managed-session-model-unavailable') }
            if ($selectionSource -ceq 'default' -and -not (Test-ManagedRouteEqual $selection $futureDefault)) { $reasons.Add('session-default-evidence-disagrees') }
            if ((Get-ManagedRouteField $session 'status') -ceq 'running') {
                $active = Get-ManagedRouteField $session 'activeRequestSelection'
                if ($null -eq $active) {
                    $reasons.Add('active-request-selection-unknown'); $dependencies.Add(@{ sessionId = $id; reason = 'unknown-active-request' })
                } elseif ((Get-ManagedRouteField $active 'provider') -ceq 'github-copilot') {
                    $reasons.Add('native-active-request-dependency'); $dependencies.Add(@{ sessionId = $id; reason = 'native-active-request' })
                }
            }
        }
    }
    if ($operations.Count -gt 0 -and -not $AcknowledgeColdHistoryLimitation) { $reasons.Add('cold-history-acknowledgement-required') }
    if ((Get-ManagedRouteField $Policy 'releaseVerified') -isnot [bool] -or
        (Get-ManagedRouteField $Policy 'releaseVerified') -ne $true) { $reasons.Add('release-not-verified') }
    if (-not (Test-ManagedRouteArtifactPin $Policy)) { $reasons.Add('release-artifact-pin-invalid') }
    $entries = Get-ManagedRouteField (Get-ManagedRouteField $Snapshot 'inventory') 'entries'
    foreach ($module in @('dsh-github-copilot', '@deepseek-ai/dsh-llm-pi-ai')) {
        $active = @($entries | Where-Object {
            (Get-ManagedRouteField $_ 'moduleName') -ceq $module -and
            (Test-ManagedRouteTrue (Get-ManagedRouteField $_ 'enabled')) -and (Get-ManagedRouteField $_ 'fiberPhase') -ceq 'active'
        })
        if ($active.Count -ne 1) { $reasons.Add('required-plugin-mount-unverified') }
    }
    $uniqueReasons = @($reasons | Select-Object -Unique)
    return [pscustomobject]@{
        status = if ($uniqueReasons.Count -gt 0) { 'blocked' } elseif ($operations.Count -eq 0) { 'already-managed' } else { 'ready' }
        eligible = $uniqueReasons.Count -eq 0
        fullBaseline = 'not-verified'
        atomic = $false
        historyScope = 'live-agents-only'
        coldHistory = 'unchanged-may-require-model-selection-on-resume'
        loadedVersionEvidence = 'plugin-reported-not-byte-attested'
        accountDiscoveryMayRefreshCredentials = Test-ManagedRouteTrue (Get-ManagedRouteField $Snapshot 'accountDiscoveryRequested')
        reasons = $uniqueReasons
        operations = @($operations)
        dependencies = @($dependencies)
        managedModelCount = $modelIds.Count
        sessionChanges = @()
        defaultChange = $false
        directCredentialWrites = $false
        evidenceSource = Get-ManagedRouteField $Snapshot 'source'
    }
}

function Invoke-DshCopilotManagedRouteRpc {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][AllowEmptyCollection()]$Arguments,
        [string]$BaseUri = 'http://127.0.0.1:3080',
        [scriptblock]$Invoker
    )
    if ($Method -cnotin @('settings/describe', 'settings/mutate', 'session/modelCatalog', 'pluginInventory/list', 'githubCopilot/migrationStatus')) {
        throw 'RPC method is outside managed-route maintenance scope.'
    }
    $uri = [uri]$BaseUri
    if (-not $uri.IsAbsoluteUri -or $uri.Scheme -cne 'http' -or $uri.Host -cnotin @('127.0.0.1', 'localhost', '[::1]') -or
        $uri.UserInfo -or $uri.Query -or $uri.Fragment -or $uri.AbsolutePath -cne '/') { throw 'Managed-route RPC requires an explicit HTTP loopback origin.' }
    $id = 'copilot-managed-route-' + [guid]::NewGuid().ToString('N')
    $request = @{ type = 'client-request'; rpcId = $id; method = $Method; payload = @{ args = $Arguments } }
    if ($Invoker) {
        $response = & $Invoker ($BaseUri.TrimEnd('/') + '/api/' + $Method) $request
    } else {
        # The published Typert HTTP carrier uses the same envelope as the Ops
        # restart preflight. No alternate server, auth fallback, or retries.
        try {
            $response = Invoke-RestMethod -Method Post -Uri ($BaseUri.TrimEnd('/') + '/api/' + $Method) `
                -ContentType 'application/json' -Body ($request | ConvertTo-Json -Depth 30 -Compress) `
                -TimeoutSec 20 -MaximumRedirection 0
        } catch {
            throw 'Managed-route HTTP request failed; response details withheld and no retry performed.'
        }
    }
    if (-not (Test-ManagedRouteObject $response) -or (Get-ManagedRouteField $response 'type') -cne 'server-response' -or
        (Get-ManagedRouteField $response 'rpcId') -cne $id) { throw 'Invalid managed-route RPC response envelope.' }
    $result = Get-ManagedRouteField $response 'result'
    $ok = Get-ManagedRouteField $result 'ok'
    if (-not (Test-ManagedRouteObject $result) -or $ok -isnot [bool]) { throw 'Invalid managed-route RPC result.' }
    if (-not $ok) {
        # Provider messages are not echoed: arbitrary RPC failures may include
        # settings values or sensitive response content.
        $code = Get-ManagedRouteField (Get-ManagedRouteField $result 'error') 'code'
        if ($code -ceq 'settings/conflict') { throw 'Managed-route settings/conflict; no retry performed.' }
        throw 'Managed-route RPC rejected or failed; no retry performed.'
    }
    if (@(Get-ManagedRouteKeys $result) -cnotcontains 'value') { throw 'Invalid managed-route RPC result.' }
    return Get-ManagedRouteField $result 'value'
}

function Get-DshCopilotManagedRouteSnapshot {
    [CmdletBinding()]
    param([string]$BaseUri = 'http://127.0.0.1:3080', [scriptblock]$Invoker, [switch]$AllowAccountDiscovery)
    $settings = Invoke-DshCopilotManagedRouteRpc -Method 'settings/describe' -Arguments @{} -BaseUri $BaseUri -Invoker $Invoker
    $inventory = Invoke-DshCopilotManagedRouteRpc -Method 'pluginInventory/list' -Arguments @{} -BaseUri $BaseUri -Invoker $Invoker
    $catalog = if ($AllowAccountDiscovery) {
        Invoke-DshCopilotManagedRouteRpc -Method 'session/modelCatalog' -Arguments @{} -BaseUri $BaseUri -Invoker $Invoker
    } else { $null }
    $receipt = Invoke-DshCopilotManagedRouteRpc -Method 'githubCopilot/migrationStatus' -Arguments @{} -BaseUri $BaseUri -Invoker $Invoker
    return [pscustomobject]@{
        source = 'live-public-rpc'; settings = $settings; inventory = $inventory; catalog = $catalog
        migrationStatus = $receipt; accountDiscoveryRequested = [bool]$AllowAccountDiscovery
    }
}

function Invoke-DshCopilotManagedRouteMigration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Policy,
        [Parameter(Mandatory)][scriptblock]$ReadLiveSnapshot,
        [Parameter(Mandatory)][scriptblock]$Mutate,
        [switch]$ApproveNativeRemoval,
        [switch]$ApproveSearchAllowlist,
        [switch]$AcknowledgeColdHistoryLimitation
    )
    # Callbacks permit isolated fake-transport tests. The CLI supplies only its
    # fresh public-RPC reader, never a saved input file or caller attestation.
    $initial = & $ReadLiveSnapshot
    if ((Get-ManagedRouteField $initial 'source') -cne 'live-public-rpc') { throw 'Apply requires fresh live evidence, not an offline snapshot.' }
    $plan = Get-DshCopilotManagedRoutePlan -Policy $Policy -Snapshot $initial `
        -ApproveNativeRemoval:$ApproveNativeRemoval -ApproveSearchAllowlist:$ApproveSearchAllowlist `
        -AcknowledgeColdHistoryLimitation:$AcknowledgeColdHistoryLimitation
    if (-not $plan.eligible -or $plan.operations.Count -eq 0) { return $plan }
    $completed = [Collections.Generic.List[string]]::new()
    $attempted = $false
    $previous = $initial
    try {
        foreach ($operation in $plan.operations) {
            $fresh = & $ReadLiveSnapshot
            if ((Get-ManagedRouteField $fresh 'source') -cne 'live-public-rpc') { throw 'Fresh live evidence unavailable.' }
            if (-not (Test-ManagedRouteUnownedFieldsEqual (Get-ManagedRouteField $previous 'migrationStatus') (Get-ManagedRouteField $fresh 'migrationStatus') 'observedAt')) {
                throw 'Runtime migration status changed after preflight.'
            }
            foreach ($field in @('settings', 'inventory', 'catalog')) {
                if (-not (Test-ManagedRouteEqual (Get-ManagedRouteField $previous $field) (Get-ManagedRouteField $fresh $field))) {
                    throw 'State changed after preflight.'
                }
            }
            $currentPlan = Get-DshCopilotManagedRoutePlan -Policy $Policy -Snapshot $fresh `
                -ApproveNativeRemoval:$ApproveNativeRemoval -ApproveSearchAllowlist:$ApproveSearchAllowlist `
        -AcknowledgeColdHistoryLimitation:$AcknowledgeColdHistoryLimitation
            if (-not $currentPlan.eligible) { throw 'Preconditions no longer hold.' }
            $descriptor = Get-ManagedRouteDescriptor (Get-ManagedRouteField $fresh 'settings') $operation.ns
            $attempted = $true
            & $Mutate $operation.ns $operation.ops (Get-ManagedRouteField $descriptor 'revision') | Out-Null
            $completed.Add($operation.ns)
            $after = & $ReadLiveSnapshot
            if ((Get-ManagedRouteField $after 'source') -cne 'live-public-rpc') { throw 'Live readback unavailable.' }
            # Unrelated namespaces and all Session selections must survive each
            # stage. Never compensate by replacing a namespace or Session log.
            foreach ($field in @('sessions', 'defaultSelection', 'plugin', 'capabilities', 'complete')) {
                if (-not (Test-ManagedRouteEqual (Get-ManagedRouteField (Get-ManagedRouteField $fresh 'migrationStatus') $field) (Get-ManagedRouteField (Get-ManagedRouteField $after 'migrationStatus') $field))) {
                    throw 'Session, default, or runtime capability changed during migration.'
                }
            }
            foreach ($beforeDescriptor in (Get-ManagedRouteField (Get-ManagedRouteField $fresh 'settings') 'namespaces')) {
                $ns = Get-ManagedRouteField $beforeDescriptor 'ns'
                $afterDescriptor = Get-ManagedRouteDescriptor (Get-ManagedRouteField $after 'settings') $ns
                if ($ns -cne $operation.ns -and -not (Test-ManagedRouteEqual $beforeDescriptor $afterDescriptor)) { throw 'Unrelated settings changed during migration.' }
                if ($ns -ceq $operation.ns) {
                    $beforeUser = Get-ManagedRouteField $beforeDescriptor 'user'
                    $afterUser = Get-ManagedRouteField $afterDescriptor 'user'
                    if (-not (Test-ManagedRouteUnownedFieldsEqual $beforeUser $afterUser 'providers')) { throw 'Unrelated settings leaf changed.' }
                    foreach ($unchangedField in @('base', 'secrets')) {
                        if (-not (Test-ManagedRouteEqual (Get-ManagedRouteField $beforeDescriptor $unchangedField) (Get-ManagedRouteField $afterDescriptor $unchangedField))) {
                            throw 'Settings inheritance or secret status changed.'
                        }
                    }
                    if ($ns -ceq 'llm-pi-ai') {
                        $beforeProviders = Get-ManagedRouteField $beforeUser 'providers'
                        $afterProviders = Get-ManagedRouteField $afterUser 'providers'
                        if (-not (Test-ManagedRouteUnownedFieldsEqual $beforeProviders $afterProviders 'github-copilot')) { throw 'Unrelated provider changed.' }
                    }
                }
            }
            $post = Get-DshCopilotManagedRoutePlan -Policy $Policy -Snapshot $after `
                -ApproveNativeRemoval:$ApproveNativeRemoval -ApproveSearchAllowlist:$ApproveSearchAllowlist `
        -AcknowledgeColdHistoryLimitation:$AcknowledgeColdHistoryLimitation
            if (-not $post.eligible -or @($post.operations | Where-Object { $_.ns -ceq $operation.ns }).Count -gt 0) { throw 'Mutation readback did not satisfy the requested stage.' }
            $previous = $after
        }
        return [pscustomobject]@{
            status = 'applied'; fullBaseline = 'not-verified'; atomic = $false
            historyScope = 'live-agents-only'; coldHistory = 'unchanged-may-require-model-selection-on-resume'
            loadedVersionEvidence = 'plugin-reported-not-byte-attested'
            completedNamespaces = @($completed); reasons = @(); sessionChanges = @(); defaultChange = $false; directCredentialWrites = $false
            accountDiscoveryMayRefreshCredentials = Test-ManagedRouteTrue (Get-ManagedRouteField $initial 'accountDiscoveryRequested')
        }
    } catch {
        return [pscustomobject]@{
            status = if ($attempted) { 'partial-or-uncertain-review-required' } else { 'blocked-state-changed' }
            fullBaseline = 'not-verified'; atomic = $false; completedNamespaces = @($completed)
            historyScope = 'live-agents-only'; coldHistory = 'unchanged-may-require-model-selection-on-resume'
            accountDiscoveryMayRefreshCredentials = Test-ManagedRouteTrue (Get-ManagedRouteField $initial 'accountDiscoveryRequested')
            reasons = @('migration-did-not-complete-recheck-live-state'); automaticRollback = $false
            sessionChanges = @(); defaultChange = $false; directCredentialWrites = $false
        }
    }
}

Export-ModuleMember -Function @(
    'Test-DshCopilotManagedRoutePolicy', 'Get-DshCopilotManagedRoutePlan',
    'Invoke-DshCopilotManagedRouteRpc', 'Get-DshCopilotManagedRouteSnapshot',
    'Invoke-DshCopilotManagedRouteMigration'
)
