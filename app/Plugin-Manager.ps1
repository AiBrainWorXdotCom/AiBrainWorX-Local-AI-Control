function Show-UserPlugins {
 if(Get-Command Reset-Activity -ErrorAction SilentlyContinue){Reset-Activity}
 $dialog=New-Object Windows.Forms.Form;$dialog.Text='AiBrainWorX | User plugins';$dialog.ClientSize=New-Object Drawing.Size(940,650);$dialog.StartPosition='CenterParent';$dialog.BackColor=$palette.Background;$dialog.ForeColor=$palette.Text;$dialog.Font=$form.Font
 [void](Ui-Label $dialog 'YOUR EXTENSIONS. YOUR WORKSPACE.' 24 22 870 32 17 $true)
 $intro=Ui-Label $dialog 'Plugins stay outside the launcher installation. App updates leave them intact. Changed code needs fresh approval.' 24 68 870 48 10;$intro.ForeColor=$palette.Muted
 $list=New-Object Windows.Forms.ListBox;$list.SetBounds(24,130,300,340);$list.DisplayMember='name';$list.BackColor=$palette.Card;$list.ForeColor=$palette.Text;$dialog.Controls.Add($list)
 $preview=Ui-Input $dialog 'No plugins installed. Put a reviewed plugin folder in your user plugin directory, then refresh. Voice/audio hooks are not implemented in API v1.' 344 130 550 340;$preview.Multiline=$true;$preview.ReadOnly=$true;$preview.ScrollBars='Vertical'
 $consent=Ui-Check $dialog 'I approve this extension. Python/Node plugins run with my account permissions.' 24 488 870
 $dialog.Tag=@{List=$list;Preview=$preview;Consent=$consent;Settings=$settings;Config=$ConfigPath;PluginHome=(Join-Path $settings.StateRoot 'plugins')}
 $list.Add_SelectedIndexChanged({param($sender,$e);$m=$sender.SelectedItem;if($m){$v=$sender.FindForm().Tag;$v.Consent.Checked=$false;$v.Preview.Text=$m.name+"`r`n"+'State: '+$m.state+"`r`n"+'Plugin version: '+$m.version+' / Host API: '+$m.apiVersion+"`r`n`r`n"+'Declared capabilities: '+(@($m.capabilities)-join ', ')+"`r`n"+'Hooks: '+(@($m.hooks)-join ', ')+"`r`n`r`n"+$(if($m.runtime -eq 'builtin'){'This is a fixed host-managed memory policy; it executes no plugin code. Set its disclosure level with Memory permissions. Other local programs are not sandboxed.'}else{'Python and Node plugins are trusted local programs, not a security sandbox. Review source and dependencies before enabling. Incompatible plugins remain disabled.'})}})
 function Refresh-UserPluginList($d){$v=$d.Tag;$r=Invoke-AwxOperation $v.Settings $v.Config 'plugins';$v.List.Items.Clear();foreach($item in @($r.items)){if($item){[void]$v.List.Items.Add($item)}}}
 [void](Ui-Button $dialog 'Refresh' 24 540 130 {param($sender,$e);try{Refresh-UserPluginList $sender.FindForm()}catch{$sender.FindForm().Tag.Preview.Text=$_.Exception.Message}})
 [void](Ui-Button $dialog 'Open plugin folder' 166 540 180 {param($sender,$e);$v=$sender.FindForm().Tag;[void][IO.Directory]::CreateDirectory($v.PluginHome);Start-Process $v.PluginHome})
 [void](Ui-Button $dialog 'Enable reviewed' 358 540 180 {param($sender,$e);$d=$sender.FindForm();$v=$d.Tag;$m=$v.List.SelectedItem;if(-not $m){return};try{[void](Invoke-AwxOperation $v.Settings $v.Config 'plugin-approve' @{id=$m.id;fingerprint=$m.fingerprint;enabled=$true;acceptLocalCodeRisk=$v.Consent.Checked});Refresh-UserPluginList $d}catch{$v.Preview.Text=$_.Exception.Message}})
 [void](Ui-Button $dialog 'Disable' 550 540 130 {param($sender,$e);$d=$sender.FindForm();$v=$d.Tag;$m=$v.List.SelectedItem;if(-not $m){return};try{[void](Invoke-AwxOperation $v.Settings $v.Config 'plugin-approve' @{id=$m.id;fingerprint=$m.fingerprint;enabled=$false});Refresh-UserPluginList $d}catch{$v.Preview.Text=$_.Exception.Message}})
 [void](Ui-Button $dialog 'Remove from launcher' 24 582 220 {param($sender,$e);$d=$sender.FindForm();$v=$d.Tag;$m=$v.List.SelectedItem;if(-not $m){return};try{[void](Invoke-AwxOperation $v.Settings $v.Config 'plugin-remove' @{id=$m.id;fingerprint=$m.fingerprint});Refresh-UserPluginList $d;$v.Preview.Text='Plugin removed from the launcher. Its source and data were archived and can be restored disabled.'}catch{$v.Preview.Text=$_.Exception.Message}})
 [void](Ui-Button $dialog 'Restore archived...' 256 582 220 {param($sender,$e);Show-ArchivedPlugins $sender.FindForm()})
 [void](Ui-Button $dialog 'Memory permissions...' 488 582 206 {param($sender,$e);Show-MemoryPluginPolicy $sender.FindForm()})
 [void](Ui-Button $dialog 'Close' 714 540 180 {param($sender,$e);$sender.FindForm().Close()})
 try{Refresh-UserPluginList $dialog}catch{$preview.Text=$_.Exception.Message}
 [void]$dialog.ShowDialog($form);$dialog.Dispose()
 if(Get-Command Reset-Activity -ErrorAction SilentlyContinue){Reset-Activity;Queue-Activity -Force}
}

