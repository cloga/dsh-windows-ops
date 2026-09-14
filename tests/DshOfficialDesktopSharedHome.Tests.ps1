Import-Module (Join-Path $PSScriptRoot '..\tools\Install-DshOfficialDesktopLocal.psm1') -Force

Describe 'Shared home filesystem fixtures' {
    BeforeEach {
        $script:fixture=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:harness=Join-Path $fixture 'shared'
        $script:profile=Join-Path $harness 'profiles\desktop'
        $script:install=Join-Path $fixture 'install'
        $script:seed=Join-Path $install 'resources\seed'
        $script:data=Join-Path $fixture 'data'
        New-Item -ItemType Directory -Path $profile,$seed,(Join-Path $harness 'sessions'),(Join-Path $profile 'node_modules'),(Join-Path $profile '.dsh-module-fallback\node_modules') -Force|Out-Null
        [IO.File]::WriteAllText((Join-Path $harness 'settings.yaml'),"fixture: true`n")
        [IO.File]::WriteAllText((Join-Path $harness '.credentials.yaml'),"fixture-only: not-a-credential`n")
        [IO.File]::WriteAllText((Join-Path $harness 'sessions\fixture.json'),'{}')
        $manifest=@'
{
  "name": "dsh-profile-desktop",
  "private": true,
  "dependencies": {},
  "dsh": {
    "profile": {
      "bundles": [
        "@deepseek-ai/dsh-base",
        "@deepseek-ai/dsh-web-app"
      ],
      "patchReload": "live"
    }
  }
}
'@
        $patch=@'
# Your patch layer for this dsh profile, applied after every bundle layer:
# a top-level YAML array of loader patch entries (id-targeted config
# overrides, disables, and insert lists; `!!js` expressions allowed).
[]
'@
        foreach($entry in @{
            'package.json'=($manifest.Replace("`r`n","`n")+"`n")
            'cordis.yml'="[]`n"
            'cordis.patch.yml'=($patch.Replace("`r`n","`n")+"`n")
            'pnpm-workspace.yaml'="packages:`n  - .`n`nnodeLinker: hoisted`nautoInstallPeers: false`n"
        }.GetEnumerator()){[IO.File]::WriteAllText((Join-Path $profile $entry.Key),$entry.Value,[Text.UTF8Encoding]::new($false))}
        $script:ops=Get-DshOfficialDesktopLocalOperations
        $ops.GetProcesses={ [pscustomobject]@{unavailable=$false;items=@()} }
    }

    It 'recognizes the observed exact bytes and renames the scaffold without changing home data' {
        (Get-FileHash (Join-Path $profile 'package.json')).Hash.ToLowerInvariant()|Should -Be 'bb3969723f1c7590c78a59cd7aaf8b98ad8eefae0ec590cfe6e7f4ef21d77f53'
        $before=@('settings.yaml','.credentials.yaml','sessions\fixture.json')|ForEach-Object{(Get-FileHash (Join-Path $harness $_)).Hash}
        InModuleScope Install-DshOfficialDesktopLocal -Parameters @{harness=$harness;install=$install;data=$data;fixture=$fixture;ops=$ops} {
            param($harness,$install,$data,$fixture,$ops)
            $selection=Get-LocalHomeSelection -SharedHome $harness -DataRoot $data
            $profileState=Get-LocalSharedProfile $harness $install $ops
            $profileState.kind|Should -Be 'legacy-blank'
            $check=[pscustomobject]@{home=$selection;sharedProfile=$profileState;sharedHomeExplicit=$true;installRoot=$install;dataRoot=$data;buildRoot=(Join-Path $fixture 'build')}
            $record=Move-LocalSharedLegacyProfile $check $ops
            Test-Path -LiteralPath $profileState.path|Should -BeFalse
            Test-Path -LiteralPath $record.destination|Should -BeTrue
            (&$ops.GetOpaqueTreeHash $record.destination)|Should -Be $profileState.fingerprint
            $record.status|Should -Be 'moved'
        }
        $after=@('settings.yaml','.credentials.yaml','sessions\fixture.json')|ForEach-Object{(Get-FileHash (Join-Path $harness $_)).Hash}
        $after|Should -Be $before
    }

    It 'rejects nonempty dependency scaffolds rather than treating them as known blank state' {
        [IO.File]::WriteAllText((Join-Path $profile 'node_modules\custom.txt'),'custom')
        InModuleScope Install-DshOfficialDesktopLocal -Parameters @{harness=$harness;install=$install;ops=$ops} {
            param($harness,$install,$ops)
            {Get-LocalSharedProfile $harness $install $ops}|Should -Throw '*nonempty-dependencies*'
        }
    }

    It 'rejects a junction even when its destination is an empty node_modules' {
        $linked=Join-Path $profile 'node_modules'
        Remove-Item -LiteralPath $linked
        $target=Join-Path $fixture 'empty'
        New-Item -ItemType Directory -Path $target|Out-Null
        New-Item -ItemType Junction -Path $linked -Target $target|Out-Null
        InModuleScope Install-DshOfficialDesktopLocal -Parameters @{harness=$harness;install=$install;ops=$ops} {
            param($harness,$install,$ops)
            {Get-LocalSharedProfile $harness $install $ops}|Should -Throw '*reparse*'
        }
    }

    It 'reuses seed-matching official metadata and rejects corrupt release core and custom patches' {
        Remove-Item -LiteralPath (Join-Path $profile 'cordis.yml')
        Remove-Item -LiteralPath (Join-Path $profile '.dsh-module-fallback\node_modules')
        Remove-Item -LiteralPath (Join-Path $profile '.dsh-module-fallback')
        foreach($root in @($profile,$seed)){
            [IO.File]::WriteAllText((Join-Path $root 'package.json'),'{"name":"@deepseek-ai/dsh-desktop-runtime","private":true,"version":"0.1.5-rc.2"}')
            [IO.File]::WriteAllText((Join-Path $root 'desktop-release.json'),'{"version":"0.1.5-rc.2","hostProtocolVersion":3,"nodeVersion":"24.17.0","pnpmVersion":"11.7.0"}')
            [IO.File]::WriteAllText((Join-Path $root 'desktop-packages.json'),'{"schemaVersion":1,"packages":[]}')
            [IO.File]::WriteAllText((Join-Path $root 'pnpm-workspace.yaml'),"packages:`n  - .`n")
            [IO.File]::WriteAllText((Join-Path $root 'pnpm-lock.yaml'),"lockfileVersion: '9.0'`n")
            New-Item -ItemType Directory (Join-Path $root 'desktop-packages')|Out-Null
            [IO.File]::WriteAllText((Join-Path $root 'desktop-packages\fixture.tgz'),'fixture tarball')
        }
        foreach($name in @('dsh','dsh-desktop-host')){
            $dir=Join-Path $profile ('node_modules\@deepseek-ai\'+$name)
            New-Item -ItemType Directory $dir -Force|Out-Null
            [IO.File]::WriteAllText((Join-Path $dir 'package.json'),('{"name":"@deepseek-ai/'+$name+'","version":"0.1.5-rc.2"}'))
        }
        InModuleScope Install-DshOfficialDesktopLocal -Parameters @{harness=$harness;install=$install;ops=$ops;profile=$profile} {
            param($harness,$install,$ops,$profile)
            (Get-LocalSharedProfile $harness $install $ops).kind|Should -Be 'official'
            $release=Join-Path $profile 'desktop-release.json';$original=[IO.File]::ReadAllText($release)
            [IO.File]::WriteAllText($release,'{}')
            {Get-LocalSharedProfile $harness $install $ops}|Should -Throw '*customized-or-corrupt*'
            [IO.File]::WriteAllText($release,$original)
            $core=Join-Path $profile 'node_modules\@deepseek-ai\dsh\package.json'
            $originalCore=[IO.File]::ReadAllText($core);[IO.File]::WriteAllText($core,'{"name":"@deepseek-ai/dsh","version":"9.0"}')
            {Get-LocalSharedProfile $harness $install $ops}|Should -Throw '*runtime-invalid*'
            [IO.File]::WriteAllText($core,$originalCore)
            [IO.File]::WriteAllText((Join-Path $profile 'cordis.patch.yml'),'- id: custom')
            {Get-LocalSharedProfile $harness $install $ops}|Should -Throw '*customized-or-corrupt*'
            [IO.File]::WriteAllText((Join-Path $profile 'package.json'),'{"name":"@deepseek-ai/dsh-desktop-runtime","dsh":{"profile":{"bundles":["@deepseek-ai/dsh-base","@deepseek-ai/dsh-web-app","@deepseek-ai/dsh-headless"]}}}')
            {Get-LocalSharedProfile $harness $install $ops}|Should -Throw '*conflicting-app-bundles*'
        }
    }
}
