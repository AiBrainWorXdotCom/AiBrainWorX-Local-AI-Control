param([ValidateSet('Gui','Start','Stop','Status','Open','UnrealStatus')][string]$Action = 'Gui', [string]$CaptureImage = '', [string]$CaptureFrames = '', [ValidateSet('Harness','Codex')][string]$Workspace = 'Harness', [string]$CaptureSettingsImage = '')
$ErrorActionPreference = 'Stop'
$ConfigPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'config.local.json'
. (Join-Path $PSScriptRoot 'Settings.ps1')
. (Join-Path $PSScriptRoot 'Control.ps1')
$settings = Read-AwxSettings $ConfigPath
$script:launchState = Invoke-AwxOperation $settings $ConfigPath 'state'
$Node = $settings.NodeExecutable
$Entry = $settings.HarnessEntry
$Project = $settings.WorkspaceRoot
$Python = $settings.PythonExecutable
$Bridge = Join-Path (Split-Path $PSScriptRoot -Parent) 'bridge\unreal_mcp.py'
$QwenControl = Join-Path $PSScriptRoot 'Strata-Control.ps1'
$BaseUrl = 'http://127.0.0.1:3080'
$Stdout = Join-Path $settings.StateRoot 'logs\harness-stdout.log'
$Stderr = Join-Path $settings.StateRoot 'logs\harness-stderr.log'

function Get-HarnessProcess {
    @(Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" | Where-Object {
        $_.ExecutablePath -eq $Node -and $_.CommandLine -and
        $_.CommandLine.Contains($Entry) -and $_.CommandLine.Contains('--port 3080')
    })
}

function Test-HarnessPort {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $pending = $client.BeginConnect('127.0.0.1',3080,$null,$null)
        if (-not $pending.AsyncWaitHandle.WaitOne(200)) { return $false }
        $client.EndConnect($pending)
        return $true
    } catch { return $false } finally { $client.Dispose() }
}

function Get-HarnessStatus {
    if (@(Get-HarnessProcess).Count -eq 0) {
        if (Test-HarnessPort) { return 'Port 3080 belongs to another process. Start is blocked.' }
        return 'Stopped - click Start Harness when needed.'
    }
    if (Test-HarnessPort) {
        try {
            $run = Get-Content -LiteralPath (Join-Path $settings.StateRoot 'harness-runtime.local.json') -Raw | ConvertFrom-Json
            if ($run.ProfileId -eq $script:launchState.activeId -and @((Get-HarnessProcess) | Where-Object {$_.ProcessId -eq $run.Pid}).Count) { return 'Running - local Harness is ready on port 3080.' }
        } catch {}
        return 'Running - stop/start Harness once to apply saved profiles.'
    }
    return 'Starting - loading Harness and its Unreal tools.'
}

function Get-QwenStatus {
    try {
        $health = Invoke-RestMethod 'http://127.0.0.1:8081/health' -TimeoutSec 1
        if ($health.service -eq 'strata' -and $health.loaded) { return 'Model: ready through Strata on port 8081.' }
        return 'Model: loading.'
    } catch { return 'Model: stopped or still starting.' }
}

