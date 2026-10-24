$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('aibrainworx-client-test-' + [guid]::NewGuid().ToString('N'))
$oldCodexHome = [Environment]::GetEnvironmentVariable('CODEX_HOME','Process')
try {
    [void][IO.Directory]::CreateDirectory($testRoot)
    $workspace = Join-Path $testRoot 'workspace & cost $5'
    [void][IO.Directory]::CreateDirectory($workspace)
    $node = (Get-Command node.exe -ErrorAction Stop).Source
    $entry = Join-Path $testRoot 'client stub.js'
    $marker = Join-Path $testRoot 'invoked.txt'
    $profile = Join-Path $testRoot 'aibrainworx-local.config.toml'
    [IO.File]::WriteAllText($profile,'model_provider = "local_strata"')
    [IO.File]::WriteAllText($entry,'require("fs").writeFileSync(require("path").join(__dirname,"invoked.txt"),"invoked"); process.stdout.write(JSON.stringify(process.argv.slice(2)));')
    [Environment]::SetEnvironmentVariable('CODEX_HOME',$testRoot,'Process')
    $config = Join-Path $testRoot 'config.local.json'
    $settings = @{NodeExecutable=$node;HarnessEntry=$entry;PythonExecutable=$node;StrataRoot=$testRoot;StrataConfig=$profile;StrataPython=$node;WorkspaceRoot=$workspace;StateRoot=$testRoot;ModelLabel='Test model';CodexEntry=$entry}
    [IO.File]::WriteAllText($config,($settings | ConvertTo-Json))
    $launcher = Join-Path $root 'app\Start-Codex.ps1'
    & $launcher -ConfigPath $config -CheckOnly | Out-Null
    if (Test-Path -LiteralPath $marker) { throw 'CheckOnly unexpectedly executed a client.' }
    $actual = (& $launcher -ConfigPath $config) | ConvertFrom-Json
    if ($actual.Count -ne 4 -or $actual[0] -cne '--profile' -or $actual[1] -cne 'aibrainworx-local' -or $actual[2] -cne '--cd' -or $actual[3] -cne $workspace) { throw 'Client arguments were not preserved.' }
    [IO.File]::WriteAllText($entry,'process.exit(7);')
    $rejected = $false
    try { & $launcher -ConfigPath $config } catch { $rejected = $true }
    if (-not $rejected) { throw 'A failed client was reported as successful.' }
    Rename-Item -LiteralPath $profile -NewName 'profile.disabled.toml'
    $rejected = $false
    try { & $launcher -ConfigPath $config -CheckOnly | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'A missing local profile was accepted.' }
    Write-Output 'Client launch checks passed: no-start validation, argument preservation, failure reporting and missing-profile handling.'
} finally {
    [Environment]::SetEnvironmentVariable('CODEX_HOME',$oldCodexHome,'Process')
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = (Resolve-Path -LiteralPath $testRoot).Path
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
        if (-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or -not ([IO.Path]::GetFileName($resolved)).StartsWith('aibrainworx-client-test-')) { throw 'Refusing cleanup outside the temporary test folder.' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
# The deliberately failing stub must not leak its native exit code into a CI
# wrapper that dot-sources this script. Assertions above still fail normally.
$global:LASTEXITCODE = 0
