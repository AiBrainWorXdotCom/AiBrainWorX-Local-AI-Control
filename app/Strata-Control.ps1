param([ValidateSet('Gui', 'Start', 'Stop', 'Status')][string]$Action = 'Gui', [string]$CaptureImage = '', [switch]$AsJson)
$ErrorActionPreference = 'Stop'
$ConfigPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'config.local.json'
. (Join-Path $PSScriptRoot 'Settings.ps1')
. (Join-Path $PSScriptRoot 'Control.ps1')
$settings = Read-AwxSettings $ConfigPath
$profileState = Invoke-AwxOperation $settings $ConfigPath 'state'
if ($profileState.active.model.backend -ne 'strata') { throw 'Start and stop this backend in Ollama or LM Studio. The launcher connects to its local API.' }
if (-not ($settings.StrataRoot -and $settings.StrataPython)) { throw 'Run Setup.cmd to configure the Strata engine before starting it.' }
$StrataRoot = $settings.StrataRoot
$Python = $settings.StrataPython
$Server = Join-Path $StrataRoot 'serve\server.py'
$Config = $profileState.active.model.configPath
$Port = 8081
$BaseUrl = "http://127.0.0.1:$Port"
$Stdout = Join-Path $settings.StateRoot 'logs\coder-stdout.log'
$Stderr = Join-Path $settings.StateRoot 'logs\coder-stderr.log'

$installed=Get-Content -LiteralPath $Config -Raw -Encoding UTF8 | ConvertFrom-Json
$ModelIds=@($installed.model_name)+@($installed.aliases)
. (Join-Path $PSScriptRoot 'Model-Lifecycle.ps1')
function Get-CoderStatus { (Get-CoderSnapshot).detail }
if($AsJson){
    [Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
    try {
        $message=''
        if($Action -eq 'Start'){$message=Start-Coder;Start-AwxService $settings $ConfigPath}
        elseif($Action -eq 'Stop'){$message=Stop-Coder}
        $snapshot=Get-CoderSnapshot
        $snapshot|Add-Member -NotePropertyName message -NotePropertyValue $message
        $snapshot|ConvertTo-Json -Compress
    } catch { [Console]::Error.WriteLine((@{error=$_.Exception.Message}|ConvertTo-Json -Compress));exit 1 }
    return
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
$form.Text = 'AiBrainWorX | Strata Model Control'
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
$title.Text = $profileState.active.model.modelId
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
