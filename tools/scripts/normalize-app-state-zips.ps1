param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Initialize-AppStateNormalizationZipSupport {
    if (-not ([System.Management.Automation.PSTypeName]'System.IO.Compression.ZipArchive').Type) {
        Add-Type -AssemblyName 'System.IO.Compression.FileSystem' -ErrorAction SilentlyContinue
        Add-Type -AssemblyName 'System.IO.Compression' -ErrorAction SilentlyContinue
    }
}

function Get-AppStateNormalizationZipPaths {
    param([string]$RepositoryRoot)

    $roots = @(
        'windows\init',
        'windows\update',
        'linux\init',
        'linux\update'
    )

    foreach ($relativeRoot in @($roots)) {
        $fullRoot = Join-Path $RepositoryRoot $relativeRoot
        if (-not (Test-Path -LiteralPath $fullRoot)) {
            continue
        }

        foreach ($zipPath in @(
            Get-ChildItem -LiteralPath $fullRoot -Recurse -Filter 'app-state.zip' -File -ErrorAction SilentlyContinue |
                Where-Object { [string]::Equals([string](Split-Path -Path $_.DirectoryName -Leaf), 'app-state', [System.StringComparison]::OrdinalIgnoreCase) } |
                Sort-Object FullName
        )) {
            if ($null -ne $zipPath) {
                [string]$zipPath.FullName
            }
        }
    }
}

function Get-AppStateNormalizationAllowedProfileTokens {
    return @('manager', 'assistant', 'default', 'public')
}

function Test-AppStateNormalizationAllowedProfileToken {
    param([string]$Token)

    $normalizedToken = if ($null -eq $Token) { '' } else { [string]$Token.Trim().ToLowerInvariant() }
    if ([string]::IsNullOrWhiteSpace([string]$normalizedToken)) {
        return $true
    }

    return (@(Get-AppStateNormalizationAllowedProfileTokens) -contains $normalizedToken)
}

function Normalize-AppStateNormalizationManifestPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace([string]$Path)) {
        return ''
    }

    return (([string]$Path).Replace('/', '\')).TrimStart('\')
}

function Get-AppStateNormalizationTaskJsonPath {
    param([string]$ZipPath)

    $pluginRoot = Split-Path -Path $ZipPath -Parent
    $taskRoot = Split-Path -Path $pluginRoot -Parent
    return (Join-Path $taskRoot 'task.json')
}

function Get-AppStateNormalizationTaskAppStateSpec {
    param([string]$ZipPath)

    $taskJsonPath = Get-AppStateNormalizationTaskJsonPath -ZipPath $ZipPath
    if (-not (Test-Path -LiteralPath $taskJsonPath -PathType Leaf)) {
        return $null
    }

    $taskJsonText = [string](Get-Content -LiteralPath $taskJsonPath -Raw -ErrorAction Stop)
    if ([string]::IsNullOrWhiteSpace([string]$taskJsonText)) {
        return $null
    }

    $taskJson = ConvertFrom-Json -InputObject $taskJsonText -ErrorAction Stop
    if ($null -eq $taskJson -or $taskJson.PSObject.Properties.Match('appState').Count -lt 1) {
        return $null
    }

    return $taskJson.appState
}

function Test-AppStateNormalizationTaskUsesCanonicalManagerPayload {
    param([AllowNull()]$AppStateSpec)

    if ($null -eq $AppStateSpec) {
        return $false
    }

    if ($AppStateSpec.PSObject.Properties.Match('portableProfilePayload').Count -gt 0 -and [bool]$AppStateSpec.portableProfilePayload) {
        return $true
    }

    $relevantRules = New-Object 'System.Collections.Generic.List[object]'
    foreach ($collectionName in @('profileDirectories', 'profileFiles', 'userRegistryKeys')) {
        if ($AppStateSpec.PSObject.Properties.Match($collectionName).Count -lt 1) {
            continue
        }

        foreach ($entry in @($AppStateSpec.$collectionName)) {
            if ($null -ne $entry) {
                $relevantRules.Add($entry) | Out-Null
            }
        }
    }

    if ($relevantRules.Count -lt 1) {
        return $false
    }

    foreach ($rule in $relevantRules) {
        $targetProfiles = @()
        if ($rule -is [System.Collections.IDictionary]) {
            if ($rule.Contains('targetProfiles')) {
                $targetProfiles = @($rule['targetProfiles'])
            }
        }
        elseif ($rule.PSObject.Properties.Match('targetProfiles').Count -gt 0) {
            $targetProfiles = @($rule.targetProfiles)
        }

        foreach ($targetProfile in @($targetProfiles)) {
            $normalizedTarget = if ($null -eq $targetProfile) { '' } else { [string]$targetProfile.Trim() }
            if (-not [string]::IsNullOrWhiteSpace([string]$normalizedTarget)) {
                return $false
            }
        }
    }

    return $true
}

function Get-AppStateNormalizationSourceToken {
    param(
        [string]$SourcePath,
        [string]$CollectionName,
        [string]$Scope = ''
    )

    $normalizedSourcePath = Normalize-AppStateNormalizationManifestPath -Path $SourcePath
    if ([string]::IsNullOrWhiteSpace([string]$normalizedSourcePath)) {
        return ''
    }

    $pattern = ''
    switch ([string]$CollectionName) {
        'profileDirectories' { $pattern = '^payload\\profile-directories\\([^\\]+)\\' }
        'profileFiles' { $pattern = '^payload\\profile-files\\([^\\]+)\\' }
        'registryImports' {
            if ([string]::Equals([string]$Scope, 'user', [System.StringComparison]::OrdinalIgnoreCase)) {
                $pattern = '^payload\\registry\\user\\([^\\]+)\\'
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$pattern)) {
        return ''
    }

    $match = [regex]::Match($normalizedSourcePath, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        return ''
    }

    return [string]$match.Groups[1].Value.Trim().ToLowerInvariant()
}

function Get-AppStateNormalizationCanonicalSourcePath {
    param(
        [string]$SourcePath,
        [string]$CollectionName,
        [string]$Scope = '',
        [string]$CanonicalToken = 'manager'
    )

    $normalizedSourcePath = Normalize-AppStateNormalizationManifestPath -Path $SourcePath
    if ([string]::IsNullOrWhiteSpace([string]$normalizedSourcePath)) {
        return ''
    }

    switch ([string]$CollectionName) {
        'profileDirectories' {
            return ([regex]::Replace($normalizedSourcePath, '^payload\\profile-directories\\[^\\]+\\', ('payload\profile-directories\' + [string]$CanonicalToken + '\'), [System.Text.RegularExpressions.RegexOptions]::IgnoreCase))
        }
        'profileFiles' {
            return ([regex]::Replace($normalizedSourcePath, '^payload\\profile-files\\[^\\]+\\', ('payload\profile-files\' + [string]$CanonicalToken + '\'), [System.Text.RegularExpressions.RegexOptions]::IgnoreCase))
        }
        'registryImports' {
            if ([string]::Equals([string]$Scope, 'user', [System.StringComparison]::OrdinalIgnoreCase)) {
                return ([regex]::Replace($normalizedSourcePath, '^payload\\registry\\user\\[^\\]+\\', ('payload\registry\user\' + [string]$CanonicalToken + '\'), [System.Text.RegularExpressions.RegexOptions]::IgnoreCase))
            }
        }
    }

    return $normalizedSourcePath
}

function Copy-AppStateNormalizationManifestEntry {
    param([AllowNull()]$Entry)

    $copy = [ordered]@{}
    if ($null -eq $Entry) {
        return $copy
    }

    foreach ($property in @($Entry.PSObject.Properties)) {
        if ($null -eq $property) {
            continue
        }

        $value = $property.Value
        if (($value -is [System.Collections.IEnumerable]) -and -not ($value -is [string])) {
            $copy[$property.Name] = @($value)
        }
        else {
            $copy[$property.Name] = $value
        }
    }

    return $copy
}

function Get-AppStateNormalizationForeignTokensFromManifest {
    param([AllowNull()]$Manifest)

    $tokens = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    if ($null -eq $Manifest) {
        return @()
    }

    foreach ($collectionName in @('profileDirectories', 'profileFiles', 'registryImports')) {
        foreach ($entry in @($Manifest.$collectionName)) {
            if ($null -eq $entry) {
                continue
            }

            $scope = ''
            if ($entry.PSObject.Properties.Match('scope').Count -gt 0) {
                $scope = [string]$entry.scope
            }

            $sourceToken = Get-AppStateNormalizationSourceToken -SourcePath ([string]$entry.sourcePath) -CollectionName $collectionName -Scope $scope
            if (-not (Test-AppStateNormalizationAllowedProfileToken -Token $sourceToken)) {
                [void]$tokens.Add($sourceToken)
            }

            if ($entry.PSObject.Properties.Match('targetProfiles').Count -gt 0) {
                foreach ($targetProfile in @($entry.targetProfiles)) {
                    $normalizedTarget = if ($null -eq $targetProfile) { '' } else { [string]$targetProfile.Trim().ToLowerInvariant() }
                    if ([string]::IsNullOrWhiteSpace([string]$normalizedTarget)) {
                        continue
                    }
                    if (-not (Test-AppStateNormalizationAllowedProfileToken -Token $normalizedTarget)) {
                        [void]$tokens.Add($normalizedTarget)
                    }
                }
            }
        }
    }

    return @($tokens | Sort-Object)
}

function Get-AppStateNormalizationEmbeddedUserTokensFromText {
    param([string]$Content)

    $tokens = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    if ([string]::IsNullOrWhiteSpace([string]$Content)) {
        return @()
    }

    foreach ($pattern in @(
        '(?i)C:\\Users\\([^\\]+)',
        '(?i)C:\\\\Users\\\\([^\\]+)'
    )) {
        foreach ($match in @([regex]::Matches($Content, $pattern))) {
            if ($null -eq $match -or -not $match.Success -or $match.Groups.Count -lt 2) {
                continue
            }

            $token = [string]$match.Groups[1].Value.Trim().ToLowerInvariant()
            if ([string]::IsNullOrWhiteSpace([string]$token) -or (Test-AppStateNormalizationAllowedProfileToken -Token $token)) {
                continue
            }

            [void]$tokens.Add($token)
        }
    }

    return @($tokens | Sort-Object)
}

function Get-AppStateNormalizationForeignTokensFromRegistryFiles {
    param([string]$ScratchRoot)

    $tokens = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $registryRoot = Join-Path $ScratchRoot 'payload\registry\user'
    if (-not (Test-Path -LiteralPath $registryRoot -PathType Container)) {
        return @()
    }

    foreach ($registryFile in @(
        Get-ChildItem -LiteralPath $registryRoot -Recurse -Filter *.reg -File -Force -ErrorAction SilentlyContinue |
            Sort-Object FullName
    )) {
        $content = [string](Get-Content -LiteralPath $registryFile.FullName -Raw -Encoding Unicode -ErrorAction SilentlyContinue)
        if ([string]::IsNullOrWhiteSpace([string]$content)) {
            $content = [string](Get-Content -LiteralPath $registryFile.FullName -Raw -ErrorAction SilentlyContinue)
        }
        foreach ($token in @(Get-AppStateNormalizationEmbeddedUserTokensFromText -Content $content)) {
            [void]$tokens.Add($token)
        }
    }

    return @($tokens | Sort-Object)
}

function Ensure-AppStateNormalizationDirectory {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace([string]$Path)) {
        return
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Get-AppStateNormalizationAbsolutePath {
    param(
        [string]$ScratchRoot,
        [string]$ManifestPath
    )

    return (Join-Path $ScratchRoot (Normalize-AppStateNormalizationManifestPath -Path $ManifestPath))
}

function Get-AppStateNormalizationTargetProfileKey {
    param(
        [AllowNull()]$Entry,
        [bool]$ClearTargetProfiles = $false
    )

    if ($ClearTargetProfiles -or $null -eq $Entry -or $Entry.PSObject.Properties.Match('targetProfiles').Count -lt 1) {
        return ''
    }

    $tokens = @(
        foreach ($targetProfile in @($Entry.targetProfiles)) {
            $normalizedTarget = if ($null -eq $targetProfile) { '' } else { [string]$targetProfile.Trim().ToLowerInvariant() }
            if (-not [string]::IsNullOrWhiteSpace([string]$normalizedTarget)) {
                $normalizedTarget
            }
        }
    ) | Sort-Object -Unique

    return (@($tokens) -join '|')
}

function Test-AppStateNormalizationHasForeignTargetProfiles {
    param([AllowNull()]$Entry)

    if ($null -eq $Entry -or $Entry.PSObject.Properties.Match('targetProfiles').Count -lt 1) {
        return $false
    }

    foreach ($targetProfile in @($Entry.targetProfiles)) {
        $normalizedTarget = if ($null -eq $targetProfile) { '' } else { [string]$targetProfile.Trim().ToLowerInvariant() }
        if ([string]::IsNullOrWhiteSpace([string]$normalizedTarget)) {
            continue
        }
        if (-not (Test-AppStateNormalizationAllowedProfileToken -Token $normalizedTarget)) {
            return $true
        }
    }

    return $false
}

function Compare-AppStateNormalizationCandidatePreference {
    param(
        [AllowNull()]$Left,
        [AllowNull()]$Right
    )

    if ($null -eq $Left) { return 1 }
    if ($null -eq $Right) { return -1 }

    $leftTime = if ($Left.LastWriteTimeUtc -is [datetime]) { [datetime]$Left.LastWriteTimeUtc } else { [datetime]::MinValue }
    $rightTime = if ($Right.LastWriteTimeUtc -is [datetime]) { [datetime]$Right.LastWriteTimeUtc } else { [datetime]::MinValue }
    if ($leftTime -gt $rightTime) { return -1 }
    if ($leftTime -lt $rightTime) { return 1 }

    $leftLength = if ($null -eq $Left.Length) { 0L } else { [long]$Left.Length }
    $rightLength = if ($null -eq $Right.Length) { 0L } else { [long]$Right.Length }
    if ($leftLength -gt $rightLength) { return -1 }
    if ($leftLength -lt $rightLength) { return 1 }

    $leftToken = if ($null -eq $Left.SourceToken) { '' } else { [string]$Left.SourceToken.Trim().ToLowerInvariant() }
    $rightToken = if ($null -eq $Right.SourceToken) { '' } else { [string]$Right.SourceToken.Trim().ToLowerInvariant() }
    return [string]::CompareOrdinal($leftToken, $rightToken)
}

function Select-AppStateNormalizationPreferredCandidate {
    param([object[]]$Candidates = @())

    $preferred = $null
    foreach ($candidate in @($Candidates)) {
        if ($null -eq $preferred) {
            $preferred = $candidate
            continue
        }

        if ((Compare-AppStateNormalizationCandidatePreference -Left $candidate -Right $preferred) -lt 0) {
            $preferred = $candidate
        }
    }

    return $preferred
}

function Merge-AppStateNormalizationDirectoryCandidates {
    param(
        [string]$ScratchRoot,
        [string]$CanonicalSourcePath,
        [object[]]$Candidates = @()
    )

    $mergeRoot = Join-Path $ScratchRoot ('__app-state-normalize-' + [guid]::NewGuid().ToString('N'))
    $mergeDirectory = Join-Path $mergeRoot 'merge'
    Ensure-AppStateNormalizationDirectory -Path $mergeDirectory

    $directoryRelatives = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    [void]$directoryRelatives.Add('')
    $fileCandidatesByRelativePath = @{}
    $candidateAbsolutePaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    try {
        foreach ($candidate in @($Candidates)) {
            if ($null -eq $candidate) {
                continue
            }

            $candidateAbsolutePath = [string]$candidate.OriginalAbsolutePath
            if ([string]::IsNullOrWhiteSpace([string]$candidateAbsolutePath) -or -not (Test-Path -LiteralPath $candidateAbsolutePath -PathType Container)) {
                continue
            }

            [void]$candidateAbsolutePaths.Add($candidateAbsolutePath)

            foreach ($directory in @(
                Get-ChildItem -LiteralPath $candidateAbsolutePath -Recurse -Directory -Force -ErrorAction SilentlyContinue |
                    Sort-Object FullName
            )) {
                $relativeDirectory = [string]$directory.FullName.Substring($candidateAbsolutePath.TrimEnd('\').Length).TrimStart('\')
                [void]$directoryRelatives.Add($relativeDirectory)
            }

            foreach ($file in @(
                Get-ChildItem -LiteralPath $candidateAbsolutePath -Recurse -File -Force -ErrorAction SilentlyContinue |
                    Sort-Object FullName
            )) {
                $relativeFile = [string]$file.FullName.Substring($candidateAbsolutePath.TrimEnd('\').Length).TrimStart('\')
                if (-not $fileCandidatesByRelativePath.ContainsKey($relativeFile)) {
                    $fileCandidatesByRelativePath[$relativeFile] = New-Object 'System.Collections.Generic.List[object]'
                }

                $fileCandidatesByRelativePath[$relativeFile].Add([pscustomobject]@{
                    FullName = [string]$file.FullName
                    RelativePath = [string]$relativeFile
                    Length = [long]$file.Length
                    LastWriteTimeUtc = [datetime]$file.LastWriteTimeUtc
                    SourceToken = [string]$candidate.SourceToken
                }) | Out-Null
            }
        }

        foreach ($relativeDirectory in @($directoryRelatives | Sort-Object)) {
            $targetDirectory = if ([string]::IsNullOrWhiteSpace([string]$relativeDirectory)) {
                $mergeDirectory
            }
            else {
                Join-Path $mergeDirectory $relativeDirectory
            }

            Ensure-AppStateNormalizationDirectory -Path $targetDirectory
        }

        foreach ($relativeFile in @($fileCandidatesByRelativePath.Keys | Sort-Object)) {
            $winner = Select-AppStateNormalizationPreferredCandidate -Candidates ([object[]]$fileCandidatesByRelativePath[$relativeFile])
            if ($null -eq $winner) {
                continue
            }

            $targetFilePath = Join-Path $mergeDirectory $relativeFile
            Ensure-AppStateNormalizationDirectory -Path (Split-Path -Path $targetFilePath -Parent)
            Copy-Item -LiteralPath ([string]$winner.FullName) -Destination $targetFilePath -Force -ErrorAction Stop
            (Get-Item -LiteralPath $targetFilePath).LastWriteTimeUtc = [datetime]$winner.LastWriteTimeUtc
        }

        foreach ($candidateAbsolutePath in @($candidateAbsolutePaths | Sort-Object { $_.Length } -Descending)) {
            if (Test-Path -LiteralPath $candidateAbsolutePath) {
                Remove-Item -LiteralPath $candidateAbsolutePath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        $canonicalAbsolutePath = Get-AppStateNormalizationAbsolutePath -ScratchRoot $ScratchRoot -ManifestPath $CanonicalSourcePath
        Ensure-AppStateNormalizationDirectory -Path (Split-Path -Path $canonicalAbsolutePath -Parent)
        if (Test-Path -LiteralPath $canonicalAbsolutePath) {
            Remove-Item -LiteralPath $canonicalAbsolutePath -Recurse -Force -ErrorAction SilentlyContinue
        }

        Move-Item -LiteralPath $mergeDirectory -Destination $canonicalAbsolutePath -Force -ErrorAction Stop
        return $canonicalAbsolutePath
    }
    finally {
        if (Test-Path -LiteralPath $mergeRoot) {
            Remove-Item -LiteralPath $mergeRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Normalize-AppStateNormalizationRegistryContent {
    param(
        [string]$Path,
        [string[]]$ForeignTokens = @()
    )

    if ([string]::IsNullOrWhiteSpace([string]$Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }

    $content = [string](Get-Content -LiteralPath $Path -Raw -Encoding Unicode -ErrorAction SilentlyContinue)
    if ([string]::IsNullOrWhiteSpace([string]$content)) {
        $content = [string](Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue)
    }
    if ([string]::IsNullOrWhiteSpace([string]$content)) {
        return
    }

    $normalizedContent = [string]$content
    foreach ($token in @($ForeignTokens | Sort-Object -Unique)) {
        $normalizedToken = if ($null -eq $token) { '' } else { [string]$token.Trim().ToLowerInvariant() }
        if ([string]::IsNullOrWhiteSpace([string]$normalizedToken) -or (Test-AppStateNormalizationAllowedProfileToken -Token $normalizedToken)) {
            continue
        }

        $normalizedContent = [regex]::Replace($normalizedContent, ('(?i)C:\\\\Users\\\\' + [regex]::Escape($normalizedToken) + '(?=\\\\)'), 'C:\\Users\\manager')
        $normalizedContent = [regex]::Replace($normalizedContent, ('(?i)C:\\Users\\' + [regex]::Escape($normalizedToken) + '(?=\\)'), 'C:\Users\manager')
    }

    if (-not [string]::Equals($normalizedContent, $content, [System.StringComparison]::Ordinal)) {
        Set-Content -LiteralPath $Path -Value $normalizedContent -Encoding Unicode
    }
}

function Normalize-AppStateZipPayload {
    param([string]$ZipPath)

    Initialize-AppStateNormalizationZipSupport

    $taskAppStateSpec = Get-AppStateNormalizationTaskAppStateSpec -ZipPath $ZipPath
    $taskUsesCanonicalManagerPayload = Test-AppStateNormalizationTaskUsesCanonicalManagerPayload -AppStateSpec $taskAppStateSpec
    $scratchRoot = Join-Path ([System.Environment]::GetEnvironmentVariable('SystemDrive')) ('clagnosn-' + [guid]::NewGuid().ToString('N'))
    $expectedTaskName = [System.IO.Path]::GetFileName((Split-Path -Path (Split-Path -Path $ZipPath -Parent) -Parent))
    $result = [ordered]@{
        ZipPath = [string]$ZipPath
        TaskName = [string]$expectedTaskName
        Changed = $false
        Status = 'unchanged'
        ForeignUsers = @()
    }

    try {
        if (Test-Path -LiteralPath $scratchRoot) {
            Remove-Item -LiteralPath $scratchRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        Ensure-AppStateNormalizationDirectory -Path $scratchRoot
        [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $scratchRoot)
        $manifestPath = Join-Path $scratchRoot 'app-state.manifest.json'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            $result.Status = 'missing-manifest'
            return [pscustomobject]$result
        }

        $manifest = ConvertFrom-Json -InputObject ([string](Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop)) -ErrorAction Stop
        $manifestTaskName = if ($manifest.PSObject.Properties.Match('taskName').Count -gt 0) { [string]$manifest.taskName } else { '' }
        $taskNameChanged = (-not [string]::Equals([string]$manifestTaskName, [string]$expectedTaskName, [System.StringComparison]::OrdinalIgnoreCase))

        $foreignUserSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($token in @(Get-AppStateNormalizationForeignTokensFromManifest -Manifest $manifest)) {
            [void]$foreignUserSet.Add([string]$token)
        }
        foreach ($token in @(Get-AppStateNormalizationForeignTokensFromRegistryFiles -ScratchRoot $scratchRoot)) {
            [void]$foreignUserSet.Add([string]$token)
        }
        $foreignTokens = @($foreignUserSet | Sort-Object)
        $result.ForeignUsers = @($foreignTokens)
        if (@($foreignTokens).Count -lt 1 -and -not $taskNameChanged) {
            return [pscustomobject]$result
        }

        if (@($foreignTokens).Count -gt 0 -and -not $taskUsesCanonicalManagerPayload) {
            throw ("App-state zip '{0}' contains foreign profile tokens ({1}) but the owning task contract is not portable or profile-generic." -f [string]$ZipPath, ((@($foreignTokens) -join ', ')))
        }

        $profileDirectoryGroups = @{}
        $profileFileGroups = @{}
        $registryGroups = @{}
        $normalizedProfileDirectories = New-Object 'System.Collections.Generic.List[object]'
        $normalizedProfileFiles = New-Object 'System.Collections.Generic.List[object]'
        $normalizedRegistryImports = New-Object 'System.Collections.Generic.List[object]'
        $orderIndex = 0

        foreach ($entry in @($manifest.profileDirectories)) {
            if ($null -eq $entry) {
                continue
            }

            $orderIndex++
            $sourceToken = Get-AppStateNormalizationSourceToken -SourcePath ([string]$entry.sourcePath) -CollectionName 'profileDirectories'
            $hasForeignSource = (-not (Test-AppStateNormalizationAllowedProfileToken -Token $sourceToken))
            $hasForeignTargets = Test-AppStateNormalizationHasForeignTargetProfiles -Entry $entry
            $clearTargetProfiles = ($hasForeignSource -or $hasForeignTargets)
            $normalizedSourcePath = if ($hasForeignSource) {
                Get-AppStateNormalizationCanonicalSourcePath -SourcePath ([string]$entry.sourcePath) -CollectionName 'profileDirectories'
            }
            else {
                Normalize-AppStateNormalizationManifestPath -Path ([string]$entry.sourcePath)
            }

            $groupKey = ('{0}|{1}' -f ([string]$entry.relativeDestinationPath).ToLowerInvariant(), (Get-AppStateNormalizationTargetProfileKey -Entry $entry -ClearTargetProfiles $clearTargetProfiles))
            if (-not $profileDirectoryGroups.ContainsKey($groupKey)) {
                $profileDirectoryGroups[$groupKey] = New-Object 'System.Collections.Generic.List[object]'
            }

            $profileDirectoryGroups[$groupKey].Add([pscustomobject]@{
                OrderIndex = [int]$orderIndex
                Entry = $entry
                SourceToken = [string]$sourceToken
                NormalizedSourcePath = [string]$normalizedSourcePath
                OriginalAbsolutePath = Get-AppStateNormalizationAbsolutePath -ScratchRoot $scratchRoot -ManifestPath ([string]$entry.sourcePath)
                ClearTargetProfiles = [bool]$clearTargetProfiles
            }) | Out-Null
        }

        foreach ($groupKey in @($profileDirectoryGroups.Keys)) {
            $groupEntries = [object[]]($profileDirectoryGroups[$groupKey] | Sort-Object OrderIndex)
            $canonicalSourcePath = [string]$groupEntries[0].NormalizedSourcePath
            if (@($groupEntries).Count -gt 1) {
                Merge-AppStateNormalizationDirectoryCandidates -ScratchRoot $scratchRoot -CanonicalSourcePath $canonicalSourcePath -Candidates $groupEntries | Out-Null
            }
            else {
                $entryPath = [string]$groupEntries[0].OriginalAbsolutePath
                $canonicalAbsolutePath = Get-AppStateNormalizationAbsolutePath -ScratchRoot $scratchRoot -ManifestPath $canonicalSourcePath
                if (-not [string]::Equals($entryPath, $canonicalAbsolutePath, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $entryPath -PathType Container)) {
                    Ensure-AppStateNormalizationDirectory -Path (Split-Path -Path $canonicalAbsolutePath -Parent)
                    if (Test-Path -LiteralPath $canonicalAbsolutePath) {
                        Remove-Item -LiteralPath $canonicalAbsolutePath -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    Move-Item -LiteralPath $entryPath -Destination $canonicalAbsolutePath -Force -ErrorAction Stop
                }
            }

            $manifestEntry = Copy-AppStateNormalizationManifestEntry -Entry $groupEntries[0].Entry
            $manifestEntry.sourcePath = [string]$canonicalSourcePath
            if ($groupEntries[0].ClearTargetProfiles -or $manifestEntry.Contains('targetProfiles')) {
                $manifestEntry.targetProfiles = @()
            }
            $normalizedProfileDirectories.Add([pscustomobject]$manifestEntry) | Out-Null
        }

        foreach ($entry in @($manifest.profileFiles)) {
            if ($null -eq $entry) {
                continue
            }

            $orderIndex++
            $sourceToken = Get-AppStateNormalizationSourceToken -SourcePath ([string]$entry.sourcePath) -CollectionName 'profileFiles'
            $hasForeignSource = (-not (Test-AppStateNormalizationAllowedProfileToken -Token $sourceToken))
            $hasForeignTargets = Test-AppStateNormalizationHasForeignTargetProfiles -Entry $entry
            $clearTargetProfiles = ($hasForeignSource -or $hasForeignTargets)
            $normalizedSourcePath = if ($hasForeignSource) {
                Get-AppStateNormalizationCanonicalSourcePath -SourcePath ([string]$entry.sourcePath) -CollectionName 'profileFiles'
            }
            else {
                Normalize-AppStateNormalizationManifestPath -Path ([string]$entry.sourcePath)
            }

            $groupKey = ('{0}|{1}' -f ([string]$entry.relativeDestinationPath).ToLowerInvariant(), (Get-AppStateNormalizationTargetProfileKey -Entry $entry -ClearTargetProfiles $clearTargetProfiles))
            if (-not $profileFileGroups.ContainsKey($groupKey)) {
                $profileFileGroups[$groupKey] = New-Object 'System.Collections.Generic.List[object]'
            }

            $absolutePath = Get-AppStateNormalizationAbsolutePath -ScratchRoot $scratchRoot -ManifestPath ([string]$entry.sourcePath)
            $item = $null
            if (Test-Path -LiteralPath $absolutePath -PathType Leaf) {
                $item = Get-Item -LiteralPath $absolutePath -Force
            }

            $profileFileGroups[$groupKey].Add([pscustomobject]@{
                OrderIndex = [int]$orderIndex
                Entry = $entry
                SourceToken = [string]$sourceToken
                NormalizedSourcePath = [string]$normalizedSourcePath
                OriginalAbsolutePath = [string]$absolutePath
                ClearTargetProfiles = [bool]$clearTargetProfiles
                Length = if ($null -ne $item) { [long]$item.Length } else { 0L }
                LastWriteTimeUtc = if ($null -ne $item) { [datetime]$item.LastWriteTimeUtc } else { [datetime]::MinValue }
            }) | Out-Null
        }

        foreach ($groupKey in @($profileFileGroups.Keys)) {
            $groupEntries = [object[]]$profileFileGroups[$groupKey]
            $winner = Select-AppStateNormalizationPreferredCandidate -Candidates $groupEntries
            if ($null -eq $winner) {
                continue
            }

            $canonicalSourcePath = [string]$winner.NormalizedSourcePath
            $canonicalAbsolutePath = Get-AppStateNormalizationAbsolutePath -ScratchRoot $scratchRoot -ManifestPath $canonicalSourcePath
            Ensure-AppStateNormalizationDirectory -Path (Split-Path -Path $canonicalAbsolutePath -Parent)
            if (-not [string]::Equals([string]$winner.OriginalAbsolutePath, [string]$canonicalAbsolutePath, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $winner.OriginalAbsolutePath -PathType Leaf)) {
                Copy-Item -LiteralPath $winner.OriginalAbsolutePath -Destination $canonicalAbsolutePath -Force -ErrorAction Stop
                (Get-Item -LiteralPath $canonicalAbsolutePath).LastWriteTimeUtc = [datetime]$winner.LastWriteTimeUtc
            }

            foreach ($groupEntry in @($groupEntries)) {
                $pathToRemove = [string]$groupEntry.OriginalAbsolutePath
                if ([string]::Equals($pathToRemove, $canonicalAbsolutePath, [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }
                if (Test-Path -LiteralPath $pathToRemove -PathType Leaf) {
                    Remove-Item -LiteralPath $pathToRemove -Force -ErrorAction SilentlyContinue
                }
            }

            $manifestEntry = Copy-AppStateNormalizationManifestEntry -Entry $winner.Entry
            $manifestEntry.sourcePath = [string]$canonicalSourcePath
            if ($winner.ClearTargetProfiles -or $manifestEntry.Contains('targetProfiles')) {
                $manifestEntry.targetProfiles = @()
            }
            $normalizedProfileFiles.Add([pscustomobject]$manifestEntry) | Out-Null
        }

        foreach ($entry in @($manifest.registryImports)) {
            if ($null -eq $entry) {
                continue
            }

            $scope = if ($entry.PSObject.Properties.Match('scope').Count -gt 0) { [string]$entry.scope } else { '' }
            if (-not [string]::Equals([string]$scope, 'user', [System.StringComparison]::OrdinalIgnoreCase)) {
                $normalizedRegistryImports.Add([pscustomobject](Copy-AppStateNormalizationManifestEntry -Entry $entry)) | Out-Null
                continue
            }

            $orderIndex++
            $sourceToken = Get-AppStateNormalizationSourceToken -SourcePath ([string]$entry.sourcePath) -CollectionName 'registryImports' -Scope $scope
            $hasForeignSource = (-not (Test-AppStateNormalizationAllowedProfileToken -Token $sourceToken))
            $hasForeignTargets = Test-AppStateNormalizationHasForeignTargetProfiles -Entry $entry
            $clearTargetProfiles = ($hasForeignSource -or $hasForeignTargets)
            $normalizedSourcePath = if ($hasForeignSource) {
                Get-AppStateNormalizationCanonicalSourcePath -SourcePath ([string]$entry.sourcePath) -CollectionName 'registryImports' -Scope $scope
            }
            else {
                Normalize-AppStateNormalizationManifestPath -Path ([string]$entry.sourcePath)
            }

            $groupKey = ('{0}|{1}' -f ([string]$entry.registryPath).ToLowerInvariant(), (Get-AppStateNormalizationTargetProfileKey -Entry $entry -ClearTargetProfiles $clearTargetProfiles))
            if (-not $registryGroups.ContainsKey($groupKey)) {
                $registryGroups[$groupKey] = New-Object 'System.Collections.Generic.List[object]'
            }

            $absolutePath = Get-AppStateNormalizationAbsolutePath -ScratchRoot $scratchRoot -ManifestPath ([string]$entry.sourcePath)
            $item = $null
            if (Test-Path -LiteralPath $absolutePath -PathType Leaf) {
                $item = Get-Item -LiteralPath $absolutePath -Force
            }

            $registryGroups[$groupKey].Add([pscustomobject]@{
                OrderIndex = [int]$orderIndex
                Entry = $entry
                SourceToken = [string]$sourceToken
                NormalizedSourcePath = [string]$normalizedSourcePath
                OriginalAbsolutePath = [string]$absolutePath
                ClearTargetProfiles = [bool]$clearTargetProfiles
                Length = if ($null -ne $item) { [long]$item.Length } else { 0L }
                LastWriteTimeUtc = if ($null -ne $item) { [datetime]$item.LastWriteTimeUtc } else { [datetime]::MinValue }
            }) | Out-Null
        }

        foreach ($groupKey in @($registryGroups.Keys)) {
            $groupEntries = [object[]]$registryGroups[$groupKey]
            $winner = Select-AppStateNormalizationPreferredCandidate -Candidates $groupEntries
            if ($null -eq $winner) {
                continue
            }

            $canonicalSourcePath = [string]$winner.NormalizedSourcePath
            $canonicalAbsolutePath = Get-AppStateNormalizationAbsolutePath -ScratchRoot $scratchRoot -ManifestPath $canonicalSourcePath
            Ensure-AppStateNormalizationDirectory -Path (Split-Path -Path $canonicalAbsolutePath -Parent)
            if (-not [string]::Equals([string]$winner.OriginalAbsolutePath, [string]$canonicalAbsolutePath, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $winner.OriginalAbsolutePath -PathType Leaf)) {
                Copy-Item -LiteralPath $winner.OriginalAbsolutePath -Destination $canonicalAbsolutePath -Force -ErrorAction Stop
                (Get-Item -LiteralPath $canonicalAbsolutePath).LastWriteTimeUtc = [datetime]$winner.LastWriteTimeUtc
            }

            Normalize-AppStateNormalizationRegistryContent -Path $canonicalAbsolutePath -ForeignTokens @($foreignTokens)

            foreach ($groupEntry in @($groupEntries)) {
                $pathToRemove = [string]$groupEntry.OriginalAbsolutePath
                if ([string]::Equals($pathToRemove, $canonicalAbsolutePath, [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }
                if (Test-Path -LiteralPath $pathToRemove -PathType Leaf) {
                    Remove-Item -LiteralPath $pathToRemove -Force -ErrorAction SilentlyContinue
                }
            }

            $manifestEntry = Copy-AppStateNormalizationManifestEntry -Entry $winner.Entry
            $manifestEntry.sourcePath = [string]$canonicalSourcePath
            if ($winner.ClearTargetProfiles -or $manifestEntry.Contains('targetProfiles')) {
                $manifestEntry.targetProfiles = @()
            }
            $normalizedRegistryImports.Add([pscustomobject]$manifestEntry) | Out-Null
        }

        foreach ($foreignToken in @($foreignTokens)) {
            foreach ($relativeRoot in @('payload\profile-directories', 'payload\profile-files', 'payload\registry\user')) {
                $foreignRoot = Join-Path (Join-Path $scratchRoot $relativeRoot) $foreignToken
                if (Test-Path -LiteralPath $foreignRoot) {
                    Remove-Item -LiteralPath $foreignRoot -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }

        if (@($foreignTokens).Count -gt 0) {
            $manifest.profileDirectories = @($normalizedProfileDirectories.ToArray())
            $manifest.profileFiles = @($normalizedProfileFiles.ToArray())
            $manifest.registryImports = @($normalizedRegistryImports.ToArray())
        }
        if ($manifest.PSObject.Properties.Match('taskName').Count -lt 1) {
            $manifest | Add-Member -NotePropertyName taskName -NotePropertyValue ([string]$expectedTaskName)
        }
        else {
            $manifest.taskName = [string]$expectedTaskName
        }
        Set-Content -LiteralPath $manifestPath -Value ($manifest | ConvertTo-Json -Depth 16) -Encoding UTF8

        Remove-Item -LiteralPath $ZipPath -Force -ErrorAction Stop
        $archiveInputPaths = @(Get-ChildItem -LiteralPath $scratchRoot -Force -ErrorAction SilentlyContinue)
        if (@($archiveInputPaths).Count -gt 0) {
            [System.IO.Compression.ZipFile]::CreateFromDirectory($scratchRoot, $ZipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)
        }

        $result.Changed = $true
        $result.Status = 'normalized'
        return [pscustomobject]$result
    }
    finally {
        Remove-Item -LiteralPath $scratchRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$reports = @(
    foreach ($zipPath in @(Get-AppStateNormalizationZipPaths -RepositoryRoot $RepoRoot)) {
        Normalize-AppStateZipPayload -ZipPath $zipPath
    }
)

foreach ($report in @($reports | Where-Object { $_ -ne $null })) {
    $taskName = if ([string]::IsNullOrWhiteSpace([string]$report.TaskName)) { [System.IO.Path]::GetFileName((Split-Path -Path (Split-Path -Path [string]$report.ZipPath -Parent) -Parent)) } else { [string]$report.TaskName }
    Write-Host ("[{0}] {1}" -f [string]$report.Status, [string]$taskName)
    if (@($report.ForeignUsers).Count -gt 0) {
        Write-Host ("  foreign-users: {0}" -f ((@($report.ForeignUsers) | Sort-Object) -join ', '))
    }
}

if ($PassThru) {
    $reports
}
