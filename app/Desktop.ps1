# Native desktop workspace. Model requests and lifecycle checks run outside the UI thread.
. (Join-Path $PSScriptRoot 'Model-Lifecycle.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.Http
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class AwxDesktopWindow {
 [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd,int attribute,ref int value,int size);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd,int command);
}
'@
[Windows.Forms.Application]::EnableVisualStyles()
$palette=@{Background=[Drawing.ColorTranslator]::FromHtml('#17191F');Card=[Drawing.ColorTranslator]::FromHtml('#20232B');Border=[Drawing.ColorTranslator]::FromHtml('#353A46');Text=[Drawing.ColorTranslator]::FromHtml('#F0F1F5');Muted=[Drawing.ColorTranslator]::FromHtml('#A6ADB9');Cyan=[Drawing.ColorTranslator]::FromHtml('#8AB4FF');Purple=[Drawing.ColorTranslator]::FromHtml('#A6B8D8');Button=[Drawing.ColorTranslator]::FromHtml('#303642')}
$form=New-Object Windows.Forms.Form
$form.Text='AiBrainWorX Model Launcher  |  '+$script:launchState.version
$form.Icon=New-Object Drawing.Icon((Join-Path (Split-Path $PSScriptRoot -Parent) 'media/aibrainworx-green.ico'))
$form.ClientSize=New-Object Drawing.Size(1040,690)
$form.MinimumSize=New-Object Drawing.Size(1040,690)
$form.StartPosition='CenterScreen';$form.BackColor=$palette.Background;$form.ForeColor=$palette.Text
$form.Font=New-Object Drawing.Font('Segoe UI',9);$form.AutoScaleMode='None'
$tips=New-Object Windows.Forms.ToolTip

function Ui-Label($Parent,$Text,$X,$Y,$W,$H=24,$Size=10,$Bold=$false){
 $v=New-Object Windows.Forms.Label;$v.Text=$Text;$v.UseMnemonic=$false;$v.AutoEllipsis=$true;$v.SetBounds($X,$Y,$W,$H);$v.ForeColor=$palette.Text
 $v.Font=New-Object Drawing.Font('Segoe UI',$Size,$(if($Bold){[Drawing.FontStyle]::Bold}else{[Drawing.FontStyle]::Regular}));$Parent.Controls.Add($v);return $v
}
function Ui-Button($Parent,$Text,$X,$Y,$W,$Handler){
 $v=New-Object Windows.Forms.Button;$v.Text=$Text;$v.SetBounds($X,$Y,$W,34);$v.FlatStyle='Flat';$v.FlatAppearance.BorderColor=$palette.Border;$v.BackColor=$palette.Button;$v.ForeColor=$palette.Text;$v.Cursor='Hand';$v.Add_Click($Handler);$Parent.Controls.Add($v);return $v
}
function Ui-Input($Parent,$Text,$X,$Y,$W,$H=27){
 $v=New-Object Windows.Forms.TextBox;$v.Text=$Text;$v.SetBounds($X,$Y,$W,$H);$v.BorderStyle='FixedSingle';$v.BackColor=$palette.Card;$v.ForeColor=$palette.Text;$Parent.Controls.Add($v);return $v
}
function Ui-Combo($Parent,$Items,$X,$Y,$W){
 $v=New-Object Windows.Forms.ComboBox;$v.SetBounds($X,$Y,$W,30);$v.DropDownStyle='DropDownList';$v.BackColor=$palette.Card;$v.ForeColor=$palette.Text;$v.FlatStyle='Flat';$v.Items.AddRange([object[]]$Items);if($v.Items.Count){$v.SelectedIndex=0};$Parent.Controls.Add($v);return $v
}
function Ui-Check($Parent,$Text,$X,$Y,$W){$v=New-Object Windows.Forms.CheckBox;$v.Text=$Text;$v.SetBounds($X,$Y,$W,26);$Parent.Controls.Add($v);return $v}
function Ui-Box($Parent,$X,$Y,$W,$H){$v=New-Object Windows.Forms.Panel;$v.SetBounds($X,$Y,$W,$H);$v.BackColor=$palette.Card;$Parent.Controls.Add($v);return $v}
function Ui-Document($Title,$Text){
 $d=New-Object Windows.Forms.Form;$d.Text=$Title;$d.Size=New-Object Drawing.Size(850,600);$d.StartPosition='CenterParent';$d.BackColor=$palette.Background;$d.ForeColor=$palette.Text
 $t=Ui-Input $d $Text 16 16 800 510;$t.Multiline=$true;$t.ReadOnly=$true;$t.ScrollBars='Vertical';$t.Font=New-Object Drawing.Font('Consolas',10);$t.Anchor='Top,Bottom,Left,Right'
 [void]$d.ShowDialog($form);$d.Dispose()
}
$side=Ui-Box $form 0 0 200 666;$side.Anchor='Top,Bottom,Left';$side.BackColor=[Drawing.ColorTranslator]::FromHtml('#111318');$side.AutoScroll=$true;$side.AutoScrollMinSize=New-Object Drawing.Size(176,704)
$logo=New-Object Windows.Forms.PictureBox;$logo.SetBounds(13,19,158,41);$logo.SizeMode='Zoom';$logo.Image=[Drawing.Image]::FromFile((Join-Path (Split-Path $PSScriptRoot -Parent) 'media/aibrainworx-wordmark-green.png'));$side.Controls.Add($logo)
$brand=Ui-Label $side 'LOCAL AI WORKSPACE' 21 65 150 22 8;$brand.ForeColor=$palette.Muted
$content=New-Object Windows.Forms.Panel;$content.SetBounds(200,0,840,666);$content.Anchor='Top,Bottom,Left,Right';$form.Controls.Add($content)
$bar=New-Object Windows.Forms.StatusStrip;$bar.BackColor=$palette.Card;$bar.ForeColor=$palette.Muted
$feedback=New-Object Windows.Forms.ToolStripStatusLabel;$feedback.Text='Ready';$feedback.Spring=$true;$feedback.TextAlign='MiddleLeft';[void]$bar.Items.Add($feedback);$form.Controls.Add($bar)
$pages=@{};$nav=@{}
foreach($name in @('Overview','Chat','Models','Memory','Training','Updates','Activity')){$p=New-Object Windows.Forms.Panel;$p.Bounds=New-Object Drawing.Rectangle(0,0,840,666);$p.Dock='Fill';$p.Visible=$false;$p.AutoScroll=$true;$content.Controls.Add($p);$pages[$name]=$p}
function Show-Page([string]$Name){
 foreach($key in $pages.Keys){$pages[$key].Visible=$key -eq $Name;$nav[$key].BackColor=if($key -eq $Name){$palette.Button}else{$side.BackColor}}
 $pages[$Name].BringToFront();if($Name -ne 'Chat' -and $script:videoHost){try{$script:videoHost.Player.controls.pause()}catch{}}
 if($Name -eq 'Models'){Refresh-ModelEditor}
 if($Name -eq 'Training'){Refresh-Training}
 if($Name -eq 'Chat' -and $script:chatProfile -ne $script:launchState.activeId){Reset-Chat}
 if($Name -eq 'Memory'){Refresh-Memory}
 if($Name -eq 'Activity'){Queue-Activity -Force}
}
$y=102
foreach($name in @('Overview','Chat','Models','Memory','Training','Updates','Activity')){
 $b=Ui-Button $side $name 12 $y 160 {param($sender,$e);Show-Page $sender.Tag};$b.Tag=$name;$b.TextAlign='MiddleLeft';$b.Padding=New-Object Windows.Forms.Padding(12,0,0,0);$b.FlatAppearance.BorderSize=0;$nav[$name]=$b;$y+=39
}
[void](Ui-Button $side 'Profiles + prompts' 12 384 160 {Edit-Profile})
[void](Ui-Button $side 'Diagnostics' 12 424 160 {try{Show-AwxDiagnostics $form $settings $ConfigPath}catch{$feedback.Text=$_.Exception.Message}})
$coreCaption=Ui-Label $side 'CORE SERVICES' 20 552 150 20 8 $true;$coreCaption.ForeColor=$palette.Muted
$modelLed=Ui-Label $side ([char]0x25CF) 19 576 18 22 11;$modelLed.ForeColor=$palette.Muted
$modelLedText=Ui-Label $side 'Model: checking' 39 577 135 22 9
$harnessLed=Ui-Label $side ([char]0x25CF) 19 601 18 22 11;$harnessLed.ForeColor=$palette.Muted
$harnessLedText=Ui-Label $side 'Harness: checking' 39 602 135 22 9
$version=Ui-Label $side ('v'+$script:launchState.version) 20 646 150 22 8;$version.ForeColor=$palette.Muted
$byline=Ui-Label $side 'Made by AiBrainWorX' 20 674 150 24 8;$byline.ForeColor=$palette.Muted

