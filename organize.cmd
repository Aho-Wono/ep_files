@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Organize-EpFiles.ps1"
set "organize_exit_code=%ERRORLEVEL%"
echo.
if not "%organize_exit_code%"=="0" echo An error occurred. Exit code: %organize_exit_code%
pause
exit /b %organize_exit_code%
