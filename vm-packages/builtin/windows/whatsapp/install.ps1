$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-whatsapp-application"

Import-Module 'C:\Windows\Temp\clagnos-store-install-state.psm1' -Force -DisableNameChecking

$managerUser = '__VM_ADMIN_USER__'
$managerPassword = '__VM_ADMIN_PASS__'
$helperPath = 'C:\Windows\Temp\clagnos-interactive-session-helper.ps1'

$taskConfig = [ordered]@{
    TaskName = '119-install-whatsapp-application'
    PackageId = '9NKSQGP7F2NH'
    LegacyRunOnceName = 'ClagnosInstallWhatsApp'
    PortableWingetPath = 'C:\ProgramData\clagnos\tools\winget-x64\winget.exe'
    InteractiveTaskSuffix = 'interactive-install'
    WaitTimeoutSeconds = 240
}

if (-not (Test-Path -LiteralPath $helperPath)) {
    throw ("Interactive session helper was not found: {0}" -f $helperPath)
}

. $helperPath

function Resolve-WhatsAppAppId {
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
            $nameText.ToLowerInvariant().Contains('whatsapp') -or
            $appIdText.ToLowerInvariant().Contains('whatsapp')
        )
    })

    foreach ($entry in @($startApps)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.AppID)) {
            return [string]$entry.AppID
        }
    }

    return ''
}

function Resolve-WhatsAppExecutable {
    $packages = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object {
        $pkgName = [string]$_.Name
        $pkgFamily = [string]$_.PackageFamilyName
        if ([string]::IsNullOrWhiteSpace([string]$pkgName) -and [string]::IsNullOrWhiteSpace([string]$pkgFamily)) {
            return $false
        }

        $pkgNameLower = $pkgName.ToLowerInvariant()
        $pkgFamilyLower = $pkgFamily.ToLowerInvariant()
        return ($pkgNameLower.Contains('whatsapp') -or $pkgFamilyLower.Contains('whatsapp'))
    })

    foreach ($package in @($packages)) {
        $installLocation = [string]$package.InstallLocation
        if ([string]::IsNullOrWhiteSpace([string]$installLocation)) {
            continue
        }

        foreach ($candidate in @(
            (Join-Path $installLocation 'WhatsApp.Root.exe'),
            (Join-Path $installLocation 'app\WhatsApp.exe'),
            (Join-Path $installLocation 'WhatsApp.exe')
        )) {
            if (Test-Path -LiteralPath $candidate) {
                return [string]$candidate
            }
        }
    }

    return ''
}

