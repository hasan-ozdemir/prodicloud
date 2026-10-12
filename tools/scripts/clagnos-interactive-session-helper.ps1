Set-StrictMode -Version 2.0

function Ensure-ClagnosDirectory {
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace([string]$Path)) {
        throw "Directory path is empty."
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Open-ClagnosWritableRegistryKey {
    param(
        [string]$Path
    )

    $regPath = Convert-ClagnosRegistryProviderPathToRegExePath -Path $Path
    $baseKey = $null
    $subKey = ''

    switch -regex ($regPath) {
        '^HKEY_CURRENT_USER(?:\\(?<sub>.*))?$' {
            $baseKey = [Microsoft.Win32.Registry]::CurrentUser
            $subKey = [string]$Matches['sub']
            break
        }
        '^HKEY_LOCAL_MACHINE(?:\\(?<sub>.*))?$' {
            $baseKey = [Microsoft.Win32.Registry]::LocalMachine
            $subKey = [string]$Matches['sub']
            break
        }
        '^HKEY_USERS(?:\\(?<sub>.*))?$' {
            $baseKey = [Microsoft.Win32.Registry]::Users
            $subKey = [string]$Matches['sub']
            break
        }
        '^HKEY_CLASSES_ROOT(?:\\(?<sub>.*))?$' {
            $baseKey = [Microsoft.Win32.Registry]::ClassesRoot
            $subKey = [string]$Matches['sub']
            break
        }
        '^HKEY_CURRENT_CONFIG(?:\\(?<sub>.*))?$' {
            $baseKey = [Microsoft.Win32.Registry]::CurrentConfig
            $subKey = [string]$Matches['sub']
            break
        }
        default {
            throw ("Unsupported registry hive: {0}" -f $regPath)
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$subKey)) {
        return $baseKey
    }

    $key = $baseKey.OpenSubKey($subKey, $true)
    if ($null -ne $key) {
        return $key
    }

    return $baseKey.CreateSubKey($subKey)
}

function Set-ClagnosRegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        [object]$Value,
        [Microsoft.Win32.RegistryValueKind]$Kind
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }

    if ((Get-Item -LiteralPath $Path).PSProvider.Name -eq 'Registry') {
        $isDefaultValue = ([string]::IsNullOrWhiteSpace([string]$Name) -or [string]::Equals([string]$Name, '(default)', [System.StringComparison]::OrdinalIgnoreCase))
        $registryValueName = if ($isDefaultValue) { '' } else { [string]$Name }
        $key = $null
        try {
            $key = Open-ClagnosWritableRegistryKey -Path $Path
            $key.SetValue($registryValueName, $Value, $Kind)
            return
        }
        catch [System.UnauthorizedAccessException] {
            Set-ClagnosRegistryValueWithRegExe -Path $Path -Name $Name -Value $Value -Kind $Kind -IsDefaultValue:$isDefaultValue
            return
        }
        finally {
            if ($key -is [System.IDisposable]) {
                $key.Dispose()
            }
        }
    }

    throw ("Unsupported registry path: {0}" -f $Path)
}

function Convert-ClagnosRegistryProviderPathToRegExePath {
    param([string]$Path)

    $candidate = [string]$Path
    if ([string]::IsNullOrWhiteSpace([string]$candidate)) {
        throw "Registry path is empty."
    }

    if ($candidate.StartsWith('Registry::', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $candidate.Substring(10)
    }

    if ($candidate -match '^(HKLM|HKCU|HKCR|HKU|HKCC):\\') {
        return ($candidate -replace '^(HKLM):', 'HKEY_LOCAL_MACHINE' `
                            -replace '^(HKCU):', 'HKEY_CURRENT_USER' `
                            -replace '^(HKCR):', 'HKEY_CLASSES_ROOT' `
                            -replace '^(HKU):', 'HKEY_USERS' `
                            -replace '^(HKCC):', 'HKEY_CURRENT_CONFIG')
    }

    return $candidate
}

function Convert-ClagnosRegistryValueKindToRegExeType {
    param([Microsoft.Win32.RegistryValueKind]$Kind)

    switch ($Kind) {
        ([Microsoft.Win32.RegistryValueKind]::String) { return 'REG_SZ' }
        ([Microsoft.Win32.RegistryValueKind]::ExpandString) { return 'REG_EXPAND_SZ' }
        ([Microsoft.Win32.RegistryValueKind]::DWord) { return 'REG_DWORD' }
        ([Microsoft.Win32.RegistryValueKind]::QWord) { return 'REG_QWORD' }
        ([Microsoft.Win32.RegistryValueKind]::MultiString) { return 'REG_MULTI_SZ' }
        ([Microsoft.Win32.RegistryValueKind]::Binary) { return 'REG_BINARY' }
        default { throw ("Unsupported registry value kind for reg.exe fallback: {0}" -f [string]$Kind) }
    }
}

function Convert-ClagnosRegistryValueToRegExeData {
    param(
        [object]$Value,
        [Microsoft.Win32.RegistryValueKind]$Kind
    )

    switch ($Kind) {
        ([Microsoft.Win32.RegistryValueKind]::String) { return [string]$Value }
        ([Microsoft.Win32.RegistryValueKind]::ExpandString) { return [string]$Value }
        ([Microsoft.Win32.RegistryValueKind]::DWord) { return [string]([uint32]$Value) }
        ([Microsoft.Win32.RegistryValueKind]::QWord) { return [string]([uint64]$Value) }
        ([Microsoft.Win32.RegistryValueKind]::MultiString) { return ((@($Value) | ForEach-Object { [string]$_ }) -join '\0') }
        ([Microsoft.Win32.RegistryValueKind]::Binary) { return ((@($Value) | ForEach-Object { '{0:x2}' -f [byte]$_ }) -join ',') }
        default { throw ("Unsupported registry value data for reg.exe fallback: {0}" -f [string]$Kind) }
    }
}

function Set-ClagnosRegistryValueWithRegExe {
    param(
        [string]$Path,
        [string]$Name,
        [object]$Value,
        [Microsoft.Win32.RegistryValueKind]$Kind,
        [switch]$IsDefaultValue
    )

    $regPath = Convert-ClagnosRegistryProviderPathToRegExePath -Path $Path
    $regType = Convert-ClagnosRegistryValueKindToRegExeType -Kind $Kind
    $regData = Convert-ClagnosRegistryValueToRegExeData -Value $Value -Kind $Kind

    & reg.exe add $regPath /f | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw ("reg add failed while creating key '{0}'." -f $regPath)
    }

    $arguments = @('add', $regPath)
    if ($IsDefaultValue) {
        $arguments += '/ve'
    }
    else {
        $arguments += '/v'
        $arguments += [string]$Name
    }
    $arguments += '/t'
    $arguments += $regType
    $arguments += '/d'
    $arguments += [string]$regData
    $arguments += '/f'

    & reg.exe @arguments | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw ("reg add failed for '{0}'." -f $regPath)
    }
}

