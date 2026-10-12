$ErrorActionPreference = 'Stop'
Write-Host 'Update task started: configure-language-settings'

$taskName = '136-configure-language-settings'
$managerUser = '__VM_ADMIN_USER__'
$managerPassword = '__VM_ADMIN_PASS__'
$assistantUser = '__ASSISTANT_USER__'
$assistantPassword = '__ASSISTANT_PASS__'
$helperPath = 'C:\Windows\Temp\clagnos-interactive-session-helper.ps1'

$primaryLanguage = 'en-US'
$secondaryLanguage = 'tr-TR'

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
        $availableCapabilities = @(
            Get-WindowsCapability -Online -ErrorAction SilentlyContinue |
                Where-Object { $_ -ne $null -and -not [string]::IsNullOrWhiteSpace([string]$_.Name) }
        )
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

    if ($basicState -notin @('Installed', 'InstallPending')) {
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

        if ($capabilityState -notin @('Installed', 'InstallPending', 'Unavailable')) {
            return $false
        }
    }

    return $true
}

function Test-LanguageCapabilityDeferredVerificationAllowed {
    param([AllowNull()]$StateMap)

    if ($null -eq $StateMap) {
        return $false
    }

    foreach ($capabilityName in @('Language.Basic', 'Language.Handwriting', 'Language.OCR', 'Language.Speech', 'Language.TextToSpeech')) {
        $capabilityState = 'Unavailable'
        if ($StateMap.PSObject.Properties.Match($capabilityName).Count -gt 0) {
            $candidate = [string]$StateMap.$capabilityName
            if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) {
                $capabilityState = $candidate
            }
        }

        if ($capabilityState -notin @('NotPresent', 'Unavailable', 'InstallPending', 'Installed')) {
            return $false
        }
    }

    return $true
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
    param(
        [string]$LanguageTag,
        [string]$DisplayName
    )

    Write-StateIntent ("Language components for {0} will be installed." -f [string]$DisplayName)
    Write-StateStart ("Installing language components for {0}..." -f [string]$DisplayName)

    $interactiveTaskName = ('{0}-install-{1}' -f $taskName, (($LanguageTag -replace '[^a-zA-Z0-9]+', '-').Trim('-')))
    $paths = Get-ClagnosInteractivePaths -TaskName $interactiveTaskName
    $workerScript = @'
$ErrorActionPreference = "Stop"
$helperPath = "__HELPER_PATH__"
$resultPath = "__RESULT_PATH__"
$taskName = "__TASK_NAME__"
$languageTag = "__LANGUAGE_TAG__"

. $helperPath

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
    $availableCapabilities = @(
        Get-WindowsCapability -Online -ErrorAction SilentlyContinue |
            Where-Object { $_ -ne $null -and -not [string]::IsNullOrWhiteSpace([string]$_.Name) }
    )

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

    if ($basicState -notin @('Installed', 'InstallPending')) {
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

        if ($capabilityState -notin @('Installed', 'InstallPending', 'Unavailable')) {
            return $false
        }
    }

    return $true
}

