Import-Module (Join-Path $PSScriptRoot '..\tools\DshCopilotBootstrap.psm1') -Force

Describe 'DSH Copilot bootstrap' {
    BeforeEach {
        $script:root = Join-Path $TestDrive 'dsh'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
    }

    It 'removes only reviewed legacy route state and never writes provider transport settings' {
        $settings = Join-Path $root 'settings.yaml'
        @'
locale:
  language: en-US
llm-pi-ai:
  providers:
    fixture:
      models:
        - id: fixture
    github-copilot:
      apiKeyEnv: COPILOT_GITHUB_TOKEN
      api: openai-responses
      baseURL: http://127.0.0.1:7777/v1
      models:
        - id: legacy
    github-copilot-chat:
      apiKeyEnv: COPILOT_GITHUB_TOKEN
      baseURL: http://127.0.0.1:7777/v1
'@ | Set-Content -LiteralPath $settings -Encoding UTF8
        $result = Remove-DshLegacyCopilotSettings -Path $settings
        $text = Get-Content -LiteralPath $settings -Raw
        $result.removedRoutes | Should -Contain 'github-copilot'
        $result.removedRoutes | Should -Contain 'github-copilot-chat'
        $text | Should -Match 'fixture:'
        $text | Should -Not -Match 'COPILOT_GITHUB_TOKEN|127\.0\.0\.1:7777|github-copilot-chat'
    }

    It 'previews legacy settings cleanup without mutation' {
        $settings = Join-Path $root 'settings.yaml'
        @'
# dsh-windows-ops: copilot settings begin
legacy
# dsh-windows-ops: copilot settings end
'@ | Set-Content -LiteralPath $settings -Encoding UTF8
        $before = Get-Content -LiteralPath $settings -Raw
        (Remove-DshLegacyCopilotSettings -Path $settings -DryRun).status | Should -Be 'would-change'
        Get-Content -LiteralPath $settings -Raw | Should -Be $before
    }

    It 'removes the reviewed legacy credential reference without changing records' {
        $path = Join-Path $root '.credentials.yaml'
        @'
version: 1
refs:
  COPILOT_GITHUB_TOKEN: legacy/copilot
records:
  legacy/copilot:
    kind: api-key
    payload:
      version: 1
      secret: redacted-test-value
'@ | Set-Content -LiteralPath $path -Encoding UTF8

        $result = Remove-DshLegacyCopilotCredentialReference -Path $path
        $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8

        $result.changed | Should -Be $true
        $text | Should -Not -Match '(?m)^\s{2}COPILOT_GITHUB_TOKEN\s*:'
        $text | Should -Match '(?m)^\s{2}legacy/copilot\s*:'
        (Remove-DshLegacyCopilotCredentialReference -Path $path).changed | Should -Be $false
    }

    It 'is idempotent for direct plugin profile patches' {
        $patch = Join-Path $root 'cordis.patch.yml'
        Set-Content -LiteralPath $patch -Value "[]`n" -Encoding UTF8
        (Set-DshCopilotProfilePatch -Path $patch).status | Should -Be 'changed'
        (Set-DshCopilotProfilePatch -Path $patch).status | Should -Be 'unchanged'
    }

    It 'refuses unmanaged conflicts outside an existing managed block' {
        $path = Join-Path $root 'cordis.patch.yml'
        Set-Content -LiteralPath $path -Value "[]`n" -Encoding UTF8
        Set-DshCopilotProfilePatch -Path $path | Out-Null
        Add-Content -LiteralPath $path -Value "`n- id: web`n  config:`n    searchProvider: other"
        $threw = $false
        try {
            Set-DshCopilotProfilePatch -Path $path | Out-Null
        } catch {
            $threw = $true
        }
        $threw | Should -Be $true
    }

    It 'selects hosted Search without disabling the web host or tool' {
        $path = Join-Path $root 'cordis.patch.yml'
        Set-Content -LiteralPath $path -Value "[]`n" -Encoding UTF8
        Set-DshCopilotProfilePatch -Path $path | Out-Null
        $text = Get-Content -LiteralPath $path -Raw
        $text | Should -Match '(?s)- id: web\s+config:\s+searchProvider: github-copilot-hosted'
        $text | Should -Not -Match '(?m)^\s*-\s+id:\s+web-search-deepseek\s*$'
        $text | Should -Not -Match '(?m)^\s*-\s+id:\s+tool-web\s*$'
        $text | Should -Match 'providers: \[github-copilot\]'
    }

    It 'accepts a repaired reference-free route with complete mixed protocol models' {
        $settings = Join-Path $root 'settings.yaml'
        @'
llm-pi-ai:
  providers:
    github-copilot:
      displayName: GitHub Copilot
      models:
        - id: responses-model
          api: openai-responses
        - id: account-model
          api: openai-completions
'@ | Set-Content -LiteralPath $settings -Encoding UTF8
        $route = Get-DshCopilotRouteState -SettingsPath $settings
        $route.referenceFree | Should -Be $true
        $route.modelsComplete | Should -Be $true
        $route.mixedProtocolApis | Should -Be $true
        $route.status | Should -Be 'available'
        (Set-DshCopilotModelSelection -Path $settings -Model account-model).status | Should -Be 'changed'
        { Set-DshCopilotModelSelection -Path $settings -Model unavailable-model } |
            Should -Throw '*not in the signed-in account*'
        $text = Get-Content -LiteralPath $settings -Raw
        $text | Should -Not -Match 'baseURL|apiKeyEnv'
        $text | Should -Match 'provider: github-copilot'
    }

    It 'accepts complete model entries regardless of id and api field order' {
        $settings = Join-Path $root 'settings.yaml'
        @'
llm-pi-ai:
  providers:
    github-copilot:
      models:
        - api: openai-responses
          id: responses-model
        - id: completions-model
          api: openai-completions
'@ | Set-Content -LiteralPath $settings -Encoding UTF8

        $route = Get-DshCopilotRouteState -SettingsPath $settings
        $route.status | Should -Be 'available'
        $route.modelsComplete | Should -Be $true
        $route.mixedProtocolApis | Should -Be $true
        @($route.availableModels) | Should -Be @('responses-model', 'completions-model')
    }

    It 'accepts the plugin-generated flow map and model list route' {
        $settings = Join-Path $root 'settings.yaml'
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixtures\windows-copilot\settings-flow.yaml') `
            -Destination $settings

        $route = Get-DshCopilotRouteState -SettingsPath $settings

        $route.status | Should -Be 'available'
        $route.referenceFree | Should -Be $true
        $route.modelsComplete | Should -Be $true
        $route.mixedProtocolApis | Should -Be $true
        @($route.availableModels) | Should -Be @('gemini-3.6-flash', 'gpt-5.6-sol')
        (Set-DshCopilotModelSelection -Path $settings -Model 'gpt-5.6-sol').status |
            Should -Be 'changed'
    }

    It 'detects forbidden and incomplete fields in flow routes' {
        $settings = Join-Path $root 'settings.yaml'
        @'
llm-pi-ai:
  providers:
    github-copilot:
      {
        apiKeyEnv: COPILOT_GITHUB_TOKEN,
        models: [{ id: good, api: openai-responses }, { id: incomplete }],
      }
'@ | Set-Content -LiteralPath $settings -Encoding UTF8

        $route = Get-DshCopilotRouteState -SettingsPath $settings

        $route.status | Should -Be 'legacy-reference-route'
        $route.referenceFree | Should -Be $false
        $route.modelsComplete | Should -Be $false
        @($route.forbiddenKeys) | Should -Contain 'apiKeyEnv'
    }

    It 'reports empty and incomplete existing-grant routes as repair required' {
        $settings = Join-Path $root 'settings.yaml'
        @'
llm-pi-ai:
  providers:
    github-copilot: {}
'@ | Set-Content -LiteralPath $settings -Encoding UTF8
        $empty = Get-DshCopilotRouteState -SettingsPath $settings
        $empty.exists | Should -Be $true
        $empty.status | Should -Be 'route-has-no-models'

        @'
llm-pi-ai:
  providers:
    github-copilot:
      models:
        - id: responses-model
          api: openai-responses
        - id: incomplete-model
'@ | Set-Content -LiteralPath $settings -Encoding UTF8
        $incomplete = Get-DshCopilotRouteState -SettingsPath $settings
        $incomplete.modelsComplete | Should -Be $false
        $incomplete.status | Should -Be 'route-model-api-missing'
        { Set-DshCopilotModelSelection -Path $settings -Model responses-model } |
            Should -Throw '*complete reference-free mixed-protocol*'

        @'
llm-pi-ai:
  providers:
    github-copilot:
      models:
        - id: responses-model
          api: openai-responses
'@ | Set-Content -LiteralPath $settings -Encoding UTF8
        $singleProtocol = Get-DshCopilotRouteState -SettingsPath $settings
        $singleProtocol.modelsComplete | Should -Be $true
        $singleProtocol.mixedProtocolApis | Should -Be $false
        $singleProtocol.status | Should -Be 'route-mixed-protocol-apis-missing'
    }

    It 'reports only safe metadata for the built-in Copilot grant' {
        $credentialHome = Join-Path $root 'credential-home'
        New-Item -ItemType Directory -Path $credentialHome -Force | Out-Null
        @'
version: 1
records:
  llm-pi-ai/github-copilot:
    kind: grant
    payload:
      availableModelIds:
        - fixture-model
'@ | Set-Content -LiteralPath (Join-Path $credentialHome '.credentials.yaml') -Encoding UTF8

        $result = Test-DshCopilotCredentialRecord -DshHome $credentialHome
        $result.configured | Should -Be $true
        $result.kind | Should -Be 'grant'
        $result.PSObject.Properties.Name | Should -Not -Contain 'payload'
        ($result | ConvertTo-Json) | Should -Not -Match 'fixture-model'
    }

    It 'returns sign-in-required when the Copilot grant is absent' {
        $credentialHome = Join-Path $root 'missing-credential'
        New-Item -ItemType Directory -Path $credentialHome -Force | Out-Null
        (Test-DshCopilotCredentialRecord -DshHome $credentialHome).status |
            Should -Be 'sign-in-required'
    }

    It 'accepts only the exact official Desktop-managed runtime selector' {
        $lock = [pscustomobject]@{
            components = [pscustomobject]@{
                desktop = [pscustomobject]@{
                    defaultRuntimeSelector = 'desktop-official'
                    runtimeSelectors = @([pscustomobject]@{
                        id = 'desktop-official'
                        source = 'desktop-managed-download'
                        root = '%APPDATA%\io.github.hairyf.deepseek-harness-desktop\dependencies\dsh'
                        package = [pscustomobject]@{
                            version = '0.1.2-rc.1'
                            entrypoint = 'node_modules\@deepseek-ai\dsh\lib\bin.js'
                        }
                    })
                }
            }
        }
        $officialRoot = [IO.Path]::GetFullPath(
            [Environment]::ExpandEnvironmentVariables([string]$lock.components.desktop.runtimeSelectors[0].root)
        )
        $official = [pscustomobject]@{
            valid = $true
            selector = 'desktop-official'
            source = 'desktop-managed-download'
            version = '0.1.2-rc.1'
            packageRoot = Join-Path $officialRoot 'node_modules\@deepseek-ai\dsh'
            entryPath = Join-Path $officialRoot 'node_modules\@deepseek-ai\dsh\lib\bin.js'
            processIds = @(12)
        }
        (Test-DshActiveDesktopCore -DeploymentLock $lock `
            -DesktopRuntimeState $official).selector | Should -Be 'desktop-official'

        $official.version = '0.1.2-alpha.6'
        { Test-DshActiveDesktopCore -DeploymentLock $lock `
            -DesktopRuntimeState $official } | Should -Throw '*exact managed path and locked version*'

        $official.version = '0.1.2-rc.1'
        $official.selector = 'controlled-fork'
        { Test-DshActiveDesktopCore -DeploymentLock $lock `
            -DesktopRuntimeState $official } | Should -Throw '*Unsupported Desktop runtime selector*'
    }

    It 'removes local Core resolution and invokes the official entrypoint for plugin commands' {
        Get-Command Resolve-DshCliInfo -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        (Get-Command Test-DshActiveDesktopCore).Parameters.Keys | Should -Not -Contain 'CliInfo'

        $scriptText = Get-Content -LiteralPath (
            Join-Path $PSScriptRoot '..\tools\enable-copilot-search-vision.ps1'
        ) -Raw
        $scriptText | Should -Not -Match 'DshCliPath|Resolve-DshCliInfo|ForkCliInfo|controlled-fork'
        $scriptText | Should -Match (
            [regex]::Escape('& $node.Source $officialRuntime.entryPath plugin')
        )
        $scriptText | Should -Match 'Test-DshRuntimeSchemaState'
    }

    It 'refuses a renderer without the exact SlotOutlet marker' {
        $package = Join-Path $root 'package'
        $renderer = Join-Path $package 'node_modules\@deepseek-ai\dsh-client-ui-renderer\lib'
        $flat = Join-Path $root 'home\profiles\node_modules\@deepseek-ai\dsh-client-ui-renderer\lib'
        New-Item -ItemType Directory -Path $renderer -Force | Out-Null
        New-Item -ItemType Directory -Path $flat -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $renderer 'client.js') -Value 'exports.inject = inject;' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $flat 'client.js') -Value 'exports.inject = inject;' -Encoding UTF8
        $threw = $false
        try {
            Test-DshRendererCompatibility -PackageRoot $package -DshHome (Join-Path $root 'home') | Out-Null
        } catch {
            $threw = $true
        }
        $threw | Should -Be $true
    }

    It 'accepts a hoisted renderer beside the active official package' {
        $package = Join-Path $root 'prefix\node_modules\@deepseek-ai\dsh'
        $renderer = Join-Path $root 'prefix\node_modules\@deepseek-ai\dsh-client-ui-renderer\lib'
        $flat = Join-Path $root 'home\profiles\node_modules\@deepseek-ai\dsh-client-ui-renderer\lib'
        New-Item -ItemType Directory -Path $package -Force | Out-Null
        New-Item -ItemType Directory -Path $renderer -Force | Out-Null
        New-Item -ItemType Directory -Path $flat -Force | Out-Null
        $source = "function SlotOutlet() {}`nexports.SlotOutlet = SlotOutlet;`nreturn module.exports;"
        Set-Content -LiteralPath (Join-Path $renderer 'client.js') -Value $source -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $flat 'client.js') -Value $source -Encoding UTF8

        $result = Test-DshRendererCompatibility -PackageRoot $package -DshHome (Join-Path $root 'home')

        $result.healthy | Should -Be $true
        $result.renderer | Should -Be (Join-Path $renderer 'client.js')
    }

    It 'does not require the controlled flat renderer for the official Desktop runtime' {
        $package = Join-Path $root 'official\node_modules\@deepseek-ai\dsh'
        $renderer = Join-Path $package 'node_modules\@deepseek-ai\dsh-client-ui-renderer\lib'
        New-Item -ItemType Directory -Path $renderer -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $renderer 'client.js') `
            -Value "function SlotOutlet() {}`nexports.SlotOutlet = SlotOutlet;" -Encoding UTF8

        $result = Test-DshRendererCompatibility -PackageRoot $package `
            -DshHome (Join-Path $root 'home') -RequireFlatFallback:$false

        $result.healthy | Should -Be $true
        $result.flatRenderer | Should -BeNullOrEmpty
    }

    It 'backs up and restores every tracked profile file' {
        $file = Join-Path $root 'settings.yaml'
        $state = Join-Path $root 'state'
        Set-Content -LiteralPath $file -Value 'before' -Encoding UTF8
        $backup = New-DshCopilotBackup -Paths @($file) -StateRoot $state
        Set-Content -LiteralPath $file -Value 'after' -Encoding UTF8
        $expected = @([pscustomobject]@{
            path = [IO.Path]::GetFullPath($file)
            exists = $true
            fingerprint = Get-DshCopilotPathFingerprint -Path $file
        })
        Complete-DshCopilotBackup -StateRoot $state -OperationId $backup.operationId -ExpectedStates $expected | Out-Null
        Restore-DshCopilotBackup -StateRoot $state -OperationId $backup.operationId | Out-Null
        (Get-Content -LiteralPath $file -Raw).Trim() | Should -Be 'before'
    }

    It 'refuses rollback after a tracked file changes again' {
        $file = Join-Path $root 'settings.yaml'
        $state = Join-Path $root 'state'
        Set-Content -LiteralPath $file -Value 'before' -Encoding UTF8
        $backup = New-DshCopilotBackup -Paths @($file) -StateRoot $state
        Set-Content -LiteralPath $file -Value 'bootstrap' -Encoding UTF8
        $expected = @([pscustomobject]@{
            path = [IO.Path]::GetFullPath($file)
            exists = $true
            fingerprint = Get-DshCopilotPathFingerprint -Path $file
        })
        Complete-DshCopilotBackup -StateRoot $state -OperationId $backup.operationId -ExpectedStates $expected | Out-Null
        Set-Content -LiteralPath $file -Value 'later-user-change' -Encoding UTF8
        $threw = $false
        try {
            Restore-DshCopilotBackup -StateRoot $state -OperationId $backup.operationId | Out-Null
        } catch {
            $threw = $true
        }
        $threw | Should -Be $true
        (Get-Content -LiteralPath $file -Raw).Trim() | Should -Be 'later-user-change'
    }

    It 'backs up and restores a reviewed legacy provider closure and rejects unknown versions' {
        $lock = Get-Content -LiteralPath (
            Join-Path $PSScriptRoot '..\deployments\windows-copilot.lock.json'
        ) -Raw -Encoding UTF8 | ConvertFrom-Json
        $profile = Join-Path $root 'profiles\web'
        $packageRoot = Join-Path $profile 'node_modules\dsh-web-search-provider'
        New-Item -ItemType Directory -Path (Join-Path $packageRoot 'lib') -Force |
            Out-Null
        '{"version":"0.2.2"}' |
            Set-Content -LiteralPath (Join-Path $packageRoot 'package.json') -Encoding UTF8
        'payload' |
            Set-Content -LiteralPath (Join-Path $packageRoot 'lib\index.js') -Encoding UTF8
        '{"dependencies":{"dsh-web-search-provider":"0.2.2"}}' |
            Set-Content -LiteralPath (Join-Path $profile 'package.json') -Encoding UTF8

        $reviewed = Test-DshReviewedLegacySearchProvider -Lock $lock `
            -ProfileRoot $profile
        $reviewed.present | Should -Be $true
        $reviewed.fingerprint.kind | Should -Be 'directory'

        $state = Join-Path $root 'state'
        $backup = New-DshCopilotBackup -Paths @($packageRoot) -StateRoot $state
        Remove-Item -LiteralPath $packageRoot -Recurse -Force
        $expected = @([pscustomobject]@{
            path = [IO.Path]::GetFullPath($packageRoot)
            exists = $false
            fingerprint = Get-DshCopilotPathFingerprint -Path $packageRoot
        })
        Complete-DshCopilotBackup -StateRoot $state -OperationId $backup.operationId `
            -ExpectedStates $expected | Out-Null
        Restore-DshCopilotBackup -StateRoot $state -OperationId $backup.operationId |
            Out-Null
        (Get-Content -LiteralPath (Join-Path $packageRoot 'lib\index.js') -Raw).Trim() |
            Should -Be 'payload'

        '{"version":"9.9.9"}' |
            Set-Content -LiteralPath (Join-Path $packageRoot 'package.json') -Encoding UTF8
        {
            Test-DshReviewedLegacySearchProvider -Lock $lock -ProfileRoot $profile
        } | Should -Throw '*not in the reviewed migration inventory*'
    }

    It 'tracks Copilot payload directories and uses the global deployment mutex' {
        $scriptText = Get-Content -LiteralPath (
            Join-Path $PSScriptRoot '..\tools\enable-copilot-search-vision.ps1'
        ) -Raw
        $scriptText | Should -Match "node_modules\\dsh-github-copilot"
        $scriptText | Should -Match "Enter-WindowsCopilotDeploymentLock"
        $scriptText | Should -Match "Exit-WindowsCopilotDeploymentLock"
        $scriptText | Should -Match "Test-WindowsCopilotProfileCoherence"
        $scriptText | Should -Match "Save-WindowsCopilotLockedArtifact"
        $scriptText.IndexOf('Test-WindowsCopilotProfileCoherence') |
            Should -BeLessThan $scriptText.IndexOf('Complete-DshCopilotBackup')
    }

    It 'rejects the pre-fix sandbox contract under the required gate' {
        $package = Join-Path $root 'package'
        $sandbox = Join-Path $package 'node_modules\@deepseek-ai\dsh-sandbox\lib'
        $bash = Join-Path $package 'node_modules\@deepseek-ai\dsh-tool-bash\lib'
        $pwsh = Join-Path $package 'node_modules\@deepseek-ai\dsh-tool-pwsh\lib'
        New-Item -ItemType Directory -Path $sandbox, $bash, $pwsh -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $sandbox 'index.js') -Encoding UTF8 -Value @'
export async function approveEscalation(request, approval) {
  if (request.requestedMode === request.effectiveMode) throw new Error('not strictly wider')
  await approval.approver.request()
  return request.requestedMode
}
'@
        foreach ($tool in @(
            [pscustomobject]@{ root = $bash; name = 'bash' },
            [pscustomobject]@{ root = $pwsh; name = 'pwsh' }
        )) {
            Set-Content -LiteralPath (Join-Path $tool.root 'index.js') -Encoding UTF8 -Value @"
const approveEscalation = () => {}
approveEscalation()
export function apply(ctx) {
  ctx.tools.register({
    name: '$($tool.name)',
    parameters: {
      sandbox_permissions: { type: 'string' },
      justification: { type: 'string' },
    },
    async execute(args, exec) {
      return ctx.shell.run(ctx.shell.resolve({
        command: args.command,
        sandboxPolicy: { mode: 'danger-full-access' },
        signal: exec.signal,
      }))
    },
  })
}
"@
        }
        {
            Test-DshSandboxRegression -PackageRoot $package `
                -ProbeScript (Join-Path $PSScriptRoot '..\tools\dsh-sandbox-regression-probe.mjs') -Mode Require
        } | Should -Throw '*sandbox non-widening regression gate*'
    }

    It 'passes omitted non-widening calls and an approved wider sandbox request' {
        $nodeModules = Join-Path $root 'prefix\node_modules'
        $package = Join-Path $nodeModules '@deepseek-ai\dsh'
        $sandbox = Join-Path $nodeModules '@deepseek-ai\dsh-sandbox\lib'
        $bash = Join-Path $nodeModules '@deepseek-ai\dsh-tool-bash\lib'
        $pwsh = Join-Path $nodeModules '@deepseek-ai\dsh-tool-pwsh\lib'
        New-Item -ItemType Directory -Path $package -Force | Out-Null
        New-Item -ItemType Directory -Path $sandbox, $bash, $pwsh -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $sandbox 'index.js') -Encoding UTF8 -Value @'
export async function approveEscalation(request, approval) {
  const wider = {
    'read-only': ['workspace-write', 'danger-full-access'],
    'workspace-write': ['danger-full-access'],
  }
  if (!(wider[request.effectiveMode] ?? []).includes(request.requestedMode)) {
    throw new Error('not strictly wider')
  }
  await approval.approver.request()
  return request.requestedMode
}
'@
        foreach ($tool in @(
            [pscustomobject]@{ root = $bash; name = 'bash' },
            [pscustomobject]@{ root = $pwsh; name = 'pwsh' }
        )) {
            Set-Content -LiteralPath (Join-Path $tool.root 'index.js') -Encoding UTF8 -Value @"
const approveEscalation = () => {}
approveEscalation()
export function apply(ctx) {
  ctx.tools.register({
    name: '$($tool.name)',
    parameters: {
      sandbox_permissions: { type: 'string' },
      justification: { type: 'string' },
    },
    async execute(args, exec) {
      return ctx.shell.run(ctx.shell.resolve({
        command: args.command,
        sandboxPolicy: { mode: 'danger-full-access' },
        signal: exec.signal,
      }))
    },
  })
}
"@
        }
        $result = Test-DshSandboxRegression -PackageRoot $package `
            -ProbeScript (Join-Path $PSScriptRoot '..\tools\dsh-sandbox-regression-probe.mjs') -Mode Require
        $result.status | Should -Be 'passed'
        $result.effectiveMode | Should -Be 'danger-full-access'
        $result.sameMode | Should -Be 'omitted-no-op-explicit-rejected'
        $result.narrowerMode | Should -Be 'omitted-no-op-explicit-rejected'
        $result.sameAndNarrowerApprovalCalls | Should -Be 0
        $result.widerApprovalCalls | Should -Be 1
        @($result.tools).Count | Should -Be 2
        @($result.tools | Where-Object { $_.approvalCalls -ne 0 }).Count | Should -Be 0

        Set-Content -LiteralPath (Join-Path $pwsh 'index.js') -Encoding UTF8 -Value @'
const approveEscalation = () => {}
approveEscalation()
export const applyMissing = true
'@
        {
            Test-DshSandboxRegression -PackageRoot $package `
                -ProbeScript (Join-Path $PSScriptRoot '..\tools\dsh-sandbox-regression-probe.mjs') -Mode Require
        } | Should -Throw '*sandbox non-widening regression gate*'
    }
}
