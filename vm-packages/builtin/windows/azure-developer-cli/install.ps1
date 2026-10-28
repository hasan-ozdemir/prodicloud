$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-azd-tool"

Import-Module 'C:\Windows\Temp\prodicloud-session-environment.psm1' -Force -DisableNameChecking

function Refresh-SessionPath {
    Refresh-ProdicloudSessionPath | Out-Null
}

function Resolve-AzdExecutablePath {
    $command = Get-Command azd -ErrorAction SilentlyContinue
    if ($command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source) -and (Test-Path -LiteralPath ([string]$command.Source) -PathType Leaf)) {
        return [string]$command.Source
    }

    $programFiles = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
    $programFilesX86 = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFilesX86)
    $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    foreach ($root in @($programFiles,$programFilesX86)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$root)) {
            $candidates.Add((Join-Path $root 'Azure Dev CLI\azd.exe')) | Out-Null
            $candidates.Add((Join-Path $root 'Microsoft SDKs\Azure\Azure Developer CLI\azd.exe')) | Out-Null
        }
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$localAppData)) {
        $candidates.Add((Join-Path $localAppData 'Programs\Azure Dev CLI\azd.exe')) | Out-Null
        $candidates.Add((Join-Path $localAppData 'Programs\Azure Dev CLI\azd-windows-amd64.exe')) | Out-Null
    }
    foreach ($candidate in @($candidates)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return [string]$candidate
        }
    }
    return ''
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

Refresh-SessionPath
$existingAzdPath = Resolve-AzdExecutablePath
if (-not [string]::IsNullOrWhiteSpace([string]$existingAzdPath)) {
    & $existingAzdPath version
    if ($LASTEXITCODE -eq 0) {
        Write-Host ("Existing azd installation is already healthy at {0}. Skipping winget install." -f $existingAzdPath)
        Write-Host "install-azd-tool-completed"
        Write-Host "Update task completed: install-azd-tool"
        return
    }
    Write-Host ("Existing azd executable failed its version check (exit {0}); continuing with unattended WinGet install." -f [int]$LASTEXITCODE) -ForegroundColor Yellow
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
$azdPath = Resolve-AzdExecutablePath
if ([string]::IsNullOrWhiteSpace([string]$azdPath)) {
    throw 'azd.exe was not found in PATH or a supported Azure Developer CLI installation directory after installation.'
}

& $azdPath version
if ($LASTEXITCODE -ne 0) {
    throw ("azd version failed at '{0}' with exit code {1}." -f $azdPath,[int]$LASTEXITCODE)
}

Write-Host "install-azd-tool-completed"
Write-Host "Update task completed: install-azd-tool"

