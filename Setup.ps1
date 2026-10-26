param([switch]$Plan,[switch]$CheckPrerequisites)
$ErrorActionPreference = 'Stop'
$RepoRoot = $PSScriptRoot
$RuntimeRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'AiBrainWorX\LocalAI'
. (Join-Path $RepoRoot 'app\Setup-Prerequisites.ps1')

function Ask-Yes([string]$Question) { return (Read-Host "$Question [y/N]") -match '^(y|yes)$' }
function Write-Utf8([string]$Path,[string]$Text) { [IO.File]::WriteAllText($Path,$Text,(New-Object System.Text.UTF8Encoding($false))) }
function Refresh-ProcessPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User') + ';' + $env:Path
}
function Find-WorkingCommand([string]$Name) {
    foreach ($command in @(Get-Command $Name -CommandType Application -All -ErrorAction SilentlyContinue)) {
        try {
            $global:LASTEXITCODE=0
            $version=@(& $command.Source --version 2>$null)
            if ($LASTEXITCODE -eq 0 -and $version.Count -gt 0) { return $command.Source }
        } catch { continue }
    }
    return $null
}
function Require-Command([string]$Name,[string]$Package,[string]$Manual) {
    $command = Find-WorkingCommand $Name
    if ($command) { return $command }
    Write-Host "Missing or non-working $Name. Official installation: $Manual" -ForegroundColor Yellow
    if ((Get-Command winget.exe -ErrorAction SilentlyContinue) -and (Ask-Yes "Install $Package using Windows Package Manager?")) {
        & winget.exe install --exact --id $Package --source winget | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Installation of $Package did not finish." }
        Refresh-ProcessPath
        $command = Find-WorkingCommand $Name
        if ($command) { return $command }
    }
    throw "Install $Name from $Manual, close this window and rerun Setup.cmd. See docs/first-run.md."
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
Write-Host 'First time? See docs/first-run.md. Answer y to an installation offer, or n to install it yourself.'
if ($Plan) {
    Write-Host 'PLAN ONLY: check Python and Node; choose Strata, Ollama or LM Studio; reuse or install Strata when selected; optionally download a model; prepare Harness, a local Codex profile and optional Unreal tools.'
    Write-Host 'Tested Coder download: approximately 58.4 GB, plus prepared data. Other models differ.'
    return
}

if ($CheckPrerequisites) {
    $missing=@()
    if (Find-AwxPython) { Write-Host 'Python: OK (working 64-bit 3.10+).' } else { $missing+='Python'; Write-Host 'Python: MISSING or unsupported; Store shortcuts do not count.' }
    foreach ($name in @('node.exe','npm.cmd')) {
        if (Find-WorkingCommand $name) { Write-Host "${name}: OK" } else { $missing+=$name; Write-Host "${name}: MISSING or non-working" }
    }
    Write-Host 'Read-only check: no installation, model download, configuration write or server start.'
    if ($missing.Count) { Write-Host 'Run Setup.cmd to install missing tools, or follow docs/first-run.md.'; exit 2 }
    $global:LASTEXITCODE=0
    return
}

try {
Write-Host "`nStep 1 of 4: Check and install prerequisites" -ForegroundColor Cyan
$Python = Require-AwxPython
$Node = Require-Command 'node.exe' 'OpenJS.NodeJS.LTS' 'https://nodejs.org/'
$Npm = Require-Command 'npm.cmd' 'OpenJS.NodeJS.LTS' 'https://nodejs.org/'
[void][System.IO.Directory]::CreateDirectory($RuntimeRoot)

Write-Host "`nStep 2 of 4: Choose your model server" -ForegroundColor Cyan
Write-Host '1: Strata (installed GGUF models)'
Write-Host '2: Ollama local server'
Write-Host '3: LM Studio local server'
Write-Host '4: llama.cpp / llama-swap local compatible server'
$backendChoice=Read-Host 'Choose a local backend [1]'
$ModelBackend='strata';$ModelBaseUrl='http://127.0.0.1:8081/v1';$ModelId=''
$StrataRoot='';$StrataConfig='';$StrataPython=''
if($backendChoice -in @('2','3','4')) {
    $ModelBackend=@{'2'='ollama';'3'='lmstudio';'4'='compatible'}[$backendChoice]
    $defaultApi=@{ollama='http://127.0.0.1:11434/v1';lmstudio='http://127.0.0.1:1234/v1';compatible='http://127.0.0.1:8080/v1'}[$ModelBackend]
    $entered=Read-Host "Local API URL [$defaultApi]"
    $ModelBaseUrl=if($entered){$entered}else{$defaultApi}
    $ModelId=Read-Host 'Exact installed model identifier (you can change it in the app)'
    if(-not $ModelId){throw 'An installed model identifier is required. Start the server and check its model list.'}
    $model=[pscustomobject]@{model_name=$ModelId}
    Write-Host 'No Strata installation or model download is required. Start the chosen local server separately.'
} else {
    $Git=Require-Command 'git.exe' 'Git.Git' 'https://git-scm.com/download/win'
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
    throw 'This alpha expects a loopback Strata config on port 8081 without a key. Keep existing settings, or prepare a separate matching config with Strata setup.'
}
$StrataPython = Join-Path $StrataRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $StrataPython)) { throw 'The source-based Strata Python environment is missing.' }

}

