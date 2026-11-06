$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Setup.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Setup.ps1 did not parse.'}
$definition=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Ensure-AwxStrataRuntime'},$false)
if(-not $definition){throw 'Strata runtime preparation function missing.'}
. ([scriptblock]::Create($definition.Extent.Text))
function Assert($Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Invoke-AwxDependencyProbe($Executable,$Arguments,$Timeout){if($script:probeReady){return 'AWX_STRATA_READY'};return $null}
function Write-SetupConsole($Message){}
function Run-Checked($Command,$Arguments){$script:calls++;$script:lastArgs=$Arguments;if($script:installSucceeds){$script:probeReady=$true}}
$testDir=Join-Path ([IO.Path]::GetTempPath()) ('awx-runtime-check-'+[guid]::NewGuid().ToString('N'))
try {
    [void][IO.Directory]::CreateDirectory($testDir)
    $marker=Join-Path $testDir 'managed.txt'
    [IO.File]::WriteAllText((Join-Path $testDir 'requirements.txt'),'jinja2==3.1.6')
    $script:calls=0;$script:probeReady=$false;$script:installSucceeds=$true
    $rejected=$false
    try {Ensure-AwxStrataRuntime 'python' $testDir $marker}catch{$rejected=$_.Exception.Message -like '*was not modified*'}
    Assert ($rejected -and $script:calls -eq 0) 'An existing unmanaged environment was modified.'
    [IO.File]::WriteAllText($marker,'managed')
    Ensure-AwxStrataRuntime 'python' $testDir $marker
    Assert ($script:calls -eq 1 -and $script:lastArgs -contains '-r' -and $script:lastArgs -contains (Join-Path $testDir 'requirements.txt')) 'Managed environment did not install official requirements.'
    Ensure-AwxStrataRuntime 'python' $testDir $marker
    Assert ($script:calls -eq 1) 'A healthy environment was unnecessarily reinstalled.'
    $script:probeReady=$false;$script:installSucceeds=$false;$rejected=$false
    try {Ensure-AwxStrataRuntime 'python' $testDir $marker}catch{$rejected=$_.Exception.Message -like '*could not be verified*'}
    Assert $rejected 'An incomplete dependency installation was reported as successful.'
    $script:installSucceeds=$true
    Ensure-AwxStrataRuntime 'python' $testDir $marker
    Assert ($script:calls -eq 3) 'A failed managed installation was not retried.'
    Write-Output 'Strata runtime setup checks passed: unmanaged preservation, installation, verification and retry.'
} finally {
    if(Test-Path -LiteralPath $testDir){
        $resolved=(Resolve-Path -LiteralPath $testDir).Path
        $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
        if(-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or -not ([IO.Path]::GetFileName($resolved)).StartsWith('awx-runtime-check-')){throw 'Refusing cleanup outside this test folder.'}
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
