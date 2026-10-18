$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-codex-application"

Import-Module 'C:\Windows\Temp\clagnos-store-install-state.psm1' -Force -DisableNameChecking

$managerUser = '__VM_ADMIN_USER__'
$managerPassword = '__VM_ADMIN_PASS__'
$helperPath = 'C:\Windows\Temp\clagnos-interactive-session-helper.ps1'
$taskName = '120-install-codex-application'
$packageId = '9PLM9XGG6VKS'
$legacyRunOnceName = 'ClagnosInstallCodexApp'
$portableWingetPath = 'C:\ProgramData\clagnos\tools\winget-x64\winget.exe'
$interactiveTaskSuffix = 'interactive-install'
$waitTimeoutSeconds = 240

if (-not (Test-Path -LiteralPath $helperPath)) {
    throw ("Interactive session helper was not found: {0}" -f $helperPath)
}

. $helperPath

function Get-CodexPackages {
    $allPackages = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
    if (@($allPackages).Count -eq 0) {
        return @()
    }

    return @(
        $allPackages | Where-Object {
            $pkgName = [string]$_.Name
            $pkgFamily = [string]$_.PackageFamilyName
            if ([string]::IsNullOrWhiteSpace([string]$pkgName) -and [string]::IsNullOrWhiteSpace([string]$pkgFamily)) {
                return $false
            }

            $pkgNameLower = $pkgName.ToLowerInvariant()
            $pkgFamilyLower = $pkgFamily.ToLowerInvariant()
            return (
                $pkgNameLower.Contains('openai.codex') -or
                $pkgFamilyLower.Contains('openai.codex') -or
                $pkgNameLower.Contains('codex') -or
                $pkgFamilyLower.Contains('codex')
            )
        }
    )
}

function Resolve-CodexExecutable {
    $preferredCandidate = Join-Path $env:ProgramFiles 'WindowsApps\OpenAI.Codex_26.306.996.0_x64__2p2nqsd0c76g0\app\Codex.exe'
    if (Test-Path -LiteralPath $preferredCandidate) {
        return [string]$preferredCandidate
    }

    foreach ($package in @(Get-CodexPackages)) {
        $installLocation = [string]$package.InstallLocation
        if ([string]::IsNullOrWhiteSpace([string]$installLocation)) {
            continue
        }

        foreach ($candidate in @(
            (Join-Path $installLocation 'app\Codex.exe'),
            (Join-Path $installLocation 'Codex.exe')
        )) {
            if (Test-Path -LiteralPath $candidate) {
                return [string]$candidate
            }
        }
    }

    return ''
}

function Resolve-CodexAppId {
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
            $nameText.ToLowerInvariant().Contains('codex') -or
            $appIdText.ToLowerInvariant().Contains('openai.codex') -or
            $appIdText.ToLowerInvariant().Contains('codex')
        )
    })

    foreach ($entry in @($startApps)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.AppID)) {
            return [string]$entry.AppID
        }
    }

    return ''
}