Write-Host "`nStep 3 of 4: Prepare coding clients" -ForegroundColor Cyan
$packages = Join-Path $RuntimeRoot 'agent-packages'
$harnessInstalled = Test-Path -LiteralPath (Join-Path $packages 'node_modules\@deepseek-ai\dsh\lib\bin.js')
$codexInstalled = Test-Path -LiteralPath (Join-Path $packages 'node_modules\.bin\codex.cmd')
if (-not ($harnessInstalled -and $codexInstalled)) {
    if (-not (Ask-Yes 'Install the official DeepSeek Harness and Codex CLI packages into this app runtime?')) { throw 'Agent package installation was cancelled.' }
    Run-Checked $Npm @('install','--prefix',$packages,'@deepseek-ai/dsh@0.2.1-rc.2','@openai/codex@0.160.0')
}
$HarnessEntry = Join-Path $packages 'node_modules\@deepseek-ai\dsh\lib\bin.js'
$CodexCommand = Join-Path $packages 'node_modules\.bin\codex.cmd'
$CodexEntry = Join-Path $packages 'node_modules\@openai\codex\bin\codex.js'
Write-Host "`nStep 4 of 4: Choose your project and save local settings" -ForegroundColor Cyan
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
$settings = [ordered]@{NodeExecutable=$Node;HarnessEntry=$HarnessEntry;HarnessHome=(Join-Path $RuntimeRoot 'harness-home');PythonExecutable=$Python;StrataRoot=$StrataRoot;StrataConfig=$StrataConfig;StrataPython=$StrataPython;ModelBackend=$ModelBackend;ModelBaseUrl=$ModelBaseUrl;ModelId=$ModelId;WorkspaceRoot=$WorkspaceRoot;UnrealProjectName=$UnrealName;EnginePython=$EnginePython;StateRoot=$RuntimeRoot;ModelLabel=$model.model_name;CodexCommand=$CodexCommand;CodexEntry=$CodexEntry}
$configPath = Join-Path $RepoRoot 'config.local.json'
Save-Backup $configPath
Write-Utf8 $configPath ($settings | ConvertTo-Json)
# Generate isolated client homes using this checkout's current location.
# No global client profile or existing workspace instruction file is replaced.
Run-Checked $Python @((Join-Path $RepoRoot 'app/control_runtime.py'),'prepare','--config',$configPath)
Write-Host "`nSetup complete. Open Launch.cmd, start the model, then choose your coding workspace." -ForegroundColor Cyan
Write-Host 'Model files are reused. Local paths and logs stay in ignored configuration/runtime folders.'
Write-Host 'Made by AiBrainWorX'
$global:LASTEXITCODE=0
} catch {
    Write-Host "`nSetup did not finish: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'You can rerun Setup.cmd after fixing this step. Existing model downloads and settings were kept.'
    exit 1
}