. (Join-Path $PSScriptRoot 'Model-Library.ps1')
. (Join-Path $PSScriptRoot 'Skills.ps1')
[void](Ui-Button $side 'Skills + templates' 12 464 160 {Show-WorkflowLibrary})
[void](Ui-Button $side 'Support development' 12 504 160 {Start-Process 'https://ko-fi.com/aibrainworx'})

# Overview: operational controls, no website hero or marketing sections.
$overview=$pages.Overview
[void](Ui-Label $overview 'Workspace' 32 24 500 32 21 $true)
$sub=Ui-Label $overview 'One project. Your models, instructions and memory.' 33 63 740 24 10;$sub.ForeColor=$palette.Muted
[void](Ui-Label $overview 'ACTIVE PROFILE' 33 105 150 22 8 $true)
$profilePicker=Ui-Combo $overview @() 200 101 420
[void](Ui-Button $overview 'Edit profile' 638 97 160 {Edit-Profile})
$modelBox=Ui-Box $overview 32 155 766 154
$modelCaption=Ui-Label $modelBox 'MODEL' 20 14 100 22 8 $true;$modelCaption.ForeColor=$palette.Muted
$connectionState=Ui-Label $modelBox 'CHECKING MODEL' 446 10 300 27 10 $true;$connectionState.TextAlign='MiddleCenter';$connectionState.ForeColor=$palette.Muted
$modelName=Ui-Label $modelBox '' 20 39 720 31 17 $true
$modelEndpoint=Ui-Label $modelBox '' 20 75 720 22 9;$modelEndpoint.ForeColor=$palette.Muted
$modelStart=Ui-Button $modelBox 'Start model' 20 108 155 {Begin-ModelAction 'Start'}
$modelStop=Ui-Button $modelBox 'Stop model' 187 108 155 {Begin-ModelAction 'Stop'}
$modelChange=Ui-Button $modelBox 'Change model' 586 108 160 {Show-Page 'Models'}
$modelProgress=New-Object Windows.Forms.ProgressBar;$modelProgress.SetBounds(0,150,766,4);$modelProgress.Style='Marquee';$modelProgress.MarqueeAnimationSpeed=30;$modelProgress.Visible=$false;$modelBox.Controls.Add($modelProgress)
$script:modelActionJob=$null;$script:modelSnapshot=$null;$script:modelSnapshotProfile='';$script:modelSnapshotKey='';$script:modelStateRevision=0
function Apply-ModelState($Snapshot) {
 $script:modelSnapshot=$Snapshot;$script:modelSnapshotProfile=$script:launchState.activeId;$script:modelSnapshotKey=($script:launchState.active.model|ConvertTo-Json -Compress)
 $managed=$script:launchState.active.model.backend -eq 'strata';$view=Get-AwxModelPresentation $Snapshot $managed
 $connectionState.Text=$view.label;$connectionState.BackColor=[Drawing.ColorTranslator]::FromHtml($view.background);$connectionState.ForeColor=[Drawing.ColorTranslator]::FromHtml($view.foreground)
 $modelLedText.Text='Model: '+$view.state;$modelLed.ForeColor=switch($view.state){'running'{[Drawing.ColorTranslator]::FromHtml('#91E7AB')};{$_ -in @('error','conflict','unavailable')}{[Drawing.ColorTranslator]::FromHtml('#FF9F9F')};{$_ -in @('starting','stopping','checking')}{[Drawing.ColorTranslator]::FromHtml('#FFD386')};default{$palette.Muted}};$tips.SetToolTip($modelLedText,$view.detail)
 $modelEndpoint.Text=$view.detail;$tips.SetToolTip($modelEndpoint,$script:launchState.active.model.baseUrl);$tips.SetToolTip($connectionState,$view.detail)
 $modelProgress.Visible=$view.busy;$modelStart.Enabled=$view.startEnabled;$modelStop.Enabled=$view.stopEnabled
 $modelStart.Text=if(-not $managed){'Start in backend app'}elseif($view.state -eq 'starting'){'Starting...'}elseif($view.state -eq 'running'){'Model running'}else{'Start model'}
 $modelStop.Text=if($view.state -eq 'stopping'){'Stopping...'}else{'Stop model'}
 $modelStart.BackColor=if($view.startEnabled){[Drawing.ColorTranslator]::FromHtml('#BEFFCA')}else{$palette.Button};$modelStart.ForeColor=if($view.startEnabled){[Drawing.ColorTranslator]::FromHtml('#10271B')}else{$palette.Muted}
 $modelStop.BackColor=if($view.stopEnabled){[Drawing.ColorTranslator]::FromHtml('#963E49')}else{$palette.Button};$modelStop.ForeColor=if($view.stopEnabled){$palette.Text}else{$palette.Muted}
 $modelChange.Enabled=-not [bool]$script:modelActionJob;$profilePicker.Enabled=$modelChange.Enabled
}
function Begin-ModelAction([string]$Action) {
 if($script:modelActionJob){return}
 $script:modelStateRevision++
 try{
  $script:modelActionJob=Start-AwxModelOperation $Action -ConfigPath $ConfigPath;$script:modelActionProfile=$script:launchState.activeId
  $state=if($Action -eq 'Start'){'starting'}else{'stopping'}
  $detail=if($Action -eq 'Start'){'Starting model. Loading can take several minutes.'}else{'Stopping the model and verifying its engine processes have exited...'}
  Apply-ModelState ([pscustomobject]@{state=$state;canStart=$false;canStop=$false;detail=$detail});$feedback.Text=$detail
 }catch{Apply-ModelState ([pscustomobject]@{state='error';canStart=$true;canStop=$false;detail=$_.Exception.Message});$feedback.Text=$_.Exception.Message}
}
$clientBox=Ui-Box $overview 32 325 766 149
[void](Ui-Label $clientBox 'CODING CLIENT' 20 14 160 22 8 $true)
$workspacePicker=Ui-Combo $clientBox @('DeepSeek Harness','Codex CLI (optional)') 20 43 302
$workspacePicker.SelectedIndex=if($Workspace -eq 'Codex'){1}else{0}
$clientStatus=Ui-Label $clientBox 'Checking client status...' 20 87 720 42 9;$clientStatus.ForeColor=$palette.Muted
$workspaceStart=Ui-Button $clientBox 'Start' 354 40 100 {try{$feedback.Text=Start-Harness}catch{$feedback.Text=$_.Exception.Message};Refresh-Overview}
$workspaceStop=Ui-Button $clientBox 'Stop' 466 40 100 {try{$feedback.Text=Stop-Harness}catch{$feedback.Text=$_.Exception.Message};Refresh-Overview}
$workspaceOpen=Ui-Button $clientBox 'Open chat' 578 40 168 {try{$feedback.Text=if($workspacePicker.SelectedIndex -eq 1){Open-Codex}else{Open-Harness}}catch{$feedback.Text=$_.Exception.Message}}
$workspaceOpen.BackColor=[Drawing.ColorTranslator]::FromHtml('#315F9F')
. (Join-Path $PSScriptRoot 'Hardware.ps1')
$hardware=Get-LocalHardware
$resource=Ui-Box $overview 32 490 766 105
$gpuValue=Ui-Label $resource $hardware.GPU 18 16 240 24 10 $true
$cpuValue=Ui-Label $resource $hardware.CPU 273 16 240 24 10 $true
$ramValue=Ui-Label $resource $hardware.RAM 524 16 225 24 10 $true
$gpuLive=Ui-Label $resource 'VRAM: no telemetry' 18 49 240 24 9;$gpuLive.ForeColor=$palette.Muted
$cpuLive=Ui-Label $resource 'CPU: no telemetry' 273 49 240 24 9;$cpuLive.ForeColor=$palette.Muted
$ramLive=Ui-Label $resource 'RAM: no telemetry' 524 49 225 24 9;$ramLive.ForeColor=$palette.Muted
$speedValue=Ui-Label $overview 'Decode: waiting for model metrics' 33 604 740 24 10;$speedValue.ForeColor=$palette.Cyan
$prefillValue=Ui-Label $overview 'Prompt processing: no sample | First token: no sample' 33 631 740 22 9;$prefillValue.ForeColor=$palette.Muted