function Get-ClagnosInteractivePaths {
    param(
        [string]$TaskName
    )

    $taskNameText = [string]$TaskName
    if ([string]::IsNullOrWhiteSpace([string]$taskNameText)) {
        throw "Interactive task name is empty."
    }

    $safeTaskName = ($taskNameText -replace '[^a-zA-Z0-9\-]', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace([string]$safeTaskName)) {
        throw "Interactive task name became empty after sanitization."
    }

    $rootPath = Join-Path 'C:\ProgramData\clagnos\interactive' $safeTaskName
    return [pscustomobject]@{
        RootPath = $rootPath
        WorkerPath = Join-Path $rootPath 'worker.ps1'
        ResultPath = Join-Path $rootPath 'result.json'
        LogPath = Join-Path $rootPath 'worker.log'
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
    param(
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw ("JSON file was not found: {0}" -f $Path)
    }

    $text = [string](Get-Content -LiteralPath $Path -Raw -ErrorAction Stop)
    if ([string]::IsNullOrWhiteSpace([string]$text)) {
        throw ("JSON file is empty: {0}" -f $Path)
    }

    return (ConvertFrom-Json -InputObject $text)
}

function Write-ClagnosInteractiveResult {
    param(
        [string]$ResultPath,
        [string]$TaskName,
        [bool]$Success,
        [string]$Summary,
        [string[]]$Details = @()
    )

    $payload = [ordered]@{
        TaskName = [string]$TaskName
        Success = [bool]$Success
        Summary = [string]$Summary
        Details = @($Details | ForEach-Object { [string]$_ })
        CompletedUtc = [DateTime]::UtcNow.ToString('o')
    }

    Write-ClagnosJsonFile -Path $ResultPath -Value $payload
}

function Wait-ClagnosFileReady {
    param(
        [string]$Path,
        [int]$TimeoutSeconds = 600,
        [int]$PollSeconds = 2
    )

    if ($TimeoutSeconds -lt 5) {
        $TimeoutSeconds = 5
    }
    if ($PollSeconds -lt 1) {
        $PollSeconds = 1
    }

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $Path) {
            $fileInfo = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
            if ($null -ne $fileInfo -and [int64]$fileInfo.Length -gt 0) {
                return $true
            }
        }

        Start-Sleep -Seconds $PollSeconds
    }

    return $false
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

    throw "powershell.exe was not found."
}

function Get-ClagnosLocalPrincipalName {
    param(
        [string]$UserName
    )

    if ([string]::IsNullOrWhiteSpace([string]$UserName)) {
        throw "User name is empty."
    }

    return ("{0}\{1}" -f $env:COMPUTERNAME, [string]$UserName)
}

function Get-ClagnosUserNameVariants {
    param(
        [string]$UserName
    )

    $variants = New-Object 'System.Collections.Generic.List[string]'
    if ([string]::IsNullOrWhiteSpace([string]$UserName)) {
        return @($variants.ToArray())
    }

    foreach ($candidate in @(
        [string]$UserName,
        ('.\' + [string]$UserName),
        ("{0}\{1}" -f [string]$env:COMPUTERNAME, [string]$UserName)
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$candidate)) {
            continue
        }

        if (-not $variants.Contains([string]$candidate)) {
            [void]$variants.Add([string]$candidate)
        }
    }

    return @($variants.ToArray())
}

