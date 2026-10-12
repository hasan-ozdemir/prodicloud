$ErrorActionPreference = 'Stop'

$script:TaskMap = @{
    'google-chrome' = '03-install-chrome-application'
    'microsoft-edge' = '103-install-edge-application'
    'vscode' = '116-install-vscode-application'
    'docker-desktop' = '134-install-docker-desktop-application-application'
    'wsl' = '121-install-wsl-feature'
    'ollama' = '135-install-ollama-tool'
    'azure-cli' = '130-install-azure-cli-tool-tool'
    'azd' = '108-install-azd-tool'
    'gh-cli' = '107-install-gh-tool'
    'rclone' = '105-install-rclone-tool'
    'google-drive' = '129-install-google-drive-application-application'
    'onedrive' = '104-install-onedrive-application'
    'vlc' = '131-install-vlc-application'
    'nvda' = '115-install-nvda-application'
    'jaws' = '133-install-jaws-application'
    'anydesk' = '109-install-anydesk-application'
    'itunes' = '117-install-itunes-application'
    'icloud' = '122-install-icloud-application'
    'teams' = '114-install-teams-application'
    'whatsapp' = '119-install-whatsapp-application'
    'codex-app' = '120-install-codex-application'
    'be-my-eyes' = '118-install-be-my-eyes-application-application'
    'windscribe' = '112-install-windscribe-application'
    'vs2022community' = '132-install-vs2022community-application-application'
}

