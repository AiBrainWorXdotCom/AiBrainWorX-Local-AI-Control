# Windows PowerShell 5.1 compatible. Loading this file performs no installation.
# HELP: DEPENDENCIES - importing helpers/probing a Store alias must never start a
# runtime download. Require-AwxPython is the separate, explicitly consented gate.
function Write-AwxPrerequisiteOutput([string]$Text,[ConsoleColor]$ForegroundColor) {
    $options=@{Object=$Text}
    if ($PSBoundParameters.ContainsKey('ForegroundColor')) { $options.ForegroundColor=$ForegroundColor }
    if (Get-Command Write-SetupConsole -ErrorAction SilentlyContinue) { Write-SetupConsole @options }
    else { Write-Host @options }
}
function ConvertTo-AwxNativeArgument([string]$Value) {
    # CommandLineToArgvW quoting, including embedded quotes and trailing slashes.
    return '"' + [regex]::Replace([regex]::Replace($Value,'(\\*)"','$1$1\"'),'(\\+)$','$1$1') + '"'
}

function Invoke-AwxDependencyProbe([string]$Executable,[string[]]$Arguments,[int]$TimeoutMilliseconds=10000) {
    $process = New-Object Diagnostics.Process
    try {
        $info = New-Object Diagnostics.ProcessStartInfo
        $info.FileName = $Executable
        $info.Arguments = (@($Arguments | ForEach-Object { ConvertTo-AwxNativeArgument $_ }) -join ' ')
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        # Probing a Python install-manager/launcher alias must never install a
        # runtime. Keep this restriction local to the child process environment.
        $info.EnvironmentVariables['PYTHON_MANAGER_AUTOMATIC_INSTALL']='false'
        $info.EnvironmentVariables.Remove('PYLAUNCHER_ALLOW_INSTALL')
        $info.EnvironmentVariables.Remove('PYLAUNCHER_ALWAYS_INSTALL')
        $process.StartInfo = $info
        [void]$process.Start()
        $output = $process.StandardOutput.ReadToEndAsync()
        $errors = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutMilliseconds)) {
            # Only this probe process is ours. No name/port-based termination.
            $process.Kill()
            [void]$process.WaitForExit(1000)
            return $null
        }
        if ($process.ExitCode -ne 0) { return $null }
        if (-not $output.Wait(1000) -or -not $errors.Wait(1000)) { return $null }
        return $output.GetAwaiter().GetResult().Trim()
    } catch { return $null } finally { $process.Dispose() }
}

function Get-AwxPythonCandidates {
    $candidates = New-Object 'Collections.Generic.List[object]'
    foreach ($name in @('python.exe','python3.exe')) {
        foreach ($command in @(Get-Command $name -CommandType Application -All -ErrorAction SilentlyContinue)) {
            $candidates.Add([pscustomobject]@{Executable=$command.Source;Arguments=@()})
        }
    }
    $launchers = @((Get-Command py.exe -CommandType Application -All -ErrorAction SilentlyContinue | ForEach-Object {$_.Source}))
    $launchers += @( (Join-Path $env:SystemRoot 'py.exe'), (Join-Path $env:LOCALAPPDATA 'Programs\Python\Launcher\py.exe') )
    foreach ($launcher in @($launchers | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $launcher -PathType Leaf) {
            foreach ($selector in @('-3.12','-3')) {
                $candidates.Add([pscustomobject]@{Executable=$launcher;Arguments=@($selector)})
            }
        }
    }
    # python.org installers register the interpreter even when PATH was unchecked
    # or the current process predates the installation. Include this user's keys.
    foreach ($registry in @('HKCU:\Software\Python\PythonCore','HKLM:\Software\Python\PythonCore','HKLM:\Software\WOW6432Node\Python\PythonCore')) {
        foreach ($key in @(Get-ChildItem -LiteralPath $registry -ErrorAction SilentlyContinue)) {
            $install = Get-Item -LiteralPath ($key.PSPath+'\InstallPath') -ErrorAction SilentlyContinue
            if ($install) {
                $path = $install.GetValue('ExecutablePath')
                if (-not $path -and $install.GetValue('')) { $path=Join-Path $install.GetValue('') 'python.exe' }
                if ($path) { $candidates.Add([pscustomobject]@{Executable=[string]$path;Arguments=@()}) }
            }
        }
    }
    foreach ($parent in @((Join-Path $env:LOCALAPPDATA 'Programs\Python'),$env:ProgramFiles)) {
        foreach ($folder in @(Get-ChildItem -LiteralPath $parent -Directory -Filter 'Python3*' -ErrorAction SilentlyContinue)) {
            $candidates.Add([pscustomobject]@{Executable=(Join-Path $folder.FullName 'python.exe');Arguments=@()})
        }
    }
    return $candidates.ToArray()
}

