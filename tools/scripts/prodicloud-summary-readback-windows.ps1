$ErrorActionPreference = "Stop"

$companyName = "__SELECTED_COMPANY_NAME__"
$companyWebAddress = "__SELECTED_COMPANY_WEB_ADDRESS__"
$employeeEmailAddress = "__SELECTED_EMPLOYEE_EMAIL_ADDRESS__"
$employeeFullName = "__SELECTED_EMPLOYEE_FULL_NAME__"
$managerUser = "__VM_ADMIN_USER__"
$managerPassword = "__VM_ADMIN_PASS__"
$assistantUser = "__ASSISTANT_USER__"
$assistantPassword = "__ASSISTANT_PASS__"
$hostStartupProfileJsonBase64 = "__HOST_STARTUP_PROFILE_JSON_B64__"
$publicDesktop = "C:\Users\Public\Desktop"
$publicChromeUserDataDir = 'C:\Users\Public\AppData\Local\Google\Chrome\UserData'
$publicEdgeUserDataDir = 'C:\Users\Public\AppData\Local\Microsoft\msedge\UserData'
$dockerStartupShortcutPath = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp\Docker Desktop.lnk"
$ollamaStartupShortcutPath = ("C:\Users\{0}\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\Ollama.lnk" -f $managerUser)
$shortcutRunAsAdminFlag = 0x00002000
$unresolvedCompanyNameToken = ('__' + 'SELECTED_COMPANY_NAME' + '__')
$unresolvedCompanyWebAddressToken = ('__' + 'SELECTED_COMPANY_WEB_ADDRESS' + '__')
$unresolvedEmployeeEmailAddressToken = ('__' + 'SELECTED_EMPLOYEE_EMAIL_ADDRESS' + '__')
$unresolvedEmployeeFullNameToken = ('__' + 'SELECTED_EMPLOYEE_FULL_NAME' + '__')
$storeHelperPath = 'C:\Windows\Temp\prodicloud-store-install-state.psm1'
$launcherHelperPath = 'C:\Windows\Temp\prodicloud-shortcut-launcher.psm1'
$interactiveHelperPath = 'C:\Windows\Temp\prodicloud-interactive-session-helper.ps1'

if (Test-Path -LiteralPath $storeHelperPath) {
    Import-Module $storeHelperPath -Force -DisableNameChecking
}
if (Test-Path -LiteralPath $launcherHelperPath) {
    Import-Module $launcherHelperPath -Force -DisableNameChecking
}
if (Test-Path -LiteralPath $interactiveHelperPath) {
    . $interactiveHelperPath
}

function Invoke-CommandWithTimeout {
    param(
        [scriptblock]$Action,
        [int]$TimeoutSeconds = 20
    )

    $job = Start-Job -ScriptBlock $Action
    $completed = Wait-Job -Job $job -Timeout $TimeoutSeconds
    if (-not $completed) {
        Stop-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force
        return [pscustomobject]@{ Success = $false; TimedOut = $true }
    }

    $jobReceiveErrors = @()
    $output = Receive-Job -Job $job -ErrorAction SilentlyContinue -ErrorVariable jobReceiveErrors
    if ($output) {
        $output | ForEach-Object { Write-Host ([string]$_) }
    }
    foreach ($jobError in @($jobReceiveErrors)) {
        Write-Warning ([string]$jobError)
    }

    $state = $job.ChildJobs[0].JobStateInfo.State
    $hadErrors = @($job.ChildJobs[0].Error).Count -gt 0
    Remove-Job -Job $job -Force
    return [pscustomobject]@{ Success = ($state -ne 'Failed' -and -not $hadErrors); TimedOut = $false }
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

function Test-TcpPortReachable {
    param(
        [string]$HostName,
        [int]$Port,
        [int]$TimeoutSeconds = 5
    )

    if ([string]::IsNullOrWhiteSpace([string]$HostName) -or $Port -lt 1 -or $Port -gt 65535) {
        return $false
    }

    $client = New-Object System.Net.Sockets.TcpClient
    $waitHandle = $null
    try {
        $async = $client.BeginConnect([string]$HostName, [int]$Port, $null, $null)
        $waitHandle = $async.AsyncWaitHandle
        if (-not $waitHandle.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds), $false)) {
            return $false
        }

        $client.EndConnect($async)
        return $client.Connected
    }
    catch {
        return $false
    }
    finally {
        if ($null -ne $waitHandle) {
            try { $waitHandle.Close() } catch { }
        }
        try { $client.Dispose() } catch { }
    }
}

Import-Module 'C:\Windows\Temp\prodicloud-session-environment.psm1' -Force -DisableNameChecking

function Refresh-SessionPath {
    Refresh-ProdicloudSessionPath | Out-Null
}

function Invoke-NativeCommandProbe {
    param(
        [string]$FilePath,
        [string[]]$Arguments = @(),
        [int]$TimeoutSeconds = 15,
        [switch]$SuppressOutput
    )

    $job = Start-Job -ScriptBlock {
        try {
            $output = & $using:FilePath @using:Arguments 2>&1 | Out-String
            return [pscustomobject]@{
                ExitCode = [int]$LASTEXITCODE
                Output = [string]$output
                InvocationFailed = $false
            }
        }
        catch {
            return [pscustomobject]@{
                ExitCode = 1
                Output = [string]($_ | Out-String)
                InvocationFailed = $true
            }
        }
    }

    $completed = Wait-Job -Job $job -Timeout $TimeoutSeconds
    if (-not $completed) {
        Stop-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force
        return [pscustomobject]@{
            Success = $false
            TimedOut = $true
            ExitCode = -1
            Output = ''
        }
    }

    $probeResult = Receive-Job -Job $job -ErrorAction SilentlyContinue | Select-Object -Last 1
    Remove-Job -Job $job -Force

    $outputText = ''
    $exitCode = 1
    $invocationFailed = $true
    if ($null -ne $probeResult) {
        $outputText = [string]$probeResult.Output
        $exitCode = [int]$probeResult.ExitCode
        $invocationFailed = [bool]$probeResult.InvocationFailed
    }

    if ((-not $SuppressOutput) -and -not [string]::IsNullOrWhiteSpace([string]$outputText)) {
        foreach ($line in @([string]$outputText -split "(`r`n|`n|`r)")) {
            if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
                Write-Host $line
            }
        }
    }

    return [pscustomobject]@{
        Success = (-not $invocationFailed -and $exitCode -eq 0)
        TimedOut = $false
        ExitCode = [int]$exitCode
        Output = [string]$outputText
    }
}