$script:SourceManifestJson = @'
{
  "version": 1,
  "apps": [
    { "id": "google-chrome", "displayName": "Google Chrome", "profileFiles": [ "AppData\\Local\\Google\\Chrome\\User Data\\Local State", "AppData\\Local\\Google\\Chrome\\User Data\\Default\\Bookmarks", "AppData\\Local\\Google\\Chrome\\User Data\\Default\\Preferences" ], "userRegistryKeys": [ "HKCU\\Software\\Google\\Chrome" ] },
    { "id": "microsoft-edge", "displayName": "Microsoft Edge", "profileFiles": [ "AppData\\Local\\Microsoft\\Edge\\User Data\\Local State", "AppData\\Local\\Microsoft\\Edge\\User Data\\Default\\Bookmarks", "AppData\\Local\\Microsoft\\Edge\\User Data\\Default\\Preferences" ], "userRegistryKeys": [ "HKCU\\Software\\Microsoft\\Edge" ] },
    { "id": "vscode", "displayName": "Visual Studio Code", "profileDirectories": [ "AppData\\Roaming\\Code\\User" ], "userRegistryKeys": [ "HKCU\\Software\\Microsoft\\VSCommon" ] },
    { "id": "docker-desktop", "displayName": "Docker Desktop", "profileFiles": [ ".docker\\config.json", "AppData\\Roaming\\Docker\\settings-store.json", "AppData\\Roaming\\Docker\\daemon.json", "AppData\\Roaming\\Docker Desktop\\settings-store.json" ], "userRegistryKeys": [ "HKCU\\Software\\Docker Desktop", "HKCU\\Software\\Docker Inc." ] },
    { "id": "wsl", "displayName": "Windows Subsystem for Linux", "distributionAllowList": [ "docker-desktop" ], "userRegistryKeys": [ "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Lxss" ] },
    { "id": "ollama", "displayName": "Ollama", "profileFiles": [ "AppData\\Local\\Ollama\\config.json", "AppData\\Roaming\\Ollama\\config.json", "AppData\\Roaming\\ollama app.exe\\config.json" ] },
    { "id": "azure-cli", "displayName": "Azure CLI", "profileDirectories": [ ".azure" ] },
    { "id": "azd", "displayName": "Azure Developer CLI", "profileDirectories": [ ".azd" ] },
    { "id": "gh-cli", "displayName": "GitHub CLI", "profileDirectories": [ "AppData\\Roaming\\GitHub CLI", "AppData\\Local\\GitHub CLI" ] },
    { "id": "rclone", "displayName": "Rclone", "profileDirectories": [ "AppData\\Roaming\\rclone" ] },
    { "id": "google-drive", "displayName": "Google Drive", "userRegistryKeys": [ "HKCU\\Software\\Google\\DriveFS" ] },
    { "id": "onedrive", "displayName": "OneDrive", "userRegistryKeys": [ "HKCU\\Software\\Microsoft\\OneDrive" ] },
    { "id": "vlc", "displayName": "VLC media player", "profileFiles": [ "AppData\\Roaming\\vlc\\vlcrc" ], "userRegistryKeys": [ "HKCU\\Software\\VideoLAN\\VLC" ] },
    { "id": "nvda", "displayName": "NVDA", "profileDirectories": [ "AppData\\Roaming\\nvda" ], "userRegistryKeys": [ "HKCU\\Software\\NVDA" ] },
    { "id": "jaws", "displayName": "JAWS", "profileDirectories": [ "AppData\\Roaming\\Freedom Scientific\\JAWS\\2025\\Settings" ], "machineRegistryKeys": [ "HKLM\\Software\\Freedom Scientific", "HKLM\\Software\\WOW6432Node\\Freedom Scientific" ], "userRegistryKeys": [ "HKCU\\Software\\Freedom Scientific" ] },
    { "id": "anydesk", "displayName": "AnyDesk", "profileFiles": [ "AppData\\Roaming\\AnyDesk\\user.conf", "AppData\\Roaming\\AnyDesk\\system.conf" ], "userRegistryKeys": [ "HKCU\\Software\\AnyDesk" ] },
    { "id": "itunes", "displayName": "iTunes", "userRegistryKeys": [ "HKCU\\Software\\Apple Computer, Inc." ] },
    { "id": "icloud", "displayName": "iCloud", "userRegistryKeys": [ "HKCU\\Software\\Apple Inc.\\iCloud", "HKCU\\Software\\Apple Computer, Inc." ] },
    { "id": "teams", "displayName": "Microsoft Teams", "profileDirectories": [ "AppData\\Local\\Packages\\MSTeams_*\\Settings" ] },
    { "id": "whatsapp", "displayName": "WhatsApp", "profileDirectories": [ "AppData\\Local\\Packages\\5319275A.WhatsAppDesktop_*\\Settings" ] },
    { "id": "codex-app", "displayName": "Codex App", "profileDirectories": [ "AppData\\Local\\Packages\\OpenAI.Codex_*\\Settings" ] },
    { "id": "be-my-eyes", "displayName": "Be My Eyes", "profileDirectories": [ "AppData\\Local\\Packages\\BeMyEyes.BeMyEyes_*\\Settings" ] },
    { "id": "windscribe", "displayName": "Windscribe", "profileDirectories": [ "AppData\\Local\\Windscribe" ], "userRegistryKeys": [ "HKCU\\Software\\Windscribe" ] },
    { "id": "vs2022community", "displayName": "Visual Studio 2022 Community", "userRegistryKeys": [ "HKCU\\Software\\Microsoft\\VisualStudio", "HKCU\\Software\\Microsoft\\VSCommon" ] }
  ]
}
'@

function Ensure-LocalAppStatePluginDirectory {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace([string]$Path)) { return }
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Get-LocalAppStatePluginRepoRoot {
    $modulesRoot = Split-Path -Path $PSScriptRoot -Parent
    if ([string]::IsNullOrWhiteSpace([string]$modulesRoot)) {
        throw 'Local app-state export could not resolve the modules root.'
    }

    $repoRoot = Split-Path -Path $modulesRoot -Parent
    if ([string]::IsNullOrWhiteSpace([string]$repoRoot)) {
        throw 'Local app-state export could not resolve the repository root.'
    }

    return [string]$repoRoot
}

