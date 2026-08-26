Import-Module (Join-Path $PSScriptRoot '..\tools\DshCopilotBootstrap.psm1') -Force

Describe 'DSH Copilot bootstrap' {
    BeforeEach {
        $script:root = Join-Path $TestDrive 'dsh'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
    }

    It 'does not write managed settings during dry-run' {
        $path = Join-Path $root 'settings.yaml'
        Set-Content -LiteralPath $path -Value "# existing`n" -Encoding UTF8
        $before = Get-Content -LiteralPath $path -Raw
        $result = Set-DshCopilotSettings -Path $path -BaseUrl 'http://127.0.0.1:7777/v1' `
            -Model 'fixture-model' -VisionCapable $true -DryRun
        $result.status | Should Be 'would-change'
        Get-Content -LiteralPath $path -Raw | Should Be $before
    }

    It 'is idempotent for settings and profile patches' {
        $settings = Join-Path $root 'settings.yaml'
        $patch = Join-Path $root 'cordis.patch.yml'
        Set-Content -LiteralPath $patch -Value "[]`n" -Encoding UTF8
        (Set-DshCopilotSettings -Path $settings -BaseUrl 'http://127.0.0.1:7777/v1' `
            -Model 'fixture-model' -VisionCapable $true).status | Should Be 'changed'
        (Set-DshCopilotSettings -Path $settings -BaseUrl 'http://127.0.0.1:7777/v1' `
            -Model 'fixture-model' -VisionCapable $true).status | Should Be 'unchanged'
        (Set-DshCopilotProfilePatch -Path $patch).status | Should Be 'changed'
        (Set-DshCopilotProfilePatch -Path $patch).status | Should Be 'unchanged'
    }

    It 'refuses duplicate managed blocks' {
        $path = Join-Path $root 'settings.yaml'
        $block = @'
# dsh-windows-ops: copilot settings begin
# dsh-windows-ops: copilot settings end
# dsh-windows-ops: copilot settings begin
# dsh-windows-ops: copilot settings end
'@
        Set-Content -LiteralPath $path -Value $block -Encoding UTF8
        $threw = $false
        try {
            Set-DshCopilotSettings -Path $path -BaseUrl 'http://127.0.0.1:7777/v1' `
                -Model 'fixture-model' -VisionCapable $true | Out-Null
        } catch {
            $threw = $true
        }
        $threw | Should Be $true
    }

    It 'refuses unmanaged conflicts outside an existing managed block' {
        $path = Join-Path $root 'cordis.patch.yml'
        Set-Content -LiteralPath $path -Value "[]`n" -Encoding UTF8
        Set-DshCopilotProfilePatch -Path $path | Out-Null
        Add-Content -LiteralPath $path -Value "`n- id: tool-web`n  disabled: false"
        $threw = $false
        try {
            Set-DshCopilotProfilePatch -Path $path | Out-Null
        } catch {
            $threw = $true
        }
        $threw | Should Be $true
    }

    It 'disables conflicting search rows in the managed profile block' {
        $path = Join-Path $root 'cordis.patch.yml'
        Set-Content -LiteralPath $path -Value "[]`n" -Encoding UTF8
        Set-DshCopilotProfilePatch -Path $path | Out-Null
        $text = Get-Content -LiteralPath $path -Raw
        $text | Should Match '(?s)- id: web-search-deepseek\s+disabled: true'
        $text | Should Match '(?s)- id: tool-web\s+disabled: true'
        $text | Should Match 'providers: \[copilot-responses\]'
    }

    It 'resolves the npm flat global core and validates fork provenance' {
        $global = Join-Path $root 'global'
        $package = Join-Path $global '@deepseek-ai\dsh'
        New-Item -ItemType Directory -Path $package -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $package 'package.json') `
            -Value '{"version":"1.2.3","repository":{"url":"https://github.com/cloga/deepseek-harness.git"}}' -Encoding UTF8
        $cli = Join-Path $root 'dsh.cmd'
        Set-Content -LiteralPath $cli -Value '@echo off' -Encoding ASCII
        $info = Resolve-DshCliInfo -DshCliPath $cli -GlobalRoots @($global)
        $info.packageRoot | Should Be ([IO.Path]::GetFullPath($package))
        $info.repository | Should Be 'cloga/deepseek-harness'
    }

    It 'requires explicit catalog metadata for vision' {
        $catalog = [pscustomobject]@{ data = @(
            [pscustomobject]@{ id = 'vision-by-name-only' },
            [pscustomobject]@{ id = 'actual-image'; input = @('text', 'image') }
        ) }
        (Get-DshCatalogModel -Catalog $catalog -Model 'vision-by-name-only').visionCapable | Should Be $false
        (Get-DshCatalogModel -Catalog $catalog -Model 'actual-image').visionCapable | Should Be $true
    }

    It 'accepts only an active Desktop descendant using the local package' {
        $cli = [pscustomobject]@{ cliPath = 'C:\npm\dsh.cmd'; packageRoot = 'C:\npm\node_modules\@deepseek-ai\dsh' }
        $processes = @(
            [pscustomobject]@{ ProcessId = 10; ParentProcessId = 1; Name = 'DeepSeek Harness.exe'; CommandLine = 'desktop' },
            [pscustomobject]@{ ProcessId = 11; ParentProcessId = 10; Name = 'node.exe'; CommandLine = 'node C:\npm\node_modules\@deepseek-ai\dsh\apps\cli\lib\index.js web' }
        )
        (Test-DshActiveDesktopCore -CliInfo $cli -Processes $processes).healthy | Should Be $true
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
        $threw | Should Be $true
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
            sha256 = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
        })
        Complete-DshCopilotBackup -StateRoot $state -OperationId $backup.operationId -ExpectedStates $expected | Out-Null
        Restore-DshCopilotBackup -StateRoot $state -OperationId $backup.operationId | Out-Null
        (Get-Content -LiteralPath $file -Raw).Trim() | Should Be 'before'
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
            sha256 = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
        })
        Complete-DshCopilotBackup -StateRoot $state -OperationId $backup.operationId -ExpectedStates $expected | Out-Null
        Set-Content -LiteralPath $file -Value 'later-user-change' -Encoding UTF8
        $threw = $false
        try {
            Restore-DshCopilotBackup -StateRoot $state -OperationId $backup.operationId | Out-Null
        } catch {
            $threw = $true
        }
        $threw | Should Be $true
        (Get-Content -LiteralPath $file -Raw).Trim() | Should Be 'later-user-change'
    }

    It 'reports the pre-fix sandbox contract as expected-fail' {
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
        Set-Content -LiteralPath (Join-Path $bash 'index.js') -Encoding UTF8 -Value 'approveEscalation'
        Set-Content -LiteralPath (Join-Path $pwsh 'index.js') -Encoding UTF8 -Value 'approveEscalation'
        $result = Test-DshSandboxRegression -PackageRoot $package `
            -ProbeScript (Join-Path $PSScriptRoot '..\tools\dsh-sandbox-regression-probe.mjs') -Mode Report
        $result.status | Should Be 'expected-fail'
    }

    It 'passes same narrower and wider sandbox behavior without lowering policy' {
        $package = Join-Path $root 'package'
        $sandbox = Join-Path $package 'node_modules\@deepseek-ai\dsh-sandbox\lib'
        $bash = Join-Path $package 'node_modules\@deepseek-ai\dsh-tool-bash\lib'
        $pwsh = Join-Path $package 'node_modules\@deepseek-ai\dsh-tool-pwsh\lib'
        New-Item -ItemType Directory -Path $sandbox, $bash, $pwsh -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $sandbox 'index.js') -Encoding UTF8 -Value @'
export async function approveEscalation(request, approval) {
  const rank = { 'read-only': 0, 'workspace-write': 1, 'danger-full-access': 2 }
  if (rank[request.requestedMode] <= rank[request.effectiveMode]) return request.effectiveMode
  await approval.approver.request()
  return request.requestedMode
}
'@
        Set-Content -LiteralPath (Join-Path $bash 'index.js') -Encoding UTF8 -Value 'approveEscalation'
        Set-Content -LiteralPath (Join-Path $pwsh 'index.js') -Encoding UTF8 -Value 'approveEscalation'
        $result = Test-DshSandboxRegression -PackageRoot $package `
            -ProbeScript (Join-Path $PSScriptRoot '..\tools\dsh-sandbox-regression-probe.mjs') -Mode Require
        $result.status | Should Be 'passed'
        $result.effectiveMode | Should Be 'danger-full-access'
    }
}