function Test-ClagnosUserNameMatch {
    param(
        [string]$ObservedUserName,
        [string]$ExpectedUserName
    )

    if ([string]::IsNullOrWhiteSpace([string]$ObservedUserName) -or [string]::IsNullOrWhiteSpace([string]$ExpectedUserName)) {
        return $false
    }

    foreach ($candidate in @(Get-ClagnosUserNameVariants -UserName $ExpectedUserName)) {
        if ([string]::Equals([string]$ObservedUserName, [string]$candidate, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Get-ClagnosWinlogonAutologonState {
    function Get-WinlogonPropertyText {
        param(
            [AllowNull()]
            [psobject]$InputObject,
            [string]$PropertyName
        )

        if ($null -eq $InputObject -or [string]::IsNullOrWhiteSpace([string]$PropertyName)) {
            return ''
        }

        if ($InputObject.PSObject.Properties.Match([string]$PropertyName).Count -lt 1) {
            return ''
        }

        return [string]$InputObject.([string]$PropertyName)
    }

    $winlogon = $null
    try {
        $winlogon = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction Stop
    }
    catch {
        $winlogon = $null
    }

    $autoAdminLogon = Get-WinlogonPropertyText -InputObject $winlogon -PropertyName 'AutoAdminLogon'
    $defaultUserName = Get-WinlogonPropertyText -InputObject $winlogon -PropertyName 'DefaultUserName'
    $defaultDomainName = Get-WinlogonPropertyText -InputObject $winlogon -PropertyName 'DefaultDomainName'
    $defaultPassword = Get-WinlogonPropertyText -InputObject $winlogon -PropertyName 'DefaultPassword'

    return [pscustomobject]@{
        AutoAdminLogon = [string]$autoAdminLogon
        AutoAdminLogonEnabled = [string]::Equals([string]$autoAdminLogon, '1', [System.StringComparison]::OrdinalIgnoreCase)
        DefaultUserName = [string]$defaultUserName
        DefaultDomainName = [string]$defaultDomainName
        DefaultPasswordPresent = (-not [string]::IsNullOrWhiteSpace([string]$defaultPassword))
    }
}

function Get-ClagnosExplorerProcessOwners {
    $owners = New-Object 'System.Collections.Generic.List[string]'

    try {
        $explorerProcesses = @(Get-Process -Name 'explorer' -IncludeUserName -ErrorAction Stop)
        foreach ($process in @($explorerProcesses)) {
            $ownerName = [string]$process.UserName
            if ([string]::IsNullOrWhiteSpace([string]$ownerName)) {
                continue
            }

            if (-not $owners.Contains([string]$ownerName)) {
                [void]$owners.Add([string]$ownerName)
            }
        }
    }
    catch {
    }

    $processes = @(Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction SilentlyContinue)
    foreach ($process in @($processes)) {
        try {
            $owner = Invoke-CimMethod -InputObject $process -MethodName GetOwner -ErrorAction Stop
            if ($null -eq $owner -or [int]$owner.ReturnValue -ne 0) {
                continue
            }

            $ownerUser = [string]$owner.User
            if ([string]::IsNullOrWhiteSpace([string]$ownerUser)) {
                continue
            }

            $ownerDomain = [string]$owner.Domain
            $qualifiedOwner = if ([string]::IsNullOrWhiteSpace([string]$ownerDomain)) {
                $ownerUser
            }
            else {
                ("{0}\{1}" -f [string]$ownerDomain, [string]$ownerUser)
            }

            if (-not $owners.Contains([string]$qualifiedOwner)) {
                [void]$owners.Add([string]$qualifiedOwner)
            }
        }
        catch {
        }
    }

    return @($owners.ToArray())
}

function Get-ClagnosUserInteractiveDesktopStatus {
    param(
        [string]$UserName
    )

    $winlogonState = Get-ClagnosWinlogonAutologonState
    $activeUser = ''
    try {
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $activeUser = [string]$computerSystem.UserName
    }
    catch {
        $activeUser = ''
    }

    $bootAgeSeconds = 0
    try {
        $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $bootAgeSeconds = [int][Math]::Round(((Get-Date) - [DateTime]$operatingSystem.LastBootUpTime).TotalSeconds, 0)
    }
    catch {
        $bootAgeSeconds = 0
    }

    $explorerOwners = @(Get-ClagnosExplorerProcessOwners)
    $activeUserMatch = Test-ClagnosUserNameMatch -ObservedUserName ([string]$activeUser) -ExpectedUserName $UserName
    $explorerReady = $false
    foreach ($owner in @($explorerOwners)) {
        if (Test-ClagnosUserNameMatch -ObservedUserName ([string]$owner) -ExpectedUserName $UserName) {
            $explorerReady = $true
            break
        }
    }

    $autologonUserMatch = [string]::Equals([string]$winlogonState.DefaultUserName, [string]$UserName, [System.StringComparison]::OrdinalIgnoreCase)
    $ready = ($activeUserMatch -and $explorerReady)
    $reasonCode = 'desktop-unavailable'
    $note = 'The expected interactive desktop session is not ready.'

    if ([bool]$ready) {
        $reasonCode = 'ready'
        $note = 'The expected interactive desktop session is ready.'
    }
    elseif (-not [bool]$winlogonState.AutoAdminLogonEnabled) {
        $reasonCode = 'autologon-disabled'
        $note = ("Autologon is disabled or not configured for '{0}'." -f [string]$UserName)
    }
    elseif (-not [bool]$autologonUserMatch) {
        $reasonCode = 'autologon-different-user'
        if ([string]::IsNullOrWhiteSpace([string]$winlogonState.DefaultUserName)) {
            $note = ("Autologon is enabled but DefaultUserName is empty instead of '{0}'." -f [string]$UserName)
        }
        else {
            $note = ("Autologon is enabled for '{0}' instead of '{1}'." -f [string]$winlogonState.DefaultUserName, [string]$UserName)
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$activeUser) -and -not [bool]$activeUserMatch) {
        $reasonCode = 'other-user-active'
        $note = ("Another interactive user is active: '{0}'." -f [string]$activeUser)
    }
    elseif ([bool]$activeUserMatch -and -not [bool]$explorerReady) {
        $reasonCode = 'explorer-not-ready'
        $note = ("User '{0}' is signed in, but explorer.exe is not ready yet." -f [string]$UserName)
    }
    elseif ([bool]$winlogonState.AutoAdminLogonEnabled -and [bool]$autologonUserMatch) {
        $reasonCode = 'autologon-pending'
        $note = ("Autologon is configured for '{0}', but the desktop session has not appeared yet after boot." -f [string]$UserName)
    }

    return [pscustomobject]@{
        UserName = [string]$UserName
        Ready = [bool]$ready
        ReasonCode = [string]$reasonCode
        Note = [string]$note
        AutoAdminLogon = [string]$winlogonState.AutoAdminLogon
        AutoAdminLogonEnabled = [bool]$winlogonState.AutoAdminLogonEnabled
        DefaultUserName = [string]$winlogonState.DefaultUserName
        DefaultDomainName = [string]$winlogonState.DefaultDomainName
        DefaultPasswordPresent = [bool]$winlogonState.DefaultPasswordPresent
        ActiveUser = [string]$activeUser
        ActiveUserMatch = [bool]$activeUserMatch
        ExplorerOwners = @($explorerOwners)
        ExplorerReady = [bool]$explorerReady
        BootAgeSeconds = [int]$bootAgeSeconds
        WaitApplied = $false
        WaitedSeconds = 0
    }
}

function Write-ClagnosInteractiveDesktopStatusLine {
    param(
        [AllowNull()]
        [psobject]$Status,
        [string]$Label = 'interactive-desktop-state'
    )

    if ($null -eq $Status) {
        Write-Host ("{0} => state=none" -f [string]$Label)
        return
    }

    $activeUser = if ([string]::IsNullOrWhiteSpace([string]$Status.ActiveUser)) { '(none)' } else { [string]$Status.ActiveUser }
    $defaultUserName = if ([string]::IsNullOrWhiteSpace([string]$Status.DefaultUserName)) { '(none)' } else { [string]$Status.DefaultUserName }
    Write-Host (
        "{0} => ready={1}; reason={2}; autologon={3}; default-user={4}; active-user={5}; explorer-ready={6}; waited={7}s; uptime={8}s; note={9}" -f `
        [string]$Label,
        [bool]$Status.Ready,
        [string]$Status.ReasonCode,
        [bool]$Status.AutoAdminLogonEnabled,
        $defaultUserName,
        $activeUser,
        [bool]$Status.ExplorerReady,
        [int]$Status.WaitedSeconds,
        [int]$Status.BootAgeSeconds,
        [string]$Status.Note
    )
}

function Wait-ClagnosUserInteractiveDesktopReady {
    param(
        [string]$UserName,
        [int]$WaitSeconds = 0,
        [int]$PollSeconds = 5
    )

    $status = Get-ClagnosUserInteractiveDesktopStatus -UserName $UserName
    $waitSecondsValue = [Math]::Max(0, [int]$WaitSeconds)
    $pollSecondsValue = [Math]::Max(1, [int]$PollSeconds)
    $canWait = ($waitSecondsValue -gt 0) -and (([string]$status.ReasonCode -eq 'autologon-pending') -or ([string]$status.ReasonCode -eq 'explorer-not-ready'))
    if (-not $canWait) {
        return $status
    }

    Write-Host ("interactive-desktop-wait => user={0}; reason={1}; timeout={2}s" -f [string]$UserName, [string]$status.ReasonCode, [int]$waitSecondsValue)
    $startTime = Get-Date
    $deadline = $startTime.AddSeconds($waitSecondsValue)
    do {
        Start-Sleep -Seconds $pollSecondsValue
        $status = Get-ClagnosUserInteractiveDesktopStatus -UserName $UserName
        if ([bool]$status.Ready) {
            break
        }
    } while ((Get-Date) -lt $deadline)

    $waitedSeconds = [int][Math]::Round(((Get-Date) - $startTime).TotalSeconds, 0)
    $status = $status | Select-Object *
    if ($status.PSObject.Properties.Match('WaitApplied').Count -gt 0) {
        $status.WaitApplied = $true
    }
    else {
        $status | Add-Member -NotePropertyName WaitApplied -NotePropertyValue $true
    }
    if ($status.PSObject.Properties.Match('WaitedSeconds').Count -gt 0) {
        $status.WaitedSeconds = $waitedSeconds
    }
    else {
        $status | Add-Member -NotePropertyName WaitedSeconds -NotePropertyValue $waitedSeconds
    }

    return $status
}

function New-ClagnosInteractiveDesktopBlockMessage {
    param(
        [string]$ActivityDescription,
        [string]$ExpectedUserName,
        [AllowNull()]
        [psobject]$Status
    )

    $activity = if ([string]::IsNullOrWhiteSpace([string]$ActivityDescription)) { 'Microsoft Store install' } else { [string]$ActivityDescription.Trim() }
    $userText = if ([string]::IsNullOrWhiteSpace([string]$ExpectedUserName)) { 'the expected user' } else { [string]$ExpectedUserName.Trim() }
    if ($null -eq $Status) {
        return [pscustomobject]@{
            Summary = ("{0} requires the {1} interactive desktop session, but its readiness could not be determined." -f $activity, $userText)
            WarningMessage = ("{0} blocked: the {1} interactive desktop session could not be verified." -f $activity, $userText)
            ReasonCode = 'status-unavailable'
        }
    }

    $summary = ''
    $warningMessage = ''
    switch ([string]$Status.ReasonCode) {
        'autologon-disabled' {
            $summary = ("{0} requires the {1} interactive desktop session, but autologon is disabled or not configured for that user. Run 102-configure-autologon-settings and restart the VM before retrying the Microsoft Store task." -f $activity, $userText)
            $warningMessage = ("{0} blocked: autologon is disabled or not configured for {1}. Run 102-autologon-manager-user and restart the VM." -f $activity, $userText)
            break
        }
        'autologon-different-user' {
            $configuredUser = if ([string]::IsNullOrWhiteSpace([string]$Status.DefaultUserName)) { '(none)' } else { [string]$Status.DefaultUserName }
            $summary = ("{0} requires the {1} interactive desktop session, but autologon is currently configured for '{2}'. Run 102-configure-autologon-settings and restart the VM before retrying the Microsoft Store task." -f $activity, $userText, $configuredUser)
            $warningMessage = ("{0} blocked: autologon is configured for '{1}' instead of {2}. Run 102-autologon-manager-user and restart the VM." -f $activity, $configuredUser, $userText)
            break
        }
        'other-user-active' {
            $activeUser = if ([string]::IsNullOrWhiteSpace([string]$Status.ActiveUser)) { '(unknown)' } else { [string]$Status.ActiveUser }
            $summary = ("{0} requires the {1} interactive desktop session, but another interactive user is active: '{2}'." -f $activity, $userText, $activeUser)
            $warningMessage = ("{0} blocked: another interactive user is active ({1})." -f $activity, $activeUser)
            break
        }
        'explorer-not-ready' {
            $summary = ("{0} requires the {1} interactive desktop session. Autologon is configured and the user is signed in, but explorer.exe was still not ready within the bounded wait. Retry after the desktop finishes initializing." -f $activity, $userText)
            $warningMessage = ("{0} blocked: {1} is signed in, but explorer.exe is not ready yet. Retry after the desktop finishes initializing." -f $activity, $userText)
            break
        }
        'autologon-pending' {
            $summary = ("{0} requires the {1} interactive desktop session. Autologon is configured, but the desktop session did not appear within the bounded wait after boot. Retry after the autologon desktop is available." -f $activity, $userText)
            $warningMessage = ("{0} blocked: autologon is configured for {1}, but the desktop session is not ready yet. Retry after the desktop appears." -f $activity, $userText)
            break
        }
        default {
            $summary = ("{0} requires the {1} interactive desktop session. {2}" -f $activity, $userText, [string]$Status.Note)
            $warningMessage = ("{0} blocked: {1}" -f $activity, [string]$Status.Note)
            break
        }
    }

    return [pscustomobject]@{
        Summary = [string]$summary
        WarningMessage = [string]$warningMessage
        ReasonCode = [string]$Status.ReasonCode
    }
}

function Test-ClagnosUserInteractiveDesktopReady {
    param(
        [string]$UserName
    )

    $status = Get-ClagnosUserInteractiveDesktopStatus -UserName $UserName
    return [bool]$status.Ready
}

function ConvertTo-ClagnosPowerShellSingleQuotedLiteral {
    param(
        [AllowNull()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return ''
    }

    return ([string]$Value).Replace("'", "''")
}

function ConvertTo-ClagnosPowerShellStringArrayLiteral {
    param(
        [string[]]$Values = @()
    )

    $quotedValues = @(
        @($Values) |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object { ("'" + (ConvertTo-ClagnosPowerShellSingleQuotedLiteral -Value ([string]$_)) + "'") }
    )

    if (@($quotedValues).Count -eq 0) {
        return '@()'
    }

    return ('@(' + ((@($quotedValues) -join ', ')) + ')')
}

function Get-ClagnosCurrentUserStartAppMatches {
    param(
        [string[]]$AppIdPatterns = @()
    )

    $normalizedPatterns = @(
        @($AppIdPatterns) |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
    )
    if (@($normalizedPatterns).Count -eq 0) {
        return @()
    }
    if (-not (Get-Command Get-StartApps -ErrorAction SilentlyContinue)) {
        return @()
    }

    $matches = New-Object 'System.Collections.Generic.List[string]'
    foreach ($entry in @(Get-StartApps -ErrorAction SilentlyContinue)) {
        $appIdText = [string]$entry.AppID
        if ([string]::IsNullOrWhiteSpace([string]$appIdText)) {
            continue
        }

        foreach ($pattern in @($normalizedPatterns)) {
            if ($appIdText -like [string]$pattern) {
                if (-not $matches.Contains([string]$appIdText)) {
                    [void]$matches.Add([string]$appIdText)
                }
                break
            }
        }
    }

    return @($matches.ToArray())
}

function Invoke-ClagnosUserAppxRegistrationRepair {
    param(
        [string]$TaskName,
        [string]$RunAsUser,
        [string]$RunAsPassword,
        [string]$HelperPath,
        [string]$PackageManifestPath,
        [string[]]$AppIdPatterns = @(),
        [int]$WaitTimeoutSeconds = 60,
        [int]$HeartbeatSeconds = 10,
        [string]$RunAsMode = 'password'
    )

    if ([string]::IsNullOrWhiteSpace([string]$TaskName)) {
        throw 'Interactive AppX repair task name is empty.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$RunAsUser)) {
        throw 'Interactive AppX repair user is empty.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$HelperPath) -or -not (Test-Path -LiteralPath $HelperPath)) {
        throw ("Interactive AppX repair helper path is invalid: {0}" -f [string]$HelperPath)
    }
    if ([string]::IsNullOrWhiteSpace([string]$PackageManifestPath) -or -not (Test-Path -LiteralPath $PackageManifestPath)) {
        throw ("Interactive AppX repair manifest path is invalid: {0}" -f [string]$PackageManifestPath)
    }

    $normalizedPatterns = @(
        @($AppIdPatterns) |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
    )
    if (@($normalizedPatterns).Count -eq 0) {
        throw ("Interactive AppX repair app-id patterns are empty for task '{0}'." -f [string]$TaskName)
    }

    $paths = Get-ClagnosInteractivePaths -TaskName $TaskName
    $helperPathSafe = ConvertTo-ClagnosPowerShellSingleQuotedLiteral -Value ([string]$HelperPath)
    $resultPathSafe = ConvertTo-ClagnosPowerShellSingleQuotedLiteral -Value ([string]$paths.ResultPath)
    $taskNameSafe = ConvertTo-ClagnosPowerShellSingleQuotedLiteral -Value ([string]$paths.TaskName)
    $manifestPathSafe = ConvertTo-ClagnosPowerShellSingleQuotedLiteral -Value ([string]$PackageManifestPath)
    $patternArrayLiteral = ConvertTo-ClagnosPowerShellStringArrayLiteral -Values @($normalizedPatterns)

    $workerScript = @(
        '$ErrorActionPreference = ''Stop'''
        '. ''' + $helperPathSafe + ''''
        '$appIdPatterns = ' + $patternArrayLiteral
        '$resultPath = ''' + $resultPathSafe + ''''
        '$taskName = ''' + $taskNameSafe + ''''
        '$manifestPath = ''' + $manifestPathSafe + ''''
        'try {'
        '    $matches = @(Get-ClagnosCurrentUserStartAppMatches -AppIdPatterns $appIdPatterns)'
        '    if (@($matches).Count -lt 1) {'
        '        Add-AppxPackage -DisableDevelopmentMode -Register $manifestPath -ErrorAction Stop *> $null'
        '        $matches = @(Get-ClagnosCurrentUserStartAppMatches -AppIdPatterns $appIdPatterns)'
        '    }'
        '    Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success (@($matches).Count -gt 0) -Summary (''app-id-match-count='' + [int]@($matches).Count) -Details @($matches)'
        '}'
        'catch {'
        '    Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $false -Summary ([string]$_.Exception.Message)'
        '    exit 1'
        '}'
    ) -join "`n"

    return (Invoke-ClagnosInteractiveDesktopAutomation `
        -TaskName $TaskName `
        -RunAsUser $RunAsUser `
        -RunAsPassword $RunAsPassword `
        -WorkerScriptText $workerScript `
        -WaitTimeoutSeconds $WaitTimeoutSeconds `
        -HeartbeatSeconds $HeartbeatSeconds `
        -RunAsMode $RunAsMode)
}

function Remove-ClagnosInteractiveScheduledTask {
    param(
        [string]$TaskName
    )

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
        [string]$WorkerPath,
        [string]$RunAsPassword,
        [string]$RunAsMode = 'password'
    )

    Remove-ClagnosInteractiveScheduledTask -TaskName $TaskName

    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    $root = $service.GetFolder('\')
    $definition = $service.NewTask(0)

    $definition.RegistrationInfo.Description = ("clagnos interactive automation for {0}" -f [string]$TaskName)
    $definition.Settings.Enabled = $true
    $definition.Settings.Hidden = $true
    $definition.Settings.StartWhenAvailable = $true
    $definition.Settings.AllowDemandStart = $true
    $definition.Settings.DisallowStartIfOnBatteries = $false
    $definition.Settings.StopIfGoingOnBatteries = $false
    $definition.Settings.ExecutionTimeLimit = 'PT1H'
    $definition.Settings.MultipleInstances = 0

    $runAsUserText = [string]$RunAsUser
    $isServiceAccount = [string]::Equals($runAsUserText, 'SYSTEM', [System.StringComparison]::OrdinalIgnoreCase) -or [string]::Equals($runAsUserText, 'NT AUTHORITY\SYSTEM', [System.StringComparison]::OrdinalIgnoreCase)
    $useInteractiveToken = [string]::Equals([string]$RunAsMode, 'interactiveToken', [System.StringComparison]::OrdinalIgnoreCase)
    if ($isServiceAccount) {
        $principalName = 'SYSTEM'
        $definition.Principal.UserId = $principalName
        $definition.Principal.LogonType = 5
        $definition.Principal.RunLevel = 1
    }
    elseif ($useInteractiveToken) {
        $principalName = Get-ClagnosLocalPrincipalName -UserName $runAsUserText
        $definition.Principal.UserId = $principalName
        $definition.Principal.LogonType = 3
        $definition.Principal.RunLevel = 1
    }
    else {
        $principalName = Get-ClagnosLocalPrincipalName -UserName $runAsUserText
        $definition.Principal.UserId = $principalName
        $definition.Principal.LogonType = 1
        $definition.Principal.RunLevel = 1
    }

    $action = $definition.Actions.Create(0)
    $action.Path = Get-ClagnosPowerShellExePath
    $action.Arguments = ('-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f [string]$WorkerPath)
    $action.WorkingDirectory = (Split-Path -Path $WorkerPath -Parent)

    $trigger = $definition.Triggers.Create(1)
    $trigger.StartBoundary = ([DateTime]::Now.AddMinutes(10).ToString('s'))

    if (-not $isServiceAccount -and -not $useInteractiveToken -and [string]::IsNullOrWhiteSpace([string]$RunAsPassword)) {
        throw "Interactive scheduled task password is empty."
    }

    if ($isServiceAccount) {
        $null = $root.RegisterTaskDefinition($TaskName, $definition, 6, $principalName, $null, 5, $null)
        return
    }

    if ($useInteractiveToken) {
        $null = $root.RegisterTaskDefinition($TaskName, $definition, 6, $null, $null, 3, $null)
        return
    }

    $null = $root.RegisterTaskDefinition($TaskName, $definition, 6, $principalName, [string]$RunAsPassword, 1, $null)
}

function Start-ClagnosInteractiveScheduledTask {
    param(
        [string]$TaskName
    )

    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    $root = $service.GetFolder('\')
    $task = $root.GetTask($TaskName)
    if ($null -eq $task) {
        throw ("Scheduled task was not found: {0}" -f $TaskName)
    }

    $null = $task.Run($null)
}

function Get-ClagnosInteractiveScheduledTaskSnapshot {
    param(
        [string]$TaskName
    )

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
    param(
        [string]$WorkerPath
    )

    $workerPathText = [string]$WorkerPath
    if ([string]::IsNullOrWhiteSpace([string]$workerPathText)) {
        return @()
    }

    return @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $commandLine = [string]$_.CommandLine
                -not [string]::IsNullOrWhiteSpace([string]$commandLine) -and
                $commandLine.IndexOf($workerPathText, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
            }
    )
}

function Stop-ClagnosInteractiveWorkerProcesses {
    param(
        [string]$WorkerPath
    )

    $stoppedProcessIds = New-Object 'System.Collections.Generic.List[int]'
    foreach ($process in @(Get-ClagnosInteractiveWorkerProcesses -WorkerPath $WorkerPath)) {
        $processId = 0
        try {
            $processId = [int]$process.ProcessId
        }
        catch {
            $processId = 0
        }

        if ($processId -le 0) {
            continue
        }

        try {
            Stop-Process -Id $processId -Force -ErrorAction Stop
            [void]$stoppedProcessIds.Add($processId)
        }
        catch {
        }
    }

    return @($stoppedProcessIds.ToArray())
}

function Get-ClagnosInteractiveScheduledTaskStateLabel {
    param(
        [int]$State
    )

    switch ([int]$State) {
        0 { return 'unknown' }
        1 { return 'disabled' }
        2 { return 'queued' }
        3 { return 'ready' }
        4 { return 'running' }
        default { return ('state-{0}' -f [int]$State) }
    }
}

function Invoke-ClagnosInteractiveDesktopAutomation {
    param(
        [string]$TaskName,
        [string]$RunAsUser,
        [string]$RunAsPassword,
        [string]$WorkerScriptText,
        [int]$WaitTimeoutSeconds = 900,
        [int]$HeartbeatSeconds = 0,
        [string]$RunAsMode = 'password'
    )

    if ([string]::IsNullOrWhiteSpace([string]$WorkerScriptText)) {
        throw "Interactive worker script text is empty."
    }
    $runAsUserText = [string]$RunAsUser
    $isServiceAccount = [string]::Equals($runAsUserText, 'SYSTEM', [System.StringComparison]::OrdinalIgnoreCase) -or [string]::Equals($runAsUserText, 'NT AUTHORITY\SYSTEM', [System.StringComparison]::OrdinalIgnoreCase)
    $useInteractiveToken = [string]::Equals([string]$RunAsMode, 'interactiveToken', [System.StringComparison]::OrdinalIgnoreCase)
    if (-not $isServiceAccount -and -not $useInteractiveToken -and [string]::IsNullOrWhiteSpace([string]$RunAsPassword)) {
        throw "Interactive worker cannot run because the run-as password is empty."
    }

    $paths = Get-ClagnosInteractivePaths -TaskName $TaskName
    Ensure-ClagnosDirectory -Path $paths.RootPath

    $staleProcessIds = @(Stop-ClagnosInteractiveWorkerProcesses -WorkerPath $paths.WorkerPath)
    if (@($staleProcessIds).Count -gt 0) {
        Write-Host ("Stopped stale interactive worker process(es) for '{0}': {1}" -f [string]$paths.TaskName, ((@($staleProcessIds) | ForEach-Object { [string]$_ }) -join ', ')) -ForegroundColor DarkCyan
    }

    if (Test-Path -LiteralPath $paths.ResultPath) {
        Remove-Item -LiteralPath $paths.ResultPath -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $paths.WorkerPath) {
        Remove-Item -LiteralPath $paths.WorkerPath -Force -ErrorAction SilentlyContinue
    }

    [System.IO.File]::WriteAllText($paths.WorkerPath, [string]$WorkerScriptText, (New-Object System.Text.UTF8Encoding($false)))
    try {
        $modeLabel = 'password-logon'
        if ($isServiceAccount) {
            $modeLabel = 'service-account'
        }
        elseif ($useInteractiveToken) {
            $modeLabel = 'interactive-token'
        }

        Write-Host ("Interactive task '{0}' will run for {1} using {2}." -f [string]$paths.TaskName, [string]$RunAsUser, $modeLabel) -ForegroundColor DarkCyan
        Register-ClagnosInteractiveScheduledTask -TaskName $paths.ScheduledTaskName -RunAsUser $RunAsUser -WorkerPath $paths.WorkerPath -RunAsPassword $RunAsPassword -RunAsMode $RunAsMode
        Start-ClagnosInteractiveScheduledTask -TaskName $paths.ScheduledTaskName
        Write-Host ("Running interactive task '{0}'..." -f [string]$paths.TaskName) -ForegroundColor Cyan

        $pollSeconds = 2
        $heartbeatSeconds = 15
        if ($HeartbeatSeconds -gt 0) {
            $heartbeatSeconds = [Math]::Max(5, [int]$HeartbeatSeconds)
        }
        elseif ($WaitTimeoutSeconds -ge 1800) {
            $heartbeatSeconds = 30
        }
        $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Max(5, [int]$WaitTimeoutSeconds))
        $startTime = [DateTime]::UtcNow
        $nextHeartbeatUtc = $startTime.AddSeconds($heartbeatSeconds)
        $completed = $false
        while ([DateTime]::UtcNow -lt $deadline) {
            if (Test-Path -LiteralPath $paths.ResultPath) {
                $fileInfo = Get-Item -LiteralPath $paths.ResultPath -ErrorAction SilentlyContinue
                if ($null -ne $fileInfo -and [int64]$fileInfo.Length -gt 0) {
                    $completed = $true
                    break
                }
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

                $nextHeartbeatUtc = [DateTime]::UtcNow.AddSeconds($heartbeatSeconds)
            }

            Start-Sleep -Seconds $pollSeconds
        }
        if (-not $completed) {
            $snapshot = Get-ClagnosInteractiveScheduledTaskSnapshot -TaskName $paths.ScheduledTaskName
            if ($null -eq $snapshot) {
                throw ("Interactive worker timed out without a result file: {0}" -f $paths.ResultPath)
            }

            throw ("Interactive worker timed out without a result file: state={0}; last-task-result={1}; last-run-time={2}" -f [int]$snapshot.State, [int]$snapshot.LastTaskResult, [string]$snapshot.LastRunTime)
        }

        $result = Read-ClagnosJsonFile -Path $paths.ResultPath
        $summary = if ($result.PSObject.Properties.Match('Summary').Count -gt 0) { [string]$result.Summary } else { 'Interactive desktop worker reported failure.' }
        if ($result.PSObject.Properties.Match('Success').Count -eq 0 -or -not [bool]$result.Success) {
            $detailText = ''
            if ($result.PSObject.Properties.Match('Details').Count -gt 0 -and $null -ne $result.Details) {
                $detailText = ((@($result.Details | ForEach-Object { [string]$_ }) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join ' | ')
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$detailText)) {
                throw ("{0} ({1})" -f $summary, $detailText)
            }
            throw $summary
        }

        Write-Host ("Interactive task '{0}' completed successfully for {1} using {2}." -f [string]$paths.TaskName, [string]$RunAsUser, $modeLabel) -ForegroundColor Green
        return $result
    }
    finally {
        try {
            Remove-ClagnosInteractiveScheduledTask -TaskName $paths.ScheduledTaskName
        }
        catch {
            Write-Warning ("interactive-task-cleanup-warning: {0}" -f $_.Exception.Message)
        }
        $stoppedProcessIds = @(Stop-ClagnosInteractiveWorkerProcesses -WorkerPath $paths.WorkerPath)
        if (@($stoppedProcessIds).Count -gt 0) {
            Write-Host ("Stopped lingering interactive worker process(es) for '{0}': {1}" -f [string]$paths.TaskName, ((@($stoppedProcessIds) | ForEach-Object { [string]$_ }) -join ', ')) -ForegroundColor DarkCyan
        }
        Remove-Item -LiteralPath $paths.WorkerPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $paths.ResultPath -Force -ErrorAction SilentlyContinue
    }
}