function Get-WhatsAppInstallState {
    param([string]$WingetExe)

    $appId = Resolve-WhatsAppAppId
    if (-not [string]::IsNullOrWhiteSpace([string]$appId)) {
        return [pscustomobject]@{
            Healthy = $true
            LaunchKind = 'app-id'
            LaunchTarget = [string]$appId
            DetectionSource = 'app-id'
        }
    }

    $resolvedExe = Resolve-WhatsAppExecutable
    if (-not [string]::IsNullOrWhiteSpace([string]$resolvedExe)) {
        return [pscustomobject]@{
            Healthy = $true
            LaunchKind = 'executable'
            LaunchTarget = [string]$resolvedExe
            DetectionSource = 'executable'
        }
    }

    $packages = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object {
        ([string]$_.Name).ToLowerInvariant().Contains('whatsapp') -or
        ([string]$_.PackageFamilyName).ToLowerInvariant().Contains('whatsapp')
    })
    if (@($packages).Count -gt 0) {
        return [pscustomobject]@{
            Healthy = $false
            LaunchKind = 'package-only'
            LaunchTarget = [string]$packages[0].PackageFamilyName
            DetectionSource = 'package'
        }
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$WingetExe)) {
        Write-Host 'Running: winget list whatsapp'
        $listOutput = & $WingetExe list whatsapp
        $listText = [string]($listOutput | Out-String)
        if (-not [string]::IsNullOrWhiteSpace([string]$listText) -and $listText.ToLowerInvariant().Contains('whatsapp')) {
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
        [int]$TimeoutSeconds = 60,
        [string]$Label = 'process'
    )

    $logRoot = Join-Path $env:TEMP 'clagnos-whatsapp'
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

Invoke-ClagnosRefreshSessionPath
$wingetExe = Resolve-ClagnosWingetExe -PortableCandidate ([string]$taskConfig.PortableWingetPath)
if ([string]::IsNullOrWhiteSpace([string]$wingetExe)) {
    throw 'winget command is not available.'
}

Write-Host "Resolved winget executable: $wingetExe"
$existingState = Get-WhatsAppInstallState -WingetExe $wingetExe
if ([bool]$existingState.Healthy) {
    Remove-ClagnosRunOnceEntry -Name ([string]$taskConfig.LegacyRunOnceName)
    $stateRecord = Write-ClagnosStoreInstallState -TaskName ([string]$taskConfig.TaskName) -State installed -Summary ('WhatsApp is launch-ready via {0}.' -f [string]$existingState.DetectionSource) -PackageId ([string]$taskConfig.PackageId) -RunOnceName ([string]$taskConfig.LegacyRunOnceName) -LaunchKind ([string]$existingState.LaunchKind) -LaunchTarget ([string]$existingState.LaunchTarget)
    Write-ClagnosStoreInstallStateStatusLine -TaskName ([string]$taskConfig.TaskName) -StateRecord $stateRecord
    Write-Host 'install-whatsapp-application-completed'
    Write-Host 'Update task completed: install-whatsapp-application'
    return
}

if (Test-ClagnosRunOnceEntryPresent -Name ([string]$taskConfig.LegacyRunOnceName)) {
    Remove-ClagnosRunOnceEntry -Name ([string]$taskConfig.LegacyRunOnceName)
    Write-Host 'store-install-cleanup => task=119-install-whatsapp-application; removed-stale-run-once=True'
}

$workerTaskName = "{0}-{1}" -f ([string]$taskConfig.TaskName), ([string]$taskConfig.InteractiveTaskSuffix)
$paths = Get-ClagnosInteractivePaths -TaskName $workerTaskName
$workerScript = @'
$ErrorActionPreference = "Stop"
$helperPath = "__HELPER_PATH__"
$storeHelperPath = "__STORE_HELPER_PATH__"
$resultPath = "__RESULT_PATH__"
$taskName = "__TASK_NAME__"
$packageId = "__PACKAGE_ID__"

. $helperPath
Import-Module $storeHelperPath -Force -DisableNameChecking

function Resolve-WhatsAppAppId {
    if (-not (Get-Command Get-StartApps -ErrorAction SilentlyContinue)) {
        return ''
    }

    $startApps = @(Get-StartApps | Where-Object {
        $text = (([string]$_.Name) + ' ' + ([string]$_.AppID)).ToLowerInvariant()
        return $text.Contains('whatsapp')
    })

    foreach ($entry in @($startApps)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.AppID)) {
            return [string]$entry.AppID
        }
    }

    return ''
}

function Resolve-WhatsAppExecutable {
    $packages = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object {
        $text = (([string]$_.Name) + ' ' + ([string]$_.PackageFamilyName)).ToLowerInvariant()
        return $text.Contains('whatsapp')
    })

    foreach ($package in @($packages)) {
        $installLocation = [string]$package.InstallLocation
        if ([string]::IsNullOrWhiteSpace([string]$installLocation)) {
            continue
        }

        foreach ($candidate in @(
            (Join-Path $installLocation 'WhatsApp.Root.exe'),
            (Join-Path $installLocation 'app\WhatsApp.exe'),
            (Join-Path $installLocation 'WhatsApp.exe')
        )) {
            if (Test-Path -LiteralPath $candidate) {
                return [string]$candidate
            }
        }
    }

    return ''
}

function Test-WhatsAppInstalled {
    if (-not [string]::IsNullOrWhiteSpace([string](Resolve-WhatsAppAppId))) {
        return $true
    }

    return (-not [string]::IsNullOrWhiteSpace([string](Resolve-WhatsAppExecutable)))
}

Invoke-ClagnosRefreshSessionPath
$wingetExe = Resolve-ClagnosWingetExe -PortableCandidate "__PORTABLE_WINGET_PATH__"
if ([string]::IsNullOrWhiteSpace([string]$wingetExe)) {
    Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $false -Summary 'winget command is not available.'
    exit 1
}

if (-not (Test-WhatsAppInstalled)) {
    $installOutput = @(& $wingetExe install --id $packageId --source msstore --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1)
    $installExit = [int]$LASTEXITCODE
    $installText = [string]($installOutput | Out-String)
    if ($installExit -ne 0 -and $installExit -ne -1978335189) {
        Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $false -Summary ("winget install failed with exit code {0}." -f $installExit) -Details @($installText)
        exit 1
    }
}

