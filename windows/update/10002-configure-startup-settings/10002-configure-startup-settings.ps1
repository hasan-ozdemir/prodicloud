$ErrorActionPreference = "Stop"
Write-Host "Update task started: configure-startup-settings"

$taskName = '10002-configure-startup-settings'
$managerUser = "__VM_ADMIN_USER__"
$assistantUser = "__ASSISTANT_USER__"
$assistantPassword = "__ASSISTANT_PASS__"
$hostStartupProfileJsonBase64 = "__HOST_STARTUP_PROFILE_JSON_B64__"
$machineStartupFolder = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp'
$machineStartupApprovedFolderPath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
$machineRunPath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
$machineRunApprovalPath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
$machineRun32Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run32'
$machineRun32ApprovalPath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'
$interactiveHelperPath = 'C:\Windows\Temp\clagnos-interactive-session-helper.ps1'

Import-Module 'C:\Windows\Temp\clagnos-session-environment.psm1' -Force -DisableNameChecking
if (Test-Path -LiteralPath $interactiveHelperPath) {
    . $interactiveHelperPath
}

function Refresh-SessionPath {
    Refresh-ClagnosSessionPath | Out-Null
}

function Invoke-RegQuiet {
    param(
        [string]$Verb,
        [string[]]$Arguments
    )

    $segments = @('reg', [string]$Verb)
    foreach ($argument in @($Arguments)) {
        $segments += ('"{0}"' -f [string]$argument)
    }

    $command = ((@($segments) -join ' ') + ' >nul 2>&1')
    cmd.exe /d /c $command | Out-Null
    return [int]$LASTEXITCODE
}

function Resolve-CommandPath {
    param(
        [string]$CommandName,
        [string[]]$FallbackCandidates = @()
    )

    if (-not [string]::IsNullOrWhiteSpace([string]$CommandName)) {
        $command = Get-Command $CommandName -ErrorAction SilentlyContinue
        if ($command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source)) {
            $candidate = [string]$command.Source
            if ([System.IO.Path]::IsPathRooted($candidate) -and (Test-Path -LiteralPath $candidate)) {
                return [string]$candidate
            }
        }
    }

    foreach ($candidate in @($FallbackCandidates)) {
        if ([string]::IsNullOrWhiteSpace([string]$candidate)) {
            continue
        }

        if (Test-Path -LiteralPath $candidate) {
            return [string]$candidate
        }
    }

    return ""
}

function Resolve-ExecutableUnderDirectory {
    param(
        [string[]]$RootPaths = @(),
        [string]$ExecutableName
    )

    if ([string]::IsNullOrWhiteSpace([string]$ExecutableName)) {
        return ""
    }

    foreach ($rootPath in @($RootPaths)) {
        if ([string]::IsNullOrWhiteSpace([string]$rootPath) -or -not (Test-Path -LiteralPath $rootPath)) {
            continue
        }

        $directCandidate = Join-Path $rootPath $ExecutableName
        if (Test-Path -LiteralPath $directCandidate) {
            return [string]$directCandidate
        }

        $match = Get-ChildItem -LiteralPath $rootPath -Filter $ExecutableName -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName | Select-Object -First 1
        if ($match -and (Test-Path -LiteralPath $match.FullName)) {
            return [string]$match.FullName
        }
    }

    return ""
}

function Resolve-AppPackageExecutablePath {
    param(
        [string]$NameFragment,
        [string[]]$PackageNameHints = @(),
        [string]$ExecutableName
    )

    if ([string]::IsNullOrWhiteSpace([string]$ExecutableName)) {
        return ""
    }

    $allPackages = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
    if (@($allPackages).Count -eq 0) {
        return ""
    }

    $normalizedNameFragment = [string]$NameFragment
    if (-not [string]::IsNullOrWhiteSpace([string]$normalizedNameFragment)) {
        $normalizedNameFragment = $normalizedNameFragment.Trim().ToLowerInvariant()
    }

    $normalizedHints = @(
        @($PackageNameHints) |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object { $_.Trim().ToLowerInvariant() }
    )

    $matchingPackages = @(
        $allPackages | Where-Object {
            $pkgName = [string]$_.Name
            $pkgFamily = [string]$_.PackageFamilyName
            $installLocation = [string]$_.InstallLocation
            if ([string]::IsNullOrWhiteSpace([string]$installLocation)) { return $false }
            if ([string]::IsNullOrWhiteSpace([string]$pkgName) -and [string]::IsNullOrWhiteSpace([string]$pkgFamily)) { return $false }

            $pkgNameLower = $pkgName.ToLowerInvariant()
            $pkgFamilyLower = $pkgFamily.ToLowerInvariant()
            if (-not [string]::IsNullOrWhiteSpace([string]$normalizedNameFragment)) {
                if ($pkgNameLower.Contains($normalizedNameFragment) -or $pkgFamilyLower.Contains($normalizedNameFragment)) {
                    return $true
                }
            }

            foreach ($hint in @($normalizedHints)) {
                if ($pkgNameLower.Contains($hint) -or $pkgFamilyLower.Contains($hint)) {
                    return $true
                }
            }

            return $false
        }
    )

    foreach ($package in @($matchingPackages)) {
        $installLocation = [string]$package.InstallLocation
        if ([string]::IsNullOrWhiteSpace([string]$installLocation)) {
            continue
        }

        $candidate = Join-Path $installLocation $ExecutableName
        if (Test-Path -LiteralPath $candidate) {
            return [string]$candidate
        }

        $match = Get-ChildItem -LiteralPath $installLocation -Filter $ExecutableName -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($match -and (Test-Path -LiteralPath $match.FullName)) {
            return [string]$match.FullName
        }
    }

    return ""
}

function Resolve-StartAppId {
    param([string]$NameFragment)

    if ([string]::IsNullOrWhiteSpace([string]$NameFragment)) {
        return ""
    }

    if (-not (Get-Command Get-StartApps -ErrorAction SilentlyContinue)) {
        return ""
    }

    $normalized = $NameFragment.Trim().ToLowerInvariant()
    $startApps = @(Get-StartApps | Where-Object {
        $nameText = [string]$_.Name
        if ([string]::IsNullOrWhiteSpace([string]$nameText)) {
            return $false
        }

        return $nameText.ToLowerInvariant().Contains($normalized)
    })

    foreach ($entry in @($startApps)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.AppID)) {
            return [string]$entry.AppID
        }
    }

    return ""
}

function Resolve-AppxAppIdFromPackage {
    param(
        [string]$NameFragment,
        [string[]]$PackageNameHints = @()
    )

    $allPackages = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
    if (@($allPackages).Count -eq 0) {
        return ""
    }

    $normalizedNameFragment = [string]$NameFragment
    if (-not [string]::IsNullOrWhiteSpace([string]$normalizedNameFragment)) {
        $normalizedNameFragment = $normalizedNameFragment.Trim().ToLowerInvariant()
    }

    $normalizedHints = @(
        @($PackageNameHints) |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object { $_.Trim().ToLowerInvariant() }
    )

    $matchingPackages = @(
        $allPackages | Where-Object {
            $pkgName = [string]$_.Name
            $pkgFamily = [string]$_.PackageFamilyName
            $installLocation = [string]$_.InstallLocation
            if ([string]::IsNullOrWhiteSpace([string]$installLocation)) { return $false }
            if ([string]::IsNullOrWhiteSpace([string]$pkgName) -and [string]::IsNullOrWhiteSpace([string]$pkgFamily)) { return $false }

            $pkgNameLower = $pkgName.ToLowerInvariant()
            $pkgFamilyLower = $pkgFamily.ToLowerInvariant()
            if (-not [string]::IsNullOrWhiteSpace([string]$normalizedNameFragment)) {
                if ($pkgNameLower.Contains($normalizedNameFragment) -or $pkgFamilyLower.Contains($normalizedNameFragment)) {
                    return $true
                }
            }

            foreach ($hint in @($normalizedHints)) {
                if ($pkgNameLower.Contains($hint) -or $pkgFamilyLower.Contains($hint)) {
                    return $true
                }
            }

            return $false
        }
    )

    foreach ($package in @($matchingPackages)) {
        $manifestPath = Join-Path ([string]$package.InstallLocation) 'AppxManifest.xml'
        if (-not (Test-Path -LiteralPath $manifestPath)) {
            continue
        }

        try {
            [xml]$manifestXml = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop
            $appNodes = @($manifestXml.SelectNodes("//*[local-name()='Application']"))
            foreach ($appNode in @($appNodes)) {
                $applicationId = [string]$appNode.GetAttribute('Id')
                if ([string]::IsNullOrWhiteSpace([string]$applicationId)) {
                    continue
                }

                return ("{0}!{1}" -f [string]$package.PackageFamilyName, $applicationId)
            }
        }
        catch {
        }
    }

    return ""
}

function Resolve-StoreAppId {
    param(
        [string]$NameFragment,
        [string[]]$PackageNameHints = @()
    )

    $startAppsAppId = Resolve-StartAppId -NameFragment $NameFragment
    if (-not [string]::IsNullOrWhiteSpace([string]$startAppsAppId)) {
        return $startAppsAppId
    }

    return (Resolve-AppxAppIdFromPackage -NameFragment $NameFragment -PackageNameHints $PackageNameHints)
}

