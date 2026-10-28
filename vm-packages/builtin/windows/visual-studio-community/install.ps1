$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-vs2022community-application"

$taskConfig = [ordered]@{
    ChocoExe = "$env:ProgramData\chocolatey\bin\choco.exe"
    PackageId = 'visualstudio2022community'
    DevenvPath = 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\devenv.exe'
    VsWhereCandidates = @(
        'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe',
        'C:\Program Files\Microsoft Visual Studio\Installer\vswhere.exe'
    )
    DevenvWaitTimeoutSeconds = 90
    DevenvWaitPollSeconds = 5
}

Import-Module 'C:\Windows\Temp\prodicloud-session-environment.psm1' -Force -DisableNameChecking

function Refresh-SessionPath {
    Refresh-ProdicloudSessionPath | Out-Null
}

function Resolve-VsWhereExe {
    foreach ($candidate in @($taskConfig.VsWhereCandidates)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate) -and (Test-Path -LiteralPath $candidate)) {
            return [string]$candidate
        }
    }

    return ''
}

function Resolve-DevenvPath {
    if (Test-Path -LiteralPath ([string]$taskConfig.DevenvPath)) {
        return [string]$taskConfig.DevenvPath
    }

    $vsWhereExe = Resolve-VsWhereExe
    if (-not [string]::IsNullOrWhiteSpace([string]$vsWhereExe)) {
        $vsWhereOutput = & $vsWhereExe -latest -products Microsoft.VisualStudio.Product.Community -property installationPath 2>$null
        $installationPath = [string]($vsWhereOutput | Out-String)
        if (-not [string]::IsNullOrWhiteSpace([string]$installationPath)) {
            $installationPath = $installationPath.Trim()
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$installationPath)) {
            $candidate = Join-Path $installationPath 'Common7\IDE\devenv.exe'
            if (Test-Path -LiteralPath $candidate) {
                return [string]$candidate
            }
        }
    }

    foreach ($candidate in @(
        'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\devenv.exe',
        'C:\Program Files (x86)\Microsoft Visual Studio\2022\Community\Common7\IDE\devenv.exe'
    )) {
        if (Test-Path -LiteralPath $candidate) {
            return [string]$candidate
        }
    }

    return ''
}

function Test-ChocoPackageListed {
    Write-Host ("Running: choco list --local-only {0} --exact --limit-output" -f [string]$taskConfig.PackageId)
    $listOutput = & ([string]$taskConfig.ChocoExe) list --local-only ([string]$taskConfig.PackageId) --exact --limit-output
    $listExit = [int]$LASTEXITCODE
    $listText = [string]($listOutput | Out-String)
    return ($listExit -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$listText) -and $listText.ToLowerInvariant().Contains(([string]$taskConfig.PackageId).ToLowerInvariant()))
}

function Wait-DevenvReady {
    $deadline = [DateTime]::UtcNow.AddSeconds([int]$taskConfig.DevenvWaitTimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        Refresh-SessionPath
        $resolvedPath = Resolve-DevenvPath
        if (-not [string]::IsNullOrWhiteSpace([string]$resolvedPath)) {
            return [string]$resolvedPath
        }

        Start-Sleep -Seconds ([int]$taskConfig.DevenvWaitPollSeconds)
    }

    return (Resolve-DevenvPath)
}

Refresh-SessionPath

$existingDevenvPath = Resolve-DevenvPath
if (-not [string]::IsNullOrWhiteSpace([string]$existingDevenvPath)) {
    Write-Host ("Visual Studio 2022 Community executable already exists: {0}" -f [string]$existingDevenvPath)
    Write-Host "install-vs2022community-application-completed"
    Write-Host "Update task completed: install-vs2022community-application"
    return
}

if (-not (Test-Path -LiteralPath ([string]$taskConfig.ChocoExe))) {
    throw "choco was not found."
}

Write-Host ("Running: choco install {0} -y --no-progress --ignore-detected-reboot" -f [string]$taskConfig.PackageId)
& ([string]$taskConfig.ChocoExe) install ([string]$taskConfig.PackageId) -y --no-progress --ignore-detected-reboot
$installExit = [int]$LASTEXITCODE

Refresh-SessionPath
$resolvedDevenvPath = Wait-DevenvReady
$packageListed = $false
if ($installExit -notin @(0, 2, 1641, 3010)) {
    $packageListed = Test-ChocoPackageListed
    if (-not [string]::IsNullOrWhiteSpace([string]$resolvedDevenvPath)) {
        Write-Host ("vs2022-step-readback: tolerated-choco-exit={0}; devenv={1}" -f $installExit, [string]$resolvedDevenvPath)
    }
    elseif ($packageListed) {
        throw ("choco install {0} returned exit code {1} and the package is listed locally, but devenv.exe was still not found." -f [string]$taskConfig.PackageId, $installExit)
    }
    else {
        throw ("choco install {0} failed with exit code {1}." -f [string]$taskConfig.PackageId, $installExit)
    }
}

if ([string]::IsNullOrWhiteSpace([string]$resolvedDevenvPath)) {
    throw ("choco install {0} failed with exit code {1}." -f [string]$taskConfig.PackageId, $installExit)
}

Write-Host "install-vs2022community-application-completed"
Write-Host "Update task completed: install-vs2022community-application"

