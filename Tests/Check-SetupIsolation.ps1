# Offline checks only: no downloads, venv creation, package installs or services.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$setup=Join-Path $root 'Setup.ps1'
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('awx-isolation-test-'+[guid]::NewGuid().ToString('N'))
function Assert($Condition,[string]$Message) { if(-not $Condition){throw $Message} }
try {
    $tokens=$null;$parseErrors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($setup,[ref]$tokens,[ref]$parseErrors)
    Assert (-not $parseErrors.Count) 'Setup.ps1 has a PowerShell parse error.'
    # Extract functions without running the installation body or its prompts.
    foreach($definition in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)) {
        . ([scriptblock]::Create($definition.Extent.Text))
    }
    $PublicOutput=$true;$script:SetupRedactions=@{}
    Add-SetupPrivateValue 'C:\Fixture\Private Owner' '<home>'
    Add-SetupPrivateValue 'E:\Private Runtime' '<runtime>'
    Add-SetupPrivateValue 'SecretProject' '<project>'
    $safe=Protect-SetupText 'At C:/Fixture/Private Owner/config and E:\Private Runtime\cache for SecretProject; https://example.com/model'
    Assert ($safe -notmatch 'Private Owner|Private Runtime|SecretProject') 'Public output exposed a configured private path or project name.'
    Assert ($safe -match 'https://example.com/model') 'Public filtering damaged a public model URL.'
    $privacyBefore=$script:SetupRedactions.Clone()
    $script:SetupRedactions=@{}
    foreach($generic in @('workspace','source','runtime','logs')) { Add-SetupWorkspacePrivacy ('C:\InstallTest\'+$generic) }
    Assert ((Protect-SetupText 'Choose your coding workspace. Source runtime logs.') -ceq 'Choose your coding workspace. Source runtime logs.') 'Generic directory names damaged normal public instructions.'
    Assert ((Protect-SetupText 'C:\InstallTest\workspace\file.txt') -notmatch 'C:\\InstallTest') 'Skipping a generic basename exposed its full private path.'
    Add-SetupPrivateValue 'workspace' '<project>'
    Assert ((Protect-SetupText 'workspace') -ceq '<project>') 'An actual .uproject name matching a generic directory name was not redacted.'
    $script:SetupRedactions=$privacyBefore
    Assert-SetupPorts 8082 3080
    Assert-SetupPorts 1 65535
    foreach($ports in @(@(0,3080),@(8082,65536),@(8082,8082))) {
        $failed=$false
        try { Assert-SetupPorts $ports[0] $ports[1] } catch { $failed=$true }
        Assert $failed 'An out-of-range or duplicate service port was accepted.'
    }
    Assert (Test-SetupWithin 'C:\InstallTest\runtime\Strata' 'C:\InstallTest\runtime') 'A real runtime child was rejected.'
    Assert (-not (Test-SetupWithin 'C:\InstallTest\runtime-elsewhere' 'C:\InstallTest\runtime')) 'Sibling prefix was mistaken for a contained directory.'
    foreach($badPath in @('relative\runtime','C:drive-relative','C:\')) {
        $failed=$false
        try { Resolve-SetupDirectory $badPath 'RuntimeRoot' | Out-Null } catch { $failed=$true }
        Assert $failed 'A relative path or drive root was accepted for isolation.'
    }
    . (Join-Path $root 'app\Setup-Prerequisites.ps1')
    $script:AwxSetupIsolated=$true
    function Find-AwxPython { return $null }
    function Find-WorkingCommand { return $null }
    function Ask-Yes { throw 'An isolated run tried to offer a global install.' }
    $failed=$false
    try { Require-AwxPython | Out-Null } catch { $failed=$_.Exception.Message -like '*No global Python installation*' }
    Assert $failed 'Isolated missing-Python handling did not fail without offering an install.'
    $failed=$false
    try { Require-Command 'node.exe' 'OpenJS.NodeJS.LTS' 'https://nodejs.org/' | Out-Null } catch { $failed=$_.Exception.Message -like '*No global prerequisite installation*' }
    Assert $failed 'Isolated missing-Node handling did not fail without offering an install.'
    [void][IO.Directory]::CreateDirectory($temporary)
    $batch=Join-Path $temporary 'public-output-fixture.cmd'
    [IO.File]::WriteAllText($batch,"@echo off`r`necho fixture stdout C:\Fixture\Private Owner\config SecretProject`r`necho fixture stderr E:\Private Runtime\cache 1>&2`r`nexit /b 0`r`n",(New-Object Text.UTF8Encoding($false)))
    $script:SetupPython=$null
    $batchOutput=@(Run-Checked $batch @() 6>&1)
    Assert (($batchOutput -join "`n") -notmatch 'Private Owner|Private Runtime|SecretProject') 'Public batch output exposed private stdout or stderr.'
    Assert (($batchOutput -join "`n") -match 'fixture stdout' -and ($batchOutput -join "`n") -match 'fixture stderr') 'Public batch filtering lost ordinary output or stderr.'
    [IO.File]::WriteAllText($batch,"@echo off`r`nexit /b 7`r`n",(New-Object Text.UTF8Encoding($false)))
    $failed=$false
    try { Run-Checked $batch @() } catch { $failed=$_.Exception.Message -like '*installation command failed*' }
    Assert $failed 'A failing public batch command was reported as successful.'
    $runtime=Join-Path $temporary 'runtime'
    $workspace=Join-Path $temporary 'workspace'
    $shell=(Get-Process -Id $PID).Path
    # Existing tools may be probed. These two entry points must not create either
    # requested directory or a config, start a service, or offer any download.
    $config=Join-Path $root 'config.local.json'
    $configBefore=if(Test-Path -LiteralPath $config){(Get-FileHash -LiteralPath $config).Hash}else{''}
    foreach($mode in @('-Plan','-CheckPrerequisites')) {
        $output=@(& $shell -NoProfile -ExecutionPolicy Bypass -File $setup $mode -RuntimeRoot $runtime -WorkspaceRoot $workspace -GatewayPort 18082 -HarnessPort 13080 -PublicOutput 2>&1)
        Assert ($LASTEXITCODE -in @(0,2)) 'A read-only isolated entry point failed unexpectedly.'
        Assert (-not (Test-Path -LiteralPath $runtime) -and -not (Test-Path -LiteralPath $workspace)) 'A read-only check created an installation directory.'
        Assert (($output -join "`n") -notmatch [regex]::Escape($temporary)) 'Read-only public output exposed test paths.'
        Assert (($output -join "`n") -match 'settings 18082; Harness 13080') 'Explicit isolated service ports were not accepted by Setup.'
    }
    $output=@(& $shell -NoProfile -ExecutionPolicy Bypass -File $setup -Plan -GatewayPort 0 -PublicOutput 2>&1)
    Assert ($LASTEXITCODE -eq 1 -and ($output -join "`n") -match 'between 1 and 65535') 'Setup did not reject an invalid service port before doing any work.'
    $configAfter=if(Test-Path -LiteralPath $config){(Get-FileHash -LiteralPath $config).Hash}else{''}
    Assert ($configBefore -ceq $configAfter) 'A read-only check changed local configuration.'
    Write-Host 'Setup isolation checks passed: private output, generic names, service ports, absolute paths, containment, no global install offers, read-only plan and prerequisite checks.'
} finally {
    if(Test-Path -LiteralPath $temporary) {
        $resolved=(Resolve-Path -LiteralPath $temporary).Path
        $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
        if(-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or -not ([IO.Path]::GetFileName($resolved)).StartsWith('awx-isolation-test-')) { throw 'Refusing cleanup outside this temporary isolation check.' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
$global:LASTEXITCODE=0
