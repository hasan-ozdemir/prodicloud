[CmdletBinding()]
param(
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$packageRoot = Join-Path $repoRoot 'packages'
$script:ClagnosPackageStateSourceAddresses = @()
try {
    $script:ClagnosPackageStateSourceAddresses = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' } | Select-Object -ExpandProperty IPAddress)
}
catch { $script:ClagnosPackageStateSourceAddresses = @() }

function New-ClagnosProfileFileRule {
    param([string]$Path, [string[]]$TargetProfiles = @())

    return [ordered]@{
        path = [string]$Path
        targetProfiles = @($TargetProfiles)
    }
}

function Set-ClagnosPackageAppStatePolicy {
    param(
        [string]$PackageId,
        [AllowNull()]$AppState,
        [switch]$RemoveSnapshot
    )

    $manifestPath = Join-Path $packageRoot (Join-Path 'builtin\windows' (Join-Path $PackageId 'package.json'))
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw ("Package manifest is missing: {0}" -f $manifestPath) }
    $manifest = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop) -ErrorAction Stop
    if ($null -ne $AppState) {
        $manifest | Add-Member -MemberType NoteProperty -Name appState -Value $AppState -Force
    }
    elseif ($manifest.PSObject.Properties.Match('appState').Count -gt 0) {
        $manifest.PSObject.Properties.Remove('appState')
    }

    $zipPath = Join-Path $packageRoot (Join-Path 'builtin\windows' (Join-Path $PackageId 'app-state\app-state.zip'))
    if ($Apply -and $RemoveSnapshot -and (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
        Remove-Item -LiteralPath $zipPath -Force
        $appStateDirectory = Split-Path -Parent $zipPath
        if (@(Get-ChildItem -LiteralPath $appStateDirectory -Force -ErrorAction SilentlyContinue).Count -eq 0) {
            Remove-Item -LiteralPath $appStateDirectory -Force
        }
    }

    if ($Apply) {
        Set-Content -LiteralPath $manifestPath -Value (ConvertTo-Json -InputObject $manifest -Depth 100) -Encoding UTF8
    }
    Write-Output ("{0}: {1}" -f $PackageId, $(if ($null -eq $AppState) { 'no portable app-state policy' } else { 'portable app-state policy' }))
}

