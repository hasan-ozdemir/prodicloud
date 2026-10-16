$ErrorActionPreference = "Stop"
Write-Host "Update task started: create-public-desktop-shortcuts"

$companyName = "__SELECTED_COMPANY_NAME__"
$companyWebAddress = "__SELECTED_COMPANY_WEB_ADDRESS__"
$companyEmailAddress = "__SELECTED_COMPANY_EMAIL_ADDRESS__"
$employeeEmailAddress = "__SELECTED_EMPLOYEE_EMAIL_ADDRESS__"
$employeeFullName = "__SELECTED_EMPLOYEE_FULL_NAME__"
$shortcutSocialBusinessLinkedInUrl = "__WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_LINKEDIN_URL__"
$shortcutSocialBusinessYouTubeUrl = "__WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_YOUTUBE_URL__"
$shortcutSocialBusinessGitHubUrl = "__WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_GITHUB_URL__"
$shortcutSocialBusinessTikTokUrl = "__WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_TIKTOK_URL__"
$shortcutSocialBusinessInstagramUrl = "__WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_INSTAGRAM_URL__"
$shortcutSocialBusinessFacebookUrl = "__WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_FACEBOOK_URL__"
$shortcutSocialBusinessXUrl = "__WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_X_URL__"
$shortcutSocialBusinessSnapchatUrl = "__WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_SNAPCHAT_URL__"
$shortcutSocialBusinessNextSosyalUrl = "__WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_NEXTSOSYAL_URL__"
$shortcutSocialPersonalLinkedInUrl = "__WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_LINKEDIN_URL__"
$shortcutSocialPersonalYouTubeUrl = "__WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_YOUTUBE_URL__"
$shortcutSocialPersonalGitHubUrl = "__WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_GITHUB_URL__"
$shortcutSocialPersonalTikTokUrl = "__WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_TIKTOK_URL__"
$shortcutSocialPersonalInstagramUrl = "__WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_INSTAGRAM_URL__"
$shortcutSocialPersonalFacebookUrl = "__WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_FACEBOOK_URL__"
$shortcutSocialPersonalXUrl = "__WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_X_URL__"
$shortcutWebBusinessHomeUrl = "__WIN_PUBLIC_SHORTCUT_WEB_BUSINESS_HOME_URL__"
$shortcutWebBusinessBlogUrl = "__WIN_PUBLIC_SHORTCUT_WEB_BUSINESS_BLOG_URL__"
$managerUser = "__VM_ADMIN_USER__"
$managerPassword = "__VM_ADMIN_PASS__"
$assistantUser = "__ASSISTANT_USER__"
$assistantPassword = "__ASSISTANT_PASS__"
$publicDesktop = "C:\Users\Public\Desktop"
$publicChromeUserDataDir = "C:\Users\Public\AppData\Local\Google\Chrome\UserData"
$publicEdgeUserDataDir = "C:\Users\Public\AppData\Local\Microsoft\msedge\UserData"
$beMyEyesStoreProductId = "9MSW46LTDWGF"
$beMyEyesStoreUri = "ms-windows-store://pdp/?ProductId=9MSW46LTDWGF"
$codexAppFallbackPath = ""
$whatsAppFallbackPath = ""
$iCloudFallbackPath = ""
$shortcutRunAsAdminFlag = 0x00002000
$unresolvedCompanyNameToken = ('__' + 'SELECTED_COMPANY_NAME' + '__')
$unresolvedCompanyWebAddressToken = ('__' + 'SELECTED_COMPANY_WEB_ADDRESS' + '__')
$unresolvedCompanyEmailAddressToken = ('__' + 'SELECTED_COMPANY_EMAIL_ADDRESS' + '__')
$unresolvedEmployeeEmailAddressToken = ('__' + 'SELECTED_EMPLOYEE_EMAIL_ADDRESS' + '__')
$unresolvedEmployeeFullNameToken = ('__' + 'SELECTED_EMPLOYEE_FULL_NAME' + '__')
$storeHelperPath = 'C:\Windows\Temp\clagnos-store-install-state.psm1'
$launcherHelperPath = 'C:\Windows\Temp\clagnos-shortcut-launcher.psm1'
$interactiveHelperPath = 'C:\Windows\Temp\clagnos-interactive-session-helper.ps1'
# Use the direct .lnk target+arguments form until the combined invocation exceeds
# the practical shortcut-length ceiling; only then emit a managed launcher script.
$managedShortcutInvocationThreshold = 259

if (Test-Path -LiteralPath $storeHelperPath) {
    Import-Module $storeHelperPath -Force -DisableNameChecking
}
if (Test-Path -LiteralPath $launcherHelperPath) {
    Import-Module $launcherHelperPath -Force -DisableNameChecking
}
if (Test-Path -LiteralPath $interactiveHelperPath) {
    . $interactiveHelperPath
}

function ConvertFrom-UnicodeCodePoints {
    param([int[]]$CodePoints)

    if ($null -eq $CodePoints -or @($CodePoints).Count -eq 0) {
        return ''
    }

    $builder = New-Object System.Text.StringBuilder
    foreach ($codePoint in @($CodePoints)) {
        [void]$builder.Append([char][int]$codePoint)
    }

    return $builder.ToString()
}

