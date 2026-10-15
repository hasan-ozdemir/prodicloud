$ErrorActionPreference = "Stop"
Write-Host "Update task started: copy-user-settings"

$taskName = '10005-copy-user-settings'
$managerUser = "__VM_ADMIN_USER__"
$managerPassword = "__VM_ADMIN_PASS__"
$assistantUser = "__ASSISTANT_USER__"
$assistantPassword = "__ASSISTANT_PASS__"
$helperPath = "C:\Windows\Temp\clagnos-interactive-session-helper.ps1"

if (-not (Test-Path -LiteralPath $helperPath)) {
    throw ("Interactive session helper was not found: {0}" -f $helperPath)
}

. $helperPath

$copySkipEvidence = New-Object 'System.Collections.Generic.List[object]'

function Write-Detail {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace([string]$Text)) {
        return
    }

    Write-Host ([string]$Text)
}

function Write-CopyInfo {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace([string]$Text)) {
        return
    }

    Write-Host ([string]$Text) -ForegroundColor DarkCyan
}

function Add-CopySkipEvidence {
    param(
        [string]$Reason,
        [string]$Label,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace([string]$Reason)) {
        return
    }

    $copySkipEvidence.Add([pscustomobject]@{
        Reason = [string]$Reason
        Label = [string]$Label
        Path = [string]$Path
    }) | Out-Null
}

function Write-CopySkipEvidenceSummary {
    $skipCount = 0
    if ($null -ne ([object]$copySkipEvidence)) {
        $skipCount = [int]$copySkipEvidence.Count
    }

    if ($skipCount -eq 0) {
        Write-Detail 'copy-user-settings-skip-summary: none'
        return
    }

    Write-Detail ("copy-user-settings-skip-summary: count={0}" -f $skipCount)
    foreach ($group in @($copySkipEvidence | Group-Object Reason | Sort-Object Name)) {
        Write-Detail ("copy-user-settings-skip-reason: {0} => {1}" -f [string]$group.Name, [int]$group.Count)
    }

    foreach ($entry in @($copySkipEvidence | Select-Object -First 20)) {
        Write-Detail ("copy-user-settings-skip-item: {0} => {1} => {2}" -f [string]$entry.Reason, [string]$entry.Label, [string]$entry.Path)
    }
}

function Assert-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        [object]$ExpectedValue
    )

    if ([string]::IsNullOrWhiteSpace([string]$Name) -or [string]::Equals([string]$Name, '(default)', [System.StringComparison]::OrdinalIgnoreCase)) {
        $actualValue = [string](Get-Item -Path $Path -ErrorAction Stop).GetValue('')
    }
    else {
        $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        $actualValue = $item.$Name
    }

    if ([string]$actualValue -ne [string]$ExpectedValue) {
        throw ("Registry validation failed: {0}\{1} expected '{2}' but got '{3}'." -f $Path, $Name, $ExpectedValue, $actualValue)
    }
}

function Invoke-RegQuiet {
    param(
        [string]$Verb,
        [string[]]$Arguments
    )

    $segments = @('reg', [string]$Verb)
    foreach ($argument in @($Arguments)) {
        $segments += ('"{0}"' -f [string]$argument)
    }

    $command = ((@($segments) -join ' ') + ' >nul 2>&1')
    cmd.exe /d /c $command | Out-Null
    return [int]$LASTEXITCODE
}

function Test-RegExeBranchExists {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace([string]$Path)) {
        return $false
    }

    return ((Invoke-RegQuiet -Verb 'query' -Arguments @($Path)) -eq 0)
}

function Assert-HiddenShellDesktopIcons {
    param(
        [string]$RootPath,
        [string]$Label
    )

    foreach ($desktopIconRoot in @(
        (Join-Path $RootPath 'Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel'),
        (Join-Path $RootPath 'Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu')
    )) {
        Assert-RegistryValue -Path $desktopIconRoot -Name '{59031a47-3f72-44a7-89c5-5595fe6b30ee}' -ExpectedValue 1
        Assert-RegistryValue -Path $desktopIconRoot -Name '{20D04FE0-3AEA-1069-A2D8-08002B30309D}' -ExpectedValue 1
        Assert-RegistryValue -Path $desktopIconRoot -Name '{5399E694-6CE5-4D6C-8FCE-1D8870FDCBA0}' -ExpectedValue 1
    }

    Write-Detail ("copy-user-settings-shell-icons-hidden: {0}" -f $Label)
}

function Ensure-LocalUserExists {
    param([string]$UserName)

    if ([string]::IsNullOrWhiteSpace([string]$UserName)) {
        throw "User name is empty."
    }

    $user = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
    if ($null -eq $user) {
        throw ("Local user was not found: {0}" -f $UserName)
    }
}

function Clear-DesktopEntries {
    param([string]$DesktopPath)

    if ([string]::IsNullOrWhiteSpace([string]$DesktopPath) -or -not (Test-Path -LiteralPath $DesktopPath)) {
        return
    }

    Get-ChildItem -LiteralPath $DesktopPath -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.PSIsContainer) {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
        }
        else {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
        }
    }

    Write-Detail ("copy-user-settings-desktop-cleared: {0}" -f $DesktopPath)
}

function Get-LocalUserProfilePath {
    param([string]$UserName)

    $expectedPath = "C:\Users\$UserName"
    $profile = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\*' -ErrorAction SilentlyContinue | Where-Object {
        [string]::Equals([string]$_.ProfileImagePath, $expectedPath, [System.StringComparison]::OrdinalIgnoreCase)
    } | Select-Object -First 1

    if ($null -eq $profile) {
        return ''
    }

    return [string]$profile.ProfileImagePath
}

function Test-PortableProfileHiveReady {
    param([string]$ProfilePath)

    if ([string]::IsNullOrWhiteSpace([string]$ProfilePath) -or -not (Test-Path -LiteralPath $ProfilePath)) {
        return $false
    }

    $ntUserPath = Join-Path $ProfilePath 'NTUSER.DAT'
    return (Test-Path -LiteralPath $ntUserPath)
}

