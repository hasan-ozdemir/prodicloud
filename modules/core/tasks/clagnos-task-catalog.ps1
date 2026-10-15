# Shared task discovery helpers for portable task folders.

function Read-ClagnosTaskCatalogState {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw ("Task catalog was not found: {0}" -f $Path)
    }

    $entries = @{}
    $lines = @(Get-Content -LiteralPath $Path -ErrorAction Stop)
    $inTasks = $false
    $sawTasks = $false
    for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
        $line = [string]$lines[$lineIndex]
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) { continue }
        if ($trimmed -match '^\[(?<section>[A-Za-z0-9_-]+)\]$') {
            if ($Matches.section -cne 'tasks' -or $sawTasks) {
                throw ("Task catalog '{0}' may contain only one [tasks] table." -f $Path)
            }
            $sawTasks = $true
            $inTasks = $true
            continue
        }
        if (-not $inTasks -or $trimmed -notmatch '^(?:"(?<quoted>[A-Za-z0-9][A-Za-z0-9._-]*)"|(?<bare>[A-Za-z0-9][A-Za-z0-9._-]*))\s*=\s*(?<value>true|false)\s*(?:#.*)?$') {
            throw ("Invalid tasks.toml entry at {0}:{1}. Expected a task id and a true/false value inside [tasks]." -f $Path, ($lineIndex + 1))
        }

        $id = if (-not [string]::IsNullOrWhiteSpace([string]$Matches.quoted)) { [string]$Matches.quoted } else { [string]$Matches.bare }
        if ($entries.ContainsKey($id)) {
            throw ("Task catalog '{0}' contains duplicate task id '{1}'." -f $Path, $id)
        }
        $entries[$id] = [bool]([string]$Matches.value -ceq 'true')
    }

    if (-not $sawTasks) { throw ("Task catalog '{0}' is missing its [tasks] table." -f $Path) }
    return [pscustomobject]@{ Path = [string]$Path; Entries = $entries; Lines = @($lines) }
}

function Set-ClagnosTaskCatalogEnabled {
    param(
        [string]$Path,
        [string]$TaskId,
        [bool]$Enabled
    )

    $catalog = Read-ClagnosTaskCatalogState -Path $Path
    if (-not $catalog.Entries.ContainsKey($TaskId)) {
        throw ("Task '{0}' is not registered in tasks.toml: {1}" -f $TaskId, $Path)
    }
    if ([bool]$catalog.Entries[$TaskId] -eq [bool]$Enabled) { return $false }

    $quotedId = [regex]::Escape($TaskId)
    $pattern = '^\s*(?:"' + $quotedId + '"|' + $quotedId + ')\s*=\s*(?:true|false)(\s*(?:#.*)?)$'
    $updated = $false
    $newLines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in @($catalog.Lines)) {
        if (-not $updated -and [string]$line -match $pattern) {
            $newLines.Add(('"{0}" = {1}{2}' -f $TaskId, $(if ($Enabled) { 'true' } else { 'false' }), [string]$Matches[1])) | Out-Null
            $updated = $true
        }
        else { $newLines.Add([string]$line) | Out-Null }
    }
    if (-not $updated) { throw ("Task '{0}' could not be updated in tasks.toml: {1}" -f $TaskId, $Path) }

    $directory = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($Path))
    $tempPath = Join-Path $directory ('.tasks.toml.clagnos-{0}.tmp' -f ([guid]::NewGuid().ToString('N')))
    try {
        [System.IO.File]::WriteAllLines($tempPath, [string[]]$newLines.ToArray(), ([System.Text.UTF8Encoding]::new($false)))
        Move-Item -LiteralPath $tempPath -Destination $Path -Force -ErrorAction Stop
    }
    finally {
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
    }

    $verified = Read-ClagnosTaskCatalogState -Path $Path
    if ([bool]$verified.Entries[$TaskId] -ne [bool]$Enabled) {
        throw ("Task availability did not verify after updating tasks.toml for '{0}'." -f $TaskId)
    }
    return $true
}

function Convert-ClagnosTaskCatalogPriority {
    param(
        [AllowNull()]
        [object]$Value,
        [int]$DefaultValue
    )

    if ($null -eq $Value) {
        return [int]$DefaultValue
    }

    try {
        $priority = [int]$Value
    }
    catch {
        return [int]$DefaultValue
    }

    if ($priority -lt 1) {
        return [int]$DefaultValue
    }

    return [int]$priority
}

function Convert-ClagnosTaskCatalogBool {
    param(
        [AllowNull()]
        [object]$Value,
        [bool]$DefaultValue = $true
    )

    if ($null -eq $Value) {
        return [bool]$DefaultValue
    }

    if ($Value -is [bool]) {
        return [bool]$Value
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace([string]$text)) {
        return [bool]$DefaultValue
    }

    switch ($text.Trim().ToLowerInvariant()) {
        '1' { return $true }
        'true' { return $true }
        'yes' { return $true }
        'y' { return $true }
        'on' { return $true }
        '0' { return $false }
        'false' { return $false }
        'no' { return $false }
        'n' { return $false }
        'off' { return $false }
        default { return [bool]$DefaultValue }
    }
}