function Get-ClagnosArchiveEntryBytes {
    param([System.IO.Compression.ZipArchiveEntry]$Entry)

    $stream = $Entry.Open()
    try {
        $memory = New-Object System.IO.MemoryStream
        try {
            $stream.CopyTo($memory)
            return ,([byte[]]$memory.ToArray())
        }
        finally { $memory.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Get-ClagnosAppStateProfileLabelFromEntry {
    param([string]$EntryName)

    $normalized = ([string]$EntryName).Replace('\','/')
    if ($normalized -match '(?i)^payload/(?:profile-directories|profile-files|registry/user)/(?<label>manager|assistant)/') {
        return [string]$Matches.label.ToLowerInvariant()
    }
    return ''
}

function ConvertTo-ClagnosPortableAppStateString {
    param([string]$Value)

    $result = [string]$Value
    $result = [regex]::Replace($result, '(?i)[A-Z]:\\Users\\[^\\/"'']+', '%CLAGNOS_TARGET_PROFILE_PATH%')
    $result = [regex]::Replace($result, '(?i)[A-Z]:\\Program Files \(x86\)', '%CLAGNOS_PROGRAM_FILES_X86%')
    $result = [regex]::Replace($result, '(?i)[A-Z]:\\Program Files', '%CLAGNOS_PROGRAM_FILES%')
    $result = [regex]::Replace($result, '(?i)[A-Z]:\\ProgramData', '%CLAGNOS_PROGRAM_DATA%')
    $result = [regex]::Replace($result, '(?i)[A-Z]:\\Windows', '%CLAGNOS_WINDOWS_DIRECTORY%')
    $result = [regex]::Replace($result, '(?i)17\.0_[A-Za-z0-9]+', '%CLAGNOS_VS_INSTANCE_DIRECTORY%')
    $result = [regex]::Replace($result, '(?i)S-1-5-21-\d+-\d+-\d+-\d+', '%CLAGNOS_TARGET_USER_SID%')
    $result = [regex]::Replace($result, '(?i)(?<![A-Z0-9_])([A-Z]):\\', '%CLAGNOS_SYSTEM_DRIVE%\')
    $result = [regex]::Replace($result, '(?i)(?<![A-Z0-9_.-])' + [regex]::Escape([string]$env:COMPUTERNAME) + '(?![A-Z0-9_.-])', '%CLAGNOS_COMPUTER_NAME%')
    foreach ($address in @($script:ClagnosPackageStateSourceAddresses)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$address)) {
            $result = [regex]::Replace($result, '(?<![0-9.])' + [regex]::Escape([string]$address) + '(?![0-9.])', '%CLAGNOS_PRIMARY_IPV4_ADDRESS%')
        }
    }
    return [string]$result
}

function ConvertTo-ClagnosPortableAppStateObject {
    param([AllowNull()]$Value, [string]$PropertyName = '')

    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) { return (ConvertTo-ClagnosPortableAppStateString -Value ([string]$Value)) }
    if ($Value -is [System.Array]) {
        $items = @()
        foreach ($item in @($Value)) { $items += (ConvertTo-ClagnosPortableAppStateObject -Value $item -PropertyName $PropertyName) }
        return ,$items
    }
    if ($Value -is [pscustomobject]) {
        foreach ($property in @($Value.PSObject.Properties)) {
            if ([string]$property.Name -match '(?i)(password|secret|token|credential|auth|account|email|gaia|sign.?in|sync|client.?id|machine.?id|device.?id|sid|hostname|computername|subscription|tenant|user.?id)') {
                $Value.PSObject.Properties.Remove([string]$property.Name)
                continue
            }
            $property.Value = ConvertTo-ClagnosPortableAppStateObject -Value $property.Value -PropertyName ([string]$property.Name)
        }
        return $Value
    }
    return $Value
}

function ConvertTo-ClagnosPortableAppStatePayloadBytes {
    param([string]$EntryName, [byte[]]$Bytes)

    $extension = [IO.Path]::GetExtension([string]$EntryName).ToLowerInvariant()
    if ($extension -notin @('.json','.yml','.yaml','.xml','.ini','.config','.toml','.txt','.vssettings','.jcf','.jdf','.vpf','.vlcrc') -and [IO.Path]::GetFileName([string]$EntryName) -ne 'config') {
        return ,$Bytes
    }
    $memory = New-Object System.IO.MemoryStream(,([byte[]]$Bytes))
    $reader = New-Object System.IO.StreamReader($memory, [System.Text.Encoding]::UTF8, $true)
    try { $content = [string]$reader.ReadToEnd() }
    finally { $reader.Dispose(); $memory.Dispose() }
    if ($content.Contains([char]0)) { return ,$Bytes }

    if ($extension -eq '.json') {
        try {
            $document = ConvertFrom-Json -InputObject $content -ErrorAction Stop
            $document = ConvertTo-ClagnosPortableAppStateObject -Value $document
            $content = ConvertTo-Json -InputObject $document -Depth 100
        }
        catch {
            $content = ConvertTo-ClagnosPortableAppStateString -Value $content
        }
    }
    elseif ($extension -in @('.xml','.vssettings','.config')) {
        try {
            [xml]$document = $content
            $allNodes = @($document.SelectNodes('//*'))
            foreach ($node in $allNodes) {
                if ($null -eq $node -or $null -eq $node.ParentNode) { continue }
                if ([string]$node.LocalName -match '(?i)(password|secret|token|credential|authentication|auth|account|email|identity|user.?name|machine.?id|device.?id|computer.?name|hostname)') {
                    [void]$node.ParentNode.RemoveChild($node)
                    continue
                }
                foreach ($attribute in @($node.Attributes)) { $attribute.Value = ConvertTo-ClagnosPortableAppStateString -Value ([string]$attribute.Value) }
                foreach ($textNode in @($node.ChildNodes | Where-Object { $_.NodeType -in @([System.Xml.XmlNodeType]::Text,[System.Xml.XmlNodeType]::CDATA) })) {
                    $textNode.Value = ConvertTo-ClagnosPortableAppStateString -Value ([string]$textNode.Value)
                }
            }
            $content = [string]$document.OuterXml
        }
        catch {
            $content = ConvertTo-ClagnosPortableAppStateString -Value $content
        }
    }
    else {
        $content = ConvertTo-ClagnosPortableAppStateString -Value $content
        if ($extension -in @('.ini','.jcf','.jdf','.vpf','.vlcrc','.toml','.yml','.yaml','.reg','.properties') -or [IO.Path]::GetFileName([string]$EntryName) -eq 'config') {
            $lines = New-Object 'System.Collections.Generic.List[string]'
            $skipRecentSection = $false
            foreach ($line in @($content -split '\r?\n')) {
                if ($extension -eq '.ini' -and $line -match '^\s*\[RecentsMRL\]\s*$') { $skipRecentSection = $true; continue }
                if ($skipRecentSection -and $line -match '^\s*\[') { $skipRecentSection = $false }
                if ($skipRecentSection) { continue }
                if ($line -match '^\s*[^#;\[].*?\s*(?:=|:).*?$' -and $line -match '(?i)(password|secret|token|credential|authentication|api.?key|private.?key|account|email|subscription|tenant|user.?id|(^|[._-])user(name)?\s*=)') { continue }
                $lines.Add([string]$line) | Out-Null
            }
            $content = @($lines.ToArray()) -join [Environment]::NewLine
        }
    }

    return ,([System.Text.Encoding]::UTF8.GetBytes([string]$content))
}

function Set-ClagnosPortablePackageSnapshot {
    param(
        [string]$PackageId,
        [hashtable]$FileRules
    )

    $zipPath = Join-Path $packageRoot (Join-Path 'builtin\windows' (Join-Path $PackageId 'app-state\app-state.zip'))
    if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
        Write-Output ("{0}: policy updated; no local snapshot payload is present" -f $PackageId)
        return
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $sourceArchive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    $temporaryZip = $zipPath + '.generalized'
    if (Test-Path -LiteralPath $temporaryZip) { Remove-Item -LiteralPath $temporaryZip -Force }
    $targetArchive = $null
    $profileFiles = New-Object 'System.Collections.Generic.List[object]'
    try {
        $oldManifestEntry = $sourceArchive.GetEntry('app-state.manifest.json')
        if ($null -eq $oldManifestEntry) { throw ("Snapshot has no app-state manifest: {0}" -f $PackageId) }
        $reader = New-Object System.IO.StreamReader($oldManifestEntry.Open())
        try { $oldManifest = ConvertFrom-Json -InputObject $reader.ReadToEnd() -ErrorAction Stop }
        finally { $reader.Dispose() }

        $existingPayload = @($sourceArchive.Entries | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Name) })
        $hasDynamicArchiveSourcePath = @($oldManifest.profileFiles | Where-Object { [string]$_.sourcePath -match '%CLAGNOS_[A-Z0-9_]+%' }).Count -gt 0
        if ($PackageId -ne 'azure-developer-cli' -and -not $hasDynamicArchiveSourcePath -and @($oldManifest.profileFiles).Count -gt 0 -and @($oldManifest.profileDirectories).Count -eq 0 -and @($oldManifest.registryImports).Count -eq 0 -and
            @($existingPayload | Where-Object { -not [string]::Equals([string]$_.FullName, 'app-state.manifest.json', [System.StringComparison]::OrdinalIgnoreCase) -and -not [string]$_.FullName.StartsWith('payload/profile-files/', [System.StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) {
            Write-Output ("{0}: snapshot is already in the portable profile-file format" -f $PackageId)
            return
        }

        $targetArchive = [System.IO.Compression.ZipFile]::Open($temporaryZip, [System.IO.Compression.ZipArchiveMode]::Create)
        foreach ($profileLabel in @($FileRules.Keys | Sort-Object)) {
            foreach ($rule in @($FileRules[$profileLabel])) {
                $destinationPath = [string]$rule.Destination
                $candidate = @($sourceArchive.Entries | Where-Object {
                    -not [string]::IsNullOrWhiteSpace([string]$_.Name) -and
                    [string]::Equals((Get-ClagnosAppStateProfileLabelFromEntry -EntryName ([string]$_.FullName)), [string]$profileLabel, [System.StringComparison]::OrdinalIgnoreCase) -and
                    ([string]$_.FullName).Replace('\','/') -match [string]$rule.Pattern
                } | Sort-Object { $_.FullName.Length }, FullName | Select-Object -First 1)
                if (@($candidate).Count -lt 1) { continue }

                if ($destinationPath.Contains('%FILE_NAME%')) { $destinationPath = $destinationPath.Replace('%FILE_NAME%', [IO.Path]::GetFileName([string]$candidate[0].FullName)) }
                $sourceLeaf = [IO.Path]::GetFileName($destinationPath)
                $payloadPath = ('payload/profile-files/{0}/{1}' -f [string]$profileLabel, $sourceLeaf)
                $newEntry = $targetArchive.CreateEntry($payloadPath, [System.IO.Compression.CompressionLevel]::Optimal)
                $payloadBytes = ConvertTo-ClagnosPortableAppStatePayloadBytes -EntryName ([string]$candidate[0].FullName) -Bytes (Get-ClagnosArchiveEntryBytes -Entry $candidate[0])
                $outStream = $newEntry.Open()
                try { $outStream.Write([byte[]]$payloadBytes, 0, ([byte[]]$payloadBytes).Length) }
                finally { $outStream.Dispose() }

                $profileFiles.Add([ordered]@{
                    sourcePath = [string]$payloadPath
                    relativeDestinationPath = [string]$destinationPath
                    targetProfiles = @([string]$profileLabel)
                }) | Out-Null
            }
        }

        if ([int]$profileFiles.Count -eq 0) { throw ("Snapshot curation retained no files for package '{0}'." -f $PackageId) }
        $newManifest = [ordered]@{
            version = 3
            taskName = [string]$oldManifest.taskName
            machineDirectories = @()
            machineFiles = @()
            profileDirectories = @()
            profileFiles = @($profileFiles.ToArray())
            registryImports = @()
        }
        $manifestEntry = $targetArchive.CreateEntry('app-state.manifest.json', [System.IO.Compression.CompressionLevel]::Optimal)
        $manifestStream = $manifestEntry.Open()
        try {
            $manifestBytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $newManifest -Depth 40))
            $manifestStream.Write($manifestBytes, 0, $manifestBytes.Length)
        }
        finally { $manifestStream.Dispose() }
    }
    finally {
        if ($null -ne $targetArchive) { $targetArchive.Dispose() }
        $sourceArchive.Dispose()
    }

    if ($Apply) {
        Move-Item -LiteralPath $temporaryZip -Destination $zipPath -Force
    }
    else {
        Remove-Item -LiteralPath $temporaryZip -Force
    }
    Write-Output ("{0}: curated {1} portable preference files" -f $PackageId, [int]$profileFiles.Count)
}

$dropAppState = @(
    'anydesk','be-my-eyes','chocolatey','codex-app','docker-desktop','google-chrome','google-drive',
    'github-copilot-cli','icloud','itunes','microsoft-edge','microsoft-teams','onedrive','rclone','whatsapp','windscribe'
)
foreach ($id in @($dropAppState)) { Set-ClagnosPackageAppStatePolicy -PackageId $id -AppState $null -RemoveSnapshot }

$policies = [ordered]@{
    'azure-cli' = [ordered]@{
        profileFiles = @((New-ClagnosProfileFileRule -Path '.azure\config'))
        removeSnapshot = $false
    }
    'azure-developer-cli' = [ordered]@{
        profileFiles = @((New-ClagnosProfileFileRule -Path '.azd\config.json'))
        removeSnapshot = $false
    }
    'github-cli' = [ordered]@{
        profileFiles = @((New-ClagnosProfileFileRule -Path 'AppData\Roaming\GitHub CLI\config.yml'))
        removeSnapshot = $false
    }
    'visual-studio-code' = [ordered]@{
        profileFiles = @(
            (New-ClagnosProfileFileRule -Path 'AppData\Roaming\Code\User\settings.json'),
            (New-ClagnosProfileFileRule -Path 'AppData\Roaming\Code\User\keybindings.json')
        )
        removeSnapshot = $false
    }
    'visual-studio-community' = [ordered]@{
        profileFiles = @((New-ClagnosProfileFileRule -Path 'AppData\Local\Microsoft\VisualStudio\17.0_*\Settings\CurrentSettings.vssettings'))
        removeSnapshot = $false
    }
    'nvda' = [ordered]@{
        profileFiles = @((New-ClagnosProfileFileRule -Path 'AppData\Roaming\nvda\nvda.ini'))
        removeSnapshot = $false
    }
    'jaws' = [ordered]@{
        profileFiles = @(
            (New-ClagnosProfileFileRule -Path 'AppData\Roaming\Freedom Scientific\JAWS\2025\Settings\enu\DEFAULT.JCF' -TargetProfiles @('manager')),
            (New-ClagnosProfileFileRule -Path 'AppData\Roaming\Freedom Scientific\JAWS\2025\Settings\enu\DEFAULT.JDF' -TargetProfiles @('manager')),
            (New-ClagnosProfileFileRule -Path 'AppData\Roaming\Freedom Scientific\JAWS\2025\Settings\VoiceProfiles\*.VPF' -TargetProfiles @('manager'))
        )
        removeSnapshot = $false
    }
    'vlc' = [ordered]@{
        profileFiles = @(
            (New-ClagnosProfileFileRule -Path 'AppData\Roaming\vlc\vlcrc'),
            (New-ClagnosProfileFileRule -Path 'AppData\Roaming\vlc\vlc-qt-interface.ini')
        )
        removeSnapshot = $false
    }
    'windows-subsystem-linux' = [ordered]@{
        profileFiles = @((New-ClagnosProfileFileRule -Path '.wslconfig'))
        removeSnapshot = $true
    }
    'google-gemini-cli' = [ordered]@{
        profileFiles = @((New-ClagnosProfileFileRule -Path '.gemini\settings.json'))
        removeSnapshot = $true
    }
    'openai-codex-cli' = [ordered]@{
        profileFiles = @((New-ClagnosProfileFileRule -Path '.codex\config.toml'))
        removeSnapshot = $true
    }
    'ollama' = [ordered]@{
        profileFiles = @(
            (New-ClagnosProfileFileRule -Path 'AppData\Roaming\ollama app.exe\config.json'),
            (New-ClagnosProfileFileRule -Path 'AppData\Roaming\Ollama\config.json'),
            (New-ClagnosProfileFileRule -Path 'AppData\Local\Ollama\config.json')
        )
        removeSnapshot = $true
    }
}

foreach ($id in @($policies.Keys)) {
    $state = [ordered]@{
        machineDirectories = @()
        machineFiles = @()
        profileDirectories = @()
        profileFiles = @($policies[$id].profileFiles)
        machineRegistryKeys = @()
        userRegistryKeys = @()
    }
    Set-ClagnosPackageAppStatePolicy -PackageId $id -AppState $state -RemoveSnapshot:([bool]$policies[$id].removeSnapshot)
}

$snapshotRules = [ordered]@{
    'azure-cli' = @{ manager = @(@{ Pattern = '(?i)(?:/\.azure/config|\.azure_config)$'; Destination = '.azure\config' }) }
    'azure-developer-cli' = @{ manager = @(@{ Pattern = '(?i)(?:/\.azd/config\.json|\.azd_config\.json)$'; Destination = '.azd\config.json' }); assistant = @(@{ Pattern = '(?i)(?:/\.azd/config\.json|\.azd_config\.json)$'; Destination = '.azd\config.json' }) }
    'github-cli' = @{ manager = @(@{ Pattern = '(?i)(?:GitHub_CLI/config\.yml|GitHub[_ ]CLI_config\.yml)$'; Destination = 'AppData\Roaming\GitHub CLI\config.yml' }); assistant = @(@{ Pattern = '(?i)(?:GitHub_CLI/config\.yml|GitHub[_ ]CLI_config\.yml)$'; Destination = 'AppData\Roaming\GitHub CLI\config.yml' }) }
    'visual-studio-code' = @{
        manager = @(
            @{ Pattern = '(?i)Code_User(?:/(?:AppData_Roaming_Code_User/)?)?settings\.json$|Code_User_settings\.json$'; Destination = 'AppData\Roaming\Code\User\settings.json' },
            @{ Pattern = '(?i)Code_User(?:/(?:AppData_Roaming_Code_User/)?)?keybindings\.json$|Code_User_keybindings\.json$'; Destination = 'AppData\Roaming\Code\User\keybindings.json' }
        )
        assistant = @(
            @{ Pattern = '(?i)Code_User(?:/(?:AppData_Roaming_Code_User/)?)?settings\.json$|Code_User_settings\.json$'; Destination = 'AppData\Roaming\Code\User\settings.json' },
            @{ Pattern = '(?i)Code_User(?:/(?:AppData_Roaming_Code_User/)?)?keybindings\.json$|Code_User_keybindings\.json$'; Destination = 'AppData\Roaming\Code\User\keybindings.json' }
        )
    }
    'visual-studio-community' = @{ manager = @(@{ Pattern = '(?i)(?:Microsoft_VisualStudio/[^/]+/Settings/CurrentSettings\.vssettings|Microsoft_VisualStudio_.*_Settings_CurrentSettings\.vssettings)$'; Destination = 'AppData\Local\Microsoft\VisualStudio\%CLAGNOS_VS_INSTANCE_DIRECTORY%\Settings\CurrentSettings.vssettings' }) }
    'nvda' = @{ manager = @(@{ Pattern = '(?i)(?:AppData_Roaming_nvda/nvda\.ini|AppData_Roaming_nvda_nvda\.ini)$'; Destination = 'AppData\Roaming\nvda\nvda.ini' }) }
    'jaws' = @{ manager = @(
        @{ Pattern = '(?i)(?:Freedom_Scientific_JAWS_2025_Settings/enu/DEFAULT\.JCF|Freedom Scientific_JAWS_2025_Settings_enu_DEFAULT\.JCF)$'; Destination = 'AppData\Roaming\Freedom Scientific\JAWS\2025\Settings\enu\DEFAULT.JCF' },
        @{ Pattern = '(?i)(?:Freedom_Scientific_JAWS_2025_Settings/enu/DEFAULT\.JDF|Freedom Scientific_JAWS_2025_Settings_enu_DEFAULT\.JDF)$'; Destination = 'AppData\Roaming\Freedom Scientific\JAWS\2025\Settings\enu\DEFAULT.JDF' },
        @{ Pattern = '(?i)(?:Freedom_Scientific_JAWS_2025_Settings/VoiceProfiles/Eloquence\.VPF|Freedom Scientific_JAWS_2025_Settings_VoiceProfiles_Eloquence\.VPF)$'; Destination = 'AppData\Roaming\Freedom Scientific\JAWS\2025\Settings\VoiceProfiles\Eloquence.VPF' },
        @{ Pattern = '(?i)(?:Freedom_Scientific_JAWS_2025_Settings/VoiceProfiles/SAPI 5X 64\.VPF|Freedom Scientific_JAWS_2025_Settings_VoiceProfiles_SAPI 5X 64\.VPF)$'; Destination = 'AppData\Roaming\Freedom Scientific\JAWS\2025\Settings\VoiceProfiles\SAPI 5X 64.VPF' }
    ) }
    'vlc' = @{ manager = @(
        @{ Pattern = '(?i)(?:AppData_Roaming_vlc/vlcrc|AppData_Roaming_vlc_vlcrc)$'; Destination = 'AppData\Roaming\vlc\vlcrc' },
        @{ Pattern = '(?i)(?:AppData_Roaming_vlc/vlc-qt-interface\.ini|AppData_Roaming_vlc_vlc-qt-interface\.ini)$'; Destination = 'AppData\Roaming\vlc\vlc-qt-interface.ini' }
    ) }
}

foreach ($id in @($snapshotRules.Keys)) {
    if (-not $Apply) { Write-Output ("{0}: snapshot would be curated" -f $id); continue }
    Set-ClagnosPortablePackageSnapshot -PackageId $id -FileRules $snapshotRules[$id]
}

if ($Apply) { Write-Output 'Package app-state maintenance completed.' }
else { Write-Output 'Dry run only. Re-run with -Apply to write manifests and snapshots.' }