function Test-InvalidCompanyName {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return $true
    }

    $trimmed = $Value.Trim()
    if ([string]::Equals($trimmed, $unresolvedCompanyNameToken, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    if ([string]::Equals($trimmed, "SELECTED_COMPANY_NAME", [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    if ($trimmed.StartsWith("__", [System.StringComparison]::Ordinal) -and $trimmed.EndsWith("__", [System.StringComparison]::Ordinal)) {
        return $true
    }

    return $false
}

function Test-InvalidCompanyWebAddress {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return $true
    }

    $trimmed = $Value.Trim()
    if ([string]::Equals($trimmed, $unresolvedCompanyWebAddressToken, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    if ([string]::Equals($trimmed, 'SELECTED_COMPANY_WEB_ADDRESS', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    if ($trimmed.StartsWith('__', [System.StringComparison]::Ordinal) -and $trimmed.EndsWith('__', [System.StringComparison]::Ordinal)) {
        return $true
    }

    return (-not ($trimmed -match '^https?://'))
}

function Test-InvalidEmployeeEmailAddress {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return $true
    }

    $trimmed = $Value.Trim()
    if ([string]::Equals($trimmed, $unresolvedEmployeeEmailAddressToken, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    if ([string]::Equals($trimmed, 'SELECTED_EMPLOYEE_EMAIL_ADDRESS', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    if ($trimmed.StartsWith('__', [System.StringComparison]::Ordinal) -and $trimmed.EndsWith('__', [System.StringComparison]::Ordinal)) {
        return $true
    }
    if (($trimmed -split '@').Count -lt 2) {
        return $true
    }

    return $false
}

function Test-InvalidEmployeeFullName {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return $true
    }

    $trimmed = $Value.Trim()
    if ([string]::Equals($trimmed, $unresolvedEmployeeFullNameToken, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    if ([string]::Equals($trimmed, 'SELECTED_EMPLOYEE_FULL_NAME', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    if ($trimmed.StartsWith('__', [System.StringComparison]::Ordinal) -and $trimmed.EndsWith('__', [System.StringComparison]::Ordinal)) {
        return $true
    }

    return $false
}

function Get-EmployeeEmailBaseName {
    param([string]$EmailAddress)

    if (Test-InvalidEmployeeEmailAddress -Value $EmailAddress) {
        throw "SELECTED_EMPLOYEE_EMAIL_ADDRESS must be a non-placeholder email address before running 10002-create-public-desktop-shortcuts."
    }

    return [string]($EmailAddress.Trim().Split('@')[0])
}

function ConvertTo-LowerInvariantText {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return ""
    }

    return [string]$Value.Trim().ToLowerInvariant()
}

function ConvertTo-TitleCaseShortcutText {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return ""
    }

    $textInfo = [System.Globalization.CultureInfo]::InvariantCulture.TextInfo
    return [string]$textInfo.ToTitleCase($Value.Trim().ToLowerInvariant())
}

function Normalize-ShortcutUrl {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return ''
    }

    $trimmed = [string]$Value.Trim()
    return $trimmed.TrimEnd('/')
}

function Resolve-OptionalShortcutUrl {
    param(
        [string]$ConfiguredValue,
        [string]$FallbackUrl
    )

    $normalizedFallback = Normalize-ShortcutUrl -Value $FallbackUrl
    if ([string]::IsNullOrWhiteSpace([string]$ConfiguredValue)) {
        return [string]$normalizedFallback
    }

    $trimmed = [string]$ConfiguredValue.Trim()
    if ($trimmed.StartsWith('__', [System.StringComparison]::Ordinal) -and $trimmed.EndsWith('__', [System.StringComparison]::Ordinal)) {
        return [string]$normalizedFallback
    }
    if (-not ($trimmed -match '^https?://')) {
        return [string]$normalizedFallback
    }

    return (Normalize-ShortcutUrl -Value $trimmed)
}

if (Test-InvalidCompanyName -Value $companyName) {
    throw "SELECTED_COMPANY_NAME is required for the Windows business public desktop shortcut flow. Set SELECTED_COMPANY_NAME in clagnos.env before running 10002-create-public-desktop-shortcuts."
}
if (Test-InvalidEmployeeEmailAddress -Value $employeeEmailAddress) {
    throw "SELECTED_EMPLOYEE_EMAIL_ADDRESS is required for the Windows public desktop shortcut flow. Set SELECTED_EMPLOYEE_EMAIL_ADDRESS in clagnos.env before running 10002-create-public-desktop-shortcuts."
}
if (Test-InvalidEmployeeFullName -Value $employeeFullName) {
    throw "SELECTED_EMPLOYEE_FULL_NAME is required for the Windows public desktop shortcut flow. Set SELECTED_EMPLOYEE_FULL_NAME in clagnos.env before running 10002-create-public-desktop-shortcuts."
}

$companyName = $companyName.Trim()
$companyWebAddress = $companyWebAddress.Trim()
$companyEmailAddress = [string]$companyEmailAddress.Trim()
$employeeEmailAddress = $employeeEmailAddress.Trim()
$employeeFullName = $employeeFullName.Trim()
$employeeEmailBaseName = Get-EmployeeEmailBaseName -EmailAddress $employeeEmailAddress
$companyDisplayName = ConvertTo-TitleCaseShortcutText -Value $companyName
$companyChromeProfileDirectory = ConvertTo-LowerInvariantText -Value $companyName
$employeeEmailBaseName = ConvertTo-LowerInvariantText -Value $employeeEmailBaseName
$defaultBusinessWebRootUrl = Resolve-OptionalShortcutUrl -ConfiguredValue $companyWebAddress -FallbackUrl 'https://www.example.com'
$companyWebRootUrl = Resolve-OptionalShortcutUrl -ConfiguredValue $shortcutWebBusinessHomeUrl -FallbackUrl $defaultBusinessWebRootUrl
$companyBlogUrl = Resolve-OptionalShortcutUrl -ConfiguredValue $shortcutWebBusinessBlogUrl -FallbackUrl ($companyWebRootUrl + '/blog')
$socialBusinessLinkedInUrl = Resolve-OptionalShortcutUrl -ConfiguredValue $shortcutSocialBusinessLinkedInUrl -FallbackUrl 'https://www.linkedin.com/company/'
$socialPersonalLinkedInUrl = Resolve-OptionalShortcutUrl -ConfiguredValue $shortcutSocialPersonalLinkedInUrl -FallbackUrl 'https://www.linkedin.com/'
$socialBusinessYouTubeUrl = Resolve-OptionalShortcutUrl -ConfiguredValue $shortcutSocialBusinessYouTubeUrl -FallbackUrl 'https://www.youtube.com/'
$socialPersonalYouTubeUrl = Resolve-OptionalShortcutUrl -ConfiguredValue $shortcutSocialPersonalYouTubeUrl -FallbackUrl 'https://www.youtube.com/'
$socialBusinessGitHubUrl = Resolve-OptionalShortcutUrl -ConfiguredValue $shortcutSocialBusinessGitHubUrl -FallbackUrl 'https://github.com/'
$socialPersonalGitHubUrl = Resolve-OptionalShortcutUrl -ConfiguredValue $shortcutSocialPersonalGitHubUrl -FallbackUrl 'https://github.com/'
$socialBusinessTikTokUrl = Resolve-OptionalShortcutUrl -ConfiguredValue $shortcutSocialBusinessTikTokUrl -FallbackUrl 'https://www.tiktok.com/'
$socialPersonalTikTokUrl = Resolve-OptionalShortcutUrl -ConfiguredValue $shortcutSocialPersonalTikTokUrl -FallbackUrl 'https://www.tiktok.com/'
$socialBusinessInstagramUrl = Resolve-OptionalShortcutUrl -ConfiguredValue $shortcutSocialBusinessInstagramUrl -FallbackUrl 'https://instagram.com/'
$socialPersonalInstagramUrl = Resolve-OptionalShortcutUrl -ConfiguredValue $shortcutSocialPersonalInstagramUrl -FallbackUrl 'https://instagram.com/'
$socialBusinessFacebookUrl = Resolve-OptionalShortcutUrl -ConfiguredValue $shortcutSocialBusinessFacebookUrl -FallbackUrl 'https://www.facebook.com/'
$socialPersonalFacebookUrl = Resolve-OptionalShortcutUrl -ConfiguredValue $shortcutSocialPersonalFacebookUrl -FallbackUrl 'https://www.facebook.com/'
$socialBusinessXUrl = Resolve-OptionalShortcutUrl -ConfiguredValue $shortcutSocialBusinessXUrl -FallbackUrl 'https://x.com/'
$socialPersonalXUrl = Resolve-OptionalShortcutUrl -ConfiguredValue $shortcutSocialPersonalXUrl -FallbackUrl 'https://x.com/'
$socialBusinessSnapchatUrl = Resolve-OptionalShortcutUrl -ConfiguredValue $shortcutSocialBusinessSnapchatUrl -FallbackUrl 'https://www.snapchat.com/'
$socialBusinessNextSosyalUrl = Resolve-OptionalShortcutUrl -ConfiguredValue $shortcutSocialBusinessNextSosyalUrl -FallbackUrl 'https://sosyal.teknofest.app/'

function Get-ChromeProfileDirectoryForShortcut {
    param(
        [ValidateSet('business','personal')]
        [string]$ProfileKind = 'business'
    )

    if ([string]::Equals([string]$ProfileKind, 'personal', [System.StringComparison]::OrdinalIgnoreCase)) {
        return [string]$employeeEmailBaseName
    }

    return [string]$companyChromeProfileDirectory
}

function Get-ChromeArgsPrefix {
    param(
        [ValidateSet('business','personal')]
        [string]$ProfileKind = 'business',
        [ValidateSet('remote','setup','bank')]
        [string]$Variant = 'remote'
    )

    $profileDirectory = Get-ChromeProfileDirectoryForShortcut -ProfileKind $ProfileKind
    return ('--new-window --start-maximized --user-data-dir="{0}" --profile-directory="{1}"' -f $publicChromeUserDataDir, $profileDirectory)
}

function Get-EdgeArgsPrefix {
    param(
        [ValidateSet('business','personal')]
        [string]$ProfileKind = 'business',
        [ValidateSet('remote','setup','bank')]
        [string]$Variant = 'remote'
    )

    $profileDirectory = Get-ChromeProfileDirectoryForShortcut -ProfileKind $ProfileKind
    return ('--new-window --start-maximized --user-data-dir="{0}" --profile-directory="{1}"' -f $publicEdgeUserDataDir, $profileDirectory)
}

Import-Module 'C:\Windows\Temp\clagnos-session-environment.psm1' -Force -DisableNameChecking

function Refresh-SessionPath {
    Refresh-ClagnosSessionPath | Out-Null
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

        $match = Get-ChildItem -LiteralPath $rootPath -Filter $ExecutableName -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
        if ($match -and (Test-Path -LiteralPath $match.FullName)) {
            return [string]$match.FullName
        }
    }

    return ""
}

function Resolve-VsWhereExe {
    foreach ($candidate in @(
        'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe',
        'C:\Program Files\Microsoft Visual Studio\Installer\vswhere.exe'
    )) {
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate) -and (Test-Path -LiteralPath $candidate)) {
            return [string]$candidate
        }
    }

    return ''
}

function Resolve-Vs2022CommunityExecutablePath {
    $canonicalCandidates = @(
        'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\devenv.exe',
        'C:\Program Files (x86)\Microsoft Visual Studio\2022\Community\Common7\IDE\devenv.exe'
    )

    foreach ($candidate in @($canonicalCandidates)) {
        if (Test-Path -LiteralPath $candidate) {
            return [string]$candidate
        }
    }

    $vsWhereExe = Resolve-VsWhereExe
    if (-not [string]::IsNullOrWhiteSpace([string]$vsWhereExe)) {
        try {
            $vsWhereOutput = & $vsWhereExe -latest -products Microsoft.VisualStudio.Product.Community -property installationPath 2>$null
            $installationPath = [string]($vsWhereOutput | Out-String)
            if (-not [string]::IsNullOrWhiteSpace([string]$installationPath)) {
                $installationPath = $installationPath.Trim()
                $resolvedCandidate = Join-Path $installationPath 'Common7\IDE\devenv.exe'
                if (Test-Path -LiteralPath $resolvedCandidate) {
                    return [string]$resolvedCandidate
                }
            }
        }
        catch {
        }
    }

    return $canonicalCandidates[0]
}

function Resolve-JawsRootFromRegistry {
    foreach ($registryPath in @(
        'HKLM:\Software\Freedom Scientific\JAWS\2025',
        'HKLM:\Software\WOW6432Node\Freedom Scientific\JAWS\2025'
    )) {
        if (-not (Test-Path -LiteralPath $registryPath)) {
            continue
        }

        $targetPath = [string](Get-ItemProperty -LiteralPath $registryPath -Name 'Target' -ErrorAction SilentlyContinue).Target
        if ([string]::IsNullOrWhiteSpace([string]$targetPath)) {
            continue
        }

        $normalizedPath = $targetPath.Trim().TrimEnd('\')
        if (Test-Path -LiteralPath $normalizedPath) {
            return [string]$normalizedPath
        }
    }

    return ''
}

function Resolve-JawsExecutablePath {
    $registryRoot = Resolve-JawsRootFromRegistry
    if (-not [string]::IsNullOrWhiteSpace([string]$registryRoot)) {
        $registryCandidate = Resolve-ExecutableUnderDirectory -RootPaths @($registryRoot) -ExecutableName 'jfw.exe'
        if (-not [string]::IsNullOrWhiteSpace([string]$registryCandidate)) {
            return [string]$registryCandidate
        }
    }

    foreach ($candidate in @(
        'C:\Program Files\Freedom Scientific\JAWS\2025\jfw.exe',
        'C:\Program Files (x86)\Freedom Scientific\JAWS\2025\jfw.exe'
    )) {
        if (Test-Path -LiteralPath $candidate) {
            return [string]$candidate
        }
    }

    return 'C:\Program Files\Freedom Scientific\JAWS\2025\jfw.exe'
}

function Resolve-OfficeExecutable {
    param([string]$ExeName)

    if ([string]::IsNullOrWhiteSpace([string]$ExeName)) {
        return ""
    }

    foreach ($root in @(
        "C:\Program Files\Microsoft Office\root\Office16",
        "C:\Program Files (x86)\Microsoft Office\root\Office16",
        "C:\Program Files\Microsoft Office\Office16",
        "C:\Program Files (x86)\Microsoft Office\Office16"
    )) {
        $candidate = Join-Path $root $ExeName
        if (Test-Path -LiteralPath $candidate) {
            return [string]$candidate
        }
    }

    return ""
}

function Resolve-StartAppId {
    param(
        [string]$NameFragment,
        [string[]]$PackageNameHints = @()
    )

    if ([string]::IsNullOrWhiteSpace([string]$NameFragment)) {
        if (@($PackageNameHints).Count -lt 1) {
            return ""
        }
    }

    if (-not (Get-Command Get-StartApps -ErrorAction SilentlyContinue)) {
        return ""
    }

    $normalized = [string]$NameFragment
    if (-not [string]::IsNullOrWhiteSpace([string]$normalized)) {
        $normalized = $normalized.Trim().ToLowerInvariant()
    }
    $normalizedHints = @(
        @($PackageNameHints) |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object { $_.Trim().ToLowerInvariant() }
    )
    $startApps = @(Get-StartApps | Where-Object {
        $nameText = [string]$_.Name
        $appIdText = [string]$_.AppID

        if (-not [string]::IsNullOrWhiteSpace([string]$normalized)) {
            if ((-not [string]::IsNullOrWhiteSpace([string]$nameText) -and $nameText.ToLowerInvariant().Contains($normalized)) -or
                (-not [string]::IsNullOrWhiteSpace([string]$appIdText) -and $appIdText.ToLowerInvariant().Contains($normalized))) {
                return $true
            }
        }

        foreach ($hint in @($normalizedHints)) {
            if ((-not [string]::IsNullOrWhiteSpace([string]$nameText) -and $nameText.ToLowerInvariant().Contains($hint)) -or
                (-not [string]::IsNullOrWhiteSpace([string]$appIdText) -and $appIdText.ToLowerInvariant().Contains($hint))) {
                return $true
            }
        }

        return $false
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
            if ([string]::IsNullOrWhiteSpace([string]$installLocation)) {
                return $false
            }
            if ([string]::IsNullOrWhiteSpace([string]$pkgName) -and [string]::IsNullOrWhiteSpace([string]$pkgFamily)) {
                return $false
            }

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
        $manifestPath = Join-Path ([string]$package.InstallLocation) "AppxManifest.xml"
        if (-not (Test-Path -LiteralPath $manifestPath)) {
            continue
        }

        try {
            [xml]$manifestXml = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop
            $appNodes = @($manifestXml.SelectNodes("//*[local-name()='Application']"))
            foreach ($appNode in @($appNodes)) {
                $applicationId = [string]$appNode.GetAttribute("Id")
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

    $packageAppId = Resolve-AppxAppIdFromPackage -NameFragment $NameFragment -PackageNameHints $PackageNameHints
    if (-not [string]::IsNullOrWhiteSpace([string]$packageAppId)) {
        return $packageAppId
    }

    $allPackages = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
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
    $matchingFamilies = @(
        $allPackages | Where-Object {
            $pkgNameLower = ([string]$_.Name).ToLowerInvariant()
            $pkgFamilyLower = ([string]$_.PackageFamilyName).ToLowerInvariant()
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
        } |
            ForEach-Object { [string]$_.PackageFamilyName } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
    )

    if (@($matchingFamilies).Count -gt 0 -and (Get-Command Get-StartApps -ErrorAction SilentlyContinue)) {
        $startApps = @(Get-StartApps | Where-Object {
            $appIdText = [string]$_.AppID
            foreach ($family in @($matchingFamilies)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$appIdText) -and
                    $appIdText.StartsWith(($family + '!'), [System.StringComparison]::OrdinalIgnoreCase)) {
                    return $true
                }
            }

            return $false
        })

        foreach ($entry in @($startApps)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$entry.AppID)) {
                return [string]$entry.AppID
            }
        }
    }

    return (Resolve-StartAppId -NameFragment $NameFragment -PackageNameHints $PackageNameHints)
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
            if ([string]::IsNullOrWhiteSpace([string]$installLocation)) {
                return $false
            }
            if ([string]::IsNullOrWhiteSpace([string]$pkgName) -and [string]::IsNullOrWhiteSpace([string]$pkgFamily)) {
                return $false
            }

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

function Get-AppPackagesByHints {
    param(
        [string]$NameFragment,
        [string[]]$PackageNameHints = @()
    )

    $allPackages = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
    if (@($allPackages).Count -eq 0) {
        return @()
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

    return @(
        $allPackages | Where-Object {
            $pkgName = [string]$_.Name
            $pkgFamily = [string]$_.PackageFamilyName
            $installLocation = [string]$_.InstallLocation
            if ([string]::IsNullOrWhiteSpace([string]$installLocation)) {
                return $false
            }
            if ([string]::IsNullOrWhiteSpace([string]$pkgName) -and [string]::IsNullOrWhiteSpace([string]$pkgFamily)) {
                return $false
            }

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
}

function Resolve-AppPackageManifestPath {
    param(
        [string]$NameFragment,
        [string[]]$PackageNameHints = @()
    )

    foreach ($package in @(Get-AppPackagesByHints -NameFragment $NameFragment -PackageNameHints $PackageNameHints)) {
        $installLocation = [string]$package.InstallLocation
        if ([string]::IsNullOrWhiteSpace([string]$installLocation)) {
            continue
        }

        $manifestPath = Join-Path $installLocation 'AppxManifest.xml'
        if (Test-Path -LiteralPath $manifestPath) {
            return [string]$manifestPath
        }
    }

    return ''
}

function Ensure-ManagedUserStoreAppRegistration {
    param(
        [string]$RepairTaskName,
        [string]$DisplayName,
        [string]$NameFragment,
        [string[]]$PackageNameHints = @()
    )

    if (-not (Get-Command Invoke-ClagnosUserAppxRegistrationRepair -ErrorAction SilentlyContinue)) {
        return
    }

    $packages = @(Get-AppPackagesByHints -NameFragment $NameFragment -PackageNameHints $PackageNameHints)
    if (@($packages).Count -eq 0) {
        return
    }

    $primaryPackage = @(
        $packages | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_.PackageFamilyName) -and
            -not [string]::IsNullOrWhiteSpace([string]$_.InstallLocation)
        } | Select-Object -First 1
    )[0]
    if ($null -eq $primaryPackage) {
        return
    }

    $manifestPath = Resolve-AppPackageManifestPath -NameFragment $NameFragment -PackageNameHints $PackageNameHints
    if ([string]::IsNullOrWhiteSpace([string]$manifestPath)) {
        return
    }

    $packageFamily = [string]$primaryPackage.PackageFamilyName
    if ([string]::IsNullOrWhiteSpace([string]$packageFamily)) {
        return
    }

    $appIdPatterns = @("{0}!*" -f [string]$packageFamily)
    foreach ($registrationTarget in @(
        [pscustomobject]@{ Label = 'manager'; UserName = [string]$managerUser; Password = [string]$managerPassword },
        [pscustomobject]@{ Label = 'assistant'; UserName = [string]$assistantUser; Password = [string]$assistantPassword }
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$registrationTarget.UserName) -or [string]::IsNullOrWhiteSpace([string]$registrationTarget.Password)) {
            continue
        }

        $registrationTaskName = ("{0}-{1}-appid-repair" -f [string]$RepairTaskName, [string]$registrationTarget.Label)
        try {
            $result = $null
            foreach ($attempt in @(
                [pscustomobject]@{ WaitTimeoutSeconds = 45; HeartbeatSeconds = 10 },
                [pscustomobject]@{ WaitTimeoutSeconds = 90; HeartbeatSeconds = 15 }
            )) {
                try {
                    $result = Invoke-ClagnosUserAppxRegistrationRepair `
                        -TaskName $registrationTaskName `
                        -RunAsUser ([string]$registrationTarget.UserName) `
                        -RunAsPassword ([string]$registrationTarget.Password) `
                        -HelperPath $interactiveHelperPath `
                        -PackageManifestPath $manifestPath `
                        -AppIdPatterns $appIdPatterns `
                        -WaitTimeoutSeconds ([int]$attempt.WaitTimeoutSeconds) `
                        -HeartbeatSeconds ([int]$attempt.HeartbeatSeconds) `
                        -RunAsMode 'password'
                    break
                }
                catch {
                    $repairAttemptError = [string]$_.Exception.Message
                    $isLastAttempt = ([int]$attempt.WaitTimeoutSeconds -eq 90)
                    if ($repairAttemptError -match '(?i)Interactive worker timed out without a result file' -and -not $isLastAttempt) {
                        Write-Host ("public-shortcut-user-appid-retry: {0} => {1} => retrying after interactive timeout" -f [string]$DisplayName, [string]$registrationTarget.Label) -ForegroundColor DarkCyan
                        continue
                    }

                    throw
                }
            }

            $summary = if ($result.PSObject.Properties.Match('Summary').Count -gt 0) { [string]$result.Summary } else { 'completed' }
            Write-Host ("public-shortcut-user-appid-repair: {0} => {1} => {2}" -f [string]$DisplayName, [string]$registrationTarget.Label, $summary)
        }
        catch {
            $repairError = [string]$_.Exception.Message
            if ($repairError -match '(?i)0x80070005|access is denied') {
                Write-Host ("public-shortcut-user-appid-repair-skip: {0} => {1} => {2}" -f [string]$DisplayName, [string]$registrationTarget.Label, $repairError) -ForegroundColor Yellow
            }
            else {
                Write-Warning ("public-shortcut-user-appid-repair: {0} => {1} => {2}" -f [string]$DisplayName, [string]$registrationTarget.Label, $repairError)
            }
        }
    }
}

function Resolve-ExistingOrFallbackPath {
    param(
        [string]$PreferredPath,
        [string]$ResolvedPath,
        [string]$FallbackPath
    )

    foreach ($candidate in @($PreferredPath, $ResolvedPath, $FallbackPath)) {
        if ([string]::IsNullOrWhiteSpace([string]$candidate)) {
            continue
        }

        $expandedCandidate = [Environment]::ExpandEnvironmentVariables([string]$candidate)
        if (Test-Path -LiteralPath $expandedCandidate) {
            return [string]$expandedCandidate
        }
    }

    return ""
}

function Resolve-ICloudExecutablePath {
    $resolvedFromPackage = Resolve-AppPackageExecutablePath -NameFragment "icloud" -PackageNameHints @("icloud", "AppleInc.iCloud", "9PKTQ5699M62") -ExecutableName "iCloudHome.exe"
    $resolvedPath = Resolve-ExistingOrFallbackPath -PreferredPath "" -ResolvedPath $resolvedFromPackage -FallbackPath ""
    if (-not [string]::IsNullOrWhiteSpace([string]$resolvedPath)) {
        return [string]$resolvedPath
    }

    foreach ($candidate in @(
        "C:\Program Files\iCloud\iCloudHome.exe",
        "C:\Program Files (x86)\iCloud\iCloudHome.exe"
    )) {
        if (Test-Path -LiteralPath $candidate) {
            return [string]$candidate
        }
    }

    return ""
}

function Test-ICloudAppId {
    param([string]$AppId)

    if ([string]::IsNullOrWhiteSpace([string]$AppId)) {
        return $false
    }

    if ([string]$AppId -match '(?i)filepicker') {
        return $false
    }

    return ([string]$AppId -match '(?i)icloud|apple')
}

function Resolve-ICloudAppId {
    $candidates = @(
        (Resolve-AppxAppIdFromPackage -NameFragment 'icloud' -PackageNameHints @('AppleInc.iCloud', '9PKTQ5699M62', 'icloud')),
        (Resolve-StartAppId -NameFragment 'icloud' -PackageNameHints @('AppleInc.iCloud', '9PKTQ5699M62', 'icloud')),
        (Resolve-StoreAppId -NameFragment 'icloud' -PackageNameHints @('AppleInc.iCloud', '9PKTQ5699M62', 'icloud'))
    )

    foreach ($candidate in @($candidates)) {
        if (Test-ICloudAppId -AppId ([string]$candidate)) {
            return [string]$candidate
        }
    }

    return ''
}

function Ensure-Directory {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace([string]$Path)) {
        return
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Clear-DesktopEntries {
    param([string]$DesktopPath)

    if ([string]::IsNullOrWhiteSpace([string]$DesktopPath) -or -not (Test-Path -LiteralPath $DesktopPath)) {
        return
    }

    Get-ChildItem -LiteralPath $DesktopPath -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            if ($_.PSIsContainer) {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
            }
            else {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
            }

            Write-Host ("user-desktop-entry-removed: {0}" -f $_.FullName)
        }
        catch {
            throw ("Failed to remove user desktop entry '{0}': {1}" -f $_.FullName, $_.Exception.Message)
        }
    }
}

function Get-ShortcutDetails {
    param([string]$ShortcutPath)

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    return [pscustomobject]@{
        TargetPath = [string]$shortcut.TargetPath
        Arguments = [string]$shortcut.Arguments
        WorkingDirectory = [string]$shortcut.WorkingDirectory
        IconLocation = [string]$shortcut.IconLocation
        Hotkey = [string]$shortcut.Hotkey
        WindowStyle = [int]$shortcut.WindowStyle
    }
}

function Set-ShortcutRunAsAdministratorFlag {
    param(
        [string]$ShortcutPath,
        [bool]$Enabled = $true
    )

    if ([string]::IsNullOrWhiteSpace([string]$ShortcutPath) -or -not (Test-Path -LiteralPath $ShortcutPath)) {
        throw ("Shortcut path was not found for admin flag patching: {0}" -f $ShortcutPath)
    }

    $bytes = [System.IO.File]::ReadAllBytes($ShortcutPath)
    if ($bytes.Length -lt 0x18) {
        throw ("Shortcut header is too small for admin flag patching: {0}" -f $ShortcutPath)
    }

    $linkFlags = [System.BitConverter]::ToUInt32($bytes, 0x14)
    if ($Enabled) {
        $linkFlags = $linkFlags -bor [uint32]$shortcutRunAsAdminFlag
    }
    else {
        $linkFlags = $linkFlags -band (-bnot [uint32]$shortcutRunAsAdminFlag)
    }

    $flagBytes = [System.BitConverter]::GetBytes([uint32]$linkFlags)
    [System.Array]::Copy($flagBytes, 0, $bytes, 0x14, $flagBytes.Length)
    [System.IO.File]::WriteAllBytes($ShortcutPath, $bytes)
}

function Add-ShortcutUserReadAccess {
    param([string]$ShortcutPath)

    if ([string]::IsNullOrWhiteSpace([string]$ShortcutPath) -or -not (Test-Path -LiteralPath $ShortcutPath)) {
        return
    }

    try {
        $acl = Get-Acl -LiteralPath $ShortcutPath
        $readExecuteRights = [System.Security.AccessControl.FileSystemRights]::ReadAndExecute
        $everyoneSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-1-0')

        # Preserve explicit ACL intent while ensuring all user profiles can read/execute shortcut artifacts.
        $acl.PurgeAccessRules($everyoneSid)
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $everyoneSid,
            $readExecuteRights,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        $acl.AddAccessRule($accessRule)
        Set-Acl -LiteralPath $ShortcutPath -AclObject $acl | Out-Null
    }
    catch {
        Write-Host ("public-shortcut-acl-skip: {0} => {1}" -f $ShortcutPath, $_.Exception.Message)
    }
}

function Set-PublicShortcutReadPermissions {
    param([string]$ShortcutPath)

    Add-ShortcutUserReadAccess -ShortcutPath $ShortcutPath
}

function Get-ShortcutRunAsAdministratorFlag {
    param([string]$ShortcutPath)

    if ([string]::IsNullOrWhiteSpace([string]$ShortcutPath) -or -not (Test-Path -LiteralPath $ShortcutPath)) {
        return $false
    }

    $bytes = [System.IO.File]::ReadAllBytes($ShortcutPath)
    if ($bytes.Length -lt 0x18) {
        return $false
    }

    $linkFlags = [System.BitConverter]::ToUInt32($bytes, 0x14)
    return (($linkFlags -band [uint32]$shortcutRunAsAdminFlag) -ne 0)
}

function Resolve-WrittenShortcutPath {
    param(
        [string]$ExpectedShortcutPath,
        [string]$OutputDirectory,
        [string]$ShortcutName
    )

    if (-not [string]::IsNullOrWhiteSpace([string]$ExpectedShortcutPath) -and (Test-Path -LiteralPath $ExpectedShortcutPath)) {
        return [string]$ExpectedShortcutPath
    }

    if ([string]::IsNullOrWhiteSpace([string]$OutputDirectory) -or -not (Test-Path -LiteralPath $OutputDirectory)) {
        return [string]$ExpectedShortcutPath
    }

    $shortcutNameKey = Get-NormalizedShortcutNameKey -Value $ShortcutName
    foreach ($candidate in @(Get-ChildItem -LiteralPath $OutputDirectory -Filter '*.lnk' -File -ErrorAction SilentlyContinue)) {
        $candidateBaseName = [System.IO.Path]::GetFileNameWithoutExtension([string]$candidate.Name)
        $candidateKey = Get-NormalizedShortcutNameKey -Value $candidateBaseName
        if ([string]::Equals([string]$candidateKey, [string]$shortcutNameKey, [System.StringComparison]::Ordinal)) {
            return [string]$candidate.FullName
        }
    }

    return [string]$ExpectedShortcutPath
}

function Test-ShortcutValueMatch {
    param(
        [string]$ExpectedValue,
        [string]$ActualValue
    )

    return [string]::Equals([string]$ExpectedValue, [string]$ActualValue, [System.StringComparison]::OrdinalIgnoreCase)
}

function Normalize-ShortcutHotkey {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return ""
    }

    $parts = @(
        $Value -split '\+' |
        ForEach-Object { [string]$_ } |
        ForEach-Object { $_.Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
    )
    if (-not $parts -or $parts.Count -eq 0) {
        return ""
    }

    $modifierOrder = @('CTRL', 'ALT', 'SHIFT')
    $normalizedParts = New-Object 'System.Collections.Generic.List[string]'
    foreach ($modifier in $modifierOrder) {
        foreach ($part in $parts) {
            if ([string]::Equals($part, $modifier, [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$normalizedParts.Add($modifier)
            }
        }
    }

    foreach ($part in $parts) {
        $upperPart = $part.ToUpperInvariant()
        if ($modifierOrder -contains $upperPart) {
            continue
        }

        [void]$normalizedParts.Add($upperPart)
    }

    return ($normalizedParts -join '+')
}

function New-ShortcutSpec {
    param(
        [string]$Name,
        [string]$TargetPath,
        [string]$Arguments = "",
        [string]$WorkingDirectory = "",
        [string]$IconLocation = "",
        [string]$Hotkey = "",
        [int]$ShowCmd = 3,
        [bool]$RunAsAdmin = $true,
        [bool]$AllowMissingTargetPath = $false,
        [string]$ValidationKind = "generic",
        [string]$ProfileKind = "",
        [string]$DestinationUrl = "",
        [string[]]$CleanupAliases = @(),
        [bool]$CleanupMatchTargetOnly = $false,
        [bool]$CleanupAliasMatchByNameOnly = $false
    )

    return [pscustomobject]@{
        Name = [string]$Name
        TargetPath = [string]$TargetPath
        Arguments = [string]$Arguments
        WorkingDirectory = [string]$WorkingDirectory
        EffectiveTargetPath = [string]$TargetPath
        EffectiveArguments = [string]$Arguments
        EffectiveWorkingDirectory = [string]$WorkingDirectory
        IconLocation = [string]$IconLocation
        Hotkey = [string]$Hotkey
        ShowCmd = [int]$ShowCmd
        RunAsAdmin = [bool]$RunAsAdmin
        AllowMissingTargetPath = [bool]$AllowMissingTargetPath
        ValidationKind = [string]$ValidationKind
        ProfileKind = [string]$ProfileKind
        DestinationUrl = [string]$DestinationUrl
        CleanupAliases = @($CleanupAliases | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        CleanupMatchTargetOnly = [bool]$CleanupMatchTargetOnly
        CleanupAliasMatchByNameOnly = [bool]$CleanupAliasMatchByNameOnly
        UsesManagedLauncher = $false
        LauncherPath = ''
    }
}

function Get-ShortcutEffectiveTargetPath {
    param([pscustomobject]$Spec)

    if ($null -eq $Spec) {
        return ''
    }

    if ($Spec.PSObject.Properties.Match('EffectiveTargetPath').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$Spec.EffectiveTargetPath)) {
        return [string]$Spec.EffectiveTargetPath
    }

    return [string]$Spec.TargetPath
}

function Get-ShortcutEffectiveArguments {
    param([pscustomobject]$Spec)

    if ($null -eq $Spec) {
        return ''
    }

    if ($Spec.PSObject.Properties.Match('EffectiveArguments').Count -gt 0) {
        return [string]$Spec.EffectiveArguments
    }

    return [string]$Spec.Arguments
}

function Get-ShortcutEffectiveWorkingDirectory {
    param([pscustomobject]$Spec)

    if ($null -eq $Spec) {
        return ''
    }

    if ($Spec.PSObject.Properties.Match('EffectiveWorkingDirectory').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$Spec.EffectiveWorkingDirectory)) {
        return [string]$Spec.EffectiveWorkingDirectory
    }

    return [string]$Spec.WorkingDirectory
}

function ConvertTo-ManagedShortcutLauncherSpec {
    param([pscustomobject]$Spec)

    if ($null -eq $Spec) {
        return $null
    }

    if (-not (Get-Command Test-ClagnosShortcutNeedsManagedLauncher -ErrorAction SilentlyContinue)) {
        return $Spec
    }

    $effectiveTargetPath = Get-ShortcutEffectiveTargetPath -Spec $Spec
    $effectiveArguments = Get-ShortcutEffectiveArguments -Spec $Spec
    $effectiveWorkingDirectory = Get-ShortcutEffectiveWorkingDirectory -Spec $Spec

    if (-not (Test-ClagnosShortcutNeedsManagedLauncher -TargetPath $effectiveTargetPath -Arguments $effectiveArguments -Threshold $managedShortcutInvocationThreshold)) {
        return $Spec
    }

    $launcherPath = Get-ClagnosShortcutLauncherFilePath -ShortcutName ([string]$Spec.Name) -Subdirectory 'public-desktop'
    $wrappedSpec = [pscustomobject]@{
        Name = [string]$Spec.Name
        TargetPath = [string]$cmdExe
        Arguments = (Get-ClagnosShortcutLauncherInvocationArguments -LauncherPath $launcherPath)
        WorkingDirectory = [string](Split-Path -Path $launcherPath -Parent)
        EffectiveTargetPath = [string]$effectiveTargetPath
        EffectiveArguments = [string]$effectiveArguments
        EffectiveWorkingDirectory = [string]$effectiveWorkingDirectory
        IconLocation = [string]$Spec.IconLocation
        Hotkey = [string]$Spec.Hotkey
        ShowCmd = [int]$Spec.ShowCmd
        RunAsAdmin = [bool]$Spec.RunAsAdmin
        AllowMissingTargetPath = [bool]$Spec.AllowMissingTargetPath
        ValidationKind = [string]$Spec.ValidationKind
        ProfileKind = [string]$Spec.ProfileKind
        DestinationUrl = [string]$Spec.DestinationUrl
        CleanupAliases = @($Spec.CleanupAliases)
        CleanupMatchTargetOnly = [bool]$Spec.CleanupMatchTargetOnly
        CleanupAliasMatchByNameOnly = [bool]$Spec.CleanupAliasMatchByNameOnly
        UsesManagedLauncher = $true
        LauncherPath = [string]$launcherPath
    }

    Write-Host ("shortcut-launcher-enabled: {0} => {1}" -f [string]$Spec.Name, [string]$launcherPath)
    return $wrappedSpec
}

function New-ShortcutFromSpec {
    param(
        [pscustomobject]$Spec,
        [string]$OutputDirectory
    )

    if ($null -eq $Spec) {
        throw "Shortcut spec is required."
    }

    $name = [string]$Spec.Name
    $targetPath = [string]$Spec.TargetPath
    if ([string]::IsNullOrWhiteSpace([string]$name)) {
        throw "Shortcut name is empty."
    }
    if ([string]::IsNullOrWhiteSpace([string]$targetPath)) {
        throw ("Shortcut target is empty for '{0}'." -f $name)
    }
    if (-not [bool]$Spec.AllowMissingTargetPath -and -not (Test-Path -LiteralPath $targetPath)) {
        throw ("Shortcut target was not found for '{0}': {1}" -f $name, $targetPath)
    }

    if ($Spec.PSObject.Properties.Match('UsesManagedLauncher').Count -gt 0 -and [bool]$Spec.UsesManagedLauncher) {
        $launcherPath = [string]$Spec.LauncherPath
        if ([string]::IsNullOrWhiteSpace([string]$launcherPath)) {
            throw ("Managed launcher path is empty for '{0}'." -f $name)
        }

        Write-ClagnosShortcutLauncherFile `
            -LauncherPath $launcherPath `
            -TargetPath (Get-ShortcutEffectiveTargetPath -Spec $Spec) `
            -Arguments (Get-ShortcutEffectiveArguments -Spec $Spec) `
            -WorkingDirectory (Get-ShortcutEffectiveWorkingDirectory -Spec $Spec) | Out-Null
    }

    Ensure-Directory -Path $OutputDirectory
    $shortcutPath = Join-Path $OutputDirectory ($name + ".lnk")
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $targetPath
    $shortcut.Arguments = [string]$Spec.Arguments
    $expectedWorkingDirectory = ""
    if (-not [string]::IsNullOrWhiteSpace([string]$Spec.WorkingDirectory)) {
        $expectedWorkingDirectory = [string]$Spec.WorkingDirectory
        $shortcut.WorkingDirectory = $expectedWorkingDirectory
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string](Split-Path -Path $targetPath -Parent))) {
        $expectedWorkingDirectory = [string](Split-Path -Path $targetPath -Parent)
        $shortcut.WorkingDirectory = $expectedWorkingDirectory
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Spec.IconLocation)) {
        $shortcut.IconLocation = [string]$Spec.IconLocation
    }
    else {
        $shortcut.IconLocation = ("{0},0" -f $targetPath)
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Spec.Hotkey)) {
        $shortcut.Hotkey = [string]$Spec.Hotkey
    }
    $shortcut.WindowStyle = [int]$Spec.ShowCmd
    $shortcut.Save()

    $writtenShortcutPath = Resolve-WrittenShortcutPath -ExpectedShortcutPath $shortcutPath -OutputDirectory $OutputDirectory -ShortcutName $name
    if (-not [string]::Equals([string]$writtenShortcutPath, [string]$shortcutPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host ("shortcut-path-reconciled: {0} => {1}" -f [string]$name, [string]$writtenShortcutPath)
    }

    if ([bool]$Spec.RunAsAdmin) {
        Set-ShortcutRunAsAdministratorFlag -ShortcutPath $writtenShortcutPath -Enabled $true
    }

    Set-PublicShortcutReadPermissions -ShortcutPath $writtenShortcutPath

    $writtenDetails = Get-ShortcutDetails -ShortcutPath $writtenShortcutPath
    if (-not (Test-ShortcutValueMatch -ExpectedValue $targetPath -ActualValue ([string]$writtenDetails.TargetPath))) {
        throw ("Shortcut target validation failed for '{0}'." -f $name)
    }
    if (-not (Test-ShortcutValueMatch -ExpectedValue ([string]$Spec.Arguments) -ActualValue ([string]$writtenDetails.Arguments))) {
        throw ("Shortcut arguments validation failed for '{0}'." -f $name)
    }
    if (-not (Test-ShortcutValueMatch -ExpectedValue $expectedWorkingDirectory -ActualValue ([string]$writtenDetails.WorkingDirectory))) {
        throw ("Shortcut working directory validation failed for '{0}'." -f $name)
    }
    if ((Normalize-ShortcutHotkey -Value ([string]$Spec.Hotkey)) -ne (Normalize-ShortcutHotkey -Value ([string]$writtenDetails.Hotkey))) {
        throw ("Shortcut hotkey validation failed for '{0}'." -f $name)
    }
    if ([int]$writtenDetails.WindowStyle -ne [int]$Spec.ShowCmd) {
        throw ("Shortcut window style validation failed for '{0}'." -f $name)
    }
    if ([bool]$Spec.RunAsAdmin -ne (Get-ShortcutRunAsAdministratorFlag -ShortcutPath $writtenShortcutPath)) {
        throw ("Shortcut admin flag validation failed for '{0}'." -f $name)
    }

    Write-Host ("shortcut-ok: {0}" -f $name)
}

function Resolve-EmbeddedShortcutCommandPath {
    param([string]$Arguments)

    $expandedArguments = [Environment]::ExpandEnvironmentVariables([string]$Arguments)
    if ([string]::IsNullOrWhiteSpace([string]$expandedArguments)) {
        return ""
    }

    foreach ($pattern in @(
        '(?i)start\s+""\s+"([^"]+)"',
        '(?i)start\s+"?([^"\s]+\.(?:exe|cmd|bat))',
        '(?i)&\s*''([^'']+\.(?:exe|cmd|bat))''',
        '(?i)&\s*"([^"]+\.(?:exe|cmd|bat))"',
        '(?i)(?:^|[&\s])("?[%A-Za-z0-9_:\\ .()-]+\.(?:exe|cmd|bat))',
        '(?i)(?:^|[&\s])(docker|azd|az|gh|wsl|python|node|pwsh|powershell|rclone|ffmpeg|git-bash|copilot|gemini|codex)(?:\s|$)'
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

    return ""
}

function Test-ShortcutSpecEligible {
    param([pscustomobject]$Spec)

    if ($null -eq $Spec) {
        return $false
    }

    $targetPath = Get-ShortcutEffectiveTargetPath -Spec $Spec
    if ([string]::IsNullOrWhiteSpace([string]$targetPath)) {
        return $false
    }

    $validationKind = [string]$Spec.ValidationKind
    $targetExists = Test-Path -LiteralPath $targetPath
    if (-not $targetExists) {
        return $false
    }

    $effectiveArguments = Get-ShortcutEffectiveArguments -Spec $Spec
    if (($validationKind -eq 'store-appid') -and [string]::IsNullOrWhiteSpace([string]$effectiveArguments)) {
        return $false
    }

    $targetLeaf = [System.IO.Path]::GetFileName([string]$targetPath)
    if (($targetLeaf -in @('cmd.exe','powershell.exe','pwsh.exe')) -and ($validationKind -in @('console','app'))) {
        $embeddedCommandPath = Resolve-EmbeddedShortcutCommandPath -Arguments ([string]$effectiveArguments)
        if ([string]::IsNullOrWhiteSpace([string]$embeddedCommandPath)) {
            $normalizedArguments = ([string]$effectiveArguments).Trim()
            if (
                ($validationKind -eq 'console') -and
                [string]::Equals([string]$targetLeaf, 'cmd.exe', [System.StringComparison]::OrdinalIgnoreCase) -and
                (
                    ($normalizedArguments -match '^(?i)/(k|c)\s+cd(?:\s|$)') -or
                    ($normalizedArguments -match '^(?i)/(k|c)\s*$')
                )
            ) {
                return $true
            }

            return $false
        }
    }

    return $true
}

function Add-Spec {
    param(
        [System.Collections.Generic.List[object]]$List,
        [pscustomobject]$Spec
    )

    if ($null -eq $List -or $null -eq $Spec) {
        return
    }

    $Spec = ConvertTo-ManagedShortcutLauncherSpec -Spec $Spec

    if (-not (Test-ShortcutSpecEligible -Spec $Spec)) {
        $skipMessage = ("public-shortcut-skip: {0} => target or embedded command could not be resolved." -f [string]$Spec.Name)
        $validationKind = [string]$Spec.ValidationKind
        if ([bool]$Spec.AllowMissingTargetPath -and ($validationKind -in @('app', 'console'))) {
            Write-Host $skipMessage
        }
        else {
            Write-Warning $skipMessage
        }
        return
    }

    [void]$List.Add($Spec)
}

function New-ChromeShortcutSpec {
    param(
        [string]$Name,
        [string]$Url,
        [ValidateSet('business','personal')]
        [string]$ProfileKind = 'business',
        [ValidateSet('remote','setup','bank')]
        [string]$Variant = 'remote',
        [string[]]$CleanupAliases = @()
    )

    return (New-ShortcutSpec `
        -Name $Name `
        -TargetPath $chromeTarget `
        -Arguments ((Get-ChromeArgsPrefix -ProfileKind $ProfileKind -Variant $Variant) + ' "' + [string]$Url + '"') `
        -IconLocation ($chromeTarget + ",0") `
        -AllowMissingTargetPath $true `
        -ValidationKind ("chrome-" + [string]$Variant) `
        -ProfileKind $ProfileKind `
        -DestinationUrl ([string]$Url) `
        -CleanupAliases $CleanupAliases)
}

function New-StoreAppShortcutSpec {
    param(
        [string]$Name,
        [string]$AppId,
        [string[]]$CleanupAliases = @()
    )

    return (New-ShortcutSpec `
        -Name $Name `
        -TargetPath $explorerExe `
        -Arguments ("shell:AppsFolder\" + [string]$AppId) `
        -IconLocation ($explorerExe + ",0") `
        -ValidationKind 'store-appid' `
        -CleanupAliases $CleanupAliases)
}

function Read-StoreTaskStateRecord {
    param([string]$TaskName)

    if ([string]::IsNullOrWhiteSpace([string]$TaskName) -or -not (Get-Command Read-ClagnosStoreInstallState -ErrorAction SilentlyContinue)) {
        return $null
    }

    return (Read-ClagnosStoreInstallState -TaskName $TaskName)
}

function Add-StoreManagedShortcutSpec {
    param(
        [System.Collections.Generic.List[object]]$List,
        [string]$ShortcutName,
        [string]$TaskName,
        [string]$AppId,
        [string]$ExecutablePath = '',
        [string[]]$CleanupAliases = @()
    )

    $hasLiveAppId = (-not [string]::IsNullOrWhiteSpace([string]$AppId))
    $hasLiveExecutable = (-not [string]::IsNullOrWhiteSpace([string]$ExecutablePath) -and (Test-Path -LiteralPath $ExecutablePath))
    $stateRecord = Read-StoreTaskStateRecord -TaskName $TaskName
    if ($null -ne $stateRecord -and -not [string]::Equals([string]$stateRecord.state, 'installed', [System.StringComparison]::OrdinalIgnoreCase) -and -not $hasLiveAppId -and -not $hasLiveExecutable) {
        $summary = if ($stateRecord.PSObject.Properties.Match('summary').Count -gt 0) { [string]$stateRecord.summary } else { 'state record indicates the app is not launch-ready.' }
        Write-Host ("public-shortcut-skip: {0} => store state={1}; {2}" -f [string]$ShortcutName, [string]$stateRecord.state, $summary)
        return
    }

    if ($null -ne $stateRecord -and -not [string]::Equals([string]$stateRecord.state, 'installed', [System.StringComparison]::OrdinalIgnoreCase) -and ($hasLiveAppId -or $hasLiveExecutable)) {
        Write-Host ("public-shortcut-recover: {0} => store state={1}; live launch target resolved, continuing with shortcut creation." -f [string]$ShortcutName, [string]$stateRecord.state)
    }

    if ($null -ne $stateRecord) {
        $stateLaunchKind = if ($stateRecord.PSObject.Properties.Match('launchKind').Count -gt 0) { [string]$stateRecord.launchKind } else { '' }
        $stateLaunchTarget = if ($stateRecord.PSObject.Properties.Match('launchTarget').Count -gt 0) { [string]$stateRecord.launchTarget } else { '' }

        if ([string]::IsNullOrWhiteSpace([string]$AppId) -and
            [string]::Equals($stateLaunchKind, 'app-id', [System.StringComparison]::OrdinalIgnoreCase) -and
            -not [string]::IsNullOrWhiteSpace([string]$stateLaunchTarget)) {
            $AppId = [string]$stateLaunchTarget
        }

        if ([string]::IsNullOrWhiteSpace([string]$ExecutablePath) -and
            [string]::Equals($stateLaunchKind, 'executable', [System.StringComparison]::OrdinalIgnoreCase) -and
            -not [string]::IsNullOrWhiteSpace([string]$stateLaunchTarget) -and
            (Test-Path -LiteralPath $stateLaunchTarget)) {
            $ExecutablePath = [string]$stateLaunchTarget
        }
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$AppId)) {
        Add-Spec -List $List -Spec (New-StoreAppShortcutSpec -Name $ShortcutName -AppId $AppId -CleanupAliases $CleanupAliases)
        return
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$ExecutablePath) -and (Test-Path -LiteralPath $ExecutablePath)) {
        Add-Spec -List $List -Spec (New-ShortcutSpec -Name $ShortcutName -TargetPath $ExecutablePath -ValidationKind 'app' -CleanupAliases $CleanupAliases)
        return
    }

    if ($null -ne $stateRecord) {
        $summary = if ($stateRecord.PSObject.Properties.Match('summary').Count -gt 0) { [string]$stateRecord.summary } else { 'launch target could not be resolved.' }
        Write-Warning ("public-shortcut-skip: {0} => store state=installed but launch target is unresolved; {1}" -f [string]$ShortcutName, $summary)
        return
    }

    Write-Warning ("public-shortcut-skip: {0} => store app id or executable could not be resolved." -f [string]$ShortcutName)
}

function Get-NormalizedShortcutNameKey {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return ""
    }

    if (Get-Command Get-ClagnosShortcutNormalizedKey -ErrorAction SilentlyContinue) {
        return (Get-ClagnosShortcutNormalizedKey -Value $Value)
    }

    return ([regex]::Replace($Value.Trim().ToLowerInvariant(), '[^a-z0-9]+', ''))
}

function Get-NormalizedShortcutPath {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return ""
    }

    return ([string]$Value).Trim().Trim('"').ToLowerInvariant()
}

function Get-NormalizedShortcutUrl {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return ""
    }

    return [string]$Value.Trim().Trim('"').ToLowerInvariant()
}

function Get-ShortcutUrlFromArguments {
    param([string]$Arguments)

    if ([string]::IsNullOrWhiteSpace([string]$Arguments)) {
        return ""
    }

    $match = [regex]::Match([string]$Arguments, '(?i)"((?:https?://|chrome://)[^"]+)"')
    if (-not $match.Success) {
        return ""
    }

    return [string]$match.Groups[1].Value
}

function Test-ShortcutDetailsMatchManagedSpec {
    param(
        [pscustomobject]$Details,
        [string]$ShortcutBaseName,
        [pscustomobject]$Spec
    )

    if ($null -eq $Details -or $null -eq $Spec) {
        return $false
    }

    $existingNameKey = Get-NormalizedShortcutNameKey -Value $ShortcutBaseName
    $actualInvocation = if (Get-Command Get-ClagnosShortcutResolvedInvocation -ErrorAction SilentlyContinue) {
        Get-ClagnosShortcutResolvedInvocation -TargetPath ([string]$Details.TargetPath) -Arguments ([string]$Details.Arguments) -WorkingDirectory ([string]$Details.WorkingDirectory)
    }
    else {
        [pscustomobject]@{
            UsesManagedLauncher = $false
            LauncherPath = ''
            TargetPath = [string]$Details.TargetPath
            Arguments = [string]$Details.Arguments
            WorkingDirectory = [string]$Details.WorkingDirectory
        }
    }
    $existingTargetPath = Get-NormalizedShortcutPath -Value ([string]$actualInvocation.TargetPath)
    $managedTargetPath = Get-NormalizedShortcutPath -Value (Get-ShortcutEffectiveTargetPath -Spec $Spec)
    $existingArguments = [string]$actualInvocation.Arguments
    $managedArguments = Get-ShortcutEffectiveArguments -Spec $Spec
    $normalizedExistingUrl = Get-NormalizedShortcutUrl -Value (Get-ShortcutUrlFromArguments -Arguments $existingArguments)
    $normalizedManagedUrl = Get-NormalizedShortcutUrl -Value ([string]$Spec.DestinationUrl)

    foreach ($cleanupAlias in @($Spec.CleanupAliases)) {
        if (-not [string]::Equals($existingNameKey, (Get-NormalizedShortcutNameKey -Value ([string]$cleanupAlias)), [System.StringComparison]::Ordinal)) {
            continue
        }

        if ([bool]$Spec.CleanupAliasMatchByNameOnly) {
            return $true
        }

        if ([string]::Equals($existingTargetPath, $managedTargetPath, [System.StringComparison]::Ordinal)) {
            return $true
        }

        if (($Spec.ValidationKind -like 'chrome-*') -and [string]::Equals($existingTargetPath, (Get-NormalizedShortcutPath -Value $chromeTarget), [System.StringComparison]::Ordinal)) {
            return $true
        }
    }

    if ($Spec.ValidationKind -like 'chrome-*') {
        if ([string]::Equals($existingTargetPath, (Get-NormalizedShortcutPath -Value $chromeTarget), [System.StringComparison]::Ordinal) -and
            -not [string]::IsNullOrWhiteSpace([string]$normalizedExistingUrl) -and
            [string]::Equals($normalizedExistingUrl, $normalizedManagedUrl, [System.StringComparison]::Ordinal)) {
            return $true
        }

        return $false
    }

    if ([bool]$Spec.CleanupMatchTargetOnly -and
        -not [string]::IsNullOrWhiteSpace([string]$managedTargetPath) -and
        [string]::Equals($existingTargetPath, $managedTargetPath, [System.StringComparison]::Ordinal)) {
        return $true
    }

    if (($Spec.ValidationKind -in @('store-appid', 'store-deeplink', 'explorer-shell')) -and
        [string]::Equals($existingTargetPath, $managedTargetPath, [System.StringComparison]::Ordinal) -and
        [string]::Equals(([string]$existingArguments).Trim(), ([string]$managedArguments).Trim(), [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    if (
        [string]::Equals($existingTargetPath, $managedTargetPath, [System.StringComparison]::Ordinal) -and
        [string]::Equals(([string]$existingArguments).Trim(), ([string]$managedArguments).Trim(), [System.StringComparison]::OrdinalIgnoreCase)
    ) {
        return $true
    }

    return $false
}

function Find-ManagedShortcutSpecByName {
    param(
        [object[]]$Specs,
        [string]$ShortcutBaseName
    )

    $shortcutNameKey = Get-NormalizedShortcutNameKey -Value $ShortcutBaseName
    foreach ($spec in @($Specs)) {
        if ($null -eq $spec) {
            continue
        }

        $specNameKey = Get-NormalizedShortcutNameKey -Value ([string]$spec.Name)
        if ([string]::Equals($shortcutNameKey, $specNameKey, [System.StringComparison]::Ordinal)) {
            return $spec
        }
    }

    return $null
}

function Find-ManagedShortcutSpecByDetails {
    param(
        [object[]]$Specs,
        [pscustomobject]$Details,
        [string]$ShortcutBaseName
    )

    foreach ($spec in @($Specs)) {
        if ($null -eq $spec) {
            continue
        }

        if (Test-ShortcutDetailsMatchManagedSpec -Details $Details -ShortcutBaseName $ShortcutBaseName -Spec $spec) {
            return $spec
        }
    }

    return $null
}

function Test-PublicDesktopAlreadyNormalized {
    param(
        [string]$PublicDesktopPath,
        [object[]]$Specs,
        [string[]]$OwnedShortcutNames = @()
    )

    foreach ($spec in @($Specs)) {
        if ($null -eq $spec) {
            continue
        }

        $managedShortcutPath = Join-Path $PublicDesktopPath (([string]$spec.Name) + '.lnk')
        if (-not (Test-Path -LiteralPath $managedShortcutPath)) {
            return $false
        }

        try {
            $managedDetails = Get-ShortcutDetails -ShortcutPath $managedShortcutPath
        }
        catch {
            return $false
        }

        if (-not (Test-ShortcutDetailsMatchManagedSpec -Details $managedDetails -ShortcutBaseName ([string]$spec.Name) -Spec $spec)) {
            return $false
        }
    }

    foreach ($existingShortcutFile in @(Get-ChildItem -LiteralPath $PublicDesktopPath -Filter "*.lnk" -File -ErrorAction SilentlyContinue)) {
        $shortcutBaseName = [System.IO.Path]::GetFileNameWithoutExtension([string]$existingShortcutFile.Name)
        $matchedSpec = Find-ManagedShortcutSpecByName -Specs $Specs -ShortcutBaseName $shortcutBaseName
        if ($null -ne $matchedSpec) {
            continue
        }

        if (@($OwnedShortcutNames) -contains [string]$shortcutBaseName) {
            return $false
        }

        try {
            $existingDetails = Get-ShortcutDetails -ShortcutPath ([string]$existingShortcutFile.FullName)
        }
        catch {
            return $false
        }

        if ($null -ne (Find-ManagedShortcutSpecByDetails -Specs $Specs -Details $existingDetails -ShortcutBaseName $shortcutBaseName)) {
            return $false
        }
    }

    return $true
}

function Test-ShortcutRemovalLockedMessage {
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace([string]$Message)) {
        return $false
    }

    $normalizedMessage = ([string]$Message).ToLowerInvariant()
    return (
        $normalizedMessage.Contains('because it is being used by another process') -or
        $normalizedMessage.Contains('being used by another process') -or
        $normalizedMessage.Contains('cannot access the file')
    )
}

function Test-ExistingPublicShortcutMatchesManagedSpec {
    param(
        [string]$ShortcutPath,
        [string]$ShortcutBaseName,
        [object]$Spec
    )

    if ([string]::IsNullOrWhiteSpace([string]$ShortcutPath) -or
        [string]::IsNullOrWhiteSpace([string]$ShortcutBaseName) -or
        $null -eq $Spec -or
        -not (Test-Path -LiteralPath $ShortcutPath)) {
        return $false
    }

    try {
        $existingDetails = Get-ShortcutDetails -ShortcutPath $ShortcutPath
    }
    catch {
        return $false
    }

    return (Test-ShortcutDetailsMatchManagedSpec -Details $existingDetails -ShortcutBaseName $ShortcutBaseName -Spec $Spec)
}

function Remove-ExistingPublicShortcut {
    param(
        [System.IO.FileInfo]$ShortcutFile,
        [string]$ShortcutBaseName,
        [object]$MatchedSpec,
        [int]$MaxAttempts = 6,
        [int]$RetryDelaySeconds = 2
    )

    if ($null -eq $ShortcutFile) {
        throw "Shortcut file metadata is required."
    }

    $shortcutPath = [string]$ShortcutFile.FullName
    $lastErrorMessage = ''

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction Stop
            return [pscustomobject]@{
                Removed = $true
                Retained = $false
            }
        }
        catch {
            $lastErrorMessage = [string]$_.Exception.Message
            if (($null -ne $MatchedSpec) -and
                (Test-ShortcutRemovalLockedMessage -Message $lastErrorMessage) -and
                (Test-ExistingPublicShortcutMatchesManagedSpec -ShortcutPath $shortcutPath -ShortcutBaseName $ShortcutBaseName -Spec $MatchedSpec)) {
                Write-Host ("public-desktop-retained: {0} => locked-managed-shortcut" -f $ShortcutFile.Name)
                return [pscustomobject]@{
                    Removed = $false
                    Retained = $true
                }
            }

            if (($attempt -lt $MaxAttempts) -and (Test-ShortcutRemovalLockedMessage -Message $lastErrorMessage)) {
                Write-Host ("public-desktop-remove-retry: {0} => attempt {1}/{2}" -f $ShortcutFile.Name, $attempt, $MaxAttempts)
                Start-Sleep -Seconds $RetryDelaySeconds
                continue
            }

            throw ("Failed to remove existing public shortcut '{0}': {1}" -f $shortcutPath, $lastErrorMessage)
        }
    }

    throw ("Failed to remove existing public shortcut '{0}': {1}" -f $shortcutPath, $lastErrorMessage)
}

function Resolve-IconLocation {
    param(
        [string]$PreferredPath,
        [string]$FallbackPath
    )

    $iconTarget = [string]$FallbackPath
    if (-not [string]::IsNullOrWhiteSpace([string]$PreferredPath)) {
        $iconTarget = [string]$PreferredPath
    }

    return ($iconTarget + ",0")
}

Refresh-SessionPath
Ensure-Directory -Path $publicDesktop
Ensure-Directory -Path $publicChromeUserDataDir

$explorerExe = Resolve-CommandPath -CommandName "explorer.exe" -FallbackCandidates @("C:\Windows\explorer.exe")
$chromeExe = Resolve-CommandPath -CommandName "chrome.exe" -FallbackCandidates @(
    "C:\Program Files\Google\Chrome\Application\chrome.exe",
    "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
)
$chromeTarget = Resolve-ExistingOrFallbackPath -PreferredPath "C:\Program Files\Google\Chrome\Application\chrome.exe" -ResolvedPath $chromeExe -FallbackPath "C:\Program Files\Google\Chrome\Application\chrome.exe"
$controlExe = Resolve-CommandPath -CommandName "control.exe" -FallbackCandidates @("C:\Windows\System32\control.exe")
$cmdExe = Resolve-CommandPath -CommandName "cmd.exe" -FallbackCandidates @("C:\Windows\System32\cmd.exe")
$powershellExe = Resolve-CommandPath -CommandName "powershell.exe" -FallbackCandidates @("C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe")
$pwshExe = Resolve-CommandPath -CommandName "pwsh.exe" -FallbackCandidates @("C:\Program Files\PowerShell\7\pwsh.exe")
$dockerDesktopExe = Resolve-ExistingOrFallbackPath -PreferredPath "C:\Program Files\Docker\Docker\Docker Desktop.exe" -ResolvedPath (Resolve-CommandPath -CommandName "Docker Desktop.exe" -FallbackCandidates @("C:\Program Files\Docker\Docker\Docker Desktop.exe")) -FallbackPath "C:\Program Files\Docker\Docker\Docker Desktop.exe"
$gitBashExe = Resolve-CommandPath -CommandName "git-bash.exe" -FallbackCandidates @("C:\Program Files\Git\git-bash.exe")
$pythonExe = Resolve-CommandPath -CommandName "python.exe" -FallbackCandidates @("C:\Python312\python.exe")
$nodeExe = Resolve-CommandPath -CommandName "node.exe" -FallbackCandidates @("C:\Program Files\nodejs\node.exe")
$rcloneExe = Resolve-CommandPath -CommandName "rclone.exe" -FallbackCandidates @(
    "C:\ProgramData\chocolatey\bin\rclone.exe",
    "C:\Program Files\rclone\rclone.exe"
)
$wslExe = Resolve-CommandPath -CommandName "wsl.exe" -FallbackCandidates @("C:\Windows\System32\wsl.exe")
$dockerExe = Resolve-CommandPath -CommandName "docker.exe" -FallbackCandidates @("C:\Program Files\Docker\Docker\resources\bin\docker.exe")
$azExe = Resolve-CommandPath -CommandName "az.cmd" -FallbackCandidates @(
    "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd",
    "C:\ProgramData\chocolatey\bin\az.cmd"
)
$azdExe = Resolve-CommandPath -CommandName "azd.exe" -FallbackCandidates @("C:\Program Files\Azure Developer CLI\azd.exe")
$ghExe = Resolve-CommandPath -CommandName "gh.exe" -FallbackCandidates @("C:\Program Files\GitHub CLI\gh.exe")
$ffmpegExe = Resolve-CommandPath -CommandName "ffmpeg.exe" -FallbackCandidates @("C:\ProgramData\chocolatey\bin\ffmpeg.exe")
$sevenZipExe = Resolve-CommandPath -CommandName "7z.exe" -FallbackCandidates @(
    "C:\ProgramData\chocolatey\bin\7z.exe",
    "C:\Program Files\7-Zip\7z.exe",
    "C:\Program Files\7-Zip\7zFM.exe"
)
$processExplorerExe = Resolve-CommandPath -CommandName "procexp64.exe" -FallbackCandidates @(
    "C:\ProgramData\chocolatey\lib\sysinternals\tools\procexp64.exe",
    "C:\ProgramData\chocolatey\bin\procexp64.exe",
    "C:\ProgramData\chocolatey\bin\procexp.exe",
    "C:\Windows\System32\procexp64.exe"
)
$ioUnlockerExe = Resolve-CommandPath -CommandName "IObitUnlocker.exe" -FallbackCandidates @(
    "C:\Program Files (x86)\IObit\IObit Unlocker\IObitUnlocker.exe",
    "C:\Program Files\IObit\IObit Unlocker\IObitUnlocker.exe",
    "C:\ProgramData\chocolatey\bin\IObitUnlocker.exe"
)
$anyDeskExe = Resolve-ExistingOrFallbackPath -PreferredPath "C:\Program Files (x86)\AnyDesk\AnyDesk.exe" -ResolvedPath (Resolve-CommandPath -CommandName "AnyDesk.exe" -FallbackCandidates @(
    "C:\Program Files (x86)\AnyDesk\AnyDesk.exe",
    "C:\Program Files\AnyDesk\AnyDesk.exe"
)) -FallbackPath "C:\Program Files (x86)\AnyDesk\AnyDesk.exe"
$windscribeExe = Resolve-CommandPath -CommandName "Windscribe.exe" -FallbackCandidates @(
    "C:\Program Files\Windscribe\Windscribe.exe",
    "C:\Program Files (x86)\Windscribe\Windscribe.exe"
)
$vs2022CommunityExe = Resolve-Vs2022CommunityExecutablePath
$vsCodeCmdPath = Resolve-ExistingOrFallbackPath -PreferredPath ("%LocalAppData%\Programs\Microsoft VS Code\bin\code.cmd") -ResolvedPath (Resolve-CommandPath -CommandName "code.cmd" -FallbackCandidates @(
    ("C:\Users\{0}\AppData\Local\Programs\Microsoft VS Code\bin\code.cmd" -f $managerUser),
    ("C:\Users\{0}\AppData\Local\Programs\Microsoft VS Code\bin\code.cmd" -f $assistantUser)
)) -FallbackPath ("%LocalAppData%\Programs\Microsoft VS Code\bin\code.cmd")
$codexCmdResolvedPath = Resolve-CommandPath -CommandName "codex.cmd" -FallbackCandidates @(
    ("C:\Users\{0}\AppData\Roaming\npm\codex.cmd" -f $managerUser),
    ("C:\Users\{0}\AppData\Roaming\npm\codex.cmd" -f $assistantUser),
    "C:\Program Files\nodejs\codex.cmd"
)
$codexCmdPath = if (-not [string]::IsNullOrWhiteSpace([string]$codexCmdResolvedPath) -and $codexCmdResolvedPath.ToLowerInvariant().Contains('\users\')) {
    '%UserProfile%\AppData\Roaming\npm\codex.cmd'
}
elseif (-not [string]::IsNullOrWhiteSpace([string]$codexCmdResolvedPath)) {
    [string]$codexCmdResolvedPath
}
else {
    ''
}
$geminiCmdResolvedPath = Resolve-CommandPath -CommandName "gemini.cmd" -FallbackCandidates @(
    ("C:\Users\{0}\AppData\Roaming\npm\gemini.cmd" -f $managerUser),
    ("C:\Users\{0}\AppData\Roaming\npm\gemini.cmd" -f $assistantUser),
    "C:\Program Files\nodejs\gemini.cmd"
)
$geminiCmdPath = if (-not [string]::IsNullOrWhiteSpace([string]$geminiCmdResolvedPath) -and $geminiCmdResolvedPath.ToLowerInvariant().Contains('\users\')) {
    '%UserProfile%\AppData\Roaming\npm\gemini.cmd'
}
elseif (-not [string]::IsNullOrWhiteSpace([string]$geminiCmdResolvedPath)) {
    [string]$geminiCmdResolvedPath
}
else {
    ''
}
$itunesExe = Resolve-ExistingOrFallbackPath -PreferredPath "C:\Program Files\iTunes\iTunes.exe" -ResolvedPath (Resolve-CommandPath -CommandName "iTunes.exe" -FallbackCandidates @(
    "C:\Program Files\iTunes\iTunes.exe",
    "C:\Program Files (x86)\iTunes\iTunes.exe"
)) -FallbackPath "C:\Program Files\iTunes\iTunes.exe"
$nvdaExe = "C:\Program Files (x86)\NVDA\nvda.exe"
$jawsExe = Resolve-JawsExecutablePath
$edgeExe = Resolve-ExistingOrFallbackPath -PreferredPath "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" -ResolvedPath (Resolve-CommandPath -CommandName "msedge.exe" -FallbackCandidates @(
    "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
)) -FallbackPath "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
$vlcExe = Resolve-ExistingOrFallbackPath -PreferredPath "C:\Program Files\VideoLAN\VLC\vlc.exe" -ResolvedPath (Resolve-CommandPath -CommandName "vlc.exe" -FallbackCandidates @(
    "C:\Program Files\VideoLAN\VLC\vlc.exe",
    "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe"
)) -FallbackPath "C:\Program Files\VideoLAN\VLC\vlc.exe"
$oneDriveResolvedPath = Resolve-CommandPath -CommandName "OneDrive.exe" -FallbackCandidates @(
    "C:\Program Files\Microsoft OneDrive\OneDrive.exe",
    ("C:\Users\{0}\AppData\Local\Microsoft\OneDrive\OneDrive.exe" -f $managerUser),
    ("C:\Users\{0}\AppData\Local\Microsoft\OneDrive\OneDrive.exe" -f $assistantUser)
)
$oneDriveExe = if (-not [string]::IsNullOrWhiteSpace([string]$oneDriveResolvedPath) -and $oneDriveResolvedPath.ToLowerInvariant().Contains('\users\')) {
    '%LocalAppData%\Microsoft\OneDrive\OneDrive.exe'
}
else {
    Resolve-ExistingOrFallbackPath -PreferredPath "C:\Program Files\Microsoft OneDrive\OneDrive.exe" -ResolvedPath $oneDriveResolvedPath -FallbackPath "%LocalAppData%\Microsoft\OneDrive\OneDrive.exe"
}
$googleDriveResolvedExe = Resolve-CommandPath -CommandName "GoogleDriveFS.exe" -FallbackCandidates @("C:\Program Files\Google\Drive File Stream\GoogleDriveFS.exe")
if ([string]::IsNullOrWhiteSpace([string]$googleDriveResolvedExe)) {
    $googleDriveResolvedExe = Resolve-ExecutableUnderDirectory -RootPaths @("C:\Program Files\Google\Drive File Stream") -ExecutableName "GoogleDriveFS.exe"
}
$googleDriveExe = Resolve-ExistingOrFallbackPath -PreferredPath "C:\Program Files\Google\Drive File Stream\GoogleDriveFS.exe" -ResolvedPath $googleDriveResolvedExe -FallbackPath "C:\Program Files\Google\Drive File Stream\GoogleDriveFS.exe"
$iCloudExe = Resolve-ICloudExecutablePath

Ensure-ManagedUserStoreAppRegistration -RepairTaskName '10003-teams' -DisplayName 'Microsoft Teams' -NameFragment 'teams' -PackageNameHints @('teams')
Ensure-ManagedUserStoreAppRegistration -RepairTaskName '10003-bemyeyes' -DisplayName 'Be My Eyes' -NameFragment 'bemyeyes' -PackageNameHints @('be my eyes', 'bemyeyes', $beMyEyesStoreProductId)
Ensure-ManagedUserStoreAppRegistration -RepairTaskName '10003-codex' -DisplayName 'Codex app' -NameFragment 'codex' -PackageNameHints @('OpenAI.Codex', '2p2nqsd0c76g0', '9PLM9XGG6VKS')
Ensure-ManagedUserStoreAppRegistration -RepairTaskName '10003-whatsapp' -DisplayName 'WhatsApp Business' -NameFragment 'whatsapp' -PackageNameHints @('whatsapp', '5319275A.WhatsAppDesktop', '9NKSQGP7F2NH')
Ensure-ManagedUserStoreAppRegistration -RepairTaskName '10003-icloud' -DisplayName 'iCloud' -NameFragment 'icloud' -PackageNameHints @('AppleInc.iCloud', '9PKTQ5699M62', 'icloud')

$teamsAppId = Resolve-StoreAppId -NameFragment "teams" -PackageNameHints @("teams")
$teamsExe = Resolve-CommandPath -CommandName "ms-teams.exe" -FallbackCandidates @("C:\Program Files\WindowsApps\MSTeams_8wekyb3d8bbwe\ms-teams.exe")
$windscribeAppId = Resolve-StoreAppId -NameFragment "windscribe" -PackageNameHints @("windscribe")
$beMyEyesAppId = Resolve-StoreAppId -NameFragment "be my eyes" -PackageNameHints @("be my eyes", $beMyEyesStoreProductId)
$codexAppId = Resolve-StoreAppId -NameFragment "codex" -PackageNameHints @("OpenAI.Codex", "2p2nqsd0c76g0", "9PLM9XGG6VKS")
$codexAppResolvedExe = Resolve-AppPackageExecutablePath -NameFragment "codex" -PackageNameHints @("OpenAI.Codex", "2p2nqsd0c76g0", "9PLM9XGG6VKS") -ExecutableName "Codex.exe"
$whatsAppBusinessAppId = Resolve-StoreAppId -NameFragment "whatsapp" -PackageNameHints @("whatsapp", "5319275A.WhatsAppDesktop", "9NKSQGP7F2NH")
$whatsAppRootExe = Resolve-AppPackageExecutablePath -NameFragment "whatsapp" -PackageNameHints @("whatsapp", "5319275A.WhatsAppDesktop") -ExecutableName "WhatsApp.Root.exe"
$iCloudAppId = Resolve-ICloudAppId

$outlookExe = Resolve-OfficeExecutable -ExeName "OUTLOOK.EXE"
$wordExe = Resolve-OfficeExecutable -ExeName "WINWORD.EXE"
$excelExe = Resolve-OfficeExecutable -ExeName "EXCEL.EXE"
$powerPointExe = Resolve-OfficeExecutable -ExeName "POWERPNT.EXE"
$oneNoteExe = Resolve-OfficeExecutable -ExeName "ONENOTE.EXE"

$codexAppExe = if (-not [string]::IsNullOrWhiteSpace([string]$codexAppResolvedExe) -and (Test-Path -LiteralPath $codexAppResolvedExe)) {
    [string]$codexAppResolvedExe
}
else {
    ''
}
$whatsAppBusinessTarget = Resolve-ExistingOrFallbackPath -PreferredPath $whatsAppRootExe -ResolvedPath $whatsAppRootExe -FallbackPath $whatsAppFallbackPath
$edgeBusinessArgs = Get-EdgeArgsPrefix -ProfileKind 'business' -Variant 'remote'
$sevenZipCliPath = Resolve-ExistingOrFallbackPath -PreferredPath "C:\ProgramData\chocolatey\bin\7z.exe" -ResolvedPath $sevenZipExe -FallbackPath "C:\ProgramData\chocolatey\bin\7z.exe"

$shortcutSpecs = New-Object 'System.Collections.Generic.List[object]'
$cicekSepetiLabel = ConvertFrom-UnicodeCodePoints -CodePoints @(0x00C7, 0x0069, 0x00E7, 0x0065, 0x006B, 0x0053, 0x0065, 0x0070, 0x0065, 0x0074, 0x0069)
$eksiSozlukLabel = ConvertFrom-UnicodeCodePoints -CodePoints @(0x0045, 0x006B, 0x015F, 0x0069, 0x0053, 0x00F6, 0x007A, 0x006C, 0x00FC, 0x006B)
$r13CicekSepetiBusinessName = ('r13{0} Business' -f $cicekSepetiLabel)
$r14CicekSepetiPersonalName = ('r14{0} Personal' -f $cicekSepetiLabel)
$q1EksiSozlukName = ('q1{0}' -f $eksiSozlukLabel)

$socialWebShortcuts = @(
    @{ Name = "s1LinkedIn Business"; Url = $socialBusinessLinkedInUrl; ProfileKind = "business" },
    @{ Name = "s2LinkedIn Personal"; Url = $socialPersonalLinkedInUrl; ProfileKind = "personal" },
    @{ Name = "s3YouTube Business"; Url = $socialBusinessYouTubeUrl; ProfileKind = "business" },
    @{ Name = "s4YouTube Personal"; Url = $socialPersonalYouTubeUrl; ProfileKind = "personal" },
    @{ Name = "s5GitHub Business"; Url = $socialBusinessGitHubUrl; ProfileKind = "business" },
    @{ Name = "s6GitHub Personal"; Url = $socialPersonalGitHubUrl; ProfileKind = "personal" },
    @{ Name = "s7TikTok Business"; Url = $socialBusinessTikTokUrl; ProfileKind = "business" },
    @{ Name = "s8TikTok Personal"; Url = $socialPersonalTikTokUrl; ProfileKind = "personal" },
    @{ Name = "s9Instagram Business"; Url = $socialBusinessInstagramUrl; ProfileKind = "business" },
    @{ Name = "s10Instagram Personal"; Url = $socialPersonalInstagramUrl; ProfileKind = "personal" },
    @{ Name = "s11Facebook Business"; Url = $socialBusinessFacebookUrl; ProfileKind = "business" },
    @{ Name = "s12Facebook Personal"; Url = $socialPersonalFacebookUrl; ProfileKind = "personal" },
    @{ Name = "s13X-Twitter Business"; Url = $socialBusinessXUrl; ProfileKind = "business" },
    @{ Name = "s14X-Twitter Personal"; Url = $socialPersonalXUrl; ProfileKind = "personal" },
    @{ Name = ("s15{0} Web" -f $companyDisplayName); Url = $companyWebRootUrl; ProfileKind = "business" },
    @{ Name = ("s16{0} Blog" -f $companyDisplayName); Url = $companyBlogUrl; ProfileKind = "business" },
    @{ Name = "s17SnapChat Business"; Url = $socialBusinessSnapchatUrl; ProfileKind = "business" },
    @{ Name = "s18NextSosyal Business"; Url = $socialBusinessNextSosyalUrl; ProfileKind = "business" }
)
$bankShortcuts = @(
    @{ Name = "b1GarantiBank Business"; Url = "https://sube.garantibbva.com.tr/isube/login/login/passwordentrycorporate-tr"; ProfileKind = "business" },
    @{ Name = "b2GarantiBank Personal"; Url = "https://sube.garantibbva.com.tr/isube/login/login/passwordentrypersonal-tr"; ProfileKind = "personal" },
    @{ Name = "b3QnbBank Business"; Url = "https://internetsubesi.qnb.com.tr/Login/LoginPage.aspx?FromDK=true"; ProfileKind = "business" },
    @{ Name = "b4QnbBank Personal"; Url = "https://internetsubesi.qnb.com.tr/Login/LoginPage.aspx"; ProfileKind = "personal" },
    @{ Name = "b5AktifBank Business"; Url = "https://kurumsal.aktifbank.com.tr/default.aspx?lang=tr-TR"; ProfileKind = "business" },
    @{ Name = "b6AktifBank Personal"; Url = "https://online.aktifbank.com.tr/default.aspx?lang=tr-TR"; ProfileKind = "personal" },
    @{ Name = "b7ZiraatBank Business"; Url = "https://kurumsal.ziraatbank.com.tr/Transactions/Login/FirstLogin.aspx?customertype=crp"; ProfileKind = "business" },
    @{ Name = "b8ZiraatBank Personal"; Url = "https://bireysel.ziraatbank.com.tr/Transactions/Login/FirstLogin.aspx"; ProfileKind = "personal" }
)
$developerWebShortcuts = @(
    @{ Name = "g1Apple Developer"; Url = "https://developer.apple.com/account" },
    @{ Name = "g2Google Developer"; Url = "https://play.google.com/console/signin" },
    @{ Name = "g3Microsoft Developer"; Url = "https://aka.ms/submitwindowsapp" },
    @{ Name = "g4Azure Portal"; Url = "https://portal.azure.com" }
)
$marketplaceWebShortcuts = @(
    @{ Name = "m1Digital Tax Office"; Url = "https://dijital.gib.gov.tr/portal/login"; ProfileKind = "business" },
    @{ Name = "r1Sahibinden Business"; Url = "https://secure.sahibinden.com/giris"; ProfileKind = "business" },
    @{ Name = "r2Sahibinden Personal"; Url = "https://www.sahibinden.com"; ProfileKind = "personal" },
    @{ Name = "r3Letgo Business"; Url = "https://www.letgo.com"; ProfileKind = "business" },
    @{ Name = "r4Letgo Personal"; Url = "https://www.letgo.com"; ProfileKind = "personal" },
    @{ Name = "r5Trendyol Business"; Url = "https://partner.trendyol.com"; ProfileKind = "business" },
    @{ Name = "r6Trendyol Personal"; Url = "https://www.trendyol.com/uyelik"; ProfileKind = "personal" },
    @{ Name = "r7Amazon TR Business"; Url = "https://sellercentral.amazon.com.tr"; ProfileKind = "business" },
    @{ Name = "r8Amazon TR Personal"; Url = "https://www.amazon.com.tr/ap/signin"; ProfileKind = "personal" },
    @{ Name = "r9HepsiBurada Business"; Url = "https://merchant.hepsiburada.com"; ProfileKind = "business" },
    @{ Name = "r10HepsiBurada Personal"; Url = "https://giris.hepsiburada.com"; ProfileKind = "personal" },
    @{ Name = "r11N11 Business"; Url = "https://so.n11.com"; ProfileKind = "business" },
    @{ Name = "r12N11 Personal"; Url = "https://www.n11.com/giris-yap"; ProfileKind = "personal" },
    @{ Name = $r13CicekSepetiBusinessName; Url = "https://seller.ciceksepeti.com/giris"; ProfileKind = "business"; CleanupAliases = @("r13CicekSepeti Business") },
    @{ Name = $r14CicekSepetiPersonalName; Url = "https://www.ciceksepeti.com/uye-girisi"; ProfileKind = "personal"; CleanupAliases = @("r14CicekSepeti Personal") },
    @{ Name = "r15Pazarama Business"; Url = "https://isortagim.pazarama.com"; ProfileKind = "business" },
    @{ Name = "r16Pazarama Personal"; Url = "https://account.pazarama.com/giris"; ProfileKind = "personal" },
    @{ Name = "r17PTTAVM Business"; Url = "https://merchant.pttavm.com/magaza-giris"; ProfileKind = "business" },
    @{ Name = "r18PTTAVM Personal"; Url = "https://www.pttavm.com"; ProfileKind = "personal" },
    @{ Name = "r19Ozon Business"; Url = "https://seller.ozon.ru/app/registration/signin?locale=en"; ProfileKind = "business" },
    @{ Name = "r20Ozon Personal"; Url = "https://www-ozon-ru.translate.goog/?_x_tr_sl=ru&_x_tr_tl=en&_x_tr_hl=en&_x_tr_hist=true"; ProfileKind = "personal" },
    @{ Name = "r21Getir Business"; Url = "https://panel.getircarsi.com/login"; ProfileKind = "business" },
    @{ Name = "r22Getir Personal"; Url = "https://getir.com"; ProfileKind = "personal" }
)
$quickAccessWebShortcuts = @(
    @{ Name = $q1EksiSozlukName; Url = "https://www.eksisozluk.com"; ProfileKind = "business"; CleanupAliases = @("q1SourTimes", "q1Eksisozluk") },
    @{ Name = "q2Spotify"; Url = "https://accounts.spotify.com/en/login?continue=https%3A%2F%2Fopen.spotify.com" },
    @{ Name = "q3Netflix"; Url = "https://www.netflix.com/tr-en/login" },
    @{ Name = "q4eGovernment"; Url = "https://www.turkiye.gov.tr" },
    @{ Name = "q5Apple Account"; Url = "https://account.apple.com/sign-in" },
    @{ Name = "q6AJet Flights"; Url = "https://ajet.com" },
    @{ Name = "q7TCDD Train"; Url = "https://ebilet.tcddtasimacilik.gov.tr" },
    @{ Name = "q8OBilet Bus"; Url = "https://www.obilet.com/?giris" }
)

Add-Spec -List $shortcutSpecs -Spec (New-ChromeShortcutSpec -Name "a1ChatGPT Web" -Url "https://chatgpt.com" -ProfileKind 'business' -Variant 'remote')
if (-not [string]::IsNullOrWhiteSpace([string]$codexAppId)) {
    Add-StoreManagedShortcutSpec -List $shortcutSpecs -ShortcutName 'a2CodexApp' -TaskName '120-install-codex-application' -AppId $codexAppId -ExecutablePath $codexAppExe
}
elseif (-not [string]::IsNullOrWhiteSpace([string]$codexAppExe)) {
    Add-StoreManagedShortcutSpec -List $shortcutSpecs -ShortcutName 'a2CodexApp' -TaskName '120-install-codex-application' -AppId '' -ExecutablePath $codexAppExe
}
if (-not [string]::IsNullOrWhiteSpace([string]$beMyEyesAppId)) {
    Add-StoreManagedShortcutSpec -List $shortcutSpecs -ShortcutName 'a3Be My Eyes' -TaskName '118-install-be-my-eyes-application-application' -AppId $beMyEyesAppId
}
else {
    Add-StoreManagedShortcutSpec -List $shortcutSpecs -ShortcutName 'a3Be My Eyes' -TaskName '118-install-be-my-eyes-application-application' -AppId ''
}
if (-not [string]::IsNullOrWhiteSpace([string]$whatsAppBusinessAppId)) {
    Add-StoreManagedShortcutSpec -List $shortcutSpecs -ShortcutName 'a4WhatsApp Business' -TaskName '119-install-whatsapp-application' -AppId $whatsAppBusinessAppId -ExecutablePath $whatsAppBusinessTarget
}
else {
    Add-StoreManagedShortcutSpec -List $shortcutSpecs -ShortcutName 'a4WhatsApp Business' -TaskName '119-install-whatsapp-application' -AppId '' -ExecutablePath $whatsAppBusinessTarget
}
Add-Spec -List $shortcutSpecs -Spec (New-ChromeShortcutSpec -Name "a5WhatsApp Personal" -Url "https://web.whatsapp.com" -ProfileKind 'personal' -Variant 'remote')
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "a6AnyDesk" -TargetPath $anyDeskExe -AllowMissingTargetPath $true -ValidationKind "app" -CleanupAliases @("AnyDesk") -CleanupMatchTargetOnly $true)
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "a7Docker Desktop" -TargetPath $dockerDesktopExe -AllowMissingTargetPath $true -ValidationKind "app")
if (-not [string]::IsNullOrWhiteSpace([string]$windscribeExe)) {
    Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "a8WindScribe" -TargetPath $windscribeExe -AllowMissingTargetPath $true -ValidationKind "app" -CleanupAliases @("Windscribe") -CleanupMatchTargetOnly $true)
}
elseif (-not [string]::IsNullOrWhiteSpace([string]$windscribeAppId)) {
    Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "a8WindScribe" -TargetPath $explorerExe -Arguments ("shell:AppsFolder\" + $windscribeAppId) -IconLocation ($explorerExe + ",0") -ValidationKind "store-appid" -CleanupAliases @("Windscribe"))
}
else {
    Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "a8WindScribe" -TargetPath "C:\Program Files\Windscribe\Windscribe.exe" -AllowMissingTargetPath $true -ValidationKind "app" -CleanupAliases @("Windscribe") -CleanupMatchTargetOnly $true)
}
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "a9VLC Player" -TargetPath $vlcExe -AllowMissingTargetPath $true -ValidationKind "app" -CleanupAliases @("VLC media player") -CleanupMatchTargetOnly $true)
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "a10NVDA" -TargetPath $nvdaExe -Hotkey "Ctrl+Alt+N" -AllowMissingTargetPath $true -ValidationKind "app" -CleanupAliases @("NVDA") -CleanupAliasMatchByNameOnly $true)
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "a11MS Edge" -TargetPath $edgeExe -Arguments $edgeBusinessArgs -IconLocation ($edgeExe + ",0") -AllowMissingTargetPath $true -ValidationKind "edge-remote" -CleanupAliases @("Microsoft Edge"))
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "a12Itunes" -TargetPath $itunesExe -AllowMissingTargetPath $true -ValidationKind "app" -CleanupAliases @("iTunes") -CleanupMatchTargetOnly $true)

foreach ($spec in @($bankShortcuts)) {
    Add-Spec -List $shortcutSpecs -Spec (New-ChromeShortcutSpec -Name ([string]$spec.Name) -Url ([string]$spec.Url) -ProfileKind ([string]$spec.ProfileKind) -Variant 'bank')
}

Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "c1Cmd" -TargetPath $cmdExe -Arguments "/k cd /d %UserProfile%" -WorkingDirectory "%UserProfile%" -IconLocation ($cmdExe + ",0") -ValidationKind "console")

Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "d1RClone CLI" -TargetPath $cmdExe -Arguments "/k cd /d %UserProfile% & rclone" -WorkingDirectory "%UserProfile%" -IconLocation (Resolve-IconLocation -PreferredPath $rcloneExe -FallbackPath $cmdExe) -ValidationKind "console")
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "d2One Drive" -TargetPath $oneDriveExe -AllowMissingTargetPath $true -ValidationKind "app")
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "d3Google Drive" -TargetPath $googleDriveExe -AllowMissingTargetPath $true -ValidationKind "app")
if (-not [string]::IsNullOrWhiteSpace([string]$iCloudAppId)) {
    Add-StoreManagedShortcutSpec -List $shortcutSpecs -ShortcutName 'd4ICloud' -TaskName '122-install-icloud-application' -AppId $iCloudAppId -ExecutablePath $iCloudExe
}
else {
    Add-StoreManagedShortcutSpec -List $shortcutSpecs -ShortcutName 'd4ICloud' -TaskName '122-install-icloud-application' -AppId '' -ExecutablePath $iCloudExe
}
$mailShortcutArguments = if (-not [string]::IsNullOrWhiteSpace([string]$outlookExe)) {
    ('/c start "" "{0}" /select "outlook:\\{1}\\Inbox"' -f $outlookExe, $employeeEmailAddress)
}
else {
    ('/c start outlook.exe /select "outlook:\\{0}\\Inbox"' -f $employeeEmailAddress)
}
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name ("e1Mail {0}" -f $employeeEmailAddress) -TargetPath $cmdExe -Arguments $mailShortcutArguments -IconLocation (Resolve-IconLocation -PreferredPath $outlookExe -FallbackPath $cmdExe) -AllowMissingTargetPath $true -ValidationKind "app")