function Convert-ClagnosTaskCatalogTimeout {
    param(
        [AllowNull()]
        [object]$Value,
        [int]$DefaultValue = 180
    )

    $timeoutSeconds = $DefaultValue
    try {
        if ($null -ne $Value -and -not [string]::IsNullOrWhiteSpace([string]$Value)) {
            $timeoutSeconds = [int]$Value
        }
    }
    catch {
        $timeoutSeconds = $DefaultValue
    }

    if ($timeoutSeconds -le 30) {
        $timeoutSeconds = 30
    }
    else {
        $timeoutSeconds = (30 + (15 * [int][Math]::Ceiling(($timeoutSeconds - 30) / 15.0)))
    }
    if ($timeoutSeconds -gt 7200) {
        $timeoutSeconds = 7200
    }

    return [int]$timeoutSeconds
}

function Get-ClagnosTaskDefaultTimeoutSeconds {
    return 180
}

function ConvertTo-ClagnosTaskFolderDependsOn {
    param(
        [AllowNull()]$InputObject,
        [string]$TaskLabel
    )

    $values = New-Object 'System.Collections.Generic.List[string]'
    $seen = @{}
    foreach ($item in @(ConvertTo-ObjectArrayCompat -InputObject $InputObject)) {
        if ($null -eq $item) {
            continue
        }

        $text = [string]$item
        if ([string]::IsNullOrWhiteSpace([string]$text)) {
            continue
        }

        $normalized = $text.Trim()
        if ($seen.ContainsKey($normalized)) {
            continue
        }

        $values.Add($normalized) | Out-Null
        $seen[$normalized] = $true
    }

    return @($values.ToArray())
}

function Resolve-ClagnosTaskCatalogRepoRoot {
    param([string]$StartPath = $PSScriptRoot)

    $cursor = [string]$StartPath
    while (-not [string]::IsNullOrWhiteSpace([string]$cursor)) {
        if (Test-Path -LiteralPath (Join-Path $cursor 'clagnos.ps1')) {
            return [string]$cursor
        }

        $parent = [string](Split-Path -Path $cursor -Parent)
        if ([string]::IsNullOrWhiteSpace([string]$parent) -or
            [string]::Equals([string]$parent, [string]$cursor, [System.StringComparison]::OrdinalIgnoreCase)) {
            break
        }

        $cursor = $parent
    }

    return ''
}

function Get-ClagnosTaskCatalogObservedDurationMap {
    if ($null -ne $script:ClagnosTaskCatalogObservedDurationMap) {
        return $script:ClagnosTaskCatalogObservedDurationMap
    }

    $observedDurations = @{}
    $repoRoot = Resolve-ClagnosTaskCatalogRepoRoot -StartPath $PSScriptRoot
    if (-not [string]::IsNullOrWhiteSpace([string]$repoRoot) -and (Test-Path -LiteralPath $repoRoot)) {
        $logFiles = @(
            Get-ChildItem -LiteralPath $repoRoot -Filter 'clagnos-log-*.txt' -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTimeUtc -Descending
        )
        foreach ($logFile in @($logFiles)) {
            foreach ($line in @(Get-Content -LiteralPath $logFile.FullName -ErrorAction SilentlyContinue)) {
                if ([string]$line -notmatch '^Task completed:\s+(?<name>[^\r\n(]+?)\s+\((?<seconds>[0-9][0-9\.,]*)s\)\s+-\s+success\b') {
                    continue
                }

                $taskName = [string]$Matches.name.Trim()
                if ($observedDurations.ContainsKey($taskName)) {
                    continue
                }

                $secondsText = ([string]$Matches.seconds).Replace(',', '')
                $seconds = [double]::PositiveInfinity
                try {
                    $seconds = [double]$secondsText
                }
                catch {
                    $seconds = [double]::PositiveInfinity
                }

                $observedDurations[$taskName] = [double]$seconds
            }
        }
    }

    $script:ClagnosTaskCatalogObservedDurationMap = $observedDurations
    return $script:ClagnosTaskCatalogObservedDurationMap
}

function Get-ClagnosTaskBandRank {
    param([string]$TaskType)

    switch ([string]$TaskType) {
        'initial' { return 0 }
        'normal' { return 1 }
        'final' { return 2 }
        default { return 99 }
    }
}

