$ErrorActionPreference = 'Stop'

function Ensure-ProdicloudAppStateDirectory {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace([string]$Path)) {
        return
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Get-ProdicloudAppStateProfileLeafName {
    param([string]$UserName)

    $text = if ($null -eq $UserName) { '' } else { [string]$UserName.Trim() }
    if ([string]::IsNullOrWhiteSpace([string]$text)) { return '' }
    $text = $text.Replace('/', '\')
    if ($text.Contains('\')) { $text = [string](@($text -split '\\')[-1]) }
    return [string]$text.Trim()
}

function Get-ProdicloudAppStateMachinePlaceholderValues {
    param([hashtable]$Overrides = @{})

    $systemDrive = [string]$env:SystemDrive
    if ([string]::IsNullOrWhiteSpace([string]$systemDrive) -and -not [string]::IsNullOrWhiteSpace([string]$env:WINDIR)) {
        $systemDrive = [System.IO.Path]::GetPathRoot([string]$env:WINDIR).TrimEnd('\')
    }

    $machineValues = @{
        PRODICLOUD_COMPUTER_NAME = [string]$env:COMPUTERNAME
        PRODICLOUD_SYSTEM_DRIVE = [string]$systemDrive
        PRODICLOUD_WINDOWS_DIRECTORY = [string]$env:WINDIR
        PRODICLOUD_PROGRAM_DATA = [string]$env:ProgramData
        PRODICLOUD_PROGRAM_FILES = [string]$env:ProgramFiles
        PRODICLOUD_PROGRAM_FILES_X86 = [string]${env:ProgramFiles(x86)}
        PRODICLOUD_PRIMARY_IPV4_ADDRESS = ''
        PRODICLOUD_TARGET_CPU_COUNT = ''
        PRODICLOUD_TARGET_MEMORY_GB = ''
    }

    try {
        $processors = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)
        $logicalCount = @($processors | ForEach-Object {
            if ($_.NumberOfLogicalProcessors) { [int]$_.NumberOfLogicalProcessors }
            elseif ($_.NumberOfCores) { [int]$_.NumberOfCores }
        } | Measure-Object -Sum).Sum
        if ($logicalCount -gt 0) { $machineValues.PRODICLOUD_TARGET_CPU_COUNT = [string][int]$logicalCount }
    }
    catch { }
    try {
        $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        if ([double]$computer.TotalPhysicalMemory -gt 0) {
            $memoryGb = [Math]::Round(([double]$computer.TotalPhysicalMemory / 1GB), 2)
            $machineValues.PRODICLOUD_TARGET_MEMORY_GB = $memoryGb.ToString('0.##', [Globalization.CultureInfo]::InvariantCulture)
        }
    }
    catch { }
    try {
        $addresses = @()
        if (Get-Command Get-NetIPAddress -ErrorAction SilentlyContinue) {
            $addresses = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object {
                -not [bool]$_.SkipAsSource -and $_.IPAddress -notmatch '^(127\.|169\.254\.)'
            } | Select-Object -ExpandProperty IPAddress)
        }
        if (@($addresses).Count -eq 0) {
            $addresses = @(Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -ErrorAction Stop |
                Where-Object { [bool]$_.IPEnabled } |
                ForEach-Object { @($_.IPAddress) } |
                Where-Object { $_ -match '^\d{1,3}(?:\.\d{1,3}){3}$' -and $_ -notmatch '^(127\.|169\.254\.)' })
        }
        if (@($addresses).Count -gt 0) { $machineValues.PRODICLOUD_PRIMARY_IPV4_ADDRESS = [string]$addresses[0] }
    }
    catch { }

    foreach ($key in @($Overrides.Keys)) { $machineValues[[string]$key] = [string]$Overrides[$key] }
    return $machineValues
}

function Get-ProdicloudAppStateProfilePlaceholderValues {
    param(
        [object[]]$ProfileTargets = @(),
        [string]$ManagerUser = '',
        [string]$AssistantUser = '',
        [hashtable]$MachineValues = @{},
        [hashtable]$Overrides = @{}
    )

    $profiles = @{}
    if ([string]::IsNullOrWhiteSpace([string]$ManagerUser)) {
        $managerTarget = @($ProfileTargets | Where-Object { [string]::Equals([string]$_.Label, 'manager', [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
        if (@($managerTarget).Count -gt 0) { $ManagerUser = [string]$managerTarget[0].UserName }
    }
    if ([string]::IsNullOrWhiteSpace([string]$AssistantUser)) {
        $assistantTarget = @($ProfileTargets | Where-Object { [string]::Equals([string]$_.Label, 'assistant', [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
        if (@($assistantTarget).Count -gt 0) { $AssistantUser = [string]$assistantTarget[0].UserName }
    }
    $cimProfiles = @()
    if (@($ProfileTargets | Where-Object { $_ -and [string]$_.ProfilePath }).Count -gt 0) {
        try { $cimProfiles = @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop) } catch { $cimProfiles = @() }
    }

    foreach ($profileTarget in @($ProfileTargets)) {
        if ($null -eq $profileTarget) { continue }
        $label = [string]$profileTarget.Label
        $profilePath = [string]$profileTarget.ProfilePath
        $userName = [string]$profileTarget.UserName
        if ([string]::IsNullOrWhiteSpace([string]$label) -or [string]::IsNullOrWhiteSpace([string]$profilePath)) { continue }

        $sid = ''
        foreach ($cimProfile in @($cimProfiles)) {
            if ([string]::Equals(([string]$cimProfile.LocalPath).TrimEnd('\'), $profilePath.TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)) {
                $sid = [string]$cimProfile.SID
                break
            }
        }
        if ($profileTarget.PSObject.Properties.Match('SID').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$profileTarget.SID)) {
            $sid = [string]$profileTarget.SID
        }
        elseif ($profileTarget.PSObject.Properties.Match('UserSid').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$profileTarget.UserSid)) {
            $sid = [string]$profileTarget.UserSid
        }

        $userMap = @{}
        foreach ($key in @($MachineValues.Keys)) { $userMap[[string]$key] = [string]$MachineValues[$key] }
        $userMap['PRODICLOUD_VM_ADMIN_USER'] = [string](Get-ProdicloudAppStateProfileLeafName -UserName $ManagerUser)
        $userMap['PRODICLOUD_ASSISTANT_USER'] = [string](Get-ProdicloudAppStateProfileLeafName -UserName $AssistantUser)
        $userMap['PRODICLOUD_TARGET_USER'] = [string](Get-ProdicloudAppStateProfileLeafName -UserName $userName)
        $userMap['PRODICLOUD_TARGET_PROFILE_PATH'] = [string]$profilePath
        $userMap['PRODICLOUD_TARGET_USER_SID'] = [string]$sid
        $userMap['PRODICLOUD_LOCAL_APP_DATA'] = Join-Path $profilePath 'AppData\Local'
        $userMap['PRODICLOUD_ROAMING_APP_DATA'] = Join-Path $profilePath 'AppData\Roaming'
        $userMap['PRODICLOUD_VS_INSTANCE_DIRECTORY'] = ''

        $visualStudioRoot = Join-Path $profilePath 'AppData\Local\Microsoft\VisualStudio'
        if (Test-Path -LiteralPath $visualStudioRoot -PathType Container) {
            $instance = @(Get-ChildItem -LiteralPath $visualStudioRoot -Directory -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^17\.0_[A-Za-z0-9]+$' } |
                Sort-Object LastWriteTimeUtc -Descending |
                Select-Object -First 1)
            if (@($instance).Count -gt 0) { $userMap['PRODICLOUD_VS_INSTANCE_DIRECTORY'] = [string]$instance[0].Name }
        }

        foreach ($key in @($Overrides.Keys)) { $userMap[[string]$key] = [string]$Overrides[$key] }
        $profiles[$label.ToLowerInvariant()] = $userMap
    }

    $managerTarget = @($ProfileTargets | Where-Object { [string]::Equals([string]$_.Label, 'manager', [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
    $assistantTarget = @($ProfileTargets | Where-Object { [string]::Equals([string]$_.Label, 'assistant', [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
    foreach ($userMap in @($profiles.Values)) {
        $userMap['PRODICLOUD_VM_ADMIN_PROFILE_PATH'] = if (@($managerTarget).Count -gt 0) { [string]$managerTarget[0].ProfilePath } else { '' }
        $userMap['PRODICLOUD_ASSISTANT_PROFILE_PATH'] = if (@($assistantTarget).Count -gt 0) { [string]$assistantTarget[0].ProfilePath } else { '' }
        $userMap['PRODICLOUD_VM_ADMIN_USER_SID'] = if ($profiles.ContainsKey('manager')) { [string]$profiles['manager'].PRODICLOUD_TARGET_USER_SID } else { '' }
        $userMap['PRODICLOUD_ASSISTANT_USER_SID'] = if ($profiles.ContainsKey('assistant')) { [string]$profiles['assistant'].PRODICLOUD_TARGET_USER_SID } else { '' }
    }

    return $profiles
}

function ConvertTo-ProdicloudAppStatePortableText {
    param(
        [string]$Text,
        [hashtable]$ActualValues,
        [ValidateSet('plain','json','registry')][string]$Format = 'plain'
    )

    $result = [string]$Text
    foreach ($sourceValue in @($ActualValues.Keys | Sort-Object { ([string]$_).Length } -Descending)) {
        $actual = [string]$sourceValue
        $placeholder = [string]$ActualValues[$sourceValue]
        if ([string]::IsNullOrWhiteSpace([string]$actual) -or [string]::IsNullOrWhiteSpace([string]$placeholder)) { continue }
        if ($Format -in @('json','registry')) { $actual = $actual.Replace('\', '\\') }
        $index = $result.IndexOf($actual, [System.StringComparison]::OrdinalIgnoreCase)
        while ($index -ge 0) {
            $result = $result.Substring(0, $index) + $placeholder + $result.Substring($index + $actual.Length)
            $index = $result.IndexOf($actual, $index + $placeholder.Length, [System.StringComparison]::OrdinalIgnoreCase)
        }
    }

    if ($ActualValues.ContainsKey('__PRODICLOUD_SOURCE_COMPUTER_NAME__')) {
        $computerName = [string]$ActualValues['__PRODICLOUD_SOURCE_COMPUTER_NAME__']
        if (-not [string]::IsNullOrWhiteSpace([string]$computerName)) {
            $result = [regex]::Replace($result, '(?i)(?<![A-Z0-9_.-])' + [regex]::Escape($computerName) + '(?![A-Z0-9_.-])', '%PRODICLOUD_COMPUTER_NAME%')
        }
    }
    if ($ActualValues.ContainsKey('__PRODICLOUD_SOURCE_IPV4__')) {
        $address = [string]$ActualValues['__PRODICLOUD_SOURCE_IPV4__']
        if (-not [string]::IsNullOrWhiteSpace([string]$address)) {
            $result = [regex]::Replace($result, '(?<![0-9.])' + [regex]::Escape($address) + '(?![0-9.])', '%PRODICLOUD_PRIMARY_IPV4_ADDRESS%')
        }
    }
    return [string]$result
}

function ConvertTo-ProdicloudAppStatePortableObject {
    param(
        [AllowNull()]$Value,
        [hashtable]$ActualValues,
        [ValidateSet('plain','json','registry')][string]$Format = 'plain',
        [switch]$RemoveSensitiveFields
    )

    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) { return (ConvertTo-ProdicloudAppStatePortableText -Text ([string]$Value) -ActualValues $ActualValues -Format $Format) }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in @($Value.Keys)) {
            if ($RemoveSensitiveFields -and [string]$key -match '(?i)(password|secret|token|credential|(^|[._-])auth|api.?key|private.?key|account|email|gaia|sign.?in|sync|client.?id|machine.?id|device.?id|sid|subscription|tenant|user.?id)') {
                $Value.Remove($key)
                continue
            }
            $Value[$key] = ConvertTo-ProdicloudAppStatePortableObject -Value $Value[$key] -ActualValues $ActualValues -Format $Format -RemoveSensitiveFields:$RemoveSensitiveFields
        }
        return $Value
    }
    if ($Value -is [System.Array]) {
        $items = @()
        foreach ($item in @($Value)) { $items += (ConvertTo-ProdicloudAppStatePortableObject -Value $item -ActualValues $ActualValues -Format $Format -RemoveSensitiveFields:$RemoveSensitiveFields) }
        return ,$items
    }
    if ($Value -is [pscustomobject]) {
        foreach ($property in @($Value.PSObject.Properties)) {
            if ($RemoveSensitiveFields -and [string]$property.Name -match '(?i)(password|secret|token|credential|(^|[._-])auth|api.?key|private.?key|account|email|gaia|sign.?in|sync|client.?id|machine.?id|device.?id|sid|subscription|tenant|user.?id)') {
                $Value.PSObject.Properties.Remove([string]$property.Name)
                continue
            }
            $property.Value = ConvertTo-ProdicloudAppStatePortableObject -Value $property.Value -ActualValues $ActualValues -Format $Format -RemoveSensitiveFields:$RemoveSensitiveFields
        }
        return $Value
    }
    return $Value
}

function Remove-ProdicloudAppStateSensitiveTextLines {
    param(
        [string]$Content,
        [string]$Extension
    )

    if ([string]$Extension -in @('.xml','.vssettings','.config')) {
        try {
            [xml]$document = [string]$Content
            foreach ($node in @($document.SelectNodes('//*'))) {
                if ($null -eq $node -or $null -eq $node.ParentNode) { continue }
                if ([string]$node.LocalName -match '(?i)(password|secret|token|credential|authentication|(^|[._-])auth|api.?key|private.?key|account|email|identity|sign.?in|sync|client.?id|machine.?id|device.?id|sid|subscription|tenant|user.?id)') {
                    [void]$node.ParentNode.RemoveChild($node)
                    continue
                }
                foreach ($attribute in @($node.Attributes)) {
                    if ([string]$attribute.Name -match '(?i)(password|secret|token|credential|(^|[._-])auth|api.?key|private.?key|account|email|client.?id|machine.?id|device.?id|sid|tenant|subscription)') {
                        [void]$node.Attributes.Remove($attribute)
                    }
                }
            }
            return [string]$document.OuterXml
        }
        catch { return [string]$Content }
    }

    $lines = New-Object 'System.Collections.Generic.List[string]'
    $skipSensitiveSection = $false
    foreach ($line in @(([string]$Content) -split '\r?\n')) {
        if ($line -match '^\s*\[(?<section>[^\]]+)\]\s*$') {
            $skipSensitiveSection = ([string]$Matches.section -match '(?i)(password|secret|token|credential|auth|api.?key|private.?key|account|identity)')
            if ($skipSensitiveSection) { continue }
        }
        if ($skipSensitiveSection) { continue }
        if ($line -match '^\s*[#;]' -or [string]::IsNullOrWhiteSpace([string]$line)) {
            $lines.Add([string]$line) | Out-Null
            continue
        }
        if ($line -match '^\s*["'']?(?<key>[A-Za-z0-9_.-]+)["'']?\s*(?:=|:)\s*' -and
            [string]$Matches.key -match '(?i)(password|secret|token|credential|(^|[._-])auth|api.?key|private.?key|account|email|gaia|sign.?in|sync|client.?id|machine.?id|device.?id|sid|subscription|tenant|user.?id)') {
            continue
        }
        if ($line -match '(?i)(?:gh[pousr]_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,})') {
            continue
        }
        $lines.Add([string]$line) | Out-Null
    }
    return @($lines.ToArray()) -join [Environment]::NewLine
}

function ConvertTo-ProdicloudAppStateHardwareSettingsToPortable {
    param([string]$Content, [string]$FileName)

    if (-not [string]::Equals([string]$FileName, '.wslconfig', [System.StringComparison]::OrdinalIgnoreCase)) {
        return [string]$Content
    }

    $result = [regex]::Replace([string]$Content, '(?im)^(\s*processors\s*=\s*)\d+\s*$', '$1%PRODICLOUD_TARGET_CPU_COUNT%')
    $result = [regex]::Replace([string]$result, '(?im)^(\s*memory\s*=\s*)\d+(?:\.\d+)?\s*(?:KB|MB|GB|TB)?\s*$', '$1%PRODICLOUD_TARGET_MEMORY_GB%GB')
    return [string]$result
}

function Get-ProdicloudAppStateCaptureActualValues {
    param(
        [hashtable]$MachineValues,
        [hashtable]$ProfileValues,
        [string]$ProfileLabel
    )

    $actualValues = @{}
    foreach ($machinePath in @(
        @{ Name = 'ProgramFilesX86'; Value = [string]$env:ProgramFilesX86; Token = '%PRODICLOUD_PROGRAM_FILES_X86%' },
        @{ Name = 'ProgramFiles'; Value = [string]$env:ProgramFiles; Token = '%PRODICLOUD_PROGRAM_FILES%' },
        @{ Name = 'ProgramData'; Value = [string]$env:ProgramData; Token = '%PRODICLOUD_PROGRAM_DATA%' },
        @{ Name = 'Windows'; Value = [string]$env:WINDIR; Token = '%PRODICLOUD_WINDOWS_DIRECTORY%' }
    )) {
        if (-not [string]::IsNullOrWhiteSpace([string]$machinePath.Value)) { $actualValues[[string]$machinePath.Value] = [string]$machinePath.Token }
    }
    $systemDrive = [string]$MachineValues.PRODICLOUD_SYSTEM_DRIVE
    if (-not [string]::IsNullOrWhiteSpace([string]$systemDrive)) { $actualValues[$systemDrive.TrimEnd('\')] = '%PRODICLOUD_SYSTEM_DRIVE%' }

    foreach ($label in @('manager','assistant')) {
        if ($ProfileValues.ContainsKey([string]$label)) {
            $profilePath = [string]$ProfileValues[[string]$label].PRODICLOUD_TARGET_PROFILE_PATH
            $pathToken = if ([string]::Equals([string]$label, [string]$ProfileLabel, [System.StringComparison]::OrdinalIgnoreCase)) { '%PRODICLOUD_TARGET_PROFILE_PATH%' } elseif ($label -eq 'manager') { '%PRODICLOUD_VM_ADMIN_PROFILE_PATH%' } else { '%PRODICLOUD_ASSISTANT_PROFILE_PATH%' }
            if (-not [string]::IsNullOrWhiteSpace([string]$profilePath)) { $actualValues[[string]$profilePath] = [string]$pathToken }
            $sid = [string]$ProfileValues[[string]$label].PRODICLOUD_TARGET_USER_SID
            $sidToken = if ([string]::Equals([string]$label, [string]$ProfileLabel, [System.StringComparison]::OrdinalIgnoreCase)) { '%PRODICLOUD_TARGET_USER_SID%' } elseif ($label -eq 'manager') { '%PRODICLOUD_VM_ADMIN_USER_SID%' } else { '%PRODICLOUD_ASSISTANT_USER_SID%' }
            if (-not [string]::IsNullOrWhiteSpace([string]$sid)) { $actualValues[$sid] = [string]$sidToken }
            if ([string]::Equals([string]$label, [string]$ProfileLabel, [System.StringComparison]::OrdinalIgnoreCase)) {
                $visualStudioDirectory = [string]$ProfileValues[[string]$label].PRODICLOUD_VS_INSTANCE_DIRECTORY
                if (-not [string]::IsNullOrWhiteSpace([string]$visualStudioDirectory)) { $actualValues[$visualStudioDirectory] = '%PRODICLOUD_VS_INSTANCE_DIRECTORY%' }
            }
        }
    }
    $actualValues['__PRODICLOUD_SOURCE_COMPUTER_NAME__'] = [string]$MachineValues.PRODICLOUD_COMPUTER_NAME
    $actualValues['__PRODICLOUD_SOURCE_IPV4__'] = [string]$MachineValues.PRODICLOUD_PRIMARY_IPV4_ADDRESS
    return $actualValues
}

function ConvertTo-ProdicloudAppStatePortablePayload {
    param(
        [string]$ScratchRoot,
        [psobject]$Manifest,
        [object[]]$ProfileTargets = @(),
        [string]$ManagerUser = '',
        [string]$AssistantUser = ''
    )

    $machineValues = Get-ProdicloudAppStateMachinePlaceholderValues
    $profileValues = Get-ProdicloudAppStateProfilePlaceholderValues -ProfileTargets @($ProfileTargets) -ManagerUser $ManagerUser -AssistantUser $AssistantUser -MachineValues $machineValues
    foreach ($collectionName in @('machineDirectories','machineFiles','profileDirectories','profileFiles','registryImports')) {
        foreach ($entry in @($Manifest.$collectionName)) {
            if ($null -eq $entry) { continue }
            $labels = @()
            if ($entry.PSObject.Properties.Match('targetProfiles').Count -gt 0) {
                $labels = @($entry.targetProfiles | ForEach-Object { ([string]$_).ToLowerInvariant() } | Where-Object { $_ -in @('manager','assistant') })
            }
            $profileLabel = if (@($labels).Count -eq 1) { [string]$labels[0] } else { '' }
            $actualValues = Get-ProdicloudAppStateCaptureActualValues -MachineValues $machineValues -ProfileValues $profileValues -ProfileLabel $profileLabel
            [void](ConvertTo-ProdicloudAppStatePortableObject -Value $entry -ActualValues $actualValues -Format plain)
        }
    }

    foreach ($entry in @($Manifest.profileDirectories) + @($Manifest.profileFiles)) {
        if ($null -eq $entry -or @($entry.targetProfiles).Count -ne 1) { continue }
        $label = ([string]$entry.targetProfiles[0]).ToLowerInvariant()
        if ($profileValues.ContainsKey($label) -and $entry.PSObject.Properties.Match('relativeDestinationPath').Count -gt 0) {
            $value = [string]$entry.relativeDestinationPath
            $sourceInstance = [string]$profileValues[$label].PRODICLOUD_VS_INSTANCE_DIRECTORY
            if (-not [string]::IsNullOrWhiteSpace([string]$sourceInstance)) {
                $entry.relativeDestinationPath = $value.Replace($sourceInstance, '%PRODICLOUD_VS_INSTANCE_DIRECTORY%')
            }
        }
    }

    $textExtensions = @('.json','.xml','.reg','.ini','.txt','.yaml','.yml','.toml','.config','.settings','.ps1','.psm1','.cmd','.bat','.conf','.properties','.vssettings','.winprf','.vlcrc')
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $ScratchRoot 'payload') -Recurse -File -Force -ErrorAction SilentlyContinue)) {
        if ([IO.Path]::GetExtension($file.Name).ToLowerInvariant() -notin $textExtensions -and $file.Name -notin @('config','nvda.ini','DEFAULT.JCF','DEFAULT.JDF','.wslconfig')) { continue }
        $bytes = [IO.File]::ReadAllBytes($file.FullName)
        $encodingInfo = Get-ProdicloudAppStateTextFileEncoding -Bytes $bytes
        $encoding = [System.Text.Encoding]$encodingInfo.Encoding
        $content = [string]$encoding.GetString($bytes, [int]$encodingInfo.Offset, $bytes.Length - [int]$encodingInfo.Offset)
        if ($content.Contains([char]0)) { continue }
        $relativePath = [string]$file.FullName.Substring($ScratchRoot.Length).TrimStart([char[]]@('\','/')).Replace('\','/')
        $profileLabel = Get-ProdicloudAppStatePayloadProfileLabel -Path $relativePath
        if ([string]::IsNullOrWhiteSpace([string]$profileLabel)) {
            foreach ($collectionName in @('profileDirectories','profileFiles','registryImports')) {
                foreach ($entry in @($Manifest.$collectionName)) {
                    if ($null -eq $entry -or [string]::IsNullOrWhiteSpace([string]$entry.sourcePath)) { continue }
                    $sourcePath = ([string]$entry.sourcePath).Replace('\','/').TrimStart('/')
                    if ($relativePath.StartsWith($sourcePath.TrimEnd('/') + '/', [System.StringComparison]::OrdinalIgnoreCase) -or [string]::Equals($relativePath, $sourcePath, [System.StringComparison]::OrdinalIgnoreCase)) {
                        if ($entry.PSObject.Properties.Match('targetProfiles').Count -gt 0 -and @($entry.targetProfiles).Count -eq 1) {
                            $profileLabel = [string]$entry.targetProfiles[0]
                        }
                        break
                    }
                }
                if (-not [string]::IsNullOrWhiteSpace([string]$profileLabel)) { break }
            }
        }
        $actualValues = Get-ProdicloudAppStateCaptureActualValues -MachineValues $machineValues -ProfileValues $profileValues -ProfileLabel $profileLabel
        $format = if ([IO.Path]::GetExtension($file.Name).ToLowerInvariant() -eq '.json') { 'json' } elseif ([IO.Path]::GetExtension($file.Name).ToLowerInvariant() -eq '.reg') { 'registry' } else { 'plain' }
        if ($format -eq 'json') {
            try {
                $jsonObject = ConvertFrom-Json -InputObject $content -ErrorAction Stop
                $jsonObject = ConvertTo-ProdicloudAppStatePortableObject -Value $jsonObject -ActualValues $actualValues -Format plain -RemoveSensitiveFields
                $content = ConvertTo-Json -InputObject $jsonObject -Depth 100
            }
            catch {
                $content = ConvertTo-ProdicloudAppStatePortableText -Text $content -ActualValues $actualValues -Format json
            }
        }
        else {
            $content = ConvertTo-ProdicloudAppStatePortableText -Text $content -ActualValues $actualValues -Format $format
        }
        $content = ConvertTo-ProdicloudAppStateHardwareSettingsToPortable -Content ([string]$content) -FileName ([string]$file.Name)
        $content = Remove-ProdicloudAppStateSensitiveTextLines -Content ([string]$content) -Extension ([IO.Path]::GetExtension($file.Name).ToLowerInvariant())
        [IO.File]::WriteAllText($file.FullName, [string]$content, $encoding)
    }
}

function Resolve-ProdicloudAppStatePlaceholderText {
    param(
        [string]$Text,
        [hashtable]$Replacements,
        [ValidateSet('plain','json','registry')][string]$Format = 'plain',
        [string]$SourceLabel = 'payload'
    )

    $pattern = '%(?<name>PRODICLOUD_[A-Z0-9_]+)%'
    $resolved = [regex]::Replace([string]$Text, $pattern, {
        param($match)
        $name = [string]$match.Groups['name'].Value
        if ($null -eq $Replacements -or -not $Replacements.ContainsKey($name)) {
            throw ("Unsupported app-state placeholder '%{0}%' in {1}." -f $name, $SourceLabel)
        }
        $value = [string]$Replacements[$name]
        if ([string]::IsNullOrWhiteSpace([string]$value)) {
            throw ("App-state placeholder '%{0}%' has no value for this target in {1}." -f $name, $SourceLabel)
        }
        if ($Format -in @('json','registry')) {
            $encoded = ConvertTo-Json -InputObject $value -Compress
            return [string]$encoded.Substring(1, $encoded.Length - 2)
        }
        return [string]$value
    })

    if ([regex]::IsMatch([string]$resolved, '%PRODICLOUD_[A-Z0-9_]+%')) {
        throw ("Unresolved prodicloud app-state placeholder remains in {0}." -f $SourceLabel)
    }
    return [string]$resolved
}

function Get-ProdicloudAppStatePayloadProfileLabel {
    param([string]$Path)

    $normalized = ([string]$Path).Replace('\', '/')
    if ($normalized -match '(?i)^payload/(?:profile-directories|profile-files)/(?<label>manager|assistant)/') {
        return [string]$Matches.label.ToLowerInvariant()
    }
    if ($normalized -match '(?i)^payload/registry/user/(?<label>manager|assistant)/') {
        return [string]$Matches.label.ToLowerInvariant()
    }
    return ''
}

function Get-ProdicloudAppStateTextFileEncoding {
    param([byte[]]$Bytes)

    if ($Bytes.Length -ge 4 -and $Bytes[0] -eq 0 -and $Bytes[1] -eq 0 -and $Bytes[2] -eq 0xFE -and $Bytes[3] -eq 0xFF) {
        return [pscustomobject]@{ Encoding = [System.Text.Encoding]::UTF32; Offset = 4 }
    }
    if ($Bytes.Length -ge 4 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE -and $Bytes[2] -eq 0 -and $Bytes[3] -eq 0) {
        return [pscustomobject]@{ Encoding = [System.Text.Encoding]::UTF32; Offset = 4 }
    }
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        return [pscustomobject]@{ Encoding = New-Object System.Text.UTF8Encoding($true); Offset = 3 }
    }
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) {
        return [pscustomobject]@{ Encoding = [System.Text.Encoding]::Unicode; Offset = 2 }
    }
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF) {
        return [pscustomobject]@{ Encoding = [System.Text.Encoding]::BigEndianUnicode; Offset = 2 }
    }
    return [pscustomobject]@{ Encoding = New-Object System.Text.UTF8Encoding($false); Offset = 0 }
}

function Expand-ProdicloudAppStatePayloadPlaceholders {
    param(
        [string]$ExpandedRoot,
        [object[]]$ProfileTargets = @(),
        [string]$ManagerUser = '',
        [string]$AssistantUser = '',
        [hashtable]$MachineOverrides = @{},
        [hashtable]$ProfileOverrides = @{}
    )

    $machineValues = Get-ProdicloudAppStateMachinePlaceholderValues -Overrides $MachineOverrides
    $profileValues = Get-ProdicloudAppStateProfilePlaceholderValues -ProfileTargets @($ProfileTargets) -ManagerUser $ManagerUser -AssistantUser $AssistantUser -MachineValues $machineValues -Overrides $ProfileOverrides
    $globalValues = @{}
    foreach ($key in @($machineValues.Keys)) { $globalValues[[string]$key] = [string]$machineValues[$key] }
    $globalValues['PRODICLOUD_VM_ADMIN_USER'] = [string](Get-ProdicloudAppStateProfileLeafName -UserName $ManagerUser)
    $globalValues['PRODICLOUD_ASSISTANT_USER'] = [string](Get-ProdicloudAppStateProfileLeafName -UserName $AssistantUser)

    $manifestPath = Join-Path $ExpandedRoot 'app-state.manifest.json'
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $manifest = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop) -ErrorAction Stop
        foreach ($collectionName in @('machineDirectories','machineFiles','profileDirectories','profileFiles','registryImports')) {
            if ($manifest.PSObject.Properties.Match($collectionName).Count -lt 1) { continue }
            $expandedEntries = New-Object 'System.Collections.Generic.List[object]'
            foreach ($entry in @($manifest.$collectionName)) {
                if ($null -eq $entry) { continue }
                $labels = @()
                if ($entry.PSObject.Properties.Match('targetProfiles').Count -gt 0) {
                    $labels = @($entry.targetProfiles | ForEach-Object { ([string]$_).ToLowerInvariant() } | Where-Object { $_ -in @('manager','assistant') })
                }
                $isUserRegistry = ($collectionName -eq 'registryImports' -and [string]$entry.scope -eq 'user')
                $isProfileScoped = ($collectionName -in @('profileDirectories','profileFiles') -or $isUserRegistry)
                if ($isProfileScoped -and @($labels).Count -eq 0) { $labels = @($profileValues.Keys) }
                if (-not $isProfileScoped -or @($labels).Count -eq 0) {
                    $labels = @('')
                }
                foreach ($label in @($labels)) {
                    $entryCopy = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $entry -Depth 20 -Compress) -ErrorAction Stop
                    $replacementSet = $globalValues
                    if (-not [string]::IsNullOrWhiteSpace([string]$label) -and $profileValues.ContainsKey([string]$label)) {
                        $replacementSet = $profileValues[[string]$label]
                        if ($isProfileScoped -and $entryCopy.PSObject.Properties.Match('targetProfiles').Count -gt 0) {
                            $entryCopy.targetProfiles = @([string]$label)
                        }
                    }
                    foreach ($property in @($entryCopy.PSObject.Properties)) {
                        if ($property.Value -is [string]) {
                            $property.Value = Resolve-ProdicloudAppStatePlaceholderText -Text ([string]$property.Value) -Replacements $replacementSet -Format plain -SourceLabel ('manifest.' + $collectionName + '.' + [string]$property.Name)
                        }
                        elseif ($property.Value -is [array]) {
                            $values = @()
                            foreach ($item in @($property.Value)) {
                                if ($item -is [string]) { $values += (Resolve-ProdicloudAppStatePlaceholderText -Text ([string]$item) -Replacements $replacementSet -Format plain -SourceLabel ('manifest.' + $collectionName + '.' + [string]$property.Name)) }
                                else { $values += $item }
                            }
                            $property.Value = $values
                        }
                    }
                    $expandedEntries.Add($entryCopy) | Out-Null
                }
            }
            $manifest.$collectionName = @($expandedEntries.ToArray())
        }
        Set-Content -LiteralPath $manifestPath -Value (ConvertTo-Json -InputObject $manifest -Depth 40) -Encoding UTF8
    }

    $textExtensions = @('.json','.xml','.reg','.ini','.txt','.yaml','.yml','.toml','.config','.settings','.ps1','.psm1','.cmd','.bat','.conf','.properties','.vssettings','.winprf','.xspf','.vlcrc')
    foreach ($file in @(Get-ChildItem -LiteralPath $ExpandedRoot -Recurse -File -Force -ErrorAction Stop)) {
        if ([string]::Equals([string]$file.FullName, [string]$manifestPath, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ([IO.Path]::GetExtension($file.Name).ToLowerInvariant() -notin $textExtensions -and $file.Name -notin @('config','nvda.ini','DEFAULT.JCF','DEFAULT.JDF')) { continue }
        $bytes = [IO.File]::ReadAllBytes($file.FullName)
        $encodingInfo = Get-ProdicloudAppStateTextFileEncoding -Bytes $bytes
        $encoding = [System.Text.Encoding]$encodingInfo.Encoding
        $content = [string]$encoding.GetString($bytes, [int]$encodingInfo.Offset, $bytes.Length - [int]$encodingInfo.Offset)
        if ($content.Contains([char]0)) { continue }

        $profileLabel = Get-ProdicloudAppStatePayloadProfileLabel -Path ([string]$file.FullName.Substring($ExpandedRoot.Length).TrimStart('\','/'))
        $replacementSet = $globalValues
        if (-not [string]::IsNullOrWhiteSpace([string]$profileLabel) -and $profileValues.ContainsKey([string]$profileLabel)) {
            $replacementSet = $profileValues[[string]$profileLabel]
        }
        $format = if ([IO.Path]::GetExtension($file.Name).ToLowerInvariant() -eq '.json') { 'json' } elseif ([IO.Path]::GetExtension($file.Name).ToLowerInvariant() -eq '.reg') { 'registry' } else { 'plain' }
        $content = Resolve-ProdicloudAppStatePlaceholderText -Text $content -Replacements $replacementSet -Format $format -SourceLabel ([string]$file.Name)
        if ([regex]::IsMatch([string]$content, '%PRODICLOUD_[A-Z0-9_]+%')) {
            throw ("Unresolved app-state placeholder remains in payload file '{0}'." -f [string]$file.FullName)
        }
        [IO.File]::WriteAllText($file.FullName, $content, $encoding)
    }
}

function Wait-ProdicloudAppStateZipReady {
    param(
        [string]$ZipPath,
        [int]$TimeoutSeconds = 60
    )

    if ([string]::IsNullOrWhiteSpace([string]$ZipPath) -or -not (Test-Path -LiteralPath $ZipPath)) {
        throw ("Task app-state zip was not found on guest: {0}" -f [string]$ZipPath)
    }

    $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Max($TimeoutSeconds, 5))
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $stream = [System.IO.File]::Open($ZipPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
            try {
                return [int64]$stream.Length
            }
            finally {
                if ($null -ne $stream) { $stream.Dispose() }
            }
        }
        catch {
            Start-Sleep -Milliseconds 500
        }
    }

    throw ("App-state zip stayed busy after upload: {0}" -f [string]$ZipPath)
}

function Get-ProdicloudAppStateManifestFromExpandedRoot {
    param(
        [string]$ExpandedRoot,
        [string]$TaskName
    )

    $manifestPath = Join-Path $ExpandedRoot 'app-state.manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw ("App-state manifest was not found in expanded payload: {0}" -f $manifestPath)
    }

    $manifestText = [string](Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop)
    if ([string]::IsNullOrWhiteSpace([string]$manifestText)) {
        throw ("App-state manifest is empty: {0}" -f $manifestPath)
    }

    $manifest = ConvertFrom-Json -InputObject $manifestText -ErrorAction Stop
    $resolvedTaskName = ''
    if ($manifest.PSObject.Properties.Match('taskName').Count -gt 0) {
        $resolvedTaskName = [string]$manifest.taskName
    }
    if (-not [string]::Equals([string]$resolvedTaskName, [string]$TaskName, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("App-state manifest taskName '{0}' does not match task '{1}'." -f [string]$resolvedTaskName, [string]$TaskName)
    }

    return $manifest
}

function Get-ProdicloudAppStateProfileTargets {
    param(
        [string]$ManagerUser,
        [string]$AssistantUser,
        [object[]]$ProfileTargets = @()
    )

    function Convert-ProdicloudAppStateProfileLabel {
        param([string]$Value)

        $normalized = if ($null -eq $Value) { '' } else { [string]$Value.Trim() }
        if ([string]::IsNullOrWhiteSpace([string]$normalized)) {
            return ''
        }

        return $normalized.ToLowerInvariant()
    }

    function Convert-ProdicloudAppStateUserNameToProfileLeaf {
        param([string]$Value)

        $text = if ($null -eq $Value) { '' } else { [string]$Value.Trim() }
        if ([string]::IsNullOrWhiteSpace([string]$text)) {
            return ''
        }

        if ($text.Contains('\')) {
            $parts = @($text -split '\\')
            $text = [string]$parts[$parts.Count - 1]
        }
        if ($text.Contains('/')) {
            $parts = @($text -split '/')
            $text = [string]$parts[$parts.Count - 1]
        }

        return [string]$text.Trim()
    }

    if (@($ProfileTargets).Count -gt 0) {
        $explicitRows = New-Object 'System.Collections.Generic.List[object]'
        $explicitSeen = @{}
        foreach ($target in @($ProfileTargets)) {
            if ($null -eq $target) {
                continue
            }

            $label = ''
            $userName = ''
            $profilePath = ''
            if ($target -is [System.Collections.IDictionary]) {
                if ($target.Contains('Label')) { $label = [string]$target['Label'] }
                if ($target.Contains('label')) { $label = [string]$target['label'] }
                if ($target.Contains('UserName')) { $userName = [string]$target['UserName'] }
                if ($target.Contains('userName')) { $userName = [string]$target['userName'] }
                if ($target.Contains('ProfilePath')) { $profilePath = [string]$target['ProfilePath'] }
                if ($target.Contains('profilePath')) { $profilePath = [string]$target['profilePath'] }
            }
            else {
                if ($target.PSObject.Properties.Match('Label').Count -gt 0) { $label = [string]$target.Label }
                elseif ($target.PSObject.Properties.Match('label').Count -gt 0) { $label = [string]$target.label }
                if ($target.PSObject.Properties.Match('UserName').Count -gt 0) { $userName = [string]$target.UserName }
                elseif ($target.PSObject.Properties.Match('userName').Count -gt 0) { $userName = [string]$target.userName }
                if ($target.PSObject.Properties.Match('ProfilePath').Count -gt 0) { $profilePath = [string]$target.ProfilePath }
                elseif ($target.PSObject.Properties.Match('profilePath').Count -gt 0) { $profilePath = [string]$target.profilePath }
            }

            $profilePath = [string]$profilePath.Trim()
            if ([string]::IsNullOrWhiteSpace([string]$profilePath) -or -not (Test-Path -LiteralPath $profilePath)) {
                continue
            }

            $userName = Convert-ProdicloudAppStateUserNameToProfileLeaf -Value $userName
            if ([string]::IsNullOrWhiteSpace([string]$userName)) {
                $userName = [string](Split-Path -Path $profilePath -Leaf)
            }

            $label = Convert-ProdicloudAppStateProfileLabel -Value $label
            if ([string]::IsNullOrWhiteSpace([string]$label)) {
                $label = Convert-ProdicloudAppStateProfileLabel -Value $userName
            }

            $dedupeKey = $profilePath.TrimEnd('\').ToLowerInvariant()
            if ($explicitSeen.ContainsKey($dedupeKey)) {
                continue
            }

            $explicitRows.Add([pscustomobject]@{
                Label = [string]$label
                UserName = [string]$userName
                ProfilePath = [string]$profilePath
            }) | Out-Null
            $explicitSeen[$dedupeKey] = $true
        }

        return @($explicitRows.ToArray())
    }

    $rows = New-Object 'System.Collections.Generic.List[object]'
    $seen = @{}
    $managerProfileLeaf = Convert-ProdicloudAppStateUserNameToProfileLeaf -Value $ManagerUser
    $assistantProfileLeaf = Convert-ProdicloudAppStateUserNameToProfileLeaf -Value $AssistantUser

    foreach ($row in @(
        @{ Label = 'manager'; UserName = [string]$managerProfileLeaf; Path = ('C:\Users\{0}' -f [string]$managerProfileLeaf) },
        @{ Label = 'assistant'; UserName = [string]$assistantProfileLeaf; Path = ('C:\Users\{0}' -f [string]$assistantProfileLeaf) }
    )) {
        $profilePath = [string]$row.Path
        if ([string]::IsNullOrWhiteSpace([string]$profilePath) -or -not (Test-Path -LiteralPath $profilePath)) {
            continue
        }

        $normalizedPath = $profilePath.TrimEnd('\').ToLowerInvariant()
        if ($seen.ContainsKey($normalizedPath)) {
            continue
        }

        $rows.Add([pscustomobject]@{
            Label = [string]$row.Label
            UserName = [string]$row.UserName
            ProfilePath = [string]$profilePath
        }) | Out-Null
        $seen[$normalizedPath] = $true
    }

    return @($rows.ToArray())
}

function Get-ProdicloudAppStateEntryTargetProfiles {
    param([AllowNull()]$Entry)

    if ($null -eq $Entry -or $Entry.PSObject.Properties.Match('targetProfiles').Count -lt 1) {
        return @()
    }

    return @(
        @($Entry.targetProfiles) |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object { $_.Trim().ToLowerInvariant() } |
            Select-Object -Unique
    )
}

function Get-ProdicloudAppStateSelectedProfileTargets {
    param(
        [object[]]$ProfileTargets,
        [AllowNull()]$Entry
    )

    $targetProfiles = @(Get-ProdicloudAppStateEntryTargetProfiles -Entry $Entry)
    if (@($targetProfiles).Count -lt 1) {
        return @($ProfileTargets)
    }

    return @(
        @($ProfileTargets) | Where-Object {
            $label = if ($_.PSObject.Properties.Match('Label').Count -gt 0) { [string]$_.Label } else { '' }
            $userName = if ($_.PSObject.Properties.Match('UserName').Count -gt 0) { [string]$_.UserName } else { '' }
            $normalizedValues = @($label, $userName) |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
                ForEach-Object { $_.Trim().ToLowerInvariant() }
            foreach ($value in @($normalizedValues)) {
                if (@($targetProfiles) -contains $value) {
                    return $true
                }
            }
            return $false
        }
    )
}

function Invoke-ProdicloudRegImport {
    param([string]$SourcePath)

    if ([string]::IsNullOrWhiteSpace([string]$SourcePath) -or -not (Test-Path -LiteralPath $SourcePath)) {
        return $false
    }

    cmd.exe /d /c ('reg import "{0}" >nul 2>&1' -f $SourcePath) | Out-Null
    return ([int]$LASTEXITCODE -eq 0)
}

function Get-ProdicloudMountedUserHive {
    param(
        [string]$ProfilePath,
        [string]$PreferredLabel
    )

    if ([string]::IsNullOrWhiteSpace([string]$ProfilePath)) {
        return $null
    }

    $normalizedProfilePath = [string]$ProfilePath.TrimEnd('\')
    try {
        $profile = @(Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue | Where-Object {
            [string]::Equals(([string]$_.LocalPath).TrimEnd('\'), $normalizedProfilePath, [System.StringComparison]::OrdinalIgnoreCase)
        } | Select-Object -First 1)
        if (@($profile).Count -gt 0) {
            $entry = $profile[0]
            if ($entry.PSObject.Properties.Match('Loaded').Count -gt 0 -and [bool]$entry.Loaded -and $entry.PSObject.Properties.Match('SID').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$entry.SID)) {
                return [pscustomobject]@{
                    Root = ('HKEY_USERS\{0}' -f [string]$entry.SID)
                    Temporary = $false
                    MountName = [string]$entry.SID
                }
            }
        }
    }
    catch {
    }

    $ntUserDatPath = Join-Path $ProfilePath 'NTUSER.DAT'
    if (-not (Test-Path -LiteralPath $ntUserDatPath)) {
        return $null
    }

    $sanitized = (($PreferredLabel -replace '[^A-Za-z0-9]', '_')).Trim('_')
    if ([string]::IsNullOrWhiteSpace([string]$sanitized)) {
        $sanitized = 'user'
    }

    $mountName = ('PRODICLOUD_APPSTATE_{0}' -f $sanitized)
    cmd.exe /d /c ('reg load "HKU\{0}" "{1}" >nul 2>&1' -f $mountName, $ntUserDatPath) | Out-Null
    if ([int]$LASTEXITCODE -ne 0) {
        return $null
    }

    return [pscustomobject]@{
        Root = ('HKEY_USERS\{0}' -f $mountName)
        Temporary = $true
        MountName = [string]$mountName
    }
}

function Test-ProdicloudAppStateProfileRegistryReplayAvailable {
    param([AllowNull()]$ProfileTarget)

    if ($null -eq $ProfileTarget) {
        return $false
    }

    $profilePath = if ($ProfileTarget.PSObject.Properties.Match('ProfilePath').Count -gt 0) { [string]$ProfileTarget.ProfilePath } else { '' }
    if ([string]::IsNullOrWhiteSpace([string]$profilePath) -or -not (Test-Path -LiteralPath $profilePath -PathType Container)) {
        return $false
    }

    $ntUserDatPath = Join-Path $profilePath 'NTUSER.DAT'
    if (Test-Path -LiteralPath $ntUserDatPath -PathType Leaf) {
        return $true
    }

    try {
        $profile = @(Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue | Where-Object {
            [string]::Equals(([string]$_.LocalPath).TrimEnd('\'), ([string]$profilePath).TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)
        } | Select-Object -First 1)
        if (@($profile).Count -gt 0) {
            $entry = $profile[0]
            if ($entry.PSObject.Properties.Match('Loaded').Count -gt 0 -and [bool]$entry.Loaded) {
                return $true
            }
        }
    }
    catch {
    }

    return $false
}

function Close-ProdicloudMountedUserHive {
    param([AllowNull()]$MountInfo)

    if ($null -eq $MountInfo) {
        return
    }

    if (-not $MountInfo.PSObject.Properties.Match('Temporary').Count -or -not [bool]$MountInfo.Temporary) {
        return
    }

    $mountName = [string]$MountInfo.MountName
    if ([string]::IsNullOrWhiteSpace([string]$mountName)) {
        return
    }

    cmd.exe /d /c ('reg unload "HKU\{0}" >nul 2>&1' -f $mountName) | Out-Null
}

function Convert-ProdicloudAppStateRegRoot {
    param(
        [string]$SourcePath,
        [string]$SourceRoot,
        [string]$DestinationRoot,
        [string]$DestinationPath
    )

    $content = [string](Get-Content -LiteralPath $SourcePath -Raw -Encoding Unicode -ErrorAction SilentlyContinue)
    if ([string]::IsNullOrWhiteSpace([string]$content)) {
        $content = [string](Get-Content -LiteralPath $SourcePath -Raw -ErrorAction SilentlyContinue)
    }
    if ([string]::IsNullOrWhiteSpace([string]$content)) {
        return $false
    }

    $escapedSourceRoot = [regex]::Escape([string]$SourceRoot)
    $rewritten = [regex]::Replace(
        $content,
        ('(?im)^\[(\-?){0}(?=\\|])' -f $escapedSourceRoot),
        [System.Text.RegularExpressions.MatchEvaluator]{
            param($match)
            return ('[{0}{1}' -f [string]$match.Groups[1].Value, [string]$DestinationRoot)
        })

    Ensure-ProdicloudAppStateDirectory -Path (Split-Path -Path $DestinationPath -Parent)
    Set-Content -LiteralPath $DestinationPath -Value $rewritten -Encoding Unicode
    return $true
}

function Convert-ProdicloudAppStateRegistryPathToCanonicalRoot {
    param([string]$RegistryPath)

    if ([string]::IsNullOrWhiteSpace([string]$RegistryPath)) {
        return ''
    }

    $trimmed = ([string]$RegistryPath).Trim()
    $trimmed = $trimmed -replace '^HKCU\\', 'HKEY_CURRENT_USER\'
    $trimmed = $trimmed -replace '^HKLM\\', 'HKEY_LOCAL_MACHINE\'
    $trimmed = $trimmed -replace '^HKCR\\', 'HKEY_CLASSES_ROOT\'
    $trimmed = $trimmed -replace '^HKU\\', 'HKEY_USERS\'
    return [string]$trimmed
}

function Convert-ProdicloudAppStateRegistryPathToProviderPath {
    param([string]$RegistryPath)

    if ([string]::IsNullOrWhiteSpace([string]$RegistryPath)) {
        return ''
    }

    $trimmed = Convert-ProdicloudAppStateRegistryPathToCanonicalRoot -RegistryPath $RegistryPath
    if ([string]::IsNullOrWhiteSpace([string]$trimmed)) {
        return ''
    }

    return ('Registry::{0}' -f $trimmed)
}

function Invoke-ProdicloudAppStateWslRegistryPurge {
    param(
        [string]$MountedUserRegistryRoot,
        [string]$RegistryPath,
        [string[]]$DistributionAllowList = @()
    )

    $normalizedAllowList = @(
        @($DistributionAllowList) |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object { $_.Trim().ToLowerInvariant() } |
            Select-Object -Unique
    )
    if (@($normalizedAllowList).Count -lt 1) {
        return
    }

    $normalizedRegistryPath = ([string]$RegistryPath).Trim()
    if (-not $normalizedRegistryPath.StartsWith('HKCU\', [System.StringComparison]::OrdinalIgnoreCase)) {
        return
    }

    $relativeRegistryPath = $normalizedRegistryPath.Substring(5)
    $providerRoot = Convert-ProdicloudAppStateRegistryPathToProviderPath -RegistryPath ('{0}\{1}' -f $MountedUserRegistryRoot, $relativeRegistryPath)
    if ([string]::IsNullOrWhiteSpace([string]$providerRoot) -or -not (Test-Path -LiteralPath $providerRoot)) {
        return
    }

    foreach ($childKey in @(Get-ChildItem -LiteralPath $providerRoot -ErrorAction SilentlyContinue | Sort-Object PSChildName)) {
        $distributionName = ''
        try {
            $distributionName = [string](Get-ItemPropertyValue -LiteralPath $childKey.PSPath -Name 'DistributionName' -ErrorAction Stop)
        }
        catch {
            continue
        }

        if ([string]::IsNullOrWhiteSpace([string]$distributionName)) {
            continue
        }

        if (@($normalizedAllowList) -contains $distributionName.Trim().ToLowerInvariant()) {
            continue
        }

        Remove-Item -LiteralPath $childKey.PSPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Copy-ProdicloudAppStateFile {
    param(
        [string]$SourcePath,
        [string]$DestinationPath
    )

    Ensure-ProdicloudAppStateDirectory -Path (Split-Path -Path $DestinationPath -Parent)
    try {
        Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force -ErrorAction Stop
        return [pscustomobject]@{
            Copied = $true
            Skipped = $false
            Reason = ''
        }
    }
    catch {
        Write-Host ("app-state-file-copy-skip => source={0}; destination={1}; reason={2}" -f [string]$SourcePath, [string]$DestinationPath, $_.Exception.Message)
        return [pscustomobject]@{
            Copied = $false
            Skipped = $true
            Reason = [string]$_.Exception.Message
        }
    }
}

function Copy-ProdicloudAppStateDirectoryContents {
    param(
        [string]$SourcePath,
        [string]$DestinationPath
    )

    Ensure-ProdicloudAppStateDirectory -Path $DestinationPath
    $copiedCount = 0
    $skippedCount = 0
    $firstSkipReason = ''
    foreach ($item in @(Get-ChildItem -LiteralPath $SourcePath -Force -ErrorAction SilentlyContinue)) {
        try {
            Copy-Item -LiteralPath $item.FullName -Destination $DestinationPath -Recurse -Force -ErrorAction Stop
            $copiedCount++
        }
        catch {
            Write-Host ("app-state-directory-copy-skip => source={0}; destination={1}; reason={2}" -f [string]$item.FullName, [string]$DestinationPath, $_.Exception.Message)
            $skippedCount++
            if ([string]::IsNullOrWhiteSpace([string]$firstSkipReason)) {
                $firstSkipReason = [string]$_.Exception.Message
            }
        }
    }

    return [pscustomobject]@{
        CopiedAny = ($copiedCount -gt 0)
        CopiedCount = [int]$copiedCount
        SkippedAny = ($skippedCount -gt 0)
        SkippedCount = [int]$skippedCount
        Reason = [string]$firstSkipReason
    }
}

function Set-ProdicloudAppStateOperationReplayStatus {
    param(
        [AllowNull()]$Operation,
        [string]$Status,
        [string]$Reason = ''
    )

    if ($null -eq $Operation) {
        return
    }

    if ($Operation.PSObject.Properties.Match('ReplayStatus').Count -lt 1) {
        $Operation | Add-Member -NotePropertyName 'ReplayStatus' -NotePropertyValue ([string]$Status)
    }
    else {
        $Operation.ReplayStatus = [string]$Status
    }

    if ($Operation.PSObject.Properties.Match('ReplayReason').Count -lt 1) {
        $Operation | Add-Member -NotePropertyName 'ReplayReason' -NotePropertyValue ([string]$Reason)
    }
    else {
        $Operation.ReplayReason = [string]$Reason
    }
}

function Get-ProdicloudAppStateOperationReplayStatus {
    param([AllowNull()]$Operation)

    $status = 'applied'
    $reason = ''
    if ($null -ne $Operation) {
        if ($Operation.PSObject.Properties.Match('ReplayStatus').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$Operation.ReplayStatus)) {
            $status = [string]$Operation.ReplayStatus
        }
        if ($Operation.PSObject.Properties.Match('ReplayReason').Count -gt 0) {
            $reason = [string]$Operation.ReplayReason
        }
    }

    return [pscustomobject]@{
        Status = [string]$status
        Reason = [string]$reason
    }
}

function Set-ProdicloudAppStateBackupRecordStatus {
    param(
        [AllowNull()]$Record,
        [string]$Status,
        [string]$Reason = ''
    )

    if ($null -eq $Record) {
        return
    }

    if ($Record.PSObject.Properties.Match('BackupStatus').Count -lt 1) {
        $Record | Add-Member -NotePropertyName 'BackupStatus' -NotePropertyValue ([string]$Status)
    }
    else {
        $Record.BackupStatus = [string]$Status
    }

    if ($Record.PSObject.Properties.Match('BackupReason').Count -lt 1) {
        $Record | Add-Member -NotePropertyName 'BackupReason' -NotePropertyValue ([string]$Reason)
    }
    else {
        $Record.BackupReason = [string]$Reason
    }
}

function Get-ProdicloudAppStateBackupRecordStatus {
    param([AllowNull()]$Record)

    $status = 'captured'
    $reason = ''
    if ($null -ne $Record) {
        if ($Record.PSObject.Properties.Match('BackupStatus').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$Record.BackupStatus)) {
            $status = [string]$Record.BackupStatus
        }
        if ($Record.PSObject.Properties.Match('BackupReason').Count -gt 0) {
            $reason = [string]$Record.BackupReason
        }
    }

    return [pscustomobject]@{
        Status = [string]$status
        Reason = [string]$reason
    }
}

function Invoke-ProdicloudRegExport {
    param(
        [string]$RegistryPath,
        [string]$DestinationPath
    )

    if ([string]::IsNullOrWhiteSpace([string]$RegistryPath) -or [string]::IsNullOrWhiteSpace([string]$DestinationPath)) {
        return $false
    }

    Ensure-ProdicloudAppStateDirectory -Path (Split-Path -Path $DestinationPath -Parent)
    cmd.exe /d /c ('reg export "{0}" "{1}" /y >nul 2>&1' -f $RegistryPath, $DestinationPath) | Out-Null
    return ([int]$LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $DestinationPath))
}

function ConvertTo-ProdicloudAppStateCaptureSafeName {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return 'item'
    }

    return (([string]$Value -replace '^[A-Za-z]:', '') -replace '[\\/:*?"<>| ]', '_').Trim('_')
}

function Test-ProdicloudAppStateCaptureExcludedItem {
    param(
        [string]$SourcePath,
        [string[]]$ExcludeNames = @(),
        [string[]]$ExcludePathPatterns = @(),
        [string[]]$ExcludeFilePatterns = @()
    )

    $leafName = [System.IO.Path]::GetFileName([string]$SourcePath)
    foreach ($excludeName in @($ExcludeNames)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$excludeName) -and [string]::Equals([string]$leafName, [string]$excludeName, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    foreach ($pathPattern in @($ExcludePathPatterns)) {
        if ([string]::IsNullOrWhiteSpace([string]$pathPattern)) { continue }
        if ([string]$SourcePath -like [string]$pathPattern) {
            return $true
        }
    }

    if (Test-Path -LiteralPath $SourcePath -PathType Leaf) {
        foreach ($filePattern in @($ExcludeFilePatterns)) {
            if ([string]::IsNullOrWhiteSpace([string]$filePattern)) { continue }
            if ([string]$leafName -like [string]$filePattern) {
                return $true
            }
        }
    }

    return $false
}

function Copy-ProdicloudAppStateCaptureTree {
    param(
        [string]$SourcePath,
        [string]$DestinationPath,
        [string[]]$ExcludeNames = @(),
        [string[]]$ExcludePathPatterns = @(),
        [string[]]$ExcludeFilePatterns = @()
    )

    if ([string]::IsNullOrWhiteSpace([string]$SourcePath) -or -not (Test-Path -LiteralPath $SourcePath)) {
        return $false
    }

    if (Test-ProdicloudAppStateCaptureExcludedItem -SourcePath $SourcePath -ExcludeNames $ExcludeNames -ExcludePathPatterns $ExcludePathPatterns -ExcludeFilePatterns $ExcludeFilePatterns) {
        return $false
    }

    $item = Get-Item -LiteralPath $SourcePath -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) {
        return $false
    }

    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        return $false
    }

    if ($item.PSIsContainer) {
        Ensure-ProdicloudAppStateDirectory -Path $DestinationPath
        $copiedAny = $false
        foreach ($child in @(Get-ChildItem -LiteralPath $SourcePath -Force -ErrorAction SilentlyContinue)) {
            $childDestination = Join-Path $DestinationPath $child.Name
            if (Copy-ProdicloudAppStateCaptureTree -SourcePath ([string]$child.FullName) -DestinationPath $childDestination -ExcludeNames $ExcludeNames -ExcludePathPatterns $ExcludePathPatterns -ExcludeFilePatterns $ExcludeFilePatterns) {
                $copiedAny = $true
            }
        }
        return $copiedAny
    }

    Ensure-ProdicloudAppStateDirectory -Path (Split-Path -Path $DestinationPath -Parent)
    try {
        Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force -ErrorAction Stop
        return $true
    }
    catch {
        Write-Host ("app-state-capture-file-skip => source={0}; destination={1}; reason={2}" -f [string]$SourcePath, [string]$DestinationPath, $_.Exception.Message)
        return $false
    }
}

function Get-ProdicloudAppStateScratchRootPath {
    param(
        [string]$Prefix
    )

    $normalizedPrefix = if ([string]::IsNullOrWhiteSpace([string]$Prefix)) { 'app-state' } else { ([string]$Prefix -replace '[^A-Za-z0-9\-]', '-').Trim('-') }
    if ([string]::IsNullOrWhiteSpace([string]$normalizedPrefix)) {
        $normalizedPrefix = 'app-state'
    }

    foreach ($basePath in @('C:\t', 'C:\Windows\Temp')) {
        try {
            Ensure-ProdicloudAppStateDirectory -Path $basePath
            return (Join-Path $basePath ('{0}-{1}' -f $normalizedPrefix, ([guid]::NewGuid().ToString('N'))))
        }
        catch {
        }
    }

    return (Join-Path $env:TEMP ('{0}-{1}' -f $normalizedPrefix, ([guid]::NewGuid().ToString('N'))))
}

function Normalize-ProdicloudAppStateComparablePath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace([string]$Path)) {
        return ''
    }

    $normalizedPath = ([string]$Path).Trim().Replace('/', '\')
    $uncPrefix = ''
    if ($normalizedPath.StartsWith('\\')) {
        $uncPrefix = '\\'
        $normalizedPath = $normalizedPath.TrimStart('\')
    }

    $normalizedPath = [regex]::Replace($normalizedPath, '\\{2,}', '\')
    return ($uncPrefix + $normalizedPath).TrimEnd('\')
}

function Get-ProdicloudAppStateRelativePathFromBase {
    param(
        [string]$BasePath,
        [string]$CandidatePath
    )

    $normalizedBasePath = [string](Normalize-ProdicloudAppStateComparablePath -Path $BasePath)
    $normalizedCandidatePath = [string](Normalize-ProdicloudAppStateComparablePath -Path $CandidatePath)
    if ([string]::IsNullOrWhiteSpace([string]$normalizedBasePath) -or [string]::IsNullOrWhiteSpace([string]$normalizedCandidatePath)) {
        return ''
    }

    if ([string]::Equals([string]$normalizedBasePath, [string]$normalizedCandidatePath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return ''
    }

    $normalizedPrefix = $normalizedBasePath + '\'
    if (-not $normalizedCandidatePath.StartsWith($normalizedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return ''
    }

    return [string]$normalizedCandidatePath.Substring($normalizedBasePath.Length).TrimStart('\')
}

function Resolve-ProdicloudAppStateReplayDestinationPaths {
    param(
        [string]$BasePath,
        [string]$RelativeOrAbsolutePath
    )

    if ([string]::IsNullOrWhiteSpace([string]$RelativeOrAbsolutePath)) {
        return @()
    }

    $candidatePath = [string]$RelativeOrAbsolutePath
    if (-not [System.IO.Path]::IsPathRooted($candidatePath) -and -not [string]::IsNullOrWhiteSpace([string]$BasePath)) {
        $candidatePath = Join-Path $BasePath $candidatePath
    }

    $hasWildcard = ($candidatePath.IndexOf('*', [System.StringComparison]::Ordinal) -ge 0 -or $candidatePath.IndexOf('?', [System.StringComparison]::Ordinal) -ge 0)
    if ($hasWildcard) {
        return @(
            Get-ChildItem -Path $candidatePath -Force -ErrorAction SilentlyContinue |
                Sort-Object FullName |
                Select-Object -ExpandProperty FullName -Unique
        )
    }

    return @([string]$candidatePath)
}

function Get-ProdicloudAppStateFileHashValue {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace([string]$Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return ''
    }

    try {
        $hash = Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop
        if ($null -eq $hash -or $hash.PSObject.Properties.Match('Hash').Count -lt 1) {
            return ''
        }

        return ([string]$hash.Hash).Trim().ToLowerInvariant()
    }
    catch {
        return ''
    }
}

function Get-ProdicloudAppStateNormalizedRegLines {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace([string]$Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }

    $content = [string](Get-Content -LiteralPath $Path -Raw -Encoding Unicode -ErrorAction SilentlyContinue)
    if ([string]::IsNullOrWhiteSpace([string]$content)) {
        $content = [string](Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue)
    }
    if ([string]::IsNullOrWhiteSpace([string]$content)) {
        return @()
    }

    $logicalLines = New-Object 'System.Collections.Generic.List[string]'
    $buffer = ''
    foreach ($rawLine in @($content -split "`r?`n")) {
        $trimmedEnd = [string]$rawLine.TrimEnd()
        if ([string]::IsNullOrWhiteSpace([string]$buffer)) {
            $buffer = [string]$trimmedEnd
        }
        else {
            $buffer = ('{0}{1}' -f [string]$buffer, [string]$trimmedEnd.TrimStart())
        }

        if ($buffer.EndsWith('\')) {
            $buffer = $buffer.Substring(0, ($buffer.Length - 1))
            continue
        }

        $line = [string]$buffer.Trim()
        $buffer = ''
        if ([string]::IsNullOrWhiteSpace([string]$line)) {
            continue
        }
        if ([string]::Equals([string]$line, 'Windows Registry Editor Version 5.00', [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $logicalLines.Add($line) | Out-Null
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$buffer)) {
        $line = [string]$buffer.Trim()
        if (-not [string]::IsNullOrWhiteSpace([string]$line) -and -not [string]::Equals([string]$line, 'Windows Registry Editor Version 5.00', [System.StringComparison]::OrdinalIgnoreCase)) {
            $logicalLines.Add($line) | Out-Null
        }
    }

    return @($logicalLines.ToArray())
}

function Backup-ProdicloudTaskUserRegistry {
    param(
        [string]$RegistryPath,
        [psobject]$ProfileTarget,
        [string]$BackupPath
    )

    $mountInfo = Get-ProdicloudMountedUserHive -ProfilePath ([string]$ProfileTarget.ProfilePath) -PreferredLabel ([string]$ProfileTarget.UserName)
    if ($null -eq $mountInfo) {
        return $false
    }

    try {
        $canonicalPath = Convert-ProdicloudAppStateRegistryPathToCanonicalRoot -RegistryPath $RegistryPath
        if ([string]::IsNullOrWhiteSpace([string]$canonicalPath) -or
            -not $canonicalPath.StartsWith('HKEY_CURRENT_USER', [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }

        $mountedRoot = $canonicalPath -replace '^HKEY_CURRENT_USER', ([string]$mountInfo.Root)
        $tempExportPath = Join-Path ([System.IO.Path]::GetTempPath()) ('prodicloud-reg-export-{0}.reg' -f ([guid]::NewGuid().ToString('N')))
        try {
            if (-not (Invoke-ProdicloudRegExport -RegistryPath $mountedRoot -DestinationPath $tempExportPath)) {
                return $false
            }

            return (Convert-ProdicloudAppStateRegRoot -SourcePath $tempExportPath -SourceRoot ([string]$mountInfo.Root) -DestinationRoot 'HKEY_CURRENT_USER' -DestinationPath $BackupPath)
        }
        finally {
            Remove-Item -LiteralPath $tempExportPath -Force -ErrorAction SilentlyContinue
        }
    }
    finally {
        Close-ProdicloudMountedUserHive -MountInfo $mountInfo
    }
}

function Restore-ProdicloudTaskUserRegistryFromBackup {
    param(
        [string]$BackupPath,
        [string]$RegistryPath,
        [psobject]$ProfileTarget
    )

    $mountInfo = Get-ProdicloudMountedUserHive -ProfilePath ([string]$ProfileTarget.ProfilePath) -PreferredLabel ([string]$ProfileTarget.UserName)
    if ($null -eq $mountInfo) {
        return $false
    }

    try {
        $tempImportPath = Join-Path ([System.IO.Path]::GetTempPath()) ('prodicloud-reg-import-{0}.reg' -f ([guid]::NewGuid().ToString('N')))
        try {
            if (-not (Convert-ProdicloudAppStateRegRoot -SourcePath $BackupPath -SourceRoot 'HKEY_CURRENT_USER' -DestinationRoot ([string]$mountInfo.Root) -DestinationPath $tempImportPath)) {
                return $false
            }

            cmd.exe /d /c ('reg import "{0}" >nul 2>&1' -f $tempImportPath) | Out-Null
            return ([int]$LASTEXITCODE -eq 0)
        }
        finally {
            Remove-Item -LiteralPath $tempImportPath -Force -ErrorAction SilentlyContinue
        }
    }
    finally {
        Close-ProdicloudMountedUserHive -MountInfo $mountInfo
    }
}

function Remove-ProdicloudTaskRegistryPath {
    param(
        [string]$RegistryPath,
        [string]$Scope,
        [psobject]$ProfileTarget
    )

    if ([string]::Equals([string]$Scope, 'machine', [System.StringComparison]::OrdinalIgnoreCase)) {
        $providerPath = Convert-ProdicloudAppStateRegistryPathToProviderPath -RegistryPath $RegistryPath
        if (-not [string]::IsNullOrWhiteSpace([string]$providerPath) -and (Test-Path -LiteralPath $providerPath)) {
            Remove-Item -LiteralPath $providerPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        return
    }

    $mountInfo = Get-ProdicloudMountedUserHive -ProfilePath ([string]$ProfileTarget.ProfilePath) -PreferredLabel ([string]$ProfileTarget.UserName)
    if ($null -eq $mountInfo) {
        return
    }

    try {
        $canonicalPath = Convert-ProdicloudAppStateRegistryPathToCanonicalRoot -RegistryPath $RegistryPath
        if ([string]::IsNullOrWhiteSpace([string]$canonicalPath) -or
            -not $canonicalPath.StartsWith('HKEY_CURRENT_USER', [System.StringComparison]::OrdinalIgnoreCase)) {
            return
        }

        $mountedProviderPath = Convert-ProdicloudAppStateRegistryPathToProviderPath -RegistryPath ($canonicalPath -replace '^HKEY_CURRENT_USER', ([string]$mountInfo.Root))
        if (-not [string]::IsNullOrWhiteSpace([string]$mountedProviderPath) -and (Test-Path -LiteralPath $mountedProviderPath)) {
            Remove-Item -LiteralPath $mountedProviderPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    finally {
        Close-ProdicloudMountedUserHive -MountInfo $mountInfo
    }
}

function Get-ProdicloudTaskAppStateReplayOperations {
    param(
        [string]$ExpandedRoot,
        [psobject]$Manifest,
        [object[]]$ProfileTargets = @()
    )

    $operations = New-Object 'System.Collections.Generic.List[object]'
    $seen = @{}

    foreach ($entry in @($Manifest.machineDirectories)) {
        if ($null -eq $entry) { continue }
        $sourcePath = Join-Path $ExpandedRoot ([string]$entry.sourcePath)
        $destinationPath = [string]$entry.destinationPath
        if (-not (Test-Path -LiteralPath $sourcePath) -or [string]::IsNullOrWhiteSpace([string]$destinationPath)) { continue }
        $key = ('directory|machine|{0}' -f $destinationPath.TrimEnd('\').ToLowerInvariant())
        if ($seen.ContainsKey($key)) { continue }
        $operations.Add([pscustomobject]@{
            Kind = 'directory'
            Scope = 'machine'
            SourcePath = [string]$sourcePath
            DestinationPath = [string]$destinationPath
            RegistryPath = ''
            ProfileLabel = ''
            UserName = ''
            ProfilePath = ''
            DistributionAllowList = @()
        }) | Out-Null
        $seen[$key] = $true
    }

    foreach ($entry in @($Manifest.machineFiles)) {
        if ($null -eq $entry) { continue }
        $sourcePath = Join-Path $ExpandedRoot ([string]$entry.sourcePath)
        $destinationPath = [string]$entry.destinationPath
        if (-not (Test-Path -LiteralPath $sourcePath) -or [string]::IsNullOrWhiteSpace([string]$destinationPath)) { continue }
        $key = ('file|machine|{0}' -f $destinationPath.ToLowerInvariant())
        if ($seen.ContainsKey($key)) { continue }
        $operations.Add([pscustomobject]@{
            Kind = 'file'
            Scope = 'machine'
            SourcePath = [string]$sourcePath
            DestinationPath = [string]$destinationPath
            RegistryPath = ''
            ProfileLabel = ''
            UserName = ''
            ProfilePath = ''
            DistributionAllowList = @()
        }) | Out-Null
        $seen[$key] = $true
    }

    foreach ($entry in @($Manifest.profileDirectories)) {
        if ($null -eq $entry) { continue }
        $sourcePath = Join-Path $ExpandedRoot ([string]$entry.sourcePath)
        $relativeDestinationPath = [string]$entry.relativeDestinationPath
        if (-not (Test-Path -LiteralPath $sourcePath) -or [string]::IsNullOrWhiteSpace([string]$relativeDestinationPath)) { continue }

        foreach ($profileTarget in @(Get-ProdicloudAppStateSelectedProfileTargets -ProfileTargets $ProfileTargets -Entry $entry)) {
            $destinationPaths = @(Resolve-ProdicloudAppStateReplayDestinationPaths -BasePath ([string]$profileTarget.ProfilePath) -RelativeOrAbsolutePath $relativeDestinationPath)
            if (@($destinationPaths).Count -lt 1) {
                Write-Warning ("app-state-profile-directory-target-skip => {0} => no-match for {1}" -f [string]$profileTarget.Label, [string]$relativeDestinationPath)
                continue
            }

            foreach ($destinationPath in @($destinationPaths)) {
                $key = ('directory|profile|{0}|{1}' -f [string]$profileTarget.Label, ([string]$destinationPath).TrimEnd('\').ToLowerInvariant())
                if ($seen.ContainsKey($key)) { continue }
                $operations.Add([pscustomobject]@{
                    Kind = 'directory'
                    Scope = 'profile'
                    SourcePath = [string]$sourcePath
                    DestinationPath = [string]$destinationPath
                    RegistryPath = ''
                    ProfileLabel = [string]$profileTarget.Label
                    UserName = [string]$profileTarget.UserName
                    ProfilePath = [string]$profileTarget.ProfilePath
                    DistributionAllowList = @()
                }) | Out-Null
                $seen[$key] = $true
            }
        }
    }

    foreach ($entry in @($Manifest.profileFiles)) {
        if ($null -eq $entry) { continue }
        $sourcePath = Join-Path $ExpandedRoot ([string]$entry.sourcePath)
        $relativeDestinationPath = [string]$entry.relativeDestinationPath
        if (-not (Test-Path -LiteralPath $sourcePath) -or [string]::IsNullOrWhiteSpace([string]$relativeDestinationPath)) { continue }

        foreach ($profileTarget in @(Get-ProdicloudAppStateSelectedProfileTargets -ProfileTargets $ProfileTargets -Entry $entry)) {
            $destinationPaths = @(Resolve-ProdicloudAppStateReplayDestinationPaths -BasePath ([string]$profileTarget.ProfilePath) -RelativeOrAbsolutePath $relativeDestinationPath)
            if (@($destinationPaths).Count -lt 1) {
                Write-Warning ("app-state-profile-file-target-skip => {0} => no-match for {1}" -f [string]$profileTarget.Label, [string]$relativeDestinationPath)
                continue
            }

            foreach ($destinationPath in @($destinationPaths)) {
                $key = ('file|profile|{0}|{1}' -f [string]$profileTarget.Label, ([string]$destinationPath).ToLowerInvariant())
                if ($seen.ContainsKey($key)) { continue }
                $operations.Add([pscustomobject]@{
                    Kind = 'file'
                    Scope = 'profile'
                    SourcePath = [string]$sourcePath
                    DestinationPath = [string]$destinationPath
                    RegistryPath = ''
                    ProfileLabel = [string]$profileTarget.Label
                    UserName = [string]$profileTarget.UserName
                    ProfilePath = [string]$profileTarget.ProfilePath
                    DistributionAllowList = @()
                }) | Out-Null
                $seen[$key] = $true
            }
        }
    }

    foreach ($entry in @($Manifest.registryImports)) {
        if ($null -eq $entry) { continue }
        $scope = if ($entry.PSObject.Properties.Match('scope').Count -gt 0) { [string]$entry.scope } else { '' }
        $registryPath = if ($entry.PSObject.Properties.Match('registryPath').Count -gt 0) { [string]$entry.registryPath } else { '' }
        $sourcePath = Join-Path $ExpandedRoot ([string]$entry.sourcePath)
        $distributionAllowList = @(
            @($entry.distributionAllowList) |
                ForEach-Object { [string]$_ } |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
        )
        if ([string]::IsNullOrWhiteSpace([string]$registryPath) -or -not (Test-Path -LiteralPath $sourcePath)) { continue }
        if ([string]::Equals([string]$scope, 'machine', [System.StringComparison]::OrdinalIgnoreCase)) {
            $key = ('registry|machine|{0}' -f $registryPath.ToLowerInvariant())
            if ($seen.ContainsKey($key)) { continue }
            $operations.Add([pscustomobject]@{
                Kind = 'registry'
                Scope = 'machine'
                SourcePath = [string]$sourcePath
                DestinationPath = ''
                RegistryPath = [string]$registryPath
                ProfileLabel = ''
                UserName = ''
                ProfilePath = ''
                DistributionAllowList = @($distributionAllowList)
            }) | Out-Null
            $seen[$key] = $true
            continue
        }

        foreach ($profileTarget in @(Get-ProdicloudAppStateSelectedProfileTargets -ProfileTargets $ProfileTargets -Entry $entry)) {
            if (-not (Test-ProdicloudAppStateProfileRegistryReplayAvailable -ProfileTarget $profileTarget)) {
                Write-Host ("app-state-user-registry-skip => {0} => no-hive-file" -f [string]$profileTarget.Label)
                continue
            }

            $key = ('registry|profile|{0}|{1}' -f [string]$profileTarget.Label, $registryPath.ToLowerInvariant())
            if ($seen.ContainsKey($key)) { continue }
            $operations.Add([pscustomobject]@{
                Kind = 'registry'
                Scope = 'profile'
                SourcePath = [string]$sourcePath
                DestinationPath = ''
                RegistryPath = [string]$registryPath
                ProfileLabel = [string]$profileTarget.Label
                UserName = [string]$profileTarget.UserName
                ProfilePath = [string]$profileTarget.ProfilePath
                DistributionAllowList = @($distributionAllowList)
            }) | Out-Null
            $seen[$key] = $true
        }
    }

    return @($operations.ToArray())
}

function Invoke-ProdicloudTaskAppStateReplayOperations {
    param([object[]]$Operations = @())

    $machineRegistryImports = 0
    $userRegistryImports = 0
    $machineDirectoryCopies = 0
    $machineFileCopies = 0
    $profileDirectoryCopies = 0
    $profileFileCopies = 0

    foreach ($operation in @($Operations)) {
        if ($null -eq $operation) {
            continue
        }

        Set-ProdicloudAppStateOperationReplayStatus -Operation $operation -Status 'applied' -Reason ''
        switch ([string]$operation.Kind) {
            'directory' {
                if (-not (Test-Path -LiteralPath ([string]$operation.SourcePath) -PathType Container)) {
                    Write-Host ("app-state-directory-skip => {0}" -f [string]$operation.SourcePath)
                    Set-ProdicloudAppStateOperationReplayStatus -Operation $operation -Status 'skipped' -Reason 'source-missing'
                    continue
                }

                $copyResult = Copy-ProdicloudAppStateDirectoryContents -SourcePath ([string]$operation.SourcePath) -DestinationPath ([string]$operation.DestinationPath)
                if ([bool]$copyResult.SkippedAny) {
                    Set-ProdicloudAppStateOperationReplayStatus -Operation $operation -Status 'skipped' -Reason $(if ([string]::IsNullOrWhiteSpace([string]$copyResult.Reason)) { 'directory-copy-skipped' } else { [string]$copyResult.Reason })
                    continue
                }

                if ([bool]$copyResult.CopiedAny -or -not (Get-ChildItem -LiteralPath ([string]$operation.SourcePath) -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) {
                    if ([string]::Equals([string]$operation.Scope, 'machine', [System.StringComparison]::OrdinalIgnoreCase)) {
                        $machineDirectoryCopies++
                    }
                    else {
                        $profileDirectoryCopies++
                    }
                }
            }
            'file' {
                if (-not (Test-Path -LiteralPath ([string]$operation.SourcePath) -PathType Leaf)) {
                    Write-Host ("app-state-file-skip => {0}" -f [string]$operation.SourcePath)
                    Set-ProdicloudAppStateOperationReplayStatus -Operation $operation -Status 'skipped' -Reason 'source-missing'
                    continue
                }

                $copyResult = Copy-ProdicloudAppStateFile -SourcePath ([string]$operation.SourcePath) -DestinationPath ([string]$operation.DestinationPath)
                if (-not [bool]$copyResult.Copied) {
                    Set-ProdicloudAppStateOperationReplayStatus -Operation $operation -Status 'skipped' -Reason $(if ([string]::IsNullOrWhiteSpace([string]$copyResult.Reason)) { 'file-copy-skipped' } else { [string]$copyResult.Reason })
                    continue
                }

                if ([bool]$copyResult.Copied) {
                    if ([string]::Equals([string]$operation.Scope, 'machine', [System.StringComparison]::OrdinalIgnoreCase)) {
                        $machineFileCopies++
                    }
                    else {
                        $profileFileCopies++
                    }
                }
            }
            'registry' {
                if (-not (Test-Path -LiteralPath ([string]$operation.SourcePath) -PathType Leaf)) {
                    Write-Host ("app-state-registry-skip => {0}" -f [string]$operation.SourcePath)
                    Set-ProdicloudAppStateOperationReplayStatus -Operation $operation -Status 'skipped' -Reason 'source-missing'
                    continue
                }

                if ([string]::Equals([string]$operation.Scope, 'machine', [System.StringComparison]::OrdinalIgnoreCase)) {
                    if (Invoke-ProdicloudRegImport -SourcePath ([string]$operation.SourcePath)) {
                        $machineRegistryImports++
                    }
                    else {
                        Write-Host ("app-state-machine-registry-import-skip => {0}" -f [string]$operation.SourcePath)
                        Set-ProdicloudAppStateOperationReplayStatus -Operation $operation -Status 'skipped' -Reason 'registry-import-failed'
                    }
                    continue
                }

                $profileTarget = [pscustomobject]@{
                    Label = [string]$operation.ProfileLabel
                    UserName = [string]$operation.UserName
                    ProfilePath = [string]$operation.ProfilePath
                }
                $mountInfo = Get-ProdicloudMountedUserHive -ProfilePath ([string]$profileTarget.ProfilePath) -PreferredLabel ([string]$profileTarget.UserName)
                if ($null -eq $mountInfo) {
                    Write-Host ("app-state-user-registry-skip => {0} => hive-unavailable" -f [string]$profileTarget.Label)
                    Set-ProdicloudAppStateOperationReplayStatus -Operation $operation -Status 'skipped' -Reason 'hive-unavailable'
                    continue
                }

                $rewrittenPath = Join-Path ([System.IO.Path]::GetTempPath()) (('prodicloud-reg-rewrite-{0}-{1}.reg' -f ([guid]::NewGuid().ToString('N')), ([string]$profileTarget.UserName -replace '[^A-Za-z0-9]', '_')))
                try {
                    if (@($operation.DistributionAllowList).Count -gt 0) {
                        Invoke-ProdicloudAppStateWslRegistryPurge -MountedUserRegistryRoot ([string]$mountInfo.Root) -RegistryPath 'HKCU\Software\Microsoft\Windows\CurrentVersion\Lxss' -DistributionAllowList @($operation.DistributionAllowList)
                    }
                    if (-not (Convert-ProdicloudAppStateRegRoot -SourcePath ([string]$operation.SourcePath) -SourceRoot 'HKEY_CURRENT_USER' -DestinationRoot ([string]$mountInfo.Root) -DestinationPath $rewrittenPath)) {
                        Write-Host ("app-state-user-registry-skip => {0} => rewrite-failed" -f [string]$profileTarget.Label)
                        Set-ProdicloudAppStateOperationReplayStatus -Operation $operation -Status 'skipped' -Reason 'rewrite-failed'
                        continue
                    }

                    if (Invoke-ProdicloudRegImport -SourcePath $rewrittenPath) {
                        $userRegistryImports++
                    }
                    else {
                        Write-Host ("app-state-user-registry-import-skip => {0} => {1}" -f [string]$profileTarget.Label, [string]$operation.SourcePath)
                        Set-ProdicloudAppStateOperationReplayStatus -Operation $operation -Status 'skipped' -Reason 'registry-import-failed'
                    }
                }
                finally {
                    Remove-Item -LiteralPath $rewrittenPath -Force -ErrorAction SilentlyContinue
                    Close-ProdicloudMountedUserHive -MountInfo $mountInfo
                }
            }
        }
    }

    $skippedCount = @(
        @($Operations) | Where-Object {
            $status = Get-ProdicloudAppStateOperationReplayStatus -Operation $_
            [string]$status.Status -eq 'skipped'
        }
    ).Count

    return [pscustomobject]@{
        MachineRegistryImports = [int]$machineRegistryImports
        UserRegistryImports = [int]$userRegistryImports
        MachineDirectoryCopies = [int]$machineDirectoryCopies
        MachineFileCopies = [int]$machineFileCopies
        ProfileDirectoryCopies = [int]$profileDirectoryCopies
        ProfileFileCopies = [int]$profileFileCopies
        SkippedCount = [int]$skippedCount
    }
}

function Backup-ProdicloudTaskAppStateOperations {
    param(
        [object[]]$Operations = @(),
        [string]$BackupRoot
    )

    Ensure-ProdicloudAppStateDirectory -Path $BackupRoot
    $records = New-Object 'System.Collections.Generic.List[object]'
    $index = 0
    foreach ($operation in @($Operations)) {
        if ($null -eq $operation) {
            continue
        }

        $index++
        $backupBaseName = ('{0:D3}-{1}-{2}' -f $index, [string]$operation.Scope, [string]$operation.Kind)
        $record = [ordered]@{
            Kind = [string]$operation.Kind
            Scope = [string]$operation.Scope
            DestinationPath = [string]$operation.DestinationPath
            RegistryPath = [string]$operation.RegistryPath
            ProfileLabel = [string]$operation.ProfileLabel
            UserName = [string]$operation.UserName
            ProfilePath = [string]$operation.ProfilePath
            BackupPath = ''
            Existed = $false
            BackupStatus = 'captured'
            BackupReason = ''
        }

        switch ([string]$operation.Kind) {
            'file' {
                $destinationPath = [string]$operation.DestinationPath
                if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
                    $backupPath = Join-Path (Join-Path $BackupRoot 'files') ((ConvertTo-ProdicloudAppStateCaptureSafeName -Value $backupBaseName) + [System.IO.Path]::GetExtension($destinationPath))
                    Ensure-ProdicloudAppStateDirectory -Path (Split-Path -Path $backupPath -Parent)
                    $copyResult = Copy-ProdicloudAppStateFile -SourcePath $destinationPath -DestinationPath $backupPath
                    $record.Existed = $true
                    if ([bool]$copyResult.Copied) {
                        $record.BackupPath = [string]$backupPath
                    }
                    else {
                        $record.BackupStatus = 'skipped'
                        $record.BackupReason = $(if ([string]::IsNullOrWhiteSpace([string]$copyResult.Reason)) { 'backup-copy-skipped' } else { [string]$copyResult.Reason })
                    }
                }
                else {
                    $record.BackupStatus = 'not-required'
                    $record.BackupReason = 'destination-missing'
                }
            }
            'directory' {
                $destinationPath = [string]$operation.DestinationPath
                if (Test-Path -LiteralPath $destinationPath -PathType Container) {
                    $backupPath = Join-Path (Join-Path $BackupRoot 'directories') (ConvertTo-ProdicloudAppStateCaptureSafeName -Value $backupBaseName)
                    Ensure-ProdicloudAppStateDirectory -Path (Split-Path -Path $backupPath -Parent)
                    $copyResult = Copy-ProdicloudAppStateDirectoryContents -SourcePath $destinationPath -DestinationPath $backupPath
                    $record.Existed = $true
                    if (-not [bool]$copyResult.SkippedAny) {
                        $record.BackupPath = [string]$backupPath
                    }
                    else {
                        $record.BackupStatus = 'skipped'
                        $record.BackupReason = $(if ([string]::IsNullOrWhiteSpace([string]$copyResult.Reason)) { 'backup-copy-skipped' } else { [string]$copyResult.Reason })
                    }
                }
                else {
                    $record.BackupStatus = 'not-required'
                    $record.BackupReason = 'destination-missing'
                }
            }
            'registry' {
                $backupPath = Join-Path (Join-Path $BackupRoot 'registry') ((ConvertTo-ProdicloudAppStateCaptureSafeName -Value ($backupBaseName + '-' + [string]$operation.RegistryPath)) + '.reg')
                $exported = $false
                if ([string]::Equals([string]$operation.Scope, 'machine', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $canonicalRegistryPath = Convert-ProdicloudAppStateRegistryPathToCanonicalRoot -RegistryPath ([string]$operation.RegistryPath)
                    $providerPath = Convert-ProdicloudAppStateRegistryPathToProviderPath -RegistryPath $canonicalRegistryPath
                    if (-not [string]::IsNullOrWhiteSpace([string]$providerPath) -and (Test-Path -LiteralPath $providerPath)) {
                        $exported = Invoke-ProdicloudRegExport -RegistryPath $canonicalRegistryPath -DestinationPath $backupPath
                    }
                }
                else {
                    $profileTarget = [pscustomobject]@{
                        Label = [string]$operation.ProfileLabel
                        UserName = [string]$operation.UserName
                        ProfilePath = [string]$operation.ProfilePath
                    }
                    $exported = Backup-ProdicloudTaskUserRegistry -RegistryPath ([string]$operation.RegistryPath) -ProfileTarget $profileTarget -BackupPath $backupPath
                }

                if ($exported) {
                    $record.BackupPath = [string]$backupPath
                    $record.Existed = $true
                }
                elseif ([string]::Equals([string]$operation.Scope, 'machine', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $record.BackupStatus = 'not-required'
                    $record.BackupReason = 'registry-missing'
                }
                else {
                    $record.Existed = [bool](Test-ProdicloudAppStateProfileRegistryReplayAvailable -ProfileTarget ([pscustomobject]@{
                        Label = [string]$operation.ProfileLabel
                        UserName = [string]$operation.UserName
                        ProfilePath = [string]$operation.ProfilePath
                    }))
                    $record.BackupStatus = $(if ([bool]$record.Existed) { 'skipped' } else { 'not-required' })
                    $record.BackupReason = $(if ([bool]$record.Existed) { 'backup-export-skipped' } else { 'hive-unavailable' })
                }
            }
        }

        $records.Add([pscustomobject]$record) | Out-Null
    }

    return @($records.ToArray())
}

function Test-ProdicloudTaskAppStateDirectoryMatches {
    param(
        [string]$SourcePath,
        [string]$DestinationPath
    )

    if ([string]::IsNullOrWhiteSpace([string]$SourcePath) -or -not (Test-Path -LiteralPath $SourcePath -PathType Container)) {
        return [pscustomobject]@{ Success = $false; Reason = 'source-missing' }
    }
    if ([string]::IsNullOrWhiteSpace([string]$DestinationPath) -or -not (Test-Path -LiteralPath $DestinationPath -PathType Container)) {
        return [pscustomobject]@{ Success = $false; Reason = 'destination-missing' }
    }

    $normalizedSourceRoot = [string](Normalize-ProdicloudAppStateComparablePath -Path $SourcePath)
    foreach ($directory in @(Get-ChildItem -LiteralPath $SourcePath -Recurse -Directory -Force -ErrorAction SilentlyContinue | Sort-Object FullName)) {
        $relativePath = [string](Normalize-ProdicloudAppStateComparablePath -Path ([string]$directory.FullName))
        if ($relativePath.StartsWith($normalizedSourceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            $relativePath = $relativePath.Substring($normalizedSourceRoot.Length).TrimStart('\')
        }
        if ([string]::IsNullOrWhiteSpace([string]$relativePath)) {
            continue
        }

        $destinationChild = Join-Path $DestinationPath $relativePath
        if (-not (Test-Path -LiteralPath $destinationChild -PathType Container)) {
            return [pscustomobject]@{ Success = $false; Reason = ('missing-directory:{0}' -f [string]$relativePath) }
        }
    }

    foreach ($file in @(Get-ChildItem -LiteralPath $SourcePath -Recurse -File -Force -ErrorAction SilentlyContinue | Sort-Object FullName)) {
        $relativePath = [string](Normalize-ProdicloudAppStateComparablePath -Path ([string]$file.FullName))
        if ($relativePath.StartsWith($normalizedSourceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            $relativePath = $relativePath.Substring($normalizedSourceRoot.Length).TrimStart('\')
        }
        if ([string]::IsNullOrWhiteSpace([string]$relativePath)) {
            continue
        }

        $destinationChild = Join-Path $DestinationPath $relativePath
        if (-not (Test-Path -LiteralPath $destinationChild -PathType Leaf)) {
            return [pscustomobject]@{ Success = $false; Reason = ('missing-file:{0}' -f [string]$relativePath) }
        }

        $sourceHash = Get-ProdicloudAppStateFileHashValue -Path ([string]$file.FullName)
        $destinationHash = Get-ProdicloudAppStateFileHashValue -Path $destinationChild
        if ([string]::IsNullOrWhiteSpace([string]$sourceHash) -or -not [string]::Equals([string]$sourceHash, [string]$destinationHash, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{ Success = $false; Reason = ('hash-mismatch:{0}' -f [string]$relativePath) }
        }
    }

    return [pscustomobject]@{ Success = $true; Reason = '' }
}

function Test-ProdicloudTaskAppStateRegistryMatches {
    param(
        [string]$SourcePath,
        [string]$RegistryPath,
        [string]$Scope,
        [psobject]$ProfileTarget
    )

    if ([string]::IsNullOrWhiteSpace([string]$SourcePath) -or -not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        return [pscustomobject]@{ Success = $false; Reason = 'source-missing' }
    }

    $tempExportPath = Join-Path ([System.IO.Path]::GetTempPath()) ('prodicloud-reg-verify-{0}.reg' -f ([guid]::NewGuid().ToString('N')))
    $exported = $false
    try {
        if ([string]::Equals([string]$Scope, 'machine', [System.StringComparison]::OrdinalIgnoreCase)) {
            $canonicalRegistryPath = Convert-ProdicloudAppStateRegistryPathToCanonicalRoot -RegistryPath $RegistryPath
            $providerPath = Convert-ProdicloudAppStateRegistryPathToProviderPath -RegistryPath $canonicalRegistryPath
            if (-not [string]::IsNullOrWhiteSpace([string]$providerPath) -and (Test-Path -LiteralPath $providerPath)) {
                $exported = Invoke-ProdicloudRegExport -RegistryPath $canonicalRegistryPath -DestinationPath $tempExportPath
            }
        }
        else {
            $exported = Backup-ProdicloudTaskUserRegistry -RegistryPath $RegistryPath -ProfileTarget $ProfileTarget -BackupPath $tempExportPath
        }

        if (-not $exported) {
            return [pscustomobject]@{ Success = $false; Reason = 'registry-export-failed' }
        }

        $expectedLines = @(Get-ProdicloudAppStateNormalizedRegLines -Path $SourcePath)
        $actualLines = @(Get-ProdicloudAppStateNormalizedRegLines -Path $tempExportPath)
        $actualSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($line in @($actualLines)) {
            [void]$actualSet.Add([string]$line)
        }

        foreach ($line in @($expectedLines)) {
            if (-not $actualSet.Contains([string]$line)) {
                return [pscustomobject]@{ Success = $false; Reason = ('registry-line-missing:{0}' -f [string]$line) }
            }
        }

        return [pscustomobject]@{ Success = $true; Reason = '' }
    }
    finally {
        Remove-Item -LiteralPath $tempExportPath -Force -ErrorAction SilentlyContinue
    }
}

function Test-ProdicloudTaskAppStateOperations {
    param([object[]]$Operations = @())

    $items = New-Object 'System.Collections.Generic.List[object]'
    foreach ($operation in @($Operations)) {
        if ($null -eq $operation) {
            continue
        }

        $status = 'verified'
        $reason = ''
        $replayStatus = Get-ProdicloudAppStateOperationReplayStatus -Operation $operation
        if ([string]$replayStatus.Status -eq 'skipped') {
            $status = 'skipped'
            $reason = [string]$replayStatus.Reason
        }
        else {
            switch ([string]$operation.Kind) {
                'file' {
                    if (-not (Test-Path -LiteralPath ([string]$operation.DestinationPath) -PathType Leaf)) {
                        $status = 'mismatch'
                        $reason = 'destination-missing'
                    }
                    else {
                        $sourceHash = Get-ProdicloudAppStateFileHashValue -Path ([string]$operation.SourcePath)
                        $destinationHash = Get-ProdicloudAppStateFileHashValue -Path ([string]$operation.DestinationPath)
                        if ([string]::IsNullOrWhiteSpace([string]$sourceHash) -or -not [string]::Equals([string]$sourceHash, [string]$destinationHash, [System.StringComparison]::OrdinalIgnoreCase)) {
                            $status = 'mismatch'
                            $reason = 'hash-mismatch'
                        }
                    }
                }
                'directory' {
                    $directoryMatch = Test-ProdicloudTaskAppStateDirectoryMatches -SourcePath ([string]$operation.SourcePath) -DestinationPath ([string]$operation.DestinationPath)
                    if (-not [bool]$directoryMatch.Success) {
                        $status = 'mismatch'
                        $reason = [string]$directoryMatch.Reason
                    }
                }
                'registry' {
                    $profileTarget = [pscustomobject]@{
                        Label = [string]$operation.ProfileLabel
                        UserName = [string]$operation.UserName
                        ProfilePath = [string]$operation.ProfilePath
                    }
                    $registryMatch = Test-ProdicloudTaskAppStateRegistryMatches -SourcePath ([string]$operation.SourcePath) -RegistryPath ([string]$operation.RegistryPath) -Scope ([string]$operation.Scope) -ProfileTarget $profileTarget
                    if (-not [bool]$registryMatch.Success) {
                        $status = 'mismatch'
                        $reason = [string]$registryMatch.Reason
                    }
                }
            }
        }

        $items.Add([pscustomobject]@{
            Kind = [string]$operation.Kind
            Scope = [string]$operation.Scope
            DestinationPath = [string]$operation.DestinationPath
            RegistryPath = [string]$operation.RegistryPath
            ProfileLabel = [string]$operation.ProfileLabel
            UserName = [string]$operation.UserName
            Status = [string]$status
            Reason = [string]$reason
        }) | Out-Null
    }

    $rows = @($items.ToArray())
    $mismatches = @($rows | Where-Object { [string]$_.Status -eq 'mismatch' })
    $skipped = @($rows | Where-Object { [string]$_.Status -eq 'skipped' })
    return [pscustomobject]@{
        CheckedCount = @($rows).Count
        MismatchCount = @($mismatches).Count
        SkippedCount = @($skipped).Count
        Succeeded = (@($mismatches).Count -eq 0)
        Items = $rows
    }
}

function Test-ProdicloudTaskAppStateRollbackState {
    param([object[]]$BackupRecords = @())

    $items = New-Object 'System.Collections.Generic.List[object]'
    foreach ($record in @($BackupRecords)) {
        if ($null -eq $record) {
            continue
        }

        $status = 'verified'
        $reason = ''
        $backupStatus = Get-ProdicloudAppStateBackupRecordStatus -Record $record
        if ([string]$backupStatus.Status -eq 'skipped') {
            $status = 'skipped'
            $reason = [string]$backupStatus.Reason
        }
        else {
            switch ([string]$record.Kind) {
                'file' {
                    if ([bool]$record.Existed) {
                        if (-not (Test-Path -LiteralPath ([string]$record.DestinationPath) -PathType Leaf)) {
                            $status = 'mismatch'
                            $reason = 'destination-missing'
                        }
                        else {
                            $backupHash = Get-ProdicloudAppStateFileHashValue -Path ([string]$record.BackupPath)
                            $destinationHash = Get-ProdicloudAppStateFileHashValue -Path ([string]$record.DestinationPath)
                            if ([string]::IsNullOrWhiteSpace([string]$backupHash) -or -not [string]::Equals([string]$backupHash, [string]$destinationHash, [System.StringComparison]::OrdinalIgnoreCase)) {
                                $status = 'mismatch'
                                $reason = 'hash-mismatch'
                            }
                        }
                    }
                    elseif (Test-Path -LiteralPath ([string]$record.DestinationPath)) {
                        $status = 'mismatch'
                        $reason = 'path-still-present'
                    }
                }
                'directory' {
                    if ([bool]$record.Existed) {
                        $directoryMatch = Test-ProdicloudTaskAppStateDirectoryMatches -SourcePath ([string]$record.BackupPath) -DestinationPath ([string]$record.DestinationPath)
                        if (-not [bool]$directoryMatch.Success) {
                            $status = 'mismatch'
                            $reason = [string]$directoryMatch.Reason
                        }
                    }
                    elseif (Test-Path -LiteralPath ([string]$record.DestinationPath)) {
                        $status = 'mismatch'
                        $reason = 'path-still-present'
                    }
                }
                'registry' {
                    $profileTarget = [pscustomobject]@{
                        Label = [string]$record.ProfileLabel
                        UserName = [string]$record.UserName
                        ProfilePath = [string]$record.ProfilePath
                    }
                    if ([bool]$record.Existed) {
                        $registryMatch = Test-ProdicloudTaskAppStateRegistryMatches -SourcePath ([string]$record.BackupPath) -RegistryPath ([string]$record.RegistryPath) -Scope ([string]$record.Scope) -ProfileTarget $profileTarget
                        if (-not [bool]$registryMatch.Success) {
                            $status = 'mismatch'
                            $reason = [string]$registryMatch.Reason
                        }
                    }
                    else {
                        $tempExportPath = Join-Path ([System.IO.Path]::GetTempPath()) ('prodicloud-reg-rollback-{0}.reg' -f ([guid]::NewGuid().ToString('N')))
                        $exported = $false
                        try {
                            if ([string]::Equals([string]$record.Scope, 'machine', [System.StringComparison]::OrdinalIgnoreCase)) {
                                $canonicalRegistryPath = Convert-ProdicloudAppStateRegistryPathToCanonicalRoot -RegistryPath ([string]$record.RegistryPath)
                                $providerPath = Convert-ProdicloudAppStateRegistryPathToProviderPath -RegistryPath $canonicalRegistryPath
                                if (-not [string]::IsNullOrWhiteSpace([string]$providerPath) -and (Test-Path -LiteralPath $providerPath)) {
                                    $exported = Invoke-ProdicloudRegExport -RegistryPath $canonicalRegistryPath -DestinationPath $tempExportPath
                                }
                            }
                            else {
                                $exported = Backup-ProdicloudTaskUserRegistry -RegistryPath ([string]$record.RegistryPath) -ProfileTarget $profileTarget -BackupPath $tempExportPath
                            }
                        }
                        finally {
                            Remove-Item -LiteralPath $tempExportPath -Force -ErrorAction SilentlyContinue
                        }

                        if ($exported) {
                            $status = 'mismatch'
                            $reason = 'registry-still-present'
                        }
                    }
                }
            }
        }

        $items.Add([pscustomobject]@{
            Kind = [string]$record.Kind
            Scope = [string]$record.Scope
            DestinationPath = [string]$record.DestinationPath
            RegistryPath = [string]$record.RegistryPath
            ProfileLabel = [string]$record.ProfileLabel
            UserName = [string]$record.UserName
            Status = [string]$status
            Reason = [string]$reason
        }) | Out-Null
    }

    $rows = @($items.ToArray())
    $mismatches = @($rows | Where-Object { [string]$_.Status -eq 'mismatch' })
    $skipped = @($rows | Where-Object { [string]$_.Status -eq 'skipped' })
    return [pscustomobject]@{
        CheckedCount = @($rows).Count
        MismatchCount = @($mismatches).Count
        SkippedCount = @($skipped).Count
        Succeeded = (@($mismatches).Count -eq 0)
        Items = $rows
    }
}

function Invoke-ProdicloudTaskAppStateRollback {
    param([object[]]$BackupRecords = @())

    $records = @($BackupRecords)
    [array]::Reverse($records)
    foreach ($record in @($records)) {
        if ($null -eq $record) {
            continue
        }

        $backupStatus = Get-ProdicloudAppStateBackupRecordStatus -Record $record
        if ([string]$backupStatus.Status -eq 'skipped') {
            continue
        }

        try {
            switch ([string]$record.Kind) {
                'file' {
                    $destinationPath = [string]$record.DestinationPath
                    if ([bool]$record.Existed -and -not [string]::IsNullOrWhiteSpace([string]$record.BackupPath) -and (Test-Path -LiteralPath ([string]$record.BackupPath))) {
                        Ensure-ProdicloudAppStateDirectory -Path (Split-Path -Path $destinationPath -Parent)
                        Copy-Item -LiteralPath ([string]$record.BackupPath) -Destination $destinationPath -Force -ErrorAction SilentlyContinue
                    }
                    else {
                        Remove-Item -LiteralPath $destinationPath -Force -ErrorAction SilentlyContinue
                    }
                }
                'directory' {
                    $destinationPath = [string]$record.DestinationPath
                    Remove-Item -LiteralPath $destinationPath -Recurse -Force -ErrorAction SilentlyContinue
                    if ([bool]$record.Existed -and -not [string]::IsNullOrWhiteSpace([string]$record.BackupPath) -and (Test-Path -LiteralPath ([string]$record.BackupPath))) {
                        Ensure-ProdicloudAppStateDirectory -Path (Split-Path -Path $destinationPath -Parent)
                        Copy-Item -LiteralPath ([string]$record.BackupPath) -Destination $destinationPath -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
                'registry' {
                    $profileTarget = [pscustomobject]@{
                        Label = [string]$record.ProfileLabel
                        UserName = [string]$record.UserName
                        ProfilePath = [string]$record.ProfilePath
                    }
                    if ([bool]$record.Existed -and -not [string]::IsNullOrWhiteSpace([string]$record.BackupPath) -and (Test-Path -LiteralPath ([string]$record.BackupPath))) {
                        if ([string]::Equals([string]$record.Scope, 'machine', [System.StringComparison]::OrdinalIgnoreCase)) {
                            cmd.exe /d /c ('reg import "{0}" >nul 2>&1' -f ([string]$record.BackupPath)) | Out-Null
                        }
                        else {
                            [void](Restore-ProdicloudTaskUserRegistryFromBackup -BackupPath ([string]$record.BackupPath) -RegistryPath ([string]$record.RegistryPath) -ProfileTarget $profileTarget)
                        }
                    }
                    else {
                        Remove-ProdicloudTaskRegistryPath -RegistryPath ([string]$record.RegistryPath) -Scope ([string]$record.Scope) -ProfileTarget $profileTarget
                    }
                }
            }
        }
        catch {
        }
    }

    return (Test-ProdicloudTaskAppStateRollbackState -BackupRecords @($BackupRecords))
}

function Stop-ProdicloudManagedProcessesGracefully {
    param(
        [string[]]$ProcessNames = @(),
        [int]$GracefulWaitSeconds = 10
    )

    $normalizedNames = @(
        @($ProcessNames) |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object { $_.Trim() } |
            Select-Object -Unique
    )
    if (@($normalizedNames).Count -lt 1) {
        return
    }

    foreach ($processName in @($normalizedNames)) {
        foreach ($process in @(Get-Process -Name $processName -ErrorAction SilentlyContinue)) {
            try {
                if ($process.MainWindowHandle -ne 0) {
                    [void]$process.CloseMainWindow()
                }
            }
            catch {
            }
        }
    }

    $deadline = (Get-Date).AddSeconds([Math]::Max($GracefulWaitSeconds, 1))
    do {
        $remaining = @()
        foreach ($processName in @($normalizedNames)) {
            $remaining += @(Get-Process -Name $processName -ErrorAction SilentlyContinue)
        }
        if (@($remaining).Count -lt 1) {
            return
        }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)

    foreach ($process in @($remaining | Sort-Object Id -Unique)) {
        try {
            Stop-Process -Id $process.Id -Force -ErrorAction Stop
        }
        catch {
        }
    }
}

function Get-ProdicloudTaskAppStateManagedProcessNames {
    param([string]$TaskName)

    if ([string]::Equals([string]$TaskName, '03-install-chrome-application', [System.StringComparison]::OrdinalIgnoreCase)) {
        return @('chrome')
    }
    if ([string]::Equals([string]$TaskName, '103-install-edge-application', [System.StringComparison]::OrdinalIgnoreCase)) {
        return @('msedge')
    }

    return @()
}

function Invoke-ProdicloudTaskAppStateBrowserPreflight {
    param(
        [string]$TaskName,
        [ValidateSet('capture', 'replay')]
        [string]$Mode
    )

    $processNames = @(Get-ProdicloudTaskAppStateManagedProcessNames -TaskName $TaskName)
    if (@($processNames).Count -lt 1) {
        return
    }

    Write-Host ("app-state preflight => task={0}; mode={1}; managed-processes={2}" -f [string]$TaskName, [string]$Mode, (@($processNames) -join ','))
    Stop-ProdicloudManagedProcessesGracefully -ProcessNames @($processNames) -GracefulWaitSeconds 15
    Write-Host ("app-state preflight done => task={0}; mode={1}" -f [string]$TaskName, [string]$Mode)
}

function Invoke-ProdicloudTaskAppStateCapturePreflight {
    param([string]$TaskName)

    Invoke-ProdicloudTaskAppStateBrowserPreflight -TaskName $TaskName -Mode 'capture'
}

function Invoke-ProdicloudTaskAppStateReplayPreflight {
    param([string]$TaskName)

    Invoke-ProdicloudTaskAppStateBrowserPreflight -TaskName $TaskName -Mode 'replay'
}

function Resolve-ProdicloudAppStateCapturePathMatches {
    param(
        [string]$BasePath,
        [string]$RelativeOrAbsolutePath
    )

    if ([string]::IsNullOrWhiteSpace([string]$RelativeOrAbsolutePath)) {
        return @()
    }

    $candidatePath = [string]$RelativeOrAbsolutePath
    if (-not [System.IO.Path]::IsPathRooted($candidatePath) -and -not [string]::IsNullOrWhiteSpace([string]$BasePath)) {
        $candidatePath = Join-Path $BasePath $candidatePath
    }

    $hasWildcard = ($candidatePath.IndexOf('*', [System.StringComparison]::Ordinal) -ge 0 -or $candidatePath.IndexOf('?', [System.StringComparison]::Ordinal) -ge 0)
    if ($hasWildcard) {
        return @(
            Resolve-Path -Path $candidatePath -ErrorAction SilentlyContinue |
                Sort-Object Path |
                Select-Object -ExpandProperty Path
        )
    }

    if (Test-Path -LiteralPath $candidatePath) {
        return @([string](Resolve-Path -LiteralPath $candidatePath).Path)
    }

    return @()
}

function Test-ProdicloudAppStateLxssRegistryPath {
    param([string]$RegistryPath)

    return [string]::Equals(
        (Convert-ProdicloudAppStateRegistryPathToCanonicalRoot -RegistryPath $RegistryPath),
        'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Lxss',
        [System.StringComparison]::OrdinalIgnoreCase
    )
}

function Get-ProdicloudAppStateAllowedLxssRegistryKeys {
    param([string[]]$DistributionAllowList = @())

    $normalizedAllowList = @(
        @($DistributionAllowList) |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object { $_.Trim().ToLowerInvariant() } |
            Select-Object -Unique
    )
    if (@($normalizedAllowList).Count -lt 1) {
        return @()
    }

    $providerRoot = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Lxss'
    if (-not (Test-Path -LiteralPath $providerRoot)) {
        return @()
    }

    return @(
        Get-ChildItem -LiteralPath $providerRoot -ErrorAction SilentlyContinue |
            Sort-Object PSChildName |
            ForEach-Object {
                $distributionName = ''
                try {
                    $distributionName = [string](Get-ItemPropertyValue -LiteralPath $_.PSPath -Name 'DistributionName' -ErrorAction Stop)
                }
                catch {
                    return
                }
                if ([string]::IsNullOrWhiteSpace([string]$distributionName)) {
                    return
                }
                if (@($normalizedAllowList) -notcontains $distributionName.Trim().ToLowerInvariant()) {
                    return
                }
                [pscustomobject]@{
                    DistributionName = [string]$distributionName
                    RegistryPath = ('HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Lxss\{0}' -f [string]$_.PSChildName)
                    KeyName = [string]$_.PSChildName
                }
            } |
            Where-Object { $_ -ne $null }
    )
}

function Export-ProdicloudFilteredLxssRegistry {
    param(
        [string]$DestinationPath,
        [string[]]$DistributionAllowList = @()
    )

    $allowedEntries = @(Get-ProdicloudAppStateAllowedLxssRegistryKeys -DistributionAllowList $DistributionAllowList)
    if (@($allowedEntries).Count -lt 1) {
        return $false
    }

    $tempExportPath = Join-Path $env:TEMP (('prodicloud-lxss-{0}.reg' -f ([guid]::NewGuid().ToString('N'))))
    try {
        if (-not (Invoke-ProdicloudRegExport -RegistryPath 'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Lxss' -DestinationPath $tempExportPath)) {
            return $false
        }

        $content = [string](Get-Content -LiteralPath $tempExportPath -Raw -Encoding Unicode -ErrorAction SilentlyContinue)
        if ([string]::IsNullOrWhiteSpace([string]$content)) {
            $content = [string](Get-Content -LiteralPath $tempExportPath -Raw -ErrorAction SilentlyContinue)
        }
        if ([string]::IsNullOrWhiteSpace([string]$content)) {
            return $false
        }

        $blocks = @([regex]::Split($content.Trim(), '(?:\r?\n){2,}'))
        if (@($blocks).Count -lt 2) {
            return $false
        }

        $rootPath = 'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Lxss'
        $allowedRegistryPaths = @($allowedEntries | ForEach-Object { [string]$_.RegistryPath })
        $defaultKey = [string]$allowedEntries[0].KeyName
        $outputBlocks = New-Object 'System.Collections.Generic.List[string]'
        [void]$outputBlocks.Add([string]$blocks[0].Trim())

        foreach ($block in @($blocks | Select-Object -Skip 1)) {
            $lines = @([regex]::Split([string]$block.Trim(), '\r?\n'))
            if (@($lines).Count -lt 1) {
                continue
            }

            $keyLine = [string]$lines[0]
            $match = [regex]::Match($keyLine, '^\[(.+)\]$')
            if (-not $match.Success) {
                continue
            }

            $blockRegistryPath = [string]$match.Groups[1].Value
            if ([string]::Equals($blockRegistryPath, $rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                $rewrittenLines = New-Object 'System.Collections.Generic.List[string]'
                [void]$rewrittenLines.Add($keyLine)
                foreach ($line in @($lines | Select-Object -Skip 1)) {
                    if ($line -match '^\s*"NatIpAddress"=') { continue }
                    if ($line -match '^\s*"DefaultDistribution"=') { continue }
                    [void]$rewrittenLines.Add([string]$line)
                }
                [void]$rewrittenLines.Add(('"DefaultDistribution"="{{{0}}}"' -f $defaultKey.Trim('{}')))
                [void]$outputBlocks.Add(($rewrittenLines -join [Environment]::NewLine))
                continue
            }

            $keepBlock = $false
            foreach ($allowedRegistryPath in @($allowedRegistryPaths)) {
                if (
                    [string]::Equals($blockRegistryPath, $allowedRegistryPath, [System.StringComparison]::OrdinalIgnoreCase) -or
                    $blockRegistryPath.StartsWith(($allowedRegistryPath + '\'), [System.StringComparison]::OrdinalIgnoreCase)
                ) {
                    $keepBlock = $true
                    break
                }
            }
            if ($keepBlock) {
                [void]$outputBlocks.Add(([string]$block).Trim())
            }
        }

        Ensure-ProdicloudAppStateDirectory -Path (Split-Path -Path $DestinationPath -Parent)
        Set-Content -LiteralPath $DestinationPath -Value (($outputBlocks -join ([Environment]::NewLine + [Environment]::NewLine)) + [Environment]::NewLine) -Encoding Unicode
        return $true
    }
    finally {
        Remove-Item -LiteralPath $tempExportPath -Force -ErrorAction SilentlyContinue
    }
}

function Export-ProdicloudAppStateUserRegistry {
    param(
        [string]$RegistryPath,
        [string]$DestinationPath,
        [psobject]$ProfileTarget,
        [string[]]$DistributionAllowList = @()
    )

    if ($null -eq $ProfileTarget) {
        return $false
    }

    if (Test-ProdicloudAppStateLxssRegistryPath -RegistryPath $RegistryPath) {
        return (Export-ProdicloudFilteredLxssRegistry -DestinationPath $DestinationPath -DistributionAllowList $DistributionAllowList)
    }

    $mountInfo = Get-ProdicloudMountedUserHive -ProfilePath ([string]$ProfileTarget.ProfilePath) -PreferredLabel ([string]$ProfileTarget.UserName)
    if ($null -eq $mountInfo) {
        return $false
    }

    try {
        $canonicalRoot = Convert-ProdicloudAppStateRegistryPathToCanonicalRoot -RegistryPath $RegistryPath
        if ([string]::IsNullOrWhiteSpace([string]$canonicalRoot)) {
            return $false
        }

        $mountedRoot = $canonicalRoot -replace '^HKEY_CURRENT_USER', ([string]$mountInfo.Root)
        $tempExportPath = Join-Path $env:TEMP (('prodicloud-reg-export-{0}.reg' -f ([guid]::NewGuid().ToString('N'))))
        try {
            if (-not (Invoke-ProdicloudRegExport -RegistryPath $mountedRoot -DestinationPath $tempExportPath)) {
                return $false
            }
            return (Convert-ProdicloudAppStateRegRoot -SourcePath $tempExportPath -SourceRoot ([string]$mountInfo.Root) -DestinationRoot 'HKEY_CURRENT_USER' -DestinationPath $DestinationPath)
        }
        finally {
            Remove-Item -LiteralPath $tempExportPath -Force -ErrorAction SilentlyContinue
        }
    }
    finally {
        Close-ProdicloudMountedUserHive -MountInfo $mountInfo
    }
}

function Compress-ProdicloudAppStateCaptureRoot {
    param(
        [string]$SourceRoot,
        [string]$DestinationZipPath
    )

    if ([string]::IsNullOrWhiteSpace([string]$SourceRoot) -or -not (Test-Path -LiteralPath $SourceRoot)) {
        throw "App-state capture root is missing."
    }

    Remove-Item -LiteralPath $DestinationZipPath -Force -ErrorAction SilentlyContinue
    $previousProgressPreference = $global:ProgressPreference
    try {
        $global:ProgressPreference = 'SilentlyContinue'
        Compress-Archive -LiteralPath @(Get-ChildItem -LiteralPath $SourceRoot -Force | Select-Object -ExpandProperty FullName) -DestinationPath $DestinationZipPath -Force
    }
    finally {
        $global:ProgressPreference = $previousProgressPreference
    }
}

function Invoke-ProdicloudTaskAppStateCapture {
    param(
        [string]$TaskName,
        [string]$PlanPath,
        [string]$OutputZipPath,
        [string]$ManagerUser,
        [string]$AssistantUser,
        [object[]]$ProfileTargets = @()
    )

    if ([string]::IsNullOrWhiteSpace([string]$PlanPath) -or -not (Test-Path -LiteralPath $PlanPath)) {
        throw ("App-state capture plan was not found: {0}" -f [string]$PlanPath)
    }

    $planText = [string](Get-Content -LiteralPath $PlanPath -Raw -ErrorAction Stop)
    $plan = ConvertFrom-Json -InputObject $planText -ErrorAction Stop
    if ($null -eq $plan) {
        throw "App-state capture plan could not be parsed."
    }

    $scratchRoot = Get-ProdicloudAppStateScratchRootPath -Prefix 'azv-capture'
    Ensure-ProdicloudAppStateDirectory -Path $scratchRoot
    $payloadRoot = Join-Path $scratchRoot 'payload'
    Ensure-ProdicloudAppStateDirectory -Path $payloadRoot

    $profileTargets = @(Get-ProdicloudAppStateProfileTargets -ManagerUser $ManagerUser -AssistantUser $AssistantUser -ProfileTargets @($ProfileTargets))
    $machineRegistryExports = 0
    $userRegistryExports = 0
    $machineDirectoryExports = 0
    $machineFileExports = 0
    $profileDirectoryExports = 0
    $profileFileExports = 0
    $skipCount = 0

    $manifest = [ordered]@{
        version = 3
        taskName = [string]$TaskName
        machineDirectories = @()
        machineFiles = @()
        profileDirectories = @()
        profileFiles = @()
        registryImports = @()
    }

    try {
        Remove-Item -LiteralPath $OutputZipPath -Force -ErrorAction SilentlyContinue
        Invoke-ProdicloudTaskAppStateCapturePreflight -TaskName $TaskName
        $machineDirectoryIndex = 0
        foreach ($entry in @($plan.machineDirectories)) {
            if ($null -eq $entry -or [string]::IsNullOrWhiteSpace([string]$entry.path)) { continue }
            $machineDirectoryIndex++
            $machineMatchIndex = 0
            foreach ($matchPath in @(Resolve-ProdicloudAppStateCapturePathMatches -BasePath '' -RelativeOrAbsolutePath ([string]$entry.path))) {
                $machineMatchIndex++
                $payloadName = ('{0:D3}-{1:D3}-{2}' -f $machineDirectoryIndex, $machineMatchIndex, (ConvertTo-ProdicloudAppStateCaptureSafeName -Value (Split-Path -Path $matchPath -Leaf)))
                $payloadPath = Join-Path 'payload\machine-directories' $payloadName
                if (Copy-ProdicloudAppStateCaptureTree -SourcePath $matchPath -DestinationPath (Join-Path $scratchRoot $payloadPath) -ExcludeNames @($entry.excludeNames) -ExcludePathPatterns @($entry.excludePathPatterns) -ExcludeFilePatterns @($entry.excludeFilePatterns)) {
                    $manifest.machineDirectories += @{
                        sourcePath = [string]$payloadPath
                        destinationPath = [string]$matchPath
                    }
                    $machineDirectoryExports++
                }
                else {
                    $skipCount++
                }
            }
        }

        $machineFileIndex = 0
        foreach ($entry in @($plan.machineFiles)) {
            if ($null -eq $entry -or [string]::IsNullOrWhiteSpace([string]$entry.path)) { continue }
            $machineFileIndex++
            $machineMatchIndex = 0
            foreach ($matchPath in @(Resolve-ProdicloudAppStateCapturePathMatches -BasePath '' -RelativeOrAbsolutePath ([string]$entry.path))) {
                $machineMatchIndex++
                $payloadName = ('{0:D3}-{1:D3}-{2}' -f $machineFileIndex, $machineMatchIndex, (ConvertTo-ProdicloudAppStateCaptureSafeName -Value (Split-Path -Path $matchPath -Leaf)))
                $payloadPath = Join-Path 'payload\machine-files' $payloadName
                if (Copy-ProdicloudAppStateCaptureTree -SourcePath $matchPath -DestinationPath (Join-Path $scratchRoot $payloadPath) -ExcludeNames @($entry.excludeNames) -ExcludePathPatterns @($entry.excludePathPatterns) -ExcludeFilePatterns @($entry.excludeFilePatterns)) {
                    $manifest.machineFiles += @{
                        sourcePath = [string]$payloadPath
                        destinationPath = [string]$matchPath
                    }
                    $machineFileExports++
                }
                else {
                    $skipCount++
                }
            }
        }

        foreach ($entry in @($plan.profileDirectories)) {
            if ($null -eq $entry -or [string]::IsNullOrWhiteSpace([string]$entry.path)) { continue }
            foreach ($profileTarget in @(Get-ProdicloudAppStateSelectedProfileTargets -ProfileTargets $profileTargets -Entry $entry)) {
                foreach ($matchPath in @(Resolve-ProdicloudAppStateCapturePathMatches -BasePath ([string]$profileTarget.ProfilePath) -RelativeOrAbsolutePath ([string]$entry.path))) {
                    $relativeToProfile = Get-ProdicloudAppStateRelativePathFromBase -BasePath ([string]$profileTarget.ProfilePath) -CandidatePath $matchPath
                    if ([string]::IsNullOrWhiteSpace([string]$relativeToProfile)) {
                        $skipCount++
                        continue
                    }

                    $payloadPath = Join-Path ('payload\profile-directories\' + [string]$profileTarget.Label) (ConvertTo-ProdicloudAppStateCaptureSafeName -Value $relativeToProfile)
                    if (Copy-ProdicloudAppStateCaptureTree -SourcePath $matchPath -DestinationPath (Join-Path $scratchRoot $payloadPath) -ExcludeNames @($entry.excludeNames) -ExcludePathPatterns @($entry.excludePathPatterns) -ExcludeFilePatterns @($entry.excludeFilePatterns)) {
                        $manifest.profileDirectories += @{
                            sourcePath = [string]$payloadPath
                            relativeDestinationPath = [string]$relativeToProfile
                            targetProfiles = @([string]$profileTarget.Label)
                        }
                        $profileDirectoryExports++
                    }
                    else {
                        $skipCount++
                    }
                }
            }
        }

        foreach ($entry in @($plan.profileFiles)) {
            if ($null -eq $entry -or [string]::IsNullOrWhiteSpace([string]$entry.path)) { continue }
            foreach ($profileTarget in @(Get-ProdicloudAppStateSelectedProfileTargets -ProfileTargets $profileTargets -Entry $entry)) {
                foreach ($matchPath in @(Resolve-ProdicloudAppStateCapturePathMatches -BasePath ([string]$profileTarget.ProfilePath) -RelativeOrAbsolutePath ([string]$entry.path))) {
                    $relativeToProfile = Get-ProdicloudAppStateRelativePathFromBase -BasePath ([string]$profileTarget.ProfilePath) -CandidatePath $matchPath
                    if ([string]::IsNullOrWhiteSpace([string]$relativeToProfile)) {
                        $skipCount++
                        continue
                    }

                    $payloadPath = Join-Path ('payload\profile-files\' + [string]$profileTarget.Label) (ConvertTo-ProdicloudAppStateCaptureSafeName -Value $relativeToProfile)
                    if (Copy-ProdicloudAppStateCaptureTree -SourcePath $matchPath -DestinationPath (Join-Path $scratchRoot $payloadPath) -ExcludeNames @($entry.excludeNames) -ExcludePathPatterns @($entry.excludePathPatterns) -ExcludeFilePatterns @($entry.excludeFilePatterns)) {
                        $manifest.profileFiles += @{
                            sourcePath = [string]$payloadPath
                            relativeDestinationPath = [string]$relativeToProfile
                            targetProfiles = @([string]$profileTarget.Label)
                        }
                        $profileFileExports++
                    }
                    else {
                        $skipCount++
                    }
                }
            }
        }

        foreach ($entry in @($plan.machineRegistryKeys)) {
            if ($null -eq $entry -or [string]::IsNullOrWhiteSpace([string]$entry.path)) { continue }
            $payloadPath = Join-Path 'payload\registry\machine' ((ConvertTo-ProdicloudAppStateCaptureSafeName -Value ([string]$entry.path)) + '.reg')
            if (Invoke-ProdicloudRegExport -RegistryPath (Convert-ProdicloudAppStateRegistryPathToCanonicalRoot -RegistryPath ([string]$entry.path)) -DestinationPath (Join-Path $scratchRoot $payloadPath)) {
                $manifest.registryImports += @{
                    sourcePath = [string]$payloadPath
                    scope = 'machine'
                    registryPath = [string](Convert-ProdicloudAppStateRegistryPathToCanonicalRoot -RegistryPath ([string]$entry.path))
                }
                $machineRegistryExports++
            }
            else {
                $skipCount++
            }
        }

        foreach ($entry in @($plan.userRegistryKeys)) {
            if ($null -eq $entry -or [string]::IsNullOrWhiteSpace([string]$entry.path)) { continue }
            foreach ($profileTarget in @(Get-ProdicloudAppStateSelectedProfileTargets -ProfileTargets $profileTargets -Entry $entry)) {
                $payloadPath = Join-Path ('payload\registry\user\' + [string]$profileTarget.Label) ((ConvertTo-ProdicloudAppStateCaptureSafeName -Value ([string]$entry.path)) + '.reg')
                if (Export-ProdicloudAppStateUserRegistry -RegistryPath ([string]$entry.path) -DestinationPath (Join-Path $scratchRoot $payloadPath) -ProfileTarget $profileTarget -DistributionAllowList @($entry.distributionAllowList)) {
                    $registryEntry = [ordered]@{
                        sourcePath = [string]$payloadPath
                        scope = 'user'
                        registryPath = [string](Convert-ProdicloudAppStateRegistryPathToCanonicalRoot -RegistryPath ([string]$entry.path))
                        targetProfiles = @([string]$profileTarget.Label)
                    }
                    if (@($entry.distributionAllowList).Count -gt 0) {
                        $registryEntry.distributionAllowList = @($entry.distributionAllowList)
                    }
                    $manifest.registryImports += $registryEntry
                    $userRegistryExports++
                }
                else {
                    $skipCount++
                }
            }
        }

        $totalCapturedItems =
            [int]$machineRegistryExports +
            [int]$userRegistryExports +
            [int]$machineDirectoryExports +
            [int]$machineFileExports +
            [int]$profileDirectoryExports +
            [int]$profileFileExports
        if ($totalCapturedItems -gt 0) {
            ConvertTo-ProdicloudAppStatePortablePayload `
                -ScratchRoot $scratchRoot `
                -Manifest ([pscustomobject]$manifest) `
                -ProfileTargets @($profileTargets) `
                -ManagerUser $ManagerUser `
                -AssistantUser $AssistantUser
            Set-Content -LiteralPath (Join-Path $scratchRoot 'app-state.manifest.json') -Value ($manifest | ConvertTo-Json -Depth 12) -Encoding UTF8
            Compress-ProdicloudAppStateCaptureRoot -SourceRoot $scratchRoot -DestinationZipPath $OutputZipPath
        }
        return [pscustomobject]@{
            MachineRegistryExports = [int]$machineRegistryExports
            UserRegistryExports = [int]$userRegistryExports
            MachineDirectoryExports = [int]$machineDirectoryExports
            MachineFileExports = [int]$machineFileExports
            ProfileDirectoryExports = [int]$profileDirectoryExports
            ProfileFileExports = [int]$profileFileExports
            SkipCount = [int]$skipCount
            CreatedZip = ($totalCapturedItems -gt 0)
        }
    }
    finally {
        Remove-Item -LiteralPath $scratchRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $PlanPath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-ProdicloudTaskAppStateReplay {
    param(
        [string]$ZipPath,
        [string]$TaskName,
        [string]$ManagerUser,
        [string]$AssistantUser,
        [object[]]$ProfileTargets = @()
    )

    if ([string]::IsNullOrWhiteSpace([string]$ZipPath) -or -not (Test-Path -LiteralPath $ZipPath)) {
        throw ("Task app-state zip was not found on guest: {0}" -f [string]$ZipPath)
    }

    $replayWatch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Host ("app-state start => task={0}; mode=replay" -f [string]$TaskName)
    $zipLength = Wait-ProdicloudAppStateZipReady -ZipPath $ZipPath -TimeoutSeconds 60

    $scratchRoot = Get-ProdicloudAppStateScratchRootPath -Prefix 'azv-replay'
    Ensure-ProdicloudAppStateDirectory -Path $scratchRoot
    $previousProgressPreference = $global:ProgressPreference
    try {
        $global:ProgressPreference = 'SilentlyContinue'
        Expand-Archive -LiteralPath $ZipPath -DestinationPath $scratchRoot -Force
    }
    finally {
        $global:ProgressPreference = $previousProgressPreference
    }

    try {
        $manifest = Get-ProdicloudAppStateManifestFromExpandedRoot -ExpandedRoot $scratchRoot -TaskName $TaskName
        Invoke-ProdicloudTaskAppStateReplayPreflight -TaskName $TaskName
        $profileTargets = @(Get-ProdicloudAppStateProfileTargets -ManagerUser $ManagerUser -AssistantUser $AssistantUser -ProfileTargets @($ProfileTargets))
        Expand-ProdicloudAppStatePayloadPlaceholders `
            -ExpandedRoot $scratchRoot `
            -ProfileTargets @($profileTargets) `
            -ManagerUser $ManagerUser `
            -AssistantUser $AssistantUser
        $manifest = Get-ProdicloudAppStateManifestFromExpandedRoot -ExpandedRoot $scratchRoot -TaskName $TaskName
        $operations = @(Get-ProdicloudTaskAppStateReplayOperations -ExpandedRoot $scratchRoot -Manifest $manifest -ProfileTargets @($profileTargets))
        $backupRoot = Get-ProdicloudAppStateScratchRootPath -Prefix 'azv-rollback'
        Ensure-ProdicloudAppStateDirectory -Path $backupRoot
        $backupRecords = @(Backup-ProdicloudTaskAppStateOperations -Operations @($operations) -BackupRoot $backupRoot)

        try {
            $replayResult = Invoke-ProdicloudTaskAppStateReplayOperations -Operations @($operations)
            $verifyResult = Test-ProdicloudTaskAppStateOperations -Operations @($operations)
            if (-not [bool]$verifyResult.Succeeded) {
                throw ("Task app-state restore verification failed for '{0}'." -f [string]$TaskName)
            }

            Write-Host ("app-state done => task={0}; mode=replay; bytes={1}; profiles={2}; checked={3}; mismatches={4}; skipped={5}; elapsed={6:N1}s" -f [string]$TaskName, [int64]$zipLength, @($profileTargets).Count, [int]$verifyResult.CheckedCount, [int]$verifyResult.MismatchCount, [int]$verifyResult.SkippedCount, $replayWatch.Elapsed.TotalSeconds)

            return [pscustomobject]@{
                MachineRegistryImports = [int]$replayResult.MachineRegistryImports
                UserRegistryImports = [int]$replayResult.UserRegistryImports
                MachineDirectoryCopies = [int]$replayResult.MachineDirectoryCopies
                MachineFileCopies = [int]$replayResult.MachineFileCopies
                ProfileDirectoryCopies = [int]$replayResult.ProfileDirectoryCopies
                ProfileFileCopies = [int]$replayResult.ProfileFileCopies
                SkippedCount = [int]$replayResult.SkippedCount
                Verified = $true
                VerifyCheckedCount = [int]$verifyResult.CheckedCount
                VerifyMismatchCount = [int]$verifyResult.MismatchCount
                VerifySkippedCount = [int]$verifyResult.SkippedCount
                VerifyItems = @($verifyResult.Items)
                RollbackPerformed = $false
                RollbackSucceeded = $false
            }
        }
        catch {
            $rollbackResult = Invoke-ProdicloudTaskAppStateRollback -BackupRecords @($backupRecords)
            Write-Host ("app-state rollback => task={0}; checked={1}; mismatches={2}; skipped={3}; elapsed={4:N1}s" -f [string]$TaskName, [int]$rollbackResult.CheckedCount, [int]$rollbackResult.MismatchCount, [int]$rollbackResult.SkippedCount, $replayWatch.Elapsed.TotalSeconds)
            if (-not [bool]$rollbackResult.Succeeded) {
                throw ("{0} Rollback verification also failed for '{1}'." -f [string]$_.Exception.Message, [string]$TaskName)
            }

            throw
        }
        finally {
            Remove-Item -LiteralPath $backupRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    finally {
        if ($replayWatch.IsRunning) {
            $replayWatch.Stop()
        }
        Remove-Item -LiteralPath $scratchRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $ZipPath -Force -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember -Function Invoke-ProdicloudTaskAppStateReplay, Invoke-ProdicloudTaskAppStateCapture
