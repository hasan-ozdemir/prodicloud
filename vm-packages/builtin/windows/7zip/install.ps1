$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-7zip-tool"

Import-Module 'C:\Windows\Temp\clagnos-session-environment.psm1' -Force -DisableNameChecking

function Refresh-SessionPath {
    Refresh-ClagnosSessionPath | Out-Null
}

$chocoExe = "$env:ProgramData\chocolatey\bin\choco.exe"
if (-not (Test-Path -LiteralPath $chocoExe)) { throw "choco was not found." }
Refresh-SessionPath

if (Get-Command 7z -ErrorAction SilentlyContinue) {
    Write-Host "Existing 7-Zip installation is already healthy. Skipping choco install."
    7z
    Write-Host "Update task completed: install-7zip-tool"
    return
}

& $chocoExe install 7zip -y --no-progress --ignore-detected-reboot
if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 2) { throw "choco install 7zip failed with exit code $LASTEXITCODE." }
Refresh-SessionPath
if (-not (Get-Command 7z -ErrorAction SilentlyContinue)) { throw "7z command was not found after install." }
7z
Write-Host "Update task completed: install-7zip-tool"

