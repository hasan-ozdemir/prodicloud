# Host startup mirror helpers.

# Handles Convert-ClagnosStartupMirrorMatchText.
function Convert-ClagnosStartupMirrorMatchText {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return ''
    }

    $builder = New-Object System.Text.StringBuilder
    foreach ($ch in ([string]$Value).ToLowerInvariant().ToCharArray()) {
        if ([char]::IsLetterOrDigit($ch)) {
            [void]$builder.Append($ch)
        }
    }

    return [string]$builder.ToString()
}

# Handles Get-ClagnosStartupMirrorAppCatalog.
function Get-ClagnosStartupMirrorAppCatalog {
    return @(
        [pscustomobject]@{
            Key = 'docker-desktop'
            DisplayName = 'Docker Desktop'
            MatchNames = @('Docker Desktop')
            MatchCommandFragments = @('Docker Desktop.exe')
        },
        [pscustomobject]@{
            Key = 'ollama'
            DisplayName = 'Ollama'
            MatchNames = @('Ollama', 'Ollama.lnk')
            MatchCommandFragments = @('ollama app.exe', 'ollama.exe')
        },
        [pscustomobject]@{
            Key = 'onedrive'
            DisplayName = 'OneDrive'
            MatchNames = @('OneDrive')
            MatchCommandFragments = @('OneDrive.exe', 'OneDrive.Sync.Service.exe')
        },
        [pscustomobject]@{
            Key = 'teams'
            DisplayName = 'Teams'
            MatchNames = @('Teams')
            MatchCommandFragments = @('ms-teams.exe', 'msteams:system-initiated', 'shell:AppsFolder\\MSTeams_', 'MSTeams_8wekyb3d8bbwe!')
        },
        [pscustomobject]@{
            Key = 'itunes-helper'
            DisplayName = 'iTunesHelper'
            MatchNames = @('iTunesHelper')
            MatchCommandFragments = @('iTunesHelper.exe')
        },
        [pscustomobject]@{
            Key = 'google-drive'
            DisplayName = 'Google Drive'
            MatchNames = @('Google Drive', 'GoogleDriveFS')
            MatchCommandFragments = @('GoogleDriveFS.exe')
        },
        [pscustomobject]@{
            Key = 'windscribe'
            DisplayName = 'Windscribe'
            MatchNames = @('Windscribe')
            MatchCommandFragments = @('Windscribe.exe')
        },
        [pscustomobject]@{
            Key = 'anydesk'
            DisplayName = 'AnyDesk'
            MatchNames = @('AnyDesk')
            MatchCommandFragments = @('AnyDesk.exe')
        },
        [pscustomobject]@{
            Key = 'codex-app'
            DisplayName = 'Codex App'
            MatchNames = @('Codex')
            MatchCommandFragments = @('Codex.exe', 'OpenAI.Codex')
        }
    )
}

# Handles Test-ClagnosStartupMirrorAppMatch.
function Test-ClagnosStartupMirrorAppMatch {
    param(
        [psobject]$Entry,
        [psobject]$Definition
    )

    if ($null -eq $Entry -or $null -eq $Definition) {
        return $false
    }

    $entryNameText = Convert-ClagnosStartupMirrorMatchText -Value ([string]$Entry.Name)
    $entryCommandText = Convert-ClagnosStartupMirrorMatchText -Value ([string]$Entry.Command)

    foreach ($matchName in @($Definition.MatchNames)) {
        $normalized = Convert-ClagnosStartupMirrorMatchText -Value ([string]$matchName)
        if (-not [string]::IsNullOrWhiteSpace([string]$normalized) -and $entryNameText.Contains($normalized)) {
            return $true
        }
    }

    foreach ($fragment in @($Definition.MatchCommandFragments)) {
        $normalized = Convert-ClagnosStartupMirrorMatchText -Value ([string]$fragment)
        if (-not [string]::IsNullOrWhiteSpace([string]$normalized) -and $entryCommandText.Contains($normalized)) {
            return $true
        }
    }

    return $false
}

# Handles Resolve-ClagnosHostStartupMirrorProfileFromEntries.
function Resolve-ClagnosHostStartupMirrorProfileFromEntries {
    param([object[]]$Entries)

    $enabledEntries = @(
        @($Entries) |
            Where-Object {
                if ($null -eq $_) { return $false }
                if ($_.PSObject.Properties.Match('Enabled').Count -eq 0) { return $true }
                return [bool]$_.Enabled
            }
    )

    $profile = @()
    foreach ($definition in @(Get-ClagnosStartupMirrorAppCatalog)) {
        $match = @($enabledEntries | Where-Object {
            Test-ClagnosStartupMirrorAppMatch -Entry $_ -Definition $definition
        } | Select-Object -First 1)

        if (@($match).Count -eq 0) {
            continue
        }

        $entry = $match[0]
        $profile += [pscustomobject]@{
            Key = [string]$definition.Key
            DisplayName = [string]$definition.DisplayName
            LocalEntryName = [string]$entry.Name
            EntryType = if ($entry.PSObject.Properties.Match('EntryType').Count -gt 0) { [string]$entry.EntryType } else { '' }
            Scope = if ($entry.PSObject.Properties.Match('Scope').Count -gt 0) { [string]$entry.Scope } else { '' }
            Command = if ($entry.PSObject.Properties.Match('Command').Count -gt 0) { [string]$entry.Command } else { '' }
        }
    }

    return @($profile)
}

