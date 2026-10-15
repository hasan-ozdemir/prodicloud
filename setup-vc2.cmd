@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-vc2.ps1" %*
exit /b %ERRORLEVEL%
