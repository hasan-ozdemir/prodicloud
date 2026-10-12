$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-windscribe-application"

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

function Test-WindscribeInstalled {
    Write-Host "Running: winget list windscribe"
    $listOutput = & $wingetExe list windscribe
    $listText = [string]($listOutput | Out-String)
    if (-not [string]::IsNullOrWhiteSpace($listText) -and $listText.ToLowerInvariant().Contains("windscribe")) {
        return $true
    }

    if (Get-Command Get-StartApps -ErrorAction SilentlyContinue) {
        $startApps = @(Get-StartApps | Where-Object { ([string]$_.Name).ToLowerInvariant().Contains("windscribe") })
        if ($startApps.Count -gt 0) {
            return $true
        }
    }

    return $false
}

Refresh-SessionPath
$wingetExe = Resolve-WingetExe
if ([string]::IsNullOrWhiteSpace([string]$wingetExe)) {
    throw "winget command is not available."
}

Write-Host "Resolved winget executable: $wingetExe"
if (Test-WindscribeInstalled) {
    Write-Host "Existing Windscribe installation is already healthy. Skipping winget install."
    Write-Host "install-windscribe-application-completed"
    Write-Host "Update task completed: install-windscribe-application"
    return
}

Write-Host "Running: winget install windscribe --accept-source-agreements --accept-package-agreements --silent --disable-interactivity"
& $wingetExe install windscribe --accept-source-agreements --accept-package-agreements --silent --disable-interactivity
$installExit = [int]$LASTEXITCODE
if ($installExit -ne 0 -and $installExit -ne -1978335189) {
    throw "winget install windscribe failed with exit code $installExit."
}

if (-not (Test-WindscribeInstalled)) {
    throw "Windscribe install could not be verified."
}

Write-Host "install-windscribe-application-completed"
Write-Host "Update task completed: install-windscribe-application"

