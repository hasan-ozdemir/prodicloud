$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-google-drive-application"

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

function Resolve-ExecutableUnderDirectory {
    param(
        [string]$RootPath,
        [string]$ExecutableName
    )

    if ([string]::IsNullOrWhiteSpace([string]$RootPath) -or [string]::IsNullOrWhiteSpace([string]$ExecutableName)) {
        return ""
    }
    if (-not (Test-Path -LiteralPath $RootPath)) {
        return ""
    }

    $directCandidate = Join-Path $RootPath $ExecutableName
    if (Test-Path -LiteralPath $directCandidate) {
        return [string]$directCandidate
    }

    $match = Get-ChildItem -LiteralPath $RootPath -Filter $ExecutableName -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName | Select-Object -First 1
    if ($match -and (Test-Path -LiteralPath $match.FullName)) {
        return [string]$match.FullName
    }

    return ""
}

function Resolve-GoogleDriveExe {
    $primary = "C:\Program Files\Google\Drive File Stream\GoogleDriveFS.exe"
    if (Test-Path -LiteralPath $primary) {
        return [string]$primary
    }

    return (Resolve-ExecutableUnderDirectory -RootPath "C:\Program Files\Google\Drive File Stream" -ExecutableName "GoogleDriveFS.exe")
}

Refresh-SessionPath
$existingExe = Resolve-GoogleDriveExe
if (-not [string]::IsNullOrWhiteSpace([string]$existingExe)) {
    Write-Host ("Google Drive executable already exists: {0}" -f $existingExe)
    Write-Host "install-google-drive-application-completed"
    Write-Host "Update task completed: install-google-drive-application"
    return
}

$wingetExe = Resolve-WingetExe
if ([string]::IsNullOrWhiteSpace([string]$wingetExe)) {
    throw "winget command is not available."
}

Write-Host "Resolved winget executable: $wingetExe"
Write-Host "Running: winget install --id Google.GoogleDrive --accept-source-agreements --accept-package-agreements --silent --disable-interactivity"
& $wingetExe install --id Google.GoogleDrive --accept-source-agreements --accept-package-agreements --silent --disable-interactivity
$installExit = [int]$LASTEXITCODE
if ($installExit -ne 0 -and $installExit -ne -1978335189) {
    throw "winget install Google.GoogleDrive failed with exit code $installExit."
}

Refresh-SessionPath
$installedExe = Resolve-GoogleDriveExe
if ([string]::IsNullOrWhiteSpace([string]$installedExe)) {
    Write-Host "Running: winget list --id Google.GoogleDrive"
    $listOutput = & $wingetExe list --id Google.GoogleDrive
    $listText = [string]($listOutput | Out-String)
    if ([string]::IsNullOrWhiteSpace($listText) -or -not $listText.ToLowerInvariant().Contains("google drive")) {
        throw "Google Drive install could not be verified."
    }
}

Write-Host "install-google-drive-application-completed"
Write-Host "Update task completed: install-google-drive-application"

