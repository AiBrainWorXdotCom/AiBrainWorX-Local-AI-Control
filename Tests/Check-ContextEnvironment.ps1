$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'app\Context-Environment.ps1')
$keys = @('ACP_MODEL_CONTEXT_LIMIT','BILI_SESSIONS_DIR','ACP_AUTO_UPDATE','BILI_ADVISORY_CHECK','BILI_RELEASE_NOTES_CHECK','BILI_SQLITE_AUTO_DOWNLOAD')
$original = @{}
foreach ($key in $keys) { $original[$key] = [Environment]::GetEnvironmentVariable($key,'Process'); [Environment]::SetEnvironmentVariable($key,('before-'+$key),'Process') }
$prepared = [pscustomobject]@{HarnessBillionContext=$true;HarnessContextSessionDir='C:\test-only\sessions';Model=[pscustomobject]@{contextWindow=16384}}
try {
    $actual = Invoke-AwxHarnessContextEnvironment $prepared { foreach ($key in $keys) { [Environment]::GetEnvironmentVariable($key,'Process') } }
    $expected = @('16384','C:\test-only\sessions','0','0','0','0')
    for ($i=0; $i -lt $keys.Count; $i++) { if ($actual[$i] -cne $expected[$i]) { throw ('Incorrect child environment for '+$keys[$i]) } }
    foreach ($key in $keys) { if ([Environment]::GetEnvironmentVariable($key,'Process') -cne ('before-'+$key)) { throw ('Caller environment changed: '+$key) } }
    try { Invoke-AwxHarnessContextEnvironment $prepared { throw 'deliberate failure' }; throw 'Expected failure was not propagated.' } catch { if ($_.Exception.Message -ne 'deliberate failure') { throw } }
    foreach ($key in $keys) { if ([Environment]::GetEnvironmentVariable($key,'Process') -cne ('before-'+$key)) { throw ('Caller environment changed after failure: '+$key) } }
    $prepared.HarnessBillionContext=$false
    $unchanged=Invoke-AwxHarnessContextEnvironment $prepared { [Environment]::GetEnvironmentVariable('ACP_AUTO_UPDATE','Process') }
    if ($unchanged -cne 'before-ACP_AUTO_UPDATE') { throw 'An unenabled extension changed the child environment.' }
    Write-Output 'Context extension environment passed: selected context, pinned-update policy, isolation and restoration.'
} finally { foreach ($key in $keys) { [Environment]::SetEnvironmentVariable($key,$original[$key],'Process') } }
