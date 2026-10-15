# Shared platform defaults and config-key helpers.

# Handles Get-ClagnosPlatformDefaults.
function Get-ClagnosPlatformDefaults {
    param(
        [ValidateSet('windows','linux')]
        [string]$Platform
    )

    if ($Platform -eq 'windows') {
        return [ordered]@{
            PlatformLabel = 'windows'
            WindowTitle = 'az vm'
            VmNameDefault = ''
            VmImageDefault = 'MicrosoftWindowsDesktop:office-365:win11-25h2-avd-m365:latest'
            VmSizeDefault = 'Standard_B4as_v2'
            VmDiskSizeDefault = '128'
            VmInitTaskDirDefault = 'vm-init\windows'
            VmUpdateTaskDirDefault = 'vm-update\windows'
            RunCommandId = 'RunPowerShellScript'
            SshShell = 'powershell'
            IncludeRdp = $true
        }
    }

    return [ordered]@{
        PlatformLabel = 'linux'
        WindowTitle = 'az vm'
        VmNameDefault = ''
        VmImageDefault = 'Canonical:ubuntu-24_04-lts:server:latest'
        VmSizeDefault = 'Standard_B2as_v2'
        VmDiskSizeDefault = '40'
        VmInitTaskDirDefault = 'vm-init\linux'
        VmUpdateTaskDirDefault = 'vm-update\linux'
        RunCommandId = 'RunShellScript'
        SshShell = 'bash'
        IncludeRdp = $false
    }
}

# Handles Get-ClagnosPlatformVmConfigKey.
function Get-ClagnosPlatformVmConfigKey {
    param(
        [ValidateSet('windows','linux')]
        [string]$Platform,
        [ValidateSet('VM_IMAGE','VM_SIZE','VM_DISK_SIZE_GB')]
        [string]$BaseKey
    )

    $prefix = if ($Platform -eq 'windows') { 'WIN_' } else { 'LIN_' }
    return ($prefix + $BaseKey)
}

# Handles Get-ClagnosPlatformTaskCatalogConfigKey.
function Get-ClagnosPlatformTaskCatalogConfigKey {
    param(
        [ValidateSet('windows','linux')]
        [string]$Platform,
        [ValidateSet('init','update')]
        [string]$Stage
    )

    if ($Platform -eq 'windows') {
        if ($Stage -eq 'init') {
            return 'WIN_VM_INIT_TASK_DIR'
        }

        return 'WIN_VM_UPDATE_TASK_DIR'
    }

    if ($Stage -eq 'init') {
        return 'LIN_VM_INIT_TASK_DIR'
    }

    return 'LIN_VM_UPDATE_TASK_DIR'
}

function Get-ClagnosDerivedVmNameFromEmployeeEmailAddress {
    param([string]$EmployeeEmailAddress)

    $emailText = [string]$EmployeeEmailAddress
    if ([string]::IsNullOrWhiteSpace([string]$emailText)) {
        return ''
    }

    $trimmed = $emailText.Trim()
    if (Test-ClagnosConfigPlaceholderValue -Value $trimmed) {
        return ''
    }

    $parts = @($trimmed -split '@')
    if (@($parts).Count -lt 2 -or [string]::IsNullOrWhiteSpace([string]$parts[0])) {
        return ''
    }

    $localPart = [string]$parts[0].Trim().ToLowerInvariant()
    $normalized = [regex]::Replace($localPart, '[^a-z0-9-]+', '-')
    $normalized = [regex]::Replace($normalized, '-{2,}', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace([string]$normalized)) {
        return ''
    }

    if (-not ($normalized[0] -match '[a-z]')) {
        $normalized = ('u-{0}' -f $normalized)
    }

    $suffix = '-vm'
    if (-not $normalized.EndsWith($suffix, [System.StringComparison]::OrdinalIgnoreCase)) {
        $normalized = ('{0}{1}' -f $normalized.TrimEnd('-'), $suffix)
    }

    $maxLength = 64
    if ($normalized.Length -gt $maxLength) {
        $baseLength = $maxLength - $suffix.Length
        if ($baseLength -lt 1) {
            $baseLength = 1
        }
        $baseText = $normalized.Substring(0, [Math]::Min($baseLength, $normalized.Length))
        $baseText = $baseText.Trim('-')
        if ([string]::IsNullOrWhiteSpace([string]$baseText)) {
            $baseText = 'u'
        }
        $normalized = ('{0}{1}' -f $baseText, $suffix)
    }

    return [string]$normalized
}

# Handles Resolve-ClagnosPlatformConfigMap.
function Resolve-ClagnosPlatformConfigMap {
    param(
        [hashtable]$ConfigMap,
        [ValidateSet('windows','linux')]
        [string]$Platform
    )

    $resolved = @{}
    if ($ConfigMap) {
        foreach ($key in @($ConfigMap.Keys)) {
            $resolved[[string]$key] = [string]$ConfigMap[$key]
        }
    }

    foreach ($baseKey in @('VM_IMAGE','VM_SIZE','VM_DISK_SIZE_GB')) {
        $platformKey = Get-ClagnosPlatformVmConfigKey -Platform $Platform -BaseKey ([string]$baseKey)
        $genericValue = [string](Get-ConfigValue -Config $resolved -Key ([string]$baseKey) -DefaultValue '')
        $platformValue = [string](Get-ConfigValue -Config $resolved -Key ([string]$platformKey) -DefaultValue '')
        if (-not [string]::IsNullOrWhiteSpace([string]$genericValue)) {
            $resolved[[string]$baseKey] = [string]$genericValue
            continue
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$platformValue)) {
            $resolved[[string]$baseKey] = [string]$platformValue
            continue
        }
        if ($resolved.ContainsKey([string]$baseKey)) {
            $resolved.Remove([string]$baseKey)
        }
    }

    $resolvedVmName = [string](Get-ConfigValue -Config $resolved -Key 'SELECTED_VM_NAME' -DefaultValue '')
    if ([string]::IsNullOrWhiteSpace([string]$resolvedVmName)) {
        $derivedVmName = Get-ClagnosDerivedVmNameFromEmployeeEmailAddress -EmployeeEmailAddress ([string](Get-ConfigValue -Config $resolved -Key 'SELECTED_EMPLOYEE_EMAIL_ADDRESS' -DefaultValue ''))
        if (-not [string]::IsNullOrWhiteSpace([string]$derivedVmName)) {
            $resolved['SELECTED_VM_NAME'] = [string]$derivedVmName
        }
    }

    $resolved['SELECTED_VM_OS'] = $Platform
    return $resolved
}

