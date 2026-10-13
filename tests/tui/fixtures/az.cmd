@echo off
setlocal
set "CLAGNOS_TUI_AZ_ARGUMENT_LINE=%*"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0az-fixture.ps1"
exit /b %ERRORLEVEL%
