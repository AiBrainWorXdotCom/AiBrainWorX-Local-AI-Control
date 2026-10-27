$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
function Assert($Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Write-Fixture([string]$Path,[string]$Text){[IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))}
function Run-Fixture([string]$Script,[string]$Config){
 $info=New-Object Diagnostics.ProcessStartInfo;$info.FileName=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
 $info.Arguments='-NoProfile -ExecutionPolicy Bypass -File "{0}" -Action Status -AsJson -ConfigPath "{1}"' -f $Script,$Config
 $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 $process=New-Object Diagnostics.Process;$process.StartInfo=$info
 try{[void]$process.Start();$output=$process.StandardOutput.ReadToEndAsync();$errors=$process.StandardError.ReadToEndAsync();Assert ($process.WaitForExit(15000)) 'Fixture controller timed out.';Assert ($process.ExitCode -eq 0) ('Fixture controller failed: '+$errors.Result);return ($output.Result|ConvertFrom-Json)}finally{$process.Dispose()}
}
foreach($name in @('app/Control.ps1','app/Desktop.ps1','app/Launcher.ps1','app/Strata-Control.ps1')){$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile((Join-Path $root $name),[ref]$null,[ref]$errors);Assert (-not $errors.Count) ('PowerShell parse failed: '+$name)}
$desktop=Get-Content -LiteralPath (Join-Path $root 'app/Desktop.ps1') -Raw
Assert ($desktop.Contains('Start-AwxModelOperation $Action -ConfigPath $ConfigPath')) 'Start/stop actions lost the isolated config.'
Assert ($desktop.Contains("Start-AwxModelOperation 'Status' -ConfigPath `$ConfigPath")) 'Background model status lost the isolated config.'
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('aibrainworx-model-config-'+[guid]::NewGuid().ToString('N'))
try{
 $fixtureApp=Join-Path $temporary 'space & cost $5/app';[void][IO.Directory]::CreateDirectory($fixtureApp)
 $private=Join-Path $temporary 'private & cost $5.json'
 $fixtureControl=Join-Path $fixtureApp 'Control.ps1';$fixtureStrata=Join-Path $fixtureApp 'Strata-Control.ps1'
 Copy-Item -LiteralPath (Join-Path $root 'app/Control.ps1') -Destination $fixtureControl
 Write-Fixture $fixtureStrata @'
param([string]$Action,[switch]$AsJson,[string]$ConfigPath)
@{action=$Action;asJson=[bool]$AsJson;config=$ConfigPath}|ConvertTo-Json -Compress
'@
 . $fixtureControl
 # These action names reach only the echo fixture above. No lifecycle code,
 # health check, service, model executable, or native UI is invoked.
 foreach($actionName in @('Status','Start','Stop')){
  $job=Start-AwxModelOperation $actionName -ConfigPath $private
  Assert ($job.Process.WaitForExit(15000)) 'Echo child timed out.'
  $reply=Complete-AwxOperation $job
  Assert ($reply.action -eq $actionName -and $reply.asJson) 'The requested lifecycle action was changed.'
  Assert ($reply.config -ceq $private) 'The child did not receive the exact private config path.'
 }
 Push-Location -LiteralPath $temporary
 try{$job=Start-AwxModelOperation 'Status' -ConfigPath (Split-Path $private -Leaf);Assert ($job.Process.WaitForExit(15000)) 'Relative-path echo child timed out.';$reply=Complete-AwxOperation $job;Assert ($reply.config -ceq $private) 'A relative private config did not resolve against the PowerShell working folder.'}finally{Pop-Location}
 $rejected=$false;try{[void](Start-AwxModelOperation 'Status' -ConfigPath '')}catch{$rejected=$true};Assert $rejected 'An empty explicit config must not fall back to production.'

 # Exercise the actual controller initialization with harmless settings,
 # state and lifecycle fixtures, and a decoy checkout-default config.
 Copy-Item -LiteralPath (Join-Path $root 'app/Strata-Control.ps1') -Destination $fixtureStrata -Force
 $modelConfig=Join-Path $temporary 'model-fixture.json';Write-Fixture $modelConfig '{"model_name":"fixture","aliases":[]}'
 $privateState=Join-Path $temporary 'private-state';$decoyState=Join-Path $temporary 'decoy-state'
 $privateSettings=@{CaptureSentinel='private';StateRoot=$privateState;StrataRoot=$temporary;StrataPython='fixture-only';ModelConfig=$modelConfig}
 $decoySettings=@{CaptureSentinel='decoy';StateRoot=$decoyState;StrataRoot=$temporary;StrataPython='fixture-only';ModelConfig=$modelConfig}
 Write-Fixture $private ($privateSettings|ConvertTo-Json -Compress)
 Write-Fixture (Join-Path (Split-Path $fixtureApp -Parent) 'config.local.json') ($decoySettings|ConvertTo-Json -Compress)
 Write-Fixture (Join-Path $fixtureApp 'Settings.ps1') @'
function Read-AwxSettings([string]$ConfigPath){Get-Content -LiteralPath $ConfigPath -Raw|ConvertFrom-Json}
'@
 Write-Fixture $fixtureControl @'
function Invoke-AwxOperation($Settings,[string]$ConfigPath,[string]$Action){
 if($Action -ne 'state'){throw 'Only fixture state reads are allowed.'}
 [pscustomobject]@{active=[pscustomobject]@{model=[pscustomobject]@{backend='strata';modelId='fixture';configPath=$Settings.ModelConfig}}}
}
function Start-AwxService {throw 'No service may be started by this regression.'}
'@
 Write-Fixture (Join-Path $fixtureApp 'Model-Lifecycle.ps1') @'
function Get-CoderSnapshot{[pscustomobject]@{state='stopped';sentinel=$settings.CaptureSentinel;profileConfig=$ConfigPath;modelConfig=$Config;stateRoot=$settings.StateRoot}}
function Start-Coder{throw 'No model may be started by this regression.'}
function Stop-Coder{throw 'No model may be stopped by this regression.'}
'@
 $reply=Run-Fixture $fixtureStrata $private
 Assert ($reply.sentinel -ceq 'private') 'The controller replaced the private config with its checkout default.'
 Assert ($reply.profileConfig -ceq $private -and $reply.stateRoot -ceq $privateState -and $reply.modelConfig -ceq $modelConfig) 'Controller state/log/model paths escaped the supplied config.'
 Assert (-not (Test-Path -LiteralPath $privateState) -and -not (Test-Path -LiteralPath $decoyState)) 'The fixture performed an unexpected state mutation.'
}finally{
 if(Test-Path -LiteralPath $temporary){$resolved=[IO.Path]::GetFullPath($temporary);$tempPrefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\';Assert ($resolved.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved).StartsWith('aibrainworx-model-config-')) 'Refusing cleanup outside the isolated fixture directory.';Remove-Item -LiteralPath $resolved -Recurse -Force}
}
'Model config isolation passed: status/start/stop argument forwarding and private controller initialization; no model, service or UI invoked.'
