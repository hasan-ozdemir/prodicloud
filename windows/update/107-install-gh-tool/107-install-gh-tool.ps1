$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-gh-tool"

Import-Module 'C:\Windows\Temp\clagnos-session-environment.psm1' -Force -DisableNameChecking

function Refresh-SessionPath {
    Refresh-ClagnosSessionPath | Out-Null
}

$chocoExe = "$env:ProgramData\chocolatey\bin\choco.exe"
if (-not (Test-Path -LiteralPath $chocoExe)) { throw "choco was not found." }
Refresh-SessionPath

if (Get-Command gh -ErrorAction SilentlyContinue) {
    Write-Host "Existing GitHub CLI installation is already healthy. Skipping choco install."
    gh --version
    Write-Host "Update task completed: install-gh-tool"
    return
}

& $chocoExe install gh -y --no-progress --ignore-detected-reboot
if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 2) { throw "choco install gh failed with exit code $LASTEXITCODE." }
Refresh-SessionPath
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw "gh command was not found after install." }
gh --version
Write-Host "Update task completed: install-gh-tool"

