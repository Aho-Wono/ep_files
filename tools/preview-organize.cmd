@echo off
setlocal
cd /d "%~dp0.."
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Organize-EpFiles.ps1" -WhatIf
set "organize_exit_code=%ERRORLEVEL%"
echo.
pause
exit /b %organize_exit_code%

