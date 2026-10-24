@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\Check-Installation.ps1" >nul
if errorlevel 1 (
  call "%~dp0Setup.cmd"
  "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\Check-Installation.ps1" >nul
  if errorlevel 1 exit /b 1
)
start "AiBrainWorX Local AI" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0app\Launcher.ps1"
