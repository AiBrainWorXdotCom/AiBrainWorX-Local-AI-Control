param([switch]$Plan)
$ErrorActionPreference = 'Stop'
$RepoRoot = $PSScriptRoot
$RuntimeRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'AiBrainWorX\LocalAI'

function Ask-Yes([string]$Question) { return (Read-Host "$Question [y/N]") -match '^(y|yes)$' }
function Write-Utf8([string]$Path,[string]$Text) { [IO.File]::WriteAllText($Path,$Text,(New-Object System.Text.UTF8Encoding($false))) }
function Refresh-ProcessPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
}
function Require-Command([string]$Name,[string]$Package,[string]$Manual) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    Write-Host "Missing $Name. Official installation: $Manual" -ForegroundColor Yellow
    if ((Get-Command winget.exe -ErrorAction SilentlyContinue) -and (Ask-Yes "Install $Package using Windows Package Manager?")) {
        & winget.exe install --exact --id $Package --source winget
        if ($LASTEXITCODE -ne 0) { throw "Installation of $Package did not finish." }
        Refresh-ProcessPath
        $command = Get-Command $Name -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }
    throw "Install $Name from its official source, then run Setup.cmd again."
}
function Run-Checked([string]$Command,[string[]]$Arguments) {
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'An installation command failed. See the output above; existing files have been kept.' }
}
function Save-Backup([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        $backupRoot = Join-Path $RuntimeRoot 'backups'
        [void][System.IO.Directory]::CreateDirectory($backupRoot)
        Copy-Item -LiteralPath $Path -Destination (Join-Path $backupRoot (([IO.Path]::GetFileName($Path)) + '.' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.bak'))
    }
}

Write-Host "`nAiBrainWorX / Local AI setup" -ForegroundColor Cyan
Write-Host 'This installs or reuses local tools. It does not start the model or change your normal Codex profile.'
Write-Host 'Upstream licenses: Strata MIT; Harness MIT; Codex CLI Apache-2.0.'
Write-Host 'Qwen weights have separate terms. Read MODEL-LICENSES.md before choosing a download.'
if ($Plan) {
    Write-Host 'PLAN ONLY: check Git, Python and Node; reuse or install Strata; optionally download a model; prepare Harness, a local Codex profile and optional Unreal tools.'
    Write-Host 'Tested Coder download: approximately 58.4 GB, plus prepared data. Other models differ.'
    return
}

$Git = Require-Command 'git.exe' 'Git.Git' 'https://git-scm.com/download/win'
$Python = Require-Command 'python.exe' 'Python.Python.3.12' 'https://www.python.org/downloads/windows/'
$Node = Require-Command 'node.exe' 'OpenJS.NodeJS.LTS' 'https://nodejs.org/'
$Npm = Require-Command 'npm.cmd' 'OpenJS.NodeJS.LTS' 'https://nodejs.org/'
Run-Checked $Python @('-c','import sys; assert sys.version_info >= (3,10), "Python 3.10 or newer is required"')
[void][System.IO.Directory]::CreateDirectory($RuntimeRoot)

$knownStrata = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'LocalAI\Strata'
$defaultStrata = if (Test-Path -LiteralPath (Join-Path $knownStrata 'setup.py')) { $knownStrata } else { Join-Path $RuntimeRoot 'Strata' }
$entered = Read-Host "Strata folder [Enter for $defaultStrata]"
$StrataRoot = if ($entered) { [IO.Path]::GetFullPath($entered.Trim('"')) } else { $defaultStrata }
if (-not (Test-Path -LiteralPath (Join-Path $StrataRoot 'setup.py'))) {
    if (-not (Ask-Yes 'Download the official Strata v0.2.4 source and its setup dependencies?')) { throw 'Strata setup was cancelled.' }
    if ((Test-Path -LiteralPath $StrataRoot) -and @(Get-ChildItem -LiteralPath $StrataRoot -Force).Count) { throw 'Choose an empty folder or an existing Strata installation.' }
    Run-Checked $Git @('clone','--depth','1','--branch','v0.2.4','https://github.com/Niko1221/Strata.git',$StrataRoot)
}

Push-Location -LiteralPath $StrataRoot
try {
    & '.\START-HERE.bat' --check
    if ($LASTEXITCODE -ne 0) { throw 'Strata hardware check failed. Resolve its reported requirements first.' }
    $models = @(Get-ChildItem -LiteralPath $StrataRoot -Filter 'strata-*.json' -File | Where-Object {
        try { $candidate = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json; $candidate.exe -and $candidate.args -and $candidate.model_name } catch { $false }
    })
    if ($models.Count -eq 0 -or (Ask-Yes 'Install another model instead of reusing the installed model files?')) {
        Write-Host '1: Our tested Qwen 3.8 Coder IQ1_M preset (58.4 GB download, additional prepared data; tested on 12 GB VRAM / 32 GB RAM).'
        Write-Host '2: Use Strata hardware-guided setup to choose another supported model. Download size and terms vary.'
        Write-Host 'Model terms: https://huggingface.co/Qwen/Qwen3.8-Flash-Next/blob/main/LICENSE'
        Write-Host 'Quantized model card: https://huggingface.co/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF'
        $choice = Read-Host 'Choose 1 or 2 [Enter for guided setup]'
        if ((Read-Host 'After reviewing applicable model terms and disk needs, type DOWNLOAD to continue') -cne 'DOWNLOAD') { throw 'No model download was started.' }
        if ($choice -eq '1') {
            & '.\START-HERE.bat' --yes --setup --family coder --model IQ1_M --context 16384 --vision no --host 127.0.0.1 --port 8081 --no-start
        } else {
            & '.\START-HERE.bat' --setup --context 16384 --vision no --host 127.0.0.1 --port 8081 --no-start
        }
        if ($LASTEXITCODE -ne 0) { throw 'Strata setup is incomplete. Its resumable downloads are retained.' }
        $models = @(Get-ChildItem -LiteralPath $StrataRoot -Filter 'strata-*.json' -File | Where-Object {
            try { $candidate = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json; $candidate.exe -and $candidate.args -and $candidate.model_name } catch { $false }
        })
    }
} finally { Pop-Location }
if (-not $models.Count) { throw 'No usable model configuration was found.' }
for ($i=0; $i -lt $models.Count; $i++) { Write-Host ('{0}: {1}' -f ($i+1),$models[$i].BaseName) }
$selectedIndex = 0
if ($models.Count -gt 1) {
    $answer = Read-Host 'Select an installed model number [1]'
    if ($answer) { $number = 0; if (-not [int]::TryParse($answer,[ref]$number) -or $number -lt 1 -or $number -gt $models.Count) { throw 'Invalid model number.' }; $selectedIndex=$number-1 }
}
$StrataConfig = $models[$selectedIndex].FullName
$model = Get-Content -LiteralPath $StrataConfig -Raw | ConvertFrom-Json
if (($model.host -and $model.host -ne '127.0.0.1') -or ($model.port -and $model.port -ne 8081) -or $model.api_key) {
    throw 'Version 1 expects a loopback Strata config on port 8081 without a key. Keep existing settings, or prepare a separate matching config with Strata setup.'
}
$StrataPython = Join-Path $StrataRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $StrataPython)) { throw 'The source-based Strata Python environment is missing.' }

