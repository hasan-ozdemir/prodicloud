$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-teams-application"

$taskConfig = [ordered]@{
    TaskName = '114-install-teams-application'
    ManagerUser = '__VM_ADMIN_USER__'
    ManagerPassword = '__VM_ADMIN_PASS__'
    HelperPath = 'C:\Windows\Temp\clagnos-interactive-session-helper.ps1'
    StoreHelperPath = 'C:\Windows\Temp\clagnos-store-install-state.psm1'
    PortableWingetPath = 'C:\ProgramData\clagnos\tools\winget-x64\winget.exe'
    StorePackageName = 'Microsoft Teams'
    StoreSource = 'msstore'
    LegacyRunOnceName = 'ClagnosInstallTeams'
    InteractiveTaskSuffix = 'interactive-install'
    InteractiveDesktopWaitSeconds = 30
    WaitTimeoutSeconds = 240
    StoreSessionErrorRegex = '(?i)0x80070520|logon session|microsoft store|msstore'
    ExecutableCandidates = @(
        'C:\Program Files\WindowsApps\MSTeams_8wekyb3d8bbwe\ms-teams.exe',
        'C:\Program Files\WindowsApps\MSTeams_8wekyb3d8bbwe\MSTeams.exe'
    )
}

$taskName = [string]$taskConfig.TaskName
$managerUser = [string]$taskConfig.ManagerUser
$managerPassword = [string]$taskConfig.ManagerPassword
$helperPath = [string]$taskConfig.HelperPath

if (-not (Test-Path -LiteralPath $helperPath)) {
    throw ("Interactive session helper was not found: {0}" -f $helperPath)
}
if (-not (Test-Path -LiteralPath ([string]$taskConfig.StoreHelperPath))) {
    throw ("Store install state helper was not found: {0}" -f [string]$taskConfig.StoreHelperPath)
}

. $helperPath
Import-Module ([string]$taskConfig.StoreHelperPath) -Force -DisableNameChecking

function Get-TeamsPackages {
    return @(
        Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object {
            $nameText = [string]$_.Name
            $familyText = [string]$_.PackageFamilyName
            if ([string]::IsNullOrWhiteSpace([string]$nameText) -and [string]::IsNullOrWhiteSpace([string]$familyText)) {
                return $false
            }

            $combinedText = ($nameText + ' ' + $familyText).ToLowerInvariant()
            return ($combinedText.Contains('msteams') -or $combinedText.Contains('teams'))
        }
    )
}

function Resolve-TeamsAppId {
    if (-not (Get-Command Get-StartApps -ErrorAction SilentlyContinue)) {
        return ''
    }

    $startApps = @(Get-StartApps | Where-Object {
        $nameText = [string]$_.Name
        $appIdText = [string]$_.AppID
        if ([string]::IsNullOrWhiteSpace([string]$nameText) -and [string]::IsNullOrWhiteSpace([string]$appIdText)) {
            return $false
        }

        $combinedText = ($nameText + ' ' + $appIdText).ToLowerInvariant()
        return ($combinedText.Contains('teams') -or $combinedText.Contains('msteams'))
    })

    foreach ($entry in @($startApps)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.AppID)) {
            return [string]$entry.AppID
        }
    }

    return ''
}

function Resolve-TeamsExecutable {
    $command = Get-Command 'ms-teams.exe' -ErrorAction SilentlyContinue
    if ($command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source) -and (Test-Path -LiteralPath ([string]$command.Source))) {
        return [string]$command.Source
    }

    foreach ($candidate in @($taskConfig.ExecutableCandidates)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate) -and (Test-Path -LiteralPath $candidate)) {
            return [string]$candidate
        }
    }

    foreach ($package in @(Get-TeamsPackages)) {
        $installLocation = [string]$package.InstallLocation
        if ([string]::IsNullOrWhiteSpace([string]$installLocation) -or -not (Test-Path -LiteralPath $installLocation)) {
            continue
        }

        foreach ($candidate in @(
            (Join-Path $installLocation 'ms-teams.exe'),
            (Join-Path $installLocation 'MSTeams.exe')
        )) {
            if (Test-Path -LiteralPath $candidate) {
                return [string]$candidate
            }
        }

        $match = Get-ChildItem -LiteralPath $installLocation -Filter 'ms-teams.exe' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($match -and (Test-Path -LiteralPath $match.FullName)) {
            return [string]$match.FullName
        }
    }

    return ''
}