# Handles Get-ClagnosStartupApprovedStateCode.
function Get-ClagnosStartupApprovedStateCode {
    param(
        [object]$ApprovalItem,
        [string]$ValueName
    )

    if ($null -eq $ApprovalItem -or [string]::IsNullOrWhiteSpace([string]$ValueName)) {
        return -1
    }

    $property = @($ApprovalItem.PSObject.Properties | Where-Object { [string]$_.Name -eq $ValueName } | Select-Object -First 1)
    if (@($property).Count -eq 0 -or $null -eq $property[0].Value) {
        return -1
    }

    $bytes = @($property[0].Value)
    if (@($bytes).Count -eq 0) {
        return -1
    }

    return [int]$bytes[0]
}

# Handles Resolve-ClagnosStartupShortcutCommand.
function Resolve-ClagnosStartupShortcutCommand {
    param([string]$ShortcutPath)

    if ([string]::IsNullOrWhiteSpace([string]$ShortcutPath) -or -not (Test-Path -LiteralPath $ShortcutPath)) {
        return ''
    }

    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($ShortcutPath)
        $targetPath = [string]$shortcut.TargetPath
        $arguments = [string]$shortcut.Arguments
        if ([string]::IsNullOrWhiteSpace([string]$targetPath)) {
            return [string]$ShortcutPath
        }

        if ([string]::IsNullOrWhiteSpace([string]$arguments)) {
            return [string]$targetPath
        }

        return ("{0} {1}" -f $targetPath, $arguments).Trim()
    }
    catch {
        return [string]$ShortcutPath
    }
}