function Select-AwxPython([object[]]$Candidates,[int]$TimeoutMilliseconds=10000) {
    $seen = @{}
    $code = "import sys,json,struct,sqlite3,venv; print('ABX_PYTHON='+json.dumps({'executable':sys.executable,'version':list(sys.version_info[:3]),'bits':struct.calcsize('P')*8}))"
    foreach ($candidate in $Candidates) {
        $key = $candidate.Executable+'|'+($candidate.Arguments -join '|')
        if ($seen.ContainsKey($key) -or -not (Test-Path -LiteralPath $candidate.Executable -PathType Leaf)) { continue }
        $seen[$key]=$true
        $text = Invoke-AwxDependencyProbe $candidate.Executable (@($candidate.Arguments)+@('-I','-c',$code)) $TimeoutMilliseconds
        if (-not $text -or -not $text.StartsWith('ABX_PYTHON=')) { continue }
        try {
            $result = $text.Substring(11) | ConvertFrom-Json
            if ($result.bits -ne 64 -or $result.version.Count -lt 2 -or $result.version[0] -ne 3 -or $result.version[1] -lt 10) { continue }
            if (-not [IO.Path]::IsPathRooted($result.executable) -or -not (Test-Path -LiteralPath $result.executable -PathType Leaf)) { continue }
            return [IO.Path]::GetFullPath($result.executable)
        } catch { continue }
    }
    return $null
}

function Find-AwxPython { return Select-AwxPython @(Get-AwxPythonCandidates) }

function Require-AwxPython {
    $python = Find-AwxPython
    if ($python) { Write-AwxPrerequisiteOutput 'Python: working 64-bit Python 3.10+ found.' -ForegroundColor Green; return $python }
    if ($script:AwxSetupIsolated) { throw 'Isolated setup needs an existing working 64-bit Python 3.10+. No global Python installation was attempted.' }
    Write-AwxPrerequisiteOutput 'A working 64-bit Python 3.10+ is required. A Microsoft Store shortcut alone is not Python.' -ForegroundColor Yellow
    Write-AwxPrerequisiteOutput 'Setup can install Python 3.12 for this Windows user, without changing the optional shared py.exe launcher.'
    Write-AwxPrerequisiteOutput 'No Microsoft account is required.'
    if ((Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue) -and (Ask-Yes 'Install Python 3.12 using Windows Package Manager?')) {
        # An existing all-user Python Launcher can make a per-user silent install
        # request elevation and roll back with MSI 1625. The launcher is optional:
        # we save/use the interpreter directly and leave shared py.exe untouched.
        # --custom appends supported options, retaining winget's signed installer,
        # hash validation and per-user installation defaults.
        $installOutput=@()
        $oldPreference=$ErrorActionPreference
        try {
            $ErrorActionPreference='Continue'
            & winget.exe install --exact --id Python.Python.3.12 --source winget --architecture x64 --scope user --custom 'Include_launcher=0 InstallLauncherAllUsers=0' 2>&1 | Tee-Object -Variable installOutput | ForEach-Object { Write-AwxPrerequisiteOutput $_ }
            $installExit=$LASTEXITCODE
        } finally { $ErrorActionPreference=$oldPreference }
        if ($installExit -ne 0) {
            if (($installOutput -join "`n") -match '\b1625\b|0x80070659') {
                throw 'Windows blocked Python installation (1625). Setup left Windows security policies unchanged. See docs/first-run.md: installer 1625, or ask the PC administrator for an approved Python installation.'
            }
            throw 'Python installation did not finish. See docs/first-run.md for the manual installation steps, then rerun Setup.cmd.'
        }
        Refresh-ProcessPath
        $python = Find-AwxPython
        if ($python) { Write-AwxPrerequisiteOutput 'Python: installation verified.' -ForegroundColor Green; return $python }
    }
    throw 'Install 64-bit Python from https://www.python.org/downloads/windows/ (include pip and venv). Close this window and rerun Setup.cmd. See docs/first-run.md. Existing files were kept.'
}