# Handles Resolve-ClagnosPlatformSelection.
function Resolve-ClagnosPlatformSelection {
    param(
        [hashtable]$ConfigMap,
        [string]$EnvFilePath,
        [switch]$AutoMode,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag,
        [hashtable]$ConfigOverrides,
        [switch]$DeferEnvWrite,
        [switch]$PromptWhenFlagsMissing
    )

    if ($WindowsFlag -and $LinuxFlag) {
        Throw-FriendlyError -Detail 'Both --windows and --linux were provided. Select only one.' -Code 11 -Summary 'Conflicting OS selection flags were provided.' -Hint 'Use only one of --windows or --linux.'
    }

    $selected = ''
    if ($WindowsFlag) {
        $selected = 'windows'
    }
    elseif ($LinuxFlag) {
        $selected = 'linux'
    }
    else {
        if (-not $PromptWhenFlagsMissing) {
            $fromOverride = ''
            if ($ConfigOverrides -and $ConfigOverrides.ContainsKey('SELECTED_VM_OS')) {
                $fromOverride = [string]$ConfigOverrides['SELECTED_VM_OS']
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$fromOverride)) {
                $candidate = $fromOverride.Trim().ToLowerInvariant()
                if ($candidate -eq 'windows' -or $candidate -eq 'linux') {
                    $selected = $candidate
                }
                else {
                    Write-Warning ("Invalid SELECTED_VM_OS override '{0}'. Expected windows|linux." -f $fromOverride)
                }
            }

            if ([string]::IsNullOrWhiteSpace([string]$selected)) {
                $fromEnv = [string](Get-ConfigValue -Config $ConfigMap -Key 'SELECTED_VM_OS' -DefaultValue '')
                if (-not [string]::IsNullOrWhiteSpace($fromEnv)) {
                    $candidate = $fromEnv.Trim().ToLowerInvariant()
                    if ($candidate -eq 'windows' -or $candidate -eq 'linux') {
                        $selected = $candidate
                    }
                    else {
                        Write-Warning ("Invalid SELECTED_VM_OS '{0}' in .env. Expected windows|linux." -f $fromEnv)
                    }
                }
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($selected)) {
        if ($AutoMode) {
            Throw-FriendlyError -Detail 'VM OS type is unresolved in auto mode.' -Code 12 -Summary 'Auto mode requires SELECTED_VM_OS.' -Hint 'Set SELECTED_VM_OS=windows|linux in .env, or pass --windows/--linux.'
        }

        while ($true) {
            $raw = Read-Host 'Select VM OS type (windows/linux, default=windows)'
            if ([string]::IsNullOrWhiteSpace($raw)) {
                $selected = 'windows'
                break
            }

            $candidate = $raw.Trim().ToLowerInvariant()
            if ($candidate -eq 'w') { $candidate = 'windows' }
            if ($candidate -eq 'l') { $candidate = 'linux' }
            if ($candidate -eq 'windows' -or $candidate -eq 'linux') {
                $selected = $candidate
                break
            }

            Write-Host "Please enter 'windows' or 'linux'." -ForegroundColor Yellow
        }
    }

    if ($ConfigOverrides) {
        $ConfigOverrides['VM_OS_TYPE'] = $selected
    }

    if (-not $AutoMode -and -not $DeferEnvWrite) {
        Set-DotEnvValue -Path $EnvFilePath -Key 'SELECTED_VM_OS' -Value $selected
    }

    Write-Host ("VM OS type '{0}' will be used." -f $selected) -ForegroundColor Green
    return $selected
}

# Handles Get-ClagnosDefaultTcpPortsCsv.
function Get-ClagnosDefaultSshPortText {
    return '444'
}

# Handles Get-ClagnosDefaultRdpPortText.
function Get-ClagnosDefaultRdpPortText {
    return '3389'
}

# Handles Get-ClagnosDefaultPowerShellPortText.
function Get-ClagnosDefaultPowerShellPortText {
    return '5985'
}

# Handles Get-ClagnosDefaultTcpPortsCsv.
function Get-ClagnosDefaultTcpPortsCsv {
    return '80,443,8444,389,5173,3000,3001,8080,5432,3306,6837,4000,4001,5000,5001,5985,6000,6001,6060,7000,7001,7070,8000,8001,9000,9001,9090,2222,3333,4444,5555,6666,7777,8888,9999,11434'
}

# Handles Get-ClagnosDefaultPySshClientPathText.
function Get-ClagnosDefaultPySshClientPathText {
    return 'tools/pyssh/ssh_client.py'
}
