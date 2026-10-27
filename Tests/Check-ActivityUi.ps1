$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'app/Plugin-Manager.ps1')
function Assert($Condition,[string]$Message){if(-not $Condition){throw $Message}}
$desktop=Get-Content -LiteralPath (Join-Path $root 'app/Desktop.ps1') -Raw
$manager=Get-Content -LiteralPath (Join-Path $root 'app/Plugin-Manager.ps1') -Raw
$launcher=Get-Content -LiteralPath (Join-Path $root 'app/Launcher.ps1') -Raw
foreach($path in @('app/Desktop.ps1','app/Plugin-Manager.ps1','app/Launcher.ps1')){$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile((Join-Path $root $path),[ref]$null,[ref]$errors);Assert (-not $errors.Count) ('PowerShell parse failed: '+$path)}
Assert ($launcher.Contains("'Updates','Activity'")) 'Activity is missing from capture page validation.'
Assert ($launcher.Contains('[string]$ConfigPath =')) 'Isolated configuration captures are not supported.'
Assert ($launcher.Contains('$HarnessPort') -and -not $launcher.Contains('--port 3080')) 'Harness launch must honor the configured port.'
Assert ($desktop.Contains('[Math]::Min(1260') -and $desktop.Contains('[Math]::Min(800')) 'Roomier defaults must remain bounded by the working area.'
Assert ($desktop.Contains('$page.AutoScrollMinSize') -and $desktop.Contains('$modelLedText') -and $desktop.Contains('$harnessLedText')) 'Scrollable pages and permanent core health labels are required.'
Assert ($manager -notmatch 'Get-CimInstance|Get-Process|Invoke-RestMethod|GetStringAsync') 'The optional UI must reuse model telemetry and never enumerate processes itself.'
Assert ($manager.Contains('$script:activityJobEpoch -eq $script:activityEpoch')) 'Stale results need an approval-change epoch check.'
Assert ($manager.Contains('$script:activityJobBackend -eq $script:launchState.active.model.backend')) 'Stale results need a backend check.'
Assert ($manager.Contains("'plugin-remove'") -and $manager.Contains("'plugin-restore'")) 'Plugin removal and disabled restore must be available without restarting.'
Assert ($launcher.Contains('[switch]$CaptureProcessSnapshot')) 'An explicit process snapshot capture option is required.'
$launcherAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'app/Launcher.ps1'),[ref]$null,[ref]$null)
$captureValidation=$launcherAst.Find({param($node)$node -is [Management.Automation.Language.IfStatementAst] -and $node.Extent.Text.Contains("throw 'CaptureProcessSnapshot requires")},$true)
Assert ($null -ne $captureValidation) 'Process snapshot capture validation is missing.'
foreach($case in @(
 @{Request=$false;Image='';Frames='';Page='Overview';Action='Gui';Valid=$true},
 @{Request=$true;Image='';Frames='';Page='Activity';Action='Gui';Valid=$false},
 @{Request=$true;Image='fixture.png';Frames='';Page='Overview';Action='Gui';Valid=$false},
 @{Request=$true;Image='';Frames='frames';Page='Updates';Action='Gui';Valid=$false},
 @{Request=$true;Image='fixture.png';Frames='';Page='Activity';Action='Status';Valid=$false},
 @{Request=$true;Image='fixture.png';Frames='';Page='Activity';Action='Gui';Valid=$true},
 @{Request=$true;Image='';Frames='frames';Page='Activity';Action='Gui';Valid=$true}
)){
 $CaptureProcessSnapshot=$case.Request;$CaptureImage=$case.Image;$CaptureFrames=$case.Frames;$CapturePage=$case.Page;$Action=$case.Action;$CaptureSettingsImage='';$rejected=$false
 try{& ([scriptblock]::Create($captureValidation.Extent.Text))}catch{$rejected=$true}
 Assert ($rejected -ne $case.Valid) 'A snapshot capture combination was accepted or rejected incorrectly.'
}
$CaptureProcessSnapshot=$false;$CaptureImage='';$CaptureFrames='';$Action='Gui'
$desktopAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'app/Desktop.ps1'),[ref]$null,[ref]$null)
$captureRequest=@($desktopAst.FindAll({param($node)$node -is [Management.Automation.Language.IfStatementAst] -and $node.Clauses[0].Item1.Extent.Text -eq '$CaptureProcessSnapshot'},$true))
Assert ($captureRequest.Count -eq 1 -and $captureRequest[0].Extent.Text.Contains('Queue-Activity -InspectProcesses') -and $captureRequest[0].Extent.Text.Contains('$activityGpu.Checked=$false')) 'Only the explicit one-shot capture option may request process collection, with GPU collection off.'
Assert ($desktop.Contains('$CaptureProcessSnapshot -and -not $script:captureProcessSnapshotCompleted') -and $desktop.Contains('$script:captureProcessWaitTicks -lt 150')) 'Snapshot captures must wait for completion with a bounded timeout.'

