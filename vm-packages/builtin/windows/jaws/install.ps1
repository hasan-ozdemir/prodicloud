$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-jaws-application"

$taskConfig = [ordered]@{
    PortableWingetPath = "C:\ProgramData\prodicloud\tools\winget-x64\winget.exe"
    PackageId = 'FreedomScientific.JAWS.2025'
    ProductLanguage = 'enu'
    InstallerUiLanguage = 'enu'
    DisableExternalServices = $true
    ManagerUser = '__VM_ADMIN_USER__'
    AssistantUser = '__ASSISTANT_USER__'
    AcceptableWingetExitCodes = @(0, -1978335189, -2147024894)
    JawsExeCandidates = @(
        "C:\Program Files\Freedom Scientific\JAWS\2025\jfw.exe",
        "C:\Program Files (x86)\Freedom Scientific\JAWS\2025\jfw.exe"
    )
    JawsRegistryRoots = @(
        'HKLM:\Software\Freedom Scientific\JAWS\2025',
        'HKLM:\Software\WOW6432Node\Freedom Scientific\JAWS\2025'
    )
    JawsInstallDirectory = 'C:\Program Files\Freedom Scientific\JAWS\2025'
    WingetSourceTimeoutSeconds = 45
    WingetCommandTimeoutSeconds = 120
    WingetInstallTimeoutSeconds = 300
    WingetInactivitySeconds = 60
    WingetHeartbeatSeconds = 15
    InstallVerifyTimeoutSeconds = 90
    InstallVerifyPollSeconds = 5
}

Import-Module 'C:\Windows\Temp\prodicloud-session-environment.psm1' -Force -DisableNameChecking

function Refresh-SessionPath {
    Refresh-ProdicloudSessionPath | Out-Null
}

function Resolve-WingetExe {
    $portableCandidate = [string]$taskConfig.PortableWingetPath
    if (Test-Path -LiteralPath $portableCandidate) {
        return [string]$portableCandidate
    }

    $cmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($cmd -and -not [string]::IsNullOrWhiteSpace([string]$cmd.Source)) {
        return [string]$cmd.Source
    }

    return ""
}

