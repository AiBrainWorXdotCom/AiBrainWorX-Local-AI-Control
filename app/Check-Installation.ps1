$ErrorActionPreference='Stop'
try {
    . (Join-Path $PSScriptRoot 'Settings.ps1')
    $settings=Read-AwxSettings (Join-Path (Split-Path $PSScriptRoot -Parent) 'config.local.json')
    foreach($field in @('NodeExecutable','HarnessEntry','PythonExecutable')) {
        if(-not (Test-Path -LiteralPath $settings.$field -PathType Leaf)){throw 'Setup required'}
    }
    if(-not (Test-Path -LiteralPath $settings.WorkspaceRoot -PathType Container)){throw 'Setup required'}
    exit 0
} catch {
    Write-Output 'This portable launcher needs setup for this PC. Run Setup.cmd to select its installed tools and model.'
    exit 2
}
