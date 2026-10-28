$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-vlc-application"

$taskConfig = [ordered]@{
    WingetInstallTimeoutSeconds = 150
    VerificationTimeoutSeconds = 20
    VerificationPollSeconds = 5
    LogTailLineCount = 20
}

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

function Resolve-VlcExe {
    foreach ($candidate in @(
        "C:\Program Files\VideoLAN\VLC\vlc.exe",
        "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe"
    )) {
        if (Test-Path -LiteralPath $candidate) {
            return [string]$candidate
        }
    }

    return ""
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
        [int]$TimeoutSeconds = 120,
        [string]$Label = 'process'
    )

    $logRoot = Join-Path $env:TEMP 'prodicloud-vlc'
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

function Test-VlcInstalled {
    param(
        [switch]$AnnounceWingetListProbe,
        [string]$WingetExe = ''
    )

    $installedExe = Resolve-VlcExe
    if (-not [string]::IsNullOrWhiteSpace([string]$installedExe)) {
        return [pscustomobject]@{
            Installed = $true
            VerificationMode = 'executable'
            Path = [string]$installedExe
        }
    }

    if ($AnnounceWingetListProbe) {
        Write-Host 'Running: winget list --id VideoLAN.VLC'
    }

    if ([string]::IsNullOrWhiteSpace([string]$WingetExe)) {
        return [pscustomobject]@{
            Installed = $false
            VerificationMode = ''
            Path = ''
        }
    }

    $listOutput = & ([string]$WingetExe) list --id VideoLAN.VLC 2>&1
    $listExit = [int]$LASTEXITCODE
    $listText = [string]($listOutput | Out-String)
    if ($listExit -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$listText) -and $listText.ToLowerInvariant().Contains('vlc')) {
        return [pscustomobject]@{
            Installed = $true
            VerificationMode = 'winget-list'
            Path = ''
        }
    }

    return [pscustomobject]@{
        Installed = $false
        VerificationMode = ''
        Path = ''
    }
}

function Wait-ForVlcInstallVerification {
    param(
        [int]$TimeoutSeconds,
        [int]$PollSeconds,
        [string]$WingetExe = ''
    )

    $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Max(5, [int]$TimeoutSeconds))
    $announcedWingetListProbe = $false
    do {
        $probe = Test-VlcInstalled -AnnounceWingetListProbe:(-not $announcedWingetListProbe) -WingetExe $WingetExe
        $announcedWingetListProbe = $true
        if ([bool]$probe.Installed) {
            return $probe
        }

        if ([DateTime]::UtcNow -ge $deadline) {
            break
        }

        Start-Sleep -Seconds ([Math]::Max(1, [int]$PollSeconds))
    } while ($true)

    return [pscustomobject]@{
        Installed = $false
        VerificationMode = ''
        Path = ''
    }
}

Refresh-SessionPath
$wingetExe = Resolve-WingetExe
$existingVlc = Test-VlcInstalled -WingetExe $wingetExe
if ([bool]$existingVlc.Installed) {
    if ([string]::Equals([string]$existingVlc.VerificationMode, 'executable', [System.StringComparison]::OrdinalIgnoreCase) -and -not [string]::IsNullOrWhiteSpace([string]$existingVlc.Path)) {
        Write-Host ("VLC executable already exists: {0}" -f [string]$existingVlc.Path)
    }
    else {
        Write-Host 'VLC is already installed according to winget.'
    }
    Write-Host "install-vlc-application-completed"
    Write-Host "Update task completed: install-vlc-application"
    return
}

if ([string]::IsNullOrWhiteSpace([string]$wingetExe)) {
    throw "winget command is not available."
}

Write-Host "Resolved winget executable: $wingetExe"
Write-Host "Running: winget install --id VideoLAN.VLC --accept-source-agreements --accept-package-agreements --silent --disable-interactivity"
$installResult = Invoke-ProcessWithTimeout `
    -FilePath $wingetExe `
    -ArgumentList @('install', '--id', 'VideoLAN.VLC', '--accept-source-agreements', '--accept-package-agreements', '--silent', '--disable-interactivity') `
    -TimeoutSeconds ([int]$taskConfig.WingetInstallTimeoutSeconds) `
    -Label 'winget-install-vlc-application'
$installExit = [int]$installResult.ExitCode
$needsPostInstallVerification = $false
if ([bool]$installResult.TimedOut) {
    Write-Warning ("winget install VideoLAN.VLC exceeded the bounded wait ({0}s); post-install verification will determine whether the package is usable." -f [int]$taskConfig.WingetInstallTimeoutSeconds)
    $needsPostInstallVerification = $true
}
elseif ($installExit -ne 0 -and $installExit -ne -1978335189) {
    Write-Warning ("winget install VideoLAN.VLC returned exit code {0}; post-install verification will determine whether the package is usable." -f $installExit)
    $needsPostInstallVerification = $true
}

Refresh-SessionPath
$verifiedVlc = Wait-ForVlcInstallVerification -TimeoutSeconds ([int]$taskConfig.VerificationTimeoutSeconds) -PollSeconds ([int]$taskConfig.VerificationPollSeconds) -WingetExe $wingetExe
if (-not [bool]$verifiedVlc.Installed) {
    throw ("VLC install could not be verified within {0}s. stdoutLog={1}; stderrLog={2}" -f [int]$taskConfig.VerificationTimeoutSeconds, [string]$installResult.StdoutLog, [string]$installResult.StderrLog)
}

if ([string]::Equals([string]$verifiedVlc.VerificationMode, 'winget-list', [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Host ("install-vlc-application-verified: winget-list (install-exit={0})" -f $installExit)
}
else {
    if ($needsPostInstallVerification) {
        Write-Host ("install-vlc-application-verified: executable => {0} (install-exit={1})" -f [string]$verifiedVlc.Path, $installExit)
    }
    else {
        Write-Host ("install-vlc-application-verified: executable => {0}" -f [string]$verifiedVlc.Path)
    }
}

$global:LASTEXITCODE = 0
Write-Host "install-vlc-application-completed"
Write-Host "Update task completed: install-vlc-application"

