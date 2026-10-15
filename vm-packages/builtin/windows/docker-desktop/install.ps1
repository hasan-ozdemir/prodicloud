$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-docker-desktop-application"

$taskConfig = [ordered]@{
    TaskName = '134-install-docker-desktop-application'
    ManagerUser = '__VM_ADMIN_USER__'
    ManagerPassword = '__VM_ADMIN_PASS__'
    InteractiveHelperPath = 'C:\Windows\Temp\clagnos-interactive-session-helper.ps1'
    InteractiveLaunchTaskSuffix = 'interactive-launch'
    PortableWingetPath = 'C:\ProgramData\clagnos\tools\winget-x64\winget.exe'
    DockerDesktopPackageId = 'Docker.DockerDesktop'
    DockerDesktopExecutablePath = 'C:\Program Files\Docker\Docker\Docker Desktop.exe'
    DockerServiceName = 'com.docker.service'
    DockerUsersGroupName = 'docker-users'
    DockerUsersGroupDescription = 'Docker Desktop Users'
    DockerMachinePathEntry = 'C:\Program Files\Docker\Docker\resources\bin'
    DockerStartupShortcutPath = (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp\Docker Desktop.lnk')
    DockerInstallTimeoutSeconds = 900
    DockerVersionTimeoutSeconds = 8
    DockerStatusTimeoutSeconds = 30
    DockerInfoTimeoutSeconds = 45
    DockerDesktopStartTimeoutSeconds = 90
    DockerReadinessTimeoutSeconds = 360
    DockerReadinessPollSeconds = 5
    InteractiveDesktopWaitSeconds = 45
    InteractiveLaunchTimeoutSeconds = 120
    DockerWslBootstrapTimeoutSeconds = 180
    DockerPrerequisiteServices = @('vmcompute', 'hns', 'wslservice', 'LxssManager')
    DockerLocalUsers = @('__VM_ADMIN_USER__', '__ASSISTANT_USER__')
}

Import-Module 'C:\Windows\Temp\clagnos-session-environment.psm1' -Force -DisableNameChecking

$interactiveHelperPath = [string]$taskConfig.InteractiveHelperPath
if (-not (Test-Path -LiteralPath $interactiveHelperPath)) {
    throw ("Interactive session helper was not found: {0}" -f $interactiveHelperPath)
}

. $interactiveHelperPath

function Refresh-SessionPath {
    Refresh-ClagnosSessionPath | Out-Null
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

function Resolve-DockerExePath {
    $dockerCommand = Get-Command docker -ErrorAction SilentlyContinue
    if ($dockerCommand -and -not [string]::IsNullOrWhiteSpace([string]$dockerCommand.Source)) {
        return [string]$dockerCommand.Source
    }

    $candidate = 'C:\Program Files\Docker\Docker\resources\bin\docker.exe'
    if (Test-Path -LiteralPath $candidate) {
        return [string]$candidate
    }

    return 'docker'
}

function Convert-CimDateTimeToUtc {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }

    try {
        return [System.Management.ManagementDateTimeConverter]::ToDateTime([string]$Value).ToUniversalTime()
    }
    catch {
        return $null
    }
}

function Get-StaleInstallerProcesses {
    $nowUtc = [DateTime]::UtcNow
    $nameRegex = '^(winget|msiexec|MSTeamsSetupx64|AppInstallerCLI|WindowsPackageManagerServer)\.exe$'
    $processes = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $name = [string]$_.Name
        $commandLine = [string]$_.CommandLine
        $matchesKnownInstaller = ($name -match $nameRegex)
        $matchesDockerInstall = ($commandLine -match 'Docker\.DockerDesktop|Docker Desktop Installer|DockerDesktopInstaller')
        $matchesPortableWinget = ($commandLine -match 'ProgramData\\clagnos\\tools\\winget-x64')
        $matchesInstallState = ($commandLine -match 'WinGet\\defaultState')
        if (-not ($matchesKnownInstaller -or $matchesDockerInstall -or $matchesPortableWinget -or $matchesInstallState)) {
            return $false
        }

        $createdUtc = Convert-CimDateTimeToUtc -Value ([string]$_.CreationDate)
        if ($null -eq $createdUtc) {
            return $true
        }

        return (($nowUtc - $createdUtc).TotalSeconds -ge 20)
    } | Select-Object ProcessId, Name, CommandLine, CreationDate

    return @($processes)
}

function Format-InstallerProcessSummary {
    param(
        [object[]]$Processes
    )

    if ($null -eq $Processes -or @($Processes).Count -eq 0) {
        return '(none)'
    }

    return (@($Processes) | ForEach-Object {
        $commandLine = [string]$_.CommandLine
        if ($commandLine.Length -gt 160) {
            $commandLine = $commandLine.Substring(0, 160) + '...'
        }

        return ("{0}:{1}:{2}" -f [int]$_.ProcessId, [string]$_.Name, $commandLine)
    }) -join ' | '
}

function Stop-StaleInstallerProcesses {
    $staleProcesses = Get-StaleInstallerProcesses
    if (@($staleProcesses).Count -eq 0) {
        return @()
    }

    Write-Host ("Stopping stale installer processes before Docker Desktop install: {0}" -f (Format-InstallerProcessSummary -Processes $staleProcesses))
    foreach ($proc in @($staleProcesses | Sort-Object ProcessId -Descending)) {
        try {
            Stop-Process -Id ([int]$proc.ProcessId) -Force -ErrorAction Stop
        }
        catch {
        }
    }

    Start-Sleep -Seconds 1
    $remaining = Get-StaleInstallerProcesses
    if (@($remaining).Count -gt 0) {
        throw ("Stale installer processes still active before Docker Desktop install: {0}" -f (Format-InstallerProcessSummary -Processes $remaining))
    }

    return @($staleProcesses)
}

