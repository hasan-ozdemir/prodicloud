$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-anydesk-application"

$taskConfig = [ordered]@{
    WingetInstallTimeoutSeconds = 300
    WingetSourceUpdateTimeoutSeconds = 120
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

    Write-Host "AnyDesk was not found at either managed machine installation path."
    return [pscustomobject]@{
        Installed = $false
        Path = ""
    }
}

function Get-AnyDeskAuthenticodeInfo {
    param([Parameter(Mandatory = $true)][string]$Path)
    $pwshCandidate = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
    $childPowerShell = if (Test-Path -LiteralPath $pwshCandidate -PathType Leaf) { $pwshCandidate } else { Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' }
    if (-not (Test-Path -LiteralPath $childPowerShell -PathType Leaf)) { throw 'Windows PowerShell was not found for isolated AnyDesk Authenticode verification.' }
    $escapedPath = $Path.Replace("'", "''")
    $childScript = @"
`$ErrorActionPreference = 'Stop'
`$signature = Get-AuthenticodeSignature -LiteralPath '$escapedPath' -ErrorAction Stop
`$version = (Get-Item -LiteralPath '$escapedPath' -ErrorAction Stop).VersionInfo
`$signer = if (`$null -ne `$signature.SignerCertificate) { [string]`$signature.SignerCertificate.Subject } else { '' }
[pscustomobject]@{ Status = [string]`$signature.Status; Signer = `$signer; Company = [string]`$version.CompanyName; Product = [string]`$version.ProductName; ProductVersion = [string]`$version.ProductVersion } | ConvertTo-Json -Compress
"@
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))
    $probe = Invoke-ProcessWithTimeout -Label 'verify-anydesk-authenticode' -FilePath $childPowerShell -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand',$encodedCommand) -TimeoutSeconds 30
    if ([bool]$probe.TimedOut -or [int]$probe.ExitCode -ne 0) { throw ("Isolated AnyDesk Authenticode verification failed (exit {0}): {1}" -f [int]$probe.ExitCode,[string]$probe.StderrText) }
    $jsonLine = @([string]$probe.StdoutText -split "`r?`n" | Where-Object { [string]$_ -match '^\s*\{' } | Select-Object -Last 1)
    if ($jsonLine.Count -ne 1) { throw ("Isolated AnyDesk Authenticode verification returned no JSON result. Output: {0}" -f ([string]$probe.StdoutText).Trim()) }
    try { return (ConvertFrom-Json -InputObject ([string]$jsonLine[0]) -ErrorAction Stop) }
    catch { throw ("Isolated AnyDesk Authenticode verification returned invalid JSON: {0}" -f ([string]$jsonLine[0]).Trim()) }
}