$p=[pscustomobject]@{pid=321;name='private-project.exe';cpuPercent=12.5;memoryBytes=64MB;gpuMemoryBytes=16MB}
$private=ConvertTo-AwxProcessRow $p $true
$normal=ConvertTo-AwxProcessRow $p $false
Assert ($private[0] -eq 'Process 321' -and $normal[0] -eq 'private-project.exe') 'Capture privacy must hide every process name.'
Assert (($private[1..4]-join '|') -eq ($normal[1..4]-join '|')) 'Capture privacy changed real measurements.'
Assert ($private[2] -eq (12.5).ToString('N1') -and $private[3] -eq (64.0).ToString('N1') -and $private[4] -eq (16.0).ToString('N1')) 'Sampled CPU/RAM/GPU values were not retained.'
foreach($bad in @($null,-1,[double]::NaN,[double]::PositiveInfinity,'not a number',$true)){Assert ((Format-AwxPanelNumber $bad) -eq 'Unavailable') 'Unavailable measurements must never become fabricated zeroes.'}
Assert ((Format-AwxPanelMemory 'bad') -eq 'Unavailable') 'Invalid process memory must render safely.'
Assert ((ConvertTo-AwxPanelText ("a`n"+('b'*200)) 20).Length -eq 20) 'Panel text must be bounded.'
Assert ((ConvertTo-AwxPanelText "a`nb") -eq 'a b') 'Control characters must not become extra UI rows.'
Assert ((ConvertTo-AwxPanelText @{secret='value'}) -eq '') 'Arbitrary objects must not be formatted into the panel.'

$progress=Get-AwxUpdateProgress ([pscustomobject]@{completed=2;total=8;state='checking';unit='checks'})
Assert ($progress.Percent -eq 25 -and $progress.Completed -eq 2 -and $progress.Total -eq 8) 'Progress must count real check jobs.'
Assert ((Get-AwxUpdateProgress ([pscustomobject]@{completed=8;total=8;state='checking';unit='checks'})).Percent -eq 99) 'A running check must not show 100 percent.'
Assert ((Get-AwxUpdateProgress ([pscustomobject]@{completed=8;total=8;state='complete';unit='checks'})).Complete) 'Completed check jobs must be recognized.'
foreach($bad in @(@{completed=9;total=8;state='checking';unit='checks'},@{completed=0;total=0;state='checking';unit='checks'},@{completed='invalid';total=8;state='checking';unit='checks'},@{completed=1;total=8;state='checking';unit='bytes'})){Assert ($null -eq (Get-AwxUpdateProgress ([pscustomobject]$bad))) 'Invalid progress record was accepted.'}

