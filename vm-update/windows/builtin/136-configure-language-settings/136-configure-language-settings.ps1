$ErrorActionPreference = 'Stop'
Write-Host 'Update task started: configure-language-settings'

$taskName = '136-configure-language-settings'
$managerUser = '__VM_ADMIN_USER__'
$managerPassword = '__VM_ADMIN_PASS__'
$assistantUser = '__ASSISTANT_USER__'
$assistantPassword = '__ASSISTANT_PASS__'
$helperPath = 'C:\Windows\Temp\clagnos-interactive-session-helper.ps1'

$primaryLanguage = '__WIN_DEFAULT_UI_LANGUAGE__'
$additionalLanguages = @('__WIN_ADDITIONAL_LANGUAGES__' -split ',' | ForEach-Object { ([string]$_).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
$secondaryLanguage = if (@($additionalLanguages).Count -gt 0) { [string]$additionalLanguages[0] } else { 'tr-TR' }
$script:LanguagePolicyChanged = $true
$script:LanguagePolicyMarkerPath = Join-Path $env:ProgramData 'clagnos\state\language-policy.json'

if (-not (Test-Path -LiteralPath $helperPath)) {
    throw ("Interactive session helper was not found: {0}" -f $helperPath)
}

. $helperPath

function Write-StateIntent {
    param([string]$Message)

    if (-not [string]::IsNullOrWhiteSpace([string]$Message)) {
        Write-Host ([string]$Message) -ForegroundColor DarkCyan
    }
}

function Write-StateStart {
    param([string]$Message)

    if (-not [string]::IsNullOrWhiteSpace([string]$Message)) {
        Write-Host ([string]$Message) -ForegroundColor Cyan
    }
}

function Write-StateSuccess {
    param([string]$Message)

    if (-not [string]::IsNullOrWhiteSpace([string]$Message)) {
        Write-Host ([string]$Message) -ForegroundColor Green
    }
}

function Write-StateSkip {
    param([string]$Message)

    if (-not [string]::IsNullOrWhiteSpace([string]$Message)) {
        Write-Host ([string]$Message) -ForegroundColor DarkCyan
    }
}

function Get-InstalledLanguageSafe {
    param([string]$LanguageTag)

    if ([string]::IsNullOrWhiteSpace([string]$LanguageTag)) {
        return @()
    }

    if (-not (Get-Command Get-InstalledLanguage -ErrorAction SilentlyContinue)) {
        return @()
    }

    return @(
        Get-InstalledLanguage -Language $LanguageTag -ErrorAction SilentlyContinue |
            Where-Object { $_ -ne $null }
    )
}

function Get-LanguageFeatureSummary {
    param([AllowNull()]$InstalledLanguage)

    if ($null -eq $InstalledLanguage) {
        return 'details not reported by Windows'
    }

    $parts = New-Object 'System.Collections.Generic.List[string]'
    foreach ($propertyName in @('LanguageFeatures', 'InstalledLanguageFeatures', 'Features')) {
        if ($InstalledLanguage.PSObject.Properties.Match($propertyName).Count -lt 1) {
            continue
        }

        $value = $InstalledLanguage.$propertyName
        if ($null -eq $value) {
            continue
        }

        foreach ($entry in @($value)) {
            $text = [string]$entry
            if ([string]::IsNullOrWhiteSpace([string]$text)) {
                continue
            }

            if (-not $parts.Contains($text)) {
                $parts.Add($text) | Out-Null
            }
        }
    }

    if ($parts.Count -eq 0) {
        foreach ($propertyName in @('BasicTyping', 'Handwriting', 'Ocr', 'Speech', 'TextToSpeech')) {
            if ($InstalledLanguage.PSObject.Properties.Match($propertyName).Count -lt 1) {
                continue
            }

            $parts.Add(("{0}={1}" -f $propertyName, [string]$InstalledLanguage.$propertyName)) | Out-Null
        }
    }

    if ($parts.Count -eq 0) {
        return 'details not reported by Windows'
    }

    return (@($parts.ToArray()) -join ', ')
}

function Get-SystemPreferredUiLanguageSafe {
    if (Get-Command Get-SystemPreferredUILanguage -ErrorAction SilentlyContinue) {
        try {
            return [string](Get-SystemPreferredUILanguage)
        }
        catch {
        }
    }

    return ''
}

function Get-LanguageCapabilityCatalog {
    param([string]$LanguageTag)

    $languageTagText = [string]$LanguageTag
    return [ordered]@{
        'Language.Basic'        = ("Language.Basic~~~{0}~0.0.1.0" -f $languageTagText)
        'Language.Handwriting'  = ("Language.Handwriting~~~{0}~0.0.1.0" -f $languageTagText)
        'Language.OCR'          = ("Language.OCR~~~{0}~0.0.1.0" -f $languageTagText)
        'Language.Speech'       = ("Language.Speech~~~{0}~0.0.1.0" -f $languageTagText)
        'Language.TextToSpeech' = ("Language.TextToSpeech~~~{0}~0.0.1.0" -f $languageTagText)
    }
}

function Get-LanguageCapabilityStateMap {
    param([string]$LanguageTag)

    $catalog = Get-LanguageCapabilityCatalog -LanguageTag $LanguageTag
    $stateMap = [ordered]@{}
    $availableCapabilities = @()
    if (Get-Command Get-WindowsCapability -ErrorAction SilentlyContinue) {
        $capabilityFilter = ("Language.*~~~{0}~*" -f [string]$LanguageTag)
        try {
            $availableCapabilities = @(
                Get-WindowsCapability -Online -Name $capabilityFilter -ErrorAction Stop |
                    Where-Object { $_ -ne $null -and -not [string]::IsNullOrWhiteSpace([string]$_.Name) }
            )
        }
        catch { $availableCapabilities = @() }
    }

    foreach ($capabilityName in @($catalog.Keys)) {
        $capabilityIdentity = [string]$catalog[$capabilityName]
        $capability = $availableCapabilities | Where-Object { [string]$_.Name -eq $capabilityIdentity } | Select-Object -First 1
        $stateMap[$capabilityName] = if ($null -eq $capability) { 'Unavailable' } else { [string]$capability.State }
    }

    return [pscustomobject]$stateMap
}

function Convert-LanguageCapabilityStateMapToSummary {
    param([AllowNull()]$StateMap)

    if ($null -eq $StateMap) {
        return 'unavailable'
    }

    $parts = New-Object 'System.Collections.Generic.List[string]'
    foreach ($capabilityName in @('Language.Basic', 'Language.Handwriting', 'Language.OCR', 'Language.Speech', 'Language.TextToSpeech')) {
        $stateValue = 'Unavailable'
        if ($StateMap.PSObject.Properties.Match($capabilityName).Count -gt 0) {
            $candidate = [string]$StateMap.$capabilityName
            if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) {
                $stateValue = $candidate
            }
        }

        $parts.Add(("{0}={1}" -f [string]$capabilityName, [string]$stateValue)) | Out-Null
    }

    return (@($parts.ToArray()) -join ', ')
}

function Test-LanguageCapabilityStateSatisfied {
    param([AllowNull()]$StateMap)

    if ($null -eq $StateMap) {
        return $false
    }

    $basicState = ''
    if ($StateMap.PSObject.Properties.Match('Language.Basic').Count -gt 0) {
        $basicState = [string]$StateMap.'Language.Basic'
    }

    if ($basicState -ne 'Installed') {
        return $false
    }

    foreach ($capabilityName in @('Language.Handwriting', 'Language.OCR', 'Language.Speech', 'Language.TextToSpeech')) {
        $capabilityState = 'Unavailable'
        if ($StateMap.PSObject.Properties.Match($capabilityName).Count -gt 0) {
            $candidate = [string]$StateMap.$capabilityName
            if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) {
                $capabilityState = $candidate
            }
        }

        if ($capabilityState -notin @('Installed', 'NotPresent', 'Unavailable')) {
            return $false
        }
    }

    return $true
}

