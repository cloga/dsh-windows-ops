Import-Module (Join-Path $PSScriptRoot '..\tools\DshCopilotManagedRoute.psm1') -Force

Describe 'Config-only Copilot managed-route maintenance' {
    BeforeEach {
        $script:policy = [pscustomobject]@{
            schemaVersion = 1; purpose = 'config-only-managed-route-maintenance'
            nativeProvider = 'github-copilot'; managedProvider = 'github-copilot-preview'
            plugin = @{ name = 'dsh-github-copilot'; version = '0.4.0-alpha.9'; artifact = @{
                name = 'dsh-github-copilot-0.4.0-alpha.9.tgz'
                url = 'https://github.com/cloga/dsh-github-copilot/releases/download/v0.4.0-alpha.9/dsh-github-copilot-0.4.0-alpha.9.tgz'
                sha256 = ('a' * 64); size = 1234; releaseTag = 'v0.4.0-alpha.9'; releaseCommit = ('b' * 40); releaseImmutable = $true
                checksumManifest = @{ name = 'SHA256SUMS'; url = 'https://github.com/cloga/dsh-github-copilot/releases/download/v0.4.0-alpha.9/SHA256SUMS'; sha256 = ('c' * 64); size = 103 }
            } }
            supportedCoreVersions = @('0.1.3-alpha.1'); migrationStatusProtocol = 1; releaseVerified = $true
            requiredCapabilities = @('agentsList', 'sessionProjections', 'settingsCas', 'providerRegistry', 'defaultSelection')
            search = @{ namespace = 'github-copilot'; path = @('providers'); from = @('github-copilot'); to = @('github-copilot-preview') }
        }
        $script:snapshot = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\copilot-managed-route\ready.json') -Raw | ConvertFrom-Json
        $script:mutations = [Collections.Generic.List[object]]::new()
        $script:reads = 0
        $script:reader = {
            $script:reads++
            $script:snapshot | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        }
        $script:mutator = {
            param($ns, $ops, $revision)
            $script:mutations.Add(@{ ns = $ns; ops = $ops; expectedRevision = $revision })
            $descriptor = @($script:snapshot.settings.namespaces | Where-Object ns -CEQ $ns)[0]
            if ($descriptor.revision -ne $revision) { throw 'settings/conflict' }
            if ($ns -ceq 'github-copilot') {
                $descriptor.user | Add-Member -NotePropertyName providers -NotePropertyValue @('github-copilot-preview') -Force
                $descriptor.value.providers = @('github-copilot-preview')
            } else {
                $descriptor.user.providers.PSObject.Properties.Remove('github-copilot')
                $descriptor.value.providers.PSObject.Properties.Remove('github-copilot')
                $script:snapshot.catalog.routableProviders = @($script:snapshot.catalog.routableProviders | Where-Object { $_ -cne 'github-copilot' })
                $script:snapshot.catalog.groups = @($script:snapshot.catalog.groups | Where-Object id -CNE 'github-copilot')
                $script:snapshot.migrationStatus.routes.nativeConfigured = $false
                $script:snapshot.migrationStatus.routes.nativeRegistered = $false
            }
            $descriptor.revision++
        }
    }

    It 'plans only an approved exact allowlist and native user-path removal' {
        $before = $snapshot | ConvertTo-Json -Depth 30
        $result = Get-DshCopilotManagedRoutePlan $policy $snapshot -ApproveNativeRemoval -ApproveSearchAllowlist -AcknowledgeColdHistoryLimitation
        $result.status | Should -Be 'ready'
        $result.fullBaseline | Should -Be 'not-verified'
        @($result.operations.ns) | Should -Be @('github-copilot', 'llm-pi-ai')
        @($result.operations[0].ops[0].value) | Should -Be @('github-copilot-preview')
        @($result.operations[1].ops[0].path) | Should -Be @('providers', 'github-copilot')
        $result.operations[1].expectedRevision | Should -Be 7
        $result.defaultChange | Should -Be $false
        $result.directCredentialWrites | Should -Be $false
        $snapshot | ConvertTo-Json -Depth 30 | Should -Be $before
    }

    It 'rejects non-boolean writability and inventory enablement without mutation' {
        foreach ($flag in @(1, 0, 'True', 'False', $null)) {
            $snapshot.settings.writable = $flag
            $result = Get-DshCopilotManagedRoutePlan $policy $snapshot -ApproveNativeRemoval -ApproveSearchAllowlist -AcknowledgeColdHistoryLimitation
            $result.eligible | Should -Be $false
            $result.reasons | Should -Contain 'settings-not-writable'
            $snapshot.settings.writable = $true
            $snapshot.inventory.entries[0].enabled = $flag
            $result = Get-DshCopilotManagedRoutePlan $policy $snapshot -ApproveNativeRemoval -ApproveSearchAllowlist -AcknowledgeColdHistoryLimitation
            $result.eligible | Should -Be $false
            $snapshot.inventory.entries[0].enabled = $true
        }
        $mutations.Count | Should -Be 0
    }

    It 'rejects non-boolean secret and native compatibility flags' {
        foreach ($flag in @(1, 0, 'True', 'False', $null)) {
            $snapshot.settings.namespaces[0].secrets = @(@{ path = @('providers', 'github-copilot', 'apiKey'); set = $flag })
            (Get-DshCopilotManagedRoutePlan $policy $snapshot).reasons | Should -Contain 'secret-status-unverified'
            $snapshot.settings.namespaces[0].secrets = @()
            $snapshot.settings.namespaces[0].user.providers.'github-copilot'.compat.supportsStrictMode = $flag
            (Get-DshCopilotManagedRoutePlan $policy $snapshot).reasons | Should -Contain 'native-user-profile-not-reviewed'
            $snapshot.settings.namespaces[0].user.providers.'github-copilot'.compat.supportsStrictMode = $false
        }
    }

    It 'requires separate removal and allowlist approvals' {
        $result = Get-DshCopilotManagedRoutePlan $policy $snapshot
        $result.reasons | Should -Contain 'native-removal-approval-required'
        $result.reasons | Should -Contain 'search-allowlist-approval-required'
    }

    It 'rejects unsupported policy pins and silent allowlist expansion' {
        $policy.plugin.version = '0.3.0-cloga.15'
        { Test-DshCopilotManagedRoutePolicy $policy } | Should -Throw
    }

    It 'rejects arbitrary allowlists including the empty follow-current list' {
        $snapshot.settings.namespaces[1].value.providers = @()
        (Get-DshCopilotManagedRoutePlan $policy $snapshot -ApproveNativeRemoval -ApproveSearchAllowlist -AcknowledgeColdHistoryLimitation).reasons |
            Should -Contain 'search-allowlist-not-reviewed'
    }

    It 'rejects inherited native profiles and ownership journals in any layer' {
        $snapshot.settings.namespaces[0].base.providers | Add-Member -NotePropertyName github-copilot -NotePropertyValue @{}
        (Get-DshCopilotManagedRoutePlan $policy $snapshot).reasons | Should -Contain 'inherited-native-profile'
        foreach ($layer in @('base', 'user', 'value')) {
            $snapshot.settings.namespaces[1].$layer | Add-Member -NotePropertyName temporaryRouteBackup -NotePropertyValue 'not-even-valid-json' -Force
            (Get-DshCopilotManagedRoutePlan $policy $snapshot).reasons | Should -Contain 'route-ownership-journal-present'
            $snapshot.settings.namespaces[1].$layer.PSObject.Properties.Remove('temporaryRouteBackup')
        }
    }

    It 'refuses secret-bearing or unreviewed native profiles without displaying secrets' {
        $snapshot.settings.namespaces[0].secrets = @(@{ path = @('providers', 'github-copilot', 'apiKey'); set = $true })
        $snapshot.settings.namespaces[0].user.providers.'github-copilot' | Add-Member -NotePropertyName headers -NotePropertyValue @{ Authorization = 'SYNTHETIC-DO-NOT-PRINT' }
        $result = Get-DshCopilotManagedRoutePlan $policy $snapshot
        $result.reasons | Should -Contain 'native-profile-has-secrets'
        $result.reasons | Should -Contain 'native-user-profile-not-reviewed'
        $result | ConvertTo-Json -Depth 20 | Should -Not -Match 'SYNTHETIC-DO-NOT-PRINT'
    }

    It 'rejects missing duplicate or revisionless settings namespaces' {
        $snapshot.settings.namespaces += $snapshot.settings.namespaces[0]
        (Get-DshCopilotManagedRoutePlan $policy $snapshot).reasons | Should -Contain 'settings-descriptor-missing-duplicate-or-invalid'
        $snapshot.settings.namespaces = @($snapshot.settings.namespaces[0..2])
        $snapshot.settings.namespaces[0].PSObject.Properties.Remove('revision')
        (Get-DshCopilotManagedRoutePlan $policy $snapshot).reasons | Should -Contain 'settings-descriptor-missing-duplicate-or-invalid'
    }

    It 'requires actual managed catalog evidence instead of a manually populated native model list' {
        $snapshot.catalog = $null
        $result = Get-DshCopilotManagedRoutePlan $policy $snapshot
        $result.reasons | Should -Contain 'catalog-unverified'
        $result.eligible | Should -Be $false
    }

    It 'rejects managed failures and duplicate managed groups' {
        $snapshot.catalog.failures = @(@{ id = 'github-copilot-preview'; name = 'Copilot'; message = 'unavailable' })
        $snapshot.catalog.groups += $snapshot.catalog.groups[1]
        $result = Get-DshCopilotManagedRoutePlan $policy $snapshot
        $result.reasons | Should -Contain 'managed-catalog-failed'
        $result.reasons | Should -Contain 'managed-route-unavailable-or-duplicate'
    }

    It 'reports native defaults without automatically selecting a model' {
        $snapshot.catalog.default.provider = 'github-copilot'
        $snapshot.settings.namespaces[2].value.provider = 'github-copilot'
        $result = Get-DshCopilotManagedRoutePlan $policy $snapshot
        $result.reasons | Should -Contain 'native-future-default-dependency'
        $result.defaultChange | Should -Be $false
    }

    It 'refuses native effective selection and an unknown running request' {
        $snapshot.migrationStatus.sessions = @(@{
            id = 'fixture-session'; status = 'running'; selectionSource = 'pending'
            effectiveSelection = @{ provider = 'github-copilot'; model = 'account-model' }; activeRequestSelection = $null
        })
        $result = Get-DshCopilotManagedRoutePlan $policy $snapshot
        $result.reasons | Should -Contain 'native-session-dependency'
        $result.reasons | Should -Contain 'active-request-selection-unknown'
        $snapshot.migrationStatus.sessions[0].effectiveSelection = $null
        $snapshot.migrationStatus.sessions[0].selectionSource = 'unknown'
        (Get-DshCopilotManagedRoutePlan $policy $snapshot).reasons | Should -Contain 'session-selection-unknown'
    }

    It 'permits a known managed running caller but not its still-native active request' {
        $selection = @{ provider = 'github-copilot-preview'; model = 'account-model' }
        $snapshot.migrationStatus.sessions = @(@{
            id = 'fixture-session'; status = 'running'; selectionSource = 'pending'
            effectiveSelection = $selection; activeRequestSelection = $selection
        })
        (Get-DshCopilotManagedRoutePlan $policy $snapshot -ApproveNativeRemoval -ApproveSearchAllowlist -AcknowledgeColdHistoryLimitation).status | Should -Be 'ready'
        $snapshot.migrationStatus.sessions[0].activeRequestSelection = @{ provider = 'github-copilot'; model = 'account-model' }
        (Get-DshCopilotManagedRoutePlan $policy $snapshot).reasons | Should -Contain 'native-active-request-dependency'
    }

    It 'refuses a managed Session model missing from fresh account metadata' {
        $snapshot.migrationStatus.sessions = @(@{
            id = 'fixture-session'; status = 'idle'; selectionSource = 'pending'
            effectiveSelection = @{ provider = 'github-copilot-preview'; model = 'no-longer-available' }; activeRequestSelection = $null
        })
        (Get-DshCopilotManagedRoutePlan $policy $snapshot).reasons | Should -Contain 'managed-session-model-unavailable'
    }

    It 'rejects malformed receipt flags unknown fields and duplicate live identities' {
        $snapshot.migrationStatus.capabilities.settingsCas = 'true'
        (Get-DshCopilotManagedRoutePlan $policy $snapshot).reasons | Should -Contain 'migration-status-invalid-or-version-mismatch'
        $snapshot.migrationStatus.capabilities.settingsCas = $true
        $snapshot.migrationStatus | Add-Member -NotePropertyName unexpected -NotePropertyValue 'ignored-proof-is-not-proof'
        (Get-DshCopilotManagedRoutePlan $policy $snapshot).reasons | Should -Contain 'migration-status-invalid-or-version-mismatch'
        $snapshot.migrationStatus.PSObject.Properties.Remove('unexpected')
        $session = @{ id = 'duplicate'; status = 'idle'; selectionSource = 'default'; effectiveSelection = @{ provider = 'github-copilot-preview'; model = 'account-model' }; activeRequestSelection = $null }
        $snapshot.migrationStatus.sessions = @($session, $session)
        (Get-DshCopilotManagedRoutePlan $policy $snapshot).reasons | Should -Contain 'migration-status-invalid-or-version-mismatch'
    }

    It 'requires cold history acknowledgement without changing or opening cold Sessions' {
        (Get-DshCopilotManagedRoutePlan $policy $snapshot -ApproveNativeRemoval -ApproveSearchAllowlist).reasons | Should -Contain 'cold-history-acknowledgement-required'
    }

    It 'refuses mismatched loaded plugin versions or a disabled OAuth owner mount' {
        $snapshot.migrationStatus.plugin.version = '0.4.0-alpha.8'
        $snapshot.inventory.entries[1].enabled = $false
        $result = Get-DshCopilotManagedRoutePlan $policy $snapshot
        $result.reasons | Should -Contain 'migration-status-invalid-or-version-mismatch'
        $result.reasons | Should -Contain 'required-plugin-mount-unverified'
    }

    It 'rejects incomplete public evidence and never trusts caller attestation booleans' {
        $snapshot.migrationStatus.complete.sessions = $false
        $snapshot | Add-Member -NotePropertyName evidence -NotePropertyValue @{ loadedArtifactVerified = $true; sessionSelectionsFresh = $true }
        (Get-DshCopilotManagedRoutePlan $policy $snapshot).reasons | Should -Contain 'migration-status-incomplete'
        $snapshot.migrationStatus.capabilities.settingsCas = $false
        (Get-DshCopilotManagedRoutePlan $policy $snapshot).reasons | Should -Contain 'required-public-capability-unavailable'
    }

    It 'requires verified immutable release metadata and rejects unversioned artifact URLs' {
        $policy.releaseVerified = $false
        (Get-DshCopilotManagedRoutePlan $policy $snapshot).reasons | Should -Contain 'release-not-verified'
        $policy.plugin.artifact.url = 'https://example.com/latest.tgz'
        (Get-DshCopilotManagedRoutePlan $policy $snapshot).reasons | Should -Contain 'release-artifact-pin-invalid'
    }

    It 'does not treat an offline ready snapshot as Apply authority' {
        { Invoke-DshCopilotManagedRouteMigration $policy $reader $mutator -ApproveNativeRemoval -ApproveSearchAllowlist -AcknowledgeColdHistoryLimitation } | Should -Throw '*fresh live*'
        $mutations.Count | Should -Be 0
    }

    It 'performs ordered CAS stages with fresh reads and is idempotent' {
        $script:snapshot.source = 'live-public-rpc'
        $result = Invoke-DshCopilotManagedRouteMigration $policy $reader $mutator -ApproveNativeRemoval -ApproveSearchAllowlist -AcknowledgeColdHistoryLimitation
        $result.status | Should -Be 'applied'
        @($mutations.ns) | Should -Be @('github-copilot', 'llm-pi-ai')
        @($mutations.expectedRevision) | Should -Be @(3, 7)
        $reads | Should -Be 5
        $snapshot.settings.namespaces[0].user.providers.fixture.displayName | Should -Be 'Preserved provider'
        $snapshot.settings.namespaces[2].revision | Should -Be 2
        $again = Invoke-DshCopilotManagedRouteMigration $policy $reader $mutator
        $again.status | Should -Be 'already-managed'
        $mutations.Count | Should -Be 2
    }

    It 'executes the complete live-reader CAS flow through fake published RPC envelopes' {
        $script:wireMethods = [Collections.Generic.List[string]]::new()
        $script:wireInvoker = {
            param($uri, $request)
            $script:wireMethods.Add($request.method)
            $value = switch ($request.method) {
                'settings/describe' { $script:snapshot.settings }
                'pluginInventory/list' { $script:snapshot.inventory }
                'session/modelCatalog' { $script:snapshot.catalog }
                'githubCopilot/migrationStatus' { $script:snapshot.migrationStatus.observedAt++; $script:snapshot.migrationStatus }
                'settings/mutate' {
                    $parameters = $request.payload.args
                    & $script:mutator $parameters.ns $parameters.ops $parameters.expectedRevision
                    @($script:snapshot.settings.namespaces | Where-Object ns -CEQ $parameters.ns)[0]
                }
                default { throw 'Unexpected RPC method' }
            }
            @{ type = 'server-response'; rpcId = $request.rpcId; result = @{ ok = $true; value = $value } } | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        }
        $readWire = { Get-DshCopilotManagedRouteSnapshot -Invoker $script:wireInvoker -AllowAccountDiscovery }
        $writeWire = {
            param($ns, $ops, $revision)
            Invoke-DshCopilotManagedRouteRpc -Method 'settings/mutate' -Arguments @{ ns = $ns; ops = $ops; expectedRevision = $revision } -Invoker $script:wireInvoker
        }
        $result = Invoke-DshCopilotManagedRouteMigration $policy $readWire $writeWire -ApproveNativeRemoval -ApproveSearchAllowlist -AcknowledgeColdHistoryLimitation
        $result.status | Should -Be 'applied'
        @($wireMethods | Where-Object { $_ -eq 'githubCopilot/migrationStatus' }).Count | Should -Be 5
        @($wireMethods | Where-Object { $_ -eq 'settings/mutate' }).Count | Should -Be 2
        @($wireMethods) | Should -Not -Contain 'session/selectModel'
    }

    It 'fails closed before mutation on changed preflight evidence' {
        $script:snapshot.source = 'live-public-rpc'
        $changingReader = {
            $script:reads++
            if ($script:reads -eq 2) { $script:snapshot.settings.namespaces[0].revision++ }
            $script:snapshot | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        }
        $result = Invoke-DshCopilotManagedRouteMigration $policy $changingReader $mutator -ApproveNativeRemoval -ApproveSearchAllowlist -AcknowledgeColdHistoryLimitation
        $result.status | Should -Be 'blocked-state-changed'
        $mutations.Count | Should -Be 0
    }

    It 'reports uncertain mutation failure without retry or automatic compensation' {
        $script:snapshot.source = 'live-public-rpc'
        $failing = { param($ns, $ops, $revision); $script:mutations.Add($ns); throw 'settings/conflict' }
        $result = Invoke-DshCopilotManagedRouteMigration $policy $reader $failing -ApproveNativeRemoval -ApproveSearchAllowlist -AcknowledgeColdHistoryLimitation
        $result.status | Should -Be 'partial-or-uncertain-review-required'
        $result.automaticRollback | Should -Be $false
        $mutations.Count | Should -Be 1
    }

    It 'reports partial completion when native removal is rejected after allowlist change' {
        $script:snapshot.source = 'live-public-rpc'
        $secondFailure = {
            param($ns, $ops, $revision)
            if ($ns -ceq 'llm-pi-ai') { throw 'settings/conflict' }
            & $script:mutator $ns $ops $revision
        }
        $result = Invoke-DshCopilotManagedRouteMigration $policy $reader $secondFailure -ApproveNativeRemoval -ApproveSearchAllowlist -AcknowledgeColdHistoryLimitation
        $result.status | Should -Be 'partial-or-uncertain-review-required'
        @($result.completedNamespaces) | Should -Be @('github-copilot')
        $snapshot.settings.namespaces[0].user.providers.'github-copilot' | Should -Not -BeNullOrEmpty
    }

    It 'detects unrelated provider changes and never restores over the new user state' {
        $script:snapshot.source = 'live-public-rpc'
        $altering = {
            param($ns, $ops, $revision)
            & $script:mutator $ns $ops $revision
            if ($ns -ceq 'llm-pi-ai') {
                $script:snapshot.settings.namespaces[0].user.providers.fixture.displayName = 'Concurrent edit'
            }
        }
        $result = Invoke-DshCopilotManagedRouteMigration $policy $reader $altering -ApproveNativeRemoval -ApproveSearchAllowlist -AcknowledgeColdHistoryLimitation
        $result.status | Should -Be 'partial-or-uncertain-review-required'
        $result.automaticRollback | Should -Be $false
        $snapshot.settings.namespaces[0].user.providers.fixture.displayName | Should -Be 'Concurrent edit'
    }

    It 'rejects a successful write response when the requested leaf did not change' {
        $script:snapshot.source = 'live-public-rpc'
        $noOp = { param($ns, $ops, $revision); $script:mutations.Add($ns) }
        $result = Invoke-DshCopilotManagedRouteMigration $policy $reader $noOp -ApproveNativeRemoval -ApproveSearchAllowlist -AcknowledgeColdHistoryLimitation
        $result.status | Should -Be 'partial-or-uncertain-review-required'
        $mutations.Count | Should -Be 1
    }

    It 'detects a native route that remains registered after user-path removal' {
        & $mutator 'github-copilot' @() 3
        & $mutator 'llm-pi-ai' @() 7
        $snapshot.catalog.routableProviders += 'github-copilot'
        (Get-DshCopilotManagedRoutePlan $policy $snapshot).reasons | Should -Contain 'native-registry-route-remains'
    }
}

