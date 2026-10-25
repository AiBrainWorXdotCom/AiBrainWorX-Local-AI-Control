# Shared process controls and state presentation. No work runs merely by importing.
function Get-CoderProcess {
    $serverMatch='"'+$Server.Replace('/','\')+'"'
    $configMatch='"'+$Config.Replace('/','\')+'"'
    @(Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" | Where-Object {
        if (-not $_.CommandLine) { return $false }
        $command=$_.CommandLine.Replace('/','\')
        $command.IndexOf($serverMatch,[StringComparison]::OrdinalIgnoreCase) -ge 0 -and
        $command.IndexOf($configMatch,[StringComparison]::OrdinalIgnoreCase) -ge 0 -and
        $command -match ('--port\s+'+[regex]::Escape([string]$Port)+'(?:\s|$)')
    })
}

function Test-PortBusy {
    $client=New-Object Net.Sockets.TcpClient
    try {
        $pending=$client.BeginConnect('127.0.0.1',$Port,$null,$null)
        if(-not $pending.AsyncWaitHandle.WaitOne(200)){return $false}
        $client.EndConnect($pending);return $true
    } catch { return $false } finally { $client.Dispose() }
}

function Get-CoderSnapshot {
    $owned=@(Get-CoderProcess);$health=$null
    try{$health=Invoke-RestMethod "$BaseUrl/health" -TimeoutSec 2}catch{}
    $ready=$health -and $health.service -eq 'strata' -and $health.loaded -and $health.model -in $ModelIds
    $phase='stopped';$detail='Model is stopped. Click Start model to load it.'
    $canStart=$false;$canStop=$owned.Count -gt 0
    if($ready){$phase='running';$detail=if($canStop){'Model is running and ready. Stop model releases its memory.'}else{'Model is ready in another controller. Stop it in its owning app.'}}
    elseif($health -and $health.service -eq 'strata' -and $health.loaded){$phase='conflict';$detail='A different Strata model is running. Select its profile to stop it first.'}
    elseif($owned.Count){$phase='starting';$detail='Model process is running. Waiting for its API; the first load can take several minutes.'}
    elseif(Test-PortBusy){$phase='conflict';$detail='Port 8081 is occupied. No second model will be started.'}
    else{$canStart=$true}
    [pscustomobject]@{backend='strata';modelId=$profileState.active.model.modelId;state=$phase;ready=[bool]$ready;canStart=$canStart;canStop=$canStop;detail=$detail}
}

function Invoke-AwxTreeKill([int]$ProcessId) {
    # Capture native stderr rather than turning a harmless exiting-child message
    # into a PowerShell terminating error before the final state can be checked.
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=Join-Path $env:SystemRoot 'System32\taskkill.exe'
    $info.Arguments='/PID {0} /T /F' -f $ProcessId
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $p=New-Object Diagnostics.Process;$p.StartInfo=$info
    try{[void]$p.Start();$stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync();if(-not $p.WaitForExit(5000)){$p.Kill();throw 'The stop command timed out.'};return $p.ExitCode}finally{$p.Dispose()}
}

function Stop-AwxOwnedTree($Roots) {
    $snapshot=@(Get-CimInstance Win32_Process)
    $verifiedRoots=@($Roots | Where-Object {$root=$_;@($snapshot | Where-Object {$_.ProcessId -eq $root.ProcessId -and $_.CreationDate -eq $root.CreationDate}).Count})
    if(-not $verifiedRoots.Count){return}
    $owned=@{};foreach($root in $verifiedRoots){$owned[[int]$root.ProcessId]=$root}
    do {
        $added=$false
        foreach($p in $snapshot){if(-not $owned.ContainsKey([int]$p.ProcessId) -and $owned.ContainsKey([int]$p.ParentProcessId) -and $p.CreationDate -ge $owned[[int]$p.ParentProcessId].CreationDate){$owned[[int]$p.ProcessId]=$p;$added=$true}}
    } while($added)
    foreach($root in $verifiedRoots){
        $same=@(Get-CimInstance Win32_Process -Filter ('ProcessId = '+$root.ProcessId) | Where-Object {$_.CreationDate -eq $root.CreationDate})
        if($same.Count){[void](Invoke-AwxTreeKill ([int]$root.ProcessId))}
    }
    # Recheck the entire captured tree. An exited child is success, even if
    # taskkill reported it during the race. PID reuse never authorizes a kill.
    $remaining=@()
    for($attempt=0;$attempt -lt 8;$attempt++){
        $remaining=@(Get-CimInstance Win32_Process | Where-Object {$owned.ContainsKey([int]$_.ProcessId) -and $_.CreationDate -eq $owned[[int]$_.ProcessId].CreationDate})
        if(-not $remaining.Count){return}
        if($attempt -eq 0){foreach($p in $remaining){$fresh=@(Get-CimInstance Win32_Process -Filter ('ProcessId = '+$p.ProcessId) | Where-Object {$_.CreationDate -eq $p.CreationDate});if($fresh.Count){[void](Invoke-AwxTreeKill ([int]$p.ProcessId))}}}
        Start-Sleep -Milliseconds 200
    }
    throw ('Stop incomplete: {0} model process(es) are still running. Open Diagnostics before retrying.' -f $remaining.Count)
}

function Start-Coder {
    $lock=New-Object Threading.Mutex($false,'Local\StrataCoderManualStart8081');$held=$false
    try {
        $held=$lock.WaitOne(0);if(-not $held){throw 'Another model operation is in progress.'}
        if(@(Get-CoderProcess).Count){return 'Model is already starting or running.'}
        if(Test-PortBusy){throw 'Port 8081 is occupied. No second model was started.'}
        foreach($file in @($Python,$Server,$Config)){if(-not (Test-Path -LiteralPath $file -PathType Leaf)){throw "Missing installed component: $file"}}
        $arguments='-u "{0}" --engine strata --config "{1}" --port {2}' -f $Server,$Config,$Port
        $process=Start-Process -FilePath $Python -ArgumentList $arguments -WorkingDirectory $StrataRoot -WindowStyle Hidden -RedirectStandardOutput $Stdout -RedirectStandardError $Stderr -PassThru
        return 'Starting model. Loading can take several minutes; the status turns green when ready.'
    } finally {if($held){$lock.ReleaseMutex()};$lock.Dispose()}
}

function Stop-Coder {
    $lock=New-Object Threading.Mutex($false,'Local\StrataCoderManualStart8081');$held=$false
    try {
        $held=$lock.WaitOne(0);if(-not $held){throw 'Another model operation is in progress.'}
        $processes=@(Get-CoderProcess)
        if(-not $processes.Count){return 'Model is already stopped.'}
        Stop-AwxOwnedTree $processes
        return 'Model stopped. Its engine processes have exited and memory is released.'
    } finally {if($held){$lock.ReleaseMutex()};$lock.Dispose()}
}

function Get-AwxModelPresentation($Snapshot,[bool]$Managed=$true) {
    $phase=if($Snapshot.state){$Snapshot.state}elseif($Snapshot.ready){'running'}else{'unavailable'}
    $styles=@{
        checking=@('CHECKING MODEL','#303642','#D1D7E0');stopped=@('STOPPED','#343A46','#E3E8EF')
        starting=@('STARTING - PLEASE WAIT','#59441F','#FFE0A1');stopping=@('STOPPING - PLEASE WAIT','#59441F','#FFE0A1')
        running=@('RUNNING - READY','#163F32','#BEFFCA');conflict=@('MODEL CONFLICT','#542E32','#FFD1D6')
        unavailable=@('SERVER OFFLINE','#542E32','#FFD1D6');error=@('ACTION FAILED','#542E32','#FFD1D6')
    }
    if(-not $styles.ContainsKey($phase)){$phase='error'}
    $s=$styles[$phase]
    [pscustomobject]@{state=$phase;label=$s[0];background=$s[1];foreground=$s[2];startEnabled=($Managed -and [bool]$Snapshot.canStart);stopEnabled=($Managed -and [bool]$Snapshot.canStop);busy=($phase -in @('starting','stopping'));detail=$Snapshot.detail}
}
