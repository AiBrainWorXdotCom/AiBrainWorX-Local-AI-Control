param(
    [ValidateSet('Interactive','Status')][string]$Action = 'Interactive',
    [string]$ConfigPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'config.local.json')
)
$ErrorActionPreference = 'Stop'
$ConfigPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ConfigPath)
. (Join-Path $PSScriptRoot 'Settings.ps1')
. (Join-Path $PSScriptRoot 'Control.ps1')
$settings = Read-AwxSettings $ConfigPath
$state = Invoke-AwxOperation $settings $ConfigPath 'state'
$identity = [string]$state.activeId
if ($identity -notmatch '^[A-Za-z0-9-]{1,64}$') { throw 'The selected profile identifier is invalid.' }
$harnessHome = Join-Path (Join-Path (Join-Path $settings.StateRoot 'managed-clients') $identity) 'harness'
$target = Join-Path $harnessHome 'profiles\web'
$manifest = Join-Path $target 'package.json'
$port = if ($settings.HarnessPort) { [int]$settings.HarnessPort } else { 3080 }
if ($port -lt 1 -or $port -gt 65535) { throw 'Invalid Harness port.' }

function Read-ContextStatus {
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { return 'Not installed in this profile.' }
    try { $data = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw 'The Harness profile manifest is unreadable; no files were changed.' }
    if ($null -eq $data -or $data -is [array]) { throw 'The Harness profile manifest is invalid; no files were changed.' }
    $dependency = if ($data.dependencies) { $data.dependencies.'billion-context' } else { $null }
    $bundles = if ($data.dsh -and $data.dsh.profile) { @($data.dsh.profile.bundles) } else { @() }
    $registered = $bundles -contains 'billion-context'
    $packagePresent = Test-Path -LiteralPath (Join-Path $target 'node_modules\billion-context\package.json') -PathType Leaf
    if ($registered -and -not $packagePresent) { return 'Bundle registered but package files are missing. Repair is needed.' }
    if ($registered -and $dependency) { return 'Registered in this profile. Start Harness and verify compression before relying on it.' }
    if ($registered) { return 'Bundle registered but dependency missing. Repair is needed.' }
    if ($dependency) { return 'Disabled in this profile; downloaded package and saved session data remain.' }
    return 'Not installed in this profile.'
}

function Write-ContextManifest($data) {
    $tmp = $manifest + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    # Windows PowerShell 5.1 cannot reliably marshal a null backup argument to
    # File.Replace. Keep the replacement atomic by using a unique backup path.
    $replaceBackup = $manifest + '.' + [guid]::NewGuid().ToString('N') + '.replace-backup'
    $replaced = $false
    try {
        [IO.File]::WriteAllText($tmp,($data | ConvertTo-Json -Depth 50),(New-Object Text.UTF8Encoding($false)))
        [IO.File]::Replace($tmp,$manifest,$replaceBackup)
        $replaced = $true
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        # If replacement failed, retain any backup created for recovery.
        if ($replaced -and (Test-Path -LiteralPath $replaceBackup)) { Remove-Item -LiteralPath $replaceBackup -Force -ErrorAction SilentlyContinue }
    }
}

if ($Action -eq 'Status') { Read-ContextStatus; return }
Write-Host 'AiBrainWorX / Experimental long-context extension' -ForegroundColor Cyan
Write-Host ('Selected profile: ' + $state.active.name)
Write-Host (Read-ContextStatus)
Write-Host ''
Write-Host 'Billion-Context is third-party code, not a sandbox. It can access your account files and conversations.'
Write-Host 'It stores session data separately. Launcher disables automatic updates and security advisories for its pinned release.'
Write-Host 'Check security advisories manually. Other plugin network activity is still possible. Review its license.'
Write-Host 'Compression does not expand the model context or eliminate answer-length limits.'
Write-Host 'The plugin may not intercept every Harness provider. Stop Harness before changing it.'
Write-Host 'Project: https://github.com/ranxianglei/billion-context'
Write-Host ''
Write-Host '[1] Install or enable for this profile  [2] Disable for this profile  [Q] Cancel'
$choice = Read-Host 'Choose an option'
if ($choice -notin @('1','2')) { return }
if ($choice -eq '1') {
    Write-Host 'This may download the pinned npm package and its dependencies. No global installation is used.'
    if ((Read-Host 'Type INSTALL to continue') -cne 'INSTALL') { return }
} else {
    Write-Host 'Disabling removes the bundle registration only. Package files and session data are kept.'
    if ((Read-Host 'Type DISABLE to continue') -cne 'DISABLE') { return }
}