# Exercise demand collection without creating windows or contacting any model.
$script:starts=0;$script:lastPayload=$null
function Start-AwxOperation($Settings,$ConfigPath,$Action,$Payload){$script:starts++;$script:lastPayload=$Payload;Assert ($Action -eq 'plugin-panels') 'Unexpected monitor operation.';return [pscustomobject]@{Process=[pscustomobject]@{HasExited=$false}}}
$settings=[pscustomobject]@{};$ConfigPath='isolated-test.json'
$pages=@{Activity=[pscustomobject]@{Visible=$false}};$activityRefresh=[pscustomobject]@{Enabled=$true};$activityGpu=[pscustomobject]@{Checked=$true}
$script:launchState=[pscustomobject]@{activeId='test';active=[pscustomobject]@{model=[pscustomobject]@{backend='strata'}}}
$script:cachedModelMetrics=[pscustomobject]@{live=[pscustomobject]@{tok_s=42}};$script:activityEpoch=1;$script:activityJob=$null;$script:activityCanPoll=$true;$script:activityNext=[datetime]::MinValue
Queue-Activity -Force
Assert ($script:starts -eq 0) 'Hidden Activity pages must not collect.'
$pages.Activity.Visible=$true;$script:activityCanPoll=$false
Queue-Activity
Assert ($script:starts -eq 0) 'Disabled monitors must not poll.'
Queue-Activity -Force
Assert ($script:starts -eq 1 -and -not $script:lastPayload.inspectProcesses -and -not $script:lastPayload.includeGpuProcesses) 'Light polling must never request process collection.'
Assert ($script:lastPayload.modelMetrics.live.tok_s -eq 42) 'Panel collection did not reuse cached model metrics.'
Queue-Activity -InspectProcesses
Assert ($script:activityPendingProcesses -and $script:starts -eq 1) 'Explicit refresh must wait for an in-flight sample.'
$script:activityJob=$null
Queue-Activity -InspectProcesses
Assert ($script:starts -eq 2 -and $script:lastPayload.inspectProcesses -and $script:lastPayload.includeGpuProcesses) 'Only explicit refresh may request driver-dependent process data.'
$activityMetrics=$null;$activityServices=$null;$activityProcesses=$null
Reset-Activity
Assert ($script:activityEpoch -eq 2 -and -not $script:activityCanPoll -and -not $script:activityProcessCache.Count) 'Changing plugin approval must invalidate samples immediately.'

# Completing a light or stale sample cannot release a requested snapshot capture.
function Complete-AwxOperation($Operation){[pscustomobject]@{items=@()}}
function Show-ActivityResults($Report,$WithProcesses){}
function Render-Activity{}
function Queue-Activity([switch]$Force,[switch]$InspectProcesses){}
function Complete-FixtureSample([bool]$Processes,[bool]$Stale=$false){
 $script:activityJobProcesses=$Processes;$script:activityJobEpoch=if($Stale){$script:activityEpoch-1}else{$script:activityEpoch};$script:activityJobBackend='strata';$script:activityJobProfile='test';$script:captureProcessSnapshotCompleted=$false
 $script:activityJob=[pscustomobject]@{Process=[pscustomobject]@{HasExited=$true}}
 Poll-Activity
 return $script:captureProcessSnapshotCompleted
}
Assert (-not (Complete-FixtureSample $true)) 'A normal capture must not request snapshot waiting.'
$CaptureProcessSnapshot=$true
Assert (-not (Complete-FixtureSample $false)) 'A light sample cannot complete a process snapshot capture.'
Assert (-not (Complete-FixtureSample $true $true)) 'A stale sample cannot complete a process snapshot capture.'
Assert (Complete-FixtureSample $true) 'The actual completed process request must release capture waiting.'
$CaptureProcessSnapshot=$false

$temporary=Join-Path ([IO.Path]::GetTempPath()) ('aibrainworx-ui-test-'+[guid]::NewGuid().ToString('N'))
try{
 $settings=[pscustomobject]@{StateRoot=$temporary};$dir=Join-Path $temporary 'update-checks';[void][IO.Directory]::CreateDirectory($dir)
 $script:updateProgressId=[guid]::NewGuid().ToString('N');$script:updateProgressPath=Join-Path $dir ($script:updateProgressId+'.local.json');$other=Join-Path $dir 'another-check.local.json'
 [IO.File]::WriteAllText($script:updateProgressPath,'{}');[IO.File]::WriteAllText($other,'{}');$own=$script:updateProgressPath
 Remove-AwxUpdateProgress
 Assert (-not (Test-Path -LiteralPath $own) -and (Test-Path -LiteralPath $other)) 'Progress cleanup touched another check.'
}finally{if(Test-Path -LiteralPath $temporary){$resolved=[IO.Path]::GetFullPath($temporary);$tempPrefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\';Assert ($resolved.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved).StartsWith('aibrainworx-ui-test-')) 'Refusing cleanup outside the isolated test directory.';Remove-Item -LiteralPath $resolved -Recurse -Force}}
'Activity UI contracts passed (no windows launched, no model HTTP requests).'
