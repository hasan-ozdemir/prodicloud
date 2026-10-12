# Run-command task block replacement helpers.

function Resolve-ClagnosTaskRepoRootFromPath {
    param([string]$StartPath)

    if ([string]::IsNullOrWhiteSpace([string]$StartPath)) {
        return ''
    }

    $cursor = [string]$StartPath
    if (Test-Path -LiteralPath $cursor -PathType Leaf) {
        $cursor = [string](Split-Path -Path $cursor -Parent)
    }

    while (-not [string]::IsNullOrWhiteSpace([string]$cursor)) {
        if (Test-Path -LiteralPath (Join-Path $cursor 'clagnos.ps1')) {
            return [string]$cursor
        }

        $parent = [string](Split-Path -Path $cursor -Parent)
        if ([string]::IsNullOrWhiteSpace([string]$parent) -or [string]::Equals([string]$parent, [string]$cursor, [System.StringComparison]::OrdinalIgnoreCase)) {
            break
        }

        $cursor = $parent
    }

    return ''
}

# Handles Apply-ClagnosTaskBlockReplacements.
function Apply-ClagnosTaskBlockReplacements {
    param(
        [object[]]$TaskBlocks,
        [hashtable]$Replacements,
        [hashtable]$Context
    )

    if (-not $TaskBlocks) {
        return @()
    }

    $resolvedBlocks = @()
    foreach ($taskBlock in $TaskBlocks) {
        $taskName = [string]$taskBlock.Name
        $taskScript = [string]$taskBlock.Script
        $relativePath = ''
        $directoryPath = ''
        $taskRootPath = ''
        $taskMetadataPath = ''
        $stageRootDirectoryPath = ''
        if ($taskBlock.PSObject.Properties.Match('RelativePath').Count -gt 0) {
            $relativePath = [string]$taskBlock.RelativePath
        }
        if ($taskBlock.PSObject.Properties.Match('DirectoryPath').Count -gt 0) {
            $directoryPath = [string]$taskBlock.DirectoryPath
        }
        if ($taskBlock.PSObject.Properties.Match('TaskRootPath').Count -gt 0) {
            $taskRootPath = [string]$taskBlock.TaskRootPath
        }
        if ($taskBlock.PSObject.Properties.Match('TaskMetadataPath').Count -gt 0) {
            $taskMetadataPath = [string]$taskBlock.TaskMetadataPath
        }
        if ($taskBlock.PSObject.Properties.Match('StageRootDirectoryPath').Count -gt 0) {
            $stageRootDirectoryPath = [string]$taskBlock.StageRootDirectoryPath
        }
        $timeoutSeconds = 180
        if ($taskBlock.PSObject.Properties.Match('TimeoutSeconds').Count -gt 0) {
            $timeoutSeconds = Get-ClagnosTaskTimeoutSeconds -TaskBlock $taskBlock -DefaultTimeoutSeconds 180
        }
        $assetSpecs = @()
        if ($taskBlock.PSObject.Properties.Match('AssetSpecs').Count -gt 0 -and $null -ne $taskBlock.AssetSpecs) {
            $assetSpecs = @(ConvertTo-ObjectArrayCompat -InputObject $taskBlock.AssetSpecs)
        }

        $effectiveReplacements = @{}
        if ($Replacements) {
            foreach ($key in $Replacements.Keys) {
                $effectiveReplacements[[string]$key] = [string]$Replacements[$key]
            }
        }

        $taskOverrides = Get-ClagnosTaskBlockTokenOverrides -TaskBlock $taskBlock -Context $Context
        if ($taskOverrides) {
            foreach ($key in $taskOverrides.Keys) {
                $effectiveReplacements[[string]$key] = [string]$taskOverrides[$key]
            }
        }

        if ($effectiveReplacements.Count -gt 0) {
            foreach ($key in $effectiveReplacements.Keys) {
                $token = "__{0}__" -f [string]$key
                $value = [string]$effectiveReplacements[$key]
                $taskScript = $taskScript.Replace($token, $value)
            }
        }

        $repoRoot = ''
        foreach ($candidatePath in @($taskMetadataPath, $taskRootPath, $directoryPath, $stageRootDirectoryPath)) {
            if ([string]::IsNullOrWhiteSpace([string]$candidatePath)) {
                continue
            }

            $repoRoot = Resolve-ClagnosTaskRepoRootFromPath -StartPath $candidatePath
            if (-not [string]::IsNullOrWhiteSpace([string]$repoRoot)) {
                break
            }
        }

        $isWindowsPowerShellTask = $false
        foreach ($pathCandidate in @($relativePath, $taskName, $directoryPath)) {
            if ([string]::IsNullOrWhiteSpace([string]$pathCandidate)) {
                continue
            }

            if ([string]$pathCandidate -match '(?i)\.ps1$' -or [string]$pathCandidate -match '^(?:windows[\\/])' -or [string]$pathCandidate -match '(?i)[\\/]windows[\\/]') {
                $isWindowsPowerShellTask = $true
                break
            }
        }

        if ($isWindowsPowerShellTask -and -not [string]::IsNullOrWhiteSpace([string]$repoRoot)) {
            $assetSpecs += [pscustomobject]@{
                LocalPath = (Join-Path $repoRoot 'modules\core\tasks\clagnos-session-environment.psm1')
                RemotePath = 'C:/Windows/Temp/clagnos-session-environment.psm1'
            }
        }

        $assetCopies = @()
        $assetCopyKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        if (-not [string]::IsNullOrWhiteSpace([string]$directoryPath)) {
            foreach ($assetSpec in @($assetSpecs)) {
                $assetLocalPath = [string]$assetSpec.LocalPath
                $assetRemotePath = [string]$assetSpec.RemotePath
                if ($effectiveReplacements.Count -gt 0) {
                    foreach ($key in $effectiveReplacements.Keys) {
                        $token = "__{0}__" -f [string]$key
                        $value = [string]$effectiveReplacements[$key]
                        $assetLocalPath = $assetLocalPath.Replace($token, $value)
                        $assetRemotePath = $assetRemotePath.Replace($token, $value)
                    }
                }

                if (-not [System.IO.Path]::IsPathRooted($assetLocalPath)) {
                    $assetLocalPath = Join-Path $directoryPath ($assetLocalPath.Replace('/', '\'))
                }
                if (-not (Test-Path -LiteralPath $assetLocalPath)) {
                    throw ("Task asset was not found for '{0}': {1}" -f $taskName, $assetLocalPath)
                }

                $resolvedLocalPath = [string](Resolve-Path -LiteralPath $assetLocalPath).Path
                $copyKey = ("{0}|{1}" -f [string]$resolvedLocalPath, [string]$assetRemotePath)
                if ($assetCopyKeys.Add([string]$copyKey)) {
                    $assetCopies += [pscustomobject]@{
                        LocalPath = [string]$resolvedLocalPath
                        RemotePath = [string]$assetRemotePath
                    }
                }
            }

        }

        $resolvedBlocks += [pscustomobject]@{
            Name = $taskName
            Script = $taskScript
            RelativePath = $relativePath
            DirectoryPath = $directoryPath
            TaskRootPath = $taskRootPath
            TaskMetadataPath = $taskMetadataPath
            StageRootDirectoryPath = $stageRootDirectoryPath
            AssetCopies = @($assetCopies)
            TimeoutSeconds = [int]$timeoutSeconds
            Priority = if ($taskBlock.PSObject.Properties.Match('Priority').Count -gt 0) { [int]$taskBlock.Priority } else { 0 }
            TaskType = if ($taskBlock.PSObject.Properties.Match('TaskType').Count -gt 0) { [string]$taskBlock.TaskType } else { '' }
            Source = if ($taskBlock.PSObject.Properties.Match('Source').Count -gt 0) { [string]$taskBlock.Source } else { '' }
            TaskNumber = if ($taskBlock.PSObject.Properties.Match('TaskNumber').Count -gt 0) { [int]$taskBlock.TaskNumber } else { 0 }
            AppStateSpec = if ($taskBlock.PSObject.Properties.Match('AppStateSpec').Count -gt 0) { $taskBlock.AppStateSpec } else { $null }
            ProgramSpec = if ($taskBlock.PSObject.Properties.Match('ProgramSpec').Count -gt 0) { $taskBlock.ProgramSpec } else { $null }
            Extensions = if ($taskBlock.PSObject.Properties.Match('Extensions').Count -gt 0) { $taskBlock.Extensions } else { $null }
            DependsOn = if ($taskBlock.PSObject.Properties.Match('DependsOn').Count -gt 0) { @($taskBlock.DependsOn) } else { @() }
            ObservedDurationSeconds = if ($taskBlock.PSObject.Properties.Match('ObservedDurationSeconds').Count -gt 0) { [double]$taskBlock.ObservedDurationSeconds } else { [double]::PositiveInfinity }
        }
    }

    return $resolvedBlocks
}

