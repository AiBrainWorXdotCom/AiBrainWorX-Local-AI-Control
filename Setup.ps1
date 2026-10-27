<#
.SYNOPSIS
Install or reuse local model and coding tools after explicit download consent.
.DESCRIPTION
HELP: DEPENDENCIES - existing 64-bit Python 3.10+, Node/npm and Git are checked
before use. Missing global prerequisites are never installed by isolated runs.
HELP: CONSENT - the source/package questions and exact DOWNLOAD confirmation
remain required. Read-only Plan/CheckPrerequisites never install or save files.
.PARAMETER RuntimeRoot
Optional absolute private runtime directory. When supplied, Strata must be inside
this directory; the normal Documents Strata installation is not auto-selected.
Supplying RuntimeRoot enables isolation and disables global prerequisite installs.
.PARAMETER WorkspaceRoot
Optional absolute project directory. Supply this and RuntimeRoot in a separate
source checkout for isolated acceptance; the checkout still owns config.local.json.
.PARAMETER PublicOutput
Mask private roots, absolute child-output paths and project names in the console.
Private answers are hidden during entry. Saved configuration remains real/private.
.PARAMETER GatewayPort
Settings-service loopback port, 1-65535. Default 8082. Choose a separate port for
an isolated test so launching it cannot reuse the production service port.
.PARAMETER HarnessPort
Harness loopback port, 1-65535. Default 3080. Must differ from GatewayPort.
.EXAMPLE
.\Setup.ps1 -Plan -PublicOutput
.EXAMPLE
.\Setup.ps1 -RuntimeRoot C:\InstallTest\runtime -WorkspaceRoot C:\InstallTest\workspace -GatewayPort 18082 -HarnessPort 13080 -PublicOutput
#>
[CmdletBinding()]
param([switch]$Plan,[switch]$CheckPrerequisites,[string]$RuntimeRoot,[string]$WorkspaceRoot,[switch]$PublicOutput,[int]$GatewayPort=8082,[int]$HarnessPort=3080)
$ErrorActionPreference = 'Stop'
$RepoRoot = $PSScriptRoot
$script:AwxSetupIsolated = $PSBoundParameters.ContainsKey('RuntimeRoot')
$script:SetupRedactions = @{}
$script:SetupPython = $null