# Quick chat uses no agent tools, keeping small and creative models usable.
$chat=$pages.Chat
[void](Ui-Label $chat 'Local chat' 32 24 740 34 21 $true)
$ch=Ui-Label $chat 'Local conversations with automatic handoffs. Project memory stays separate. Ctrl+Enter sends.' 33 65 750 26 10;$ch.ForeColor=$palette.Muted
$chatOutput=New-Object Windows.Forms.RichTextBox;$chatOutput.SetBounds(32,111,766,365);$chatOutput.BackColor=$palette.Card;$chatOutput.ForeColor=$palette.Text;$chatOutput.Font=New-Object Drawing.Font('Segoe UI',11);$chatOutput.ReadOnly=$true;$chatOutput.BorderStyle='FixedSingle';$chat.Controls.Add($chatOutput)
$chatInput=Ui-Input $chat '' 32 491 766 76;$chatInput.Multiline=$true;$chatInput.AcceptsReturn=$true;$chatInput.MaxLength=16000;$chatInput.ScrollBars='Vertical'
$script:chatSession=[guid]::NewGuid().ToString('N');$script:chatFinish='';$script:chatJob=$null;$script:chatMessages=New-Object Collections.ArrayList;$script:chatProfile=$script:launchState.activeId;$script:chatReply='';$script:chatDone=$false
function Reset-Chat {if($script:chatJob){return};$script:chatSession=[guid]::NewGuid().ToString('N');$script:chatFinish='';$script:chatMessages.Clear();$script:chatReply='';$chatOutput.Clear();$script:chatProfile=$script:launchState.activeId}
function Send-Chat {
 try{
  if($script:chatJob -or -not $chatInput.Text.Trim()){return}
  if($script:chatProfile -ne $script:launchState.activeId){Reset-Chat}
  Start-AwxService $settings $ConfigPath
  $text=$chatInput.Text.Trim();[void]$script:chatMessages.Add(@{role='user';content=$text})
  $chatOutput.AppendText("You`r`n"+$text+"`r`n`r`nAssistant`r`n");$chatInput.Clear();$script:chatReply='';$script:chatDone=$false
  $chatPayload=@{profileId=$script:launchState.activeId;messages=@($script:chatMessages)}
  if($script:launchState.active.model.backend -in @('strata','compatible')){
   $chatPayload.messages=@(@{role='user';content=$text});$chatPayload.sessionId=$script:chatSession;$chatPayload.requestId=[guid]::NewGuid().ToString('N')
  }
  $script:chatFinish=''
  $script:chatJob=Start-AwxOperation $settings $ConfigPath 'chat' $chatPayload -Stream
  $chatSend.Enabled=$false;$chatStop.Enabled=$true;$feedback.Text='Local model is processing the request...'
 }catch{$feedback.Text=$_.Exception.Message}
}
$chatSend=Ui-Button $chat 'Send' 32 584 130 {Send-Chat}
$chatStop=Ui-Button $chat 'Stop reply' 174 584 130 {if($script:chatJob){$script:chatJob.Process.Kill();$feedback.Text='Chat connection closed. The backend may take a moment to stop.'}};$chatStop.Enabled=$false
[void](Ui-Button $chat 'New conversation' 316 584 190 {Reset-Chat})
[void](Ui-Button $chat 'Make a memory note' 518 584 280 {if($script:chatReply){Show-Page 'Memory';Clear-MemoryEditor;$memoryTitle.Text='Conversation note';$memoryBody.Text=$script:chatReply.Substring(0,[Math]::Min(4000,$script:chatReply.Length));$memorySource.Text='Local chat response; review before saving.';$memoryVerified.Checked=$false}})
. (Join-Path $PSScriptRoot 'Video.ps1')
$chatInput.Add_KeyDown({param($sender,$e);if($e.Control -and $e.KeyCode -eq 'Enter'){$e.SuppressKeyPress=$true;Send-Chat}})
function Poll-Chat {
 if(-not $script:chatJob){return}
 $job=$script:chatJob;$n=0
 while($job.Line -and $job.Line.IsCompleted -and $n -lt 60){
  $line=$job.Line.Result
  if($null -eq $line){$job.Line=$null;break}
  if($line){try{$part=$line|ConvertFrom-Json;if($part.delta){$script:chatReply+=$part.delta;$chatOutput.AppendText($part.delta);$chatOutput.SelectionStart=$chatOutput.TextLength;$chatOutput.ScrollToCaret()};if($part.thinking){$feedback.Text='Thinking... reasoning uses the configured output budget.'};if($part.done){$script:chatDone=$true;$script:chatFinish=$part.finishReason}}catch{$feedback.Text='The local backend returned an unreadable stream.'}}
  $job.Line=$job.Process.StandardOutput.ReadLineAsync();$n++
 }
 if($job.Process.HasExited -and -not $job.Line){
  if($script:chatDone){[void]$script:chatMessages.Add(@{role='assistant';content=$script:chatReply});$chatOutput.AppendText("`r`n`r`n");$feedback.Text=if($script:chatFinish -eq 'length'){'Reply paused safely. Ask it to continue when ready.'}elseif($script:launchState.active.model.backend -in @('strata','compatible')){'Reply complete. Conversation saved locally; project memory stays separate.'}else{'Reply complete. Only memories you save are persisted.'}}
  else{if($script:chatMessages.Count){$script:chatMessages.RemoveAt($script:chatMessages.Count-1)};try{$errorData=$job.Errors.Result|ConvertFrom-Json;$feedback.Text=$errorData.error}catch{$feedback.Text='Reply stopped or unavailable. Check the selected local backend.'};$chatOutput.AppendText("`r`n[Reply ended]`r`n`r`n")}
  $job.Process.Dispose();$script:chatJob=$null;$chatSend.Enabled=$true;$chatStop.Enabled=$false
 }
}

. (Join-Path $PSScriptRoot 'Training.ps1')

