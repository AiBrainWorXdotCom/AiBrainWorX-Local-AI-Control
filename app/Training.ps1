$trainingPage=$pages.Training
[void](Ui-Label $trainingPage 'Offline training' 32 24 740 34 21 $true)
$trainingIntro=Ui-Label $trainingPage 'Tiny text LoRA. Local HF weights + JSONL; adapter output stays separate.' 33 65 750 26 10;$trainingIntro.ForeColor=$palette.Muted
function Training-Path($Title,$Y,$Kind){
 [void](Ui-Label $trainingPage $Title 32 ($Y+2) 170 24 9)
 $input=Ui-Input $trainingPage '' 208 $Y 452
 $button=Ui-Button $trainingPage 'Browse' 675 ($Y-3) 120 {param($sender,$e);$v=$sender.Tag;if($v.Kind -eq 'folder'){$d=New-Object Windows.Forms.FolderBrowserDialog;if($d.ShowDialog($form) -eq 'OK'){$v.Input.Text=$d.SelectedPath}}else{$d=New-Object Windows.Forms.OpenFileDialog;$d.Filter=if($v.Kind -eq 'python'){'Python executable (*.exe)|*.exe'}else{'Local JSONL (*.jsonl)|*.jsonl'};if($d.ShowDialog($form) -eq 'OK'){$v.Input.Text=$d.FileName}};$d.Dispose()}
 $button.Tag=@{Input=$input;Kind=$Kind};return $input
}
$trainPython=Training-Path 'Training Python' 110 'python'
$trainModel=Training-Path 'HF checkpoint folder' 155 'folder'
$trainDataset=Training-Path 'Local JSONL dataset' 200 'dataset'
$trainOutput=Training-Path 'Output parent folder' 245 'folder'
[void](Ui-Label $trainingPage 'Token length' 32 294 160 24 9)
$trainLength=New-Object Windows.Forms.NumericUpDown;$trainLength.SetBounds(208,291,130,28);$trainLength.Minimum=64;$trainLength.Maximum=1024;$trainLength.Increment=64;$trainingPage.Controls.Add($trainLength)
[void](Ui-Label $trainingPage 'LoRA rank' 370 294 110 24 9)
$trainRank=Ui-Combo $trainingPage @('4','8','16') 490 291 130
[void](Ui-Label $trainingPage 'Steps (max 500)' 32 337 170 24 9)
$trainSteps=New-Object Windows.Forms.NumericUpDown;$trainSteps.SetBounds(208,334,130,28);$trainSteps.Minimum=1;$trainSteps.Maximum=500;$trainingPage.Controls.Add($trainSteps)
$trainCuda=Ui-Check $trainingPage 'Use CUDA (requires free VRAM)' 370 334 425
$trainAllow=Ui-Check $trainingPage 'Enable training starts for this profile, including coding-client tools' 32 382 765
$trainInfo=Ui-Label $trainingPage 'Review model/data rights first. No downloads, package installs, inference shutdown or base-weight overwrites. Batch 1, 1,000 examples, full-sequence loss; initial workflow is LoRA, not QLoRA.' 32 422 766 58 9;$trainInfo.ForeColor=$palette.Muted
$script:trainingTask=$null;$script:trainingAction='';$script:trainingIdentity='';$script:trainingLoading=$false;$script:trainingReview=$false
function Refresh-Training {
 $script:trainingLoading=$true;$p=$script:launchState.active;$o=$p.training
 $trainPython.Text=if($o.python){$o.python}else{$settings.PythonExecutable};$trainModel.Text=$o.modelPath;$trainDataset.Text=$o.datasetPath;$trainOutput.Text=$o.outputRoot;$trainLength.Value=$o.maxLength;$trainSteps.Value=$o.maxSteps;$trainRank.SelectedIndex=[Array]::IndexOf(@('4','8','16'),[string]$o.rank);$trainCuda.Checked=$o.useCuda;$trainAllow.Checked=$p.allowTraining
 $script:trainingLoading=$false;$script:trainingReview=$false;$trainStart.Enabled=$false;$script:trainingIdentity=''
 if(-not $script:trainingTask){Queue-Training 'training-latest'}
}
function Save-Training {
 try{
  $script:launchState=Invoke-AwxOperation $settings $ConfigPath 'state';$p=$script:launchState.active|ConvertTo-Json -Depth 15|ConvertFrom-Json
  $p.training=[pscustomobject]@{python=$trainPython.Text.Trim();modelPath=$trainModel.Text.Trim();datasetPath=$trainDataset.Text.Trim();outputRoot=$trainOutput.Text.Trim();useCuda=$trainCuda.Checked;rank=[int]$trainRank.Text;maxLength=[int]$trainLength.Value;maxExamples=1000;maxSteps=[int]$trainSteps.Value};$p.allowTraining=$trainAllow.Checked
  $script:launchState=Invoke-AwxOperation $settings $ConfigPath 'save' @{profile=$p;revision=$script:launchState.revision;saveAsNew=$false}
  $script:trainingReview=$false;$trainStart.Enabled=$false;$trainStatus.Text='Settings saved. Run Preflight before Start. Reopen coding clients to discover training tools.'
   return $true
 }catch{$trainStatus.Text=$_.Exception.Message;return $false}
}
function Queue-Training([string]$Action){
 if($script:trainingTask){return}
 try{$payload=@{profileId=$script:launchState.activeId};if($script:trainingIdentity){$payload.jobId=$script:trainingIdentity};$script:trainingTask=Start-AwxOperation $settings $ConfigPath $Action $payload;$script:trainingAction=$Action;$script:trainingProfile=$script:launchState.activeId;$trainCheck.Enabled=$false;$trainStart.Enabled=$false}catch{$trainStatus.Text=$_.Exception.Message}
}
$trainSave=Ui-Button $trainingPage 'Save settings' 32 491 165 {[void](Save-Training)}
$trainCheck=Ui-Button $trainingPage 'Preflight' 210 491 150 {if(Save-Training){Queue-Training 'training-preflight'}}
$trainStart=Ui-Button $trainingPage 'Start LoRA' 373 491 150 {Queue-Training 'training-start'};$trainStart.Enabled=$false
$trainStop=Ui-Button $trainingPage 'Stop job' 536 491 120 {if($script:trainingIdentity){Queue-Training 'training-stop'}}
[void](Ui-Button $trainingPage 'Datasets' 669 491 130 {Show-ModelLibrary 'Datasets'})
$trainStatus=Ui-Label $trainingPage 'Save your paths, then run Preflight. No training has been started.' 32 546 766 77 10;$trainStatus.ForeColor=$palette.Cyan
$trainFoot=Ui-Label $trainingPage 'Optional dependencies must be installed in a separate environment. Training execution is experimental; a successful preflight is not a validated training run.' 32 624 766 40 8;$trainFoot.ForeColor=$palette.Muted
foreach($control in @($trainPython,$trainModel,$trainDataset,$trainOutput)){$control.Add_TextChanged({if(-not $script:trainingLoading){$script:trainingReview=$false;$trainStart.Enabled=$false}})}
function Poll-Training {
 if(-not $script:trainingTask -or -not $script:trainingTask.Process.HasExited){return}
 try{
  $r=Complete-AwxOperation $script:trainingTask
  if($script:trainingProfile -ne $script:launchState.activeId){return}
  if($script:trainingAction -eq 'training-preflight'){$script:trainingReview=$r.ready;$trainStatus.Text=if($r.ready){'Preflight passed: '+$r.model.storedParameters+' stored parameters / '+$r.examples+' examples. '+$r.note}else{'Missing training packages: '+($r.missing -join ', ')+'. Install them in the chosen training environment; no training started.'}}
  else{if($r.id){$script:trainingIdentity=$r.id};$trainStatus.Text=if($r.phase){$r.state+': '+$r.phase+$(if($r.totalSteps){' / step '+$r.step+' of '+$r.totalSteps}else{''})}else{$r.note}}
 }catch{$trainStatus.Text=$_.Exception.Message}finally{$script:trainingTask=$null;$trainCheck.Enabled=$true;$trainStart.Enabled=$script:trainingReview -and $script:launchState.active.allowTraining}
}

foreach($control in @($trainLength,$trainSteps)){$control.Add_ValueChanged({if(-not $script:trainingLoading){$script:trainingReview=$false;$trainStart.Enabled=$false}})}
$trainRank.Add_SelectedIndexChanged({if(-not $script:trainingLoading){$script:trainingReview=$false;$trainStart.Enabled=$false}})
foreach($control in @($trainCuda,$trainAllow)){$control.Add_CheckedChanged({if(-not $script:trainingLoading){$script:trainingReview=$false;$trainStart.Enabled=$false}})}
