function Start-AwxOperation($Settings,[string]$ConfigPath,[string]$Action,$Payload=$null,[switch]$Stream) {
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $Settings.PythonExecutable
    $start.Arguments = '"{0}" {1} --config "{2}"' -f (Join-Path $PSScriptRoot 'control_runtime.py'),$Action,$ConfigPath
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.RedirectStandardInput = $true
    $start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $start.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    [void]$process.Start()
    $output = if(-not $Stream){$process.StandardOutput.ReadToEndAsync()}else{$null}
    $errors = $process.StandardError.ReadToEndAsync()
    if ($null -ne $Payload) { $process.StandardInput.Write(($Payload | ConvertTo-Json -Depth 15 -Compress)) }
    $process.StandardInput.Close()
    return [pscustomobject]@{Process=$process;Output=$output;Errors=$errors;Line=$(if($Stream){$process.StandardOutput.ReadLineAsync()}else{$null})}
}

function Start-AwxModelOperation([ValidateSet('Start','Stop','Status')][string]$Action,[ValidateNotNullOrEmpty()][string]$ConfigPath=(Join-Path (Split-Path $PSScriptRoot -Parent) 'config.local.json')) {
    $ConfigPath=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ConfigPath)
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    # HELP-ISOLATION: a private launcher config must follow every lifecycle child.
    $start.Arguments='-NoProfile -ExecutionPolicy Bypass -File "{0}" -Action {1} -AsJson -ConfigPath "{2}"' -f (Join-Path $PSScriptRoot 'Strata-Control.ps1'),$Action,$ConfigPath
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $start.StandardOutputEncoding=New-Object Text.UTF8Encoding($false)
    $start.StandardErrorEncoding=New-Object Text.UTF8Encoding($false)
    $process=New-Object Diagnostics.Process;$process.StartInfo=$start;[void]$process.Start()
    [pscustomobject]@{Process=$process;Output=$process.StandardOutput.ReadToEndAsync();Errors=$process.StandardError.ReadToEndAsync()}
}

function Complete-AwxOperation($Operation) {
    try {
        if ($Operation.Process.ExitCode -ne 0) {
            $message = 'The operation failed. Check this PC installation.'
            try { $message = ($Operation.Errors.Result | ConvertFrom-Json).error } catch {}
            throw $message
        }
        return ($Operation.Output.Result | ConvertFrom-Json)
    } finally { $Operation.Process.Dispose() }
}

function Invoke-AwxOperation($Settings,[string]$ConfigPath,[string]$Action,$Payload=$null) {
    $operation = Start-AwxOperation $Settings $ConfigPath $Action $Payload
    if (-not $operation.Process.WaitForExit(15000)) { $operation.Process.Kill(); $operation.Process.Dispose(); throw 'The local operation timed out.' }
    return (Complete-AwxOperation $operation)
}

