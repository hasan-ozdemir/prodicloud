$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-ffmpeg-tool"

Import-Module 'C:\Windows\Temp\clagnos-session-environment.psm1' -Force -DisableNameChecking

function Refresh-SessionPath {
    Refresh-ClagnosSessionPath | Out-Null
}

$chocoExe = "$env:ProgramData\chocolatey\bin\choco.exe"
if (-not (Test-Path -LiteralPath $chocoExe)) { throw "choco was not found." }
Refresh-SessionPath

if (Get-Command ffmpeg -ErrorAction SilentlyContinue) {
    Write-Host "Existing FFmpeg installation is already healthy. Skipping choco install."
    ffmpeg -version
    Write-Host "Update task completed: install-ffmpeg-tool"
    return
}

& $chocoExe install ffmpeg -y --no-progress --ignore-detected-reboot
if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 2) { throw "choco install ffmpeg failed with exit code $LASTEXITCODE." }
Refresh-SessionPath
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) { throw "ffmpeg command was not found after install." }
ffmpeg -version
Write-Host "Update task completed: install-ffmpeg-tool"

