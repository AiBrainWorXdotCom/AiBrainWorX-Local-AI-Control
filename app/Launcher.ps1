param([ValidateSet('Gui','Start','Stop','Status','Open','UnrealStatus')][string]$Action = 'Gui', [string]$CaptureImage = '', [string]$CaptureFrames = '')
$ErrorActionPreference = 'Stop'
$ConfigPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'config.local.json'
. (Join-Path $PSScriptRoot 'Settings.ps1')
$settings = Read-AwxSettings $ConfigPath
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
    if (Test-HarnessPort) { return 'Running - local Harness is ready on port 3080.' }
    return 'Starting - loading Harness and its Unreal tools.'
}

function Get-QwenStatus {
    try {
        $health = Invoke-RestMethod 'http://127.0.0.1:8081/health' -TimeoutSec 1
        if ($health.service -eq 'strata' -and $health.loaded) { return 'Qwen: ready through Strata on port 8081.' }
        return 'Qwen: loading.'
    } catch { return 'Qwen: stopped or still starting.' }
}

function Start-Harness {
    $mutex = New-Object System.Threading.Mutex($false,'Local\DeepSeekHarnessManual3080')
    $held = $false
    try {
        $held = $mutex.WaitOne(0)
        if (-not $held) { throw 'Another Harness start is in progress.' }
        if (@(Get-HarnessProcess).Count -gt 0) { return 'Harness is already starting or running.' }
        if (Test-HarnessPort) { throw 'Port 3080 is already occupied. No second server was started.' }
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
            if ($settings.HarnessHome) { [Environment]::SetEnvironmentVariable('DSH_HOME',$settings.HarnessHome,'Process') }
            $process = Start-Process -FilePath $Node -ArgumentList $arguments -WorkingDirectory $Project -WindowStyle Hidden -RedirectStandardOutput $Stdout -RedirectStandardError $Stderr -PassThru
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

function Get-UnrealStatus {
    if (-not ($settings.UnrealProjectName -and $settings.EnginePython)) { return 'Unreal tools are optional. Run Setup.cmd to connect an Unreal project.' }
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $Python
    $start.Arguments = '"{0}" --status' -f $Bridge
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.EnvironmentVariables['UE_PROJECT_ROOT'] = $Project
    $start.EnvironmentVariables['UE_PROJECT_NAME'] = $settings.UnrealProjectName
    $start.EnvironmentVariables['UE_ENGINE_PYTHON'] = $settings.EnginePython
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
$form.ClientSize = New-Object System.Drawing.Size(1000,704)
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

function New-ControlButton($parent,$text,$x,$y,$width,$handler,$accent=$null) {
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
}

$brand = New-Text $form 'AiBrainWorX' 32 23 500 35 19 $true $palette.Cyan
$edition = New-Text $form 'LOCAL AI / DEVELOPER CONTROL' 32 64 650 22 9 $true $palette.Muted
$localTag = New-Text $form 'LOCALHOST  /  MANUAL START' 705 31 265 28 9 $true $palette.Purple
$title = New-Text $form 'Big model. Everyday hardware.' 30 103 940 49 28 $true
$subtitle = New-Text $form ($settings.ModelLabel + ' + Strata + Codex + DeepSeek Harness') 32 160 940 28 11 $false $palette.Muted

$gpuCard = New-Card 32 210 300 80 $palette.Cyan
$gpuLabel = New-Text $gpuCard 'GRAPHICS' 16 12 265 18 8 $true $palette.Muted
$gpuValue = New-Text $gpuCard $hardware.GPU 16 36 274 31 13 $true
$cpuCard = New-Card 350 210 300 80 $palette.Purple
$cpuLabel = New-Text $cpuCard 'PROCESSOR' 16 12 265 18 8 $true $palette.Muted
$cpuValue = New-Text $cpuCard $hardware.CPU 16 36 274 31 13 $true
$ramCard = New-Card 668 210 300 80 $palette.Cyan
$ramLabel = New-Text $ramCard 'SYSTEM MEMORY' 16 12 270 18 8 $true $palette.Muted
$ramValue = New-Text $ramCard $hardware.RAM 16 36 274 31 13 $true

$modelCard = New-Card 32 314 456 205 $palette.Cyan
$modelEyebrow = New-Text $modelCard '01 / MODEL ENGINE' 20 16 415 22 9 $true $palette.Cyan
$modelTitle = New-Text $modelCard 'Local model / Strata' 20 48 415 35 18 $true
$modelEndpoint = New-Text $modelCard 'LOCAL INFERENCE  /  127.0.0.1:8081' 21 91 415 20 9 $false $palette.Muted
$modelStatus = New-Text $modelCard 'Checking model...' 21 118 415 34 10 $false $palette.Muted
New-ControlButton $modelCard 'Start Qwen' 20 156 200 { try { $feedback.Text = & $QwenControl -Action Start } catch { $feedback.Text = $_.Exception.Message }; Update-Panel } $palette.Cyan
New-ControlButton $modelCard 'Stop Qwen' 236 156 200 { try { $feedback.Text = & $QwenControl -Action Stop } catch { $feedback.Text = $_.Exception.Message }; Update-Panel }

$harnessCard = New-Card 512 314 456 205 $palette.Purple
$harnessEyebrow = New-Text $harnessCard '02 / AGENT WORKSPACE' 20 16 415 22 9 $true $palette.Purple
$harnessTitle = New-Text $harnessCard 'DeepSeek Harness' 20 48 415 35 18 $true
$harnessEndpoint = New-Text $harnessCard 'BROWSER CHAT  /  127.0.0.1:3080' 21 91 415 20 9 $false $palette.Muted
$status = New-Text $harnessCard 'Checking Harness...' 21 118 415 34 10 $false $palette.Muted
New-ControlButton $harnessCard 'Start' 20 156 120 { try { $feedback.Text = Start-Harness } catch { $feedback.Text = $_.Exception.Message }; Update-Panel }
New-ControlButton $harnessCard 'Stop' 152 156 120 { try { $feedback.Text = Stop-Harness } catch { $feedback.Text = $_.Exception.Message }; Update-Panel }
New-ControlButton $harnessCard 'Open chat' 284 156 152 { try { $feedback.Text = Open-Harness } catch { $feedback.Text = $_.Exception.Message } } $palette.Purple

$unrealCard = New-Card 32 543 936 83 $palette.Purple
$unrealTitle = New-Text $unrealCard 'UNREAL ENGINE / OPTIONAL EDITOR TOOLS' 20 13 710 23 10 $true
$unrealStatus = New-Text $unrealCard 'Five inspection tools configured. Check the live editor connection.' 21 42 708 30 9 $false $palette.Muted
New-ControlButton $unrealCard 'Check Unreal' 760 24 156 { try { $unrealStatus.Text = Get-UnrealStatus } catch { $unrealStatus.Text = $_.Exception.Message } }
$feedback = New-Text $form '' 32 635 936 24 9 $false $palette.Purple
$footer = New-Text $form 'Made by AiBrainWorX' 32 675 340 23 10 $true $palette.Cyan
$note = New-Text $form 'Closing this panel keeps your services running.' 330 676 390 22 8 $false $palette.Muted

$logs = New-Object System.Windows.Forms.LinkLabel
$logs.Text = 'Logs + files'
$logs.LinkColor = $palette.Muted
$logs.ActiveLinkColor = $palette.Cyan
$logs.VisitedLinkColor = $palette.Muted
$logs.SetBounds(860,675,110,22)
$logs.Add_LinkClicked({ Start-Process -FilePath "$env:SystemRoot\explorer.exe" -ArgumentList ('"{0}"' -f $PSScriptRoot) })
$form.Controls.Add($logs)

function Update-Panel {
    try {
        $status.Text = Get-HarnessStatus
        $modelStatus.Text = Get-QwenStatus
        $status.ForeColor = if ($status.Text.StartsWith('Running')) { $palette.Cyan } else { $palette.Muted }
        $modelStatus.ForeColor = if ($modelStatus.Text.Contains('ready')) { $palette.Cyan } else { $palette.Muted }
    }
    catch { $feedback.Text = $_.Exception.Message }
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 5000
$timer.Add_Tick({ Update-Panel })
$form.Add_Shown({
    [void][AiBrainWorXWindow]::ShowWindow($form.Handle,9)
    Update-Panel
    $timer.Start()
    if ($CaptureImage) {
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
    } elseif ($CaptureImage) { $form.Close() }
})
$form.Add_FormClosed({ $timer.Stop(); $timer.Dispose() })
[void]$form.ShowDialog()
$form.Dispose()
