param([string]$ConfigPath = '', [switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
if (-not $ConfigPath) { $ConfigPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'config.local.json' }
. (Join-Path $PSScriptRoot 'Settings.ps1')
. (Join-Path $PSScriptRoot 'Control.ps1')
$settings = Read-AwxSettings $ConfigPath
$entry = [string]$settings.CodexEntry
if (-not $entry -and $settings.CodexCommand) {
    # Compatibility with configurations produced before CodexEntry was stored.
    $modules = Split-Path (Split-Path $settings.CodexCommand -Parent) -Parent
    $entry = Join-Path $modules '@openai\codex\bin\codex.js'
}
if (-not $entry -or -not [IO.Path]::IsPathRooted($entry) -or $entry -match '[\r\n"\x00]' -or -not (Test-Path -LiteralPath $entry -PathType Leaf)) {
    throw 'The optional Codex CLI is not configured. Run Setup.cmd again before choosing it.'
}
if (-not (Test-Path -LiteralPath $settings.NodeExecutable -PathType Leaf) -or -not (Test-Path -LiteralPath $settings.WorkspaceRoot -PathType Container)) {
    throw 'The configured runtime or workspace is unavailable. Run Setup.cmd again.'
}
$prepared = Invoke-AwxOperation $settings $ConfigPath 'prepare'
$profileHome = $prepared.CodexHome
if (-not (Test-Path -LiteralPath (Join-Path $profileHome 'aibrainworx-local.config.toml') -PathType Leaf)) {
    throw 'The local coding profile is missing. Run Setup.cmd to prepare it.'
}
if ($CheckOnly) { Write-Output 'Local Codex launcher configuration is valid. No client was started.'; return }
# Invoke Node directly: arguments remain data instead of passing through a .cmd shell.
$previousHome = [Environment]::GetEnvironmentVariable('CODEX_HOME','Process')
try {
    [Environment]::SetEnvironmentVariable('CODEX_HOME',$profileHome,'Process')
    & $settings.NodeExecutable $entry --profile aibrainworx-local --cd $prepared.WorkspaceRoot
    if ($LASTEXITCODE -ne 0) { throw 'The coding client exited with an error. Check the message above.' }
} finally { [Environment]::SetEnvironmentVariable('CODEX_HOME',$previousHome,'Process') }
