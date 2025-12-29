@echo off
REM mytool/install-meslo-font.bat
REM Batch wrapper to run PowerShell script with admin privileges

setlocal enabledelayedexpansion

REM Get the directory where this batch file is located
set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%install-meslo-font.ps1"

REM Check if the PowerShell script exists
if not exist "!PS_SCRIPT!" (
    echo ERROR: install-meslo-font.ps1 not found in %SCRIPT_DIR%
    pause
    exit /b 1
)

REM Run PowerShell script with admin privileges
powershell -Command "Start-Process PowerShell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"!PS_SCRIPT!\"' -Verb RunAs"

exit /b 0