foreach ($spec in @($developerWebShortcuts)) {
    Add-Spec -List $shortcutSpecs -Spec (New-ChromeShortcutSpec -Name ([string]$spec.Name) -Url ([string]$spec.Url) -ProfileKind 'business' -Variant 'remote')
}

Add-Spec -List $shortcutSpecs -Spec (New-ChromeShortcutSpec -Name "i1Internet Business" -Url $companyWebRootUrl -ProfileKind 'business' -Variant 'remote' -CleanupAliases @("Google Chrome", "Chrome"))
Add-Spec -List $shortcutSpecs -Spec (New-ChromeShortcutSpec -Name "i2Internet Personal" -Url "https://www.google.com" -ProfileKind 'personal' -Variant 'remote')
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "j0Jaws" -TargetPath $jawsExe -Hotkey "Ctrl+Shift+J" -AllowMissingTargetPath $true -ValidationKind "app" -CleanupAliases @("JAWS") -CleanupAliasMatchByNameOnly $true)

$codexCliLaunchCommand = if (-not [string]::IsNullOrWhiteSpace([string]$codexCmdPath)) {
    ('/c start "" /max /high "{0}" -c model_reasoning_summary=detailed -c hide_agent_reasoning=false -c show_raw_agent_reasoning=true -c tui.animations=true --enable multi_agent --enable fast_mode --yolo -s danger-full-access --cd "%UserProfile%" --search' -f $codexCmdPath)
}
else {
    '/c start "" /max /high codex -c model_reasoning_summary=detailed -c hide_agent_reasoning=false -c show_raw_agent_reasoning=true -c tui.animations=true --enable multi_agent --enable fast_mode --yolo -s danger-full-access --cd "%UserProfile%" --search'
}
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "k1Codex CLI" -TargetPath $cmdExe -Arguments $codexCliLaunchCommand -WorkingDirectory "%UserProfile%" -IconLocation (Resolve-IconLocation -PreferredPath $codexCmdResolvedPath -FallbackPath $cmdExe) -AllowMissingTargetPath $true -ValidationKind "console")
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "k2Gemini CLI" -TargetPath $cmdExe -Arguments ('/c cd /d %UserProfile% & start "" "{0}" --screen-reader --yolo' -f $geminiCmdPath) -WorkingDirectory "%UserProfile%" -IconLocation ($cmdExe + ",0") -AllowMissingTargetPath $true -ValidationKind "console")
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "k3Github Copilot CLI" -TargetPath $cmdExe -Arguments '/c cd /d %UserProfile% & %UserProfile%\AppData\Roaming\npm\copilot.cmd --screen-reader --yolo --no-ask-user --model claude-haiku-4.5' -WorkingDirectory "%UserProfile%" -IconLocation ($cmdExe + ",0") -AllowMissingTargetPath $true -ValidationKind "console")