function Wait-ClagnosCondition {
    param(
        [scriptblock]$Condition,
        [int]$TimeoutSeconds = 30,
        [int]$PollMilliseconds = 250
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (& $Condition) {
            return $true
        }

        Start-Sleep -Milliseconds $PollMilliseconds
    }

    return $false
}

function Get-LoggedOnUserSessionIds {
    param([string]$UserName)

    if ([string]::IsNullOrWhiteSpace([string]$UserName)) {
        return @()
    }

    $sessionIds = @()
    $quserOutput = @()
    try {
        $quserOutput = @(cmd.exe /c quser 2>$null)
    }
    catch {
        return @()
    }
    foreach ($line in @($quserOutput)) {
        $text = [string]$line
        if ([string]::IsNullOrWhiteSpace([string]$text)) { continue }
        if ($text -match '^\s*USERNAME\b') { continue }

        $normalized = $text.TrimStart('>').Trim()
        $parts = @($normalized -split '\s+')
        if (@($parts).Count -lt 3) { continue }
        if (-not [string]::Equals([string]$parts[0], $UserName, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($parts[2] -match '^\d+$') {
            $sessionIds += [int]$parts[2]
        }
    }

    return @($sessionIds | Select-Object -Unique)
}

function Stop-LoggedOnUserSessions {
    param([string]$UserName)

    foreach ($sessionId in @(Get-LoggedOnUserSessionIds -UserName $UserName)) {
        try {
            & logoff $sessionId | Out-Null
            Write-Detail ("copy-user-settings-session-logoff: {0} => {1}" -f $UserName, $sessionId)
        }
        catch {
            Add-CopySkipEvidence -Reason 'session-logoff-failed' -Label $UserName -Path ([string]$sessionId)
            Write-Detail ("copy-user-settings-session-logoff-skip: {0} => {1}" -f $sessionId, $_.Exception.Message)
        }
    }
}

function Stop-UserProcesses {
    param([string]$UserName)

    if ([string]::IsNullOrWhiteSpace([string]$UserName)) {
        return
    }

    $normalizedUser = $UserName.ToLowerInvariant()
    $processes = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    foreach ($process in @($processes)) {
        try {
            $owner = Invoke-CimMethod -InputObject $process -MethodName GetOwner -ErrorAction Stop
            if ($null -eq $owner -or [int]$owner.ReturnValue -ne 0) { continue }
            $ownerUser = [string]$owner.User
            if ([string]::IsNullOrWhiteSpace([string]$ownerUser)) { continue }
            if (-not [string]::Equals($ownerUser.ToLowerInvariant(), $normalizedUser, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            Stop-Process -Id ([int]$process.ProcessId) -Force -ErrorAction SilentlyContinue
        }
        catch {
        }
    }
}

function Ensure-UserProfileMaterialized {
    param(
        [string]$UserName,
        [string]$UserPassword
    )

    Ensure-LocalUserExists -UserName $UserName

    $existingProfilePath = Get-LocalUserProfilePath -UserName $UserName
    if (-not [string]::IsNullOrWhiteSpace([string]$existingProfilePath) -and (Test-PortableProfileHiveReady -ProfilePath $existingProfilePath)) {
        Write-Detail ("copy-user-settings-profile-ready: {0} => {1}" -f $UserName, $existingProfilePath)
        return [string]$existingProfilePath
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$existingProfilePath) -and (Test-Path -LiteralPath $existingProfilePath)) {
        Write-Detail ("copy-user-settings-profile-partial: {0} => {1}" -f $UserName, $existingProfilePath)
    }

    $materializeTaskName = "{0}-materialize-{1}" -f $taskName, $UserName
    $paths = Get-ClagnosInteractivePaths -TaskName $materializeTaskName
    $workerScript = @'
$ErrorActionPreference = "Stop"
$helperPath = "__HELPER_PATH__"
$resultPath = "__RESULT_PATH__"
$taskName = "__TASK_NAME__"

. $helperPath

$profilePath = [Environment]::GetFolderPath('UserProfile')
Ensure-ClagnosDirectory -Path $profilePath
Ensure-ClagnosDirectory -Path (Join-Path $profilePath 'Desktop')
Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $true -Summary 'User profile materialized.' -Details @($profilePath)
'@

    $workerScript = $workerScript.Replace('__HELPER_PATH__', $helperPath)
    $workerScript = $workerScript.Replace('__RESULT_PATH__', [string]$paths.ResultPath)
    $workerScript = $workerScript.Replace('__TASK_NAME__', $materializeTaskName)

    $null = Invoke-ClagnosInteractiveDesktopAutomation `
        -TaskName $materializeTaskName `
        -RunAsUser $UserName `
        -RunAsPassword $UserPassword `
        -WorkerScriptText $workerScript `
        -WaitTimeoutSeconds 180

    if (-not (Wait-ClagnosCondition -Condition {
        $path = Get-LocalUserProfilePath -UserName $UserName
        return (-not [string]::IsNullOrWhiteSpace([string]$path) -and (Test-PortableProfileHiveReady -ProfilePath $path))
    } -TimeoutSeconds 30)) {
        throw ("User profile hive could not be materialized: {0}" -f $UserName)
    }

    $profilePath = Get-LocalUserProfilePath -UserName $UserName
    Write-Detail ("copy-user-settings-profile-materialized: {0} => {1}" -f $UserName, $profilePath)
    return [string]$profilePath
}

function Remove-RegistryMountIfPresent {
    param([string]$MountName)

    if ([string]::IsNullOrWhiteSpace([string]$MountName)) {
        return
    }

    $null = Invoke-RegQuiet -Verb 'unload' -Arguments @(("HKU\{0}" -f $MountName))
}

function Mount-RegistryHive {
    param(
        [string]$MountName,
        [string]$HiveFilePath
    )

    if ([string]::IsNullOrWhiteSpace([string]$MountName)) {
        throw "Registry mount name is empty."
    }
    if ([string]::IsNullOrWhiteSpace([string]$HiveFilePath) -or -not (Test-Path -LiteralPath $HiveFilePath)) {
        throw ("Registry hive file was not found: {0}" -f $HiveFilePath)
    }

    Remove-RegistryMountIfPresent -MountName $MountName
    $exitCode = Invoke-RegQuiet -Verb 'load' -Arguments @(("HKU\{0}" -f $MountName), $HiveFilePath)
    if ($exitCode -ne 0) {
        throw ("reg load failed for HKU\{0} => {1}" -f $MountName, $HiveFilePath)
    }

    return ("Registry::HKEY_USERS\{0}" -f $MountName)
}

function Dismount-RegistryHive {
    param([string]$MountName)

    if ([string]::IsNullOrWhiteSpace([string]$MountName)) {
        return
    }

    try {
        Set-Location -Path 'C:\'
    }
    catch {
    }

    $registryBranch = "HKU\{0}" -f $MountName
    foreach ($attempt in 1..12) {
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        Start-Sleep -Milliseconds 400

        $exitCode = Invoke-RegQuiet -Verb 'unload' -Arguments @($registryBranch)
        if ($exitCode -eq 0) {
            return
        }

        if (-not (Test-RegExeBranchExists -Path $registryBranch)) {
            return
        }

        Start-Sleep -Milliseconds 800
    }

    $exitCode = Invoke-RegQuiet -Verb 'unload' -Arguments @($registryBranch)
    if ($exitCode -eq 0) {
        return
    }

    if (-not (Test-RegExeBranchExists -Path $registryBranch)) {
        return
    }

    throw ("reg unload failed for HKU\{0} with exit code {1}" -f $MountName, $exitCode)
}

function Test-RegistryRelativePathExcluded {
    param(
        [string]$RelativePath,
        [string[]]$ExcludedPrefixes
    )

    $candidate = [string]$RelativePath
    if ([string]::IsNullOrWhiteSpace([string]$candidate)) {
        return $false
    }

    $candidate = $candidate.Trim('\').ToLowerInvariant()
    foreach ($prefix in @($ExcludedPrefixes)) {
        $normalizedPrefix = [string]$prefix
        if ([string]::IsNullOrWhiteSpace([string]$normalizedPrefix)) { continue }
        $normalizedPrefix = $normalizedPrefix.Trim('\').ToLowerInvariant()
        if ($candidate -eq $normalizedPrefix -or $candidate.StartsWith($normalizedPrefix + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Copy-RegistryBranch {
    param(
        [string]$SourcePath,
        [string]$TargetPath,
        [string[]]$ExcludedPrefixes = @(),
        [string]$RelativePath = ''
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        return
    }

    if (Test-RegistryRelativePathExcluded -RelativePath $RelativePath -ExcludedPrefixes $ExcludedPrefixes) {
        Add-CopySkipEvidence -Reason 'excluded-registry-branch' -Label $RelativePath -Path $SourcePath
        Write-Detail ("copy-user-settings-registry-skip: {0}" -f $RelativePath)
        return
    }

    if (-not (Test-Path -LiteralPath $TargetPath)) {
        New-Item -Path $TargetPath -Force | Out-Null
    }

    try {
        $sourceKey = Get-Item -LiteralPath $SourcePath -ErrorAction Stop
        $targetKey = Get-Item -LiteralPath $TargetPath -ErrorAction Stop
    }
    catch {
        if ($_.Exception -is [System.Security.SecurityException] -or $_.Exception -is [System.UnauthorizedAccessException]) {
            Add-CopySkipEvidence -Reason 'registry-branch-access-denied' -Label $RelativePath -Path $SourcePath
            Write-Detail ("copy-user-settings-registry-branch-skip: access-denied => {0}" -f $SourcePath)
            return
        }
        throw
    }
    $targetValueNames = @($targetKey.GetValueNames())
    try {
        try {
            $defaultValue = $sourceKey.GetValue('', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $defaultKind = $sourceKey.GetValueKind('')
            $targetHasDefault = @($targetValueNames | Where-Object { [string]::IsNullOrEmpty([string]$_) }).Count -gt 0
            if (($null -ne $defaultValue -or $defaultKind -ne [Microsoft.Win32.RegistryValueKind]::Unknown) -and -not $targetHasDefault) {
                Set-ClagnosRegistryValue -Path $TargetPath -Name '(default)' -Value $defaultValue -Kind $defaultKind
            }
        }
        catch {
        }

        foreach ($valueName in @($sourceKey.GetValueNames())) {
            try {
                $valueKind = $sourceKey.GetValueKind($valueName)
                if ($valueKind -eq [Microsoft.Win32.RegistryValueKind]::Unknown) {
                    continue
                }
                if (@($targetValueNames | Where-Object { [string]::Equals([string]$_,[string]$valueName,[System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) {
                    continue
                }
                $valueData = $sourceKey.GetValue($valueName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                Set-ClagnosRegistryValue -Path $TargetPath -Name $valueName -Value $valueData -Kind $valueKind
            }
            catch {
                Add-CopySkipEvidence -Reason 'registry-value-skip' -Label $valueName -Path ("{0}\{1}" -f $SourcePath, $valueName)
                Write-Detail ("copy-user-settings-registry-value-skip: {0}\{1} => {2}" -f $SourcePath, $valueName, $_.Exception.Message)
            }
        }

        foreach ($child in @(Get-ChildItem -LiteralPath $SourcePath -ErrorAction SilentlyContinue)) {
            try {
                $childSourcePath = [string]$child.PSPath
                $childTargetPath = Join-Path $TargetPath $child.PSChildName
                $childRelativePath = if ([string]::IsNullOrWhiteSpace([string]$RelativePath)) {
                    [string]$child.PSChildName
                }
                else {
                    "{0}\{1}" -f $RelativePath.Trim('\'), [string]$child.PSChildName
                }

                Copy-RegistryBranch -SourcePath $childSourcePath -TargetPath $childTargetPath -ExcludedPrefixes $ExcludedPrefixes -RelativePath $childRelativePath
            }
            finally {
                if ($child -is [System.IDisposable]) {
                    $child.Dispose()
                }
            }
        }
    }
    finally {
        if ($targetKey -is [System.IDisposable]) { $targetKey.Dispose() }
        if ($sourceKey -is [System.IDisposable]) {
            $sourceKey.Dispose()
        }
    }
}

function Get-ExistingRobocopyPathList {
    param(
        [string]$BasePath,
        [string[]]$RelativePaths
    )

    $paths = @()
    foreach ($relativePath in @($RelativePaths)) {
        if ([string]::IsNullOrWhiteSpace([string]$relativePath)) { continue }
        $candidate = Join-Path $BasePath $relativePath
        $paths += [string]$candidate
    }

    return @($paths)
}

function Write-ExistingCopyExclusions {
    param(
        [string]$SourcePath,
        [string[]]$ExcludedDirectories = @(),
        [string[]]$ExcludedFiles = @(),
        [string]$Label
    )

    foreach ($relativeDirectory in @($ExcludedDirectories)) {
        if ([string]::IsNullOrWhiteSpace([string]$relativeDirectory)) {
            continue
        }

        $candidate = Join-Path $SourcePath $relativeDirectory
        if (Test-Path -LiteralPath $candidate) {
            Add-CopySkipEvidence -Reason 'excluded-directory' -Label $Label -Path $candidate
            Write-Detail ("copy-user-settings-file-skip: {0} excluded-directory => {1}" -f $Label, $candidate)
        }
    }

    foreach ($excludedFile in @($ExcludedFiles)) {
        $excludedText = [string]$excludedFile
        if ([string]::IsNullOrWhiteSpace([string]$excludedText)) {
            continue
        }

        $candidate = if ($excludedText.Contains('\') -or $excludedText.Contains('/')) {
            Join-Path $SourcePath $excludedText
        }
        else {
            Join-Path $SourcePath $excludedText
        }

        if (Test-Path -LiteralPath $candidate) {
            Add-CopySkipEvidence -Reason 'excluded-file' -Label $Label -Path $candidate
            Write-Detail ("copy-user-settings-file-skip: {0} excluded-file => {1}" -f $Label, $candidate)
        }
    }
}

function Get-TargetPruneSkipReason {
    param([string]$Message)

    $text = [string]$Message
    if ([string]::IsNullOrWhiteSpace([string]$text)) {
        return ''
    }

    $normalized = $text.ToLowerInvariant()
    if ($normalized.Contains('being used by another process') -or $normalized.Contains('cannot access the file')) {
        return 'locked-target'
    }

    if ($normalized.Contains('access is denied') -or $normalized.Contains('error 5')) {
        return 'access-denied'
    }

    if ($normalized.Contains('file cannot be accessed by the system') -or $normalized.Contains('error 1920')) {
        return 'device-specific-placeholder'
    }

    if ($normalized.Contains('reparse point')) {
        return 'reparse-point'
    }

    if ($normalized.Contains('cloud file provider is not running') -or
        $normalized.Contains('error 362') -or
        $normalized.Contains('error 4390') -or
        $normalized.Contains('tag present in the reparse point buffer is invalid')) {
        return 'device-specific-placeholder'
    }

    return ''
}

function Get-RobocopyFailureSkipReason {
    param([string]$DetailText)

    $text = [string]$DetailText
    if ([string]::IsNullOrWhiteSpace([string]$text)) {
        return ''
    }

    $normalized = $text.ToLowerInvariant()
    if ($normalized.Contains('being used by another process') -or
        $normalized.Contains('cannot access the file') -or
        $normalized.Contains('error 32')) {
        return 'locked-file'
    }

    if ($normalized.Contains('access is denied') -or $normalized.Contains('error 5')) {
        return 'access-denied'
    }

    if ($normalized.Contains('file cannot be accessed by the system') -or $normalized.Contains('error 1920')) {
        return 'device-specific-placeholder'
    }

    if ($normalized.Contains('reparse point')) {
        return 'reparse-point'
    }

    if ($normalized.Contains('cloud file provider is not running') -or
        $normalized.Contains('error 362') -or
        $normalized.Contains('error 4390') -or
        $normalized.Contains('tag present in the reparse point buffer is invalid')) {
        return 'device-specific-placeholder'
    }

    return ''
}

function Remove-StaleExcludedTargetPaths {
    param(
        [string]$TargetPath,
        [string[]]$ExcludedDirectories = @(),
        [string[]]$ExcludedFiles = @(),
        [string]$Label
    )

    # Exclusions apply to incoming source data only. Existing target content is
    # user-owned and must never be deleted as a side effect of an update rerun.
    if (-not [string]::IsNullOrWhiteSpace([string]$TargetPath) -and (Test-Path -LiteralPath $TargetPath)) {
        Add-CopySkipEvidence -Reason 'target-preserved' -Label $Label -Path $TargetPath
        Write-Detail ("copy-user-settings-target-preserved: {0}; excluded target data was left untouched" -f $Label)
    }
}

function Invoke-RobocopyBranch {
    param(
        [string]$SourcePath,
        [string]$TargetPath,
        [string[]]$ExcludedDirectories = @(),
        [string[]]$ExcludedFiles = @(),
        [string[]]$TargetPruneExcludedDirectories = @(),
        [string[]]$TargetPruneExcludedFiles = @(),
        [string]$Label
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        Add-CopySkipEvidence -Reason 'missing-source' -Label $Label -Path $SourcePath
        Write-Detail ("copy-user-settings-file-skip: missing source => {0}" -f $SourcePath)
        return
    }

    Ensure-ClagnosDirectory -Path $TargetPath
    $robocopyExe = Join-Path $env:WINDIR 'System32\robocopy.exe'
    if (-not (Test-Path -LiteralPath $robocopyExe)) {
        throw "robocopy.exe was not found."
    }

    if ($PSBoundParameters.ContainsKey('TargetPruneExcludedDirectories') -eq $false -or $null -eq $TargetPruneExcludedDirectories) {
        $TargetPruneExcludedDirectories = @($ExcludedDirectories)
    }
    if ($PSBoundParameters.ContainsKey('TargetPruneExcludedFiles') -eq $false -or $null -eq $TargetPruneExcludedFiles) {
        $TargetPruneExcludedFiles = @($ExcludedFiles)
    }

    Write-ExistingCopyExclusions -SourcePath $SourcePath -ExcludedDirectories $ExcludedDirectories -ExcludedFiles $ExcludedFiles -Label $Label
    Remove-StaleExcludedTargetPaths -TargetPath $TargetPath -ExcludedDirectories $TargetPruneExcludedDirectories -ExcludedFiles $TargetPruneExcludedFiles -Label $Label

    $argumentList = @(
        $SourcePath,
        $TargetPath,
        '/E',
        '/COPY:DAT',
        '/DCOPY:DAT',
        '/MT:16',
        '/R:1',
        '/W:1',
        '/XJ',
        '/XC',
        '/XN',
        '/XO',
        '/NFL',
        '/NDL',
        '/NJH',
        '/NJS',
        '/NP'
    )

    $xdList = @(Get-ExistingRobocopyPathList -BasePath $SourcePath -RelativePaths $ExcludedDirectories)
    if (@($xdList).Count -gt 0) {
        $argumentList += '/XD'
        $argumentList += @($xdList)
    }

    if (@($ExcludedFiles).Count -gt 0) {
        $xfList = @()
        foreach ($excludedFile in @($ExcludedFiles)) {
            $excludedText = [string]$excludedFile
            if ([string]::IsNullOrWhiteSpace([string]$excludedText)) {
                continue
            }

            if ($excludedText.Contains('\') -or $excludedText.Contains('/')) {
                $xfList += (Join-Path $SourcePath $excludedText)
            }
            else {
                $xfList += $excludedText
            }
        }

        $argumentList += '/XF'
        $argumentList += @($xfList)
    }

    $robocopyOutput = @(& $robocopyExe @argumentList 2>&1)
    $exitCode = [int]$LASTEXITCODE
    if ($exitCode -gt 7) {
        $detailLines = @(
            @($robocopyOutput) |
                ForEach-Object { [string]$_ } |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
                Select-Object -Last 25
        )
        $detailText = if (@($detailLines).Count -gt 0) {
            [string](($detailLines -join ' | ') -replace '\s+', ' ')
        }
        else {
            ''
        }

        $normalizedDetail = [string]$detailText
        $normalizedDetail = $normalizedDetail.ToLowerInvariant()
        if ($exitCode -gt 7 -and $normalizedDetail.Contains('webcachelock.dat') -and $normalizedDetail.Contains('error 32')) {
            Write-CopyInfo ("Ignoring locked WebCacheLock.dat while copying {0}; the live WebCache lock file is not required for the replicated profile." -f $Label)
            Add-CopySkipEvidence -Reason 'locked-file' -Label $Label -Path (Join-Path $SourcePath 'Microsoft\Windows\WebCacheLock.dat')
            Write-Detail ("copy-user-settings-file-skip: {0} locked WebCacheLock.dat" -f $Label)
            return
        }

        if ($exitCode -gt 7 -and ($normalizedDetail.Contains('access is denied') -or $normalizedDetail.Contains('error 5'))) {
            Write-CopyInfo ("Ignoring access denied items while copying {0}; protected or session-owned files are skipped for profile safety." -f $Label)
            Add-CopySkipEvidence -Reason 'access-denied' -Label $Label -Path $SourcePath
            Write-Detail ("copy-user-settings-file-skip: {0} access-denied => {1}" -f $Label, $SourcePath)
            return
        }

        $skipReason = Get-RobocopyFailureSkipReason -DetailText $detailText
        if (-not [string]::IsNullOrWhiteSpace([string]$skipReason)) {
            Write-CopyInfo ("Skipping non-portable items while copying {0}; branch contained {1} artifacts that should not be mirrored." -f $Label, $skipReason)
            Add-CopySkipEvidence -Reason $skipReason -Label $Label -Path $SourcePath
            Write-Detail ("copy-user-settings-file-skip: {0} {1} => {2}" -f $Label, $skipReason, $SourcePath)
            return
        }

        if ([string]::IsNullOrWhiteSpace([string]$detailText)) {
            throw ("robocopy failed for {0} with exit code {1}." -f $Label, $exitCode)
        }

        throw ("robocopy failed for {0} with exit code {1}. detail: {2}" -f $Label, $exitCode, $detailText)
    }

    Remove-StaleExcludedTargetPaths -TargetPath $TargetPath -ExcludedDirectories $TargetPruneExcludedDirectories -ExcludedFiles $TargetPruneExcludedFiles -Label $Label
    Write-Detail ("copy-user-settings-file-ok: {0}" -f $Label)
}

function Invoke-ProfileRelativeCopy {
    param(
        [string]$SourceProfilePath,
        [string]$TargetProfilePath,
        [string]$RelativePath,
        [string]$Label,
        [string[]]$ExcludedDirectories = @(),
        [string[]]$ExcludedFiles = @()
    )

    if ([string]::IsNullOrWhiteSpace([string]$RelativePath)) {
        return
    }

    $sourcePath = Join-Path $SourceProfilePath $RelativePath
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        Add-CopySkipEvidence -Reason 'missing-source' -Label $Label -Path $sourcePath
        Write-Detail ("copy-user-settings-file-skip: missing source => {0}" -f $RelativePath)
        return
    }

    $targetPath = Join-Path $TargetProfilePath $RelativePath
    $sourceItem = Get-Item -LiteralPath $sourcePath -Force -ErrorAction Stop
    $isSourceReparsePoint = (($sourceItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq [System.IO.FileAttributes]::ReparsePoint)
    if ($isSourceReparsePoint) {
        Add-CopySkipEvidence -Reason 'reparse-point' -Label $Label -Path $sourcePath
        Write-Detail ("copy-user-settings-file-skip: {0} source reparse-point => {1}" -f $Label, $RelativePath)
        return
    }

    if ($sourceItem.PSIsContainer) {
        Invoke-RobocopyBranch `
            -SourcePath $sourcePath `
            -TargetPath $targetPath `
            -ExcludedDirectories $ExcludedDirectories `
            -ExcludedFiles $ExcludedFiles `
            -Label $Label
        return
    }

    Ensure-ClagnosDirectory -Path (Split-Path -Path $targetPath -Parent)
    try {
        Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force -ErrorAction Stop
        Write-Detail ("copy-user-settings-file-ok: {0}" -f $Label)
    }
    catch {
        $message = [string]$_.Exception.Message
        $normalizedMessage = $message.ToLowerInvariant()
        if ($normalizedMessage.Contains('access to the path') -or $normalizedMessage.Contains('access is denied')) {
            Add-CopySkipEvidence -Reason 'access-denied' -Label $Label -Path $sourcePath
            Write-CopyInfo ("Skipping access denied file while copying {0}: {1}" -f $Label, $sourcePath)
            Write-Detail ("copy-user-settings-file-skip: {0} access-denied => {1}" -f $Label, $RelativePath)
            return
        }

        if ($normalizedMessage.Contains('because it is being used by another process') -or $normalizedMessage.Contains('being used by another process')) {
            Add-CopySkipEvidence -Reason 'locked-file' -Label $Label -Path $sourcePath
            Write-CopyInfo ("Skipping locked file while copying {0}: {1}" -f $Label, $sourcePath)
            Write-Detail ("copy-user-settings-file-skip: {0} locked-file => {1}" -f $Label, $RelativePath)
            return
        }

        throw
    }
}

function Test-UserProcessesRunning {
    param([string]$UserName)

    if ([string]::IsNullOrWhiteSpace([string]$UserName)) {
        return $false
    }

    $normalizedUser = $UserName.ToLowerInvariant()
    foreach ($process in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)) {
        try {
            $owner = Invoke-CimMethod -InputObject $process -MethodName GetOwner -ErrorAction Stop
            if ($null -eq $owner -or [int]$owner.ReturnValue -ne 0) { continue }
            $ownerUser = [string]$owner.User
            if ([string]::IsNullOrWhiteSpace([string]$ownerUser)) { continue }
            if ([string]::Equals($ownerUser.ToLowerInvariant(), $normalizedUser, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
        catch {
        }
    }

    return $false
}

function Wait-UserSessionsAndProcessesToSettle {
    param(
        [string]$UserName,
        [int]$TimeoutSeconds = 8
    )

    $settled = Wait-ClagnosCondition -Condition {
        (@(Get-LoggedOnUserSessionIds -UserName $UserName).Count -eq 0) -and
        (-not (Test-UserProcessesRunning -UserName $UserName))
    } -TimeoutSeconds $TimeoutSeconds -PollMilliseconds 250

    if ($settled) {
        Write-Detail ("copy-user-settings-user-settled: {0}" -f $UserName)
        return
    }

    Write-CopyInfo ("Proceeding after the bounded user-settle wait expired for {0}; later copy steps will still validate the resulting state." -f $UserName)
}

function Get-LoadedUserHiveRoots {
    param([string]$UserName)

    Ensure-LocalUserExists -UserName $UserName
    $user = Get-LocalUser -Name $UserName -ErrorAction Stop
    $sid = [string]$user.SID
    $mainRoot = ''
    $classesRoot = ''

    if (-not [string]::IsNullOrWhiteSpace([string]$sid)) {
        $candidateMainRoot = "Registry::HKEY_USERS\$sid"
        if (Test-Path -LiteralPath $candidateMainRoot) {
            $mainRoot = $candidateMainRoot
        }

        $candidateClassesRoot = "Registry::HKEY_USERS\${sid}_Classes"
        if (Test-Path -LiteralPath $candidateClassesRoot) {
            $classesRoot = $candidateClassesRoot
        }
    }

    return [pscustomobject]@{
        Sid = [string]$sid
        MainRoot = [string]$mainRoot
        ClassesRoot = [string]$classesRoot
    }
}

function Get-PortableProfileExcludedDirectories {
    return @(
        'AppData\Local\Temp',
        'AppData\LocalLow\Temp',
        'AppData\Local\CrashDumps',
        'AppData\Local\ConnectedDevicesPlatform',
        'AppData\Local\D3DSCache',
        'AppData\Local\Comms',
        'AppData\Local\Programs',
        'AppData\Local\npm-cache',
        'AppData\Local\Package Cache',
        'AppData\Local\Ollama',
        'AppData\Local\Docker',
        'AppData\Local\Microsoft\WindowsApps',
        'AppData\Local\Microsoft\Windows\INetCache',
        'AppData\Local\Microsoft\Windows\WebCache',
        'AppData\Local\Microsoft\Windows\Explorer',
        'AppData\Local\Microsoft\Windows\Notifications',
        'AppData\Local\Microsoft\Windows\DeliveryOptimization',
        'AppData\Local\Microsoft\Credentials',
        'AppData\Roaming\Microsoft\Credentials',
        'AppData\Local\Microsoft\Protect',
        'AppData\Roaming\Microsoft\Protect',
        'AppData\Local\Microsoft\Vault',
        'AppData\Roaming\Microsoft\Vault',
        'AppData\Local\Microsoft\IdentityCRL',
        'AppData\Roaming\Microsoft\IdentityCRL',
        'AppData\Roaming\npm',
        'AppData\Local\Publishers',
        'AppData\Local\docker-secrets-engine',
        'AppData\Local\Packages'
    )
}

function Get-PortableProfileExcludedFiles {
    return @(
        'NTUSER.DAT*',
        'UsrClass.dat*',
        '*.lock',
        '*.tmp',
        '*.temp',
        '*.etl',
        '*.log',
        '*.db-shm',
        '*.db-wal',
        '*.crdownload',
        'thumbcache*',
        'iconcache*',
        'WebCacheLock.dat',
        'Login Data*',
        'Cookies*'
    )
}

function Get-PortableProfileTargetPruneExcludedFiles {
    return @(
        @(Get-PortableProfileExcludedFiles) |
            Where-Object {
                [string]$_ -notin @(
                    'NTUSER.DAT*',
                    'UsrClass.dat*'
                )
            }
    )
}

function Get-PortableRegistryExcludedPrefixes {
    return @(
        'Software\Classes',
        'Software\Microsoft\Windows\CurrentVersion\CloudStore',
        'Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts',
        'Software\Microsoft\Windows\Shell\Associations',
        'Software\Microsoft\IdentityCRL'
    )
}

function Get-PortableRegistryClassesExcludedPrefixes {
    return @(
        'Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository'
    )
}

function Assert-RepresentativePathCopiedIfPresent {
    param(
        [string]$SourceProfilePath,
        [string]$TargetProfilePath,
        [string]$RelativePath
    )

    $sourcePath = Join-Path $SourceProfilePath $RelativePath
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        return
    }

    $targetPath = Join-Path $TargetProfilePath $RelativePath
    if (-not (Test-Path -LiteralPath $targetPath)) {
        throw ("Representative mirrored path is missing: {0}" -f $targetPath)
    }
}

function Assert-ExcludedPathAbsentIfPresent {
    param(
        [string]$SourceProfilePath,
        [string]$TargetProfilePath,
        [string]$RelativePath
    )

    $sourcePath = Join-Path $SourceProfilePath $RelativePath
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        return
    }

    $targetPath = Join-Path $TargetProfilePath $RelativePath
    if (Test-Path -LiteralPath $targetPath) {
        throw ("Excluded portable path was copied unexpectedly: {0}" -f $RelativePath)
    }
}

function Assert-RegistryBranchMirroredIfPresent {
    param(
        [string]$SourceRoot,
        [string]$TargetRoot,
        [string]$RelativePath
    )

    $sourcePath = if ([string]::IsNullOrWhiteSpace([string]$RelativePath)) { $SourceRoot } else { Join-Path $SourceRoot $RelativePath }
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        return
    }

    $targetPath = if ([string]::IsNullOrWhiteSpace([string]$RelativePath)) { $TargetRoot } else { Join-Path $TargetRoot $RelativePath }
    if (-not (Test-Path -LiteralPath $targetPath)) {
        throw ("Representative mirrored registry branch is missing: {0}" -f $targetPath)
    }
}

function Invoke-PortableProfileMirror {
    param(
        [string]$SourceProfilePath,
        [string]$TargetProfilePath,
        [string]$Label
    )

    Ensure-ClagnosDirectory -Path $TargetProfilePath
    Invoke-RobocopyBranch `
        -SourcePath $SourceProfilePath `
        -TargetPath $TargetProfilePath `
        -ExcludedDirectories @(Get-PortableProfileExcludedDirectories) `
        -ExcludedFiles @(Get-PortableProfileExcludedFiles) `
        -TargetPruneExcludedFiles @(Get-PortableProfileTargetPruneExcludedFiles) `
        -Label $Label
}

function Invoke-PortableRegistryMirror {
    param(
        [string]$SourceMainRoot,
        [string]$TargetMainRoot,
        [string]$SourceClassesRoot = '',
        [string]$TargetClassesRoot = '',
        [string]$Label
    )

    Copy-RegistryBranch `
        -SourcePath $SourceMainRoot `
        -TargetPath $TargetMainRoot `
        -ExcludedPrefixes @(Get-PortableRegistryExcludedPrefixes) `
        -RelativePath ''
    Write-Detail ("copy-user-settings-registry-main-ok: {0}" -f $Label)

    if (-not [string]::IsNullOrWhiteSpace([string]$SourceClassesRoot) -and
        -not [string]::IsNullOrWhiteSpace([string]$TargetClassesRoot) -and
        (Test-Path -LiteralPath $SourceClassesRoot)) {
        Copy-RegistryBranch `
            -SourcePath $SourceClassesRoot `
            -TargetPath $TargetClassesRoot `
            -ExcludedPrefixes @(Get-PortableRegistryClassesExcludedPrefixes) `
            -RelativePath ''
        Write-Detail ("copy-user-settings-registry-classes-ok: {0}" -f $Label)
    }
}

function Invoke-PortableAssistantRegistryMirror {
    param(
        [string]$UserName,
        [string]$ProfilePath
    )

    $ntUserPath = Join-Path $ProfilePath 'NTUSER.DAT'
    $usrClassPath = Join-Path $ProfilePath 'AppData\Local\Microsoft\Windows\UsrClass.dat'
    $loadedRoots = Get-LoadedUserHiveRoots -UserName $UserName

    if (-not [string]::IsNullOrWhiteSpace([string]$loadedRoots.MainRoot)) {
        Invoke-PortableRegistryMirror `
            -SourceMainRoot 'Registry::HKEY_CURRENT_USER' `
            -TargetMainRoot ([string]$loadedRoots.MainRoot) `
            -SourceClassesRoot 'Registry::HKEY_CURRENT_USER\Software\Classes' `
            -TargetClassesRoot ([string]$loadedRoots.ClassesRoot) `
            -Label 'assistant'
        return
    }

    if (-not (Test-Path -LiteralPath $ntUserPath)) {
        Write-CopyInfo ("Skipping assistant registry mirror because the portable user hive is not materialized yet: {0}" -f $ntUserPath)
        Add-CopySkipEvidence -Reason 'missing-assistant-hive' -Label 'assistant' -Path $ntUserPath
        return
    }

    $mainMountName = 'ClagnosAssistantNtUser'
    $classesMountName = 'ClagnosAssistantUsrClass'
    $mainRoot = $null
    $classesRoot = $null
    try {
        $mainRoot = Mount-RegistryHive -MountName $mainMountName -HiveFilePath $ntUserPath
        if (Test-Path -LiteralPath $usrClassPath) {
            $classesRoot = Mount-RegistryHive -MountName $classesMountName -HiveFilePath $usrClassPath
        }

        Invoke-PortableRegistryMirror `
            -SourceMainRoot 'Registry::HKEY_CURRENT_USER' `
            -TargetMainRoot $mainRoot `
            -SourceClassesRoot 'Registry::HKEY_CURRENT_USER\Software\Classes' `
            -TargetClassesRoot $classesRoot `
            -Label 'assistant'
    }
    finally {
        foreach ($mountName in @($classesMountName, $mainMountName)) {
            if ([string]::IsNullOrWhiteSpace([string]$mountName)) {
                continue
            }
            try {
                Dismount-RegistryHive -MountName $mountName
            }
            catch {
                Write-Detail ("copy-user-settings-hive-unload-warning: {0}" -f $_.Exception.Message)
                throw
            }
        }
    }
}

function Invoke-PortableDefaultProfileRegistryMirror {
    param([string]$DefaultProfilePath)

    $ntUserPath = Join-Path $DefaultProfilePath 'NTUSER.DAT'
    $usrClassPath = Join-Path $DefaultProfilePath 'AppData\Local\Microsoft\Windows\UsrClass.dat'
    if (-not (Test-Path -LiteralPath $ntUserPath)) {
        Write-CopyInfo ("Skipping default-profile registry mirror because the portable user hive is not present: {0}" -f $ntUserPath)
        Add-CopySkipEvidence -Reason 'missing-default-hive' -Label 'default-profile' -Path $ntUserPath
        return
    }

    $mainMountName = 'ClagnosDefaultNtUser'
    $classesMountName = 'ClagnosDefaultUsrClass'
    $mainRoot = $null
    $classesRoot = $null
    try {
        $mainRoot = Mount-RegistryHive -MountName $mainMountName -HiveFilePath $ntUserPath
        if (Test-Path -LiteralPath $usrClassPath) {
            $classesRoot = Mount-RegistryHive -MountName $classesMountName -HiveFilePath $usrClassPath
        }

        Invoke-PortableRegistryMirror `
            -SourceMainRoot 'Registry::HKEY_CURRENT_USER' `
            -TargetMainRoot $mainRoot `
            -SourceClassesRoot 'Registry::HKEY_CURRENT_USER\Software\Classes' `
            -TargetClassesRoot $classesRoot `
            -Label 'default-profile'
    }
    finally {
        foreach ($mountName in @($classesMountName, $mainMountName)) {
            if ([string]::IsNullOrWhiteSpace([string]$mountName)) {
                continue
            }
            try {
                Dismount-RegistryHive -MountName $mountName
            }
            catch {
                Write-Detail ("copy-user-settings-hive-unload-warning: {0}" -f $_.Exception.Message)
                throw
            }
        }
    }
}

function Invoke-PortableLogonRegistryMirror {
    Invoke-PortableRegistryMirror `
        -SourceMainRoot 'Registry::HKEY_CURRENT_USER' `
        -TargetMainRoot 'Registry::HKEY_USERS\.DEFAULT' `
        -Label 'logon-screen'
}

Ensure-LocalUserExists -UserName $managerUser
Ensure-LocalUserExists -UserName $assistantUser

$managerProfilePath = Get-LocalUserProfilePath -UserName $managerUser
if ([string]::IsNullOrWhiteSpace([string]$managerProfilePath) -or -not (Test-Path -LiteralPath $managerProfilePath)) {
    throw ("Manager profile path was not found: {0}" -f $managerUser)
}

$assistantProfilePath = Ensure-UserProfileMaterialized -UserName $assistantUser -UserPassword $assistantPassword
Write-Detail 'copy-user-settings-user-sessions-preserved: no managed-user sessions or processes were stopped'

$defaultProfilePath = 'C:\Users\Default'
if (-not (Test-Path -LiteralPath $defaultProfilePath)) {
    throw ("Default user profile path was not found: {0}" -f $defaultProfilePath)
}

Invoke-PortableProfileMirror -SourceProfilePath $managerProfilePath -TargetProfilePath $assistantProfilePath -Label 'assistant'
Write-Detail 'copy-user-settings-stage-ok: assistant-profile-mirror'
Invoke-PortableProfileMirror -SourceProfilePath $managerProfilePath -TargetProfilePath $defaultProfilePath -Label 'default-profile'
Write-Detail 'copy-user-settings-stage-ok: default-profile-mirror'
Invoke-PortableAssistantRegistryMirror -UserName $assistantUser -ProfilePath $assistantProfilePath
Write-Detail 'copy-user-settings-stage-ok: assistant-registry-mirror'
Invoke-PortableDefaultProfileRegistryMirror -DefaultProfilePath $defaultProfilePath
Write-Detail 'copy-user-settings-stage-ok: default-profile-registry-mirror'
Invoke-PortableLogonRegistryMirror
Write-Detail 'copy-user-settings-stage-ok: logon-registry-mirror'

foreach ($requiredRelativePath in @(
    'Desktop',
    'Documents',
    'Favorites',
    'Videos',
    'Pictures',
    'Downloads',
    'Links',
    'Music'
)) {
    Assert-RepresentativePathCopiedIfPresent -SourceProfilePath $managerProfilePath -TargetProfilePath $assistantProfilePath -RelativePath $requiredRelativePath
    Assert-RepresentativePathCopiedIfPresent -SourceProfilePath $managerProfilePath -TargetProfilePath $defaultProfilePath -RelativePath $requiredRelativePath
}

$assistantLoadedRoots = Get-LoadedUserHiveRoots -UserName $assistantUser
if (-not [string]::IsNullOrWhiteSpace([string]$assistantLoadedRoots.MainRoot)) {
    Assert-RegistryBranchMirroredIfPresent -SourceRoot 'Registry::HKEY_CURRENT_USER' -TargetRoot ([string]$assistantLoadedRoots.MainRoot) -RelativePath 'Software\Microsoft\Windows\CurrentVersion\Explorer'
    Assert-RegistryBranchMirroredIfPresent -SourceRoot 'Registry::HKEY_CURRENT_USER' -TargetRoot ([string]$assistantLoadedRoots.MainRoot) -RelativePath 'Environment'
}

Assert-RegistryBranchMirroredIfPresent -SourceRoot 'Registry::HKEY_CURRENT_USER' -TargetRoot 'Registry::HKEY_USERS\.DEFAULT' -RelativePath 'Software\Microsoft\Windows\CurrentVersion\Explorer'
Assert-RegistryBranchMirroredIfPresent -SourceRoot 'Registry::HKEY_CURRENT_USER' -TargetRoot 'Registry::HKEY_USERS\.DEFAULT' -RelativePath 'Environment'

Write-CopySkipEvidenceSummary
Write-Detail 'copy-user-settings-portable-mirror-validated'
Write-Host "copy-user-settings-completed"
Write-Host "Update task completed: copy-user-settings"