function Start-AwxService($Settings,[string]$ConfigPath) {
    # HELP-ISOLATION: separate test workspaces use a distinct loopback port and mutex.
    $gatewayPort=if($Settings.GatewayPort){[int]$Settings.GatewayPort}else{8082}
    if($gatewayPort -lt 1 -or $gatewayPort -gt 65535){throw 'Invalid gateway port.'}
    $healthUrl='http://127.0.0.1:'+$gatewayPort+'/health'
    $mutex = New-Object Threading.Mutex($false,('Local\AiBrainWorXControl'+$gatewayPort))
    $held = $false
    try {
    $held = $mutex.WaitOne(5000)
    if (-not $held) { throw 'Another settings-service start is in progress. Try again.' }
    $scriptPath = Join-Path $PSScriptRoot 'control_runtime.py'
    $expected = Invoke-AwxOperation $Settings $ConfigPath 'state'
    $health=$null
    try { $health = Invoke-RestMethod $healthUrl -TimeoutSec 1 } catch {}
    if($health) {
        if ($health.service -eq 'aibrainworx-control' -and $health.dataIdentity -eq $expected.dataIdentity) {
            if ($health.version -eq $expected.version) { return }
            $connections=@(Get-NetTCPConnection -LocalPort $gatewayPort -State Established -ErrorAction SilentlyContinue)
            if($connections.Count){throw 'Wait for active model requests to finish before updating the settings service.'}
            $owned=@(Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" | Where-Object {$_.ExecutablePath -eq $Settings.PythonExecutable -and $_.CommandLine -and $_.CommandLine.IndexOf(('"'+$scriptPath+'"'),[StringComparison]::OrdinalIgnoreCase) -ge 0 -and $_.CommandLine.IndexOf(('"'+$ConfigPath+'"'),[StringComparison]::OrdinalIgnoreCase) -ge 0 -and $_.CommandLine.Contains(' serve ')})
            if($owned.Count -ne 1){throw 'An older settings service needs to be closed before this update can start.'}
            $verified=Get-CimInstance Win32_Process -Filter ('ProcessId = '+$owned[0].ProcessId)
            if($verified.CreationDate -ne $owned[0].CreationDate){throw 'The settings service changed. Try again.'}
            Stop-Process -Id $owned[0].ProcessId
            Start-Sleep -Milliseconds 200
        } else {
        throw ('Port '+$gatewayPort+' belongs to another application.')
        }
    } else {
        $socket = New-Object Net.Sockets.TcpClient
        try {
            $pending = $socket.BeginConnect('127.0.0.1',$gatewayPort,$null,$null)
            if ($pending.AsyncWaitHandle.WaitOne(100) -and $socket.Connected) { throw ('Port '+$gatewayPort+' is occupied. Diagnostics can help identify the conflict.') }
        } finally { $socket.Dispose() }
    }
    $arguments = '"{0}" serve --config "{1}"' -f $scriptPath,$ConfigPath
    $logs = Join-Path $Settings.StateRoot 'logs'
    [void][IO.Directory]::CreateDirectory($logs)
    Start-Process -FilePath $Settings.PythonExecutable -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logs 'control-stdout.log') -RedirectStandardError (Join-Path $logs 'control-stderr.log') | Out-Null
    for ($attempt=0; $attempt -lt 20; $attempt++) {
        Start-Sleep -Milliseconds 150
        try {
            $health=Invoke-RestMethod $healthUrl -TimeoutSec 1
            if ($health.service -eq 'aibrainworx-control' -and $health.dataIdentity -eq $expected.dataIdentity -and $health.version -eq $expected.version) { return }
        } catch {}
    }
    throw 'The local settings service did not become ready. Check Diagnostics and local logs.'
    } finally { if ($held) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
}

function Save-AwxEditor($Dialog,[bool]$AsNew) {
    $ui = $Dialog.Tag
    try {
        $profile = ($ui.State.active | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
        $profile.name = $ui.Name.Text.Trim()
        $profile.workspaceRoot = $ui.Folder.Text.Trim().Trim('"')
        $profile.enginePython = $ui.Engine.Text.Trim().Trim('"')
        $profile.useInstructions = $ui.UsePrompt.Checked
        $profile.instructions = $ui.Prompt.Text
        $profile.overrideSampling = $ui.Sampling.Checked
        $profile.temperature = [double]$ui.Temperature.Value / 100
        $profile.topP = [double]$ui.TopP.Value / 100
        $profile.maxOutputTokens = [int]$ui.Tokens.Value
        $profile.useAndroid = $ui.Android.Checked
        $profile.useBlender = $ui.Blender.Checked
        $profile.preset = $ui.State.presets[$ui.Preset.SelectedIndex].id
        $ui.Result = Invoke-AwxOperation $ui.Settings $ui.ConfigPath 'save' @{profile=$profile;saveAsNew=$AsNew;revision=$ui.State.revision}
        $Dialog.DialogResult = [Windows.Forms.DialogResult]::OK
        $Dialog.Close()
    } catch { $ui.Feedback.Text = $_.Exception.Message }
}

function Show-AwxSettings($Owner,$Settings,[string]$ConfigPath,$State,[string]$CaptureImage='') {
    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = 'AiBrainWorX | Instructions, model settings and profiles'
    $dialog.ClientSize = New-Object Drawing.Size(900,776)
    $dialog.StartPosition = 'CenterParent'
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox = $false
    $dialog.BackColor = $Owner.BackColor
    $dialog.ForeColor = $Owner.ForeColor
    $dialog.Font = New-Object Drawing.Font('Segoe UI',10)
    $ui = @{State=$State;Settings=$Settings;ConfigPath=$ConfigPath;Result=$null}
    $dialog.Tag = $ui
    function Label($Text,$X,$Y,$W,$H=24) {
        $item = New-Object Windows.Forms.Label
        $item.Text=$Text; $item.UseMnemonic=$false; $item.SetBounds($X,$Y,$W,$H)
        $dialog.Controls.Add($item)
        return $item
    }
    function InputBox($Text,$X,$Y,$W,$H=28) {
        $item = New-Object Windows.Forms.TextBox
        $item.Text=$Text; $item.SetBounds($X,$Y,$W,$H); $item.BackColor=[Drawing.ColorTranslator]::FromHtml('#182438'); $item.ForeColor=$dialog.ForeColor
        $item.BorderStyle='FixedSingle';$dialog.Controls.Add($item)
        return $item
    }
    function Button($Text,$X,$Y,$W,$Handler) {
        $item = New-Object Windows.Forms.Button
        $item.Text=$Text;$item.SetBounds($X,$Y,$W,34);$item.FlatStyle='Flat';$item.BackColor=[Drawing.ColorTranslator]::FromHtml('#243349');$item.Add_Click($Handler)
        $dialog.Controls.Add($item);return $item
    }
    [void](Label 'LAUNCH PROFILE / SAVED ON THIS PC' 24 18 850)
    [void](Label 'Profile name' 24 55 130)
    $ui.Name = InputBox $State.active.name 164 52 710
    [void](Label 'Project folder' 24 97 130)
    $ui.Folder = InputBox $State.active.workspaceRoot 164 94 580
    $browse = Button 'Browse' 756 90 118 { param($sender,$e); $d=$sender.FindForm();$pick=New-Object Windows.Forms.FolderBrowserDialog; if($pick.ShowDialog($d) -eq 'OK'){$d.Tag.Folder.Text=$pick.SelectedPath};$pick.Dispose() }
    [void](Label 'Engine Python' 24 139 130)
    $ui.Engine = InputBox $State.active.enginePython 164 136 580
    $browseEngine = Button 'Browse' 756 132 118 { param($sender,$e);$d=$sender.FindForm();$pick=New-Object Windows.Forms.FolderBrowserDialog;$pick.Description='Choose the engine folder containing remote_execution.py. Unreal is optional.';if($pick.ShowDialog($d) -eq 'OK'){$d.Tag.Engine.Text=$pick.SelectedPath};$pick.Dispose() }
    [void](Label 'Unreal is optional. Select its PythonScriptPlugin folder to enable editor inspection.' 164 168 710 22)
    $ui.Preset = New-Object Windows.Forms.ComboBox
    $ui.Preset.DropDownStyle='DropDownList';$ui.Preset.SetBounds(24,205,405,30)
    $ui.Preset.Items.AddRange([object[]]@($State.presets | ForEach-Object {$_.name}));$ui.Preset.SelectedIndex=0
    for($i=0;$i -lt $State.presets.Count;$i++){if($State.presets[$i].id -eq $State.active.preset){$ui.Preset.SelectedIndex=$i}}
    $dialog.Controls.Add($ui.Preset)
    $load = Button 'Load template' 444 201 135 {param($sender,$e);$u=$sender.FindForm().Tag;$p=$u.State.presets[$u.Preset.SelectedIndex];$u.Prompt.Text=$p.text;$u.UsePrompt.Checked=$true;if($p.profileDefaults){$u.Android.Checked=$p.profileDefaults.useAndroid;$u.Blender.Checked=$p.profileDefaults.useBlender}}
    $ui.UsePrompt = New-Object Windows.Forms.CheckBox
    $ui.UsePrompt.Text='Use custom instructions';$ui.UsePrompt.SetBounds(608,204,270,26);$ui.UsePrompt.Checked=[bool]$State.active.useInstructions
    $dialog.Controls.Add($ui.UsePrompt)
    $ui.Prompt = InputBox $State.active.instructions 24 246 850 210
    $ui.Prompt.Multiline=$true;$ui.Prompt.ScrollBars='Vertical';$ui.Prompt.AcceptsReturn=$true;$ui.Prompt.MaxLength=8192
    $ui.Prompt.Font=New-Object Drawing.Font('Consolas',10)
    $ui.UsePrompt.Add_CheckedChanged({param($sender,$e);$sender.FindForm().Tag.Prompt.Enabled=$sender.Checked})
    $ui.Prompt.Enabled=$ui.UsePrompt.Checked
    [void](Label 'Added to new model requests. Client tool permissions and built-in instructions remain in place.' 24 466 850 26)
    $ui.Sampling = New-Object Windows.Forms.CheckBox
    $ui.Sampling.Text='Override temperature and top-p';$ui.Sampling.SetBounds(24,506,850,28);$ui.Sampling.Checked=[bool]$State.active.overrideSampling
    $dialog.Controls.Add($ui.Sampling)
    [void](Label 'Temperature' 24 548 140)
    $ui.Android=New-Object Windows.Forms.CheckBox
    $ui.Android.Text='Android inspection tools';$ui.Android.SetBounds(24,650,410,27);$ui.Android.Checked=[bool]$State.active.useAndroid;$dialog.Controls.Add($ui.Android)
    $ui.Blender=New-Object Windows.Forms.CheckBox
    $ui.Blender.Text='Blender inspection tools (add-on required)';$ui.Blender.SetBounds(450,650,424,27);$ui.Blender.Checked=[bool]$State.active.useBlender;$dialog.Controls.Add($ui.Blender)
    $ui.TempValue=Label ('{0:N2}' -f $State.active.temperature) 385 548 80
    $ui.Temperature=New-Object Windows.Forms.TrackBar
    $ui.Temperature.Minimum=0;$ui.Temperature.Maximum=200;$ui.Temperature.TickFrequency=25;$ui.Temperature.Value=[int]([double]$State.active.temperature*100);$ui.Temperature.SetBounds(164,540,215,46)
    $dialog.Controls.Add($ui.Temperature)
    [void](Label 'Top-p' 24 596 140)
    $ui.TopValue=Label ('{0:N2}' -f $State.active.topP) 385 596 80
    $ui.TopP=New-Object Windows.Forms.TrackBar
    $ui.TopP.Minimum=1;$ui.TopP.Maximum=100;$ui.TopP.TickFrequency=10;$ui.TopP.Value=[int]([double]$State.active.topP*100);$ui.TopP.SetBounds(164,588,215,46)
    $dialog.Controls.Add($ui.TopP)
    $ui.Temperature.Add_ValueChanged({param($sender,$e);$sender.FindForm().Tag.TempValue.Text='{0:N2}' -f ($sender.Value/100)})
    $ui.TopP.Add_ValueChanged({param($sender,$e);$sender.FindForm().Tag.TopValue.Text='{0:N2}' -f ($sender.Value/100)})
    $ui.Sampling.Add_CheckedChanged({param($sender,$e);$u=$sender.FindForm().Tag;$u.Temperature.Enabled=$sender.Checked;$u.TopP.Enabled=$sender.Checked})
    $ui.Temperature.Enabled=$ui.Sampling.Checked;$ui.TopP.Enabled=$ui.Sampling.Checked
    [void](Label 'Maximum output tokens' 514 550 350)
    $ui.Tokens=New-Object Windows.Forms.NumericUpDown
    $ui.Tokens.Minimum=64;$ui.Tokens.Maximum=65536;$ui.Tokens.Increment=128;$ui.Tokens.Value=$State.active.maxOutputTokens;$ui.Tokens.SetBounds(514,583,260,30)
    $dialog.Controls.Add($ui.Tokens)
    [void](Label 'This is a cap; a client can request less.' 514 623 350 25)
    $ui.Feedback=Label '' 24 679 850 36
    $ui.Feedback.ForeColor=[Drawing.ColorTranslator]::FromHtml('#B5A2FF')
    $save=Button 'Save profile' 24 727 200 {param($sender,$e);Save-AwxEditor $sender.FindForm() $false}
    $saveAs=Button 'Save as new' 244 727 200 {param($sender,$e);Save-AwxEditor $sender.FindForm() $true}
    $cancel=Button 'Cancel' 674 727 200 {param($sender,$e);$sender.FindForm().Close()}
    if($CaptureImage){
        $ui.Name.Text='Unreal development - example';$ui.Folder.Text='C:\Projects\YourGame';$ui.Engine.Text='C:\Epic\UE_5.8\Engine\Plugins\Experimental\PythonScriptPlugin\Content\Python'
        $ui.Preset.SelectedIndex=1;$ui.Prompt.Text=$State.presets[1].text;$ui.UsePrompt.Checked=$true;$ui.Sampling.Checked=$true;$save.Enabled=$false;$saveAs.Enabled=$false
        $dialog.Tag.Capture=$CaptureImage
        $dialog.Add_Shown({param($sender,$e);$bitmap=New-Object Drawing.Bitmap($sender.Width,$sender.Height);try{$sender.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$sender.Width,$sender.Height)));$bitmap.Save($sender.Tag.Capture,[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()};$sender.Close()})
    }
    [void]$dialog.ShowDialog($Owner)
    $result=$dialog.Tag.Result
    $dialog.Dispose()
    return $result
}

function Show-AwxDiagnostics($Owner,$Settings,[string]$ConfigPath) {
    $dialog=New-Object Windows.Forms.Form
    $dialog.Text='AiBrainWorX | Connection diagnostics';$dialog.ClientSize=New-Object Drawing.Size(900,410);$dialog.StartPosition='CenterParent'
    $dialog.BackColor=$Owner.BackColor;$dialog.ForeColor=$Owner.ForeColor;$dialog.Font=$Owner.Font
    $list=New-Object Windows.Forms.ListView
    $list.View='Details';$list.FullRowSelect=$true;$list.SetBounds(20,20,860,300);$list.BackColor=$Owner.BackColor;$list.ForeColor=$Owner.ForeColor
    [void]$list.Columns.Add('Check',180);[void]$list.Columns.Add('Status',130);[void]$list.Columns.Add('Detail',520);$dialog.Controls.Add($list)
    $note=New-Object Windows.Forms.Label;$note.Text='Checking local connections. No generation request is sent.';$note.SetBounds(20,329,850,26);$dialog.Controls.Add($note)
    $copy=New-Object Windows.Forms.Button;$copy.Text='Copy report';$copy.Enabled=$false;$copy.SetBounds(20,366,180,30);$dialog.Controls.Add($copy)
    $close=New-Object Windows.Forms.Button;$close.Text='Close';$close.SetBounds(700,366,180,30);$close.Add_Click({param($sender,$e);$sender.FindForm().Close()});$dialog.Controls.Add($close)
    $job=Start-AwxOperation $Settings $ConfigPath 'diagnose'
    $timer=New-Object Windows.Forms.Timer;$timer.Interval=150
    $dialog.Tag=@{Job=$job;Timer=$timer;List=$list;Note=$note;Copy=$copy;Report='';Completed=$false}
    $timer.Add_Tick({param($sender,$e);$d=$sender.Tag;$u=$d.Tag;if(-not $u.Job.Process.HasExited){return};$sender.Stop();$u.Completed=$true;try{$report=Complete-AwxOperation $u.Job;foreach($check in $report.checks){$item=New-Object Windows.Forms.ListViewItem($check.name);[void]$item.SubItems.Add($check.status);[void]$item.SubItems.Add($check.detail);[void]$u.List.Items.Add($item)};$u.Note.Text=$report.note;$u.Report='AiBrainWorX '+$report.version+"`r`n"+(@($report.checks | ForEach-Object {$_.name+': '+$_.status+' - '+$_.detail}) -join "`r`n");$u.Copy.Enabled=$true}catch{$u.Note.Text=$_.Exception.Message}})
    $timer.Tag=$dialog
    $copy.Add_Click({param($sender,$e);[Windows.Forms.Clipboard]::SetText($sender.FindForm().Tag.Report)})
    $dialog.Add_FormClosed({param($sender,$e);$sender.Tag.Timer.Stop();$sender.Tag.Timer.Dispose();if(-not $sender.Tag.Completed){if(-not $sender.Tag.Job.Process.HasExited){$sender.Tag.Job.Process.Kill()};$sender.Tag.Job.Process.Dispose()}})
    $timer.Start();[void]$dialog.ShowDialog($Owner);$dialog.Dispose()
}
