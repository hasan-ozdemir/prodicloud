param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
    [int]$TopEntries = 5,
    [double]$MinimumReportSizeMb = 5,
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Initialize-AppStateAuditZipSupport {
    if (-not ([System.Management.Automation.PSTypeName]'System.IO.Compression.ZipArchive').Type) {
        Add-Type -AssemblyName 'System.IO.Compression.FileSystem' -ErrorAction SilentlyContinue
        Add-Type -AssemblyName 'System.IO.Compression' -ErrorAction SilentlyContinue
    }
}

function Get-AppStateAuditAllowedProfileTokens {
    return @('manager', 'assistant', 'default', 'public')
}

function Test-AppStateAuditAllowedProfileToken {
    param([string]$Token)

    $normalizedToken = if ($null -eq $Token) { '' } else { [string]$Token.Trim().ToLowerInvariant() }
    if ([string]::IsNullOrWhiteSpace([string]$normalizedToken)) {
        return $true
    }

    return (@(Get-AppStateAuditAllowedProfileTokens) -contains $normalizedToken)
}

function Get-AppStateAuditSourceToken {
    param(
        [string]$SourcePath,
        [string]$CollectionName,
        [string]$Scope = ''
    )

    $normalizedSourcePath = if ([string]::IsNullOrWhiteSpace([string]$SourcePath)) { '' } else { ([string]$SourcePath).Replace('/', '\').TrimStart('\') }
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

function Get-AppStateAuditEmbeddedUserTokensFromRegistryText {
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
            if ([string]::IsNullOrWhiteSpace([string]$token) -or (Test-AppStateAuditAllowedProfileToken -Token $token)) {
                continue
            }

            [void]$tokens.Add($token)
        }
    }

    return @($tokens | Sort-Object)
}

function Get-AppStateAuditZipPaths {
    param([string]$RepositoryRoot)

    $roots = @(
        'vm-init\windows',
        'vm-update\windows',
        'vm-init\linux',
        'vm-update\linux'
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
                $zipPath.FullName
            }
        }
    }
}

