Describe 'Required Node workflow failure propagation' {
    It 'stops after failing command <FailureAt> rather than masking its exit code' -TestCases @(
        @{ FailureAt = 1; ExpectedCount = 1; ExpectedExit = 17 }
        @{ FailureAt = 2; ExpectedCount = 2; ExpectedExit = 17 }
        @{ FailureAt = 3; ExpectedCount = 3; ExpectedExit = 17 }
        @{ FailureAt = 4; ExpectedCount = 4; ExpectedExit = 17 }
        @{ FailureAt = 16; ExpectedCount = 16; ExpectedExit = 17 }
        @{ FailureAt = 17; ExpectedCount = 17; ExpectedExit = 17 }
        @{ FailureAt = 0; ExpectedCount = 17; ExpectedExit = 0 }
    ) {
        param($FailureAt, $ExpectedCount, $ExpectedExit)
        $workflow = Get-Content (Join-Path $PSScriptRoot '..\.github\workflows\plugin-catalog.yml') -Raw
        $start = $workflow.IndexOf('      - name: Validate repository, catalog, plugin, and scripts')
        $start | Should -BeGreaterOrEqual 0
        $section = $workflow.Substring($start)
        $end = $section.IndexOf("`n  repository-content:")
        $end | Should -BeGreaterThan 0
        $section = $section.Substring(0, $end)
        $run = [regex]::Match($section, '(?s)        run: \|\r?\n(?<body>.*)')
        $run.Success | Should -BeTrue
        $body = ([regex]::Matches($run.Groups['body'].Value, '(?m)^          (?<line>[^\r\n]*)') |
            ForEach-Object { $_.Groups['line'].Value }) -join "`n"
        $body | Should -Match 'tests\\native-desktop-acceptance\.test\.mjs'
        $body | Should -Match 'tests\\native-asar-release-smoke\.test\.mjs'
        $body | Should -Match 'tests\\native-profile-metadata\.test\.mjs'
        $body | Should -Match 'tools\\native-profile-metadata\.mjs'
        $body | Should -Match 'tests\\native-archive-process\.test\.mjs'
        $body | Should -Match 'tests\\native-asar-extract\.test\.mjs'
        $body | Should -Match 'tools\\native-archive-process\.mjs'
        $body | Should -Match 'tools\\native-asar-extract\.mjs'
        $body | Should -Match 'tests\\native-release-diagnostic\.test\.mjs'
        $body | Should -Match 'tools\\native-release-diagnostic\.mjs'
        $script = Join-Path $TestDrive "workflow-$FailureAt.ps1"
        $audit = Join-Path $TestDrive "audit-$FailureAt.txt"
        $prefix = @'
param([int] $FailureAt, [string] $AuditPath)
$script:Count = 0
function global:node {
    $script:Count++
    Add-Content -LiteralPath $AuditPath -Value $script:Count
    if ($script:Count -eq $FailureAt) { $global:LASTEXITCODE = 17 }
    else { $global:LASTEXITCODE = 0 }
}
'@
        Set-Content -LiteralPath $script -Value ($prefix + "`n" + $body) -Encoding UTF8
        $shell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        & $shell -NoProfile -NonInteractive -File $script -FailureAt $FailureAt -AuditPath $audit
        $LASTEXITCODE | Should -Be $ExpectedExit
        @(Get-Content -LiteralPath $audit).Count | Should -Be $ExpectedCount
    }
}