foreach ($spec in @($marketplaceWebShortcuts)) {
    $cleanupAliases = if ($spec.ContainsKey('CleanupAliases')) { @($spec.CleanupAliases) } else { @() }
    Add-Spec -List $shortcutSpecs -Spec (New-ChromeShortcutSpec -Name ([string]$spec.Name) -Url ([string]$spec.Url) -ProfileKind ([string]$spec.ProfileKind) -Variant 'remote' -CleanupAliases $cleanupAliases)
}

Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "n1Notepad" -TargetPath "C:\Windows\System32\notepad.exe" -ValidationKind "app")

Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "o1Outlook" -TargetPath $outlookExe -AllowMissingTargetPath $true -ValidationKind "office")
if (-not [string]::IsNullOrWhiteSpace([string]$teamsAppId)) {
    Add-StoreManagedShortcutSpec -List $shortcutSpecs -ShortcutName 'o2Teams' -TaskName '114-install-teams-application' -AppId $teamsAppId -ExecutablePath $teamsExe
}
else {
    Add-StoreManagedShortcutSpec -List $shortcutSpecs -ShortcutName 'o2Teams' -TaskName '114-install-teams-application' -AppId '' -ExecutablePath $teamsExe
}
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "o3Word" -TargetPath $wordExe -AllowMissingTargetPath $true -ValidationKind "office")
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "o4Excel" -TargetPath $excelExe -AllowMissingTargetPath $true -ValidationKind "office")
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "o5Power Point" -TargetPath $powerPointExe -AllowMissingTargetPath $true -ValidationKind "office")
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "o6OneNote" -TargetPath $oneNoteExe -AllowMissingTargetPath $true -ValidationKind "office")

