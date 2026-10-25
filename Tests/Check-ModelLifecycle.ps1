$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'app/Model-Lifecycle.ps1')
function Assert($Value,$Message){if(-not $Value){throw $Message}}
function Process([int]$Id,[int]$Parent,[int]$Created=1){[pscustomobject]@{ProcessId=$Id;ParentProcessId=$Parent;CreationDate=$Created;CommandLine=''}}
$script:fake=@();$script:killed=@();$script:mode='race'
function Get-CimInstance($ClassName,[string]$Filter){if($Filter -match '^ProcessId = (\d+)$'){$wanted=[int]$Matches[1];@($script:fake|Where-Object {$_.ProcessId -eq $wanted})}else{@($script:fake)}}
function Invoke-AwxTreeKill([int]$ProcessId){
 $script:killed+=,$ProcessId
 if($script:mode -eq 'race'){$script:fake=@($script:fake|Where-Object {$_.ProcessId -notin @(101,102)})}
 elseif($script:mode -eq 'survivor'){$script:fake=@($script:fake|Where-Object {$_.ProcessId -ne 101})}
 return 1 # Windows reports an already-exited child: final state decides success.
}
function Start-Sleep($Milliseconds){}
$parent=Process 101 1;$child=Process 102 101 2;$unrelated=Process 909 1
$script:fake=@($parent,$child,$unrelated);Stop-AwxOwnedTree @($parent)
Assert ($script:fake.Count -eq 1 -and $script:fake[0].ProcessId -eq 909) 'Stop touched an unrelated process.'
Assert ($script:killed.Count -eq 1 -and $script:killed[0] -eq 101) 'An exited child was retried as a failure.'
$script:fake=@((Process 101 1 8),(Process 103 101 9));$script:killed=@()
Stop-AwxOwnedTree @($parent)
Assert ($script:killed.Count -eq 0) 'A reused root PID authorized stopping its new descendants.'
$script:mode='survivor';$script:fake=@($parent,$child,$unrelated);$script:killed=@();$failed=$false
try{Stop-AwxOwnedTree @($parent)}catch{$failed=$_.Exception.Message -like 'Stop incomplete:*'}
Assert $failed 'A surviving child was incorrectly reported stopped.'
Assert (909 -notin $script:killed) 'An unrelated process was targeted.'
$Server='C:\AI\Strata\serve\server.py';$Config='C:\AI\Strata\strata-coder.json';$Port=8081
$good=Process 201 1;$good.CommandLine='python.exe "C:\AI\Strata\serve\server.py" --config "C:\AI\Strata\strata-coder.json" --port 8081'
$wrong=Process 202 1;$wrong.CommandLine=$good.CommandLine.Replace('--port 8081','--port 80810')
$script:fake=@($good,$wrong)
Assert (@(Get-CoderProcess).Count -eq 1) 'Process ownership accepted another port.'
foreach($case in @(
 @{state='stopped';canStart=$true;canStop=$false},@{state='starting';canStart=$false;canStop=$true},
 @{state='running';canStart=$false;canStop=$true},@{state='stopping';canStart=$false;canStop=$false}
)){
 $view=Get-AwxModelPresentation ([pscustomobject]$case)
 Assert ($view.startEnabled -eq $case.canStart -and $view.stopEnabled -eq $case.canStop) ('Incorrect controls for '+$case.state)
 if($case.state -eq 'running'){Assert ($view.foreground -eq '#BEFFCA') 'Running status lost its visible green indicator.'}
}
$external=Get-AwxModelPresentation ([pscustomobject]@{state='running';canStart=$true;canStop=$true}) $false
Assert (-not $external.startEnabled -and -not $external.stopEnabled) 'An external backend gained unsupported lifecycle controls.'
Write-Output 'Model lifecycle passed: exited-child race, survivor detection, PID reuse, ownership and distinct button states.'