function Get-LocalAppStatePluginExportConfig {
    $repoRoot = Get-LocalAppStatePluginRepoRoot
    $stageRoot = Join-Path $repoRoot 'windows\update'
    return [ordered]@{
        RepoRoot = [string]$repoRoot
        StageRoot = [string]$stageRoot
        ExportScratchRoot = (Join-Path $env:TEMP 'clagnos-local-app-state-export')
        SourceManifest = (ConvertFrom-Json -InputObject $script:SourceManifestJson -ErrorAction Stop)
        TaskMap = $script:TaskMap.Clone()
    }
}

function Get-LocalAppStatePluginDirectoryPath {
    param(
        [hashtable]$TaskConfig,
        [string]$TaskName
    )

    if ($null -eq $TaskConfig -or [string]::IsNullOrWhiteSpace([string]$TaskName)) {
        return ''
    }

    $stageRoot = [string]$TaskConfig.StageRoot
    foreach ($candidate in @(
        (Join-Path $stageRoot $TaskName),
        (Join-Path $stageRoot ('disabled\' + $TaskName)),
        (Join-Path $stageRoot ('local\' + $TaskName)),
        (Join-Path $stageRoot ('local\disabled\' + $TaskName))
    )) {
        if (Test-Path -LiteralPath $candidate) {
            return (Join-Path $candidate 'app-state')
        }
    }

    return (Join-Path (Join-Path $stageRoot $TaskName) 'app-state')
}

function Resolve-LocalAppStatePathMatches {
    param(
        [string]$RootPath,
        [string]$RelativeOrAbsolutePath
    )

    if ([string]::IsNullOrWhiteSpace([string]$RelativeOrAbsolutePath)) {
        return @()
    }

    $candidatePath = [string]$RelativeOrAbsolutePath
    if (-not [System.IO.Path]::IsPathRooted($candidatePath) -and -not [string]::IsNullOrWhiteSpace([string]$RootPath)) {
        $candidatePath = Join-Path $RootPath $candidatePath
    }

    $hasWildcard = ($candidatePath.IndexOf('*', [System.StringComparison]::Ordinal) -ge 0 -or $candidatePath.IndexOf('?', [System.StringComparison]::Ordinal) -ge 0)
    if ($hasWildcard) {
        return @(
            Get-ChildItem -Path $candidatePath -Force -ErrorAction SilentlyContinue |
                Sort-Object FullName |
                Select-Object -ExpandProperty FullName
        )
    }

    if (Test-Path -LiteralPath $candidatePath) {
        return @([string](Resolve-Path -LiteralPath $candidatePath).Path)
    }

    return @()
}

function Convert-ToLocalAppStateSafeName {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return 'item'
    }

    return (($Value -replace '^[A-Za-z]:', '') -replace '[\\/:*?"<>| ]', '_').Trim('_')
}

function Copy-LocalAppStatePayloadItem {
    param(
        [string]$SourcePath,
        [string]$BuildRoot,
        [string]$RelativePayloadPath
    )

    if ([string]::IsNullOrWhiteSpace([string]$SourcePath) -or [string]::IsNullOrWhiteSpace([string]$BuildRoot) -or [string]::IsNullOrWhiteSpace([string]$RelativePayloadPath)) {
        return $false
    }

    $destinationPath = Join-Path $BuildRoot $RelativePayloadPath
    Ensure-LocalAppStatePluginDirectory -Path (Split-Path -Path $destinationPath -Parent)
    try {
        if (Test-Path -LiteralPath $SourcePath -PathType Container) {
            Copy-Item -LiteralPath $SourcePath -Destination $destinationPath -Recurse -Force -ErrorAction Stop
        }
        else {
            Copy-Item -LiteralPath $SourcePath -Destination $destinationPath -Force -ErrorAction Stop
        }
        return $true
    }
    catch {
        Write-Warning ("local-app-state-copy-skip => {0} => {1}" -f $SourcePath, $_.Exception.Message)
        return $false
    }
}

function Invoke-LocalAppStateRegExport {
    param(
        [string]$RegistryPath,
        [string]$DestinationPath
    )

    if ([string]::IsNullOrWhiteSpace([string]$RegistryPath) -or [string]::IsNullOrWhiteSpace([string]$DestinationPath)) {
        return $false
    }

    Ensure-LocalAppStatePluginDirectory -Path (Split-Path -Path $DestinationPath -Parent)
    cmd.exe /d /c ('reg export "{0}" "{1}" /y >nul 2>&1' -f $RegistryPath, $DestinationPath) | Out-Null
    return ([int]$LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $DestinationPath))
}

function Test-WslAppStateRegistryPath {
    param([string]$RegistryPath)

    return [string]::Equals(
        ([string]$RegistryPath).Trim(),
        'HKCU\Software\Microsoft\Windows\CurrentVersion\Lxss',
        [System.StringComparison]::OrdinalIgnoreCase
    )
}

function Get-LocalAppStateAllowedWslRegistryKeys {
    param(
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
        return @()
    }

    $providerRoot = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Lxss'
    if (-not (Test-Path -LiteralPath $providerRoot)) {
        return @()
    }

    $rows = New-Object 'System.Collections.Generic.List[object]'
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

        if (@($normalizedAllowList) -notcontains $distributionName.Trim().ToLowerInvariant()) {
            continue
        }

        $rows.Add([pscustomobject]@{
            DistributionName = [string]$distributionName
            RegistryPath = ('HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Lxss\{0}' -f [string]$childKey.PSChildName)
            KeyName = [string]$childKey.PSChildName
        }) | Out-Null
    }

    return @($rows.ToArray())
}

function Export-FilteredLocalWslAppStateRegistry {
    param(
        [string]$RegistryPath,
        [string]$DestinationPath,
        [string[]]$DistributionAllowList = @()
    )

    $allowedKeyEntries = @(Get-LocalAppStateAllowedWslRegistryKeys -RegistryPath $RegistryPath -DistributionAllowList $DistributionAllowList)
    if (@($allowedKeyEntries).Count -lt 1) {
        return $false
    }

    $tempExportPath = Join-Path ([System.IO.Path]::GetTempPath()) (('clagnos-wsl-plugin-{0}.reg' -f ([guid]::NewGuid().ToString('N'))))
    try {
        if (-not (Invoke-LocalAppStateRegExport -RegistryPath $RegistryPath -DestinationPath $tempExportPath)) {
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
        $allowedRegistryPaths = @($allowedKeyEntries | ForEach-Object { [string]$_.RegistryPath })
        $defaultKey = [string]$allowedKeyEntries[0].KeyName
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

        Ensure-LocalAppStatePluginDirectory -Path (Split-Path -Path $DestinationPath -Parent)
        Set-Content -LiteralPath $DestinationPath -Value (($outputBlocks -join ([Environment]::NewLine + [Environment]::NewLine)) + [Environment]::NewLine) -Encoding Unicode
        return $true
    }
    finally {
        Remove-Item -LiteralPath $tempExportPath -Force -ErrorAction SilentlyContinue
    }
}

function Export-LocalAppStatePlugins {
    param(
        [hashtable]$TaskConfig,
        [string]$ManagerUser = '',
        [string]$AssistantUser = ''
    )

    if ($null -eq $TaskConfig) {
        $TaskConfig = Get-LocalAppStatePluginExportConfig
    }

    $sourceManifest = $TaskConfig.SourceManifest
    $apps = @($sourceManifest.apps)
    $taskMap = $TaskConfig.TaskMap
    $scratchRoot = [string]$TaskConfig.ExportScratchRoot
    $currentProfilePath = [Environment]::GetFolderPath('UserProfile')

    Ensure-LocalAppStatePluginDirectory -Path ([string]$TaskConfig.StageRoot)
    Remove-Item -LiteralPath $scratchRoot -Recurse -Force -ErrorAction SilentlyContinue
    Ensure-LocalAppStatePluginDirectory -Path $scratchRoot

    $pluginPaths = New-Object 'System.Collections.Generic.List[string]'
    $skippedApps = New-Object 'System.Collections.Generic.List[string]'

    foreach ($app in @($apps)) {
        if ($null -eq $app) { continue }

        $appId = [string]$app.id
        $taskName = ''
        if ($taskMap.ContainsKey($appId)) {
            $taskName = [string]$taskMap[$appId]
        }
        if ([string]::IsNullOrWhiteSpace([string]$taskName)) {
            [void]$skippedApps.Add($appId)
            continue
        }

        $buildRoot = Join-Path $scratchRoot $taskName
        $pluginDirectory = Get-LocalAppStatePluginDirectoryPath -TaskConfig $TaskConfig -TaskName $taskName
        $pluginZipPath = Join-Path $pluginDirectory 'app-state.zip'
        Remove-Item -LiteralPath $buildRoot -Recurse -Force -ErrorAction SilentlyContinue
        Ensure-LocalAppStatePluginDirectory -Path $buildRoot

        $manifest = [ordered]@{
            version = 1
            taskName = [string]$taskName
            machineDirectories = @()
            machineFiles = @()
            profileDirectories = @()
            profileFiles = @()
            registryImports = @()
        }

        foreach ($registryPath in @($app.machineRegistryKeys)) {
            $payloadPath = Join-Path ('payload\registry\' + $appId) ((Convert-ToLocalAppStateSafeName -Value ([string]$registryPath)) + '.reg')
            if (Invoke-LocalAppStateRegExport -RegistryPath ([string]$registryPath) -DestinationPath (Join-Path $buildRoot $payloadPath)) {
                $manifest.registryImports += @{
                    sourcePath = [string]$payloadPath
                    scope = 'machine'
                }
            }
        }

        $distributionAllowList = @(
            @($app.distributionAllowList) |
                ForEach-Object { [string]$_ } |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
        )
        foreach ($registryPath in @($app.userRegistryKeys)) {
            $payloadPath = Join-Path ('payload\registry\' + $appId) ((Convert-ToLocalAppStateSafeName -Value ([string]$registryPath)) + '.reg')
            $destinationPath = Join-Path $buildRoot $payloadPath
            $exported = $false
            if ((Test-WslAppStateRegistryPath -RegistryPath ([string]$registryPath)) -and @($distributionAllowList).Count -gt 0) {
                $exported = Export-FilteredLocalWslAppStateRegistry -RegistryPath ([string]$registryPath) -DestinationPath $destinationPath -DistributionAllowList $distributionAllowList
            }
            else {
                $exported = Invoke-LocalAppStateRegExport -RegistryPath ([string]$registryPath) -DestinationPath $destinationPath
            }

            if ($exported) {
                $entry = [ordered]@{
                    sourcePath = [string]$payloadPath
                    scope = 'user'
                }
                if (@($distributionAllowList).Count -gt 0) {
                    $entry.distributionAllowList = @($distributionAllowList)
                }
                $manifest.registryImports += $entry
            }
        }

        foreach ($pattern in @($app.machineDirectories)) {
            foreach ($matchPath in @(Resolve-LocalAppStatePathMatches -RootPath '' -RelativeOrAbsolutePath ([string]$pattern))) {
                $payloadPath = Join-Path ('payload\machine-directories\' + $appId) (Convert-ToLocalAppStateSafeName -Value $matchPath)
                if (Copy-LocalAppStatePayloadItem -SourcePath $matchPath -BuildRoot $buildRoot -RelativePayloadPath $payloadPath) {
                    $manifest.machineDirectories += @{
                        sourcePath = [string]$payloadPath
                        destinationPath = [string]$matchPath
                    }
                }
            }
        }

        foreach ($pattern in @($app.machineFiles)) {
            foreach ($matchPath in @(Resolve-LocalAppStatePathMatches -RootPath '' -RelativeOrAbsolutePath ([string]$pattern))) {
                $payloadPath = Join-Path ('payload\machine-files\' + $appId) (Convert-ToLocalAppStateSafeName -Value $matchPath)
                if (Copy-LocalAppStatePayloadItem -SourcePath $matchPath -BuildRoot $buildRoot -RelativePayloadPath $payloadPath) {
                    $manifest.machineFiles += @{
                        sourcePath = [string]$payloadPath
                        destinationPath = [string]$matchPath
                    }
                }
            }
        }

        foreach ($pattern in @($app.profileDirectories)) {
            foreach ($matchPath in @(Resolve-LocalAppStatePathMatches -RootPath $currentProfilePath -RelativeOrAbsolutePath ([string]$pattern))) {
                $relativeToProfile = $matchPath.Substring($currentProfilePath.TrimEnd('\').Length).TrimStart('\')
                if ([string]::IsNullOrWhiteSpace([string]$relativeToProfile)) { continue }
                $payloadPath = Join-Path ('payload\profile-directories\' + $appId) (Convert-ToLocalAppStateSafeName -Value $relativeToProfile)
                if (Copy-LocalAppStatePayloadItem -SourcePath $matchPath -BuildRoot $buildRoot -RelativePayloadPath $payloadPath) {
                    $manifest.profileDirectories += @{
                        sourcePath = [string]$payloadPath
                        relativeDestinationPath = [string]$relativeToProfile
                    }
                }
            }
        }

        foreach ($pattern in @($app.profileFiles)) {
            foreach ($matchPath in @(Resolve-LocalAppStatePathMatches -RootPath $currentProfilePath -RelativeOrAbsolutePath ([string]$pattern))) {
                $relativeToProfile = $matchPath.Substring($currentProfilePath.TrimEnd('\').Length).TrimStart('\')
                if ([string]::IsNullOrWhiteSpace([string]$relativeToProfile)) { continue }
                $payloadPath = Join-Path ('payload\profile-files\' + $appId) (Convert-ToLocalAppStateSafeName -Value $relativeToProfile)
                if (Copy-LocalAppStatePayloadItem -SourcePath $matchPath -BuildRoot $buildRoot -RelativePayloadPath $payloadPath) {
                    $manifest.profileFiles += @{
                        sourcePath = [string]$payloadPath
                        relativeDestinationPath = [string]$relativeToProfile
                    }
                }
            }
        }

        $itemCount =
            @($manifest.machineDirectories).Count +
            @($manifest.machineFiles).Count +
            @($manifest.profileDirectories).Count +
            @($manifest.profileFiles).Count +
            @($manifest.registryImports).Count

        if ($itemCount -lt 1) {
            Remove-Item -LiteralPath $pluginDirectory -Recurse -Force -ErrorAction SilentlyContinue
            continue
        }

        Set-Content -LiteralPath (Join-Path $buildRoot 'app-state.manifest.json') -Value ($manifest | ConvertTo-Json -Depth 8) -Encoding UTF8
        Remove-Item -LiteralPath $pluginDirectory -Recurse -Force -ErrorAction SilentlyContinue
        Ensure-LocalAppStatePluginDirectory -Path $pluginDirectory
        Compress-Archive -LiteralPath @(Get-ChildItem -LiteralPath $buildRoot -Force | Select-Object -ExpandProperty FullName) -DestinationPath $pluginZipPath -Force
        [void]$pluginPaths.Add($pluginZipPath)
    }

    Remove-Item -LiteralPath $scratchRoot -Recurse -Force -ErrorAction SilentlyContinue

    return [pscustomobject]@{
        PluginCount = [int]$pluginPaths.Count
        PluginPaths = @($pluginPaths.ToArray())
        SkippedApps = @($skippedApps.ToArray())
    }
}

Export-ModuleMember -Function Get-LocalAppStatePluginExportConfig, Export-LocalAppStatePlugins