$script:LanguageSourceIsoUrl = 'https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26100.1.240331-1435.ge_release_amd64fre_CLIENT_LOF_PACKAGES_OEM.iso'
$script:LanguageSourceIsoBytes = [int64]6251841536
$script:LanguageSourceRoot = 'C:\ProgramData\clagnos\cache\language-source'
$script:LanguageSourceIsoPath = Join-Path $script:LanguageSourceRoot 'windows-11-24h2-25h2-language-features-x64.iso'
$script:LanguageOperationDeadlineUtc = [DateTime]::UtcNow.AddMinutes(12.5)

function Get-LanguageRemainingSeconds {
    return [int][Math]::Floor(($script:LanguageOperationDeadlineUtc - [DateTime]::UtcNow).TotalSeconds)
}

function Assert-LanguageOperationTimeRemaining {
    param([string]$Phase)

    if ((Get-LanguageRemainingSeconds) -le 0) {
        throw ("The Turkish language task reached its 13-minute operation budget during '{0}'." -f $Phase)
    }
}

function Clear-LanguageSourceCache {
    if (Test-Path -LiteralPath $script:LanguageSourceIsoPath -PathType Leaf) {
        Remove-Item -LiteralPath $script:LanguageSourceIsoPath -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $script:LanguageSourceRoot -PathType Container) {
        foreach ($pattern in @('curl-language-source-*.out','curl-language-source-*.err','dism-*.out','dism-*.err')) {
            Get-ChildItem -LiteralPath $script:LanguageSourceRoot -Filter $pattern -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        }
        $remaining = @(Get-ChildItem -LiteralPath $script:LanguageSourceRoot -Force -ErrorAction SilentlyContinue)
        if ($remaining.Count -eq 0) { Remove-Item -LiteralPath $script:LanguageSourceRoot -Force -ErrorAction SilentlyContinue }
    }
    Write-Host 'language-source-cache-cleaned => temporary Microsoft language ISO and task output files were removed.'
}