function Get-TeamsInstallState {
    param([string]$WingetExe)

    $appId = Resolve-TeamsAppId
    if (-not [string]::IsNullOrWhiteSpace([string]$appId)) {
        return [pscustomobject]@{
            Healthy = $true
            LaunchKind = 'app-id'
            LaunchTarget = [string]$appId
            DetectionSource = 'app-id'
        }
    }

    $resolvedExe = Resolve-TeamsExecutable
    if (-not [string]::IsNullOrWhiteSpace([string]$resolvedExe)) {
        return [pscustomobject]@{
            Healthy = $true
            LaunchKind = 'executable'
            LaunchTarget = [string]$resolvedExe
            DetectionSource = 'executable'
        }
    }

    $packages = @(Get-TeamsPackages)
    if (@($packages).Count -gt 0) {
        return [pscustomobject]@{
            Healthy = $false
            LaunchKind = 'package-only'
            LaunchTarget = [string]$packages[0].PackageFamilyName
            DetectionSource = 'package'
        }
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$WingetExe)) {
        Write-Host 'Running: winget list Microsoft Teams'
        $listOutput = & $WingetExe list "Microsoft Teams"
        $listText = [string]($listOutput | Out-String)
        if (-not [string]::IsNullOrWhiteSpace([string]$listText) -and $listText.ToLowerInvariant().Contains('teams')) {
            return [pscustomobject]@{
                Healthy = $false
                LaunchKind = 'listed-only'
                LaunchTarget = 'winget-list'
                DetectionSource = 'winget'
            }
        }
    }

    return [pscustomobject]@{
        Healthy = $false
        LaunchKind = ''
        LaunchTarget = ''
        DetectionSource = 'none'
    }
}

Invoke-ClagnosRefreshSessionPath
$wingetExe = Resolve-ClagnosWingetExe -PortableCandidate ([string]$taskConfig.PortableWingetPath)
if ([string]::IsNullOrWhiteSpace([string]$wingetExe)) {
    throw 'winget command is not available.'
}

Write-Host "Resolved winget executable: $wingetExe"
$existingState = Get-TeamsInstallState -WingetExe $wingetExe
if ([bool]$existingState.Healthy) {
    Remove-ClagnosRunOnceEntry -Name ([string]$taskConfig.LegacyRunOnceName)
    $stateRecord = Write-ClagnosStoreInstallState -TaskName $taskName -State installed -Summary ('Microsoft Teams is launch-ready via {0}.' -f [string]$existingState.DetectionSource) -PackageId ([string]$taskConfig.StorePackageName) -RunOnceName ([string]$taskConfig.LegacyRunOnceName) -LaunchKind ([string]$existingState.LaunchKind) -LaunchTarget ([string]$existingState.LaunchTarget)
    Write-ClagnosStoreInstallStateStatusLine -TaskName $taskName -StateRecord $stateRecord
    Write-Host 'Existing Microsoft Teams installation is already healthy. Skipping winget install.'
    Write-Host 'install-teams-application-completed'
    Write-Host 'Update task completed: install-teams-application'
    return
}

if (Test-ClagnosRunOnceEntryPresent -Name ([string]$taskConfig.LegacyRunOnceName)) {
    Remove-ClagnosRunOnceEntry -Name ([string]$taskConfig.LegacyRunOnceName)
    Write-Host 'store-install-cleanup => task=114-install-teams-application; removed-stale-run-once=True'
}

$interactiveDesktopStatus = Wait-ClagnosUserInteractiveDesktopReady -UserName $managerUser -WaitSeconds ([int]$taskConfig.InteractiveDesktopWaitSeconds) -PollSeconds 5
Write-ClagnosInteractiveDesktopStatusLine -Status $interactiveDesktopStatus
if (-not [bool]$interactiveDesktopStatus.Ready) {
    $blockMessage = New-ClagnosInteractiveDesktopBlockMessage -ActivityDescription 'Microsoft Teams install' -ExpectedUserName $managerUser -Status $interactiveDesktopStatus
    Remove-ClagnosRunOnceEntry -Name ([string]$taskConfig.LegacyRunOnceName)
    $stateRecord = Write-ClagnosStoreInstallState -TaskName $taskName -State degraded -Summary ([string]$blockMessage.Summary) -PackageId ([string]$taskConfig.StorePackageName) -RunOnceName ([string]$taskConfig.LegacyRunOnceName) -LaunchKind ([string]$existingState.LaunchKind) -LaunchTarget ([string]$existingState.LaunchTarget)
    Write-ClagnosStoreInstallStateStatusLine -TaskName $taskName -StateRecord $stateRecord
    throw ([string]$blockMessage.WarningMessage)
}

