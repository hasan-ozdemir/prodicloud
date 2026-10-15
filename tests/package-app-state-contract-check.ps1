param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'

function Assert-ClagnosPackageAppState {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Add-ClagnosSensitiveJsonKeyFindings {
    param([AllowNull()]$Value, [System.Collections.Generic.List[string]]$Findings, [string]$Path = '')

    if ($null -eq $Value) { return }
    if ($Value -is [pscustomobject]) {
        foreach ($property in @($Value.PSObject.Properties)) {
            $propertyPath = if ([string]::IsNullOrWhiteSpace([string]$Path)) { [string]$property.Name } else { $Path + '.' + [string]$property.Name }
            if ([string]$property.Name -match '(?i)(password|secret|token|credential|api.?key|private.?key|account|email|gaia|sign.?in|client.?id|machine.?id|device.?id|subscription|tenant|user.?id)') {
                $Findings.Add([string]$propertyPath) | Out-Null
            }
            Add-ClagnosSensitiveJsonKeyFindings -Value $property.Value -Findings $Findings -Path $propertyPath
        }
    }
    elseif ($Value -is [array]) {
        foreach ($item in @($Value)) { Add-ClagnosSensitiveJsonKeyFindings -Value $item -Findings $Findings -Path $Path }
    }
}

$packageRoot = Join-Path $RepoRoot 'vm-packages'
$manifests = @(Get-ChildItem -LiteralPath $packageRoot -Recurse -File -Filter package.json -ErrorAction SilentlyContinue)
$noPortableIdentityState = @('anydesk','be-my-eyes','codex-app','docker-desktop','google-chrome','google-drive','github-copilot-cli','icloud','itunes','microsoft-edge','microsoft-teams','onedrive','rclone','whatsapp','windscribe')
$manifestPaths = @{}
foreach ($manifestFile in @($manifests)) {
    $manifest = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $manifestFile.FullName -Raw) -ErrorAction Stop
    $manifestPaths[[string]$manifest.id] = $manifestFile.FullName
    if ($null -eq $manifest.appState) { continue }

    foreach ($collectionName in @('machineDirectories','machineFiles','profileDirectories','profileFiles','machineRegistryKeys','userRegistryKeys')) {
        foreach ($rule in @($manifest.appState.$collectionName)) {
            if ($null -eq $rule) { continue }
            $path = [string]$rule.path
            Assert-ClagnosPackageAppState -Condition ($path -notmatch '(?i)(^|[\\/])\.npmrc$|(?:^|[\\/])hosts\.yml$|(?:^|[\\/])auth(?:entication)?(?:[\\/]|$)|(?:^|[\\/])Login Data$|Cookies(?:\.binarycookies)?$') -Message ("Package '{0}' app-state rule contains a credential or session path." -f [string]$manifest.id)
            Assert-ClagnosPackageAppState -Condition ($path -notmatch '(?i)AppData\\Local\\(?:Google\\Chrome|Microsoft\\Edge)\\User Data$|OneDrive$|WhatsApp|GitHub CLI$|\.azure$|\.azd$') -Message ("Package '{0}' app-state rule captures a broad identity or authenticated profile directory." -f [string]$manifest.id)
            Assert-ClagnosPackageAppState -Condition ($path -notmatch '^[A-Z]:\\Users\\[^\\]+') -Message ("Package '{0}' app-state rule contains a source-machine profile path." -f [string]$manifest.id)
        }
    }
}

foreach ($packageId in @($noPortableIdentityState)) {
    if (-not $manifestPaths.ContainsKey([string]$packageId)) { continue }
    $manifest = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $manifestPaths[[string]$packageId] -Raw) -ErrorAction Stop
    Assert-ClagnosPackageAppState -Condition ($null -eq $manifest.appState) -Message ("Identity-bound package '{0}' must not carry machine-specific user state." -f $packageId)
}

