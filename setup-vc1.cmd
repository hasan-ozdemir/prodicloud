@echo off
setlocal
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0setup-vc.ps1" -VmName vc1 %*
exit /b %ERRORLEVEL%