function Add-SetupPrivateValue([string]$Value,[string]$Label) {
    if ($Value) { $script:SetupRedactions[$Value]=$Label }
}
function Add-SetupWorkspacePrivacy([string]$Path) {
    Add-SetupPrivateValue $Path '<workspace>'
    $folderName=[IO.Path]::GetFileName($Path.TrimEnd('\','/'))
    # Generic test-folder names are also ordinary setup instructions. Full paths
    # still redact; an actual .uproject name is registered separately below.
    if ($folderName -notin @('workspace','source','runtime','logs')) { Add-SetupPrivateValue $folderName '<project>' }
}
function Assert-SetupPorts([int]$Gateway,[int]$Harness) {
    if ($Gateway -lt 1 -or $Gateway -gt 65535 -or $Harness -lt 1 -or $Harness -gt 65535) { throw 'GatewayPort and HarnessPort must each be between 1 and 65535.' }
    if ($Gateway -eq $Harness) { throw 'GatewayPort and HarnessPort must be different.' }
}
function Protect-SetupText([string]$Text) {
    if (-not $PublicOutput) { return $Text }
    foreach ($value in @($script:SetupRedactions.Keys | Sort-Object Length -Descending)) {
        $pattern=(@([regex]::Split($value,'[\\/]') | ForEach-Object {[regex]::Escape($_)}) -join '[\\/]')
        if ($value -notmatch '[\\/]') { $pattern='(?<!\w)'+$pattern+'(?!\w)' }
        $label=$script:SetupRedactions[$value]
        $Text=[regex]::Replace($Text,$pattern,[System.Text.RegularExpressions.MatchEvaluator]{param($match) $label},[Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    $Text=[regex]::Replace($Text,'(["''])(?:[A-Za-z]:[\\/]|\\\\)[^\r\n"'']+\1','<path>')
    $Text=[regex]::Replace($Text,'(?i)(?<![\w:])[A-Z]:[\\/][^\s"<>|]+','<path>')
    $Text=[regex]::Replace($Text,'\\\\[^\s"<>|]+','<path>')
    return $Text
}
function Write-SetupConsole([string]$Object,[ConsoleColor]$ForegroundColor,[switch]$NoNewline) {
    $options=@{Object=(Protect-SetupText $Object);NoNewline=$NoNewline}
    if ($PSBoundParameters.ContainsKey('ForegroundColor')) { $options.ForegroundColor=$ForegroundColor }
    Write-Host @options
}
function Read-SetupValue([string]$Prompt) {
    $safePrompt=Protect-SetupText $Prompt
    if (-not $PublicOutput) { return Read-Host $safePrompt }
    # HELP: PRIVACY - Read-Host's normal echo bypasses output filters. Hide typed
    # values in capture mode, including paths entered for Strata or a project.
    $secret=Read-Host $safePrompt -AsSecureString
    $pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer);$secret.Dispose() }
}
function Test-SetupWithin([string]$Path,[string]$Parent) {
    return $Path.Equals($Parent,[StringComparison]::OrdinalIgnoreCase) -or $Path.StartsWith($Parent.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)
}
function Resolve-SetupDirectory([string]$Value,[string]$Name) {
    if (-not $Value -or $Value -notmatch '^(?:[A-Za-z]:[\\/]|\\\\[^\\/]+[\\/][^\\/]+)') { throw "$Name must be an absolute Windows directory path." }
    $resolved=[IO.Path]::GetFullPath($Value.Trim('"')).TrimEnd('\','/')
    if ($resolved.TrimEnd('\') -eq [IO.Path]::GetPathRoot($resolved).TrimEnd('\') -or $resolved -eq [Environment]::GetFolderPath('UserProfile')) { throw "$Name must be a dedicated subfolder, not a drive root or the user home." }
    if (Test-Path -LiteralPath $resolved -PathType Leaf) { throw "$Name points to a file; choose a directory." }
    return $resolved
}
try {
Assert-SetupPorts $GatewayPort $HarnessPort
Add-SetupPrivateValue $RepoRoot '<source>'
Add-SetupPrivateValue ([Environment]::GetFolderPath('UserProfile')) '<home>'
if ($PSBoundParameters.ContainsKey('RuntimeRoot')) { $RuntimeRoot=Resolve-SetupDirectory $RuntimeRoot 'RuntimeRoot' }
else { $RuntimeRoot=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'AiBrainWorX\LocalAI' }
if ($PSBoundParameters.ContainsKey('WorkspaceRoot')) { $WorkspaceRoot=Resolve-SetupDirectory $WorkspaceRoot 'WorkspaceRoot' }
if ($script:AwxSetupIsolated) {
    if ((Test-SetupWithin $RuntimeRoot $RepoRoot) -or (Test-SetupWithin $RepoRoot $RuntimeRoot)) { throw 'An isolated runtime must be separate from the source checkout.' }
    if ($WorkspaceRoot -and ((Test-SetupWithin $WorkspaceRoot $RuntimeRoot) -or (Test-SetupWithin $RuntimeRoot $WorkspaceRoot))) { throw 'RuntimeRoot and WorkspaceRoot must be separate directories.' }
    if ($WorkspaceRoot -and ((Test-SetupWithin $WorkspaceRoot $RepoRoot) -or (Test-SetupWithin $RepoRoot $WorkspaceRoot))) { throw 'An isolated workspace must be separate from the source checkout.' }
}
Add-SetupPrivateValue $RuntimeRoot '<runtime>'
if ($WorkspaceRoot) { Add-SetupWorkspacePrivacy $WorkspaceRoot }
} catch {
    Write-SetupConsole "Setup options were rejected: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
. (Join-Path $RepoRoot 'app\Setup-Prerequisites.ps1')

function Ask-Yes([string]$Question) { return (Read-SetupValue "$Question [y/N]") -match '^(y|yes)$' }
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
    Write-SetupConsole "Missing or non-working $Name. Official installation: $Manual" -ForegroundColor Yellow
    if ($script:AwxSetupIsolated) { throw "Isolated setup needs existing $Name. No global prerequisite installation was attempted." }
    if ((Get-Command winget.exe -ErrorAction SilentlyContinue) -and (Ask-Yes "Install $Package using Windows Package Manager?")) {
        $oldPreference=$ErrorActionPreference
        try {
            # Windows PowerShell represents native stderr as ErrorRecords. An
            # ordinary progress/warning line must not abort a successful install.
            $ErrorActionPreference='Continue'
            & winget.exe install --exact --id $Package --source winget 2>&1 | ForEach-Object { Write-SetupConsole $_ }
            $installExit=$LASTEXITCODE
        } finally { $ErrorActionPreference=$oldPreference }
        if ($installExit -ne 0) { throw "Installation of $Package did not finish." }
        Refresh-ProcessPath
        $command = Find-WorkingCommand $Name
        if ($command) { return $command }
    }
    throw "Install $Name from $Manual, close this window and rerun Setup.cmd. See docs/first-run.md."
}
function Run-Checked([string]$Command,[string[]]$Arguments) {
    if ($PublicOutput -and $Command -match '\.(cmd|bat)$') {
        # PowerShell owns native batch-file quoting. Pipe both child streams
        # through the same privacy filter, including npm's native progress.
        $oldPreference=$ErrorActionPreference
        try {
            $ErrorActionPreference='Continue'
            & $Command @Arguments 2>&1 | ForEach-Object { Write-SetupConsole $_ }
            $commandExit=$LASTEXITCODE
        } finally { $ErrorActionPreference=$oldPreference }
        $global:LASTEXITCODE=$commandExit
    }
    elseif ($PublicOutput -and $script:SetupPython) {
        $oldRedactions=$env:AWX_SETUP_REDACTIONS_JSON
        try {
            $env:AWX_SETUP_REDACTIONS_JSON=$script:SetupRedactions | ConvertTo-Json -Compress
            & $script:SetupPython -u (Join-Path $RepoRoot 'app/setup_progress.py') --public-output -- $Command @Arguments
        } finally { [Environment]::SetEnvironmentVariable('AWX_SETUP_REDACTIONS_JSON',$oldRedactions,'Process') }
    } else { & $Command @Arguments }
    if ($LASTEXITCODE -ne 0) { throw 'An installation command failed. See the output above; existing files have been kept.' }
}
function Invoke-StrataSetup([string[]]$Arguments) {
    $oldRedactions=$env:AWX_SETUP_REDACTIONS_JSON
    try {
        $env:AWX_SETUP_REDACTIONS_JSON=$script:SetupRedactions | ConvertTo-Json -Compress
        $display=@();if ($PublicOutput) { $display+='--public-output' }
        & $StrataPython -u (Join-Path $RepoRoot 'app/setup_progress.py') @display --script (Join-Path $StrataRoot 'setup.py') -- @Arguments
        if ($LASTEXITCODE -ne 0) { throw 'Strata setup is incomplete. Its resumable downloads are retained.' }
    } finally { [Environment]::SetEnvironmentVariable('AWX_SETUP_REDACTIONS_JSON',$oldRedactions,'Process') }
}
function Save-Backup([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        $backupRoot = Join-Path $RuntimeRoot 'backups'
        [void][System.IO.Directory]::CreateDirectory($backupRoot)
        Copy-Item -LiteralPath $Path -Destination (Join-Path $backupRoot (([IO.Path]::GetFileName($Path)) + '.' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.bak'))
    }
}

Write-SetupConsole "`nAiBrainWorX / Local AI setup" -ForegroundColor Cyan
Write-SetupConsole 'This installs or reuses local tools. It does not start the model or change your normal Codex profile.'
Write-SetupConsole 'Upstream licenses: Strata MIT; Harness MIT; Codex CLI Apache-2.0.'
Write-SetupConsole 'Qwen weights have separate terms. Read MODEL-LICENSES.md before choosing a download.'
Write-SetupConsole 'First time? See docs/first-run.md. Answer y to an installation offer, or n to install it yourself.'
if ($PublicOutput) { Write-SetupConsole 'Public console mode: private paths and typed answers are hidden. Configuration and runtime files remain private.' }
if ($script:AwxSetupIsolated) { Write-SetupConsole 'Isolated paths: existing prerequisite tools may be reused; missing global tools will not be installed. Use a separate source checkout for its local configuration.' }
Write-SetupConsole "Configured service ports: settings $GatewayPort; Harness $HarnessPort. Setup does not start either service."
if ($script:AwxSetupIsolated -and (-not $PSBoundParameters.ContainsKey('GatewayPort') -or -not $PSBoundParameters.ContainsKey('HarnessPort'))) { Write-SetupConsole 'For a separate test launch, supply unused -GatewayPort and -HarnessPort values to avoid sharing the normal service ports.' -ForegroundColor Yellow }
if ($Plan) {
    Write-SetupConsole 'PLAN ONLY: check Python and Node; choose Strata, Ollama or LM Studio; reuse or install Strata when selected; optionally download a model; prepare Harness, a local Codex profile and optional Unreal tools.'
    Write-SetupConsole 'Tested Coder download: approximately 58.4 GB, plus prepared data. Other models differ.'
    return
}

if ($CheckPrerequisites) {
    $missing=@()
    if (Find-AwxPython) { Write-SetupConsole 'Python: OK (working 64-bit 3.10+).' } else { $missing+='Python'; Write-SetupConsole 'Python: MISSING or unsupported; Store shortcuts do not count.' }
    foreach ($name in @('node.exe','npm.cmd')) {
        if (Find-WorkingCommand $name) { Write-SetupConsole "${name}: OK" } else { $missing+=$name; Write-SetupConsole "${name}: MISSING or non-working" }
    }
    Write-SetupConsole 'Read-only check: no installation, model download, configuration write or server start.'
    if ($missing.Count) { Write-SetupConsole 'Run Setup.cmd to install missing tools, or follow docs/first-run.md.'; exit 2 }
    $global:LASTEXITCODE=0
    return
}

try {
Write-SetupConsole "`nStep 1 of 4: Check and install prerequisites" -ForegroundColor Cyan
$Python = Require-AwxPython
$script:SetupPython=$Python
$Node = Require-Command 'node.exe' 'OpenJS.NodeJS.LTS' 'https://nodejs.org/'
$Npm = Require-Command 'npm.cmd' 'OpenJS.NodeJS.LTS' 'https://nodejs.org/'
[void][System.IO.Directory]::CreateDirectory($RuntimeRoot)

Write-SetupConsole "`nStep 2 of 4: Choose your model server" -ForegroundColor Cyan
Write-SetupConsole '1: Strata (installed GGUF models)'
Write-SetupConsole '2: Ollama local server'
Write-SetupConsole '3: LM Studio local server'
Write-SetupConsole '4: llama.cpp / llama-swap local compatible server'
$backendChoice=Read-SetupValue 'Choose a local backend [1]'
$ModelBackend='strata';$ModelBaseUrl='http://127.0.0.1:8081/v1';$ModelId=''
$StrataRoot='';$StrataConfig='';$StrataPython=''
if($backendChoice -in @('2','3','4')) {
    $ModelBackend=@{'2'='ollama';'3'='lmstudio';'4'='compatible'}[$backendChoice]
    $defaultApi=@{ollama='http://127.0.0.1:11434/v1';lmstudio='http://127.0.0.1:1234/v1';compatible='http://127.0.0.1:8080/v1'}[$ModelBackend]
    $entered=Read-SetupValue "Local API URL [$defaultApi]"
    $ModelBaseUrl=if($entered){$entered}else{$defaultApi}
    $ModelId=Read-SetupValue 'Exact installed model identifier (you can change it in the app)'
    if(-not $ModelId){throw 'An installed model identifier is required. Start the server and check its model list.'}
    $model=[pscustomobject]@{model_name=$ModelId}
    Write-SetupConsole 'No Strata installation or model download is required. Start the chosen local server separately.'
} else {
    $Git=Require-Command 'git.exe' 'Git.Git' 'https://git-scm.com/download/win'
$knownStrata = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'LocalAI\Strata'
$defaultStrata = if (-not $script:AwxSetupIsolated -and (Test-Path -LiteralPath (Join-Path $knownStrata 'setup.py'))) { $knownStrata } else { Join-Path $RuntimeRoot 'Strata' }
$entered = Read-SetupValue "Strata folder [Enter for $defaultStrata]"
$StrataRoot = if ($entered) { [IO.Path]::GetFullPath($entered.Trim('"')) } else { $defaultStrata }
if ($script:AwxSetupIsolated -and -not (Test-SetupWithin $StrataRoot $RuntimeRoot)) { throw 'Isolated setup requires Strata inside RuntimeRoot. Use a separate source/config there to reuse existing model weights without running the production installer.' }
Add-SetupPrivateValue $StrataRoot '<strata>'
if (-not (Test-Path -LiteralPath (Join-Path $StrataRoot 'setup.py'))) {
    if (-not (Ask-Yes 'Download the official Strata v0.2.4 source and its setup dependencies?')) { throw 'Strata setup was cancelled.' }
    if ((Test-Path -LiteralPath $StrataRoot) -and @(Get-ChildItem -LiteralPath $StrataRoot -Force).Count) { throw 'Choose an empty folder or an existing Strata installation.' }
    Run-Checked $Git @('clone','--progress','--depth','1','--branch','v0.2.4','https://github.com/Niko1221/Strata.git',$StrataRoot)
}

Push-Location -LiteralPath $StrataRoot
try {
    # HELP: DEPENDENCIES - create only Strata's private venv with the interpreter
    # already validated above. START-HERE.bat may otherwise try a global Python
    # install/optional shared launcher. Preserve the alpha.5 launcher safeguards.
    $StrataPython=Join-Path $StrataRoot '.venv\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $StrataPython -PathType Leaf)) { Run-Checked $Python @('-m','venv',(Join-Path $StrataRoot '.venv')) }
    if (-not (Select-AwxPython @([pscustomobject]@{Executable=$StrataPython;Arguments=@()}))) { throw 'Strata needs a working private 64-bit Python 3.10+ environment. Existing files were kept.' }
    # HELP: PROGRESS - the wrapper changes the display only. The official setup
    # retains its range resume, SHA-256 repair, TLS and explicit model choices.
    Invoke-StrataSetup @('--check')
    $models = @(Get-ChildItem -LiteralPath $StrataRoot -Filter 'strata-*.json' -File | Where-Object {
        try { $candidate = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json; $candidate.exe -and $candidate.args -and $candidate.model_name } catch { $false }
    })
    if ($models.Count -eq 0 -or (Ask-Yes 'Install another model instead of reusing the installed model files?')) {
        Write-SetupConsole '1: Our tested Qwen 3.8 Coder IQ1_M preset (58.4 GB download, additional prepared data; tested on 12 GB VRAM / 32 GB RAM).'
        Write-SetupConsole '2: Use Strata hardware-guided setup to choose another supported model. Download size and terms vary.'
        Write-SetupConsole 'Model terms: https://huggingface.co/Qwen/Qwen3.8-Flash-Next/blob/main/LICENSE'
        Write-SetupConsole 'Quantized model card: https://huggingface.co/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF'
        $choice = Read-SetupValue 'Choose 1 or 2 [Enter for guided setup]'
        if ((Read-SetupValue 'After reviewing applicable model terms and disk needs, type DOWNLOAD to continue') -cne 'DOWNLOAD') { throw 'No model download was started.' }
        if ($choice -eq '1') {
            Invoke-StrataSetup @('--yes','--setup','--family','coder','--model','IQ1_M','--context','16384','--vision','no','--host','127.0.0.1','--port','8081','--no-start')
        } else {
            Invoke-StrataSetup @('--setup','--context','16384','--vision','no','--host','127.0.0.1','--port','8081','--no-start')
        }
        $models = @(Get-ChildItem -LiteralPath $StrataRoot -Filter 'strata-*.json' -File | Where-Object {
            try { $candidate = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json; $candidate.exe -and $candidate.args -and $candidate.model_name } catch { $false }
        })
    }
} finally { Pop-Location }
if (-not $models.Count) { throw 'No usable model configuration was found.' }
for ($i=0; $i -lt $models.Count; $i++) { Write-SetupConsole ('{0}: {1}' -f ($i+1),$models[$i].BaseName) }
$selectedIndex = 0
if ($models.Count -gt 1) {
    $answer = Read-SetupValue 'Select an installed model number [1]'
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

Write-SetupConsole "`nStep 3 of 4: Prepare coding clients" -ForegroundColor Cyan
$packages = Join-Path $RuntimeRoot 'agent-packages'
$harnessInstalled = Test-Path -LiteralPath (Join-Path $packages 'node_modules\@deepseek-ai\dsh\lib\bin.js')
$codexInstalled = Test-Path -LiteralPath (Join-Path $packages 'node_modules\.bin\codex.cmd')
if (-not ($harnessInstalled -and $codexInstalled)) {
    if (-not (Ask-Yes 'Install the official DeepSeek Harness and Codex CLI packages into this app runtime?')) { throw 'Agent package installation was cancelled.' }
    Run-Checked $Npm @('install','--progress=true','--prefix',$packages,'@deepseek-ai/dsh@0.2.1-rc.2','@openai/codex@0.160.0')
}
$HarnessEntry = Join-Path $packages 'node_modules\@deepseek-ai\dsh\lib\bin.js'
$CodexCommand = Join-Path $packages 'node_modules\.bin\codex.cmd'
$CodexEntry = Join-Path $packages 'node_modules\@openai\codex\bin\codex.js'
Write-SetupConsole "`nStep 4 of 4: Choose your project and save local settings" -ForegroundColor Cyan
if (-not $WorkspaceRoot) {
    $workspaceDefault = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'LocalAI-Workspace'
    $entered = Read-SetupValue "Working project folder [Enter for $workspaceDefault]"
    $WorkspaceRoot = if ($entered) { [IO.Path]::GetFullPath($entered.Trim('"')) } else { $workspaceDefault }
}
if ($script:AwxSetupIsolated -and ((Test-SetupWithin $WorkspaceRoot $RuntimeRoot) -or (Test-SetupWithin $RuntimeRoot $WorkspaceRoot))) { throw 'RuntimeRoot and the project workspace must be separate directories.' }
if ($script:AwxSetupIsolated -and ((Test-SetupWithin $WorkspaceRoot $RepoRoot) -or (Test-SetupWithin $RepoRoot $WorkspaceRoot))) { throw 'An isolated workspace must be separate from the source checkout.' }
Add-SetupWorkspacePrivacy $WorkspaceRoot
[void][System.IO.Directory]::CreateDirectory($WorkspaceRoot)
$projectFiles = @(Get-ChildItem -LiteralPath $WorkspaceRoot -Filter '*.uproject' -File)
$UnrealName = if ($projectFiles.Count -eq 1) { $projectFiles[0].BaseName } else { '' }
Add-SetupPrivateValue $UnrealName '<project>'
$EnginePython = ''
if ($UnrealName) {
    $EnginePython = Read-SetupValue 'Unreal engine Python plugin folder (the folder containing remote_execution.py; Enter skips live editor tools)'
    if ($EnginePython) { $EnginePython = [IO.Path]::GetFullPath($EnginePython.Trim('"')) }
    Add-SetupPrivateValue $EnginePython '<engine-python>'
    if ($EnginePython -and -not (Test-Path -LiteralPath (Join-Path $EnginePython 'remote_execution.py'))) { throw 'That folder does not contain remote_execution.py.' }
}
$settings = [ordered]@{NodeExecutable=$Node;HarnessEntry=$HarnessEntry;HarnessHome=(Join-Path $RuntimeRoot 'harness-home');PythonExecutable=$Python;StrataRoot=$StrataRoot;StrataConfig=$StrataConfig;StrataPython=$StrataPython;ModelBackend=$ModelBackend;ModelBaseUrl=$ModelBaseUrl;ModelId=$ModelId;WorkspaceRoot=$WorkspaceRoot;UnrealProjectName=$UnrealName;EnginePython=$EnginePython;StateRoot=$RuntimeRoot;ModelLabel=$model.model_name;CodexCommand=$CodexCommand;CodexEntry=$CodexEntry;GatewayPort=$GatewayPort;HarnessPort=$HarnessPort}
$configPath = Join-Path $RepoRoot 'config.local.json'
# HELP: CONFIG - only this checkout's ignored settings and chosen runtime are
# written. Back up existing local settings first. Isolated acceptance must use a
# separate source checkout because RuntimeRoot does not move config.local.json.
Save-Backup $configPath
Write-Utf8 $configPath ($settings | ConvertTo-Json)
# Generate isolated client homes using this checkout's current location.
# No global client profile or existing workspace instruction file is replaced.
Run-Checked $Python @((Join-Path $RepoRoot 'app/control_runtime.py'),'prepare','--config',$configPath)
Write-SetupConsole "`nSetup complete. Open Launch.cmd to choose your coding workspace." -ForegroundColor Cyan
Write-SetupConsole 'No model was started. Local paths and logs stay in ignored configuration/runtime folders.'
if ($ModelBackend -eq 'strata') { Write-SetupConsole 'Use the model controls to start the selected Strata configuration.' }
else { Write-SetupConsole 'Start and load your configured local model server separately before using chat.' }
Write-SetupConsole 'Made by AiBrainWorX'
$global:LASTEXITCODE=0
} catch {
    # HELP: ERRORS - surface real failures and keep resumable downloads. Never
    # print a success step or a fabricated percentage when an operation fails.
    Write-SetupConsole "`nSetup did not finish: $($_.Exception.Message)" -ForegroundColor Red
    Write-SetupConsole 'You can rerun Setup.cmd after fixing this step. Existing model downloads and settings were kept.'
    exit 1
}