foreach ($spec in @($quickAccessWebShortcuts)) {
    $profileKind = if ($spec.ContainsKey('ProfileKind')) { [string]$spec.ProfileKind } else { 'business' }
    $cleanupAliases = if ($spec.ContainsKey('CleanupAliases')) { @($spec.CleanupAliases) } else { @() }
    Add-Spec -List $shortcutSpecs -Spec (New-ChromeShortcutSpec -Name ([string]$spec.Name) -Url ([string]$spec.Url) -ProfileKind $profileKind -Variant 'remote' -CleanupAliases $cleanupAliases)
}

foreach ($spec in @($socialWebShortcuts)) {
    Add-Spec -List $shortcutSpecs -Spec (New-ChromeShortcutSpec -Name ([string]$spec.Name) -Url ([string]$spec.Url) -ProfileKind ([string]$spec.ProfileKind) -Variant 'remote')
}

Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "t1Git Bash" -TargetPath $gitBashExe -WorkingDirectory "%UserProfile%" -AllowMissingTargetPath $true -ValidationKind "console")
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "t2Python CLI" -TargetPath $cmdExe -Arguments "/c cd /d %UserProfile% & python" -WorkingDirectory "%UserProfile%" -IconLocation (Resolve-IconLocation -PreferredPath $pythonExe -FallbackPath $cmdExe) -ValidationKind "console")
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "t3NodeJS CLI" -TargetPath $cmdExe -Arguments "/c cd /d %UserProfile% & node" -WorkingDirectory "%UserProfile%" -IconLocation (Resolve-IconLocation -PreferredPath $nodeExe -FallbackPath $cmdExe) -ValidationKind "console")
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "t4Ollama App" -TargetPath $cmdExe -Arguments '/c cd /d %UserProfile% & TaskKill -im "ollama app.exe" & start "" "%LOCALAPPDATA%\Programs\Ollama\ollama app.exe"' -WorkingDirectory "%UserProfile%" -IconLocation ($cmdExe + ",0") -ValidationKind "console")
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "t5Pwsh" -TargetPath $cmdExe -Arguments "/k cd /d %UserProfile% & pwsh" -WorkingDirectory "%UserProfile%" -IconLocation (Resolve-IconLocation -PreferredPath $pwshExe -FallbackPath $cmdExe) -ValidationKind "console")
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "t6PS" -TargetPath $cmdExe -Arguments "/k cd /d %UserProfile% & powershell" -WorkingDirectory "%UserProfile%" -IconLocation ($powershellExe + ",0") -ValidationKind "console")
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "t7Azure CLI" -TargetPath $cmdExe -Arguments "/k cd /d %UserProfile% & az" -WorkingDirectory "%UserProfile%" -IconLocation (Resolve-IconLocation -PreferredPath $azExe -FallbackPath $cmdExe) -ValidationKind "console")
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "t8WSL" -TargetPath $cmdExe -Arguments "/k cd /d %UserProfile% & wsl" -WorkingDirectory "%UserProfile%" -IconLocation (Resolve-IconLocation -PreferredPath $wslExe -FallbackPath $cmdExe) -ValidationKind "console")
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "t9Docker CLI" -TargetPath $cmdExe -Arguments "/k cd /d %UserProfile% & docker" -WorkingDirectory "%UserProfile%" -IconLocation (Resolve-IconLocation -PreferredPath $dockerExe -FallbackPath $cmdExe) -ValidationKind "console")
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "t10Azd CLI" -TargetPath $cmdExe -Arguments "/k cd /d %UserProfile% & azd" -WorkingDirectory "%UserProfile%" -IconLocation (Resolve-IconLocation -PreferredPath $azdExe -FallbackPath $cmdExe) -ValidationKind "console")
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "t11GH CLI" -TargetPath $cmdExe -Arguments "/k cd /d %UserProfile% & gh" -WorkingDirectory "%UserProfile%" -IconLocation (Resolve-IconLocation -PreferredPath $ghExe -FallbackPath $cmdExe) -ValidationKind "console")
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "t12FFmpeg CLI" -TargetPath $cmdExe -Arguments "/k cd /d %UserProfile% & ffmpeg -version" -WorkingDirectory "%UserProfile%" -IconLocation (Resolve-IconLocation -PreferredPath $ffmpegExe -FallbackPath $cmdExe) -ValidationKind "console")
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "t13Seven Zip CLI" -TargetPath $cmdExe -Arguments ('/k cd /d %UserProfile% & "{0}"' -f $sevenZipCliPath) -WorkingDirectory "%UserProfile%" -IconLocation ($sevenZipCliPath + ",0") -ValidationKind "console")
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "t14Process Explorer" -TargetPath $processExplorerExe -AllowMissingTargetPath $true -ValidationKind "app")
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "t15Io Unlocker" -TargetPath $ioUnlockerExe -AllowMissingTargetPath $true -ValidationKind "app" -CleanupAliases @("IObit Unlocker") -CleanupMatchTargetOnly $true)

Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "u1User Files" -TargetPath $explorerExe -Arguments "shell:UsersFilesFolder" -IconLocation ($explorerExe + ",0") -ValidationKind "explorer-shell")
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "u2This PC" -TargetPath $explorerExe -Arguments "shell:MyComputerFolder" -IconLocation ($explorerExe + ",0") -ValidationKind "explorer-shell")
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "u3Control Panel" -TargetPath $explorerExe -Arguments "shell:ControlPanelFolder" -IconLocation ($explorerExe + ",0") -ValidationKind "explorer-shell")
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "u7Network and Sharing" -TargetPath $controlExe -Arguments "/name Microsoft.NetworkAndSharingCenter" -IconLocation ($controlExe + ",0") -ValidationKind "app")

Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "v1VS2022Com" -TargetPath $vs2022CommunityExe -WorkingDirectory (Split-Path -Path $vs2022CommunityExe -Parent) -IconLocation (Resolve-IconLocation -PreferredPath $vs2022CommunityExe -FallbackPath $powershellExe) -AllowMissingTargetPath $true -ValidationKind "app" -CleanupAliases @("Visual Studio 2022") -CleanupMatchTargetOnly $true)
Add-Spec -List $shortcutSpecs -Spec (New-ShortcutSpec -Name "v5VS Code" -TargetPath $powershellExe -Arguments ('-command "&''{0}''"' -f '%LocalAppData%\Programs\Microsoft VS Code\bin\code.cmd') -WorkingDirectory "%UserProfile%" -IconLocation ($powershellExe + ",0") -ValidationKind "app")