$workerTaskName = "{0}-{1}" -f $taskName, ([string]$taskConfig.InteractiveTaskSuffix)
$paths = Get-ClagnosInteractivePaths -TaskName $workerTaskName
$workerScript = @'
$ErrorActionPreference = "Stop"
$helperPath = "__HELPER_PATH__"
$storeHelperPath = "__STORE_HELPER_PATH__"
$resultPath = "__RESULT_PATH__"
$taskName = "__TASK_NAME__"
$storePackageName = "__STORE_PACKAGE_NAME__"

. $helperPath
Import-Module $storeHelperPath -Force -DisableNameChecking

function Resolve-TeamsAppId {
    if (-not (Get-Command Get-StartApps -ErrorAction SilentlyContinue)) {
        return ''
    }

    $startApps = @(Get-StartApps | Where-Object {
        $combinedText = (([string]$_.Name) + ' ' + ([string]$_.AppID)).ToLowerInvariant()
        return ($combinedText.Contains('teams') -or $combinedText.Contains('msteams'))
    })

    foreach ($entry in @($startApps)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.AppID)) {
            return [string]$entry.AppID
        }
    }

    return ''
}

function Resolve-TeamsExecutable {
    $command = Get-Command 'ms-teams.exe' -ErrorAction SilentlyContinue
    if ($command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source) -and (Test-Path -LiteralPath ([string]$command.Source))) {
        return [string]$command.Source
    }

    return ''
}

function Test-TeamsInstalled {
    if (-not [string]::IsNullOrWhiteSpace([string](Resolve-TeamsAppId))) {
        return $true
    }

    return (-not [string]::IsNullOrWhiteSpace([string](Resolve-TeamsExecutable)))
}

Invoke-ClagnosRefreshSessionPath
$wingetExe = Resolve-ClagnosWingetExe -PortableCandidate "__PORTABLE_WINGET_PATH__"
if ([string]::IsNullOrWhiteSpace([string]$wingetExe)) {
    Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $false -Summary 'winget command is not available.'
    exit 1
}

if (-not (Test-TeamsInstalled)) {
    Write-Host 'Running: winget install "Microsoft Teams" -s msstore --accept-source-agreements --accept-package-agreements --silent --disable-interactivity'
    $installOutput = @(& $wingetExe install "Microsoft Teams" -s msstore --accept-source-agreements --accept-package-agreements --silent --disable-interactivity 2>&1)
    $installExit = [int]$LASTEXITCODE
    $installText = [string]($installOutput | Out-String)
    if ($installExit -ne 0 -and $installExit -ne -1978335189) {
        Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $false -Summary ("winget install failed with exit code {0}." -f $installExit) -Details @($installText)
        exit 1
    }
}

if (-not (Test-TeamsInstalled)) {
    Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $false -Summary 'Microsoft Teams install could not be verified after interactive winget install.'
    exit 1
}

Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $true -Summary 'Microsoft Teams is installed.'
'@

$workerScript = $workerScript.Replace('__HELPER_PATH__', $helperPath)
$workerScript = $workerScript.Replace('__STORE_HELPER_PATH__', [string]$taskConfig.StoreHelperPath)
$workerScript = $workerScript.Replace('__RESULT_PATH__', [string]$paths.ResultPath)
$workerScript = $workerScript.Replace('__TASK_NAME__', $workerTaskName)
$workerScript = $workerScript.Replace('__STORE_PACKAGE_NAME__', [string]$taskConfig.StorePackageName)
$workerScript = $workerScript.Replace('__PORTABLE_WINGET_PATH__', [string]$taskConfig.PortableWingetPath)