function Get-LanguageSourceIso {
    Assert-LanguageOperationTimeRemaining -Phase 'source validation'
    if (Test-Path -LiteralPath $script:LanguageSourceIsoPath -PathType Leaf) {
        $existingSize = [int64](Get-Item -LiteralPath $script:LanguageSourceIsoPath -ErrorAction Stop).Length
        if ($existingSize -eq $script:LanguageSourceIsoBytes) {
            Write-StateSkip ("Reuse the verified-size Microsoft language source ISO cache ({0:N2} GiB)." -f ($existingSize / 1GB))
            return $script:LanguageSourceIsoPath
        }
        if ($existingSize -gt $script:LanguageSourceIsoBytes) {
            Remove-Item -LiteralPath $script:LanguageSourceIsoPath -Force -ErrorAction Stop
        }
    }

    $systemDrive = [string]$env:SystemDrive
    $systemDisk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $systemDrive) -ErrorAction Stop
    $freeBytes = [int64]$systemDisk.FreeSpace
    if ($freeBytes -lt [int64]($script:LanguageSourceIsoBytes + 2GB)) {
        throw ("The target needs at least {0:N2} GiB free on {1} to cache the official language source ISO and service the image; {2:N2} GiB is available." -f (($script:LanguageSourceIsoBytes + 2GB) / 1GB),$systemDrive,($freeBytes / 1GB))
    }

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($null -eq $curl -or [string]::IsNullOrWhiteSpace([string]$curl.Source)) {
        throw 'Windows curl.exe is unavailable; cannot perform the bounded Microsoft language-source download.'
    }
    if (-not (Test-Path -LiteralPath $script:LanguageSourceRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $script:LanguageSourceRoot -Force -ErrorAction Stop | Out-Null
    }

    $downloadDeadlineUtc = [DateTime]::UtcNow.AddSeconds([Math]::Min(600,(Get-LanguageRemainingSeconds) - 120))
    $lastFailure = ''
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        Assert-LanguageOperationTimeRemaining -Phase 'Microsoft ISO download'
        $stdoutPath = Join-Path $script:LanguageSourceRoot ("curl-language-source-{0}.out" -f $attempt)
        $stderrPath = Join-Path $script:LanguageSourceRoot ("curl-language-source-{0}.err" -f $attempt)
        Remove-Item -LiteralPath $stdoutPath,$stderrPath -Force -ErrorAction SilentlyContinue
        $arguments = @(
            '--fail','--location','--silent','--show-error',
            '--speed-limit','4096','--speed-time','60',
            '--continue-at','-','--output',$script:LanguageSourceIsoPath,
            $script:LanguageSourceIsoUrl
        )
        Write-Host ("Doing: download the official 24H2/25H2 language ISO from Microsoft (attempt {0}/2; maximum 600s)." -f $attempt) -ForegroundColor Cyan
        $process = Start-Process -FilePath ([string]$curl.Source) -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -ErrorAction Stop
        $lastLength = if (Test-Path -LiteralPath $script:LanguageSourceIsoPath -PathType Leaf) { [int64](Get-Item -LiteralPath $script:LanguageSourceIsoPath).Length } else { 0 }
        $lastGrowthUtc = [DateTime]::UtcNow
        $nextHeartbeatUtc = [DateTime]::UtcNow.AddSeconds(15)
        $stalled = $false
        try {
            while (-not $process.HasExited) {
                $now = [DateTime]::UtcNow
                if ($now -ge $downloadDeadlineUtc) {
                    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                    throw 'The official language source ISO exceeded its bounded download time.'
                }
                $currentLength = if (Test-Path -LiteralPath $script:LanguageSourceIsoPath -PathType Leaf) { [int64](Get-Item -LiteralPath $script:LanguageSourceIsoPath).Length } else { 0 }
                if ($currentLength -gt $lastLength) {
                    $lastLength = $currentLength
                    $lastGrowthUtc = $now
                }
                if (($now - $lastGrowthUtc).TotalSeconds -ge 60) {
                    $stalled = $true
                    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                    break
                }
                if ($now -ge $nextHeartbeatUtc) {
                    $elapsed = [int]($now - $process.StartTime.ToUniversalTime()).TotalSeconds
                    $rate = if ($elapsed -gt 0) { ($currentLength / 1MB) / $elapsed } else { 0 }
                    Write-Host ("Doing: Microsoft language ISO download is active ({0:N0}/{1:N0} MiB; {2:N1} MiB/s; attempt {3}/2)." -f ($currentLength / 1MB),($script:LanguageSourceIsoBytes / 1MB),$rate,$attempt) -ForegroundColor DarkCyan
                    $nextHeartbeatUtc = $now.AddSeconds(15)
                }
                Start-Sleep -Seconds 2
                $process.Refresh()
            }
            if (-not $stalled) {
                $process.WaitForExit()
                $process.Refresh()
                if ([int]$process.ExitCode -eq 0) {
                    $downloadedSize = if (Test-Path -LiteralPath $script:LanguageSourceIsoPath -PathType Leaf) { [int64](Get-Item -LiteralPath $script:LanguageSourceIsoPath).Length } else { 0 }
                    if ($downloadedSize -eq $script:LanguageSourceIsoBytes) {
                        Write-StateSuccess ("Microsoft language source ISO download completed ({0:N0} MiB)." -f ($downloadedSize / 1MB))
                        return $script:LanguageSourceIsoPath
                    }
                    $lastFailure = ("curl completed but downloaded {0:N0} of {1:N0} bytes." -f $downloadedSize,$script:LanguageSourceIsoBytes)
                }
                else {
                    $lastFailure = if (Test-Path -LiteralPath $stderrPath -PathType Leaf) { [string](Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue) } else { ("curl exited with code {0}." -f [int]$process.ExitCode) }
                }
            }
            else {
                $lastFailure = 'No download bytes arrived for 60 seconds.'
            }
        }
        finally {
            if ($null -ne $process -and -not $process.HasExited) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
        }
        if ($attempt -lt 2 -and [DateTime]::UtcNow.AddSeconds(30) -lt $downloadDeadlineUtc) {
            Write-Host ("Doing: resume the Microsoft language ISO once after download inactivity or a transport error ({0})." -f $lastFailure.Trim()) -ForegroundColor Yellow
            continue
        }
        throw ("The Microsoft language source ISO download failed after {0} bounded attempt(s): {1}" -f $attempt,$lastFailure.Trim())
    }
    throw 'The Microsoft language source ISO download did not complete.'
}

function Invoke-LanguageDismProcess {
    param(
        [string]$Phase,
        [string]$Arguments,
        [int]$MaximumSeconds = 180
    )

    Assert-LanguageOperationTimeRemaining -Phase $Phase
    $remaining = Get-LanguageRemainingSeconds
    $timeoutSeconds = [Math]::Min([int]$MaximumSeconds,$remaining)
    if ($timeoutSeconds -lt 5) { throw ("Less than five seconds remain before the language-task deadline at '{0}'." -f $Phase) }
    $dismPath = Join-Path $env:windir 'System32\dism.exe'
    $safePhase = [regex]::Replace($Phase,'[^A-Za-z0-9-]','-')
    $stdoutPath = Join-Path $script:LanguageSourceRoot ("dism-{0}.out" -f $safePhase)
    $stderrPath = Join-Path $script:LanguageSourceRoot ("dism-{0}.err" -f $safePhase)
    Remove-Item -LiteralPath $stdoutPath,$stderrPath -Force -ErrorAction SilentlyContinue
    Write-Host ("Doing: {0} with bounded DISM servicing (timeout {1}s)." -f $Phase,$timeoutSeconds) -ForegroundColor Cyan
    $process = Start-Process -FilePath $dismPath -ArgumentList $Arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -ErrorAction Stop
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $nextHeartbeatSeconds = 15
    try {
        while (-not $process.HasExited) {
            if ($watch.Elapsed.TotalSeconds -ge $timeoutSeconds) {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                throw ("DISM phase '{0}' exceeded its {1}s limit." -f $Phase,$timeoutSeconds)
            }
            if ([int]$watch.Elapsed.TotalSeconds -ge $nextHeartbeatSeconds) {
                Write-Host ("Doing: {0} is still running ({1}s elapsed)." -f $Phase,[int]$watch.Elapsed.TotalSeconds) -ForegroundColor DarkCyan
                $nextHeartbeatSeconds += 15
            }
            Start-Sleep -Seconds 2
            $process.Refresh()
        }
        $process.WaitForExit()
        $process.Refresh()
        $exitCode = [int]$process.ExitCode
        $outputText = @(
            foreach ($path in @($stdoutPath,$stderrPath)) {
                if (Test-Path -LiteralPath $path -PathType Leaf) { Get-Content -LiteralPath $path -Tail 40 -ErrorAction SilentlyContinue }
            }
        ) -join "`n"
        if ($exitCode -notin @(0,3010,1641)) {
            throw ("DISM phase '{0}' failed with exit code {1}. {2}" -f $Phase,$exitCode,$outputText.Trim())
        }
        if ($exitCode -in @(3010,1641)) { return $true }
        return $false
    }
    finally {
        $watch.Stop()
        if ($null -ne $process -and -not $process.HasExited) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
    }
}

