@echo off
setlocal
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0remove-vc.ps1" -VmName vc2 %*
exit /b %ERRORLEVEL%
