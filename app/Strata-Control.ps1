param([ValidateSet('Gui', 'Start', 'Stop', 'Status')][string]$Action = 'Gui', [string]$CaptureImage = '')
$ErrorActionPreference = 'Stop'
$ConfigPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'config.local.json'
. (Join-Path $PSScriptRoot 'Settings.ps1')
$settings = Read-AwxSettings $ConfigPath
$StrataRoot = $settings.StrataRoot
$Python = $settings.StrataPython
$Server = Join-Path $StrataRoot 'serve\server.py'
$Config = $settings.StrataConfig
$Port = 8081
$BaseUrl = "http://127.0.0.1:$Port"
$Stdout = Join-Path $settings.StateRoot 'logs\coder-stdout.log'
$Stderr = Join-Path $settings.StateRoot 'logs\coder-stderr.log'

function Get-CoderProcess {
    @(Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" | Where-Object {
        $_.ExecutablePath -eq $Python -and
        $_.CommandLine -and $_.CommandLine.Contains($Server) -and $_.CommandLine.Contains($Config)
    })
}

function Test-PortBusy {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $pending = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        if (-not $pending.AsyncWaitHandle.WaitOne(200)) { return $false }
        $client.EndConnect($pending)
        return $true
    } catch { return $false } finally { $client.Dispose() }
}

function Get-CoderStatus {
    $processes = @(Get-CoderProcess)
    if ($processes.Count -eq 0) {
        if (Test-PortBusy) { return 'Port 8081 is occupied; Start is blocked.' }
        return 'Stopped - GPU is free of this Coder server.'
    }
    try {
        $health = Invoke-RestMethod "$BaseUrl/health" -TimeoutSec 1
        if ($health.service -eq 'strata' -and $health.loaded) { return 'Running - model ready on port 8081.' }
        return 'Running - model is loading or unloaded.'
    } catch { return 'Starting - waiting for the server on port 8081.' }
}

function Start-Coder {
    # Serialize starts from multiple panels or command-line invocations.
    $lock = New-Object System.Threading.Mutex($false, 'Local\StrataCoderManualStart8081')
    $held = $false
    try {
        $held = $lock.WaitOne(0)
        if (-not $held) { throw 'Another Start operation is already in progress.' }
        if (@(Get-CoderProcess).Count -gt 0) { return 'Coder is already starting or running.' }
        if (Test-PortBusy) { throw 'Port 8081 is in use. No server was started.' }
        foreach ($file in @($Python, $Server, $Config)) {
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing file: $file" }
        }
        $arguments = '"{0}" --engine strata --config "{1}" --port {2}' -f $Server, $Config, $Port
        $process = Start-Process -FilePath $Python -ArgumentList $arguments -WorkingDirectory $StrataRoot -WindowStyle Hidden -RedirectStandardOutput $Stdout -RedirectStandardError $Stderr -PassThru
        return "Start requested (PID $($process.Id)). Model loading can take several minutes."
    } finally {
        if ($held) { $lock.ReleaseMutex() }
        $lock.Dispose()
    }
}

function Stop-Coder {
    $processes = @(Get-CoderProcess)
    if ($processes.Count -eq 0) { return 'Coder is already stopped.' }
    foreach ($process in $processes) {
        # Match again immediately before stopping. Never kill by executable name or port alone.
        $verified = @(Get-CoderProcess | Where-Object { $_.ProcessId -eq $process.ProcessId -and $_.CreationDate -eq $process.CreationDate })
        if ($verified.Count -eq 0) { continue }
        $result = & "$env:SystemRoot\System32\taskkill.exe" /PID $process.ProcessId /T /F 2>&1
        if ($LASTEXITCODE -ne 0 -and @(Get-CoderProcess).Count -gt 0) { throw ($result -join "`n") }
    }
    return 'Stopped Coder and its child engine processes. Active requests were cancelled.'
}

