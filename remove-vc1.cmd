@echo off
setlocal
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0remove-vc.ps1" -VmName vc1 %*
exit /b %ERRORLEVEL%