function Resolve-JawsRootFromRegistry {
    foreach ($registryPath in @($taskConfig.JawsRegistryRoots)) {
        if (-not (Test-Path -LiteralPath $registryPath)) {
            continue
        }

        $registryItem = Get-ItemProperty -LiteralPath $registryPath -ErrorAction SilentlyContinue
        $targetProperty = if ($null -ne $registryItem) { $registryItem.PSObject.Properties['Target'] } else { $null }
        $targetPath = if ($null -ne $targetProperty) { [string]$targetProperty.Value } else { '' }
        if ([string]::IsNullOrWhiteSpace([string]$targetPath)) {
            continue
        }

        $normalizedPath = $targetPath.Trim().TrimEnd('\')
        if (Test-Path -LiteralPath $normalizedPath) {
            return [string]$normalizedPath
        }
    }

    return ""
}

function Resolve-ExecutableUnderDirectory {
    param(
        [string]$RootPath,
        [string]$ExecutableName
    )

    if ([string]::IsNullOrWhiteSpace([string]$RootPath) -or [string]::IsNullOrWhiteSpace([string]$ExecutableName)) {
        return ""
    }

    if (-not (Test-Path -LiteralPath $RootPath)) {
        return ""
    }

    $directCandidate = Join-Path $RootPath $ExecutableName
    if (Test-Path -LiteralPath $directCandidate) {
        return [string]$directCandidate
    }

    $match = Get-ChildItem -LiteralPath $RootPath -Filter $ExecutableName -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName | Select-Object -First 1
    if ($match -and (Test-Path -LiteralPath $match.FullName)) {
        return [string]$match.FullName
    }

    return ""
}

function Resolve-JawsExe {
    $registryRoot = Resolve-JawsRootFromRegistry
    if (-not [string]::IsNullOrWhiteSpace([string]$registryRoot)) {
        $registryCandidate = Resolve-ExecutableUnderDirectory -RootPath $registryRoot -ExecutableName 'jfw.exe'
        if (-not [string]::IsNullOrWhiteSpace([string]$registryCandidate)) {
            return [string]$registryCandidate
        }
    }

    foreach ($candidate in @($taskConfig.JawsExeCandidates)) {
        if (Test-Path -LiteralPath $candidate) {
            return [string]$candidate
        }
    }

    return ""
}

function Set-JawsPostLogonStartup {
    param([string]$ExecutablePath)
    Set-ProdicloudJawsPostLogonStartup -UserNames @([string]$taskConfig.ManagerUser,[string]$taskConfig.AssistantUser) -Executable $ExecutablePath
}

function Get-WingetProcessActivitySnapshot {
    param([int]$RootProcessId)

    try { $processRows = @(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop) }
    catch { return $null }
    $trackedIds = New-Object 'System.Collections.Generic.HashSet[int]'
    [void]$trackedIds.Add([int]$RootProcessId)
    $expanded = $true
    while ($expanded) {
        $expanded = $false
        foreach ($process in @($processRows)) {
            if ($trackedIds.Contains([int]$process.ParentProcessId) -and $trackedIds.Add([int]$process.ProcessId)) { $expanded = $true }
        }
    }
    $cpuSeconds = 0.0
    $ioBytes = 0.0
    $memoryBytes = 0.0
    foreach ($process in @($processRows | Where-Object { $trackedIds.Contains([int]$_.ProcessId) })) {
        $cpuSeconds += ([double]$process.UserModeTime + [double]$process.KernelModeTime) / 10000000.0
        $ioBytes += [double]$process.ReadTransferCount + [double]$process.WriteTransferCount
        $memoryBytes += [double]$process.WorkingSetSize
    }
    $networkBytesPerSecond = 0.0
    $diskBytesPerSecond = 0.0
    try {
        foreach ($adapter in @(Get-CimInstance -ClassName Win32_PerfFormattedData_Tcpip_NetworkInterface -ErrorAction Stop)) {
            $networkBytesPerSecond += [double]$adapter.BytesReceivedPersec + [double]$adapter.BytesSentPersec
        }
    }
    catch { }
    try {
        $disk = @(Get-CimInstance -ClassName Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'" -ErrorAction Stop | Select-Object -First 1)
        if ($disk.Count -gt 0) { $diskBytesPerSecond = [double]$disk[0].DiskReadBytesPersec + [double]$disk[0].DiskWriteBytesPersec }
    }
    catch { }
    return [pscustomobject]@{
        ProcessCount = [int]$trackedIds.Count
        CpuSeconds = [double]$cpuSeconds
        IoBytes = [double]$ioBytes
        MemoryBytes = [double]$memoryBytes
        NetworkBytesPerSecond = [double]$networkBytesPerSecond
        DiskBytesPerSecond = [double]$diskBytesPerSecond
    }
}

function Stop-WingetProcessTree {
    param([int]$ProcessId)

    $taskkill = Join-Path $env:SystemRoot 'System32\taskkill.exe'
    if (Test-Path -LiteralPath $taskkill -PathType Leaf) { & $taskkill /F /T /PID ([string]$ProcessId) 2>$null | Out-Null }
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

function Invoke-BoundedWingetCommand {
    param(
        [string]$WingetExe,
        [string[]]$Arguments,
        [int]$TimeoutSeconds = 120,
        [int]$InactivitySeconds = 60
    )

    $runId = [Guid]::NewGuid().ToString('N')
    $stdoutPath = Join-Path $env:TEMP ('prodicloud-jaws-winget-' + $runId + '.stdout.log')
    $stderrPath = Join-Path $env:TEMP ('prodicloud-jaws-winget-' + $runId + '.stderr.log')
    $argumentLine = (@($Arguments | ForEach-Object {
        $argument = [string]$_
        if ($argument -match '[\s"]') { '"' + $argument.Replace('"','\"') + '"' } else { $argument }
    }) -join ' ')
    $startedAt = [DateTime]::UtcNow
    $process = $null
    try {
        Write-Host ("Doing: start bounded WinGet process (timeout={0}s; inactivity={1}s)" -f $TimeoutSeconds,$InactivitySeconds)
        $process = Start-Process -FilePath $WingetExe -ArgumentList $argumentLine -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -ErrorAction Stop
        $deadline = $startedAt.AddSeconds([int]$TimeoutSeconds)
        $lastProgressAt = [DateTime]::UtcNow
        $nextHeartbeatAt = [DateTime]::UtcNow.AddSeconds([int]$taskConfig.WingetHeartbeatSeconds)
        $previousActivity = Get-WingetProcessActivitySnapshot -RootProcessId ([int]$process.Id)
        $previousLogLength = 0L
        while ($true) {
            $process.Refresh()
            if ($process.HasExited) { break }
            if ([DateTime]::UtcNow -ge $deadline) {
                Stop-WingetProcessTree -ProcessId ([int]$process.Id)
                throw ("WinGet '{0}' exceeded its finite {1}-second deadline." -f [string]$Arguments[0],$TimeoutSeconds)
            }

            $currentLogLength = 0L
            foreach ($logPath in @($stdoutPath,$stderrPath)) { if (Test-Path -LiteralPath $logPath -PathType Leaf) { $currentLogLength += [int64](Get-Item -LiteralPath $logPath).Length } }
            $activity = Get-WingetProcessActivitySnapshot -RootProcessId ([int]$process.Id)
            $moved = ($currentLogLength -gt $previousLogLength)
            if ($null -ne $activity -and $null -ne $previousActivity) {
                if ([double]$activity.CpuSeconds - [double]$previousActivity.CpuSeconds -ge 0.25) { $moved = $true }
                if ([double]$activity.IoBytes -gt [double]$previousActivity.IoBytes) { $moved = $true }
                if ([Math]::Abs([double]$activity.MemoryBytes - [double]$previousActivity.MemoryBytes) -ge 32MB) { $moved = $true }
                if ([int]$activity.ProcessCount -ne [int]$previousActivity.ProcessCount) { $moved = $true }
                if ([double]$activity.NetworkBytesPerSecond -ge 4096.0 -or [double]$activity.DiskBytesPerSecond -ge 4096.0) { $moved = $true }
            }
            if ($moved) { $lastProgressAt = [DateTime]::UtcNow }
            $previousActivity = $activity
            $previousLogLength = $currentLogLength

            if (([DateTime]::UtcNow - $lastProgressAt).TotalSeconds -ge [int]$InactivitySeconds) {
                Stop-WingetProcessTree -ProcessId ([int]$process.Id)
                throw ("WinGet '{0}' made no measurable output, process, network, or disk progress for {1} seconds." -f [string]$Arguments[0],$InactivitySeconds)
            }
            if ([DateTime]::UtcNow -ge $nextHeartbeatAt) {
                $elapsed = [int]([DateTime]::UtcNow - $startedAt).TotalSeconds
                $cpu = if ($null -ne $activity) { [Math]::Round([double]$activity.CpuSeconds,1) } else { -1 }
                $io = if ($null -ne $activity) { [Math]::Round([double]$activity.IoBytes / 1MB,1) } else { -1 }
                $processCount = if ($null -ne $activity) { [int]$activity.ProcessCount } else { -1 }
                Write-Host ("Doing: WinGet '{0}' is running ({1}s; child-processes={2}; cpu={3}s; io={4}MB; log={5}bytes)" -f [string]$Arguments[0],$elapsed,$processCount,$cpu,$io,$currentLogLength) -ForegroundColor DarkCyan
                $nextHeartbeatAt = [DateTime]::UtcNow.AddSeconds([int]$taskConfig.WingetHeartbeatSeconds)
            }
            Start-Sleep -Seconds 3
        }
        $process.WaitForExit()
        $exitCode = [int]$process.ExitCode
        foreach ($logPath in @($stdoutPath,$stderrPath)) {
            if (-not (Test-Path -LiteralPath $logPath -PathType Leaf)) { continue }
            foreach ($line in @(Get-Content -LiteralPath $logPath -Tail 120 -ErrorAction SilentlyContinue)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$line)) { Write-Host ([string]$line) }
            }
        }
        $global:LASTEXITCODE = $exitCode
        return [pscustomobject]@{ ExitCode = [int]$exitCode; Output = (($stdoutPath,$stderrPath | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | ForEach-Object { Get-Content -LiteralPath $_ -Raw -ErrorAction SilentlyContinue }) -join [Environment]::NewLine) }
    }
    catch {
        if ($null -ne $process) { Stop-WingetProcessTree -ProcessId ([int]$process.Id) }
        throw
    }
    finally {
        foreach ($logPath in @($stdoutPath,$stderrPath)) { if (Test-Path -LiteralPath $logPath -PathType Leaf) { Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue } }
    }
}

function Invoke-WingetCommand {
    param([string]$WingetExe,[string[]]$Arguments)
    $commandTimeout = [int]$taskConfig.WingetCommandTimeoutSeconds
    if (@($Arguments).Count -gt 0 -and [string]$Arguments[0] -eq 'source') { $commandTimeout = [int]$taskConfig.WingetSourceTimeoutSeconds }
    if (@($Arguments).Count -gt 0 -and [string]$Arguments[0] -eq 'install') { $commandTimeout = [int]$taskConfig.WingetInstallTimeoutSeconds }
    $result = Invoke-BoundedWingetCommand -WingetExe $WingetExe -Arguments $Arguments -TimeoutSeconds $commandTimeout -InactivitySeconds ([int]$taskConfig.WingetInactivitySeconds)
    return [int]$result.ExitCode
}

function Ensure-WingetSourcesReady {
    param([string]$WingetExe)

    Write-Host "Running: winget source list"
    $listExit = Invoke-WingetCommand -WingetExe $WingetExe -Arguments @('source', 'list')
    if ($listExit -eq 0) {
        return
    }

    Write-Host ("jaws-step-repair: winget-source-list-exit={0}" -f $listExit)
    Write-Host "Running: winget source update"
    $updateExit = Invoke-WingetCommand -WingetExe $WingetExe -Arguments @('source', 'update')
    if ($updateExit -ne 0) {
        throw ("winget source update failed with exit code {0}." -f $updateExit)
    }

    Write-Host "Running: winget source list"
    $secondListExit = Invoke-WingetCommand -WingetExe $WingetExe -Arguments @('source', 'list')
    if ($secondListExit -ne 0) {
        throw ("winget source list failed with exit code {0} after bounded repair." -f $secondListExit)
    }
}

function Wait-JawsInstallVerified {
    $deadline = [DateTime]::UtcNow.AddSeconds([int]$taskConfig.InstallVerifyTimeoutSeconds)
    $startedAt = [DateTime]::UtcNow
    $nextHeartbeatAt = $startedAt.AddSeconds([int]$taskConfig.WingetHeartbeatSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        Refresh-SessionPath
        $resolvedExe = Resolve-JawsExe
        if (-not [string]::IsNullOrWhiteSpace([string]$resolvedExe)) {
            return [string]$resolvedExe
        }
        if ([DateTime]::UtcNow -ge $nextHeartbeatAt) {
            Write-Host ("Doing: wait for JAWS executable registration ({0}s elapsed)" -f [int]([DateTime]::UtcNow - $startedAt).TotalSeconds) -ForegroundColor DarkCyan
            $nextHeartbeatAt = [DateTime]::UtcNow.AddSeconds([int]$taskConfig.WingetHeartbeatSeconds)
        }

        Start-Sleep -Seconds ([int]$taskConfig.InstallVerifyPollSeconds)
    }

    return (Resolve-JawsExe)
}

function Save-JawsInstallPolicyState {
    param([string]$ExecutablePath,[string]$InstallerArguments)

    $stateDirectory = Join-Path $env:ProgramData 'prodicloud\state\packages'
    if (-not (Test-Path -LiteralPath $stateDirectory -PathType Container)) { New-Item -ItemType Directory -Path $stateDirectory -Force -ErrorAction Stop | Out-Null }
    $statePath = Join-Path $stateDirectory 'jaws-install-policy.json'
    $version = ''
    try { $version = [string](Get-Item -LiteralPath $ExecutablePath -ErrorAction Stop).VersionInfo.ProductVersion } catch { }
    $state = [ordered]@{
        PackageId = [string]$taskConfig.PackageId
        ProductLanguage = [string]$taskConfig.ProductLanguage
        InstallerUiLanguage = [string]$taskConfig.InstallerUiLanguage
        DisableExternalServices = [bool]$taskConfig.DisableExternalServices
        InstallerArguments = [string]$InstallerArguments
        InstalledVersion = [string]$version
        RecordedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    [IO.File]::WriteAllText($statePath,(ConvertTo-Json -InputObject $state -Depth 8 -Compress),(New-Object System.Text.UTF8Encoding($false)))
    $verified = Get-Content -LiteralPath $statePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ([string]$verified.PackageId -ne [string]$taskConfig.PackageId -or [string]$verified.ProductLanguage -ne 'enu' -or [string]$verified.InstallerUiLanguage -ne 'enu' -or -not [bool]$verified.DisableExternalServices -or [string]$verified.InstallerArguments -notmatch '(?i)/Language\s+enu' -or [string]$verified.InstallerArguments -notmatch '(?i)/DisableExternalServices') {
        throw 'JAWS ENU/offline install policy state did not verify after the successful installer run.'
    }
    Write-Host 'JAWS installation policy verified: product language ENU, installer UI ENU, external services disabled.'
}

function Test-JawsPackageListed {
    param(
        [string]$WingetExe,
        [string]$PackageId
    )

    Write-Host ("Running: winget list --id {0} --exact" -f $PackageId)
    $listResult = Invoke-BoundedWingetCommand -WingetExe $WingetExe -Arguments @('list','--id',$PackageId,'--exact','--accept-source-agreements','--disable-interactivity') -TimeoutSeconds ([int]$taskConfig.WingetCommandTimeoutSeconds) -InactivitySeconds ([int]$taskConfig.WingetInactivitySeconds)
    $listExit = [int]$listResult.ExitCode
    $listText = [string]$listResult.Output
    return ($listExit -eq 0 -and -not [string]::IsNullOrWhiteSpace($listText) -and $listText.ToLowerInvariant().Contains("jaws"))
}

function Test-JawsInstallRegistered {
    $resolvedExe = Resolve-JawsExe
    if (-not [string]::IsNullOrWhiteSpace([string]$resolvedExe)) {
        return $true
    }

    $registryRoot = Resolve-JawsRootFromRegistry
    if (-not [string]::IsNullOrWhiteSpace([string]$registryRoot) -and (Test-Path -LiteralPath $registryRoot)) {
        return $true
    }

    return $false
}

Refresh-SessionPath
$existingExe = Resolve-JawsExe
if (-not [string]::IsNullOrWhiteSpace([string]$existingExe)) {
    Write-Host ("Existing JAWS installation is already healthy. Skipping winget install. exe={0}" -f $existingExe)
    Install-ProdicloudJawsAppStateUpdateFiles
    Set-JawsPostLogonStartup -ExecutablePath $existingExe
    Write-Host "install-jaws-application-completed"
    Write-Host "Update task completed: install-jaws-application"
    return
}

$wingetExe = Resolve-WingetExe
if ([string]::IsNullOrWhiteSpace([string]$wingetExe)) {
    throw "winget command is not available."
}

$packageId = [string]$taskConfig.PackageId
Write-Host "Resolved winget executable: $wingetExe"
Ensure-WingetSourcesReady -WingetExe $wingetExe

$finalInstallExit = 0
$installedExe = ""
$customInstallerArguments = @('/Language',[string]$taskConfig.ProductLanguage,'/InstallerUILanguage',[string]$taskConfig.InstallerUiLanguage)
if ([bool]$taskConfig.DisableExternalServices) { $customInstallerArguments += '/DisableExternalServices' }
$customInstallerArgumentString = $customInstallerArguments -join ' '
$requiredVersion = [string]$env:PRODICLOUD_JAWS_REQUIRED_VERSION
$forceInstall = [string]$env:PRODICLOUD_JAWS_FORCE_INSTALL -match '^(?i)(1|true|yes|on)$'
if (-not [string]::IsNullOrWhiteSpace($requiredVersion)) {
    Write-Host ("JAWS repair is pinned to installed version {0}." -f $requiredVersion)
}
foreach ($attempt in 1..2) {
    $installArguments = @('install', '--id', $packageId, '--exact', '--accept-source-agreements', '--accept-package-agreements', '--silent', '--disable-interactivity', '--custom', $customInstallerArgumentString)
    if (-not [string]::IsNullOrWhiteSpace($requiredVersion)) { $installArguments += @('--version',$requiredVersion) }
    if ($forceInstall) { $installArguments += '--force' }
    Write-Host ("Running: winget {0}" -f (($installArguments | ForEach-Object { if ([string]$_ -match '\s') { '"' + [string]$_ + '"' } else { [string]$_ } }) -join ' '))
    $finalInstallExit = Invoke-WingetCommand -WingetExe $wingetExe -Arguments $installArguments

    $installedExe = Wait-JawsInstallVerified
    if (-not [string]::IsNullOrWhiteSpace([string]$installedExe)) {
        break
    }

    if (@($taskConfig.AcceptableWingetExitCodes) -contains $finalInstallExit) {
        if ((Test-JawsPackageListed -WingetExe $wingetExe -PackageId $packageId) -or (Test-JawsInstallRegistered)) {
            Write-Host ("jaws-step-readback: tolerated-winget-exit={0}" -f $finalInstallExit)
            Start-Sleep -Seconds ([int]$taskConfig.InstallVerifyPollSeconds)
            $installedExe = Wait-JawsInstallVerified
            if (-not [string]::IsNullOrWhiteSpace([string]$installedExe)) {
                break
            }
        }
    }

    if ($attempt -lt 2) {
        Write-Host ("jaws-step-retry: winget-exit={0}; attempt={1}" -f $finalInstallExit, $attempt)
        Ensure-WingetSourcesReady -WingetExe $wingetExe
        Start-Sleep -Seconds 5
    }
}

if ([string]::IsNullOrWhiteSpace([string]$installedExe)) {
    if ((Test-JawsPackageListed -WingetExe $wingetExe -PackageId $packageId) -or (Test-JawsInstallRegistered)) {
        throw "JAWS install did not materialize a launchable jfw.exe after winget reported the package."
    }

    throw ("winget install {0} failed with exit code {1}." -f $packageId, $finalInstallExit)
}

Install-ProdicloudJawsAppStateUpdateFiles
Set-JawsPostLogonStartup -ExecutablePath $installedExe
Save-JawsInstallPolicyState -ExecutablePath $installedExe -InstallerArguments $customInstallerArgumentString
Write-Host "install-jaws-application-completed"
Write-Host "Update task completed: install-jaws-application"
