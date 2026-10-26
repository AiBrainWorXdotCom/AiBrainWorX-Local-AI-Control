$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'app\Setup-Prerequisites.ps1')
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('aibrainworx-setup-test-'+[guid]::NewGuid().ToString('N'))
$oldPath=$env:Path
$oldLocal=$env:LOCALAPPDATA
$oldMode=$env:ABX_SETUP_TEST_MODE
$oldManager=$env:PYTHON_MANAGER_AUTOMATIC_INSTALL
$oldAllow=$env:PYLAUNCHER_ALLOW_INSTALL
$oldAlways=$env:PYLAUNCHER_ALWAYS_INSTALL
function Assert($Condition,[string]$Message) { if(-not $Condition){throw $Message} }
function Candidate([string]$Path,[string[]]$Prefix=@()) { [pscustomobject]@{Executable=$Path;Arguments=$Prefix} }
try {
    $space=Join-Path $temporary 'tools & cost $5'
    [void][IO.Directory]::CreateDirectory($space)
    $fixture=Join-Path $space 'probe.exe'
    Add-Type -OutputAssembly $fixture -OutputType ConsoleApplication -TypeDefinition @'
using System;
using System.Reflection;
using System.Text;
public class DependencyFixture {
    public static int Main(string[] args) {
        string mode=Environment.GetEnvironmentVariable("ABX_SETUP_TEST_MODE") ?? "good";
        if(System.IO.Path.GetFileName(Assembly.GetExecutingAssembly().Location)=="alias.exe"){mode="alias";}
        if(mode=="environment" && (Environment.GetEnvironmentVariable("PYTHON_MANAGER_AUTOMATIC_INSTALL")!="false" || Environment.GetEnvironmentVariable("PYLAUNCHER_ALLOW_INSTALL")!=null || Environment.GetEnvironmentVariable("PYLAUNCHER_ALWAYS_INSTALL")!=null)){return 8;}
        if(mode=="alias"){Console.Error.WriteLine("Python was not found; run without arguments to install from the Microsoft Store.");return 9009;}
        if(mode=="sleep"){System.Threading.Thread.Sleep(30000);return 0;}
        if(mode=="malformed"){Console.WriteLine("not Python");return 0;}
        if(mode=="args"){Console.WriteLine(Convert.ToBase64String(Encoding.UTF8.GetBytes(String.Join("\n",args))));return 0;}
        if(mode=="launcher" && (args.Length==0 || args[0]!="-3.12")){return 1;}
        if(args.Length>0 && args[0]=="install"){
            string command=String.Join("|",args);
            if(!command.Contains("--id|Python.Python.3.12") || !command.Contains("--source|winget") || !command.Contains("--scope|user") || !command.Contains("--architecture|x64") || !command.Contains("--custom|Include_launcher=0 InstallLauncherAllUsers=0") || command.Contains("--override") || command.Contains("--ignore-security-hash")){Console.WriteLine("Missing ordinary-user installer safeguards.");return 9;}
            if(mode=="policy-block"){Console.WriteLine("Installer failed with exit code: 1625");return 7;}
            Console.WriteLine("Simulated installation output, not an executable path.");return mode=="install-failed" ? 7 : 0;
        }
        string path=Assembly.GetExecutingAssembly().Location.Replace("\\","\\\\").Replace("\"","\\\"");
        Console.WriteLine("ABX_PYTHON={\"executable\":\""+path+"\",\"version\":[3,"+(mode=="old"?"9":"12")+",0],\"bits\":"+(mode=="32bit"?"32":"64")+"}");
        return 0;
    }
}
'@
    $env:ABX_SETUP_TEST_MODE='alias'
    Assert (-not (Select-AwxPython @((Candidate $fixture)))) 'The Microsoft Store placeholder was accepted as Python.'
    foreach($mode in @('old','32bit','malformed')) {
        $env:ABX_SETUP_TEST_MODE=$mode
        Assert (-not (Select-AwxPython @((Candidate $fixture)))) "Unsupported probe accepted: $mode"
    }
    $env:ABX_SETUP_TEST_MODE='good'
    Assert ((Select-AwxPython @((Candidate $fixture))) -ceq $fixture) 'A working interpreter in a path with spaces/metacharacters was not accepted.'
    $alias=Join-Path $space 'alias.exe'
    Copy-Item -LiteralPath $fixture -Destination $alias
    Assert ((Select-AwxPython @((Candidate $alias),(Candidate $fixture))) -ceq $fixture) 'An earlier Store shortcut blocked a valid later interpreter.'
    $env:ABX_SETUP_TEST_MODE='environment'
    $env:PYTHON_MANAGER_AUTOMATIC_INSTALL='true';$env:PYLAUNCHER_ALLOW_INSTALL='1';$env:PYLAUNCHER_ALWAYS_INSTALL='1'
    Assert ((Select-AwxPython @((Candidate $fixture))) -ceq $fixture) 'Read-only probe did not disable child install-on-demand settings.'
    Assert ($env:PYTHON_MANAGER_AUTOMATIC_INSTALL -ceq 'true' -and $env:PYLAUNCHER_ALLOW_INSTALL -ceq '1' -and $env:PYLAUNCHER_ALWAYS_INSTALL -ceq '1') 'Probe changed the caller install-manager environment.'
    $env:ABX_SETUP_TEST_MODE='launcher'
    Assert ((Select-AwxPython @((Candidate $fixture @('-3.12')))) -ceq $fixture) 'py.exe selector was lost.'
    $env:ABX_SETUP_TEST_MODE='args'
    $arguments=@('space & dollar $5','embedded"quote','ends with slash\','two\\"quotes')
    $roundtrip=Invoke-AwxDependencyProbe $fixture $arguments
    Assert ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($roundtrip)) -ceq ($arguments -join "`n")) 'Native argument quoting changed the command.'
    $env:ABX_SETUP_TEST_MODE='sleep'
    $watch=[Diagnostics.Stopwatch]::StartNew()
    Assert (-not (Select-AwxPython @((Candidate $fixture)) 200)) 'A hanging probe was accepted.'
    Assert ($watch.Elapsed.TotalSeconds -lt 5) 'A hanging probe was not bounded.'
    $env:ABX_SETUP_TEST_MODE='good'
    $perUser=Join-Path $temporary 'Programs\Python\Python312'
    [void][IO.Directory]::CreateDirectory($perUser)
    $python=Join-Path $perUser 'python.exe'
    Copy-Item -LiteralPath $fixture -Destination $python
    $env:LOCALAPPDATA=$temporary
    $env:Path=$env:SystemRoot
    $found=@(Get-AwxPythonCandidates | Where-Object {$_.Executable -ceq $python})
    Assert ($found.Count -eq 1) 'A per-user install missing from PATH was not discovered.'
    Assert ((Select-AwxPython $found) -ceq $python) 'Discovered per-user Python was not validated.'
    # Simulate a new user's Store-only setup followed by a successful install.
    # Only the fixture executable runs; no package/network/registry changes occur.
    $winget=Join-Path $space 'winget.exe'
    Copy-Item -LiteralPath $fixture -Destination $winget
    $env:Path=$space+';'+$env:SystemRoot
    $script:findCount=0;$script:refreshCount=0
    function Find-AwxPython { $script:findCount++; if($script:findCount -ge 2){return $fixture};return $null }
    function Ask-Yes { return $true }
    function Refresh-ProcessPath { $script:refreshCount++ }
    $selected=@(Require-AwxPython)
    Assert ($selected.Count -eq 1 -and $selected[0] -ceq $fixture) 'Installer output leaked into the returned executable path.'
    Assert ($script:findCount -eq 2 -and $script:refreshCount -eq 1) 'Python was not revalidated after installation.'
    $script:findCount=0;$env:ABX_SETUP_TEST_MODE='install-failed';$failed=$false
    try { Require-AwxPython | Out-Null } catch {$failed=$_.Exception.Message -like '*installation did not finish*'}
    Assert $failed 'A failed install was reported as success.'
    $script:findCount=0;$env:ABX_SETUP_TEST_MODE='policy-block';$blocked=$false
    try { Require-AwxPython | Out-Null } catch {$blocked=$_.Exception.Message -like '*1625*security policies unchanged*'}
    Assert $blocked 'A policy-blocked install did not give an actionable 1625 message.'
    $script:findCount=0;$env:ABX_SETUP_TEST_MODE='good'
    function Ask-Yes { return $false }
    $declined=$false
    try { Require-AwxPython | Out-Null } catch {$declined=$_.Exception.Message -like '*python.org*'}
    Assert $declined 'Declining installation did not give the official manual recovery instructions.'
    Write-Host 'Setup prerequisite checks passed: Store alias, old/32-bit Python, malformed output, launcher selectors, quoting, timeout, per-user discovery, install/retry, failed install and declined install.'
} finally {
    $env:Path=$oldPath;$env:LOCALAPPDATA=$oldLocal
    [Environment]::SetEnvironmentVariable('ABX_SETUP_TEST_MODE',$oldMode,'Process')
    [Environment]::SetEnvironmentVariable('PYTHON_MANAGER_AUTOMATIC_INSTALL',$oldManager,'Process')
    [Environment]::SetEnvironmentVariable('PYLAUNCHER_ALLOW_INSTALL',$oldAllow,'Process')
    [Environment]::SetEnvironmentVariable('PYLAUNCHER_ALWAYS_INSTALL',$oldAlways,'Process')
    if(Test-Path -LiteralPath $temporary) {
        $resolved=(Resolve-Path -LiteralPath $temporary).Path
        $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
        if(-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or -not ([IO.Path]::GetFileName($resolved)).StartsWith('aibrainworx-setup-test-')){throw 'Refusing cleanup outside the temporary setup test folder.'}
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
$global:LASTEXITCODE=0