function Install-LanguageFromMicrosoftIso {
    param([string]$LanguageTag)

    $windowsVersion = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
    $build = [string]$windowsVersion.CurrentBuildNumber
    if ($build -notin @('26100','26200')) {
        throw ("The pinned Microsoft language ISO supports Windows 11 24H2/25H2 builds 26100 and 26200; this target reports build '{0}'." -f $build)
    }
    if ([string]$env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
        throw ("The pinned Microsoft language ISO is x64; this target reports architecture '{0}'." -f [string]$env:PROCESSOR_ARCHITECTURE)
    }

    $isoPath = Get-LanguageSourceIso
    $mountedHere = $false
    try {
        $diskImage = Get-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
        if ($null -eq $diskImage -or -not [bool]$diskImage.Attached) {
            Write-Host 'Doing: mount the verified Microsoft language source ISO read-only.' -ForegroundColor Cyan
            Mount-DiskImage -ImagePath $isoPath -StorageType ISO -Access ReadOnly -ErrorAction Stop | Out-Null
            $mountedHere = $true
        }
        $volume = Get-DiskImage -ImagePath $isoPath -ErrorAction Stop | Get-Volume -ErrorAction Stop | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.DriveLetter) } | Select-Object -First 1
        if ($null -eq $volume) { throw 'Windows mounted the language ISO but did not expose a drive letter.' }
        $contentRoot = Join-Path ([string]$volume.DriveLetter + ':\') 'LanguagesAndOptionalFeatures'
        if (-not (Test-Path -LiteralPath $contentRoot -PathType Container)) {
            throw ("The Microsoft language ISO is missing its expected content folder: {0}" -f $contentRoot)
        }
        $languageCab = Get-ChildItem -LiteralPath $contentRoot -Filter ("Microsoft-Windows-Client-Language-Pack_x64_{0}.cab" -f $LanguageTag.ToLowerInvariant()) -File -Recurse -ErrorAction Stop | Select-Object -First 1
        $basicCab = Get-ChildItem -LiteralPath $contentRoot -Filter ("Microsoft-Windows-LanguageFeatures-Basic-{0}-Package~*.cab" -f $LanguageTag) -File -Recurse -ErrorAction Stop | Select-Object -First 1
        if ($null -eq $languageCab) { throw ("The Microsoft language ISO does not contain the {0} x64 display-language CAB." -f $LanguageTag) }
        if ($null -eq $basicCab) { throw ("The Microsoft language ISO does not contain the {0} Basic typing capability CAB." -f $LanguageTag) }

        $installedRows = @(Get-InstalledLanguageSafe -LanguageTag $LanguageTag)
        if (@($installedRows).Count -eq 0) {
            $quotedCab = '"{0}"' -f [string]$languageCab.FullName
            $arguments = '/English /Online /Add-Package /PackagePath:{0} /NoRestart' -f $quotedCab
            if (Invoke-LanguageDismProcess -Phase ("install {0} display language CAB" -f $LanguageTag) -Arguments $arguments -MaximumSeconds 180) { $script:LanguageDismRestartRequired = $true }
        }

        $basicState = @(Get-WindowsCapability -Online -Name ("Language.Basic~~~{0}~0.0.1.0" -f $LanguageTag) -ErrorAction Stop | Select-Object -First 1)
        if ($basicState.Count -eq 0 -or [string]$basicState[0].State -notin @('Installed','InstallPending')) {
            $quotedSource = '"{0}"' -f $contentRoot
            $arguments = '/English /Online /Add-Capability /CapabilityName:Language.Basic~~~{0}~0.0.1.0 /Source:{1} /LimitAccess /NoRestart' -f $LanguageTag,$quotedSource
            if (Invoke-LanguageDismProcess -Phase ("install {0} Basic typing capability" -f $LanguageTag) -Arguments $arguments -MaximumSeconds 180) { $script:LanguageDismRestartRequired = $true }
        }
    }
    finally {
        if ($mountedHere) {
            Write-Host 'Doing: dismount the Microsoft language source ISO.' -ForegroundColor Cyan
            Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue | Out-Null
        }
    }
}