$packages = Join-Path $RuntimeRoot 'agent-packages'
$harnessInstalled = Test-Path -LiteralPath (Join-Path $packages 'node_modules\@deepseek-ai\dsh\lib\bin.js')
$codexInstalled = Test-Path -LiteralPath (Join-Path $packages 'node_modules\.bin\codex.cmd')
if (-not ($harnessInstalled -and $codexInstalled)) {
    if (-not (Ask-Yes 'Install the official DeepSeek Harness and Codex CLI packages into this app runtime?')) { throw 'Agent package installation was cancelled.' }
    Run-Checked $Npm @('install','--prefix',$packages,'@deepseek-ai/dsh@0.2.1-rc.2','@openai/codex@0.160.0')
}
$HarnessEntry = Join-Path $packages 'node_modules\@deepseek-ai\dsh\lib\bin.js'
$CodexCommand = Join-Path $packages 'node_modules\.bin\codex.cmd'
$workspaceDefault = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'LocalAI-Workspace'
$entered = Read-Host "Working project folder [Enter for $workspaceDefault]"
$WorkspaceRoot = if ($entered) { [IO.Path]::GetFullPath($entered.Trim('"')) } else { $workspaceDefault }
[void][System.IO.Directory]::CreateDirectory($WorkspaceRoot)
$projectFiles = @(Get-ChildItem -LiteralPath $WorkspaceRoot -Filter '*.uproject' -File)
$UnrealName = if ($projectFiles.Count -eq 1) { $projectFiles[0].BaseName } else { '' }
$EnginePython = ''
if ($UnrealName) {
    $EnginePython = Read-Host 'Unreal engine Python plugin folder (the folder containing remote_execution.py; Enter skips live editor tools)'
    if ($EnginePython) { $EnginePython = [IO.Path]::GetFullPath($EnginePython.Trim('"')) }
    if ($EnginePython -and -not (Test-Path -LiteralPath (Join-Path $EnginePython 'remote_execution.py'))) { throw 'That folder does not contain remote_execution.py.' }
}
$HarnessHome = Join-Path $RuntimeRoot 'harness-home'
$oldHome = [Environment]::GetEnvironmentVariable('DSH_HOME','Process')
try {
    [Environment]::SetEnvironmentVariable('DSH_HOME',$HarnessHome,'Process')
    & $Node $HarnessEntry web --help | Out-Null
} finally { [Environment]::SetEnvironmentVariable('DSH_HOME',$oldHome,'Process') }
$profileRoot = Join-Path $HarnessHome 'profiles\web'
[void][System.IO.Directory]::CreateDirectory($profileRoot)
$profilePackage = @{name='aibrainworx-local-profile';private=$true;dependencies=@{};dsh=@{profile=@{bundles=@('@deepseek-ai/dsh-base','@deepseek-ai/dsh-web-app')}}} | ConvertTo-Json -Depth 8
Write-Utf8 (Join-Path $profileRoot 'package.json') $profilePackage
$patchPath = Join-Path $profileRoot 'cordis.patch.yml'
Save-Backup $patchPath
$aliases = @($model.aliases)
$ModelId = if ($aliases.Count -and $aliases[0]) { [string]$aliases[0] } else { [string]$model.model_name }
$profile = Get-Content -LiteralPath (Join-Path $RepoRoot 'examples\harness-profile.example.yml') -Raw
$profile = $profile.Replace('qwen3.8-flash-next-coder',$ModelId)
if (-not ($UnrealName -and $EnginePython)) { $profile = ($profile -split '(?m)^- id: mcp-unreal-local')[0] }
else {
    $bridge = (Join-Path $RepoRoot 'bridge\unreal_mcp.py').Replace('\','/')
    $profile = $profile.Replace('C:/AI/UnrealAssistant/unreal_mcp.py',$bridge).Replace('C:/Projects/MyUnrealGame',$WorkspaceRoot.Replace('\','/')).Replace('MyUnrealGame',$UnrealName).Replace('C:/Program Files/Epic Games/UE_5.8/Engine/Plugins/Experimental/PythonScriptPlugin/Content/Python',$EnginePython.Replace('\','/'))
}
$profile = $profile.Replace('apiKeyEnv: STRATA_LOCAL_TOKEN','apiKeyEnv: AIBRAINWORX_API_KEY')
Write-Utf8 $patchPath $profile

$settings = [ordered]@{NodeExecutable=$Node;HarnessEntry=$HarnessEntry;HarnessHome=$HarnessHome;PythonExecutable=$Python;StrataRoot=$StrataRoot;StrataConfig=$StrataConfig;StrataPython=$StrataPython;WorkspaceRoot=$WorkspaceRoot;UnrealProjectName=$UnrealName;EnginePython=$EnginePython;StateRoot=$RuntimeRoot;ModelLabel=$model.model_name;CodexCommand=$CodexCommand}
$configPath = Join-Path $RepoRoot 'config.local.json'
Save-Backup $configPath
Write-Utf8 $configPath ($settings | ConvertTo-Json)
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex' }
[void][System.IO.Directory]::CreateDirectory($codexHome)
$codexProfile = Join-Path $codexHome 'aibrainworx-local.config.toml'
Save-Backup $codexProfile
$template = Get-Content -LiteralPath (Join-Path $RepoRoot 'examples\dronekilla-local.config.toml') -Raw
$template = $template.Replace('qwen3.8-flash-next-coder',$ModelId).Replace('C:/AI/UnrealAssistant/model-catalog.json',(Join-Path $RuntimeRoot 'model-catalog.json').Replace('\','/'))
$catalog = Get-Content -LiteralPath (Join-Path $RepoRoot 'examples\model-catalog.json') -Raw | ConvertFrom-Json
$catalog.models[0].slug = $ModelId
Write-Utf8 (Join-Path $RuntimeRoot 'model-catalog.json') ($catalog | ConvertTo-Json -Depth 20)
if (-not ($UnrealName -and $EnginePython)) { $template = ($template -split '(?m)^\[mcp_servers.unreal_local\]')[0] }
else { $template = $template.Replace('C:/AI/UnrealAssistant/unreal_mcp.py',(Join-Path $RepoRoot 'bridge\unreal_mcp.py').Replace('\','/')).Replace('C:/Projects/MyUnrealGame',$WorkspaceRoot.Replace('\','/')).Replace('MyUnrealGame',$UnrealName).Replace('C:/Program Files/Epic Games/UE_5.8/Engine/Plugins/Experimental/PythonScriptPlugin/Content/Python',$EnginePython.Replace('\','/')) }
Write-Utf8 $codexProfile $template
Write-Host "`nSetup complete. Double-click Launch.cmd, then Start Qwen and Start Harness." -ForegroundColor Cyan
Write-Host 'Model files are reused. Local paths and logs stay in ignored configuration/runtime folders.'
Write-Host 'Made by AiBrainWorX'
