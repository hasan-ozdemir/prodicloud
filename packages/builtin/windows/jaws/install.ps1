$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-jaws-application"

$taskConfig = [ordered]@{
    PortableWingetPath = "C:\ProgramData\clagnos\tools\winget-x64\winget.exe"
    PackageId = 'FreedomScientific.JAWS.2025'
    AcceptableWingetExitCodes = @(0, -1978335189, -2147024894)
    JawsExeCandidates = @(
        "C:\Program Files\Freedom Scientific\JAWS\2025\jfw.exe",
        "C:\Program Files (x86)\Freedom Scientific\JAWS\2025\jfw.exe"
    )
    JawsRegistryRoots = @(
        'HKLM:\Software\Freedom Scientific\JAWS\2025',
        'HKLM:\Software\WOW6432Node\Freedom Scientific\JAWS\2025'
    )
    WingetSourceTimeoutSeconds = 45
    InstallVerifyTimeoutSeconds = 90
    InstallVerifyPollSeconds = 5
}

Import-Module 'C:\Windows\Temp\clagnos-session-environment.psm1' -Force -DisableNameChecking

function Refresh-SessionPath {
    Refresh-ClagnosSessionPath | Out-Null
}

function Resolve-WingetExe {
    $portableCandidate = [string]$taskConfig.PortableWingetPath
    if (Test-Path -LiteralPath $portableCandidate) {
        return [string]$portableCandidate
    }

    $cmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($cmd -and -not [string]::IsNullOrWhiteSpace([string]$cmd.Source)) {
        return [string]$cmd.Source
    }

    return ""
}