function Show-MemoryPluginPolicy($Owner){
 $d=New-Object Windows.Forms.Form;$d.Text='Memory permissions';$d.ClientSize=New-Object Drawing.Size(680,330);$d.StartPosition='CenterParent';$d.BackColor=$palette.Background;$d.ForeColor=$palette.Text;$d.Font=$form.Font
 [void](Ui-Label $d 'MEMORY DISCLOSURE' 20 18 640 32 16 $true)
 [void](Ui-Label $d 'The host controls which saved project notes can be sent to the model. Your project memory switch must also be enabled. This does not sandbox other plugins or control client tools.' 20 58 635 65 10)
 $choice=New-Object Windows.Forms.ComboBox;$choice.DropDownStyle='DropDownList';$choice.SetBounds(20,137,620,32);[void]$choice.Items.Add('Off - do not send saved notes');[void]$choice.Items.Add('User-verified notes only');[void]$choice.Items.Add('All saved project notes');$d.Controls.Add($choice)
 $status=Ui-Label $d 'Review and enable Memory access policy before changing its level.' 20 188 630 52 10;$status.ForeColor=$palette.Muted
 try{$current=Invoke-AwxOperation $settings $ConfigPath 'plugin-memory-policy-status';$choice.SelectedIndex=switch($current.level){'verified'{1} 'all'{2} default{0}}}catch{$choice.SelectedIndex=0}
 $d.Tag=@{Choice=$choice;Status=$status}
 [void](Ui-Button $d 'Save permissions' 20 260 250 {param($sender,$e);$w=$sender.FindForm();$levels=@('off','verified','all');try{$result=Invoke-AwxOperation $settings $ConfigPath 'plugin-memory-policy' @{level=$levels[$w.Tag.Choice.SelectedIndex]};$w.Tag.Status.Text=$result.note}catch{$w.Tag.Status.Text=$_.Exception.Message}})
 [void](Ui-Button $d 'Close' 390 260 250 {param($sender,$e);$sender.FindForm().Close()})
 [void]$d.ShowDialog($Owner);$d.Dispose()
}


