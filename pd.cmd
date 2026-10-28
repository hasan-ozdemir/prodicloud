@echo off
setlocal
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo - You are not running with administrator privileges.
    echo - Restarting with elevated privileges...
    start powershell -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    if %errorlevel% neq 0 (
        echo !!! Error: Failed to obtain administrator permission. Please run cmd with 'Run as administrator'.!!!
        set /p __exit_prompt=Press Enter to exit.
    )
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\prodicloud-cli.ps1" %*
set "prodicloudExitCode=%ERRORLEVEL%"
endlocal & exit /b %prodicloudExitCode%
