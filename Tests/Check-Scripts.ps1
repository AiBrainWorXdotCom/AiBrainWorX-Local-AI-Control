$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$failures = @()
Get-ChildItem -LiteralPath $root -Filter '*.ps1' -Recurse -File | ForEach-Object {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$errors) | Out-Null
    if ($errors.Count) { $failures += $errors }
}
if ($failures.Count) { throw ($failures -join "`n") }
Write-Output 'PowerShell syntax checks passed.'