try {
    $installResult = Install-Language -Language $languageTag -ErrorAction Stop
    $rebootRequired = $false
    foreach ($propertyName in @('RestartNeeded', 'RebootRequired', 'RequiresRestart')) {
        if ($null -ne $installResult -and $installResult.PSObject.Properties.Match($propertyName).Count -gt 0 -and [bool]$installResult.$propertyName) {
            $rebootRequired = $true
            break
        }
    }

    $capabilityState = Get-LanguageCapabilityStateMap -LanguageTag $languageTag
    $capabilitySummary = Convert-LanguageCapabilityStateMapToSummary -StateMap $capabilityState
    if (-not (Test-LanguageCapabilityStateSatisfied -StateMap $capabilityState)) {
        throw ("Unable to verify installed language components for '{0}' inside the system worker. {1}" -f [string]$languageTag, [string]$capabilitySummary)
    }

    if ($capabilitySummary -match '(?i)InstallPending') {
        $rebootRequired = $true
    }

    Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $true -Summary 'Language components installed.' -Details @(
        ("reboot-required={0}" -f [bool]$rebootRequired),
        ("language-capabilities={0}" -f [string]$capabilitySummary)
    )
}
catch {
    $exceptionMessage = [string]$_.Exception.Message
    $capabilityState = Get-LanguageCapabilityStateMap -LanguageTag $languageTag
    $capabilitySummary = Convert-LanguageCapabilityStateMapToSummary -StateMap $capabilityState
    $acceptPartialInstall = ($exceptionMessage -match '(?i)partially installed|0x80073CF1|2147009295') -and (Test-LanguageCapabilityStateSatisfied -StateMap $capabilityState)
    if ($acceptPartialInstall) {
        Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $true -Summary 'Language components were queued successfully and require restart.' -Details @(
            'reboot-required=true',
            ("language-capabilities={0}" -f [string]$capabilitySummary),
            'language-install-partial=true'
        )
        return
    }

    Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $false -Summary 'Language components failed.' -Details @(
        [string]$exceptionMessage,
        ("language-capabilities={0}" -f [string]$capabilitySummary)
    )
    throw
}
'@

    $workerScript = $workerScript.Replace('__HELPER_PATH__', $helperPath)
    $workerScript = $workerScript.Replace('__RESULT_PATH__', [string]$paths.ResultPath)
    $workerScript = $workerScript.Replace('__TASK_NAME__', $interactiveTaskName)
    $workerScript = $workerScript.Replace('__LANGUAGE_TAG__', $LanguageTag)

    $interactiveResult = Invoke-LanguageInteractiveAutomation `
        -InteractiveTaskName $interactiveTaskName `
        -RunAsUser 'SYSTEM' `
        -RunAsPassword '' `
        -WorkerScriptText $workerScript `
        -LanguageTag $LanguageTag `
        -WaitTimeoutSeconds 120

    $rebootRequired = $false
    $capabilitySummary = ''
    $interactiveWorkerQueued = $false
    if ($null -ne $interactiveResult -and $interactiveResult.PSObject.Properties.Match('Details').Count -gt 0 -and $null -ne $interactiveResult.Details) {
        foreach ($detail in @($interactiveResult.Details)) {
            $detailText = [string]$detail
            if ($detailText -match '^reboot-required=(?<value>true|false)$') {
                $rebootRequired = [bool]::Parse([string]$Matches['value'])
                continue
            }
            if ($detailText -match '^language-capabilities=(?<value>.+)$') {
                $capabilitySummary = [string]$Matches['value']
                continue
            }
            if ($detailText -match '^interactive-worker-queued=(?<value>true|false)$') {
                $interactiveWorkerQueued = [bool]::Parse([string]$Matches['value'])
            }
        }
    }

    $capabilityState = Get-LanguageCapabilityStateMap -LanguageTag $LanguageTag
    if ([string]::IsNullOrWhiteSpace([string]$capabilitySummary)) {
        $capabilitySummary = Convert-LanguageCapabilityStateMapToSummary -StateMap $capabilityState
    }

    $installedRows = @(Get-InstalledLanguageSafe -LanguageTag $LanguageTag)
    $capabilityStateSatisfied = Test-LanguageCapabilityStateSatisfied -StateMap $capabilityState
    $queuedInstallAccepted = (
        [bool]$interactiveWorkerQueued -or
        (
            [bool]$rebootRequired -and
            ([string]$capabilitySummary -match '(?i)InstallPending')
        )
    )

    if (@($installedRows).Count -lt 1 -and -not $capabilityStateSatisfied -and -not $queuedInstallAccepted) {
        throw ("Unable to verify installed language components for '{0}'." -f [string]$LanguageTag)
    }

    if (@($installedRows).Count -gt 0) {
        Write-Host ("language-components => {0} => {1}" -f [string]$LanguageTag, (Get-LanguageFeatureSummary -InstalledLanguage $installedRows[0]))
    }
    else {
        Write-Host ("language-capabilities => {0} => {1}" -f [string]$LanguageTag, [string]$capabilitySummary)
    }

    if ([bool]$queuedInstallAccepted) {
        $rebootRequired = $true
        Write-StateSuccess ("Language components for {0} were queued successfully and will finish after restart." -f [string]$DisplayName)
    }
    else {
        Write-StateSuccess ("Language components for {0} were installed successfully." -f [string]$DisplayName)
    }

    return [pscustomobject]@{
        LanguageTag = [string]$LanguageTag
        RebootRequired = [bool]$rebootRequired
        QueuedInstallAccepted = [bool]$queuedInstallAccepted
        CapabilitySummary = [string]$capabilitySummary
        InstalledLanguagePresent = (@($installedRows).Count -ge 1)
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
        $secondaryEntries = New-WinUserLanguageList $secondaryLanguage
        if ($null -ne $secondaryEntries -and $secondaryEntries.Count -gt 0) {
            [void]$languageList.Add($secondaryEntries[0])
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

. $helperPath

try {
    $languageList = New-WinUserLanguageList $primaryLanguage
    $secondaryEntries = New-WinUserLanguageList $secondaryLanguage
    if ($null -ne $secondaryEntries -and $secondaryEntries.Count -gt 0) {
        [void]$languageList.Add($secondaryEntries[0])
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

    $null = Invoke-ClagnosInteractiveDesktopAutomation `
        -TaskName $interactiveTaskName `
        -RunAsUser $UserName `
        -RunAsPassword $UserPassword `
        -WorkerScriptText $workerScript `
        -WaitTimeoutSeconds 300 `
        -HeartbeatSeconds 10

    Write-StateSuccess ("Language settings for user '{0}' were configured successfully." -f [string]$UserName)
}

function Set-SystemLanguageState {
    $systemPreferredUiBefore = Get-SystemPreferredUiLanguageSafe
    Write-StateIntent ('System language packages and UI settings will be configured.')
    Write-StateStart ('Configuring system language packages and UI settings...')

    $englishInstallResult = Install-LanguageComponents -LanguageTag $primaryLanguage -DisplayName 'English (United States)'
    $turkishInstallResult = Install-LanguageComponents -LanguageTag $secondaryLanguage -DisplayName 'Turkish (Turkey)'

    Write-StateStart ("Applying system preferred UI language '{0}'..." -f $primaryLanguage)
    Set-SystemPreferredUILanguage -Language $primaryLanguage
    $systemPreferredUiAfter = Get-SystemPreferredUiLanguageSafe

    if (-not [string]::Equals([string]$systemPreferredUiAfter, $primaryLanguage, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("Unable to set the system preferred UI language to '{0}'." -f $primaryLanguage)
    }

    Write-StateSuccess('System language packages and UI settings were configured successfully.')

    return [pscustomobject]@{
        RebootRequired = (
            [bool]$englishInstallResult.RebootRequired -or
            [bool]$turkishInstallResult.RebootRequired -or
            (-not [string]::Equals([string]$systemPreferredUiBefore, [string]$systemPreferredUiAfter, [System.StringComparison]::OrdinalIgnoreCase))
        )
        ComponentResults = [ordered]@{
            ([string]$primaryLanguage) = $englishInstallResult
            ([string]$secondaryLanguage) = $turkishInstallResult
        }
    }
}

function Assert-LanguageStateReadyForRestart {
    param([hashtable]$ComponentResults = @{})

    foreach ($languageTag in @($primaryLanguage, $secondaryLanguage)) {
        $capabilityState = Get-LanguageCapabilityStateMap -LanguageTag $languageTag
        $capabilitySummary = Convert-LanguageCapabilityStateMapToSummary -StateMap $capabilityState
        $installedLanguageRows = @(Get-InstalledLanguageSafe -LanguageTag $languageTag)
        $installedLanguagePresent = (@($installedLanguageRows).Count -ge 1)
        Write-Host ("language-capabilities-final => {0} => {1}" -f [string]$languageTag, [string]$capabilitySummary)
        if (-not (Test-LanguageCapabilityStateSatisfied -StateMap $capabilityState)) {
            if ($installedLanguagePresent) {
                Write-Host ("language-capabilities-info => {0} => installed-language verification is already satisfied; optional capability packages remain image-managed. {1}" -f [string]$languageTag, [string]$capabilitySummary) -ForegroundColor DarkCyan
                continue
            }

            $componentResult = $null
            if ($null -ne $ComponentResults -and $ComponentResults.ContainsKey([string]$languageTag)) {
                $componentResult = $ComponentResults[[string]$languageTag]
            }

            $allowDeferredVerification = $false
            if ($null -ne $componentResult) {
                if ($componentResult.PSObject.Properties.Match('QueuedInstallAccepted').Count -gt 0 -and [bool]$componentResult.QueuedInstallAccepted) {
                    $allowDeferredVerification = $true
                }
                elseif ($componentResult.PSObject.Properties.Match('RebootRequired').Count -gt 0 -and [bool]$componentResult.RebootRequired) {
                    $allowDeferredVerification = $true
                }
            }

            if ($allowDeferredVerification -and (Test-LanguageCapabilityDeferredVerificationAllowed -StateMap $capabilityState)) {
                Write-Host ("language-capabilities-deferred => {0} => {1}" -f [string]$languageTag, [string]$capabilitySummary) -ForegroundColor DarkCyan
                continue
            }

            throw ("Language capability verification failed for '{0}'. {1}" -f [string]$languageTag, [string]$capabilitySummary)
        }
    }
}

$rebootRequired = $false

try {
    if (-not (Get-Command Install-Language -ErrorAction SilentlyContinue)) {
        throw 'Install-Language is not available on this image.'
    }
    if (-not (Get-Command Set-SystemPreferredUILanguage -ErrorAction SilentlyContinue)) {
        throw 'Set-SystemPreferredUILanguage is not available on this image.'
    }

    $systemLanguageState = Set-SystemLanguageState
    if ([bool]$systemLanguageState.RebootRequired) {
        $rebootRequired = $true
    }

    Write-StateStart("Applying language list and UI override for '{0}'..." -f $managerUser)
    Invoke-UserLanguageConfiguration -UserName $managerUser -UserPassword $managerPassword
    Write-StateStart("Applying language list and UI override for '{0}'..." -f $assistantUser)
    Invoke-UserLanguageConfiguration -UserName $assistantUser -UserPassword $assistantPassword

    Write-StateStart('Collecting final language verification output...')
    Write-Host ("language-targets => system-ui={0}; primary-language={1}; secondary-language={2}" -f $primaryLanguage, $primaryLanguage, $secondaryLanguage)
    Write-Host ("installed-language => {0} => {1}" -f $primaryLanguage, (Get-LanguageFeatureSummary -InstalledLanguage (@(Get-InstalledLanguageSafe -LanguageTag $primaryLanguage) | Select-Object -First 1)))
    Write-Host ("installed-language => {0} => {1}" -f $secondaryLanguage, (Get-LanguageFeatureSummary -InstalledLanguage (@(Get-InstalledLanguageSafe -LanguageTag $secondaryLanguage) | Select-Object -First 1)))
    Assert-LanguageStateReadyForRestart -ComponentResults $systemLanguageState.ComponentResults

    Write-Host 'language-step-ok: restart-required-to-finalize'
    Write-Host 'TASK_REBOOT_REQUIRED:configure-language-settings'

    Write-Host 'configure-language-settings-completed'
    Write-Host 'Update task completed: configure-language-settings'
}
catch {
    throw
}