$mutex = New-Object Threading.Mutex($false,('Local\DeepSeekHarnessManual'+$port))
$held = $false
try {
    $held = $mutex.WaitOne(0)
    if (-not $held) { throw 'Another Harness start is in progress. Try again later.' }
    $listening = @([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners() | Where-Object { $_.Port -eq $port }).Count -gt 0
    $running = @(Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" | Where-Object {
        $_.ExecutablePath -eq $settings.NodeExecutable -and $_.CommandLine -and
        $_.CommandLine.Contains($settings.HarnessEntry) -and $_.CommandLine -match ('(?:^|\s)--port\s+'+[regex]::Escape([string]$port)+'(?:\s|$)')
    }).Count -gt 0
    if ($listening -or $running) { throw 'Stop Harness and wait for it to close before changing this extension.' }
    $current = Invoke-AwxOperation $settings $ConfigPath 'state'
    if ($current.activeId -ne $identity) { throw 'The selected profile changed. Reopen this manager.' }
    $data = $null
    $installedFile = Join-Path $target 'node_modules\billion-context\package.json'
    if (Test-Path -LiteralPath $manifest -PathType Leaf) {
        $data = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $data -or $data -is [array] -or -not $data.dsh -or -not $data.dsh.profile -or $data.dsh.profile.bundles -isnot [array]) {
            throw 'Harness bundle configuration is invalid. The original manifest was kept.'
        }
        if ($choice -eq '1' -and $data.dependencies.'billion-context' -and $data.dependencies.'billion-context' -cne '0.1.212') {
            throw 'A different Billion-Context version already belongs to this profile. Manage it in Harness to avoid replacing it.'
        }
        if ($choice -eq '1' -and @($data.dsh.profile.bundles) -ccontains 'billion-context' -and (Test-Path -LiteralPath $installedFile -PathType Leaf)) {
            throw 'The bundle is already registered. Verify that it is routing requests before relying on it.'
        }
    }
    $canReenable = $choice -eq '1' -and $data -and $data.dependencies.'billion-context' -ceq '0.1.212' -and (Test-Path -LiteralPath $installedFile -PathType Leaf)
    if ($choice -eq '1' -and -not $canReenable) {
        if (-not (Get-Command pnpm.cmd -ErrorAction SilentlyContinue)) { throw 'Install pnpm or rerun launcher setup first.' }
        foreach ($file in @($settings.NodeExecutable, $settings.HarnessEntry)) {
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw 'Harness or Node is missing. Run launcher setup first.' }
        }
    }
    if (Test-Path -LiteralPath $manifest -PathType Leaf) {
        # Keep a recoverable copy of both metadata files before invoking DSH's package manager.
        $backup = Join-Path (Join-Path $target '.aibrainworx-backups') ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($backup)
        Copy-Item -LiteralPath $manifest -Destination (Join-Path $backup 'package.json')
        $lock = Join-Path $target 'pnpm-lock.yaml'
        if (Test-Path -LiteralPath $lock -PathType Leaf) { Copy-Item -LiteralPath $lock -Destination (Join-Path $backup 'pnpm-lock.yaml') }
    }
    if ($canReenable) {
        $data.dsh.profile.bundles = @($data.dsh.profile.bundles) + @('billion-context')
        Write-ContextManifest $data
        Write-Host 'Bundle re-enabled. This does not verify proxy routing or compression.' -ForegroundColor Yellow
    } elseif ($choice -eq '1') {
        $previous = [Environment]::GetEnvironmentVariable('DSH_HOME','Process')
        try {
            [Environment]::SetEnvironmentVariable('DSH_HOME',$harnessHome,'Process')
            & $settings.NodeExecutable $settings.HarnessEntry plugin --profile web add 'billion-context@0.1.212' --ignore-scripts
            if ($LASTEXITCODE -ne 0) { throw 'Installation failed. The manifest backup and existing files were kept; inspect the output above.' }
        } finally { [Environment]::SetEnvironmentVariable('DSH_HOME',$previous,'Process') }
        Write-Host 'Installation completed. This does not verify proxy routing or compression.' -ForegroundColor Yellow
    } else {
        if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw 'No Harness profile manifest was found.' }
        $data.dsh.profile.bundles = @($data.dsh.profile.bundles | Where-Object { $_ -cne 'billion-context' })
        Write-ContextManifest $data
        Write-Host 'Disabled in this profile. Restart Harness to use its regular compaction.' -ForegroundColor Green
    }
    Write-Host (Read-ContextStatus)
} catch {
    Write-Host ('Could not complete the action: ' + $_.Exception.Message) -ForegroundColor Red
} finally {
    if ($held) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
    [void](Read-Host 'Press Enter to close')
}
