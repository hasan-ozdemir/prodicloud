# Shared local-machine app-state helpers for the task command.

function Test-ProdicloudLocalAppStateWindowsHost {
    return ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)
}

function Resolve-ProdicloudTaskAppStateRequestedUsers {
    param([string]$UserOptionValue = '')

    $rawValue = if ($null -eq $UserOptionValue) { '' } else { [string]$UserOptionValue }
    if ([string]::IsNullOrWhiteSpace([string]$rawValue)) {
        return @('.all.')
    }

    $tokens = New-Object 'System.Collections.Generic.List[string]'
    $seen = @{}
    foreach ($segment in @($rawValue -split ',')) {
        $value = if ($null -eq $segment) { '' } else { [string]$segment.Trim() }
        if ([string]::IsNullOrWhiteSpace([string]$value)) {
            continue
        }

        $normalizedValue = $value.ToLowerInvariant()
        if ($seen.ContainsKey($normalizedValue)) {
            continue
        }

        $tokens.Add($normalizedValue) | Out-Null
        $seen[$normalizedValue] = $true
    }

    if (@($tokens).Count -lt 1) {
        return @('.all.')
    }

    if ((@($tokens) -contains '.all.') -and @($tokens).Count -gt 1) {
        Throw-FriendlyError `
            -Detail "The .all. user selector cannot be combined with other user values." `
            -Code 67 `
            -Summary "Task app-state user selection is invalid." `
            -Hint "Use either --user=.all. or a specific list such as --user=.current. or --user=operator,assistant."
    }

    return @($tokens.ToArray())
}

function Get-ProdicloudLocalAppStateExcludedProfileNames {
    return @(
        'all users',
        'default',
        'default user',
        'defaultaccount',
        'defaultuser0',
        'public',
        'wdagutilityaccount',
        'administrator'
    )
}

function Get-ProdicloudLocalAppStateProfileCatalog {
    if (-not (Test-ProdicloudLocalAppStateWindowsHost)) {
        Throw-FriendlyError `
            -Detail "Local-machine app-state operations are only supported on Windows operator machines." `
            -Code 67 `
            -Summary "Local app-state target is unsupported on this operating system." `
            -Hint "Run task --save-app-state/--restore-app-state --source=lm|--target=lm from Windows."
    }

    $usersRoot = Join-Path $env:SystemDrive 'Users'
    if (-not (Test-Path -LiteralPath $usersRoot -PathType Container)) {
        return @()
    }

    $excludedNames = @(
        Get-ProdicloudLocalAppStateExcludedProfileNames |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object { $_.Trim().ToLowerInvariant() }
    )

    $rows = New-Object 'System.Collections.Generic.List[object]'
    foreach ($profileDirectory in @(Get-ChildItem -LiteralPath $usersRoot -Directory -Force -ErrorAction SilentlyContinue | Sort-Object Name)) {
        if ($null -eq $profileDirectory) {
            continue
        }

        $userName = [string]$profileDirectory.Name
        if ([string]::IsNullOrWhiteSpace([string]$userName)) {
            continue
        }

        $normalizedUserName = $userName.Trim().ToLowerInvariant()
        if (@($excludedNames) -contains $normalizedUserName) {
            continue
        }

        $ntUserDatPath = Join-Path $profileDirectory.FullName 'NTUSER.DAT'
        if (-not (Test-Path -LiteralPath $ntUserDatPath -PathType Leaf)) {
            continue
        }

        $rows.Add([pscustomobject]@{
            Label = [string]$normalizedUserName
            UserName = [string]$userName
            ProfilePath = [string]$profileDirectory.FullName
            NtUserDatPath = [string]$ntUserDatPath
        }) | Out-Null
    }

    return @($rows.ToArray())
}

function Resolve-ProdicloudLocalAppStateProfileTargets {
    param([string[]]$RequestedUsers = @())

    $tokens = @(Resolve-ProdicloudTaskAppStateRequestedUsers -UserOptionValue (@($RequestedUsers) -join ','))
    $catalog = @(Get-ProdicloudLocalAppStateProfileCatalog)
    $catalogMap = @{}
    foreach ($entry in @($catalog)) {
        if ($null -eq $entry) {
            continue
        }

        $label = [string]$entry.Label
        $userName = [string]$entry.UserName
        if (-not [string]::IsNullOrWhiteSpace([string]$label)) {
            $catalogMap[$label.ToLowerInvariant()] = $entry
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$userName)) {
            $catalogMap[$userName.Trim().ToLowerInvariant()] = $entry
        }
    }

    if (@($tokens).Count -eq 1 -and [string]::Equals([string]$tokens[0], '.all.', [System.StringComparison]::OrdinalIgnoreCase)) {
        return @($catalog)
    }

    $selectedTargets = New-Object 'System.Collections.Generic.List[object]'
    $selectedPaths = @{}
    foreach ($token in @($tokens)) {
        $lookupKey = [string]$token
        if ([string]::Equals([string]$lookupKey, '.current.', [System.StringComparison]::OrdinalIgnoreCase)) {
            $lookupKey = [string][System.Environment]::UserName
        }

        if ([string]::IsNullOrWhiteSpace([string]$lookupKey)) {
            continue
        }

        $normalizedLookup = $lookupKey.Trim().ToLowerInvariant()
        if (-not $catalogMap.ContainsKey($normalizedLookup)) {
            Throw-FriendlyError `
                -Detail ("Local user '{0}' was not found under C:\Users with a real profile root." -f [string]$lookupKey) `
                -Code 67 `
                -Summary "Task app-state local user selection is invalid." `
                -Hint "Use --user=.all., --user=.current., or one or more real local profile names such as --user=operator,assistant."
        }

        $target = $catalogMap[$normalizedLookup]
        $pathKey = [string]$target.ProfilePath
        if ([string]::IsNullOrWhiteSpace([string]$pathKey)) {
            continue
        }

        $normalizedPathKey = $pathKey.TrimEnd('\').ToLowerInvariant()
        if ($selectedPaths.ContainsKey($normalizedPathKey)) {
            continue
        }

        $selectedTargets.Add([pscustomobject]@{
            Label = [string]$target.Label
            UserName = [string]$target.UserName
            ProfilePath = [string]$target.ProfilePath
            NtUserDatPath = [string]$target.NtUserDatPath
        }) | Out-Null
        $selectedPaths[$normalizedPathKey] = $true
    }

    return @($selectedTargets.ToArray())
}

function ConvertTo-ProdicloudLocalAppStateRegistryProviderPath {
    param([string]$RegistryPath)

    $canonicalPath = Convert-ProdicloudAppStateRegistryPathToCanonicalRootLocal -RegistryPath $RegistryPath
    if ([string]::IsNullOrWhiteSpace([string]$canonicalPath)) {
        return ''
    }

    return ('Registry::{0}' -f $canonicalPath)
}