# Model connections are saved with the project profile.
$models=$pages.Models
[void](Ui-Label $models 'Models' 32 24 720 34 21 $true)
$help=Ui-Label $models 'Connect installed local models. Downloads stay in the backend app.' 33 65 750 27 10;$help.ForeColor=$palette.Muted
[void](Ui-Label $models 'Backend' 32 113 160)
$backendPicker=Ui-Combo $models @('Strata','Ollama','LM Studio','llama.cpp / llama-swap') 210 110 360
[void](Ui-Label $models 'Local API' 32 157 160)
$modelUrl=Ui-Input $models '' 210 154 584
[void](Ui-Label $models 'Strata configuration' 32 201 175)
$modelConfig=Ui-Input $models '' 210 198 450
$browseModel=Ui-Button $models 'Browse' 674 194 120 { $d=New-Object Windows.Forms.OpenFileDialog;$d.Filter='Strata configuration (*.json)|*.json';if($d.ShowDialog($form) -eq 'OK'){$modelConfig.Text=$d.FileName;Discover-Models};$d.Dispose() }
[void](Ui-Label $models 'Model identifier' 32 245 175)
$modelPicker=Ui-Combo $models @() 210 242 450;$modelPicker.DropDownStyle='DropDown';$modelPicker.DisplayMember='label'
$refreshModels=Ui-Button $models 'Refresh' 674 238 120 {Discover-Models}
[void](Ui-Label $models 'Configured context' 32 292 175)
$contextTokens=New-Object Windows.Forms.NumericUpDown;$contextTokens.SetBounds(210,289,180,28);$contextTokens.Minimum=4096;$contextTokens.Maximum=1048576;$contextTokens.Increment=1024;$contextTokens.Value=16384;$models.Controls.Add($contextTokens)
$limitHint=Ui-Label $models 'Match the limit configured in your local model server.' 210 326 570 25 9;$limitHint.ForeColor=$palette.Muted
[void](Ui-Label $models 'Reasoning parameter' 32 369 175)
$reasoningPicker=Ui-Combo $models @('Server default','none','low','medium','high','xhigh') 210 366 280
$vision=Ui-Check $models 'Model and server support image input' 210 412 540
$modelNote=Ui-Label $models 'Use a tool-capable coding model. Set reasoning only when the backend supports it. Switching connections leaves the previous model running; stop it in its owning app to release memory.' 32 455 760 62 9;$modelNote.ForeColor=$palette.Muted
[void](Ui-Button $models 'Save model to profile' 32 546 230 {Save-ModelSelection})
[void](Ui-Button $models 'Browse model library' 282 546 250 {Show-ModelLibrary})
$optionalKey=Ui-Label $models 'Optional API-key environment variable' 32 601 310 25 9;$optionalKey.ForeColor=$palette.Muted
$apiKeyEnv=Ui-Input $models '' 370 598 424
$tips.SetToolTip($apiKeyEnv,'Enter a variable name, not the secret. Set its value before starting the settings service.')
$script:backendLoading=$false;$script:modelJob=$null
function Backend-Key {return @('strata','ollama','lmstudio','compatible')[$backendPicker.SelectedIndex]}
function Refresh-ModelEditor {
 $script:backendLoading=$true;$m=$script:launchState.active.model
 $backendPicker.SelectedIndex=[Array]::IndexOf(@('strata','ollama','lmstudio','compatible'),$m.backend)
 $modelUrl.Text=$m.baseUrl;$modelConfig.Text=$m.configPath;$modelPicker.Items.Clear();$modelPicker.Text=$m.modelId;$contextTokens.Value=$m.contextWindow;$vision.Checked=$m.vision;$apiKeyEnv.Text=$m.apiKeyEnv
 $reasoningPicker.SelectedIndex=if($m.reasoningEffort){[Array]::IndexOf(@('Server default','none','low','medium','high','xhigh'),$m.reasoningEffort)}else{0}
 $modelConfig.Enabled=$m.backend -eq 'strata';$browseModel.Enabled=$modelConfig.Enabled;$modelUrl.ReadOnly=$modelConfig.Enabled
 $script:backendLoading=$false
}
$backendPicker.Add_SelectedIndexChanged({if($script:backendLoading){return};$b=Backend-Key;$modelUrl.Text=@{strata='http://127.0.0.1:8081/v1';ollama='http://127.0.0.1:11434/v1';lmstudio='http://127.0.0.1:1234/v1';compatible='http://127.0.0.1:8080/v1'}[$b];$modelConfig.Enabled=$b -eq 'strata';$browseModel.Enabled=$modelConfig.Enabled;$modelUrl.ReadOnly=$modelConfig.Enabled;$modelPicker.Items.Clear();$modelPicker.Text='';$reasoningPicker.SelectedIndex=0;$vision.Checked=$false})
$modelPicker.Add_SelectionChangeCommitted({$m=$modelPicker.SelectedItem;if($m){$contextTokens.Value=$m.contextWindow;if($m.configPath){$modelConfig.Text=$m.configPath};$reasoningPicker.SelectedIndex=if($m.reasoningEffort){[Array]::IndexOf(@('Server default','none','low','medium','high','xhigh'),$m.reasoningEffort)}else{0}}})
function Discover-Models {
 if($script:modelJob){return}
 try{$script:modelJob=Start-AwxOperation $settings $ConfigPath 'models' @{backend=(Backend-Key);baseUrl=$modelUrl.Text;configPath=$modelConfig.Text;apiKeyEnv=$apiKeyEnv.Text};$script:scanBackend=Backend-Key;$refreshModels.Enabled=$false;$modelNote.Text='Reading the local model inventory...'}catch{$modelNote.Text=$_.Exception.Message}
}
function Save-ModelSelection {
 try{
  if($script:chatJob){throw 'Stop the active reply before changing its model.'}
  $script:launchState=Invoke-AwxOperation $settings $ConfigPath 'state';$p=$script:launchState.active | ConvertTo-Json -Depth 12 | ConvertFrom-Json
  $p.model=[pscustomobject]@{backend=(Backend-Key);baseUrl=$modelUrl.Text;modelId=$modelPicker.Text.Trim();configPath=$modelConfig.Text;contextWindow=[int]$contextTokens.Value;vision=$vision.Checked;apiKeyEnv=$apiKeyEnv.Text.Trim();reasoningEffort=$(if($reasoningPicker.SelectedIndex -eq 0){''}else{$reasoningPicker.Text})}
  $script:launchState=Invoke-AwxOperation $settings $ConfigPath 'save' @{profile=$p;saveAsNew=$false;revision=$script:launchState.revision}
  $feedback.Text='Model saved. Reopen coding clients to use it. No model was stopped or downloaded.';Refresh-Overview;Queue-Status
 }catch{$modelNote.Text=$_.Exception.Message}
}

