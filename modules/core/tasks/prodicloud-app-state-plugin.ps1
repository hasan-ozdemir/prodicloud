# Shared vm-update app-state plugin helpers.

function Get-ProdicloudTaskAppStateIdentity {
    param([psobject]$TaskBlock)

    if ($null -eq $TaskBlock) { return '' }
    if ($TaskBlock.PSObject.Properties.Match('AppStateKey').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$TaskBlock.AppStateKey)) {
        return [string]$TaskBlock.AppStateKey
    }
    if ($TaskBlock.PSObject.Properties.Match('Name').Count -gt 0) { return [string]$TaskBlock.Name }
    return ''
}

function Initialize-ProdicloudAppStateZipSupport {
    if (-not ([System.Management.Automation.PSTypeName]'System.IO.Compression.ZipArchive').Type) {
        Add-Type -AssemblyName 'System.IO.Compression.FileSystem' -ErrorAction SilentlyContinue
        Add-Type -AssemblyName 'System.IO.Compression' -ErrorAction SilentlyContinue
    }
}

function Get-ProdicloudTaskStageRootDirectoryPath {
    param([psobject]$TaskBlock)

    if ($null -eq $TaskBlock) {
        return ''
    }

    if ($TaskBlock.PSObject.Properties.Match('StageRootDirectoryPath').Count -gt 0) {
        $stageRootPath = [string]$TaskBlock.StageRootDirectoryPath
        if (-not [string]::IsNullOrWhiteSpace([string]$stageRootPath)) {
            return [string]$stageRootPath
        }
    }

    $taskRootPath = ''
    if ($TaskBlock.PSObject.Properties.Match('TaskRootPath').Count -gt 0) {
        $taskRootPath = [string]$TaskBlock.TaskRootPath
    }
    if ([string]::IsNullOrWhiteSpace([string]$taskRootPath) -and $TaskBlock.PSObject.Properties.Match('DirectoryPath').Count -gt 0) {
        $taskRootPath = [string]$TaskBlock.DirectoryPath
    }

    if ([string]::IsNullOrWhiteSpace([string]$taskRootPath)) {
        return ''
    }

    $relativePath = ''
    if ($TaskBlock.PSObject.Properties.Match('RelativePath').Count -gt 0) {
        $relativePath = [string]$TaskBlock.RelativePath
    }
    if ([string]::IsNullOrWhiteSpace([string]$relativePath)) {
        return [string](Split-Path -Path $taskRootPath -Parent)
    }

    $normalizedRelative = $relativePath.Replace('\', '/')
    $segments = @($normalizedRelative.Split('/') | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if (@($segments).Count -lt 2) {
        return [string](Split-Path -Path $taskRootPath -Parent)
    }

    $stageRootPath = [string]$taskRootPath
    for ($i = 1; $i -lt @($segments).Count; $i++) {
        $stageRootPath = [string](Split-Path -Path $stageRootPath -Parent)
    }

    return [string]$stageRootPath
}

function Get-ProdicloudTaskAppStateRootDirectoryPath {
    param([psobject]$TaskBlock)

    $taskRootPath = ''
    if ($null -ne $TaskBlock -and $TaskBlock.PSObject.Properties.Match('TaskRootPath').Count -gt 0) {
        $taskRootPath = [string]$TaskBlock.TaskRootPath
    }
    if ([string]::IsNullOrWhiteSpace([string]$taskRootPath) -and $null -ne $TaskBlock -and $TaskBlock.PSObject.Properties.Match('DirectoryPath').Count -gt 0) {
        $taskRootPath = [string]$TaskBlock.DirectoryPath
    }
    if ([string]::IsNullOrWhiteSpace([string]$taskRootPath)) {
        return ''
    }

    return (Join-Path $taskRootPath 'app-state')
}

function Get-ProdicloudTaskAppStateBackupScopeDirectoryPath {
    param([psobject]$TaskBlock)

    if ($null -eq $TaskBlock) {
        return ''
    }

    $stageRootPath = Get-ProdicloudTaskStageRootDirectoryPath -TaskBlock $TaskBlock
    if ([string]::IsNullOrWhiteSpace([string]$stageRootPath)) {
        $taskRootPath = ''
        if ($TaskBlock.PSObject.Properties.Match('TaskRootPath').Count -gt 0) {
            $taskRootPath = [string]$TaskBlock.TaskRootPath
        }
        if ([string]::IsNullOrWhiteSpace([string]$taskRootPath) -and $TaskBlock.PSObject.Properties.Match('DirectoryPath').Count -gt 0) {
            $taskRootPath = [string]$TaskBlock.DirectoryPath
        }
        if ([string]::IsNullOrWhiteSpace([string]$taskRootPath)) {
            return ''
        }

        return [string](Split-Path -Path $taskRootPath -Parent)
    }

    $relativePath = ''
    if ($TaskBlock.PSObject.Properties.Match('RelativePath').Count -gt 0) {
        $relativePath = [string]$TaskBlock.RelativePath
    }

    if ([string]::Equals([string]$TaskBlock.TaskType, 'package', [System.StringComparison]::OrdinalIgnoreCase)) {
        return [string]$stageRootPath
    }
    $catalog = if ($TaskBlock.PSObject.Properties.Match('Catalog').Count -gt 0) { [string]$TaskBlock.Catalog } else { '' }
    if ($catalog -notin @('builtin','custom')) {
        $normalizedRelative = $relativePath.Replace('\', '/').TrimStart('/')
        if ($normalizedRelative -match '^(?<catalog>builtin|custom)/') { $catalog = [string]$Matches.catalog }
    }
    if ($catalog -notin @('builtin','custom')) { throw 'Task catalog source could not be resolved for app-state backup.' }
    return (Join-Path $stageRootPath $catalog)
}

function Get-ProdicloudTaskAppStateBackupRootDirectoryPath {
    param([psobject]$TaskBlock)

    if ($null -eq $TaskBlock) {
        return ''
    }

    $taskName = ''
    if ($TaskBlock.PSObject.Properties.Match('Name').Count -gt 0) {
        $taskName = Get-ProdicloudTaskAppStateIdentity -TaskBlock $TaskBlock
    }
    if ([string]::IsNullOrWhiteSpace([string]$taskName)) {
        return ''
    }

    $scopeDirectory = Get-ProdicloudTaskAppStateBackupScopeDirectoryPath -TaskBlock $TaskBlock
    if ([string]::IsNullOrWhiteSpace([string]$scopeDirectory)) {
        return ''
    }

    return (Join-Path (Join-Path $scopeDirectory 'backup-app-states') $taskName)
}

function Get-ProdicloudTaskAppStatePluginDirectoryPath {
    param([psobject]$TaskBlock)

    return (Get-ProdicloudTaskAppStateRootDirectoryPath -TaskBlock $TaskBlock)
}

function Get-ProdicloudTaskAppStateZipPath {
    param([psobject]$TaskBlock)

    $pluginDirectory = Get-ProdicloudTaskAppStatePluginDirectoryPath -TaskBlock $TaskBlock
    if ([string]::IsNullOrWhiteSpace([string]$pluginDirectory)) {
        return ''
    }

    return (Join-Path $pluginDirectory 'app-state.zip')
}

function Get-ProdicloudAppStateGuestHelperPath {
    return (Join-Path $PSScriptRoot 'prodicloud-app-state-guest.psm1')
}

function Get-ProdicloudZipArchiveEntryByName {
    param(
        [object]$Archive,
        [string]$EntryName
    )

    if ($null -eq $Archive -or [string]::IsNullOrWhiteSpace([string]$EntryName)) {
        return $null
    }

    foreach ($entry in @($Archive.Entries)) {
        if ($null -eq $entry) {
            continue
        }

        if ([string]::Equals([string]$entry.FullName, [string]$EntryName, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $entry
        }
    }

    return $null
}

function Get-ProdicloudTaskAppStateManifestFromZip {
    param(
        [string]$ZipPath,
        [string]$ExpectedTaskName
    )

    Initialize-ProdicloudAppStateZipSupport

    if ([string]::IsNullOrWhiteSpace([string]$ZipPath) -or -not (Test-Path -LiteralPath $ZipPath)) {
        throw ("App-state zip was not found: {0}" -f [string]$ZipPath)
    }

    $archive = $null
    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        $manifestEntry = Get-ProdicloudZipArchiveEntryByName -Archive $archive -EntryName 'app-state.manifest.json'
        if ($null -eq $manifestEntry) {
            throw 'app-state.manifest.json was not found at the zip root.'
        }

        $reader = New-Object System.IO.StreamReader($manifestEntry.Open())
        try {
            $manifestText = [string]$reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }

        if ([string]::IsNullOrWhiteSpace([string]$manifestText)) {
            throw 'app-state.manifest.json is empty.'
        }

        $manifest = ConvertFrom-JsonCompat -InputObject $manifestText
        if ($null -eq $manifest) {
            throw 'app-state.manifest.json could not be parsed.'
        }

        $version = 0
        if ($manifest.PSObject.Properties.Match('version').Count -gt 0) {
            try {
                $version = [int]$manifest.version
            }
            catch {
                $version = 0
            }
        }
        if ($version -lt 1) {
            throw 'app-state manifest version must be >= 1.'
        }

        $taskName = ''
        if ($manifest.PSObject.Properties.Match('taskName').Count -gt 0) {
            $taskName = [string]$manifest.taskName
        }
        if ([string]::IsNullOrWhiteSpace([string]$taskName)) {
            throw 'app-state manifest taskName is required.'
        }
        if (-not [string]::Equals([string]$taskName, [string]$ExpectedTaskName, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw ("app-state manifest taskName '{0}' does not match task '{1}'." -f [string]$taskName, [string]$ExpectedTaskName)
        }

        return [pscustomobject]@{
            Version = [int]$version
            TaskName = [string]$taskName
            Manifest = $manifest
        }
    }
    finally {
        if ($null -ne $archive) {
            $archive.Dispose()
        }
    }
}

function Get-ProdicloudTaskAppStatePluginInfo {
    param([psobject]$TaskBlock)

    $taskName = Get-ProdicloudTaskAppStateIdentity -TaskBlock $TaskBlock
    $pluginDirectory = Get-ProdicloudTaskAppStatePluginDirectoryPath -TaskBlock $TaskBlock
    $zipPath = Get-ProdicloudTaskAppStateZipPath -TaskBlock $TaskBlock
    $guestHelperPath = Get-ProdicloudAppStateGuestHelperPath

    if ([string]::IsNullOrWhiteSpace([string]$pluginDirectory) -or [string]::IsNullOrWhiteSpace([string]$taskName)) {
        return [pscustomobject]@{
            TaskName = [string]$taskName
            PluginDirectory = [string]$pluginDirectory
            ZipPath = [string]$zipPath
            GuestHelperPath = [string]$guestHelperPath
            Status = 'invalid'
            Message = 'Task app-state plugin root could not be resolved.'
            Manifest = $null
        }
    }

    if (-not (Test-Path -LiteralPath $pluginDirectory)) {
        return [pscustomobject]@{
            TaskName = [string]$taskName
            PluginDirectory = [string]$pluginDirectory
            ZipPath = [string]$zipPath
            GuestHelperPath = [string]$guestHelperPath
            Status = 'missing-plugin'
            Message = 'no plugin'
            Manifest = $null
        }
    }

    if (-not (Test-Path -LiteralPath $zipPath)) {
        return [pscustomobject]@{
            TaskName = [string]$taskName
            PluginDirectory = [string]$pluginDirectory
            ZipPath = [string]$zipPath
            GuestHelperPath = [string]$guestHelperPath
            Status = 'missing-zip'
            Message = 'plugin folder exists but app-state.zip is missing'
            Manifest = $null
        }
    }

    try {
        $manifestInfo = Get-ProdicloudTaskAppStateManifestFromZip -ZipPath $zipPath -ExpectedTaskName $taskName
        return [pscustomobject]@{
            TaskName = [string]$taskName
            PluginDirectory = [string]$pluginDirectory
            ZipPath = [string]$zipPath
            GuestHelperPath = [string]$guestHelperPath
            Status = 'ready'
            Message = 'ready'
            Manifest = $manifestInfo.Manifest
        }
    }
    catch {
        return [pscustomobject]@{
            TaskName = [string]$taskName
            PluginDirectory = [string]$pluginDirectory
            ZipPath = [string]$zipPath
            GuestHelperPath = [string]$guestHelperPath
            Status = 'invalid'
            Message = [string]$_.Exception.Message
            Manifest = $null
        }
    }
}

function Add-ProdicloudAppStatePortableJsonKeyFindings {
    param([AllowNull()]$Value, [System.Collections.Generic.List[string]]$Findings)

    if ($null -eq $Value) { return }
    if ($Value -is [pscustomobject]) {
        foreach ($property in @($Value.PSObject.Properties)) {
            if ([string]$property.Name -match '(?i)(password|secret|token|credential|api.?key|private.?key|account|email|gaia|sign.?in|client.?id|machine.?id|device.?id|subscription|tenant|user.?id)') {
                $Findings.Add([string]$property.Name) | Out-Null
            }
            Add-ProdicloudAppStatePortableJsonKeyFindings -Value $property.Value -Findings $Findings
        }
    }
    elseif ($Value -is [array]) {
        foreach ($item in @($Value)) { Add-ProdicloudAppStatePortableJsonKeyFindings -Value $item -Findings $Findings }
    }
}

function Assert-ProdicloudPackageAppStateArchivePortable {
    param([string]$ZipPath)

    if ([string]::IsNullOrWhiteSpace([string]$ZipPath) -or -not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) {
        throw 'Package app-state archive is missing.'
    }
    Initialize-ProdicloudAppStateZipSupport
    $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $manifestEntry = Get-ProdicloudZipArchiveEntryByName -Archive $archive -EntryName 'app-state.manifest.json'
        if ($null -eq $manifestEntry) { throw 'Package app-state archive has no app-state manifest.' }
        $manifestReader = New-Object System.IO.StreamReader($manifestEntry.Open())
        try { $manifest = ConvertFrom-Json -InputObject ([string]$manifestReader.ReadToEnd()) -ErrorAction Stop }
        finally { $manifestReader.Dispose() }
        if ($null -eq $manifest -or [int]$manifest.version -lt 1) { throw 'Package app-state archive has an invalid manifest.' }
        foreach ($registryEntry in @($manifest.registryImports)) {
            if ($null -eq $registryEntry) { continue }
            if (-not [string]::Equals([string]$registryEntry.scope, 'user', [System.StringComparison]::OrdinalIgnoreCase)) {
                throw 'Package app-state must not import machine-wide registry state.'
            }
            if ([string]$registryEntry.registryPath -notmatch '(?i)^(?:HKCU|HKEY_CURRENT_USER)\\') {
                throw 'Package app-state registry imports must target a selected user hive.'
            }
            if (@($registryEntry.targetProfiles | Where-Object { [string]$_ -in @('manager','assistant') }).Count -lt 1) {
                throw 'Package app-state user registry imports must explicitly target manager or assistant.'
            }
        }

        $allowedPlaceholders = @(
            'PRODICLOUD_COMPUTER_NAME','PRODICLOUD_SYSTEM_DRIVE','PRODICLOUD_SYSTEM_ROOT','PRODICLOUD_WINDOWS_DIRECTORY',
            'PRODICLOUD_PROGRAM_DATA','PRODICLOUD_PROGRAM_FILES','PRODICLOUD_PROGRAM_FILES_X86','PRODICLOUD_PRIMARY_IPV4_ADDRESS',
            'PRODICLOUD_TARGET_CPU_COUNT','PRODICLOUD_TARGET_MEMORY_GB','PRODICLOUD_VM_ADMIN_USER','PRODICLOUD_ASSISTANT_USER',
            'PRODICLOUD_TARGET_USER','PRODICLOUD_TARGET_PROFILE_PATH','PRODICLOUD_TARGET_HOME','PRODICLOUD_TARGET_USER_SID',
            'PRODICLOUD_TARGET_UID','PRODICLOUD_TARGET_GID','PRODICLOUD_VM_ADMIN_PROFILE_PATH','PRODICLOUD_ASSISTANT_PROFILE_PATH',
            'PRODICLOUD_VM_ADMIN_HOME','PRODICLOUD_ASSISTANT_HOME','PRODICLOUD_VM_ADMIN_UID','PRODICLOUD_ASSISTANT_UID',
            'PRODICLOUD_VM_ADMIN_GID','PRODICLOUD_ASSISTANT_GID','PRODICLOUD_VM_ADMIN_USER_SID','PRODICLOUD_ASSISTANT_USER_SID',
            'PRODICLOUD_LOCAL_APP_DATA','PRODICLOUD_ROAMING_APP_DATA','PRODICLOUD_VS_INSTANCE_DIRECTORY'
        )
        $allowedSet = @{}
        foreach ($placeholder in $allowedPlaceholders) { $allowedSet[$placeholder] = $true }
        $manifestJson = ConvertTo-Json -InputObject $manifest -Depth 40 -Compress
        if ([regex]::IsMatch($manifestJson, '(?i)[A-Z]:\\Users\\[^\\/\s"'']+|S-1-5-21-\d+-\d+-\d+-\d+|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|[A-Z]:\\[^\s"'']{2,}')) {
            throw 'Package app-state manifest contains an un-generalized profile or machine path.'
        }
        foreach ($match in @([regex]::Matches($manifestJson, '%PRODICLOUD_[A-Z0-9_]+%'))) {
            if (-not $allowedSet.ContainsKey([string]$match.Groups[0].Value.Trim('%'))) { throw 'Package app-state manifest contains an unsupported target placeholder.' }
        }
        $forbiddenMemberPattern = '(?i)(auth\.json|cache\.bin|hosts\.yml|cookies|login data|history|workspacestorage|\.npmrc|\.db$|onedrive|whatsapp|local state|secure preferences)'
        foreach ($entry in @($archive.Entries)) {
            if ([string]$entry.FullName -match $forbiddenMemberPattern) { throw 'Package app-state archive contains a login, history, workspace, or cache file.' }
            if ($entry.Length -le 0 -or $entry.Length -gt 5000000 -or [string]::Equals([string]$entry.FullName, 'app-state.manifest.json', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            $extension = [System.IO.Path]::GetExtension([string]$entry.Name).ToLowerInvariant()
            if ($extension -notin @('.json','.xml','.ini','.yml','.yaml','.toml','.txt','.config','.properties','.vssettings','.jcf','.jdf','.jss','.jkm','.jsb','.jsd','.vpf','.vlcrc') -and [string]$entry.Name -ne 'config') { continue }
            if ($extension -eq '.jsb') {
                $binaryStream = $entry.Open()
                try {
                    $binaryMemory = New-Object System.IO.MemoryStream
                    try {
                        $binaryStream.CopyTo($binaryMemory)
                        $binaryBytes = [byte[]]$binaryMemory.ToArray()
                    }
                    finally { $binaryMemory.Dispose() }
                }
                finally { $binaryStream.Dispose() }
                $binaryProbe = [System.Text.Encoding]::ASCII.GetString($binaryBytes) + [System.Text.Encoding]::Unicode.GetString($binaryBytes)
                if ([regex]::IsMatch($binaryProbe, '(?i)[A-Z]:\\Users\\[^\\/\s"'']+|S-1-5-21-\d+-\d+-\d+-\d+|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|[A-Z]:\\[^\s"'']{2,}')) {
                    throw ("Package app-state binary payload '{0}' contains source-machine identity or a machine-specific path." -f [string]$entry.Name)
                }
                continue
            }
            $reader = New-Object System.IO.StreamReader($entry.Open())
            try { $content = [string]$reader.ReadToEnd() }
            finally { $reader.Dispose() }
            if ($content.Contains([char]0)) { continue }
            if ([regex]::IsMatch($content, '(?i)[A-Z]:\\Users\\[^\\/\s"'']+|S-1-5-21-\d+-\d+-\d+-\d+|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')) {
                throw ("Package app-state payload '{0}' has an un-generalized profile, SID, or email value." -f [string]$entry.Name)
            }
            if ([regex]::IsMatch($content, '(?i)[A-Z]:\\[^\s"'']{2,}')) {
                throw ("Package app-state payload '{0}' has an un-generalized absolute drive path." -f [string]$entry.Name)
            }
            foreach ($match in @([regex]::Matches($content, '%PRODICLOUD_[A-Z0-9_]+%'))) {
                if (-not $allowedSet.ContainsKey([string]$match.Groups[0].Value.Trim('%'))) { throw 'Package app-state contains an unsupported target placeholder.' }
            }
            if ($extension -eq '.json') {
                try {
                    $document = ConvertFrom-Json -InputObject $content -ErrorAction Stop
                    $findings = New-Object 'System.Collections.Generic.List[string]'
                    Add-ProdicloudAppStatePortableJsonKeyFindings -Value $document -Findings $findings
                    if ($findings.Count -gt 0) { throw 'Package app-state JSON contains an authentication, account, or machine-identity field.' }
                }
                catch {
                    if ($_.Exception.Message -match '(?i)(authentication|account|machine-identity)') { throw }
                    throw ("Package app-state payload '{0}' is not valid JSON." -f [string]$entry.Name)
                }
            }
            elseif ($extension -in @('.xml','.vssettings','.config')) {
                try {
                    [xml]$xmlDocument = $content
                    $sensitiveNodes = @($xmlDocument.SelectNodes('//*') | Where-Object { [string]$_.LocalName -match '(?i)(password|secret|token|credential|authentication|api.?key|private.?key|account|email|identity|sign.?in|client.?id|machine.?id|device.?id|subscription|tenant)' })
                    if ($sensitiveNodes.Count -gt 0) { throw 'Package app-state XML contains an authentication, account, or machine-identity field.' }
                }
                catch {
                    if ($_.Exception.Message -match '(?i)(authentication|account|machine-identity)') { throw }
                    throw ("Package app-state payload '{0}' is not valid XML." -f [string]$entry.Name)
                }
            }
            elseif ($extension -in @('.ini','.yml','.yaml','.toml','.conf','.properties','.reg')) {
                $badSetting = @($content -split '\r?\n' | Where-Object { $_ -match '^\s*[^#;\[].*?\s*(?:=|:).*?$' -and $_ -match '(?i)(password|secret|token|credential|api.?key|private.?key|account|email|subscription|tenant|user.?id)' })
                if ($badSetting.Count -gt 0) { throw ("Package app-state payload '{0}' has an unsanitized credential or account field." -f [string]$entry.Name) }
            }
        }
    }
    finally { $archive.Dispose() }
}

function Get-ProdicloudTaskAppStateSelectedProfileTokens {
    param([string[]]$SelectedProfiles = @())

    $tokens = New-Object 'System.Collections.Generic.List[string]'
    $seen = @{}
    foreach ($rawProfile in @($SelectedProfiles)) {
        $value = if ($null -eq $rawProfile) { '' } else { [string]$rawProfile }
        if ([string]::IsNullOrWhiteSpace([string]$value)) {
            continue
        }

        $normalizedValue = $value.Trim().ToLowerInvariant()
        if ($seen.ContainsKey($normalizedValue)) {
            continue
        }

        $tokens.Add($normalizedValue) | Out-Null
        $seen[$normalizedValue] = $true
    }

    return @($tokens.ToArray())
}

function Test-ProdicloudTaskAppStateManifestEntryMatchesSelectedProfiles {
    param(
        [AllowNull()]$Entry,
        [string[]]$SelectedProfiles = @()
    )

    $normalizedSelections = @(Get-ProdicloudTaskAppStateSelectedProfileTokens -SelectedProfiles $SelectedProfiles)
    if (@($normalizedSelections).Count -lt 1) {
        return $true
    }

    if ($null -eq $Entry -or $Entry.PSObject.Properties.Match('targetProfiles').Count -lt 1) {
        return $false
    }

    foreach ($rawProfile in @($Entry.targetProfiles)) {
        $normalizedProfile = if ($null -eq $rawProfile) { '' } else { [string]$rawProfile.Trim().ToLowerInvariant() }
        if ([string]::IsNullOrWhiteSpace([string]$normalizedProfile)) {
            continue
        }
        if (@($normalizedSelections) -contains $normalizedProfile) {
            return $true
        }
    }

    return $false
}

function New-ProdicloudTaskAppStateFilteredZip {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceZipPath,
        [Parameter(Mandatory = $true)]
        [string]$TaskName,
        [Parameter(Mandatory = $true)]
        [string[]]$SelectedProfiles,
        [Parameter(Mandatory = $true)]
        [string]$DestinationZipPath
    )

    $normalizedSelections = @(Get-ProdicloudTaskAppStateSelectedProfileTokens -SelectedProfiles $SelectedProfiles)
    if (@($normalizedSelections).Count -lt 1) {
        Copy-Item -LiteralPath $SourceZipPath -Destination $DestinationZipPath -Force
        return [pscustomobject]@{
            ZipPath = [string]$DestinationZipPath
            Filtered = $false
            SelectionCount = 0
        }
    }

    $manifestInfo = Get-ProdicloudTaskAppStateManifestFromZip -ZipPath $SourceZipPath -ExpectedTaskName $TaskName
    $scratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('prodicloud-app-state-filter-{0}' -f ([guid]::NewGuid().ToString('N')))
    Ensure-ProdicloudAppStatePluginDirectory -Path $scratchRoot
    try {
        Initialize-ProdicloudAppStateZipSupport
        [System.IO.Compression.ZipFile]::ExtractToDirectory($SourceZipPath, $scratchRoot)

        $manifest = $manifestInfo.Manifest
        $profileDirectories = @($manifest.profileDirectories | Where-Object {
                Test-ProdicloudTaskAppStateManifestEntryMatchesSelectedProfiles -Entry $_ -SelectedProfiles $normalizedSelections
            })
        $profileFiles = @($manifest.profileFiles | Where-Object {
                Test-ProdicloudTaskAppStateManifestEntryMatchesSelectedProfiles -Entry $_ -SelectedProfiles $normalizedSelections
            })
        $registryImports = @()
        foreach ($entry in @($manifest.registryImports)) {
            if ($null -eq $entry) {
                continue
            }

            $scope = if ($entry.PSObject.Properties.Match('scope').Count -gt 0) { [string]$entry.scope } else { '' }
            if ([string]::Equals([string]$scope, 'user', [System.StringComparison]::OrdinalIgnoreCase)) {
                if (-not (Test-ProdicloudTaskAppStateManifestEntryMatchesSelectedProfiles -Entry $entry -SelectedProfiles $normalizedSelections)) {
                    continue
                }
            }
            $registryImports += $entry
        }

        $pathsToKeep = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        $pathsToKeep.Add('app-state.manifest.json') | Out-Null
        foreach ($entry in @($manifest.machineDirectories + $manifest.machineFiles + $profileDirectories + $profileFiles + $registryImports)) {
            if ($null -eq $entry -or $entry.PSObject.Properties.Match('sourcePath').Count -lt 1) {
                continue
            }
            $sourcePath = [string]$entry.sourcePath
            if ([string]::IsNullOrWhiteSpace([string]$sourcePath)) {
                continue
            }
            $pathsToKeep.Add($sourcePath.Replace('\', '/')) | Out-Null
        }

        foreach ($path in @(Get-ChildItem -LiteralPath $scratchRoot -Recurse -File | Sort-Object FullName)) {
            $relativePath = [string]([System.IO.Path]::GetRelativePath($scratchRoot, $path.FullName)).Replace('\', '/')
            if (-not $pathsToKeep.Contains($relativePath)) {
                Remove-Item -LiteralPath $path.FullName -Force -ErrorAction SilentlyContinue
            }
        }

        $updatedManifest = [ordered]@{
            version = $(if ($manifest.PSObject.Properties.Match('version').Count -gt 0) { [int]$manifest.version } else { 1 })
            taskName = [string]$manifest.taskName
            machineDirectories = @($manifest.machineDirectories)
            machineFiles = @($manifest.machineFiles)
            profileDirectories = @($profileDirectories)
            profileFiles = @($profileFiles)
            registryImports = @($registryImports)
        }
        Set-Content -LiteralPath (Join-Path $scratchRoot 'app-state.manifest.json') -Value (ConvertTo-JsonCompat -InputObject $updatedManifest -Depth 12) -Encoding UTF8

        Remove-Item -LiteralPath $DestinationZipPath -Force -ErrorAction SilentlyContinue
        $previousProgressPreference = $global:ProgressPreference
        try {
            $global:ProgressPreference = 'SilentlyContinue'
            Compress-Archive -LiteralPath @(Get-ChildItem -LiteralPath $scratchRoot -Force | Select-Object -ExpandProperty FullName) -DestinationPath $DestinationZipPath -Force
        }
        finally {
            $global:ProgressPreference = $previousProgressPreference
        }

        return [pscustomobject]@{
            ZipPath = [string]$DestinationZipPath
            Filtered = $true
            SelectionCount = @($normalizedSelections).Count
        }
    }
    finally {
        Remove-Item -LiteralPath $scratchRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-ProdicloudTaskAppStateRemoteZipPath {
    param(
        [string]$TaskName,
        [ValidateSet('windows','linux')][string]$Platform = 'windows'
    )

    $safeName = ([string]$TaskName -replace '[^A-Za-z0-9\-]', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace([string]$safeName)) {
        $safeName = 'task'
    }

    if ([string]::Equals([string]$Platform, 'linux', [System.StringComparison]::OrdinalIgnoreCase)) {
        return ('/tmp/prodicloud-app-state-{0}.zip' -f $safeName)
    }
    return ('C:/Windows/Temp/prodicloud-app-state-{0}.zip' -f $safeName)
}

function Get-ProdicloudTaskAppStateRemoteGuestHelperPath {
    param(
        [ValidateSet('windows','linux')]
        [string]$Platform
    )

    if ([string]::Equals([string]$Platform, 'linux', [System.StringComparison]::OrdinalIgnoreCase)) {
        return '/tmp/prodicloud-app-state-portability.py'
    }

    return 'C:/Windows/Temp/prodicloud-app-state-guest.psm1'
}

function Get-ProdicloudTaskAppStateLinuxPortabilityModulePath {
    return (Join-Path $PSScriptRoot 'prodicloud-app-state-portability.py')
}

function Get-ProdicloudTaskAppStateGuestScript {
    param(
        [string]$TaskName,
        [string]$RemoteZipPath,
        [string]$ManagerUser,
        [string]$AssistantUser
    )

    $taskNameSafe = [string]$TaskName.Replace("'", "''")
    $remoteZipPathSafe = [string]$RemoteZipPath.Replace("'", "''")
    $managerUserSafe = [string]$ManagerUser.Replace("'", "''")
    $assistantUserSafe = [string]$AssistantUser.Replace("'", "''")

    return @"
`$ErrorActionPreference = 'Stop'
`$modulePath = 'C:\Windows\Temp\prodicloud-app-state-guest.psm1'
if (-not (Test-Path -LiteralPath `$modulePath)) {
    throw ('Guest app-state helper was not found: {0}' -f `$modulePath)
}
Import-Module `$modulePath -Force -DisableNameChecking
`$result = Invoke-ProdicloudTaskAppStateReplay -ZipPath '$remoteZipPathSafe' -TaskName '$taskNameSafe' -ManagerUser '$managerUserSafe' -AssistantUser '$assistantUserSafe'
Write-Host ('app-state-summary => task={0}; machine-registry={1}; user-registry={2}; machine-directories={3}; machine-files={4}; profile-directories={5}; profile-files={6}; verified={7}; verify-checked={8}; verify-mismatches={9}; rollback-performed={10}; rollback-succeeded={11}' -f '$taskNameSafe', [int]`$result.MachineRegistryImports, [int]`$result.UserRegistryImports, [int]`$result.MachineDirectoryCopies, [int]`$result.MachineFileCopies, [int]`$result.ProfileDirectoryCopies, [int]`$result.ProfileFileCopies, [bool]`$result.Verified, [int]`$result.VerifyCheckedCount, [int]`$result.VerifyMismatchCount, [bool]`$result.RollbackPerformed, [bool]`$result.RollbackSucceeded)
Write-Host 'app-state-replay-completed'
"@
}

function Get-ProdicloudTaskAppStateLinuxGuestScript {
    param(
        [string]$TaskName,
        [string]$RemoteZipPath,
        [string]$ManagerUser,
        [string]$AssistantUser
    )

    $template = @'
set -euo pipefail
zip_path='__REMOTE_ZIP_PATH__'
task_name='__TASK_NAME__'
manager_user='__MANAGER_USER__'
assistant_user='__ASSISTANT_USER__'
scratch_root="$(mktemp -d /tmp/prodicloud-app-state.XXXXXX)"
cleanup() {
  rm -rf "$scratch_root"
  rm -f "$zip_path"
  rm -f /tmp/prodicloud-app-state-portability.py
}
trap cleanup EXIT
python_bin=''
if command -v python3 >/dev/null 2>&1; then
  python_bin="$(command -v python3)"
elif command -v python >/dev/null 2>&1; then
  python_bin="$(command -v python)"
else
  echo 'WARNING: app-state-linux-skip => python interpreter was not found.'
  exit 3
fi
"$python_bin" -B - "$zip_path" "$scratch_root" "$task_name" "$manager_user" "$assistant_user" <<'PY'
import json
import os
import shutil
import sys
import zipfile
sys.path.insert(0, '/tmp')
from prodicloud_app_state_portability import prepare_payload_for_restore

zip_path, scratch_root, task_name, manager_user, assistant_user = sys.argv[1:6]

def warn(message: str) -> None:
    print(f"WARNING: {message}")

def ensure_dir(path: str) -> None:
    if path:
        os.makedirs(path, exist_ok=True)

def copy_file(source_path: str, destination_path: str) -> bool:
    try:
        ensure_dir(os.path.dirname(destination_path))
        shutil.copy2(source_path, destination_path)
        return True
    except Exception as exc:
        warn(f"app-state-file-copy-skip => source={source_path}; destination={destination_path}; reason={exc}")
        return False

def copy_directory_contents(source_path: str, destination_path: str) -> bool:
    ensure_dir(destination_path)
    copied_any = False
    for child_name in sorted(os.listdir(source_path)):
        source_child = os.path.join(source_path, child_name)
        destination_child = os.path.join(destination_path, child_name)
        try:
            if os.path.isdir(source_child) and not os.path.islink(source_child):
                shutil.copytree(source_child, destination_child, dirs_exist_ok=True)
            else:
                ensure_dir(os.path.dirname(destination_child))
                shutil.copy2(source_child, destination_child)
            copied_any = True
        except Exception as exc:
            warn(f"app-state-directory-copy-skip => source={source_child}; destination={destination_path}; reason={exc}")
    return copied_any

with zipfile.ZipFile(zip_path) as archive:
    archive.extractall(scratch_root)

manifest_path = os.path.join(scratch_root, 'app-state.manifest.json')
if not os.path.exists(manifest_path):
    raise RuntimeError(f"App-state manifest was not found in expanded payload: {manifest_path}")

with open(manifest_path, 'r', encoding='utf-8') as handle:
    manifest = json.load(handle)

if str(manifest.get('taskName', '')).strip().lower() != task_name.strip().lower():
    raise RuntimeError(f"App-state manifest taskName '{manifest.get('taskName', '')}' does not match task '{task_name}'.")

manifest, profile_targets = prepare_payload_for_restore(scratch_root, manifest, manager_user, assistant_user)

def select_profile_targets(entry):
    target_profiles = [str(item).strip().lower() for item in entry.get('targetProfiles', []) if str(item).strip()]
    if not target_profiles:
        return profile_targets
    return [
        row for row in profile_targets
        if row[0].strip().lower() in target_profiles or (row[1] and row[1].strip().lower() in target_profiles)
    ]

machine_registry_imports = 0
user_registry_imports = 0
machine_directory_copies = 0
machine_file_copies = 0
profile_directory_copies = 0
profile_file_copies = 0

for entry in manifest.get('machineDirectories', []):
    source_path = os.path.join(scratch_root, str(entry.get('sourcePath', '')))
    destination_path = str(entry.get('destinationPath', '')).strip()
    if not os.path.isdir(source_path) or not destination_path:
        warn(f"app-state-machine-directory-skip => {source_path}")
        continue
    if copy_directory_contents(source_path, destination_path):
        machine_directory_copies += 1

for entry in manifest.get('machineFiles', []):
    source_path = os.path.join(scratch_root, str(entry.get('sourcePath', '')))
    destination_path = str(entry.get('destinationPath', '')).strip()
    if not os.path.isfile(source_path) or not destination_path:
        warn(f"app-state-machine-file-skip => {source_path}")
        continue
    if copy_file(source_path, destination_path):
        machine_file_copies += 1

for entry in manifest.get('profileDirectories', []):
    source_path = os.path.join(scratch_root, str(entry.get('sourcePath', '')))
    relative_destination_path = str(entry.get('relativeDestinationPath', '')).strip()
    if not os.path.isdir(source_path) or not relative_destination_path:
        warn(f"app-state-profile-directory-skip => {source_path}")
        continue
    for _, _, profile_root in select_profile_targets(entry):
        destination_path = os.path.join(profile_root, relative_destination_path)
        if copy_directory_contents(source_path, destination_path):
            profile_directory_copies += 1

for entry in manifest.get('profileFiles', []):
    source_path = os.path.join(scratch_root, str(entry.get('sourcePath', '')))
    relative_destination_path = str(entry.get('relativeDestinationPath', '')).strip()
    if not os.path.isfile(source_path) or not relative_destination_path:
        warn(f"app-state-profile-file-skip => {source_path}")
        continue
    for _, _, profile_root in select_profile_targets(entry):
        destination_path = os.path.join(profile_root, relative_destination_path)
        if copy_file(source_path, destination_path):
            profile_file_copies += 1

for entry in manifest.get('registryImports', []):
    source_path = os.path.join(scratch_root, str(entry.get('sourcePath', '')))
    if not os.path.exists(source_path):
        warn(f"app-state-registry-skip => {source_path}")
        continue
    warn(f"app-state-registry-skip => {source_path} => registry replay is ignored on linux")

print(
    'app-state-summary => task={0}; machine-registry={1}; user-registry={2}; machine-directories={3}; machine-files={4}; profile-directories={5}; profile-files={6}'.format(
        task_name,
        machine_registry_imports,
        user_registry_imports,
        machine_directory_copies,
        machine_file_copies,
        profile_directory_copies,
        profile_file_copies,
    )
)
print('app-state-replay-completed')
PY
'@

    $bashTaskName = [string]$TaskName.Replace("'", "'""'""'")
    $bashRemoteZipPath = [string]$RemoteZipPath.Replace("'", "'""'""'")
    $bashManagerUser = [string]$ManagerUser.Replace("'", "'""'""'")
    $bashAssistantUser = [string]$AssistantUser.Replace("'", "'""'""'")
    return ($template.
        Replace('__TASK_NAME__', $bashTaskName).
        Replace('__REMOTE_ZIP_PATH__', $bashRemoteZipPath).
        Replace('__MANAGER_USER__', $bashManagerUser).
        Replace('__ASSISTANT_USER__', $bashAssistantUser))
}

function Invoke-ProdicloudTaskAppStatePostProcess {
    param(
        [ValidateSet('windows','linux')]
        [string]$Platform,
        [ValidateSet('ssh','winrm')]
        [string]$Transport = 'ssh',
        [string]$RepoRoot,
        [psobject]$TaskBlock,
        [psobject]$Session,
        [string]$PySshPythonPath,
        [string]$PySshClientPath,
        [string]$HostName,
        [string]$UserName,
        [string]$Password,
        [string]$Port,
        [int]$ConnectTimeoutSeconds = 30,
        [int]$TimeoutSeconds = 180,
        [string]$ManagerUser = '',
        [string]$AssistantUser = '',
        [string]$ResourceGroup = '',
        [string]$VmName = '',
        [string]$RunCommandId = ''
    )

    $pluginInfo = Get-ProdicloudTaskAppStatePluginInfo -TaskBlock $TaskBlock
    $taskName = [string]$pluginInfo.TaskName
    $taskShell = if ($Platform -eq 'windows') { 'powershell' } else { 'bash' }

    if ($pluginInfo.Status -eq 'missing-plugin') {
        Write-Host ("App-state skipped: {0} => no plugin" -f [string]$taskName)
        return [pscustomobject]@{ Status = 'skipped'; Warning = $false; Message = 'no plugin' }
    }
    if ($pluginInfo.Status -eq 'missing-zip') {
        Write-Host ("App-state skipped: {0} => no zip" -f [string]$taskName)
        return [pscustomobject]@{ Status = 'skipped'; Warning = $false; Message = 'no zip' }
    }
    if ($pluginInfo.Status -eq 'invalid') {
        Write-Warning ("App-state warning: {0} => {1}" -f [string]$taskName, [string]$pluginInfo.Message)
        return [pscustomobject]@{ Status = 'warning'; Warning = $true; Message = [string]$pluginInfo.Message }
    }
    if ([string]::Equals([string]$TaskBlock.TaskType, 'package', [System.StringComparison]::OrdinalIgnoreCase)) {
        Assert-ProdicloudPackageAppStateArchivePortable -ZipPath ([string]$pluginInfo.ZipPath)
    }

    $remoteZipTaskName = [string]$taskName
    if ([string]::Equals([string]$Platform, 'windows', [System.StringComparison]::OrdinalIgnoreCase)) {
        $remoteZipTaskName = ('{0}-{1}' -f [string]$taskName, ([guid]::NewGuid().ToString('N').Substring(0, 8)))
    }
    $remoteZipPath = Get-ProdicloudTaskAppStateRemoteZipPath -TaskName $remoteZipTaskName -Platform $Platform
    $remoteGuestHelperPath = Get-ProdicloudTaskAppStateRemoteGuestHelperPath -Platform $Platform
    try {
        if ($Transport -eq 'ssh' -and (
            [string]::IsNullOrWhiteSpace([string]$HostName) -or
            [string]::IsNullOrWhiteSpace([string]$UserName) -or
            [string]::IsNullOrWhiteSpace([string]$Password) -or
            [string]::IsNullOrWhiteSpace([string]$Port))) {
            throw 'SSH-only app-state replay requires host, user, password, and port.'
        }

        if ($Transport -eq 'winrm') {
            if ($null -eq $Session) { throw 'WinRM app-state replay requires an active PowerShell remoting session.' }
            Write-ProdicloudActionProgress -Action ("copy package app-state archive for '{0}' over WinRM" -f $taskName)
            Copy-Item -LiteralPath ([string]$pluginInfo.ZipPath) -Destination $remoteZipPath -ToSession $Session -Force -ErrorAction Stop
        }
        else {
            Copy-ProdicloudAssetToVm -PySshPythonPath $PySshPythonPath -PySshClientPath $PySshClientPath -HostName $HostName -UserName $UserName -Password $Password -Port $Port -LocalPath ([string]$pluginInfo.ZipPath) -RemotePath $remoteZipPath -ConnectTimeoutSeconds $ConnectTimeoutSeconds | Out-Null
        }
        $scriptText = ''
        if ($Platform -eq 'windows') {
            $guestHelperPath = [string]$pluginInfo.GuestHelperPath
            if ([string]::IsNullOrWhiteSpace([string]$guestHelperPath) -or -not (Test-Path -LiteralPath $guestHelperPath)) {
                Write-Warning ("App-state warning: {0} => guest helper was not found: {1}" -f [string]$taskName, [string]$guestHelperPath)
                return [pscustomobject]@{ Status = 'warning'; Warning = $true; Message = 'guest helper missing' }
            }

            if ($Transport -eq 'winrm') {
                Write-ProdicloudActionProgress -Action ("copy app-state replay helper for '{0}' over WinRM" -f $taskName)
                Copy-Item -LiteralPath $guestHelperPath -Destination $remoteGuestHelperPath -ToSession $Session -Force -ErrorAction Stop
            }
            else {
                Copy-ProdicloudAssetToVm -PySshPythonPath $PySshPythonPath -PySshClientPath $PySshClientPath -HostName $HostName -UserName $UserName -Password $Password -Port $Port -LocalPath $guestHelperPath -RemotePath $remoteGuestHelperPath -ConnectTimeoutSeconds $ConnectTimeoutSeconds | Out-Null
            }
            $scriptText = Get-ProdicloudTaskAppStateGuestScript -TaskName $taskName -RemoteZipPath $remoteZipPath -ManagerUser $ManagerUser -AssistantUser $AssistantUser
        }
        else {
            $linuxPortabilityModulePath = Get-ProdicloudTaskAppStateLinuxPortabilityModulePath
            if (-not (Test-Path -LiteralPath $linuxPortabilityModulePath -PathType Leaf)) {
                throw ("Linux app-state portability helper was not found: {0}" -f $linuxPortabilityModulePath)
            }
            if ($Transport -eq 'winrm') { throw 'WinRM app-state replay is only supported for Windows package targets.' }
            Copy-ProdicloudAssetToVm -PySshPythonPath $PySshPythonPath -PySshClientPath $PySshClientPath -HostName $HostName -UserName $UserName -Password $Password -Port $Port -LocalPath $linuxPortabilityModulePath -RemotePath '/tmp/prodicloud-app-state-portability.py' -ConnectTimeoutSeconds $ConnectTimeoutSeconds | Out-Null
            $scriptText = Get-ProdicloudTaskAppStateLinuxGuestScript -TaskName $taskName -RemoteZipPath $remoteZipPath -ManagerUser $ManagerUser -AssistantUser $AssistantUser
        }
        $scriptTimeout = $TimeoutSeconds
        if ($scriptTimeout -lt 60) { $scriptTimeout = 60 }
        if ($scriptTimeout -gt 600) { $scriptTimeout = 600 }
        if ($Transport -eq 'winrm') {
            $remoteAppState = Invoke-ProdicloudPackageWinRmTaskScript -Session $Session -TaskName ("{0} (app-state)" -f $taskName) -ScriptText $scriptText -TimeoutSeconds $scriptTimeout
            $result = [pscustomobject]@{ ExitCode = [int]$remoteAppState.ExitCode; Output = [string]$remoteAppState.Output; OutputRelayedLive = $false }
        }
        else {
            $result = Invoke-ProdicloudSshTaskScript `
                -Session $Session `
                -PySshPythonPath $PySshPythonPath `
                -PySshClientPath $PySshClientPath `
                -HostName $HostName `
                -UserName $UserName `
                -Password $Password `
                -Port $Port `
                -Shell $taskShell `
                -TaskName ("{0} (app-state)" -f $taskName) `
                -TaskScript $scriptText `
                -TimeoutSeconds $scriptTimeout `
                -SkipRemoteCleanup
        }
        $outputWasRelayedLive = ($null -ne $result -and $result.PSObject.Properties.Match('OutputRelayedLive').Count -gt 0 -and [bool]$result.OutputRelayedLive)
        if ($null -eq $result -or [int]$result.ExitCode -ne 0) {
            if (-not $outputWasRelayedLive -and $null -ne $result -and $result.PSObject.Properties.Match('Output').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$result.Output)) {
                Write-Host ([string]$result.Output)
            }
            $exitCode = if ($null -ne $result -and $result.PSObject.Properties.Match('ExitCode').Count -gt 0) { [int]$result.ExitCode } else { -1 }
            Write-Warning ("App-state warning: {0} => replay exited with code {1}" -f [string]$taskName, $exitCode)
            return [pscustomobject]@{ Status = 'warning'; Warning = $true; Message = ("replay exited with code {0}" -f $exitCode) }
        }

        if (-not $outputWasRelayedLive -and $result.PSObject.Properties.Match('Output').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$result.Output)) {
            Write-Host ([string]$result.Output)
        }
        Write-Host ("App-state deployed: {0}" -f [string]$taskName)
        return [pscustomobject]@{ Status = 'deployed'; Warning = $false; Message = 'deployed' }
    }
    catch {
        Write-Warning ("App-state warning: {0} => {1}" -f [string]$taskName, $_.Exception.Message)
        return [pscustomobject]@{ Status = 'warning'; Warning = $true; Message = [string]$_.Exception.Message }
    }
}
