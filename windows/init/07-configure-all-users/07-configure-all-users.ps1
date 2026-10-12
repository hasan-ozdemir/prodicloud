$ErrorActionPreference = "Stop"
Write-Host "Init task started: configure-all-users"

$vmUser = "__VM_ADMIN_USER__"
$vmPass = "__VM_ADMIN_PASS__"
$assistantUser = "__ASSISTANT_USER__"
$assistantPass = "__ASSISTANT_PASS__"

# Task config
$taskConfig = [ordered]@{
    InteractiveMaterializationWaitSeconds = 20
    ProfileReadyWaitSeconds = 20
    ProfileReadyPollMilliseconds = 250
    StandardProfileDirectories = @(
        'Desktop',
        'Documents',
        'Downloads',
        'AppData',
        'AppData\Local',
        'AppData\LocalLow',
        'AppData\Roaming'
    )
}

function Ensure-ClagnosDirectory {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace([string]$Path)) {
        throw 'Directory path is empty.'
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Ensure-CreateProfileType {
    if ('ClagnosUserProfileNative' -as [type]) {
        return
    }

    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public struct ClagnosProfileInfo
{
    public int dwSize;
    public int dwFlags;
    [MarshalAs(UnmanagedType.LPWStr)]
    public string lpUserName;
    [MarshalAs(UnmanagedType.LPWStr)]
    public string lpProfilePath;
    [MarshalAs(UnmanagedType.LPWStr)]
    public string lpDefaultPath;
    [MarshalAs(UnmanagedType.LPWStr)]
    public string lpServerName;
    [MarshalAs(UnmanagedType.LPWStr)]
    public string lpPolicyPath;
    public IntPtr hProfile;
}

public static class ClagnosUserProfileNative
{
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool LogonUser(
        string lpszUsername,
        string lpszDomain,
        string lpszPassword,
        int dwLogonType,
        int dwLogonProvider,
        out IntPtr phToken);

    [DllImport("userenv.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern int CreateProfile(
        string pszUserSid,
        string pszUserName,
        StringBuilder pszProfilePath,
        int cchProfilePath);

    [DllImport("userenv.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool LoadUserProfile(
        IntPtr hToken,
        ref ClagnosProfileInfo lpProfileInfo);

    [DllImport("userenv.dll", SetLastError = true)]
    public static extern bool UnloadUserProfile(
        IntPtr hToken,
        IntPtr hProfile);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(
        IntPtr hObject);
}
"@ -ErrorAction Stop | Out-Null
}

function Get-HResultHex {
    param([int]$Value)

    $rawBytes = [System.BitConverter]::GetBytes([int]$Value)
    $unsignedValue = [System.BitConverter]::ToUInt32($rawBytes, 0)
    return ('0x{0}' -f $unsignedValue.ToString('X8'))
}

function Get-EnabledLocalUsers {
    return @(
        Get-LocalUser -ErrorAction Stop |
            Where-Object {
                $_.Enabled -and
                -not [string]::IsNullOrWhiteSpace([string]$_.Name)
            } |
            Sort-Object Name
    )
}

function Get-ManagedLocalUserPassword {
    param([string]$UserName)

    if ([string]::IsNullOrWhiteSpace([string]$UserName)) {
        return ''
    }

    if ([string]::Equals([string]$UserName, [string]$vmUser, [System.StringComparison]::OrdinalIgnoreCase)) {
        return [string]$vmPass
    }
    if ([string]::Equals([string]$UserName, [string]$assistantUser, [System.StringComparison]::OrdinalIgnoreCase)) {
        return [string]$assistantPass
    }

    return ''
}

function Get-LocalUserProfilePathBySid {
    param([string]$Sid)

    if ([string]::IsNullOrWhiteSpace([string]$Sid)) {
        return ''
    }

    $profileListPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$Sid"
    if (-not (Test-Path -LiteralPath $profileListPath)) {
        return ''
    }

    $profileEntry = Get-ItemProperty -LiteralPath $profileListPath -ErrorAction SilentlyContinue
    if ($null -eq $profileEntry) {
        return ''
    }

    return [string]$profileEntry.ProfileImagePath
}

function Get-LocalUserProfileRegistryKeyPath {
    param(
        [string]$Sid,
        [switch]$Bak
    )

    if ([string]::IsNullOrWhiteSpace([string]$Sid)) {
        return ''
    }

    $keyName = if ($Bak) { [string]$Sid + '.bak' } else { [string]$Sid }
    return ("HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\{0}" -f [string]$keyName)
}

function Get-LocalUserProfileRegistryEntry {
    param(
        [string]$Sid,
        [switch]$Bak
    )

    $keyPath = Get-LocalUserProfileRegistryKeyPath -Sid $Sid -Bak:$Bak
    if ([string]::IsNullOrWhiteSpace([string]$keyPath) -or -not (Test-Path -LiteralPath $keyPath)) {
        return $null
    }

    return (Get-ItemProperty -LiteralPath $keyPath -ErrorAction SilentlyContinue)
}

function Open-LocalMachineRegistryKey {
    param(
        [string]$KeyPath,
        [bool]$Writable = $false
    )

    if ([string]::IsNullOrWhiteSpace([string]$KeyPath)) {
        throw 'Registry key path is empty.'
    }

    $normalizedPath = [string]$KeyPath
    if ($normalizedPath.StartsWith('Registry::', [System.StringComparison]::OrdinalIgnoreCase)) {
        $normalizedPath = $normalizedPath.Substring('Registry::'.Length)
    }
    if ($normalizedPath.StartsWith('HKLM:\', [System.StringComparison]::OrdinalIgnoreCase)) {
        $normalizedPath = 'HKEY_LOCAL_MACHINE\' + $normalizedPath.Substring('HKLM:\'.Length)
    }

    if (-not $normalizedPath.StartsWith('HKEY_LOCAL_MACHINE\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("Unsupported registry root: {0}" -f [string]$KeyPath)
    }

    $subKeyPath = $normalizedPath.Substring('HKEY_LOCAL_MACHINE\'.Length)
    $openedKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey([string]$subKeyPath, [bool]$Writable)
    if ($null -eq $openedKey) {
        throw ("Registry key could not be opened: {0}" -f [string]$KeyPath)
    }

    return $openedKey
}

function Copy-RegistryKeyValues {
    param(
        [string]$SourceKeyPath,
        [string]$TargetKeyPath
    )

    if ([string]::IsNullOrWhiteSpace([string]$SourceKeyPath) -or
        [string]::IsNullOrWhiteSpace([string]$TargetKeyPath) -or
        -not (Test-Path -LiteralPath $SourceKeyPath) -or
        -not (Test-Path -LiteralPath $TargetKeyPath)) {
        throw 'Registry source or target key path is invalid.'
    }

    $sourceKey = Open-LocalMachineRegistryKey -KeyPath $SourceKeyPath -Writable:$false
    $targetKey = Open-LocalMachineRegistryKey -KeyPath $TargetKeyPath -Writable:$true
    try {
        foreach ($valueName in @($sourceKey.GetValueNames())) {
            $value = $sourceKey.GetValue([string]$valueName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $valueKind = $sourceKey.GetValueKind([string]$valueName)
            $targetKey.SetValue([string]$valueName, $value, $valueKind)
        }
    }
    finally {
        $sourceKey.Close()
        $targetKey.Close()
    }
}

function Copy-FileIfMissingBestEffort {
    param(
        [string]$SourcePath,
        [string]$TargetPath
    )

    if ([string]::IsNullOrWhiteSpace([string]$SourcePath) -or
        [string]::IsNullOrWhiteSpace([string]$TargetPath) -or
        -not (Test-Path -LiteralPath $SourcePath) -or
        (Test-Path -LiteralPath $TargetPath)) {
        return
    }

    try {
        Copy-Item -LiteralPath $SourcePath -Destination $TargetPath -Force -ErrorAction Stop
    }
    catch {
        Write-Host ("profile-artifact-skip: {0} => {1}" -f [string]$SourcePath, [string]$_.Exception.Message)
    }
}

function Test-TemporaryProfilePath {
    param([string]$ProfilePath)

    if ([string]::IsNullOrWhiteSpace([string]$ProfilePath)) {
        return $false
    }

    $leafName = [System.IO.Path]::GetFileName([string]$ProfilePath)
    if ([string]::IsNullOrWhiteSpace([string]$leafName)) {
        return $false
    }

    return $leafName.StartsWith('TEMP', [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-LocalUserProfileReady {
    param([string]$ProfilePath)

    if ([string]::IsNullOrWhiteSpace([string]$ProfilePath) -or
        (Test-TemporaryProfilePath -ProfilePath $ProfilePath) -or
        -not (Test-Path -LiteralPath $ProfilePath)) {
        return $false
    }

    $ntUserPath = Join-Path $ProfilePath 'NTUSER.DAT'
    return (Test-Path -LiteralPath $ntUserPath)
}

function Copy-ProfileHiveArtifactsIfMissing {
    param(
        [string]$Sid,
        [string]$SourceProfilePath,
        [string]$TargetProfilePath
    )

    if ([string]::IsNullOrWhiteSpace([string]$SourceProfilePath) -or
        [string]::IsNullOrWhiteSpace([string]$TargetProfilePath) -or
        -not (Test-Path -LiteralPath $SourceProfilePath)) {
        return
    }

    Ensure-ClagnosDirectory -Path $TargetProfilePath

    $targetNtUserPath = Join-Path $TargetProfilePath 'NTUSER.DAT'
    if (-not (Test-Path -LiteralPath $targetNtUserPath) -and -not [string]::IsNullOrWhiteSpace([string]$Sid)) {
        $loadedMainHivePath = "Registry::HKEY_USERS\$Sid"
        if (Test-Path -LiteralPath $loadedMainHivePath) {
            & reg.exe save ("HKEY_USERS\{0}" -f [string]$Sid) $targetNtUserPath /y | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw ("reg save failed for loaded main hive '{0}'." -f [string]$Sid)
            }
        }
    }

    foreach ($sourceItem in @(
        Get-ChildItem -LiteralPath $SourceProfilePath -Force -ErrorAction SilentlyContinue |
            Where-Object {
                -not $_.PSIsContainer -and
                [string]$_.Name -like 'NTUSER.DAT*' -and
                -not [string]::Equals([string]$_.Name, 'NTUSER.DAT', [System.StringComparison]::OrdinalIgnoreCase)
            }
    )) {
        $targetPath = Join-Path $TargetProfilePath ([string]$sourceItem.Name)
        Copy-FileIfMissingBestEffort -SourcePath $sourceItem.FullName -TargetPath $targetPath
    }

    $sourceUsrClassRoot = Join-Path $SourceProfilePath 'AppData\Local\Microsoft\Windows'
    if (-not (Test-Path -LiteralPath $sourceUsrClassRoot)) {
        return
    }

    $targetUsrClassRoot = Join-Path $TargetProfilePath 'AppData\Local\Microsoft\Windows'
    Ensure-ClagnosDirectory -Path $targetUsrClassRoot
    $targetUsrClassPath = Join-Path $targetUsrClassRoot 'UsrClass.dat'
    if (-not (Test-Path -LiteralPath $targetUsrClassPath) -and -not [string]::IsNullOrWhiteSpace([string]$Sid)) {
        $loadedClassesHivePath = "Registry::HKEY_USERS\${Sid}_Classes"
        if (Test-Path -LiteralPath $loadedClassesHivePath) {
            & reg.exe save ("HKEY_USERS\{0}_Classes" -f [string]$Sid) $targetUsrClassPath /y | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw ("reg save failed for loaded classes hive '{0}_Classes'." -f [string]$Sid)
            }
        }
    }

    foreach ($sourceItem in @(
        Get-ChildItem -LiteralPath $sourceUsrClassRoot -Force -ErrorAction SilentlyContinue |
            Where-Object {
                -not $_.PSIsContainer -and
                [string]$_.Name -like 'UsrClass.dat*' -and
                -not [string]::Equals([string]$_.Name, 'UsrClass.dat', [System.StringComparison]::OrdinalIgnoreCase)
            }
    )) {
        $targetPath = Join-Path $targetUsrClassRoot ([string]$sourceItem.Name)
        Copy-FileIfMissingBestEffort -SourcePath $sourceItem.FullName -TargetPath $targetPath
    }
}

function Wait-LocalUserProfileReady {
    param(
        [string]$Sid,
        [string]$CandidateProfilePath = ''
    )

    $deadline = [DateTime]::UtcNow.AddSeconds([int]$taskConfig.ProfileReadyWaitSeconds)
    $resolvedPath = [string]$CandidateProfilePath
    while ([DateTime]::UtcNow -lt $deadline) {
        if ([string]::IsNullOrWhiteSpace([string]$resolvedPath)) {
            $resolvedPath = Get-LocalUserProfilePathBySid -Sid $Sid
        }

        if (Test-LocalUserProfileReady -ProfilePath $resolvedPath) {
            return [string]$resolvedPath
        }

        Start-Sleep -Milliseconds ([int]$taskConfig.ProfileReadyPollMilliseconds)
        $resolvedPath = Get-LocalUserProfilePathBySid -Sid $Sid
    }

    if ([string]::IsNullOrWhiteSpace([string]$resolvedPath)) {
        $resolvedPath = Get-LocalUserProfilePathBySid -Sid $Sid
    }

    return [string]$resolvedPath
}

function Repair-TemporaryProfileMappingIfNeeded {
    param(
        [string]$Sid,
        [string]$UserName
    )

    if ([string]::IsNullOrWhiteSpace([string]$Sid) -or [string]::IsNullOrWhiteSpace([string]$UserName)) {
        return ''
    }

    $liveEntry = Get-LocalUserProfileRegistryEntry -Sid $Sid
    $bakEntry = Get-LocalUserProfileRegistryEntry -Sid $Sid -Bak
    if ($null -eq $liveEntry -or $null -eq $bakEntry) {
        return ''
    }

    $liveProfilePath = [string]$liveEntry.ProfileImagePath
    $bakProfilePath = [string]$bakEntry.ProfileImagePath
    if ([string]::IsNullOrWhiteSpace([string]$liveProfilePath) -or [string]::IsNullOrWhiteSpace([string]$bakProfilePath)) {
        return ''
    }

    if (-not (Test-TemporaryProfilePath -ProfilePath $liveProfilePath)) {
        return ''
    }

    Copy-ProfileHiveArtifactsIfMissing -Sid $Sid -SourceProfilePath $liveProfilePath -TargetProfilePath $bakProfilePath

    $liveKeyPath = Get-LocalUserProfileRegistryKeyPath -Sid $Sid
    $bakKeyPath = Get-LocalUserProfileRegistryKeyPath -Sid $Sid -Bak

    Copy-RegistryKeyValues -SourceKeyPath $bakKeyPath -TargetKeyPath $liveKeyPath
    New-ItemProperty -LiteralPath $liveKeyPath -Name 'State' -Value 0 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -LiteralPath $liveKeyPath -Name 'RefCount' -Value 0 -PropertyType DWord -Force | Out-Null
    try {
        Remove-Item -LiteralPath $bakKeyPath -Recurse -Force -ErrorAction Stop
    }
    catch {
        Write-Host ("profile-temp-bak-retained: {0} => {1}" -f [string]$UserName, [string]$_.Exception.Message)
    }

    Write-Host ("profile-temp-repaired: {0} => {1}" -f [string]$UserName, [string]$bakProfilePath)
    return [string]$bakProfilePath
}

function Get-ClagnosInteractivePaths {
    param([string]$TaskName)

    $taskNameText = [string]$TaskName
    if ([string]::IsNullOrWhiteSpace([string]$taskNameText)) {
        throw 'Interactive task name is empty.'
    }

    $safeTaskName = ($taskNameText -replace '[^a-zA-Z0-9\-]', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace([string]$safeTaskName)) {
        throw 'Interactive task name became empty after sanitization.'
    }

    $rootPath = Join-Path 'C:\ProgramData\clagnos\interactive' $safeTaskName
    return [pscustomobject]@{
        RootPath = $rootPath
        WorkerPath = Join-Path $rootPath 'worker.ps1'
        ResultPath = Join-Path $rootPath 'result.json'
        ScheduledTaskName = ('ClagnosInteractive-' + $safeTaskName)
        TaskName = $safeTaskName
    }
}

function Write-ClagnosJsonFile {
    param(
        [string]$Path,
        [object]$Value
    )

    $parentPath = Split-Path -Path $Path -Parent
    Ensure-ClagnosDirectory -Path $parentPath
    $jsonText = [string]($Value | ConvertTo-Json -Depth 8)
    [System.IO.File]::WriteAllText($Path, $jsonText, (New-Object System.Text.UTF8Encoding($false)))
}

function Read-ClagnosJsonFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw ("JSON file was not found: {0}" -f [string]$Path)
    }

    $text = [string](Get-Content -LiteralPath $Path -Raw -ErrorAction Stop)
    if ([string]::IsNullOrWhiteSpace([string]$text)) {
        throw ("JSON file is empty: {0}" -f [string]$Path)
    }

    return (ConvertFrom-Json -InputObject $text)
}

function Get-ClagnosPowerShellExePath {
    $cmd = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if ($cmd -and -not [string]::IsNullOrWhiteSpace([string]$cmd.Source)) {
        return [string]$cmd.Source
    }

    $fallback = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $fallback) {
        return [string]$fallback
    }

    throw 'powershell.exe was not found.'
}

function Get-ClagnosLocalPrincipalName {
    param([string]$UserName)

    if ([string]::IsNullOrWhiteSpace([string]$UserName)) {
        throw 'User name is empty.'
    }

    return ("{0}\{1}" -f [string]$env:COMPUTERNAME, [string]$UserName)
}

function Remove-ClagnosInteractiveScheduledTask {
    param([string]$TaskName)

    if ([string]::IsNullOrWhiteSpace([string]$TaskName)) {
        return
    }

    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    $root = $service.GetFolder('\')
    try {
        $root.DeleteTask($TaskName, 0)
    }
    catch {
        if ($_.Exception.Message -notmatch '(?i)cannot find the file specified|does not exist') {
            throw
        }
    }
}

function Register-ClagnosInteractiveScheduledTask {
    param(
        [string]$TaskName,
        [string]$RunAsUser,
        [string]$RunAsPassword,
        [string]$WorkerPath
    )

    Remove-ClagnosInteractiveScheduledTask -TaskName $TaskName

    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    $root = $service.GetFolder('\')
    $definition = $service.NewTask(0)

    $definition.RegistrationInfo.Description = ("clagnos interactive materialization for {0}" -f [string]$TaskName)
    $definition.Settings.Enabled = $true
    $definition.Settings.Hidden = $true
    $definition.Settings.StartWhenAvailable = $true
    $definition.Settings.AllowDemandStart = $true
    $definition.Settings.DisallowStartIfOnBatteries = $false
    $definition.Settings.StopIfGoingOnBatteries = $false
    $definition.Settings.ExecutionTimeLimit = 'PT1H'
    $definition.Settings.MultipleInstances = 0

    $principalName = Get-ClagnosLocalPrincipalName -UserName $RunAsUser
    $definition.Principal.UserId = $principalName
    $definition.Principal.LogonType = 1
    $definition.Principal.RunLevel = 1

    $action = $definition.Actions.Create(0)
    $action.Path = Get-ClagnosPowerShellExePath
    $action.Arguments = ('-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f [string]$WorkerPath)
    $action.WorkingDirectory = (Split-Path -Path $WorkerPath -Parent)

    $trigger = $definition.Triggers.Create(1)
    $trigger.StartBoundary = ([DateTime]::Now.AddMinutes(10).ToString('s'))

    if ([string]::IsNullOrWhiteSpace([string]$RunAsPassword)) {
        throw 'Interactive scheduled task password is empty.'
    }

    $null = $root.RegisterTaskDefinition($TaskName, $definition, 6, $principalName, [string]$RunAsPassword, 1, $null)
}

function Start-ClagnosInteractiveScheduledTask {
    param([string]$TaskName)

    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    $root = $service.GetFolder('\')
    $task = $root.GetTask($TaskName)
    if ($null -eq $task) {
        throw ("Scheduled task was not found: {0}" -f [string]$TaskName)
    }

    $null = $task.Run($null)
}

function Get-ClagnosInteractiveScheduledTaskSnapshot {
    param([string]$TaskName)

    if ([string]::IsNullOrWhiteSpace([string]$TaskName)) {
        return $null
    }

    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    $root = $service.GetFolder('\')
    try {
        $task = $root.GetTask($TaskName)
    }
    catch {
        if ($_.Exception.Message -match '(?i)cannot find the file specified|does not exist') {
            return $null
        }

        throw
    }

    return [pscustomobject]@{
        State = [int]$task.State
        LastTaskResult = [int]$task.LastTaskResult
        LastRunTime = [DateTime]$task.LastRunTime
    }
}

function Get-ClagnosInteractiveWorkerProcesses {
    param([string]$WorkerPath)

    if ([string]::IsNullOrWhiteSpace([string]$WorkerPath)) {
        return @()
    }

    return @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $commandLine = [string]$_.CommandLine
                -not [string]::IsNullOrWhiteSpace([string]$commandLine) -and
                $commandLine.IndexOf([string]$WorkerPath, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
            }
    )
}

function Stop-ClagnosInteractiveWorkerProcesses {
    param([string]$WorkerPath)

    foreach ($process in @(Get-ClagnosInteractiveWorkerProcesses -WorkerPath $WorkerPath)) {
        try {
            Stop-Process -Id ([int]$process.ProcessId) -Force -ErrorAction Stop
        }
        catch {
        }
    }
}

function Invoke-ClagnosInteractiveProfileMaterialization {
    param(
        [string]$TaskName,
        [string]$RunAsUser,
        [string]$RunAsPassword,
        [int]$WaitTimeoutSeconds = 180
    )

    $paths = Get-ClagnosInteractivePaths -TaskName $TaskName
    Ensure-ClagnosDirectory -Path $paths.RootPath
    Stop-ClagnosInteractiveWorkerProcesses -WorkerPath $paths.WorkerPath
    Remove-Item -LiteralPath $paths.ResultPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $paths.WorkerPath -Force -ErrorAction SilentlyContinue

    $workerScript = @"
\$ErrorActionPreference = 'Stop'
function Ensure-WorkerDirectory {
    param([string]\$Path)
    if ([string]::IsNullOrWhiteSpace([string]\$Path)) { throw 'Directory path is empty.' }
    if (-not (Test-Path -LiteralPath \$Path)) {
        New-Item -Path \$Path -ItemType Directory -Force | Out-Null
    }
}
function Write-WorkerResult {
    param(
        [string]\$Path,
        [bool]\$Success,
        [string]\$Summary,
        [string[]]\$Details = @()
    )
    \$payload = [ordered]@{
        Success = [bool]\$Success
        Summary = [string]\$Summary
        Details = @(\$Details | ForEach-Object { [string]\$_ })
        CompletedUtc = [DateTime]::UtcNow.ToString('o')
    }
    \$parentPath = Split-Path -Path \$Path -Parent
    Ensure-WorkerDirectory -Path \$parentPath
    \$jsonText = [string](\$payload | ConvertTo-Json -Depth 6)
    [System.IO.File]::WriteAllText(\$Path, \$jsonText, (New-Object System.Text.UTF8Encoding(\$false)))
}
try {
    \$profilePath = [Environment]::GetFolderPath('UserProfile')
    Ensure-WorkerDirectory -Path \$profilePath
    Ensure-WorkerDirectory -Path (Join-Path \$profilePath 'Desktop')
    Write-WorkerResult -Path '__RESULT_PATH__' -Success \$true -Summary 'User profile materialized.' -Details @(\$profilePath)
}
catch {
    Write-WorkerResult -Path '__RESULT_PATH__' -Success \$false -Summary ([string]\$_.Exception.Message)
    throw
}
"@

    $workerScript = $workerScript.Replace('__RESULT_PATH__', [string]$paths.ResultPath.Replace("'", "''"))
    [System.IO.File]::WriteAllText($paths.WorkerPath, [string]$workerScript, (New-Object System.Text.UTF8Encoding($false)))

    try {
        Register-ClagnosInteractiveScheduledTask -TaskName $paths.ScheduledTaskName -RunAsUser $RunAsUser -RunAsPassword $RunAsPassword -WorkerPath $paths.WorkerPath
        Start-ClagnosInteractiveScheduledTask -TaskName $paths.ScheduledTaskName

        $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Max(30, [int]$WaitTimeoutSeconds))
        while ([DateTime]::UtcNow -lt $deadline) {
            if (Test-Path -LiteralPath $paths.ResultPath) {
                $fileInfo = Get-Item -LiteralPath $paths.ResultPath -ErrorAction SilentlyContinue
                if ($null -ne $fileInfo -and [int64]$fileInfo.Length -gt 0) {
                    $result = Read-ClagnosJsonFile -Path $paths.ResultPath
                    if ($result.PSObject.Properties.Match('Success').Count -gt 0 -and [bool]$result.Success) {
                        return $result
                    }

                    $summary = if ($result.PSObject.Properties.Match('Summary').Count -gt 0) { [string]$result.Summary } else { 'Interactive profile materialization failed.' }
                    throw $summary
                }
            }

            Start-Sleep -Seconds 2
        }

        $snapshot = Get-ClagnosInteractiveScheduledTaskSnapshot -TaskName $paths.ScheduledTaskName
        if ($null -eq $snapshot) {
            throw ("Interactive worker timed out without a result file: {0}" -f [string]$paths.ResultPath)
        }

        throw ("Interactive worker timed out without a result file: state={0}; last-task-result={1}; last-run-time={2}" -f [int]$snapshot.State, [int]$snapshot.LastTaskResult, [string]$snapshot.LastRunTime)
    }
    finally {
        try {
            Remove-ClagnosInteractiveScheduledTask -TaskName $paths.ScheduledTaskName
        }
        catch {
        }

        Stop-ClagnosInteractiveWorkerProcesses -WorkerPath $paths.WorkerPath
        Remove-Item -LiteralPath $paths.WorkerPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $paths.ResultPath -Force -ErrorAction SilentlyContinue
    }
}

function Ensure-StandardProfileDirectories {
    param([string]$ProfilePath)

    if ([string]::IsNullOrWhiteSpace([string]$ProfilePath)) {
        throw 'Profile path is empty.'
    }

    Ensure-ClagnosDirectory -Path $ProfilePath
    foreach ($relativePath in @($taskConfig.StandardProfileDirectories)) {
        Ensure-ClagnosDirectory -Path (Join-Path $ProfilePath ([string]$relativePath))
    }
}

function Invoke-CreateProfileForLocalUser {
    param(
        [string]$Sid,
        [string]$UserName
    )

    if ([string]::IsNullOrWhiteSpace([string]$Sid)) {
        throw ("Local user SID is empty for '{0}'." -f [string]$UserName)
    }
    if ([string]::IsNullOrWhiteSpace([string]$UserName)) {
        throw 'Local user name is empty.'
    }

    Ensure-CreateProfileType

    $profilePathBuilder = New-Object System.Text.StringBuilder 260
    $createProfileResult = [ClagnosUserProfileNative]::CreateProfile(
        [string]$Sid,
        [string]$UserName,
        $profilePathBuilder,
        $profilePathBuilder.Capacity
    )

    $resultHex = Get-HResultHex -Value $createProfileResult
    if ($createProfileResult -ne 0 -and $resultHex -ne '0x800700B7') {
        throw ("CreateProfile failed for '{0}' with HRESULT {1}." -f [string]$UserName, [string]$resultHex)
    }

    return [string]$profilePathBuilder.ToString()
}

function Invoke-LoadUserProfileForLocalUser {
    param(
        [string]$UserName,
        [string]$Password
    )

    if ([string]::IsNullOrWhiteSpace([string]$UserName) -or [string]::IsNullOrWhiteSpace([string]$Password)) {
        return
    }

    Ensure-CreateProfileType

    $tokenHandle = [IntPtr]::Zero
    $profileInfo = New-Object ClagnosProfileInfo
    $profileInfo.dwSize = [System.Runtime.InteropServices.Marshal]::SizeOf([type][ClagnosProfileInfo])
    $profileInfo.dwFlags = 1
    $profileInfo.lpUserName = [string]$UserName

    if (-not [ClagnosUserProfileNative]::LogonUser([string]$UserName, '.', [string]$Password, 2, 0, [ref]$tokenHandle)) {
        $logonError = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw ("LogonUser failed for '{0}' with Win32 error {1}." -f [string]$UserName, [int]$logonError)
    }

    try {
        if (-not [ClagnosUserProfileNative]::LoadUserProfile($tokenHandle, [ref]$profileInfo)) {
            $loadError = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw ("LoadUserProfile failed for '{0}' with Win32 error {1}." -f [string]$UserName, [int]$loadError)
        }

        Write-Host ("profile-hive-loaded: {0}" -f [string]$UserName)
    }
    finally {
        try {
            if ($profileInfo.hProfile -ne [IntPtr]::Zero) {
                [void][ClagnosUserProfileNative]::UnloadUserProfile($tokenHandle, $profileInfo.hProfile)
            }
        }
        finally {
            if ($tokenHandle -ne [IntPtr]::Zero) {
                [void][ClagnosUserProfileNative]::CloseHandle($tokenHandle)
            }
        }
    }
}

function Ensure-LocalUserProfileMaterialized {
    param([psobject]$LocalUser)

    if ($null -eq $LocalUser) {
        throw 'Local user object is empty.'
    }

    $userName = [string]$LocalUser.Name
    $userSid = [string]$LocalUser.SID.Value
    if ([string]::IsNullOrWhiteSpace([string]$userSid) -and $LocalUser.PSObject.Properties.Match('SID').Count -gt 0 -and $null -ne $LocalUser.SID) {
        $userSid = [string]$LocalUser.SID
    }

    $existingProfilePath = Get-LocalUserProfilePathBySid -Sid $userSid
    if (Test-LocalUserProfileReady -ProfilePath $existingProfilePath) {
        Ensure-StandardProfileDirectories -ProfilePath $existingProfilePath
        Write-Host ("profile-ready: {0} => {1}" -f [string]$userName, [string]$existingProfilePath)
        return [string]$existingProfilePath
    }

    $repairedProfilePath = Repair-TemporaryProfileMappingIfNeeded -Sid $userSid -UserName $userName
    if (Test-LocalUserProfileReady -ProfilePath $repairedProfilePath) {
        Ensure-StandardProfileDirectories -ProfilePath $repairedProfilePath
        Write-Host ("profile-ready: {0} => {1}" -f [string]$userName, [string]$repairedProfilePath)
        return [string]$repairedProfilePath
    }

    $managedPassword = Get-ManagedLocalUserPassword -UserName $userName
    if (-not [string]::IsNullOrWhiteSpace([string]$managedPassword)) {
        try {
            $null = Invoke-ClagnosInteractiveProfileMaterialization -TaskName ("configure-all-users-materialize-{0}" -f [string]$userName) -RunAsUser $userName -RunAsPassword $managedPassword -WaitTimeoutSeconds ([int]$taskConfig.InteractiveMaterializationWaitSeconds)
        }
        catch {
            Write-Host ("profile-materialization-fallback: {0} => {1}" -f [string]$userName, [string]$_.Exception.Message)
        }

        $interactiveProfilePath = Wait-LocalUserProfileReady -Sid $userSid
        if (Test-LocalUserProfileReady -ProfilePath $interactiveProfilePath) {
            Ensure-StandardProfileDirectories -ProfilePath $interactiveProfilePath
            Write-Host ("profile-materialized: {0} => {1}" -f [string]$userName, [string]$interactiveProfilePath)
            return [string]$interactiveProfilePath
        }

        Invoke-LoadUserProfileForLocalUser -UserName $userName -Password $managedPassword
        $loadedProfilePath = Wait-LocalUserProfileReady -Sid $userSid
        if (Test-LocalUserProfileReady -ProfilePath $loadedProfilePath) {
            Ensure-StandardProfileDirectories -ProfilePath $loadedProfilePath
            Write-Host ("profile-materialized: {0} => {1}" -f [string]$userName, [string]$loadedProfilePath)
            return [string]$loadedProfilePath
        }
    }

    $candidateProfilePath = Invoke-CreateProfileForLocalUser -Sid $userSid -UserName $userName
    $profilePath = Wait-LocalUserProfileReady -Sid $userSid -CandidateProfilePath $candidateProfilePath
    if (-not (Test-LocalUserProfileReady -ProfilePath $profilePath)) {
        throw ("User profile could not be materialized for '{0}'." -f [string]$userName)
    }

    Ensure-StandardProfileDirectories -ProfilePath $profilePath
    Write-Host ("profile-materialized: {0} => {1}" -f [string]$userName, [string]$profilePath)
    return [string]$profilePath
}

$localUsers = @(Get-EnabledLocalUsers)
if (@($localUsers).Count -lt 1) {
    Write-Host 'configure-all-users-ready: no enabled local users found.'
    Write-Host 'Init task completed: configure-all-users'
    return
}

$materializedProfiles = New-Object 'System.Collections.Generic.List[string]'
foreach ($localUser in @($localUsers)) {
    $profilePath = Ensure-LocalUserProfileMaterialized -LocalUser $localUser
    $materializedProfiles.Add(("{0} => {1}" -f [string]$localUser.Name, [string]$profilePath)) | Out-Null
}

Write-Host ("configure-all-users-ready: {0}" -f ((@($materializedProfiles.ToArray())) -join '; '))
Write-Host 'Init task completed: configure-all-users'