function Normalize-ProdicloudLocalAppStateComparablePath {
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

function Test-ProdicloudLocalAppStatePathMatchesRule {
    param(
        [string]$ActualPath,
        [string]$RulePath
    )

    if ([string]::IsNullOrWhiteSpace([string]$ActualPath) -or [string]::IsNullOrWhiteSpace([string]$RulePath)) {
        return $false
    }

    $normalizedActual = Normalize-ProdicloudLocalAppStateComparablePath -Path $ActualPath
    $normalizedRule = Normalize-ProdicloudLocalAppStateComparablePath -Path $RulePath
    if ($normalizedRule.IndexOf('*', [System.StringComparison]::Ordinal) -ge 0 -or
        $normalizedRule.IndexOf('?', [System.StringComparison]::Ordinal) -ge 0) {
        return ($normalizedActual -like $normalizedRule)
    }

    return [string]::Equals($normalizedActual, $normalizedRule, [System.StringComparison]::OrdinalIgnoreCase)
}

function Resolve-ProdicloudLocalAppStateReplayDestinationPaths {
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

function Test-ProdicloudLocalAppStateManifestEntryAllowed {
    param(
        [AllowNull()]$Entry,
        [object[]]$Rules = @(),
        [string]$PathPropertyName
    )

    if ($null -eq $Entry) {
        return $false
    }

    $pathValue = [string](Get-ProdicloudTaskAppStateRuleValue -Rule $Entry -PropertyName $PathPropertyName)
    if ([string]::IsNullOrWhiteSpace([string]$pathValue)) {
        return $false
    }

    foreach ($rule in @($Rules)) {
        if ($null -eq $rule) {
            continue
        }

        $rulePath = if ($rule -is [string]) { [string]$rule } else { [string](Get-ProdicloudTaskAppStateRuleValue -Rule $rule -PropertyName 'path') }
        if (Test-ProdicloudLocalAppStatePathMatchesRule -ActualPath $pathValue -RulePath $rulePath) {
            return $true
        }
    }

    return $false
}

function Get-ProdicloudTaskAppStateLocalEntryTargetProfiles {
    param([AllowNull()]$Entry)

    $targetProfiles = @(Get-ProdicloudTaskAppStateRuleValue -Rule $Entry -PropertyName 'targetProfiles')
    if (@($targetProfiles).Count -lt 1) {
        return @()
    }

    return @(
        @($targetProfiles) |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object { $_.Trim().ToLowerInvariant() } |
            Select-Object -Unique
    )
}

function Get-ProdicloudTaskAppStateLocalSelectedProfileTargets {
    param(
        [object[]]$ProfileTargets,
        [AllowNull()]$Entry
    )

    $targetProfiles = @(Get-ProdicloudTaskAppStateLocalEntryTargetProfiles -Entry $Entry)
    if (@($targetProfiles).Count -lt 1) {
        return @($ProfileTargets)
    }

    return @(
        @($ProfileTargets) | Where-Object {
            $label = [string](Get-ProdicloudTaskAppStateRuleValue -Rule $_ -PropertyName 'Label')
            $userName = [string](Get-ProdicloudTaskAppStateRuleValue -Rule $_ -PropertyName 'UserName')
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

function Assert-ProdicloudTaskAppStateManifestAllowedForLocalRestore {
    param(
        [psobject]$TaskBlock,
        [psobject]$Manifest
    )

    $taskName = Get-ProdicloudTaskAppStateIdentity -TaskBlock $TaskBlock
    $ownerType = if ($null -ne $TaskBlock.PackageSpec) { 'package' } else { 'task' }
    $metadataFile = if ($ownerType -eq 'package') { 'package.json' } else { 'task.json' }
    $capturePlan = Get-ProdicloudTaskAppStateCapturePlan -TaskBlock $TaskBlock
    if ($null -eq $capturePlan) {
        Throw-FriendlyError `
            -Detail ("{0} '{1}' does not declare an app-state capture plan in {2}." -f $ownerType,[string]$taskName,$metadataFile) `
            -Code 61 `
            -Summary "App-state restore input is invalid for local replay." `
            -Hint ("Define appState in {0} or re-save the {1} payload after its plan exists." -f $metadataFile,$ownerType)
    }

    foreach ($entry in @($Manifest.machineDirectories)) {
        if (-not (Test-ProdicloudLocalAppStateManifestEntryAllowed -Entry $entry -Rules @($capturePlan.machineDirectories) -PathPropertyName 'destinationPath')) {
            Throw-FriendlyError `
                -Detail ("Machine directory restore path is outside the current {0} allow-list for {1} '{2}'." -f $metadataFile,$ownerType,[string]$taskName) `
                -Code 61 `
                -Summary "Task app-state restore input is invalid for local replay." `
                -Hint ("Re-save the {0} payload from the current {1} before running --target=lm restore." -f $ownerType,$metadataFile)
        }
    }

    foreach ($entry in @($Manifest.machineFiles)) {
        if (-not (Test-ProdicloudLocalAppStateManifestEntryAllowed -Entry $entry -Rules @($capturePlan.machineFiles) -PathPropertyName 'destinationPath')) {
            Throw-FriendlyError `
                -Detail ("Machine file restore path is outside the current {0} allow-list for {1} '{2}'." -f $metadataFile,$ownerType,[string]$taskName) `
                -Code 61 `
                -Summary "Task app-state restore input is invalid for local replay." `
                -Hint ("Re-save the {0} payload from the current {1} before running --target=lm restore." -f $ownerType,$metadataFile)
        }
    }

    foreach ($entry in @($Manifest.profileDirectories)) {
        if (-not (Test-ProdicloudLocalAppStateManifestEntryAllowed -Entry $entry -Rules @($capturePlan.profileDirectories) -PathPropertyName 'relativeDestinationPath')) {
            Throw-FriendlyError `
                -Detail ("Profile directory restore path is outside the current {0} allow-list for {1} '{2}'." -f $metadataFile,$ownerType,[string]$taskName) `
                -Code 61 `
                -Summary "Task app-state restore input is invalid for local replay." `
                -Hint ("Re-save the {0} payload from the current {1} before running --target=lm restore." -f $ownerType,$metadataFile)
        }
    }

    foreach ($entry in @($Manifest.profileFiles)) {
        if (-not (Test-ProdicloudLocalAppStateManifestEntryAllowed -Entry $entry -Rules @($capturePlan.profileFiles) -PathPropertyName 'relativeDestinationPath')) {
            Throw-FriendlyError `
                -Detail ("Profile file restore path is outside the current {0} allow-list for {1} '{2}'." -f $metadataFile,$ownerType,[string]$taskName) `
                -Code 61 `
                -Summary "Task app-state restore input is invalid for local replay." `
                -Hint ("Re-save the {0} payload from the current {1} before running --target=lm restore." -f $ownerType,$metadataFile)
        }
    }

    foreach ($entry in @($Manifest.registryImports)) {
        if ($null -eq $entry) {
            continue
        }

        $scope = if ($entry.PSObject.Properties.Match('scope').Count -gt 0) { [string]$entry.scope } else { '' }
        $registryPath = if ($entry.PSObject.Properties.Match('registryPath').Count -gt 0) { [string]$entry.registryPath } else { '' }
        if ([string]::IsNullOrWhiteSpace([string]$registryPath)) {
            Throw-FriendlyError `
                -Detail ("{0} '{1}' app-state manifest is missing registryPath metadata required for safe local restore." -f $ownerType,[string]$taskName) `
                -Code 61 `
                -Summary "Task app-state restore input is too old for local replay." `
                -Hint "Re-save the task payload with the current prodicloud version, then retry --target=lm."
        }

        $rules = if ([string]::Equals([string]$scope, 'machine', [System.StringComparison]::OrdinalIgnoreCase)) {
            @($capturePlan.machineRegistryKeys)
        }
        else {
            @($capturePlan.userRegistryKeys)
        }

        if (-not (Test-ProdicloudLocalAppStateManifestEntryAllowed -Entry ([pscustomobject]@{ registryPath = $registryPath }) -Rules $rules -PathPropertyName 'registryPath')) {
            Throw-FriendlyError `
                -Detail ("Registry restore path '{0}' is outside the current {1} allow-list for {2} '{3}'." -f [string]$registryPath,$metadataFile,$ownerType,[string]$taskName) `
                -Code 61 `
                -Summary "Task app-state restore input is invalid for local replay." `
                -Hint ("Re-save the {0} payload from the current {1} before running --target=lm restore." -f $ownerType,$metadataFile)
        }
    }
}

function Get-ProdicloudTaskAppStateLocalRestoreOperations {
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
        }) | Out-Null
        $seen[$key] = $true
    }

    foreach ($entry in @($Manifest.profileDirectories)) {
        if ($null -eq $entry) { continue }
        $sourcePath = Join-Path $ExpandedRoot ([string]$entry.sourcePath)
        $relativeDestinationPath = [string]$entry.relativeDestinationPath
        if (-not (Test-Path -LiteralPath $sourcePath) -or [string]::IsNullOrWhiteSpace([string]$relativeDestinationPath)) { continue }

        foreach ($profileTarget in @(Get-ProdicloudTaskAppStateLocalSelectedProfileTargets -ProfileTargets @($ProfileTargets) -Entry $entry)) {
            $destinationPaths = @(Resolve-ProdicloudLocalAppStateReplayDestinationPaths -BasePath ([string]$profileTarget.ProfilePath) -RelativeOrAbsolutePath $relativeDestinationPath)
            if (@($destinationPaths).Count -lt 1) { continue }

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

        foreach ($profileTarget in @(Get-ProdicloudTaskAppStateLocalSelectedProfileTargets -ProfileTargets @($ProfileTargets) -Entry $entry)) {
            $destinationPaths = @(Resolve-ProdicloudLocalAppStateReplayDestinationPaths -BasePath ([string]$profileTarget.ProfilePath) -RelativeOrAbsolutePath $relativeDestinationPath)
            if (@($destinationPaths).Count -lt 1) { continue }

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
        if ([string]::IsNullOrWhiteSpace([string]$registryPath)) { continue }
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
            }) | Out-Null
            $seen[$key] = $true
            continue
        }

        foreach ($profileTarget in @(Get-ProdicloudTaskAppStateLocalSelectedProfileTargets -ProfileTargets @($ProfileTargets) -Entry $entry)) {
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
            }) | Out-Null
            $seen[$key] = $true
        }
    }

    return @($operations.ToArray())
}
function Get-ProdicloudTaskAppStateLocalBackupRootPath {
    param(
        [psobject]$TaskBlock,
        [string]$TaskName = ''
    )

    $resolvedPath = Get-ProdicloudTaskAppStateBackupRootDirectoryPath -TaskBlock $TaskBlock
    if (-not [string]::IsNullOrWhiteSpace([string]$resolvedPath)) {
        return [string]$resolvedPath
    }

    $safeTaskName = (([string]$TaskName -replace '[^A-Za-z0-9\-]', '-').Trim('-'))
    if ([string]::IsNullOrWhiteSpace([string]$safeTaskName) -and $null -ne $TaskBlock -and $TaskBlock.PSObject.Properties.Match('Name').Count -gt 0) {
        $safeTaskName = (([string](Get-ProdicloudTaskAppStateIdentity -TaskBlock $TaskBlock) -replace '[^A-Za-z0-9\-]', '-').Trim('-'))
    }
    if ([string]::IsNullOrWhiteSpace([string]$safeTaskName)) {
        $safeTaskName = 'task'
    }

    return (Join-Path ([System.IO.Path]::GetTempPath()) ('prodicloud-app-state-local-{0}' -f $safeTaskName))
}