function Convert-Base64JsonToObjectArray {
    param([string]$Base64Text)

    if ([string]::IsNullOrWhiteSpace([string]$Base64Text)) {
        return @()
    }

    try {
        $bytes = [Convert]::FromBase64String([string]$Base64Text)
        $json = [System.Text.Encoding]::UTF8.GetString($bytes)
        if ([string]::IsNullOrWhiteSpace([string]$json)) {
            return @()
        }

        $parsed = ConvertFrom-Json -InputObject $json -ErrorAction Stop
        return @($parsed | ForEach-Object { $_ })
    }
    catch {
        Write-Warning ("Host startup profile could not be decoded: {0}" -f $_.Exception.Message)
        return @()
    }
}

function Get-StartupProfilePropertyValue {
    param(
        [AllowNull()]$Object,
        [string]$PropertyName,
        [AllowNull()]$DefaultValue = $null
    )

    if ($null -eq $Object -or [string]::IsNullOrWhiteSpace([string]$PropertyName)) {
        return $DefaultValue
    }

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($PropertyName)) {
            return $Object[$PropertyName]
        }

        return $DefaultValue
    }

    if ($Object.PSObject.Properties.Match($PropertyName).Count -gt 0) {
        return $Object.$PropertyName
    }

    return $DefaultValue
}

function Convert-StartupProfileStringArray {
    param([AllowNull()]$InputObject)

    return @(
        @($InputObject) |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
    )
}

function Expand-StartupProfileTemplateValue {
    param(
        [string]$Value,
        [AllowNull()]$UserContext = $null
    )

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return ''
    }

    $expandedValue = [string]$Value
    if ($null -ne $UserContext) {
        $profilePath = [string](Get-StartupProfilePropertyValue -Object $UserContext -PropertyName 'ProfilePath' -DefaultValue '')
        $userName = [string](Get-StartupProfilePropertyValue -Object $UserContext -PropertyName 'UserName' -DefaultValue '')
        if (-not [string]::IsNullOrWhiteSpace([string]$profilePath)) {
            $expandedValue = $expandedValue.Replace('%PROFILEPATH%', [string]$profilePath)
            $expandedValue = $expandedValue.Replace('%USERPROFILE%', [string]$profilePath)
            $expandedValue = $expandedValue.Replace('%LOCALAPPDATA%', (Join-Path $profilePath 'AppData\Local'))
            $expandedValue = $expandedValue.Replace('%APPDATA%', (Join-Path $profilePath 'AppData\Roaming'))
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$userName)) {
            $expandedValue = $expandedValue.Replace('%USERNAME%', [string]$userName)
        }
    }

    return [Environment]::ExpandEnvironmentVariables($expandedValue)
}

function Expand-StartupProfileTemplateValues {
    param(
        [AllowNull()]$InputObject,
        [AllowNull()]$UserContext = $null
    )

    return @(
        Convert-StartupProfileStringArray -InputObject $InputObject |
            ForEach-Object { Expand-StartupProfileTemplateValue -Value ([string]$_) -UserContext $UserContext } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
    )
}

function Resolve-StartupProfileExecutablePath {
    param(
        [AllowNull()]$Launch,
        [AllowNull()]$UserContext = $null
    )

    if ($null -eq $Launch) {
        return ''
    }

    $commandName = [string](Get-StartupProfilePropertyValue -Object $Launch -PropertyName 'CommandName' -DefaultValue '')
    $fallbackCandidates = @(Expand-StartupProfileTemplateValues -InputObject (Get-StartupProfilePropertyValue -Object $Launch -PropertyName 'FallbackCandidates' -DefaultValue @()) -UserContext $UserContext)
    $resolvedPath = Resolve-CommandPath -CommandName $commandName -FallbackCandidates $fallbackCandidates
    if (-not [string]::IsNullOrWhiteSpace([string]$resolvedPath)) {
        return [string]$resolvedPath
    }

    $searchRootPaths = @(Expand-StartupProfileTemplateValues -InputObject (Get-StartupProfilePropertyValue -Object $Launch -PropertyName 'SearchRootPaths' -DefaultValue @()) -UserContext $UserContext)
    $searchExecutableName = [string](Get-StartupProfilePropertyValue -Object $Launch -PropertyName 'SearchExecutableName' -DefaultValue '')
    if (@($searchRootPaths).Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$searchExecutableName)) {
        $resolvedPath = Resolve-ExecutableUnderDirectory -RootPaths $searchRootPaths -ExecutableName $searchExecutableName
        if (-not [string]::IsNullOrWhiteSpace([string]$resolvedPath)) {
            return [string]$resolvedPath
        }
    }

    $packageHints = @(Convert-StartupProfileStringArray -InputObject (Get-StartupProfilePropertyValue -Object $Launch -PropertyName 'ExecutablePackageNameHints' -DefaultValue @()))
    $packageExecutableName = [string](Get-StartupProfilePropertyValue -Object $Launch -PropertyName 'ExecutablePackageExecutableName' -DefaultValue '')
    if (@($packageHints).Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$packageExecutableName)) {
        $nameFragment = [string](Get-StartupProfilePropertyValue -Object $Launch -PropertyName 'ExecutableAppNameFragment' -DefaultValue '')
        if ([string]::IsNullOrWhiteSpace([string]$nameFragment)) {
            $nameFragment = [string](Get-StartupProfilePropertyValue -Object $Launch -PropertyName 'AppNameFragment' -DefaultValue '')
        }

        $resolvedPath = Resolve-AppPackageExecutablePath -NameFragment $nameFragment -PackageNameHints $packageHints -ExecutableName $packageExecutableName
        if (-not [string]::IsNullOrWhiteSpace([string]$resolvedPath)) {
            return [string]$resolvedPath
        }
    }

    return ''
}

function Resolve-StartupProfileStoreAppId {
    param([AllowNull()]$Launch)

    if ($null -eq $Launch) {
        return ''
    }

    $nameFragment = [string](Get-StartupProfilePropertyValue -Object $Launch -PropertyName 'AppNameFragment' -DefaultValue '')
    $packageHints = @(Convert-StartupProfileStringArray -InputObject (Get-StartupProfilePropertyValue -Object $Launch -PropertyName 'PackageNameHints' -DefaultValue @()))
    $appId = Resolve-StoreAppId -NameFragment $nameFragment -PackageNameHints $packageHints
    if (-not [string]::IsNullOrWhiteSpace([string]$appId)) {
        return [string]$appId
    }

    return [string](Get-StartupProfilePropertyValue -Object $Launch -PropertyName 'FallbackAppId' -DefaultValue '')
}

function Resolve-StartupProfileEntryTargetUsers {
    param([AllowNull()]$Entry)

    $targetUsers = @(Convert-StartupProfileStringArray -InputObject (Get-StartupProfilePropertyValue -Object $Entry -PropertyName 'TargetUsers' -DefaultValue @()))
    if (@($targetUsers).Count -lt 1) {
        return @('manager', 'assistant')
    }

    return @(
        $targetUsers |
            ForEach-Object { $_.Trim().ToLowerInvariant() } |
            Where-Object { @('manager', 'assistant') -contains $_ } |
            Select-Object -Unique
    )
}

