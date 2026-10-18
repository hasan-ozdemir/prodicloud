$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-be-my-eyes-application"

$taskConfig = [ordered]@{
    TaskName = '118-install-be-my-eyes-application-application'
    ManagerUser = '__VM_ADMIN_USER__'
    ManagerPassword = '__VM_ADMIN_PASS__'
    HelperPath = 'C:\Windows\Temp\clagnos-interactive-session-helper.ps1'
    StoreHelperPath = 'C:\Windows\Temp\clagnos-store-install-state.psm1'
    PortableWingetPath = 'C:\ProgramData\clagnos\tools\winget-x64\winget.exe'
    StoreProductId = '9MSW46LTDWGF'
    InteractiveTaskSuffix = 'interactive-install'
    LegacyRunOnceName = 'ClagnosInstallBeMyEyes'
    WaitTimeoutSeconds = 240
}

$taskName = [string]$taskConfig.TaskName
$managerUser = [string]$taskConfig.ManagerUser
$managerPassword = [string]$taskConfig.ManagerPassword
$helperPath = [string]$taskConfig.HelperPath
$storeProductId = [string]$taskConfig.StoreProductId

if (-not (Test-Path -LiteralPath $helperPath)) {
    throw ("Interactive session helper was not found: {0}" -f $helperPath)
}
if (-not (Test-Path -LiteralPath ([string]$taskConfig.StoreHelperPath))) {
    throw ("Store install state helper was not found: {0}" -f [string]$taskConfig.StoreHelperPath)
}

. $helperPath
Import-Module ([string]$taskConfig.StoreHelperPath) -Force -DisableNameChecking

function Resolve-BeMyEyesAppId {
    if (-not (Get-Command Get-StartApps -ErrorAction SilentlyContinue)) {
        return ''
    }

    $startApps = @(Get-StartApps | Where-Object {
        $nameText = [string]$_.Name
        $appIdText = [string]$_.AppID
        if ([string]::IsNullOrWhiteSpace([string]$nameText) -and [string]::IsNullOrWhiteSpace([string]$appIdText)) {
            return $false
        }

        return (
            $nameText.ToLowerInvariant().Contains('be my eyes') -or
            $appIdText.ToLowerInvariant().Contains('bemyeyes')
        )
    })

    foreach ($entry in @($startApps)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.AppID)) {
            return [string]$entry.AppID
        }
    }

    return ''
}

function Get-BeMyEyesPackages {
    return @(
        Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object {
            ([string]$_.Name).ToLowerInvariant().Contains('bemyeyes') -or
            ([string]$_.Name).ToLowerInvariant().Contains('be my eyes') -or
            ([string]$_.PackageFamilyName).ToLowerInvariant().Contains('bemyeyes')
        }
    )
}