if (-not (Test-WhatsAppInstalled)) {
    Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $false -Summary 'WhatsApp install could not be verified after interactive winget install.'
    exit 1
}

Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $true -Summary 'WhatsApp is installed.'
'@

$workerScript = $workerScript.Replace('__HELPER_PATH__', $helperPath)
$workerScript = $workerScript.Replace('__STORE_HELPER_PATH__', 'C:\Windows\Temp\clagnos-store-install-state.psm1')
$workerScript = $workerScript.Replace('__RESULT_PATH__', [string]$paths.ResultPath)
$workerScript = $workerScript.Replace('__TASK_NAME__', $workerTaskName)
$workerScript = $workerScript.Replace('__PACKAGE_ID__', [string]$taskConfig.PackageId)
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
    $catchState = Get-WhatsAppInstallState -WingetExe $wingetExe
    if ([bool]$catchState.Healthy) {
        Remove-ClagnosRunOnceEntry -Name ([string]$taskConfig.LegacyRunOnceName)
        $stateRecord = Write-ClagnosStoreInstallState -TaskName ([string]$taskConfig.TaskName) -State installed -Summary ('WhatsApp is launch-ready via {0}.' -f [string]$catchState.DetectionSource) -PackageId ([string]$taskConfig.PackageId) -RunOnceName ([string]$taskConfig.LegacyRunOnceName) -LaunchKind ([string]$catchState.LaunchKind) -LaunchTarget ([string]$catchState.LaunchTarget)
        Write-ClagnosStoreInstallStateStatusLine -TaskName ([string]$taskConfig.TaskName) -StateRecord $stateRecord
        Write-Host 'install-whatsapp-application-completed'
        Write-Host 'Update task completed: install-whatsapp-application'
        return
    }

    $installError = [string]$_.Exception.Message
    $stateRecord = Write-ClagnosStoreInstallState -TaskName ([string]$taskConfig.TaskName) -State degraded -Summary ('Unattended WhatsApp install failed: {0}' -f $installError) -PackageId ([string]$taskConfig.PackageId) -RunOnceName ([string]$taskConfig.LegacyRunOnceName) -LaunchKind ([string]$catchState.LaunchKind) -LaunchTarget ([string]$catchState.LaunchTarget)
    Write-ClagnosStoreInstallStateStatusLine -TaskName ([string]$taskConfig.TaskName) -StateRecord $stateRecord
    throw
}

Invoke-ClagnosRefreshSessionPath
$finalState = Get-WhatsAppInstallState -WingetExe $wingetExe
if (-not [bool]$finalState.Healthy) {
    $stateRecord = Write-ClagnosStoreInstallState -TaskName ([string]$taskConfig.TaskName) -State degraded -Summary ('WhatsApp is present but not yet launch-ready via a stable executable or AppID ({0}).' -f [string]$finalState.DetectionSource) -PackageId ([string]$taskConfig.PackageId) -RunOnceName ([string]$taskConfig.LegacyRunOnceName) -LaunchKind ([string]$finalState.LaunchKind) -LaunchTarget ([string]$finalState.LaunchTarget)
    Write-ClagnosStoreInstallStateStatusLine -TaskName ([string]$taskConfig.TaskName) -StateRecord $stateRecord
    throw 'WhatsApp install could not be verified.'
}

Remove-ClagnosRunOnceEntry -Name ([string]$taskConfig.LegacyRunOnceName)
$stateRecord = Write-ClagnosStoreInstallState -TaskName ([string]$taskConfig.TaskName) -State installed -Summary ('WhatsApp is launch-ready via {0}.' -f [string]$finalState.DetectionSource) -PackageId ([string]$taskConfig.PackageId) -RunOnceName ([string]$taskConfig.LegacyRunOnceName) -LaunchKind ([string]$finalState.LaunchKind) -LaunchTarget ([string]$finalState.LaunchTarget)
Write-ClagnosStoreInstallStateStatusLine -TaskName ([string]$taskConfig.TaskName) -StateRecord $stateRecord
Write-Host 'install-whatsapp-application-completed'
Write-Host 'Update task completed: install-whatsapp-application'

