Describe 'Controlled native archive extraction workflow boundary' {
    BeforeAll {
        $workflow = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\.github\workflows\native-asar-release.yml') -Raw
        $start = $workflow.IndexOf('      - name: Extract verified NSIS payload as data using existing runner 7-Zip')
        $end = $workflow.IndexOf('      - name: Qualify actual release fixture', $start)
        if ($start -lt 0 -or $end -le $start) { throw 'Extraction step not found' }
        $section = $workflow.Substring($start, $end - $start)
        $match = [regex]::Match($section, '(?s)        run: \|\r?\n(?<body>.*)')
        $script:body = ([regex]::Matches($match.Groups['body'].Value, '(?m)^          (?<line>[^\r\n]*)') |
            ForEach-Object { $_.Groups['line'].Value }) -join "`n"
    }
    It 'parses without executing any native tool or installer' {
        $tokens = $null; $errors = $null
        $null = [Management.Automation.Language.Parser]::ParseInput($body, [ref]$tokens, [ref]$errors)
        $errors.Count | Should -Be 0
    }
    It 'passes exact reviewed identity to the controlled helper, not full NSIS unpack' {
        $body | Should -Match 'tools/native-asar-extract\.mjs'
        $body | Should -Match '--seven-zip \$sevenZip --installer \$installer --installer-sha256 \$lockedInstaller\[0\]\.sha256 --installer-bytes \$lockedInstaller\[0\]\.bytes --work-root \$env:PRIVATE_ROOT'
        $body | Should -Not -Match '& \$sevenZip x \$installer|Start-Process|Assert-ArchiveListing'
        $body | Should -Match 'Join-Path\s+\$env:ProgramFiles'
        $body | Should -Match '7-Zip/7z.exe'
    }
    It 'bounds helper output and reports only fixed stage and owned reason on failure' {
        $body | Should -Match 'Length -gt 16384'
        $body | Should -Match "'reason,schemaVersion,stage,valid'"
        $body | Should -Match 'stage -isnot \[string\]'
        $body | Should -Match "'preflight','nsis-listing','nsis-selected-stream','7z-listing','7z-extraction','extracted-inventory'"
        $body | Should -Match 'ASAR_EXTRACTION_DIAGNOSTIC'
        $body | Should -Not -Match 'Write-Host[^\r\n]*\.stderr|Get-Content[^\r\n]*extraction\.stderr'
    }
    It 'requires typed bounded success before app discovery and removes private summaries' {
        $body | Should -Match 'payloadBytes -le 0 -or \$result.payloadBytes -gt 4GB'
        $body | Should -Match 'innerDeclaredBytes -gt 16GB'
        $body | Should -Match 'nsisSelectedSizeKnown -isnot \[bool\]'
        $body.IndexOf('native-asar-extraction-output-invalid') | Should -BeLessThan $body.IndexOf('--discover-application')
        $workflow | Should -Match "'extraction.json'"
    }
}
