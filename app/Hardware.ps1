function Get-LocalHardware {
    $cpu = 'CPU: see hardware check'
    $gpu = 'GPU: see hardware check'
    $ram = 'RAM: see hardware check'
    try {
        $cpu = ((Get-CimInstance Win32_Processor | Select-Object -First 1).Name -replace '\s+\d+-Core Processor','' -replace '\(R\)|\(TM\)','').Trim()
    } catch {}
    try {
        $memory = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
        $ram = '{0} GB RAM' -f [math]::Round($memory/1GB)
    } catch {}
    try {
        $smi = Join-Path $env:SystemRoot 'System32\nvidia-smi.exe'
        if (-not (Test-Path -LiteralPath $smi)) { $smi = (Get-Command nvidia-smi.exe -ErrorAction Stop).Source }
        $line = @(& $smi --query-gpu=name,memory.total --format=csv,noheader,nounits 2>$null)[0]
        if ($LASTEXITCODE -eq 0 -and $line -match '^(.*),\s*(\d+)\s*$') {
            $gpuName = ($Matches[1] -replace '^NVIDIA GeForce\s+','').Trim()
            $gpu = '{0} / {1} GB VRAM' -f $gpuName,[math]::Round(([double]$Matches[2])/1024)
        }
    } catch {
        try { $gpu = ((Get-CimInstance Win32_VideoController | Select-Object -First 1).Name) } catch {}
    }
    return [pscustomobject]@{CPU=$cpu;GPU=$gpu;RAM=$ram}
}