function Reset-ProdicloudTaskAppStateLocalBackupRoot {
    param([string]$BackupRoot)

    if ([string]::IsNullOrWhiteSpace([string]$BackupRoot)) {
        return
    }

    Remove-Item -LiteralPath $BackupRoot -Recurse -Force -ErrorAction SilentlyContinue
    Ensure-ProdicloudAppStatePluginDirectory -Path $BackupRoot
}

function Get-ProdicloudTaskAppStateLocalJournalPath {
    param([string]$BackupRoot)

    if ([string]::IsNullOrWhiteSpace([string]$BackupRoot)) {
        return ''
    }

    return (Join-Path $BackupRoot 'restore-journal.json')
}

function Get-ProdicloudTaskAppStateLocalVerifyReportPath {
    param([string]$BackupRoot)

    if ([string]::IsNullOrWhiteSpace([string]$BackupRoot)) {
        return ''
    }

    return (Join-Path $BackupRoot 'verify-report.json')
}

function Get-ProdicloudTaskAppStateLocalStagingRootPath {
    param([string]$BackupRoot)

    if ([string]::IsNullOrWhiteSpace([string]$BackupRoot)) {
        return ''
    }

    return (Join-Path $BackupRoot 'staging')
}

function Get-ProdicloudTaskAppStateLocalFileHashValue {
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

function Get-ProdicloudTaskAppStateLocalNormalizedRegLines {
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

function ConvertTo-ProdicloudTaskAppStateLocalSafeName {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return 'item'
    }

    return (([string]$Value -replace '^[A-Za-z]:', '') -replace '[\\/:*?"<>| ]', '_').Trim('_')
}

function Invoke-ProdicloudTaskLocalRegExport {
    param(
        [string]$RegistryPath,
        [string]$DestinationPath
    )

    if ([string]::IsNullOrWhiteSpace([string]$RegistryPath) -or [string]::IsNullOrWhiteSpace([string]$DestinationPath)) {
        return $false
    }

    Ensure-ProdicloudAppStatePluginDirectory -Path (Split-Path -Path $DestinationPath -Parent)
    cmd.exe /d /c ('reg export "{0}" "{1}" /y >nul 2>&1' -f $RegistryPath, $DestinationPath) | Out-Null
    return ([int]$LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $DestinationPath))
}

