$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-icloud-application"

$taskConfig = [ordered]@{
    TaskName = '122-install-icloud-application'
    ManagerUser = '__VM_ADMIN_USER__'
    ManagerPassword = '__VM_ADMIN_PASS__'
    HelperPath = 'C:\Windows\Temp\prodicloud-interactive-session-helper.ps1'
    StoreHelperPath = 'C:\Windows\Temp\prodicloud-store-install-state.psm1'
    PortableWingetPath = 'C:\ProgramData\prodicloud\tools\winget-x64\winget.exe'
    PackageId = '9PKTQ5699M62'
    PackageSource = 'msstore'
    DisplayNameFragments = @('icloud', 'appleinc.icloud')
    ExecutableName = 'iCloudHome.exe'
    InteractiveTaskSuffix = 'interactive-install'
    LegacyRunOnceName = 'ProdicloudInstallICloud'
    WaitTimeoutSeconds = 240
    ExecutableCandidates = @(
        'C:\Program Files\iCloud\iCloudHome.exe',
        'C:\Program Files (x86)\iCloud\iCloudHome.exe',
        'C:\Program Files\WindowsApps\AppleInc.iCloud_15.7.56.0_x64__nzyj5cx40ttqa\iCloud\iCloudHome.exe'
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

function Test-ICloudNameMatch {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return $false
    }

    $normalizedValue = $Value.Trim().ToLowerInvariant()
    foreach ($fragment in @($taskConfig.DisplayNameFragments)) {
        $normalizedFragment = [string]$fragment
        if ([string]::IsNullOrWhiteSpace([string]$normalizedFragment)) {
            continue
        }

        if ($normalizedValue.Contains($normalizedFragment.Trim().ToLowerInvariant())) {
            return $true
        }
    }

    return $false
}

function Resolve-ICloudAppId {
    $packages = @(Get-ICloudPackages)
    foreach ($package in @($packages)) {
        $installLocation = [string]$package.InstallLocation
        if ([string]::IsNullOrWhiteSpace([string]$installLocation) -or -not (Test-Path -LiteralPath $installLocation)) {
            continue
        }

        $manifestPath = Join-Path $installLocation 'AppxManifest.xml'
        if (-not (Test-Path -LiteralPath $manifestPath)) {
            continue
        }

        try {
            [xml]$manifestXml = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop
            $appNodes = @($manifestXml.SelectNodes("//*[local-name()='Application']"))
            foreach ($appNode in @($appNodes)) {
                $applicationId = [string]$appNode.GetAttribute('Id')
                if ([string]::IsNullOrWhiteSpace([string]$applicationId)) {
                    continue
                }

                return ("{0}!{1}" -f [string]$package.PackageFamilyName, $applicationId)
            }
        }
        catch {
        }
    }

    if (-not (Get-Command Get-StartApps -ErrorAction SilentlyContinue)) {
        return ''
    }

    $packageFamilies = @(
        $packages |
            ForEach-Object { [string]$_.PackageFamilyName } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
    )
    $startApps = @(Get-StartApps | Where-Object {
        $appIdText = [string]$_.AppID
        foreach ($family in @($packageFamilies)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$appIdText) -and
                $appIdText.StartsWith(($family + '!'), [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }

        return $false
    })

    foreach ($entry in @($startApps)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.AppID)) {
            return [string]$entry.AppID
        }
    }

    return ''
}

function Test-ICloudAppId {
    param([string]$AppId)

    if ([string]::IsNullOrWhiteSpace([string]$AppId)) {
        return $false
    }

    if ([string]$AppId -match '(?i)filepicker') {
        return $false
    }

    return ([string]$AppId -match '(?i)icloud|apple')
}

function Get-ICloudPackages {
    return @(
        Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object {
            Test-ICloudNameMatch -Value ([string]$_.Name) -or
            Test-ICloudNameMatch -Value ([string]$_.PackageFamilyName)
        }
    )
}

