$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-anydesk-application"

$taskConfig = [ordered]@{
    WingetInstallTimeoutSeconds = 90
    LogTailLineCount = 20
}

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

function Test-AnyDeskInstalled {
    $anyDeskPathCandidates = @(
        "C:\Program Files (x86)\AnyDesk\AnyDesk.exe",
        "C:\Program Files\AnyDesk\AnyDesk.exe"
    )
    foreach ($candidate in @($anyDeskPathCandidates)) {
        if (Test-Path -LiteralPath $candidate) {
            return [pscustomobject]@{
                Installed = $true
                Path = [string]$candidate
            }
        }
    }

    Write-Host "AnyDesk was not found at either managed installation path; winget install will verify the package directly."
    return [pscustomobject]@{
        Installed = $false
        Path = ""
    }
}

function Get-LogTailText {
    param(
        [string]$Path,
        [int]$LineCount = 20
    )

    if ([string]::IsNullOrWhiteSpace([string]$Path) -or -not (Test-Path -LiteralPath $Path)) {
        return ''
    }

    try {
        $tailLines = @(Get-Content -LiteralPath $Path -Tail $LineCount -ErrorAction Stop)
        if (@($tailLines).Count -eq 0) {
            return ''
        }

        return ([string](($tailLines -join [Environment]::NewLine))).Trim()
    }
    catch {
        return ''
    }
}

function Invoke-ProcessWithTimeout {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList,
        [int]$TimeoutSeconds = 90,
        [string]$Label = 'process'
    )

    $logRoot = Join-Path $env:TEMP 'clagnos-anydesk'
    [void](New-Item -ItemType Directory -Path $logRoot -Force)
    $stamp = Get-Date -Format 'yyyyMMddHHmmss'
    $stdoutLog = Join-Path $logRoot ("{0}-{1}.stdout.log" -f $Label.Replace(' ', '-'), $stamp)
    $stderrLog = Join-Path $logRoot ("{0}-{1}.stderr.log" -f $Label.Replace(' ', '-'), $stamp)
    $process = Start-Process `
        -FilePath $FilePath `
        -ArgumentList $ArgumentList `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutLog `
        -RedirectStandardError $stderrLog `
        -PassThru

    $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) {
        try {
            Stop-Process -Id ([int]$process.Id) -Force -ErrorAction Stop
        }
        catch {
        }
    }

    return [pscustomobject]@{
        TimedOut = [bool]$timedOut
        ExitCode = if ($timedOut) { 124 } else { [int]$process.ExitCode }
        StdoutLog = [string]$stdoutLog
        StderrLog = [string]$stderrLog
        StdoutText = [string](Get-LogTailText -Path $stdoutLog -LineCount ([int]$taskConfig.LogTailLineCount))
        StderrText = [string](Get-LogTailText -Path $stderrLog -LineCount ([int]$taskConfig.LogTailLineCount))
    }
}

Refresh-SessionPath
$wingetExe = Resolve-WingetExe
if ([string]::IsNullOrWhiteSpace([string]$wingetExe)) {
    throw "winget command is not available."
}

Write-Host "Resolved winget executable: $wingetExe"
$existingAnyDesk = Test-AnyDeskInstalled
if ([bool]$existingAnyDesk.Installed) {
    if (-not [string]::IsNullOrWhiteSpace([string]$existingAnyDesk.Path)) {
        Write-Host ("Existing AnyDesk installation is already healthy: {0}" -f [string]$existingAnyDesk.Path)
    }
    else {
        Write-Host "Existing AnyDesk installation is already healthy. Skipping winget install."
    }
    Write-Host "install-anydesk-application-completed"
    Write-Host "Update task completed: install-anydesk-application"
    return
}

Write-Host "Running: winget install anydesk.anydesk --accept-source-agreements --accept-package-agreements --silent --disable-interactivity"
$installResult = Invoke-ProcessWithTimeout `
    -FilePath $wingetExe `
    -ArgumentList @('install', 'anydesk.anydesk', '--accept-source-agreements', '--accept-package-agreements', '--silent', '--disable-interactivity') `
    -TimeoutSeconds ([int]$taskConfig.WingetInstallTimeoutSeconds) `
    -Label 'winget-install-anydesk-application'
$installExit = [int]$installResult.ExitCode
$needsPostInstallVerification = $false
if ([bool]$installResult.TimedOut) {
    Write-Warning ("winget install anydesk.anydesk exceeded the bounded wait ({0}s); post-install verification will determine whether the package is usable." -f [int]$taskConfig.WingetInstallTimeoutSeconds)
    $needsPostInstallVerification = $true
}
elseif ($installExit -ne 0 -and $installExit -ne -1978335189) {
    Write-Warning ("winget install anydesk.anydesk returned exit code {0}; post-install verification will determine whether the package is usable." -f $installExit)
    $needsPostInstallVerification = $true
}

$verifiedAnyDesk = Test-AnyDeskInstalled
if (-not [bool]$verifiedAnyDesk.Installed) {
    throw ("AnyDesk install could not be verified. stdoutLog={0}; stderrLog={1}" -f [string]$installResult.StdoutLog, [string]$installResult.StderrLog)
}

if ([string]::IsNullOrWhiteSpace([string]$verifiedAnyDesk.Path)) {
    Write-Host ("install-anydesk-application-verified: winget-list (install-exit={0})" -f $installExit)
}
else {
    Write-Host ("install-anydesk-application-verified: executable => {0} (install-exit={1})" -f [string]$verifiedAnyDesk.Path, $installExit)
}

$global:LASTEXITCODE = 0
Write-Host "install-anydesk-application-completed"
Write-Host "Update task completed: install-anydesk-application"