function Install-AnyDeskFromVerifiedOfficialDownload {
    param([switch]$UpdateExisting)

    $downloadRoot = ''
    $installerPath = 'C:\Windows\Temp\clagnos-anydesk-verified.exe'
    $installerWasStaged = Test-Path -LiteralPath $installerPath -PathType Leaf
    try {
        if (-not $installerWasStaged) {
            $downloadRoot = Join-Path $env:TEMP ('clagnos-anydesk-official-' + [guid]::NewGuid().ToString('N'))
            [void](New-Item -ItemType Directory -Path $downloadRoot -Force)
            $installerPath = Join-Path $downloadRoot 'AnyDesk.exe'
            Write-Host 'Doing: download the official AnyDesk installer after WinGet rejected a stale catalog hash'
            Invoke-WebRequest -Uri 'https://download.anydesk.com/AnyDesk.exe' -OutFile $installerPath -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop
        }
        else { Write-Host 'Doing: use the locally staged official AnyDesk installer after WinGet rejected a stale catalog hash' }
        $installerInfo = Get-AnyDeskAuthenticodeInfo -Path $installerPath
        if ([string]$installerInfo.Status -ne 'Valid' -or [string]$installerInfo.Signer -notmatch '(?i)O=AnyDesk Software GmbH' -or [string]$installerInfo.Company -ne 'AnyDesk Software GmbH' -or [string]$installerInfo.Product -notmatch '(?i)^AnyDesk$') {
            throw 'The official AnyDesk installer did not pass the expected valid Authenticode publisher and product checks.'
        }
        Write-Host ("Official AnyDesk installer signature verified for product version {0}." -f [string]$installerInfo.ProductVersion)

        if ($UpdateExisting) {
            $currentInstallation = Test-AnyDeskInstalled
            if (-not [bool]$currentInstallation.Installed) { throw 'AnyDesk update requires an existing verified installation.' }
            $currentInfo = Get-AnyDeskAuthenticodeInfo -Path ([string]$currentInstallation.Path)
            if ([string]$currentInfo.Status -ne 'Valid' -or [string]$currentInfo.Signer -notmatch '(?i)O=AnyDesk Software GmbH' -or [string]$currentInfo.Company -ne 'AnyDesk Software GmbH' -or [string]$currentInfo.Product -notmatch '(?i)^AnyDesk$') {
                throw 'The existing AnyDesk executable failed Authenticode verification before update; no vendor installer was run.'
            }
            $currentVersionMatch = [regex]::Match([string]$currentInfo.ProductVersion,'^\d+(?:\.\d+){1,3}')
            $candidateVersionMatch = [regex]::Match([string]$installerInfo.ProductVersion,'^\d+(?:\.\d+){1,3}')
            if (-not $currentVersionMatch.Success -or -not $candidateVersionMatch.Success) { throw 'AnyDesk current and signed installer versions could not be compared safely.' }
            $currentVersion = [version]::Parse([string]$currentVersionMatch.Value)
            $candidateVersion = [version]::Parse([string]$candidateVersionMatch.Value)
            if ($candidateVersion -le $currentVersion) {
                $message = 'AnyDesk is already current at version {0}; no vendor installer was run.' -f [string]$currentInfo.ProductVersion
                Write-Host $message
                return $message
            }
            Write-Host ("Doing: update the verified AnyDesk installation from {0} to signed publisher version {1}" -f [string]$currentInfo.ProductVersion,[string]$installerInfo.ProductVersion)
        }
        $destination = 'C:\Program Files (x86)\AnyDesk'
        $installResult = Invoke-ProcessWithTimeout `
            -FilePath $installerPath `
            -ArgumentList @('--install',('"{0}"' -f $destination),'--start-with-win','--silent','--create-shortcuts') `
            -TimeoutSeconds ([int]$taskConfig.WingetInstallTimeoutSeconds) `
            -Label 'official-signed-installer-anydesk'
        if ([bool]$installResult.TimedOut -or [int]$installResult.ExitCode -ne 0) {
            throw ("The signature-verified official AnyDesk installer failed (exit={0}, timedOut={1})." -f [int]$installResult.ExitCode,[bool]$installResult.TimedOut)
        }
        if ($UpdateExisting) {
            $updatedInstallation = Test-AnyDeskInstalled
            if (-not [bool]$updatedInstallation.Installed) { throw 'The official AnyDesk update finished without a detectable installation.' }
            $updatedInfo = Get-AnyDeskAuthenticodeInfo -Path ([string]$updatedInstallation.Path)
            if ([string]$updatedInfo.Status -ne 'Valid' -or [string]$updatedInfo.Signer -notmatch '(?i)O=AnyDesk Software GmbH' -or [string]$updatedInfo.Company -ne 'AnyDesk Software GmbH' -or [string]$updatedInfo.Product -notmatch '(?i)^AnyDesk$') {
                throw 'The updated AnyDesk executable failed Authenticode verification.'
            }
            $updatedVersionMatch = [regex]::Match([string]$updatedInfo.ProductVersion,'^\d+(?:\.\d+){1,3}')
            if (-not $updatedVersionMatch.Success -or [version]::Parse([string]$updatedVersionMatch.Value) -lt $candidateVersion) {
                throw ("The AnyDesk update did not reach the signed publisher version {0}; observed {1}." -f [string]$installerInfo.ProductVersion,[string]$updatedInfo.ProductVersion)
            }
            return ('Updated AnyDesk to verified publisher version {0}.' -f [string]$updatedInfo.ProductVersion)
        }
    }
    finally {
        if (-not $installerWasStaged -and -not [string]::IsNullOrWhiteSpace([string]$downloadRoot)) {
            if (Test-Path -LiteralPath $installerPath -PathType Leaf) { Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue }
            if (Test-Path -LiteralPath $downloadRoot -PathType Container) { Remove-Item -LiteralPath $downloadRoot -Force -ErrorAction SilentlyContinue }
        }
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
    $existingSignature = Get-AnyDeskAuthenticodeInfo -Path ([string]$existingAnyDesk.Path)
    if ([string]$existingSignature.Status -ne 'Valid' -or [string]$existingSignature.Signer -notmatch '(?i)O=AnyDesk Software GmbH' -or [string]$existingSignature.Company -ne 'AnyDesk Software GmbH' -or [string]$existingSignature.Product -notmatch '(?i)^AnyDesk$') {
        throw 'The existing AnyDesk executable failed its Authenticode publisher or product health check.'
    }
    Write-Host ("Existing AnyDesk executable passed Authenticode verification at version {0}." -f [string]$existingSignature.ProductVersion)
    if ([string]$env:CLAGNOS_PACKAGE_OPERATION_ACTION -eq 'update') {
        $updateMessage = Install-AnyDeskFromVerifiedOfficialDownload -UpdateExisting
        Write-Host $updateMessage
        $global:LASTEXITCODE = 0
        Write-Host 'install-anydesk-application-completed'
        Write-Host 'Update task completed: install-anydesk-application'
        return
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$existingAnyDesk.Path)) {
        Write-Host ("Existing AnyDesk installation is already healthy: {0}" -f [string]$existingAnyDesk.Path)
    }
    else { Write-Host 'Existing AnyDesk installation is already healthy.' }
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
$installTranscript = [string]$installResult.StdoutText + [Environment]::NewLine + [string]$installResult.StderrText
$hashMismatch = ($installTranscript -match '(?i)installer hash does not match|hash mismatch')
if ($hashMismatch) {
    Write-Warning 'WinGet rejected the AnyDesk installer because its downloaded hash did not match the catalog manifest.'
    Write-Host 'Doing: refresh the WinGet source once and retry without bypassing hash verification'
    $sourceUpdate = Invoke-ProcessWithTimeout `
        -FilePath $wingetExe `
        -ArgumentList @('source','update','--disable-interactivity') `
        -TimeoutSeconds ([int]$taskConfig.WingetSourceUpdateTimeoutSeconds) `
        -Label 'winget-source-update-anydesk'
    if (-not [bool]$sourceUpdate.TimedOut -and [int]$sourceUpdate.ExitCode -eq 0) {
        Write-Host 'Doing: retry AnyDesk install against the refreshed WinGet source'
        $installResult = Invoke-ProcessWithTimeout `
            -FilePath $wingetExe `
            -ArgumentList @('install','anydesk.anydesk','--accept-source-agreements','--accept-package-agreements','--silent','--disable-interactivity') `
            -TimeoutSeconds ([int]$taskConfig.WingetInstallTimeoutSeconds) `
            -Label 'winget-install-anydesk-application-retry'
        $installExit = [int]$installResult.ExitCode
        $installTranscript = [string]$installResult.StdoutText + [Environment]::NewLine + [string]$installResult.StderrText
        $hashMismatch = ($installTranscript -match '(?i)installer hash does not match|hash mismatch')
    }
}
$verifiedAnyDesk = Test-AnyDeskInstalled
if (-not [bool]$verifiedAnyDesk.Installed) {
    if (-not $hashMismatch) { Write-Warning 'WinGet did not produce a verified AnyDesk machine install; checking the official signed publisher installer.' }
    Install-AnyDeskFromVerifiedOfficialDownload
    $verifiedAnyDesk = Test-AnyDeskInstalled
}
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
    $failureDetail = if ($hashMismatch) { 'WinGet hash verification still blocked the install after one source refresh; no hash bypass was attempted. ' } else { ' ' }
    throw ("AnyDesk install could not be verified.{0}stdoutLog={1}; stderrLog={2}" -f $failureDetail,[string]$installResult.StdoutLog, [string]$installResult.StderrLog)
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

