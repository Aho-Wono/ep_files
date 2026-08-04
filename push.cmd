@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Publish-EpFiles.ps1"
set "push_exit_code=%ERRORLEVEL%"
echo.
if not "%push_exit_code%"=="0" echo Push stopped safely. Exit code: %push_exit_code%
pause
exit /b %push_exit_code%