$expectedPortableArchives = @('azure-cli','azure-developer-cli','github-cli','jaws','nvda','visual-studio-code','visual-studio-community','vlc')
$expectedPortablePolicies = @('azure-cli','azure-developer-cli','github-cli','google-gemini-cli','jaws','nvda','ollama','openai-codex-cli','visual-studio-code','visual-studio-community','vlc','windows-subsystem-linux')
$archiveFiles = @(Get-ChildItem -LiteralPath $packageRoot -Recurse -File -Filter app-state.zip -ErrorAction SilentlyContinue)
$repoRootFullPath = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
foreach ($archiveFile in @($archiveFiles)) {
    $archiveRelativePath = $archiveFile.FullName.Substring($repoRootFullPath.Length + 1).Replace([char]92, [char]47)
    $null = & git -C $RepoRoot ls-files --error-unmatch -- $archiveRelativePath 2>$null
    Assert-ClagnosPackageAppState -Condition ($LASTEXITCODE -eq 0) -Message ("Package app-state archive must be tracked by Git: {0}" -f $archiveRelativePath)
}
$builtinWindowsArchiveRoot = Join-Path $packageRoot 'builtin\windows'
$builtinWindowsArchives = @(Get-ChildItem -LiteralPath $builtinWindowsArchiveRoot -Recurse -File -Filter app-state.zip -ErrorAction SilentlyContinue)
Assert-ClagnosPackageAppState -Condition (@($builtinWindowsArchives | Where-Object { [string]$_.Directory.Parent.Name -notin $expectedPortableArchives }).Count -eq 0) -Message 'Builtin package snapshots must be in the reviewed settings-only allow-list.'
foreach ($packageId in @($expectedPortableArchives)) {
    if (@($builtinWindowsArchives | Where-Object { [string]$_.Directory.Parent.Name -eq [string]$packageId }).Count -gt 1) {
        throw ("Duplicate builtin package snapshot found: {0}" -f $packageId)
    }
}
foreach ($packageId in @($expectedPortablePolicies)) {
    Assert-ClagnosPackageAppState -Condition ($manifestPaths.ContainsKey([string]$packageId)) -Message ("Portable package app-state policy is missing: {0}" -f $packageId)
    $manifest = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $manifestPaths[[string]$packageId] -Raw) -ErrorAction Stop
    Assert-ClagnosPackageAppState -Condition ($null -ne $manifest.appState) -Message ("Portable package app-state policy is missing from '{0}'." -f $packageId)
}