function Resolve-JawsRootFromRegistry {
    foreach ($registryPath in @($taskConfig.JawsRegistryRoots)) {
        if (-not (Test-Path -LiteralPath $registryPath)) {
            continue
        }

        $targetPath = [string](Get-ItemProperty -LiteralPath $registryPath -Name 'Target' -ErrorAction SilentlyContinue).Target
        if ([string]::IsNullOrWhiteSpace([string]$targetPath)) {
            continue
        }

        $normalizedPath = $targetPath.Trim().TrimEnd('\')
        if (Test-Path -LiteralPath $normalizedPath) {
            return [string]$normalizedPath
        }
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

function Resolve-JawsExe {
    $registryRoot = Resolve-JawsRootFromRegistry
    if (-not [string]::IsNullOrWhiteSpace([string]$registryRoot)) {
        $registryCandidate = Resolve-ExecutableUnderDirectory -RootPath $registryRoot -ExecutableName 'jfw.exe'
        if (-not [string]::IsNullOrWhiteSpace([string]$registryCandidate)) {
            return [string]$registryCandidate
        }
    }

    foreach ($candidate in @($taskConfig.JawsExeCandidates)) {
        if (Test-Path -LiteralPath $candidate) {
            return [string]$candidate
        }
    }

    return ""
}

function Invoke-WingetCommand {
    param(
        [string]$WingetExe,
        [string[]]$Arguments
    )

    & $WingetExe @Arguments | ForEach-Object {
        if ($null -ne $_) {
            Write-Host ([string]$_)
        }
    }
    return [int]$LASTEXITCODE
}

function Ensure-WingetSourcesReady {
    param([string]$WingetExe)

    Write-Host "Running: winget source list"
    $listExit = Invoke-WingetCommand -WingetExe $WingetExe -Arguments @('source', 'list')
    if ($listExit -eq 0) {
        return
    }

    Write-Host ("jaws-step-repair: winget-source-list-exit={0}" -f $listExit)
    Write-Host "Running: winget source update"
    $updateExit = Invoke-WingetCommand -WingetExe $WingetExe -Arguments @('source', 'update')
    if ($updateExit -ne 0) {
        throw ("winget source update failed with exit code {0}." -f $updateExit)
    }

    Write-Host "Running: winget source list"
    $secondListExit = Invoke-WingetCommand -WingetExe $WingetExe -Arguments @('source', 'list')
    if ($secondListExit -ne 0) {
        throw ("winget source list failed with exit code {0} after bounded repair." -f $secondListExit)
    }
}

function Wait-JawsInstallVerified {
    $deadline = [DateTime]::UtcNow.AddSeconds([int]$taskConfig.InstallVerifyTimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        Refresh-SessionPath
        $resolvedExe = Resolve-JawsExe
        if (-not [string]::IsNullOrWhiteSpace([string]$resolvedExe)) {
            return [string]$resolvedExe
        }

        Start-Sleep -Seconds ([int]$taskConfig.InstallVerifyPollSeconds)
    }

    return (Resolve-JawsExe)
}

function Test-JawsPackageListed {
    param(
        [string]$WingetExe,
        [string]$PackageId
    )

    Write-Host ("Running: winget list --id {0} --exact" -f $PackageId)
    $listOutput = & $WingetExe list --id $PackageId --exact
    $listExit = [int]$LASTEXITCODE
    $listText = [string]($listOutput | Out-String)
    return ($listExit -eq 0 -and -not [string]::IsNullOrWhiteSpace($listText) -and $listText.ToLowerInvariant().Contains("jaws"))
}

function Test-JawsInstallRegistered {
    $resolvedExe = Resolve-JawsExe
    if (-not [string]::IsNullOrWhiteSpace([string]$resolvedExe)) {
        return $true
    }

    $registryRoot = Resolve-JawsRootFromRegistry
    if (-not [string]::IsNullOrWhiteSpace([string]$registryRoot) -and (Test-Path -LiteralPath $registryRoot)) {
        return $true
    }

    return $false
}

Refresh-SessionPath
$existingExe = Resolve-JawsExe
if (-not [string]::IsNullOrWhiteSpace([string]$existingExe)) {
    Write-Host ("Existing JAWS installation is already healthy. Skipping winget install. exe={0}" -f $existingExe)
    Write-Host "install-jaws-application-completed"
    Write-Host "Update task completed: install-jaws-application"
    return
}

$wingetExe = Resolve-WingetExe
if ([string]::IsNullOrWhiteSpace([string]$wingetExe)) {
    throw "winget command is not available."
}

$packageId = [string]$taskConfig.PackageId
Write-Host "Resolved winget executable: $wingetExe"
Ensure-WingetSourcesReady -WingetExe $wingetExe

$finalInstallExit = 0
$installedExe = ""
foreach ($attempt in 1..2) {
    Write-Host ("Running: winget install --id {0} --exact --accept-source-agreements --accept-package-agreements --silent --disable-interactivity" -f $packageId)
    $finalInstallExit = Invoke-WingetCommand -WingetExe $wingetExe -Arguments @('install', '--id', $packageId, '--exact', '--accept-source-agreements', '--accept-package-agreements', '--silent', '--disable-interactivity')

    $installedExe = Wait-JawsInstallVerified
    if (-not [string]::IsNullOrWhiteSpace([string]$installedExe)) {
        break
    }

    if (@($taskConfig.AcceptableWingetExitCodes) -contains $finalInstallExit) {
        if ((Test-JawsPackageListed -WingetExe $wingetExe -PackageId $packageId) -or (Test-JawsInstallRegistered)) {
            Write-Host ("jaws-step-readback: tolerated-winget-exit={0}" -f $finalInstallExit)
            Start-Sleep -Seconds ([int]$taskConfig.InstallVerifyPollSeconds)
            $installedExe = Wait-JawsInstallVerified
            if (-not [string]::IsNullOrWhiteSpace([string]$installedExe)) {
                break
            }
        }
    }

    if ($attempt -lt 2) {
        Write-Host ("jaws-step-retry: winget-exit={0}; attempt={1}" -f $finalInstallExit, $attempt)
        Ensure-WingetSourcesReady -WingetExe $wingetExe
        Start-Sleep -Seconds 5
    }
}

if ([string]::IsNullOrWhiteSpace([string]$installedExe)) {
    if ((Test-JawsPackageListed -WingetExe $wingetExe -PackageId $packageId) -or (Test-JawsInstallRegistered)) {
        throw "JAWS install did not materialize a launchable jfw.exe after winget reported the package."
    }

    throw ("winget install {0} failed with exit code {1}." -f $packageId, $finalInstallExit)
}

Write-Host "install-jaws-application-completed"
Write-Host "Update task completed: install-jaws-application"