function Start-Harness {
    $mutex = New-Object System.Threading.Mutex($false,'Local\DeepSeekHarnessManual3080')
    $held = $false
    try {
        $held = $mutex.WaitOne(0)
        if (-not $held) { throw 'Another Harness start is in progress.' }
        if (@(Get-HarnessProcess).Count -gt 0) { return (Get-HarnessStatus) }
        if (Test-HarnessPort) { throw 'Port 3080 is already occupied. No second server was started.' }
        $prepared = Invoke-AwxOperation $settings $ConfigPath 'prepare'
        Start-AwxService $settings $ConfigPath
        foreach ($file in @($Node,$Entry,$Python,$Bridge)) {
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing installed component: $file" }
        }
        $arguments = '"{0}" web --no-open --host 127.0.0.1 --port 3080' -f $Entry
        # Windows PowerShell 5.1, also used by the Qwen panel, has no -Environment switch.
        # Temporarily supply a placeholder to this process's child; preserve the caller's value.
        $previousKey = [Environment]::GetEnvironmentVariable('AIBRAINWORX_API_KEY','Process')
        $previousHome = [Environment]::GetEnvironmentVariable('DSH_HOME','Process')
        try {
            [Environment]::SetEnvironmentVariable('AIBRAINWORX_API_KEY','strata-local-no-auth','Process')
            [Environment]::SetEnvironmentVariable('DSH_HOME',$prepared.HarnessHome,'Process')
            $process = Start-Process -FilePath $Node -ArgumentList $arguments -WorkingDirectory $prepared.WorkspaceRoot -WindowStyle Hidden -RedirectStandardOutput $Stdout -RedirectStandardError $Stderr -PassThru
            [IO.File]::WriteAllText((Join-Path $settings.StateRoot 'harness-runtime.local.json'),(@{Pid=$process.Id;ProfileId=$prepared.ProfileId} | ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
        } finally {
            [Environment]::SetEnvironmentVariable('AIBRAINWORX_API_KEY',$previousKey,'Process')
            [Environment]::SetEnvironmentVariable('DSH_HOME',$previousHome,'Process')
        }
        return "Harness start requested (PID $($process.Id)). Qwen has its own Start button."
    } finally {
        if ($held) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Stop-Harness {
    foreach ($process in @(Get-HarnessProcess)) {
        $verified = @(Get-HarnessProcess | Where-Object { $_.ProcessId -eq $process.ProcessId -and $_.CreationDate -eq $process.CreationDate })
        if ($verified.Count -eq 0) { continue }
        & "$env:SystemRoot\System32\taskkill.exe" /PID $process.ProcessId /T /F | Out-Null
        if ($LASTEXITCODE -ne 0 -and @(Get-HarnessProcess).Count -gt 0) { throw 'Harness could not be stopped.' }
    }
    return 'Harness stopped. Qwen is controlled separately.'
}

function Open-Harness {
    if (@(Get-HarnessProcess).Count -eq 0 -or -not (Test-HarnessPort)) { throw 'Start Harness and wait for Running before opening it.' }
    # Harness authenticates its browser with a process URL. Never display that credential in status output.
    $log = if (Test-Path -LiteralPath $Stdout) { Get-Content -LiteralPath $Stdout -Raw } else { '' }
    $match = [regex]::Match($log,'http://127\.0\.0\.1:3080/[^\s\x1b]*')
    if (-not $match.Success) { throw 'The browser sign-in URL is not ready. Try Open Harness again shortly.' }
    Start-Process -FilePath $match.Value | Out-Null
    return 'Harness opened in your browser.'
}

function Open-Codex {
    $health = Invoke-RestMethod 'http://127.0.0.1:8081/health' -TimeoutSec 2
    if ($health.service -ne 'strata' -or -not $health.loaded) { throw 'Start the model and wait for Ready before opening a coding client.' }
    Start-AwxService $settings $ConfigPath
    $launcher = Join-Path $PSScriptRoot 'Start-Codex.ps1'
    & $launcher -ConfigPath $ConfigPath -CheckOnly | Out-Null
    $arguments = '-NoProfile -NoExit -ExecutionPolicy Bypass -File "{0}" -ConfigPath "{1}"' -f $launcher,$ConfigPath
    # This is an interactive coding terminal opened by the user's Open CLI button.
    Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $arguments -WorkingDirectory $Project -WindowStyle Normal | Out-Null
    return 'Local Codex CLI opened. The model and Harness remain under separate controls.'
}

function Get-UnrealStatus {
    $selected = $script:launchState.active
    if (-not ($selected.unrealProjectName -and $selected.enginePython)) { return 'Unreal tools are optional. Choose the project and engine folder in Settings.' }
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $Python
    $start.Arguments = '"{0}" --status' -f $Bridge
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.EnvironmentVariables['UE_PROJECT_ROOT'] = $selected.workspaceRoot
    $start.EnvironmentVariables['UE_PROJECT_NAME'] = $selected.unrealProjectName
    $start.EnvironmentVariables['UE_ENGINE_PYTHON'] = $selected.enginePython
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    [void]$process.Start()
    $output = $process.StandardOutput.ReadToEndAsync()
    $errorOutput = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(20000)) { $process.Kill(); throw 'Unreal inspection timed out. No editor changes were requested.' }
    if ($process.ExitCode -ne 0) { throw 'Unreal inspection is unavailable. Check the engine Python setting and open the project.' }
    $state = $output.Result | ConvertFrom-Json
    $process.Dispose()
    if ($state.editor_connected) { return 'Unreal editor connected. Five read-only inspection tools available.' }
    return 'Open the configured Unreal project for live actor and asset inspection.'
}

switch ($Action) {
    'Start' { Start-Harness; return }
    'Stop' { Stop-Harness; return }
    'Status' { Get-HarnessStatus; Get-QwenStatus; return }
    'Open' { Open-Harness; return }
    'UnrealStatus' { Get-UnrealStatus; return }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.Http
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class AiBrainWorXWindow {
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int command);
}
'@
[System.Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object System.Windows.Forms.Form
$form.Text = 'AiBrainWorX | Local AI Control'
$form.ClientSize = New-Object System.Drawing.Size(1000,855)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.AutoScaleMode = 'None'
$palette = @{
    Background = [System.Drawing.ColorTranslator]::FromHtml('#0C111B')
    Card = [System.Drawing.ColorTranslator]::FromHtml('#141D2B')
    Border = [System.Drawing.ColorTranslator]::FromHtml('#29384D')
    Text = [System.Drawing.ColorTranslator]::FromHtml('#F0F5FC')
    Muted = [System.Drawing.ColorTranslator]::FromHtml('#A6B4CB')
    Cyan = [System.Drawing.ColorTranslator]::FromHtml('#6DE7D6')
    Purple = [System.Drawing.ColorTranslator]::FromHtml('#B5A2FF')
    Button = [System.Drawing.ColorTranslator]::FromHtml('#243349')
}
$form.BackColor = $palette.Background
$form.ForeColor = $palette.Text
$form.Font = New-Object System.Drawing.Font('Segoe UI',10)
. (Join-Path $PSScriptRoot 'Hardware.ps1')
$hardware = Get-LocalHardware

function New-Text($parent,$text,$x,$y,$width,$height,$size=10,$bold=$false,$color=$null) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $text
    $label.UseMnemonic = $false
    $label.SetBounds($x,$y,$width,$height)
    $style = if ($bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    $label.Font = New-Object System.Drawing.Font('Segoe UI',$size,$style)
    $label.ForeColor = if ($color) { $color } else { $palette.Text }
    $label.BackColor = [System.Drawing.Color]::Transparent
    $parent.Controls.Add($label)
    return $label
}

function New-Card($x,$y,$width,$height,$accent) {
    $panel = New-Object System.Windows.Forms.Panel
    $panel.SetBounds($x,$y,$width,$height)
    $panel.BackColor = $palette.Card
    $panel.Tag = $accent
    $panel.Add_Paint({
        param($sender,$paint)
        $pen = New-Object System.Drawing.Pen($palette.Border)
        $brush = New-Object System.Drawing.SolidBrush($sender.Tag)
        try {
            $paint.Graphics.DrawRectangle($pen,0,0,$sender.Width-1,$sender.Height-1)
            $paint.Graphics.FillRectangle($brush,0,0,52,3)
        } finally { $pen.Dispose(); $brush.Dispose() }
    })
    $form.Controls.Add($panel)
    return $panel
}

function New-ControlButton($parent,$text,$x,$y,$width,$handler,$accent=$null,[switch]$PassThru) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $text
    $button.SetBounds($x,$y,$width,38)
    $button.FlatStyle = 'Flat'
    $button.FlatAppearance.BorderSize = 0
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.Font = New-Object System.Drawing.Font('Segoe UI',10,[System.Drawing.FontStyle]::Bold)
    $button.BackColor = if ($accent) { $accent } else { $palette.Button }
    $button.ForeColor = if ($accent) { $palette.Background } else { $palette.Text }
    $button.Add_Click($handler)
    $parent.Controls.Add($button)
    if ($PassThru) { return $button }
}

$brand = New-Text $form 'AiBrainWorX' 32 23 500 35 19 $true $palette.Cyan
$edition = New-Text $form ('PORTABLE WINDOWS LOCAL AI / '+$script:launchState.version) 32 64 650 22 9 $true $palette.Muted
$localTag = New-Text $form 'LOCALHOST  /  MANUAL START' 705 31 265 28 9 $true $palette.Purple
$title = New-Text $form 'Portable local AI. Your workflow.' 30 96 940 49 26 $true
$subtitle = New-Text $form ($settings.ModelLabel + ' + saved prompts, sampling controls and project profiles') 32 148 940 28 10 $false $palette.Muted

$profileLabel = New-Text $form 'PROFILE' 32 201 90 26 9 $true $palette.Cyan
$profilePicker=New-Object Windows.Forms.ComboBox
$profilePicker.DropDownStyle='DropDownList';$profilePicker.SetBounds(126,196,512,32);$profilePicker.Font=New-Object Drawing.Font('Segoe UI',12)
$form.Controls.Add($profilePicker)
New-ControlButton $form 'Settings' 658 191 145 { try { $script:launchState=Invoke-AwxOperation $settings $ConfigPath 'state';$result=Show-AwxSettings $form $settings $ConfigPath $script:launchState; if($null -ne $result){$script:launchState=$result;Refresh-ProfilePicker;$feedback.Text='Saved locally. '+(Get-HarnessStatus);Update-Panel} } catch {$feedback.Text=$_.Exception.Message} }
New-ControlButton $form 'Diagnostics' 823 191 145 { try { Show-AwxDiagnostics $form $settings $ConfigPath } catch {$feedback.Text=$_.Exception.Message} }

$gpuCard = New-Card 32 252 300 100 $palette.Cyan
$gpuLabel = New-Text $gpuCard 'GRAPHICS' 16 12 265 18 8 $true $palette.Muted
$gpuValue = New-Text $gpuCard $hardware.GPU 16 36 274 31 13 $true
$gpuLive = New-Text $gpuCard 'VRAM usage: waiting for model metrics' 16 72 274 22 9 $false $palette.Muted
$cpuCard = New-Card 350 252 300 100 $palette.Purple
$cpuLabel = New-Text $cpuCard 'PROCESSOR' 16 12 265 18 8 $true $palette.Muted
$cpuValue = New-Text $cpuCard $hardware.CPU 16 36 274 31 13 $true
$cpuLive = New-Text $cpuCard 'CPU usage: waiting for model metrics' 16 72 274 22 9 $false $palette.Muted
$ramCard = New-Card 668 252 300 100 $palette.Cyan
$ramLabel = New-Text $ramCard 'SYSTEM MEMORY' 16 12 270 18 8 $true $palette.Muted
$ramValue = New-Text $ramCard $hardware.RAM 16 36 274 31 13 $true
$ramLive = New-Text $ramCard 'RAM usage: waiting for model metrics' 16 72 274 22 9 $false $palette.Muted

$speedCard = New-Card 32 368 936 60 $palette.Cyan
$speedValue=New-Text $speedCard 'Waiting for model metrics' 16 15 400 30 15 $true $palette.Cyan
$speedDetail=New-Text $speedCard 'Shared Strata model / current or last request' 430 12 488 44 9 $false $palette.Muted

$modelCard = New-Card 32 444 456 205 $palette.Cyan
$modelEyebrow = New-Text $modelCard '01 / MODEL ENGINE' 20 16 415 22 9 $true $palette.Cyan
$modelTitle = New-Text $modelCard 'Local model / Strata' 20 48 415 35 18 $true
$modelEndpoint = New-Text $modelCard 'LOCAL INFERENCE  /  127.0.0.1:8081' 21 91 415 20 9 $false $palette.Muted
$modelStatus = New-Text $modelCard 'Checking model...' 21 118 415 34 10 $false $palette.Muted
New-ControlButton $modelCard 'Start model' 20 156 200 { try { $feedback.Text = & $QwenControl -Action Start;Start-AwxService $settings $ConfigPath } catch { $feedback.Text = $_.Exception.Message }; Update-Panel } $palette.Cyan
New-ControlButton $modelCard 'Stop model' 236 156 200 { try { $feedback.Text = & $QwenControl -Action Stop } catch { $feedback.Text = $_.Exception.Message }; Update-Panel }

$harnessCard = New-Card 512 444 456 205 $palette.Purple
$harnessEyebrow = New-Text $harnessCard '02 / CHOOSE YOUR WORKSPACE' 20 16 415 22 9 $true $palette.Purple
$workspacePicker = New-Object System.Windows.Forms.ComboBox
$workspacePicker.DropDownStyle = 'DropDownList'
$workspacePicker.FlatStyle = 'Flat'
$workspacePicker.BackColor = $palette.Button
$workspacePicker.ForeColor = $palette.Text
$workspacePicker.Font = New-Object System.Drawing.Font('Segoe UI',13,[System.Drawing.FontStyle]::Bold)
$workspacePicker.SetBounds(20,48,416,34)
$workspacePicker.Items.AddRange(@('DeepSeek Harness (browser)','Codex CLI (optional)'))
$workspacePicker.SelectedIndex = if ($Workspace -eq 'Codex') { 1 } else { 0 }
$harnessCard.Controls.Add($workspacePicker)
$harnessEndpoint = New-Text $harnessCard 'BROWSER CHAT  /  127.0.0.1:3080' 21 91 415 20 9 $false $palette.Muted
$status = New-Text $harnessCard 'Checking Harness...' 21 118 415 34 10 $false $palette.Muted
$workspaceStart = New-ControlButton $harnessCard 'Start' 20 156 120 { try { $feedback.Text = Start-Harness } catch { $feedback.Text = $_.Exception.Message }; Update-Panel } -PassThru
$workspaceStop = New-ControlButton $harnessCard 'Stop' 152 156 120 { try { $feedback.Text = Stop-Harness } catch { $feedback.Text = $_.Exception.Message }; Update-Panel } -PassThru
$workspaceOpen = New-ControlButton $harnessCard 'Open chat' 284 156 152 { try { $feedback.Text = if ($workspacePicker.SelectedIndex -eq 1) { Open-Codex } else { Open-Harness } } catch { $feedback.Text = $_.Exception.Message } } $palette.Purple -PassThru

$unrealCard = New-Card 32 667 936 83 $palette.Purple
$unrealTitle = New-Text $unrealCard 'UNREAL ENGINE / OPTIONAL EDITOR TOOLS' 20 13 710 23 10 $true
$unrealStatus = New-Text $unrealCard 'Five inspection tools configured. Check the live editor connection.' 21 42 708 30 9 $false $palette.Muted
New-ControlButton $unrealCard 'Check Unreal' 760 24 156 { try { $unrealStatus.Text = Get-UnrealStatus } catch { $unrealStatus.Text = $_.Exception.Message } }
$feedback = New-Text $form '' 32 760 936 43 9 $false $palette.Purple
$footer = New-Text $form 'Made by AiBrainWorX' 32 823 290 23 10 $true $palette.Cyan
$note = New-Text $form 'Closing this panel keeps your services running.' 330 824 390 22 8 $false $palette.Muted

$logs = New-Object System.Windows.Forms.LinkLabel
$logs.Text = 'Logs + files'
$logs.LinkColor = $palette.Muted
$logs.ActiveLinkColor = $palette.Cyan
$logs.VisitedLinkColor = $palette.Muted
$logs.SetBounds(860,823,110,22)
$logs.Add_LinkClicked({ Start-Process -FilePath "$env:SystemRoot\explorer.exe" -ArgumentList ('"{0}"' -f $PSScriptRoot) })
$form.Controls.Add($logs)

function Refresh-ProfilePicker {
    $script:loadingProfiles=$true
    $profilePicker.Items.Clear()
    $profilePicker.Items.AddRange([object[]]@($script:launchState.profiles | ForEach-Object {$_.name}))
    for($i=0;$i -lt $script:launchState.profiles.Count;$i++){if($script:launchState.profiles[$i].id -eq $script:launchState.activeId){$profilePicker.SelectedIndex=$i}}
    $script:loadingProfiles=$false
}
Refresh-ProfilePicker
$profilePicker.Add_SelectedIndexChanged({
    if($script:loadingProfiles -or $profilePicker.SelectedIndex -lt 0){return}
    try{$chosen=$script:launchState.profiles[$profilePicker.SelectedIndex].id;$script:launchState=Invoke-AwxOperation $settings $ConfigPath 'select' @{id=$chosen};$feedback.Text='Selected '+$script:launchState.active.name;Update-Panel}
    catch{$feedback.Text=$_.Exception.Message;Refresh-ProfilePicker}
})

$script:metricsClient=New-Object Net.Http.HttpClient
$script:metricsClient.Timeout=[TimeSpan]::FromSeconds(2)
$script:metricsTask=$null
function Update-Metrics {
    if($null -ne $script:metricsTask -and $script:metricsTask.IsCompleted){
        try{
            $m=$script:metricsTask.Result | ConvertFrom-Json
            if($m.live.state -eq 'generating' -and $null -ne $m.live.tok_s){$speedValue.Text='Live: {0:N1} tokens/s' -f $m.live.tok_s}
            elseif(@($m.requests).Count -gt 0 -and $null -ne $m.requests[0].decode_tok_s){$speedValue.Text='Idle - last: {0:N1} tokens/s' -f $m.requests[0].decode_tok_s}
            else{$speedValue.Text='Model '+$m.live.state+' - no speed sample'}
            if($null -ne $m.hardware.gpu_mem_used -and $null -ne $m.hardware.gpu_mem_total){$gpuLive.Text='VRAM: {0:N1} / {1:N1} GB' -f ($m.hardware.gpu_mem_used/1GB),($m.hardware.gpu_mem_total/1GB)}
            if($null -ne $m.hardware.cpu){$cpuLive.Text='CPU usage: {0:N1}%' -f $m.hardware.cpu}
            if($null -ne $m.hardware.ram_used -and $null -ne $m.hardware.ram_total){$ramLive.Text='Used: {0:N1} / {1:N1} GB' -f ($m.hardware.ram_used/1GB),($m.hardware.ram_total/1GB)}
        }catch{$speedValue.Text='Model metrics unavailable';$gpuLive.Text='VRAM usage unavailable';$cpuLive.Text='CPU usage unavailable';$ramLive.Text='RAM usage unavailable'}
        $script:metricsTask=$null
    }
    if($null -eq $script:metricsTask){$script:metricsTask=$script:metricsClient.GetStringAsync('http://127.0.0.1:8081/metrics')}
}

function Update-Panel {
    try {
        $terminal = $workspacePicker.SelectedIndex -eq 1
        $workspaceStart.Enabled = -not $terminal
        $workspaceStop.Enabled = -not $terminal
        $workspaceOpen.Text = if ($terminal) { 'Open CLI' } else { 'Open chat' }
        $harnessEndpoint.Text = if ($terminal) { 'LOCAL PROFILE  /  aibrainworx-local' } else { 'BROWSER CHAT  /  127.0.0.1:3080' }
        $status.Text = if ($terminal) { 'Uses the running model. Close its terminal to end the client.' } else { Get-HarnessStatus }
        $modelStatus.Text = Get-QwenStatus
        $status.ForeColor = if ($status.Text.StartsWith('Running')) { $palette.Cyan } else { $palette.Muted }
        $modelStatus.ForeColor = if ($modelStatus.Text.Contains('ready')) { $palette.Cyan } else { $palette.Muted }
        $speedDetail.Text='Profile: '+$script:launchState.active.name+"`r`n"+'Output cap: '+$script:launchState.active.maxOutputTokens+' | Instructions: '+$(if($script:launchState.active.useInstructions){'on'}else{'off'})
        Update-Metrics
    }
    catch { $feedback.Text = $_.Exception.Message }
}
$workspacePicker.Add_SelectedIndexChanged({ Update-Panel })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 2000
$timer.Add_Tick({ Update-Panel })
$form.Add_Shown({
    [void][AiBrainWorXWindow]::ShowWindow($form.Handle,9)
    Update-Panel
    $timer.Start()
    if($CaptureSettingsImage){[void](Show-AwxSettings $form $settings $ConfigPath $script:launchState $CaptureSettingsImage);$form.Close();return}
    if ($CaptureImage -and -not $CaptureFrames) {
        $script:imageTimer=New-Object Windows.Forms.Timer;$script:imageTimer.Interval=300;$script:imageTicks=0
        $script:imageTimer.Add_Tick({$script:imageTicks++;Update-Metrics;if($script:imageTicks -lt 3){return};$script:imageTimer.Stop();$bitmap=New-Object Drawing.Bitmap($form.Width,$form.Height);try{$form.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$form.Width,$form.Height)));$bitmap.Save($CaptureImage,[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()};$script:imageTimer.Dispose();$form.Close()})
        $script:imageTimer.Start()
    } elseif ($CaptureImage) {
        $bitmap = New-Object System.Drawing.Bitmap($form.Width,$form.Height)
        try { $form.DrawToBitmap($bitmap,(New-Object System.Drawing.Rectangle(0,0,$form.Width,$form.Height))); $bitmap.Save($CaptureImage,[System.Drawing.Imaging.ImageFormat]::Png) }
        finally { $bitmap.Dispose() }
    }
    if ($CaptureFrames) {
        [void][System.IO.Directory]::CreateDirectory($CaptureFrames)
        $script:captureIndex = 0
        $script:captureTimer = New-Object System.Windows.Forms.Timer
        $script:captureTimer.Interval = 200
        $script:captureTimer.Add_Tick({
            $bitmap = New-Object System.Drawing.Bitmap($form.Width,$form.Height)
            try {
                $form.DrawToBitmap($bitmap,(New-Object System.Drawing.Rectangle(0,0,$form.Width,$form.Height)))
                $bitmap.Save((Join-Path $CaptureFrames ('frame-{0:D4}.png' -f $script:captureIndex)),[System.Drawing.Imaging.ImageFormat]::Png)
            } finally { $bitmap.Dispose() }
            $script:captureIndex++
            if ($script:captureIndex -ge 60) { $script:captureTimer.Stop(); $script:captureTimer.Dispose(); $form.Close() }
        })
        $script:captureTimer.Start()
    }
})
$form.Add_FormClosed({ $timer.Stop(); $timer.Dispose();$script:metricsClient.CancelPendingRequests();$script:metricsClient.Dispose() })
[void]$form.ShowDialog()
$form.Dispose()