function Show-ArchivedPlugins($Owner){
 $d=New-Object Windows.Forms.Form;$d.Text='Restore an archived plugin';$d.ClientSize=New-Object Drawing.Size(640,390);$d.StartPosition='CenterParent';$d.BackColor=$palette.Background;$d.ForeColor=$palette.Text;$d.Font=$form.Font
 [void](Ui-Label $d 'Restored plugins stay disabled until you review and enable them.' 20 18 600 44 10)
 $list=New-Object Windows.Forms.ListBox;$list.SetBounds(20,72,600,220);$list.DisplayMember='name';$list.BackColor=$palette.Card;$list.ForeColor=$palette.Text;$d.Controls.Add($list)
 $status=Ui-Label $d '' 20 342 600 38 9;$d.Tag=@{List=$list;Status=$status;Owner=$Owner}
 [void](Ui-Button $d 'Restore selected' 20 304 190 {param($sender,$e);$w=$sender.FindForm();$v=$w.Tag;$m=$v.List.SelectedItem;if(-not $m){return};try{[void](Invoke-AwxOperation $settings $ConfigPath 'plugin-restore' @{archiveId=$m.archiveId});Refresh-UserPluginList $v.Owner;$w.Close()}catch{$v.Status.Text=$_.Exception.Message}})
 [void](Ui-Button $d 'Close' 430 304 190 {param($sender,$e);$sender.FindForm().Close()})
 try{$r=Invoke-AwxOperation $settings $ConfigPath 'plugin-archives';foreach($m in @($r.items)){if($m){[void]$list.Items.Add($m)}};if(-not $list.Items.Count){$status.Text='No archived plugins.'}}catch{$status.Text=$_.Exception.Message}
 [void]$d.ShowDialog($Owner);$d.Dispose()
}

# Panel values are data only. Never render paths, command lines, markup, or executable UI.
function ConvertTo-AwxPanelText($Value,[int]$Limit=160){
 if($null -eq $Value){return ''};if($Value -isnot [string] -and $Value -isnot [ValueType]){return ''}
 $text=([string]$Value)-replace '[\x00-\x1F\x7F]',' ';if($text.Length -gt $Limit){return $text.Substring(0,$Limit)};return $text
}
function Format-AwxPanelNumber($Value,[string]$Format='N1'){
 if($null -eq $Value -or $Value -is [bool]){return 'Unavailable'}
 $number=0.0;if(-not [double]::TryParse([string]$Value,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$number) -or [double]::IsNaN($number) -or [double]::IsInfinity($number) -or $number -lt 0){return 'Unavailable'}
 return $number.ToString($Format)
}
function ConvertTo-AwxProcessRow($Process,[bool]$HideNames=$false){
 $identity=Format-AwxPanelNumber $Process.pid 'F0';$name=if($HideNames){'Process '+$identity}else{ConvertTo-AwxPanelText $Process.name 80}
 $memory=Format-AwxPanelMemory $Process.memoryBytes;$gpu=Format-AwxPanelMemory $Process.gpuMemoryBytes
 return ,@($name,$identity,(Format-AwxPanelNumber $Process.cpuPercent),$memory,$gpu)
}
function Format-AwxPanelMemory($Value){
 $number=0.0;if($null -eq $Value -or $Value -is [bool] -or -not [double]::TryParse([string]$Value,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$number)){return 'Unavailable'}
 return (Format-AwxPanelNumber ($number/1MB))
}