# Handles Get-ClagnosHostStartupEntries.
function Get-ClagnosHostStartupEntries {
    $entries = @()

    $runDefinitions = @(
        @{ Scope = 'CurrentUser'; EntryType = 'Run'; RunPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; ApprovalPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' },
        @{ Scope = 'CurrentUser'; EntryType = 'Run32'; RunPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run32'; ApprovalPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32' },
        @{ Scope = 'LocalMachine'; EntryType = 'Run'; RunPath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'; ApprovalPath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' },
        @{ Scope = 'LocalMachine'; EntryType = 'Run32'; RunPath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run32'; ApprovalPath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32' }
    )

    foreach ($definition in @($runDefinitions)) {
        $runPath = [string]$definition.RunPath
        if (-not (Test-Path -LiteralPath $runPath)) {
            continue
        }

        $runItem = Get-ItemProperty -Path $runPath -ErrorAction SilentlyContinue
        $approvalItem = $null
        if (Test-Path -LiteralPath ([string]$definition.ApprovalPath)) {
            $approvalItem = Get-ItemProperty -Path ([string]$definition.ApprovalPath) -ErrorAction SilentlyContinue
        }

        foreach ($property in @($runItem.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS(ParentPath|Path|ChildName|Drive|Provider)$' })) {
            $stateCode = Get-ClagnosStartupApprovedStateCode -ApprovalItem $approvalItem -ValueName ([string]$property.Name)
            $entries += [pscustomobject]@{
                Name = [string]$property.Name
                Command = [string]$property.Value
                EntryType = [string]$definition.EntryType
                Scope = [string]$definition.Scope
                Enabled = ($stateCode -lt 0 -or $stateCode -eq 2)
                StateCode = [int]$stateCode
            }
        }
    }

    $startupFolders = @(
        @{ Scope = 'CurrentUser'; FolderPath = (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'); ApprovalPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder' },
        @{ Scope = 'LocalMachine'; FolderPath = (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp'); ApprovalPath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder' }
    )

    foreach ($definition in @($startupFolders)) {
        $folderPath = [string]$definition.FolderPath
        if ([string]::IsNullOrWhiteSpace([string]$folderPath) -or -not (Test-Path -LiteralPath $folderPath)) {
            continue
        }

        $approvalItem = $null
        if (Test-Path -LiteralPath ([string]$definition.ApprovalPath)) {
            $approvalItem = Get-ItemProperty -Path ([string]$definition.ApprovalPath) -ErrorAction SilentlyContinue
        }

        foreach ($file in @(Get-ChildItem -LiteralPath $folderPath -File -ErrorAction SilentlyContinue | Where-Object { -not [string]::Equals([string]$_.Name, 'desktop.ini', [System.StringComparison]::OrdinalIgnoreCase) })) {
            $stateCode = Get-ClagnosStartupApprovedStateCode -ApprovalItem $approvalItem -ValueName ([string]$file.Name)
            $entries += [pscustomobject]@{
                Name = [string]$file.Name
                Command = Resolve-ClagnosStartupShortcutCommand -ShortcutPath ([string]$file.FullName)
                EntryType = 'StartupFolder'
                Scope = [string]$definition.Scope
                Enabled = ($stateCode -lt 0 -or $stateCode -eq 2)
                StateCode = [int]$stateCode
            }
        }
    }

    return @($entries)
}

# Handles Get-ClagnosHostAccessibilityConfigurationValue.
function Get-ClagnosHostAccessibilityConfigurationValue {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace([string]$Path) -or -not (Test-Path -LiteralPath $Path)) {
        return ''
    }

    $item = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue
    if ($null -eq $item -or $item.PSObject.Properties.Match('Configuration').Count -eq 0) {
        return ''
    }

    return [string]$item.Configuration
}

# Handles Get-ClagnosHostAccessibilityAssistiveTechnologyEntries.
function Get-ClagnosHostAccessibilityAssistiveTechnologyEntries {
    $entries = @()
    $atRoot = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Accessibility\ATs'
    if (-not (Test-Path -LiteralPath $atRoot)) {
        return @()
    }

    foreach ($key in @(Get-ChildItem -LiteralPath $atRoot -ErrorAction SilentlyContinue | Sort-Object PSChildName)) {
        if ($null -eq $key) {
            continue
        }

        $item = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
        if ($null -eq $item) {
            continue
        }

        $entries += [pscustomobject]@{
            Key = [string]$key.PSChildName
            ApplicationName = if ($item.PSObject.Properties.Match('ApplicationName').Count -gt 0) { [string]$item.ApplicationName } else { '' }
            Description = if ($item.PSObject.Properties.Match('Description').Count -gt 0) { [string]$item.Description } else { '' }
            SimpleProfile = if ($item.PSObject.Properties.Match('SimpleProfile').Count -gt 0) { [string]$item.SimpleProfile } else { '' }
            StartExe = if ($item.PSObject.Properties.Match('StartExe').Count -gt 0) { [string]$item.StartExe } else { '' }
            TerminateOnDesktopSwitch = if ($item.PSObject.Properties.Match('TerminateOnDesktopSwitch').Count -gt 0) { [string]$item.TerminateOnDesktopSwitch } else { '' }
            Profile = if ($item.PSObject.Properties.Match('Profile').Count -gt 0) { [string]$item.Profile } else { '' }
        }
    }

    return @($entries)
}

# Handles Get-ClagnosHostAutostartScheduledTasks.
function Get-ClagnosHostAutostartScheduledTasks {
    $results = @()

    if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        return @()
    }

    try {
        $scheduledTasks = @(Get-ScheduledTask -ErrorAction Stop)
    }
    catch {
        return @()
    }

    foreach ($task in @($scheduledTasks)) {
        if ($null -eq $task) {
            continue
        }

        $triggerSummaries = @()
        foreach ($trigger in @($task.Triggers)) {
            if ($null -eq $trigger) {
                continue
            }

            $triggerType = ''
            if ($trigger.PSObject.Properties.Match('TriggerType').Count -gt 0) {
                $triggerType = [string]$trigger.TriggerType
            }
            if ([string]::IsNullOrWhiteSpace([string]$triggerType)) {
                $triggerType = [string]$trigger.GetType().Name
            }
            if ($triggerType -notmatch 'Logon|Boot') {
                continue
            }

            $triggerSummaries += [pscustomobject]@{
                TriggerType = [string]$triggerType
                UserId = if ($trigger.PSObject.Properties.Match('UserId').Count -gt 0) { [string]$trigger.UserId } else { '' }
                Enabled = if ($trigger.PSObject.Properties.Match('Enabled').Count -gt 0) { [string]$trigger.Enabled } else { '' }
            }
        }

        if (@($triggerSummaries).Count -eq 0) {
            continue
        }

        $actionSummaries = @()
        foreach ($action in @($task.Actions)) {
            if ($null -eq $action) {
                continue
            }

            $actionSummaries += [pscustomobject]@{
                Execute = if ($action.PSObject.Properties.Match('Execute').Count -gt 0) { [string]$action.Execute } else { '' }
                Arguments = if ($action.PSObject.Properties.Match('Arguments').Count -gt 0) { [string]$action.Arguments } else { '' }
                WorkingDirectory = if ($action.PSObject.Properties.Match('WorkingDirectory').Count -gt 0) { [string]$action.WorkingDirectory } else { '' }
            }
        }

        $results += [pscustomobject]@{
            TaskName = if ($task.PSObject.Properties.Match('TaskName').Count -gt 0) { [string]$task.TaskName } else { '' }
            TaskPath = if ($task.PSObject.Properties.Match('TaskPath').Count -gt 0) { [string]$task.TaskPath } else { '' }
            State = if ($task.PSObject.Properties.Match('State').Count -gt 0) { [string]$task.State } else { '' }
            Enabled = if ($task.PSObject.Properties.Match('State').Count -gt 0) { -not [string]::Equals([string]$task.State, 'Disabled', [System.StringComparison]::OrdinalIgnoreCase) } else { $true }
            UserId = if ($task.PSObject.Properties.Match('Principal').Count -gt 0 -and $null -ne $task.Principal -and $task.Principal.PSObject.Properties.Match('UserId').Count -gt 0) { [string]$task.Principal.UserId } else { '' }
            RunLevel = if ($task.PSObject.Properties.Match('Principal').Count -gt 0 -and $null -ne $task.Principal -and $task.Principal.PSObject.Properties.Match('RunLevel').Count -gt 0) { [string]$task.Principal.RunLevel } else { '' }
            Triggers = @($triggerSummaries)
            Actions = @($actionSummaries)
        }
    }

    return @($results)
}

# Handles Get-ClagnosHostAutostartDiscovery.
function Get-ClagnosHostAutostartDiscovery {
    return [pscustomobject]@{
        CapturedAtUtc = [DateTime]::UtcNow.ToString('o')
        StartupEntries = @(Get-ClagnosHostStartupEntries)
        ScheduledTasks = @(Get-ClagnosHostAutostartScheduledTasks)
        Accessibility = [pscustomobject]@{
            LocalMachineConfiguration = (Get-ClagnosHostAccessibilityConfigurationValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Accessibility')
            CurrentUserConfiguration = (Get-ClagnosHostAccessibilityConfigurationValue -Path 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Accessibility')
            AssistiveTechnologies = @(Get-ClagnosHostAccessibilityAssistiveTechnologyEntries)
        }
    }
}

# Handles Get-ClagnosHostStartupMirrorProfile.
function Get-ClagnosHostStartupMirrorProfile {
    try {
        $entries = @(Get-ClagnosHostStartupEntries)
        return @(Resolve-ClagnosHostStartupMirrorProfileFromEntries -Entries $entries)
    }
    catch {
        return @()
    }
}

# Handles Get-ClagnosHostStartupMirrorProfileJsonBase64.
function Get-ClagnosHostStartupMirrorProfileJsonBase64 {
    $profile = @(Get-ClagnosHostStartupMirrorProfile)
    $json = [string](ConvertTo-Json -InputObject @($profile) -Depth 6 -Compress)
    if ([string]::IsNullOrWhiteSpace([string]$json)) {
        $json = '[]'
    }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    return [Convert]::ToBase64String($bytes)
}

function Get-ClagnosApprovedStartupProfileCatalog {
    return @(
        [pscustomobject][ordered]@{
            Key = 'docker-desktop'
            Name = 'Docker Desktop'
            OwnedNames = @('Docker Desktop')
            Scope = 'CurrentUser'
            EntryType = 'Run'
            TargetUsers = @('manager', 'assistant')
            EnableLocalMachineCompat = $false
            Launch = [pscustomobject][ordered]@{
                Kind = 'executable'
                CommandName = 'Docker Desktop.exe'
                FallbackCandidates = @('C:\Program Files\Docker\Docker\Docker Desktop.exe')
                Arguments = '--minimized'
            }
        }
        [pscustomobject][ordered]@{
            Key = 'microsoft-lists'
            Name = 'Microsoft.Lists'
            OwnedNames = @('Microsoft.Lists')
            Scope = 'CurrentUser'
            EntryType = 'Run'
            TargetUsers = @('manager', 'assistant')
            EnableLocalMachineCompat = $false
            Launch = [pscustomobject][ordered]@{
                Kind = 'executable'
                SearchRootPaths = @('C:\Program Files\Microsoft OneDrive')
                SearchExecutableName = 'OneDrive.Sync.Service.exe'
                Arguments = ''
            }
        }
        [pscustomobject][ordered]@{
            Key = 'onedrive'
            Name = 'OneDrive'
            OwnedNames = @('OneDrive')
            Scope = 'CurrentUser'
            EntryType = 'Run'
            TargetUsers = @('manager', 'assistant')
            EnableLocalMachineCompat = $false
            Launch = [pscustomobject][ordered]@{
                Kind = 'executable'
                CommandName = 'OneDrive.exe'
                FallbackCandidates = @(
                    'C:\Program Files\Microsoft OneDrive\OneDrive.exe',
                    '%LOCALAPPDATA%\Microsoft\OneDrive\OneDrive.exe'
                )
                Arguments = '/background'
            }
        }
        [pscustomobject][ordered]@{
            Key = 'teams'
            Name = 'Teams'
            OwnedNames = @('Teams')
            Scope = 'CurrentUser'
            EntryType = 'Run'
            TargetUsers = @('manager', 'assistant')
            EnableLocalMachineCompat = $false
            Launch = [pscustomobject][ordered]@{
                Kind = 'store-app'
                AppNameFragment = 'teams'
                PackageNameHints = @('MSTeams', 'MicrosoftTeams', 'teams')
                FallbackAppId = 'MSTeams_8wekyb3d8bbwe!MSTeams'
                ExecutableCommandName = 'ms-teams.exe'
                ExecutableFallbackCandidates = @(
                    'C:\Program Files\WindowsApps\MSTeams_8wekyb3d8bbwe\ms-teams.exe',
                    '%LOCALAPPDATA%\Microsoft\WindowsApps\MSTeams_8wekyb3d8bbwe\ms-teams.exe'
                )
                ExecutableArguments = 'msteams:system-initiated'
                UnresolvedWrapperCommandName = 'cmd.exe'
                UnresolvedWrapperFallbackCandidates = @('C:\Windows\System32\cmd.exe')
                UnresolvedWrapperArguments = '/c start "" ms-teams.exe msteams:system-initiated'
            }
        }
        [pscustomobject][ordered]@{
            Key = 'ollama'
            Name = 'Ollama'
            OwnedNames = @('Ollama')
            Scope = 'CurrentUser'
            EntryType = 'StartupFolder'
            TargetUsers = @('manager', 'assistant')
            EnableLocalMachineCompat = $false
            Launch = [pscustomobject][ordered]@{
                Kind = 'command-wrapper'
                WrapperCommandName = 'cmd.exe'
                WrapperFallbackCandidates = @('C:\Windows\System32\cmd.exe')
                WrapperArguments = '/c if exist "%LOCALAPPDATA%\Programs\Ollama\ollama app.exe" start "" "%LOCALAPPDATA%\Programs\Ollama\ollama app.exe"'
                IconFallbackCandidates = @('%LOCALAPPDATA%\Programs\Ollama\ollama app.exe')
            }
        }
        [pscustomobject][ordered]@{
            Key = 'send-to-onenote'
            Name = 'Send to OneNote'
            OwnedNames = @('Send to OneNote')
            Scope = 'CurrentUser'
            EntryType = 'StartupFolder'
            TargetUsers = @('manager', 'assistant')
            EnableLocalMachineCompat = $false
            Launch = [pscustomobject][ordered]@{
                Kind = 'executable'
                CommandName = 'ONENOTEM.EXE'
                FallbackCandidates = @(
                    'C:\Program Files\Microsoft Office\root\Office16\ONENOTEM.EXE',
                    'C:\Program Files (x86)\Microsoft Office\root\Office16\ONENOTEM.EXE'
                )
                Arguments = '/tsr'
            }
        }
        [pscustomobject][ordered]@{
            Key = 'itunes-helper'
            Name = 'iTunesHelper'
            OwnedNames = @('iTunesHelper')
            Scope = 'LocalMachine'
            EntryType = 'Run'
            TargetUsers = @()
            EnableLocalMachineCompat = $false
            Launch = [pscustomobject][ordered]@{
                Kind = 'executable'
                CommandName = 'iTunesHelper.exe'
                FallbackCandidates = @(
                    'C:\Program Files\iTunes\iTunesHelper.exe',
                    'C:\Program Files (x86)\iTunes\iTunesHelper.exe'
                )
                Arguments = ''
            }
        }
        [pscustomobject][ordered]@{
            Key = 'jaws'
            Name = 'JAWS'
            OwnedNames = @('JAWS')
            Scope = 'LocalMachine'
            EntryType = 'Run'
            TargetUsers = @()
            EnableLocalMachineCompat = $false
            Launch = [pscustomobject][ordered]@{
                Kind = 'executable'
                CommandName = 'jfw.exe'
                FallbackCandidates = @(
                    'C:\Program Files\Freedom Scientific\JAWS\2025\jfw.exe',
                    'C:\Program Files (x86)\Freedom Scientific\JAWS\2025\jfw.exe'
                )
                Arguments = '/run'
            }
        }
        [pscustomobject][ordered]@{
            Key = 'security-health'
            Name = 'SecurityHealth'
            OwnedNames = @('SecurityHealth')
            Scope = 'LocalMachine'
            EntryType = 'Run'
            TargetUsers = @()
            EnableLocalMachineCompat = $false
            Launch = [pscustomobject][ordered]@{
                Kind = 'executable'
                FallbackCandidates = @('C:\WINDOWS\system32\SecurityHealthSystray.exe')
                Arguments = ''
            }
        }
        [pscustomobject][ordered]@{
            Key = 'anydesk'
            Name = 'AnyDesk'
            OwnedNames = @('AnyDesk')
            Scope = 'CurrentUser'
            EntryType = 'Run'
            TargetUsers = @('manager', 'assistant')
            EnableLocalMachineCompat = $false
            Launch = [pscustomobject][ordered]@{
                Kind = 'executable'
                CommandName = 'AnyDesk.exe'
                FallbackCandidates = @(
                    'C:\Program Files\AnyDesk\AnyDesk.exe',
                    'C:\Program Files (x86)\AnyDesk\AnyDesk.exe'
                )
                Arguments = ''
            }
        }
        [pscustomobject][ordered]@{
            Key = 'whatsapp'
            Name = 'WhatsApp'
            OwnedNames = @('WhatsApp')
            Scope = 'CurrentUser'
            EntryType = 'Run'
            TargetUsers = @('manager', 'assistant')
            EnableLocalMachineCompat = $false
            Launch = [pscustomobject][ordered]@{
                Kind = 'store-app'
                AppNameFragment = 'whatsapp'
                PackageNameHints = @('whatsapp', '5319275A.WhatsAppDesktop', '9NKSQGP7F2NH')
                FallbackAppId = '5319275A.WhatsAppDesktop_cv1g1gvanyjgm!App'
                ExecutablePackageNameHints = @('whatsapp', '5319275A.WhatsAppDesktop')
                ExecutablePackageExecutableName = 'WhatsApp.Root.exe'
                ExecutableArguments = ''
            }
        }
        [pscustomobject][ordered]@{
            Key = 'icloud'
            Name = 'iCloud'
            OwnedNames = @('iCloud')
            Scope = 'CurrentUser'
            EntryType = 'Run'
            TargetUsers = @('manager', 'assistant')
            EnableLocalMachineCompat = $false
            Launch = [pscustomobject][ordered]@{
                Kind = 'store-app'
                AppNameFragment = 'icloud'
                PackageNameHints = @('AppleInc.iCloud', '9PKTQ5699M62', 'icloud')
                FallbackAppId = 'AppleInc.iCloud_nzyj5cx40ttqa!iCloud'
                ExecutableFallbackCandidates = @(
                    'C:\Program Files\iCloud\iCloudHome.exe',
                    'C:\Program Files (x86)\iCloud\iCloudHome.exe'
                )
                ExecutablePackageNameHints = @('AppleInc.iCloud', '9PKTQ5699M62', 'icloud')
                ExecutablePackageExecutableName = 'iCloudHome.exe'
                ExecutableArguments = ''
            }
        }
        [pscustomobject][ordered]@{
            Key = 'google-drive'
            Name = 'Google Drive'
            OwnedNames = @('Google Drive')
            Scope = 'CurrentUser'
            EntryType = 'Run'
            TargetUsers = @('manager', 'assistant')
            EnableLocalMachineCompat = $false
            Launch = [pscustomobject][ordered]@{
                Kind = 'executable'
                CommandName = 'GoogleDriveFS.exe'
                FallbackCandidates = @('C:\Program Files\Google\Drive File Stream\GoogleDriveFS.exe')
                SearchRootPaths = @('C:\Program Files\Google\Drive File Stream')
                SearchExecutableName = 'GoogleDriveFS.exe'
                Arguments = ''
            }
        }
        [pscustomobject][ordered]@{
            Key = 'm365-copilot'
            Name = 'Microsoft 365 Copilot'
            OwnedNames = @('Microsoft 365 Copilot')
            Scope = 'CurrentUser'
            EntryType = 'Run'
            TargetUsers = @('manager', 'assistant')
            EnableLocalMachineCompat = $false
            Launch = [pscustomobject][ordered]@{
                Kind = 'store-app'
                AppNameFragment = 'copilot'
                PackageNameHints = @('MicrosoftOfficeHub', 'Microsoft.MicrosoftOfficeHub', 'copilot')
                FallbackAppId = 'Microsoft.MicrosoftOfficeHub_8wekyb3d8bbwe!Microsoft.MicrosoftOfficeHub'
            }
        }
    )
}

function Get-ClagnosApprovedStartupProfileEntries {
    return @(
        Get-ClagnosApprovedStartupProfileCatalog |
            ForEach-Object {
                ConvertFrom-JsonCompat -InputObject (ConvertTo-JsonCompat -InputObject $_ -Depth 12)
            }
    )
}

function Get-ClagnosApprovedStartupProfileDocument {
    return [ordered]@{
        schemaVersion = 1
        mergeMode = 'additive'
        entries = @(Get-ClagnosApprovedStartupProfileEntries)
    }
}

function Get-ClagnosApprovedStartupProfileJsonBase64 {
    $entries = @(Get-ClagnosApprovedStartupProfileEntries)
    $json = [string](ConvertTo-JsonCompat -InputObject @($entries) -Depth 12)
    if ([string]::IsNullOrWhiteSpace([string]$json)) {
        $json = '[]'
    }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    return [Convert]::ToBase64String($bytes)
}

function Get-ClagnosTaskStartupProfileExtension {
    param([psobject]$TaskBlock)

    if ($null -eq $TaskBlock -or $TaskBlock.PSObject.Properties.Match('Extensions').Count -lt 1 -or $null -eq $TaskBlock.Extensions) {
        return $null
    }

    $extensions = $TaskBlock.Extensions
    if ($extensions -is [System.Collections.IDictionary]) {
        if ($extensions.Contains('startupProfile')) {
            return $extensions['startupProfile']
        }
        return $null
    }

    if ($extensions.PSObject.Properties.Match('startupProfile').Count -gt 0) {
        return $extensions.startupProfile
    }

    return $null
}

function Test-ClagnosTaskStartupProfileEnabled {
    param([psobject]$TaskBlock)

    return ($null -ne (Get-ClagnosTaskStartupProfileExtension -TaskBlock $TaskBlock))
}

function Get-ClagnosTaskStartupProfileSourcePath {
    param([psobject]$TaskBlock)

    $extension = Get-ClagnosTaskStartupProfileExtension -TaskBlock $TaskBlock
    if ($null -eq $extension) {
        return ''
    }

    if ($extension -is [System.Collections.IDictionary]) {
        if ($extension.Contains('sourcePath')) {
            return [string]$extension['sourcePath']
        }
        return ''
    }

    if ($extension.PSObject.Properties.Match('sourcePath').Count -gt 0) {
        return [string]$extension.sourcePath
    }

    return ''
}

function Get-ClagnosTaskAppStateZipJsonEntryObject {
    param(
        [string]$ZipPath,
        [string]$EntryName
    )

    Initialize-ClagnosAppStateZipSupport

    if ([string]::IsNullOrWhiteSpace([string]$ZipPath) -or
        [string]::IsNullOrWhiteSpace([string]$EntryName) -or
        -not (Test-Path -LiteralPath $ZipPath)) {
        return $null
    }

    $archive = $null
    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        $entry = Get-ClagnosZipArchiveEntryByName -Archive $archive -EntryName $EntryName
        if ($null -eq $entry) {
            return $null
        }

        $reader = New-Object System.IO.StreamReader($entry.Open())
        try {
            $content = [string]$reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }

        if ([string]::IsNullOrWhiteSpace([string]$content)) {
            return $null
        }

        return (ConvertFrom-JsonCompat -InputObject $content)
    }
    finally {
        if ($null -ne $archive) {
            $archive.Dispose()
        }
    }
}

function New-ClagnosTaskStartupProfilePluginManifest {
    param(
        [string]$TaskName,
        [string]$SourcePath
    )

    return [ordered]@{
        version = 1
        taskName = [string]$TaskName
        machineDirectories = @()
        machineFiles = @()
        profileDirectories = @()
        profileFiles = @()
        registryImports = @()
        extensions = [ordered]@{
            startupProfile = [ordered]@{
                schemaVersion = 1
                sourcePath = [string]$SourcePath
            }
        }
    }
}

function Write-ClagnosTaskStartupProfilePluginZip {
    param([psobject]$TaskBlock)

    if ($null -eq $TaskBlock) {
        return $null
    }

    $taskName = if ($TaskBlock.PSObject.Properties.Match('Name').Count -gt 0) { [string]$TaskBlock.Name } else { '' }
    $sourcePath = Get-ClagnosTaskStartupProfileSourcePath -TaskBlock $TaskBlock
    if ([string]::IsNullOrWhiteSpace([string]$taskName) -or [string]::IsNullOrWhiteSpace([string]$sourcePath)) {
        return $null
    }

    $pluginDirectory = Get-ClagnosTaskAppStatePluginDirectoryPath -TaskBlock $TaskBlock
    $zipPath = Get-ClagnosTaskAppStateZipPath -TaskBlock $TaskBlock
    if ([string]::IsNullOrWhiteSpace([string]$pluginDirectory) -or [string]::IsNullOrWhiteSpace([string]$zipPath)) {
        return $null
    }

    Ensure-ClagnosAppStatePluginDirectory -Path $pluginDirectory
    $scratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('clagnos-startup-profile-plugin-{0}' -f ([guid]::NewGuid().ToString('N')))
    Ensure-ClagnosAppStatePluginDirectory -Path $scratchRoot
    try {
        $manifest = New-ClagnosTaskStartupProfilePluginManifest -TaskName $taskName -SourcePath $sourcePath
        $profileDocument = Get-ClagnosApprovedStartupProfileDocument
        $sourceRelativePath = ([string]$sourcePath).Replace('/', '\')
        $sourceFilePath = Join-Path $scratchRoot $sourceRelativePath
        $sourceParentPath = Split-Path -Path $sourceFilePath -Parent
        Ensure-ClagnosAppStatePluginDirectory -Path $sourceParentPath
        Set-Content -LiteralPath $sourceFilePath -Value (ConvertTo-JsonCompat -InputObject $profileDocument -Depth 12) -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $scratchRoot 'app-state.manifest.json') -Value (ConvertTo-JsonCompat -InputObject $manifest -Depth 12) -Encoding UTF8
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
        $previousProgressPreference = $global:ProgressPreference
        try {
            $global:ProgressPreference = 'SilentlyContinue'
            Compress-Archive -LiteralPath @(Get-ChildItem -LiteralPath $scratchRoot -Force | Select-Object -ExpandProperty FullName) -DestinationPath $zipPath -Force
        }
        finally {
            $global:ProgressPreference = $previousProgressPreference
        }
    }
    finally {
        Remove-Item -LiteralPath $scratchRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    return [pscustomobject]@{
        TaskName = [string]$taskName
        ZipPath = [string]$zipPath
        SourcePath = [string]$sourcePath
    }
}

function Ensure-ClagnosTaskStartupProfilePlugin {
    param([psobject]$TaskBlock)

    if (-not (Test-ClagnosTaskStartupProfileEnabled -TaskBlock $TaskBlock)) {
        return $null
    }

    $sourcePath = Get-ClagnosTaskStartupProfileSourcePath -TaskBlock $TaskBlock
    if ([string]::IsNullOrWhiteSpace([string]$sourcePath)) {
        return $null
    }

    $pluginInfo = Get-ClagnosTaskAppStatePluginInfo -TaskBlock $TaskBlock
    $requiresRefresh = $true
    if ($pluginInfo.Status -eq 'ready' -and $null -ne $pluginInfo.Manifest) {
        $manifest = $pluginInfo.Manifest
        $extension = $null
        if ($manifest.PSObject.Properties.Match('extensions').Count -gt 0 -and $null -ne $manifest.extensions) {
            if ($manifest.extensions -is [System.Collections.IDictionary]) {
                if ($manifest.extensions.Contains('startupProfile')) {
                    $extension = $manifest.extensions['startupProfile']
                }
            }
            elseif ($manifest.extensions.PSObject.Properties.Match('startupProfile').Count -gt 0) {
                $extension = $manifest.extensions.startupProfile
            }
        }

        if ($null -ne $extension) {
            $manifestSourcePath = ''
            if ($extension -is [System.Collections.IDictionary]) {
                if ($extension.Contains('sourcePath')) {
                    $manifestSourcePath = [string]$extension['sourcePath']
                }
            }
            elseif ($extension.PSObject.Properties.Match('sourcePath').Count -gt 0) {
                $manifestSourcePath = [string]$extension.sourcePath
            }

            $profileDocument = Get-ClagnosTaskAppStateZipJsonEntryObject -ZipPath ([string]$pluginInfo.ZipPath) -EntryName $manifestSourcePath
            if (-not [string]::IsNullOrWhiteSpace([string]$manifestSourcePath) -and
                [string]::Equals([string]$manifestSourcePath, [string]$sourcePath, [System.StringComparison]::OrdinalIgnoreCase) -and
                $null -ne $profileDocument -and
                $profileDocument.PSObject.Properties.Match('entries').Count -gt 0) {
                $requiresRefresh = $false
            }
        }
    }

    if ($requiresRefresh) {
        [void](Write-ClagnosTaskStartupProfilePluginZip -TaskBlock $TaskBlock)
    }

    return (Get-ClagnosTaskAppStatePluginInfo -TaskBlock $TaskBlock)
}

function Get-ClagnosTaskStartupProfileEntries {
    param([psobject]$TaskBlock)

    $pluginInfo = Ensure-ClagnosTaskStartupProfilePlugin -TaskBlock $TaskBlock
    if ($null -eq $pluginInfo -or $pluginInfo.Status -ne 'ready') {
        return @(Get-ClagnosApprovedStartupProfileEntries)
    }

    $sourcePath = Get-ClagnosTaskStartupProfileSourcePath -TaskBlock $TaskBlock
    $profileDocument = Get-ClagnosTaskAppStateZipJsonEntryObject -ZipPath ([string]$pluginInfo.ZipPath) -EntryName $sourcePath
    if ($null -eq $profileDocument -or $profileDocument.PSObject.Properties.Match('entries').Count -lt 1) {
        return @(Get-ClagnosApprovedStartupProfileEntries)
    }

    return @($profileDocument.entries)
}

function Get-ClagnosTaskStartupProfileJsonBase64 {
    param([psobject]$TaskBlock)

    $entries = @(Get-ClagnosTaskStartupProfileEntries -TaskBlock $TaskBlock)
    $json = [string](ConvertTo-JsonCompat -InputObject @($entries) -Depth 12)
    if ([string]::IsNullOrWhiteSpace([string]$json)) {
        $json = '[]'
    }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    return [Convert]::ToBase64String($bytes)
}

# Handles Get-ClagnosHostAutostartDiscoveryJsonBase64.
function Get-ClagnosHostAutostartDiscoveryJsonBase64 {
    $discovery = Get-ClagnosHostAutostartDiscovery
    $json = [string](ConvertTo-Json -InputObject $discovery -Depth 8 -Compress)
    if ([string]::IsNullOrWhiteSpace([string]$json)) {
        $json = '{}'
    }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    return [Convert]::ToBase64String($bytes)
}
