# Shared vm-update app-state plugin helpers.

function Get-ClagnosTaskAppStateIdentity {
    param([psobject]$TaskBlock)

    if ($null -eq $TaskBlock) { return '' }
    if ($TaskBlock.PSObject.Properties.Match('AppStateKey').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$TaskBlock.AppStateKey)) {
        return [string]$TaskBlock.AppStateKey
    }
    if ($TaskBlock.PSObject.Properties.Match('Name').Count -gt 0) { return [string]$TaskBlock.Name }
    return ''
}

function Initialize-ClagnosAppStateZipSupport {
    if (-not ([System.Management.Automation.PSTypeName]'System.IO.Compression.ZipArchive').Type) {
        Add-Type -AssemblyName 'System.IO.Compression.FileSystem' -ErrorAction SilentlyContinue
        Add-Type -AssemblyName 'System.IO.Compression' -ErrorAction SilentlyContinue
    }
}

function Get-ClagnosTaskStageRootDirectoryPath {
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

function Get-ClagnosTaskAppStateRootDirectoryPath {
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

function Get-ClagnosTaskAppStateBackupScopeDirectoryPath {
    param([psobject]$TaskBlock)

    if ($null -eq $TaskBlock) {
        return ''
    }

    $stageRootPath = Get-ClagnosTaskStageRootDirectoryPath -TaskBlock $TaskBlock
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

    if (-not [string]::IsNullOrWhiteSpace([string]$relativePath)) {
        $normalizedRelative = $relativePath.Replace('\', '/').TrimStart('/')
        if ($normalizedRelative.StartsWith('local/', [System.StringComparison]::OrdinalIgnoreCase)) {
            return (Join-Path $stageRootPath 'local')
        }
    }

    $taskRootPath = ''
    if ($TaskBlock.PSObject.Properties.Match('TaskRootPath').Count -gt 0) {
        $taskRootPath = [string]$TaskBlock.TaskRootPath
    }
    if ([string]::IsNullOrWhiteSpace([string]$taskRootPath) -and $TaskBlock.PSObject.Properties.Match('DirectoryPath').Count -gt 0) {
        $taskRootPath = [string]$TaskBlock.DirectoryPath
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$taskRootPath)) {
        $taskParentPath = [string](Split-Path -Path $taskRootPath -Parent)
        if ([string]::Equals([string](Split-Path -Path $taskParentPath -Leaf), 'local', [System.StringComparison]::OrdinalIgnoreCase)) {
            return (Join-Path $stageRootPath 'local')
        }
    }

    return [string]$stageRootPath
}

function Get-ClagnosTaskAppStateBackupRootDirectoryPath {
    param([psobject]$TaskBlock)

    if ($null -eq $TaskBlock) {
        return ''
    }

    $taskName = ''
    if ($TaskBlock.PSObject.Properties.Match('Name').Count -gt 0) {
        $taskName = Get-ClagnosTaskAppStateIdentity -TaskBlock $TaskBlock
    }
    if ([string]::IsNullOrWhiteSpace([string]$taskName)) {
        return ''
    }

    $scopeDirectory = Get-ClagnosTaskAppStateBackupScopeDirectoryPath -TaskBlock $TaskBlock
    if ([string]::IsNullOrWhiteSpace([string]$scopeDirectory)) {
        return ''
    }

    return (Join-Path (Join-Path $scopeDirectory 'backup-app-states') $taskName)
}

function Get-ClagnosTaskAppStatePluginDirectoryPath {
    param([psobject]$TaskBlock)

    return (Get-ClagnosTaskAppStateRootDirectoryPath -TaskBlock $TaskBlock)
}

function Get-ClagnosTaskAppStateZipPath {
    param([psobject]$TaskBlock)

    $pluginDirectory = Get-ClagnosTaskAppStatePluginDirectoryPath -TaskBlock $TaskBlock
    if ([string]::IsNullOrWhiteSpace([string]$pluginDirectory)) {
        return ''
    }

    return (Join-Path $pluginDirectory 'app-state.zip')
}

function Get-ClagnosAppStateGuestHelperPath {
    return (Join-Path $PSScriptRoot 'clagnos-app-state-guest.psm1')
}

function Get-ClagnosZipArchiveEntryByName {
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

function Get-ClagnosTaskAppStateManifestFromZip {
    param(
        [string]$ZipPath,
        [string]$ExpectedTaskName
    )

    Initialize-ClagnosAppStateZipSupport

    if ([string]::IsNullOrWhiteSpace([string]$ZipPath) -or -not (Test-Path -LiteralPath $ZipPath)) {
        throw ("App-state zip was not found: {0}" -f [string]$ZipPath)
    }

    $archive = $null
    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        $manifestEntry = Get-ClagnosZipArchiveEntryByName -Archive $archive -EntryName 'app-state.manifest.json'
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

function Get-ClagnosTaskAppStatePluginInfo {
    param([psobject]$TaskBlock)

    $taskName = Get-ClagnosTaskAppStateIdentity -TaskBlock $TaskBlock
    $pluginDirectory = Get-ClagnosTaskAppStatePluginDirectoryPath -TaskBlock $TaskBlock
    $zipPath = Get-ClagnosTaskAppStateZipPath -TaskBlock $TaskBlock
    $guestHelperPath = Get-ClagnosAppStateGuestHelperPath

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
        $manifestInfo = Get-ClagnosTaskAppStateManifestFromZip -ZipPath $zipPath -ExpectedTaskName $taskName
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

function Get-ClagnosTaskAppStateSelectedProfileTokens {
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

function Test-ClagnosTaskAppStateManifestEntryMatchesSelectedProfiles {
    param(
        [AllowNull()]$Entry,
        [string[]]$SelectedProfiles = @()
    )

    $normalizedSelections = @(Get-ClagnosTaskAppStateSelectedProfileTokens -SelectedProfiles $SelectedProfiles)
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

function New-ClagnosTaskAppStateFilteredZip {
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

    $normalizedSelections = @(Get-ClagnosTaskAppStateSelectedProfileTokens -SelectedProfiles $SelectedProfiles)
    if (@($normalizedSelections).Count -lt 1) {
        Copy-Item -LiteralPath $SourceZipPath -Destination $DestinationZipPath -Force
        return [pscustomobject]@{
            ZipPath = [string]$DestinationZipPath
            Filtered = $false
            SelectionCount = 0
        }
    }

    $manifestInfo = Get-ClagnosTaskAppStateManifestFromZip -ZipPath $SourceZipPath -ExpectedTaskName $TaskName
    $scratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('clagnos-app-state-filter-{0}' -f ([guid]::NewGuid().ToString('N')))
    Ensure-ClagnosAppStatePluginDirectory -Path $scratchRoot
    try {
        Initialize-ClagnosAppStateZipSupport
        [System.IO.Compression.ZipFile]::ExtractToDirectory($SourceZipPath, $scratchRoot)

        $manifest = $manifestInfo.Manifest
        $profileDirectories = @($manifest.profileDirectories | Where-Object {
                Test-ClagnosTaskAppStateManifestEntryMatchesSelectedProfiles -Entry $_ -SelectedProfiles $normalizedSelections
            })
        $profileFiles = @($manifest.profileFiles | Where-Object {
                Test-ClagnosTaskAppStateManifestEntryMatchesSelectedProfiles -Entry $_ -SelectedProfiles $normalizedSelections
            })
        $registryImports = @()
        foreach ($entry in @($manifest.registryImports)) {
            if ($null -eq $entry) {
                continue
            }

            $scope = if ($entry.PSObject.Properties.Match('scope').Count -gt 0) { [string]$entry.scope } else { '' }
            if ([string]::Equals([string]$scope, 'user', [System.StringComparison]::OrdinalIgnoreCase)) {
                if (-not (Test-ClagnosTaskAppStateManifestEntryMatchesSelectedProfiles -Entry $entry -SelectedProfiles $normalizedSelections)) {
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

function Get-ClagnosTaskAppStateRemoteZipPath {
    param([string]$TaskName)

    $safeName = ([string]$TaskName -replace '[^A-Za-z0-9\-]', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace([string]$safeName)) {
        $safeName = 'task'
    }

    return ('C:/Windows/Temp/clagnos-app-state-{0}.zip' -f $safeName)
}

function Get-ClagnosTaskAppStateRemoteGuestHelperPath {
    param(
        [ValidateSet('windows','linux')]
        [string]$Platform
    )

    if ([string]::Equals([string]$Platform, 'linux', [System.StringComparison]::OrdinalIgnoreCase)) {
        return '/tmp/clagnos-app-state-guest.psm1'
    }

    return 'C:/Windows/Temp/clagnos-app-state-guest.psm1'
}

function Get-ClagnosTaskAppStateGuestScript {
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
`$modulePath = 'C:\Windows\Temp\clagnos-app-state-guest.psm1'
if (-not (Test-Path -LiteralPath `$modulePath)) {
    throw ('Guest app-state helper was not found: {0}' -f `$modulePath)
}
Import-Module `$modulePath -Force -DisableNameChecking
`$result = Invoke-ClagnosTaskAppStateReplay -ZipPath '$remoteZipPathSafe' -TaskName '$taskNameSafe' -ManagerUser '$managerUserSafe' -AssistantUser '$assistantUserSafe'
Write-Host ('app-state-summary => task={0}; machine-registry={1}; user-registry={2}; machine-directories={3}; machine-files={4}; profile-directories={5}; profile-files={6}; verified={7}; verify-checked={8}; verify-mismatches={9}; rollback-performed={10}; rollback-succeeded={11}' -f '$taskNameSafe', [int]`$result.MachineRegistryImports, [int]`$result.UserRegistryImports, [int]`$result.MachineDirectoryCopies, [int]`$result.MachineFileCopies, [int]`$result.ProfileDirectoryCopies, [int]`$result.ProfileFileCopies, [bool]`$result.Verified, [int]`$result.VerifyCheckedCount, [int]`$result.VerifyMismatchCount, [bool]`$result.RollbackPerformed, [bool]`$result.RollbackSucceeded)
Write-Host 'app-state-replay-completed'
"@
}

function Get-ClagnosTaskAppStateLinuxGuestScript {
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
scratch_root="$(mktemp -d /tmp/clagnos-app-state.XXXXXX)"
cleanup() {
  rm -rf "$scratch_root"
  rm -f "$zip_path"
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
"$python_bin" - "$zip_path" "$scratch_root" "$task_name" "$manager_user" "$assistant_user" <<'PY'
import json
import os
import shutil
import sys
import zipfile

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

profile_targets = []
seen_targets = set()
for label, user_name, profile_path in (
    ('manager', manager_user, f"/home/{manager_user}" if manager_user else ''),
    ('assistant', assistant_user, f"/home/{assistant_user}" if assistant_user else ''),
):
    if not profile_path or not os.path.isdir(profile_path):
        continue
    normalized_path = os.path.normpath(profile_path)
    if normalized_path in seen_targets:
        continue
    profile_targets.append((label, user_name, normalized_path))
    seen_targets.add(normalized_path)

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

function Invoke-ClagnosTaskAppStatePostProcess {
    param(
        [ValidateSet('windows','linux')]
        [string]$Platform,
        [ValidateSet('ssh')]
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

    $pluginInfo = Get-ClagnosTaskAppStatePluginInfo -TaskBlock $TaskBlock
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

    $remoteZipTaskName = [string]$taskName
    if ([string]::Equals([string]$Platform, 'windows', [System.StringComparison]::OrdinalIgnoreCase)) {
        $remoteZipTaskName = ('{0}-{1}' -f [string]$taskName, ([guid]::NewGuid().ToString('N').Substring(0, 8)))
    }
    $remoteZipPath = Get-ClagnosTaskAppStateRemoteZipPath -TaskName $remoteZipTaskName
    $remoteGuestHelperPath = Get-ClagnosTaskAppStateRemoteGuestHelperPath -Platform $Platform
    try {
        if ([string]::IsNullOrWhiteSpace([string]$HostName) -or
            [string]::IsNullOrWhiteSpace([string]$UserName) -or
            [string]::IsNullOrWhiteSpace([string]$Password) -or
            [string]::IsNullOrWhiteSpace([string]$Port)) {
            throw 'SSH-only app-state replay requires host, user, password, and port.'
        }

        Copy-ClagnosAssetToVm -PySshPythonPath $PySshPythonPath -PySshClientPath $PySshClientPath -HostName $HostName -UserName $UserName -Password $Password -Port $Port -LocalPath ([string]$pluginInfo.ZipPath) -RemotePath $remoteZipPath -ConnectTimeoutSeconds $ConnectTimeoutSeconds | Out-Null
        $scriptText = ''
        if ($Platform -eq 'windows') {
            $guestHelperPath = [string]$pluginInfo.GuestHelperPath
            if ([string]::IsNullOrWhiteSpace([string]$guestHelperPath) -or -not (Test-Path -LiteralPath $guestHelperPath)) {
                Write-Warning ("App-state warning: {0} => guest helper was not found: {1}" -f [string]$taskName, [string]$guestHelperPath)
                return [pscustomobject]@{ Status = 'warning'; Warning = $true; Message = 'guest helper missing' }
            }

            Copy-ClagnosAssetToVm -PySshPythonPath $PySshPythonPath -PySshClientPath $PySshClientPath -HostName $HostName -UserName $UserName -Password $Password -Port $Port -LocalPath $guestHelperPath -RemotePath $remoteGuestHelperPath -ConnectTimeoutSeconds $ConnectTimeoutSeconds | Out-Null
            $scriptText = Get-ClagnosTaskAppStateGuestScript -TaskName $taskName -RemoteZipPath $remoteZipPath -ManagerUser $ManagerUser -AssistantUser $AssistantUser
        }
        else {
            $scriptText = Get-ClagnosTaskAppStateLinuxGuestScript -TaskName $taskName -RemoteZipPath $remoteZipPath -ManagerUser $ManagerUser -AssistantUser $AssistantUser
        }
        $scriptTimeout = $TimeoutSeconds
        if ($scriptTimeout -lt 60) { $scriptTimeout = 60 }
        if ($scriptTimeout -gt 600) { $scriptTimeout = 600 }
        $result = Invoke-ClagnosSshTaskScript `
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