function Reset-Activity {
 $script:activityEpoch++;$script:activityCanPoll=$false;$script:activityProcessCache=@{};$script:activityNext=[datetime]::MinValue;$script:activityPendingProcesses=$false;$script:activityPendingRefresh=$false
 if($activityProcesses){$activityProcesses.Items.Clear()};if($activityMetrics){$activityMetrics.Items.Clear()};if($activityServices){$activityServices.Items.Clear()}
}
function Queue-Activity([switch]$Force,[switch]$InspectProcesses){
 if(-not $pages.Activity.Visible){return}
 if($script:activityJob){if($InspectProcesses){$script:activityPendingProcesses=$true};if($Force){$script:activityPendingRefresh=$true};return}
 if(-not $Force -and -not $InspectProcesses -and (-not $script:activityCanPoll -or [datetime]::UtcNow -lt $script:activityNext)){return}
 try{
  $script:activityJob=Start-AwxOperation $settings $ConfigPath 'plugin-panels' @{backend=$script:launchState.active.model.backend;modelMetrics=$script:cachedModelMetrics;inspectProcesses=[bool]$InspectProcesses;includeGpuProcesses=([bool]$InspectProcesses -and $activityGpu.Checked)}
  $script:activityJobEpoch=$script:activityEpoch;$script:activityJobBackend=$script:launchState.active.model.backend;$script:activityJobProfile=$script:launchState.activeId;$script:activityJobProcesses=[bool]$InspectProcesses
  $script:activityNext=[datetime]::UtcNow.AddSeconds(5);$activityRefresh.Enabled=$false
 }catch{$activityStatus.Text='Monitor unavailable. Open User plugins to review its status.'}
}
function Show-ActivityResults($Report,[bool]$WithProcesses){
 $selected=if($activityPicker.SelectedItem){[string]$activityPicker.SelectedItem.id}else{''};$script:activityLoading=$true;$activityPicker.Items.Clear();$script:activityCanPoll=$false
 foreach($entry in @($Report.items)|Select-Object -First 24){
  if(-not $entry){continue};$entry.name=ConvertTo-AwxPanelText $entry.name 80;[void]$activityPicker.Items.Add($entry)
  if($entry.state -in @('enabled','error')){$script:activityCanPoll=$true}
  $key=[string]$entry.id+'|'+[string]$entry.fingerprint
  if($WithProcesses -and $entry.state -eq 'enabled' -and $entry.panel){$script:activityProcessCache[$key]=@{Rows=@($entry.panel.processes|Select-Object -First 128);At=[datetime]::Now}}
 }
 for($i=0;$i -lt $activityPicker.Items.Count;$i++){if($activityPicker.Items[$i].id -eq $selected){$activityPicker.SelectedIndex=$i}}
 if($activityPicker.SelectedIndex -lt 0 -and $activityPicker.Items.Count){$activityPicker.SelectedIndex=0};$script:activityLoading=$false;Render-Activity
 if(-not $activityPicker.Items.Count -and $Report.detail){$activityStatus.Text=ConvertTo-AwxPanelText $Report.detail 180}
}
function Add-AwxActivityRow($List,[object[]]$Values){
 if(-not $Values.Count){return};$row=New-Object Windows.Forms.ListViewItem((ConvertTo-AwxPanelText $Values[0] 160));for($i=1;$i -lt $Values.Count;$i++){[void]$row.SubItems.Add((ConvertTo-AwxPanelText $Values[$i] 180))};[void]$List.Items.Add($row)
}
function Render-Activity {
 if($script:activityLoading){return};$activityMetrics.Items.Clear();$activityServices.Items.Clear();$activityProcesses.Items.Clear();$entry=$activityPicker.SelectedItem;$activityRefresh.Enabled=$false
 if(-not $entry){$activityStatus.Text='No Activity plugin installed. Add or restore one in User plugins.';$activityNote.Text='Core model and Harness status stays available in the sidebar and Workspace.';return}
 $activityStatus.Text=(ConvertTo-AwxPanelText $entry.name 80)+'  /  '+(ConvertTo-AwxPanelText $entry.state 30)
 if($entry.state -ne 'enabled' -or -not $entry.panel){$activityNote.Text=if($entry.detail){ConvertTo-AwxPanelText $entry.detail 240}else{'This monitor is disabled. Review its source in User plugins to enable it.'};return}
 $activityRefresh.Enabled=-not [bool]$script:activityJob
 foreach($m in @($entry.panel.metrics)|Select-Object -First 32){if($m){$value=if($null -eq $m.value){'Unavailable'}else{ConvertTo-AwxPanelText $m.value 80};if($m.unit -and $null -ne $m.value){$value+=' '+(ConvertTo-AwxPanelText $m.unit 24)};Add-AwxActivityRow $activityMetrics @($m.label,$value,$m.state)}}
 foreach($s in @($entry.panel.services)|Select-Object -First 16){if($s){Add-AwxActivityRow $activityServices @($s.name,$s.state,$s.detail)}}
 $key=[string]$entry.id+'|'+[string]$entry.fingerprint;$sample=$script:activityProcessCache[$key]
 if($sample){foreach($p in @($sample.Rows)){if($p){Add-AwxActivityRow $activityProcesses (ConvertTo-AwxProcessRow $p $script:activityHideNames)}}}
 $activityProcessCaption.Text=if($script:activityHideNames){'Process names hidden for capture. Actual sampled values are retained.'}elseif($sample){'Process snapshot at '+$sample.At.ToString('HH:mm:ss')+'. Refresh explicitly for a new sample.'}else{'No process sample yet. Refresh processes to collect one snapshot.'}
 $activityNote.Text=ConvertTo-AwxPanelText $entry.panel.note 240
}
function Poll-Activity {
 if($script:activityJob -and $script:activityJob.Process.HasExited){
  $current=$script:activityJobEpoch -eq $script:activityEpoch -and $script:activityJobBackend -eq $script:launchState.active.model.backend -and $script:activityJobProfile -eq $script:launchState.activeId
  try{$report=Complete-AwxOperation $script:activityJob;if($current){Show-ActivityResults $report $script:activityJobProcesses}}
  catch{$activityStatus.Text='Monitor sample unavailable. Review the plugin in User plugins.'}
  finally{if($CaptureProcessSnapshot -and $script:activityJobProcesses -and $current){$script:captureProcessSnapshotCompleted=$true};$script:activityJob=$null;Render-Activity}
  $processes=$script:activityPendingProcesses;$refresh=$script:activityPendingRefresh;$script:activityPendingProcesses=$false;$script:activityPendingRefresh=$false
  if($processes -or $refresh){Queue-Activity -Force:$refresh -InspectProcesses:$processes}
 }
 Queue-Activity
}