function Convert-AppStateAuditPathToStageLabel {
    param(
        [string]$RepositoryRoot,
        [string]$ZipPath
    )

    $relative = [string]$ZipPath.Substring($RepositoryRoot.TrimEnd('\').Length).TrimStart('\')
    $parts = @($relative -split '[\\/]')
    if ($parts.Count -lt 4) {
        return ''
    }

    return ('{0}/{1}' -f [string]$parts[0], [string]$parts[1])
}

function Get-AppStateAuditReport {
    param(
        [string]$RepositoryRoot,
        [string]$ZipPath,
        [int]$TopCount
    )

    Initialize-AppStateAuditZipSupport

    $archive = $null
    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        $manifest = $null
        $manifestEntry = @($archive.Entries | Where-Object { [string]::Equals([string]$_.FullName, 'app-state.manifest.json', [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
        if ($null -ne $manifestEntry) {
            $reader = New-Object System.IO.StreamReader($manifestEntry.Open())
            try {
                $manifestText = [string]$reader.ReadToEnd()
            }
            finally {
                $reader.Dispose()
            }

            if (-not [string]::IsNullOrWhiteSpace([string]$manifestText)) {
                $manifest = ConvertFrom-Json -InputObject $manifestText -ErrorAction SilentlyContinue
            }
        }

        $taskName = ''
        if ($null -ne $manifest -and $manifest.PSObject.Properties.Match('taskName').Count -gt 0) {
            $taskName = [string]$manifest.taskName
        }
        if ([string]::IsNullOrWhiteSpace([string]$taskName)) {
            $pluginRoot = [string](Split-Path -Path $ZipPath -Parent)
            $taskName = [System.IO.Path]::GetFileName((Split-Path -Path $pluginRoot -Parent))
        }

        $foreignTargets = New-Object 'System.Collections.Generic.List[string]'
        $foreignSourceUsers = New-Object 'System.Collections.Generic.List[string]'
        $foreignEmbeddedUsers = New-Object 'System.Collections.Generic.List[string]'
        foreach ($collectionName in @('profileDirectories', 'profileFiles', 'registryImports')) {
            foreach ($entry in @($manifest.$collectionName)) {
                if ($null -eq $entry) {
                    continue
                }

                $scope = ''
                if ($entry.PSObject.Properties.Match('scope').Count -gt 0) {
                    $scope = [string]$entry.scope
                }

                $sourceToken = Get-AppStateAuditSourceToken -SourcePath ([string]$entry.sourcePath) -CollectionName $collectionName -Scope $scope
                if (-not (Test-AppStateAuditAllowedProfileToken -Token $sourceToken)) {
                    if ($foreignSourceUsers -notcontains $sourceToken) {
                        $foreignSourceUsers.Add($sourceToken) | Out-Null
                    }
                }

                if ($entry.PSObject.Properties.Match('targetProfiles').Count -gt 0) {
                    foreach ($targetProfile in @($entry.targetProfiles)) {
                        $normalized = if ($null -eq $targetProfile) { '' } else { [string]$targetProfile }
                        if ([string]::IsNullOrWhiteSpace([string]$normalized)) {
                            continue
                        }
                        $normalized = $normalized.Trim().ToLowerInvariant()
                        if (Test-AppStateAuditAllowedProfileToken -Token $normalized) {
                            continue
                        }
                        if ($foreignTargets -notcontains $normalized) {
                            $foreignTargets.Add($normalized) | Out-Null
                        }
                    }
                }
            }
        }

        foreach ($registryEntry in @(
            $archive.Entries |
                Where-Object { ([string]$_.FullName -match '^payload/registry/user/.+\.reg$') -or ([string]$_.FullName -match '^payload\\registry\\user\\.+\.reg$') }
        )) {
            $reader = New-Object System.IO.StreamReader($registryEntry.Open())
            try {
                $registryText = [string]$reader.ReadToEnd()
            }
            finally {
                $reader.Dispose()
            }

            foreach ($embeddedToken in @(Get-AppStateAuditEmbeddedUserTokensFromRegistryText -Content $registryText)) {
                if ($foreignEmbeddedUsers -notcontains $embeddedToken) {
                    $foreignEmbeddedUsers.Add($embeddedToken) | Out-Null
                }
            }
        }

        $foreignUsers = New-Object 'System.Collections.Generic.List[string]'
        foreach ($token in @($foreignTargets) + @($foreignSourceUsers) + @($foreignEmbeddedUsers)) {
            $normalizedToken = if ($null -eq $token) { '' } else { [string]$token.Trim().ToLowerInvariant() }
            if ([string]::IsNullOrWhiteSpace([string]$normalizedToken)) {
                continue
            }
            if ($foreignUsers -notcontains $normalizedToken) {
                $foreignUsers.Add($normalizedToken) | Out-Null
            }
        }

        $largestEntries = @(
            $archive.Entries |
                Sort-Object Length -Descending |
                Select-Object -First $TopCount |
                ForEach-Object {
                    [pscustomobject]@{
                        Path = [string]$_.FullName
                        SizeMb = [math]::Round(([double]$_.Length / 1MB), 2)
                    }
                }
        )

        return [pscustomobject]@{
            TaskName = [string]$taskName
            Stage = Convert-AppStateAuditPathToStageLabel -RepositoryRoot $RepositoryRoot -ZipPath $ZipPath
            ZipPath = [string]$ZipPath
            SizeMb = [math]::Round(((Get-Item -LiteralPath $ZipPath).Length / 1MB), 2)
            ForeignTargets = @($foreignTargets.ToArray())
            ForeignSourceUsers = @($foreignSourceUsers.ToArray())
            ForeignEmbeddedUsers = @($foreignEmbeddedUsers.ToArray())
            ForeignUsers = @($foreignUsers.ToArray())
            LargestEntries = @($largestEntries)
        }
    }
    finally {
        if ($null -ne $archive) {
            $archive.Dispose()
        }
    }
}

$zipPaths = @(Get-AppStateAuditZipPaths -RepositoryRoot $RepoRoot)
if (@($zipPaths).Count -lt 1) {
    Write-Host 'No app-state zip payloads were found.'
    return
}

$reports = @(
    foreach ($zipPath in @($zipPaths)) {
        Get-AppStateAuditReport -RepositoryRoot $RepoRoot -ZipPath $zipPath -TopCount $TopEntries
    }
) | Sort-Object SizeMb -Descending

foreach ($report in @($reports)) {
    Write-Host ("[{0}] {1} => {2} MB" -f [string]$report.Stage, [string]$report.TaskName, [string]$report.SizeMb)
    if (@($report.ForeignTargets).Count -gt 0) {
        Write-Host ("  foreign-targets: {0}" -f ((@($report.ForeignTargets) | Sort-Object) -join ', '))
    }
    if (@($report.ForeignSourceUsers).Count -gt 0) {
        Write-Host ("  foreign-source-users: {0}" -f ((@($report.ForeignSourceUsers) | Sort-Object) -join ', '))
    }
    if (@($report.ForeignEmbeddedUsers).Count -gt 0) {
        Write-Host ("  foreign-embedded-users: {0}" -f ((@($report.ForeignEmbeddedUsers) | Sort-Object) -join ', '))
    }

    if ([double]$report.SizeMb -ge [double]$MinimumReportSizeMb) {
        foreach ($entry in @($report.LargestEntries)) {
            Write-Host ("  top-entry: {0} => {1} MB" -f [string]$entry.Path, [string]$entry.SizeMb)
        }
    }
}

if ($PassThru) {
    $reports
}