Add-Spec -List $shortcutSpecs -Spec (New-ChromeShortcutSpec -Name "z1Google Account Setup" -Url "chrome://settings/syncSetup" -ProfileKind 'business' -Variant 'setup')
Add-Spec -List $shortcutSpecs -Spec (New-ChromeShortcutSpec -Name "z2Office365 Account Setup" -Url "https://portal.office.com" -ProfileKind 'business' -Variant 'setup')

$ownedManagedShortcutNames = @(
    "a1ChatGPT Web",
    "a2CodexApp",
    "a3Be My Eyes",
    "a4WhatsApp Business",
    "a5WhatsApp Personal",
    "a6AnyDesk",
    "a7Docker Desktop",
    "a8WindScribe",
    "a9VLC Player",
    "a10NVDA",
    "a11MS Edge",
    "a12Itunes",
    "b1GarantiBank Business",
    "b2GarantiBank Personal",
    "b3QnbBank Business",
    "b4QnbBank Personal",
    "b5AktifBank Business",
    "b6AktifBank Personal",
    "b7ZiraatBank Business",
    "b8ZiraatBank Personal",
    "c1Cmd",
    "d1RClone CLI",
    "d2One Drive",
    "d3Google Drive",
    "d4ICloud",
    ("e1Mail {0}" -f $employeeEmailAddress),
    "g1Apple Developer",
    "g2Google Developer",
    "g3Microsoft Developer",
    "g4Azure Portal",
    "i1Internet Business",
    "i2Internet Personal",
    "j0Jaws",
    "k1Codex CLI",
    "k2Gemini CLI",
    "k3Github Copilot CLI",
    "m1Digital Tax Office",
    "n1Notepad",
    "o1Outlook",
    "o2Teams",
    "o3Word",
    "o4Excel",
    "o5Power Point",
    "o6OneNote",
    $q1EksiSozlukName,
    "q2Spotify",
    "q3Netflix",
    "q4eGovernment",
    "q5Apple Account",
    "q6AJet Flights",
    "q7TCDD Train",
    "q8OBilet Bus",
    "r1Sahibinden Business",
    "r2Sahibinden Personal",
    "r3Letgo Business",
    "r4Letgo Personal",
    "r5Trendyol Business",
    "r6Trendyol Personal",
    "r7Amazon TR Business",
    "r8Amazon TR Personal",
    "r9HepsiBurada Business",
    "r10HepsiBurada Personal",
    "r11N11 Business",
    "r12N11 Personal",
    $r13CicekSepetiBusinessName,
    $r14CicekSepetiPersonalName,
    "r15Pazarama Business",
    "r16Pazarama Personal",
    "r17PTTAVM Business",
    "r18PTTAVM Personal",
    "r19Ozon Business",
    "r20Ozon Personal",
    "r21Getir Business",
    "r22Getir Personal",
    "s1LinkedIn Business",
    "s2LinkedIn Personal",
    "s3YouTube Business",
    "s4YouTube Personal",
    "s5GitHub Business",
    "s6GitHub Personal",
    "s7TikTok Business",
    "s8TikTok Personal",
    "s9Instagram Business",
    "s10Instagram Personal",
    "s11Facebook Business",
    "s12Facebook Personal",
    "s13X-Twitter Business",
    "s14X-Twitter Personal",
    ("s15{0} Web" -f $companyDisplayName),
    ("s16{0} Blog" -f $companyDisplayName),
    "s17SnapChat Business",
    "s18NextSosyal Business",
    "t1Git Bash",
    "t2Python CLI",
    "t3NodeJS CLI",
    "t4Ollama App",
    "t5Pwsh",
    "t6PS",
    "t7Azure CLI",
    "t8WSL",
    "t9Docker CLI",
    "t10Azd CLI",
    "t11GH CLI",
    "t12FFmpeg CLI",
    "t13Seven Zip CLI",
    "t14Process Explorer",
    "t15Io Unlocker",
    "u1User Files",
    "u2This PC",
    "u3Control Panel",
    "u7Network and Sharing",
    "v1VS2022Com",
    "v5VS Code",
    "z1Google Account Setup",
    "z2Office365 Account Setup"
) | Select-Object -Unique

