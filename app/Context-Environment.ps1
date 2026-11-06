function Invoke-AwxHarnessContextEnvironment($Prepared,[scriptblock]$Action) {
    if (-not $Prepared.HarnessBillionContext) { & $Action; return }
    # Advisory checks are disabled for this pinned build; check them manually.
    $values = [ordered]@{
        ACP_MODEL_CONTEXT_LIMIT = [string]$Prepared.Model.contextWindow
        BILI_SESSIONS_DIR = [string]$Prepared.HarnessContextSessionDir
        ACP_AUTO_UPDATE = '0'
        BILI_ADVISORY_CHECK = '0'
        BILI_RELEASE_NOTES_CHECK = '0'
        BILI_SQLITE_AUTO_DOWNLOAD = '0'
    }
    $previous = @{}
    foreach ($name in $values.Keys) { $previous[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
    try {
        foreach ($name in $values.Keys) { [Environment]::SetEnvironmentVariable($name,$values[$name],'Process') }
        & $Action
    } finally {
        foreach ($name in $values.Keys) { [Environment]::SetEnvironmentVariable($name,$previous[$name],'Process') }
    }
}