function Invoke-LanguageInteractiveAutomation {
    param(
        [string]$InteractiveTaskName,
        [string]$RunAsUser,
        [string]$RunAsPassword,
        [string]$WorkerScriptText,
        [string]$LanguageTag,
        [int]$WaitTimeoutSeconds = 180
    )

    $paths = Get-ClagnosInteractivePaths -TaskName $InteractiveTaskName
    Ensure-ClagnosDirectory -Path $paths.RootPath

    $staleProcessIds = @(Stop-ClagnosInteractiveWorkerProcesses -WorkerPath $paths.WorkerPath)
    if (@($staleProcessIds).Count -gt 0) {
        Write-Host ("Stopped stale interactive worker process(es) for '{0}': {1}" -f [string]$paths.TaskName, ((@($staleProcessIds) | ForEach-Object { [string]$_ }) -join ', ')) -ForegroundColor DarkCyan
    }

    Remove-Item -LiteralPath $paths.ResultPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $paths.WorkerPath -Force -ErrorAction SilentlyContinue
    [System.IO.File]::WriteAllText($paths.WorkerPath, [string]$WorkerScriptText, (New-Object System.Text.UTF8Encoding($false)))

    try {
        Write-Host ("Interactive task '{0}' will run for {1} using service-account." -f [string]$paths.TaskName, [string]$RunAsUser) -ForegroundColor DarkCyan
        Register-ClagnosInteractiveScheduledTask -TaskName $paths.ScheduledTaskName -RunAsUser $RunAsUser -WorkerPath $paths.WorkerPath -RunAsPassword $RunAsPassword -RunAsMode 'password'
        Start-ClagnosInteractiveScheduledTask -TaskName $paths.ScheduledTaskName
        Write-Host ("Running interactive task '{0}'..." -f [string]$paths.TaskName) -ForegroundColor Cyan

        $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Max(30, [int]$WaitTimeoutSeconds))
        $startTime = [DateTime]::UtcNow
        $nextHeartbeatUtc = $startTime.AddSeconds(15)
        $satisfiedPollCount = 0
        while ([DateTime]::UtcNow -lt $deadline) {
            if (Test-Path -LiteralPath $paths.ResultPath) {
                $fileInfo = Get-Item -LiteralPath $paths.ResultPath -ErrorAction SilentlyContinue
                if ($null -ne $fileInfo -and [int64]$fileInfo.Length -gt 0) {
                    return (Read-ClagnosJsonFile -Path $paths.ResultPath)
                }
            }

            $capabilityState = Get-LanguageCapabilityStateMap -LanguageTag $LanguageTag
            if (Test-LanguageCapabilityStateSatisfied -StateMap $capabilityState) {
                $satisfiedPollCount++
                if ($satisfiedPollCount -ge 3) {
                    $capabilitySummary = Convert-LanguageCapabilityStateMapToSummary -StateMap $capabilityState
                    Write-Host ("Interactive task '{0}' is still running, but language capability state is already satisfied for {1}. Continuing with the installed state." -f [string]$paths.TaskName, [string]$LanguageTag) -ForegroundColor DarkCyan
                    return [pscustomobject]@{
                        Success = $true
                        Summary = 'Language components installed.'
                        Details = @(
                            'reboot-required=true',
                            ("language-capabilities={0}" -f [string]$capabilitySummary),
                            'interactive-worker-short-circuited=true'
                        )
                    }
                }
            }
            else {
                $satisfiedPollCount = 0
            }

            if ([DateTime]::UtcNow -ge $nextHeartbeatUtc) {
                $elapsedSeconds = [Math]::Round(([DateTime]::UtcNow - $startTime).TotalSeconds, 0)
                $snapshot = Get-ClagnosInteractiveScheduledTaskSnapshot -TaskName $paths.ScheduledTaskName
                if ($null -eq $snapshot) {
                    Write-Host ("Waiting for interactive task '{0}'... elapsed={1}s; state=not-found" -f [string]$paths.TaskName, [int]$elapsedSeconds) -ForegroundColor DarkCyan
                }
                else {
                    $stateLabel = Get-ClagnosInteractiveScheduledTaskStateLabel -State ([int]$snapshot.State)
                    Write-Host ("Waiting for interactive task '{0}'... elapsed={1}s; state={2}; last-task-result={3}" -f [string]$paths.TaskName, [int]$elapsedSeconds, [string]$stateLabel, [int]$snapshot.LastTaskResult) -ForegroundColor DarkCyan
                }

                $nextHeartbeatUtc = [DateTime]::UtcNow.AddSeconds(15)
            }

            Start-Sleep -Seconds 2
        }

        $snapshot = Get-ClagnosInteractiveScheduledTaskSnapshot -TaskName $paths.ScheduledTaskName
        if ($null -ne $snapshot -and [int]$snapshot.State -eq 4 -and [int]$snapshot.LastTaskResult -eq 267009) {
            $capabilityState = Get-LanguageCapabilityStateMap -LanguageTag $LanguageTag
            $capabilitySummary = Convert-LanguageCapabilityStateMapToSummary -StateMap $capabilityState
            Write-Host ("Interactive task '{0}' is still running in the background for {1}; accepting the queued install and continuing with restart-required state." -f [string]$paths.TaskName, [string]$LanguageTag) -ForegroundColor DarkCyan
            return [pscustomobject]@{
                Success = $true
                Summary = 'Language components were queued successfully and require restart.'
                Details = @(
                    'reboot-required=true',
                    ("language-capabilities={0}" -f [string]$capabilitySummary),
                    'interactive-worker-queued=true',
                    ("interactive-worker-state={0}" -f [int]$snapshot.State),
                    ("interactive-worker-last-task-result={0}" -f [int]$snapshot.LastTaskResult)
                )
            }
        }

        $capabilityState = Get-LanguageCapabilityStateMap -LanguageTag $LanguageTag
        if (Test-LanguageCapabilityStateSatisfied -StateMap $capabilityState) {
            $capabilitySummary = Convert-LanguageCapabilityStateMapToSummary -StateMap $capabilityState
            Write-Host ("Interactive task '{0}' timed out without a result file, but language capability state is already satisfied for {1}. Continuing with the installed state." -f [string]$paths.TaskName, [string]$LanguageTag) -ForegroundColor DarkCyan
            return [pscustomobject]@{
                Success = $true
                Summary = 'Language components installed.'
                Details = @(
                    'reboot-required=true',
                    ("language-capabilities={0}" -f [string]$capabilitySummary),
                    'interactive-worker-short-circuited=true',
                    'interactive-worker-timeout-recovered=true'
                )
            }
        }

        if ($null -eq $snapshot) {
            throw ("Interactive worker timed out without a result file: {0}" -f $paths.ResultPath)
        }

        throw ("Interactive worker timed out without a result file: state={0}; last-task-result={1}; last-run-time={2}" -f [int]$snapshot.State, [int]$snapshot.LastTaskResult, [string]$snapshot.LastRunTime)
    }
    finally {
        try {
            Remove-ClagnosInteractiveScheduledTask -TaskName $paths.ScheduledTaskName
        }
        catch {
            Write-Host ("interactive-task-cleanup-info: {0}" -f $_.Exception.Message) -ForegroundColor DarkCyan
        }
        $stoppedProcessIds = @(Stop-ClagnosInteractiveWorkerProcesses -WorkerPath $paths.WorkerPath)
        if (@($stoppedProcessIds).Count -gt 0) {
            Write-Host ("Stopped lingering interactive worker process(es) for '{0}': {1}" -f [string]$paths.TaskName, ((@($stoppedProcessIds) | ForEach-Object { [string]$_ }) -join ', ')) -ForegroundColor DarkCyan
        }
        Remove-Item -LiteralPath $paths.WorkerPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $paths.ResultPath -Force -ErrorAction SilentlyContinue
    }
}