function Get-BeMyEyesInstallState {
    $appId = Resolve-BeMyEyesAppId
    if (-not [string]::IsNullOrWhiteSpace([string]$appId)) {
        return [pscustomobject]@{
            Healthy = $true
            LaunchKind = 'app-id'
            LaunchTarget = [string]$appId
            DetectionSource = 'app-id'
        }
    }

    $packages = @(Get-BeMyEyesPackages)
    if (@($packages).Count -gt 0) {
        return [pscustomobject]@{
            Healthy = $false
            LaunchKind = 'package-only'
            LaunchTarget = [string]$packages[0].PackageFamilyName
            DetectionSource = 'package'
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
$existingState = Get-BeMyEyesInstallState
if ([bool]$existingState.Healthy) {
    Remove-ClagnosRunOnceEntry -Name ([string]$taskConfig.LegacyRunOnceName)
    $stateRecord = Write-ClagnosStoreInstallState -TaskName $taskName -State installed -Summary ('Be My Eyes is launch-ready via {0}.' -f [string]$existingState.DetectionSource) -PackageId $storeProductId -RunOnceName ([string]$taskConfig.LegacyRunOnceName) -LaunchKind ([string]$existingState.LaunchKind) -LaunchTarget ([string]$existingState.LaunchTarget)
    Write-ClagnosStoreInstallStateStatusLine -TaskName $taskName -StateRecord $stateRecord
    Write-Host 'install-be-my-eyes-application-completed'
    Write-Host 'Update task completed: install-be-my-eyes-application'
    return
}

$wingetExe = Resolve-ClagnosWingetExe -PortableCandidate ([string]$taskConfig.PortableWingetPath)
if ([string]::IsNullOrWhiteSpace([string]$wingetExe)) {
    throw 'winget command is not available.'
}

if (Test-ClagnosRunOnceEntryPresent -Name ([string]$taskConfig.LegacyRunOnceName)) {
    Remove-ClagnosRunOnceEntry -Name ([string]$taskConfig.LegacyRunOnceName)
    Write-Host 'store-install-cleanup => task=118-install-be-my-eyes-application-application; removed-stale-run-once=True'
}

$workerTaskName = "{0}-{1}" -f $taskName, ([string]$taskConfig.InteractiveTaskSuffix)
$paths = Get-ClagnosInteractivePaths -TaskName $workerTaskName
$workerScript = @'
$ErrorActionPreference = "Stop"
$helperPath = "__HELPER_PATH__"
$storeHelperPath = "__STORE_HELPER_PATH__"
$resultPath = "__RESULT_PATH__"
$taskName = "__TASK_NAME__"
$storeProductId = "__STORE_PRODUCT_ID__"

. $helperPath
Import-Module $storeHelperPath -Force -DisableNameChecking

function Resolve-BeMyEyesAppId {
    if (-not (Get-Command Get-StartApps -ErrorAction SilentlyContinue)) {
        return ''
    }

    $startApps = @(Get-StartApps | Where-Object {
        $nameText = [string]$_.Name
        $appIdText = [string]$_.AppID
        if ([string]::IsNullOrWhiteSpace([string]$nameText) -and [string]::IsNullOrWhiteSpace([string]$appIdText)) {
            return $false
        }

        return (
            $nameText.ToLowerInvariant().Contains('be my eyes') -or
            $appIdText.ToLowerInvariant().Contains('bemyeyes')
        )
    })

    foreach ($entry in @($startApps)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.AppID)) {
            return [string]$entry.AppID
        }
    }

    return ''
}

function Test-BeMyEyesInstalled {
    return (-not [string]::IsNullOrWhiteSpace([string](Resolve-BeMyEyesAppId)))
}

Invoke-ClagnosRefreshSessionPath
$wingetExe = Resolve-ClagnosWingetExe -PortableCandidate "__PORTABLE_WINGET_PATH__"
if ([string]::IsNullOrWhiteSpace([string]$wingetExe)) {
    Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $false -Summary 'winget command is not available.'
    exit 1
}

if (-not (Test-BeMyEyesInstalled)) {
    $installOutput = @(& $wingetExe install --id $storeProductId --source msstore --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1)
    $installExit = [int]$LASTEXITCODE
    $installText = [string]($installOutput | Out-String)
    if ($installExit -ne 0 -and $installExit -ne -1978335189) {
        Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $false -Summary ("winget install failed with exit code {0}." -f $installExit) -Details @($installText)
        exit 1
    }
}

if (-not (Test-BeMyEyesInstalled)) {
    Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $false -Summary 'Be My Eyes install could not be verified after unattended WinGet install.'
    exit 1
}

Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $true -Summary 'Be My Eyes is installed.'
'@

$workerScript = $workerScript.Replace('__HELPER_PATH__', $helperPath)
$workerScript = $workerScript.Replace('__STORE_HELPER_PATH__', [string]$taskConfig.StoreHelperPath)
$workerScript = $workerScript.Replace('__RESULT_PATH__', [string]$paths.ResultPath)
$workerScript = $workerScript.Replace('__TASK_NAME__', $workerTaskName)
$workerScript = $workerScript.Replace('__STORE_PRODUCT_ID__', $storeProductId)
$workerScript = $workerScript.Replace('__PORTABLE_WINGET_PATH__', [string]$taskConfig.PortableWingetPath)

try {
    $null = Invoke-ClagnosInteractiveDesktopAutomation `
        -TaskName $workerTaskName `
        -RunAsUser $managerUser `
        -RunAsPassword $managerPassword `
        -WorkerScriptText $workerScript `
        -WaitTimeoutSeconds ([int]$taskConfig.WaitTimeoutSeconds) `
        -RunAsMode 'password'
}
catch {
    Invoke-ClagnosRefreshSessionPath
    $catchState = Get-BeMyEyesInstallState
    if ([bool]$catchState.Healthy) {
        Remove-ClagnosRunOnceEntry -Name ([string]$taskConfig.LegacyRunOnceName)
        $stateRecord = Write-ClagnosStoreInstallState -TaskName $taskName -State installed -Summary ('Be My Eyes is launch-ready via {0}.' -f [string]$catchState.DetectionSource) -PackageId $storeProductId -RunOnceName ([string]$taskConfig.LegacyRunOnceName) -LaunchKind ([string]$catchState.LaunchKind) -LaunchTarget ([string]$catchState.LaunchTarget)
        Write-ClagnosStoreInstallStateStatusLine -TaskName $taskName -StateRecord $stateRecord
        Write-Host 'install-be-my-eyes-application-completed'
        Write-Host 'Update task completed: install-be-my-eyes-application'
        return
    }

    $installError = [string]$_.Exception.Message
    $stateRecord = Write-ClagnosStoreInstallState -TaskName $taskName -State degraded -Summary ('Unattended Be My Eyes install failed: {0}' -f $installError) -PackageId $storeProductId -RunOnceName ([string]$taskConfig.LegacyRunOnceName) -LaunchKind ([string]$catchState.LaunchKind) -LaunchTarget ([string]$catchState.LaunchTarget)
    Write-ClagnosStoreInstallStateStatusLine -TaskName $taskName -StateRecord $stateRecord
    throw
}

Invoke-ClagnosRefreshSessionPath
$finalState = Get-BeMyEyesInstallState
if (-not [bool]$finalState.Healthy) {
    $stateRecord = Write-ClagnosStoreInstallState -TaskName $taskName -State degraded -Summary ('Be My Eyes is present but not yet launch-ready via a stable AppID ({0}).' -f [string]$finalState.DetectionSource) -PackageId $storeProductId -RunOnceName ([string]$taskConfig.LegacyRunOnceName) -LaunchKind ([string]$finalState.LaunchKind) -LaunchTarget ([string]$finalState.LaunchTarget)
    Write-ClagnosStoreInstallStateStatusLine -TaskName $taskName -StateRecord $stateRecord
    throw 'Be My Eyes install could not be verified.'
}

Remove-ClagnosRunOnceEntry -Name ([string]$taskConfig.LegacyRunOnceName)
$stateRecord = Write-ClagnosStoreInstallState -TaskName $taskName -State installed -Summary ('Be My Eyes is launch-ready via {0}.' -f [string]$finalState.DetectionSource) -PackageId $storeProductId -RunOnceName ([string]$taskConfig.LegacyRunOnceName) -LaunchKind ([string]$finalState.LaunchKind) -LaunchTarget ([string]$finalState.LaunchTarget)
Write-ClagnosStoreInstallStateStatusLine -TaskName $taskName -StateRecord $stateRecord
Write-Host 'install-be-my-eyes-application-completed'
Write-Host 'Update task completed: install-be-my-eyes-application'