# AiBrainWorX Memory: shared by model profiles pointing at the same project.
$mem=$pages.Memory
[void](Ui-Label $mem 'AiBrainWorX Memory' 32 24 740 34 21 $true)
$mh=Ui-Label $mem 'Decisions, facts and open work. Saved locally; included only when enabled.' 33 65 750 25 10;$mh.ForeColor=$palette.Muted
$memoryQuery=Ui-Input $mem '' 32 105 220
[void](Ui-Button $mem 'Search' 262 101 85 {Refresh-Memory})
$archiveView=Ui-Check $mem 'Archive' 364 104 120;$archiveView.Add_CheckedChanged({Refresh-Memory})
$memoryList=New-Object Windows.Forms.ListBox;$memoryList.SetBounds(32,170,270,346);$memoryList.BackColor=$palette.Card;$memoryList.ForeColor=$palette.Text;$memoryList.DisplayMember='title';$memoryList.BorderStyle='FixedSingle';$mem.Controls.Add($memoryList)
[void](Ui-Label $mem 'Memory title' 326 138 468 22 9)
$memoryTitle=Ui-Input $mem '' 326 166 468
$memoryKind=Ui-Combo $mem @('fact','decision','task','handoff') 326 207 180
$memoryPin=Ui-Check $mem 'Pin' 525 207 90
$memoryVerified=Ui-Check $mem 'User verified' 627 207 160
$memoryBody=Ui-Input $mem '' 326 249 468 212;$memoryBody.Multiline=$true;$memoryBody.ScrollBars='Vertical';$memoryBody.MaxLength=4000;$memoryTitle.MaxLength=120
[void](Ui-Label $mem 'Source or evidence (optional)' 326 472 468 23 9)
$memorySource=Ui-Input $mem '' 326 498 468;$memorySource.MaxLength=500
$memoryEnabled=Ui-Check $mem 'Include this project memory in new model requests' 32 537 760
$script:memoryIdentity='';$script:memoryStamp='';$script:memoryLoading=$false
function Clear-MemoryEditor {$script:memoryIdentity='';$script:memoryStamp='';$memoryTitle.Clear();$memoryBody.Clear();$memorySource.Clear();$memoryKind.SelectedIndex=0;$memoryPin.Checked=$false;$memoryVerified.Checked=$false}
function Refresh-Memory {
 try{$r=Invoke-AwxOperation $settings $ConfigPath 'memory-list' @{query=$memoryQuery.Text;archived=$archiveView.Checked};$memoryList.Items.Clear();foreach($i in @($r.items)){[void]$memoryList.Items.Add($i)};$script:memoryLoading=$true;$memoryEnabled.Checked=$script:launchState.active.useMemory;$script:memoryLoading=$false;Clear-MemoryEditor;$feedback.Text='Project memories: '+$memoryList.Items.Count}catch{$feedback.Text=$_.Exception.Message}
}
$memoryList.Add_SelectedIndexChanged({$r=$memoryList.SelectedItem;if($r){$script:memoryIdentity=$r.id;$script:memoryStamp=$r.updated;$memoryTitle.Text=$r.title;$memoryBody.Text=$r.body;$memorySource.Text=$r.source;$memoryKind.SelectedItem=$r.kind;$memoryPin.Checked=[bool]$r.pinned;$memoryVerified.Checked=[bool]$r.verified}})
[void](Ui-Button $mem 'New' 32 574 82 {Clear-MemoryEditor})
[void](Ui-Button $mem 'Save' 126 574 82 {try{[void](Invoke-AwxOperation $settings $ConfigPath 'memory-save' @{id=$script:memoryIdentity;updated=$script:memoryStamp;title=$memoryTitle.Text;body=$memoryBody.Text;source=$memorySource.Text;kind=$memoryKind.Text;pinned=$memoryPin.Checked;verified=$memoryVerified.Checked});Refresh-Memory;$feedback.Text='Memory saved locally.'}catch{$feedback.Text=$_.Exception.Message}})
[void](Ui-Button $mem 'Archive / restore' 220 574 145 {try{if(-not $script:memoryIdentity){throw 'Select a memory first.'};[void](Invoke-AwxOperation $settings $ConfigPath 'memory-archive' @{id=$script:memoryIdentity;restore=$archiveView.Checked});Refresh-Memory}catch{$feedback.Text=$_.Exception.Message}})
[void](Ui-Button $mem 'Context preview' 377 574 160 {try{$r=Invoke-AwxOperation $settings $ConfigPath 'memory-preview' @{query=$memoryQuery.Text};Ui-Document 'Memory context preview' ('Preview only; actual inclusion requires the memory checkbox. '+$r.note+"`r`n`r`n"+$r.text)}catch{$feedback.Text=$_.Exception.Message}})
[void](Ui-Button $mem 'Export handoff' 549 574 245 {try{$r=Invoke-AwxOperation $settings $ConfigPath 'handoff';$d=New-Object Windows.Forms.SaveFileDialog;$d.Filter='Markdown handoff (*.md)|*.md';$d.FileName='aibrainworx-project-handoff.md';if($d.ShowDialog($form) -eq 'OK'){[IO.File]::WriteAllText($d.FileName,$r.markdown,(New-Object Text.UTF8Encoding($false)));$feedback.Text='Handoff exported. Review its notes before sharing.'};$d.Dispose()}catch{$feedback.Text=$_.Exception.Message}})
$memoryEnabled.Add_CheckedChanged({if($script:memoryLoading){return};try{$script:launchState=Invoke-AwxOperation $settings $ConfigPath 'state';$p=$script:launchState.active;$p.useMemory=$memoryEnabled.Checked;$script:launchState=Invoke-AwxOperation $settings $ConfigPath 'save' @{profile=$p;revision=$script:launchState.revision;saveAsNew=$false};$feedback.Text='Memory setting saved for this profile.'}catch{$feedback.Text=$_.Exception.Message}})