function Install-LanguageComponents {
    param([string]$LanguageTag,[string]$DisplayName)

    $capabilityState = Get-LanguageCapabilityStateMap -LanguageTag $LanguageTag
    $capabilitySummary = Convert-LanguageCapabilityStateMapToSummary -StateMap $capabilityState
    $basicState = if ($capabilityState.PSObject.Properties.Match('Language.Basic').Count -gt 0) { [string]$capabilityState.'Language.Basic' } else { 'Unavailable' }
    $installedRows = @(Get-InstalledLanguageSafe -LanguageTag $LanguageTag)
    if (@($installedRows).Count -gt 0 -and $basicState -eq 'Installed' -and (Test-LanguageCapabilityStateSatisfied -StateMap $capabilityState)) {
        Write-StateSuccess ("Language pack {0} is already installed." -f $LanguageTag)
        Write-Host ("language-capabilities-current => {0} => {1}" -f $LanguageTag,$capabilitySummary)
        Clear-LanguageSourceCache
        return [pscustomobject]@{ LanguageTag=$LanguageTag; RebootRequired=$false; CapabilitySummary=$capabilitySummary; InstalledLanguagePresent=$true }
    }

    $displayLanguageAlreadyInstalled = @($installedRows).Count -gt 0
    if ($displayLanguageAlreadyInstalled) {
        Write-StateIntent ("The {0} display language pack is already registered; install only the missing required Basic typing capability." -f $DisplayName)
    }
    else {
        Write-StateIntent ("Install the {0} display language pack and required Basic typing capability from Microsoft's matching Windows 11 language ISO; optional OCR, speech, and handwriting features are skipped." -f $DisplayName)
    }
    $script:LanguageDismRestartRequired = $false
    Install-LanguageFromMicrosoftIso -LanguageTag $LanguageTag
    $rebootRequired = [bool]$script:LanguageDismRestartRequired
    $verifyDeadline = [DateTime]::UtcNow.AddSeconds([Math]::Min(45,[Math]::Max(1,(Get-LanguageRemainingSeconds))))
    do {
        $capabilityState = Get-LanguageCapabilityStateMap -LanguageTag $LanguageTag
        $capabilitySummary = Convert-LanguageCapabilityStateMapToSummary -StateMap $capabilityState
        $basicState = if ($capabilityState.PSObject.Properties.Match('Language.Basic').Count -gt 0) { [string]$capabilityState.'Language.Basic' } else { 'Unavailable' }
        $installedRows = @(Get-InstalledLanguageSafe -LanguageTag $LanguageTag)
        if ((@($installedRows).Count -gt 0 -or $rebootRequired) -and $basicState -in @('Installed','InstallPending')) { break }
        Write-Host ("Doing: wait for Windows to register the {0} language components; current state: {1}" -f $LanguageTag,$capabilitySummary) -ForegroundColor DarkCyan
        Start-Sleep -Seconds 5
    } while ([DateTime]::UtcNow -lt $verifyDeadline)

    if ($basicState -eq 'InstallPending' -or $capabilitySummary -match '(?i)InstallPending' -or $rebootRequired) {
        $rebootRequired = $true
        Write-Host ("language-components-pending-restart => {0} => {1}" -f $LanguageTag,$capabilitySummary) -ForegroundColor Yellow
    }
    elseif ($basicState -ne 'Installed' -or @($installedRows).Count -lt 1) {
        throw ("DISM completed, but Windows did not verify the {0} display language and Basic capability. Capability state: {1}" -f $LanguageTag,$capabilitySummary)
    }
    Write-Host ("language-capabilities => {0} => {1}" -f $LanguageTag,$capabilitySummary)
    if ($rebootRequired) {
        Write-Host ("language-info: {0} package servicing is staged and will be verified after the one allowed restart." -f $DisplayName) -ForegroundColor Yellow
    }
    else {
        Write-StateSuccess ("Language pack {0} was installed on the target VM." -f $DisplayName)
    }
    return [pscustomobject]@{
        LanguageTag=[string]$LanguageTag
        RebootRequired=[bool]$rebootRequired
        CapabilitySummary=[string]$capabilitySummary
        InstalledLanguagePresent=(@($installedRows).Count -ge 1 -or $basicState -eq 'Installed')
    }
}