$managedShortcutNames = @($shortcutSpecs | ForEach-Object { [string]$_.Name })
if (@($managedShortcutNames | Select-Object -Unique).Count -ne @($managedShortcutNames).Count) {
    throw "The public desktop shortcut manifest contains duplicate shortcut names."
}

$managedUserDesktopRoots = @(
    ("C:\Users\{0}\Desktop" -f $managerUser),
    ("C:\Users\{0}\Desktop" -f $assistantUser),
    "C:\Users\Default\Desktop"
)
$stagingRoot = ''
$publicDesktopLauncherRoot = if (Get-Command Get-ClagnosShortcutLauncherRoot -ErrorAction SilentlyContinue) { Get-ClagnosShortcutLauncherRoot -Subdirectory 'public-desktop' } else { '' }
$publicDesktopAlreadyNormalized = Test-PublicDesktopAlreadyNormalized -PublicDesktopPath $publicDesktop -Specs $shortcutSpecs -OwnedShortcutNames $ownedManagedShortcutNames

try {
    if ($publicDesktopAlreadyNormalized) {
        Write-Host "public-desktop-normalized: no changes required"
    }
    else {
        $stagingRoot = Join-Path $env:TEMP ("clagnos-public-desktop-" + [guid]::NewGuid().ToString("N"))
        Ensure-Directory -Path $stagingRoot
        if (-not [string]::IsNullOrWhiteSpace([string]$publicDesktopLauncherRoot) -and (Test-Path -LiteralPath $publicDesktopLauncherRoot)) {
            Remove-Item -LiteralPath $publicDesktopLauncherRoot -Recurse -Force -ErrorAction SilentlyContinue
        }

        foreach ($shortcutSpec in $shortcutSpecs) {
            try {
                New-ShortcutFromSpec -Spec $shortcutSpec -OutputDirectory $stagingRoot
            }
            catch {
                throw ("Failed while creating public shortcut '{0}': {1}" -f [string]$shortcutSpec.Name, $_.Exception.Message)
            }
        }

        foreach ($existingShortcutFile in @(Get-ChildItem -LiteralPath $publicDesktop -Filter "*.lnk" -File -ErrorAction SilentlyContinue)) {
            $shortcutBaseName = [System.IO.Path]::GetFileNameWithoutExtension([string]$existingShortcutFile.Name)
            $matchedSpec = Find-ManagedShortcutSpecByName -Specs $shortcutSpecs -ShortcutBaseName $shortcutBaseName
            $isOwnedManagedShortcutName = (@($ownedManagedShortcutNames) -contains [string]$shortcutBaseName)

            if ($null -eq $matchedSpec) {
                $existingDetails = $null
                try {
                    $existingDetails = Get-ShortcutDetails -ShortcutPath ([string]$existingShortcutFile.FullName)
                }
                catch {
                    Write-Warning ("public-desktop-inspect-skip: {0} => {1}" -f $existingShortcutFile.FullName, $_.Exception.Message)
                    continue
                }

                $matchedSpec = Find-ManagedShortcutSpecByDetails -Specs $shortcutSpecs -Details $existingDetails -ShortcutBaseName $shortcutBaseName
            }

            if ($null -eq $matchedSpec -and -not $isOwnedManagedShortcutName) {
                continue
            }

            $removalResult = Remove-ExistingPublicShortcut -ShortcutFile $existingShortcutFile -ShortcutBaseName $shortcutBaseName -MatchedSpec $matchedSpec
            if ([bool]$removalResult.Removed) {
                if ($null -ne $matchedSpec) {
                    Write-Host ("public-desktop-removed: {0} => managed-by {1}" -f $existingShortcutFile.Name, [string]$matchedSpec.Name)
                }
                else {
                    Write-Host ("public-desktop-removed: {0} => inactive-managed-shortcut" -f $existingShortcutFile.Name)
                }
            }
        }

        foreach ($stagedShortcutFile in @(Get-ChildItem -LiteralPath $stagingRoot -Filter "*.lnk" -File -ErrorAction SilentlyContinue)) {
            $shortcutName = [System.IO.Path]::GetFileNameWithoutExtension([string]$stagedShortcutFile.Name)
            $destinationPath = Join-Path $publicDesktop $stagedShortcutFile.Name
            $matchedSpec = Find-ManagedShortcutSpecByName -Specs $shortcutSpecs -ShortcutBaseName $shortcutName
            if (($null -ne $matchedSpec) -and (Test-ExistingPublicShortcutMatchesManagedSpec -ShortcutPath $destinationPath -ShortcutBaseName $shortcutName -Spec $matchedSpec)) {
                Write-Host ("public-shortcut-path-retained: {0} => existing-managed-shortcut" -f [string]$shortcutName)
                Remove-Item -LiteralPath $stagedShortcutFile.FullName -Force -ErrorAction SilentlyContinue
                continue
            }

            Move-Item -LiteralPath $stagedShortcutFile.FullName -Destination $destinationPath -Force
        }

        foreach ($expectedShortcutName in @($managedShortcutNames)) {
            $expectedShortcutPath = Join-Path $publicDesktop ($expectedShortcutName + ".lnk")
            $resolvedShortcutPath = Resolve-WrittenShortcutPath -ExpectedShortcutPath $expectedShortcutPath -OutputDirectory $publicDesktop -ShortcutName $expectedShortcutName
            if (-not (Test-Path -LiteralPath $resolvedShortcutPath)) {
                throw ("Managed public shortcut was not created: {0}" -f $expectedShortcutPath)
            }

            if (-not [string]::Equals([string]$resolvedShortcutPath, [string]$expectedShortcutPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                Write-Host ("public-shortcut-path-reconciled: {0} => {1}" -f [string]$expectedShortcutName, [string]$resolvedShortcutPath)
            }
        }

        $inactiveManagedShortcuts = @(
            Get-ChildItem -LiteralPath $publicDesktop -Filter "*.lnk" -File -ErrorAction SilentlyContinue |
                Where-Object {
                    $baseName = [System.IO.Path]::GetFileNameWithoutExtension([string]$_.Name)
                    (@($ownedManagedShortcutNames) -contains [string]$baseName) -and (@($managedShortcutNames) -notcontains [string]$baseName)
                }
        )
        if (@($inactiveManagedShortcuts).Count -gt 0) {
            throw ("Inactive managed shortcuts remain on the public desktop: {0}" -f ((@($inactiveManagedShortcuts | Select-Object -ExpandProperty Name)) -join ', '))
        }
    }

    foreach ($spec in $shortcutSpecs) {
        if ($null -eq $spec) {
            continue
        }

        $managedShortcutPath = Join-Path $publicDesktop ([string]$spec.Name + '.lnk')
        Set-PublicShortcutReadPermissions -ShortcutPath $managedShortcutPath
    }

    foreach ($managedUserDesktopRoot in @($managedUserDesktopRoots)) {
        Clear-DesktopEntries -DesktopPath ([string]$managedUserDesktopRoot)
    }
}
finally {
    if (-not [string]::IsNullOrWhiteSpace([string]$stagingRoot) -and (Test-Path -LiteralPath $stagingRoot)) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "create-public-desktop-shortcuts-completed"
Write-Host "Update task completed: create-public-desktop-shortcuts"

