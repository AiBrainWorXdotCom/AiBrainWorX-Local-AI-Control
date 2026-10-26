# Windows PowerShell 5.1 compatible. Loading this file performs no installation.
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
    if ($python) { Write-Host 'Python: working 64-bit Python 3.10+ found.' -ForegroundColor Green; return $python }
    Write-Host 'A working 64-bit Python 3.10+ is required. A Microsoft Store shortcut alone is not Python.' -ForegroundColor Yellow
    Write-Host 'Setup can install Python 3.12 for this Windows user. No Microsoft account is required.'
    if ((Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue) -and (Ask-Yes 'Install Python 3.12 using Windows Package Manager?')) {
        & winget.exe install --exact --id Python.Python.3.12 --source winget --architecture x64 --scope user | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'Python installation did not finish. See docs/first-run.md for the manual installation steps, then rerun Setup.cmd.' }
        Refresh-ProcessPath
        $python = Find-AwxPython
        if ($python) { Write-Host 'Python: installation verified.' -ForegroundColor Green; return $python }
    }
    throw 'Install 64-bit Python from https://www.python.org/downloads/windows/ (include pip and venv). Close this window and rerun Setup.cmd. See docs/first-run.md. Existing files were kept.'
}
