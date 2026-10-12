# Shared app-state capture helpers.

function New-ClagnosAppStateCaptureSpec {
    param(
        [string]$TaskName,
        [object[]]$MachineDirectories = @(),
        [object[]]$MachineFiles = @(),
        [object[]]$ProfileDirectories = @(),
        [object[]]$ProfileFiles = @(),
        [object[]]$MachineRegistryKeys = @(),
        [object[]]$UserRegistryKeys = @()
    )

    return [ordered]@{
        taskName = [string]$TaskName
        machineDirectories = @($MachineDirectories)
        machineFiles = @($MachineFiles)
        profileDirectories = @($ProfileDirectories)
        profileFiles = @($ProfileFiles)
        machineRegistryKeys = @($MachineRegistryKeys)
        userRegistryKeys = @($UserRegistryKeys)
    }
}

function New-ClagnosAppStatePathCaptureRule {
    param(
        [string]$Path,
        [string[]]$TargetProfiles = @(),
        [string[]]$ExcludeNames = @(),
        [string[]]$ExcludePathPatterns = @(),
        [string[]]$ExcludeFilePatterns = @()
    )

    return [ordered]@{
        path = [string]$Path
        targetProfiles = @($TargetProfiles | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        excludeNames = @($ExcludeNames | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        excludePathPatterns = @($ExcludePathPatterns | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        excludeFilePatterns = @($ExcludeFilePatterns | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    }
}

function New-ClagnosAppStateRegistryCaptureRule {
    param(
        [string]$Path,
        [string[]]$TargetProfiles = @(),
        [string[]]$DistributionAllowList = @()
    )

    return [ordered]@{
        path = [string]$Path
        targetProfiles = @($TargetProfiles | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        distributionAllowList = @($DistributionAllowList | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    }
}

function Ensure-ClagnosAppStatePluginDirectory {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace([string]$Path)) {
        return
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Convert-ClagnosAppStateRegistryPathToCanonicalRootLocal {
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

function Get-ClagnosAllowedAppStateProfileLabels {
    return @('manager', 'assistant')
}

function Get-ClagnosAllowedAppStateTargetProfiles {
    param([string[]]$TargetProfiles = @())

    if (@($TargetProfiles).Count -lt 1) {
        return @()
    }

    $allowedLabels = @(
        Get-ClagnosAllowedAppStateProfileLabels |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object { $_.Trim().ToLowerInvariant() }
    )
    $resolved = New-Object 'System.Collections.Generic.List[string]'
    $seen = @{}
    foreach ($rawProfile in @($TargetProfiles)) {
        $value = if ($null -eq $rawProfile) { '' } else { [string]$rawProfile }
        if ([string]::IsNullOrWhiteSpace([string]$value)) {
            continue
        }

        $normalizedValue = $value.Trim().ToLowerInvariant()
        if (@($allowedLabels) -notcontains $normalizedValue) {
            continue
        }
        if ($seen.ContainsKey($normalizedValue)) {
            continue
        }

        $resolved.Add($normalizedValue) | Out-Null
        $seen[$normalizedValue] = $true
    }

    return @($resolved.ToArray())
}

function Get-ClagnosTaskAppStateSpecCollectionValue {
    param(
        [AllowNull()]$Spec,
        [string]$CollectionName
    )

    if ($null -eq $Spec -or [string]::IsNullOrWhiteSpace([string]$CollectionName)) {
        return @()
    }

    if ($Spec -is [System.Collections.IDictionary]) {
        if ($Spec.Contains($CollectionName)) {
            return @($Spec[$CollectionName])
        }
        return @()
    }

    if ($Spec.PSObject.Properties.Match($CollectionName).Count -gt 0) {
        return @($Spec.$CollectionName)
    }

    return @()
}

function Get-ClagnosTaskAppStateRuleValue {
    param(
        [AllowNull()]$Rule,
        [string]$PropertyName
    )

    if ($null -eq $Rule -or [string]::IsNullOrWhiteSpace([string]$PropertyName)) {
        return $null
    }

    if ($Rule -is [System.Collections.IDictionary]) {
        if ($Rule.Contains($PropertyName)) {
            return $Rule[$PropertyName]
        }
        return $null
    }

    if ($Rule.PSObject.Properties.Match($PropertyName).Count -gt 0) {
        return $Rule.$PropertyName
    }

    return $null
}

function Get-ClagnosTaskAppStateLegacyRegistryPathFromZipEntry {
    param(
        [object]$Archive,
        [string]$EntryName
    )

    $entry = Get-ClagnosZipArchiveEntryByName -Archive $Archive -EntryName $EntryName
    if ($null -eq $entry) {
        return ''
    }

    $reader = New-Object System.IO.StreamReader($entry.Open())
    try {
        $content = [string]$reader.ReadToEnd()
    }
    finally {
        $reader.Dispose()
    }

    foreach ($lineRaw in @($content -split "`r?`n")) {
        $match = [regex]::Match([string]$lineRaw, '^\[(.+?)\]$')
        if ($match.Success) {
            return [string]$match.Groups[1].Value
        }
    }

    return ''
}

function Convert-ClagnosLegacyManifestToCaptureSpec {
    param(
        [string]$ZipPath,
        [string]$TaskName
    )

    $manifestInfo = Get-ClagnosTaskAppStateManifestFromZip -ZipPath $ZipPath -ExpectedTaskName $TaskName
    Initialize-ClagnosAppStateZipSupport
    $archive = $null
    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        $machineDirectories = New-Object 'System.Collections.Generic.List[object]'
        $machineFiles = New-Object 'System.Collections.Generic.List[object]'
        $profileDirectories = New-Object 'System.Collections.Generic.List[object]'
        $profileFiles = New-Object 'System.Collections.Generic.List[object]'
        $machineRegistryKeys = New-Object 'System.Collections.Generic.List[object]'
        $userRegistryKeys = New-Object 'System.Collections.Generic.List[object]'

        foreach ($entry in @($manifestInfo.Manifest.machineDirectories)) {
            if ($null -eq $entry -or [string]::IsNullOrWhiteSpace([string]$entry.destinationPath)) { continue }
            $machineDirectories.Add((New-ClagnosAppStatePathCaptureRule -Path ([string]$entry.destinationPath))) | Out-Null
        }
        foreach ($entry in @($manifestInfo.Manifest.machineFiles)) {
            if ($null -eq $entry -or [string]::IsNullOrWhiteSpace([string]$entry.destinationPath)) { continue }
            $machineFiles.Add((New-ClagnosAppStatePathCaptureRule -Path ([string]$entry.destinationPath))) | Out-Null
        }
        foreach ($entry in @($manifestInfo.Manifest.profileDirectories)) {
            if ($null -eq $entry -or [string]::IsNullOrWhiteSpace([string]$entry.relativeDestinationPath)) { continue }
            $targetProfiles = @()
            if ($entry.PSObject.Properties.Match('targetProfiles').Count -gt 0) {
                $targetProfiles = @(Get-ClagnosAllowedAppStateTargetProfiles -TargetProfiles @($entry.targetProfiles | ForEach-Object { [string]$_ }))
                if (@($targetProfiles).Count -lt 1) { continue }
            }
            $profileDirectories.Add((New-ClagnosAppStatePathCaptureRule -Path ([string]$entry.relativeDestinationPath) -TargetProfiles $targetProfiles)) | Out-Null
        }
        foreach ($entry in @($manifestInfo.Manifest.profileFiles)) {
            if ($null -eq $entry -or [string]::IsNullOrWhiteSpace([string]$entry.relativeDestinationPath)) { continue }
            $targetProfiles = @()
            if ($entry.PSObject.Properties.Match('targetProfiles').Count -gt 0) {
                $targetProfiles = @(Get-ClagnosAllowedAppStateTargetProfiles -TargetProfiles @($entry.targetProfiles | ForEach-Object { [string]$_ }))
                if (@($targetProfiles).Count -lt 1) { continue }
            }
            $profileFiles.Add((New-ClagnosAppStatePathCaptureRule -Path ([string]$entry.relativeDestinationPath) -TargetProfiles $targetProfiles)) | Out-Null
        }
        foreach ($entry in @($manifestInfo.Manifest.registryImports)) {
            if ($null -eq $entry -or [string]::IsNullOrWhiteSpace([string]$entry.sourcePath)) { continue }
            $registryPath = Get-ClagnosTaskAppStateLegacyRegistryPathFromZipEntry -Archive $archive -EntryName ([string]$entry.sourcePath)
            if ([string]::IsNullOrWhiteSpace([string]$registryPath)) { continue }
            $canonicalRegistryPath = Convert-ClagnosAppStateRegistryPathToCanonicalRootLocal -RegistryPath $registryPath
            if (-not [string]::IsNullOrWhiteSpace([string]$canonicalRegistryPath)) {
                $registryPath = [string]$canonicalRegistryPath
            }
            $targetProfiles = @()
            if ($entry.PSObject.Properties.Match('targetProfiles').Count -gt 0) {
                $targetProfiles = @(Get-ClagnosAllowedAppStateTargetProfiles -TargetProfiles @($entry.targetProfiles | ForEach-Object { [string]$_ }))
                if (-not [string]::Equals([string]$entry.scope, 'machine', [System.StringComparison]::OrdinalIgnoreCase) -and @($targetProfiles).Count -lt 1) {
                    continue
                }
            }
            $distributionAllowList = @()
            if ($entry.PSObject.Properties.Match('distributionAllowList').Count -gt 0) {
                $distributionAllowList = @($entry.distributionAllowList | ForEach-Object { [string]$_ })
            }
            if ([string]::Equals([string]$entry.scope, 'machine', [System.StringComparison]::OrdinalIgnoreCase)) {
                $machineRegistryKeys.Add((New-ClagnosAppStateRegistryCaptureRule -Path $registryPath -DistributionAllowList $distributionAllowList)) | Out-Null
            }
            else {
                if (-not [string]::Equals([string]$registryPath, 'HKEY_CURRENT_USER', [System.StringComparison]::OrdinalIgnoreCase) -and -not $registryPath.StartsWith('HKEY_CURRENT_USER\', [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }
                $userRegistryKeys.Add((New-ClagnosAppStateRegistryCaptureRule -Path $registryPath -TargetProfiles $targetProfiles -DistributionAllowList $distributionAllowList)) | Out-Null
            }
        }

        return (New-ClagnosAppStateCaptureSpec `
            -TaskName $TaskName `
            -MachineDirectories @($machineDirectories.ToArray()) `
            -MachineFiles @($machineFiles.ToArray()) `
            -ProfileDirectories @($profileDirectories.ToArray()) `
            -ProfileFiles @($profileFiles.ToArray()) `
            -MachineRegistryKeys @($machineRegistryKeys.ToArray()) `
            -UserRegistryKeys @($userRegistryKeys.ToArray()))
    }
    finally {
        if ($null -ne $archive) {
            $archive.Dispose()
        }
    }
}

function Merge-ClagnosTaskAppStateCaptureSpec {
    param(
        [AllowNull()]$PrimarySpec,
        [AllowNull()]$LegacySpec,
        [string]$TaskName
    )

    $merged = New-ClagnosAppStateCaptureSpec -TaskName $TaskName
    foreach ($collectionName in @('machineDirectories','machineFiles','profileDirectories','profileFiles','machineRegistryKeys','userRegistryKeys')) {
        $collector = New-Object 'System.Collections.Generic.Dictionary[string, object]' ([System.StringComparer]::OrdinalIgnoreCase)
        $specsToMerge = if ($null -ne $PrimarySpec) {
            @($PrimarySpec)
        }
        else {
            @($LegacySpec)
        }

        foreach ($spec in @($specsToMerge)) {
            foreach ($rule in @(Get-ClagnosTaskAppStateSpecCollectionValue -Spec $spec -CollectionName $collectionName)) {
                if ($null -eq $rule) { continue }
                $rulePath = ''
                if ($rule -is [string]) {
                    $rulePath = [string]$rule
                }
                else {
                    $rulePath = [string](Get-ClagnosTaskAppStateRuleValue -Rule $rule -PropertyName 'path')
                }
                if ([string]::IsNullOrWhiteSpace([string]$rulePath)) { continue }
                if (@('machineRegistryKeys','userRegistryKeys') -contains [string]$collectionName) {
                    $canonicalRulePath = Convert-ClagnosAppStateRegistryPathToCanonicalRootLocal -RegistryPath $rulePath
                    if (-not [string]::IsNullOrWhiteSpace([string]$canonicalRulePath)) {
                        $rulePath = [string]$canonicalRulePath
                    }
                }

                $ruleKey = $rulePath.Trim().ToLowerInvariant()
                $ruleTargetProfiles = @(Get-ClagnosTaskAppStateRuleValue -Rule $rule -PropertyName 'targetProfiles')
                if (@($ruleTargetProfiles).Count -gt 0) {
                    if (@('profileDirectories','profileFiles','userRegistryKeys') -contains [string]$collectionName) {
                        $ruleTargetProfiles = @(Get-ClagnosAllowedAppStateTargetProfiles -TargetProfiles @($ruleTargetProfiles | ForEach-Object { [string]$_ }))
                        if (@($ruleTargetProfiles).Count -lt 1) {
                            continue
                        }
                    }

                    $profilesKey = (@($ruleTargetProfiles | ForEach-Object { [string]$_ } | Sort-Object) -join ',').ToLowerInvariant()
                    if (-not [string]::IsNullOrWhiteSpace([string]$profilesKey)) {
                        $ruleKey = ('{0}|profiles={1}' -f $ruleKey, $profilesKey)
                    }
                }
                if (-not $collector.ContainsKey($ruleKey)) {
                    $collector[$ruleKey] = $rule
                }
            }
        }

        if ($merged -is [System.Collections.IDictionary]) {
            $merged[$collectionName] = @($collector.Values)
        }
        else {
            $merged | Add-Member -NotePropertyName $collectionName -NotePropertyValue @($collector.Values) -Force
        }
    }

    return $merged
}

function Get-ClagnosTaskAppStateCapturePlan {
    param([psobject]$TaskBlock)

    if ($null -eq $TaskBlock) {
        return $null
    }

    $taskName = if ($TaskBlock.PSObject.Properties.Match('Name').Count -gt 0) { [string]$TaskBlock.Name } else { '' }
    if ([string]::IsNullOrWhiteSpace([string]$taskName)) {
        return $null
    }

    $primarySpec = $null
    if ($TaskBlock.PSObject.Properties.Match('AppStateSpec').Count -gt 0) {
        $primarySpec = $TaskBlock.AppStateSpec
    }
    $legacySpec = $null
    $zipPath = Get-ClagnosTaskAppStateZipPath -TaskBlock $TaskBlock
    if (-not [string]::IsNullOrWhiteSpace([string]$zipPath) -and (Test-Path -LiteralPath $zipPath)) {
        try {
            $legacySpec = Convert-ClagnosLegacyManifestToCaptureSpec -ZipPath $zipPath -TaskName $taskName
        }
        catch {
            Write-Warning ("App-state capture warning: {0} => legacy zip coverage could not be parsed: {1}" -f [string]$taskName, $_.Exception.Message)
        }
    }

    if ($null -eq $primarySpec -and $null -eq $legacySpec) {
        return $null
    }

    return (Merge-ClagnosTaskAppStateCaptureSpec -PrimarySpec $primarySpec -LegacySpec $legacySpec -TaskName $taskName)
}

function ConvertTo-ClagnosTaskAppStateCapturePlanJson {
    param([psobject]$CapturePlan)

    if ($null -eq $CapturePlan) {
        return ''
    }

    return [string](ConvertTo-JsonCompat -InputObject $CapturePlan -Depth 12)
}

function Get-ClagnosTaskAppStateRemoteCapturePlanPath {
    param([string]$TaskName)

    $safeName = (([string]$TaskName -replace '[^A-Za-z0-9\-]', '-').Trim('-'))
    if ([string]::IsNullOrWhiteSpace([string]$safeName)) {
        $safeName = 'task'
    }

    return ('C:/Windows/Temp/clagnos-app-state-plan-{0}.json' -f $safeName)
}

function Get-ClagnosTaskAppStateRemoteCaptureZipPath {
    param([string]$TaskName)

    $safeName = (([string]$TaskName -replace '[^A-Za-z0-9\-]', '-').Trim('-'))
    if ([string]::IsNullOrWhiteSpace([string]$safeName)) {
        $safeName = 'task'
    }

    return ('C:/Windows/Temp/clagnos-app-state-capture-{0}.zip' -f $safeName)
}

function Get-ClagnosTaskAppStateGuestCaptureScript {
    param(
        [string]$TaskName,
        [string]$PlanPath,
        [string]$OutputZipPath,
        [string]$ManagerUser,
        [string]$AssistantUser
    )

    $taskNameSafe = [string]$TaskName.Replace("'", "''")
    $planPathSafe = [string]$PlanPath.Replace("'", "''")
    $outputZipPathSafe = [string]$OutputZipPath.Replace("'", "''")
    $managerUserSafe = [string]$ManagerUser.Replace("'", "''")
    $assistantUserSafe = [string]$AssistantUser.Replace("'", "''")

    return @"
`$ErrorActionPreference = 'Stop'
`$modulePath = 'C:\Windows\Temp\clagnos-app-state-guest.psm1'
if (-not (Test-Path -LiteralPath `$modulePath)) {
    throw ('Guest app-state helper was not found: {0}' -f `$modulePath)
}
Import-Module `$modulePath -Force -DisableNameChecking
`$result = Invoke-ClagnosTaskAppStateCapture -TaskName '$taskNameSafe' -PlanPath '$planPathSafe' -OutputZipPath '$outputZipPathSafe' -ManagerUser '$managerUserSafe' -AssistantUser '$assistantUserSafe'
Write-Host ('app-state-save-summary => task={0}; zip={1}; machine-registry={2}; user-registry={3}; machine-directories={4}; machine-files={5}; profile-directories={6}; profile-files={7}; skipped={8}' -f '$taskNameSafe', '$outputZipPathSafe', [int]`$result.MachineRegistryExports, [int]`$result.UserRegistryExports, [int]`$result.MachineDirectoryExports, [int]`$result.MachineFileExports, [int]`$result.ProfileDirectoryExports, [int]`$result.ProfileFileExports, [int]`$result.SkipCount)
if ([bool]`$result.CreatedZip) {
    Write-Host 'app-state-save-completed'
}
else {
    Write-Host 'app-state-save-skipped'
}
"@
}

function Save-ClagnosTaskAppStateFromVm {
    param(
        [ValidateSet('windows','linux')]
        [string]$Platform,
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
        [string]$AssistantUser = ''
    )

    $capturePlan = Get-ClagnosTaskAppStateCapturePlan -TaskBlock $TaskBlock
    $taskName = if ($null -ne $TaskBlock -and $TaskBlock.PSObject.Properties.Match('Name').Count -gt 0) { [string]$TaskBlock.Name } else { '' }
    if ($null -eq $capturePlan) {
        Write-Host ("App-state skipped: {0} => no app-state spec or legacy coverage" -f [string]$taskName)
        return [pscustomobject]@{ Status = 'skipped'; Message = 'no app-state spec or legacy coverage'; Warning = $false }
    }

    $pluginDirectory = Get-ClagnosTaskAppStatePluginDirectoryPath -TaskBlock $TaskBlock
    $zipPath = Get-ClagnosTaskAppStateZipPath -TaskBlock $TaskBlock
    Ensure-ClagnosAppStatePluginDirectory -Path $pluginDirectory
    Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue

    $planJson = ConvertTo-ClagnosTaskAppStateCapturePlanJson -CapturePlan $capturePlan
    if ([string]::IsNullOrWhiteSpace([string]$planJson)) {
        Write-Host ("App-state skipped: {0} => empty capture plan" -f [string]$taskName)
        return [pscustomobject]@{ Status = 'skipped'; Message = 'empty capture plan'; Warning = $false }
    }

    $safeTaskName = (([string]$taskName -replace '[^A-Za-z0-9\-]', '-').Trim('-'))
    if ([string]::IsNullOrWhiteSpace([string]$safeTaskName)) {
        $safeTaskName = 'task'
    }

    $remotePlanPath = Get-ClagnosTaskAppStateRemoteCapturePlanPath -TaskName $taskName
    $remoteZipPath = Get-ClagnosTaskAppStateRemoteCaptureZipPath -TaskName $taskName
    $localPlanPath = Join-Path ([System.IO.Path]::GetTempPath()) ('clagnos-app-state-plan-{0}-{1}.json' -f $safeTaskName, ([guid]::NewGuid().ToString('N')))
    try {
        $scriptTimeout = $TimeoutSeconds
        if ($scriptTimeout -lt 60) { $scriptTimeout = 60 }
        if ($scriptTimeout -gt 3600) { $scriptTimeout = 3600 }
        $taskShell = 'powershell'
        $captureScript = ''
        Set-Content -LiteralPath $localPlanPath -Value $planJson -Encoding UTF8
        if ([string]::Equals($Platform, 'windows', [System.StringComparison]::OrdinalIgnoreCase)) {
            $guestHelperPath = Get-ClagnosAppStateGuestHelperPath
            Copy-ClagnosAssetToVm -PySshPythonPath $PySshPythonPath -PySshClientPath $PySshClientPath -HostName $HostName -UserName $UserName -Password $Password -Port $Port -LocalPath $localPlanPath -RemotePath $remotePlanPath -ConnectTimeoutSeconds $ConnectTimeoutSeconds | Out-Null
            Copy-ClagnosAssetToVm -PySshPythonPath $PySshPythonPath -PySshClientPath $PySshClientPath -HostName $HostName -UserName $UserName -Password $Password -Port $Port -LocalPath $guestHelperPath -RemotePath 'C:/Windows/Temp/clagnos-app-state-guest.psm1' -ConnectTimeoutSeconds $ConnectTimeoutSeconds | Out-Null
            $captureScript = Get-ClagnosTaskAppStateGuestCaptureScript -TaskName $taskName -PlanPath $remotePlanPath -OutputZipPath $remoteZipPath -ManagerUser $ManagerUser -AssistantUser $AssistantUser
        }
        else {
            $taskShell = 'bash'
            Copy-ClagnosAssetToVm -PySshPythonPath $PySshPythonPath -PySshClientPath $PySshClientPath -HostName $HostName -UserName $UserName -Password $Password -Port $Port -LocalPath $localPlanPath -RemotePath $remotePlanPath -ConnectTimeoutSeconds $ConnectTimeoutSeconds | Out-Null
            $bashTaskName = [string]$taskName.Replace("'", "'""'""'")
            $bashRemotePlanPath = [string]$remotePlanPath.Replace("'", "'""'""'")
            $bashRemoteZipPath = [string]$remoteZipPath.Replace("'", "'""'""'")
            $bashManagerUser = [string]$ManagerUser.Replace("'", "'""'""'")
            $bashAssistantUser = [string]$AssistantUser.Replace("'", "'""'""'")
            $captureScript = @"
set -euo pipefail
task_name='$bashTaskName'
plan_path='$bashRemotePlanPath'
zip_path='$bashRemoteZipPath'
manager_user='$bashManagerUser'
assistant_user='$bashAssistantUser'
scratch_root="$(mktemp -d /tmp/clagnos-app-state-save.XXXXXX)"
cleanup() {
  rm -rf "$scratch_root"
  rm -f "$plan_path"
}
trap cleanup EXIT
python_bin=''
if command -v python3 >/dev/null 2>&1; then
  python_bin="$(command -v python3)"
elif command -v python >/dev/null 2>&1; then
  python_bin="$(command -v python)"
else
  echo 'WARNING: app-state-save-skip => python interpreter was not found.'
  exit 3
fi
"$python_bin" - "$task_name" "$plan_path" "$zip_path" "$manager_user" "$assistant_user" <<'PY'
import glob
import json
import os
import re
import shutil
import sys
import tempfile
import zipfile

task_name, plan_path, zip_path, manager_user, assistant_user = sys.argv[1:6]

def warn(message: str) -> None:
    print(f"WARNING: {message}")

def safe_name(text: str) -> str:
    return re.sub(r'[^A-Za-z0-9_.-]+', '-', text.strip()).strip('-') or 'item'

def expand_machine_path(raw_path: str) -> str:
    return os.path.expandvars(raw_path.replace('\\\\', '/').replace('/', os.sep))

def profile_map():
    mapping = {}
    for label, user_name, profile_path in (
        ('manager', manager_user, f"/home/{manager_user}" if manager_user else ''),
        ('assistant', assistant_user, f"/home/{assistant_user}" if assistant_user else ''),
    ):
        if profile_path and os.path.isdir(profile_path):
            mapping[label] = os.path.normpath(profile_path)
            if user_name:
                mapping[user_name.lower()] = os.path.normpath(profile_path)
    return mapping

def resolve_profiles(target_profiles, all_profiles):
    if not target_profiles:
        seen = set()
        ordered = []
        for key in ('manager', 'assistant'):
            path = all_profiles.get(key, '')
            if path and path not in seen:
                ordered.append((key, path))
                seen.add(path)
        return ordered
    ordered = []
    seen = set()
    for raw_profile in target_profiles:
        key = str(raw_profile).strip().lower()
        path = all_profiles.get(key, '')
        if path and path not in seen:
            ordered.append((key, path))
            seen.add(path)
    return ordered

def should_skip(name: str, exclude_names, exclude_patterns) -> bool:
    lower_name = name.lower()
    for entry in exclude_names:
        if lower_name == str(entry).strip().lower():
            return True
    for pattern in exclude_patterns:
        try:
            if re.fullmatch(str(pattern), name, flags=re.IGNORECASE):
                return True
        except re.error:
            continue
    return False

def copy_tree(source_path, destination_root, exclude_names=None, exclude_patterns=None):
    copied_any = False
    exclude_names = exclude_names or []
    exclude_patterns = exclude_patterns or []
    if os.path.isfile(source_path):
        os.makedirs(os.path.dirname(destination_root), exist_ok=True)
        shutil.copy2(source_path, destination_root)
        return True
    for root, dirnames, filenames in os.walk(source_path):
        dirnames[:] = [
            name for name in dirnames
            if not os.path.islink(os.path.join(root, name)) and not should_skip(name, exclude_names, exclude_patterns)
        ]
        relative_root = os.path.relpath(root, source_path)
        destination_dir = destination_root if relative_root == '.' else os.path.join(destination_root, relative_root)
        os.makedirs(destination_dir, exist_ok=True)
        for filename in filenames:
            if should_skip(filename, exclude_names, exclude_patterns):
                continue
            source_file = os.path.join(root, filename)
            if os.path.islink(source_file):
                continue
            try:
                shutil.copy2(source_file, os.path.join(destination_dir, filename))
                copied_any = True
            except Exception as exc:
                warn(f"app-state-save-copy-skip => source={source_file}; reason={exc}")
    return copied_any

with open(plan_path, 'r', encoding='utf-8') as handle:
    plan = json.load(handle)

if str(plan.get('taskName', '')).strip().lower() != task_name.strip().lower():
    raise RuntimeError(f"App-state capture plan taskName '{plan.get('taskName', '')}' does not match task '{task_name}'.")

scratch_root = tempfile.mkdtemp(prefix='clagnos-app-state-linux-')
payload_root = os.path.join(scratch_root, 'payload')
os.makedirs(payload_root, exist_ok=True)
manifest = {
    'version': 2,
    'taskName': task_name,
    'machineDirectories': [],
    'machineFiles': [],
    'profileDirectories': [],
    'profileFiles': [],
    'registryImports': []
}
profile_paths = profile_map()
machine_directory_exports = 0
machine_file_exports = 0
profile_directory_exports = 0
profile_file_exports = 0
skip_count = 0

for index, rule in enumerate(plan.get('machineDirectories', []), start=1):
    source_path = expand_machine_path(str(rule.get('path', '')).strip())
    matches = sorted(glob.glob(source_path))
    if not matches:
        skip_count += 1
        continue
    for match_path in matches:
        if not os.path.isdir(match_path):
            continue
        destination_rel = os.path.join('machine-directories', safe_name(f'{index}-{os.path.basename(match_path)}'))
        destination_abs = os.path.join(payload_root, destination_rel)
        if copy_tree(match_path, destination_abs, rule.get('excludeNames', []), rule.get('excludeFilePatterns', [])):
            manifest['machineDirectories'].append({
                'sourcePath': destination_rel.replace(os.sep, '/'),
                'destinationPath': match_path
            })
            machine_directory_exports += 1

for index, rule in enumerate(plan.get('machineFiles', []), start=1):
    source_path = expand_machine_path(str(rule.get('path', '')).strip())
    matches = sorted(glob.glob(source_path))
    if not matches:
        skip_count += 1
        continue
    for match_path in matches:
        if not os.path.isfile(match_path):
            continue
        destination_rel = os.path.join('machine-files', safe_name(f'{index}-{os.path.basename(match_path)}'))
        destination_abs = os.path.join(payload_root, destination_rel)
        os.makedirs(os.path.dirname(destination_abs), exist_ok=True)
        shutil.copy2(match_path, destination_abs)
        manifest['machineFiles'].append({
            'sourcePath': destination_rel.replace(os.sep, '/'),
            'destinationPath': match_path
        })
        machine_file_exports += 1

for index, rule in enumerate(plan.get('profileDirectories', []), start=1):
    target_profiles = resolve_profiles(rule.get('targetProfiles', []), profile_paths)
    if not target_profiles:
        skip_count += 1
        continue
    for label, profile_root in target_profiles:
        relative_path = str(rule.get('path', '')).strip().replace('\\\\', '/').replace('/', os.sep)
        source_path = os.path.join(profile_root, relative_path)
        matches = sorted(glob.glob(source_path))
        if not matches:
            skip_count += 1
            continue
        for match_path in matches:
            if not os.path.isdir(match_path):
                continue
            destination_rel = os.path.join('profile-directories', safe_name(f'{index}-{label}-{os.path.basename(match_path)}'))
            destination_abs = os.path.join(payload_root, destination_rel)
            if copy_tree(match_path, destination_abs, rule.get('excludeNames', []), rule.get('excludeFilePatterns', [])):
                manifest['profileDirectories'].append({
                    'sourcePath': destination_rel.replace(os.sep, '/'),
                    'relativeDestinationPath': os.path.relpath(match_path, profile_root).replace(os.sep, '/'),
                    'targetProfiles': [label]
                })
                profile_directory_exports += 1

for index, rule in enumerate(plan.get('profileFiles', []), start=1):
    target_profiles = resolve_profiles(rule.get('targetProfiles', []), profile_paths)
    if not target_profiles:
        skip_count += 1
        continue
    for label, profile_root in target_profiles:
        relative_path = str(rule.get('path', '')).strip().replace('\\\\', '/').replace('/', os.sep)
        source_path = os.path.join(profile_root, relative_path)
        matches = sorted(glob.glob(source_path))
        if not matches:
            skip_count += 1
            continue
        for match_path in matches:
            if not os.path.isfile(match_path):
                continue
            destination_rel = os.path.join('profile-files', safe_name(f'{index}-{label}-{os.path.basename(match_path)}'))
            destination_abs = os.path.join(payload_root, destination_rel)
            os.makedirs(os.path.dirname(destination_abs), exist_ok=True)
            shutil.copy2(match_path, destination_abs)
            manifest['profileFiles'].append({
                'sourcePath': destination_rel.replace(os.sep, '/'),
                'relativeDestinationPath': os.path.relpath(match_path, profile_root).replace(os.sep, '/'),
                'targetProfiles': [label]
            })
            profile_file_exports += 1

manifest_path = os.path.join(scratch_root, 'app-state.manifest.json')
with open(manifest_path, 'w', encoding='utf-8') as handle:
    json.dump(manifest, handle, indent=2)

created_zip = bool(manifest['machineDirectories'] or manifest['machineFiles'] or manifest['profileDirectories'] or manifest['profileFiles'])
if created_zip:
    with zipfile.ZipFile(zip_path, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        archive.write(manifest_path, arcname='app-state.manifest.json')
        for root, _, filenames in os.walk(payload_root):
            for filename in filenames:
                abs_path = os.path.join(root, filename)
                arcname = os.path.relpath(abs_path, scratch_root).replace(os.sep, '/')
                archive.write(abs_path, arcname=arcname)

print(
    'app-state-save-summary => task={0}; zip={1}; machine-registry={2}; user-registry={3}; machine-directories={4}; machine-files={5}; profile-directories={6}; profile-files={7}; skipped={8}'.format(
        task_name,
        zip_path,
        0,
        0,
        machine_directory_exports,
        machine_file_exports,
        profile_directory_exports,
        profile_file_exports,
        skip_count,
    )
)
print('app-state-save-completed' if created_zip else 'app-state-save-skipped')
PY
"@
        }
        $result = Invoke-ClagnosSshTaskScript `
            -Session $Session `
            -PySshPythonPath $PySshPythonPath `
            -PySshClientPath $PySshClientPath `
            -HostName $HostName `
            -UserName $UserName `
            -Password $Password `
            -Port $Port `
            -Shell $taskShell `
            -TaskName ("{0} (app-state-save)" -f [string]$taskName) `
            -TaskScript $captureScript `
            -TimeoutSeconds $scriptTimeout `
            -SkipRemoteCleanup
        $outputWasRelayedLive = ($null -ne $result -and $result.PSObject.Properties.Match('OutputRelayedLive').Count -gt 0 -and [bool]$result.OutputRelayedLive)
        if ($null -eq $result -or [int]$result.ExitCode -ne 0) {
            $exitCode = if ($null -ne $result -and $result.PSObject.Properties.Match('ExitCode').Count -gt 0) { [int]$result.ExitCode } else { -1 }
            Write-Warning ("App-state warning: {0} => save exited with code {1}" -f [string]$taskName, $exitCode)
            return [pscustomobject]@{ Status = 'warning'; Message = ("save exited with code {0}" -f $exitCode); Warning = $true }
        }

        if (-not $outputWasRelayedLive -and $result.PSObject.Properties.Match('Output').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$result.Output)) {
            Write-Host ([string]$result.Output)
        }

        if ($result.PSObject.Properties.Match('Output').Count -gt 0 -and [string]$result.Output -match 'app-state-save-skipped') {
            Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
            Write-Host ("App-state skipped: {0} => no discoverable live payload" -f [string]$taskName)
            return [pscustomobject]@{ Status = 'skipped'; Message = 'no discoverable live payload'; Warning = $false }
        }

        Copy-ClagnosAssetFromVm -PySshPythonPath $PySshPythonPath -PySshClientPath $PySshClientPath -HostName $HostName -UserName $UserName -Password $Password -Port $Port -RemotePath $remoteZipPath -LocalPath $zipPath -ConnectTimeoutSeconds $ConnectTimeoutSeconds
        Write-Host ("App-state saved: {0} => {1}" -f [string]$taskName, [string]$zipPath)
        return [pscustomobject]@{ Status = 'saved'; Message = 'saved'; Warning = $false; ZipPath = [string]$zipPath }
    }
    catch {
        Write-Warning ("App-state warning: {0} => {1}" -f [string]$taskName, $_.Exception.Message)
        return [pscustomobject]@{ Status = 'warning'; Message = [string]$_.Exception.Message; Warning = $true }
    }
    finally {
        if ($localPlanPath -and (Test-Path -LiteralPath $localPlanPath)) {
            Remove-Item -LiteralPath $localPlanPath -Force -ErrorAction SilentlyContinue
        }
    }
}