function Get-CodexInstallState {
    param([string]$WingetExe)

    $codexAppId = Resolve-CodexAppId
    if (-not [string]::IsNullOrWhiteSpace([string]$codexAppId)) {
        return [pscustomobject]@{
            Healthy = $true
            LaunchKind = 'app-id'
            LaunchTarget = [string]$codexAppId
            DetectionSource = 'app-id'
        }
    }

    $codexExe = Resolve-CodexExecutable
    if (-not [string]::IsNullOrWhiteSpace([string]$codexExe)) {
        return [pscustomobject]@{
            Healthy = $true
            LaunchKind = 'executable'
            LaunchTarget = [string]$codexExe
            DetectionSource = 'executable'
        }
    }

    $packages = @(Get-CodexPackages)
    if (@($packages).Count -gt 0) {
        return [pscustomobject]@{
            Healthy = $false
            LaunchKind = 'package-only'
            LaunchTarget = [string]$packages[0].PackageFamilyName
            DetectionSource = 'package'
        }
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$WingetExe)) {
        Write-Host 'Running: winget list codex'
        $listOutput = & $WingetExe list codex
        $listText = [string]($listOutput | Out-String)
        if (-not [string]::IsNullOrWhiteSpace([string]$listText)) {
            $normalizedList = $listText.ToLowerInvariant()
            if ($normalizedList.Contains('codex') -or $normalizedList.Contains('openai')) {
                return [pscustomobject]@{
                    Healthy = $false
                    LaunchKind = 'listed-only'
                    LaunchTarget = 'winget-list'
                    DetectionSource = 'winget'
                }
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
$wingetExe = Resolve-ClagnosWingetExe -PortableCandidate $portableWingetPath
if ([string]::IsNullOrWhiteSpace([string]$wingetExe)) {
    throw 'winget command is not available.'
}

Write-Host "Resolved winget executable: $wingetExe"
$existingState = Get-CodexInstallState -WingetExe $wingetExe
if ([bool]$existingState.Healthy) {
    Remove-ClagnosRunOnceEntry -Name $legacyRunOnceName
    $stateRecord = Write-ClagnosStoreInstallState -TaskName $taskName -State installed -Summary ('Codex app is launch-ready via {0}.' -f [string]$existingState.DetectionSource) -PackageId $packageId -RunOnceName $legacyRunOnceName -LaunchKind ([string]$existingState.LaunchKind) -LaunchTarget ([string]$existingState.LaunchTarget)
    Write-ClagnosStoreInstallStateStatusLine -TaskName $taskName -StateRecord $stateRecord
    Write-Host 'Existing Codex app installation is already healthy. Skipping winget install.'
    Write-Host 'install-codex-application-completed'
    Write-Host 'Update task completed: install-codex-application'
    return
}

if (Test-ClagnosRunOnceEntryPresent -Name $legacyRunOnceName) {
    Remove-ClagnosRunOnceEntry -Name $legacyRunOnceName
    Write-Host 'store-install-cleanup => task=120-install-codex-application; removed-stale-run-once=True'
}

$workerTaskName = "{0}-{1}" -f $taskName, $interactiveTaskSuffix
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

function Get-CodexPackages {
    $allPackages = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
    if (@($allPackages).Count -eq 0) {
        return @()
    }

    return @(
        $allPackages | Where-Object {
            $text = (([string]$_.Name) + ' ' + ([string]$_.PackageFamilyName)).ToLowerInvariant()
            return ($text.Contains('openai.codex') -or $text.Contains('codex'))
        }
    )
}

function Resolve-CodexExecutable {
    foreach ($package in @(Get-CodexPackages)) {
        $installLocation = [string]$package.InstallLocation
        if ([string]::IsNullOrWhiteSpace([string]$installLocation)) {
            continue
        }

        foreach ($candidate in @(
            (Join-Path $installLocation 'app\Codex.exe'),
            (Join-Path $installLocation 'Codex.exe')
        )) {
            if (Test-Path -LiteralPath $candidate) {
                return [string]$candidate
            }
        }
    }

    return ''
}

function Resolve-CodexAppId {
    if (-not (Get-Command Get-StartApps -ErrorAction SilentlyContinue)) {
        return ''
    }

    $startApps = @(Get-StartApps | Where-Object {
        $text = (([string]$_.Name) + ' ' + ([string]$_.AppID)).ToLowerInvariant()
        return ($text.Contains('openai.codex') -or $text.Contains('codex'))
    })

    foreach ($entry in @($startApps)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.AppID)) {
            return [string]$entry.AppID
        }
    }

    return ''
}

function Test-CodexInstalled {
    if (-not [string]::IsNullOrWhiteSpace([string](Resolve-CodexAppId))) {
        return $true
    }

    return (-not [string]::IsNullOrWhiteSpace([string](Resolve-CodexExecutable)))
}

Invoke-ClagnosRefreshSessionPath
$wingetExe = Resolve-ClagnosWingetExe -PortableCandidate "__PORTABLE_WINGET_PATH__"
if ([string]::IsNullOrWhiteSpace([string]$wingetExe)) {
    Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $false -Summary 'winget command is not available.'
    exit 1
}

if (-not (Test-CodexInstalled)) {
    $installOutput = @(& $wingetExe install --id $packageId --source msstore --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1)
    $installExit = [int]$LASTEXITCODE
    $installText = [string]($installOutput | Out-String)
    if ($installExit -ne 0 -and $installExit -ne -1978335189) {
        Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $false -Summary ("winget install failed with exit code {0}." -f $installExit) -Details @($installText)
        exit 1
    }
}

if (-not (Test-CodexInstalled)) {
    Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $false -Summary 'Codex app install could not be verified after interactive winget install.'
    exit 1
}

Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $true -Summary 'Codex app is installed.'
'@

$workerScript = $workerScript.Replace('__HELPER_PATH__', $helperPath)
$workerScript = $workerScript.Replace('__STORE_HELPER_PATH__', 'C:\Windows\Temp\clagnos-store-install-state.psm1')
$workerScript = $workerScript.Replace('__RESULT_PATH__', [string]$paths.ResultPath)
$workerScript = $workerScript.Replace('__TASK_NAME__', $workerTaskName)
$workerScript = $workerScript.Replace('__PACKAGE_ID__', $packageId)
$workerScript = $workerScript.Replace('__PORTABLE_WINGET_PATH__', $portableWingetPath)

try {
    $null = Invoke-ClagnosInteractiveDesktopAutomation `
        -TaskName $workerTaskName `
        -RunAsUser $managerUser `
        -RunAsPassword $managerPassword `
        -WorkerScriptText $workerScript `
        -WaitTimeoutSeconds $waitTimeoutSeconds `
        -RunAsMode 'password'
}
catch {
    Invoke-ClagnosRefreshSessionPath
    $catchState = Get-CodexInstallState -WingetExe $wingetExe
    if ([bool]$catchState.Healthy) {
        Remove-ClagnosRunOnceEntry -Name $legacyRunOnceName
        $stateRecord = Write-ClagnosStoreInstallState -TaskName $taskName -State installed -Summary ('Codex app is launch-ready via {0}.' -f [string]$catchState.DetectionSource) -PackageId $packageId -RunOnceName $legacyRunOnceName -LaunchKind ([string]$catchState.LaunchKind) -LaunchTarget ([string]$catchState.LaunchTarget)
        Write-ClagnosStoreInstallStateStatusLine -TaskName $taskName -StateRecord $stateRecord
        Write-Host 'install-codex-application-completed'
        Write-Host 'Update task completed: install-codex-application'
        return
    }

    $installError = [string]$_.Exception.Message
    $stateRecord = Write-ClagnosStoreInstallState -TaskName $taskName -State degraded -Summary ('Unattended Codex app install failed: {0}' -f $installError) -PackageId $packageId -RunOnceName $legacyRunOnceName -LaunchKind ([string]$catchState.LaunchKind) -LaunchTarget ([string]$catchState.LaunchTarget)
    Write-ClagnosStoreInstallStateStatusLine -TaskName $taskName -StateRecord $stateRecord
    throw
}

Invoke-ClagnosRefreshSessionPath
$finalState = Get-CodexInstallState -WingetExe $wingetExe
if (-not [bool]$finalState.Healthy) {
    $stateRecord = Write-ClagnosStoreInstallState -TaskName $taskName -State degraded -Summary ('Codex app is present but not yet launch-ready via a stable executable or AppID ({0}).' -f [string]$finalState.DetectionSource) -PackageId $packageId -RunOnceName $legacyRunOnceName -LaunchKind ([string]$finalState.LaunchKind) -LaunchTarget ([string]$finalState.LaunchTarget)
    Write-ClagnosStoreInstallStateStatusLine -TaskName $taskName -StateRecord $stateRecord
    throw 'Codex app install could not be verified.'
}

Remove-ClagnosRunOnceEntry -Name $legacyRunOnceName
$stateRecord = Write-ClagnosStoreInstallState -TaskName $taskName -State installed -Summary ('Codex app is launch-ready via {0}.' -f [string]$finalState.DetectionSource) -PackageId $packageId -RunOnceName $legacyRunOnceName -LaunchKind ([string]$finalState.LaunchKind) -LaunchTarget ([string]$finalState.LaunchTarget)
Write-ClagnosStoreInstallStateStatusLine -TaskName $taskName -StateRecord $stateRecord
Write-Host 'install-codex-application-completed'
Write-Host 'Update task completed: install-codex-application'

