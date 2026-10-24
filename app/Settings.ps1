function Read-AwxSettings([string]$ConfigPath) {
    if (-not $ConfigPath) { $ConfigPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'config.local.json' }
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw 'Run Setup.cmd first to configure your installation.' }
    $settings = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    foreach ($field in @('NodeExecutable','HarnessEntry','PythonExecutable','WorkspaceRoot','StateRoot')) {
        if (-not $settings.$field) { throw "Missing setup setting: $field. Run Setup.cmd again." }
    }
    foreach ($field in @('NodeExecutable','HarnessEntry','PythonExecutable','WorkspaceRoot','StateRoot')) {
        $value = [string]$settings.$field
        if (-not [System.IO.Path]::IsPathRooted($value) -or $value -match '[\r\n"\x00]') { throw "Invalid local path in setting: $field" }
    }
    [void][System.IO.Directory]::CreateDirectory((Join-Path $settings.StateRoot 'logs'))
    return $settings
}