try {
    $null = Invoke-ClagnosInteractiveDesktopAutomation `
        -TaskName $workerTaskName `
        -RunAsUser $managerUser `
        -RunAsPassword $managerPassword `
        -WorkerScriptText $workerScript `
        -WaitTimeoutSeconds ([int]$taskConfig.WaitTimeoutSeconds) `
        -RunAsMode 'interactiveToken'
}
catch {
    Invoke-ClagnosRefreshSessionPath
    $catchState = Get-TeamsInstallState -WingetExe $wingetExe
    if ([bool]$catchState.Healthy) {
        Remove-ClagnosRunOnceEntry -Name ([string]$taskConfig.LegacyRunOnceName)
        $stateRecord = Write-ClagnosStoreInstallState -TaskName $taskName -State installed -Summary ('Microsoft Teams is launch-ready via {0}.' -f [string]$catchState.DetectionSource) -PackageId ([string]$taskConfig.StorePackageName) -RunOnceName ([string]$taskConfig.LegacyRunOnceName) -LaunchKind ([string]$catchState.LaunchKind) -LaunchTarget ([string]$catchState.LaunchTarget)
        Write-ClagnosStoreInstallStateStatusLine -TaskName $taskName -StateRecord $stateRecord
        Write-Host 'install-teams-application-completed'
        Write-Host 'Update task completed: install-teams-application'
        return
    }

    $interactiveError = [string]$_.Exception.Message
    if ($interactiveError -match ([string]$taskConfig.StoreSessionErrorRegex)) {
        Remove-ClagnosRunOnceEntry -Name ([string]$taskConfig.LegacyRunOnceName)
        $stateRecord = Write-ClagnosStoreInstallState -TaskName $taskName -State degraded -Summary 'Microsoft Teams install requires an interactive Store-capable session and no next-boot follow-up was scheduled.' -PackageId ([string]$taskConfig.StorePackageName) -RunOnceName ([string]$taskConfig.LegacyRunOnceName) -LaunchKind ([string]$catchState.LaunchKind) -LaunchTarget ([string]$catchState.LaunchTarget)
        Write-ClagnosStoreInstallStateStatusLine -TaskName $taskName -StateRecord $stateRecord
        throw 'Microsoft Teams install requires an interactive Store-capable session and cannot be deferred to a later boot.'
    }

    $stateRecord = Write-ClagnosStoreInstallState -TaskName $taskName -State degraded -Summary ('Microsoft Teams interactive install failed: {0}' -f $interactiveError) -PackageId ([string]$taskConfig.StorePackageName) -RunOnceName ([string]$taskConfig.LegacyRunOnceName) -LaunchKind ([string]$catchState.LaunchKind) -LaunchTarget ([string]$catchState.LaunchTarget)
    Write-ClagnosStoreInstallStateStatusLine -TaskName $taskName -StateRecord $stateRecord
    throw
}

Invoke-ClagnosRefreshSessionPath
$finalState = Get-TeamsInstallState -WingetExe $wingetExe
if (-not [bool]$finalState.Healthy) {
    $stateRecord = Write-ClagnosStoreInstallState -TaskName $taskName -State degraded -Summary ('Microsoft Teams is present but not yet launch-ready via a stable target ({0}).' -f [string]$finalState.DetectionSource) -PackageId ([string]$taskConfig.StorePackageName) -RunOnceName ([string]$taskConfig.LegacyRunOnceName) -LaunchKind ([string]$finalState.LaunchKind) -LaunchTarget ([string]$finalState.LaunchTarget)
    Write-ClagnosStoreInstallStateStatusLine -TaskName $taskName -StateRecord $stateRecord
    throw 'Microsoft Teams install could not be verified.'
}

Remove-ClagnosRunOnceEntry -Name ([string]$taskConfig.LegacyRunOnceName)
$stateRecord = Write-ClagnosStoreInstallState -TaskName $taskName -State installed -Summary ('Microsoft Teams is launch-ready via {0}.' -f [string]$finalState.DetectionSource) -PackageId ([string]$taskConfig.StorePackageName) -RunOnceName ([string]$taskConfig.LegacyRunOnceName) -LaunchKind ([string]$finalState.LaunchKind) -LaunchTarget ([string]$finalState.LaunchTarget)
Write-ClagnosStoreInstallStateStatusLine -TaskName $taskName -StateRecord $stateRecord
Write-Host 'install-teams-application-completed'
Write-Host 'Update task completed: install-teams-application'