function Sort-ClagnosTaskInventoryRows {
    param([object[]]$Rows)

    $bandOrder = @('initial', 'normal', 'final')
    $sortedRows = New-Object 'System.Collections.Generic.List[object]'
    foreach ($band in @($bandOrder)) {
        $bandRows = @($Rows | Where-Object { [string]::Equals([string]$_.TaskType, [string]$band, [System.StringComparison]::OrdinalIgnoreCase) })
        if (@($bandRows).Count -lt 1) {
            continue
        }

        $bandNameMap = @{}
        foreach ($row in @($bandRows)) {
            $bandNameMap[[string]$row.Name] = $row
        }

        foreach ($row in @($bandRows)) {
            foreach ($dependencyName in @($row.DependsOn)) {
                if ([string]::IsNullOrWhiteSpace([string]$dependencyName)) {
                    continue
                }
                if ($bandNameMap.ContainsKey([string]$dependencyName)) {
                    continue
                }
                if (@($Rows | Where-Object { [string]::Equals([string]$_.Name, [string]$dependencyName, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) {
                    continue
                }
                throw ("Task '{0}' depends on '{1}', but that task was not found in the discovered inventory." -f [string]$row.Name, [string]$dependencyName)
            }
        }

        $remainingRows = New-Object 'System.Collections.Generic.List[object]'
        foreach ($row in @($bandRows)) {
            $remainingRows.Add($row) | Out-Null
        }

        while ($remainingRows.Count -gt 0) {
            $remainingNameMap = @{}
            foreach ($remainingRow in @($remainingRows.ToArray())) {
                $remainingNameMap[[string]$remainingRow.Name] = $true
            }

            $readyRows = @(
                $remainingRows.ToArray() |
                    Where-Object {
                        $pendingDependencies = @(
                            @($_.DependsOn) |
                                Where-Object {
                                    -not [string]::IsNullOrWhiteSpace([string]$_) -and
                                    $bandNameMap.ContainsKey([string]$_) -and
                                    $remainingNameMap.ContainsKey([string]$_)
                                }
                        )
                        @($pendingDependencies).Count -eq 0
                    }
            )

            if (@($readyRows).Count -lt 1) {
                $cycleTaskNames = @($remainingRows.ToArray() | ForEach-Object { [string]$_.Name } | Sort-Object)
                throw ("Task dependency cycle detected in the '{0}' band: {1}" -f [string]$band, ($cycleTaskNames -join ', '))
            }

            $readyRows = @(
                $readyRows |
                    Sort-Object `
                        @{ Expression = { [int]$_.Priority } }, `
                        @{ Expression = { [int]$_.TimeoutSeconds } }, `
                        @{ Expression = { [double]$_.ObservedDurationSeconds } }, `
                        @{ Expression = { [string]$_.Name } }
            )

            $readyRow = @($readyRows | Select-Object -First 1)
            if (@($readyRow).Count -lt 1) {
                throw ("Task ordering failed in the '{0}' band because no ready task could be selected." -f [string]$band)
            }

            $sortedRows.Add($readyRow[0]) | Out-Null
            [void]$remainingRows.Remove($readyRow[0])
        }
    }

    return @($sortedRows.ToArray())
}

function Test-ClagnosTaskPriorityFitsType {
    param(
        [string]$TaskType,
        [int]$Priority
    )

    switch ([string]$TaskType) {
        'initial' { return ($Priority -ge 1 -and $Priority -le 99) }
        'normal' { return ($Priority -ge 101 -and $Priority -le 999) }
        'final' { return ($Priority -ge 10001 -and $Priority -le 10099) }
        default { return $false }
    }
}

function Get-ClagnosTrackedTaskTypeFromNumber {
    param(
        [int]$TaskNumber,
        [string]$TaskName = ''
    )

    if ($TaskNumber -ge 1 -and $TaskNumber -le 99) {
        return 'initial'
    }
    if ($TaskNumber -ge 101 -and $TaskNumber -le 999) {
        return 'normal'
    }
    if ($TaskNumber -ge 10001 -and $TaskNumber -le 10099) {
        return 'final'
    }

    $label = if ([string]::IsNullOrWhiteSpace([string]$TaskName)) { [string]$TaskNumber } else { [string]$TaskName }
    throw ("Tracked task '{0}' must use an initial (01-99), normal (101-999), or final (10001-10099) task number." -f $label)
}

function ConvertTo-ClagnosTaskFolderStringArray {
    param([AllowNull()]$InputObject)

    $values = New-Object 'System.Collections.Generic.List[string]'
    foreach ($item in @(ConvertTo-ObjectArrayCompat -InputObject $InputObject)) {
        if ($null -eq $item) {
            continue
        }

        $text = [string]$item
        if ([string]::IsNullOrWhiteSpace([string]$text)) {
            continue
        }

        $values.Add($text) | Out-Null
    }

    return @($values.ToArray())
}

function ConvertTo-ClagnosTaskFolderAssetSpecs {
    param(
        [AllowNull()]$Assets,
        [string]$TaskLabel
    )

    $assetSpecs = @()
    foreach ($asset in @(ConvertTo-ObjectArrayCompat -InputObject $Assets)) {
        if ($null -eq $asset) {
            continue
        }

        $localPath = ''
        $remotePath = ''
        if ($asset -is [System.Collections.IDictionary]) {
            if ($asset.Contains('local')) { $localPath = [string]$asset['local'] }
            if ($asset.Contains('remote')) { $remotePath = [string]$asset['remote'] }
        }
        else {
            if ($asset.PSObject.Properties.Match('local').Count -gt 0) { $localPath = [string]$asset.local }
            if ($asset.PSObject.Properties.Match('remote').Count -gt 0) { $remotePath = [string]$asset.remote }
        }

        if ([string]::IsNullOrWhiteSpace([string]$localPath) -or [string]::IsNullOrWhiteSpace([string]$remotePath)) {
            throw ("Invalid task.json assets entry for '{0}': each asset requires non-empty 'local' and 'remote' values." -f [string]$TaskLabel)
        }

        $assetSpecs += [pscustomobject]@{
            LocalPath = [string]$localPath
            RemotePath = [string]$remotePath
        }
    }

    return @($assetSpecs)
}

function ConvertTo-ClagnosTaskFolderPathRule {
    param(
        [AllowNull()]$Rule,
        [string]$TaskLabel,
        [string]$CollectionName
    )

    if ($null -eq $Rule) {
        return $null
    }

    if ($Rule -is [string]) {
        if ([string]::IsNullOrWhiteSpace([string]$Rule)) {
            return $null
        }

        return [ordered]@{
            path = [string]$Rule
            targetProfiles = @()
            excludeNames = @()
            excludePathPatterns = @()
            excludeFilePatterns = @()
        }
    }

    $path = ''
    $targetProfiles = @()
    $excludeNames = @()
    $excludePathPatterns = @()
    $excludeFilePatterns = @()
    if ($Rule -is [System.Collections.IDictionary]) {
        if ($Rule.Contains('path')) { $path = [string]$Rule['path'] }
        if ($Rule.Contains('targetProfiles')) { $targetProfiles = ConvertTo-ClagnosTaskFolderStringArray -InputObject $Rule['targetProfiles'] }
        if ($Rule.Contains('excludeNames')) { $excludeNames = ConvertTo-ClagnosTaskFolderStringArray -InputObject $Rule['excludeNames'] }
        if ($Rule.Contains('excludePathPatterns')) { $excludePathPatterns = ConvertTo-ClagnosTaskFolderStringArray -InputObject $Rule['excludePathPatterns'] }
        if ($Rule.Contains('excludeFilePatterns')) { $excludeFilePatterns = ConvertTo-ClagnosTaskFolderStringArray -InputObject $Rule['excludeFilePatterns'] }
    }
    else {
        if ($Rule.PSObject.Properties.Match('path').Count -gt 0) { $path = [string]$Rule.path }
        if ($Rule.PSObject.Properties.Match('targetProfiles').Count -gt 0) { $targetProfiles = ConvertTo-ClagnosTaskFolderStringArray -InputObject $Rule.targetProfiles }
        if ($Rule.PSObject.Properties.Match('excludeNames').Count -gt 0) { $excludeNames = ConvertTo-ClagnosTaskFolderStringArray -InputObject $Rule.excludeNames }
        if ($Rule.PSObject.Properties.Match('excludePathPatterns').Count -gt 0) { $excludePathPatterns = ConvertTo-ClagnosTaskFolderStringArray -InputObject $Rule.excludePathPatterns }
        if ($Rule.PSObject.Properties.Match('excludeFilePatterns').Count -gt 0) { $excludeFilePatterns = ConvertTo-ClagnosTaskFolderStringArray -InputObject $Rule.excludeFilePatterns }
    }

    if ([string]::IsNullOrWhiteSpace([string]$path)) {
        throw ("Invalid task.json {0} entry for '{1}': each rule requires a non-empty 'path'." -f [string]$CollectionName, [string]$TaskLabel)
    }

    return [ordered]@{
        path = [string]$path
        targetProfiles = @($targetProfiles)
        excludeNames = @($excludeNames)
        excludePathPatterns = @($excludePathPatterns)
        excludeFilePatterns = @($excludeFilePatterns)
    }
}

function ConvertTo-ClagnosTaskFolderRegistryRule {
    param(
        [AllowNull()]$Rule,
        [string]$TaskLabel,
        [string]$CollectionName
    )

    if ($null -eq $Rule) {
        return $null
    }

    if ($Rule -is [string]) {
        if ([string]::IsNullOrWhiteSpace([string]$Rule)) {
            return $null
        }

        return [ordered]@{
            path = [string]$Rule
            targetProfiles = @()
            distributionAllowList = @()
        }
    }

    $path = ''
    $targetProfiles = @()
    $distributionAllowList = @()
    if ($Rule -is [System.Collections.IDictionary]) {
        if ($Rule.Contains('path')) { $path = [string]$Rule['path'] }
        if ($Rule.Contains('targetProfiles')) { $targetProfiles = ConvertTo-ClagnosTaskFolderStringArray -InputObject $Rule['targetProfiles'] }
        if ($Rule.Contains('distributionAllowList')) { $distributionAllowList = ConvertTo-ClagnosTaskFolderStringArray -InputObject $Rule['distributionAllowList'] }
    }
    else {
        if ($Rule.PSObject.Properties.Match('path').Count -gt 0) { $path = [string]$Rule.path }
        if ($Rule.PSObject.Properties.Match('targetProfiles').Count -gt 0) { $targetProfiles = ConvertTo-ClagnosTaskFolderStringArray -InputObject $Rule.targetProfiles }
        if ($Rule.PSObject.Properties.Match('distributionAllowList').Count -gt 0) { $distributionAllowList = ConvertTo-ClagnosTaskFolderStringArray -InputObject $Rule.distributionAllowList }
    }

    if ([string]::IsNullOrWhiteSpace([string]$path)) {
        throw ("Invalid task.json {0} entry for '{1}': each rule requires a non-empty 'path'." -f [string]$CollectionName, [string]$TaskLabel)
    }

    return [ordered]@{
        path = [string]$path
        targetProfiles = @($targetProfiles)
        distributionAllowList = @($distributionAllowList)
    }
}

function ConvertTo-ClagnosTaskFolderAppStateSpec {
    param(
        [AllowNull()]$AppState,
        [string]$TaskName,
        [string]$TaskLabel
    )

    if ($null -eq $AppState) {
        return $null
    }

    $spec = [ordered]@{
        taskName = [string]$TaskName
        portableProfilePayload = $false
        machineDirectories = @()
        machineFiles = @()
        profileDirectories = @()
        profileFiles = @()
        machineRegistryKeys = @()
        userRegistryKeys = @()
    }

    if ($AppState -is [System.Collections.IDictionary]) {
        if ($AppState.Contains('portableProfilePayload')) {
            $spec.portableProfilePayload = Convert-ClagnosTaskCatalogBool -Value $AppState['portableProfilePayload'] -DefaultValue $false
        }
    }
    elseif ($AppState.PSObject.Properties.Match('portableProfilePayload').Count -gt 0) {
        $spec.portableProfilePayload = Convert-ClagnosTaskCatalogBool -Value $AppState.portableProfilePayload -DefaultValue $false
    }

    $pathCollections = @('machineDirectories', 'machineFiles', 'profileDirectories', 'profileFiles')
    foreach ($collectionName in @($pathCollections)) {
        $rawRules = @()
        if ($AppState -is [System.Collections.IDictionary]) {
            if ($AppState.Contains($collectionName)) {
                $rawRules = @(ConvertTo-ObjectArrayCompat -InputObject $AppState[$collectionName])
            }
        }
        elseif ($AppState.PSObject.Properties.Match($collectionName).Count -gt 0) {
            $rawRules = @(ConvertTo-ObjectArrayCompat -InputObject $AppState.$collectionName)
        }

        $normalizedRules = @()
        foreach ($rawRule in @($rawRules)) {
            $rule = ConvertTo-ClagnosTaskFolderPathRule -Rule $rawRule -TaskLabel $TaskLabel -CollectionName $collectionName
            if ($null -ne $rule) {
                $normalizedRules += $rule
            }
        }
        $spec[$collectionName] = @($normalizedRules)
    }

    $registryCollections = @('machineRegistryKeys', 'userRegistryKeys')
    foreach ($collectionName in @($registryCollections)) {
        $rawRules = @()
        if ($AppState -is [System.Collections.IDictionary]) {
            if ($AppState.Contains($collectionName)) {
                $rawRules = @(ConvertTo-ObjectArrayCompat -InputObject $AppState[$collectionName])
            }
        }
        elseif ($AppState.PSObject.Properties.Match($collectionName).Count -gt 0) {
            $rawRules = @(ConvertTo-ObjectArrayCompat -InputObject $AppState.$collectionName)
        }

        $normalizedRules = @()
        foreach ($rawRule in @($rawRules)) {
            $rule = ConvertTo-ClagnosTaskFolderRegistryRule -Rule $rawRule -TaskLabel $TaskLabel -CollectionName $collectionName
            if ($null -ne $rule) {
                $normalizedRules += $rule
            }
        }
        $spec[$collectionName] = @($normalizedRules)
    }

    return [pscustomobject]$spec
}

function Get-ClagnosTaskFolderMetadata {
    param(
        [string]$MetadataPath,
        [string]$TaskName,
        [int]$TaskNumber
    )

    $taskLabel = if ([string]::IsNullOrWhiteSpace([string]$TaskName)) { [string]$MetadataPath } else { [string]$TaskName }
    if (-not (Test-Path -LiteralPath $MetadataPath)) {
        throw ("task.json was not found: {0}" -f [string]$MetadataPath)
    }

    $metadataText = [string](Get-Content -LiteralPath $MetadataPath -Raw -ErrorAction Stop)
    if ([string]::IsNullOrWhiteSpace([string]$metadataText)) {
        throw ("task.json is empty: {0}" -f [string]$MetadataPath)
    }

    try {
        $metadata = ConvertFrom-JsonCompat -InputObject $metadataText
    }
    catch {
        throw ("task.json parse failed for '{0}': {1}" -f [string]$MetadataPath, $_.Exception.Message)
    }

    if ($null -ne $metadata -and $null -ne $metadata.PSObject.Properties['enabled']) {
        throw ("Task availability belongs in tasks.toml; remove 'enabled' from {0}." -f $MetadataPath)
    }
    $priority = Convert-ClagnosTaskCatalogPriority -Value $(if ($null -ne $metadata -and $metadata.PSObject.Properties.Match('priority').Count -gt 0) { $metadata.priority } else { $null }) -DefaultValue $TaskNumber
    $timeoutSeconds = Convert-ClagnosTaskCatalogTimeout -Value $(if ($null -ne $metadata -and $metadata.PSObject.Properties.Match('timeout').Count -gt 0) { $metadata.timeout } else { $null }) -DefaultValue (Get-ClagnosTaskDefaultTimeoutSeconds)
    $assets = @()
    if ($null -ne $metadata -and $metadata.PSObject.Properties.Match('assets').Count -gt 0 -and $null -ne $metadata.assets) {
        $assets = @(ConvertTo-ClagnosTaskFolderAssetSpecs -Assets $metadata.assets -TaskLabel $taskLabel)
    }

    $appStateSpec = $null
    if ($null -ne $metadata -and $metadata.PSObject.Properties.Match('appState').Count -gt 0 -and $null -ne $metadata.appState) {
        $appStateSpec = ConvertTo-ClagnosTaskFolderAppStateSpec -AppState $metadata.appState -TaskName $TaskName -TaskLabel $taskLabel
    }

    $dependsOn = @()
    if ($null -ne $metadata -and $metadata.PSObject.Properties.Match('dependsOn').Count -gt 0 -and $null -ne $metadata.dependsOn) {
        $dependsOn = @(ConvertTo-ClagnosTaskFolderDependsOn -InputObject $metadata.dependsOn -TaskLabel $taskLabel)
    }

    $extensions = $null
    if ($null -ne $metadata -and $metadata.PSObject.Properties.Match('extensions').Count -gt 0 -and $null -ne $metadata.extensions) {
        $extensions = ConvertFrom-JsonCompat -InputObject (ConvertTo-JsonCompat -InputObject $metadata.extensions -Depth 20)
    }

    return [pscustomobject]@{
        Priority = [int]$priority
        TimeoutSeconds = [int]$timeoutSeconds
        AssetSpecs = @($assets)
        AppStateSpec = $appStateSpec
        DependsOn = @($dependsOn)
        Extensions = $extensions
    }
}

function Write-ClagnosTaskFolderSkipWarning {
    param(
        [string]$RelativeFolderPath,
        [string]$Message
    )

    $label = if ([string]::IsNullOrWhiteSpace([string]$RelativeFolderPath)) { '(unknown-task-folder)' } else { [string]$RelativeFolderPath }
    Write-Warning ("Task folder skipped: {0} => {1}" -f $label, [string]$Message)
}

function Get-ClagnosTaskFolderCandidates {
    param([string]$DirectoryPath)

    $rootPath = (Resolve-Path -LiteralPath $DirectoryPath).Path
    $candidates = New-Object 'System.Collections.Generic.List[object]'

    foreach ($catalogName in @('builtin', 'custom')) {
        $catalogRoot = Join-Path $rootPath $catalogName
        if (-not (Test-Path -LiteralPath $catalogRoot -PathType Container)) {
            throw ("Task catalog folder was not found: {0}" -f $catalogRoot)
        }
        $catalogPath = Join-Path $catalogRoot 'tasks.toml'
        $state = Read-ClagnosTaskCatalogState -Path $catalogPath
        $folders = @(Get-ChildItem -LiteralPath $catalogRoot -Directory | Where-Object { -not $_.Name.StartsWith('.') -and $_.Name -ne 'backup-app-states' } | Sort-Object Name)
        $folderNames = @($folders | ForEach-Object { [string]$_.Name })
        foreach ($catalogTaskName in @($state.Entries.Keys)) {
            if ($folderNames -notcontains [string]$catalogTaskName) {
                Write-Warning ("Task catalog entry skipped: '{0}' lists '{1}', but its task folder is absent." -f $catalogPath, [string]$catalogTaskName)
            }
        }
        foreach ($folder in @($folders)) {
            if (-not $state.Entries.ContainsKey([string]$folder.Name)) {
                Write-Warning ("Task folder skipped: {0}/{1} is not listed in tasks.toml." -f $catalogName, [string]$folder.Name)
                continue
            }
            $candidates.Add([pscustomobject]@{
                TaskRootPath = [string]$folder.FullName
                RelativeFolderPath = ("{0}/{1}" -f $catalogName, [string]$folder.Name)
                CatalogPath = [string]$catalogPath
                Catalog = [string]$catalogName
                Enabled = [bool]$state.Entries[[string]$folder.Name]
                Source = [string]$catalogName
            }) | Out-Null
        }
    }

    return @($candidates.ToArray())
}

function Read-ClagnosTaskFolderRow {
    param(
        [psobject]$Candidate,
        [string]$RootPath,
        [string]$ExpectedExtension
    )

    $taskRootPath = [string]$Candidate.TaskRootPath
    $relativeFolderPath = [string]$Candidate.RelativeFolderPath
    $folderName = [System.IO.Path]::GetFileName($taskRootPath.TrimEnd('\', '/'))
    if ([string]::IsNullOrWhiteSpace([string]$folderName)) {
        Write-ClagnosTaskFolderSkipWarning -RelativeFolderPath $relativeFolderPath -Message 'folder name is empty.'
        return $null
    }

    $namePattern = '^(?<n>\d{2,5})-(?<words>[a-z0-9]+(?:-[a-z0-9]+){1,4})$'
    if ($folderName -notmatch $namePattern) {
        Write-ClagnosTaskFolderSkipWarning -RelativeFolderPath $relativeFolderPath -Message ("folder name '{0}' does not match <task-number>-verb-noun-target format." -f [string]$folderName)
        return $null
    }

    $taskNumber = [int]$Matches.n
    $taskName = [string]$folderName
    $taskType = Get-ClagnosTrackedTaskTypeFromNumber -TaskNumber $taskNumber -TaskName $taskName

    $scriptPath = Join-Path $taskRootPath ("{0}{1}" -f [string]$taskName, [string]$ExpectedExtension)
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        Write-ClagnosTaskFolderSkipWarning -RelativeFolderPath $relativeFolderPath -Message ("main task script was not found: {0}" -f [System.IO.Path]::GetFileName($scriptPath))
        return $null
    }

    $metadataPath = Join-Path $taskRootPath 'task.json'
    $metadata = $null
    try {
        $metadata = Get-ClagnosTaskFolderMetadata -MetadataPath $metadataPath -TaskName $taskName -TaskNumber $taskNumber
    }
    catch {
        Write-ClagnosTaskFolderSkipWarning -RelativeFolderPath $relativeFolderPath -Message $_.Exception.Message
        return $null
    }

    $priority = [int]$metadata.Priority
    if (-not (Test-ClagnosTaskPriorityFitsType -TaskType $taskType -Priority $priority)) {
        Write-ClagnosTaskFolderSkipWarning -RelativeFolderPath $relativeFolderPath -Message ("priority '{0}' is outside the allowed {1} band." -f $priority, [string]$taskType)
        return $null
    }

    $script = [string](Get-Content -LiteralPath $scriptPath -Raw -ErrorAction Stop)
    $relativeScriptPath = ("{0}/{1}{2}" -f $relativeFolderPath.Trim('/'), [string]$taskName, [string]$ExpectedExtension)
    $isEnabled = [bool]$Candidate.Enabled
    $disabledReason = if ($isEnabled) { '' } else { 'disabled-in-tasks-toml' }

    return [pscustomobject]@{
        Name = [string]$taskName
        Script = [string]$script
        Path = [string]$scriptPath
        TaskRootPath = [string]$taskRootPath
        TaskMetadataPath = [string]$metadataPath
        CatalogPath = [string]$Candidate.CatalogPath
        Catalog = [string]$Candidate.Catalog
        RelativePath = [string]$relativeScriptPath
        DirectoryPath = [string]$taskRootPath
        StageRootDirectoryPath = [string]$RootPath
        TimeoutSeconds = [int]$metadata.TimeoutSeconds
        Priority = [int]$priority
        AssetSpecs = @($metadata.AssetSpecs)
        AppStateSpec = $metadata.AppStateSpec
        Extensions = $metadata.Extensions
        TaskType = [string]$taskType
        Source = [string]$Candidate.Source
        TaskNumber = [int]$taskNumber
        Enabled = [bool]$isEnabled
        DisabledReason = [string]$disabledReason
        DependsOn = @($metadata.DependsOn)
        ObservedDurationSeconds = [double]::PositiveInfinity
    }
}

function Get-ClagnosTaskBlocksFromDirectory {
    param(
        [string]$DirectoryPath,
        [ValidateSet('windows','linux')]
        [string]$Platform,
        [ValidateSet('init','update')]
        [string]$Stage,
        [switch]$SuppressSkipMessages
    )

    if ([string]::IsNullOrWhiteSpace([string]$DirectoryPath)) {
        throw ("Task directory for stage '{0}' is empty." -f [string]$Stage)
    }

    if (-not (Test-Path -LiteralPath $DirectoryPath)) {
        throw ("Task directory was not found: {0}" -f [string]$DirectoryPath)
    }

    $expectedExtension = if ([string]::Equals([string]$Platform, 'windows', [System.StringComparison]::OrdinalIgnoreCase)) { '.ps1' } else { '.sh' }
    $rootPath = (Resolve-Path -LiteralPath $DirectoryPath).Path
    $rows = @()
    foreach ($candidate in @(Get-ClagnosTaskFolderCandidates -DirectoryPath $rootPath)) {
        try {
            $row = Read-ClagnosTaskFolderRow -Candidate $candidate -RootPath $rootPath -ExpectedExtension $expectedExtension
            if ($null -ne $row) {
                $rows += $row
            }
        }
        catch {
            Write-ClagnosTaskFolderSkipWarning -RelativeFolderPath ([string]$candidate.RelativeFolderPath) -Message $_.Exception.Message
        }
    }

    $nameMap = @{}
    foreach ($row in @($rows)) {
        if ($nameMap.ContainsKey([string]$row.Name)) {
            throw ("Task name '{0}' is duplicated between '{1}' and '{2}'." -f [string]$row.Name, [string]$nameMap[[string]$row.Name], [string]$row.RelativePath)
        }

        $nameMap[[string]$row.Name] = [string]$row.RelativePath
    }

    $priorityMap = @{}
    foreach ($row in @($rows)) {
        $priorityKey = [string]$row.Priority
        if ($priorityMap.ContainsKey($priorityKey)) {
            throw ("Tasks '{0}' and '{1}' resolve to the same priority '{2}'." -f [string]$priorityMap[$priorityKey], [string]$row.Name, [int]$row.Priority)
        }

        $priorityMap[$priorityKey] = [string]$row.Name
    }

    $observedDurationMap = Get-ClagnosTaskCatalogObservedDurationMap
    foreach ($row in @($rows)) {
        if ($observedDurationMap.ContainsKey([string]$row.Name)) {
            $row.ObservedDurationSeconds = [double]$observedDurationMap[[string]$row.Name]
        }
        else {
            $row.ObservedDurationSeconds = [double]::PositiveInfinity
        }
    }

    $sortedInventory = @(Sort-ClagnosTaskInventoryRows -Rows @($rows))

    $activeTasks = @()
    $disabledTasks = @()
    foreach ($task in @($sortedInventory)) {
        if (-not [bool]$task.Enabled) {
            if (-not $SuppressSkipMessages -and [string]::Equals([string]$task.DisabledReason, 'disabled-in-tasks-toml', [System.StringComparison]::OrdinalIgnoreCase)) {
                Write-Host ("Task skipped (disabled in tasks.toml): {0}" -f [string]$task.Name) -ForegroundColor DarkYellow
            }

            $disabledTasks += [pscustomobject]@{
                Name = [string]$task.Name
                RelativePath = [string]$task.RelativePath
                Priority = [int]$task.Priority
                TimeoutSeconds = [int]$task.TimeoutSeconds
                Extensions = $task.Extensions
                TaskType = [string]$task.TaskType
                Source = [string]$task.Source
                DisabledReason = [string]$task.DisabledReason
                TaskNumber = [int]$task.TaskNumber
                TaskRootPath = [string]$task.TaskRootPath
                TaskMetadataPath = [string]$task.TaskMetadataPath
                DependsOn = @($task.DependsOn)
                ObservedDurationSeconds = [double]$task.ObservedDurationSeconds
            }
            continue
        }

        $activeTasks += [pscustomobject]@{
            Name = [string]$task.Name
            Script = [string]$task.Script
            RelativePath = [string]$task.RelativePath
            DirectoryPath = [string]$task.DirectoryPath
            TaskRootPath = [string]$task.TaskRootPath
            TaskMetadataPath = [string]$task.TaskMetadataPath
            StageRootDirectoryPath = [string]$task.StageRootDirectoryPath
            TimeoutSeconds = [int]$task.TimeoutSeconds
            Priority = [int]$task.Priority
            AssetSpecs = @($task.AssetSpecs)
            AppStateSpec = $task.AppStateSpec
            Extensions = $task.Extensions
            TaskType = [string]$task.TaskType
            Source = [string]$task.Source
            TaskNumber = [int]$task.TaskNumber
            DependsOn = @($task.DependsOn)
            ObservedDurationSeconds = [double]$task.ObservedDurationSeconds
        }
    }

    return [ordered]@{
        ActiveTasks = @($activeTasks)
        DisabledTasks = @($disabledTasks)
        InventoryTasks = @($sortedInventory)
    }
}