function Resolve-ICloudExeFromAppxPackage {
    $packages = @(Get-ICloudPackages)

    foreach ($package in @($packages)) {
        $installLocation = [string]$package.InstallLocation
        if ([string]::IsNullOrWhiteSpace([string]$installLocation) -or -not (Test-Path -LiteralPath $installLocation)) {
            continue
        }

        $directCandidate = Join-Path $installLocation ('iCloud\' + [string]$taskConfig.ExecutableName)
        if (Test-Path -LiteralPath $directCandidate) {
            return [string]$directCandidate
        }

        $flatCandidate = Join-Path $installLocation ([string]$taskConfig.ExecutableName)
        if (Test-Path -LiteralPath $flatCandidate) {
            return [string]$flatCandidate
        }

        $match = Get-ChildItem -LiteralPath $installLocation -Filter ([string]$taskConfig.ExecutableName) -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($match -and (Test-Path -LiteralPath $match.FullName)) {
            return [string]$match.FullName
        }
    }

    return ''
}

function Resolve-ICloudExe {
    $appxResolved = Resolve-ICloudExeFromAppxPackage
    if (-not [string]::IsNullOrWhiteSpace([string]$appxResolved)) {
        return [string]$appxResolved
    }

    $command = Get-Command ([string]$taskConfig.ExecutableName) -ErrorAction SilentlyContinue
    if ($command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source) -and (Test-Path -LiteralPath ([string]$command.Source))) {
        return [string]$command.Source
    }

    foreach ($candidate in @($taskConfig.ExecutableCandidates)) {
        if ([string]::IsNullOrWhiteSpace([string]$candidate)) {
            continue
        }

        if (Test-Path -LiteralPath $candidate) {
            return [string]$candidate
        }
    }

    return ''
}

