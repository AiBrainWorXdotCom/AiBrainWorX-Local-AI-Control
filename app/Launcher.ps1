param([ValidateSet('Gui','Start','Stop','Status','Open','UnrealStatus')][string]$Action = 'Gui', [string]$CaptureImage = '', [string]$CaptureFrames = '', [ValidateSet('Harness','Codex')][string]$Workspace = 'Harness', [string]$CaptureSettingsImage = '', [ValidateSet('Overview','Chat','Models','Memory','Training','Updates')][string]$CapturePage='Overview')
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
    try { $result=Invoke-AwxOperation $settings $ConfigPath 'model-status'; return $result.detail }
    catch { return 'Selected model connection is unavailable.' }
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
    $ready=Invoke-AwxOperation $settings $ConfigPath 'model-status'
    if(-not $ready.ready){throw $ready.detail}
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

. (Join-Path $PSScriptRoot 'Desktop.ps1')