function Invoke-UserLanguageConfiguration {
    param(
        [string]$UserName,
        [string]$UserPassword
    )

    function Get-CurrentUserLanguageState {
        $languageTags = @()
        try {
            $languageTags = @(
                Get-WinUserLanguageList |
                    ForEach-Object { [string]$_.LanguageTag } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
            )
        }
        catch {
            $languageTags = @()
        }

        $uiOverride = ''
        try {
            $uiOverride = [string](Get-WinUILanguageOverride)
        }
        catch {
            $uiOverride = ''
        }

        return [pscustomobject]@{
            LanguageTags = @($languageTags)
            UiOverride = [string]$uiOverride
        }
    }

    function Test-CurrentUserLanguageConfigurationSatisfied {
        $state = Get-CurrentUserLanguageState
        $languageTags = @($state.LanguageTags)
        if (@($languageTags).Count -lt 1) {
            return $false
        }

        $currentUserUiLanguage = if (-not [string]::IsNullOrWhiteSpace([string]$state.UiOverride)) { [string]$state.UiOverride } else { [string]$languageTags[0] }
        if (-not $script:LanguagePolicyChanged -and -not [string]::IsNullOrWhiteSpace([string]$currentUserUiLanguage)) { return $true }
        $primaryMatches = [string]::Equals([string]$languageTags[0], $primaryLanguage, [System.StringComparison]::OrdinalIgnoreCase)
        $secondaryMatches = (@($languageTags) | Where-Object { [string]::Equals([string]$_, $secondaryLanguage, [System.StringComparison]::OrdinalIgnoreCase) } | Measure-Object).Count -ge 1
        $overrideMatches = (
            [string]::IsNullOrWhiteSpace([string]$state.UiOverride) -or
            [string]::Equals([string]$state.UiOverride, $primaryLanguage, [System.StringComparison]::OrdinalIgnoreCase)
        )

        return ($primaryMatches -and $secondaryMatches -and $overrideMatches)
    }

    function Test-CurrentUserLanguageConfigurationProvisionallySatisfied {
        $state = Get-CurrentUserLanguageState
        $languageTags = @($state.LanguageTags)
        if (@($languageTags).Count -lt 1) {
            return $false
        }

        $currentUserUiLanguage = if (-not [string]::IsNullOrWhiteSpace([string]$state.UiOverride)) { [string]$state.UiOverride } else { [string]$languageTags[0] }
        if (-not $script:LanguagePolicyChanged -and -not [string]::IsNullOrWhiteSpace([string]$currentUserUiLanguage)) { return $true }
        $primaryMatches = [string]::Equals([string]$languageTags[0], $primaryLanguage, [System.StringComparison]::OrdinalIgnoreCase)
        $secondaryMatches = (@($languageTags) | Where-Object { [string]::Equals([string]$_, $secondaryLanguage, [System.StringComparison]::OrdinalIgnoreCase) } | Measure-Object).Count -ge 1
        return ($primaryMatches -and $secondaryMatches)
    }

    function Wait-CurrentUserLanguageConfigurationState {
        param([int]$TimeoutSeconds = 10)

        $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Max(2, [int]$TimeoutSeconds))
        while ([DateTime]::UtcNow -lt $deadline) {
            if (Test-CurrentUserLanguageConfigurationSatisfied) {
                return 'verified'
            }
            if (Test-CurrentUserLanguageConfigurationProvisionallySatisfied) {
                return 'provisional'
            }

            Start-Sleep -Seconds 1
        }

        return 'pending'
    }

    function Set-CurrentUserLanguageConfigurationDirect {
        $languageList = New-WinUserLanguageList $primaryLanguage
        if (-not [string]::Equals([string]$primaryLanguage,[string]$secondaryLanguage,[System.StringComparison]::OrdinalIgnoreCase)) {
            $secondaryEntries = New-WinUserLanguageList $secondaryLanguage
            if ($null -ne $secondaryEntries -and $secondaryEntries.Count -gt 0) { [void]$languageList.Add($secondaryEntries[0]) }
        }

        Set-WinUserLanguageList -LanguageList $languageList -Force -WarningAction SilentlyContinue
        Set-WinUILanguageOverride -Language $primaryLanguage -WarningAction SilentlyContinue
        Write-Host 'language-user-info: language changes will take effect after the next restart or sign-in.'
        $directApplyState = Wait-CurrentUserLanguageConfigurationState -TimeoutSeconds 10
        if ([string]::Equals([string]$directApplyState, 'verified', [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
        if ([string]::Equals([string]$directApplyState, 'provisional', [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Host ("language-user-info: direct apply for '{0}' is queued and will finish after the next restart or sign-in." -f [string]$UserName) -ForegroundColor DarkCyan
            return $true
        }

        return $false
    }

    Write-StateIntent ("Language settings for user '{0}' will be configured." -f [string]$UserName)
    Write-StateStart ("Configuring language settings for user '{0}'..." -f [string]$UserName)

    if ([string]::Equals([string]$env:USERNAME, [string]$UserName, [System.StringComparison]::OrdinalIgnoreCase)) {
        if (Test-CurrentUserLanguageConfigurationSatisfied) {
            Write-StateSuccess ("Language settings for user '{0}' were already configured." -f [string]$UserName)
            return
        }

        try {
            if (Set-CurrentUserLanguageConfigurationDirect) {
                Write-StateSuccess ("Language settings for user '{0}' were configured successfully." -f [string]$UserName)
                return
            }

            Write-Host ("Current-user language state for '{0}' did not verify after direct apply; falling back to interactive automation." -f [string]$UserName) -ForegroundColor DarkCyan
        }
        catch {
            Write-Host ("Current-user direct language apply for '{0}' failed; falling back to interactive automation. {1}" -f [string]$UserName, [string]$_.Exception.Message) -ForegroundColor DarkCyan
        }
    }

    $interactiveTaskName = ('{0}-{1}' -f $taskName, [string]$UserName)
    $paths = Get-ClagnosInteractivePaths -TaskName $interactiveTaskName
    $workerScript = @'
$ErrorActionPreference = "Stop"
$helperPath = "__HELPER_PATH__"
$resultPath = "__RESULT_PATH__"
$taskName = "__TASK_NAME__"
$primaryLanguage = "__PRIMARY_LANGUAGE__"
$secondaryLanguage = "__SECONDARY_LANGUAGE__"
$languagePolicyChanged = "__LANGUAGE_POLICY_CHANGED__" -eq 'true'

. $helperPath

try {
    if (-not $languagePolicyChanged) {
        $currentTags = @(Get-WinUserLanguageList | ForEach-Object { [string]$_.LanguageTag } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        $currentOverride = ''
        try { $currentOverride = [string](Get-WinUILanguageOverride) } catch { }
        $currentUi = if (-not [string]::IsNullOrWhiteSpace($currentOverride)) { $currentOverride } elseif ($currentTags.Count -gt 0) { [string]$currentTags[0] } else { '' }
        if (-not [string]::IsNullOrWhiteSpace([string]$currentUi)) {
            $currentSummary = @(
                Get-WinUserLanguageList | ForEach-Object {
                    $tips = if ($_.PSObject.Properties.Match('InputMethodTips').Count -gt 0 -and $null -ne $_.InputMethodTips) { (@($_.InputMethodTips) -join ',') } else { '' }
                    ("{0}:{1}" -f [string]$_.LanguageTag,$tips)
                }
            ) -join '; '
            Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $true -Summary 'Existing Windows language selection preserved.' -Details @(("ui-language={0}" -f $currentUi),("language-list={0}" -f $currentSummary))
            return
        }
    }
    $languageList = New-WinUserLanguageList $primaryLanguage
    if (-not [string]::Equals([string]$primaryLanguage,[string]$secondaryLanguage,[System.StringComparison]::OrdinalIgnoreCase)) {
        $secondaryEntries = New-WinUserLanguageList $secondaryLanguage
        if ($null -ne $secondaryEntries -and $secondaryEntries.Count -gt 0) { [void]$languageList.Add($secondaryEntries[0]) }
    }

    Set-WinUserLanguageList -LanguageList $languageList -Force -WarningAction SilentlyContinue
    Set-WinUILanguageOverride -Language $primaryLanguage -WarningAction SilentlyContinue
    Write-Host 'language-user-info: language changes will take effect after the next restart or sign-in.'

    $languageSummary = @(
        Get-WinUserLanguageList |
            ForEach-Object {
                $tips = if ($_.PSObject.Properties.Match('InputMethodTips').Count -gt 0 -and $null -ne $_.InputMethodTips) { (@($_.InputMethodTips) -join ',') } else { '' }
                ("{0}:{1}" -f [string]$_.LanguageTag, $tips)
            }
    ) -join '; '
    $cultureName = ''
    try {
        $cultureName = [string](Get-Culture).Name
    }
    catch {
    }

    $details = @(
        ("language-list={0}" -f [string]$languageSummary),
        ("culture={0}" -f [string]$cultureName)
    )
    Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $true -Summary 'Language settings applied.' -Details $details
}
catch {
    Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $false -Summary 'Language settings failed.' -Details @([string]$_.Exception.Message)
    throw
}
'@

    $workerScript = $workerScript.Replace('__HELPER_PATH__', $helperPath)
    $workerScript = $workerScript.Replace('__RESULT_PATH__', [string]$paths.ResultPath)
    $workerScript = $workerScript.Replace('__TASK_NAME__', $interactiveTaskName)
    $workerScript = $workerScript.Replace('__PRIMARY_LANGUAGE__', $primaryLanguage)
    $workerScript = $workerScript.Replace('__SECONDARY_LANGUAGE__', $secondaryLanguage)
    $workerScript = $workerScript.Replace('__LANGUAGE_POLICY_CHANGED__',([bool]$script:LanguagePolicyChanged).ToString().ToLowerInvariant())

    $null = Invoke-ClagnosInteractiveDesktopAutomation `
        -TaskName $interactiveTaskName `
        -RunAsUser $UserName `
        -RunAsPassword $UserPassword `
        -WorkerScriptText $workerScript `
        -WaitTimeoutSeconds 60 `
        -HeartbeatSeconds 10

    Write-StateSuccess ("Language settings for user '{0}' were configured successfully." -f [string]$UserName)
}

function Get-LanguagePolicyMarker {
    if (-not (Test-Path -LiteralPath $script:LanguagePolicyMarkerPath -PathType Leaf)) { return $null }
    try { return (ConvertFrom-JsonCompat -InputObject ([string](Get-Content -LiteralPath $script:LanguagePolicyMarkerPath -Raw -ErrorAction Stop))) }
    catch { return $null }
}

function Save-LanguagePolicyMarker {
    $directory = Split-Path -Path $script:LanguagePolicyMarkerPath -Parent
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $marker = [ordered]@{ schemaVersion = 1; defaultUiLanguage = [string]$primaryLanguage; additionalLanguages = @($additionalLanguages); appliedAtUtc = [DateTime]::UtcNow.ToString('o',[System.Globalization.CultureInfo]::InvariantCulture) }
    $temporaryPath = $script:LanguagePolicyMarkerPath + '.tmp'
    [System.IO.File]::WriteAllText($temporaryPath,(ConvertTo-Json -InputObject $marker -Depth 4),[System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryPath -Destination $script:LanguagePolicyMarkerPath -Force -ErrorAction Stop
}

function Set-SystemLanguageState {
    $systemPreferredUiBefore = Get-SystemPreferredUiLanguageSafe
    $previousPolicy = Get-LanguagePolicyMarker
    if ($null -eq $previousPolicy) {
        $script:LanguagePolicyChanged = -not [string]::Equals([string]$systemPreferredUiBefore,$primaryLanguage,[System.StringComparison]::OrdinalIgnoreCase)
    }
    else {
        $script:LanguagePolicyChanged = -not [string]::Equals([string]$previousPolicy.defaultUiLanguage,$primaryLanguage,[System.StringComparison]::OrdinalIgnoreCase)
    }
    Write-StateIntent ('Provision additional language components on the target and apply the configured UI language only when the VC language policy changed.')
    Write-StateStart ('Configuring target Windows language components...')

    $componentResults = [ordered]@{}
    foreach ($languageTag in @($additionalLanguages | Select-Object -Unique)) {
        $displayName = if ([string]::Equals([string]$languageTag,'tr-TR',[System.StringComparison]::OrdinalIgnoreCase)) { 'Turkish (Turkey)' } else { [string]$languageTag }
        $componentResults[[string]$languageTag] = Install-LanguageComponents -LanguageTag ([string]$languageTag) -DisplayName $displayName
    }

    if ($script:LanguagePolicyChanged) {
        Write-StateStart ("Applying requested system preferred UI language '{0}'..." -f $primaryLanguage)
        Set-SystemPreferredUILanguage -Language $primaryLanguage
        $systemPreferredUiAfter = Get-SystemPreferredUiLanguageSafe
        if (-not [string]::Equals([string]$systemPreferredUiAfter,$primaryLanguage,[System.StringComparison]::OrdinalIgnoreCase)) {
            throw ("Unable to apply configured system preferred UI language '{0}'." -f $primaryLanguage)
        }
    }
    else {
        $systemPreferredUiAfter = $systemPreferredUiBefore
        Write-StateSkip ("The configured default UI language '{0}' is unchanged; preserve the current Windows language selection." -f $primaryLanguage)
    }

    Write-StateSuccess('Target Windows language components and system language policy were verified.')
    return [pscustomobject]@{
        RebootRequired = (@($componentResults.Values | Where-Object { [bool]$_.RebootRequired }).Count -gt 0 -or
            -not [string]::Equals([string]$systemPreferredUiBefore,[string]$systemPreferredUiAfter,[System.StringComparison]::OrdinalIgnoreCase))
        ComponentResults = $componentResults
    }
}

function Assert-LanguageStateReadyForRestart {
    foreach ($languageTag in @($additionalLanguages | Select-Object -Unique)) {
        $capabilityState = Get-LanguageCapabilityStateMap -LanguageTag $languageTag
        $capabilitySummary = Convert-LanguageCapabilityStateMapToSummary -StateMap $capabilityState
        Write-Host ("language-capabilities-final => {0} => {1}" -f [string]$languageTag,[string]$capabilitySummary)
        if (-not (Test-LanguageCapabilityStateSatisfied -StateMap $capabilityState)) {
            throw ("Language capability verification failed for '{0}'; the expected installed state was not present after the servicing restart. {1}" -f [string]$languageTag,[string]$capabilitySummary)
        }
    }
}
$rebootRequired = $false

try {
    if (-not (Get-Command Set-SystemPreferredUILanguage -ErrorAction SilentlyContinue)) {
        throw 'Set-SystemPreferredUILanguage is not available on this image.'
    }

    $pendingServicingPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
        'C:\Windows\WinSxS\pending.xml'
    )
    $pendingServicing = @($pendingServicingPaths | Where-Object { Test-Path -LiteralPath $_ })
    if ($pendingServicing.Count -gt 0) {
        Write-Host ("language-servicing-restart-required => {0}" -f ($pendingServicing -join ',')) -ForegroundColor Yellow
        Write-Host 'TASK_REBOOT_REQUIRED:configure-language-settings'
        return
    }

    $systemLanguageState = Set-SystemLanguageState
    if ([bool]$systemLanguageState.RebootRequired) {
        $rebootRequired = $true
    }

    Write-StateStart("Applying language list and UI override for '{0}'..." -f $managerUser)
    Invoke-UserLanguageConfiguration -UserName $managerUser -UserPassword $managerPassword
    Write-StateStart("Applying language list and UI override for '{0}'..." -f $assistantUser)
    Invoke-UserLanguageConfiguration -UserName $assistantUser -UserPassword $assistantPassword
    Save-LanguagePolicyMarker

    Write-StateStart('Collecting final language verification output...')
    Write-Host ("language-targets => system-ui={0}; configured-default={1}; additional-languages={2}; policy-changed={3}" -f (Get-SystemPreferredUiLanguageSafe),$primaryLanguage,(@($additionalLanguages) -join ','),[bool]$script:LanguagePolicyChanged)
    Write-Host ("installed-language => {0} => {1}" -f $primaryLanguage, (Get-LanguageFeatureSummary -InstalledLanguage (@(Get-InstalledLanguageSafe -LanguageTag $primaryLanguage) | Select-Object -First 1)))
    Write-Host ("installed-language => {0} => {1}" -f $secondaryLanguage, (Get-LanguageFeatureSummary -InstalledLanguage (@(Get-InstalledLanguageSafe -LanguageTag $secondaryLanguage) | Select-Object -First 1)))
    Assert-LanguageStateReadyForRestart

    if (-not $rebootRequired) { Clear-LanguageSourceCache }

    if ($rebootRequired) {
        Write-Host 'language-step-ok: restart-required-to-finalize'
        Write-Host 'TASK_REBOOT_REQUIRED:configure-language-settings'
    }
    else {
        Write-Host 'language-step-ok: already-current; no restart required'
    }

    Write-Host 'configure-language-settings-completed'
    Write-Host 'Update task completed: configure-language-settings'
}
catch {
    throw
}