Describe 'Published Typert RPC carrier for managed-route maintenance' {
    It 'uses the published argument map and checks response correlation' {
        $fake = {
            param($uri, $request)
            $uri | Should -Be 'http://127.0.0.1:3080/api/settings/mutate'
            $request.type | Should -Be 'client-request'
            $request.payload.args.ns | Should -Be 'llm-pi-ai'
            $request.payload.args.expectedRevision | Should -Be 9
            @{ type = 'server-response'; rpcId = $request.rpcId; result = @{ ok = $true; value = @{ revision = 10 } } }
        }
        $result = Invoke-DshCopilotManagedRouteRpc -Method 'settings/mutate' -Arguments @{
            ns = 'llm-pi-ai'; ops = @(@{ op = 'unset'; path = @('providers', 'github-copilot') }); expectedRevision = 9
        } -Invoker $fake
        $result.revision | Should -Be 10
    }

    It 'rejects correlated RPC responses with coerced success flags or non-object results' {
        $script:rpcCalls = 0
        foreach ($flag in @(1, 0, 'True', 'False', $null)) {
            $script:invalidOk = $flag
            $fake = {
                param($uri, $request)
                $script:rpcCalls++
                @{ type = 'server-response'; rpcId = $request.rpcId; result = @{ ok = $script:invalidOk; value = @{ revision = 10 } } }
            }
            { Invoke-DshCopilotManagedRouteRpc -Method 'settings/describe' -Arguments @{} -Invoker $fake } | Should -Throw '*Invalid managed-route RPC result*'
        }
        foreach ($value in @(1, 'True', @(@{ ok = $true; value = @{} }), $null)) {
            $script:invalidResult = $value
            $fake = {
                param($uri, $request)
                $script:rpcCalls++
                @{ type = 'server-response'; rpcId = $request.rpcId; result = $script:invalidResult }
            }
            { Invoke-DshCopilotManagedRouteRpc -Method 'settings/describe' -Arguments @{} -Invoker $fake } | Should -Throw '*Invalid managed-route RPC result*'
        }
        $script:rpcCalls | Should -Be 9
    }

    It 'rejects mismatched response IDs and settings conflicts without revealing raw errors' {
        $bad = { param($uri, $request); @{ type = 'server-response'; rpcId = 'wrong'; result = @{ ok = $true; value = @{} } } }
        { Invoke-DshCopilotManagedRouteRpc -Method 'settings/describe' -Arguments @{} -Invoker $bad } | Should -Throw '*envelope*'
        $conflict = { param($uri, $request); @{ type = 'server-response'; rpcId = $request.rpcId; result = @{ ok = $false; error = @{ code = 'settings/conflict'; message = 'SENSITIVE' } } } }
        { Invoke-DshCopilotManagedRouteRpc -Method 'settings/describe' -Arguments @{} -Invoker $conflict } | Should -Throw '*settings/conflict*'
    }

    It 'refuses unrelated RPC methods and non-loopback destinations' {
        { Invoke-DshCopilotManagedRouteRpc -Method 'session/selectModel' -Arguments @{} } | Should -Throw '*outside*'
        { Invoke-DshCopilotManagedRouteRpc -Method 'settings/describe' -Arguments @{} -BaseUri 'https://example.com' } | Should -Throw '*loopback*'
    }

    It 'keeps passive live Check free of model discovery and reads the actual migration Remote' {
        $script:called = [Collections.Generic.List[string]]::new()
        $fake = {
            param($uri, $request)
            $script:called.Add($request.method)
            $request.payload.args.Count | Should -Be 0
            @{ type = 'server-response'; rpcId = $request.rpcId; result = @{ ok = $true; value = @{} } }
        }
        $result = Get-DshCopilotManagedRouteSnapshot -Invoker $fake
        @($called) | Should -Be @('settings/describe', 'pluginInventory/list', 'githubCopilot/migrationStatus')
        $result.catalog | Should -BeNullOrEmpty
        $result.accountDiscoveryRequested | Should -Be $false
        $result.PSObject.Properties.Name | Should -Contain 'migrationStatus'
    }
}