function Resolve-StartupProfileEntrySpec {
    param(
        [AllowNull()]$Entry,
        [AllowNull()]$UserContext = $null,
        [string]$CmdExe = '',
        [string]$ExplorerExe = ''
    )

    if ($null -eq $Entry) {
        return $null
    }

    $name = [string](Get-StartupProfilePropertyValue -Object $Entry -PropertyName 'Name' -DefaultValue '')
    if ([string]::IsNullOrWhiteSpace([string]$name)) {
        return $null
    }

    $launch = Get-StartupProfilePropertyValue -Object $Entry -PropertyName 'Launch' -DefaultValue $null
    $launchKind = [string](Get-StartupProfilePropertyValue -Object $launch -PropertyName 'Kind' -DefaultValue '')
    $targetPath = ''
    $arguments = ''
    $workingDirectory = ''
    $iconLocation = ''

    switch ($launchKind) {
        'executable' {
            $targetPath = Resolve-StartupProfileExecutablePath -Launch $launch -UserContext $UserContext
            $arguments = [string](Get-StartupProfilePropertyValue -Object $launch -PropertyName 'Arguments' -DefaultValue '')
            if (-not [string]::IsNullOrWhiteSpace([string]$targetPath)) {
                $workingDirectory = Split-Path -Path $targetPath -Parent
                $iconLocation = ("{0},0" -f [string]$targetPath)
            }
        }
        'command-wrapper' {
            $targetPath = Resolve-CommandPath -CommandName ([string](Get-StartupProfilePropertyValue -Object $launch -PropertyName 'WrapperCommandName' -DefaultValue '')) -FallbackCandidates @(Expand-StartupProfileTemplateValues -InputObject (Get-StartupProfilePropertyValue -Object $launch -PropertyName 'WrapperFallbackCandidates' -DefaultValue @()) -UserContext $UserContext)
            $arguments = Expand-StartupProfileTemplateValue -Value ([string](Get-StartupProfilePropertyValue -Object $launch -PropertyName 'WrapperArguments' -DefaultValue '')) -UserContext $UserContext
            $workingDirectory = Expand-StartupProfileTemplateValue -Value '%PROFILEPATH%' -UserContext $UserContext
            $iconTarget = Resolve-CommandPath -CommandName ([string](Get-StartupProfilePropertyValue -Object $launch -PropertyName 'IconCommandName' -DefaultValue '')) -FallbackCandidates @(Expand-StartupProfileTemplateValues -InputObject (Get-StartupProfilePropertyValue -Object $launch -PropertyName 'IconFallbackCandidates' -DefaultValue @()) -UserContext $UserContext)
            if (-not [string]::IsNullOrWhiteSpace([string]$iconTarget)) {
                $iconLocation = ("{0},0" -f [string]$iconTarget)
            }
        }
        'store-app' {
            $appId = Resolve-StartupProfileStoreAppId -Launch $launch
            if (-not [string]::IsNullOrWhiteSpace([string]$appId)) {
                $targetPath = [string]$ExplorerExe
                $arguments = ("shell:AppsFolder\" + [string]$appId)
                $workingDirectory = 'C:\Windows'
                $iconLocation = if (-not [string]::IsNullOrWhiteSpace([string]$ExplorerExe)) { ("{0},0" -f [string]$ExplorerExe) } else { '' }
            }
            else {
                $targetPath = Resolve-StartupProfileExecutablePath -Launch $launch -UserContext $UserContext
                $arguments = Expand-StartupProfileTemplateValue -Value ([string](Get-StartupProfilePropertyValue -Object $launch -PropertyName 'ExecutableArguments' -DefaultValue '')) -UserContext $UserContext
                if (-not [string]::IsNullOrWhiteSpace([string]$targetPath)) {
                    $workingDirectory = Split-Path -Path $targetPath -Parent
                    $iconLocation = ("{0},0" -f [string]$targetPath)
                }
                elseif (-not [string]::IsNullOrWhiteSpace([string](Get-StartupProfilePropertyValue -Object $launch -PropertyName 'UnresolvedWrapperCommandName' -DefaultValue ''))) {
                    $targetPath = Resolve-CommandPath -CommandName ([string](Get-StartupProfilePropertyValue -Object $launch -PropertyName 'UnresolvedWrapperCommandName' -DefaultValue '')) -FallbackCandidates @(Expand-StartupProfileTemplateValues -InputObject (Get-StartupProfilePropertyValue -Object $launch -PropertyName 'UnresolvedWrapperFallbackCandidates' -DefaultValue @()) -UserContext $UserContext)
                    $arguments = Expand-StartupProfileTemplateValue -Value ([string](Get-StartupProfilePropertyValue -Object $launch -PropertyName 'UnresolvedWrapperArguments' -DefaultValue '')) -UserContext $UserContext
                    $workingDirectory = Expand-StartupProfileTemplateValue -Value '%PROFILEPATH%' -UserContext $UserContext
                    if (-not [string]::IsNullOrWhiteSpace([string]$ExplorerExe)) {
                        $iconLocation = ("{0},0" -f [string]$ExplorerExe)
                    }
                }
            }
        }
        default {
            return $null
        }
    }

    return [pscustomobject]@{
        Name = [string]$name
        OwnedNames = @(Convert-StartupProfileStringArray -InputObject (Get-StartupProfilePropertyValue -Object $Entry -PropertyName 'OwnedNames' -DefaultValue @($name)))
        TargetPath = [string]$targetPath
        Arguments = [string]$arguments
        WorkingDirectory = [string]$workingDirectory
        IconLocation = [string]$iconLocation
        ForcedLocation = [pscustomobject]@{
            Scope = [string](Get-StartupProfilePropertyValue -Object $Entry -PropertyName 'Scope' -DefaultValue '')
            EntryType = [string](Get-StartupProfilePropertyValue -Object $Entry -PropertyName 'EntryType' -DefaultValue '')
        }
        EnableLocalMachineCompat = [bool](Get-StartupProfilePropertyValue -Object $Entry -PropertyName 'EnableLocalMachineCompat' -DefaultValue $false)
    }
}

function Get-LocalUserProfileInfo {
    param([string]$UserName)

    if ([string]::IsNullOrWhiteSpace([string]$UserName)) {
        throw "User name is empty."
    }

    $expectedPath = "C:\Users\$UserName"
    $profile = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\*' -ErrorAction SilentlyContinue | Where-Object {
        [string]::Equals([string]$_.ProfileImagePath, $expectedPath, [System.StringComparison]::OrdinalIgnoreCase)
    } | Select-Object -First 1

    if ($null -eq $profile) {
        throw ("Profile was not found for user '{0}'." -f $UserName)
    }

    return [pscustomobject]@{
        UserName = [string]$UserName
        ProfileListKeyName = [string]$profile.PSChildName
        Sid = ([string]$profile.PSChildName -replace '\.bak$', '')
        ProfilePath = [string]$profile.ProfileImagePath
    }
}

function Ensure-LocalUserExists {
    param([string]$UserName)

    if ([string]::IsNullOrWhiteSpace([string]$UserName)) {
        throw "User name is empty."
    }

    $user = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
    if ($null -eq $user) {
        throw ("Local user was not found: {0}" -f $UserName)
    }
}

function Get-LocalUserProfilePath {
    param([string]$UserName)

    try {
        return [string](Get-LocalUserProfileInfo -UserName $UserName).ProfilePath
    }
    catch {
        return ''
    }
}

function Test-PortableProfileHiveReady {
    param([string]$ProfilePath)

    if ([string]::IsNullOrWhiteSpace([string]$ProfilePath) -or -not (Test-Path -LiteralPath $ProfilePath)) {
        return $false
    }

    return (Test-Path -LiteralPath (Join-Path $ProfilePath 'NTUSER.DAT'))
}

function Initialize-MissingUserProfileHive {
    param([string]$ProfilePath)

    if ([string]::IsNullOrWhiteSpace([string]$ProfilePath) -or -not (Test-Path -LiteralPath $ProfilePath)) {
        return $false
    }

    $ntUserPath = Join-Path $ProfilePath 'NTUSER.DAT'
    if (Test-Path -LiteralPath $ntUserPath) {
        return $true
    }

    $defaultProfileHive = 'C:\Users\Default\NTUSER.DAT'
    if (-not (Test-Path -LiteralPath $defaultProfileHive)) {
        return $false
    }

    Copy-Item -LiteralPath $defaultProfileHive -Destination $ntUserPath -Force
    attrib +h $ntUserPath 2>$null | Out-Null
    Write-Host ("autostart-profile-hive-seeded: {0}" -f [string]$ntUserPath)
    return (Test-Path -LiteralPath $ntUserPath)
}

function Wait-ClagnosCondition {
    param(
        [scriptblock]$Condition,
        [int]$TimeoutSeconds = 30,
        [int]$PollMilliseconds = 250
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (& $Condition) {
            return $true
        }

        Start-Sleep -Milliseconds $PollMilliseconds
    }

    return $false
}

function Ensure-UserProfileMaterialized {
    param(
        [string]$UserName,
        [string]$UserPassword
    )

    Ensure-LocalUserExists -UserName $UserName

    $existingProfilePath = Get-LocalUserProfilePath -UserName $UserName
    if (-not [string]::IsNullOrWhiteSpace([string]$existingProfilePath) -and (Test-PortableProfileHiveReady -ProfilePath $existingProfilePath)) {
        Write-Host ("autostart-profile-ready: {0} => {1}" -f [string]$UserName, [string]$existingProfilePath)
        return [string]$existingProfilePath
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$existingProfilePath) -and (Initialize-MissingUserProfileHive -ProfilePath $existingProfilePath)) {
        Write-Host ("autostart-profile-ready: {0} => {1}" -f [string]$UserName, [string]$existingProfilePath)
        return [string]$existingProfilePath
    }

    if ([string]::IsNullOrWhiteSpace([string]$UserPassword)) {
        Write-Host ("autostart-info-skip: {0} => profile materialization skipped because no password is available." -f [string]$UserName)
        return ''
    }
    if (-not (Test-Path -LiteralPath $interactiveHelperPath)) {
        Write-Host ("autostart-info-skip: {0} => profile materialization skipped because the interactive helper is unavailable." -f [string]$UserName)
        return ''
    }

    $materializeTaskName = "{0}-materialize-{1}" -f $taskName, $UserName
    $paths = Get-ClagnosInteractivePaths -TaskName $materializeTaskName
    $workerScript = @'
$ErrorActionPreference = "Stop"
$helperPath = "__HELPER_PATH__"
$resultPath = "__RESULT_PATH__"
$taskName = "__TASK_NAME__"

. $helperPath

