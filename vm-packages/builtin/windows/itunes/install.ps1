$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-itunes-application"

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

function Resolve-ItunesExe {
    foreach ($candidate in @(
        "C:\Program Files\iTunes\iTunes.exe",
        "C:\Program Files (x86)\iTunes\iTunes.exe"
    )) {
        if (Test-Path -LiteralPath $candidate) {
            return [string]$candidate
        }
    }

    return ""
}

Refresh-SessionPath
$existingExe = Resolve-ItunesExe
if (-not [string]::IsNullOrWhiteSpace([string]$existingExe)) {
    Write-Host ("iTunes executable already exists: {0}" -f $existingExe)
    Write-Host "install-itunes-application-completed"
    Write-Host "Update task completed: install-itunes-application"
    return
}

$wingetExe = Resolve-WingetExe
if ([string]::IsNullOrWhiteSpace([string]$wingetExe)) {
    throw "winget command is not available."
}

Write-Host "Resolved winget executable: $wingetExe"
Write-Host "Running: winget install --id Apple.iTunes --accept-source-agreements --accept-package-agreements --silent --disable-interactivity"
& $wingetExe install --id Apple.iTunes --accept-source-agreements --accept-package-agreements --silent --disable-interactivity
$installExit = [int]$LASTEXITCODE
if ($installExit -ne 0 -and $installExit -ne -1978335189) {
    throw "winget install Apple.iTunes failed with exit code $installExit."
}

Refresh-SessionPath
$installedExe = Resolve-ItunesExe
if ([string]::IsNullOrWhiteSpace([string]$installedExe)) {
    Write-Host "Running: winget list --id Apple.iTunes"
    $listOutput = & $wingetExe list --id Apple.iTunes
    $listText = [string]($listOutput | Out-String)
    if ([string]::IsNullOrWhiteSpace($listText) -or -not $listText.ToLowerInvariant().Contains("itunes")) {
        throw "iTunes install could not be verified."
    }
}

Write-Host "install-itunes-application-completed"
Write-Host "Update task completed: install-itunes-application"

