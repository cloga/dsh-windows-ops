Describe 'Bounded ASAR archive-listing diagnostics (inert records only)' {
    BeforeAll {
        $workflow = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\.github\workflows\native-asar-release.yml') -Raw
        $start = $workflow.IndexOf('      - name: Extract verified NSIS payload as data using existing runner 7-Zip')
        $end = $workflow.IndexOf('      - name: Qualify actual release fixture', $start)
        if ($start -lt 0 -or $end -le $start) { throw 'Extraction step not found' }
        $section = $workflow.Substring($start, $end - $start)
        $match = [regex]::Match($section, '(?s)        run: \|\r?\n(?<body>.*)')
        $body = ([regex]::Matches($match.Groups['body'].Value, '(?m)^          (?<line>[^\r\n]*)') |
            ForEach-Object { $_.Groups['line'].Value }) -join "`n"
        $tokens = $null; $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseInput($body, [ref]$tokens, [ref]$errors)
        if ($errors.Count -gt 0) { throw 'Extraction step parse failed' }
        $function = $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-ArchiveListing' }, $true)
        if ($function.Count -ne 1) { throw 'Listing function not found' }
        # Load ONLY this helper; no workflow steps, actual 7-Zip, installer or source code run.
        Invoke-Expression $function[0].Extent.Text
    }
    BeforeEach {
        $script:savedPrivate = $env:PRIVATE_ROOT
        $env:PRIVATE_ROOT = $TestDrive
        New-Item -ItemType Directory -Path (Join-Path $TestDrive 'logs') -Force | Out-Null
        $script:diagnostics = @()
        Mock Write-Host { param($Object) $script:diagnostics += [string]$Object }
        $sevenZip = { $global:LASTEXITCODE = 0; $script:listingFixture }
    }
    AfterEach { $env:PRIVATE_ROOT = $script:savedPrivate }

    It 'keeps the numeric file and directory size contract intact: <Label>' -TestCases @(
        @{ Label = 'nsis'; Record = "Path = fixture/file.bin`nSize = 12`nPacked Size = 8`nAttributes = A`n" },
        @{ Label = 'application'; Record = "Path = fixture`nSize = 0`nFolder = +`nAttributes = D`n" }
    ) {
        param($Label, $Record)
        $script:listingFixture = $Record
        { Assert-ArchiveListing 'inert-never-opened.exe' $Label } | Should -Not -Throw
        @($script:diagnostics | Where-Object { $_ -like 'ASAR_LISTING_DIAGNOSTIC *' }).Count | Should -Be 0
    }

    It 'still rejects unknown or malformed sizes and emits only owned shape: <Label> <Kind>' -TestCases @(
        @{ Label = 'nsis'; Kind = 'blank-file'; SizeLine = 'Size = '; Directory = $false; Fields = 1; Blank = 1 },
        @{ Label = 'application'; Kind = 'absent-file'; SizeLine = ''; Directory = $false; Fields = 0; Blank = 0 },
        @{ Label = 'nsis'; Kind = 'blank-directory'; SizeLine = 'Size = '; Directory = $true; Fields = 1; Blank = 1 },
        @{ Label = 'application'; Kind = 'nonnumeric'; SizeLine = 'Size = fixture-private-text'; Directory = $false; Fields = 1; Blank = 0 }
    ) {
        param($Label, $Kind, $SizeLine, $Directory, $Fields, $Blank)
        $folder = if ($Directory) { 'Folder = +' } else { 'Folder = -' }
        $script:listingFixture = ((@('Path = fixture-private-name/file.bin', $SizeLine, 'Packed Size = 8', $folder) | Where-Object { $_ -ne '' }) -join "`n") + "`n"
        { Assert-ArchiveListing 'inert-never-opened.exe' $Label } | Should -Throw '*native-asar-archive-size-invalid*'
        $records = @($script:diagnostics | Where-Object { $_ -like 'ASAR_LISTING_DIAGNOSTIC *' })
        $records.Count | Should -Be 1
        $records[0] | Should -Not -Match 'fixture-private|file.bin|inert-never-opened|Path =|Packed Size ='
        $data = $records[0].Substring('ASAR_LISTING_DIAGNOSTIC '.Length) | ConvertFrom-Json
        $data.schemaVersion | Should -Be 1
        $data.valid | Should -BeFalse
        $data.stage | Should -Be ($Label + '-listing')
        $data.recordIndex | Should -Be 1
        $data.sizeFieldCount | Should -Be $Fields
        $data.numericSizeFieldCount | Should -Be 0
        $data.blankSizeFieldCount | Should -Be $Blank
        $data.directoryFlag | Should -Be $Directory
        $data.numericPackedSizePresent | Should -BeTrue
        $data.reason | Should -Be 'native-asar-archive-size-invalid'
        ($data.PSObject.Properties.Name | Sort-Object) -join ',' |
            Should -Be 'blankSizeFieldCount,directoryFlag,numericPackedSizePresent,numericSizeFieldCount,reason,recordIndex,schemaVersion,sizeFieldCount,stage,valid'
    }

    It 'still rejects unsafe paths before any shape diagnostic' {
        $script:listingFixture = "Path = ../fixture-private-escape`nSize = `n"
        { Assert-ArchiveListing 'inert-never-opened.exe' 'nsis' } | Should -Throw '*native-asar-archive-path-rejected*'
        @($script:diagnostics | Where-Object { $_ -like 'ASAR_LISTING_DIAGNOSTIC *' }).Count | Should -Be 0
    }
}
