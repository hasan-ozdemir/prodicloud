$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-azd-tool"

Import-Module 'C:\Windows\Temp\clagnos-session-environment.psm1' -Force -DisableNameChecking

function Refresh-SessionPath {
    Refresh-ClagnosSessionPath | Out-Null
}

function Resolve-WingetExe {
    $portableCandidate = "C:\ProgramData\clagnos\tools\winget-x64\winget.exe"
    if (Test-Path -LiteralPath $portableCandidate) {
        return [string]$portableCandidate
    }

    $cmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($cmd -and -not [string]::IsNullOrWhiteSpace([string]$cmd.Source)) {
        return [string]$cmd.Source
    }

    return ""
}

Refresh-SessionPath
if (Get-Command azd -ErrorAction SilentlyContinue) {
    Write-Host "Existing azd installation is already healthy. Skipping winget install."
    azd version
    if ($LASTEXITCODE -ne 0) {
        throw "azd version failed with exit code $LASTEXITCODE."
    }
    Write-Host "install-azd-tool-completed"
    Write-Host "Update task completed: install-azd-tool"
    return
}

$wingetExe = Resolve-WingetExe
if ([string]::IsNullOrWhiteSpace([string]$wingetExe)) {
    throw "winget command is not available."
}

Write-Host "Resolved winget executable: $wingetExe"
Write-Host "Running: winget install microsoft.azd --accept-source-agreements --accept-package-agreements --silent --disable-interactivity"
& $wingetExe install microsoft.azd --accept-source-agreements --accept-package-agreements --silent --disable-interactivity
$installExit = [int]$LASTEXITCODE
if ($installExit -ne 0 -and $installExit -ne -1978335189) {
    throw "winget install microsoft.azd failed with exit code $installExit."
}

Refresh-SessionPath
if (-not (Get-Command azd -ErrorAction SilentlyContinue)) {
    throw "azd command was not found after installation."
}

azd version
if ($LASTEXITCODE -ne 0) {
    throw "azd version failed with exit code $LASTEXITCODE."
}

Write-Host "install-azd-tool-completed"
Write-Host "Update task completed: install-azd-tool"