function Get-AwxUpdateProgress($Progress){
 if($null -eq $Progress -or $Progress.unit -ne 'checks' -or $Progress.state -notin @('checking','complete')){return $null}
 $completed=0;$total=0
 if(-not [int]::TryParse([string]$Progress.completed,[ref]$completed) -or -not [int]::TryParse([string]$Progress.total,[ref]$total) -or $total -lt 1 -or $completed -lt 0 -or $completed -gt $total){return $null}
 $percent=[int][Math]::Floor(100.0*$completed/$total);if($Progress.state -ne 'complete'){$percent=[Math]::Min(99,$percent)}
 return [pscustomobject]@{Completed=$completed;Total=$total;Percent=$percent;Complete=($Progress.state -eq 'complete' -and $completed -eq $total)}
}
function Poll-UpdateProgress {
 if(-not $script:updateJob -or -not $script:updateProgressPath -or [datetime]::UtcNow -lt $script:updateProgressNext){return};$script:updateProgressNext=[datetime]::UtcNow.AddSeconds(1)
 try{$p=Get-AwxUpdateProgress (Get-Content -LiteralPath $script:updateProgressPath -Raw -Encoding UTF8|ConvertFrom-Json);if($p){$updateProgress.Value=$p.Percent;$updateDetail.Text=('{0}/{1} check jobs completed' -f $p.Completed,$p.Total);$script:updateLastProgress=$p}}catch{}
}
function Remove-AwxUpdateProgress {
 if($script:updateProgressId -match '^[a-f0-9]{32}$'){$expected=Join-Path (Join-Path $settings.StateRoot 'update-checks') ($script:updateProgressId+'.local.json');if($script:updateProgressPath -eq $expected -and (Test-Path -LiteralPath $expected -PathType Leaf)){Remove-Item -LiteralPath $expected -Force -ErrorAction SilentlyContinue}}
 $script:updateProgressPath='';$script:updateProgressId=''
}