function Get-ProdicloudTaskLocalMountedUserHive {
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
            if ($entry.PSObject.Properties.Match('Loaded').Count -gt 0 -and [bool]$entry.Loaded -and
                $entry.PSObject.Properties.Match('SID').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$entry.SID)) {
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
    if (-not (Test-Path -LiteralPath $ntUserDatPath -PathType Leaf)) {
        return $null
    }

    $sanitized = (($PreferredLabel -replace '[^A-Za-z0-9]', '_')).Trim('_')
    if ([string]::IsNullOrWhiteSpace([string]$sanitized)) {
        $sanitized = 'user'
    }

    $mountName = ('PRODICLOUD_LOCAL_APPSTATE_{0}' -f $sanitized)
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

function Close-ProdicloudTaskLocalMountedUserHive {
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

function Convert-ProdicloudTaskLocalRegRoot {
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

    Ensure-ProdicloudAppStatePluginDirectory -Path (Split-Path -Path $DestinationPath -Parent)
    Set-Content -LiteralPath $DestinationPath -Value $rewritten -Encoding Unicode
    return $true
}

function Backup-ProdicloudTaskLocalUserRegistry {
    param(
        [string]$RegistryPath,
        [psobject]$ProfileTarget,
        [string]$BackupPath
    )

    $mountInfo = Get-ProdicloudTaskLocalMountedUserHive -ProfilePath ([string]$ProfileTarget.ProfilePath) -PreferredLabel ([string]$ProfileTarget.UserName)
    if ($null -eq $mountInfo) {
        return $false
    }

    try {
        $canonicalPath = Convert-ProdicloudAppStateRegistryPathToCanonicalRootLocal -RegistryPath $RegistryPath
        if ([string]::IsNullOrWhiteSpace([string]$canonicalPath) -or
            -not $canonicalPath.StartsWith('HKEY_CURRENT_USER', [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }

        $mountedRoot = $canonicalPath -replace '^HKEY_CURRENT_USER', ([string]$mountInfo.Root)
        $tempExportPath = Join-Path ([System.IO.Path]::GetTempPath()) ('prodicloud-local-reg-export-{0}.reg' -f ([guid]::NewGuid().ToString('N')))
        try {
            if (-not (Invoke-ProdicloudTaskLocalRegExport -RegistryPath $mountedRoot -DestinationPath $tempExportPath)) {
                return $false
            }

            return (Convert-ProdicloudTaskLocalRegRoot -SourcePath $tempExportPath -SourceRoot ([string]$mountInfo.Root) -DestinationRoot 'HKEY_CURRENT_USER' -DestinationPath $BackupPath)
        }
        finally {
            Remove-Item -LiteralPath $tempExportPath -Force -ErrorAction SilentlyContinue
        }
    }
    finally {
        Close-ProdicloudTaskLocalMountedUserHive -MountInfo $mountInfo
    }
}

function Restore-ProdicloudTaskLocalUserRegistryFromBackup {
    param(
        [string]$BackupPath,
        [string]$RegistryPath,
        [psobject]$ProfileTarget
    )

    $mountInfo = Get-ProdicloudTaskLocalMountedUserHive -ProfilePath ([string]$ProfileTarget.ProfilePath) -PreferredLabel ([string]$ProfileTarget.UserName)
    if ($null -eq $mountInfo) {
        return $false
    }

    try {
        $tempImportPath = Join-Path ([System.IO.Path]::GetTempPath()) ('prodicloud-local-reg-import-{0}.reg' -f ([guid]::NewGuid().ToString('N')))
        try {
            if (-not (Convert-ProdicloudTaskLocalRegRoot -SourcePath $BackupPath -SourceRoot 'HKEY_CURRENT_USER' -DestinationRoot ([string]$mountInfo.Root) -DestinationPath $tempImportPath)) {
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
        Close-ProdicloudTaskLocalMountedUserHive -MountInfo $mountInfo
    }
}

function Remove-ProdicloudTaskLocalRegistryPath {
    param(
        [string]$RegistryPath,
        [string]$Scope,
        [psobject]$ProfileTarget
    )

    if ([string]::Equals([string]$Scope, 'machine', [System.StringComparison]::OrdinalIgnoreCase)) {
        $providerPath = ConvertTo-ProdicloudLocalAppStateRegistryProviderPath -RegistryPath $RegistryPath
        if (-not [string]::IsNullOrWhiteSpace([string]$providerPath) -and (Test-Path -LiteralPath $providerPath)) {
            Remove-Item -LiteralPath $providerPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        return
    }

    $mountInfo = Get-ProdicloudTaskLocalMountedUserHive -ProfilePath ([string]$ProfileTarget.ProfilePath) -PreferredLabel ([string]$ProfileTarget.UserName)
    if ($null -eq $mountInfo) {
        return
    }

    try {
        $canonicalPath = Convert-ProdicloudAppStateRegistryPathToCanonicalRootLocal -RegistryPath $RegistryPath
        if ([string]::IsNullOrWhiteSpace([string]$canonicalPath) -or
            -not $canonicalPath.StartsWith('HKEY_CURRENT_USER', [System.StringComparison]::OrdinalIgnoreCase)) {
            return
        }

        $mountedProviderPath = ConvertTo-ProdicloudLocalAppStateRegistryProviderPath -RegistryPath ($canonicalPath -replace '^HKEY_CURRENT_USER', ([string]$mountInfo.Root))
        if (-not [string]::IsNullOrWhiteSpace([string]$mountedProviderPath) -and (Test-Path -LiteralPath $mountedProviderPath)) {
            Remove-Item -LiteralPath $mountedProviderPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    finally {
        Close-ProdicloudTaskLocalMountedUserHive -MountInfo $mountInfo
    }
}

function Test-ProdicloudTaskAppStateLocalDirectoryMatches {
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

    $normalizedSourceRoot = [string](Normalize-ProdicloudLocalAppStateComparablePath -Path $SourcePath)
    foreach ($directory in @(Get-ChildItem -LiteralPath $SourcePath -Recurse -Directory -Force -ErrorAction SilentlyContinue | Sort-Object FullName)) {
        $relativePath = [string](Normalize-ProdicloudLocalAppStateComparablePath -Path ([string]$directory.FullName))
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
        $relativePath = [string](Normalize-ProdicloudLocalAppStateComparablePath -Path ([string]$file.FullName))
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

        $sourceHash = Get-ProdicloudTaskAppStateLocalFileHashValue -Path ([string]$file.FullName)
        $destinationHash = Get-ProdicloudTaskAppStateLocalFileHashValue -Path $destinationChild
        if ([string]::IsNullOrWhiteSpace([string]$sourceHash) -or -not [string]::Equals([string]$sourceHash, [string]$destinationHash, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{ Success = $false; Reason = ('hash-mismatch:{0}' -f [string]$relativePath) }
        }
    }

    return [pscustomobject]@{ Success = $true; Reason = '' }
}

function Test-ProdicloudTaskAppStateLocalRegistryMatches {
    param(
        [string]$SourcePath,
        [string]$RegistryPath,
        [string]$Scope,
        [psobject]$ProfileTarget
    )

    if ([string]::IsNullOrWhiteSpace([string]$SourcePath) -or -not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        return [pscustomobject]@{ Success = $false; Reason = 'source-missing' }
    }

    $tempExportPath = Join-Path ([System.IO.Path]::GetTempPath()) ('prodicloud-local-reg-verify-{0}.reg' -f ([guid]::NewGuid().ToString('N')))
    $exported = $false
    try {
        if ([string]::Equals([string]$Scope, 'machine', [System.StringComparison]::OrdinalIgnoreCase)) {
            $canonicalRegistryPath = Convert-ProdicloudAppStateRegistryPathToCanonicalRootLocal -RegistryPath $RegistryPath
            $providerPath = ConvertTo-ProdicloudLocalAppStateRegistryProviderPath -RegistryPath $canonicalRegistryPath
            if (-not [string]::IsNullOrWhiteSpace([string]$providerPath) -and (Test-Path -LiteralPath $providerPath)) {
                $exported = Invoke-ProdicloudTaskLocalRegExport -RegistryPath $canonicalRegistryPath -DestinationPath $tempExportPath
            }
        }
        else {
            $exported = Backup-ProdicloudTaskLocalUserRegistry -RegistryPath $RegistryPath -ProfileTarget $ProfileTarget -BackupPath $tempExportPath
        }

        if (-not $exported) {
            return [pscustomobject]@{ Success = $false; Reason = 'registry-export-failed' }
        }

        $expectedLines = @(Get-ProdicloudTaskAppStateLocalNormalizedRegLines -Path $SourcePath)
        $actualLines = @(Get-ProdicloudTaskAppStateLocalNormalizedRegLines -Path $tempExportPath)
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

function Test-ProdicloudTaskAppStateLocalRestoreOperations {
    param([object[]]$Operations = @())

    $items = New-Object 'System.Collections.Generic.List[object]'
    foreach ($operation in @($Operations)) {
        if ($null -eq $operation) {
            continue
        }

        $status = 'verified'
        $reason = ''
        switch ([string]$operation.Kind) {
            'file' {
                if (-not (Test-Path -LiteralPath ([string]$operation.DestinationPath) -PathType Leaf)) {
                    $status = 'mismatch'
                    $reason = 'destination-missing'
                }
                else {
                    $sourceHash = Get-ProdicloudTaskAppStateLocalFileHashValue -Path ([string]$operation.SourcePath)
                    $destinationHash = Get-ProdicloudTaskAppStateLocalFileHashValue -Path ([string]$operation.DestinationPath)
                    if ([string]::IsNullOrWhiteSpace([string]$sourceHash) -or -not [string]::Equals([string]$sourceHash, [string]$destinationHash, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $status = 'mismatch'
                        $reason = 'hash-mismatch'
                    }
                }
            }
            'directory' {
                $directoryMatch = Test-ProdicloudTaskAppStateLocalDirectoryMatches -SourcePath ([string]$operation.SourcePath) -DestinationPath ([string]$operation.DestinationPath)
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
                $registryMatch = Test-ProdicloudTaskAppStateLocalRegistryMatches -SourcePath ([string]$operation.SourcePath) -RegistryPath ([string]$operation.RegistryPath) -Scope ([string]$operation.Scope) -ProfileTarget $profileTarget
                if (-not [bool]$registryMatch.Success) {
                    $status = 'mismatch'
                    $reason = [string]$registryMatch.Reason
                }
            }
            default {
                $status = 'skipped'
                $reason = 'unsupported-kind'
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
    return [pscustomobject]@{
        CheckedCount = @($rows).Count
        MismatchCount = @($mismatches).Count
        Succeeded = (@($mismatches).Count -eq 0)
        Items = $rows
    }
}

function Test-ProdicloudTaskAppStateLocalRollbackState {
    param([object[]]$BackupRecords = @())

    $items = New-Object 'System.Collections.Generic.List[object]'
    foreach ($record in @($BackupRecords)) {
        if ($null -eq $record) {
            continue
        }

        $status = 'verified'
        $reason = ''
        switch ([string]$record.Kind) {
            'file' {
                if ([bool]$record.Existed) {
                    if (-not (Test-Path -LiteralPath ([string]$record.DestinationPath) -PathType Leaf)) {
                        $status = 'mismatch'
                        $reason = 'destination-missing'
                    }
                    else {
                        $backupHash = Get-ProdicloudTaskAppStateLocalFileHashValue -Path ([string]$record.BackupPath)
                        $destinationHash = Get-ProdicloudTaskAppStateLocalFileHashValue -Path ([string]$record.DestinationPath)
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
                    $directoryMatch = Test-ProdicloudTaskAppStateLocalDirectoryMatches -SourcePath ([string]$record.BackupPath) -DestinationPath ([string]$record.DestinationPath)
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
                    $registryMatch = Test-ProdicloudTaskAppStateLocalRegistryMatches -SourcePath ([string]$record.BackupPath) -RegistryPath ([string]$record.RegistryPath) -Scope ([string]$record.Scope) -ProfileTarget $profileTarget
                    if (-not [bool]$registryMatch.Success) {
                        $status = 'mismatch'
                        $reason = [string]$registryMatch.Reason
                    }
                }
                else {
                    $tempExportPath = Join-Path ([System.IO.Path]::GetTempPath()) ('prodicloud-local-reg-rollback-{0}.reg' -f ([guid]::NewGuid().ToString('N')))
                    $exported = $false
                    try {
                        if ([string]::Equals([string]$record.Scope, 'machine', [System.StringComparison]::OrdinalIgnoreCase)) {
                            $canonicalRegistryPath = Convert-ProdicloudAppStateRegistryPathToCanonicalRootLocal -RegistryPath ([string]$record.RegistryPath)
                            $providerPath = ConvertTo-ProdicloudLocalAppStateRegistryProviderPath -RegistryPath $canonicalRegistryPath
                            if (-not [string]::IsNullOrWhiteSpace([string]$providerPath) -and (Test-Path -LiteralPath $providerPath)) {
                                $exported = Invoke-ProdicloudTaskLocalRegExport -RegistryPath $canonicalRegistryPath -DestinationPath $tempExportPath
                            }
                        }
                        else {
                            $exported = Backup-ProdicloudTaskLocalUserRegistry -RegistryPath ([string]$record.RegistryPath) -ProfileTarget $profileTarget -BackupPath $tempExportPath
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
    return [pscustomobject]@{
        CheckedCount = @($rows).Count
        MismatchCount = @($mismatches).Count
        Succeeded = (@($mismatches).Count -eq 0)
        Items = $rows
    }
}

function Backup-ProdicloudTaskAppStateLocalOperations {
    param(
        [object[]]$Operations = @(),
        [string]$BackupRoot
    )

    Ensure-ProdicloudAppStatePluginDirectory -Path $BackupRoot
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
        }

        switch ([string]$operation.Kind) {
            'file' {
                $destinationPath = [string]$operation.DestinationPath
                if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
                    $backupPath = Join-Path (Join-Path $BackupRoot 'files') ((ConvertTo-ProdicloudTaskAppStateLocalSafeName -Value $backupBaseName) + [System.IO.Path]::GetExtension($destinationPath))
                    Ensure-ProdicloudAppStatePluginDirectory -Path (Split-Path -Path $backupPath -Parent)
                    Copy-Item -LiteralPath $destinationPath -Destination $backupPath -Force -ErrorAction Stop
                    $record.BackupPath = [string]$backupPath
                    $record.Existed = $true
                }
            }
            'directory' {
                $destinationPath = [string]$operation.DestinationPath
                if (Test-Path -LiteralPath $destinationPath -PathType Container) {
                    $backupPath = Join-Path (Join-Path $BackupRoot 'directories') (ConvertTo-ProdicloudTaskAppStateLocalSafeName -Value $backupBaseName)
                    Ensure-ProdicloudAppStatePluginDirectory -Path (Split-Path -Path $backupPath -Parent)
                    Copy-Item -LiteralPath $destinationPath -Destination $backupPath -Recurse -Force -ErrorAction Stop
                    $record.BackupPath = [string]$backupPath
                    $record.Existed = $true
                }
            }
            'registry' {
                $backupPath = Join-Path (Join-Path $BackupRoot 'registry') ((ConvertTo-ProdicloudTaskAppStateLocalSafeName -Value ($backupBaseName + '-' + [string]$operation.RegistryPath)) + '.reg')
                $exported = $false
                if ([string]::Equals([string]$operation.Scope, 'machine', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $canonicalRegistryPath = Convert-ProdicloudAppStateRegistryPathToCanonicalRootLocal -RegistryPath ([string]$operation.RegistryPath)
                    $providerPath = ConvertTo-ProdicloudLocalAppStateRegistryProviderPath -RegistryPath $canonicalRegistryPath
                    if (-not [string]::IsNullOrWhiteSpace([string]$providerPath) -and (Test-Path -LiteralPath $providerPath)) {
                        $exported = Invoke-ProdicloudTaskLocalRegExport -RegistryPath $canonicalRegistryPath -DestinationPath $backupPath
                    }
                }
                else {
                    $profileTarget = [pscustomobject]@{
                        Label = [string]$operation.ProfileLabel
                        UserName = [string]$operation.UserName
                        ProfilePath = [string]$operation.ProfilePath
                    }
                    $exported = Backup-ProdicloudTaskLocalUserRegistry -RegistryPath ([string]$operation.RegistryPath) -ProfileTarget $profileTarget -BackupPath $backupPath
                }

                if ($exported) {
                    $record.BackupPath = [string]$backupPath
                    $record.Existed = $true
                }
            }
        }

        $records.Add([pscustomobject]$record) | Out-Null
    }

    return @($records.ToArray())
}

function Invoke-ProdicloudTaskAppStateLocalRollback {
    param(
        [object[]]$BackupRecords = @()
    )

    $records = @($BackupRecords)
    [array]::Reverse($records)
    foreach ($record in @($records)) {
        if ($null -eq $record) {
            continue
        }

        try {
            switch ([string]$record.Kind) {
                'file' {
                    $destinationPath = [string]$record.DestinationPath
                    if ([bool]$record.Existed -and -not [string]::IsNullOrWhiteSpace([string]$record.BackupPath) -and (Test-Path -LiteralPath ([string]$record.BackupPath))) {
                        Ensure-ProdicloudAppStatePluginDirectory -Path (Split-Path -Path $destinationPath -Parent)
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
                        Ensure-ProdicloudAppStatePluginDirectory -Path (Split-Path -Path $destinationPath -Parent)
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
                            [void](Restore-ProdicloudTaskLocalUserRegistryFromBackup -BackupPath ([string]$record.BackupPath) -RegistryPath ([string]$record.RegistryPath) -ProfileTarget $profileTarget)
                        }
                    }
                    else {
                        Remove-ProdicloudTaskLocalRegistryPath -RegistryPath ([string]$record.RegistryPath) -Scope ([string]$record.Scope) -ProfileTarget $profileTarget
                    }
                }
            }
        }
        catch {
        }
    }

    return (Test-ProdicloudTaskAppStateLocalRollbackState -BackupRecords @($BackupRecords))
}

function Test-ProdicloudTaskPortableProfilePayload {
    param([psobject]$TaskBlock)

    if ($null -eq $TaskBlock -or $TaskBlock.PSObject.Properties.Match('AppStateSpec').Count -lt 1 -or $null -eq $TaskBlock.AppStateSpec) {
        return $false
    }

    $appStateSpec = $TaskBlock.AppStateSpec
    if ($appStateSpec.PSObject.Properties.Match('portableProfilePayload').Count -lt 1) {
        return $false
    }

    return [bool]$appStateSpec.portableProfilePayload
}

function Test-ProdicloudTaskCanonicalManagerProfilePayload {
    param([psobject]$TaskBlock)

    if (Test-ProdicloudTaskPortableProfilePayload -TaskBlock $TaskBlock) {
        return $true
    }

    if ($null -eq $TaskBlock -or $TaskBlock.PSObject.Properties.Match('AppStateSpec').Count -lt 1 -or $null -eq $TaskBlock.AppStateSpec) {
        return $false
    }

    $appStateSpec = $TaskBlock.AppStateSpec
    $profileRules = New-Object 'System.Collections.Generic.List[object]'
    foreach ($collectionName in @('profileDirectories', 'profileFiles', 'userRegistryKeys')) {
        if ($appStateSpec.PSObject.Properties.Match($collectionName).Count -lt 1) {
            continue
        }

        foreach ($rule in @($appStateSpec.$collectionName)) {
            if ($null -ne $rule) {
                $profileRules.Add($rule) | Out-Null
            }
        }
    }

    $rules = @($profileRules.ToArray())
    if (@($rules).Count -lt 1) {
        return $false
    }

    foreach ($rule in @($rules)) {
        $targetProfiles = @(
            Get-ProdicloudTaskAppStateRuleValue -Rule $rule -PropertyName 'targetProfiles' |
                ForEach-Object { [string]$_ } |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
        )
        if (@($targetProfiles).Count -gt 0) {
            return $false
        }
    }

    return $true
}

function Get-ProdicloudTaskPortableProfilePayloadCanonicalProfileTarget {
    return [pscustomobject]@{
        Label = 'manager'
        UserName = 'manager'
        ProfilePath = 'C:\Users\manager'
    }
}

function Get-ProdicloudTaskPortableProfilePayloadSourceProfileTarget {
    param([object[]]$ProfileTargets = @())

    $rows = New-Object 'System.Collections.Generic.List[object]'
    $seen = @{}
    foreach ($profileTarget in @($ProfileTargets)) {
        if ($null -eq $profileTarget) {
            continue
        }

        $profilePath = if ($profileTarget.PSObject.Properties.Match('ProfilePath').Count -gt 0) { [string]$profileTarget.ProfilePath } else { '' }
        $userName = if ($profileTarget.PSObject.Properties.Match('UserName').Count -gt 0) { [string]$profileTarget.UserName } else { '' }
        $label = if ($profileTarget.PSObject.Properties.Match('Label').Count -gt 0) { [string]$profileTarget.Label } else { '' }
        if ([string]::IsNullOrWhiteSpace([string]$profilePath)) {
            continue
        }

        $normalizedKey = $profilePath.TrimEnd('\').ToLowerInvariant()
        if ($seen.ContainsKey($normalizedKey)) {
            continue
        }

        $rows.Add([pscustomobject]@{
            Label = [string]$label
            UserName = [string]$userName
            ProfilePath = [string]$profilePath.TrimEnd('\')
        }) | Out-Null
        $seen[$normalizedKey] = $true
    }

    $targets = @($rows.ToArray())
    if (@($targets).Count -lt 1) {
        return $null
    }
    if (@($targets).Count -gt 1) {
        throw 'Portable app-state payload normalization requires exactly one source profile target.'
    }

    return $targets[0]
}

function Rename-ProdicloudTaskPortableProfilePayloadUserFolder {
    param(
        [string]$ScratchRoot,
        [string]$RelativeRootPath,
        [string]$SourceUserToken,
        [string]$CanonicalUserToken
    )

    if ([string]::IsNullOrWhiteSpace([string]$ScratchRoot) -or
        [string]::IsNullOrWhiteSpace([string]$RelativeRootPath) -or
        [string]::IsNullOrWhiteSpace([string]$SourceUserToken) -or
        [string]::IsNullOrWhiteSpace([string]$CanonicalUserToken)) {
        return
    }

    if ([string]::Equals([string]$SourceUserToken, [string]$CanonicalUserToken, [System.StringComparison]::OrdinalIgnoreCase)) {
        return
    }

    $rootPath = Join-Path $ScratchRoot $RelativeRootPath
    if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) {
        return
    }

    $sourcePath = Join-Path $rootPath $SourceUserToken
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
        return
    }

    $destinationPath = Join-Path $rootPath $CanonicalUserToken
    if (Test-Path -LiteralPath $destinationPath) {
        throw ("Portable app-state payload destination already exists: {0}" -f [string]$destinationPath)
    }

    Move-Item -LiteralPath $sourcePath -Destination $destinationPath -Force -ErrorAction Stop
}

function Normalize-ProdicloudTaskPortableProfilePayloadSourcePath {
    param(
        [string]$SourcePath,
        [string]$CanonicalUserToken
    )

    if ([string]::IsNullOrWhiteSpace([string]$SourcePath) -or [string]::IsNullOrWhiteSpace([string]$CanonicalUserToken)) {
        return [string]$SourcePath
    }

    $parts = @(([string]$SourcePath).Replace('/', '\').Split('\'))
    if (@($parts).Count -lt 3) {
        return [string]$SourcePath
    }

    if ([string]::Equals([string]$parts[0], 'payload', [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals([string]$parts[1], 'profile-directories', [System.StringComparison]::OrdinalIgnoreCase)) {
        $parts[2] = [string]$CanonicalUserToken
        return ($parts -join '\')
    }

    if ([string]::Equals([string]$parts[0], 'payload', [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals([string]$parts[1], 'profile-files', [System.StringComparison]::OrdinalIgnoreCase)) {
        $parts[2] = [string]$CanonicalUserToken
        return ($parts -join '\')
    }

    if (@($parts).Count -ge 4 -and
        [string]::Equals([string]$parts[0], 'payload', [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals([string]$parts[1], 'registry', [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals([string]$parts[2], 'user', [System.StringComparison]::OrdinalIgnoreCase)) {
        $parts[3] = [string]$CanonicalUserToken
        return ($parts -join '\')
    }

    return [string]$SourcePath
}

function Normalize-ProdicloudTaskPortableProfilePayloadUserRegistryExports {
    param(
        [string]$ScratchRoot,
        [string]$SourceProfilePath,
        [string]$CanonicalProfilePath
    )

    if ([string]::IsNullOrWhiteSpace([string]$ScratchRoot) -or
        [string]::IsNullOrWhiteSpace([string]$SourceProfilePath) -or
        [string]::IsNullOrWhiteSpace([string]$CanonicalProfilePath)) {
        return
    }

    $registryRoot = Join-Path $ScratchRoot 'payload\registry\user'
    if (-not (Test-Path -LiteralPath $registryRoot -PathType Container)) {
        return
    }

    $escapedSourceProfilePath = $SourceProfilePath.Replace('\', '\\')
    $escapedCanonicalProfilePath = $CanonicalProfilePath.Replace('\', '\\')
    foreach ($registryFile in @(Get-ChildItem -LiteralPath $registryRoot -Recurse -File -Filter *.reg -Force -ErrorAction SilentlyContinue | Sort-Object FullName)) {
        $content = Get-Content -LiteralPath $registryFile.FullName -Raw
        if ([string]::IsNullOrWhiteSpace([string]$content)) {
            continue
        }

        $updatedContent = $content.Replace($SourceProfilePath, $CanonicalProfilePath).Replace($escapedSourceProfilePath, $escapedCanonicalProfilePath)
        if (-not [string]::Equals([string]$updatedContent, [string]$content, [System.StringComparison]::Ordinal)) {
            Set-Content -LiteralPath $registryFile.FullName -Value $updatedContent -Encoding Unicode
        }
    }
}

function Convert-ProdicloudTaskAppStateZipToPortableProfilePayload {
    param(
        [string]$ZipPath,
        [string]$TaskName,
        [object[]]$ProfileTargets = @()
    )

    if ([string]::IsNullOrWhiteSpace([string]$ZipPath) -or -not (Test-Path -LiteralPath $ZipPath)) {
        throw ("Portable app-state zip was not found: {0}" -f [string]$ZipPath)
    }

    $manifestInfo = Get-ProdicloudTaskAppStateManifestFromZip -ZipPath $ZipPath -ExpectedTaskName $TaskName
    $scratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('prodicloud-portable-app-state-{0}' -f ([guid]::NewGuid().ToString('N')))
    Ensure-ProdicloudAppStatePluginDirectory -Path $scratchRoot

    try {
        Expand-Archive -LiteralPath $ZipPath -DestinationPath $scratchRoot -Force
        $manifest = $manifestInfo.Manifest
        $canonicalProfileTarget = Get-ProdicloudTaskPortableProfilePayloadCanonicalProfileTarget
        $sourceProfileTarget = Get-ProdicloudTaskPortableProfilePayloadSourceProfileTarget -ProfileTargets @($ProfileTargets)
        $sourceUserToken = if ($null -ne $sourceProfileTarget -and -not [string]::IsNullOrWhiteSpace([string]$sourceProfileTarget.UserName)) { [string]$sourceProfileTarget.UserName } else { '' }
        $canonicalUserToken = [string]$canonicalProfileTarget.UserName

        foreach ($entry in @($manifest.profileDirectories)) {
            if ($null -eq $entry) {
                continue
            }

            if ($entry.PSObject.Properties.Match('targetProfiles').Count -gt 0) {
                $entry.targetProfiles = @()
            }
            if ($entry.PSObject.Properties.Match('sourcePath').Count -gt 0) {
                $entry.sourcePath = Normalize-ProdicloudTaskPortableProfilePayloadSourcePath -SourcePath ([string]$entry.sourcePath) -CanonicalUserToken $canonicalUserToken
            }
        }
        foreach ($entry in @($manifest.profileFiles)) {
            if ($null -eq $entry) {
                continue
            }

            if ($entry.PSObject.Properties.Match('targetProfiles').Count -gt 0) {
                $entry.targetProfiles = @()
            }
            if ($entry.PSObject.Properties.Match('sourcePath').Count -gt 0) {
                $entry.sourcePath = Normalize-ProdicloudTaskPortableProfilePayloadSourcePath -SourcePath ([string]$entry.sourcePath) -CanonicalUserToken $canonicalUserToken
            }
        }
        foreach ($entry in @($manifest.registryImports)) {
            if ($null -eq $entry) {
                continue
            }

            $scope = if ($entry.PSObject.Properties.Match('scope').Count -gt 0) { [string]$entry.scope } else { '' }
            if ([string]::Equals([string]$scope, 'user', [System.StringComparison]::OrdinalIgnoreCase)) {
                if ($entry.PSObject.Properties.Match('targetProfiles').Count -gt 0) {
                    $entry.targetProfiles = @()
                }
                if ($entry.PSObject.Properties.Match('sourcePath').Count -gt 0) {
                    $entry.sourcePath = Normalize-ProdicloudTaskPortableProfilePayloadSourcePath -SourcePath ([string]$entry.sourcePath) -CanonicalUserToken $canonicalUserToken
                }
            }
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$sourceUserToken)) {
            Rename-ProdicloudTaskPortableProfilePayloadUserFolder -ScratchRoot $scratchRoot -RelativeRootPath 'payload\profile-directories' -SourceUserToken $sourceUserToken -CanonicalUserToken $canonicalUserToken
            Rename-ProdicloudTaskPortableProfilePayloadUserFolder -ScratchRoot $scratchRoot -RelativeRootPath 'payload\profile-files' -SourceUserToken $sourceUserToken -CanonicalUserToken $canonicalUserToken
            Rename-ProdicloudTaskPortableProfilePayloadUserFolder -ScratchRoot $scratchRoot -RelativeRootPath 'payload\registry\user' -SourceUserToken $sourceUserToken -CanonicalUserToken $canonicalUserToken
        }

        if ($null -ne $sourceProfileTarget -and
            -not [string]::IsNullOrWhiteSpace([string]$sourceProfileTarget.ProfilePath) -and
            -not [string]::Equals([string]$sourceProfileTarget.ProfilePath, [string]$canonicalProfileTarget.ProfilePath, [System.StringComparison]::OrdinalIgnoreCase)) {
            Normalize-ProdicloudTaskPortableProfilePayloadUserRegistryExports -ScratchRoot $scratchRoot -SourceProfilePath ([string]$sourceProfileTarget.ProfilePath) -CanonicalProfilePath ([string]$canonicalProfileTarget.ProfilePath)
        }

        Set-Content -LiteralPath (Join-Path $scratchRoot 'app-state.manifest.json') -Value (ConvertTo-JsonCompat -InputObject $manifest -Depth 12) -Encoding UTF8
        Remove-Item -LiteralPath $ZipPath -Force -ErrorAction SilentlyContinue
        $previousProgressPreference = $global:ProgressPreference
        try {
            $global:ProgressPreference = 'SilentlyContinue'
            Compress-Archive -LiteralPath @(Get-ChildItem -LiteralPath $scratchRoot -Force | Select-Object -ExpandProperty FullName) -DestinationPath $ZipPath -Force
        }
        finally {
            $global:ProgressPreference = $previousProgressPreference
        }
    }
    finally {
        Remove-Item -LiteralPath $scratchRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Convert-ProdicloudTaskCapturePlanToPortableProfileSourcePlan {
    param([psobject]$CapturePlan)

    if ($null -eq $CapturePlan) {
        return $null
    }

    $clone = ConvertFrom-Json -InputObject (ConvertTo-JsonCompat -InputObject $CapturePlan -Depth 12) -ErrorAction Stop
    foreach ($collectionName in @('profileDirectories', 'profileFiles', 'userRegistryKeys')) {
        if ($clone.PSObject.Properties.Match($collectionName).Count -lt 1) {
            continue
        }

        foreach ($entry in @($clone.$collectionName)) {
            if ($null -eq $entry) {
                continue
            }

            if ($entry.PSObject.Properties.Match('targetProfiles').Count -gt 0) {
                $entry.targetProfiles = @()
            }
        }
    }

    return $clone
}

function Save-ProdicloudTaskAppStateFromLocalMachine {
    param(
        [psobject]$TaskBlock,
        [string[]]$RequestedUsers = @()
    )

    if (Test-ProdicloudTaskStartupProfileEnabled -TaskBlock $TaskBlock) {
        $pluginInfo = Write-ProdicloudTaskStartupProfilePluginZip -TaskBlock $TaskBlock
        return [pscustomobject]@{
            Status = 'saved'
            Message = 'saved'
            Warning = $false
            ZipPath = if ($null -ne $pluginInfo -and $pluginInfo.PSObject.Properties.Match('ZipPath').Count -gt 0) { [string]$pluginInfo.ZipPath } else { [string](Get-ProdicloudTaskAppStateZipPath -TaskBlock $TaskBlock) }
            SelectedUsers = @()
        }
    }

    $capturePlan = Get-ProdicloudTaskAppStateCapturePlan -TaskBlock $TaskBlock
    $taskName = Get-ProdicloudTaskAppStateIdentity -TaskBlock $TaskBlock
    if ($null -eq $capturePlan) {
        Write-Host ("App-state skipped: {0} => no app-state spec or legacy coverage" -f [string]$taskName)
        return [pscustomobject]@{ Status = 'skipped'; Message = 'no app-state spec or legacy coverage'; Warning = $false; SelectedUsers = @() }
    }

    $profileTargets = @(Resolve-ProdicloudLocalAppStateProfileTargets -RequestedUsers $RequestedUsers)
    $pluginDirectory = Get-ProdicloudTaskAppStatePluginDirectoryPath -TaskBlock $TaskBlock
    $zipPath = Get-ProdicloudTaskAppStateZipPath -TaskBlock $TaskBlock
    Ensure-ProdicloudAppStatePluginDirectory -Path $pluginDirectory
    Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue

    $effectiveCapturePlan = $capturePlan
    if (Test-ProdicloudTaskPortableProfilePayload -TaskBlock $TaskBlock) {
        $effectiveCapturePlan = Convert-ProdicloudTaskCapturePlanToPortableProfileSourcePlan -CapturePlan $capturePlan
    }

    $planJson = ConvertTo-ProdicloudTaskAppStateCapturePlanJson -CapturePlan $effectiveCapturePlan
    $planPath = Join-Path ([System.IO.Path]::GetTempPath()) ('prodicloud-local-app-state-plan-{0}.json' -f ([guid]::NewGuid().ToString('N')))
    $guestHelperPath = Get-ProdicloudAppStateGuestHelperPath
    Set-Content -LiteralPath $planPath -Value $planJson -Encoding UTF8
    Import-Module $guestHelperPath -Force -DisableNameChecking

    try {
        $result = Invoke-ProdicloudTaskAppStateCapture `
            -TaskName $taskName `
            -PlanPath $planPath `
            -OutputZipPath $zipPath `
            -ManagerUser '' `
            -AssistantUser '' `
            -ProfileTargets @($profileTargets)

        if (-not [bool]$result.CreatedZip) {
            Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
            return [pscustomobject]@{
                Status = 'skipped'
                Message = 'no matching local app-state items were captured'
                Warning = $false
                SelectedUsers = @($profileTargets | ForEach-Object { [string]$_.UserName })
            }
        }

        if ((@($profileTargets).Count -eq 1) -and (Test-ProdicloudTaskCanonicalManagerProfilePayload -TaskBlock $TaskBlock)) {
            Convert-ProdicloudTaskAppStateZipToPortableProfilePayload -ZipPath $zipPath -TaskName $taskName -ProfileTargets @($profileTargets)
            Write-Host ("App-state canonical manager payload normalized: {0}" -f [string]$taskName)
        }

        if ([string]::Equals([string]$TaskBlock.TaskType, 'package', [System.StringComparison]::OrdinalIgnoreCase)) {
            try { Assert-ProdicloudPackageAppStateArchivePortable -ZipPath $zipPath }
            catch { Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue; throw }
        }

        return [pscustomobject]@{
            Status = 'saved'
            Message = 'saved'
            Warning = $false
            ZipPath = [string]$zipPath
            SelectedUsers = @($profileTargets | ForEach-Object { [string]$_.UserName })
        }
    }
    finally {
        Remove-Item -LiteralPath $planPath -Force -ErrorAction SilentlyContinue
    }
}

function Restore-ProdicloudTaskAppStateToLocalMachine {
    param(
        [psobject]$TaskBlock,
        [string[]]$RequestedUsers = @()
    )

    $pluginInfo = Get-ProdicloudTaskAppStatePluginInfo -TaskBlock $TaskBlock
    $taskName = [string]$pluginInfo.TaskName
    if ($pluginInfo.Status -ne 'ready') {
        throw ("Task app-state plugin is not ready for local restore: {0}" -f [string]$pluginInfo.Message)
    }
    if ([string]::Equals([string]$TaskBlock.TaskType, 'package', [System.StringComparison]::OrdinalIgnoreCase)) {
        Assert-ProdicloudPackageAppStateArchivePortable -ZipPath ([string]$pluginInfo.ZipPath)
    }

    $profileTargets = @(Resolve-ProdicloudLocalAppStateProfileTargets -RequestedUsers $RequestedUsers)
    $manifestInfo = Get-ProdicloudTaskAppStateManifestFromZip -ZipPath ([string]$pluginInfo.ZipPath) -ExpectedTaskName $taskName
    Assert-ProdicloudTaskAppStateManifestAllowedForLocalRestore -TaskBlock $TaskBlock -Manifest $manifestInfo.Manifest

    $backupRoot = Get-ProdicloudTaskAppStateLocalBackupRootPath -TaskBlock $TaskBlock -TaskName $taskName
    Reset-ProdicloudTaskAppStateLocalBackupRoot -BackupRoot $backupRoot
    $journalPath = Get-ProdicloudTaskAppStateLocalJournalPath -BackupRoot $backupRoot
    $verifyReportPath = Get-ProdicloudTaskAppStateLocalVerifyReportPath -BackupRoot $backupRoot
    $stagingRoot = Get-ProdicloudTaskAppStateLocalStagingRootPath -BackupRoot $backupRoot
    Ensure-ProdicloudAppStatePluginDirectory -Path $stagingRoot

    $expandedRoot = Join-Path $stagingRoot 'expanded'
    $workingZipPath = Join-Path $stagingRoot 'app-state.zip'
    Copy-Item -LiteralPath ([string]$pluginInfo.ZipPath) -Destination $workingZipPath -Force
    Expand-Archive -LiteralPath $workingZipPath -DestinationPath $expandedRoot -Force

    $guestHelperPath = Get-ProdicloudAppStateGuestHelperPath
    Import-Module $guestHelperPath -Force -DisableNameChecking

    $operations = @(Get-ProdicloudTaskAppStateLocalRestoreOperations -ExpandedRoot $expandedRoot -Manifest $manifestInfo.Manifest -ProfileTargets @($profileTargets))
    $backupRecords = @(Backup-ProdicloudTaskAppStateLocalOperations -Operations $operations -BackupRoot $backupRoot)
    $journal = [ordered]@{
        taskName = [string]$taskName
        createdAtUtc = [string][DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')
        status = 'backed-up'
        backupRoot = [string]$backupRoot
        verifyReportPath = [string]$verifyReportPath
        selectedUsers = @($profileTargets | ForEach-Object { [string]$_.UserName })
        operations = @($backupRecords)
    }
    Set-Content -LiteralPath $journalPath -Value (ConvertTo-JsonCompat -InputObject $journal -Depth 10) -Encoding UTF8

    $verifyReport = $null
    try {
        $replayResult = Invoke-ProdicloudTaskAppStateReplay `
            -ZipPath $workingZipPath `
            -TaskName $taskName `
            -ManagerUser '' `
            -AssistantUser '' `
            -ProfileTargets @($profileTargets)

        if ($null -ne $replayResult -and $replayResult.PSObject.Properties.Match('VerifyItems').Count -gt 0) {
            $verifyItems = @($replayResult.VerifyItems)
            $verifyReport = [pscustomobject]@{
                CheckedCount = @($verifyItems).Count
                MismatchCount = @(@($verifyItems | Where-Object { [string]$_.Status -eq 'mismatch' })).Count
                SkippedCount = @(@($verifyItems | Where-Object { [string]$_.Status -eq 'skipped' })).Count
                Succeeded = (@(@($verifyItems | Where-Object { [string]$_.Status -eq 'mismatch' })).Count -eq 0)
                Items = $verifyItems
            }
        }
        else {
            $verifyReport = Test-ProdicloudTaskAppStateLocalRestoreOperations -Operations @($operations)
        }
        $verifyReportDocument = [ordered]@{
            taskName = [string]$taskName
            checkedAtUtc = [string][DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')
            phase = 'post-restore'
            succeeded = [bool]$verifyReport.Succeeded
            checkedCount = [int]$verifyReport.CheckedCount
            mismatchCount = [int]$verifyReport.MismatchCount
            skippedCount = [int]$(if ($verifyReport.PSObject.Properties.Match('SkippedCount').Count -gt 0) { $verifyReport.SkippedCount } else { 0 })
            items = @($verifyReport.Items)
        }
        Set-Content -LiteralPath $verifyReportPath -Value (ConvertTo-JsonCompat -InputObject $verifyReportDocument -Depth 10) -Encoding UTF8
        if (-not [bool]$verifyReport.Succeeded) {
            throw ("Task app-state restore verification failed for '{0}'." -f [string]$taskName)
        }

        $journal.status = 'verified'
        $journal.completedAtUtc = [string][DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')
        $journal.verify = [ordered]@{
            succeeded = $true
            checkedCount = [int]$verifyReport.CheckedCount
            mismatchCount = [int]$verifyReport.MismatchCount
            skippedCount = [int]$(if ($verifyReport.PSObject.Properties.Match('SkippedCount').Count -gt 0) { $verifyReport.SkippedCount } else { 0 })
        }
        Set-Content -LiteralPath $journalPath -Value (ConvertTo-JsonCompat -InputObject $journal -Depth 10) -Encoding UTF8

        return [pscustomobject]@{
            Status = 'restored'
            Message = 'restored'
            Warning = $false
            BackupRoot = [string]$backupRoot
            JournalPath = [string]$journalPath
            VerifyReportPath = [string]$verifyReportPath
            SelectedUsers = @($profileTargets | ForEach-Object { [string]$_.UserName })
            Result = $replayResult
        }
    }
    catch {
        $rollbackResult = Invoke-ProdicloudTaskAppStateLocalRollback -BackupRecords @($backupRecords)
        $verifyReportDocument = [ordered]@{
            taskName = [string]$taskName
            checkedAtUtc = [string][DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')
            phase = $(if ($null -ne $verifyReport) { 'post-restore' } else { 'restore-exception' })
            succeeded = $(if ($null -ne $verifyReport) { [bool]$verifyReport.Succeeded } else { $false })
            checkedCount = $(if ($null -ne $verifyReport) { [int]$verifyReport.CheckedCount } else { 0 })
            mismatchCount = $(if ($null -ne $verifyReport) { [int]$verifyReport.MismatchCount } else { 0 })
            skippedCount = $(if ($null -ne $verifyReport -and $verifyReport.PSObject.Properties.Match('SkippedCount').Count -gt 0) { [int]$verifyReport.SkippedCount } else { 0 })
            error = [string]$_.Exception.Message
            rollbackAttempted = $true
            rollbackSucceeded = [bool]$rollbackResult.Succeeded
            rollbackCheckedCount = [int]$rollbackResult.CheckedCount
            rollbackMismatchCount = [int]$rollbackResult.MismatchCount
            rollbackSkippedCount = [int]$(if ($rollbackResult.PSObject.Properties.Match('SkippedCount').Count -gt 0) { $rollbackResult.SkippedCount } else { 0 })
            items = $(if ($null -ne $verifyReport) { @($verifyReport.Items) } else { @() })
            rollbackItems = @($rollbackResult.Items)
        }
        Set-Content -LiteralPath $verifyReportPath -Value (ConvertTo-JsonCompat -InputObject $verifyReportDocument -Depth 10) -Encoding UTF8

        $journal.status = $(if ([bool]$rollbackResult.Succeeded) { 'rolled-back' } else { 'rollback-failed' })
        $journal.failedAtUtc = [string][DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')
        $journal.error = [string]$_.Exception.Message
        $journal.verify = [ordered]@{
            succeeded = $(if ($null -ne $verifyReport) { [bool]$verifyReport.Succeeded } else { $false })
            checkedCount = $(if ($null -ne $verifyReport) { [int]$verifyReport.CheckedCount } else { 0 })
            mismatchCount = $(if ($null -ne $verifyReport) { [int]$verifyReport.MismatchCount } else { 0 })
            skippedCount = $(if ($null -ne $verifyReport -and $verifyReport.PSObject.Properties.Match('SkippedCount').Count -gt 0) { [int]$verifyReport.SkippedCount } else { 0 })
        }
        $journal.rollback = [ordered]@{
            succeeded = [bool]$rollbackResult.Succeeded
            checkedCount = [int]$rollbackResult.CheckedCount
            mismatchCount = [int]$rollbackResult.MismatchCount
            skippedCount = [int]$(if ($rollbackResult.PSObject.Properties.Match('SkippedCount').Count -gt 0) { $rollbackResult.SkippedCount } else { 0 })
        }
        Set-Content -LiteralPath $journalPath -Value (ConvertTo-JsonCompat -InputObject $journal -Depth 10) -Encoding UTF8
        if (-not [bool]$rollbackResult.Succeeded) {
            throw ("{0} Rollback verification also failed for '{1}'." -f [string]$_.Exception.Message, [string]$taskName)
        }
        throw
    }
}