function Ensure-MachinePathEntry {
    param([string]$Entry)

    if ([string]::IsNullOrWhiteSpace([string]$Entry)) {
        return $false
    }

    $normalizedEntry = [string]$Entry.Trim()
    if (-not (Test-Path -LiteralPath $normalizedEntry)) {
        return $false
    }

    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $parts = @($machinePath -split ";" | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    foreach ($part in @($parts)) {
        if ([string]::Equals($part, $normalizedEntry, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
    }

    $newPath = if ([string]::IsNullOrWhiteSpace($machinePath)) { $normalizedEntry } else { "$machinePath;$normalizedEntry" }
    [Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
    return $true
}

function Ensure-LocalGroupMembership {
    param(
        [string]$GroupName,
        [string]$MemberName
    )

    if (-not (Get-LocalGroup -Name $GroupName -ErrorAction SilentlyContinue)) {
        New-LocalGroup -Name $GroupName -Description ([string]$taskConfig.DockerUsersGroupDescription) -ErrorAction Stop | Out-Null
    }

    try {
        Add-LocalGroupMember -Group $GroupName -Member $MemberName -ErrorAction Stop
        Write-Host "docker-step-ok: docker-users membership added for $MemberName"
    }
    catch {
        if ($_.Exception.Message -match '(?i)already a member') {
            Write-Host "docker-step-ok: docker-users membership already exists for $MemberName"
            return
        }

        throw
    }
}

function Invoke-ProcessWithTimeout {
    param(
        [string]$Label,
        [string]$FilePath,
        [string[]]$Arguments = @(),
        [int]$TimeoutSeconds = 30
    )

    if ($TimeoutSeconds -lt 5) { $TimeoutSeconds = 5 }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = ($Arguments | ForEach-Object { if ($_ -match '\s') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    Write-Host ("Running: {0}" -f $Label)
    [void]$proc.Start()
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()
    $completed = $proc.WaitForExit([int]($TimeoutSeconds * 1000))
    if (-not $completed) {
        $activeInstallers = Get-StaleInstallerProcesses
        if (@($activeInstallers).Count -gt 0) {
            Write-Host ("Stopping installer processes after timeout: {0}" -f (Format-InstallerProcessSummary -Processes $activeInstallers))
            foreach ($installerProc in @($activeInstallers | Sort-Object ProcessId -Descending)) {
                try {
                    Stop-Process -Id ([int]$installerProc.ProcessId) -Force -ErrorAction Stop
                }
                catch {
                }
            }
        }
        try { $proc.Kill() } catch { }
        try { [void]$proc.WaitForExit() } catch { }
        Write-Warning ("{0} did not complete in time. Active installer processes: {1}" -f $Label, (Format-InstallerProcessSummary -Processes $activeInstallers))
        return [pscustomobject]@{ Success = $false; ExitCode = 124; TimedOut = $true; StdOut = ""; StdErr = ""; ActiveInstallerProcesses = @($activeInstallers) }
    }

    [void]$proc.WaitForExit()
    $stdOut = ""
    $stdErr = ""
    try { $stdOut = [string]$stdoutTask.Result } catch { }
    try { $stdErr = [string]$stderrTask.Result } catch { }

    if (-not [string]::IsNullOrWhiteSpace($stdOut)) { Write-Host $stdOut.TrimEnd() }
    if (-not [string]::IsNullOrWhiteSpace($stdErr)) { Write-Host $stdErr.TrimEnd() }

    return [pscustomobject]@{
        Success = ($proc.ExitCode -eq 0)
        ExitCode = [int]$proc.ExitCode
        TimedOut = $false
        StdOut = [string]$stdOut
        StdErr = [string]$stdErr
        ActiveInstallerProcesses = @()
    }
}

function Invoke-DockerPrerequisiteCommand {
    param(
        [string]$Label,
        [string]$FilePath,
        [string[]]$Arguments = @(),
        [int]$TimeoutSeconds = 60,
        [int[]]$AcceptedExitCodes = @(0)
    )

    $result = Invoke-ProcessWithTimeout -Label $Label -FilePath $FilePath -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds
    if ($result.TimedOut) {
        throw ("{0} timed out." -f [string]$Label)
    }

    if (-not (@($AcceptedExitCodes) -contains [int]$result.ExitCode)) {
        throw ("{0} failed with exit code {1}." -f [string]$Label, [int]$result.ExitCode)
    }

    return $result
}

function Ensure-DockerPrerequisiteServiceStarted {
    param([string]$ServiceName)

    if ([string]::IsNullOrWhiteSpace([string]$ServiceName)) {
        return
    }

    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($null -eq $service) {
        Write-Host ("docker-step-info: prerequisite-service-skip => {0} => not-found" -f [string]$ServiceName)
        return
    }

    try {
        if ([string]::Equals([string]$service.StartType, 'Disabled', [System.StringComparison]::OrdinalIgnoreCase)) {
            Set-Service -Name ([string]$service.Name) -StartupType Manual -ErrorAction Stop
        }
        elseif ([string]::Equals([string]$service.Name, 'vmcompute', [System.StringComparison]::OrdinalIgnoreCase)) {
            Set-Service -Name ([string]$service.Name) -StartupType Manual -ErrorAction Stop
        }
    }
    catch {
        Write-Host ("docker-step-info: prerequisite-service-startup-type-skip => {0} => {1}" -f [string]$service.Name, $_.Exception.Message)
    }

    $service.Refresh()
    if ([string]$service.Status -eq 'Running') {
        Write-Host ("docker-step-ok: prerequisite-service-running => {0}" -f [string]$service.Name)
        return
    }

    try {
        Start-Service -Name ([string]$service.Name) -ErrorAction Stop
        Start-Sleep -Seconds 2
        $service = Get-Service -Name ([string]$service.Name) -ErrorAction SilentlyContinue
        if ($null -ne $service -and [string]$service.Status -eq 'Running') {
            Write-Host ("docker-step-ok: prerequisite-service-started => {0}" -f [string]$service.Name)
            return
        }
    }
    catch {
        Write-Host ("docker-step-info: prerequisite-service-start-via-start-service-skip => {0} => {1}" -f [string]$service.Name, $_.Exception.Message)
    }

    $netStartResult = Invoke-ProcessWithTimeout -Label ("net start {0}" -f [string]$service.Name) -FilePath 'cmd.exe' -Arguments @('/d', '/c', ("net start ""{0}""" -f [string]$service.Name)) -TimeoutSeconds 30
    if (-not $netStartResult.Success) {
        $service = Get-Service -Name ([string]$service.Name) -ErrorAction SilentlyContinue
        if ($null -eq $service -or [string]$service.Status -ne 'Running') {
            $netStartOutputText = ((@([string]$netStartResult.StdOut, [string]$netStartResult.StdErr) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join "`n")
            $netStartLooksUnsupported = (
                [int]$netStartResult.ExitCode -eq 2 -and
                [string]::Equals([string]$service.Name, 'vmcompute', [System.StringComparison]::OrdinalIgnoreCase)
            ) -or ($netStartOutputText -match '(?i)NET HELPMSG 2185')
            if ($netStartLooksUnsupported) {
                Write-Host ("docker-step-info: prerequisite-service-net-start-skip => {0} => unsupported-by-net-start" -f [string]$service.Name)
                return
            }
            throw ("docker prerequisite service failed to start: {0} (exit={1})" -f [string]$ServiceName, [int]$netStartResult.ExitCode)
        }
    }

    Write-Host ("docker-step-ok: prerequisite-service-started => {0}" -f [string]$service.Name)
}

function Start-DockerDesktopProcess {
    param([string]$DockerDesktopExe)

    $running = @(Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue)
    if (@($running).Count -gt 0) {
        Write-Host "docker-step-ok: docker-desktop-process-already-running"
        return [pscustomobject]@{
            AlreadyRunning = $true
            StartedNow = $false
        }
    }

    Start-Process -FilePath $DockerDesktopExe -ArgumentList "--minimized" -WindowStyle Hidden
    Write-Host "docker-step-ok: docker-desktop-process-started"
    return [pscustomobject]@{
        AlreadyRunning = $false
        StartedNow = $true
    }
}

function Get-ShortcutContract {
    param([string]$ShortcutPath)

    if ([string]::IsNullOrWhiteSpace([string]$ShortcutPath) -or -not (Test-Path -LiteralPath $ShortcutPath)) {
        return $null
    }

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    return [pscustomobject]@{
        TargetPath = [string]$shortcut.TargetPath
        Arguments = [string]$shortcut.Arguments
        WorkingDirectory = [string]$shortcut.WorkingDirectory
        IconLocation = [string]$shortcut.IconLocation
    }
}

function Test-ShortcutMatches {
    param(
        [string]$ShortcutPath,
        [string]$TargetPath,
        [string]$Arguments = '',
        [string]$WorkingDirectory = '',
        [string]$IconLocation = ''
    )

    $contract = Get-ShortcutContract -ShortcutPath $ShortcutPath
    if ($null -eq $contract) {
        return $false
    }

    return (
        [string]::Equals([string]$contract.TargetPath, [string]$TargetPath, [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals([string]$contract.Arguments, [string]$Arguments, [System.StringComparison]::Ordinal) -and
        [string]::Equals([string]$contract.WorkingDirectory, [string]$WorkingDirectory, [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals([string]$contract.IconLocation, [string]$IconLocation, [System.StringComparison]::OrdinalIgnoreCase)
    )
}

function Ensure-DockerStartupShortcut {
    param([string]$DockerDesktopExe)

    $startupPath = [string]$taskConfig.DockerStartupShortcutPath
    $workingDirectory = Split-Path -Path $DockerDesktopExe -Parent
    $iconLocation = "$DockerDesktopExe,0"
    if (Test-ShortcutMatches -ShortcutPath $startupPath -TargetPath $DockerDesktopExe -Arguments '--minimized' -WorkingDirectory $workingDirectory -IconLocation $iconLocation) {
        Write-Host "docker-step-ok: startup-shortcut-already-configured"
        return
    }

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($startupPath)
    $shortcut.TargetPath = $DockerDesktopExe
    $shortcut.Arguments = '--minimized'
    $shortcut.WorkingDirectory = $workingDirectory
    $shortcut.IconLocation = $iconLocation
    $shortcut.Save()

    if (-not (Test-ShortcutMatches -ShortcutPath $startupPath -TargetPath $DockerDesktopExe -Arguments '--minimized' -WorkingDirectory $workingDirectory -IconLocation $iconLocation)) {
        throw ("Docker Desktop startup shortcut validation failed: {0}" -f $startupPath)
    }

    Write-Host "docker-step-ok: startup-shortcut"
}

function Ensure-DockerDesktopInteractiveLaunch {
    param([string]$DockerDesktopExe)

    if ([string]::IsNullOrWhiteSpace([string]$DockerDesktopExe) -or -not (Test-Path -LiteralPath $DockerDesktopExe)) {
        throw ("Docker Desktop interactive launch path is invalid: {0}" -f [string]$DockerDesktopExe)
    }

    if (Test-DockerDesktopInteractiveProcessRunning -ExpectedUserName ([string]$taskConfig.ManagerUser)) {
        Write-Host 'docker-step-ok: docker-desktop-interactive-process-already-running'
        return
    }

    Stop-NonInteractiveDockerDesktopProcesses -ExpectedUserName ([string]$taskConfig.ManagerUser)
    Stop-DockerServiceForInteractiveLaunch

    $interactiveDesktopStatus = Wait-ClagnosUserInteractiveDesktopReady -UserName ([string]$taskConfig.ManagerUser) -WaitSeconds ([int]$taskConfig.InteractiveDesktopWaitSeconds) -PollSeconds 5
    Write-ClagnosInteractiveDesktopStatusLine -Status $interactiveDesktopStatus -Label 'docker-interactive-desktop-state'
    if (-not [bool]$interactiveDesktopStatus.Ready) {
        $blockMessage = New-ClagnosInteractiveDesktopBlockMessage -ActivityDescription 'Docker Desktop launch' -ExpectedUserName ([string]$taskConfig.ManagerUser) -Status $interactiveDesktopStatus
        throw ([string]$blockMessage.WarningMessage)
    }

    $workerTaskName = "{0}-{1}" -f ([string]$taskConfig.TaskName), ([string]$taskConfig.InteractiveLaunchTaskSuffix)
    $paths = Get-ClagnosInteractivePaths -TaskName $workerTaskName
    $workerScript = @'
$ErrorActionPreference = "Stop"
$helperPath = "__HELPER_PATH__"
$resultPath = "__RESULT_PATH__"
$taskName = "__TASK_NAME__"
$dockerDesktopExe = "__DOCKER_DESKTOP_EXE__"

. $helperPath

function Test-DockerDesktopRunning {
    $processes = @(Get-Process -Name 'Docker Desktop' -IncludeUserName -ErrorAction SilentlyContinue)
    foreach ($process in @($processes)) {
        try {
            $sessionId = [int]$process.SessionId
            $userName = [string]$process.UserName
            if ($sessionId -gt 0 -and [string]::Equals([string]$userName, '__EXPECTED_USER__', [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
        catch {
        }
    }

    return $false
}

if (-not (Test-DockerDesktopRunning)) {
    Start-Process -FilePath $dockerDesktopExe -ArgumentList '--minimized' -WindowStyle Hidden
}

$deadline = [DateTime]::UtcNow.AddSeconds(45)
while ([DateTime]::UtcNow -lt $deadline) {
    if (Test-DockerDesktopRunning) {
        Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $true -Summary 'Docker Desktop launched in the interactive desktop session.'
        exit 0
    }

    Start-Sleep -Seconds 2
}

Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $false -Summary 'Docker Desktop did not appear in the interactive desktop session.'
exit 1
'@

    $workerScript = $workerScript.Replace('__HELPER_PATH__', $interactiveHelperPath)
    $workerScript = $workerScript.Replace('__RESULT_PATH__', [string]$paths.ResultPath)
    $workerScript = $workerScript.Replace('__TASK_NAME__', $workerTaskName)
    $workerScript = $workerScript.Replace('__DOCKER_DESKTOP_EXE__', [string]$DockerDesktopExe)
    $workerScript = $workerScript.Replace('__EXPECTED_USER__', ('{0}\{1}' -f $env:COMPUTERNAME, ([string]$taskConfig.ManagerUser)))

    $null = Invoke-ClagnosInteractiveDesktopAutomation `
        -TaskName $workerTaskName `
        -RunAsUser ([string]$taskConfig.ManagerUser) `
        -RunAsPassword ([string]$taskConfig.ManagerPassword) `
        -WorkerScriptText $workerScript `
        -WaitTimeoutSeconds ([int]$taskConfig.InteractiveLaunchTimeoutSeconds) `
        -RunAsMode 'interactiveToken'

    Write-Host 'docker-step-ok: interactive-desktop-launch'
}

function Resolve-DockerServices {
    $primaryService = Get-Service -Name ([string]$taskConfig.DockerServiceName) -ErrorAction SilentlyContinue
    if ($null -ne $primaryService) {
        return @($primaryService)
    }

    return @()
}

function Ensure-DockerPlatformPrerequisites {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        throw 'wsl.exe is not available. Docker Desktop requires WSL support.'
    }

    foreach ($serviceName in @($taskConfig.DockerPrerequisiteServices)) {
        Ensure-DockerPrerequisiteServiceStarted -ServiceName ([string]$serviceName)
    }

    [void](Invoke-DockerPrerequisiteCommand -Label 'wsl --install --no-distribution' -FilePath 'wsl.exe' -Arguments @('--install', '--no-distribution') -TimeoutSeconds ([int]$taskConfig.DockerWslBootstrapTimeoutSeconds) -AcceptedExitCodes @(0,1,3010))
    [void](Invoke-DockerPrerequisiteCommand -Label 'wsl --update' -FilePath 'wsl.exe' -Arguments @('--update') -TimeoutSeconds ([int]$taskConfig.DockerWslBootstrapTimeoutSeconds) -AcceptedExitCodes @(0,1,3010))
    [void](Invoke-DockerPrerequisiteCommand -Label 'wsl --set-default-version 2' -FilePath 'wsl.exe' -Arguments @('--set-default-version', '2') -TimeoutSeconds 90 -AcceptedExitCodes @(0,1))
    [void](Invoke-DockerPrerequisiteCommand -Label 'wsl --shutdown' -FilePath 'wsl.exe' -Arguments @('--shutdown') -TimeoutSeconds 45 -AcceptedExitCodes @(0,1))

    foreach ($serviceName in @($taskConfig.DockerPrerequisiteServices)) {
        Ensure-DockerPrerequisiteServiceStarted -ServiceName ([string]$serviceName)
    }

    Write-Host 'docker-step-ok: platform-prerequisites'
}

function Write-Utf8FileWithoutBom {
    param(
        [string]$Path,
        [string]$Content
    )

    $parentPath = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace([string]$parentPath) -and -not (Test-Path -LiteralPath $parentPath)) {
        New-Item -Path $parentPath -ItemType Directory -Force | Out-Null
    }

    [System.IO.File]::WriteAllText($Path, [string]$Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Ensure-DockerMasterProfileState {
    $dockerProfileRoot = Join-Path $env:USERPROFILE '.docker'
    $dockerRoamingRoot = Join-Path $env:APPDATA 'Docker'
    $dockerDesktopRoamingRoot = Join-Path $env:APPDATA 'Docker Desktop'

    $configJson = @'
{
  "auths": {},
  "credsStore": "desktop",
  "currentContext": "desktop-linux",
  "plugins": {
    "-x-cli-hints": {
      "enabled": "false"
    }
  },
  "features": {
    "hooks": "false"
  }
}
'@

    $daemonJson = @'
{
  "builder": {
    "gc": {
      "defaultKeepStorage": "20GB",
      "enabled": true
    }
  },
  "experimental": false
}
'@

    $windowsDaemonJson = @'
{
  "experimental": false
}
'@

    $settingsStoreJson = @'
{
  "AnalyticsEnabled": false,
  "AutoStart": true,
  "ContainerTerminal": "system",
  "DesktopTerminalEnabled": true,
  "DisplayedOnboarding": true,
  "EnableCLIHints": false,
  "EnableDockerAI": true,
  "InferenceCanUseGPUVariant": true,
  "IntegratedWslDistros": [],
  "LicenseTermsVersion": 2,
  "OpenUIOnStartupDisabled": true,
  "SbomIndexing": false,
  "SettingsVersion": 43,
  "ThemeSource": "dark",
  "UseContainerdSnapshotter": true
}
'@

    $installStateJson = @'
{
  "previouslyInstalled": true
}
'@

    Write-Utf8FileWithoutBom -Path (Join-Path $dockerProfileRoot 'config.json') -Content $configJson
    Write-Utf8FileWithoutBom -Path (Join-Path $dockerProfileRoot 'daemon.json') -Content $daemonJson
    Write-Utf8FileWithoutBom -Path (Join-Path $dockerProfileRoot 'windows-daemon.json') -Content $windowsDaemonJson
    Write-Utf8FileWithoutBom -Path (Join-Path $dockerRoamingRoot 'settings-store.json') -Content $settingsStoreJson
    Write-Utf8FileWithoutBom -Path (Join-Path $dockerDesktopRoamingRoot 'install-state.json') -Content $installStateJson

    Write-Host 'docker-step-ok: master-profile-state'
}

function Ensure-DockerServicesStarted {
    $services = @(Resolve-DockerServices)
    if (@($services).Count -eq 0) {
        throw ("{0} was not found after installation." -f [string]$taskConfig.DockerServiceName)
    }

    foreach ($service in @($services)) {
        try {
            Set-Service -Name ([string]$service.Name) -StartupType Manual -ErrorAction Stop
        }
        catch {
            Write-Host ("docker-step-info: service-startup-type-skip => {0} => {1}" -f [string]$service.Name, $_.Exception.Message)
        }

        $service.Refresh()
        Write-Host ("docker-step-ok: service-config => {0} => startType={1}; status={2}" -f [string]$service.Name, [string]$service.StartType, [string]$service.Status)
    }

    Start-Sleep -Seconds 2
    $resolvedServices = @(Resolve-DockerServices)
    $runningServices = @($resolvedServices | Where-Object { [string]$_.Status -eq 'Running' })
    Write-Host ("docker-step-ok: service-config => total={0}; running={1}" -f @($resolvedServices).Count, @($runningServices).Count)
}

function Ensure-DockerDesktopStarted {
    param([string]$DockerExe)

    if ([string]::IsNullOrWhiteSpace([string]$DockerExe)) {
        throw 'docker.exe is not available. Docker Desktop start requires the Docker CLI.'
    }

    $startResult = Invoke-ProcessWithTimeout -Label 'docker desktop start' -FilePath $DockerExe -Arguments @('desktop', 'start') -TimeoutSeconds ([int]$taskConfig.DockerDesktopStartTimeoutSeconds)
    if ($startResult.TimedOut) {
        throw 'docker desktop start timed out.'
    }

    if (-not $startResult.Success) {
        throw ("docker desktop start failed with exit code {0}." -f [int]$startResult.ExitCode)
    }

    Write-Host 'docker-step-ok: desktop-start-requested'
}

function Stop-DockerServiceForInteractiveLaunch {
    $service = Get-Service -Name ([string]$taskConfig.DockerServiceName) -ErrorAction SilentlyContinue
    if ($null -eq $service) {
        return
    }

    $service.Refresh()
    if ([string]$service.Status -ne 'Running') {
        Write-Host ("docker-step-ok: service-stopped-before-interactive-launch => {0}" -f [string]$service.Name)
        return
    }

    try {
        Stop-Service -Name ([string]$service.Name) -Force -ErrorAction Stop
    }
    catch {
        $service = Get-Service -Name ([string]$taskConfig.DockerServiceName) -ErrorAction SilentlyContinue
        if ($null -ne $service -and [string]$service.Status -eq 'Running') {
            throw ("docker service failed to stop before interactive launch: {0} ({1})" -f [string]$taskConfig.DockerServiceName, $_.Exception.Message)
        }
    }

    Write-Host ("docker-step-ok: service-stopped-before-interactive-launch => {0}" -f [string]$taskConfig.DockerServiceName)
}

function Test-DockerDesktopInteractiveProcessRunning {
    param([string]$ExpectedUserName)

    $processes = @(Get-Process -Name 'Docker Desktop' -IncludeUserName -ErrorAction SilentlyContinue)
    foreach ($process in @($processes)) {
        $sessionId = 0
        try { $sessionId = [int]$process.SessionId } catch { $sessionId = 0 }
        $userName = ''
        try { $userName = [string]$process.UserName } catch { $userName = '' }
        if ($sessionId -gt 0 -and (Test-ClagnosUserNameMatch -ObservedUserName $userName -ExpectedUserName $ExpectedUserName)) {
            return $true
        }
    }

    return $false
}

function Stop-NonInteractiveDockerDesktopProcesses {
    param([string]$ExpectedUserName)

    $stoppedProcessIds = New-Object 'System.Collections.Generic.List[int]'
    $processes = @(Get-Process -Name 'Docker Desktop' -IncludeUserName -ErrorAction SilentlyContinue)
    foreach ($process in @($processes)) {
        $sessionId = 0
        try { $sessionId = [int]$process.SessionId } catch { $sessionId = 0 }
        $userName = ''
        try { $userName = [string]$process.UserName } catch { $userName = '' }
        if ($sessionId -gt 0 -and (Test-ClagnosUserNameMatch -ObservedUserName $userName -ExpectedUserName $ExpectedUserName)) {
            continue
        }

        try {
            Stop-Process -Id ([int]$process.Id) -Force -ErrorAction Stop
            [void]$stoppedProcessIds.Add([int]$process.Id)
        }
        catch {
        }
    }

    if (@($stoppedProcessIds).Count -gt 0) {
        Write-Host ("docker-step-ok: cleared-noninteractive-frontends => {0}" -f ((@($stoppedProcessIds) | ForEach-Object { [string]$_ }) -join ', '))
    }
}

function Test-DockerDesktopProcessRunning {
    param([string]$DockerDesktopExe = '')

    $nameMatches = @(Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue)
    if (@($nameMatches).Count -gt 0) {
        return $true
    }

    $candidatePath = [string]$DockerDesktopExe
    if ([string]::IsNullOrWhiteSpace([string]$candidatePath)) {
        return $false
    }

    $processes = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        [string]::Equals([string]$_.ExecutablePath, $candidatePath, [System.StringComparison]::OrdinalIgnoreCase)
    })
    return (@($processes).Count -gt 0)
}

function Wait-DockerDaemonReady {
    param([string]$DockerDesktopExe)

    $dockerExe = Resolve-DockerExePath
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $lastDesktopStatusExitCode = -1
    $lastInfoExitCode = -1
    $desktopStartRequested = $false
    while ($stopwatch.Elapsed.TotalSeconds -lt [int]$taskConfig.DockerReadinessTimeoutSeconds) {
        Ensure-DockerPrerequisiteServiceStarted -ServiceName 'vmcompute'
        Ensure-DockerPrerequisiteServiceStarted -ServiceName 'hns'

        if (-not (Test-DockerDesktopInteractiveProcessRunning -ExpectedUserName ([string]$taskConfig.ManagerUser))) {
            Ensure-DockerDesktopInteractiveLaunch -DockerDesktopExe $DockerDesktopExe
            Start-Sleep -Seconds 2
            $desktopStartRequested = $false
        }

        if (-not $desktopStartRequested) {
            Ensure-DockerDesktopStarted -DockerExe $dockerExe
            Start-Sleep -Seconds 5
            $desktopStartRequested = $true
        }

        $dockerDesktopStatusResult = Invoke-ProcessWithTimeout -Label "docker desktop status" -FilePath $dockerExe -Arguments @("desktop", "status") -TimeoutSeconds ([int]$taskConfig.DockerStatusTimeoutSeconds)
        $lastDesktopStatusExitCode = [int]$dockerDesktopStatusResult.ExitCode
        $dockerInfoResult = Invoke-ProcessWithTimeout -Label "docker info" -FilePath $dockerExe -Arguments @("info") -TimeoutSeconds ([int]$taskConfig.DockerInfoTimeoutSeconds)
        $lastInfoExitCode = [int]$dockerInfoResult.ExitCode

        if ($dockerDesktopStatusResult.Success -and $dockerDesktopStatusResult.ExitCode -eq 0 -and $dockerInfoResult.Success -and $dockerInfoResult.ExitCode -eq 0) {
            return [pscustomobject]@{
                Success = $true
                DesktopStatusExitCode = $lastDesktopStatusExitCode
                InfoExitCode = $lastInfoExitCode
            }
        }

        $desktopStartRequested = $false
        Write-Host ("docker-step-wait: desktop-status-exit={0}; docker-info-exit={1}; elapsed={2:n0}s" -f $lastDesktopStatusExitCode, $lastInfoExitCode, $stopwatch.Elapsed.TotalSeconds)
        Start-Sleep -Seconds ([int]$taskConfig.DockerReadinessPollSeconds)
    }

    return [pscustomobject]@{
        Success = $false
        DesktopStatusExitCode = $lastDesktopStatusExitCode
        InfoExitCode = $lastInfoExitCode
    }
}

function Remove-DockerDesktopDeferredStart {
    $runOncePath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
    if (-not (Test-Path -LiteralPath $runOncePath)) {
        return $false
    }

    $runOnceEntry = Get-ItemProperty -Path $runOncePath -Name 'ClagnosStartDockerDesktop' -ErrorAction SilentlyContinue
    $existingValue = ''
    if ($null -ne $runOnceEntry -and $runOnceEntry.PSObject.Properties.Match('ClagnosStartDockerDesktop').Count -gt 0) {
        $existingValue = [string]$runOnceEntry.ClagnosStartDockerDesktop
    }
    if ([string]::IsNullOrWhiteSpace([string]$existingValue)) {
        return $false
    }

    Remove-ItemProperty -Path $runOncePath -Name 'ClagnosStartDockerDesktop' -ErrorAction SilentlyContinue
    $remainingEntry = Get-ItemProperty -Path $runOncePath -Name 'ClagnosStartDockerDesktop' -ErrorAction SilentlyContinue
    $remainingValue = ''
    if ($null -ne $remainingEntry -and $remainingEntry.PSObject.Properties.Match('ClagnosStartDockerDesktop').Count -gt 0) {
        $remainingValue = [string]$remainingEntry.ClagnosStartDockerDesktop
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$remainingValue)) {
        throw 'Docker Desktop stale RunOnce entry cleanup failed.'
    }

    return $true
}

function Ensure-WingetSourcesReady {
    param([string]$WingetExe)

    $sourceListResult = Invoke-ProcessWithTimeout -Label 'winget source list' -FilePath $WingetExe -Arguments @('source', 'list') -TimeoutSeconds 30
    if ($sourceListResult.Success) {
        Write-Host 'docker-step-ok: winget-sources-ready'
        return
    }

    Write-Host ("docker-step-repair: winget-source-list-exit={0}" -f [int]$sourceListResult.ExitCode)
    $sourceUpdateResult = Invoke-ProcessWithTimeout -Label 'winget source update' -FilePath $WingetExe -Arguments @('source', 'update') -TimeoutSeconds 60
    if (-not $sourceUpdateResult.Success) {
        $sourceResetResult = Invoke-ProcessWithTimeout -Label 'winget source reset' -FilePath $WingetExe -Arguments @('source', 'reset') -TimeoutSeconds 60
        if (-not $sourceResetResult.Success) {
            throw ("winget source update failed with exit code {0}; winget source reset failed with exit code {1}." -f [int]$sourceUpdateResult.ExitCode, [int]$sourceResetResult.ExitCode)
        }

        $sourceUpdateResult = Invoke-ProcessWithTimeout -Label 'winget source update' -FilePath $WingetExe -Arguments @('source', 'update') -TimeoutSeconds 60
        if (-not $sourceUpdateResult.Success) {
            throw ("winget source update failed with exit code {0} after bounded reset." -f [int]$sourceUpdateResult.ExitCode)
        }
    }

    $secondSourceListResult = Invoke-ProcessWithTimeout -Label 'winget source list' -FilePath $WingetExe -Arguments @('source', 'list') -TimeoutSeconds 30
    if (-not $secondSourceListResult.Success) {
        throw ("winget source list failed with exit code {0} after bounded repair." -f [int]$secondSourceListResult.ExitCode)
    }

    Write-Host 'docker-step-ok: winget-sources-ready'
}

function Test-DockerDesktopInstalled {
    param([string]$DockerDesktopExe)

    return ((Test-Path -LiteralPath $DockerDesktopExe) -or @((Resolve-DockerServices)).Count -gt 0)
}

function Wait-DockerDesktopInstalled {
    param([string]$DockerDesktopExe)

    $deadline = [DateTime]::UtcNow.AddSeconds(60)
    while ([DateTime]::UtcNow -lt $deadline) {
        Refresh-SessionPath
        if (Test-DockerDesktopInstalled -DockerDesktopExe $DockerDesktopExe) {
            return $true
        }

        Start-Sleep -Seconds 5
    }

    return (Test-DockerDesktopInstalled -DockerDesktopExe $DockerDesktopExe)
}

function Get-DockerDesktopUninstallRegistryKeyPaths {
    $paths = New-Object 'System.Collections.Generic.List[string]'
    foreach ($rootPath in @(
        'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )) {
        if (-not (Test-Path -LiteralPath $rootPath)) {
            continue
        }

        foreach ($child in @(Get-ChildItem -LiteralPath $rootPath -ErrorAction SilentlyContinue)) {
            try {
                $item = Get-ItemProperty -LiteralPath ([string]$child.PSPath) -ErrorAction Stop
                $displayName = [string]$item.DisplayName
                if ($displayName -like '*Docker Desktop*') {
                    [void]$paths.Add([string]$child.PSPath)
                }
            }
            catch {
            }
        }
    }

    return @($paths | Select-Object -Unique)
}

function Remove-DockerDesktopStaleRegistration {
    param(
        [string]$DockerDesktopExe,
        [switch]$AllowWhenExecutablePresent
    )

    if ((Test-DockerDesktopInstalled -DockerDesktopExe $DockerDesktopExe) -and -not $AllowWhenExecutablePresent) {
        return $false
    }

    $registryKeyPaths = @(Get-DockerDesktopUninstallRegistryKeyPaths)
    if (@($registryKeyPaths).Count -eq 0) {
        return $false
    }

    foreach ($registryKeyPath in @($registryKeyPaths)) {
        Remove-Item -LiteralPath $registryKeyPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host ("docker-step-repair: removed-stale-registration => {0}" -f [string]$registryKeyPath)
    }

    $remainingKeyPaths = @(Get-DockerDesktopUninstallRegistryKeyPaths)
    if (@($remainingKeyPaths).Count -gt 0) {
        throw ("Docker Desktop stale registration cleanup failed: {0}" -f ((@($remainingKeyPaths) | ForEach-Object { [string]$_ }) -join ', '))
    }

    return $true
}

Refresh-SessionPath

if (Remove-DockerDesktopDeferredStart) {
    Write-Host 'docker-step-cleanup: removed-stale-run-once'
}

$wingetExe = Resolve-WingetExe
if ([string]::IsNullOrWhiteSpace($wingetExe)) {
    throw "winget command is not available. Docker Desktop install requires winget."
}
Write-Host "Resolved winget executable: $wingetExe"

$dockerDesktopExe = [string]$taskConfig.DockerDesktopExecutablePath
$dockerServiceExists = $null -ne (Get-Service -Name ([string]$taskConfig.DockerServiceName) -ErrorAction SilentlyContinue)
$dockerDesktopExeExists = Test-Path -LiteralPath $dockerDesktopExe
$dockerAlreadyInstalled = ($dockerDesktopExeExists -and $dockerServiceExists)

Ensure-WingetSourcesReady -WingetExe $wingetExe

if ($dockerDesktopExeExists -and -not $dockerServiceExists) {
    Write-Host 'docker-step-repair: incomplete-install-detected => missing-service'
    if (Remove-DockerDesktopStaleRegistration -DockerDesktopExe $dockerDesktopExe -AllowWhenExecutablePresent) {
        Write-Host 'docker-step-repair: stale-registration-cleared'
    }
    $dockerAlreadyInstalled = $false
}

if ($dockerAlreadyInstalled) {
    Write-Host "Docker Desktop is already installed. Winget install step is skipped."
}
else {
    Stop-StaleInstallerProcesses | Out-Null
    $dockerInstallResult = $null
    $staleRegistrationRepaired = $false
    foreach ($attempt in 1..2) {
        Write-Host ("Running: winget install -e --id {0} --accept-source-agreements --accept-package-agreements --silent --disable-interactivity" -f [string]$taskConfig.DockerDesktopPackageId)
        $dockerInstallResult = Invoke-ProcessWithTimeout `
            -Label ("winget install {0}" -f [string]$taskConfig.DockerDesktopPackageId) `
            -FilePath $wingetExe `
            -Arguments @('install', '-e', '--id', ([string]$taskConfig.DockerDesktopPackageId), '--accept-source-agreements', '--accept-package-agreements', '--silent', '--disable-interactivity') `
            -TimeoutSeconds ([int]$taskConfig.DockerInstallTimeoutSeconds)

        if ($dockerInstallResult.Success) {
            break
        }

        if ($dockerInstallResult.TimedOut) {
            throw ("winget install {0} timed out after stale-installer cleanup. Active installer processes: {1}" -f `
                [string]$taskConfig.DockerDesktopPackageId, `
                (Format-InstallerProcessSummary -Processes $dockerInstallResult.ActiveInstallerProcesses))
        }

        if (Wait-DockerDesktopInstalled -DockerDesktopExe $dockerDesktopExe) {
            Write-Host ("docker-step-ok: install-materialized-after-exit => {0}" -f [int]$dockerInstallResult.ExitCode)
            break
        }

        $installOutputText = ((@([string]$dockerInstallResult.StdOut, [string]$dockerInstallResult.StdErr) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join "`n")
        $looksLikeStaleRegistration = (
            [int]$dockerInstallResult.ExitCode -eq -1978335189 -or
            $installOutputText -match '(?i)existing package already installed' -or
            $installOutputText -match '(?i)no available upgrade found'
        )
        if ($looksLikeStaleRegistration -and -not $staleRegistrationRepaired -and (Remove-DockerDesktopStaleRegistration -DockerDesktopExe $dockerDesktopExe)) {
            $staleRegistrationRepaired = $true
            Write-Host 'docker-step-repair: stale-registration-cleared'
            Start-Sleep -Seconds 3
            continue
        }

        if ($attempt -lt 2) {
            Write-Host ("docker-step-retry: winget-install-exit={0}; attempt={1}" -f [int]$dockerInstallResult.ExitCode, $attempt)
            Stop-StaleInstallerProcesses | Out-Null
            Ensure-WingetSourcesReady -WingetExe $wingetExe
            Start-Sleep -Seconds 5
        }
    }

    if (-not (Wait-DockerDesktopInstalled -DockerDesktopExe $dockerDesktopExe)) {
        throw ("winget install {0} failed with exit code {1}." -f [string]$taskConfig.DockerDesktopPackageId, [int]$dockerInstallResult.ExitCode)
    }

    Refresh-SessionPath
}

$machinePathChanged = Ensure-MachinePathEntry -Entry ([string]$taskConfig.DockerMachinePathEntry)
if ($machinePathChanged) {
    Refresh-SessionPath
}

Ensure-DockerPlatformPrerequisites
Ensure-DockerServicesStarted

if (Test-Path -LiteralPath $dockerDesktopExe) {
    Ensure-DockerStartupShortcut -DockerDesktopExe $dockerDesktopExe
}
else {
    throw "Docker Desktop executable not found at expected path."
}

foreach ($localUser in @($taskConfig.DockerLocalUsers)) {
    Ensure-LocalGroupMembership -GroupName ([string]$taskConfig.DockerUsersGroupName) -MemberName $localUser
}

Ensure-DockerMasterProfileState

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "docker command is not available after installation."
}

$dockerExe = Resolve-DockerExePath
$dockerVersionResult = Invoke-ProcessWithTimeout -Label "docker --version" -FilePath $dockerExe -Arguments @("--version") -TimeoutSeconds ([int]$taskConfig.DockerVersionTimeoutSeconds)
if ($dockerVersionResult.Success) {
    Write-Host "docker-step-ok: docker-client-version"
}
else {
    throw ("docker --version did not complete successfully (exit={0})." -f $dockerVersionResult.ExitCode)
}

Ensure-DockerDesktopInteractiveLaunch -DockerDesktopExe $dockerDesktopExe
Write-Host "docker-step-ok: desktop-launch-requested"
Ensure-DockerPrerequisiteServiceStarted -ServiceName 'vmcompute'
Ensure-DockerPrerequisiteServiceStarted -ServiceName 'hns'

Start-Sleep -Seconds 5
if (Test-DockerDesktopInteractiveProcessRunning -ExpectedUserName ([string]$taskConfig.ManagerUser)) {
    Write-Host "docker-step-ok: docker-desktop-interactive-process"
}
else {
    Write-Host "docker-step-info: docker-desktop-interactive-process-not-yet-visible => continuing-with-daemon-readiness-check"
}

$dockerReadiness = Wait-DockerDaemonReady -DockerDesktopExe $dockerDesktopExe
if (-not [bool]$dockerReadiness.Success) {
    throw ("Docker Desktop did not become daemon-ready in time. desktop-status-exit={0}; docker-info-exit={1}" -f [int]$dockerReadiness.DesktopStatusExitCode, [int]$dockerReadiness.InfoExitCode)
}
Write-Host "docker-step-ok: docker-desktop-status"
Write-Host "docker-step-ok: docker-engine-ready"

$global:LASTEXITCODE = 0
Write-Host "install-docker-desktop-application-completed"
Write-Host "Update task completed: install-docker-desktop-application"