function Test-InvalidCompanyName {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace([string]$Value)) { return $true }
    $trimmed = $Value.Trim()
    if ([string]::Equals($trimmed, $unresolvedCompanyNameToken, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ([string]::Equals($trimmed, "SELECTED_COMPANY_NAME", [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ($trimmed.StartsWith("__", [System.StringComparison]::Ordinal) -and $trimmed.EndsWith("__", [System.StringComparison]::Ordinal)) { return $true }
    return $false
}

function Test-InvalidEmployeeEmailAddress {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace([string]$Value)) { return $true }
    $trimmed = $Value.Trim()
    if ([string]::Equals($trimmed, $unresolvedEmployeeEmailAddressToken, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ([string]::Equals($trimmed, 'SELECTED_EMPLOYEE_EMAIL_ADDRESS', [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ($trimmed.StartsWith("__", [System.StringComparison]::Ordinal) -and $trimmed.EndsWith("__", [System.StringComparison]::Ordinal)) { return $true }
    if (($trimmed -split '@').Count -lt 2) { return $true }
    return $false
}

function Test-InvalidCompanyWebAddress {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace([string]$Value)) { return $true }
    $trimmed = $Value.Trim()
    if ([string]::Equals($trimmed, $unresolvedCompanyWebAddressToken, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ([string]::Equals($trimmed, 'SELECTED_COMPANY_WEB_ADDRESS', [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ($trimmed.StartsWith('__', [System.StringComparison]::Ordinal) -and $trimmed.EndsWith('__', [System.StringComparison]::Ordinal)) { return $true }
    return (-not ($trimmed -match '^https?://'))
}

function Test-InvalidEmployeeFullName {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace([string]$Value)) { return $true }
    $trimmed = $Value.Trim()
    if ([string]::Equals($trimmed, $unresolvedEmployeeFullNameToken, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ([string]::Equals($trimmed, 'SELECTED_EMPLOYEE_FULL_NAME', [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ($trimmed.StartsWith("__", [System.StringComparison]::Ordinal) -and $trimmed.EndsWith("__", [System.StringComparison]::Ordinal)) { return $true }
    return $false
}

function ConvertTo-TitleCaseShortcutText {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return ""
    }

    $textInfo = [System.Globalization.CultureInfo]::InvariantCulture.TextInfo
    return [string]$textInfo.ToTitleCase($Value.Trim().ToLowerInvariant())
}

function Get-EmployeeEmailBaseName {
    param([string]$EmailAddress)

    if (Test-InvalidEmployeeEmailAddress -Value $EmailAddress) {
        return ''
    }

    return [string]($EmailAddress.Trim().Split('@')[0])
}

function ConvertTo-LowerInvariantText {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return ''
    }

    return [string]$Value.Trim().ToLowerInvariant()
}

function Normalize-ShortcutUrl {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return ''
    }

    return ([string]$Value.Trim()).TrimEnd('/')
}

function Get-ChromeProfileDirectoryForShortcut {
    param(
        [ValidateSet('business','personal')]
        [string]$ProfileKind = 'business'
    )

    if ([string]::Equals([string]$ProfileKind, 'personal', [System.StringComparison]::OrdinalIgnoreCase)) {
        return [string]$script:resolvedEmployeeEmailBaseName
    }

    return [string]$script:resolvedCompanyChromeProfileDirectory
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

function Get-WindowsOptionalFeatureState {
    param([string]$FeatureName)

    if ([string]::IsNullOrWhiteSpace([string]$FeatureName)) {
        return ''
    }

    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction Stop
        if ($null -ne $feature -and $feature.PSObject.Properties.Match('State').Count -gt 0) {
            return [string]$feature.State
        }
    }
    catch {
    }

    return ''
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

function Get-ShortcutDetails {
    param([string]$ShortcutPath)

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    return [pscustomobject]@{
        TargetPath = [string]$shortcut.TargetPath
        Arguments = [string]$shortcut.Arguments
        WorkingDirectory = [string]$shortcut.WorkingDirectory
        Hotkey = [string]$shortcut.Hotkey
        WindowStyle = [int]$shortcut.WindowStyle
        RunAsAdmin = [bool](Get-ShortcutRunAsAdministratorFlag -ShortcutPath $ShortcutPath)
    }
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

        $expandedCandidate = [Environment]::ExpandEnvironmentVariables([string]$candidate)
        if (Test-Path -LiteralPath $expandedCandidate) {
            return [string]$expandedCandidate
        }
    }

    return ''
}

function Resolve-EmbeddedShortcutCommandPath {
    param([string]$Arguments)

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
        '(?i)(?:^|[&\s])("?[%A-Za-z0-9_:\\ .()-]+\.(?:exe|cmd|bat))',
        '(?i)(?:^|[&\s])(docker|azd|az|gh|wsl|python|node|pwsh|powershell|rclone|ffmpeg|git-bash|copilot|gemini|codex|outlook)(?:\s|$)'
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

        $resolved = Resolve-CommandPath -CommandName ([System.IO.Path]::GetFileName($expandedCandidate))
        if (-not [string]::IsNullOrWhiteSpace([string]$resolved)) {
            return [string]$resolved
        }
    }

    return ''
}

function Get-ShortcutHealth {
    param([string]$ShortcutPath)

    if ([string]::IsNullOrWhiteSpace([string]$ShortcutPath) -or -not (Test-Path -LiteralPath $ShortcutPath)) {
        return $null
    }

    $details = Get-ShortcutDetails -ShortcutPath $ShortcutPath
    $targetPath = [string]$details.TargetPath
    $arguments = [string]$details.Arguments
    $resolvedInvocation = if (Get-Command Get-ProdicloudShortcutResolvedInvocation -ErrorAction SilentlyContinue) {
        Get-ProdicloudShortcutResolvedInvocation -TargetPath $targetPath -Arguments $arguments -WorkingDirectory ([string]$details.WorkingDirectory)
    }
    else {
        [pscustomobject]@{
            UsesManagedLauncher = $false
            LauncherPath = ''
            TargetPath = [string]$targetPath
            Arguments = [string]$arguments
            WorkingDirectory = [string]$details.WorkingDirectory
        }
    }
    $targetExists = -not [string]::IsNullOrWhiteSpace([string]$targetPath) -and (Test-Path -LiteralPath $targetPath)
    $embeddedTargetPath = ''
    if ([bool]$resolvedInvocation.UsesManagedLauncher) {
        $embeddedTargetPath = [Environment]::ExpandEnvironmentVariables([string]$resolvedInvocation.TargetPath)
    }
    elseif ([System.IO.Path]::GetFileName($targetPath) -in @('cmd.exe', 'powershell.exe', 'pwsh.exe')) {
        $embeddedTargetPath = Resolve-EmbeddedShortcutCommandPath -Arguments $arguments
    }

    $isStoreAppLaunch = (
        [string]::Equals($targetPath, (Resolve-CommandPath -CommandName 'explorer.exe' -FallbackCandidates @('C:\Windows\explorer.exe')), [System.StringComparison]::OrdinalIgnoreCase) -and
        $arguments.StartsWith('shell:AppsFolder\', [System.StringComparison]::OrdinalIgnoreCase)
    )

    $healthy = $false
    if ($isStoreAppLaunch) {
        $healthy = $targetExists -and -not [string]::IsNullOrWhiteSpace([string]$arguments)
    }
    elseif ([string]::IsNullOrWhiteSpace([string]$embeddedTargetPath)) {
        $healthy = $targetExists
    }
    else {
        $healthy = $targetExists -and (Test-Path -LiteralPath $embeddedTargetPath)
    }

    return [pscustomobject]@{
        Details = $details
        ResolvedInvocation = $resolvedInvocation
        TargetExists = [bool]$targetExists
        EmbeddedTargetPath = [string]$embeddedTargetPath
        EmbeddedTargetExists = if ([string]::IsNullOrWhiteSpace([string]$embeddedTargetPath)) { $false } else { (Test-Path -LiteralPath $embeddedTargetPath) }
        IsStoreAppLaunch = [bool]$isStoreAppLaunch
        Healthy = [bool]$healthy
    }
}

function Write-PackagedAppInventory {
    Write-Host "PACKAGED APP INVENTORY:"

    $appDefinitions = @(
        [pscustomobject]@{ Label = 'Codex'; NameFragment = 'codex'; PackageHints = @('OpenAI.Codex', '2p2nqsd0c76g0') }
        [pscustomobject]@{ Label = 'Be My Eyes'; NameFragment = 'be my eyes'; PackageHints = @('be my eyes', '9MSW46LTDWGF') }
        [pscustomobject]@{ Label = 'Teams'; NameFragment = 'teams'; PackageHints = @('teams') }
        [pscustomobject]@{ Label = 'WhatsApp'; NameFragment = 'whatsapp'; PackageHints = @('whatsapp', '5319275A.WhatsAppDesktop') }
        [pscustomobject]@{ Label = 'Windscribe'; NameFragment = 'windscribe'; PackageHints = @('windscribe') }
        [pscustomobject]@{ Label = 'iCloud'; NameFragment = 'icloud'; PackageHints = @('icloud', 'AppleInc.iCloud', '9PKTQ5699M62') }
    )

    $packages = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
    $startApps = @()
    if (Get-Command Get-StartApps -ErrorAction SilentlyContinue) {
        $startApps = @(Get-StartApps)
    }

    function Resolve-PackagedAppId {
        param(
            [psobject]$Package,
            [object[]]$StartApps
        )

        if ($null -eq $Package) {
            return ''
        }

        $installLocation = [string]$Package.InstallLocation
        if (-not [string]::IsNullOrWhiteSpace([string]$installLocation) -and (Test-Path -LiteralPath $installLocation)) {
            $manifestPath = Join-Path $installLocation 'AppxManifest.xml'
            if (Test-Path -LiteralPath $manifestPath) {
                try {
                    [xml]$manifestXml = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop
                    $appNodes = @($manifestXml.SelectNodes("//*[local-name()='Application']"))
                    foreach ($appNode in @($appNodes)) {
                        $applicationId = [string]$appNode.GetAttribute('Id')
                        if ([string]::IsNullOrWhiteSpace([string]$applicationId)) {
                            continue
                        }

                        return ("{0}!{1}" -f [string]$Package.PackageFamilyName, $applicationId)
                    }
                }
                catch {
                }
            }
        }

        $packageFamily = [string]$Package.PackageFamilyName
        if (-not [string]::IsNullOrWhiteSpace([string]$packageFamily)) {
            foreach ($entry in @($StartApps)) {
                $appIdText = [string]$entry.AppID
                if ([string]::IsNullOrWhiteSpace([string]$appIdText)) {
                    continue
                }

                if ($appIdText.StartsWith(($packageFamily + '!'), [System.StringComparison]::OrdinalIgnoreCase)) {
                    return $appIdText
                }
            }
        }

        return ''
    }

    foreach ($definition in @($appDefinitions)) {
        $normalizedHints = @($definition.PackageHints | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { $_.ToLowerInvariant() })
        $matchingPackage = @(
            $packages | Where-Object {
                $pkgName = [string]$_.Name
                $pkgFamily = [string]$_.PackageFamilyName
                $nameLower = $pkgName.ToLowerInvariant()
                $familyLower = $pkgFamily.ToLowerInvariant()
                foreach ($hint in @($normalizedHints)) {
                    if ($nameLower.Contains($hint) -or $familyLower.Contains($hint)) {
                        return $true
                    }
                }

                return $false
            } | Select-Object -First 1
        )[0]

        $appId = Resolve-PackagedAppId -Package $matchingPackage -StartApps $startApps

        $packageName = ''
        $packageFamily = ''
        $installLocation = ''
        if ($null -ne $matchingPackage) {
            $packageName = [string]$matchingPackage.Name
            $packageFamily = [string]$matchingPackage.PackageFamilyName
            $installLocation = [string]$matchingPackage.InstallLocation
        }

        Write-Host ("packaged-app => {0}" -f [string]$definition.Label)
        Write-Host (" package-name => {0}" -f $packageName)
        Write-Host (" package-family => {0}" -f $packageFamily)
        Write-Host (" install-location => {0}" -f $installLocation)
        Write-Host (" app-id => {0}" -f [string]$appId)
    }
}

function Get-OllamaApiVersion {
    param([int]$TimeoutSeconds = 4)

    if ($TimeoutSeconds -lt 1) {
        $TimeoutSeconds = 1
    }

    try {
        $response = Invoke-RestMethod -Method Get -Uri 'http://127.0.0.1:11434/api/version' -TimeoutSec $TimeoutSeconds -ErrorAction Stop
        if ($null -ne $response -and -not [string]::IsNullOrWhiteSpace([string]$response.version)) {
            return [string]$response.version
        }
    }
    catch {
    }

    return ''
}

function Wait-OllamaApiReady {
    param([int]$TimeoutSeconds = 20)

    if ($TimeoutSeconds -lt 1) {
        $TimeoutSeconds = 1
    }

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $version = Get-OllamaApiVersion -TimeoutSeconds 4
        if (-not [string]::IsNullOrWhiteSpace([string]$version)) {
            return [string]$version
        }

        Start-Sleep -Seconds 1
    }

    return ''
}

function Write-StoreInstallStateReadback {
    param(
        [string]$TaskName,
        [string]$Label
    )

    if (-not (Get-Command Read-ProdicloudStoreInstallState -ErrorAction SilentlyContinue)) {
        Write-Host ("store-install-state => task={0}; state=helper-unavailable" -f [string]$TaskName)
        return
    }

    $stateRecord = Read-ProdicloudStoreInstallState -TaskName $TaskName
    if ($null -eq $stateRecord) {
        Write-Host ("store-install-state => task={0}; label={1}; state=none" -f [string]$TaskName, [string]$Label)
        return
    }

    $summary = if ($stateRecord.PSObject.Properties.Match('summary').Count -gt 0) { [string]$stateRecord.summary } else { '' }
    $launchKind = if ($stateRecord.PSObject.Properties.Match('launchKind').Count -gt 0) { [string]$stateRecord.launchKind } else { '' }
    $launchTarget = if ($stateRecord.PSObject.Properties.Match('launchTarget').Count -gt 0) { [string]$stateRecord.launchTarget } else { '' }
    Write-Host ("store-install-state => task={0}; label={1}; state={2}; launch-kind={3}; launch-target={4}; summary={5}" -f [string]$TaskName, [string]$Label, [string]$stateRecord.state, $launchKind, $launchTarget, $summary)
}

function Write-CopyExclusionEvidence {
    param(
        [string]$ManagerProfilePath,
        [string]$AssistantProfilePath,
        [string]$DefaultProfilePath
    )

    Write-Host "COPY USER EXCLUSION EVIDENCE:"

    $evidencePaths = @(
        'AppData\Roaming\Microsoft\Credentials',
        'AppData\Roaming\ollama app.exe\EBWebView\Default\Network',
        'AppData\Roaming\ollama app.exe\EBWebView\Default\Safe Browsing Network',
        'AppData\Roaming\ollama app.exe\EBWebView\Default\Cache',
        'AppData\Roaming\ollama app.exe\EBWebView\Default\Code Cache',
        'AppData\Roaming\ollama app.exe\EBWebView\Default\GPUCache',
        'AppData\Roaming\ollama app.exe\EBWebView\Default\Service Worker\CacheStorage',
        'AppData\Roaming\ollama app.exe\EBWebView\Default\Service Worker\ScriptCache',
        'AppData\Local\Microsoft\Windows\WebCache\WebCacheV01.dat'
    )

    foreach ($relativePath in @($evidencePaths)) {
        $managerPath = Join-Path $ManagerProfilePath $relativePath
        $assistantPath = Join-Path $AssistantProfilePath $relativePath
        $defaultPath = Join-Path $DefaultProfilePath $relativePath
        Write-Host ("copy-exclusion => {0}" -f $relativePath)
        Write-Host (" manager-source-present => {0}" -f (Test-Path -LiteralPath $managerPath))
        Write-Host (" assistant-target-present => {0}" -f (Test-Path -LiteralPath $assistantPath))
        Write-Host (" default-target-present => {0}" -f (Test-Path -LiteralPath $defaultPath))
    }
}

function Resolve-ShortcutEmbeddedCommandPath {
    param(
        [string]$TargetPath,
        [string]$Arguments
    )

    $targetText = [string]$TargetPath
    $argumentsText = [string]$Arguments
    if ([string]::IsNullOrWhiteSpace([string]$targetText)) {
        return ''
    }

    $targetFileName = [System.IO.Path]::GetFileName([string]$targetText)
    if (-not [string]::Equals($targetFileName, 'cmd.exe', [System.StringComparison]::OrdinalIgnoreCase) -and
        -not [string]::Equals($targetFileName, 'powershell.exe', [System.StringComparison]::OrdinalIgnoreCase) -and
        -not [string]::Equals($targetFileName, 'pwsh.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
        return ''
    }

    return (Resolve-EmbeddedShortcutCommandPath -Arguments $argumentsText)
}

function Get-ShortcutTargetHealth {
    param(
        [psobject]$Shortcut
    )

    $targetPath = if ($null -ne $Shortcut -and $Shortcut.PSObject.Properties.Match('TargetPath').Count -gt 0) { [string]$Shortcut.TargetPath } else { '' }
    $arguments = if ($null -ne $Shortcut -and $Shortcut.PSObject.Properties.Match('Arguments').Count -gt 0) { [string]$Shortcut.Arguments } else { '' }
    $workingDirectory = if ($null -ne $Shortcut -and $Shortcut.PSObject.Properties.Match('WorkingDirectory').Count -gt 0) { [string]$Shortcut.WorkingDirectory } else { '' }
    $resolvedInvocation = if (Get-Command Get-ProdicloudShortcutResolvedInvocation -ErrorAction SilentlyContinue) {
        Get-ProdicloudShortcutResolvedInvocation -TargetPath $targetPath -Arguments $arguments -WorkingDirectory $workingDirectory
    }
    else {
        $null
    }

    if ([string]::IsNullOrWhiteSpace([string]$targetPath)) {
        return 'orphan-target'
    }

    if ([string]::Equals([System.IO.Path]::GetFileName([string]$targetPath), 'explorer.exe', [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]$arguments -like 'shell:AppsFolder\*') {
        return 'appsfolder'
    }

    if ($null -ne $resolvedInvocation -and [bool]$resolvedInvocation.UsesManagedLauncher) {
        if (-not (Test-Path -LiteralPath ([string]$resolvedInvocation.LauncherPath))) {
            return 'wrapper-missing-launcher'
        }
        $resolvedTargetPath = [Environment]::ExpandEnvironmentVariables([string]$resolvedInvocation.TargetPath)
        if ([string]::IsNullOrWhiteSpace([string]$resolvedTargetPath) -or -not (Test-Path -LiteralPath $resolvedTargetPath)) {
            return 'wrapper-missing-command'
        }

        return 'file+launcher'
    }

    if (Test-Path -LiteralPath $targetPath) {
        $embeddedCommandPath = Resolve-ShortcutEmbeddedCommandPath -TargetPath $targetPath -Arguments $arguments
        if ([string]::IsNullOrWhiteSpace([string]$embeddedCommandPath)) {
            return 'file'
        }

        if (Test-Path -LiteralPath $embeddedCommandPath) {
            return 'file+embedded'
        }

        return 'wrapper-missing-command'
    }

    return 'orphan-target'
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
        Write-Warning ("startup-profile-decode-failed => {0}" -f $_.Exception.Message)
        return @()
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
        Sid = [string]$profile.PSChildName
        ProfilePath = [string]$profile.ProfileImagePath
    }
}

function Remove-RegistryMountIfPresent {
    param([string]$MountName)

    if ([string]::IsNullOrWhiteSpace([string]$MountName)) {
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
    $exitCode = Invoke-RegQuiet -Verb 'load' -Arguments @(("HKU\{0}" -f $MountName), $HiveFilePath)
    if ($exitCode -ne 0) {
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

    $mountPath = ("Registry::HKEY_USERS\{0}" -f $MountName)
    foreach ($attempt in 1..6) {
        if (-not (Test-Path -LiteralPath $mountPath)) {
            return
        }

        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        Start-Sleep -Milliseconds 400

        $exitCode = Invoke-RegQuiet -Verb 'unload' -Arguments @(("HKU\{0}" -f $MountName))
        if ($exitCode -eq 0 -or -not (Test-Path -LiteralPath $mountPath)) {
            return
        }

        Start-Sleep -Milliseconds 500
    }

    $exitCode = Invoke-RegQuiet -Verb 'unload' -Arguments @(("HKU\{0}" -f $MountName))
    if ($exitCode -eq 0 -or -not (Test-Path -LiteralPath $mountPath)) {
        return
    }

    Write-Warning ("reg unload failed for HKU\{0} with exit code {1}" -f $MountName, $exitCode)
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

function Get-ManagerContext {
    param([string]$UserName)

    $profileInfo = Get-LocalUserProfileInfo -UserName $UserName
    $mountName = ''
    $mainRoot = ("Registry::HKEY_USERS\{0}" -f [string]$profileInfo.Sid)
    if (-not (Test-Path -LiteralPath $mainRoot)) {
        $mountName = 'Prodicloud10099Manager'
        $mainRoot = Mount-RegistryHive -MountName $mountName -HiveFilePath (Join-Path ([string]$profileInfo.ProfilePath) 'NTUSER.DAT')
    }

    return [pscustomobject]@{
        ProfileInfo = $profileInfo
        MainRoot = [string]$mainRoot
        MountName = [string]$mountName
        StartupFolder = (Join-Path ([string]$profileInfo.ProfilePath) 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup')
        StartupApprovedStartupFolderPath = ("{0}\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder" -f [string]$mainRoot)
        RunPath = ("{0}\Software\Microsoft\Windows\CurrentVersion\Run" -f [string]$mainRoot)
        RunApprovalPath = ("{0}\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run" -f [string]$mainRoot)
        Run32Path = ("{0}\Software\Microsoft\Windows\CurrentVersion\Run32" -f [string]$mainRoot)
        Run32ApprovalPath = ("{0}\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32" -f [string]$mainRoot)
    }
}

function Get-InstalledLanguageSafe {
    param([string]$LanguageTag)

    if ([string]::IsNullOrWhiteSpace([string]$LanguageTag) -or -not (Get-Command Get-InstalledLanguage -ErrorAction SilentlyContinue)) {
        return @()
    }

    return @(
        Get-InstalledLanguage -Language $LanguageTag -ErrorAction SilentlyContinue |
            Where-Object { $_ -ne $null }
    )
}

function Get-LanguageFeatureSummary {
    param([AllowNull()]$InstalledLanguage)

    if ($null -eq $InstalledLanguage) {
        return 'details not reported by Windows'
    }

    $parts = New-Object 'System.Collections.Generic.List[string]'
    foreach ($propertyName in @('LanguageFeatures', 'InstalledLanguageFeatures', 'Features')) {
        if ($InstalledLanguage.PSObject.Properties.Match($propertyName).Count -lt 1) {
            continue
        }

        $value = $InstalledLanguage.$propertyName
        if ($null -eq $value) {
            continue
        }

        foreach ($entry in @($value)) {
            $text = [string]$entry
            if ([string]::IsNullOrWhiteSpace([string]$text)) {
                continue
            }

            if (-not $parts.Contains($text)) {
                $parts.Add($text) | Out-Null
            }
        }
    }

    if ($parts.Count -eq 0) {
        foreach ($propertyName in @('BasicTyping', 'Handwriting', 'Ocr', 'Speech', 'TextToSpeech')) {
            if ($InstalledLanguage.PSObject.Properties.Match($propertyName).Count -lt 1) {
                continue
            }

            $parts.Add(("{0}={1}" -f $propertyName, [string]$InstalledLanguage.$propertyName)) | Out-Null
        }
    }

    if ($parts.Count -eq 0) {
        return 'details not reported by Windows'
    }

    return (@($parts.ToArray()) -join ', ')
}

function Get-LanguageCapabilityCatalog {
    param([string]$LanguageTag)

    $languageTagText = [string]$LanguageTag
    return [ordered]@{
        'Language.Basic'        = ("Language.Basic~~~{0}~0.0.1.0" -f $languageTagText)
        'Language.Handwriting'  = ("Language.Handwriting~~~{0}~0.0.1.0" -f $languageTagText)
        'Language.OCR'          = ("Language.OCR~~~{0}~0.0.1.0" -f $languageTagText)
        'Language.Speech'       = ("Language.Speech~~~{0}~0.0.1.0" -f $languageTagText)
        'Language.TextToSpeech' = ("Language.TextToSpeech~~~{0}~0.0.1.0" -f $languageTagText)
    }
}

function Get-LanguageCapabilityStateMap {
    param([string]$LanguageTag)

    if ([string]::IsNullOrWhiteSpace([string]$LanguageTag) -or -not (Get-Command Get-WindowsCapability -ErrorAction SilentlyContinue)) {
        return $null
    }

    $catalog = Get-LanguageCapabilityCatalog -LanguageTag $LanguageTag
    $availableCapabilities = @(
        Get-WindowsCapability -Online -ErrorAction SilentlyContinue |
            Where-Object { $_ -ne $null -and -not [string]::IsNullOrWhiteSpace([string]$_.Name) }
    )

    $stateMap = [ordered]@{}
    foreach ($capabilityName in @($catalog.Keys)) {
        $capabilityIdentity = [string]$catalog[$capabilityName]
        $capability = $availableCapabilities | Where-Object { [string]$_.Name -eq $capabilityIdentity } | Select-Object -First 1
        $stateMap[$capabilityName] = if ($null -eq $capability) { 'Unavailable' } else { [string]$capability.State }
    }

    return [pscustomobject]$stateMap
}

function Convert-LanguageCapabilityStateMapToSummary {
    param([AllowNull()]$StateMap)

    if ($null -eq $StateMap) {
        return 'unavailable'
    }

    $parts = New-Object 'System.Collections.Generic.List[string]'
    foreach ($capabilityName in @('Language.Basic', 'Language.Handwriting', 'Language.OCR', 'Language.Speech', 'Language.TextToSpeech')) {
        $stateValue = 'Unavailable'
        if ($StateMap.PSObject.Properties.Match($capabilityName).Count -gt 0) {
            $candidate = [string]$StateMap.$capabilityName
            if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) {
                $stateValue = $candidate
            }
        }

        $parts.Add(("{0}={1}" -f [string]$capabilityName, [string]$stateValue)) | Out-Null
    }

    return (@($parts.ToArray()) -join ', ')
}

function Get-TimeZoneIdSafe {
    try {
        $timeZone = Get-TimeZone -ErrorAction Stop
        if ($null -ne $timeZone -and $timeZone.PSObject.Properties.Match('Id').Count -gt 0) {
            return [string]$timeZone.Id
        }
    }
    catch {
    }

    return ''
}

function Get-RegistryPreloadSummary {
    param([string]$RootPath)

    if ([string]::IsNullOrWhiteSpace([string]$RootPath)) {
        return ''
    }

    $preloadPath = Join-Path $RootPath 'Keyboard Layout\Preload'
    if (-not (Test-Path -LiteralPath $preloadPath)) {
        return ''
    }

    $preloadItem = Get-Item -LiteralPath $preloadPath -ErrorAction SilentlyContinue
    if ($null -eq $preloadItem) {
        return ''
    }

    $pairs = @()
    foreach ($propertyName in @($preloadItem.Property | Sort-Object)) {
        $propertyValue = Get-RegistryValueText -Path $preloadPath -ValueName ([string]$propertyName)
        if ([string]::IsNullOrWhiteSpace([string]$propertyValue)) {
            continue
        }
        $pairs += ("{0}={1}" -f [string]$propertyName, [string]$propertyValue)
    }

    return (@($pairs) -join '; ')
}

function Get-RegistryLanguageSummary {
    param([string]$RootPath)

    if ([string]::IsNullOrWhiteSpace([string]$RootPath)) {
        return ''
    }

    $internationalPath = Join-Path $RootPath 'Control Panel\International'
    if (-not (Test-Path -LiteralPath $internationalPath)) {
        return ''
    }

    $localeName = Get-RegistryValueText -Path $internationalPath -ValueName 'LocaleName'
    $shortTime = Get-RegistryValueText -Path $internationalPath -ValueName 'sShortTime'
    $timeFormat = Get-RegistryValueText -Path $internationalPath -ValueName 'sTimeFormat'
    return ("locale={0}; short-time={1}; time-format={2}; keyboard={3}" -f [string]$localeName, [string]$shortTime, [string]$timeFormat, (Get-RegistryPreloadSummary -RootPath $RootPath))
}

function Get-UserLanguageReadback {
    param(
        [string]$UserName,
        [string]$UserPassword
    )

    if (-not (Test-Path -LiteralPath $interactiveHelperPath)) {
        return $null
    }

    $interactiveTaskName = ('vm-summary-language-readback-{0}' -f [string]$UserName)
    $paths = Get-ProdicloudInteractivePaths -TaskName $interactiveTaskName
    $payloadPath = Join-Path $paths.RootPath 'language-readback.json'
    Remove-Item -LiteralPath $payloadPath -Force -ErrorAction SilentlyContinue

    $workerScript = @'
$ErrorActionPreference = "Stop"
$helperPath = "__HELPER_PATH__"
$resultPath = "__RESULT_PATH__"
$taskName = "__TASK_NAME__"
$payloadPath = "__PAYLOAD_PATH__"

. $helperPath

function Write-JsonPayload {
    param(
        [string]$Path,
        [object]$Value
    )

    $parentPath = Split-Path -Path $Path -Parent
    Ensure-ProdicloudDirectory -Path $parentPath
    [System.IO.File]::WriteAllText($Path, ([string]($Value | ConvertTo-Json -Depth 8)), (New-Object System.Text.UTF8Encoding($false)))
}

function Get-RegistryValueString {
    param(
        [string]$Path,
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace([string]$Path) -or [string]::IsNullOrWhiteSpace([string]$Name) -or -not (Test-Path -LiteralPath $Path)) {
        return ''
    }

    $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $item) {
        return ''
    }

    return [string]$item.$Name
}

try {
    $languageListSummary = @(
        Get-WinUserLanguageList |
            ForEach-Object {
                $tips = if ($_.PSObject.Properties.Match('InputMethodTips').Count -gt 0 -and $null -ne $_.InputMethodTips) { (@($_.InputMethodTips) -join ',') } else { '' }
                ("{0}:{1}" -f [string]$_.LanguageTag, [string]$tips)
            }
    ) -join '; '

    $defaultInputMethodSummary = ''
    try {
        $defaultInputMethod = Get-WinDefaultInputMethodOverride
        if ($null -ne $defaultInputMethod -and $defaultInputMethod.PSObject.Properties.Match('InputMethodTip').Count -gt 0) {
            $defaultInputMethodSummary = [string]$defaultInputMethod.InputMethodTip
        }
    }
    catch {
    }

    $preloadPath = 'HKCU:\Keyboard Layout\Preload'
    $preloadSummary = ''
    if (Test-Path -LiteralPath $preloadPath) {
        $preloadItem = Get-Item -LiteralPath $preloadPath -ErrorAction SilentlyContinue
        $preloadSummary = @(
            @($preloadItem.Property | Sort-Object) |
                ForEach-Object {
                    ("{0}={1}" -f [string]$_, (Get-RegistryValueString -Path $preloadPath -Name ([string]$_)))
                }
        ) -join '; '
    }

    $payload = [ordered]@{
        UserName = [Environment]::UserName
        LanguageList = [string]$languageListSummary
        UiLanguage = [string](Get-WinUILanguageOverride)
        Culture = [string](Get-Culture).Name
        GeoId = [string](Get-WinHomeLocation).GeoId
        LocaleName = [string](Get-RegistryValueString -Path 'HKCU:\Control Panel\International' -Name 'LocaleName')
        ShortTime = [string](Get-RegistryValueString -Path 'HKCU:\Control Panel\International' -Name 'sShortTime')
        TimeFormat = [string](Get-RegistryValueString -Path 'HKCU:\Control Panel\International' -Name 'sTimeFormat')
        DefaultInputMethod = [string]$defaultInputMethodSummary
        KeyboardPreload = [string]$preloadSummary
    }

    Write-JsonPayload -Path $payloadPath -Value $payload
    Write-ProdicloudInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $true -Summary 'Language readback collected.' -Details @($payload.LanguageList)
}
catch {
    Write-ProdicloudInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $false -Summary 'Language readback failed.' -Details @([string]$_.Exception.Message)
    throw
}
'@

    $workerScript = $workerScript.Replace('__HELPER_PATH__', $interactiveHelperPath)
    $workerScript = $workerScript.Replace('__RESULT_PATH__', [string]$paths.ResultPath)
    $workerScript = $workerScript.Replace('__TASK_NAME__', $interactiveTaskName)
    $workerScript = $workerScript.Replace('__PAYLOAD_PATH__', [string]$payloadPath)

    try {
        $null = Invoke-ProdicloudInteractiveDesktopAutomation `
            -TaskName $interactiveTaskName `
            -RunAsUser $UserName `
            -RunAsPassword $UserPassword `
            -WorkerScriptText $workerScript `
            -WaitTimeoutSeconds 300

        if (-not (Test-Path -LiteralPath $payloadPath)) {
            return $null
        }

        return (ConvertFrom-Json -InputObject ([string](Get-Content -LiteralPath $payloadPath -Raw -ErrorAction Stop)) -ErrorAction Stop)
    }
    catch {
        Write-Warning ("language-readback-failed => {0} => {1}" -f [string]$UserName, $_.Exception.Message)
        return $null
    }
    finally {
        Remove-Item -LiteralPath $payloadPath -Force -ErrorAction SilentlyContinue
    }
}

function Write-InstalledLanguageStatus {
    param([string]$LanguageTag)

    $rows = @(Get-InstalledLanguageSafe -LanguageTag $LanguageTag)
    if (@($rows).Count -lt 1) {
        $capabilityState = Get-LanguageCapabilityStateMap -LanguageTag $LanguageTag
        $capabilitySummary = Convert-LanguageCapabilityStateMapToSummary -StateMap $capabilityState
        if (-not [string]::IsNullOrWhiteSpace([string]$capabilitySummary) -and $capabilitySummary -match '(?i)InstallPending|Installed') {
            Write-Host ("installed-language => {0} => installed=pending; features={1}" -f [string]$LanguageTag, [string]$capabilitySummary)
            return
        }

        Write-Host ("installed-language => {0} => installed=false" -f [string]$LanguageTag)
        return
    }

    Write-Host ("installed-language => {0} => installed=true; features={1}" -f [string]$LanguageTag, (Get-LanguageFeatureSummary -InstalledLanguage $rows[0]))
}

function Write-UserLanguageStatus {
    param(
        [string]$UserName,
        [string]$UserPassword
    )

    $readback = Get-UserLanguageReadback -UserName $UserName -UserPassword $UserPassword
    if ($null -eq $readback) {
        Write-Host ("user-language-status => {0} => unavailable" -f [string]$UserName)
        return
    }

    Write-Host ("user-language-status => {0} => ui-language={1}; culture={2}; geo-id={3}; locale={4}; short-time={5}; time-format={6}; default-input={7}; keyboard={8}; languages={9}" -f [string]$UserName, [string]$readback.UiLanguage, [string]$readback.Culture, [string]$readback.GeoId, [string]$readback.LocaleName, [string]$readback.ShortTime, [string]$readback.TimeFormat, [string]$readback.DefaultInputMethod, [string]$readback.KeyboardPreload, [string]$readback.LanguageList)
}

function Write-DefaultLanguageStatus {
    $defaultRoot = 'Registry::HKEY_USERS\.DEFAULT'
    Write-Host ("welcome-screen-language => {0}" -f (Get-RegistryLanguageSummary -RootPath $defaultRoot))

    $defaultProfileHive = 'C:\Users\Default\NTUSER.DAT'
    if (-not (Test-Path -LiteralPath $defaultProfileHive)) {
        Write-Host 'new-user-language => unavailable'
        return
    }

    $mountName = 'Prodicloud10006Default'
    $mountedRoot = $null
    try {
        $mountedRoot = Mount-RegistryHive -MountName $mountName -HiveFilePath $defaultProfileHive
        Write-Host ("new-user-language => {0}" -f (Get-RegistryLanguageSummary -RootPath $mountedRoot))
    }
    catch {
        Write-Warning ("new-user-language-readback-failed => {0}" -f $_.Exception.Message)
    }
    finally {
        if (-not [string]::IsNullOrWhiteSpace([string]$mountName)) {
            Dismount-RegistryHive -MountName $mountName
        }
    }
}

function Resolve-StartupDisplayName {
    param([string]$Key)

    switch ([string]$Key) {
        'docker-desktop' { return 'Docker Desktop' }
        'ollama' { return 'Ollama' }
        'onedrive' { return 'OneDrive' }
        'teams' { return 'Teams' }
        'itunes-helper' { return 'iTunesHelper' }
        'google-drive' { return 'Google Drive' }
        'windscribe' { return 'Windscribe' }
        'anydesk' { return 'AnyDesk' }
        'codex-app' { return 'Codex App' }
        'jaws' { return 'JAWS' }
        default { return '' }
    }
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
            RunPath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
            ApprovalPath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
        }
        [pscustomobject]@{
            Scope = 'LocalMachine'
            EntryType = 'Run32'
            Kind = 'Run'
            RunPath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run32'
            ApprovalPath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'
        }
        [pscustomobject]@{
            Scope = 'LocalMachine'
            EntryType = 'StartupFolder'
            Kind = 'StartupFolder'
            DirectoryPath = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp'
            ApprovalPath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
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

function Get-RegistryValueText {
    param(
        [string]$Path,
        [string]$ValueName
    )

    if ([string]::IsNullOrWhiteSpace([string]$Path) -or [string]::IsNullOrWhiteSpace([string]$ValueName)) {
        return $null
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $item = Get-ItemProperty -Path $Path -Name $ValueName -ErrorAction SilentlyContinue
    if ($null -eq $item) {
        return $null
    }

    return [string]$item.$ValueName
}

function Write-ShortcutReadback {
    param(
        [string]$Label,
        [string]$ShortcutPath
    )

    $shortcut = Get-ShortcutDetails -ShortcutPath $ShortcutPath
    $targetHealth = Get-ShortcutTargetHealth -Shortcut $shortcut
    $resolvedInvocation = if (Get-Command Get-ProdicloudShortcutResolvedInvocation -ErrorAction SilentlyContinue) {
        Get-ProdicloudShortcutResolvedInvocation -TargetPath ([string]$shortcut.TargetPath) -Arguments ([string]$shortcut.Arguments) -WorkingDirectory ([string]$shortcut.WorkingDirectory)
    }
    else {
        $null
    }
    Write-Host ("{0} => {1}" -f $Label, $ShortcutPath)
    Write-Host (" target => {0}" -f [string]$shortcut.TargetPath)
    Write-Host (" args => {0}" -f [string]$shortcut.Arguments)
    if ($null -ne $resolvedInvocation -and [bool]$resolvedInvocation.UsesManagedLauncher) {
        Write-Host (" launcher => {0}" -f [string]$resolvedInvocation.LauncherPath)
        Write-Host (" effective-target => {0}" -f [string]$resolvedInvocation.TargetPath)
        Write-Host (" effective-args => {0}" -f [string]$resolvedInvocation.Arguments)
    }
    Write-Host (" hotkey => {0}" -f [string]$shortcut.Hotkey)
    Write-Host (" start-in => {0}" -f [string]$shortcut.WorkingDirectory)
    Write-Host (" show => {0}" -f [int]$shortcut.WindowStyle)
    Write-Host (" run-as-admin => {0}" -f [bool]$shortcut.RunAsAdmin)
    Write-Host (" target-health => {0}" -f [string]$targetHealth)
}

function Write-StartupEntryStatus {
    param(
        [string]$DisplayName,
        [psobject]$ProfileEntry,
        [object[]]$LocationDefinitions
    )

    $location = Resolve-RequestedStartupLocation -ProfileEntry $ProfileEntry -LocationDefinitions $LocationDefinitions
    if ($null -eq $location) {
        Write-Warning ("startup-entry-skip => {0} => unsupported method '{1}/{2}'." -f $DisplayName, [string]$ProfileEntry.Scope, [string]$ProfileEntry.EntryType)
        return
    }

    if ([string]::Equals([string]$location.Kind, 'Run', [System.StringComparison]::OrdinalIgnoreCase)) {
        $commandText = Get-RegistryValueText -Path ([string]$location.RunPath) -ValueName $DisplayName
        if ($null -eq $commandText) {
            Write-Host ("missing-startup-entry => {0} => {1}/{2}" -f $DisplayName, [string]$location.Scope, [string]$location.EntryType)
            return
        }

        $approvalState = Get-StartupApprovedStateCode -Path ([string]$location.ApprovalPath) -ValueName $DisplayName
        Write-Host ("startup-entry => {0} => {1}/{2}" -f $DisplayName, [string]$location.Scope, [string]$location.EntryType)
        Write-Host (" command => {0}" -f [string]$commandText)
        Write-Host (" approval-state => {0}" -f [int]$approvalState)
        Write-Host (" enabled => {0}" -f [bool]($approvalState -lt 0 -or $approvalState -eq 2))
        return
    }

    $shortcutPath = Join-Path ([string]$location.DirectoryPath) ($DisplayName + '.lnk')
    if (-not (Test-Path -LiteralPath $shortcutPath)) {
        Write-Host ("missing-startup-entry => {0} => {1}/{2}" -f $DisplayName, [string]$location.Scope, [string]$location.EntryType)
        return
    }

    $approvalState = Get-StartupApprovedStateCode -Path ([string]$location.ApprovalPath) -ValueName ($DisplayName + '.lnk')
    Write-ShortcutReadback -Label 'startup-entry' -ShortcutPath $shortcutPath
    Write-Host (" scope => {0}" -f [string]$location.Scope)
    Write-Host (" method => {0}" -f [string]$location.EntryType)
    Write-Host (" approval-state => {0}" -f [int]$approvalState)
    Write-Host (" enabled => {0}" -f [bool]($approvalState -lt 0 -or $approvalState -eq 2))
}

function Write-DesktopArtifactScan {
    param(
        [string]$Label,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace([string]$Path) -or -not (Test-Path -LiteralPath $Path)) {
        Write-Host ("desktop-artifacts-skip => {0} => {1}" -f $Label, $Path)
        return
    }

    $matches = @(
        Get-ChildItem -LiteralPath $Path -Force -File -ErrorAction SilentlyContinue |
            Where-Object {
                [string]::Equals([string]$_.Name, 'desktop.ini', [System.StringComparison]::OrdinalIgnoreCase) -or
                [string]::Equals([string]$_.Name, 'Thumbs.db', [System.StringComparison]::OrdinalIgnoreCase)
            }
    )
    if (@($matches).Count -eq 0) {
        Write-Host ("desktop-artifacts-clean => {0} => {1}" -f $Label, $Path)
        return
    }

    foreach ($match in @($matches)) {
        Write-Host ("desktop-artifact => {0} => {1}" -f $Label, $match.FullName)
    }
}

function Write-DesktopState {
    param(
        [string]$Label,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace([string]$Path) -or -not (Test-Path -LiteralPath $Path)) {
        Write-Host ("desktop-state-skip => {0} => {1}" -f $Label, $Path)
        return
    }

    $entries = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
    Write-Host ("desktop-state => {0} => count={1}" -f $Label, @($entries).Count)
    foreach ($entry in @($entries)) {
        Write-Host (" desktop-entry => {0}" -f $entry.FullName)
    }
}

function Get-DirectoryFileCount {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace([string]$Path) -or -not (Test-Path -LiteralPath $Path)) {
        return 0
    }

    return @(
        Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue
    ).Count
}

function Write-JawsSettingsStatus {
    param(
        [string]$Label,
        [string]$ProfilePath
    )

    $settingsPath = Join-Path ([string]$ProfilePath) 'AppData\Roaming\Freedom Scientific\JAWS\2025\Settings'
    $exists = Test-Path -LiteralPath $settingsPath
    $fileCount = if ($exists) { Get-DirectoryFileCount -Path $settingsPath } else { 0 }
    Write-Host ("jaws-settings => {0} => exists={1}; file-count={2}; path={3}" -f [string]$Label, [bool]$exists, [int]$fileCount, [string]$settingsPath)
}

function Write-JawsMachineRegistryStatus {
    param([string]$RegistryPath)

    Write-Host ("jaws-machine-registry => {0} => exists={1}" -f [string]$RegistryPath.Replace('Registry::HKEY_LOCAL_MACHINE\', 'HKLM\'), [bool](Test-Path -LiteralPath $RegistryPath))
}

function Write-JawsUserRegistryStatus {
    param([string]$UserName)

    $userContext = $null
    try {
        $userContext = Get-ManagerContext -UserName $UserName
        $registryPath = ("{0}\Software\Freedom Scientific" -f [string]$userContext.MainRoot)
        Write-Host ("jaws-user-registry => {0} => exists={1}; path={2}" -f [string]$UserName, [bool](Test-Path -LiteralPath $registryPath), [string]$registryPath)
    }
    catch {
        $message = [string]$_.Exception.Message
        if ($message -match '(?i)registry hive file was not found|ntuser\.dat|requested registry access is not allowed|access is denied') {
            Write-Host ("jaws-user-registry => {0} => unavailable; reason={1}" -f [string]$UserName, $message)
        }
        else {
            Write-Warning ("jaws-user-registry-readback-failed => {0} => {1}" -f [string]$UserName, $message)
        }
    }
    finally {
        if ($null -ne $userContext -and -not [string]::IsNullOrWhiteSpace([string]$userContext.MountName)) {
            Dismount-RegistryHive -MountName ([string]$userContext.MountName)
        }
    }
}

function Write-BrowserUserDataStatus {
    param(
        [string]$BrowserName,
        [string]$UserName,
        [string]$RelativeRoot
    )

    $rootPath = Join-Path ("C:\Users\{0}" -f [string]$UserName) [string]$RelativeRoot
    $localStatePath = Join-Path $rootPath 'Local State'
    $defaultPreferencesPath = Join-Path $rootPath 'Default\Preferences'
    $defaultExtensionsPath = Join-Path $rootPath 'Default\Extensions'

    Write-Host ("browser-user-data => {0} => {1} => exists={2}; local-state={3}; default-preferences={4}; default-extensions={5}; path={6}" -f [string]$BrowserName, [string]$UserName, [bool](Test-Path -LiteralPath $rootPath), [bool](Test-Path -LiteralPath $localStatePath), [bool](Test-Path -LiteralPath $defaultPreferencesPath), [bool](Test-Path -LiteralPath $defaultExtensionsPath), [string]$rootPath)
}

$resolvedCompanyName = if (Test-InvalidCompanyName -Value $companyName) { $unresolvedCompanyNameToken } else { $companyName.Trim() }
$resolvedCompanyWebAddress = if (Test-InvalidCompanyWebAddress -Value $companyWebAddress) { $unresolvedCompanyWebAddressToken } else { $companyWebAddress.Trim() }
$resolvedCompanyDisplayName = if (Test-InvalidCompanyName -Value $companyName) { $unresolvedCompanyNameToken } else { ConvertTo-TitleCaseShortcutText -Value $companyName.Trim() }
$resolvedEmployeeEmailAddress = if (Test-InvalidEmployeeEmailAddress -Value $employeeEmailAddress) { $unresolvedEmployeeEmailAddressToken } else { $employeeEmailAddress.Trim() }
$resolvedEmployeeFullName = if (Test-InvalidEmployeeFullName -Value $employeeFullName) { $unresolvedEmployeeFullNameToken } else { $employeeFullName.Trim() }
$script:resolvedEmployeeEmailBaseName = ConvertTo-LowerInvariantText -Value (Get-EmployeeEmailBaseName -EmailAddress $resolvedEmployeeEmailAddress)
$script:resolvedCompanyChromeProfileDirectory = ConvertTo-LowerInvariantText -Value $resolvedCompanyName
$companyWebRootUrl = Normalize-ShortcutUrl -Value $resolvedCompanyWebAddress
$expectedChromeBusinessArgs = ((Get-ChromeArgsPrefix -ProfileKind 'business' -Variant 'remote') + ' "' + [string]$companyWebRootUrl + '"')
$expectedChromeSetupArgs = ((Get-ChromeArgsPrefix -ProfileKind 'business' -Variant 'setup') + ' "chrome://settings/syncSetup"')
$expectedEdgeBusinessArgs = Get-EdgeArgsPrefix -ProfileKind 'business' -Variant 'remote'
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
$cicekSepetiLabel = ConvertFrom-UnicodeCodePoints -CodePoints @(0x00C7, 0x0069, 0x00E7, 0x0065, 0x006B, 0x0053, 0x0065, 0x0070, 0x0065, 0x0074, 0x0069)
$eksiSozlukLabel = ConvertFrom-UnicodeCodePoints -CodePoints @(0x0045, 0x006B, 0x015F, 0x0069, 0x0053, 0x00F6, 0x007A, 0x006C, 0x00FC, 0x006B)
$publicShortcutNames = @(
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
    ("e1Mail {0}" -f $resolvedEmployeeEmailAddress),
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
    ("q1{0}" -f $eksiSozlukLabel),
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
    ("r13{0} Business" -f $cicekSepetiLabel),
    ("r14{0} Personal" -f $cicekSepetiLabel),
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
    ("s15{0} Web" -f $resolvedCompanyDisplayName),
    ("s16{0} Blog" -f $resolvedCompanyDisplayName),
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
)

Write-Host "Version Info:"
try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    Write-Host "WindowsProductName=$($os.Caption)"
    Write-Host "WindowsVersion=$($os.Version)"
    Write-Host "OsBuildNumber=$($os.BuildNumber)"
}
catch {
    Write-Warning "Version info collection failed: $($_.Exception.Message)"
}

Refresh-SessionPath
Write-Host "APP PATH CHECKS:"
foreach ($commandName in @("choco", "git", "node", "python", "py", "pwsh", "gh", "ffmpeg", "7z", "az", "docker", "wsl", "ollama")) {
    $resolvedCommandPath = switch ($commandName) {
        'az' { Resolve-CommandPath -CommandName 'az' -FallbackCandidates @('C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd') }
        'docker' { Resolve-CommandPath -CommandName 'docker' -FallbackCandidates @('C:\Program Files\Docker\Docker\resources\bin\docker.exe') }
        '7z' { Resolve-CommandPath -CommandName '7z' -FallbackCandidates @('C:\ProgramData\chocolatey\bin\7z.exe','C:\Program Files\7-Zip\7z.exe','C:\Program Files (x86)\7-Zip\7z.exe') }
        'ollama' { Resolve-CommandPath -CommandName 'ollama' -FallbackCandidates @((Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'), 'C:\Program Files\Ollama\ollama.exe') }
        default { Resolve-CommandPath -CommandName $commandName }
    }

    if ([string]::IsNullOrWhiteSpace([string]$resolvedCommandPath)) {
        Write-Host "$commandName => not-found"
    }
    else {
        Write-Host ("{0} => {1}" -f $commandName, [string]$resolvedCommandPath)
    }
}

Write-Host "OPEN Ports:"
Get-NetTCPConnection -LocalPort __RDP_PORT__,__SSH_PORT__ -State Listen | Select-Object LocalAddress,LocalPort,OwningProcess | Format-Table -AutoSize
Write-Host "FIREWALL STATUS:"
Get-NetFirewallProfile | Select-Object Name,Enabled,DefaultInboundAction,DefaultOutboundAction | Format-Table -AutoSize

Write-Host "RDP COMPATIBILITY:"
$rdpTcpRoot = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
$terminalServerRoot = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
Get-ItemProperty -Path $rdpTcpRoot -Name UserAuthentication,SecurityLayer,MinEncryptionLevel -ErrorAction SilentlyContinue | Format-List *
Get-ItemProperty -Path $terminalServerRoot -Name fDenyTSConnections -ErrorAction SilentlyContinue | Format-List *

Write-Host "AUTOLOGON STATUS:"
$winlogonBaseKey = $null
$winlogonKey = $null
$winlogonReadFailed = $false
$autoAdminLogonValue = ''
$defaultUserNameValue = ''
$autologonDomain = ''
$defaultPasswordPresent = $false
try {
    $winlogonBaseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
    $winlogonKey = $winlogonBaseKey.OpenSubKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon')
    if ($null -eq $winlogonKey) {
        $winlogonReadFailed = $true
    }
    else {
        $autoAdminLogonValue = [string]$winlogonKey.GetValue('AutoAdminLogon', '')
        $defaultUserNameValue = [string]$winlogonKey.GetValue('DefaultUserName', '')
        $autologonDomain = [string]$winlogonKey.GetValue('DefaultDomainName', '')
        $defaultPasswordValue = [string]$winlogonKey.GetValue('DefaultPassword', '')
        $defaultPasswordPresent = -not [string]::IsNullOrWhiteSpace([string]$defaultPasswordValue)
    }
}
catch {
    $winlogonReadFailed = $true
}
finally {
    if ($null -ne $winlogonKey) {
        $winlogonKey.Close()
    }

    if ($null -ne $winlogonBaseKey) {
        $winlogonBaseKey.Close()
    }
}

if ($winlogonReadFailed) {
    Write-Warning "Winlogon autologon state could not be read."
}
else {
    $managerAutologonConfigured = (
        [string]::Equals([string]$autoAdminLogonValue, '1', [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals([string]$defaultUserNameValue, $managerUser, [System.StringComparison]::OrdinalIgnoreCase) -and
        -not [string]::IsNullOrWhiteSpace([string]$autologonDomain)
    )

    [pscustomobject]@{
        AutoAdminLogon = [string]$autoAdminLogonValue
        DefaultUserName = [string]$defaultUserNameValue
        DefaultDomainName = [string]$autologonDomain
        DefaultPasswordPresent = [bool]$defaultPasswordPresent
        CredentialStorageMode = $(if ($defaultPasswordPresent) { 'winlogon-defaultpassword' } else { 'sysinternals-autologon-or-external-store' })
        manager_autologon_configured = [bool]$managerAutologonConfigured
    } | Format-List *
}

Write-Host "SYSTEM RESTORE STATUS:"
Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -Name DisableSR -ErrorAction SilentlyContinue | Format-List *
try {
    $restorePoints = @(Get-ComputerRestorePoint -ErrorAction Stop)
    Write-Host ("restore-point-count={0}" -f @($restorePoints).Count)
}
catch {
    Write-Warning ("Get-ComputerRestorePoint => {0}" -f $_.Exception.Message)
}
$shadowStatus = Invoke-CommandWithTimeout -TimeoutSeconds 20 -Action { vssadmin.exe list shadows }
if (-not $shadowStatus.Success) {
    Write-Warning "vssadmin list shadows did not complete successfully"
}

Write-Host "EXPLORER BAG STATUS:"
foreach ($registryPath in @(
    'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell',
    'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\1\Shell',
    'HKCU:\Software\Microsoft\Windows\Shell\Bags\1\Desktop'
)) {
    Write-Host ("bag => {0}" -f $registryPath)
    Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue | Format-List Mode,LogicalViewMode,GroupView,Sort,SortDirection,FolderType,IconSize
}

Write-PackagedAppInventory

Write-Host "WSL FEATURE STATE:"
foreach ($featureName in @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')) {
    $featureState = Get-WindowsOptionalFeatureState -FeatureName $featureName
    if ([string]::IsNullOrWhiteSpace([string]$featureState)) {
        Write-Host ("wsl-feature => {0} => unavailable" -f $featureName)
        continue
    }

    if ([string]::Equals([string]$featureName, 'Microsoft-Windows-Subsystem-Linux', [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host ("wsl-feature => Microsoft-Windows-Subsystem-Linux => state={0}" -f $featureState)
        continue
    }

    if ([string]::Equals([string]$featureName, 'VirtualMachinePlatform', [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host ("wsl-feature => VirtualMachinePlatform => state={0}" -f $featureState)
        continue
    }

    Write-Host ("wsl-feature => {0} => state={1}" -f $featureName, $featureState)
}

Write-Host "PUBLIC DESKTOP SHORTCUT STATUS:"
$orphanManagedShortcutFiles = New-Object 'System.Collections.Generic.List[object]'
foreach ($shortcutName in @($publicShortcutNames)) {
    $shortcutPath = Join-Path $publicDesktop ($shortcutName + ".lnk")
    if (-not (Test-Path -LiteralPath $shortcutPath)) {
        Write-Host "missing-shortcut => $shortcutPath"
        continue
    }

    $shortcutHealth = Get-ShortcutHealth -ShortcutPath $shortcutPath
    $shortcut = $shortcutHealth.Details
    Write-Host "shortcut => $shortcutPath"
    Write-Host " target => $([string]$shortcut.TargetPath)"
    Write-Host " args => $([string]$shortcut.Arguments)"
    Write-Host " hotkey => $([string]$shortcut.Hotkey)"
    Write-Host " start-in => $([string]$shortcut.WorkingDirectory)"
    Write-Host " show => $([int]$shortcut.WindowStyle)"
    Write-Host " run-as-admin => $([bool]$shortcut.RunAsAdmin)"
    Write-Host " target-exists => $([bool]$shortcutHealth.TargetExists)"
    Write-Host " embedded-target => $([string]$shortcutHealth.EmbeddedTargetPath)"
    Write-Host " embedded-target-exists => $([bool]$shortcutHealth.EmbeddedTargetExists)"
    Write-Host " store-app-launch => $([bool]$shortcutHealth.IsStoreAppLaunch)"
    Write-Host " healthy => $([bool]$shortcutHealth.Healthy)"
    if (-not [bool]$shortcutHealth.Healthy) {
        $orphanManagedShortcutFiles.Add([pscustomobject]@{
            ShortcutPath = [string]$shortcutPath
            Details = $shortcut
        }) | Out-Null
    }
}

Write-Host "PUBLIC DESKTOP RECONCILE STATUS:"
$actualPublicShortcutFiles = @(
    Get-ChildItem -LiteralPath $publicDesktop -Filter "*.lnk" -File -ErrorAction SilentlyContinue | Sort-Object Name
)
$unmanagedPublicShortcutFiles = @(
    @($actualPublicShortcutFiles) |
        Where-Object {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension([string]$_.Name)
            return ($publicShortcutNames -notcontains [string]$baseName)
        }
)
Write-Host ("unmanaged-public-shortcut-count={0}" -f @($unmanagedPublicShortcutFiles).Count)
foreach ($shortcutFile in @($unmanagedPublicShortcutFiles)) {
    Write-ShortcutReadback -Label 'unmanaged-public-shortcut' -ShortcutPath ([string]$shortcutFile.FullName)
}
Write-Host ("orphan-managed-shortcut-count={0}" -f ([int]$orphanManagedShortcutFiles.Count))
foreach ($orphanShortcut in $orphanManagedShortcutFiles) {
    Write-ShortcutReadback -Label 'orphan-managed-shortcut' -ShortcutPath ([string]$orphanShortcut.ShortcutPath)
}

$edgeShortcutPath = Join-Path $publicDesktop 'a11MS Edge.lnk'
Write-Host "MS EDGE SHORTCUT CONTRACT:"
if (Test-Path -LiteralPath $edgeShortcutPath) {
    $edgeShortcutHealth = Get-ShortcutHealth -ShortcutPath $edgeShortcutPath
    $edgeShortcutDetails = $edgeShortcutHealth.Details
    $edgeResolvedInvocation = if ($null -ne $edgeShortcutHealth -and $edgeShortcutHealth.PSObject.Properties.Match('ResolvedInvocation').Count -gt 0) { $edgeShortcutHealth.ResolvedInvocation } else { $null }
    $edgeEffectiveTarget = if ($null -ne $edgeResolvedInvocation -and -not [string]::IsNullOrWhiteSpace([string]$edgeResolvedInvocation.TargetPath)) { [string]$edgeResolvedInvocation.TargetPath } else { [string]$edgeShortcutDetails.TargetPath }
    $edgeEffectiveArgs = if ($null -ne $edgeResolvedInvocation) { [string]$edgeResolvedInvocation.Arguments } else { [string]$edgeShortcutDetails.Arguments }
    $edgeArgsMatch = [string]::Equals(([string]$edgeEffectiveArgs).Trim(), ([string]$expectedEdgeBusinessArgs).Trim(), [System.StringComparison]::OrdinalIgnoreCase)
    Write-Host ("edge-shortcut-target => {0}" -f $edgeEffectiveTarget)
    Write-Host ("edge-shortcut-args => {0}" -f $edgeEffectiveArgs)
    Write-Host ("edge-shortcut-expected-args => {0}" -f [string]$expectedEdgeBusinessArgs)
    Write-Host ("edge-shortcut-user-data-root => {0}" -f $publicEdgeUserDataDir)
    if ($null -ne $edgeResolvedInvocation -and [bool]$edgeResolvedInvocation.UsesManagedLauncher) {
        Write-Host ("edge-shortcut-launcher => {0}" -f [string]$edgeResolvedInvocation.LauncherPath)
    }
    Write-Host ("edge-shortcut-args-match => {0}" -f [bool]$edgeArgsMatch)
}
else {
    Write-Host ("edge-shortcut-missing => {0}" -f $edgeShortcutPath)
}

$chromeShortcutPath = Join-Path $publicDesktop 'i1Internet Business.lnk'
Write-Host "CHROME SHORTCUT CONTRACT:"
if (Test-Path -LiteralPath $chromeShortcutPath) {
    $chromeShortcutHealth = Get-ShortcutHealth -ShortcutPath $chromeShortcutPath
    $chromeShortcutDetails = $chromeShortcutHealth.Details
    $chromeResolvedInvocation = if ($null -ne $chromeShortcutHealth -and $chromeShortcutHealth.PSObject.Properties.Match('ResolvedInvocation').Count -gt 0) { $chromeShortcutHealth.ResolvedInvocation } else { $null }
    $chromeEffectiveTarget = if ($null -ne $chromeResolvedInvocation -and -not [string]::IsNullOrWhiteSpace([string]$chromeResolvedInvocation.TargetPath)) { [string]$chromeResolvedInvocation.TargetPath } else { [string]$chromeShortcutDetails.TargetPath }
    $chromeEffectiveArgs = if ($null -ne $chromeResolvedInvocation) { [string]$chromeResolvedInvocation.Arguments } else { [string]$chromeShortcutDetails.Arguments }
    $chromeArgsMatch = [string]::Equals(([string]$chromeEffectiveArgs).Trim(), ([string]$expectedChromeBusinessArgs).Trim(), [System.StringComparison]::OrdinalIgnoreCase)
    Write-Host ("chrome-shortcut-target => {0}" -f $chromeEffectiveTarget)
    Write-Host ("chrome-shortcut-args => {0}" -f $chromeEffectiveArgs)
    Write-Host ("chrome-shortcut-expected-args => {0}" -f [string]$expectedChromeBusinessArgs)
    Write-Host ("chrome-shortcut-user-data-root => {0}" -f $publicChromeUserDataDir)
    if ($null -ne $chromeResolvedInvocation -and [bool]$chromeResolvedInvocation.UsesManagedLauncher) {
        Write-Host ("chrome-shortcut-launcher => {0}" -f [string]$chromeResolvedInvocation.LauncherPath)
    }
    Write-Host ("chrome-shortcut-args-match => {0}" -f [bool]$chromeArgsMatch)
}
else {
    Write-Host ("chrome-shortcut-missing => {0}" -f $chromeShortcutPath)
}

$chromeSetupShortcutPath = Join-Path $publicDesktop 'z1Google Account Setup.lnk'
Write-Host "CHROME SETUP SHORTCUT CONTRACT:"
if (Test-Path -LiteralPath $chromeSetupShortcutPath) {
    $chromeSetupShortcutHealth = Get-ShortcutHealth -ShortcutPath $chromeSetupShortcutPath
    $chromeSetupShortcutDetails = $chromeSetupShortcutHealth.Details
    $chromeSetupResolvedInvocation = if ($null -ne $chromeSetupShortcutHealth -and $chromeSetupShortcutHealth.PSObject.Properties.Match('ResolvedInvocation').Count -gt 0) { $chromeSetupShortcutHealth.ResolvedInvocation } else { $null }
    $chromeSetupEffectiveArgs = if ($null -ne $chromeSetupResolvedInvocation) { [string]$chromeSetupResolvedInvocation.Arguments } else { [string]$chromeSetupShortcutDetails.Arguments }
    $chromeSetupArgsMatch = [string]::Equals(([string]$chromeSetupEffectiveArgs).Trim(), ([string]$expectedChromeSetupArgs).Trim(), [System.StringComparison]::OrdinalIgnoreCase)
    Write-Host ("chrome-setup-shortcut-args => {0}" -f $chromeSetupEffectiveArgs)
    Write-Host ("chrome-setup-shortcut-expected-args => {0}" -f [string]$expectedChromeSetupArgs)
    Write-Host ("chrome-setup-shortcut-args-match => {0}" -f [bool]$chromeSetupArgsMatch)
}
else {
    Write-Host ("chrome-setup-shortcut-missing => {0}" -f $chromeSetupShortcutPath)
}

Write-Host "BROWSER USER DATA STATUS:"
Write-BrowserUserDataStatus -BrowserName 'chrome' -UserName $managerUser -RelativeRoot 'AppData\Local\Google\Chrome\User Data'
Write-BrowserUserDataStatus -BrowserName 'chrome' -UserName $assistantUser -RelativeRoot 'AppData\Local\Google\Chrome\User Data'
Write-BrowserUserDataStatus -BrowserName 'edge' -UserName $managerUser -RelativeRoot 'AppData\Local\Microsoft\Edge\User Data'
Write-BrowserUserDataStatus -BrowserName 'edge' -UserName $assistantUser -RelativeRoot 'AppData\Local\Microsoft\Edge\User Data'

Write-Host "PER-USER DESKTOP STATUS:"
Write-DesktopState -Label 'manager' -Path ("C:\Users\{0}\Desktop" -f $managerUser)
Write-DesktopState -Label 'assistant' -Path ("C:\Users\{0}\Desktop" -f $assistantUser)
Write-DesktopState -Label 'default' -Path 'C:\Users\Default\Desktop'
Write-DesktopState -Label 'public' -Path $publicDesktop

Write-Host "DESKTOP ARTIFACT STATUS:"
Write-DesktopArtifactScan -Label 'manager' -Path ("C:\Users\{0}\Desktop" -f $managerUser)
Write-DesktopArtifactScan -Label 'assistant' -Path ("C:\Users\{0}\Desktop" -f $assistantUser)
Write-DesktopArtifactScan -Label 'default' -Path 'C:\Users\Default\Desktop'
Write-DesktopArtifactScan -Label 'public' -Path $publicDesktop

Write-Host "SYSTEM VOLUME INFORMATION STATUS:"
foreach ($drive in @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty DeviceID)) {
    $sviPath = ("{0}\System Volume Information" -f [string]$drive)
    Write-Host ("svi => {0} => {1}" -f $sviPath, (Test-Path -LiteralPath $sviPath))
}

Write-Host "AUTO-START APP STATUS:"
$startupProfile = @(Convert-Base64JsonToObjectArray -Base64Text $hostStartupProfileJsonBase64)
$startupProfileByKey = @{}
foreach ($entry in @($startupProfile)) {
    if ($null -eq $entry) {
        continue
    }

    $key = if ($entry.PSObject.Properties.Match('Key').Count -gt 0) { [string]$entry.Key } else { '' }
    if ([string]::IsNullOrWhiteSpace([string]$key) -or $startupProfileByKey.ContainsKey($key)) {
        continue
    }

    $startupProfileByKey[$key] = $entry
}

$startupProfileSummary = @(
    @($startupProfileByKey.Keys | Sort-Object) |
        ForEach-Object {
            $entry = $startupProfileByKey[[string]$_]
            ("{0}:{1}:{2}" -f [string]$_, [string]$entry.EntryType, [string]$entry.Scope)
        }
)
if (@($startupProfileSummary).Count -eq 0) {
    Write-Host 'host-startup-profile => none'
}
else {
    Write-Host ("host-startup-profile => {0}" -f ($startupProfileSummary -join ', '))
}
Write-Host 'managed-startup-profile => jaws:Run:LocalMachine'

$managerContext = $null
try {
    $managerContext = Get-ManagerContext -UserName $managerUser
    $startupLocationDefinitions = @(Get-StartupLocationDefinitions -ManagerContext $managerContext)

    foreach ($startupKey in @($startupProfileByKey.Keys | Sort-Object)) {
        $displayName = Resolve-StartupDisplayName -Key ([string]$startupKey)
        if ([string]::IsNullOrWhiteSpace([string]$displayName)) {
            Write-Host ("unsupported-startup-key => {0}" -f [string]$startupKey)
            continue
        }

        Write-StartupEntryStatus -DisplayName $displayName -ProfileEntry $startupProfileByKey[[string]$startupKey] -LocationDefinitions $startupLocationDefinitions
    }

    Write-StartupEntryStatus `
        -DisplayName 'JAWS' `
        -ProfileEntry ([pscustomobject]@{
            Scope = 'LocalMachine'
            EntryType = 'Run'
        }) `
        -LocationDefinitions $startupLocationDefinitions
}
catch {
    Write-Warning ("startup-health-readback-failed => {0}" -f $_.Exception.Message)
}
finally {
    if ($null -ne $managerContext -and -not [string]::IsNullOrWhiteSpace([string]$managerContext.MountName)) {
        Dismount-RegistryHive -MountName ([string]$managerContext.MountName)
    }
}

Write-Host "LANGUAGE AND REGION STATUS:"
$systemPreferredUiLanguage = ''
if (Get-Command Get-SystemPreferredUILanguage -ErrorAction SilentlyContinue) {
    try {
        $systemPreferredUiLanguage = [string](Get-SystemPreferredUILanguage)
    }
    catch {
    }
}
$systemLocaleName = ''
if (Get-Command Get-WinSystemLocale -ErrorAction SilentlyContinue) {
    try {
        $systemLocale = Get-WinSystemLocale
        if ($null -ne $systemLocale -and $systemLocale.PSObject.Properties.Match('Name').Count -gt 0) {
            $systemLocaleName = [string]$systemLocale.Name
        }
        else {
            $systemLocaleName = [string]$systemLocale
        }
    }
    catch {
    }
}
Write-Host ("system-preferred-ui-language => {0}" -f [string]$systemPreferredUiLanguage)
Write-Host ("system-locale => {0}" -f [string]$systemLocaleName)
Write-Host ("time-zone => {0}" -f (Get-TimeZoneIdSafe))
Write-Host ("utf8-codepage-acp => {0}" -f (Get-RegistryValueText -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage' -ValueName 'ACP'))
Write-Host ("utf8-codepage-oemcp => {0}" -f (Get-RegistryValueText -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage' -ValueName 'OEMCP'))
Write-InstalledLanguageStatus -LanguageTag 'en-US'
Write-InstalledLanguageStatus -LanguageTag 'tr-TR'
Write-UserLanguageStatus -UserName $managerUser -UserPassword $managerPassword
Write-UserLanguageStatus -UserName $assistantUser -UserPassword $assistantPassword
Write-DefaultLanguageStatus

Write-Host "STORE INSTALL STATE:"
Write-StoreInstallStateReadback -TaskName '120-install-codex-application' -Label 'Codex App'
Write-StoreInstallStateReadback -TaskName '119-install-whatsapp-application' -Label 'WhatsApp'
Write-StoreInstallStateReadback -TaskName '118-install-be-my-eyes-application' -Label 'Be My Eyes'
Write-StoreInstallStateReadback -TaskName '122-install-icloud-application' -Label 'iCloud'

Write-Host "JAWS HEALTH:"
$jawsExpectedExe = 'C:\Program Files\Freedom Scientific\JAWS\2025\jfw.exe'
$jawsExe = Resolve-CommandPath -CommandName 'jfw.exe' -FallbackCandidates @(
    $jawsExpectedExe,
    'C:\Program Files (x86)\Freedom Scientific\JAWS\2025\jfw.exe'
)
Write-Host ("jaws-exe => {0}" -f $(if ([string]::IsNullOrWhiteSpace([string]$jawsExe)) { 'not-found' } else { $jawsExe }))
Write-Host ("jaws-exe-present => {0}" -f [bool](Test-Path -LiteralPath $jawsExpectedExe))
Write-Host ("jaws-exe-path-match => {0}" -f [string]::Equals([string]$jawsExe, $jawsExpectedExe, [System.StringComparison]::OrdinalIgnoreCase))
$jawsProcesses = @(Get-Process -Name 'jfw' -ErrorAction SilentlyContinue)
Write-Host ("jaws-process-count => {0}" -f @($jawsProcesses).Count)
Write-JawsSettingsStatus -Label 'manager' -ProfilePath ("C:\Users\{0}" -f $managerUser)
Write-JawsSettingsStatus -Label 'assistant' -ProfilePath ("C:\Users\{0}" -f $assistantUser)
Write-JawsMachineRegistryStatus -RegistryPath 'Registry::HKEY_LOCAL_MACHINE\Software\Freedom Scientific'
Write-JawsMachineRegistryStatus -RegistryPath 'Registry::HKEY_LOCAL_MACHINE\Software\WOW6432Node\Freedom Scientific'
Write-JawsUserRegistryStatus -UserName $managerUser
Write-JawsUserRegistryStatus -UserName $assistantUser
$wingetExe = Resolve-CommandPath -CommandName 'winget' -FallbackCandidates @('C:\ProgramData\prodicloud\tools\winget-x64\winget.exe')
if ([string]::IsNullOrWhiteSpace([string]$wingetExe)) {
    Write-Host 'jaws-winget-probe => success=False; timed-out=False; exit-code=1'
}
else {
    $jawsWingetResult = Invoke-NativeCommandProbe -FilePath $wingetExe -Arguments @('list', '--id', 'FreedomScientific.JAWS.2025', '--exact') -TimeoutSeconds 20
    Write-Host ("jaws-winget-probe => success={0}; timed-out={1}; exit-code={2}" -f [bool]$jawsWingetResult.Success, [bool]$jawsWingetResult.TimedOut, [int]$jawsWingetResult.ExitCode)
}

Write-Host "DOCKER DESKTOP HEALTH:"
$dockerDesktopExe = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
$dockerCliPath = Resolve-CommandPath -CommandName 'docker' -FallbackCandidates @('C:\Program Files\Docker\Docker\resources\bin\docker.exe')
Write-Host ("docker-desktop-exe-present => {0}" -f [bool](Test-Path -LiteralPath $dockerDesktopExe))
if ([string]::IsNullOrWhiteSpace([string]$dockerCliPath)) {
    Write-Host 'docker-cli-probe => success=False; timed-out=False; exit-code=1'
    $dockerCliResult = [pscustomobject]@{ Success = $false; TimedOut = $false; ExitCode = 1; Output = '' }
}
else {
    $dockerCliResult = Invoke-NativeCommandProbe -FilePath $dockerCliPath -Arguments @('--version') -TimeoutSeconds 10
    Write-Host ("docker-cli-probe => success={0}; timed-out={1}; exit-code={2}" -f [bool]$dockerCliResult.Success, [bool]$dockerCliResult.TimedOut, [int]$dockerCliResult.ExitCode)
}
$dockerServices = @(Get-Service -Name 'com.docker*' -ErrorAction SilentlyContinue | Sort-Object Name)
if (@($dockerServices).Count -eq 0) {
    Write-Host 'docker-services => none'
}
else {
    foreach ($dockerService in @($dockerServices)) {
        Write-Host ("docker-service => {0} => status={1}; start-type={2}" -f [string]$dockerService.Name, [string]$dockerService.Status, [string]$dockerService.StartType)
    }
}
$dockerDesktopProcesses = @(Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue)
Write-Host ("docker-desktop-process-count => {0}" -f @($dockerDesktopProcesses).Count)
if (Test-Path -LiteralPath $dockerStartupShortcutPath) {
    Write-ShortcutReadback -Label 'docker-startup-shortcut' -ShortcutPath $dockerStartupShortcutPath
    $dockerStartupShortcutHealth = Get-ShortcutHealth -ShortcutPath $dockerStartupShortcutPath
    Write-Host ("docker-startup-shortcut-healthy => {0}" -f [bool]$dockerStartupShortcutHealth.Healthy)
}
else {
    Write-Host ("docker-startup-shortcut => missing => {0}" -f $dockerStartupShortcutPath)
}
$dockerRunOncePath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
$dockerRunOnceValue = ''
if (Test-Path -LiteralPath $dockerRunOncePath) {
    $dockerRunOnceItem = Get-ItemProperty -Path $dockerRunOncePath -Name 'ProdicloudStartDockerDesktop' -ErrorAction SilentlyContinue
    if ($null -ne $dockerRunOnceItem) {
        $dockerRunOnceValue = [string]$dockerRunOnceItem.ProdicloudStartDockerDesktop
    }
}
Write-Host ("docker-runas-once-present => {0}" -f (-not [string]::IsNullOrWhiteSpace([string]$dockerRunOnceValue)))
if ([string]::IsNullOrWhiteSpace([string]$dockerCliPath)) {
    $dockerStatusResult = [pscustomobject]@{ Success = $false; TimedOut = $false; ExitCode = 1; Output = '' }
    $dockerInfoResult = [pscustomobject]@{ Success = $false; TimedOut = $false; ExitCode = 1; Output = '' }
    Write-Host 'docker-desktop-status-probe => success=False; timed-out=False; exit-code=1'
    Write-Host 'docker-info-probe => success=False; timed-out=False; exit-code=1'
}
elseif (@($dockerDesktopProcesses).Count -eq 0 -and @($dockerServices | Where-Object { [string]$_.Status -eq 'Running' }).Count -eq 0) {
    $dockerStatusResult = [pscustomobject]@{ Success = $false; TimedOut = $false; ExitCode = 1; Output = '' }
    $dockerInfoResult = [pscustomobject]@{ Success = $false; TimedOut = $false; ExitCode = 1; Output = '' }
    Write-Host 'docker-engine-deferred => Docker Desktop GUI and services are not running; daemon probes were skipped.' -ForegroundColor DarkCyan
    Write-Host 'docker-desktop-status-probe => success=False; timed-out=False; exit-code=1; deferred=True'
    Write-Host 'docker-info-probe => success=False; timed-out=False; exit-code=1; deferred=True'
}
else {
    $dockerStatusResult = Invoke-NativeCommandProbe -FilePath $dockerCliPath -Arguments @('desktop', 'status') -TimeoutSeconds 10
    Write-Host ("docker-desktop-status-probe => success={0}; timed-out={1}; exit-code={2}" -f [bool]$dockerStatusResult.Success, [bool]$dockerStatusResult.TimedOut, [int]$dockerStatusResult.ExitCode)
    $dockerInfoResult = Invoke-NativeCommandProbe -FilePath $dockerCliPath -Arguments @('info') -TimeoutSeconds 10
    Write-Host ("docker-info-probe => success={0}; timed-out={1}; exit-code={2}" -f [bool]$dockerInfoResult.Success, [bool]$dockerInfoResult.TimedOut, [int]$dockerInfoResult.ExitCode)
}
Write-Host ("docker-engine-ready => {0}" -f ([bool]$dockerCliResult.Success -and [bool]$dockerStatusResult.Success -and [bool]$dockerInfoResult.Success))

Write-Host "OLLAMA HEALTH:"
$ollamaExe = Resolve-CommandPath -CommandName 'ollama' -FallbackCandidates @((Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'), 'C:\Program Files\Ollama\ollama.exe')
Write-Host ("ollama-cli => {0}" -f $(if ([string]::IsNullOrWhiteSpace([string]$ollamaExe)) { 'not-found' } else { $ollamaExe }))
$ollamaCliResult = [pscustomobject]@{
    Success = $false
    TimedOut = $false
    ExitCode = -1
    Output = ''
}
if (-not [string]::IsNullOrWhiteSpace([string]$ollamaExe)) {
    $ollamaCliResult = Invoke-NativeCommandProbe -FilePath $ollamaExe -Arguments @('ls') -TimeoutSeconds 20 -SuppressOutput
}
$ollamaProcesses = @(Get-Process -Name 'ollama*' -ErrorAction SilentlyContinue)
$ollamaStartupShortcutHealth = $null
if (Test-Path -LiteralPath $ollamaStartupShortcutPath) {
    Write-ShortcutReadback -Label 'ollama-startup-shortcut' -ShortcutPath $ollamaStartupShortcutPath
    $ollamaStartupShortcutHealth = Get-ShortcutHealth -ShortcutPath $ollamaStartupShortcutPath
    Write-Host ("ollama-startup-shortcut-healthy => {0}" -f [bool]$ollamaStartupShortcutHealth.Healthy)
}
else {
    Write-Host ("ollama-startup-shortcut => missing => {0}" -f $ollamaStartupShortcutPath)
}
$ollamaProcessCount = @($ollamaProcesses).Count
$ollamaApiWaitSeconds = if ($ollamaProcessCount -gt 0) { 30 } else { 0 }
$ollamaApiVersion = ''
if ($ollamaApiWaitSeconds -gt 0) {
    $ollamaApiVersion = Wait-OllamaApiReady -TimeoutSeconds $ollamaApiWaitSeconds
}
else {
    Write-Host 'ollama-api-deferred => Ollama process is not running; the configured startup shortcut will launch it at sign-in.' -ForegroundColor DarkCyan
}
if (-not [bool]$ollamaCliResult.Success -and -not [string]::IsNullOrWhiteSpace([string]$ollamaApiVersion) -and -not [string]::IsNullOrWhiteSpace([string]$ollamaExe)) {
    $ollamaCliResult = Invoke-NativeCommandProbe -FilePath $ollamaExe -Arguments @('ls') -TimeoutSeconds 20 -SuppressOutput
}
$ollamaProcesses = @(Get-Process -Name 'ollama*' -ErrorAction SilentlyContinue)
Write-Host ("ollama-ls-probe => success={0}; timed-out={1}; exit-code={2}" -f [bool]$ollamaCliResult.Success, [bool]$ollamaCliResult.TimedOut, [int]$ollamaCliResult.ExitCode)
Write-Host ("ollama-process-count => {0}" -f @($ollamaProcesses).Count)
$ollamaPortOpen = Test-TcpPortReachable -HostName '127.0.0.1' -Port 11434 -TimeoutSeconds 5
Write-Host ("ollama-port-11434-open => {0}" -f [bool]$ollamaPortOpen)
Write-Host ("ollama-api-version => {0}" -f [string]$ollamaApiVersion)
$ollamaApiProbeVersion = if (-not [string]::IsNullOrWhiteSpace([string]$ollamaApiVersion)) { [string]$ollamaApiVersion } elseif ($ollamaProcessCount -gt 0) { Wait-OllamaApiReady -TimeoutSeconds 10 } else { '' }
$ollamaApiProbeSuccess = -not [string]::IsNullOrWhiteSpace([string]$ollamaApiProbeVersion)
$ollamaApiProbeTimedOut = $false
if ($ollamaApiProbeSuccess) {
    Write-Host ('ollama-api-version-response => {{"version":"{0}"}}' -f [string]$ollamaApiProbeVersion)
}
Write-Host ("ollama-api-probe => success={0}; timed-out={1}" -f [bool]$ollamaApiProbeSuccess, [bool]$ollamaApiProbeTimedOut)

Write-Host "WSL HEALTH:"
Write-Host ("docker-wsl-prereq-ready => {0}" -f (
    [string]::Equals((Get-WindowsOptionalFeatureState -FeatureName 'Microsoft-Windows-Subsystem-Linux'), 'Enabled', [System.StringComparison]::OrdinalIgnoreCase) -and
    [string]::Equals((Get-WindowsOptionalFeatureState -FeatureName 'VirtualMachinePlatform'), 'Enabled', [System.StringComparison]::OrdinalIgnoreCase)
))
foreach ($serviceName in @('WslService', 'LxssManager')) {
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($null -eq $svc) {
        Write-Host ("wsl-service => {0} => missing" -f $serviceName)
        continue
    }

    Write-Host ("wsl-service => {0} => status={1}; start-type={2}" -f [string]$svc.Name, [string]$svc.Status, [string]$svc.StartType)
}
$wslStatusResult = Invoke-NativeCommandProbe -FilePath 'wsl' -Arguments @('--status') -TimeoutSeconds 20
Write-Host ("wsl-status-probe => success={0}; timed-out={1}; exit-code={2}" -f [bool]$wslStatusResult.Success, [bool]$wslStatusResult.TimedOut, [int]$wslStatusResult.ExitCode)

try {
    $managerProfilePath = [string](Get-LocalUserProfileInfo -UserName $managerUser).ProfilePath
    $assistantProfilePath = [string](Get-LocalUserProfileInfo -UserName $assistantUser).ProfilePath
    $defaultProfilePath = 'C:\Users\Default'
    Write-CopyExclusionEvidence -ManagerProfilePath $managerProfilePath -AssistantProfilePath $assistantProfilePath -DefaultProfilePath $defaultProfilePath
}
catch {
    Write-Warning ("copy-exclusion-evidence-failed => {0}" -f $_.Exception.Message)
}



