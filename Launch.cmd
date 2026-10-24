@echo off
setlocal
if not exist "%~dp0config.local.json" (
  call "%~dp0Setup.cmd"
  exit /b %errorlevel%
)
start "AiBrainWorX Local AI" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0app\Launcher.ps1"