switch ($Action) {
    'Start' { Start-Coder; return }
    'Stop' { Stop-Coder; return }
    'Status' { Get-CoderStatus; return }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object System.Windows.Forms.Form
$form.Text = 'AiBrainWorX | Qwen Coder Control'
$form.ClientSize = New-Object System.Drawing.Size(680, 350)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.AutoScaleMode = 'None'
$form.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0C111B')
$form.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#F0F5FC')
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

$brand = New-Object System.Windows.Forms.Label
$brand.Text = 'AiBrainWorX / LOCAL AI'
$brand.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#6DE7D6')
$brand.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$brand.SetBounds(26, 22, 620, 28)
$form.Controls.Add($brand)
$title = New-Object System.Windows.Forms.Label
$title.Text = $settings.ModelLabel
$title.Font = New-Object System.Drawing.Font('Segoe UI', 22, [System.Drawing.FontStyle]::Bold)
$title.SetBounds(24, 66, 640, 48)
$form.Controls.Add($title)
$hardware = New-Object System.Windows.Forms.Label
. (Join-Path $PSScriptRoot 'Hardware.ps1')
$detected = Get-LocalHardware
$hardware.Text = $detected.GPU + '     ' + $detected.CPU + '     ' + $detected.RAM
$hardware.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#A6B4CB')
$hardware.SetBounds(27, 120, 626, 26)
$form.Controls.Add($hardware)
$status = New-Object System.Windows.Forms.Label
$status.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#141D2B')
$status.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#6DE7D6')
$status.Padding = New-Object System.Windows.Forms.Padding(12, 10, 8, 4)
$status.SetBounds(26, 164, 628, 46)
$form.Controls.Add($status)

$start = New-Object System.Windows.Forms.Button
$start.Text = 'Start Coder'
$start.SetBounds(26, 230, 196, 40)
$form.Controls.Add($start)
$stop = New-Object System.Windows.Forms.Button
$stop.Text = 'Stop Coder'
$stop.SetBounds(242, 230, 196, 40)
$form.Controls.Add($stop)
$logs = New-Object System.Windows.Forms.Button
$logs.Text = 'Open Logs'
$logs.SetBounds(458, 230, 196, 40)
$form.Controls.Add($logs)
foreach ($controlButton in @($start,$stop,$logs)) {
    $controlButton.FlatStyle = 'Flat'
    $controlButton.FlatAppearance.BorderSize = 0
    $controlButton.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#243349')
    $controlButton.ForeColor = $form.ForeColor
    $controlButton.Cursor = [System.Windows.Forms.Cursors]::Hand
    $controlButton.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
}
$start.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#6DE7D6')
$start.ForeColor = $form.BackColor
$note = New-Object System.Windows.Forms.Label
$note.Text = 'Manual start. Closing this panel leaves the model running.'
$note.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#A6B4CB')
$note.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$note.SetBounds(27, 286, 626, 24)
$form.Controls.Add($note)
$credit = New-Object System.Windows.Forms.Label
$credit.Text = 'Made by AiBrainWorX'
$credit.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#6DE7D6')
$credit.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$credit.SetBounds(26, 321, 300, 24)
$form.Controls.Add($credit)

function Update-Panel {
    try {
        $status.Text = Get-CoderStatus
        $running = @(Get-CoderProcess).Count -gt 0
        $start.Enabled = -not $running -and -not (Test-PortBusy)
        $stop.Enabled = $running
    } catch { $status.Text = $_.Exception.Message }
}
$start.Add_Click({
    try { $status.Text = Start-Coder } catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Strata Coder') | Out-Null }
    Update-Panel
})
$stop.Add_Click({
    try { $status.Text = Stop-Coder } catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Strata Coder') | Out-Null }
    Update-Panel
})
$logs.Add_Click({ Start-Process -FilePath "$env:SystemRoot\explorer.exe" -ArgumentList ('"{0}"' -f $PSScriptRoot) })
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000
$timer.Add_Tick({ Update-Panel })
$form.Add_Shown({
    Update-Panel
    $timer.Start()
    if ($CaptureImage) {
        $bitmap = New-Object System.Drawing.Bitmap($form.Width,$form.Height)
        try { $form.DrawToBitmap($bitmap,(New-Object System.Drawing.Rectangle(0,0,$form.Width,$form.Height))); $bitmap.Save($CaptureImage,[System.Drawing.Imaging.ImageFormat]::Png) }
        finally { $bitmap.Dispose() }
        $form.Close()
    }
})
$form.Add_FormClosed({ $timer.Stop(); $timer.Dispose() })
[void]$form.ShowDialog()
$form.Dispose()
