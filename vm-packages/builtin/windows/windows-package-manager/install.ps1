$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
Write-Host "Update task started: install-winget-tool"

Import-Module 'C:\Windows\Temp\prodicloud-session-environment.psm1' -Force -DisableNameChecking

function Refresh-SessionPath {
    Refresh-ProdicloudSessionPath | Out-Null
}

function Add-MachinePathEntry {
    param(
        [string]$Entry
    )

    if ([string]::IsNullOrWhiteSpace($Entry)) {
        return
    }

    $normalized = $Entry.Trim().TrimEnd('\')
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return
    }

    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $parts = @()
    if (-not [string]::IsNullOrWhiteSpace($machinePath)) {
        $parts = @($machinePath -split ';')
    }

    $exists = $false
    foreach ($part in @($parts)) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        $partNormalized = $part.Trim().TrimEnd('\')
        if ([string]::Equals($partNormalized, $normalized, [System.StringComparison]::OrdinalIgnoreCase)) {
            $exists = $true
            break
        }
    }

    if (-not $exists) {
        $updated = if ([string]::IsNullOrWhiteSpace($machinePath)) { $normalized } else { "$machinePath;$normalized" }
        [Environment]::SetEnvironmentVariable("Path", $updated, "Machine")
    }
}

function Test-WingetExecutable {
    param(
        [string]$ExePath
    )

    if ([string]::IsNullOrWhiteSpace($ExePath)) {
        return $false
    }
    if (-not (Test-Path -LiteralPath $ExePath)) {
        return $false
    }

    try {
        & $ExePath --version *> $null
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
}

function Get-WingetPortableRoot {
    return 'C:\ProgramData\prodicloud\tools\winget-x64'
}

function Expand-WingetPortableBundle {
    param(
        [string]$BundlePath
    )

    if ([string]::IsNullOrWhiteSpace([string]$BundlePath) -or -not (Test-Path -LiteralPath $BundlePath)) {
        throw "winget bundle was not found for portable extraction."
    }

    $portableRoot = Get-WingetPortableRoot
    $portableExe = Join-Path $portableRoot 'winget.exe'
    if (Test-WingetExecutable -ExePath $portableExe) {
        return [string]$portableExe
    }

    if (Test-Path -LiteralPath $portableRoot) {
        Remove-Item -LiteralPath $portableRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -Path $portableRoot -ItemType Directory -Force | Out-Null

    $tempRoot = Join-Path $env:TEMP 'prodicloud-winget-bootstrap'
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null

    $tempBundleZip = Join-Path $tempRoot 'winget-cli.msixbundle.zip'
    Copy-Item -LiteralPath $BundlePath -Destination $tempBundleZip -Force

    $bundleExtractRoot = Join-Path $tempRoot 'bundle'
    New-Item -Path $bundleExtractRoot -ItemType Directory -Force | Out-Null
    Expand-Archive -Path $tempBundleZip -DestinationPath $bundleExtractRoot -Force

    $x64Msix = Get-ChildItem -Path $bundleExtractRoot -Filter '*x64*.msix' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $x64Msix -or [string]::IsNullOrWhiteSpace([string]$x64Msix.FullName)) {
        throw "winget bundle extraction did not produce an x64 msix package."
    }

    $tempMsixZip = Join-Path $tempRoot 'winget-cli-x64.msix.zip'
    Copy-Item -LiteralPath $x64Msix.FullName -Destination $tempMsixZip -Force
    Expand-Archive -Path $tempMsixZip -DestinationPath $portableRoot -Force

    if (-not (Test-WingetExecutable -ExePath $portableExe)) {
        throw "Portable winget extraction completed, but winget.exe is still not healthy."
    }

    return [string]$portableExe
}

function Get-AppInstallerWingetExecutablePath {
    $packages = @()
    try {
        $packages = @(Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue)
    }
    catch {
        $packages = @()
    }

    if (@($packages).Count -eq 0) {
        try {
            $packages = @(Get-AppxPackage -AllUsers -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue)
        }
        catch {
            $packages = @()
        }
    }

    foreach ($package in @($packages | Sort-Object Version -Descending)) {
        $installLocation = [string]$package.InstallLocation
        if ([string]::IsNullOrWhiteSpace([string]$installLocation)) {
            continue
        }

        $candidate = Join-Path $installLocation 'winget.exe'
        if (Test-WingetExecutable -ExePath $candidate) {
            return [string]$candidate
        }
    }

    return ''
}

function Ensure-WingetBundleDownloaded {
    $cacheRoot = 'C:\ProgramData\prodicloud\cache\winget'
    $bundlePath = Join-Path $cacheRoot 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
    if ((Test-Path -LiteralPath $bundlePath) -and ((Get-Item -LiteralPath $bundlePath -ErrorAction SilentlyContinue).Length -gt 0)) {
        return [string]$bundlePath
    }

    New-Item -Path $cacheRoot -ItemType Directory -Force | Out-Null
    Write-Host "Downloading the official App Installer bundle from https://aka.ms/getwinget for portable extraction..."
    Invoke-WebRequest -UseBasicParsing -Uri 'https://aka.ms/getwinget' -OutFile $bundlePath
    if (-not (Test-Path -LiteralPath $bundlePath)) {
        throw "winget bundle download did not produce the expected file."
    }

    $downloadedItem = Get-Item -LiteralPath $bundlePath -ErrorAction Stop
    if ([int64]$downloadedItem.Length -le 0) {
        throw "winget bundle download produced an empty file."
    }

    return [string]$bundlePath
}

function Resolve-WingetExe {
    $portableCandidate = Join-Path (Get-WingetPortableRoot) 'winget.exe'
    if (Test-WingetExecutable -ExePath $portableCandidate) {
        return [string]$portableCandidate
    }

    $cmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($cmd -and -not [string]::IsNullOrWhiteSpace([string]$cmd.Source)) {
        $cmdPath = [string]$cmd.Source
        if (Test-WingetExecutable -ExePath $cmdPath) {
            return [string]$cmdPath
        }
    }

    $localCandidate = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\winget.exe"
    if (Test-WingetExecutable -ExePath $localCandidate) {
        return [string]$localCandidate
    }

    $appInstallerCandidate = Get-AppInstallerWingetExecutablePath
    if (-not [string]::IsNullOrWhiteSpace([string]$appInstallerCandidate)) {
        return [string]$appInstallerCandidate
    }

    foreach ($bundlePath in @(
        'C:\ProgramData\prodicloud\cache\winget\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle',
        'C:\ProgramData\chocolatey\lib\winget-cli\tools\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
    )) {
        if (-not (Test-Path -LiteralPath $bundlePath)) {
            continue
        }

        $portableExe = Expand-WingetPortableBundle -BundlePath $bundlePath
        if (Test-WingetExecutable -ExePath $portableExe) {
            return [string]$portableExe
        }
    }

    return ""
}

Refresh-SessionPath
$wingetExe = Resolve-WingetExe
$wingetInstalledByBootstrap = $false

if ([string]::IsNullOrWhiteSpace([string]$wingetExe)) {
    $bundlePath = Ensure-WingetBundleDownloaded
    $portableExe = Expand-WingetPortableBundle -BundlePath $bundlePath
    if (Test-WingetExecutable -ExePath $portableExe) {
        $wingetExe = [string]$portableExe
        $wingetInstalledByBootstrap = $true
    }
}
else {
    Write-Host "Existing winget installation is already healthy. Skipping bootstrap download."

    $portableExe = Join-Path (Get-WingetPortableRoot) 'winget.exe'
    if (-not (Test-WingetExecutable -ExePath $portableExe)) {
        try {
            $bundlePath = Ensure-WingetBundleDownloaded
            $portableExe = Expand-WingetPortableBundle -BundlePath $bundlePath
        }
        catch {
            Write-Warning ("Stable portable winget extraction was skipped: {0}" -f $_.Exception.Message)
            $portableExe = ''
        }
    }

    if (Test-WingetExecutable -ExePath $portableExe) {
        $wingetExe = [string]$portableExe
    }
}

if ([string]::IsNullOrWhiteSpace([string]$wingetExe)) {
    throw "winget command is not available after bootstrap."
}

Add-MachinePathEntry -Entry (Split-Path -Path $wingetExe -Parent)
Refresh-SessionPath

Write-Host "Resolved winget executable: $wingetExe"

& $wingetExe --version
if ($LASTEXITCODE -ne 0) {
    throw "winget --version failed with exit code $LASTEXITCODE."
}

Write-Host "Running: winget source list"
& $wingetExe source list
if ($LASTEXITCODE -ne 0) {
    Write-Warning "winget source list failed. Skipping forceful source reset and attempting one bounded source update."
}

Write-Host "Running: winget source update"
& $wingetExe source update
if ($LASTEXITCODE -ne 0) {
    throw "winget source update failed with exit code $LASTEXITCODE. Repair winget sources outside vm-update, then rerun the task."
}
if ($wingetInstalledByBootstrap) {
    Write-Host "winget-bootstrap-installed"
}

Write-Host "winget-ready"
Write-Host "Update task completed: install-winget-tool"