$profilePath = [Environment]::GetFolderPath('UserProfile')
Ensure-ClagnosDirectory -Path $profilePath
Ensure-ClagnosDirectory -Path (Join-Path $profilePath 'Desktop')
Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $true -Summary 'User profile materialized.' -Details @($profilePath)
'@

    $workerScript = $workerScript.Replace('__HELPER_PATH__', $interactiveHelperPath)
    $workerScript = $workerScript.Replace('__RESULT_PATH__', [string]$paths.ResultPath)
    $workerScript = $workerScript.Replace('__TASK_NAME__', $materializeTaskName)

    $materializationIssue = ''
    try {
        $null = Invoke-ClagnosInteractiveDesktopAutomation `
            -TaskName $materializeTaskName `
            -RunAsUser $UserName `
            -RunAsPassword $UserPassword `
            -WorkerScriptText $workerScript `
            -WaitTimeoutSeconds 45
    }
    catch {
        $materializationIssue = [string]$_.Exception.Message
    }

    if (-not (Wait-ClagnosCondition -Condition {
        $profilePath = Get-LocalUserProfilePath -UserName $UserName
        if ([string]::IsNullOrWhiteSpace([string]$profilePath)) {
            return $false
        }

        if (Test-PortableProfileHiveReady -ProfilePath $profilePath) {
            return $true
        }

        return (Initialize-MissingUserProfileHive -ProfilePath $profilePath)
    } -TimeoutSeconds 30)) {
        if ([string]::IsNullOrWhiteSpace([string]$materializationIssue)) {
            Write-Host ("autostart-info-skip: {0} => profile materialization did not complete within the bounded wait; startup entries for this user will be skipped until a real sign-in occurs." -f [string]$UserName)
        }
        else {
            Write-Host ("autostart-info-skip: {0} => profile materialization did not complete within the bounded wait; startup entries for this user will be skipped until a real sign-in occurs. {1}" -f [string]$UserName, [string]$materializationIssue)
        }
        return ''
    }

    $profilePath = Get-LocalUserProfilePath -UserName $UserName
    Write-Host ("autostart-profile-materialized: {0} => {1}" -f [string]$UserName, [string]$profilePath)
    return [string]$profilePath
}

function Remove-RegistryMountIfPresent {
    param([string]$MountName)

    if ([string]::IsNullOrWhiteSpace([string]$MountName)) {
        return
    }

    $mountRoot = ("Registry::HKEY_USERS\{0}" -f [string]$MountName)
    if (-not (Test-Path -LiteralPath $mountRoot)) {
        return
    }

    $null = Invoke-RegQuiet -Verb 'unload' -Arguments @(("HKU\{0}" -f $MountName))
}

function Mount-RegistryHive {
    param(
        [string]$MountName,
        [string]$HiveFilePath
    )

    if ([string]::IsNullOrWhiteSpace([string]$MountName)) {
        throw "Registry mount name is empty."
    }
    if ([string]::IsNullOrWhiteSpace([string]$HiveFilePath) -or -not (Test-Path -LiteralPath $HiveFilePath)) {
        throw ("Registry hive file was not found: {0}" -f $HiveFilePath)
    }

    Remove-RegistryMountIfPresent -MountName $MountName
    & reg.exe load ("HKU\{0}" -f $MountName) $HiveFilePath | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw ("reg load failed for HKU\{0} => {1}" -f $MountName, $HiveFilePath)
    }

    return ("Registry::HKEY_USERS\{0}" -f $MountName)
}

function Dismount-RegistryHive {
    param([string]$MountName)

    if ([string]::IsNullOrWhiteSpace([string]$MountName)) {
        return
    }

    try {
        Set-Location -Path 'C:\'
    }
    catch {
    }

    foreach ($attempt in 1..6) {
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        Start-Sleep -Milliseconds 250

        & reg.exe unload ("HKU\{0}" -f $MountName) | Out-Null
        if ($LASTEXITCODE -eq 0) {
            return
        }

        Start-Sleep -Milliseconds 500
    }

    $exitCode = Invoke-RegQuiet -Verb 'unload' -Arguments @(("HKU\{0}" -f $MountName))
    if ($exitCode -eq 0) {
        return
    }

    throw ("reg unload failed for HKU\{0} with exit code {1}" -f $MountName, $exitCode)
}

function Ensure-DirectoryPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace([string]$Path)) {
        throw "Directory path is empty."
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Resolve-RegistryPathInfo {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace([string]$Path)) {
        throw "Registry path is empty."
    }

    $trimmedPath = [string]$Path.Trim()
    if ($trimmedPath.StartsWith('Registry::', [System.StringComparison]::OrdinalIgnoreCase)) {
        $trimmedPath = $trimmedPath.Substring(10)
    }

    if ($trimmedPath.StartsWith('HKEY_LOCAL_MACHINE\', [System.StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{
            Root = 'HKEY_LOCAL_MACHINE'
            SubKeyPath = [string]$trimmedPath.Substring(19)
        }
    }
    if ($trimmedPath.StartsWith('HKEY_CURRENT_USER\', [System.StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{
            Root = 'HKEY_CURRENT_USER'
            SubKeyPath = [string]$trimmedPath.Substring(18)
        }
    }
    if ($trimmedPath.StartsWith('HKEY_USERS\', [System.StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{
            Root = 'HKEY_USERS'
            SubKeyPath = [string]$trimmedPath.Substring(11)
        }
    }
    if ($trimmedPath.StartsWith('HKLM:\', [System.StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{
            Root = 'HKEY_LOCAL_MACHINE'
            SubKeyPath = [string]$trimmedPath.Substring(6)
        }
    }
    if ($trimmedPath.StartsWith('HKCU:\', [System.StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{
            Root = 'HKEY_CURRENT_USER'
            SubKeyPath = [string]$trimmedPath.Substring(6)
        }
    }
    if ($trimmedPath.StartsWith('HKU:\', [System.StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{
            Root = 'HKEY_USERS'
            SubKeyPath = [string]$trimmedPath.Substring(5)
        }
    }

    throw ("Unsupported registry path root: {0}" -f $Path)
}

function Get-RegistryBaseKey {
    param([string]$Root)

    switch -Exact ([string]$Root) {
        'HKEY_LOCAL_MACHINE' {
            return [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Default)
        }
        'HKEY_CURRENT_USER' {
            return [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryView]::Default)
        }
        'HKEY_USERS' {
            return [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::Users, [Microsoft.Win32.RegistryView]::Default)
        }
        default {
            throw ("Unsupported registry root: {0}" -f $Root)
        }
    }
}

function Open-WritableRegistryKey {
    param(
        [string]$Path,
        [bool]$CreateIfMissing = $false
    )

    $pathInfo = Resolve-RegistryPathInfo -Path $Path
    $baseKey = Get-RegistryBaseKey -Root ([string]$pathInfo.Root)
    try {
        $subKeyPath = [string]$pathInfo.SubKeyPath
        if ([string]::IsNullOrWhiteSpace([string]$subKeyPath)) {
            return $baseKey
        }

        $registryKey = $baseKey.OpenSubKey($subKeyPath, $true)
        if (($null -eq $registryKey) -and $CreateIfMissing) {
            $registryKey = $baseKey.CreateSubKey($subKeyPath)
        }

        return $registryKey
    }
    finally {
        if (($null -ne $baseKey) -and ($null -eq $registryKey -or -not [object]::ReferenceEquals($registryKey, $baseKey))) {
            $baseKey.Dispose()
        }
    }
}

function Set-RegistryStringValue {
    param(
        [string]$Path,
        [string]$ValueName,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace([string]$ValueName)) {
        throw "Registry value name is empty."
    }

    $registryKey = Open-WritableRegistryKey -Path $Path -CreateIfMissing $true
    if ($null -eq $registryKey) {
        throw ("Registry key could not be opened for write: {0}" -f $Path)
    }

    try {
        $registryKey.SetValue($ValueName, [string]$Value, [Microsoft.Win32.RegistryValueKind]::String)
    }
    finally {
        $registryKey.Dispose()
    }
}

function Set-RegistryBinaryValue {
    param(
        [string]$Path,
        [string]$ValueName,
        [byte[]]$Value
    )

    if ([string]::IsNullOrWhiteSpace([string]$ValueName)) {
        throw "Registry value name is empty."
    }

    $registryKey = Open-WritableRegistryKey -Path $Path -CreateIfMissing $true
    if ($null -eq $registryKey) {
        throw ("Registry key could not be opened for write: {0}" -f $Path)
    }

    try {
        $registryKey.SetValue($ValueName, [byte[]]@($Value), [Microsoft.Win32.RegistryValueKind]::Binary)
    }
    finally {
        $registryKey.Dispose()
    }
}

function Ensure-RegistryPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace([string]$Path)) {
        throw "Registry path is empty."
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        $registryKey = Open-WritableRegistryKey -Path $Path -CreateIfMissing $true
        if ($null -eq $registryKey) {
            throw ("Registry key could not be created: {0}" -f $Path)
        }
        $registryKey.Dispose()
    }
}

function Remove-RegistryValueIfPresent {
    param(
        [string]$Path,
        [string]$ValueName
    )

    if ([string]::IsNullOrWhiteSpace([string]$Path) -or [string]::IsNullOrWhiteSpace([string]$ValueName)) {
        return
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $property = Get-ItemProperty -Path $Path -Name $ValueName -ErrorAction SilentlyContinue
    if ($null -eq $property) {
        return
    }

    $registryKey = Open-WritableRegistryKey -Path $Path -CreateIfMissing $false
    if ($null -eq $registryKey) {
        return
    }

    try {
        $registryKey.DeleteValue($ValueName, $false)
    }
    finally {
        $registryKey.Dispose()
    }
}

function Get-StartupApprovedStateCode {
    param(
        [string]$Path,
        [string]$ValueName
    )

    if ([string]::IsNullOrWhiteSpace([string]$Path) -or [string]::IsNullOrWhiteSpace([string]$ValueName)) {
        return -1
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        return -1
    }

    $item = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue
    if ($null -eq $item) {
        return -1
    }

    $property = @($item.PSObject.Properties | Where-Object { [string]$_.Name -eq $ValueName } | Select-Object -First 1)
    if (@($property).Count -eq 0 -or $null -eq $property[0].Value) {
        return -1
    }

    $bytes = @($property[0].Value)
    if (@($bytes).Count -eq 0) {
        return -1
    }

    return [int]$bytes[0]
}

function Ensure-StartupApprovedEnabled {
    param(
        [string]$Path,
        [string]$ValueName
    )

    if ([string]::IsNullOrWhiteSpace([string]$Path) -or [string]::IsNullOrWhiteSpace([string]$ValueName)) {
        throw "StartupApproved target is empty."
    }

    Ensure-RegistryPath -Path $Path
    $enabledValue = [byte[]](2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    Set-RegistryBinaryValue -Path $Path -ValueName $ValueName -Value $enabledValue
}

function Get-ShortcutContract {
    param([string]$ShortcutPath)

    if ([string]::IsNullOrWhiteSpace([string]$ShortcutPath) -or -not (Test-Path -LiteralPath $ShortcutPath)) {
        return $null
    }

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    return [pscustomobject]@{
        TargetPath = [string]$shortcut.TargetPath
        Arguments = [string]$shortcut.Arguments
        WorkingDirectory = [string]$shortcut.WorkingDirectory
        IconLocation = [string]$shortcut.IconLocation
    }
}

function Test-ShortcutMatches {
    param(
        [string]$ShortcutPath,
        [string]$TargetPath,
        [string]$Arguments = "",
        [string]$WorkingDirectory = "",
        [string]$IconLocation = ""
    )

    $contract = Get-ShortcutContract -ShortcutPath $ShortcutPath
    if ($null -eq $contract) {
        return $false
    }

    return (
        [string]::Equals([string]$contract.TargetPath, [string]$TargetPath, [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals([string]$contract.Arguments, [string]$Arguments, [System.StringComparison]::Ordinal) -and
        [string]::Equals([string]$contract.WorkingDirectory, [string]$WorkingDirectory, [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals([string]$contract.IconLocation, [string]$IconLocation, [System.StringComparison]::OrdinalIgnoreCase)
    )
}

function New-StartupShortcut {
    param(
        [string]$DirectoryPath,
        [string]$ApprovalPath,
        [string]$Name,
        [string]$TargetPath,
        [string]$Arguments = "",
        [string]$WorkingDirectory = "",
        [string]$IconLocation = "",
        [bool]$IgnoreApprovalWriteFailure = $false
    )

    if ([string]::IsNullOrWhiteSpace([string]$Name)) {
        throw "Startup shortcut name is empty."
    }
    if ([string]::IsNullOrWhiteSpace([string]$TargetPath)) {
        throw "Startup shortcut target is empty."
    }

    Ensure-DirectoryPath -Path $DirectoryPath
    Ensure-RegistryPath -Path $ApprovalPath

    $shortcutPath = Join-Path $DirectoryPath ($Name + '.lnk')
    $tempShortcutPath = Join-Path $DirectoryPath (("clagnos-startup-{0}.lnk" -f [System.Guid]::NewGuid().ToString('N')))
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($tempShortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.Arguments = $Arguments

    $effectiveWorkingDirectory = ""
    if ([string]::IsNullOrWhiteSpace([string]$WorkingDirectory)) {
        $parentPath = Split-Path -Path $TargetPath -Parent
        if (-not [string]::IsNullOrWhiteSpace([string]$parentPath)) {
            $effectiveWorkingDirectory = [string]$parentPath
            $shortcut.WorkingDirectory = $effectiveWorkingDirectory
        }
    }
    else {
        $effectiveWorkingDirectory = [string]$WorkingDirectory
        $shortcut.WorkingDirectory = $effectiveWorkingDirectory
    }

    $effectiveIconLocation = ""
    if ([string]::IsNullOrWhiteSpace([string]$IconLocation)) {
        $effectiveIconLocation = "$TargetPath,0"
        $shortcut.IconLocation = $effectiveIconLocation
    }
    else {
        $effectiveIconLocation = [string]$IconLocation
        $shortcut.IconLocation = $effectiveIconLocation
    }

    $shortcut.Save()
    Move-Item -LiteralPath $tempShortcutPath -Destination $shortcutPath -Force
    $approvalWriteSucceeded = $false
    try {
        Ensure-StartupApprovedEnabled -Path $ApprovalPath -ValueName ($Name + '.lnk')
        $approvalWriteSucceeded = $true
    }
    catch {
        if (-not $IgnoreApprovalWriteFailure) {
            throw
        }

        Write-Host ("autostart-info-skip: {0} => StartupApproved could not be written; shortcut artifact was kept." -f [string]$Name)
    }

    if (-not (Test-Path -LiteralPath $shortcutPath)) {
        throw ("Startup shortcut was not created: {0}" -f $shortcutPath)
    }

    if (-not (Test-ShortcutMatches -ShortcutPath $shortcutPath -TargetPath $TargetPath -Arguments $Arguments -WorkingDirectory $effectiveWorkingDirectory -IconLocation $effectiveIconLocation)) {
        throw ("Startup shortcut validation failed for '{0}'." -f $Name)
    }

    if ($approvalWriteSucceeded) {
        $approvalCode = Get-StartupApprovedStateCode -Path $ApprovalPath -ValueName ($Name + '.lnk')
        if ($approvalCode -ne 2) {
            throw ("StartupApproved validation failed for shortcut '{0}'." -f $Name)
        }
    }
}

function Ensure-StartupShortcut {
    param(
        [string]$DirectoryPath,
        [string]$ApprovalPath,
        [string]$Name,
        [string]$TargetPath,
        [string]$Arguments = "",
        [string]$WorkingDirectory = "",
        [string]$IconLocation = "",
        [bool]$IgnoreApprovalWriteFailure = $false
    )

    $shortcutPath = Join-Path $DirectoryPath ($Name + '.lnk')
    if (Test-ShortcutMatches -ShortcutPath $shortcutPath -TargetPath $TargetPath -Arguments $Arguments -WorkingDirectory $WorkingDirectory -IconLocation $IconLocation) {
        try {
            Ensure-StartupApprovedEnabled -Path $ApprovalPath -ValueName ($Name + '.lnk')
        }
        catch {
            if (-not $IgnoreApprovalWriteFailure) {
                throw
            }

            Write-Host ("autostart-info-skip: {0} => StartupApproved could not be refreshed; existing shortcut artifact was kept." -f [string]$Name)
        }
        Write-Host ("autostart-ok: {0} => already-configured shortcut" -f $Name)
        return
    }

    New-StartupShortcut -DirectoryPath $DirectoryPath -ApprovalPath $ApprovalPath -Name $Name -TargetPath $TargetPath -Arguments $Arguments -WorkingDirectory $WorkingDirectory -IconLocation $IconLocation -IgnoreApprovalWriteFailure:$IgnoreApprovalWriteFailure
    Write-Host ("autostart-ok: {0} => shortcut" -f $Name)
}

function Remove-StartupShortcutIfPresent {
    param(
        [string]$DirectoryPath,
        [string]$ApprovalPath,
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace([string]$DirectoryPath) -or [string]::IsNullOrWhiteSpace([string]$Name)) {
        return
    }

    $shortcutPath = Join-Path $DirectoryPath ($Name + '.lnk')
    if (Test-Path -LiteralPath $shortcutPath) {
        Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction Stop
        Write-Host ("autostart-entry-removed: shortcut => {0}" -f $shortcutPath)
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$ApprovalPath)) {
        Remove-RegistryValueIfPresent -Path $ApprovalPath -ValueName ($Name + '.lnk')
    }
}

function Get-QuotedCommandLine {
    param(
        [string]$TargetPath,
        [string]$Arguments = ""
    )

    if ([string]::IsNullOrWhiteSpace([string]$TargetPath)) {
        throw "Startup command target is empty."
    }

    $quotedTarget = ('"{0}"' -f $TargetPath)
    if ([string]::IsNullOrWhiteSpace([string]$Arguments)) {
        return $quotedTarget
    }

    return ("{0} {1}" -f $quotedTarget, $Arguments).Trim()
}

function Get-CompatRunEntryContract {
    param(
        [string]$TargetPath,
        [string]$Arguments = ""
    )

    if ([string]::IsNullOrWhiteSpace([string]$TargetPath)) {
        throw "Compatibility run target is empty."
    }

    $fallback = [pscustomobject]@{
        TargetPath = [string]$TargetPath
        Arguments = [string]$Arguments
    }

    if ([string]::IsNullOrWhiteSpace([string]$cmdExe) -or -not (Test-Path -LiteralPath $cmdExe)) {
        return $fallback
    }

    $workingDirectory = Split-Path -Path $TargetPath -Parent
    $launchCommand = Get-QuotedCommandLine -TargetPath $TargetPath -Arguments $Arguments
    $wrapperArguments = '/c start ""'
    if (-not [string]::IsNullOrWhiteSpace([string]$workingDirectory)) {
        $wrapperArguments = ('{0} /d "{1}"' -f $wrapperArguments, [string]$workingDirectory)
    }

    $wrapperArguments = ('{0} {1}' -f $wrapperArguments, [string]$launchCommand).Trim()
    return [pscustomobject]@{
        TargetPath = [string]$cmdExe
        Arguments = [string]$wrapperArguments
    }
}

function Resolve-EmbeddedStartupTargetPath {
    param(
        [string]$WrapperTargetPath,
        [string]$Arguments = ''
    )

    $wrapperLeaf = [System.IO.Path]::GetFileName([string]$WrapperTargetPath)
    if ($wrapperLeaf -notin @('cmd.exe', 'powershell.exe', 'pwsh.exe')) {
        return [string]$WrapperTargetPath
    }

    $expandedArguments = [Environment]::ExpandEnvironmentVariables([string]$Arguments)
    if ([string]::IsNullOrWhiteSpace([string]$expandedArguments)) {
        return ''
    }

    foreach ($pattern in @(
        '(?i)if\s+exist\s+"([^"]+)"',
        '(?i)start\s+""\s+"([^"]+)"',
        '(?i)start\s+"?([^"\s]+\.(?:exe|cmd|bat))',
        '(?i)&\s*''([^'']+\.(?:exe|cmd|bat))''',
        '(?i)&\s*"([^"]+\.(?:exe|cmd|bat))"',
        '(?i)(?:^|[&\s])("?[%A-Za-z0-9_:\\ .()-]+\.(?:exe|cmd|bat))'
    )) {
        $match = [regex]::Match($expandedArguments, $pattern)
        if (-not $match.Success) {
            continue
        }

        $candidate = [string]$match.Groups[1].Value.Trim('"', '''', ' ')
        if ([string]::IsNullOrWhiteSpace([string]$candidate)) {
            continue
        }

        $expandedCandidate = [Environment]::ExpandEnvironmentVariables($candidate)
        if (Test-Path -LiteralPath $expandedCandidate) {
            return [string]$expandedCandidate
        }

        $commandName = [System.IO.Path]::GetFileName($expandedCandidate)
        if (-not [string]::IsNullOrWhiteSpace([string]$commandName)) {
            $resolved = Resolve-CommandPath -CommandName $commandName
            if (-not [string]::IsNullOrWhiteSpace([string]$resolved)) {
                return [string]$resolved
            }
        }
    }

    return ''
}

function Test-StartupSpecEligible {
    param([pscustomobject]$Spec)

    if ($null -eq $Spec) {
        return $false
    }

    $targetPath = [string]$Spec.TargetPath
    if ([string]::IsNullOrWhiteSpace([string]$targetPath) -or -not (Test-Path -LiteralPath $targetPath)) {
        return $false
    }

    $targetLeaf = [System.IO.Path]::GetFileName($targetPath)
    if (($targetLeaf -eq 'explorer.exe') -and [string]::IsNullOrWhiteSpace([string]$Spec.Arguments)) {
        return $false
    }

    $wrapperLeaf = $targetLeaf
    if ($wrapperLeaf -in @('cmd.exe', 'powershell.exe', 'pwsh.exe')) {
        $embeddedTargetPath = Resolve-EmbeddedStartupTargetPath -WrapperTargetPath $targetPath -Arguments ([string]$Spec.Arguments)
        if ([string]::IsNullOrWhiteSpace([string]$embeddedTargetPath)) {
            return $false
        }
    }

    return $true
}

function Ensure-RunEntry {
    param(
        [string]$RunPath,
        [string]$ApprovalPath,
        [string]$Name,
        [string]$TargetPath,
        [string]$Arguments = "",
        [bool]$IgnoreApprovalWriteFailure = $false
    )

    if ([string]::IsNullOrWhiteSpace([string]$RunPath) -or [string]::IsNullOrWhiteSpace([string]$ApprovalPath)) {
        throw "Run registry path is empty."
    }
    if ([string]::IsNullOrWhiteSpace([string]$Name)) {
        throw "Run entry name is empty."
    }

    Ensure-RegistryPath -Path $RunPath
    Ensure-RegistryPath -Path $ApprovalPath

    $commandLine = Get-QuotedCommandLine -TargetPath $TargetPath -Arguments $Arguments
    Set-RegistryStringValue -Path $RunPath -ValueName $Name -Value $commandLine
    $approvalWriteSucceeded = $false
    try {
        Ensure-StartupApprovedEnabled -Path $ApprovalPath -ValueName $Name
        $approvalWriteSucceeded = $true
    }
    catch {
        if (-not $IgnoreApprovalWriteFailure) {
            throw
        }

        Write-Host ("autostart-info-skip: {0} => StartupApproved could not be written; run entry was kept." -f [string]$Name)
    }

    $actualValue = [string](Get-ItemProperty -Path $RunPath -Name $Name -ErrorAction Stop).$Name
    if (-not [string]::Equals($actualValue, $commandLine, [System.StringComparison]::Ordinal)) {
        throw ("Run entry validation failed for '{0}'." -f $Name)
    }

    if ($approvalWriteSucceeded) {
        $approvalCode = Get-StartupApprovedStateCode -Path $ApprovalPath -ValueName $Name
        if ($approvalCode -ne 2) {
            throw ("StartupApproved validation failed for run entry '{0}'." -f $Name)
        }
    }

    Write-Host ("autostart-ok: {0} => run-entry" -f $Name)
}

function Remove-RunEntryIfPresent {
    param(
        [string]$RunPath,
        [string]$ApprovalPath,
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace([string]$RunPath) -or [string]::IsNullOrWhiteSpace([string]$Name)) {
        return
    }

    Remove-RegistryValueIfPresent -Path $RunPath -ValueName $Name
    if (-not [string]::IsNullOrWhiteSpace([string]$ApprovalPath)) {
        Remove-RegistryValueIfPresent -Path $ApprovalPath -ValueName $Name
    }
}

function Get-ManagerContext {
    param([string]$UserName)

    $profileInfo = Get-LocalUserProfileInfo -UserName $UserName
    $mountName = ''
    $mainRoot = ("Registry::HKEY_USERS\{0}" -f [string]$profileInfo.Sid)
    if (-not (Test-Path -LiteralPath $mainRoot)) {
        $safeUserName = ([string]$profileInfo.UserName -replace '[^A-Za-z0-9]', '')
        if ([string]::IsNullOrWhiteSpace([string]$safeUserName)) {
            $safeUserName = 'User'
        }

        $mountName = ('Clagnos10002{0}' -f $safeUserName)
        $mainRoot = Mount-RegistryHive -MountName $mountName -HiveFilePath (Join-Path ([string]$profileInfo.ProfilePath) 'NTUSER.DAT')
    }

    return [pscustomobject]@{
        ProfileInfo = $profileInfo
        MainRoot = [string]$mainRoot
        MountName = [string]$mountName
        QualifiedUserName = ('{0}\{1}' -f $env:COMPUTERNAME, [string]$profileInfo.UserName)
        StartupFolder = (Join-Path ([string]$profileInfo.ProfilePath) 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup')
        StartupApprovedStartupFolderPath = ("{0}\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder" -f [string]$mainRoot)
        RunPath = ("{0}\Software\Microsoft\Windows\CurrentVersion\Run" -f [string]$mainRoot)
        RunApprovalPath = ("{0}\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run" -f [string]$mainRoot)
        Run32Path = ("{0}\Software\Microsoft\Windows\CurrentVersion\Run32" -f [string]$mainRoot)
        Run32ApprovalPath = ("{0}\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32" -f [string]$mainRoot)
    }
}

function Get-StartupUserContexts {
    param([string[]]$UserNames = @())

    $contexts = New-Object 'System.Collections.Generic.List[object]'
    $seenLabels = @{}
    foreach ($userNameRaw in @($UserNames)) {
        $userName = if ($null -eq $userNameRaw) { '' } else { [string]$userNameRaw.Trim() }
        if ([string]::IsNullOrWhiteSpace([string]$userName)) {
            continue
        }

        $label = $userName.ToLowerInvariant()
        if ($seenLabels.ContainsKey($label)) {
            continue
        }

        try {
            $context = Get-ManagerContext -UserName $userName
            $context | Add-Member -NotePropertyName 'Label' -NotePropertyValue ([string]$label) -Force
            $context | Add-Member -NotePropertyName 'UserName' -NotePropertyValue ([string]$userName) -Force
            $contexts.Add($context) | Out-Null
            $seenLabels[$label] = $true
        }
        catch {
            Write-Host ("autostart-info-skip: {0} => profile context could not be opened: {1}" -f [string]$userName, $_.Exception.Message)
        }
    }

    return @($contexts.ToArray())
}

function Get-StartupLocationDefinitions {
    param([pscustomobject]$ManagerContext)

    return @(
        [pscustomobject]@{
            Scope = 'CurrentUser'
            EntryType = 'Run'
            Kind = 'Run'
            RunPath = [string]$ManagerContext.RunPath
            ApprovalPath = [string]$ManagerContext.RunApprovalPath
        }
        [pscustomobject]@{
            Scope = 'CurrentUser'
            EntryType = 'Run32'
            Kind = 'Run'
            RunPath = [string]$ManagerContext.Run32Path
            ApprovalPath = [string]$ManagerContext.Run32ApprovalPath
        }
        [pscustomobject]@{
            Scope = 'CurrentUser'
            EntryType = 'StartupFolder'
            Kind = 'StartupFolder'
            DirectoryPath = [string]$ManagerContext.StartupFolder
            ApprovalPath = [string]$ManagerContext.StartupApprovedStartupFolderPath
        }
        [pscustomobject]@{
            Scope = 'LocalMachine'
            EntryType = 'Run'
            Kind = 'Run'
            RunPath = [string]$machineRunPath
            ApprovalPath = [string]$machineRunApprovalPath
        }
        [pscustomobject]@{
            Scope = 'LocalMachine'
            EntryType = 'Run32'
            Kind = 'Run'
            RunPath = [string]$machineRun32Path
            ApprovalPath = [string]$machineRun32ApprovalPath
        }
        [pscustomobject]@{
            Scope = 'LocalMachine'
            EntryType = 'StartupFolder'
            Kind = 'StartupFolder'
            DirectoryPath = [string]$machineStartupFolder
            ApprovalPath = [string]$machineStartupApprovedFolderPath
        }
    )
}

function Get-MachineStartupLocationDefinitions {
    return @(
        [pscustomobject]@{
            Scope = 'LocalMachine'
            EntryType = 'Run'
            Kind = 'Run'
            RunPath = [string]$machineRunPath
            ApprovalPath = [string]$machineRunApprovalPath
        }
        [pscustomobject]@{
            Scope = 'LocalMachine'
            EntryType = 'Run32'
            Kind = 'Run'
            RunPath = [string]$machineRun32Path
            ApprovalPath = [string]$machineRun32ApprovalPath
        }
        [pscustomobject]@{
            Scope = 'LocalMachine'
            EntryType = 'StartupFolder'
            Kind = 'StartupFolder'
            DirectoryPath = [string]$machineStartupFolder
            ApprovalPath = [string]$machineStartupApprovedFolderPath
        }
    )
}

function Resolve-RequestedStartupLocation {
    param(
        [psobject]$ProfileEntry,
        [object[]]$LocationDefinitions
    )

    if ($null -eq $ProfileEntry) {
        return $null
    }

    $scope = if ($ProfileEntry.PSObject.Properties.Match('Scope').Count -gt 0) { [string]$ProfileEntry.Scope } else { '' }
    $entryType = if ($ProfileEntry.PSObject.Properties.Match('EntryType').Count -gt 0) { [string]$ProfileEntry.EntryType } else { '' }

    return @(
        @($LocationDefinitions) |
            Where-Object {
                [string]::Equals([string]$_.Scope, $scope, [System.StringComparison]::OrdinalIgnoreCase) -and
                [string]::Equals([string]$_.EntryType, $entryType, [System.StringComparison]::OrdinalIgnoreCase)
            } |
            Select-Object -First 1
    )[0]
}

function Test-StartupRegistryFallbackException {
    param([System.Exception]$Exception)

    if ($null -eq $Exception) {
        return $false
    }

    $message = [string]$Exception.Message
    if ([string]::IsNullOrWhiteSpace([string]$message)) {
        return $false
    }

    $normalized = $message.ToLowerInvariant()
    return (
        $normalized.Contains('access to the registry key') -or
        $normalized.Contains('requested registry access is not allowed') -or
        $normalized.Contains('is denied')
    )
}

function Get-CompatStartupEntryName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace([string]$Name)) {
        return ''
    }

    return ('Clagnos Startup Compat - {0}' -f $Name)
}

function Remove-CompatScheduledTaskIfPresent {
    param([string]$TaskName)

    if ([string]::IsNullOrWhiteSpace([string]$TaskName)) {
        return
    }

    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($null -eq $task) {
        return
    }

    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
    Write-Host ("autostart-entry-removed: scheduled-task => {0}" -f [string]$TaskName)
}

function Ensure-CompatScheduledTask {
    param(
        [string]$TaskName,
        [pscustomobject]$ManagerContext,
        [string]$TargetPath,
        [string]$Arguments = ""
    )

    if ([string]::IsNullOrWhiteSpace([string]$TaskName)) {
        throw "Compatibility startup task name is empty."
    }
    if ($null -eq $ManagerContext -or [string]::IsNullOrWhiteSpace([string]$ManagerContext.QualifiedUserName)) {
        throw "Manager context is missing the qualified user name for compatibility startup."
    }

    $compatContract = Get-CompatRunEntryContract -TargetPath $TargetPath -Arguments $Arguments
    $action = New-ScheduledTaskAction -Execute ([string]$compatContract.TargetPath) -Argument ([string]$compatContract.Arguments)
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User ([string]$ManagerContext.QualifiedUserName)
    $principal = New-ScheduledTaskPrincipal -UserId ([string]$ManagerContext.QualifiedUserName) -LogonType Interactive -RunLevel Highest
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null

    $registeredTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($null -eq $registeredTask) {
        throw ("Compatibility startup task registration failed for '{0}'." -f [string]$TaskName)
    }

    Write-Host ("autostart-ok: {0} => scheduled-task" -f [string]$TaskName)
}

function Resolve-StartupLocationDefinition {
    param(
        [object[]]$LocationDefinitions,
        [string]$Scope,
        [string]$EntryType
    )

    return @(
        @($LocationDefinitions) |
            Where-Object {
                [string]::Equals([string]$_.Scope, [string]$Scope, [System.StringComparison]::OrdinalIgnoreCase) -and
                [string]::Equals([string]$_.EntryType, [string]$EntryType, [System.StringComparison]::OrdinalIgnoreCase)
            } |
            Select-Object -First 1
    )[0]
}

function Clear-OwnedStartupArtifacts {
    param(
        [psobject]$Spec,
        [object[]]$LocationDefinitions
    )

    foreach ($ownedName in @($Spec.OwnedNames)) {
        foreach ($location in @($LocationDefinitions)) {
            if ([string]::Equals([string]$location.Kind, 'Run', [System.StringComparison]::OrdinalIgnoreCase)) {
                Remove-RunEntryIfPresent -RunPath ([string]$location.RunPath) -ApprovalPath ([string]$location.ApprovalPath) -Name ([string]$ownedName)
            }
            else {
                Remove-StartupShortcutIfPresent -DirectoryPath ([string]$location.DirectoryPath) -ApprovalPath ([string]$location.ApprovalPath) -Name ([string]$ownedName)
            }
        }
    }

    $compatEntryName = Get-CompatStartupEntryName -Name ([string]$Spec.Name)
    if (-not [string]::IsNullOrWhiteSpace([string]$compatEntryName)) {
        $currentUserRunLocation = Resolve-StartupLocationDefinition -LocationDefinitions $LocationDefinitions -Scope 'CurrentUser' -EntryType 'Run'
        if ($null -ne $currentUserRunLocation) {
            Remove-RunEntryIfPresent -RunPath ([string]$currentUserRunLocation.RunPath) -ApprovalPath ([string]$currentUserRunLocation.ApprovalPath) -Name $compatEntryName
        }

        $currentUserStartupLocation = Resolve-StartupLocationDefinition -LocationDefinitions $LocationDefinitions -Scope 'CurrentUser' -EntryType 'StartupFolder'
        if ($null -ne $currentUserStartupLocation) {
            Remove-StartupShortcutIfPresent -DirectoryPath ([string]$currentUserStartupLocation.DirectoryPath) -ApprovalPath ([string]$currentUserStartupLocation.ApprovalPath) -Name $compatEntryName
        }

        Remove-CompatScheduledTaskIfPresent -TaskName $compatEntryName
    }
}

function Ensure-AppStartupLocation {
    param(
        [psobject]$Spec,
        [psobject]$ProfileEntry,
        [object[]]$LocationDefinitions,
        [pscustomobject]$ManagerContext,
        [string]$LogLabel = ""
    )

    $targetPath = [string]$Spec.TargetPath
    if (-not (Test-StartupSpecEligible -Spec ([pscustomobject]$Spec))) {
        $label = if ([string]::IsNullOrWhiteSpace([string]$LogLabel)) { [string]$Spec.Name } else { [string]$LogLabel }
        Write-Host ("autostart-info-skip: {0} => target or embedded startup command could not be resolved." -f [string]$label)
        return $false
    }

    $requestedLocation = Resolve-RequestedStartupLocation -ProfileEntry $ProfileEntry -LocationDefinitions $LocationDefinitions
    if ($null -eq $requestedLocation) {
        $label = if ([string]::IsNullOrWhiteSpace([string]$LogLabel)) { [string]$Spec.Name } else { [string]$LogLabel }
        Write-Host ("autostart-info-skip: {0} => unsupported startup method '{1}/{2}'." -f [string]$label, [string]$ProfileEntry.Scope, [string]$ProfileEntry.EntryType)
        return $false
    }

    if (
        [string]::Equals([string]$requestedLocation.Scope, 'CurrentUser', [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals([string]$requestedLocation.EntryType, 'Run', [System.StringComparison]::OrdinalIgnoreCase) -and
        $null -ne $ManagerContext -and
        -not [string]::IsNullOrWhiteSpace([string]$ManagerContext.Label) -and
        -not [string]::Equals([string]$ManagerContext.Label, 'manager', [System.StringComparison]::OrdinalIgnoreCase)
    ) {
        $portableCurrentUserLocation = Resolve-StartupLocationDefinition -LocationDefinitions $LocationDefinitions -Scope 'CurrentUser' -EntryType 'StartupFolder'
        if ($null -ne $portableCurrentUserLocation) {
            $requestedLocation = $portableCurrentUserLocation
        }
    }

    $enableLocalMachineCompat = $true
    if ($Spec.PSObject.Properties.Match('EnableLocalMachineCompat').Count -gt 0) {
        $enableLocalMachineCompat = [bool]$Spec.EnableLocalMachineCompat
    }
    $ignoreApprovalWriteFailure = ($null -ne $ManagerContext -and -not [string]::IsNullOrWhiteSpace([string]$ManagerContext.MountName))

    if ([string]::Equals([string]$requestedLocation.Kind, 'Run', [System.StringComparison]::OrdinalIgnoreCase)) {
        try {
            Ensure-RunEntry -RunPath ([string]$requestedLocation.RunPath) -ApprovalPath ([string]$requestedLocation.ApprovalPath) -Name ([string]$Spec.Name) -TargetPath $targetPath -Arguments ([string]$Spec.Arguments) -IgnoreApprovalWriteFailure:$ignoreApprovalWriteFailure
        }
        catch {
            $fallbackLocation = $null
            if (
                [string]::Equals([string]$requestedLocation.Scope, 'CurrentUser', [System.StringComparison]::OrdinalIgnoreCase) -and
                (Test-StartupRegistryFallbackException -Exception $_.Exception)
            ) {
                $fallbackLocation = Resolve-StartupLocationDefinition -LocationDefinitions $LocationDefinitions -Scope 'CurrentUser' -EntryType 'StartupFolder'
            }

            if ($null -eq $fallbackLocation) {
                throw
            }

            Write-Host ("autostart-fallback: {0} => CurrentUser/Run denied; using CurrentUser/StartupFolder" -f [string]$Spec.Name)
            Ensure-StartupShortcut -DirectoryPath ([string]$fallbackLocation.DirectoryPath) -ApprovalPath ([string]$fallbackLocation.ApprovalPath) -Name ([string]$Spec.Name) -TargetPath $targetPath -Arguments ([string]$Spec.Arguments) -WorkingDirectory ([string]$Spec.WorkingDirectory) -IconLocation ([string]$Spec.IconLocation) -IgnoreApprovalWriteFailure:$true
            Write-Host ("autostart-method => {0} => CurrentUser/StartupFolder" -f [string]$Spec.Name)
            return $true
        }

        if (
            [string]::Equals([string]$requestedLocation.Scope, 'LocalMachine', [System.StringComparison]::OrdinalIgnoreCase) -and
            $enableLocalMachineCompat
        ) {
            $compatEntryName = Get-CompatStartupEntryName -Name ([string]$Spec.Name)
            Ensure-CompatScheduledTask -TaskName $compatEntryName -ManagerContext $ManagerContext -TargetPath $targetPath -Arguments ([string]$Spec.Arguments)
            Write-Host ("autostart-compat => {0} => ScheduledTask/AtLogOn" -f [string]$Spec.Name)
        }
        Write-Host ("autostart-method => {0} => {1}/{2}" -f [string]$Spec.Name, [string]$requestedLocation.Scope, [string]$requestedLocation.EntryType)
        return $true
    }

    Ensure-StartupShortcut -DirectoryPath ([string]$requestedLocation.DirectoryPath) -ApprovalPath ([string]$requestedLocation.ApprovalPath) -Name ([string]$Spec.Name) -TargetPath $targetPath -Arguments ([string]$Spec.Arguments) -WorkingDirectory ([string]$Spec.WorkingDirectory) -IconLocation ([string]$Spec.IconLocation) -IgnoreApprovalWriteFailure:$ignoreApprovalWriteFailure
    Write-Host ("autostart-method => {0} => {1}/{2}" -f [string]$Spec.Name, [string]$requestedLocation.Scope, [string]$requestedLocation.EntryType)
    return $true
}

Refresh-SessionPath

$cmdExe = Resolve-CommandPath -CommandName "cmd.exe" -FallbackCandidates @("C:\Windows\System32\cmd.exe")
$explorerExe = Resolve-CommandPath -CommandName "explorer.exe" -FallbackCandidates @("C:\Windows\explorer.exe")
$hostStartupProfile = @(Convert-Base64JsonToObjectArray -Base64Text $hostStartupProfileJsonBase64)
$hostStartupProfileByKey = @{}
foreach ($entry in @($hostStartupProfile)) {
    if ($null -eq $entry) {
        continue
    }

    $key = if ($entry.PSObject.Properties.Match('Key').Count -gt 0) { [string]$entry.Key } else { '' }
    if ([string]::IsNullOrWhiteSpace([string]$key) -or $hostStartupProfileByKey.ContainsKey($key)) {
        continue
    }

    $hostStartupProfileByKey[$key] = $entry
}

$hostStartupSummary = @(
    @($hostStartupProfileByKey.Keys | Sort-Object) |
        ForEach-Object {
            $entry = $hostStartupProfileByKey[[string]$_]
            ("{0}:{1}:{2}" -f [string]$_, [string]$entry.EntryType, [string]$entry.Scope)
        }
)
if (@($hostStartupSummary).Count -eq 0) {
    Write-Host 'host-startup-profile => none'
}
else {
    Write-Host ("host-startup-profile => {0}" -f ($hostStartupSummary -join ', '))
}

$managedStartupSummary = @(
    @($hostStartupProfile) |
        ForEach-Object {
            $key = [string](Get-StartupProfilePropertyValue -Object $_ -PropertyName 'Key' -DefaultValue '')
            $entryType = [string](Get-StartupProfilePropertyValue -Object $_ -PropertyName 'EntryType' -DefaultValue '')
            $scope = [string](Get-StartupProfilePropertyValue -Object $_ -PropertyName 'Scope' -DefaultValue '')
            if ([string]::IsNullOrWhiteSpace([string]$key)) {
                return
            }

            ("{0}:{1}:{2}" -f [string]$key, [string]$entryType, [string]$scope)
        } |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
)
if (@($managedStartupSummary).Count -eq 0) {
    Write-Host 'managed-startup-profile => none'
}
else {
    Write-Host ("managed-startup-profile => {0}" -f ($managedStartupSummary -join ', '))
}

$userContexts = @()
try {
    [void](Ensure-UserProfileMaterialized -UserName $assistantUser -UserPassword $assistantPassword)
    $userContexts = @(Get-StartupUserContexts -UserNames @($managerUser, $assistantUser))
    $machineLocationDefinitions = @(Get-MachineStartupLocationDefinitions)
    $userContextMap = @{}
    foreach ($context in @($userContexts)) {
        if ($null -eq $context) {
            continue
        }

        $label = [string](Get-StartupProfilePropertyValue -Object $context -PropertyName 'Label' -DefaultValue '')
        if (-not [string]::IsNullOrWhiteSpace([string]$label)) {
            $userContextMap[$label] = $context
        }
    }

    foreach ($profileEntry in @($hostStartupProfile)) {
        if ($null -eq $profileEntry) {
            continue
        }

        $specName = [string](Get-StartupProfilePropertyValue -Object $profileEntry -PropertyName 'Name' -DefaultValue '')
        $entryScope = [string](Get-StartupProfilePropertyValue -Object $profileEntry -PropertyName 'Scope' -DefaultValue '')
        $entryType = [string](Get-StartupProfilePropertyValue -Object $profileEntry -PropertyName 'EntryType' -DefaultValue '')
        if ([string]::IsNullOrWhiteSpace([string]$specName) -or [string]::IsNullOrWhiteSpace([string]$entryScope) -or [string]::IsNullOrWhiteSpace([string]$entryType)) {
            continue
        }

        if ([string]::Equals([string]$entryScope, 'LocalMachine', [System.StringComparison]::OrdinalIgnoreCase)) {
            $resolvedSpec = Resolve-StartupProfileEntrySpec -Entry $profileEntry -UserContext $null -CmdExe $cmdExe -ExplorerExe $explorerExe
            if ($null -eq $resolvedSpec -or -not (Test-StartupSpecEligible -Spec $resolvedSpec)) {
                Write-Host ("autostart-info-skip: {0} => target could not be resolved on the VM." -f [string]$specName)
                continue
            }

            Clear-OwnedStartupArtifacts -Spec $resolvedSpec -LocationDefinitions $machineLocationDefinitions
            Write-Host ("autostart-managed => {0} => {1}/{2}" -f [string]$resolvedSpec.Name, [string]$entryScope, [string]$entryType)
            [void](Ensure-AppStartupLocation -Spec $resolvedSpec -ProfileEntry ([pscustomobject]@{ Scope = $entryScope; EntryType = $entryType }) -LocationDefinitions $machineLocationDefinitions -ManagerContext $null -LogLabel ([string]$resolvedSpec.Name))
            continue
        }

        foreach ($targetUserLabel in @(Resolve-StartupProfileEntryTargetUsers -Entry $profileEntry)) {
            if (-not $userContextMap.ContainsKey([string]$targetUserLabel)) {
                Write-Host ("autostart-info-skip: {0} => startup user context '{1}' is unavailable." -f [string]$specName, [string]$targetUserLabel)
                continue
            }

            $userContext = $userContextMap[[string]$targetUserLabel]
            $locationDefinitions = @(Get-StartupLocationDefinitions -ManagerContext $userContext)
            $resolvedSpec = Resolve-StartupProfileEntrySpec -Entry $profileEntry -UserContext $userContext.ProfileInfo -CmdExe $cmdExe -ExplorerExe $explorerExe
            if ($null -eq $resolvedSpec -or -not (Test-StartupSpecEligible -Spec $resolvedSpec)) {
                Write-Host ("autostart-info-skip: {0}/{1} => target could not be resolved on the VM." -f [string]$specName, [string]$targetUserLabel)
                continue
            }

            Clear-OwnedStartupArtifacts -Spec $resolvedSpec -LocationDefinitions $locationDefinitions
            Write-Host ("autostart-managed => {0}/{1} => {2}/{3}" -f [string]$resolvedSpec.Name, [string]$targetUserLabel, [string]$entryScope, [string]$entryType)
            [void](Ensure-AppStartupLocation -Spec $resolvedSpec -ProfileEntry ([pscustomobject]@{ Scope = $entryScope; EntryType = $entryType }) -LocationDefinitions $locationDefinitions -ManagerContext $userContext -LogLabel ("{0}/{1}" -f [string]$resolvedSpec.Name, [string]$targetUserLabel))
        }
    }
}
finally {
    foreach ($context in @($userContexts)) {
        if ($null -eq $context) {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace([string](Get-StartupProfilePropertyValue -Object $context -PropertyName 'MountName' -DefaultValue ''))) {
            Dismount-RegistryHive -MountName ([string]$context.MountName)
        }
    }
}

Write-Host 'configure-startup-settings-completed'
Write-Host "Update task completed: configure-startup-settings"