# Read-only component checks; all network work runs outside the UI thread.
. (Join-Path $PSScriptRoot 'Plugin-Manager.ps1')
$activity=$pages.Activity
[void](Ui-Label $activity 'Activity' 32 24 740 34 21 $true)
$activityIntro=Ui-Label $activity 'Optional monitors. Live cached model stats; process snapshots only when requested.' 33 65 766 28 10;$activityIntro.ForeColor=$palette.Muted
$activityPicker=Ui-Combo $activity @() 32 107 500;$activityPicker.DisplayMember='name'
[void](Ui-Button $activity 'User plugins' 550 103 248 {Show-UserPlugins})
$activityStatus=Ui-Label $activity 'Choose a reviewed monitor in User plugins.' 32 150 766 24 10 $true
function New-ActivityList($Parent,$Y,$Height,$Columns){
 $list=New-Object Windows.Forms.ListView;$list.SetBounds(32,$Y,766,$Height);$list.View='Details';$list.FullRowSelect=$true;$list.BackColor=$palette.Card;$list.ForeColor=$palette.Text;$list.BorderStyle='FixedSingle';$list.Font=$form.Font
 foreach($column in $Columns){[void]$list.Columns.Add($column[0],$column[1])};$Parent.Controls.Add($list);return $list
}
$activityMetrics=New-ActivityList $activity 184 132 @(@('Metric',290),@('Value',290),@('State',160))
$activityServices=New-ActivityList $activity 330 82 @(@('Service',220),@('State',140),@('Detail',380))
$activityRefresh=Ui-Button $activity 'Refresh processes' 32 427 190 {Queue-Activity -InspectProcesses};$activityRefresh.Enabled=$false
$activityGpu=Ui-Check $activity 'Include GPU process stats (driver dependent)' 240 431 550
$processCaption=if($CaptureImage -or $CaptureFrames){'Process names hidden for capture. Actual sampled values are retained.'}else{'No process sample yet. Refresh processes to collect one snapshot.'}
$activityProcessCaption=Ui-Label $activity $processCaption 32 472 766 24 9;$activityProcessCaption.ForeColor=$palette.Muted
$activityProcesses=New-ActivityList $activity 503 136 @(@('Process',245),@('PID',90),@('CPU %',110),@('RAM MB',140),@('GPU MB',145))
$activityNote=Ui-Label $activity 'Core model and Harness status stays available in the sidebar and Workspace.' 32 651 766 52 9;$activityNote.ForeColor=$palette.Muted
$script:activityJob=$null;$script:activityEpoch=0;$script:activityNext=[datetime]::MinValue;$script:activityCanPoll=$false;$script:activityLoading=$false;$script:activityPendingProcesses=$false;$script:activityPendingRefresh=$false;$script:activityProcessCache=@{};$script:activityHideNames=[bool]($CaptureImage -or $CaptureFrames);$script:cachedModelMetrics=$null;$script:captureProcessSnapshotCompleted=$false;$script:captureProcessWaitTicks=0
$activityPicker.Add_SelectedIndexChanged({Render-Activity})
$updates=$pages.Updates
[void](Ui-Label $updates 'Update Center' 32 24 740 34 21 $true)
$uh=Ui-Label $updates 'Your launcher, runtimes, models and skills. One clear view.' 33 65 750 26 10;$uh.ForeColor=$palette.Muted
$updateBox=Ui-Box $updates 32 108 766 72
$updateStatus=Ui-Label $updateBox 'READY WHEN YOU ARE' 20 10 725 25 13 $true
$updateDetail=Ui-Label $updateBox 'Read-only checks. Nothing downloads or restarts automatically.' 20 39 725 25 9;$updateDetail.ForeColor=$palette.Muted
$script:updateJob=$null;$script:updateSelection=$null;$script:updateProgressId='';$script:updateProgressPath='';$script:updateProgressNext=[datetime]::MinValue;$script:updateLastProgress=$null
$updateButton=Ui-Button $updates 'Check everything' 32 196 220 {try{if($script:updateJob){return};Remove-AwxUpdateProgress;$script:updateProgressId=[guid]::NewGuid().ToString('N');$script:updateProgressPath=Join-Path (Join-Path $settings.StateRoot 'update-checks') ($script:updateProgressId+'.local.json');$script:updateLastProgress=$null;$script:updateProgressNext=[datetime]::MinValue;$updateProgress.Value=0;$updateProgress.Visible=$true;$script:updateJob=Start-AwxOperation $settings $ConfigPath 'updates' @{includePrereleases=$previewUpdates.Checked;progressId=$script:updateProgressId};$updateButton.Enabled=$false;$updateStatus.Text='CHECKING YOUR WORKSPACE...';$updateDetail.Text='Preparing real source check jobs...'}catch{$updateStatus.Text='CHECK INCOMPLETE';$updateDetail.Text=$_.Exception.Message;$updateButton.Enabled=$true;Remove-AwxUpdateProgress}}
$previewUpdates=Ui-Check $updates 'Include preview releases' 272 204 400;$previewUpdates.Checked=$true
$updateProgress=New-Object Windows.Forms.ProgressBar;$updateProgress.SetBounds(32,236,766,8);$updateProgress.Minimum=0;$updateProgress.Maximum=100;$updateProgress.Style='Continuous';$updateProgress.Visible=$false;$updates.Controls.Add($updateProgress)
$updateList=New-Object Windows.Forms.ListView;$updateList.SetBounds(32,250,766,250);$updateList.View='Details';$updateList.FullRowSelect=$true;$updateList.MultiSelect=$false;$updateList.HideSelection=$false;$updateList.BackColor=$palette.Card;$updateList.ForeColor=$palette.Text;$updateList.BorderStyle='None';$updateList.Font=New-Object Drawing.Font('Segoe UI',10)
$updateList.OwnerDraw=$true;$updateList.ShowItemToolTips=$true
$updateList.Add_DrawColumnHeader({param($sender,$e);$brush=New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#26352E'));try{$e.Graphics.FillRectangle($brush,$e.Bounds);[Windows.Forms.TextRenderer]::DrawText($e.Graphics,$e.Header.Text,$form.Font,$e.Bounds,[Drawing.ColorTranslator]::FromHtml('#C5F5D5'),([Windows.Forms.TextFormatFlags]::Left -bor [Windows.Forms.TextFormatFlags]::VerticalCenter))}finally{$brush.Dispose()}})
$updateList.Add_DrawItem({param($sender,$e);$e.DrawDefault=$true})
$updateList.Add_DrawSubItem({param($sender,$e);$e.DrawDefault=$true})
foreach($column in @(@('Component',285),@('Installed',140),@('Latest',140),@('Status',175))){[void]$updateList.Columns.Add($column[0],$column[1])};$updates.Controls.Add($updateList)
$updateDescription=Ui-Label $updates 'Press Check everything to compare your installed components. Missing provenance is shown as Needs review, never Up to date.' 32 514 766 65 10;$updateDescription.ForeColor=$palette.Muted
$updateOpen=Ui-Button $updates 'Review selected source' 32 594 240 {if($script:updateSelection -and $script:updateSelection.url -match '^https://(github\.com|huggingface\.co|registry\.npmjs\.org)/'){Start-Process $script:updateSelection.url}};$updateOpen.Enabled=$false
$updateTrack=Ui-Button $updates 'Connect model card' 288 594 240 {
 if(-not $script:updateSelection -or -not $script:updateSelection.trackingKey){return}
 $selected=$script:updateSelection
 $dialog=New-Object Windows.Forms.Form;$dialog.Text='Track model updates';$dialog.Size=New-Object Drawing.Size(620,330);$dialog.StartPosition='CenterParent';$dialog.BackColor=$palette.Background;$dialog.ForeColor=$palette.Text;$dialog.Font=$form.Font
 [void](Ui-Label $dialog 'Original Hugging Face model card (owner/repository)' 20 20 570 26 10 $true)
 $source=Ui-Input $dialog ([string]$selected.sourceRepo) 20 55 560 30
 [void](Ui-Label $dialog 'Installed commit SHA - optional; leave blank if unknown' 20 101 570 26 10 $true)
 $revision=Ui-Input $dialog '' 20 136 560 30
 $hint=Ui-Label $dialog 'This records provenance. It never downloads, verifies or relabels weights.' 20 181 570 35 9;$hint.ForeColor=$palette.Muted
 $dialog.Tag=@{Source=$source;Revision=$revision;Key=$selected.trackingKey;Feedback=$hint;Settings=$settings;Config=$ConfigPath}
 [void](Ui-Button $dialog 'Save source' 20 235 170 {param($sender,$e);$d=$sender.FindForm();$v=$d.Tag;try{[void](Invoke-AwxOperation $v.Settings $v.Config 'track-update-source' @{key=$v.Key;repo=$v.Source.Text;revision=$v.Revision.Text});$d.Close()}catch{$v.Feedback.Text=$_.Exception.Message}})
 [void](Ui-Button $dialog 'Cancel' 410 235 170 {param($sender,$e);$sender.FindForm().Close()})
 [void]$dialog.ShowDialog($form);$dialog.Dispose()
};$updateTrack.Enabled=$false
[void](Ui-Button $updates 'User plugins' 544 594 254 {Show-UserPlugins})
$updateList.Add_SelectedIndexChanged({
 if($updateList.SelectedItems.Count){$script:updateSelection=$updateList.SelectedItems[0].Tag;$updateDescription.Text=$script:updateSelection.detail;$updateOpen.Enabled=[bool]$script:updateSelection.url;$updateTrack.Enabled=[bool]$script:updateSelection.trackingKey}
})
function Show-UpdateResults($Report){
 $updateList.BeginUpdate();$updateList.Items.Clear()
 $labels=@{available='UPDATE AVAILABLE';current='UP TO DATE';ahead='DEVELOPMENT';review='NEEDS REVIEW';unavailable='COULD NOT CHECK';unknown='NOT TRACKED';'no-release'='NO STABLE RELEASE'}
 foreach($entry in @($Report.components)){
  $item=New-Object Windows.Forms.ListViewItem([string]$entry.name);[void]$item.SubItems.Add([string]$entry.installed);[void]$item.SubItems.Add([string]$entry.latest);[void]$item.SubItems.Add([string]$labels[$entry.state]);$item.Tag=$entry;$item.ToolTipText=$entry.name+"`r`n"+$entry.detail
  $item.ForeColor=switch($entry.state){'current'{[Drawing.ColorTranslator]::FromHtml('#B4F7C9')};'available'{[Drawing.ColorTranslator]::FromHtml('#FFD386')};'unavailable'{[Drawing.ColorTranslator]::FromHtml('#FFB5B5')};default{[Drawing.ColorTranslator]::FromHtml('#C4D1E6')}}
  [void]$updateList.Items.Add($item)
 }
 $updateList.EndUpdate();$s=$Report.summary;$updateStatus.Text=('{0} UPDATES  /  {1} TO REVIEW  /  {2} CURRENT' -f $s.available,$s.review,$s.current);$updateDetail.Text=('{0} components reviewed. {1} could not be checked. Select a row for details.' -f @($Report.components).Count,$s.unavailable);$updateDescription.Text=$Report.detail
}
if($CaptureImage -and $env:AIBRAINWORX_CAPTURE_UPDATE_REPORT -and (Test-Path -LiteralPath $env:AIBRAINWORX_CAPTURE_UPDATE_REPORT)){Show-UpdateResults (Get-Content -LiteralPath $env:AIBRAINWORX_CAPTURE_UPDATE_REPORT -Raw -Encoding UTF8|ConvertFrom-Json)}

function Edit-Profile {
 try{$script:launchState=Invoke-AwxOperation $settings $ConfigPath 'state';$r=Show-AwxSettings $form $settings $ConfigPath $script:launchState;if($null -ne $r){$script:launchState=$r;Refresh-ProfilePicker;Refresh-Overview;Queue-Status;$feedback.Text='Profile saved locally.'}}catch{$feedback.Text=$_.Exception.Message}
}
function Refresh-ProfilePicker {
 $script:loadingProfiles=$true;$profilePicker.Items.Clear()
 foreach($p in @($script:launchState.profiles)){[void]$profilePicker.Items.Add($p.name)}
 for($i=0;$i -lt $script:launchState.profiles.Count;$i++){if($script:launchState.profiles[$i].id -eq $script:launchState.activeId){$profilePicker.SelectedIndex=$i}}
 $script:loadingProfiles=$false
}
$profilePicker.Add_SelectedIndexChanged({if($script:loadingProfiles -or $profilePicker.SelectedIndex -lt 0){return};try{if($script:chatJob){throw 'Stop the active reply before switching profiles.'};$script:launchState=Invoke-AwxOperation $settings $ConfigPath 'select' @{id=$script:launchState.profiles[$profilePicker.SelectedIndex].id};Refresh-Overview;if($pages.Training.Visible){Refresh-Training};Queue-Status}catch{$feedback.Text=$_.Exception.Message;Refresh-ProfilePicker}})
function Refresh-Overview {
 $m=$script:launchState.active.model;$modelName.Text=$m.modelId;$modelCaption.Text='MODEL / '+$m.backend.ToUpper()
 $activityModelKey=$script:launchState.activeId+'|'+($m|ConvertTo-Json -Compress);if($script:activityModelKey -ne $activityModelKey){$script:activityModelKey=$activityModelKey;$script:cachedModelMetrics=$null;Reset-Activity;if($pages.Activity.Visible){Queue-Activity -Force}}
 if($script:modelSnapshotProfile -eq $script:launchState.activeId -and $script:modelSnapshotKey -eq ($m|ConvertTo-Json -Compress) -and $script:modelSnapshot){Apply-ModelState $script:modelSnapshot}else{Apply-ModelState ([pscustomobject]@{state='checking';canStart=$false;canStop=$false;detail='Checking the selected local model...'})}
 $terminal=$workspacePicker.SelectedIndex -eq 1;$workspaceStart.Enabled=-not $terminal;$workspaceStop.Enabled=-not $terminal;$workspaceOpen.Text=if($terminal){'Open CLI'}else{'Open chat'}
 $clientStatus.Text=if($terminal){'Uses the selected local model. Close its terminal to end the client.'}else{Get-HarnessStatus}
 if(-not $terminal){$script:cachedHarnessStatus=$clientStatus.Text};$harnessText=if($script:cachedHarnessStatus){$script:cachedHarnessStatus}else{'Not checked. Select DeepSeek Harness to refresh client health.'};$harnessState=if($harnessText -like 'Running*'){'running'}elseif($harnessText -like 'Starting*'){'starting'}elseif($harnessText -like 'Stopped*'){'stopped'}elseif($harnessText -like 'Not checked*'){'not checked'}else{'needs review'};$harnessLedText.Text='Harness: '+$harnessState;$harnessLed.ForeColor=switch($harnessState){'running'{[Drawing.ColorTranslator]::FromHtml('#91E7AB')};'starting'{[Drawing.ColorTranslator]::FromHtml('#FFD386')};{$_ -in @('stopped','not checked')}{$palette.Muted};default{[Drawing.ColorTranslator]::FromHtml('#FF9F9F')}};$tips.SetToolTip($harnessLedText,($(if($terminal){'Last checked in DeepSeek Harness mode. '})+$harnessText))
 if($m.backend -ne 'strata'){$speedValue.Text='Decode: no telemetry from this connector';$prefillValue.Text='Prompt / first-token metrics unavailable from this connector';$gpuLive.Text='VRAM: no telemetry';$cpuLive.Text='CPU: no telemetry';$ramLive.Text='RAM: no telemetry'}
}
$workspacePicker.Add_SelectedIndexChanged({Refresh-Overview})
$script:statusJob=$null;$script:metricsTask=$null;$script:metricsClient=New-Object Net.Http.HttpClient;$script:metricsClient.Timeout=[TimeSpan]::FromSeconds(2)
function Queue-Status {if(-not $script:statusJob -and -not $script:modelActionJob){$script:statusJob=if($script:launchState.active.model.backend -eq 'strata'){Start-AwxModelOperation 'Status' -ConfigPath $ConfigPath}else{Start-AwxOperation $settings $ConfigPath 'model-status'};$script:statusProfile=$script:launchState.activeId;$script:statusModel=$script:launchState.active.model.modelId;$script:statusRevision=$script:modelStateRevision;$script:statusModelConfig=($script:launchState.active.model|ConvertTo-Json -Compress)}}
function Poll-DesktopJobs {
 Poll-Chat
 Poll-Training
 Poll-Activity
 Poll-UpdateProgress
 if($script:modelJob -and $script:modelJob.Process.HasExited){try{$r=Complete-AwxOperation $script:modelJob;if($script:scanBackend -eq (Backend-Key)){$modelPicker.Items.Clear();foreach($m in @($r.models)){[void]$modelPicker.Items.Add($m)};$modelNote.Text=$r.note;if($modelPicker.Items.Count){$modelPicker.SelectedIndex=0;$m=$modelPicker.SelectedItem;$contextTokens.Value=$m.contextWindow;if($m.configPath){$modelConfig.Text=$m.configPath};$reasoningPicker.SelectedIndex=if($m.reasoningEffort){[Array]::IndexOf(@('Server default','none','low','medium','high','xhigh'),$m.reasoningEffort)}else{0}}}}catch{$modelNote.Text=$_.Exception.Message}finally{$script:modelJob=$null;$refreshModels.Enabled=$true}}
 if($script:updateJob -and $script:updateJob.Process.HasExited){try{Poll-UpdateProgress;$r=Complete-AwxOperation $script:updateJob;Show-UpdateResults $r;$updateProgress.Value=100}catch{$updateProgress.Value=[Math]::Min(99,$updateProgress.Value);$updateStatus.Text='CHECK INCOMPLETE';$updateDescription.Text=$_.Exception.Message;$updateDetail.Text='The check did not finish. Completed jobs remain visible in the progress bar.'}finally{$script:updateJob=$null;$updateButton.Enabled=$true;Remove-AwxUpdateProgress}}
 if($script:modelActionJob -and $script:modelActionJob.Process.HasExited){
  try{$r=Complete-AwxOperation $script:modelActionJob;if($script:modelActionProfile -eq $script:launchState.activeId){Apply-ModelState $r;$feedback.Text=if($r.message){$r.message}else{$r.detail}}}
  catch{Apply-ModelState ([pscustomobject]@{state='error';canStart=$false;canStop=$false;detail=$_.Exception.Message});$feedback.Text=$_.Exception.Message}
  finally{$script:modelActionJob=$null;$modelChange.Enabled=$true;$profilePicker.Enabled=$true;Queue-Status}
 }
 if($script:statusJob -and $script:statusJob.Process.HasExited){try{$r=Complete-AwxOperation $script:statusJob;if(-not $script:modelActionJob -and $script:statusRevision -eq $script:modelStateRevision -and $script:statusModelConfig -eq ($script:launchState.active.model|ConvertTo-Json -Compress) -and $script:statusProfile -eq $script:launchState.activeId -and $script:statusModel -eq $script:launchState.active.model.modelId){Apply-ModelState $r}}catch{if(-not $script:modelActionJob){Apply-ModelState ([pscustomobject]@{state='error';canStart=$false;canStop=$false;detail=$_.Exception.Message})}}finally{$script:statusJob=$null}}
 if($script:metricsTask -and $script:metricsTask.IsCompleted){try{$m=$script:metricsTask.Result|ConvertFrom-Json;if($script:launchState.active.model.backend -eq 'strata'){
  $script:cachedModelMetrics=$m
  $speedValue.Text=if($m.live.state -eq 'generating' -and $null -ne $m.live.tok_s){'Decode rate: {0:N1} tokens/s' -f $m.live.tok_s}elseif(@($m.requests).Count -gt 0 -and $null -ne $m.requests[0].decode_tok_s){'Idle | Last decode rate: {0:N1} tokens/s' -f $m.requests[0].decode_tok_s}else{'Speed: no completed request'}
  if(@($m.requests).Count -gt 0){$last=$m.requests[0];$prefill=if($last.prompt_ms -gt 0 -and $null -ne $last.prompt_read){'{0:N0} tokens/s' -f ($last.prompt_read*1000/$last.prompt_ms)}else{'no sample'};$ttft=if($null -ne $last.first_engine_token_s){'{0:N2}s' -f $last.first_engine_token_s}else{'no sample'};$prefillValue.Text='Last prompt processing: '+$prefill+' | First token: '+$ttft+' | Cached input: '+$last.reused}
  if($null -ne $m.hardware.gpu_mem_total){$gpuLive.Text='VRAM {0:N1} / {1:N1} GB' -f ($m.hardware.gpu_mem_used/1GB),($m.hardware.gpu_mem_total/1GB)}
  if($null -ne $m.hardware.cpu){$cpuLive.Text='CPU usage {0:N0}%' -f $m.hardware.cpu}
  if($null -ne $m.hardware.ram_total){$ramLive.Text='RAM {0:N1} / {1:N1} GB' -f ($m.hardware.ram_used/1GB),($m.hardware.ram_total/1GB)}
 }}catch{$script:cachedModelMetrics=$null;if($script:launchState.active.model.backend -eq 'strata'){$speedValue.Text='Speed: model telemetry unavailable'}}finally{$script:metricsTask=$null}}
}
$timer=New-Object Windows.Forms.Timer;$timer.Interval=150;$script:pollTicks=0
$timer.Add_Tick({Poll-DesktopJobs;if($script:pollTicks%20 -eq 0 -and $pages.Training.Visible -and $script:trainingIdentity -and -not $script:trainingTask){Queue-Training 'training-status'};$script:pollTicks++;if($script:pollTicks%20 -eq 0){Queue-Status;if($script:launchState.active.model.backend -eq 'strata' -and -not $script:metricsTask){$script:metricsTask=$script:metricsClient.GetStringAsync('http://127.0.0.1:8081/metrics')};Refresh-Overview}})
# Stretch the existing native controls into the larger workspace. Small screens retain
# readable text and scroll to the remaining controls instead of compressing them.
function Set-AwxResponsiveAnchors($Container){
 foreach($control in $Container.Controls){
  if($control.Width -ge 360 -and $control.Right -ge 600){$control.Anchor='Top,Left,Right'}elseif($control.Left -ge 500 -and $control.Right -ge 700){$control.Anchor='Top,Right'}
  if($control -is [Windows.Forms.Panel]){Set-AwxResponsiveAnchors $control}
 }
}
foreach($page in $pages.Values){Set-AwxResponsiveAnchors $page;$bottom=0;foreach($control in $page.Controls){$bottom=[Math]::Max($bottom,$control.Bottom)};$page.AutoScrollMinSize=New-Object Drawing.Size(810,($bottom+16))}
$resource.Add_Resize({$column=[int](($resource.ClientSize.Width-72)/3);for($i=0;$i -lt 3;$i++){foreach($label in @(@($gpuValue,$cpuValue,$ramValue)[$i],@($gpuLive,$cpuLive,$ramLive)[$i])){$label.Left=18+$i*($column+18);$label.Width=$column}}})
$workingArea=[Windows.Forms.Screen]::FromPoint([Windows.Forms.Cursor]::Position).WorkingArea
$windowFrameWidth=$form.Width-$form.ClientSize.Width;$windowFrameHeight=$form.Height-$form.ClientSize.Height
$form.ClientSize=New-Object Drawing.Size(([Math]::Min(1260,$workingArea.Width-$windowFrameWidth)),([Math]::Min(800,$workingArea.Height-$windowFrameHeight)))
$form.StartPosition='Manual';$form.Location=New-Object Drawing.Point(($workingArea.X+[Math]::Max(0,[int](($workingArea.Width-$form.Width)/2))),($workingArea.Y+[Math]::Max(0,[int](($workingArea.Height-$form.Height)/2))))
Refresh-ProfilePicker;Refresh-Overview;Show-Page 'Overview'
$form.Add_Shown({
 [void][AwxDesktopWindow]::ShowWindow($form.Handle,5)
 $dark=1;try{[void][AwxDesktopWindow]::DwmSetWindowAttribute($form.Handle,20,[ref]$dark,4)}catch{}
 Queue-Status;$script:metricsTask=$script:metricsClient.GetStringAsync('http://127.0.0.1:8081/metrics');$timer.Start()
 if(($CaptureImage -or $CaptureFrames) -and $CapturePage -ne 'Overview'){Show-Page $CapturePage;if($CapturePage -eq 'Models'){$modelConfig.Text='C:\AI\Strata\strata-example.json'};if($CapturePage -eq 'Training'){$trainPython.Text='C:\AI\TrainingEnv\Scripts\python.exe';$trainModel.Text='C:\AI\Models\TinyText';$trainDataset.Text='C:\AI\Datasets\train.jsonl';$trainOutput.Text='C:\AI\Training'}}
 # This explicit capture option is the same one-shot demand as Refresh processes.
 if($CaptureProcessSnapshot){$activityGpu.Checked=$false;Queue-Activity -InspectProcesses}
 if($CaptureSettingsImage){[void](Show-AwxSettings $form $settings $ConfigPath $script:launchState $CaptureSettingsImage);$form.Close();return}
 if($CaptureImage -or $CaptureFrames){$script:captureIndex=0;$script:captureTimer=New-Object Windows.Forms.Timer;$script:captureTimer.Interval=200
  if($CaptureFrames){[void][IO.Directory]::CreateDirectory($CaptureFrames)}
  $script:captureTimer.Add_Tick({
   if($CaptureProcessSnapshot -and -not $script:captureProcessSnapshotCompleted){$script:captureProcessWaitTicks++;if($script:captureProcessWaitTicks -lt 150){return};$activityProcessCaption.Text='Process names hidden for capture. Snapshot request is still incomplete.';$script:captureProcessSnapshotCompleted=$true}
   $script:captureIndex++;if(-not $CaptureFrames -and $script:captureIndex -lt 30){return};$bitmap=New-Object Drawing.Bitmap($form.Width,$form.Height);try{$form.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$form.Width,$form.Height)));if($CaptureFrames){$bitmap.Save((Join-Path $CaptureFrames ('frame-{0:D4}.png' -f ($script:captureIndex-1))),[Drawing.Imaging.ImageFormat]::Png)}elseif($CaptureImage){$bitmap.Save($CaptureImage,[Drawing.Imaging.ImageFormat]::Png)}}finally{$bitmap.Dispose()};if(-not $CaptureFrames -or $script:captureIndex -ge 60){$script:captureTimer.Stop();$script:captureTimer.Dispose();$form.Close()}
  });$script:captureTimer.Start()
 }
})
$form.Add_FormClosed({$timer.Stop();$timer.Dispose();foreach($job in @($script:modelJob,$script:updateJob,$script:statusJob,$script:chatJob,$script:trainingTask,$script:activityJob)){if($job){if(-not $job.Process.HasExited){$job.Process.Kill()};$job.Process.Dispose()}};Remove-AwxUpdateProgress;$script:metricsClient.CancelPendingRequests();$script:metricsClient.Dispose();if($script:videoHost){try{$script:videoHost.Player.controls.stop();$script:videoHost.Dispose()}catch{}};$tips.Dispose();$logo.Image.Dispose();$form.Icon.Dispose()})
[void]$form.ShowDialog();$form.Dispose()