function Get-ICloudInstallState {
    $appId = Resolve-ICloudAppId
    if (Test-ICloudAppId -AppId ([string]$appId)) {
        return [pscustomobject]@{
            Healthy = $true
            LaunchKind = 'app-id'
            LaunchTarget = [string]$appId
            DetectionSource = 'app-id'
        }
    }

    $resolvedExe = Resolve-ICloudExe
    if (-not [string]::IsNullOrWhiteSpace([string]$resolvedExe)) {
        return [pscustomobject]@{
            Healthy = $true
            LaunchKind = 'executable'
            LaunchTarget = [string]$resolvedExe
            DetectionSource = 'executable'
        }
    }

    $packages = @(Get-ICloudPackages)
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

Invoke-ProdicloudRefreshSessionPath
$existingState = Get-ICloudInstallState
if ([bool]$existingState.Healthy) {
    Remove-ProdicloudRunOnceEntry -Name ([string]$taskConfig.LegacyRunOnceName)
    $stateRecord = Write-ProdicloudStoreInstallState -TaskName $taskName -State installed -Summary ('iCloud is launch-ready via {0}.' -f [string]$existingState.DetectionSource) -PackageId ([string]$taskConfig.PackageId) -RunOnceName ([string]$taskConfig.LegacyRunOnceName) -LaunchKind ([string]$existingState.LaunchKind) -LaunchTarget ([string]$existingState.LaunchTarget)
    Write-ProdicloudStoreInstallStateStatusLine -TaskName $taskName -StateRecord $stateRecord
    if ([string]::Equals([string]$existingState.LaunchKind, 'executable', [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host ("icloud-home-exe => {0}" -f [string]$existingState.LaunchTarget)
    }
    Write-Host 'install-icloud-application-completed'
    Write-Host 'Update task completed: install-icloud-application'
    return
}

$wingetExe = Resolve-ProdicloudWingetExe -PortableCandidate ([string]$taskConfig.PortableWingetPath)
if ([string]::IsNullOrWhiteSpace([string]$wingetExe)) {
    throw 'winget command is not available.'
}

Write-Host "Resolved winget executable: $wingetExe"
if (Test-ProdicloudRunOnceEntryPresent -Name ([string]$taskConfig.LegacyRunOnceName)) {
    Remove-ProdicloudRunOnceEntry -Name ([string]$taskConfig.LegacyRunOnceName)
    Write-Host 'store-install-cleanup => task=122-install-icloud-application; removed-stale-run-once=True'
}

$workerTaskName = "{0}-{1}" -f $taskName, ([string]$taskConfig.InteractiveTaskSuffix)
$paths = Get-ProdicloudInteractivePaths -TaskName $workerTaskName
$workerScript = @'
$ErrorActionPreference = "Stop"
$helperPath = "__HELPER_PATH__"
$storeHelperPath = "__STORE_HELPER_PATH__"
$resultPath = "__RESULT_PATH__"
$taskName = "__TASK_NAME__"
$packageId = "__PACKAGE_ID__"
$packageSource = "__PACKAGE_SOURCE__"

. $helperPath
Import-Module $storeHelperPath -Force -DisableNameChecking

function Test-ICloudNameMatch {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return $false
    }

    $normalizedValue = $Value.Trim().ToLowerInvariant()
    foreach ($fragment in @('icloud', 'appleinc.icloud')) {
        if ($normalizedValue.Contains([string]$fragment)) {
            return $true
        }
    }

    return $false
}

function Resolve-ICloudAppId {
    $packages = @(
        Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object {
            Test-ICloudNameMatch -Value ([string]$_.Name) -or
            Test-ICloudNameMatch -Value ([string]$_.PackageFamilyName)
        }
    )

    foreach ($package in @($packages)) {
        $installLocation = [string]$package.InstallLocation
        if ([string]::IsNullOrWhiteSpace([string]$installLocation) -or -not (Test-Path -LiteralPath $installLocation)) {
            continue
        }

        $manifestPath = Join-Path $installLocation 'AppxManifest.xml'
        if (-not (Test-Path -LiteralPath $manifestPath)) {
            continue
        }

        try {
            [xml]$manifestXml = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop
            $appNodes = @($manifestXml.SelectNodes("//*[local-name()='Application']"))
            foreach ($appNode in @($appNodes)) {
                $applicationId = [string]$appNode.GetAttribute('Id')
                if ([string]::IsNullOrWhiteSpace([string]$applicationId)) {
                    continue
                }

                return ("{0}!{1}" -f [string]$package.PackageFamilyName, $applicationId)
            }
        }
        catch {
        }
    }

    if (-not (Get-Command Get-StartApps -ErrorAction SilentlyContinue)) {
        return ''
    }

    $packageFamilies = @(
        $packages |
            ForEach-Object { [string]$_.PackageFamilyName } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
    )
    $startApps = @(Get-StartApps | Where-Object {
        $appIdText = [string]$_.AppID
        foreach ($family in @($packageFamilies)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$appIdText) -and
                $appIdText.StartsWith(($family + '!'), [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }

        return $false
    })

    foreach ($entry in @($startApps)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.AppID)) {
            return [string]$entry.AppID
        }
    }

    return ''
}

function Test-ICloudAppId {
    param([string]$AppId)

    if ([string]::IsNullOrWhiteSpace([string]$AppId)) {
        return $false
    }

    if ([string]$AppId -match '(?i)filepicker') {
        return $false
    }

    return ([string]$AppId -match '(?i)icloud|apple')
}

function Test-ICloudInstalled {
    return (Test-ICloudAppId -AppId ([string](Resolve-ICloudAppId)))
}

Invoke-ProdicloudRefreshSessionPath
$wingetExe = Resolve-ProdicloudWingetExe -PortableCandidate "__PORTABLE_WINGET_PATH__"
if ([string]::IsNullOrWhiteSpace([string]$wingetExe)) {
    Write-ProdicloudInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $false -Summary 'winget command is not available.'
    exit 1
}

if (-not (Test-ICloudInstalled)) {
    $installOutput = @(& $wingetExe install --id $packageId --source $packageSource --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1)
    $installExit = [int]$LASTEXITCODE
    $installText = [string]($installOutput | Out-String)
    if ($installExit -ne 0 -and $installExit -ne -1978335189) {
        Write-ProdicloudInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $false -Summary ("winget install failed with exit code {0}." -f $installExit) -Details @($installText)
        exit 1
    }
}

if (-not (Test-ICloudInstalled)) {
    Write-ProdicloudInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $false -Summary 'iCloud install could not be verified after interactive winget install.'
    exit 1
}

Write-ProdicloudInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $true -Summary 'iCloud is installed.'
'@

$workerScript = $workerScript.Replace('__HELPER_PATH__', $helperPath)
$workerScript = $workerScript.Replace('__STORE_HELPER_PATH__', [string]$taskConfig.StoreHelperPath)
$workerScript = $workerScript.Replace('__RESULT_PATH__', [string]$paths.ResultPath)
$workerScript = $workerScript.Replace('__TASK_NAME__', $workerTaskName)
$workerScript = $workerScript.Replace('__PACKAGE_ID__', [string]$taskConfig.PackageId)
$workerScript = $workerScript.Replace('__PACKAGE_SOURCE__', [string]$taskConfig.PackageSource)
$workerScript = $workerScript.Replace('__PORTABLE_WINGET_PATH__', [string]$taskConfig.PortableWingetPath)

try {
    $null = Invoke-ProdicloudInteractiveDesktopAutomation `
        -TaskName $workerTaskName `
        -RunAsUser $managerUser `
        -RunAsPassword $managerPassword `
        -WorkerScriptText $workerScript `
        -WaitTimeoutSeconds ([int]$taskConfig.WaitTimeoutSeconds) `
        -RunAsMode 'password'
}
catch {
    Invoke-ProdicloudRefreshSessionPath
    $catchState = Get-ICloudInstallState
    if ([bool]$catchState.Healthy) {
        Remove-ProdicloudRunOnceEntry -Name ([string]$taskConfig.LegacyRunOnceName)
        $stateRecord = Write-ProdicloudStoreInstallState -TaskName $taskName -State installed -Summary ('iCloud is launch-ready via {0}.' -f [string]$catchState.DetectionSource) -PackageId ([string]$taskConfig.PackageId) -RunOnceName ([string]$taskConfig.LegacyRunOnceName) -LaunchKind ([string]$catchState.LaunchKind) -LaunchTarget ([string]$catchState.LaunchTarget)
        Write-ProdicloudStoreInstallStateStatusLine -TaskName $taskName -StateRecord $stateRecord
        if ([string]::Equals([string]$catchState.LaunchKind, 'executable', [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Host ("icloud-home-exe => {0}" -f [string]$catchState.LaunchTarget)
        }
        Write-Host 'install-icloud-application-completed'
        Write-Host 'Update task completed: install-icloud-application'
        return
    }

    $installError = [string]$_.Exception.Message
    $stateRecord = Write-ProdicloudStoreInstallState -TaskName $taskName -State degraded -Summary ('Unattended iCloud install failed: {0}' -f $installError) -PackageId ([string]$taskConfig.PackageId) -RunOnceName ([string]$taskConfig.LegacyRunOnceName) -LaunchKind ([string]$catchState.LaunchKind) -LaunchTarget ([string]$catchState.LaunchTarget)
    Write-ProdicloudStoreInstallStateStatusLine -TaskName $taskName -StateRecord $stateRecord
    throw
}

Invoke-ProdicloudRefreshSessionPath
$finalState = Get-ICloudInstallState
if (-not [bool]$finalState.Healthy) {
    $stateRecord = Write-ProdicloudStoreInstallState -TaskName $taskName -State degraded -Summary ('iCloud is present but not yet launch-ready via a stable executable or AppID ({0}).' -f [string]$finalState.DetectionSource) -PackageId ([string]$taskConfig.PackageId) -RunOnceName ([string]$taskConfig.LegacyRunOnceName) -LaunchKind ([string]$finalState.LaunchKind) -LaunchTarget ([string]$finalState.LaunchTarget)
    Write-ProdicloudStoreInstallStateStatusLine -TaskName $taskName -StateRecord $stateRecord
    throw 'iCloud install could not be verified.'
}

Remove-ProdicloudRunOnceEntry -Name ([string]$taskConfig.LegacyRunOnceName)
$stateRecord = Write-ProdicloudStoreInstallState -TaskName $taskName -State installed -Summary ('iCloud is launch-ready via {0}.' -f [string]$finalState.DetectionSource) -PackageId ([string]$taskConfig.PackageId) -RunOnceName ([string]$taskConfig.LegacyRunOnceName) -LaunchKind ([string]$finalState.LaunchKind) -LaunchTarget ([string]$finalState.LaunchTarget)
Write-ProdicloudStoreInstallStateStatusLine -TaskName $taskName -StateRecord $stateRecord
if ([string]::Equals([string]$finalState.LaunchKind, 'executable', [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Host ("icloud-home-exe => {0}" -f [string]$finalState.LaunchTarget)
}

Write-Host 'install-icloud-application-completed'
Write-Host 'Update task completed: install-icloud-application'