$jawsManifest = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $manifestPaths['jaws'] -Raw -ErrorAction Stop) -ErrorAction Stop
$jawsAsset = @($jawsManifest.assets | Where-Object { [string]$_.local -eq 'app-state/app-state.zip' -and [string]$_.remote -eq 'C:/Windows/Temp/clagnos-jaws-app-state.zip' })
Assert-ClagnosPackageAppState -Condition ($jawsAsset.Count -eq 1) -Message 'JAWS must publish its reviewed app-state archive to the installer as an explicit remote asset.'
$jawsInstallerPath = Join-Path $packageRoot 'builtin\windows\jaws\install.ps1'
$jawsInstallerText = [string](Get-Content -LiteralPath $jawsInstallerPath -Raw -ErrorAction Stop)
foreach ($requiredJawsInstallerText in @('Stop-JawsProcessForUpdate','Install-JawsUpdateFilesFromAppState','C:\Program Files\Freedom Scientific\JAWS\2025','payload/update-files/','JAWS (jfw.exe) is still running')) {
    Assert-ClagnosPackageAppState -Condition ($jawsInstallerText.Contains($requiredJawsInstallerText)) -Message ("JAWS installer must stop jfw.exe and safely apply its update-files payload: missing '{0}'." -f $requiredJawsInstallerText)
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$forbiddenMemberPattern = '(?i)(auth\.json|cache\.bin|hosts\.yml|cookies|login data|history|workspacestorage|\.npmrc|\.db$|onedrive|whatsapp|local state|secure preferences)'
$reservedPlaceholderPattern = '%CLAGNOS_(COMPUTER_NAME|SYSTEM_DRIVE|SYSTEM_ROOT|WINDOWS_DIRECTORY|PROGRAM_DATA|PROGRAM_FILES|PROGRAM_FILES_X86|PRIMARY_IPV4_ADDRESS|TARGET_CPU_COUNT|TARGET_MEMORY_GB|VM_ADMIN_USER|ASSISTANT_USER|TARGET_USER|TARGET_PROFILE_PATH|TARGET_HOME|TARGET_USER_SID|TARGET_UID|TARGET_GID|VM_ADMIN_PROFILE_PATH|ASSISTANT_PROFILE_PATH|VM_ADMIN_HOME|ASSISTANT_HOME|VM_ADMIN_UID|ASSISTANT_UID|VM_ADMIN_GID|ASSISTANT_GID|VM_ADMIN_USER_SID|ASSISTANT_USER_SID|LOCAL_APP_DATA|ROAMING_APP_DATA|VS_INSTANCE_DIRECTORY)%'
foreach ($archiveFile in @($archiveFiles)) {
    $packageId = [string]$archiveFile.Directory.Parent.Name
    $archive = [System.IO.Compression.ZipFile]::OpenRead($archiveFile.FullName)
    try {
        $manifestEntry = $archive.GetEntry('app-state.manifest.json')
        Assert-ClagnosPackageAppState -Condition ($null -ne $manifestEntry) -Message ("Package snapshot '{0}' has no manifest." -f $packageId)
        $manifestReader = New-Object System.IO.StreamReader($manifestEntry.Open())
        try { $snapshotManifest = ConvertFrom-Json -InputObject $manifestReader.ReadToEnd() -ErrorAction Stop }
        finally { $manifestReader.Dispose() }
        foreach ($registryEntry in @($snapshotManifest.registryImports)) {
            Assert-ClagnosPackageAppState -Condition ([string]$registryEntry.scope -eq 'user' -and [string]$registryEntry.registryPath -match '(?i)^(HKCU|HKEY_CURRENT_USER)\\' -and @($registryEntry.targetProfiles).Count -gt 0) -Message ("Package snapshot '{0}' may only import an explicitly targeted user registry branch." -f $packageId)
        }
        foreach ($directoryEntry in @($snapshotManifest.profileDirectories)) {
            Assert-ClagnosPackageAppState -Condition ([string]$directoryEntry.relativeDestinationPath -notmatch '(?i)(Chrome\\User Data|Edge\\User Data|OneDrive|GitHub CLI|WhatsApp|\.azure|\.azd)') -Message ("Package snapshot '{0}' captures an identity-bound profile directory." -f $packageId)
        }

        foreach ($member in @($archive.Entries)) {
            Assert-ClagnosPackageAppState -Condition ([string]$member.FullName -notmatch $forbiddenMemberPattern) -Message ("Package snapshot '{0}' contains a cache, history, login, or credential member." -f $packageId)
            if ($member.Length -le 0 -or $member.Length -gt 1500000 -or [string]::Equals([string]$member.FullName, 'app-state.manifest.json', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            $extension = [IO.Path]::GetExtension($member.Name).ToLowerInvariant()
            if ($extension -notin @('.json','.xml','.ini','.yml','.yaml','.toml','.txt','.config','.vssettings','.jcf','.jdf','.vpf','.vlcrc') -and $member.Name -ne 'config') { continue }
            $reader = New-Object System.IO.StreamReader($member.Open())
            try { $content = [string]$reader.ReadToEnd() }
            finally { $reader.Dispose() }
            Assert-ClagnosPackageAppState -Condition (-not [regex]::IsMatch($content, '(?i)[A-Z]:\\Users\\[^\\/\s"'']+')) -Message ("Package snapshot '{0}' contains a source Windows profile path." -f $packageId)
            Assert-ClagnosPackageAppState -Condition (-not [regex]::IsMatch($content, '(?i)[A-Z]:\\[^\s"'']{2,}')) -Message ("Package snapshot '{0}' contains an un-generalized absolute drive path." -f $packageId)
            Assert-ClagnosPackageAppState -Condition (-not [regex]::IsMatch($content, 'S-1-5-21-\d+-\d+-\d+-\d+|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')) -Message ("Package snapshot '{0}' contains a source user SID or email address." -f $packageId)
            foreach ($placeholder in @([regex]::Matches($content, '%CLAGNOS_[A-Z0-9_]+%') | ForEach-Object { $_.Value } | Select-Object -Unique)) {
                Assert-ClagnosPackageAppState -Condition ($placeholder -match $reservedPlaceholderPattern) -Message ("Package snapshot '{0}' contains an unsupported target placeholder." -f $packageId)
            }
            if ($extension -eq '.json') {
                try {
                    $document = ConvertFrom-Json -InputObject $content -ErrorAction Stop
                    $findings = New-Object 'System.Collections.Generic.List[string]'
                    Add-ClagnosSensitiveJsonKeyFindings -Value $document -Findings $findings
                    Assert-ClagnosPackageAppState -Condition ($findings.Count -eq 0) -Message ("Package snapshot '{0}' contains a secret, account, or machine identity JSON field." -f $packageId)
                }
                catch {
                    if ($_.Exception.Message -like '*contains a secret*') { throw }
                }
            }
            if ($extension -in @('.xml','.vssettings','.config')) {
                try {
                    [xml]$xmlDocument = $content
                    $sensitiveNodes = @($xmlDocument.SelectNodes('//*') | Where-Object { [string]$_.LocalName -match '(?i)(password|secret|token|credential|authentication|api.?key|private.?key|account|email|identity|sign.?in|client.?id|machine.?id|device.?id|subscription|tenant)' })
                    Assert-ClagnosPackageAppState -Condition ($sensitiveNodes.Count -eq 0) -Message ("Package snapshot '{0}' contains a secret or identity XML field." -f $packageId)
                }
                catch {
                    if ($_.Exception.Message -like '*contains a secret*') { throw }
                }
            }
        }
        if ([string]::Equals($packageId,'jaws',[System.StringComparison]::OrdinalIgnoreCase)) {
            $jawsUpdateFiles = @($archive.Entries | Where-Object { ([string]$_.FullName).StartsWith('payload/update-files/',[System.StringComparison]::OrdinalIgnoreCase) -and -not ([string]$_.FullName).EndsWith('/') } | ForEach-Object { ([string]$_.FullName).Substring('payload/update-files/'.Length) } | Sort-Object)
            $expectedJawsUpdateFiles = @('JawsCertificate.cer','netapi32.dll','version.dll') | Sort-Object
            Assert-ClagnosPackageAppState -Condition (($jawsUpdateFiles -join '|') -ceq ($expectedJawsUpdateFiles -join '|')) -Message 'JAWS app-state update-files payload must contain exactly the reviewed update files.'
        }
    }
    finally { $archive.Dispose() }
}

Import-Module (Join-Path $RepoRoot 'modules\core\tasks\clagnos-app-state-guest.psm1') -Force -DisableNameChecking
. (Join-Path $RepoRoot 'modules\core\tasks\clagnos-app-state-plugin.ps1')
$guestModule = Get-Module -Name 'clagnos-app-state-guest'
foreach ($archiveFile in @($archiveFiles)) {
    Assert-ClagnosPackageAppStateArchivePortable -ZipPath ([string]$archiveFile.FullName)
}
$wslConfig = & $guestModule { ConvertTo-ClagnosAppStateHardwareSettingsToPortable -Content "[wsl2]`nprocessors=4`nmemory=8GB`n" -FileName '.wslconfig' }
Assert-ClagnosPackageAppState -Condition ($wslConfig -match '(?m)^processors=%CLAGNOS_TARGET_CPU_COUNT%$' -and $wslConfig -match '(?m)^memory=%CLAGNOS_TARGET_MEMORY_GB%GB$') -Message 'WSL CPU and memory settings must be generalized for the target VM.'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('clagnos-app-state-contract-{0}' -f [guid]::NewGuid().ToString('N'))
$testProfilePath = Join-Path $testRoot 'profile'
$payloadDirectory = Join-Path $testRoot 'payload\profile-files\manager'
$manifestPath = Join-Path $testRoot 'app-state.manifest.json'
$settingsPath = Join-Path $payloadDirectory 'settings.json'
New-Item -ItemType Directory -Path $testProfilePath -Force | Out-Null
New-Item -ItemType Directory -Path $payloadDirectory -Force | Out-Null
try {
    $testManifest = [ordered]@{
        version = 3
        taskName = 'app-state-contract-fixture'
        machineDirectories = @()
        machineFiles = @(@{ sourcePath = 'payload/machine-files/fixture.txt'; destinationPath = '%CLAGNOS_SYSTEM_DRIVE%\Clagnos\fixture.txt' })
        profileDirectories = @()
        profileFiles = @(@{ sourcePath = 'payload/profile-files/manager/settings.json'; relativeDestinationPath = '%CLAGNOS_TARGET_PROFILE_PATH%\Documents\settings.json'; targetProfiles = @('manager') })
        registryImports = @()
    }
    Set-Content -LiteralPath $manifestPath -Value (ConvertTo-Json -InputObject $testManifest -Depth 20) -Encoding UTF8
    [IO.File]::WriteAllText($settingsPath, '{"profile":"%CLAGNOS_TARGET_PROFILE_PATH%\\Documents","cpu":"%CLAGNOS_TARGET_CPU_COUNT%","memory":"%CLAGNOS_TARGET_MEMORY_GB%"}', [Text.Encoding]::UTF8)
    $profileTargets = @([pscustomobject]@{ Label = 'manager'; UserName = 'clagnosadmin'; ProfilePath = $testProfilePath; SID = 'S-1-5-21-11-22-33-1001' })
    & $guestModule {
        param($ExpandedRoot, $Targets)
        Expand-ClagnosAppStatePayloadPlaceholders -ExpandedRoot $ExpandedRoot -ProfileTargets $Targets -ManagerUser 'clagnosadmin' -MachineOverrides @{ CLAGNOS_SYSTEM_DRIVE = 'D:'; CLAGNOS_TARGET_CPU_COUNT = '12'; CLAGNOS_TARGET_MEMORY_GB = '48' }
    } $testRoot $profileTargets

    $resolvedManifest = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $manifestPath -Raw) -ErrorAction Stop
    $resolvedSettings = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $settingsPath -Raw) -ErrorAction Stop
    Assert-ClagnosPackageAppState -Condition ([string]$resolvedManifest.machineFiles[0].destinationPath -eq 'D:\Clagnos\fixture.txt') -Message 'Machine path placeholders must use the target system drive.'
    Assert-ClagnosPackageAppState -Condition ([string]$resolvedManifest.profileFiles[0].relativeDestinationPath -eq ($testProfilePath + '\Documents\settings.json')) -Message 'Profile destination placeholders must use the target profile path.'
    Assert-ClagnosPackageAppState -Condition ([string]$resolvedSettings.profile -eq ($testProfilePath + '\Documents') -and [string]$resolvedSettings.cpu -eq '12' -and [string]$resolvedSettings.memory -eq '48') -Message 'Payload placeholders must use target profile and hardware values.'
    $unsupportedFailed = $false
    try { & $guestModule { Resolve-ClagnosAppStatePlaceholderText -Text '%CLAGNOS_UNKNOWN_VALUE%' -Replacements @{} -SourceLabel 'contract-fixture' } }
    catch { $unsupportedFailed = $true }
    Assert-ClagnosPackageAppState -Condition $unsupportedFailed -Message 'Unknown target placeholders must fail before replay.'
}
finally {
    foreach ($path in @($settingsPath,$manifestPath)) { if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force } }
    foreach ($path in @($payloadDirectory,(Split-Path -Parent $payloadDirectory),(Split-Path -Parent (Split-Path -Parent $payloadDirectory)),$testProfilePath,$testRoot)) {
        if (Test-Path -LiteralPath $path -PathType Container) { Remove-Item -LiteralPath $path -Force }
    }
}

Write-Host ("[PASS] Package app-state contracts ({0} tracked builtin snapshots, {1} package manifests)" -f @($builtinWindowsArchives).Count, @($manifests).Count) -ForegroundColor Green
