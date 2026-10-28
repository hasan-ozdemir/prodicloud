$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-rclone-tool"

Import-Module 'C:\Windows\Temp\prodicloud-session-environment.psm1' -Force -DisableNameChecking

function Refresh-SessionPath {
    Refresh-ProdicloudSessionPath | Out-Null
}

function Resolve-WingetExe {
    $portableCandidate = "C:\ProgramData\prodicloud\tools\winget-x64\winget.exe"
    if (Test-Path -LiteralPath $portableCandidate) {
        return [string]$portableCandidate
    }

    $cmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($cmd -and -not [string]::IsNullOrWhiteSpace([string]$cmd.Source)) {
        return [string]$cmd.Source
    }

    return ""
}

function Resolve-RcloneExe {
    $cmd = Get-Command rclone.exe -ErrorAction SilentlyContinue
    if ($cmd -and -not [string]::IsNullOrWhiteSpace([string]$cmd.Source)) {
        return [string]$cmd.Source
    }

    foreach ($candidate in @(
        "C:\ProgramData\chocolatey\bin\rclone.exe",
        "C:\Program Files\rclone\rclone.exe"
    )) {
        if (Test-Path -LiteralPath $candidate) {
            return [string]$candidate
        }
    }

    return ""
}

Refresh-SessionPath
$existingExe = Resolve-RcloneExe
if (-not [string]::IsNullOrWhiteSpace([string]$existingExe)) {
    Write-Host ("rclone executable already exists: {0}" -f $existingExe)
    Write-Host "install-rclone-tool-completed"
    Write-Host "Update task completed: install-rclone-tool"
    return
}

$wingetExe = Resolve-WingetExe
if ([string]::IsNullOrWhiteSpace([string]$wingetExe)) {
    throw "winget command is not available."
}

Write-Host "Resolved winget executable: $wingetExe"
Write-Host "Running: winget install --id Rclone.Rclone --accept-source-agreements --accept-package-agreements --silent --disable-interactivity"
& $wingetExe install --id Rclone.Rclone --accept-source-agreements --accept-package-agreements --silent --disable-interactivity
$installExit = [int]$LASTEXITCODE
if ($installExit -ne 0 -and $installExit -ne -1978335189) {
    throw "winget install Rclone.Rclone failed with exit code $installExit."
}

Refresh-SessionPath
$installedExe = Resolve-RcloneExe
if ([string]::IsNullOrWhiteSpace([string]$installedExe)) {
    Write-Host "Running: winget list --id Rclone.Rclone"
    $listOutput = & $wingetExe list --id Rclone.Rclone
    $listText = [string]($listOutput | Out-String)
    if ([string]::IsNullOrWhiteSpace($listText) -or -not $listText.ToLowerInvariant().Contains("rclone")) {
        throw "rclone install could not be verified."
    }
}

Write-Host "install-rclone-tool-completed"
Write-Host "Update task completed: install-rclone-tool"

