@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Pull-EpFiles.ps1"
set "pull_exit_code=%ERRORLEVEL%"
echo.
if not "%pull_exit_code%"=="0" echo Pull stopped safely. Exit code: %pull_exit_code%
pause
exit /b %pull_exit_code%

