@echo off
setlocal

rem Automatically map UNC paths so CMD can run from WSL shares
pushd "%~dp0" >nul 2>&1
if errorlevel 1 (
    echo Failed to enter script directory. Aborting.
    exit /b 1
)

set "SCRIPT_DIR=%CD%"
set "PS_SCRIPT=%SCRIPT_DIR%\install-fonts.ps1"

if not exist "%PS_SCRIPT%" (
    echo Missing PowerShell installer: %PS_SCRIPT%
    popd >nul
    exit /b 1
)

echo Running PowerShell installer from:
echo   %PS_SCRIPT%
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
set "EXIT_CODE=%ERRORLEVEL%"

popd >nul

if "%EXIT_CODE%" neq "0" (
    echo.
    echo Installer exited with code %EXIT_CODE%.
    pause
    exit /b %EXIT_CODE%
)

echo.
echo All done. Fonts are ready for use. Restart Windows Terminal if it was open.
pause
exit /b 0
