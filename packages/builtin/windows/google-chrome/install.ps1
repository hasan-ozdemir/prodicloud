$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-chrome-application"

Import-Module 'C:\Windows\Temp\clagnos-session-environment.psm1' -Force -DisableNameChecking

function Refresh-SessionPath {
    Refresh-ClagnosSessionPath | Out-Null
}

function Resolve-ChocoExecutable {
    $chocoExe = "$env:ProgramData\chocolatey\bin\choco.exe"
    if (Test-Path -LiteralPath $chocoExe) {
        return [string]$chocoExe
    }

    $cmd = Get-Command choco -ErrorAction SilentlyContinue
    if ($cmd -and -not [string]::IsNullOrWhiteSpace([string]$cmd.Source)) {
        return [string]$cmd.Source
    }

    return ""
}

function Resolve-ChromeExecutable {
    $cmd = Get-Command chrome.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        foreach ($candidate in @([string]$cmd.Source, [string]$cmd.Path, [string]$cmd.Definition)) {
            if ([string]::IsNullOrWhiteSpace([string]$candidate)) { continue }
            if ([System.IO.Path]::IsPathRooted([string]$candidate) -and (Test-Path -LiteralPath $candidate)) {
                return [string]$candidate
            }
        }
    }

    foreach ($candidate in @(
        "C:\Program Files\Google\Chrome\Application\chrome.exe",
        "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
    )) {
        if (Test-Path -LiteralPath $candidate) {
            return [string]$candidate
        }
    }

    return ""
}

Refresh-SessionPath

$chocoExe = Resolve-ChocoExecutable
if ([string]::IsNullOrWhiteSpace($chocoExe)) {
    throw "choco command is not available. Google Chrome install requires Chocolatey."
}

Write-Host "Resolved choco executable: $chocoExe"
$existingChromeExe = Resolve-ChromeExecutable
if (-not [string]::IsNullOrWhiteSpace([string]$existingChromeExe)) {
    Write-Host ("Google Chrome executable already exists: {0}" -f $existingChromeExe)
    Write-Host "install-chrome-application-completed"
    Write-Host "Update task completed: install-chrome-application"
    return
}

Write-Host "Running: choco install googlechrome -y --no-progress --ignore-detected-reboot --ignore-checksums"
& $chocoExe install googlechrome -y --no-progress --ignore-detected-reboot --ignore-checksums
$chocoExit = [int]$LASTEXITCODE
if ($chocoExit -ne 0 -and $chocoExit -ne 2) {
    throw "choco install googlechrome failed with exit code $chocoExit."
}

Refresh-SessionPath

$chromeExe = Resolve-ChromeExecutable
if ([string]::IsNullOrWhiteSpace([string]$chromeExe)) {
    throw "Google Chrome executable path was not detected after installation."
}

Write-Host "Chrome executable: $chromeExe"
Write-Host "install-chrome-application-completed"
Write-Host "Update task completed: install-chrome-application"

